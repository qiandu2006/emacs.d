;;; init.el --- the entry of emacs config -*- lexical-binding: t -*-
;;; Commentary:
;; 只做引导：加载路径、包系统、按顺序 require lisp/ 下的各模块。
;; 具体配置都在 lisp/init-*.el 里。
;;; Code:

;; early-init is automatically loaded by Emacs 27+ before init.el.
;; When loaded directly (e.g. reload or batch), load it explicitly by path.
(unless (featurep 'early-init)
  (let ((early-init-file (expand-file-name "early-init.el" user-emacs-directory)))
    (when (file-exists-p early-init-file)
      (load early-init-file nil t))))
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
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

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
(require 'init-lisp)
(require 'init-ai)

(setq custom-file (locate-user-emacs-file "custom.el"))
(when (file-exists-p custom-file)
  (load custom-file))

;; ## added by OPAM user-setup for emacs / base ## 56ab50dc8996d2bb95e7856a6eddb17b ## you can edit, but keep this line
(require 'opam-user-setup "~/.emacs.d/opam-user-setup.el")
;; ## end of OPAM user-setup addition for emacs / base ## keep this line

(require 'url-parse)
(require 'url-util)

(defun my/extract-url-info (url)
  "提取 URL 的 Host 与各个 Query 参数，并在独立 Buffer 中清晰展示。"
  (interactive
   (list (read-string "URL: " (thing-at-point 'url t))))
  (let* ((parsed (url-generic-parse-url (string-trim url)))
         (host (url-host parsed))
         (full-path (url-filename parsed))
         (query-str (when (string-match "\\?\\(.*\\)" full-path)
                      (match-string 1 full-path)))
         (params (when query-str
                   ;; 解析 query 字符串并进行 URL 解码
                   (url-parse-query-string query-str nil t))))
    (with-current-buffer (get-buffer-create "*URL Info*")
      (erase-buffer)
      (insert (format "🔗 原始 URL:\n   %s\n\n" url))
      (insert (format "🌐 Host (域名):\n   %s\n\n" (or host "(无 Host)")))
      (insert "📋 参数列表 (Query Params):\n")
      (if (null params)
          (insert "   (无参数)\n")
        (dolist (param params)
          (let ((key (car param))
                (val (cadr param)))
            (insert (format "   • %-20s = %s\n" key val)))))
      (special-mode)
      (display-buffer (current-buffer)))))

(use-package rime
  :ensure t
  :custom
  (default-input-method "rime")
  ;; 直接复用 macOS 鼠须管的配置与词库
  (rime-user-data-dir "~/Library/Rime")
  ;; 针对 Apple Silicon (M1/M2/M3/M4) 与 Intel Mac 指定库路径
  (rime-emacs-module-header-root "/Applications/Emacs.app/Contents/Resources/include")
  (rime-librime-paths
   '("/opt/homebrew/lib/librime.dylib"
     "/usr/local/lib/librime.dylib"))
  :bind
  ;; 绑定 C-\ 为输入法全局切换快捷键
  (:map rime-mode-map
        ("C-`" . 'rime-send-keybinding))
  :config
  ;; 默认候选词展示方式：如果安装了 posframe 则使用悬浮窗，否则使用下方的 message
  (setq rime-show-candidate 'message))

(with-eval-after-load 'rime
  ;; 满足以下任意条件时，自动静默切为英文输入
  (setq rime-disable-predicates
        '(rime-predicate-after-alphabet-char-p    ; 刚打完英文字母后
          rime-predicate-prog-in-code-p           ; 编程模式且光标在代码段内（注释外）
          rime-predicate-space-after-cc-p         ; 中文与空格之后
          rime-predicate-current-uppercase-letter-p))) ; 输入大写字母时

(defun my/sql-compact-region-or-buffer ()
  "将选中区域或当前 Buffer 中的 SQL 多余空行和折行压缩为紧凑格式。"
  (interactive)
  (let ((beg (if (use-region-p) (region-beginning) (point-min)))
        (end (if (use-region-p) (region-end) (point-max))))
    (save-excursion
      ;; 1. 将连续两个以上的空白符替换为一个空格
      (replace-regexp-in-region "[ \t]+" " " beg end)
      ;; 2. 删除空行
      (replace-regexp-in-region "^[ \t]*\n" "" beg end)
      ;; 3. 核心关键字前保留换行，其余字段合并在一行
      (dolist (kw '("FROM" "WHERE" "GROUP BY" "HAVING" "ORDER BY" "LIMIT"))
        (goto-char beg)
        (while (re-search-forward (format "\\s-+%s\\b" kw) end t)
          (replace-match (format "\n%s" kw) t t))))
    (message "SQL 已紧凑化处理")))

(defun my/sql-to-single-line ()
  "将选中区域或当前 Buffer 中的 SQL 压缩为单行（自动安全剔除注释，防语法失效）。"
  (interactive)
  (let* ((beg (if (use-region-p) (region-beginning) (point-min)))
         (end (if (use-region-p) (region-end) (point-max)))
         (text (buffer-substring-no-properties beg end)))
    ;; 1. 剔除单行注释 -- ...
    (setq text (replace-regexp-in-string "--.*$" "" text))
    ;; 2. 剔除多行注释 /* ... */
    (setq text (replace-regexp-in-string "/\\*.*?\\*/" "" text))
    ;; 3. 将所有换行符、制表符及连续多空格压缩为单个空格
    (setq text (replace-regexp-in-string "[ \t\n\r]+" " " text))
    ;; 4. 去除首尾多余空格
    (setq text (string-trim text))
    ;; 替换原内容
    (delete-region beg end)
    (insert text)
    (message "✅ SQL 已安全压缩为单行！")))

;; 绑定快捷键（例如 C-c C-j 或与 sql-mode 绑定）
(with-eval-after-load 'sql
  (define-key sql-mode-map (kbd "C-c C-j") #'my/sql-to-single-line))

(provide 'init)

;;; init.el ends here
;; Local Variables:
;; coding: utf-8
;; byte-compile-warnings: (not unresolved obsolete)
;; End:
