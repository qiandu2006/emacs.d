;;; init-org.el --- Org Mode -*- lexical-binding: t -*-
;;; Commentary:
;; 由 init.el 按固定顺序 require，内容与拆分前保持一致。
;;; Code:

(use-package org
  :ensure nil
  :hook (org-mode . org-num-mode)
  ;; ⚠️ 核心修复 1: Agenda 和 Capture 必须是全局快捷键，随时随地呼出
  :bind (("C-c a" . org-agenda)
         ("C-c c" . org-capture)
         :map org-mode-map
         ("C-c C-x C-j" . org-clock-goto)) ; 方便一键跳回正在计时的任务
  :init
  (setq org-directory (file-truename "~/dev/org"))
  (setq org-agenda-files (list (file-truename "~/dev/org/agenda/")))
  (setq org-archive-location "~/dev/org/agenda/done.org::* From %s")

  :config
  ;; ---------------------------------------------------------------------------
  ;; 1. 基础外观与排版优化
  ;; ---------------------------------------------------------------------------
  (setq org-hide-leading-stars t
        org-hide-emphasis-markers t
        org-startup-indented t
        org-startup-folded 'content)      ; 打开文件时默认展开到二级标题

  ;; ---------------------------------------------------------------------------
  ;; 2. 核心重构：多序列 TODO 流转与日志收纳
  ;; ---------------------------------------------------------------------------
  ;; ⚠️ 核心修复 2: 开启抽屉收纳，时间戳和记录全部塞进 :LOGBOOK:，保持正文清爽
  (setq org-log-into-drawer t
        org-log-done 'time)               ; 完成任务时只记完成时间，不弹窗逼写笔记

  ;; ⚠️ 核心修复 3: 拆分为“行动主干流”与“搁置流”两条独立序列
  ;; 快捷键提示：直接按 C-c C-t 加括号里的单字母（如 C-c C-t w）瞬间直达，无需 S-Right 慢慢翻
  (setq org-todo-keywords
        '((sequence "TODO(t)" "WORKING(w!)" "HOLD(h@/!)" "|" "DONE(d!)" "CANCELED(c@/!)")
          (sequence "IDEA(i)" "SOMEDAY(s)" "|" "ABORT(a@)")))

  ;; ⚠️ 核心修复 4: 为各状态赋予清晰的颜色，一眼抓住当前焦点
  (setq org-todo-keyword-faces
        '(("TODO"     . (:foreground "#e06c75" :weight bold))       ; 待办：醒目红
          ("WORKING"  . (:foreground "#e5c07b" :weight bold))       ; 进行中：亮橙黄
          ("HOLD"     . (:foreground "#c678dd" :weight bold))       ; 暂停/阻塞：紫色
          ("DONE"     . (:foreground "#98c379" :weight bold))       ; 完成：柔和绿
          ("CANCELED" . (:foreground "#5c6370" :strike-through t))  ; 取消：灰色带删除线
          ("IDEA"     . (:foreground "#61afef" :weight bold))       ; 想法灵感：蓝色
          ("SOMEDAY"  . (:foreground "#abb2bf" :slant italic))      ; 暂缓/某天：浅灰斜体
          ("ABORT"    . (:foreground "#5c6370" :strike-through t))))

  ;; ---------------------------------------------------------------------------
  ;; 3. Babel 代码块执行配置
  ;; ---------------------------------------------------------------------------
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (shell . t)
     (python . t)
     (sqlite . t))))

(provide 'init-org)

;;; init-org.el ends here
