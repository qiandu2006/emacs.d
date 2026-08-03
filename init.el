;;; init.el --- the entry of emacs config -*- lexical-binding: t -*-
;;; Commentary:
;; 只做引导：加载路径、包系统、按顺序 require lisp/ 下的各模块。
;; 具体配置都在 lisp/init-*.el 里。
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

;; 这个顺序是刻意选定的，用于复现拆分前 init.el 的求值次序，改动前请确认：
;; - init-core 设置了 use-package 的全局开关，必须最先加载；
;; - init-ui 要在 init-completion 之前，否则 prog-mode-hook 里 yasnippet 与
;;   rainbow-delimiters / highlight-symbol 的启用次序会反过来；
;; - init-editing 要在 init-completion 之前，否则 after-init-hook 里 move-dup
;;   与 which-key 的次序会反过来；
;; - init-tools 注册的 auto-mode-alist 条目要早于 init-languages 里的 tree-sitter；
;; - init-editing 内部 hydra -> use-package-hydra -> multiple-cursors 的次序不能打乱。
(require 'init-core)
(require 'init-org)
(require 'init-editing)
(require 'init-ui)
(require 'init-completion)
(require 'init-vcs)
(require 'init-project)
(require 'init-tools)
(require 'init-languages)

(setq custom-file (locate-user-emacs-file "custom.el"))
(when (file-exists-p custom-file)
  (load custom-file))

;; ## added by OPAM user-setup for emacs / base ## 56ab50dc8996d2bb95e7856a6eddb17b ## you can edit, but keep this line
(require 'opam-user-setup "~/.emacs.d/opam-user-setup.el")
;; ## end of OPAM user-setup addition for emacs / base ## keep this line

(provide 'init)

;;; init.el ends here
;; Local Variables:
;; coding: utf-8
;; byte-compile-warnings: (not unresolved obsolete)
;; End:
