;;; init-tools.el --- 杂项工具：markdown、quickrun、restclient、gptel -*- lexical-binding: t -*-
;;; Commentary:
;; 由 init.el 按固定顺序 require，内容与拆分前保持一致。
;;; Code:

;; Markdown file support
(use-package markdown-mode
  :ensure t
  :defer t)

;; Zig mode
(use-package zig-mode
  :ensure t
  :defer t)

;; Run code
;; 注意：这里不能用 (:when (derived-mode-p 'prog-mode))，那是在加载 init.el 时
;; 对当前 buffer 求值，结果几乎总是 nil，会导致整个配置被跳过。
(use-package quickrun
  :ensure t
  :defer t
  :bind ("C-c C-q" . quickrun))

;; HTTP Request
(use-package restclient
  :ensure t
  :defer t
  :mode (("\\.http\\'" . restclient-mode)))
(use-package benchmark-init
  :ensure t
  :demand t
  :config
  ;; To disable collection of benchmark data after init is done.
  (add-hook 'after-init-hook 'benchmark-init/deactivate))

(use-package gptel
  :ensure t
  :defer t
  :config
  (setq my-gptel-proxy
	(gptel-make-openai "MyProxy"
	  :host "fast1.bbroot.com"
	  :endpoint "/v1/chat/completions"
	  :key "sk-c9300e25479d83e8e4eb21c92e6a4aa55e477156afe4993ec8a7876608b86ce8"
	  :models '(gpt-5.6-sol)))
  (setq gptel-backend my-gptel-proxy
	gptel-model 'gpt-5.6-sol)
  (message "gptel 已配置使用GPT-5.6-sol后端。")
  )

(provide 'init-tools)

;;; init-tools.el ends here
