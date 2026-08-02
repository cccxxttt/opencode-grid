# OpenCode Grid 架构

## 目标

opencode `bash` 工具 → COMSPEC shell 代理 → REST API → 网格终端单元格。

## 架构

```
                     opencode bash 工具
                           │
                    [shell 配置]
                           │
                tg-shell.cmd (COMSPEC 代理)
                   │           │
           写入参数到临时文件    回退: cmd.exe
                   │
                tg-proxy.ps1
                   │
           POST /api/exec (127.0.0.1:7890)
                   │
        extension.js HTTP 服务器 (class K)
                   │
         ┌─────────┼─────────┐
         │         │         │
     _handleExec _handleSend _handleRead
         │
     L.resolve(cellId) → {tabId, localCellId}
         │
     GridPanel 终端写入 → xterm.js 渲染
```

## 核心组件

### tg-shell.cmd
COMSPEC shell 代理包装器。拦截所有 shell 调用，将参数写入临时文件，然后调用 PowerShell 代理。如果 API 调用失败，回退到 `cmd.exe` 本地执行。

通过 `TG_DIR` 动态路径解析定位 `tg-proxy.ps1`（支持通过 PATH 调用时的 `%~dp0` 损坏情况）。

### tg-proxy.ps1
从临时文件读取参数，解析命令，调用 `POST /api/exec`。处理三种响应：
- `{opencode: true}` → 退出码 2，信号批次本地执行
- `{output: ...}` → 打印输出，退出码 0（API 已处理）
- `{error: ...}` → 退出码 1，回退到本地执行

### extension.js — HTTP 服务器 (class K)
嵌入 Node.js `http.createServer`，默认 7890 端口，自动 EADDRINUSE 重试。

| 端点 | 方法 | 功能 |
|---|---|---|
| `/api/health` | GET | 健康检查 |
| `/api/info` | GET | 网格信息 |
| `/api/diag` | GET | 诊断（selectedCell、缓冲区长度） |
| `/api/exec` | POST | 在单元格执行命令并返回输出 |
| `/api/send` | POST | 向单元格发送文本 |
| `/api/read` | POST | 读取单元格输出 |
| `/api/broadcast` | POST | 广播到所有单元格 |

### 状态机：忙锁

```
     POST 请求 → _markActive() → _busy = true
                                   │
                            10s 空闲定时器
                                   │
                            _busy = false
```

API 活动时拒绝侧边栏单元格切换。10 秒无请求自动解锁。

## 安装流程

1. 添加扩展目录的 `tg-shell.cmd` 到 opencode `shell` 配置
2. 通过侧边栏 **Setup OpenCode** 按钮自动完成
3. 重启 opencode 使新配置生效

## 关键设计决策

- **API 活动忙锁**（非 shell 提示检测）：可靠；不依赖特定 shell 的输出格式
- **纯 REST**（非 MCP）：避免 MCP 协议的复杂性和端口竞争
- **COMSPEC 级代理**（非 spawn 拦截）：在所有 Node.js 版本和外部工具中一致工作
- **临时文件参数传递**：避免批处理转义问题（`&`, `|`, `>` 等）
- **动态 TG_DIR**：解决通过 PATH 调用时 `%~dp0` 回退到 CWD 的问题

## 多实例隔离

### 问题
两个 VS Code 窗口同时打开 opencode-grid 时，opencode 的 bash 工具可能把命令路由到另一个窗口的 API 服务器。

### 方案：VS Code 窗口 PID 锁定的端口文件

```
VS Code 窗口 A                         VS Code 窗口 B
  extHost Pid: A_host                     extHost Pid: B_host
  vscodeWindowPid: A_win                  vscodeWindowPid: B_win
  API 端口: 7890                          API 端口: 7891
  ports/win-A_win-xxxx.json               ports/win-B_win-yyyy.json

opencode A 终端                          opencode B 终端
  tg-proxy.ps1                            tg-proxy.ps1
    ├ 爬链: powershell→tg-shell→open      ├ 爬链: powershell→tg-shell→open
    │ →shell→pwsh→Code.exe(A_win)         │ →shell→pwsh→Code.exe(B_win)
    ├ 匹配 A_win → 端口 7890             ├ 匹配 B_win → 端口 7891
    └ POST /api/exec → A 的 cell         └ POST /api/exec → B 的 cell
```

### 关键机制

| 环节 | 说明 |
|---|---|
| `process.ppid` | 扩展宿主的父进程 pid = VS Code 窗口进程 pid。每个窗口唯一，即使打开同一 workspace |
| 端口文件名 | `win-<vscodeWindowPid>-<workspaceHash>.json`，位于 `<extensionPath>/data/ports/` |
| 心跳 | 每 30 秒更新 `ts` 字段。代理端跳过超过 2 分钟无跳动的文件 |
| 缓存 | 以 opencode 进程 pid 为 key，缓存到 `%TEMP%\tg-port-opencode-<pid>.txt`，TTL 120 秒 |

### tg-proxy.ps1 端口发现策略（按优先级）

1. **缓存**（< 50ms）— 读 `%TEMP%\tg-port-opencode-<opencodePid>.txt`，验证端口文件活跃后直接使用
2. **进程链匹配** — 从 `$PID` 爬父进程链到根（`Get-ParentPid`），匹配端口文件中 `vscodeWindowPid` 在祖先集中
3. **workspace 路径前缀** — `$PWD.StartsWith(info.workspace)`，应对进程链断开等边缘场景
4. **最新活跃文件** — 心跳 2 分钟内的最新文件
5. **回落 7890** — 无端口文件时的默认值

## 长输出回读

### 问题
`_outputBuffers` 有 50000 字符硬限制（`OUTPUT_BUFFER_SIZE=5e4`）。`_handleExec` 用 `(g.readCell()||"").slice(m)` 从全局缓冲区截取新输出，长上下文时 `m` 接近或超过 50000 导致 `slice` 返回空或错乱内容。

### 方案：独立 PTY onData 订阅

`_handleExec` 在执行前通过 `term.pty.onData(chunk=>{execRaw+=chunk})` 注册独立的输出捕获器。返回时释放订阅器（`execDisposable.dispose()`）。捕获的输出不受 `OUTPUT_BUFFER_SIZE` 限制。

fallback 路径（无 node-pty 或隐藏单元格）保留原来的 `readCell().slice(m)` 逻辑。

PTY 包装器（`_spawnPty`）的 `onData` 方法改为返回 disposable，使扩展代码可以多次订阅而互不干扰。
