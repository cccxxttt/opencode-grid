# Changelog

## [0.6.0] — 2026

### Added
- **多实例隔离** — 端口文件以 VS Code 窗口 PID 为主键 (`win-<vscodePid>-<wsHash>.json`)，消除同一 workspace 多窗口互相覆盖的问题
- **tg-proxy.ps1 进程链端口发现** — 从 `$PID` 爬父进程链，匹配祖先中的 `vscodeWindowPid`，精准定位当前窗口的 API 服务器，不受端口冲突和文件覆盖影响
- **端口发现缓存** — 以 opencode 祖先 pid 为 key 缓存端口到 `%TEMP%\tg-port-opencode-<pid>.txt`（TTL 120 秒），连续 shell 调用仅首次爬链
- **心跳续期** — 扩展每 30 秒更新端口文件 `ts` 字段，代理端据此跳过过期文件
- **Custom API 可视化管理** — 侧边栏新增 "Custom API" glass-card，可在 UI 中添加/删除 OpenAI 兼容 API provider（名称、Base URL、API Key、自定义模型），写入 `~/.config/opencode/opencode.json` 并自动备份
- **Active model 下拉** — 侧边栏自定义模型下拉，切换后写入 opencode `model` 字段

### Fixed
- **长输出回读**（根因：OUTPUT_BUFFER_SIZE=50000 截断后 `slice(m)` 失效）— `_handleExec` 新增独立 PTY onData 订阅路径，直接捕获输出而不依赖 `_outputBuffers` 全局缓冲区快照，不再受 50000 字符限制
- **`_spawnPty` child_process 路径** — `onData` 包装器改为返回 disposable，支持独立订阅
- **`tg-proxy.ps1` `Invoke-RestMethod` 超时** — `TimeoutSec` 从 5 秒增长到 3600 秒，匹配扩展端 1 小时上限
- **PowerShell `$cmd.Trim()` crash** — `$cmd` 为 `[System.Char]` 时 `.Trim()` 报错，改为 `"$cmd".Trim()`

### Changed
- 端口文件从 `~/.opencode-grid/api-port-<wsHash>.json` 移至 `~/.opencode-grid/ports/win-<vscodePid>-<wsHash>.json`
- `deactivate` 清理逻辑改按 `extHostPid` 匹配删除

## [0.5.0] — 2026

### Added
- **COMSPEC shell proxy** — `tg-shell.cmd` + `tg-proxy.ps1` 将 opencode bash 命令路由到网格单元格
- **嵌入 HTTP API 服务器** — 默认 7890 端口，`/api/exec` 端点用于命令执行
- **Setup OpenCode 按钮** — 侧边栏一键配置 opencode `shell` 路径
- **`_selectedCell` 跟踪** — 侧边栏下拉菜单选择目标单元格，API 自动路由
- **忙锁机制** — 命令执行时拒绝单元格切换，10 秒空闲自动解锁
- **`TG_DIR` 动态路径解析** — 解决通过 PATH 调用时 `%~dp0` 回退到 CWD 的问题

### Changed
- 所有 `terminalGrid` 命名 → `opencodeGrid`
- 所有 `Terminal Grid` 显示文本 → `OpenCode Grid`
- 状态栏文本 `TG :${d}` → `OCG :${d}`
- `H._selectedCell` 默认值 `0` → `-1`（opencode 模式）
- 侧边栏 `_selectedCell` 默认值 `0` → `-1`
- 侧边栏下拉菜单使用全局 cell ID（代替局部索引）

### Fixed
- `selectCell` 处理程序同时位于 GridPanel (class x) 和 Sidebar (class z)
- `sendConfig()` 现在发送 `cellIds` 和 `selectedCell` 到 webview
- 侧边栏 webview `updateCellSelector` 使用 `msg.cellIds[i]` 代替局部索引 `i`

## [0.4.0] - 2026

### Added
- **Multiple Tab Support** (#3) — open many independent grids as separate editor tabs
  - Sidebar **Tabs** card (collapsed by default, above Grid Size) with `+ New`, `⧉ Duplicate`, `× Close`
  - Right-click or double-click a tab for inline rename (no native dialog; focus stays in sidebar)
  - Per-tab isolation of labels, cell overrides, merged regions, startup steps, and custom name
  - **Sparse global cell IDs** — MCP `sendToCell` / `readCell` keep same signature; LLMs that remember a cell ID stay correct as long as the tab is open
  - `getGridInfo` extended with `tabs[]` + `activeTabId`; flat `rows`/`cols`/`cellCount`/`cellLabels` retained for backward compat
  - Multi-tab restore across VS Code restarts via `lastTabs[]` snapshot
  - Active tab indicator on Grid Size card header (`→ Tab 2`)
  - Editor tab title uses 1-based display index matching sidebar
- **VSCodium support** (#4) — linux-x64 `node-pty` prebuild bundled in VSIX so `require("node-pty")` resolves without network install
- **Tab management commands**: `Terminal Grid: New Tab`, `Duplicate Active Tab`, `Close Active Tab`, `Reset All Tabs (clear zombies)`, `Reset Cell IDs`
- **Security section** in README — all 8 language translations (en, ko, ja, zh-CN, de, es, fr, pt-BR)
- Localized help tooltips for Tabs and MCP Registration cards in 7 languages

### Changed
- **MCP hygiene** (#2) — on activation, stale `terminal-grid` entries in Claude Desktop config whose referenced `mcp-server.js` no longer exists are quietly removed
- `Open Grid` now preserves the active tab's identity: tab name, cell overrides, sidebar slot, and (when grid size unchanged) cell IDs all carry over
- `loadPreset` writes to the active tab's namespace and keeps it in the same slot

### Fixed
- Sidebar flicker on Open Grid eliminated via atomic `PanelRegistry.replace` (single `onDidChange` fire)
- Hidden tabs after reload now force-loaded shortly after first deserialize fires (option B self-heal), so the sidebar reflects all open grids almost immediately instead of after a 1.5s wait
- Zombie webview panels (stale VS Code workbench state pointing to removed extension paths) cleaned up via deserialize fallback removal + activation-time self-heal
- `dispose()` is idempotent and only clears `lastGrid`/`lastTabs` when the last panel closes
- Rename UI moved from `vscode.window.showInputBox` to in-card inline `<input>` — focus no longer jumps to the editor's top bar

### Security
- README Security section documents: `127.0.0.1`-only listener, configurable port (`terminalGrid.apiPort`, default `7890`), config file paths written, and recommended uninstall procedure (`Unregister MCP from Claude Desktop` before removal; stale entries auto-cleanup on next load)
- MCP registration remains explicit opt-in via the sidebar — no auto-registration on install (#2)

## [0.3.7] - 2026

### Added
- Copy (Plain) context menu — strips terminal wrapping artifacts
- Codex CLI auto-registration (`~/.codex/config.toml`)
- Auto-patch stale `.mcp.json` in workspace folders on activation
- "Why Terminal Grid?" section and AI-focused tagline in README

### Fixed
- Copy (Plain) clipboard write via `vscode.env.clipboard` (webview sandbox workaround)
- `getSelectionPosition()` property mismatch (`x`/`y` vs `row`/`col`)
- Selection lost on context menu click — now cached at right-click time

## [0.3.6] - 2026

### Added
- MCP auto-registration for Claude Code (`~/.claude.json`) and Claude Desktop
- VS Code Copilot MCP registration (`vscode.lm.registerMcpServerDefinitionProvider`)
- LLM TUI detection — auto-sends CSI u key sequences for Enter/Tab/arrows
- ANSI strip for `read_cell` output
- Chunked PTY writes to prevent input drops
- Project Folders sidebar — click to switch, Ctrl+click to open in new window

### Changed
- README restructured: MCP-first layout with demo GIF
- Removed manual MCP config instructions (auto-registers now)
- Removed node-pty requirement section (bundled)

## [0.3.5] - 2026

### Added
- Startup commands UI with sequential steps (command, wait, key)
- Per-cell startup step overrides
- Shell type selection (system default, bash, PowerShell, cmd, zsh)
- Default command per preset
- Key passthrough for special keys in terminal
- Build automation — VSIX auto-package and install on compile

## [0.3.4] - 2026

### Added
- 8 built-in color themes
- Broadcast CSI u support for LLM apps
- Grid resize (change rows/cols without reopening)
- Search improvements in sidebar

## [0.3.2] - 2026

### Fixed
- Marketplace image URLs (use raw GitHub links)
- Exclude GIF from VSIX package

## [0.3.1] - 2026

### Added
- MCP server integration — built-in HTTP bridge for LLM orchestration
- `Terminal Grid: Copy MCP Config` command
- `broadcast` MCP tool for sending to all cells
- Health check auto-shutdown for MCP server process
- Remote-SSH compatibility (`extensionKind: ["workspace"]`)
- `terminalGrid.apiPort` setting

### Fixed
- MCP server zombie process prevention (stdin close + health check)

## [0.3.0] - 2026

### Added
- Per-cell terminal customization (background, foreground, font)
- Settings tabs UI — [All] [1] [2] [3]... for global/per-cell control
- Collapsible sidebar sections with persisted state
- Selective broadcast — choose which cells receive broadcast input
- Agent API: `sendToCell`, `readCell`, `getGridInfo` commands
- `getCellLabels` in grid info response
- Built-in API test command (`Terminal Grid: Test API`)

### Fixed
- Override indicator (yellow border) clearing on global reset
- Settings tabs not appearing after grid open
- Preset load timing — config sent after grid creation
- `readCell(id, 0)` now returns empty string instead of full buffer
- node-pty install banner stuck on "Installing..."
- Dynamic spacing between collapsed/expanded sections

## [0.2.0] - 2026

### Added
- Sidebar control panel with glass-morphism UI
- Preset system — save/load/delete grid configurations
- Per-project preset auto-load
- Startup commands with per-cell assignment
- Cell labels and renaming
- Broadcast input to all terminals
- Custom font file loading (.ttf, .otf, .woff, .woff2)
- Terminal zoom control (50–300%)
- Color customization (background, foreground)
- Context menu (paste, clear, restart, kill, rename)
- Grid panel serialization (restore on VS Code restart)
- node-pty installation flow with sidebar banner

## [0.1.0] - 2026

### Added
- Initial release
- Grid terminal layout in editor tab
- Configurable rows and columns
- xterm.js terminal emulation
- node-pty pseudo-terminal backend
- Fallback to child_process when node-pty unavailable
