# Emacs 配置指南与功能快捷键速查手册 (README)

欢迎使用本 Emacs 配置！本配置深度基于 **GNU Emacs 29/30+ 原生轻量哲学** 打造，集成了企业级多语言开发栈（Java/Lisp/Go/Rust）、极致丝滑的中文排版与输入体验、高度结构化的 Org GTD 个人效能体系，以及全新的 **AI Native Agent-Shell 深度协作系统** 与 **飞书个人会话远程通信网关 (方案 B)**。

---

## 目录
- [一、 启动与基础设施特性](#一-启动与基础设施特性)
- [二、 AI Native 智能协同系统 (特性 5, 6, 7, 10, 11)](#二-ai-native-智能协同系统)
- [三、 飞书个人会话双向远程通信网关 (方案 B)](#三-飞书个人会话双向远程通信网关-方案-b)
- [四、 全量功能按键速查总表 (Cheat Sheet)](#四-全量功能按键速查总表-cheat-sheet)
  - [1. AI 与 Agent-Shell 快捷键](#1-ai-与-agent-shell-快捷键)
  - [2. 编程语言与 LSP (Eglot / SLY) 快捷键](#2-编程语言与-lsp-eglot--sly-快捷键)
  - [3. 编辑与光标微操 (Hydra / Iedit / Avy) 快捷键](#3-编辑与光标微操-hydra--iedit--avy-快捷键)
  - [4. 全局检索、窗口与项目管理](#4-全局检索窗口与项目管理)
  - [5. Org-Mode 个人效能 (GTD) 快捷键](#5-org-mode-个人效能-gtd-快捷键)
  - [6. 特色工作流辅助工具](#6-特色工作流辅助工具)

---

## 一、 启动与基础设施特性

### 1. `bin/ec`：防爆启动脚本 (特性 9)
macOS 默认对图形进程的文件描述符限制仅 256，在大型代码工程中 LSP 和 Agent 启动 `kqueue` 文件监控极易触发崩溃。
- **启动命令**：在终端中使用 `~/.emacs.d/bin/ec` 代替原生启动方式。
- **机制**：
  - 自动提升当前软限制：`ulimit -n 65536`；
  - 智能解析 Homebrew 或应用目录下的 `emacsclient`；
  - 携带 `-a ""` 参数：若后台未启动 Emacs 守护进程（Daemon），则静默自动启动后再连接。

### 2. 1GB 内存优化与双阶段 GC (特性 8)
- **启动阶段**：`gc-cons-threshold` 设为最大，启动过程零停顿；
- **运行阶段**：将 GC 基准阀门稳定在 **1GB** (`(* 1024 1024 1024)`)；
- **空闲回收**：配置 `(run-with-idle-timer 2 t #'garbage-collect)`，在光标停歇 2 秒后利用闲置 CPU 执行轻量 GC，兼顾高吞吐与低停顿。

---

## 二、 AI Native 智能协同系统

配置将 `C-c a` 设为全局 AI Agent 专属快捷键前缀，打通了终端、代码、差异审阅及大模型引擎。

### 1. 多模型后端聚合 (特性 5)
支持在 Emacs 中直接启动和切换不同的主流 Agent 引擎：
- **Claude Code**：`C-c a l` 启动 Claude 交互；
- **Cursor Agent**：`C-c a u` 启动 Cursor Agent 会话；
- **OpenAI Codex**：`C-c a o` 启动 Codex 会话；
- **通用 Agent-Shell**：`C-c a a` 启动通用 Agent 会话；
- **多会话切换**：`C-c a s` 快速在多个运行中的 Agent 间切换。
- **凭证自愈**：执行 `M-x my/agent-shell-fix-auth` 自动将 `~/.claude/.credentials.json` 凭证同步进 macOS Keychain 并热重载会话。

### 2. 上下文感知式阅读与 Magit 差量审阅 (特性 6 & 11)
全局绑定 **`C-c a e`**（挂载于 `prog-mode` 与 `magit-mode`）：
- **普通代码窗口**：
  - 若有**选区（Region）**：精准提取选中的代码块发问；
  - 若**无选区**：自动利用 Treesit / defun 解析当前光标所在的**函数或类全貌**，自动组装行号、文件路径与语法模式发问。
- **Magit Diff 窗口**：
  - 自动感知当前光标所在的 **Diff Hunk** 或 **文件差异**；
  - 自动提取 Commit 区间、Revision 与修改内容，直接送入 Agent 进行专业的代码审查与修改意图解读。

### 3. 网络与接口自愈重试 (特性 7 & 10)
- 内置针对大模型接口超限（`429 Too Many Requests`）与 `RetriableError` 的自动侦测；
- 采用 **`5s -> 10s -> 20s -> 40s -> 80s`** 的五级指数退避重试阶梯；
- 自动提取上一轮失败的用户指令并组装恢复引导语，在网络或 API 抖动时实现无人值守自愈。

### 4. 超大输出截断保护 (Buffer Display Cap)
当 Agent 执行 Tool Call 输出超过 120,000 字符时，Emacs Buffer 仅渲染前 80k 与后 40k 字符，防止 UI 卡死，同时完整的日志原样保存在外部转储文件（`~/.cache/agent-shell/transcripts/`）中。

---

## 三、 飞书个人会话双向远程通信网关 (方案 B)

专为**无法创建企业级 Bot 应用**的个人打造，通过 `lark-cli` 直接连接飞书**“给自己的会话窗口（Chat with Myself）”**。

### 1. 启动与管理
- **启动网关**：在任意 Agent-Shell 缓冲区中按下 `C-c a L`（或 `M-x my/agent-shell-lark-start`）；
- **停止网关**：按下 `C-c a S`（或 `M-x my/agent-shell-lark-stop`）；
- **查看状态**：`M-x my/agent-shell-lark-status` 查看轮询周期与当前绑定状态。

### 2. 远程操作指南（在手机或电脑飞书上）
1. **下发 Prompt**：直接向“给自己的会话”发文字，Emacs 端自动识别并注入 Agent；若 Agent 忙碌，会自动在后台排队并向您发送入队反馈。
2. **远程打断**：发送文本 **/cc** 即可向 Emacs 触发 `agent-shell-interrupt` 强行打断当前任务。
3. **文本式权限审批**：
   当 Agent 发起敏感操作（如执行 Shell、写入文件）时，飞书端会收到提示：
   ```text
   🔒 [权限审批请求]
   操作: Run command: git push
   请直接回复数字序号选择操作:
     1: Allow
     2: Reject
   (亦可回复 y 允许 / n 拒绝)
   ```
   您只需在手机飞书上**直接回复 `1` 或 `y`** 即可放行，回复 `2` 或 `n` 拒绝。
4. **LaTeX 科学公式渲染**：
   若 Agent 输出包含 `$$...$$` 或 `\[...\]`，本地 Node.js (MathJax) 会自动将其渲染为高清图片并换入飞书消息中展示。
5. **首次权限授权提示**：
   向个人会话发消息需要拥有 `im:message.send_as_user` 授权。若遇到权限提示，只需在终端运行一次 `lark-cli auth login --scope "im:message.send_as_user"` 并在浏览器点击授权即可。

---

## 四、 全量功能按键速查总表 (Cheat Sheet)

### 1. AI 与 Agent-Shell 快捷键

| 快捷键 | 作用域 | 功能描述 |
| :--- | :--- | :--- |
| **`C-c a a`** | 全局 | 打开 / 启动主 `agent-shell` 交互终端 |
| **`C-c a g`** | 全局 | 启动 Antigravity 专属会话 (`agy acp`) |
| **`C-c a l`** | 全局 | 启动 Claude Code 专属会话 (`claude-agent-acp`) |
| **`C-c a u`** | 全局 | 启动 Cursor Agent 专属会话 (`agent acp`) |
| **`C-c a o`** | 全局 | 启动 OpenAI Codex 专属会话 (`codex-acp`) |
| **`C-c a s`** | 全局 | 快速在活动的 Agent 缓冲区之间切换 |
| **`C-c a e`** | 代码 / Magit | 上下文感知代码解读 / Diff 差异审阅（支持选区、函数、Diff Hunk） |
| **`C-c a L`** | 全局 | 启动飞书个人会话同步网关 (Scheme B) |
| **`C-c a S`** | 全局 | 停止飞书个人会话同步网关 |
| `M-x my/agent-shell-fix-auth` | 全局 | 同步 Claude 凭证至 macOS Keychain 并热重载会话 |
| `M-x my/agent-shell-lark-status` | 全局 | 查看飞书个人会话网关运行状态 |

---

### 2. 编程语言与 LSP (Eglot / SLY) 快捷键

代码缓冲区统一采用原生 **Eglot**（Java/Go/Rust/C++）与 **SLY**（Common Lisp）驱动，快捷键前缀统一为 `C-c .`：

| 快捷键 | 模式 | 功能描述 |
| :--- | :--- | :--- |
| **`C-c . d`** | Eglot / SLY | 跳转到定义 (`xref-find-definitions`) |
| **`C-c . i`** | Eglot | 跳转到接口实现 (`xref-find-implementations`) |
| **`C-c . R`** | Eglot / SLY | 查找所有符号引用 (`xref-find-references`) |
| **`C-c . b`** | Eglot / SLY | 返回跳转前的位置 (`xref-go-back`) |
| **`C-c . r`** | Eglot | 符号重命名 (`eglot-rename`) |
| **`C-c . a`** | Eglot | Code Actions 代码修复 / 快速重构 |
| **`C-c . f`** | Eglot | 格式化当前缓冲区 (`eglot-format-buffer`) |
| **`C-c . h`** | Eglot / SLY | 悬浮查看文档与类型签名 (`eldoc`) |
| **`C-c . e`** | SLY (Lisp) | 交互式对光标处 defun 求值 |
| **`C-c . k`** | SLY (Lisp) | 编译并加载当前 Lisp 文件 |
| **`C-c . m`** | SLY (Lisp) | 单步展开宏 (`sly-expand-1`) |
| **`C-c . M`** | SLY (Lisp) | 完全展开宏 (`sly-macroexpand-all`) |
| **`C-c C-z`** | Lisp Mode | 打开并切换至 SLY REPL |
| **`C-c C-q`** | 编程模式 | `quickrun` 即时运行当前代码 |
| **`M-n` / `M-p`** | 编程模式 | Flymake 下一个 / 上一个语法错误跳转 |

---

### 3. 编辑与光标微操 (Hydra / Iedit / Avy) 快捷键

| 快捷键 | 功能描述 |
| :--- | :--- |
| **`C-a`** | `mwim-beginning-of-code-or-line`：智能在代码首字符与行首间切换 |
| **`C-e`** | `mwim-end-of-code-or-line`：智能在代码尾与行尾间切换 |
| **`C-;`** | `iedit-mode`：同时批量重命名/编辑当前缓冲区所有匹配项 |
| **`C-:`** | `tiny-expand`：快速根据表达式生成数字/字母序列 |
| **`C-c f`** | `format-all`：格式化选中区域或整个缓冲区 |
| **`C-x C-h m`** | **唤出 Hydra 多光标控制面板**（支持下文多光标微操） |
| ↳ `n` / `p` | 在 Hydra 中选中下一个 / 上一个相同匹配项 |
| ↳ `N` / `P` | 跳过当前并跳向下一个 / 上一个匹配项 |
| ↳ `a` | 选中所有匹配项进入多光标编辑 |
| ↳ `l` | 将选中行拆分为多行独立光标 |
| ↳ `0` / `A` | 多光标批量插入递增数字 / 字母序列 |
| ↳ `\|` | 多光标文本垂直对齐 |
| **`C-j C-SPC`** | `avy-goto-char-timer`：快速跳转到字符（**支持输入拼音首字母跳中文**） |
| **`C-=`** | `expand-region`：智能按语义层级逐步扩大选中区域 |
| **`<f4>`** | `highlight-symbol`：高亮/取消高亮光标所在符号 |
| **`C-x o`** | `ace-window`：多窗口一键标号直达切换 |

---

### 4. 全局检索、窗口与项目管理

| 快捷键 | 功能描述 |
| :--- | :--- |
| **`C-s`** | `swiper`：当前缓冲区交互式正则行搜索 |
| **`C-x b`** | `ivy-switch-buffer`：智能模糊切换 Buffer |
| **`C-c v`** | `ivy-push-view`：暂存当前窗口布局视图 |
| **`C-c s`** | `ivy-switch-view`：切换并恢复已保存的窗口视图 |
| **`C-c V`** | `ivy-pop-view`：删除暂存的窗口视图 |
| **`C-x C-SPC`** / **`C-x C-@`** | `counsel-mark-ring`：交互式在全局历史光标标记点间跳转 |
| **`M-0`** | `treemacs-select-window`：一键将光标聚焦至左侧 Treemacs 文件树 |
| **`C-x t t`** | 开关 Treemacs 项目文件树侧边栏 |
| **`C-x g`** | `magit-status`：呼出 Git 版本控制中心面板 |
| **`C-c r`** | `recentf-open`：打开最近访问过的文件列表 |
| **`Shift + 方向键`** | `windmove`：按方向键快速在相邻窗口间跳跃 |
| **`F2`** | 快速打开个人配置入口 `init.el` |
| **`F3`** | 快速重新加载 `init.el`（热生效） |

---

### 5. Org-Mode 个人效能 (GTD) 快捷键

| 快捷键 | 作用域 | 功能描述 |
| :--- | :--- | :--- |
| **`C-c A`** | 全局 | 打开全局 Org Agenda 日程与任务汇总表 |
| **`C-c c`** | 全局 | 打开全局 Org Capture 随时随地收集想法与待办 |
| **`C-c C-x C-j`** | Org 模式 | 一键跳回当前正在计时的任务项 |
| **`C-c C-t <key>`** | Org 模式 | **任务状态单字母快速流转**： |
| ↳ `C-c C-t t` | Org 模式 | 流转至 **TODO**（待办：红） |
| ↳ `C-c C-t w` | Org 模式 | 流转至 **WORKING**（进行中：亮橙黄） |
| ↳ `C-c C-t h` | Org 模式 | 流转至 **HOLD**（阻塞暂停：紫色） |
| ↳ `C-c C-t d` | Org 模式 | 流转至 **DONE**（完成：绿色，自动折叠时间戳入抽屉） |
| ↳ `C-c C-t c` | Org 模式 | 流转至 **CANCELED**（取消：删除线灰） |
| ↳ `C-c C-t i` | Org 模式 | 流转至 **IDEA**（想法灵感：蓝色） |
| ↳ `C-c C-t s` | Org 模式 | 流转至 **SOMEDAY**（未来某天：浅灰斜体） |

---

### 6. 特色工作流辅助工具

| 快捷键 / 命令 | 作用域 | 功能描述 |
| :--- | :--- | :--- |
| **`C-c C-j`** | SQL Mode / 选中区 | `my/sql-to-single-line`：安全剔除注释并压缩为单行 SQL |
| `M-x my/sql-compact-region-or-buffer` | SQL Mode | 将 SQL 压缩为紧凑多行格式（保留关键子句换行） |
| `M-x my/extract-url-info` | 全局 | 在独立窗口清晰展示 URL 的 Host 与解析后的每个 Query 参数 |
| **`C-\`** | 全局 | 切换 Rime 输入法（自动挂接系统鼠须管配置） |
| `~/.emacs.d/bin/ec` | Shell 命令行 | 提高 fd=65536 限制并安全拉起 Emacsclient |
