;;; init-vcs.el --- 版本控制：magit、git-gutter -*- lexical-binding: t -*-
;;; Commentary:
;; 由 init.el 按固定顺序 require，内容与拆分前保持一致。
;;; Code:

(use-package magit
  :ensure t
  :bind
  ("C-x g" . magit-status))

(use-package git-gutter
  :ensure t
  :config
  (global-git-gutter-mode +1))

(provide 'init-vcs)

;;; init-vcs.el ends here
