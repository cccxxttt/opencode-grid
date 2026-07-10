# Terminal Grid — OpenCode MCP 增强版

基于 [koenma/terminal-grid](https://github.com/koenma-studio/terminal-grid) v0.4.0，新增 **OpenCode MCP 注册支持**，并修复了 cell ID 映射 bug。

## 修改内容

### 1. OpenCode MCP 注册支持

原版仅支持注册到 Claude Desktop，本版新增 **Register in OpenCode** 按钮：

- 在侧边栏 **MCP Registration** 区域，Claude Desktop 按钮下方新增 OpenCode 按钮
- 点击后写入 `~/.config/opencode/opencode.json`，格式为 OpenCode 原生 `mcp` 配置：

```json
{
  "mcp": {
    "terminal-grid": {
      "type": "local",
      "command": ["node", "/path/to/mcp-server.js"],
      "environment": { "TERMINAL_GRID_PORT": "7890" },
      "enabled": true
    }
  }
}
```

- 自动清理功能同样适用于 OpenCode 配置
- 注册状态检测同时覆盖 Claude Desktop 和 OpenCode

### 2. Cell ID 映射 Bug 修复

**问题**：MCP 工具的 `send_to_cell` 和 `read_cell` 使用 0-based local index 发送 cell ID，但 HTTP API 的 `L.resolve()` 只按全局 ID 查找，导致 `Invalid cell id` 错误。

**修复**：在 `L.resolve()` 中增加 local index 回退逻辑 — 全局 ID 查找失败后，按 `0 <= e < cellCount` 作为 local index 处理，确保两个 ID 系统都能正确解析。

### 3. 涉及文件

| 文件 | 改动 |
|---|---|
| `dist/extension.js` | ~11 处改动：新增 OpenCode 路径/格式/注册/注销/检查/清理 + resolve 修复 + webview UI |
| `mcp-server.js` | 未修改（MCP Server 本身无问题） |

## 安装

将目录复制到 VS Code 扩展目录：

```bash
xcopy /E /I terminal_grid_opencode %USERPROFILE%\.vscode\extensions\koenma.terminal-grid-0.4.0
```

然后重启 VS Code。

## 使用

### 打开终端网格

`Ctrl+Shift+P` → **Terminal Grid: Open Custom Grid** → 选择布局（如 2×3）

### 注册 MCP 到 OpenCode

1. 点击侧边栏的 **Terminal Grid** 图标
2. 展开 **MCP Registration** 区域
3. 点击 **Register in OpenCode** 按钮
4. 重启 OpenCode

### MCP 工具

| 工具 | 说明 |
|---|---|
| `get_grid_info` | 获取网格布局信息（行列数、cell 数量、标签） |
| `send_to_cell` | 向指定 cell 发送命令（cellId 从 1 开始） |
| `read_cell` | 读取指定 cell 输出 |
| `broadcast` | 广播命令到所有 cell |

### 示例

```
在 OpenCode 中：
  先使用 get_grid_info 查看网格布局
  然后用 send_to_cell(1) 在第一个终端运行命令
  用 read_cell(1) 读取输出
```

## 原始功能

- 最多 4×5 (20) 个终端排布在一个编辑器标签页中
- 拖拽边框调整大小
- 单元格合并
- 广播输入
- 启动命令与预设
- 每个 cell 独立配色/字体
- 多标签页支持
- MCP AI 代理控制（Claude Desktop / OpenCode / Claude Code / Codex）

## 许可

MIT License。基于 [koenma/terminal-grid](https://github.com/koenma-studio/terminal-grid) v0.4.0 修改。
