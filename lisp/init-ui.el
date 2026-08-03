;;; init-ui.el --- 外观：模式栏、字体、配色、主题 -*- lexical-binding: t -*-
;;; Commentary:
;; 由 init.el 按固定顺序 require，内容与拆分前保持一致。
;;; Code:

(setq sml/no-confirm-load-theme t) ;; Get rid of "Loading a theme can run Lisp code. Really load? (y or n) " message

(use-package smart-mode-line
  :ensure t
  :defer t
  :init (sml/setup))
(use-package cnfonts
  :ensure t
  :custom
  (cnfonts-default-fontsize 18)
  :config
  (cnfonts-mode 1))
(use-package rainbow-delimiters
  :ensure t
  :defer t
  :hook (prog-mode . rainbow-delimiters-mode))

;; highlight-symbol-mode 是 buffer-local 的，放在 :init 只会作用于启动时的
;; *scratch*，必须挂到 prog-mode-hook 才对每个代码 buffer 生效
(use-package highlight-symbol
  :ensure t
  :defer t
  :hook (prog-mode . highlight-symbol-mode)
  :bind ("<f4>" . highlight-symbol))
(load-theme 'manoj-dark t)

(provide 'init-ui)

;;; init-ui.el ends here
