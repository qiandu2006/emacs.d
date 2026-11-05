# Emacs AI Native 增强与飞书个人会话协同设计文档 (Design Specification)

## 1. 概述与设计目标

本文档详细定义了在 `~/.emacs.d` 中落地由 `emacs.compare` 沉淀而来的 11 项核心生产力特性的架构设计与实现方案。

### 1.1 核心特性矩阵

| 序号 | 特性名称 | 架构归属 | 交付形式 |
| :---: | :--- | :--- | :--- |
| **5** | **多模型后端聚合** | 本地 AI 系统 | `lisp/init-ai.el`（Claude Code / Cursor / Codex / 通用 Agent 统一路由） |
| **6** | **上下文感知式阅读与代码审阅** | 本地 AI 系统 | `lisp/agent-shell-reading.el`（选中区 / 当前 Defun / 类感知） |
| **7** | **网络与接口自愈重试** | 本地 AI 系统 | `lisp/agent-shell-auto-retry.el`（监听 Agent 事件流进行错误恢复） |
| **8** | **1GB GC 内存优化策略** | 基础运行时 | `early-init.el` 与 `lisp/init-core.el`（两阶段 GC + 闲置回收） |
| **9** | **`fd=65536` 防爆启动** | 基础运行时 | `bin/ec`（提升系统软限制，守护进程快速拉起） |
| **10**| **故障自愈指数退避** | 本地 AI 系统 | `lisp/agent-shell-auto-retry.el`（`5/10/20/40/80s` 阶梯退避 + 上文重发） |
| **11**| **Magit 差量辅助审阅** | 本地 AI 系统 | `lisp/agent-shell-reading.el`（自动提取当前 Hunk/File 差异元信息） |
| **1-4**| **飞书远程交互网关 (方案 B)** | 远程通信系统 | `lisp/agent-shell-lark.el`（“给自己的会话”轮询网关 + 文本审批 + 公式渲染） |

---

## 2. 本地核心特性设计 (特性 5, 6, 7, 8, 9, 10, 11)

### 2.1 运行时基础设施优化（特性 8 & 9）

