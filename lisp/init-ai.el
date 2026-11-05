;;; init-ai.el --- AI Agent Integrations (Agent-Shell, Antigravity, Claude, Cursor, Codex) -*- lexical-binding: t -*-

;;; Commentary:
;; Aggregates multi-model Agent backends, buffer protection caps,
;; auto-retry mechanisms, code reading/diff review, and Lark bridge.

;;; Code:

(require 'map)
(require 'seq)
(require 'subr-x)

;; Ensure standard CLI paths are present in exec-path and PATH environment
(dolist (dir '("~/.local/bin" "/opt/homebrew/bin" "/usr/local/bin" "~/go/bin" "~/.cargo/bin"))
  (let ((expanded (expand-file-name dir)))
    (when (file-directory-p expanded)
      (add-to-list 'exec-path expanded)
      (unless (member (file-name-as-directory expanded)
                      (parse-colon-path (getenv "PATH")))
        (setenv "PATH" (concat expanded path-separator (getenv "PATH")))))))

;; Require Agent-Shell and core subpackages
(require 'agent-shell)
(require 'agent-shell-chat-mode)
(require 'agent-shell-antigravity nil t)
(require 'agent-shell-anthropic nil t)
(require 'agent-shell-cursor nil t)
(require 'agent-shell-openai nil t)
(require 'agent-shell-auto-retry nil t)
(require 'agent-shell-reading nil t)
(require 'agent-shell-lark nil t)

;; Keep chat-style labels enabled. Render live prompt replacement
;; through `display' to prevent 1-pixel collapse on some terminal frames.
(setq agent-shell-chat-mode-enabled t)

(defun my/agent-shell-chat-fix-live-prompt (&rest _)
  "Keep the chat-mode live prompt visible at end-of-buffer."
  (when (and (bound-and-true-p agent-shell-chat-mode)
             (not (bound-and-true-p agent-shell-prompt-bar-mode))
             comint-last-prompt)
    (let* ((beg (marker-position (car comint-last-prompt)))
           (end (marker-position (cdr comint-last-prompt)))
           (overlay
            (seq-find
             (lambda (item)
               (eq (overlay-get item 'category) 'agent-shell-chat-me))
             (overlays-in (max (point-min) (1- beg))
                          (min (point-max) (1+ end)))))
           (replacement (and overlay (overlay-get overlay 'before-string))))
      (when (and replacement (string-match-p "❯" replacement))
        (overlay-put overlay 'display replacement)
        (overlay-put overlay 'before-string nil)))))

(unless (advice-member-p #'my/agent-shell-chat-fix-live-prompt 'agent-shell-chat--label-prompts)
  (advice-add 'agent-shell-chat--label-prompts :after #'my/agent-shell-chat-fix-live-prompt))

(defun my/agent-shell-transcript-file-path ()
  "Return an `agent-shell' transcript path outside the project tree."
  (let* ((cwd (directory-file-name (file-truename (agent-shell-cwd))))
         (project-name (file-name-nondirectory cwd))
         (safe-name (replace-regexp-in-string
                     "[^[:alnum:]._-]+" "-"
                     (if (string-empty-p project-name) "root" project-name)))
         (project-key (format "%s-%s" safe-name (substring (secure-hash 'sha1 cwd) 0 12)))
         (cache-root (or (getenv "XDG_CACHE_HOME") (expand-file-name "~/.cache")))
         (dir (expand-file-name (concat "agent-shell/transcripts/" project-key "/") cache-root)))
    (make-directory dir t)
    (expand-file-name (format-time-string "%F-%H-%M-%S.md") dir)))

(setq agent-shell-transcript-file-path-function #'my/agent-shell-transcript-file-path)

(defvar my/agent-shell-tool-output-display-max-chars 120000
  "Maximum characters of a tool output body rendered in agent-shell buffers.
Display-only: transcripts still receive the complete output.")

(defvar my/agent-shell-tool-output-display-head-chars 80000
  "Characters kept from start when truncating tool output for display.")

(defvar my/agent-shell-tool-output-display-tail-chars 40000
  "Characters kept from end when truncating tool output for display.")

(defun my/agent-shell-tool-output-display-truncate (text transcript-file)
  "Return a display-only truncated copy of TEXT."
  (let* ((len (length text))
         (head (min my/agent-shell-tool-output-display-head-chars len))
         (tail (min my/agent-shell-tool-output-display-tail-chars (max 0 (- len head))))
         (omitted (- len head tail)))
    (concat
     (format "[agent-shell display truncated tool output]\nOriginal: %d chars. Showing first %d and last %d chars.\nFull output: %s\n\n"
             len head tail (or transcript-file "<transcript disabled>"))
     (substring text 0 head)
     (format "\n\n... omitted %d chars from Emacs display only ...\n\n" omitted)
     (if (> tail 0)
         (substring text (- len tail))
       ""))))

(defun my/agent-shell-tool-output-display-cap (orig &rest args)
  "Cap large tool output bodies before ORIG renders them in Emacs."
  (let* ((state (plist-get args :state))
         (block-id (plist-get args :block-id))
         (body (plist-get args :body))
         (tool-call (and state block-id (map-nested-elt state `(:tool-calls ,block-id))))
         (limit my/agent-shell-tool-output-display-max-chars))
    (if (and tool-call
             (stringp body)
             (integerp limit)
             (> limit 0)
             (> (length body) limit)
             (not (string-prefix-p "[agent-shell display truncated tool output]" body)))
        (let* ((shell-buffer (map-elt state :buffer))
               (transcript-file (and (buffer-live-p shell-buffer)
                                     (buffer-local-value 'agent-shell--transcript-file shell-buffer)))
               (new-args (copy-sequence args)))
          (setq new-args
                (plist-put new-args :body (my/agent-shell-tool-output-display-truncate body transcript-file)))
          (apply orig new-args))
      (apply orig args))))

(unless (advice-member-p #'my/agent-shell-tool-output-display-cap 'agent-shell--update-fragment)
  (advice-add 'agent-shell--update-fragment :around #'my/agent-shell-tool-output-display-cap))

(defun my/agent-shell-fix-auth ()
  "Sync ~/.claude/.credentials.json to macOS Keychain and reload live Claude sessions."
  (interactive)
  (let ((creds (expand-file-name "~/.claude/.credentials.json")))
    (unless (file-exists-p creds)
      (user-error "%s not found; run /login in a terminal Claude Code session" creds))
    (unless (zerop (call-process-shell-command
                    (format "security add-generic-password -U -s \"Claude Code-credentials\" -a \"$USER\" -w \"$(cat %s)\""
                            (shell-quote-argument creds))))
      (user-error "Keychain sync failed"))
    (let (reloaded)
      (dolist (buffer (agent-shell-buffers))
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (when (and (eq (map-nested-elt (agent-shell--state) '(:agent-config :identifier))
                           'claude-code)
                       (map-nested-elt (agent-shell--state) '(:session :id)))
              (let ((name (buffer-name)))
                (agent-shell-reload)
                (push name reloaded))))))
      (message "Keychain synced; reloaded: %s"
               (if reloaded
                   (string-join (nreverse reloaded) ", ")
                 "no live Claude sessions")))))

;; Multi-model adapters (Feature 5)
;; 1. Antigravity: use `agy acp` or `agy_acp_server.par`
(setq agent-shell-antigravity-acp-command
      (if (executable-find "agy")
          '("agy" "acp")
        '("agy_acp_server.par")))

;; 2. Claude Code: use `claude-agent-acp`
(setq agent-shell-anthropic-claude-acp-command '("claude-agent-acp"))

;; 3. OpenAI Codex: use `codex-acp`
(setq agent-shell-openai-codex-acp-command '("codex-acp"))
(setq agent-shell-openai-default-model-id "gpt-6.1-sol")
(setq agent-shell-openai-default-config-options '(("reasoning_effort" . "medium")))

;; 4. Cursor: use `agent acp`
(setq agent-shell-cursor-acp-command '("agent" "acp"))

;; Keybindings inside agent-shell-mode-map
(with-eval-after-load 'agent-shell
  (define-key agent-shell-mode-map (kbd "C-c ?") #'agent-shell-help-menu)
  (define-key agent-shell-mode-map (kbd "C-c C-h") #'agent-shell-help-menu)
  (define-key agent-shell-mode-map (kbd "C-c C-r") #'my/agent-shell-switch-session))

;; Historical Session Discovery & Switching (Cross-Project & Pagination)
(defcustom my/agent-shell-list-all-projects-sessions t
  "When non-nil, query historical sessions across all projects rather than only current CWD."
  :type 'boolean
  :group 'agent-shell)

(defun my/agent-shell--list-sessions-all-projects-advice (orig-fn &rest args)
  "Allow session/list to query all projects when `my/agent-shell-list-all-projects-sessions' is t."
  (if my/agent-shell-list-all-projects-sessions
      (let ((plist (copy-sequence args)))
        (setq plist (plist-put plist :cwd nil))
        (apply orig-fn plist))
    (apply orig-fn args)))

(unless (advice-member-p #'my/agent-shell--list-sessions-all-projects-advice 'agent-shell--list-sessions)
  (advice-add 'agent-shell--list-sessions :around #'my/agent-shell--list-sessions-all-projects-advice))

(defun my/agent-shell-switch-session (&optional arg)
  "Interactively browse, search, and switch to any historical agent session.
Fetches all historical sessions (including conversations from 10+ days ago)
across projects with full pagination.
With prefix ARG (\\[universal-argument]), replace the current shell buffer;
otherwise, open the historical session in a new dedicated buffer."
  (interactive "P")
  (let* ((shell-buf (if (derived-mode-p 'agent-shell-mode)
                        (current-buffer)
                      (seq-first (agent-shell-buffers))))
         (state (and (buffer-live-p shell-buf)
                     (buffer-local-value 'agent-shell--state shell-buf))))
    (unless (and state (map-elt state :client))
      (user-error "No active agent-shell connection. Please start an agent first (e.g. C-c a o)"))
    (message "Fetching historical sessions from agent (including past projects)...")
    (agent-shell--list-sessions
     :state state
     :cwd nil
     :buffer shell-buf
     :page-limit 10
     :on-success
     (lambda (raw-sessions)
       (run-at-time
        0 nil
        (lambda ()
          (let* ((sorted (agent-shell--sort-sessions-by-recency raw-sessions)))
            (if (null sorted)
                (message "No historical sessions found for this agent.")
              (let* ((choices
                      (mapcar
                       (lambda (s)
                         (let* ((title (or (map-elt s 'title) "Untitled conversation"))
                                (date-raw (or (map-elt s 'updatedAt) (map-elt s 'createdAt)))
                                (date-str (if date-raw (agent-shell--format-session-date date-raw) "Unknown date"))
                                (cwd (or (map-elt s 'cwd) ""))
                                (dir-name (if (string-empty-p cwd) "-" (file-name-nondirectory (directory-file-name cwd))))
                                (sid (substring (or (map-elt s 'sessionId) "") 0 8))
                                (label (format "%-42s  %-15s  %-16s  (%s)"
                                               (truncate-string-to-width title 42 0 nil "…")
                                               date-str
                                               (concat "[" dir-name "]")
                                               sid)))
                           (cons label s)))
                       sorted))
                     (selection (completing-read "Switch to historical session: "
                                                 (mapcar #'car choices)
                                                 nil t))
                     (selected-session (cdr (assoc selection choices))))
                (when selected-session
                  (let* ((sid (map-elt selected-session 'sessionId))
                         (title (map-elt selected-session 'title))
                         (cwd (map-elt selected-session 'cwd))
                         (config (map-elt state :agent-config)))
                    (if (and arg (derived-mode-p 'agent-shell-mode))
                        (progn
                          (message "Reloading session [%s] into current buffer..." (or title sid))
                          (agent-shell-restart :session-id sid))
                      (let* ((target-dir (if (and cwd (file-directory-p cwd))
                                             (file-name-as-directory (expand-file-name cwd))
                                           default-directory))
                             (default-directory target-dir)
                             (new-buf (agent-shell--start :config config
                                                          :session-id sid
                                                          :cwd target-dir
                                                          :new-session t
                                                          :no-focus t)))
                        (when title
                          (shell-maker-set-buffer-name
                           new-buf
                           (format "*%s: %s*"
                                   (map-elt config :mode-line-name)
                                   (truncate-string-to-width title 22 0 nil "…"))))
                        (agent-shell--display-buffer new-buf)
                        (message "Resumed historical session [%s] (Project: %s)" (or title sid) target-dir)))))))))))
     :on-failure
     (lambda (err _)
       (message "Failed to fetch historical sessions: %s" err)))))

;; Codex Model Choices and Interactive Starter
(defvar my/agent-shell-openai-available-models
  '(("6.1 Sol (workhorse coding, fast)" . "gpt-6.1-sol")
    ("6 Astra (frontier intelligence, highest capability)" . "gpt-6-astra")
    ("6.1 Terra (balanced codex model)" . "gpt-6.1-terra")
    ("6 Sol (previous generation workhorse)" . "gpt-6-sol")
    ("6 Luna (fast and affordable)" . "gpt-6-luna")
    ("5.6 Sol (legacy workhorse)" . "gpt-5.6-sol")
    ("5.6 Terra (legacy balanced)" . "gpt-5.6-terra")
    ("5.6 Luna (legacy fast)" . "gpt-5.6-luna"))
  "Available models for OpenAI Codex in codex-acp.")

(defvar my/agent-shell-openai-available-thought-levels
  '("low" "medium" "high" "xhigh" "max" "ultra")
  "Available reasoning effort levels for OpenAI Codex.")

(defun my/agent-shell-openai-start-codex (&optional arg)
  "Start an interactive Codex agent shell.
With prefix ARG (\\[universal-argument]), prompt interactively for the
model and reasoning effort before launching."
  (interactive "P")
  (if arg
      (let* ((choice (completing-read "Select Codex Model: "
                                      (mapcar #'car my/agent-shell-openai-available-models)
                                      nil t nil nil (caar my/agent-shell-openai-available-models)))
             (model-id (cdr (assoc choice my/agent-shell-openai-available-models)))
             (thought (completing-read "Select Reasoning Effort: "
                                       my/agent-shell-openai-available-thought-levels
                                       nil t nil nil "medium"))
             (agent-shell-openai-default-model-id model-id)
             (agent-shell-openai-default-config-options `(("reasoning_effort" . ,thought))))
        (message "Starting Codex with model: %s (reasoning: %s)..." model-id thought)
        (agent-shell-openai-start-codex))
    (agent-shell-openai-start-codex)))

;; Slash commands support in agent-shell prompt
(defun my/agent-shell-slash-command-advice (orig-fn &rest args)
  "Intercept slash commands typed directly into prompt: /session, /model, /thought, /mode, /help."
  (if (and (derived-mode-p 'agent-shell-mode)
           (fboundp 'comint-line-beginning-position))
      (let* ((input (string-trim (buffer-substring-no-properties
                                  (comint-line-beginning-position)
                                  (point-max)))))
        (cond
         ((or (string= input "/session") (string= input "/history") (string= input "/resume"))
          (delete-region (comint-line-beginning-position) (point-max))
          (call-interactively #'my/agent-shell-switch-session))
         ((string= input "/model")
          (delete-region (comint-line-beginning-position) (point-max))
          (call-interactively #'agent-shell-set-session-model))
         ((or (string= input "/thought") (string= input "/effort"))
          (delete-region (comint-line-beginning-position) (point-max))
          (call-interactively #'agent-shell-set-session-thought-level))
         ((string= input "/mode")
          (delete-region (comint-line-beginning-position) (point-max))
          (call-interactively #'agent-shell-set-session-mode))
         ((or (string= input "/help") (string= input "/menu") (string= input "/?"))
          (delete-region (comint-line-beginning-position) (point-max))
          (call-interactively #'agent-shell-help-menu))
         (t
          (apply orig-fn args))))
    (apply orig-fn args)))

(unless (advice-member-p #'my/agent-shell-slash-command-advice 'agent-shell-submit)
  (advice-add 'agent-shell-submit :around #'my/agent-shell-slash-command-advice))

;; Global Prefix Map for Agent Shell (C-c a)
(define-prefix-command 'my/agent-shell-prefix-map)
(global-set-key (kbd "C-c a") 'my/agent-shell-prefix-map)

(define-key my/agent-shell-prefix-map (kbd "a") #'agent-shell)
(define-key my/agent-shell-prefix-map (kbd "s") #'agent-shell-switch-buffer)
(define-key my/agent-shell-prefix-map (kbd "r") #'my/agent-shell-switch-session)
(define-key my/agent-shell-prefix-map (kbd "g") #'agent-shell-antigravity-start-agent)
(define-key my/agent-shell-prefix-map (kbd "l") #'agent-shell-anthropic-start-claude-code)
(define-key my/agent-shell-prefix-map (kbd "u") #'agent-shell-cursor-start-agent)
(define-key my/agent-shell-prefix-map (kbd "o") #'my/agent-shell-openai-start-codex)
(define-key my/agent-shell-prefix-map (kbd "e") #'my/agent-shell-ask-dwim)
(define-key my/agent-shell-prefix-map (kbd "L") #'my/agent-shell-lark-start)
(define-key my/agent-shell-prefix-map (kbd "S") #'my/agent-shell-lark-stop)
(define-key my/agent-shell-prefix-map (kbd "?") #'agent-shell-help-menu)
(define-key my/agent-shell-prefix-map (kbd "h") #'agent-shell-help-menu)

;; Which-key friendly prompt annotations
(with-eval-after-load 'which-key
  (which-key-add-key-based-replacements "C-c a" "agent-shell")
  (which-key-add-key-based-replacements
    "C-c a a" "agent-shell (default)"
    "C-c a s" "switch agent buffer"
    "C-c a r" "resume/switch session (history)"
    "C-c a g" "start antigravity"
    "C-c a l" "start claude code"
    "C-c a u" "start cursor agent"
    "C-c a o" "start codex (OpenAI)"
    "C-c a e" "ask dwim / review diff"
    "C-c a L" "start lark bridge"
    "C-c a S" "stop lark bridge"
    "C-c a ?" "agent-shell help menu"
    "C-c a h" "agent-shell help menu"))

(provide 'init-ai)
;;; init-ai.el ends here
