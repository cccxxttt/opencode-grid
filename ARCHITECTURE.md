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
