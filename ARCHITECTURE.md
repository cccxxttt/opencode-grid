# Terminal Grid + opencode 集成架构

## 目标

本地 `opencode` CLI 可以通过扩展的 REST API 在指定的 terminal-grid cell（含远程 SSH cell）上执行命令和读取结果。

## 架构

```
┌─────────────────────────────────────────────────┐
│  VS Code Extension Host                         │
│  ┌─────────────────────────────────────────┐   │
│  │  Terminal Grid Extension                │   │
│  │  ┌──────────────────────┐              │   │
│  │  │ HTTP Server (class K)│              │   │
│  │  │  post /api/send      │              │   │
│  │  │  post /api/read      │              │   │
│  │  │  post /api/exec ◄────┼──── curl     │   │
│  │  └──────────────────────┘      ^       │   │
│  │         │                       │       │   │
│  │         ▼                       │       │   │
│  │  ┌──────────────┐              │       │   │
│  │  │ Terminal     │              │       │   │
│  │  │ Grid Panel   │              │       │   │
│  │  │ (cells)      │              │       │   │
│  │  │  cell 0      │              │       │   │
│  │  │  cell 1 ◄────┼── 发命令到指定 cell  │   │
│  │  │  cell 2      │              │       │   │
│  │  └──────────────┘              │       │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
         ▲
         │ http://127.0.0.1:7890
         │
┌────────┴────────┐
│ opencode CLI    │
│ (本地终端)      │
│  MCP 工具       │
│  → curl 调 API  │
└─────────────────┘
```

## API 端点

所有 API 返回 `Content-Type: application/json`。

### `POST /api/send`

向指定 cell 发送文本。

```json
// Request
{"cellId": 0, "text": "ls -la", "submit": true}

// Response
{"success": true}
```

### `POST /api/read`

读取指定 cell 的输出。

```json
// Request
{"cellId": 0, "lines": 50}

// Response
{"output": "... terminal output ..."}
```

### `POST /api/exec`

向指定 cell 发命令，等待一段时间后返回输出（组合 send + read）。

```json
// Request
{"cellId": 0, "command": "ls -la", "timeout": 10000}

// Response
{"output": "... command output ..."}
```

### `POST /api/info`

获取 grid 信息。

### `GET /api/health`

健康检查。

## opencode 工具配置

在 opencode 的 MCP 工具中，用 `curl` 调用上述 API：

```json
// opencode.json 的 tools 配置中
{
  "name": "terminal_exec",
  "description": "在 terminal-grid 的指定 cell 执行命令",
  "command": "curl",
  "args": [
    "-s", "-X", "POST",
    "http://127.0.0.1:7890/api/exec",
    "-H", "Content-Type: application/json",
    "-d", "{\"cellId\":CELL_ID,\"command\":\"${command}\"}"
  ]
}
```

## 关键设计点

1. **无 MCP Server 进程**：MCP 协议代码已删除，只有纯 REST API
2. **cellId 作为参数**：每次 API 调用显式指定 cellId，不依赖全局状态
3. **远程 SSH 兼容**：扩展负责底层终端通信，API 调用方无需关心 cell 是本地还是远程
4. **Cell 编号**：与 terminal-grid 的 cellId 一致（grid 内从左到右、从上到下编号）
