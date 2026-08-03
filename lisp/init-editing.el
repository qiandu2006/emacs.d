;;; init-editing.el --- 编辑增强：光标移动、多光标、跳转 -*- lexical-binding: t -*-
;;; Commentary:
;; 由 init.el 按固定顺序 require，内容与拆分前保持一致。
;;; Code:

(use-package mwim
  :ensure t
  :bind
  ("C-a" . mwim-beginning-of-code-or-line)
  ("C-e" . mwim-end-of-code-or-line))
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
  ;; 原先绑在 C-; 会覆盖 iedit-mode，改用 C-:
  :bind
  ("C-:" . tiny-expand))
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

(provide 'init-editing)

;;; init-editing.el ends here
