# OpenCode Grid

基于 [koenma/terminal-grid](https://github.com/koenma-studio/terminal-grid) v0.4.0，增加 **COMSPEC shell 代理**，实现 opencode `bash` 工具到网格终端的路由。

## 架构

```
opencode bash 工具
    → tg-shell.cmd (COMSPEC shell 代理)
        → tg-proxy.ps1 (PowerShell API 客户端)
            → POST /api/exec (嵌入扩展的 HTTP 服务器, 127.0.0.1:7890)
                → 写入网格单元格终端
```

- 不使用 MCP 协议 — 纯 HTTP REST
- 不使用 spawn/PTY 拦截 — OS 级别 COMSPEC 代理
- 单元格选择通过侧边栏下拉菜单完成

## 安装

```bash
xcopy /E /I opencode-grid %USERPROFILE%\.vscode\extensions\opencode-grid
```

重启 VS Code。

## 使用

### 1. 打开网格
`Ctrl+Shift+P` → **OpenCode Grid: Open Custom Grid** → 选择布局（如 2×3）

### 2. 设置 Shell 代理（一次性）
点击侧边栏 **Setup OpenCode** 按钮，自动写入 `~/.config/opencode/opencode.json` 的 `shell` 路径。

### 3. 路由命令到单元格
从侧边栏下拉单元格选择器选择目标单元格 → 在 opencode 中运行命令 → 命令写入所选单元格。

### 4. 添加自定义 API（可选）
侧边栏 **Custom API** 卡片中点击 "+ Add Provider"，填写：
- Provider Name（显示名，如 `My Custom GPT`）
- Base URL（如 `https://api.openai.com/v1` 或 `http://127.0.0.1:11434/v1`）
- API Key（明文，或用 `{env:VAR_NAME}` / `{file:path}` 引用环境变量/文件）
- Models（至少一个 Model ID + 显示名）

保存后写入 `~/.config/opencode/opencode.json`（先备份 `.bak`）。在卡片底部 **Active model** 下拉选择默认模型。重启 opencode 进程使配置生效。

## 文件说明

| 文件 | 作用 |
|---|---|
| `dist/extension.js` | 扩展主代码：WebviewPanel + HTTP API 服务器 + 侧边栏 |
| `tg-shell.cmd` | COMSPEC 代理包装器：拦截 shell 调用 → 调用 PowerShell → 回退到 cmd.exe |
| `tg-proxy.ps1` | PowerShell API 代理：读取参数 → 调用 `POST /api/exec` |
| `package.json` | 扩展元数据 + 命令 + 配置项 |

## API 端点（嵌入 HTTP 服务器，默认 7890 端口）

| 端点 | 说明 |
|---|---|
| `GET /api/health` | 健康检查 |
| `GET /api/info` | 网格信息 |
| `GET /api/diag` | 诊断（含 `selectedCell`） |
| `POST /api/exec` | 在单元格执行命令（返回输出） |
| `POST /api/send` | 向单元格发送文本 |
| `POST /api/read` | 读取单元格输出 |
| `POST /api/broadcast` | 广播到所有单元格 |

## 许可

MIT License。基于 [koenma/terminal-grid](https://github.com/koenma-studio/terminal-grid) v0.4.0 修改。
