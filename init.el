;;; init.el --- the entry of emacs config -*- lexical-binding: t -*-
;;; Code:

(require 'early-init)
(require 'custom)

(require 'cl-lib)
(require 'subr-x) ;; cl-loop来自这里

(setq byte-compile-warnings '(not-cl-functions))

(cl-defun open-init-file()
  "Open init file."
  (interactive)
  (find-file "~/.emacs.d/init.el"))

(global-set-key (kbd "<f2>") 'open-init-file)

(cl-defun reload-init-file()
  "Reload init.el file."
  (interactive)
  (load-file "~/.emacs.d/init.el"))

(global-set-key (kbd "<f3>") 'reload-init-file)

;; packages
(add-to-list 'load-path (concat user-emacs-directory "lisp"))

(package-initialize)
(require 'package)
(setq package-enable-at-startup nil)
(setq package-archives
      '(("gnu" . "http://mirrors.tuna.tsinghua.edu.cn/elpa/gnu/")
	("melpa" . "http://mirrors.tuna.tsinghua.edu.cn/elpa/melpa/")))
(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))


;; Emacs builtin packages
(setq-default auto-window-vscroll nil
	      default-directory "~"
	      default-text-properties '(line-spacing 0.2 line-height 1.2) ;default line height
	      frame-title-format "%b"
	      help-window-select t
	      initial-major-mode 'fundamental-mode
	      inhibit-startup-screen t ; disable the startup screen splash
	      isearch-allow-motion t
	      isearch-lazy-count t
	      kill-whole-line t
	      mode-line-compact t
	      make-backup-files nil	; disable backup file
	      read-process-output-max (* 4 1024 1024)
	      require-final-newline t
	      scroll-conservatively 1000
	      show-trailing-whitespace t
	      system-time-locale "C"
	      use-short-answers t)

;; visual-line-mode
(add-hook 'after-init-hook 'global-visual-line-mode)

;; pixel-scroll-precise-mode
(add-hook 'after-init-hook 'pixel-scroll-precision-mode)


;; exec path from shell
(use-package exec-path-from-shell
  :ensure t
  :config
  (when (memq window-system '(mac ns x))
    (exec-path-from-shell-initialize)))

;; Highlight Current Line
(use-package hl-line
  :when (display-graphic-p)
  :hook (prog-mode . hl-line-mode)
  :defer t)

;; ibuffer
(defalias 'list-buffers 'ibuffer)

;; latex
(add-hook 'LaTeX-mode-hook 'prettify-symbols-mode)

;; Org Mode
(use-package org
  :hook (org-mode . org-num-mode)
  :config
  (setq org-hide-leading-stars t
	org-hide-emphasis-markers t
	org-startup-indented t)
  :bind (:map org-mode-map
	      ("C-c a" . org-agenda)
	      ("C-c c" . org-capture)))

(setq org-directory (file-truename "~/dev/org"))
(setq org-agenda-files (list "~/dev/org/agenda/")
      org-log-done 'time)
(setq org-archive-location "~/dev/org/agenda/done.org::* From %s")

(use-package mwim
  :ensure t
  :bind
  ("C-a" . mwim-beginning-of-code-or-line)
  ("C-e" . mwim-end-of-code-or-line))

(setq org-todo-keywords
      '((sequence "TODO(t!)" "SOMEDAY(s)" "NEXT(n)" "WORKING(w)" "PENDING(p)" "|" "DONE(d@/!)" "ABORT(a@/!)")
	))

;; Pulse the cursor line
(dolist (cmd '(recenter-top-bottom other-window))
  (advice-add cmd :after (lambda (&rest _) (pulse-momentary-highlight-one-line))))

;; Show Paren Mode
(use-package paren
  :config
  (setq show-paren-when-point-in-periphery t
	show-paren-when-point-inside-paren t
	show-paren-style 'mixed))

(use-package expand-region
  :ensure t
  :bind ("C-=" . er/expand-region))

;; Recentf
(use-package recentf
  :hook (after-init . recentf-mode)
  ;; recentf-open since v29.1, recentf-open-files since v22
  :bind (("C-c r" . #'recentf-open)))

;; windmove.el, use  <SHIFT - arrow key> to switch buffers
(use-package windmove
  :config (windmove-default-keybindings)
  :defer t)

;; Third part packages
;; make use-package default behavior better
;; with `use-package-always-ensure' you won't need ":ensure t" all the time
;; with `use-package-always-defer' you won't need ":defer t" all the time
(setq use-package-enable-imenu-support t
      use-package-expand-minimally t)

;; Settings for company, auto-complete only for coding.
(use-package company
  :ensure t
  :init (global-company-mode)
  :defer t
  :config
  (setq company-minimum-prefix-length 1) ; 只需敲 1 个字母就开始进行自动补全
  (setq company-tooltip-align-annotations t)
  (setq company-idle-delay 0.0)
  (setq company-show-quick-access t) ;; 给选项编号 (按快捷键 M-1、M-2 等等来进行选择).
  (setq company-selection-wrap-around t)
  (setq company-transformers '(company-sort-by-occurrence))) ; 根据选择的频率进行排序，读者如果不喜欢可以去掉

(use-package company-box
  :ensure t
  :defer t
  :if window-system
  :hook (company-mode . company-box-mode))

;; format all, formatter for almost languages
;; great for programmers
(use-package format-all :ensure t :defer t
  ;; enable format on save with format-all-mode
  ;; :hook ((prog-mode . format-all-mode)
  ;; 	   (format-all-mode . format-all-ensure-formatter))
  ;; and bind a shortcut to manual format
  :bind ("C-c f" . #'format-all-region-or-buffer))

;; iedit - edit same text in one buffer or region
(use-package iedit
  :ensure t
  :defer t
  :bind ("C-;" . iedit-mode))

;; move-dup, move/copy line or region
(use-package move-dup
  :ensure t
  :defer t
  :hook (after-init . global-move-dup-mode))

;; Settings for which-key - suggest next key
(use-package which-key :ensure t
  :hook (after-init . which-key-mode))

;; solve the Chinese paste issue
;; let Emacs auto-guess the selection coding according to the Windows/system settings
(prefer-coding-system 'utf-8)
(setq locale-coding-system 'utf-8)

;; Configs for programming languages
;; (add-hook 'prog-mode-hook (lambda () (setq-local column-number-mode t)))
(column-number-mode t)                       ; 在 Mode line 上显示列号
(add-hook 'prog-mode-hook 'display-line-numbers-mode)
;; (add-hook 'prog-mode-hook 'electric-pair-mode)
(electric-pair-mode t) ;; 自动匹配括号
(add-hook 'prog-mode-hook #'show-paren-mode) ; 编程模式下，光标在括号上时高亮另一个括号
(global-auto-revert-mode t)                  ; 当另一程序修改了文件时，让 Emacs 及时刷新 Buffer
(delete-selection-mode t)                    ; 选中文本后输入文本会替换文本（更符合我们习惯了的其它编辑器的逻辑）
(setq inhibit-startup-message t)             ; 关闭启动 Emacs 时的欢迎界面
(setq make-backup-files nil)                 ; 关闭文件自动备份
(add-hook 'prog-mode-hook 'flymake-mode)
(add-hook 'prog-mode-hook 'hs-minor-mode) ; 编程模式下，可以折叠代码块
(global-display-line-numbers-mode 1)         ; 在 Window 显示行号
(savehist-mode 1)                            ; （可选）打开 Buffer 历史记录保存
(global-display-line-numbers-mode t)
(add-to-list 'default-frame-alist '(width . 90))  ; （可选）设定启动图形界面时的初始 Frame 宽度（字符数）
(add-to-list 'default-frame-alist '(height . 55)) ; （可选）设定启动图形界面时的初始 Frame 高度（字符数）
(add-hook 'prog-mode-hook 'prettify-symbols-mode)
(add-hook 'prog-mode-hook 'which-function-mode)
(global-set-key (kbd "M-/") 'hippie-expand) ; 输入几个字符前缀，然后按下 M-/ 调用 hippie-expand 函数，它会根据前缀匹配后面的内容。不同于普通的代码补全，它的补全还包括了文件名、elisp 函数名等。

(use-package counsel
  :defer t
  :ensure t)

(use-package swiper
  :ensure t)

(use-package ivy
  :ensure t
  :init
  (ivy-mode 1)
  (counsel-mode 1)
  :config
  (setq ivy-use-virtual-buffers t)
  (setq search-default-mode #'char-fold-to-regexp)
  (setq ivy-count-format "(%d%d) ")
  :bind
  (("C-s" . 'swiper)
   ("C-x b" . 'ivy-switch-buffer)
   ("C-c v" . 'ivy-push-view)
   ("C-c s" . 'ivy-switch-view)
   ("C-c V" . 'ivy-pop-view)
   ("C-x C-@" . 'counsel-mark-ring) ; 在某些终端上C-x C-SPC 会被映射为C-x, C-@, 比如在macOS上，所以要手动设置
   ("C-x C-SPC" . 'counsel-mark-ring)
   :map minibuffer-local-map
   ("C-r" . counsel-minibuffer-history)))

(use-package amx
  :ensure t
  :defer t
  :init (amx-mode))

(use-package ace-window
  :ensure t
  :defer t
  :bind (("C-x o" . 'ace-window)))

(use-package hydra
  :ensure t)

(use-package use-package-hydra
  :ensure t
  :after hydra)

(use-package multiple-cursors
  :ensure t
  :defer t
  :after hydra
  :bind
  (("C-x C-h m" . hydra-multiple-cursors/body)
   ("C-S-<mouse-1>" . mc/toggle-cursor-on-click))
  :hydra (hydra-multiple-cursors
	  (:hint nil)
	  "
Up^^             Down^^           Miscellaneous           % 2(mc/num-cursors) cursor%s(if (> (mc/num-cursors) 1) \"s\" \"\")
------------------------------------------------------------------
 [_p_]   Prev     [_n_]   Next     [_l_] Edit lines  [_0_] Insert numbers
 [_P_]   Skip     [_N_]   Skip     [_a_] Mark all    [_A_] Insert letters
 [_M-p_] Unmark   [_M-n_] Unmark   [_s_] Search      [_q_] Quit
 [_|_] Align with input CHAR       [Click] Cursor at point"
	  ("l" mc/edit-lines :exit t)
	  ("a" mc/mark-all-like-this :exit t)
	  ("n" mc/mark-next-like-this)
	  ("N" mc/skip-to-next-like-this)
	  ("M-n" mc/unmark-next-like-this)
	  ("p" mc/mark-previous-like-this)
	  ("P" mc/skip-to-previous-like-this)
	  ("M-p" mc/unmark-previous-like-this)
	  ("|" mc/vertical-align)
	  ("s" mc/mark-all-in-region-regexp :exit t)
	  ("0" mc/insert-numbers :exit t)
	  ("A" mc/insert-letters :exit t)
	  ("<mouse-1>" mc/add-cursor-on-click)
	  ;; Help with click recognition in this hydra
	  ("<down-mouse-1>" ignore)
	  ("<drag-mouse-1>" ignore)
	  ("q" nil)))



(use-package tiny
  :ensure t
  :defer t
  ;; 可选绑定快捷键，笔者个人感觉不绑定快捷键也无妨
  :bind
  ("C-;" . tiny-expand))

(setq sml/no-confirm-load-theme t) ;; Get rid of "Loading a theme can run Lisp code. Really load? (y or n) " message

(use-package good-scroll
  :ensure t
  :if window-system ; 图形化界面时才使用这个插件
  :init (good-scroll-mode))

(use-package smart-mode-line
  :ensure t
  :defer t
  :init (sml/setup))


(global-set-key (kbd "C-j") nil)
(use-package avy
  :ensure t
  :defer t
  :bind
  (("C-j C-SPC" . avy-goto-char-timer)))

(use-package ace-pinyin
  :ensure t
  :config
  (ace-pinyin-global-mode +1))

(use-package magit
  :ensure t
  :bind
  ("C-x g" . magit-status))

(use-package git-gutter
  :ensure t
  :config
  (global-git-gutter-mode +1))

(use-package consult
  :ensure t)

(use-package cnfonts
  :ensure t
  :custom
  (cnfonts-default-fontsize 18)
  :config
  (cnfonts-mode 1))

(use-package marginalia
  :ensure t
  :defer t
  :config
  (marginalia-mode)
  :bind (:map minibuffer-local-map
              ("M-A" . marginalia-cycle)))

(use-package rainbow-delimiters
  :ensure t
  :defer t
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package highlight-symbol
  :ensure t
  :init (highlight-symbol-mode)
  :bind ("<f4>" . highlight-symbol))

(use-package yasnippet
  :ensure t
  :defer t
  :hook
  (prog-mode . yas-minor-mode)
  :config
  (yas-reload-all)
  ;; add company-yasnippet to company-backends
  (cl-defun company-mode/backend-with-yas (backend)
    (if (and (listp backend) (member 'company-yasnippet backend))
	backend
      (append (if (consp backend) backend (list backend))
              '(:with company-yasnippet))))
  (setq company-backends (mapcar #'company-mode/backend-with-yas company-backends))
  ;; unbind <TAB> completion
  (define-key yas-minor-mode-map [(tab)]        nil)
  (define-key yas-minor-mode-map (kbd "TAB")    nil)
  (define-key yas-minor-mode-map (kbd "<tab>")  nil)
  :bind
  (:map yas-minor-mode-map ("S-<tab>" . yas-expand)))

(use-package yasnippet-snippets
  :ensure t
  :defer t
  :after yasnippet)



(use-package dap-mode
  :ensure t
  :defer t
  :after hydra
  :commands dap-debug
  :custom
  (dap-auto-configure-mode t)
  :config
  (dap-ui-mode 1)
  :hydra
  (hydra-dap-mode
   (:color pink :hint nil :foreign-keys run)
   "
^Stepping^          ^Switch^                 ^Breakpoints^         ^Debug^                     ^Eval
^^^^^^^^----------------------------------------------------------------------------------------------------------------
_n_: Next           _ss_: Session            _bb_: Toggle          _dd_: Debug                 _ee_: Eval
_i_: Step in        _st_: Thread             _bd_: Delete          _dr_: Debug recent          _er_: Eval region
_o_: Step out       _sf_: Stack frame        _ba_: Add             _dl_: Debug last            _es_: Eval thing at point
_c_: Continue       _su_: Up stack frame     _bc_: Set condition   _de_: Edit debug template   _ea_: Add expression.
_r_: Restart frame  _sd_: Down stack frame   _bh_: Set hit count   _ds_: Debug restart
_Q_: Disconnect     _sl_: List locals        _bl_: Set log message
                  _sb_: List breakpoints
                  _sS_: List sessions
"
   ("n" dap-next)
   ("i" dap-step-in)
   ("o" dap-step-out)
   ("c" dap-continue)
   ("r" dap-restart-frame)
   ("ss" dap-switch-session)
   ("st" dap-switch-thread)
   ("sf" dap-switch-stack-frame)
   ("su" dap-up-stack-frame)
   ("sd" dap-down-stack-frame)
   ("sl" dap-ui-locals)
   ("sb" dap-ui-breakpoints)
   ("sS" dap-ui-sessions)
   ("bb" dap-breakpoint-toggle)
   ("ba" dap-breakpoint-add)
   ("bd" dap-breakpoint-delete)
   ("bc" dap-breakpoint-condition)
   ("bh" dap-breakpoint-hit-condition)
   ("bl" dap-breakpoint-log-message)
   ("dd" dap-debug)
   ("dr" dap-debug-recent)
   ("ds" dap-debug-restart)
   ("dl" dap-debug-last)
   ("de" dap-debug-edit-template)
   ("ee" dap-eval)
   ("ea" dap-ui-expressions-add)
   ("er" dap-eval-region)
   ("es" dap-eval-thing-at-point)
   ("q" nil "quit" :color blue)
   ("Q" dap-disconnect :color red)))

;; Flymake
(use-package flymake
  :defer t
  :hook (prog-mode . flymake-mode)
  :bind (("M-n" . #'flymake-goto-next-error)
	 ("M-p" . #'flymake-goto-prev-error)))

;; Markdown file support
(use-package markdown-mode
  :ensure t
  :defer t)

;; Zig mode
(use-package zig-mode
  :ensure t
  :defer t)

;; Run code
(use-package quickrun
  :ensure t
  :defer t
  :when (derived-mode-p 'prog-mode))

;; HTTP Request
(use-package restclient
  :ensure t
  :defer t
  :mode (("\\.http\\'" . restclient-mode)))

;; Language Server (eglot - builtin since v29)
(use-package eglot
  ;; 对于 Emacs 29+ 是内置的，ensure t 可以兼容旧版本
  :ensure t
  ;; 在所有编程模式下自动尝试启动 eglot，但排除 emacs-lisp-mode
  :hook (prog-mode . (lambda ()
                       (unless (derived-mode-p 'emacs-lisp-mode)
                         (eglot-ensure))))
  :config
  ;; Common Lisp language server (CL-LSP communicates over stdio).
  (add-to-list 'eglot-server-programs
               '(lisp-mode . ("/Users/fred.du/.emacs.d/bin/cl-lsp" "--stdio")))

  ;; 设置 eglot 在保存时自动格式化
  (add-hook 'eglot-managed-mode-hook
            (lambda () (add-hook 'before-save-hook #'eglot-format-buffer nil t)))

  ;; 为 eglot 定义一套方便的快捷键, 绑定在 eglot 激活的 buffer 中
  (define-key eglot-mode-map (kbd "C-c . r") #'eglot-rename)             ; 重命名
  (define-key eglot-mode-map (kbd "C-c . a") #'eglot-code-actions)       ; Code Actions (修复、重构等)
  (define-key eglot-mode-map (kbd "C-c . f") #'eglot-format-buffer)      ; 格式化 Buffer
  (define-key eglot-mode-map (kbd "C-c . h") #'eldoc)                    ; 显示光标处信息 (等同于 hover)
  ;; 使用 Emacs 内置的 xref 进行跳转，这是 eglot 的推荐方式
  (define-key eglot-mode-map (kbd "C-c . d") #'xref-find-definitions)    ; 跳转到定义
  (define-key eglot-mode-map (kbd "C-c . i") #'xref-find-implementations); 查找实现
  (define-key eglot-mode-map (kbd "C-c . R") #'xref-find-references)     ; 查找引用
  (define-key eglot-mode-map (kbd "C-c . b") #'xref-go-back)             ; 返回跳转前的位置
)

(use-package treesit
  :defer t
  :when (and (fboundp 'treesit-available-p) (treesit-available-p))
  :mode (("\\(?:Dockerfile\\(?:\\..*\\)?\\|\\.[Dd]ockerfile\\)\\'" . dockerfile-ts-mode)
	 ("\\.go\\'" . go-ts-mode)
	 ("/go\\.mod\\'" . go-mod-ts-mode)
	 ("\\.rs\\'" . rust-ts-mode)
	 ("\\.ts\\'" . typescript-ts-mode)
	 ("\\.y[a]?ml\\'" . yaml-ts-mode))
  :config (setq treesit-font-lock-level 4)
  :init
  (setq major-mode-remap-alist
	'((sh-mode         . bash-ts-mode)
	  (c-mode          . c-ts-mode)
	  (c++-mode        . c++-ts-mode)
	  (c-or-c++-mode   . c-or-c++-ts-mode)
	  (css-mode        . css-ts-mode)
	  (js-mode         . js-ts-mode)
	  (java-mode       . java-ts-mode)
	  (js-json-mode    . json-ts-mode)
	  (makefile-mode   . cmake-ts-mode)
	  (python-mode     . python-ts-mode)
	  (ruby-mode       . ruby-ts-mode)
	  (conf-toml-mode  . toml-ts-mode)))
  (setq treesit-language-source-alist
	'((bash       . ("https://github.com/tree-sitter/tree-sitter-bash"))
	  (c          . ("https://github.com/tree-sitter/tree-sitter-c"))
	  (cpp        . ("https://github.com/tree-sitter/tree-sitter-cpp"))
	  (css        . ("https://github.com/tree-sitter/tree-sitter-css"))
	  (cmake      . ("https://github.com/uyha/tree-sitter-cmake"))
	  (csharp     . ("https://github.com/tree-sitter/tree-sitter-c-sharp.git"))
	  (dockerfile . ("https://github.com/camdencheek/tree-sitter-dockerfile"))
	  (elisp      . ("https://github.com/Wilfred/tree-sitter-elisp"))
	  (go         . ("https://github.com/tree-sitter/tree-sitter-go"))
	  (gomod      . ("https://github.com/camdencheek/tree-sitter-go-mod.git"))
	  (html       . ("https://github.com/tree-sitter/tree-sitter-html"))
	  (java       . ("https://github.com/tree-sitter/tree-sitter-java.git"))
	  (javascript . ("https://github.com/tree-sitter/tree-sitter-javascript"))
	  (json       . ("https://github.com/tree-sitter/tree-sitter-json"))
	  (lua        . ("https://github.com/Azganoth/tree-sitter-lua"))
	  (make       . ("https://github.com/alemuller/tree-sitter-make"))
	  (markdown   . ("https://github.com/MDeiml/tree-sitter-markdown" nil "tree-sitter-markdown/src"))
	  (ocaml      . ("https://github.com/tree-sitter/tree-sitter-ocaml" "v0.24.2" "ocaml/src"))
	  (org        . ("https://github.com/milisims/tree-sitter-org"))
	  (python     . ("https://github.com/tree-sitter/tree-sitter-python"))
	  (php        . ("https://github.com/tree-sitter/tree-sitter-php"))
	  (typescript . ("https://github.com/tree-sitter/tree-sitter-typescript" nil "typescript/src"))
	  (tsx        . ("https://github.com/tree-sitter/tree-sitter-typescript" nil "tsx/src"))
	  (ruby       . ("https://github.com/tree-sitter/tree-sitter-ruby"))
	  (rust       . ("https://github.com/tree-sitter/tree-sitter-rust"))
	  (sql        . ("https://github.com/m-novikov/tree-sitter-sql"))
	  (vue        . ("https://github.com/merico-dev/tree-sitter-vue"))
	  (yaml       . ("https://github.com/ikatyang/tree-sitter-yaml"))
	  (toml       . ("https://github.com/tree-sitter/tree-sitter-toml"))
	  (zig        . ("https://github.com/GrayJack/tree-sitter-zig")))))

(load-theme 'manoj-dark t)

(use-package benchmark-init
  :ensure t
  :demand t
  :config
  ;; To disable collection of benchmark data after init is done.
  (add-hook 'after-init-hook 'benchmark-init/deactivate))

(use-package gptel
  :ensure t
  :defer t
  :config
  (setq my-gptel-proxy
	(gptel-make-openai "MyProxy"
	  :host "fast1.bbroot.com"
	  :endpoint "/v1/chat/completions"
	  :key "sk-c9300e25479d83e8e4eb21c92e6a4aa55e477156afe4993ec8a7876608b86ce8"
	  :models '(gpt-5.6-sol)))
  (setq gptel-backend my-gptel-proxy
	gptel-model 'gpt-5.6-sol)
  (message "gptel 已配置使用GPT-5.6-sol后端。")
  )

(use-package treemacs
  :ensure t
  :defer t
  :init
  (with-eval-after-load 'winum
    (define-key winum-keymap (kbd "M-0") #'treemacs-select-window))
  :config
  (progn
    (setq treemacs-collapse-dirs                   (if treemacs-python-executable 3 0)
          treemacs-deferred-git-apply-delay        0.5
          treemacs-directory-name-transformer      #'identity
          treemacs-display-in-side-window          t
          treemacs-eldoc-display                   'simple
          treemacs-file-event-delay                2000
          treemacs-file-extension-regex            treemacs-last-period-regex-value
          treemacs-file-follow-delay               0.2
          treemacs-file-name-transformer           #'identity
          treemacs-follow-after-init               t
          treemacs-expand-after-init               t
          treemacs-find-workspace-method           'find-for-file-or-pick-first
          treemacs-git-command-pipe                ""
          treemacs-goto-tag-strategy               'refetch-index
          treemacs-header-scroll-indicators        '(nil . "^^^^^^")
          treemacs-hide-dot-git-directory          t
          treemacs-indentation                     2
          treemacs-indentation-string              " "
          treemacs-is-never-other-window           nil
          treemacs-max-git-entries                 5000
          treemacs-missing-project-action          'ask
          treemacs-move-files-by-mouse-dragging    t
          treemacs-move-forward-on-expand          nil
          treemacs-no-png-images                   nil
          treemacs-no-delete-other-windows         t
          treemacs-project-follow-cleanup          nil
          treemacs-persist-file                    (expand-file-name ".cache/treemacs-persist" user-emacs-directory)
          treemacs-position                        'left
          treemacs-read-string-input               'from-child-frame
          treemacs-recenter-distance               0.1
          treemacs-recenter-after-file-follow      nil
          treemacs-recenter-after-tag-follow       nil
          treemacs-recenter-after-project-jump     'always
          treemacs-recenter-after-project-expand   'on-distance
          treemacs-litter-directories              '("/node_modules" "/.venv" "/.cask")
          treemacs-project-follow-into-home        nil
          treemacs-show-cursor                     nil
          treemacs-show-hidden-files               t
          treemacs-silent-filewatch                nil
          treemacs-silent-refresh                  nil
          treemacs-sorting                         'alphabetic-asc
          treemacs-select-when-already-in-treemacs 'move-back
          treemacs-space-between-root-nodes        t
          treemacs-tag-follow-cleanup              t
          treemacs-tag-follow-delay                1.5
          treemacs-text-scale                      nil
          treemacs-user-mode-line-format           nil
          treemacs-user-header-line-format         nil
          treemacs-wide-toggle-width               70
          treemacs-width                           35
          treemacs-width-increment                 1
          treemacs-width-is-initially-locked       t
          treemacs-workspace-switch-cleanup        nil)

    ;; The default width and height of the icons is 22 pixels. If you are
    ;; using a Hi-DPI display, uncomment this to double the icon size.
    ;;(treemacs-resize-icons 44)

    (treemacs-follow-mode t)
    (treemacs-filewatch-mode t)
    (treemacs-fringe-indicator-mode 'always)
    (when treemacs-python-executable
      (treemacs-git-commit-diff-mode t))

    (pcase (cons (not (null (executable-find "git")))
                 (not (null treemacs-python-executable)))
      (`(t . t)
       (treemacs-git-mode 'deferred))
      (`(t . _)
       (treemacs-git-mode 'simple)))

    (treemacs-hide-gitignored-files-mode nil))
  :bind
  (:map global-map
        ("M-0"       . treemacs-select-window)
        ("C-x t 1"   . treemacs-delete-other-windows)
        ("C-x t t"   . treemacs)
        ("C-x t d"   . treemacs-select-directory)
        ("C-x t B"   . treemacs-bookmark)
        ("C-x t C-t" . treemacs-find-file)
        ("C-x t M-t" . treemacs-find-tag)))

(use-package treemacs-evil
  :after (treemacs evil)
  :ensure t)

(use-package treemacs-projectile
  :after (treemacs projectile)
  :ensure t)

(use-package treemacs-icons-dired
  :hook (dired-mode . treemacs-icons-dired-enable-once)
  :ensure t)

(use-package treemacs-persp ;;treemacs-perspective if you use perspective.el vs. persp-mode
  :after (treemacs persp-mode) ;;or perspective vs. persp-mode
  :ensure t
  :config (treemacs-set-scope-type 'Perspectives))

(use-package treemacs-tab-bar ;;treemacs-tab-bar if you use tab-bar-mode
  :after (treemacs)
  :ensure t
  :config (treemacs-set-scope-type 'Tabs))

;;; --- Go 语言配置 ---
(use-package go-mode
  :ensure t  ; 确保 go-mode 包已安装
  :defer t   ; 延迟加载，直到打开 .go 文件

  ;; 当 go-mode 启动时，执行以下配置
  :hook
  (go-mode . (lambda ()
               ;; 关键一步：在 go-mode 启动时，自动尝试启动 Eglot
               (eglot-ensure)

               ;; 设置格式化工具为 goimports，而不是默认的 gofmt
               (setq-local gofmt-command "goimports")

               ;; 保存文件时自动格式化
               (add-hook 'before-save-hook 'gofmt-before-save nil 'local)))

  ;; 为 go-mode 设置一些方便的快捷键
  :bind (:map go-mode-map
              ("C-c C-r" . eglot-rename)          ; 重命名符号
              ("C-c C-a" . eglot-code-actions)    ; 代码操作 (如 "实现接口")
              ("M-." . xref-find-definitions)     ; 跳转到定义 (Eglot 会接管这个)
              ("M-," . xref-pop-marker-stack)))   ; 从定义处返回


(use-package rustic
  :ensure t
  :defer t
  :config
  (setq rustic-rustfmt-args "nightly")
  (setq rustic-lsp-client 'eglot))

(setq custom-file (locate-user-emacs-file "custom.el"))
(when (file-exists-p custom-file)
  (load custom-file))

(provide 'init)

;;; init.el ends here
;;; Local Variables:
;; coding: utf-8
;; byte-compile-warnings: (not unresolved obsolete)
;; End:
;; ## added by OPAM user-setup for emacs / base ## 56ab50dc8996d2bb95e7856a6eddb17b ## you can edit, but keep this line
(require 'opam-user-setup "~/.emacs.d/opam-user-setup.el")
;; ## end of OPAM user-setup addition for emacs / base ## keep this line
