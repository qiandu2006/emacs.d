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
(load (expand-file-name "lisp/agent-shell-lark.el" user-emacs-directory) nil t)

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

;; Replay entire previous conversation, tool execution, and thinking steps when resuming (Feature 2)
(setq agent-shell-session-restore-verbosity 'full)

;; Keybindings inside agent-shell-mode-map
(with-eval-after-load 'agent-shell
  (define-key agent-shell-mode-map (kbd "C-c ?") #'agent-shell-help-menu)
  (define-key agent-shell-mode-map (kbd "C-c C-h") #'agent-shell-help-menu)
  (define-key agent-shell-mode-map (kbd "C-c C-r") #'my/agent-shell-switch-session)
  (define-key agent-shell-mode-map (kbd "C-c C-m") #'my/agent-shell-set-model)
  (define-key agent-shell-mode-map (kbd "C-c C-t") #'my/agent-shell-set-thought-level))

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
     :page-limit 50
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
                                (sid-raw (or (map-elt s 'sessionId) ""))
                                (sid (if (> (length sid-raw) 8) (substring sid-raw 0 8) sid-raw))
                                (label (format "%-42s  %-15s  %-16s  (%s)"
                                               (truncate-string-to-width title 42 0 nil "…")
                                               date-str
                                               (concat "[" dir-name "]")
                                               sid)))
                           (cons label s)))
                       sorted))
                     (selection (let ((ivy-initial-inputs-alist nil)
                                      (ivy--default nil)
                                      (this-command 'my/agent-shell-switch-session))
                                  (completing-read "Switch to historical session: "
                                                   (mapcar #'car choices)
                                                   nil t nil nil nil)))
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

;; Slash command completion support (interactive dropdown candidates)
(defvar my/agent-shell-builtin-commands
  '(("history" . "切换/恢复历史会话 (全工程全量检索)")
    ("session" . "切换/恢复历史会话 (全工程全量检索)")
    ("resume"  . "恢复上一轮历史会话")
    ("model"   . "切换当前大模型 (如 6.1 Sol / 6 Astra)")
    ("thought" . "切换推理深度 (low / medium / high / max)")
    ("effort"  . "切换思考推理等级")
    ("mode"    . "切换权限模式 (read-only / workspace-write / full-access)")
    ("help"    . "呼出命令控制面板与菜单")
    ("clear"   . "清空当前终端屏幕")
    ("compact" . "压缩上下文会话历史")
    ("lark"    . "启动飞书远程网关"))
  "Default built-in slash commands for agent-shell completion.")

(defun my/agent-shell--clean-prompt-input ()
  "Reliably clear any text typed at the current prompt."
  (let ((start (or (and (fboundp 'agent-shell--prompt-input-start)
                        (agent-shell--prompt-input-start))
                   (and (bound-and-true-p comint-last-prompt)
                        (marker-position (cdr comint-last-prompt)))
                   (and (fboundp 'comint-line-beginning-position)
                        (comint-line-beginning-position)))))
    (when (and start (< start (point-max)))
      (delete-region start (point-max))))
  (when (fboundp 'agent-shell--clear-prompt-input)
    (ignore-errors (agent-shell--clear-prompt-input))))

(defun my/agent-shell--capf-exit-dispatch (string status)
  "Execute slash command when STATUS is `finished', or insert space otherwise."
  (if (eq status 'finished)
      (let ((cmd (string-trim (replace-regexp-in-string "^/" "" string))))
        (cond
         ((member cmd '("history" "session" "resume"))
          (my/agent-shell--clean-prompt-input)
          (run-at-time 0.05 nil #'my/agent-shell-switch-session))
         ((string= cmd "model")
          (my/agent-shell--clean-prompt-input)
          (run-at-time 0.05 nil #'my/agent-shell-set-model))
         ((member cmd '("thought" "effort"))
          (my/agent-shell--clean-prompt-input)
          (run-at-time 0.05 nil #'my/agent-shell-set-thought-level))
         ((string= cmd "mode")
          (my/agent-shell--clean-prompt-input)
          (run-at-time 0.05 nil #'my/agent-shell-set-mode))
         ((member cmd '("help" "menu" "?"))
          (my/agent-shell--clean-prompt-input)
          (run-at-time 0.05 nil #'agent-shell-help-menu))
         ((string= cmd "clear")
          (my/agent-shell--clean-prompt-input)
          (run-at-time 0.05 nil (if (fboundp 'agent-shell-clear-buffer)
                                    #'agent-shell-clear-buffer
                                  #'shell-maker-clear-buffer)))
         ((string= cmd "lark")
          (my/agent-shell--clean-prompt-input)
          (run-at-time 0.05 nil #'my/agent-shell-lark-start))
         (t
          (insert " "))))
    nil))

(defun my/agent-shell--command-completion-at-point-advice (orig-fn &rest args)
  "Augment slash command completion with built-in commands (/history, /model, etc.)."
  (when-let* ((bounds (agent-shell--completion-bounds "[:alnum:]_-" ?/))
              ((agent-shell-completion--command-start-p (1- (map-elt bounds :start))))
              (source (or (and (buffer-live-p agent-shell-completion--shell-buffer)
                               agent-shell-completion--shell-buffer)
                          (agent-shell--shell-buffer :no-error t :no-create t))))
    (let* ((state (and (buffer-live-p source) (buffer-local-value 'agent-shell--state source)))
           (acp-commands (and state (map-elt state :available-commands)))
           (acp-descs (mapcar (lambda (c)
                                (cons (map-elt c 'name)
                                      (map-elt c 'description)))
                              acp-commands))
           (all-descs (append my/agent-shell-builtin-commands acp-descs))
           (table (mapcar #'car all-descs)))
      (list (map-elt bounds :start)
            (map-elt bounds :end)
            table
            :exclusive t
            :company-prefix-length t
            :annotation-function
            (lambda (name)
              (when-let* ((desc (cdr (assoc name all-descs))))
                (concat "  " desc)))
            :company-kind (lambda (_) 'function)
            :exit-function #'my/agent-shell--capf-exit-dispatch))))

(unless (advice-member-p #'my/agent-shell--command-completion-at-point-advice 'agent-shell--command-completion-at-point)
  (advice-add 'agent-shell--command-completion-at-point :around #'my/agent-shell--command-completion-at-point-advice))

;; Ensure company completion in agent-shell triggers instantly on /
(add-hook 'agent-shell-mode-hook
          (lambda ()
            (setq-local company-minimum-prefix-length 1)
            (setq-local company-idle-delay 0.05)
            (when (fboundp 'company-mode)
              (company-mode 1))))

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

(defun my/agent-shell-set-thought-level ()
  "Interactively select and change reasoning effort (thought level).
Guarantees clean Ivy completion without prompt text pollution,
and supports both live ACP config options and fallback options."
  (interactive)
  (let* ((shell-buf (if (derived-mode-p 'agent-shell-mode)
                        (current-buffer)
                      (seq-first (agent-shell-buffers))))
         (state (and (buffer-live-p shell-buf)
                     (buffer-local-value 'agent-shell--state shell-buf))))
    (unless (and state (map-elt state :client))
      (user-error "No active agent-shell connection. Please start an agent first (e.g. C-c a o)"))
    (with-current-buffer shell-buf
      (let* ((option (agent-shell--config-option-by-category state "thought_level"))
             (acp-levels (agent-shell--get-available-thought-levels state))
             (current-id (or (agent-shell--current-thought-level-id state)
                             (map-elt option :current-value)
                             "medium"))
             (choices (if acp-levels
                          (mapcar (lambda (v)
                                    (cons (format "%-8s  (%s)"
                                                  (map-elt v :name)
                                                  (or (map-elt v :description) ""))
                                          (map-elt v :value)))
                                  acp-levels)
                        (mapcar (lambda (lvl)
                                  (cons (capitalize lvl) lvl))
                                my/agent-shell-openai-available-thought-levels)))
             (default-label (or (car (seq-find (lambda (c) (string= (cdr c) current-id)) choices))
                                (caar choices)))
             (selection (let ((ivy-initial-inputs-alist nil)
                              (ivy--default nil)
                              (this-command 'my/agent-shell-set-thought-level))
                          (completing-read "Set thought level (reasoning effort): "
                                           (mapcar #'car choices)
                                           nil t nil nil default-label)))
             (selected-val (cdr (assoc selection choices))))
        (when selected-val
          (if (and option (map-elt option :id))
              (agent-shell--set-session-config-option
               :config-id (map-elt option :id)
               :value selected-val
               :on-success (lambda ()
                             (message "Thought level (reasoning effort) set to: %s" selected-val))
               :on-failure (lambda (err _)
                             (message "Failed to set thought level: %s" err)))
            (setq agent-shell-openai-default-config-options
                  `(("reasoning_effort" . ,selected-val)))
            (message "Thought level set to: %s (applied to session)" selected-val)))))))

(defun my/agent-shell-set-model ()
  "Interactively select and change LLM model.
Guarantees clean Ivy completion without prompt text pollution,
and supports live ACP model options."
  (interactive)
  (let* ((shell-buf (if (derived-mode-p 'agent-shell-mode)
                        (current-buffer)
                      (seq-first (agent-shell-buffers))))
         (state (and (buffer-live-p shell-buf)
                     (buffer-local-value 'agent-shell--state shell-buf))))
    (unless (and state (map-elt state :client))
      (user-error "No active agent-shell connection. Please start an agent first (e.g. C-c a o)"))
    (with-current-buffer shell-buf
      (let* ((available (agent-shell--get-available-models state))
             (current-id (agent-shell--current-model-id state))
             (choices (if available
                          (mapcar (lambda (m)
                                    (cons (format "%-24s  %s"
                                                  (map-elt m :name)
                                                  (or (map-elt m :description) ""))
                                          (map-elt m :model-id)))
                                  available)
                        (mapcar (lambda (m)
                                  (cons (car m) (cdr m)))
                                my/agent-shell-openai-available-models)))
             (default-choice (or (car (seq-find (lambda (c) (equal (cdr c) current-id)) choices))
                                 (caar choices)))
             (selection (let ((ivy-initial-inputs-alist nil)
                              (ivy--default nil)
                              (this-command 'my/agent-shell-set-model))
                          (completing-read "Set model: "
                                           (mapcar #'car choices)
                                           nil t nil nil default-choice)))
             (selected-id (cdr (assoc selection choices))))
        (when selected-id
          (agent-shell--config-option-set-model-id
           :model-id selected-id
           :on-success (lambda ()
                         (message "Model switched to: %s" selected-id))))))))

(defun my/agent-shell-set-mode ()
  "Interactively select and change session mode (read-only / workspace-write / full-access)."
  (interactive)
  (let* ((shell-buf (if (derived-mode-p 'agent-shell-mode)
                        (current-buffer)
                      (seq-first (agent-shell-buffers))))
         (state (and (buffer-live-p shell-buf)
                     (buffer-local-value 'agent-shell--state shell-buf))))
    (unless (and state (map-elt state :client))
      (user-error "No active agent-shell connection. Please start an agent first (e.g. C-c a o)"))
    (with-current-buffer shell-buf
      (let* ((modes (or (map-elt state :modes)
                        (agent-shell--get-available-modes state)))
             (current-id (agent-shell--current-mode-id state))
             (choices (mapcar (lambda (m)
                                (cons (format "%-20s  %s"
                                              (map-elt m :name)
                                              (or (map-elt m :description) ""))
                                      (map-elt m :id)))
                              modes))
             (default-choice (or (car (seq-find (lambda (c) (equal (cdr c) current-id)) choices))
                                 (caar choices)))
             (selection (let ((ivy-initial-inputs-alist nil)
                              (ivy--default nil)
                              (this-command 'my/agent-shell-set-mode))
                          (completing-read "Set mode: "
                                           (mapcar #'car choices)
                                           nil t nil nil default-choice)))
             (selected-id (cdr (assoc selection choices))))
        (when selected-id
          (agent-shell--set-session-mode-id
           :mode-id selected-id
           :on-success (lambda ()
                         (message "Mode switched to: %s" selected-id))))))))

;; Slash commands support in agent-shell prompt
(defun my/agent-shell-slash-command-advice (orig-fn &rest args)
  "Intercept slash commands typed directly into prompt: /session, /history, /model, /thought, /mode, /help, /clear, /lark."
  (if (derived-mode-p 'agent-shell-mode)
      (let* ((raw (or (and (fboundp 'agent-shell--prompt-input)
                           (agent-shell--prompt-input))
                      (and (fboundp 'comint-line-beginning-position)
                           (buffer-substring-no-properties
                            (comint-line-beginning-position)
                            (point-max)))
                      ""))
             ;; Strip prompt characters like ❯ or > or spaces
             (input (string-trim (replace-regexp-in-string "^[❯>\\s-]+" "" (string-trim raw)))))
        (cond
         ((or (string= input "/session") (string= input "/history") (string= input "/resume")
              (string-prefix-p "/session " input) (string-prefix-p "/history " input) (string-prefix-p "/resume " input))
          (my/agent-shell--clean-prompt-input)
          (setq this-command 'my/agent-shell-switch-session)
          (run-at-time 0.05 nil #'my/agent-shell-switch-session))
         ((or (string= input "/model") (string-prefix-p "/model " input))
          (my/agent-shell--clean-prompt-input)
          (setq this-command 'my/agent-shell-set-model)
          (run-at-time 0.05 nil #'my/agent-shell-set-model))
         ((or (string= input "/thought") (string= input "/effort")
              (string-prefix-p "/thought " input) (string-prefix-p "/effort " input))
          (my/agent-shell--clean-prompt-input)
          (setq this-command 'my/agent-shell-set-thought-level)
          (run-at-time 0.05 nil #'my/agent-shell-set-thought-level))
         ((or (string= input "/mode") (string-prefix-p "/mode " input))
          (my/agent-shell--clean-prompt-input)
          (setq this-command 'my/agent-shell-set-mode)
          (run-at-time 0.05 nil #'my/agent-shell-set-mode))
         ((or (string= input "/help") (string= input "/menu") (string= input "/?"))
          (my/agent-shell--clean-prompt-input)
          (setq this-command 'agent-shell-help-menu)
          (run-at-time 0.05 nil #'agent-shell-help-menu))
         ((string= input "/clear")
          (my/agent-shell--clean-prompt-input)
          (run-at-time 0.05 nil (if (fboundp 'agent-shell-clear-buffer)
                                    #'agent-shell-clear-buffer
                                  #'shell-maker-clear-buffer)))
         ((string= input "/lark")
          (my/agent-shell--clean-prompt-input)
          (run-at-time 0.05 nil #'my/agent-shell-lark-start))
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
(define-key my/agent-shell-prefix-map (kbd "t") #'my/agent-shell-set-thought-level)
(define-key my/agent-shell-prefix-map (kbd "m") #'my/agent-shell-set-model)
(define-key my/agent-shell-prefix-map (kbd "M") #'my/agent-shell-set-mode)
(define-key my/agent-shell-prefix-map (kbd "g") #'agent-shell-antigravity-start-agent)
(define-key my/agent-shell-prefix-map (kbd "l") #'agent-shell-anthropic-start-claude-code)
(define-key my/agent-shell-prefix-map (kbd "u") #'agent-shell-cursor-start-agent)
(define-key my/agent-shell-prefix-map (kbd "o") #'my/agent-shell-openai-start-codex)
(define-key my/agent-shell-prefix-map (kbd "e") #'my/agent-shell-ask-dwim)
(defun my/agent-shell-lark-reload ()
  "Reload agent-shell-lark.el and restart the bridge."
  (interactive)
  (when (fboundp 'my/agent-shell-lark-stop)
    (my/agent-shell-lark-stop))
  (load-file (expand-file-name "lisp/agent-shell-lark.el" user-emacs-directory))
  (my/agent-shell-lark-start)
  (message "agent-shell-lark reloaded and started!"))

(define-key my/agent-shell-prefix-map (kbd "L") #'my/agent-shell-lark-start)
(define-key my/agent-shell-prefix-map (kbd "S") #'my/agent-shell-lark-stop)
(define-key my/agent-shell-prefix-map (kbd "R") #'my/agent-shell-lark-reload)
(define-key my/agent-shell-prefix-map (kbd "?") #'agent-shell-help-menu)
(define-key my/agent-shell-prefix-map (kbd "h") #'agent-shell-help-menu)

;; Which-key friendly prompt annotations
(with-eval-after-load 'which-key
  (which-key-add-key-based-replacements "C-c a" "agent-shell")
  (which-key-add-key-based-replacements
    "C-c a a" "agent-shell (default)"
    "C-c a s" "switch agent buffer"
    "C-c a r" "resume/switch session (history)"
    "C-c a t" "set thought level / effort"
    "C-c a m" "switch model"
    "C-c a M" "switch mode (permissions)"
    "C-c a g" "start antigravity"
    "C-c a l" "start claude code"
    "C-c a u" "start cursor agent"
    "C-c a o" "start codex (OpenAI)"
    "C-c a e" "ask dwim / review diff"
    "C-c a L" "start lark bridge"
    "C-c a S" "stop lark bridge"
    "C-c a R" "reload lark bridge"
    "C-c a ?" "agent-shell help menu"
    "C-c a h" "agent-shell help menu"))

(provide 'init-ai)
;;; init-ai.el ends here
