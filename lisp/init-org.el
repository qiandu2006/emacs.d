;;; init-org.el --- Org Mode -*- lexical-binding: t -*-
;;; Commentary:
;; 由 init.el 按固定顺序 require，内容与拆分前保持一致。
;;; Code:

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
(setq org-todo-keywords
      '((sequence "TODO(t!)" "SOMEDAY(s)" "NEXT(n)" "WORKING(w)" "PENDING(p)" "|" "DONE(d@/!)" "ABORT(a@/!)")
	))

(provide 'init-org)

;;; init-org.el ends here
