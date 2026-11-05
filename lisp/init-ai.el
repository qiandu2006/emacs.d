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

(use-package agent-shell
  :ensure t
  :config
  (require 'agent-shell-chat-mode)
  (setq agent-shell-transcript-file-path-function #'my/agent-shell-transcript-file-path)

  (unless (advice-member-p #'my/agent-shell-chat-fix-live-prompt 'agent-shell-chat--label-prompts)
    (advice-add 'agent-shell-chat--label-prompts :after #'my/agent-shell-chat-fix-live-prompt))

  (unless (advice-member-p #'my/agent-shell-tool-output-display-cap 'agent-shell--update-fragment)
    (advice-add 'agent-shell--update-fragment :around #'my/agent-shell-tool-output-display-cap))

  ;; Multi-model adapters (Feature 5)
  ;; 1. Antigravity: use `agy acp` or `agy_acp_server.par`
  (require 'agent-shell-antigravity nil t)
  (setq agent-shell-antigravity-acp-command
        (if (executable-find "agy")
            '("agy" "acp")
          '("agy_acp_server.par")))

  ;; 2. Claude Code: use `claude-agent-acp`
  (require 'agent-shell-anthropic nil t)
  (setq agent-shell-anthropic-claude-acp-command '("claude-agent-acp"))

  ;; 3. OpenAI Codex: use `codex-acp`
  (require 'agent-shell-openai nil t)
  (setq agent-shell-openai-codex-acp-command '("codex-acp"))

  ;; 4. Cursor: use `agent acp`
  (require 'agent-shell-cursor nil t)
  (setq agent-shell-cursor-acp-command '("agent" "acp"))

  ;; Auto-retry on retriable errors & 429 (Features 7 & 10)
  (require 'agent-shell-auto-retry)

  ;; Context-aware reading and Magit diff review (Features 6 & 11)
  (require 'agent-shell-reading)

  ;; Lark personal self-chat bridge (Features 1-4 Scheme B)
  (require 'agent-shell-lark)

  ;; Keybindings
  (global-set-key (kbd "C-c a a") #'agent-shell)
  (global-set-key (kbd "C-c a s") #'agent-shell-switch-buffer)
  (when (fboundp 'agent-shell-antigravity-start-agent)
    (global-set-key (kbd "C-c a g") #'agent-shell-antigravity-start-agent))
  (when (fboundp 'agent-shell-anthropic-start-claude-code)
    (global-set-key (kbd "C-c a l") #'agent-shell-anthropic-start-claude-code))
  (when (fboundp 'agent-shell-cursor-start-agent)
    (global-set-key (kbd "C-c a u") #'agent-shell-cursor-start-agent))
  (when (fboundp 'agent-shell-openai-start-codex)
    (global-set-key (kbd "C-c a o") #'agent-shell-openai-start-codex))
  (global-set-key (kbd "C-c a e") #'my/agent-shell-ask-dwim)
  (global-set-key (kbd "C-c a L") #'my/agent-shell-lark-start)
  (global-set-key (kbd "C-c a S") #'my/agent-shell-lark-stop))

(provide 'init-ai)
;;; init-ai.el ends here
