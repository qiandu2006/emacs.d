;;; agent-shell-lark.el --- Lark bridge for agent-shell (Scheme B: User Self-Chat) -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Two-way bridge between `agent-shell' buffers and Lark/Feishu "Chat with myself"
;; (给自己的会话窗口) for users who cannot create an enterprise bot app.
;;
;; Scheme B Design:
;;   - Outbound (Emacs -> Lark): relays progress messages, turn completion summaries,
;;     and permission requests to the user's personal self-chat.
;;   - Inbound (Lark -> Emacs): non-blocking periodic polling of self-chat via
;;     `lark-cli im +chat-messages-list', deduplicating outbound echoes, routing
;;     prompts to `agent-shell-prompt-queue', handling "/cc" interrupts, and resolving
;;     permission approvals via plain text replies (1/2, y/n).
;;   - Formula Rendering: Display and inline LaTeX formulas ($$...$$, \[...\], $...$)
;;     are converted into mathematical Unicode characters and structured blockquotes,
;;     rendering cleanly on both Desktop and Mobile while strictly preserving code blocks.

;;; Code:

(require 'agent-shell)
(require 'agent-shell-prompt-queue)
(require 'json)
(require 'map)
(require 'seq)
(require 'subr-x)

(eval-when-compile
  (require 'cl-lib))

(defgroup agent-shell-lark nil
  "Lark self-chat bridge for `agent-shell'."
  :group 'agent-shell)

