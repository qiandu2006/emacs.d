;;; init-core.el --- Emacs 内置设置、备份策略、编程模式全局开关 -*- lexical-binding: t -*-
;;; Commentary:
;; 由 init.el 按固定顺序 require，内容与拆分前保持一致。
;;; Code:

;; Emacs builtin packages
(setq-default auto-window-vscroll nil
	      default-directory "~"
	      line-spacing nil
	      default-text-properties nil
	      frame-title-format "%b"
	      help-window-select t
	      initial-major-mode 'fundamental-mode
	      inhibit-startup-screen t ; disable the startup screen splash
	      isearch-allow-motion t
	      isearch-lazy-count t
	      kill-whole-line t
	      mode-line-compact t
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

;; 备份与自动保存：保留版本化历史，但集中存放，避免在项目目录里散落 file~ 和 #file#
(let ((backup-dir (expand-file-name ".cache/backups/" user-emacs-directory)))
  (make-directory backup-dir t)
  (setq backup-directory-alist       `(("." . ,backup-dir))
	auto-save-file-name-transforms `((".*" ,backup-dir t))
	backup-by-copying  t
	version-control    t
	delete-old-versions t
	kept-new-versions  6
	kept-old-versions  2))


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
;; solve the Chinese paste issue
;; let Emacs auto-guess the selection coding according to the Windows/system settings
(prefer-coding-system 'utf-8)
(setq locale-coding-system 'utf-8)

;; Configs for programming languages
;; (add-hook 'prog-mode-hook (lambda () (setq-local column-number-mode t)))
(column-number-mode t)                       ; 在 Mode line 上显示列号
;; (add-hook 'prog-mode-hook 'electric-pair-mode)
(electric-pair-mode t) ;; 自动匹配括号
(add-hook 'prog-mode-hook #'show-paren-mode) ; 编程模式下，光标在括号上时高亮另一个括号
(global-auto-revert-mode t)                  ; 当另一程序修改了文件时，让 Emacs 及时刷新 Buffer
(delete-selection-mode t)                    ; 选中文本后输入文本会替换文本（更符合我们习惯了的其它编辑器的逻辑）
(setq inhibit-startup-message t)             ; 关闭启动 Emacs 时的欢迎界面
(add-hook 'prog-mode-hook 'hs-minor-mode) ; 编程模式下，可以折叠代码块
(global-display-line-numbers-mode 1)         ; 在 Window 显示行号（已覆盖 prog-mode，无需再挂 hook）
(savehist-mode 1)                            ; （可选）打开 Buffer 历史记录保存
(add-to-list 'default-frame-alist '(width . 90))  ; （可选）设定启动图形界面时的初始 Frame 宽度（字符数）
(add-to-list 'default-frame-alist '(height . 55)) ; （可选）设定启动图形界面时的初始 Frame 高度（字符数）
(add-hook 'prog-mode-hook 'prettify-symbols-mode)
(add-hook 'prog-mode-hook 'which-function-mode)
(global-set-key (kbd "M-/") 'hippie-expand) ; 输入几个字符前缀，然后按下 M-/ 调用 hippie-expand 函数，它会根据前缀匹配后面的内容。不同于普通的代码补全，它的补全还包括了文件名、elisp 函数名等。

(provide 'init-core)

;;; init-core.el ends here
