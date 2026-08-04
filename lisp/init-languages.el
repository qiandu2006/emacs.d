;;; init-languages.el --- 语言支持：flymake、eglot、tree-sitter、Go、Rust -*- lexical-binding: t -*-
;;; Commentary:
;; 由 init.el 按固定顺序 require，内容与拆分前保持一致。
;;; Code:

;; Flymake
(use-package flymake
  :defer t
  :hook (prog-mode . flymake-mode)
  :bind (("M-n" . #'flymake-goto-next-error)
	 ("M-p" . #'flymake-goto-prev-error)))
(defun my/eglot-enable-format-on-save ()
  "在受 eglot 管理的 buffer 中启用保存时格式化。"
  (add-hook 'before-save-hook #'eglot-format-buffer nil t))

(defun my/eglot-organize-imports ()
  "通过 LSP code action 整理 import，服务器不支持时静默跳过。"
  (when (eglot-managed-p)
    (ignore-errors
      (eglot-code-action-organize-imports (point-min) (point-max)))))

;; Language Server (eglot - builtin since v29)
;; 只对确实配了服务器的语言自动启动，避免在没有 LSP 的模式下反复报连接失败。
;; 新增语言时，把对应的 <mode> 加进下面的 :hook 列表即可。
;; Common Lisp 走 SLY（见 init-lisp.el），不挂 eglot。
;; 当前各语言服务器：java=jdtls, rust=rust-analyzer, c/c++=clangd,
;; go=gopls（尚未安装，装好后即可生效）。
(use-package eglot
  ;; 对于 Emacs 29+ 是内置的，ensure t 可以兼容旧版本
  :ensure t
  :hook ((java-ts-mode
	  go-ts-mode
	  rust-ts-mode
	  c-ts-mode
	  c++-ts-mode) . eglot-ensure)
  :config
  ;; Java: jdtls 1.60 自身要求 JDK 21+ 运行，而项目按 JavaSE-11 编译，二者必须分开指定。
  ;; Lombok 必须以 javaagent 挂载，否则 @Slf4j/@RequiredArgsConstructor 生成的成员一律报未解析。
  (add-to-list 'eglot-server-programs
               '((java-mode java-ts-mode)
                 . ("jdtls"
                    "--java-executable" "/Users/fred.du/.sdkman/candidates/java/25.0.3-tem/bin/java"
                    "--jvm-arg=-javaagent:/Users/fred.du/.m2/repository/org/projectlombok/lombok/1.18.38/lombok-1.18.38.jar"
                    :initializationOptions
                    (:settings
                     (:java
                      (:configuration
                       (:runtimes [(:name "JavaSE-11"
                                    :path "/Users/fred.du/.sdkman/candidates/java/11.0.30-tem"
                                    :default t)])))))))

  ;; 保存时自动格式化。用具名函数而不是匿名 lambda，这样重新加载 init.el
  ;; （F3）不会把同一个钩子重复挂上去。
  (add-hook 'eglot-managed-mode-hook #'my/eglot-enable-format-on-save)

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
  ;; 逐项追加而不是整体 setq，避免清掉 Emacs 自身或其他包已经注册的映射
  (dolist (remap '((sh-mode         . bash-ts-mode)
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
    (add-to-list 'major-mode-remap-alist remap))
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
;;; --- Go 语言配置 ---
;; .go 由上面的 treesit 配置直接打开为 go-ts-mode，所以配置必须挂在 go-ts-mode 上，
;; 挂在 go-mode 上不会生效。Eglot 由 eglot 那节的 :hook 统一启动。
;; 格式化交给 eglot（gopls），这里只额外补上 import 整理，避免和 gofmt 重复跑一遍。
(use-package go-ts-mode
  :defer t
  :hook (go-ts-mode . my/go-ts-setup)
  :init
  (defun my/go-ts-setup ()
    (add-hook 'before-save-hook #'my/eglot-organize-imports nil t)))

;;; --- Rust 语言配置 ---
;; 同理，.rs 打开为 rust-ts-mode，rustic 不会被加载，
;; 它的 rustic-lsp-client / rustic-rustfmt-args 设置此前一直是空转的。
;; rust-analyzer 已安装，Eglot 会自动接管；格式化沿用全局的保存时格式化。

(provide 'init-languages)

;;; init-languages.el ends here