(defcustom agent-shell-lark-cli-command
  (or (executable-find "lark-cli")
      (let ((brew-path "/opt/homebrew/bin/lark-cli"))
        (and (file-executable-p brew-path) brew-path))
      "lark-cli")
  "Path to the Lark CLI executable."
  :type 'string
  :group 'agent-shell-lark)

(defcustom agent-shell-lark-user-id "ou_1ff3608ed8199c1b25cd79ae5d0a36c7"
  "Open ID of the current user. Used to resolve or verify self-chat."
  :type 'string
  :group 'agent-shell-lark)

(defcustom agent-shell-lark-chat-id "oc_09b8602e2998cf916370a67c214e7a5e"
  "Chat ID of the user's self-conversation.
If nil, the bridge queries `lark-cli' to discover it automatically."
  :type '(choice (const :tag "Auto-discover" nil)
                 (string :tag "Chat ID"))
  :group 'agent-shell-lark)

(defcustom agent-shell-lark-poll-interval 2.0
  "Seconds between polling queries for new messages in self-chat."
  :type 'number
  :group 'agent-shell-lark)

(defcustom agent-shell-lark-command-timeout 20
  "Seconds to allow for outbound commands before timing out."
  :type 'integer
  :group 'agent-shell-lark)

(defcustom agent-shell-lark-max-message-length 24000
  "Maximum characters of agent output relayed per message."
  :type 'integer
  :group 'agent-shell-lark)

(defcustom agent-shell-lark-relay-turn-complete t
  "When non-nil, relay the final agent response on turn complete."
  :type 'boolean
  :group 'agent-shell-lark)

(defcustom agent-shell-lark-relay-progress-messages t
  "When non-nil, relay progress messages between tool calls."
  :type 'boolean
  :group 'agent-shell-lark)

(defcustom agent-shell-lark-render-formulas t
  "When non-nil, render display math ($$...$$, \\[...\\]) as images via Node.js MathJax."
  :type 'boolean
  :group 'agent-shell-lark)

(defcustom agent-shell-lark-formula-tools-directory
  (expand-file-name "lark-tools" user-emacs-directory)
  "Directory holding tex2svg.js and node_modules (MathJax)."
  :type 'directory
  :group 'agent-shell-lark)

(defcustom agent-shell-lark-interrupt-commands '("/cc")
  "Text commands from Lark that interrupt the active agent session."
  :type '(repeat string)
  :group 'agent-shell-lark)

(defcustom agent-shell-lark-log-buffer-name "*agent-shell-lark-log*"
  "Buffer name collecting bridge diagnostics."
  :type 'string
  :group 'agent-shell-lark)

;;; State

(defvar agent-shell-lark--bound-buffer nil
  "Current `agent-shell' buffer bound to the bridge.")

(defvar agent-shell-lark--poll-timer nil
  "Timer instance for inbound polling.")

(defvar agent-shell-lark--poll-process nil
  "Active polling process, if one is currently in-flight.")

(defvar agent-shell-lark--seen-message-ids nil
  "List of recent message IDs already processed.")

(defvar agent-shell-lark--sent-message-ids nil
  "List of message IDs sent by Emacs to ignore on inbound poll.")

(defvar agent-shell-lark--sent-text-hashes nil
  "List of content hashes of outbound messages to prevent echo loops.")

(defvar agent-shell-lark--pending-permission nil
  "Alist holding current pending permission request:
`((:respond . fn) (:options . list) (:title . str))'.")

(defvar agent-shell-lark--turn-tail ""
  "Accumulated text tail for the current turn.")

(defvar agent-shell-lark--progress-tail ""
  "Accumulated assistant text between tool calls.")

(defvar agent-shell-lark--subscriptions nil
  "Event subscription tokens for the bound agent buffer.")

(defvar agent-shell-lark--formula-keys nil
  "Alist of (FORMULA-SHA1 . IMAGE-KEY) for uploaded formula images.")

;;; Logging

(defun agent-shell-lark--log (format-string &rest args)
  "Log formatted message with timestamp to `agent-shell-lark-log-buffer-name'."
  (let ((line (apply #'format format-string args))
        (time-str (format-time-string "%Y-%m-%d %H:%M:%S")))
    (with-current-buffer (get-buffer-create agent-shell-lark-log-buffer-name)
      (goto-char (point-max))
      (insert (format "[%s] %s\n" time-str line)))))

;;; Formula rendering & LaTeX-to-Unicode conversion for Lark

(defconst agent-shell-lark--tex-symbols
  '(;; Calligraphic & Blackboard
    ("\\\\mathcal{H}" . "ℋ")
    ("\\\\mathcal{L}" . "ℒ")
    ("\\\\mathcal{O}" . "𝒪")
    ("\\\\mathcal{N}" . "𝒩")
    ("\\\\mathcal{D}" . "𝒟")
    ("\\\\mathcal{F}" . "ℱ")
    ("\\\\mathcal{X}" . "𝒳")
    ("\\\\mathcal{Y}" . "𝒴")
    ("\\\\mathbb{R}" . "ℝ")
    ("\\\\mathbb{E}" . "𝔼")
    ("\\\\mathbb{P}" . "ℙ")
    ("\\\\mathbb{Z}" . "ℤ")
    ("\\\\mathbb{C}" . "ℂ")
    ("\\\\mathbb{N}" . "ℕ")
    ;; Greek uppercase (case-sensitive)
    ("\\\\Gamma" . "Γ")
    ("\\\\Delta" . "Δ")
    ("\\\\Theta" . "Θ")
    ("\\\\Lambda" . "Λ")
    ("\\\\Xi" . "Ξ")
    ("\\\\Pi" . "Π")
    ("\\\\Sigma" . "Σ")
    ("\\\\Upsilon" . "Υ")
    ("\\\\Phi" . "Φ")
    ("\\\\Psi" . "Ψ")
    ("\\\\Omega" . "Ω")
    ;; Greek lowercase
    ("\\\\alpha" . "α")
    ("\\\\beta" . "β")
    ("\\\\gamma" . "γ")
    ("\\\\delta" . "δ")
    ("\\\\epsilon" . "ε")
    ("\\\\varepsilon" . "ε")
    ("\\\\zeta" . "ζ")
    ("\\\\eta" . "η")
    ("\\\\theta" . "θ")
    ("\\\\vartheta" . "ϑ")
    ("\\\\iota" . "ι")
    ("\\\\kappa" . "κ")
    ("\\\\lambda" . "λ")
    ("\\\\mu" . "μ")
    ("\\\\nu" . "ν")
    ("\\\\xi" . "ξ")
    ("\\\\pi" . "π")
    ("\\\\varpi" . "ϖ")
    ("\\\\rho" . "ρ")
    ("\\\\varrho" . "ϱ")
    ("\\\\sigma" . "σ")
    ("\\\\varsigma" . "ς")
    ("\\\\tau" . "τ")
    ("\\\\upsilon" . "υ")
    ("\\\\phi" . "ϕ")
    ("\\\\varphi" . "φ")
    ("\\\\chi" . "χ")
    ("\\\\psi" . "ψ")
    ("\\\\omega" . "ω")
    ;; Set & Logic & Relations
    ("\\\\in" . "∈")
    ("\\\\notin" . "∉")
    ("\\\\subset" . "⊂")
    ("\\\\subseteq" . "⊆")
    ("\\\\supset" . "⊃")
    ("\\\\supseteq" . "⊇")
    ("\\\\cap" . "∩")
    ("\\\\cup" . "∪")
    ("\\\\forall" . "∀")
    ("\\\\exists" . "∃")
    ("\\\\emptyset" . "∅")
    ("\\\\implies" . "⟹")
    ("\\\\iff" . "⟺")
    ("\\\\to" . "→")
    ("\\\\rightarrow" . "→")
    ("\\\\leftarrow" . "←")
    ("\\\\mapsto" . "↦")
    ;; Math Operators
    ("\\\\nabla" . "∇")
    ("\\\\partial" . "∂")
    ("\\\\sum" . "∑")
    ("\\\\prod" . "∏")
    ("\\\\int" . "∫")
    ("\\\\oint" . "∮")
    ("\\\\infty" . "∞")
    ("\\\\approx" . "≈")
    ("\\\\sim" . "∼")
    ("\\\\simeq" . "≃")
    ("\\\\cong" . "≅")
    ("\\\\equiv" . "≡")
    ("\\\\neq" . "≠")
    ("\\\\ne" . "≠")
    ("\\\\leq" . "≤")
    ("\\\\le" . "≤")
    ("\\\\geq" . "≥")
    ("\\\\ge" . "≥")
    ("\\\\ll" . "≪")
    ("\\\\gg" . "≫")
    ("\\\\times" . "×")
    ("\\\\cdot" . "·")
    ("\\\\pm" . "±")
    ("\\\\mp" . "∓")
    ("\\\\div" . "÷")
    ("\\\\otimes" . "⊗")
    ("\\\\oplus" . "⊕")
    ("\\\\odot" . "⊙")
    ("\\\\circ" . "∘")
    ;; Delimiters & Accents
    ("\\\\langle" . "⟨")
    ("\\\\rangle" . "⟩")
    ("\\\\Vert" . "‖")
    ("\\\\|" . "‖")
    ("\\\\{" . "{")
    ("\\\\}" . "}")
    ;; Strip \left and \right
    ("\\\\left" . "")
    ("\\\\right" . "")
    ;; Spacing
    ("\\\\quad" . "  ")
    ("\\\\qquad" . "    ")
    ("\\\\," . " ")
    ("\\\\;" . " ")
    ("\\\\!" . ""))
  "Mapping of LaTeX TeX control sequences to Unicode characters.")

(defun agent-shell-lark--clean-tex (tex)
  "Convert raw LaTeX math string TEX into human-readable Unicode math."
  (let ((case-fold-search nil)
        (s tex))
    ;; Functions and wrappers: \text{...}, \mathrm{...}, \mathbf{...}
    (setq s (replace-regexp-in-string "\\\\\\(text\\|mathrm\\|mathbf\\|boldsymbol\\|operatorname\\){\\([^}]+\\)}" "\\2" s t))
    (setq s (replace-regexp-in-string "\\\\frac{\\([^}]+\\)}{\\([^}]+\\)}" "(\\1 / \\2)" s t))
    (setq s (replace-regexp-in-string "\\\\sqrt{\\([^}]+\\)}" "√(\\1)" s t))
    (setq s (replace-regexp-in-string "\\\\sqrt" "√" s t t))
    ;; Symbol replacements (case-sensitive)
    (dolist (pair agent-shell-lark--tex-symbols)
      (setq s (replace-regexp-in-string (car pair) (cdr pair) s t t)))
    ;; Subscripts and superscripts
    (setq s (replace-regexp-in-string "\\^2\\b" "²" s t t))
    (setq s (replace-regexp-in-string "\\^{2}" "²" s t t))
    (setq s (replace-regexp-in-string "\\^3\\b" "³" s t t))
    (setq s (replace-regexp-in-string "\\^{3}" "³" s t t))
    (setq s (replace-regexp-in-string "\\^T\\b" "ᵀ" s t t))
    (setq s (replace-regexp-in-string "\\^{T}" "ᵀ" s t t))
    (setq s (replace-regexp-in-string "\\^\\*" "*" s t t))
    (setq s (replace-regexp-in-string "\\^{k}" "ᵏ" s t t))
    (setq s (replace-regexp-in-string "\\^{n}" "ⁿ" s t t))
    (setq s (replace-regexp-in-string "\\^-1" "⁻¹" s t t))
    ;; Unwrap subscripts like _{new} -> _new, _{old} -> _old, _{Euc} -> _Euc
    (setq s (replace-regexp-in-string "_{\\([^{}]+\\)}" "_\\1" s t))
    ;; Clean remaining single braces like {H} -> H
    (setq s (replace-regexp-in-string "{\\([^{}]+\\)}" "\\1" s t))
    (string-trim s)))

(defun agent-shell-lark--formula-tools-ready-p ()
  "Return non-nil when the formula rendering toolchain is available."
  (and (executable-find "node")
       (executable-find "rsvg-convert")
       (executable-find agent-shell-lark-cli-command)
       (file-executable-p (expand-file-name "render-formula.sh" agent-shell-lark-formula-tools-directory))
       (file-exists-p (expand-file-name "tex2svg.js" agent-shell-lark-formula-tools-directory))))

(defun agent-shell-lark--formula-disk-key (hash)
  "Return cached Lark image_key for HASH from disk if exists."
  (let ((key-file (expand-file-name (concat hash ".key")
                                    (expand-file-name "agent-shell-lark"
                                                      (or (getenv "XDG_CACHE_HOME") "~/.cache")))))
    (when (and (file-exists-p key-file) (> (file-attribute-size (file-attributes key-file)) 0))
      (string-trim (with-temp-buffer
                     (insert-file-contents key-file)
                     (buffer-string))))))

(defun agent-shell-lark--extract-display-formulas (text)
  "Extract unique display math strings from non-code segments of TEXT."
  (let ((parts (split-string text "```" nil))
        (is-code nil)
        (formulas nil))
    (dolist (part parts)
      (unless is-code
        (let ((start 0))
          (while (string-match "\\$\\$\\([^$]+?\\)\\$\\$\\|\\\\\\[\\(\\(?:.\\|\n\\)*?\\)\\\\\\]" part start)
            (let ((f (or (match-string 1 part) (match-string 2 part))))
              (when (and f (not (string-empty-p (string-trim f))))
                (push (string-trim f) formulas)))
            (setq start (match-end 0)))))
      (setq is-code (not is-code)))
    (seq-uniq (nreverse formulas))))

(defun agent-shell-lark--render-formula-async (formula callback)
  "Render and upload FORMULA, then invoke (CALLBACK KEY-OR-NIL)."
  (let* ((script (expand-file-name "render-formula.sh" agent-shell-lark-formula-tools-directory))
         (hash (sha1 formula))
         (mem-key (cdr (assoc hash agent-shell-lark--formula-keys)))
         (disk-key (agent-shell-lark--formula-disk-key hash)))
    (cond
     (mem-key (funcall callback mem-key))
     (disk-key
      (push (cons hash disk-key) agent-shell-lark--formula-keys)
      (funcall callback disk-key))
     (t
      (let* ((buf (generate-new-buffer " *agent-shell-lark-formula*"))
             (proc (make-process
                    :name "agent-shell-lark-formula"
                    :buffer buf
                    :connection-type 'pipe
                    :command (list script)
                    :sentinel
                    (lambda (p _event)
                      (when (memq (process-status p) '(exit signal))
                        (let* ((ok (zerop (process-exit-status p)))
                               (out (with-current-buffer (process-buffer p)
                                      (string-trim (buffer-string)))))
                          (kill-buffer (process-buffer p))
                          (if (and ok (not (string-empty-p out)))
                              (progn
                                (push (cons hash out) agent-shell-lark--formula-keys)
                                (funcall callback out))
                            (agent-shell-lark--log "Formula render failed (%d): %s"
                                                   (process-exit-status p) out)
                            (funcall callback nil))))))))
        (process-send-string proc formula)
        (process-send-eof proc))))))

(defun agent-shell-lark--format-math-segment (text)
  "Format LaTeX formulas in a non-code segment TEXT for Lark.
Display math is replaced with rendered HD image tags `![formula](image_key)'
when available, or styled blockquotes on fallback.  Inline math is converted
to mathematical Unicode characters."
  (let ((case-fold-search nil)
        (s text))
    ;; 1. Convert Display Math ($$...$$ or \[...\]) to HD images or quote blocks
    (setq s (replace-regexp-in-string
             "\\$\\$\\([^$]+?\\)\\$\\$\\|\\\\\\[\\(\\(?:.\\|\n\\)*?\\)\\\\\\]"
             (lambda (match)
               (let* ((inner (string-trim
                              (if (string-prefix-p "$$" match)
                                  (substring match 2 -2)
                                (substring match 2 -2))))
                      (hash (sha1 inner))
                      (key (or (cdr (assoc hash agent-shell-lark--formula-keys))
                               (agent-shell-lark--formula-disk-key hash))))
                 (if key
                     (format "\n\n![formula](%s)\n\n" key)
                   (let ((cleaned (agent-shell-lark--clean-tex inner)))
                     (format "\n\n> 📐 **公式**：\n> %s\n\n" cleaned)))))
             s t t))
    ;; 2. Convert Inline Math ($...$ or \(...\)) to clean Unicode math
    (setq s (replace-regexp-in-string
             "\\$\\([^$\n]+?\\)\\$\\|\\\\(\\([^)]+?\\)\\\\)"
             (lambda (match)
               (let* ((inner (if (string-prefix-p "$" match)
                                 (substring match 1 -1)
                               (substring match 2 -2)))
                      (cleaned (agent-shell-lark--clean-tex inner)))
                 cleaned))
             s t t))
    s))

(defun agent-shell-lark--format-math-for-lark (text)
  "Format LaTeX formulas in TEXT for Lark (Feishu) rendering while preserving code blocks."
  (let ((parts (split-string text "```" nil))
        (is-code nil)
        (result nil))
    (dolist (part parts)
      (if is-code
          (push (concat "```" part "```") result)
        (push (agent-shell-lark--format-math-segment part) result))
      (setq is-code (not is-code)))
    (string-join (nreverse result) "")))

;;; Outbound Messaging

(defun agent-shell-lark--resolve-chat-id ()
  "Return the effective chat ID, discovering it if necessary."
  (or agent-shell-lark-chat-id
      (when agent-shell-lark-user-id
        (condition-case nil
            (with-temp-buffer
              (when (zerop (call-process agent-shell-lark-cli-command nil (current-buffer) nil
                                         "im" "+chat-messages-list"
                                         "--user-id" agent-shell-lark-user-id
                                         "--page-size" "1"))
                (goto-char (point-min))
                (let* ((json (json-read))
                       (messages (map-nested-elt json '(data messages)))
                       (first (and (vectorp messages) (> (length messages) 0) (aref messages 0))))
                  (when first
                    (setq agent-shell-lark-chat-id (map-elt first 'chat_id))))))
          (error nil)))
      "oc_09b8602e2998cf916370a67c214e7a5e"))

(defun agent-shell-lark--remember-sent (text)
  "Record TEXT hash and prefix to avoid inbound echo processing."
  (let ((hash (secure-hash 'sha1 (string-trim text))))
    (push hash agent-shell-lark--sent-text-hashes)
    (when (> (length agent-shell-lark--sent-text-hashes) 200)
      (setq agent-shell-lark--sent-text-hashes (seq-take agent-shell-lark--sent-text-hashes 100)))))

(defun agent-shell-lark--send-internal (prepared-text chat-id &optional reply-to-id)
  "Dispatch outbound PREPARED-TEXT to CHAT-ID or REPLY-TO-ID via `lark-cli'."
  (agent-shell-lark--remember-sent prepared-text)
  (let ((send-buf (get-buffer-create " *agent-shell-lark-send*")))
    (with-current-buffer send-buf (erase-buffer))
    (make-process
     :name "agent-shell-lark-send"
     :buffer send-buf
     :connection-type 'pipe
     :command (if reply-to-id
                  (list agent-shell-lark-cli-command
                        "im" "+messages-reply"
                        "--message-id" reply-to-id
                        "--markdown" prepared-text)
                (list agent-shell-lark-cli-command
                      "im" "+messages-send"
                      "--chat-id" chat-id
                      "--markdown" prepared-text))
     :sentinel
     (lambda (process _event)
       (when (memq (process-status process) '(exit signal))
         (if (zerop (process-exit-status process))
             (agent-shell-lark--log "Sent outbound message successfully (%d chars)" (length prepared-text))
           (let ((err-text (with-current-buffer (process-buffer process)
                             (string-trim (buffer-string)))))
             (agent-shell-lark--log "Warning: Outbound message failed (exit code %d): %s"
                                    (process-exit-status process)
                                    (if (string-empty-p err-text) "Check permissions/scopes" err-text)))))))))

(defun agent-shell-lark--send (text &optional reply-to-id)
  "Send TEXT to the user's self-conversation asynchronously.
If `agent-shell-lark-render-formulas' is non-nil, display math ($$...$$, \\[...\\])
is rendered via local Node.js MathJax as HD images before sending."
  (let ((chat-id (agent-shell-lark--resolve-chat-id)))
    (unless chat-id
      (agent-shell-lark--log "Error: chat_id not resolved; cannot send message")
      (user-error "Lark chat_id not configured"))
    (let* ((clean-text (if (> (length text) agent-shell-lark-max-message-length)
                           (concat (substring text 0 agent-shell-lark-max-message-length)
                                   "\n\n[... truncated by agent-shell-lark ...]")
                         text)))
      (if (and agent-shell-lark-render-formulas
               (agent-shell-lark--formula-tools-ready-p))
          (let* ((formulas (agent-shell-lark--extract-display-formulas clean-text))
                 (missing (seq-remove
                           (lambda (f)
                             (or (assoc (sha1 f) agent-shell-lark--formula-keys)
                                 (agent-shell-lark--formula-disk-key (sha1 f))))
                           formulas))
                 (pending (length missing))
                 (finish (lambda ()
                           (let ((prepared-text (agent-shell-lark--format-math-for-lark clean-text)))
                             (agent-shell-lark--send-internal prepared-text chat-id reply-to-id)))))
            (if (zerop pending)
                (funcall finish)
              (dolist (formula missing)
                (agent-shell-lark--render-formula-async
                 formula
                 (lambda (_key)
                   (setq pending (1- pending))
                   (when (zerop pending)
                     (funcall finish)))))))
        (let ((prepared-text (agent-shell-lark--format-math-for-lark clean-text)))
          (agent-shell-lark--send-internal prepared-text chat-id reply-to-id))))))

;;; Inbound Polling & Command Dispatch

(defun agent-shell-lark--seen-p (msg-id)
  "Return non-nil if MSG-ID has already been handled."
  (or (member msg-id agent-shell-lark--seen-message-ids)
      (member msg-id agent-shell-lark--sent-message-ids)))

(defun agent-shell-lark--remember-seen (msg-id)
  "Mark MSG-ID as seen."
  (push msg-id agent-shell-lark--seen-message-ids)
  (when (> (length agent-shell-lark--seen-message-ids) 300)
    (setq agent-shell-lark--seen-message-ids (seq-take agent-shell-lark--seen-message-ids 150))))

(defun agent-shell-lark--extract-text (msg)
  "Extract human-readable text from parsed MSG."
  (let ((content (map-elt msg 'content))
        (msg-type (map-elt msg 'msg_type)))
    (cond
     ((stringp content)
      (if (string-prefix-p "{" (string-trim content))
          (ignore-errors
            (let ((parsed (json-read-from-string content)))
              (or (map-elt parsed 'text) content)))
        content))
     (t nil))))

(defun agent-shell-lark--handle-inbound-text (text msg-id)
  "Handle user input TEXT from message MSG-ID."
  (let ((trimmed (string-trim text)))
    (cond
     ;; 1. Check echo loop
     ((or (string-prefix-p "🔗" trimmed)
          (string-prefix-p "🚀 [Emacs]" trimmed)
          (string-prefix-p "⏳ [Emacs]" trimmed)
          (string-prefix-p "🏁 [Emacs]" trimmed)
          (string-prefix-p "🏁 **[Agent" trimmed)
          (string-prefix-p "⚡ **[Agent" trimmed)
          (string-prefix-p "🔒 **[权限" trimmed)
          (string-prefix-p "✅ [Emacs]" trimmed)
          (string-prefix-p "⚠ [Emacs]" trimmed)
          (string-prefix-p "❓ 未能识别" trimmed)
          (string-prefix-p "⏹ [Emacs]" trimmed)
          (seq-some (lambda (hash) (equal hash (secure-hash 'sha1 trimmed)))
                    agent-shell-lark--sent-text-hashes))
      (agent-shell-lark--log "Ignored self echo message: %s" msg-id))

     ;; 2. Interrupt command
     ((member (downcase trimmed) agent-shell-lark-interrupt-commands)
      (agent-shell-lark--log "Received interrupt /cc from Lark")
      (if (buffer-live-p agent-shell-lark--bound-buffer)
          (with-current-buffer agent-shell-lark--bound-buffer
            (agent-shell-interrupt t)
            (agent-shell-lark--send "⏹ [Emacs] Agent 已中断 (Interrupted)." msg-id))
        (agent-shell-lark--send "⚠ [Emacs] 目标 Agent 缓冲区已关闭，无法中断。" msg-id)))

     ;; 3. Pending permission approval
     (agent-shell-lark--pending-permission
      (agent-shell-lark--resolve-permission trimmed msg-id))

     ;; 4. Inject prompt to Agent
     (t
      (agent-shell-lark--inject-prompt trimmed msg-id)))))

(defun agent-shell-lark--resolve-permission (input msg-id)
  "Match INPUT against pending permission options."
  (let* ((pending agent-shell-lark--pending-permission)
         (respond (map-elt pending :respond))
         (options (map-elt pending :options))
         (title (map-elt pending :title))
         (lower (downcase (string-trim input)))
         selected-opt)
    (cond
     ;; Answer by index: "1", "2"
     ((string-match-p "\\`[0-9]+\\'" lower)
      (let ((idx (1- (string-to-number lower))))
        (when (and (>= idx 0) (< idx (length options)))
          (setq selected-opt (nth idx options)))))
     ;; Answer by affirmative keyword: "y", "yes", "allow", "ok"
     ((member lower '("y" "yes" "allow" "ok" "确认" "允许"))
      (setq selected-opt (seq-find (lambda (opt)
                                     (string-prefix-p "allow" (or (map-elt opt :kind) "")))
                                   options)))
     ;; Answer by negative keyword: "n", "no", "reject", "deny"
     ((member lower '("n" "no" "reject" "deny" "拒绝" "取消"))
      (setq selected-opt (seq-find (lambda (opt)
                                     (string-prefix-p "reject" (or (map-elt opt :kind) "")))
                                   options))))

    (if selected-opt
        (progn
          (setq agent-shell-lark--pending-permission nil)
          (when (functionp respond)
            (funcall respond selected-opt))
          (agent-shell-lark--log "Permission resolved: %s -> %s" title (map-elt selected-opt :label))
          (agent-shell-lark--send (format "✅ [Emacs] 权限已处理: **%s** (%s)"
                                          (or (map-elt selected-opt :label) "已选择")
                                          title)
                                  msg-id))
      (agent-shell-lark--send (format "❓ 未能识别选项: \"%s\"。请回复序号（如 1 或 2）或 y/n。" input) msg-id))))

(defun agent-shell-lark--inject-prompt (text msg-id)
  "Inject TEXT prompt into the bound agent buffer."
  (if (not (buffer-live-p agent-shell-lark--bound-buffer))
      (agent-shell-lark--send "⚠ [Emacs] 未找到活动的 agent-shell 缓冲区，请在 Emacs 启动后再试。" msg-id)
    (with-current-buffer agent-shell-lark--bound-buffer
      (condition-case err
          (let ((is-busy (shell-maker-busy)))
            (if is-busy
                (progn
                  (agent-shell--prompt-queue-enqueue :prompt text)
                  (agent-shell-lark--send (format "⏳ [Emacs] Agent 当前忙碌，Prompt 已入队排队。\n\n内容: %s"
                                                  (truncate-string-to-width text 60 nil nil "..."))
                                          msg-id))
              (agent-shell-insert :shell-buffer agent-shell-lark--bound-buffer
                                  :text text
                                  :submit t
                                  :no-focus t)
              (agent-shell-lark--send (format "🚀 [Emacs] Prompt 已接收并开始执行...\n\n内容: %s"
                                              (truncate-string-to-width text 60 nil nil "..."))
                                      msg-id))
            (agent-shell-lark--log "Injected prompt into %s: %s"
                                   (buffer-name agent-shell-lark--bound-buffer)
                                   (truncate-string-to-width text 40 nil nil "...")))
        (error
         (agent-shell-lark--log "Inject prompt error: %s" (error-message-string err))
         (agent-shell-lark--send (format "⚠ [Emacs] 提交 Prompt 失败: %s" (error-message-string err))
                                 msg-id))))))

(defun agent-shell-lark--poll ()
  "Perform one poll cycle for new messages."
  (when (and (null agent-shell-lark--poll-process)
             (buffer-live-p agent-shell-lark--bound-buffer))
    (let ((chat-id (agent-shell-lark--resolve-chat-id)))
      (when chat-id
        (let ((buf (get-buffer-create " *agent-shell-lark-poll*")))
          (with-current-buffer buf (erase-buffer))
          (setq agent-shell-lark--poll-process
                (make-process
                 :name "agent-shell-lark-poll"
                 :buffer buf
                 :connection-type 'pipe
                 :command (list agent-shell-lark-cli-command
                                "im" "+chat-messages-list"
                                "--chat-id" chat-id
                                "--page-size" "5"
                                "--order" "desc")
                 :sentinel #'agent-shell-lark--poll-sentinel)))))))

(defun agent-shell-lark--message-recent-p (time-str)
  "Return non-nil if TIME-STR is within the last 1 hour (3600s)."
  (if (null time-str)
      t
    (condition-case nil
        (let* ((parsed (parse-time-string time-str))
               (encoded (and (nth 5 parsed) (encode-time parsed)))
               (diff (and encoded (float-time (time-subtract (current-time) encoded)))))
          (or (null diff) (< (abs diff) 3600)))
      (error t))))

(defun agent-shell-lark--poll-sentinel (process _event)
  "Process output from the polling PROCESS."
  (setq agent-shell-lark--poll-process nil)
  (when (memq (process-status process) '(exit signal))
    (when (zerop (process-exit-status process))
      (with-current-buffer (process-buffer process)
        (goto-char (point-min))
        (condition-case err
            (let* ((json (json-read))
                   (messages (map-nested-elt json '(data messages))))
              (when (vectorp messages)
                ;; Iterate chronological (oldest to newest among latest 5)
                (dolist (msg (nreverse (append messages nil)))
                  (let ((msg-id (map-elt msg 'message_id))
                        (ctime (map-elt msg 'create_time)))
                    (when (and msg-id (not (agent-shell-lark--seen-p msg-id)))
                      (agent-shell-lark--remember-seen msg-id)
                      (when (agent-shell-lark--message-recent-p ctime)
                        (when-let* ((text (agent-shell-lark--extract-text msg)))
                          (agent-shell-lark--handle-inbound-text text msg-id))))))))
          (error
           (agent-shell-lark--log "Poll JSON parse error: %s" (error-message-string err))))))))

;;; Permission Responder (Hooks into agent-shell)

(defun agent-shell-lark--responder (permission)
  "Relay PERMISSION request to Lark self-chat with numbered options."
  (when-let* ((tool-call (map-elt permission :tool-call))
              (options (map-elt permission :options))
              (title (or (map-elt tool-call :title) "Tool execution permission required")))
    (setq agent-shell-lark--pending-permission
          (list (cons :respond (map-elt permission :respond))
                (cons :options options)
                (cons :title title)))
    (let ((options-text
           (string-join
            (seq-map-indexed
             (lambda (opt idx)
               (format "  **%d**: %s" (1+ idx) (or (map-elt opt :label) "Option")))
             options)
            "\n")))
      (agent-shell-lark--send
       (format "🔒 **[权限审批请求]**\n\n操作: **%s**\n\n请直接回复数字序号选择操作:\n%s\n\n*(亦可回复 y 允许 / n 拒绝)*"
               title options-text))
      (agent-shell-lark--log "Permission requested: %s" title)))
  nil)

;;; Event Listeners for agent-shell

(defun agent-shell-lark--on-chunk (event)
  "Track text chunks to accumulate progress."
  (when-let* ((chunk (map-nested-elt event '(:data :text-chunk))))
    (setq agent-shell-lark--turn-tail (concat agent-shell-lark--turn-tail chunk))
    (setq agent-shell-lark--progress-tail (concat agent-shell-lark--progress-tail chunk))))

(defun agent-shell-lark--on-tool-start (_event)
  "Relay accumulated progress summary before a tool executes."
  (when (and agent-shell-lark-relay-progress-messages
             (not (string-empty-p (string-trim agent-shell-lark--progress-tail))))
    (agent-shell-lark--send (format "⚡ **[Agent 进度]**\n\n%s"
                                    (string-trim agent-shell-lark--progress-tail)))
    (setq agent-shell-lark--progress-tail "")))

(defun agent-shell-lark--on-turn-complete (event)
  "Relay turn complete message to Lark."
  (when agent-shell-lark-relay-turn-complete
    (let ((output (string-trim agent-shell-lark--turn-tail)))
      (unless (string-empty-p output)
        (agent-shell-lark--send (format "🏁 **[Agent 回合完成]**\n\n%s" output)))))
  (setq agent-shell-lark--turn-tail "")
  (setq agent-shell-lark--progress-tail ""))

;;; Lifecycle Management

(defun agent-shell-lark--subscribe (buffer)
  "Subscribe event handlers to BUFFER."
  (setq agent-shell-lark--subscriptions
        (list (agent-shell-subscribe-to :shell-buffer buffer
                                        :event 'agent-message-chunk
                                        :on-event #'agent-shell-lark--on-chunk)
              (agent-shell-subscribe-to :shell-buffer buffer
                                        :event 'turn-complete
                                        :on-event #'agent-shell-lark--on-turn-complete))))

(defun agent-shell-lark--unsubscribe ()
  "Unsubscribe all active event handlers."
  (dolist (sub agent-shell-lark--subscriptions)
    (ignore-errors (agent-shell-unsubscribe :subscription sub)))
  (setq agent-shell-lark--subscriptions nil))

;;;###autoload
(defun my/agent-shell-lark-start (&optional buffer)
  "Start the Lark Scheme B bridge bound to BUFFER (defaults to current buffer)."
  (interactive)
  (let ((target (or buffer (current-buffer))))
    (unless (derived-mode-p 'agent-shell-mode)
      (let ((shells (agent-shell-buffers)))
        (if shells
            (setq target (car shells))
          (user-error "No agent-shell buffer found. Please start an agent-shell first"))))
    (setq agent-shell-lark--bound-buffer target)
    (agent-shell-lark--unsubscribe)
    (agent-shell-lark--subscribe target)
    ;; Register permission responder
    (setq agent-shell-permission-responder-function #'agent-shell-lark--responder)
    ;; Reset poll buffer and in-flight process
    (when (process-live-p agent-shell-lark--poll-process)
      (delete-process agent-shell-lark--poll-process))
    (setq agent-shell-lark--poll-process nil)
    (when-let* ((buf (get-buffer " *agent-shell-lark-poll*")))
      (with-current-buffer buf (erase-buffer)))
    ;; Start polling timer
    (when (timerp agent-shell-lark--poll-timer)
      (cancel-timer agent-shell-lark--poll-timer))
    (setq agent-shell-lark--poll-timer
          (run-with-timer 1.0 agent-shell-lark-poll-interval #'agent-shell-lark--poll))
    (agent-shell-lark--log "Lark bridge started; bound to %s (poll interval: %.1fs)"
                           (buffer-name target) agent-shell-lark-poll-interval)
    (agent-shell-lark--send
     (format "🔗 **[Emacs Agent-Shell 网关已连接]**\n\n已绑定缓冲区: `%s`\n可通过此窗口发送 Prompt、回复 1/2 审批权限，或发送 `/cc` 中断当前任务。"
             (buffer-name target)))
    (message "Lark bridge (Scheme B) started and bound to %s" (buffer-name target))))

;;;###autoload
(defun my/agent-shell-lark-stop ()
  "Stop the Lark bridge and cancel timers."
  (interactive)
  (when (timerp agent-shell-lark--poll-timer)
    (cancel-timer agent-shell-lark--poll-timer))
  (setq agent-shell-lark--poll-timer nil)
  (when (process-live-p agent-shell-lark--poll-process)
    (delete-process agent-shell-lark--poll-process))
  (setq agent-shell-lark--poll-process nil)
  (agent-shell-lark--unsubscribe)
  (setq agent-shell-permission-responder-function nil)
  (agent-shell-lark--log "Lark bridge stopped")
  (message "Lark bridge stopped"))

;;;###autoload
(defun my/agent-shell-lark-status ()
  "Show current Lark bridge status in the echo area."
  (interactive)
  (let ((running (timerp agent-shell-lark--poll-timer))
        (buf (and (buffer-live-p agent-shell-lark--bound-buffer)
                  (buffer-name agent-shell-lark--bound-buffer))))
    (message "Lark Bridge: %s | Bound Buffer: %s | Chat ID: %s | Poll: %.1fs"
             (if running "ACTIVE" "STOPPED")
             (or buf "NONE")
             (or agent-shell-lark-chat-id "auto")
             agent-shell-lark-poll-interval)))

(provide 'agent-shell-lark)
;;; agent-shell-lark.el ends here