#### 2.1.1 1GB GC 内存管理策略 (特性 8)
- **启动阶段**：在 [early-init.el](file:///Users/fred.du/.emacs.d/early-init.el) 将 `gc-cons-threshold` 设为 `most-positive-fixnum`，消除启动过程中的垃圾回收停顿。
- **运行阶段**：启动完成后将基准门槛调整为 **1GB**（`(* 1024 1024 1024)` 字节），配合 `run-with-idle-timer 2 t #'garbage-collect`，在 Emacs 空闲 2 秒后主动触发 GC，兼顾高吞吐与内存平稳。

#### 2.1.2 文件描述符防爆启动脚本 (特性 9)
- **痛点**：macOS launchd 默认文件描述符软限制仅 256，LSP 与 Agent 大项目文件树监听（kqueue）极易触发 `Too many open files` 异常导致崩溃。
- **设计**：在 [bin/ec](file:///Users/fred.du/.emacs.d/bin/ec) 中使用 `ulimit -n 65536 2>/dev/null` 提升 fd 限制，并直接通过 `emacsclient -a "" -c "$@"` 支持在守护进程未启动时自动静默拉起 Emacs Daemon。

---

### 2.2 多模型后端聚合架构（特性 5）
在 `lisp/init-ai.el` 中统一聚合主流 Agent 引擎与 Emacs 原生通信协议（ACP）：
1. **Claude Code** (`agent-shell-anthropic` & `claude-code-ide`)：通过 MCP 与 ACP 协议接入。
2. **Cursor Agent** (`agent-shell-cursor`)：通过 Cursor 命令行适配器启动交互。
3. **OpenAI Codex** (`agent-shell-openai`)：直连 Codex 系列模型。
4. **统一快捷键命名空间**：
   - `C-c a a`：启动/切换通用 `agent-shell`；
   - `C-c a l`：启动 Claude Code；
   - `C-c a u`：启动 Cursor Agent；
   - `C-c a o`：启动 OpenAI Codex；
   - `C-c a s`：在活动的 Agent Buffers 之间快速切换。
5. **防御性 Buffer 保护 (Display Cap)**：
   通过 advice 拦截 `agent-shell--update-fragment`，当单次 Tool 运行输出超过 120,000 字符时，在 Emacs 缓冲区仅渲染前 80k 与后 40k，避免界面冻结，底层完整数据保留在转储文件（Transcript）与 ACP 载荷中。
6. **macOS Keychain 认证自愈**：
   提供 `my/agent-shell-fix-auth` 命令，一键将 `~/.claude/.credentials.json` 的最新凭证同步入 macOS Keychain 并热重载活跃 Session。

---

### 2.3 上下文感知式阅读与代码审阅（特性 6 & 11）
在 `lisp/agent-shell-reading.el` 中提供全局次要模式 `my/agent-shell-reading-mode`（挂载至 `prog-mode-hook` 与 `magit-mode-hook`），绑定快捷键 **`C-c a e`**：

#### 上下文智能探测规则 (DWIM - Do What I Mean)
```
               按下 C-c a e
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
 处于 Magit 缓冲区?        普通代码缓冲区?
   /         \              /          \
选区激活?    未激活?     选区激活?     未激活?
  │            │           │             │
  ▼            ▼           ▼             ▼
提取选区    提取当前光标   提取选区代码   调用 (bounds-of-thing-at-point 'defun)
diff片断    所在 Hunk /    文本          自动提取当前函数 / 类全貌
            文件差异全量
        \              /            \    /
         ──────────────┬─────────────┘
                       ▼
          自动组装为格式化 Prompt:
          - Source 文件名
          - 语法模式 (Mode)
          - 行号范围 (Lines N-M)
          - Magit 提交区间与 Diff 详情 (若是)
          - 代码 / Diff 原始内容
                       │
                       ▼
          送入 agent-shell-send-dwim
          (C-u 新建 Shell，C-u C-u 选择已有 Shell)
```

---

### 2.4 网络自愈与指数退避重试（特性 7 & 10）
在 `lisp/agent-shell-auto-retry.el` 中建立基于公共事件流的自动恢复管道：
1. **触发识别**：正则匹配回合尾部的致命可重试标记：
   - `^Error: RetriableError:`
   - `exceeded retry limit, last status:[[:space:]]*429[[:space:]]+Too Many Requests$`
2. **阶梯退避策略**：
   按 `[5, 10, 20, 40, 80]` 秒阶梯逐步延迟，最多重试 5 次。
3. **上下文继承与自愈重放**：
   自动记录上一轮由用户发起的 Prompt 内容，重试时自动组装引导词：
   ```text
   [auto-retry] The previous turn failed with a retriable error. Please continue working on the task where you left off.

   Last user prompt before the failure:
   <原用户指令>
   ```
4. **中断与耗尽保护**：用户新输入指令时立即清空退避计时器；5 次耗尽后发出 `retry-exhausted` 事件并挂起等待人工接管。

---

## 3. 方案 B：飞书“给自己会话”远程交互与通信网关设计

由于用户环境无法创建企业级 Bot 应用，本方案完全基于 `lark-cli` 当前已有的**个人用户身份（User Identity）**与**给自己的专属聊天窗口（Chat with Myself）**展开设计。

### 3.1 传输通道与身份建模
- **会话定位**：通过用户自身 open_id（`ou_1ff3608ed8199c1b25cd79ae5d0a36c7`）直接解析到给自己的专属会话 `chat_id`（`oc_09b8602e2998cf916370a67c214e7a5e`）。
- **认证要求**：使用用户凭据。向个人会话发消息需要拥有 `im:message.send_as_user` 授权（未授权时提供自动化唤起授权向导）。

### 3.2 双向交互架构设计

```
 ┌──────────────────────────────────────────────────────────────┐
 │                      飞书客户端 (用户手机 / 桌面)            │
 │                      【给自己的会话窗口】                     │
 └──────────────────────────────┬───────────────────────────────┘
                                ▲
            1. 周期性拉取消息     │  2. 发送进度/完成/审批请求
         (im +chat-messages-list)│  (im +messages-send)
                                │
 ┌──────────────────────────────┴───────────────────────────────┐
 │            Emacs: agent-shell-lark (方案 B 用户网关)         │
 ├──────────────────────────────────────────────────────────────┤
 │  【入站处理引擎 (Inbound)】                                   │
 │   • 异步非阻塞定时器 (默认 2s 轮询一次)                       │
 │   • 环形去重队列 (Seen Message IDs, 过滤己方发送的回显)        │
 │   • 命令调度:                                                │
 │     - 文本 "/cc" -> 触发 Emacs 端 agent-shell-interrupt      │
 │     - 审批中 -> 匹配 "1/y/allow" 或 "2/n/reject" 文本回复    │
 │     - 常规文本 -> 注入 agent-shell-prompt-queue (排队机制)    │
 ├──────────────────────────────────────────────────────────────┤
 │  【出站中继引擎 (Outbound)】                                  │
 │   • 阶段性进度 (Progress Messages): 各 Tool 之间的思考输出    │
 │   • 任务完成提醒: 回合结束自动发送 Summary 并 @操作员         │
 │   • 文本式审批请求:                                          │
 │     "🔒 需要执行权限: [运行 bash 命令]                       │
 │      1: 允许执行 (Allow)                                     │
 │      2: 拒绝 (Reject)                                        │
 │      请直接回复数字 (1 或 2)"                                │
 ├──────────────────────────────────────────────────────────────┤
 │  【LaTeX 科学公式图片渲染引擎】                              │
 │   • 正则扫描 $$...$$ 或 \[...\] 块                           │
 │   • Node.js (MathJax) 渲染为 SVG                            │
 │   • rsvg-convert 栅格化为 PNG (支持降级保护)                  │
 │   • lark-cli 上传图片获取 image_key 并替换为内联 Markdown     │
 └──────────────────────────────────────────────────────────────┘
```

### 3.3 核心技术攻坚与规避逻辑
1. **自发自收回环风暴（Echo Loop Prevention）**：
   在“给自己的会话”中，Emacs 代表用户发出的通知和用户输入的指令**发件人均是同一个 open_id**。
   - **防御机制**：Emacs 端发送任何消息后，立即将其记录至 `agent-shell-lark--sent-messages` 缓存集；轮询拉取消息时，凡在此集中的 `message_id` 或内容哈希一律静默丢弃。
2. **交互式卡片降级为精准文本审批**：
   因为卡片交互动作（Action Buttons）在开放平台强校验 Bot 身份，本方案将审批流平滑降级为序号选择（Option 1/2 或 y/n），Emacs 内部保持完整的异步 `respond` 回调挂起，直到用户在飞书回复选项。
3. **公式渲染弹性降级**：
   本地存在 `node` 与 `rsvg-convert` 时自动渲染高清公式图片；缺失时无缝回退为原始 LaTeX 源码，绝不中断消息传递。

---

## 4. 文件结构与安装加载编排

新增及改造文件在 `~/.emacs.d` 下的落地布局如下：

```
~/.emacs.d/
├── bin/
│   └── ec                             # [特性 9] 提升 fd 至 65536 的启动脚本
├── lark-tools/                        # [特性 3] 公式图片渲染工具链
│   ├── package.json
│   └── tex2svg.js
├── lisp/
│   ├── init-ai.el                     # [特性 5] AI 聚合模块与展示保护
│   ├── agent-shell-reading.el         # [特性 6 & 11] 代码阅读与 Magit 差量审阅
│   ├── agent-shell-auto-retry.el      # [特性 7 & 10] 故障自愈指数退避引擎
│   └── agent-shell-lark.el            # [特性 1-4 方案 B] 个人会话远程通信网关
├── init.el                            # 挂载 (require 'init-ai)
├── design.md                          # 本设计文档
└── README.md                          # 最终使用手册与全量按键速查表
```

---

## 5. 键位映射速查总表

| 快捷键 | 作用范围 | 功能说明 | 对应特性 |
| :--- | :--- | :--- | :---: |
| **`C-c a a`** | 全局 | 打开 / 调出主 `agent-shell` 交互终端 | 特性 5 |
| **`C-c a l`** | 全局 | 启动 Claude Code 专属会话 | 特性 5 |
| **`C-c a u`** | 全局 | 启动 Cursor Agent 专属会话 | 特性 5 |
| **`C-c a o`** | 全局 | 启动 OpenAI Codex 专属会话 | 特性 5 |
| **`C-c a s`** | 全局 | 快速切换活动中的多个 Agent 会话缓冲区 | 特性 5 |
| **`C-c a e`** | 代码 / Magit | 上下文感知代码解释 / 审阅（支持函数、选中区、Magit Diff Hunk） | 特性 6 & 11 |
| **`M-x my/agent-shell-lark-start`** | Agent Shell | 启动飞书个人会话双向同步网关 | 特性 1-4 (B) |
| **`M-x my/agent-shell-lark-stop`** | Agent Shell | 停止飞书同步网关 | 特性 1-4 (B) |
| **`M-x my/agent-shell-fix-auth`** | 全局 | 同步 Claude 凭证至 macOS Keychain 并热重载会话 | 特性 5 |
