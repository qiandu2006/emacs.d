;;; init-lisp.el --- Common Lisp：SLY + paredit + Roswell/SBCL -*- lexical-binding: t -*-
;;; Commentary:
;; Common Lisp 走交互式路线（SLY），不挂 eglot/cl-lsp。
;; 实现为 Roswell 管理的 SBCL（`ros -Q run`），带 Quicklisp。
;;; Code:

;; .asd 是 ASDF 系统定义，按 Lisp 源码编辑
(add-to-list 'auto-mode-alist '("\\.asd\\'" . lisp-mode))

(use-package sly
  :ensure t
  :defer t
  :commands (sly sly-connect)
  :custom
  ;; Roswell 启动 SBCL 并加载 Quicklisp（-Q）
  (inferior-lisp-program "ros -Q run")
  (sly-net-coding-system 'utf-8-unix)
  (sly-kill-without-query-p t)
  :hook (lisp-mode . sly-editing-mode)
  :bind (:map lisp-mode-map
              ("C-c C-z" . sly)
              ("C-c . d" . sly-edit-definition)
              ("C-c . R" . sly-edit-uses)
              ("C-c . e" . sly-eval-defun)
              ("C-c . k" . sly-compile-and-load-file)
              ("C-c . h" . sly-documentation)
              ("C-c . m" . sly-expand-1)
              ("C-c . M" . sly-macroexpand-all)
              :map sly-mode-map
              ("C-c . d" . sly-edit-definition)
              ("C-c . R" . sly-edit-uses)
              ("C-c . e" . sly-eval-defun)
              ("C-c . b" . sly-pop-find-definition-stack))
  :config
  ;; sly-fancy：补全、autodoc、stickers、Trace Dialog 等常用扩展
  (sly-setup '(sly-fancy)))

(use-package paredit
  :ensure t
  :defer t
  :hook ((lisp-mode . enable-paredit-mode)
         (sly-mode . enable-paredit-mode)))

(provide 'init-lisp)

;;; init-lisp.el ends here
