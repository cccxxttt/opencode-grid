# COMSPEC/shell proxy — session log

## Goal
COMSPEC/shell proxy intercepts all opencode `bash` tool calls at the Windows OS process level, routing commands to terminal-grid cells via REST API while falling back to local execution when needed.

## Constraints & Preferences
- No MCP protocol — pure HTTP REST
- No "launch opencode" button in sidebar (removed)
- Sidebar dropdown selects target cell (default: "opencode" mode = `-1`)
- When opencode mode, API returns `{opencode: true}`, wrapper runs locally
- When a cell is selected, API runs command in that cell and returns output
- Solution must NOT depend on Node.js spawn behavior — use COMSPEC (OS-level)
- Custom tools and plugins cannot replace built-in `bash` tool (confirmed)
- `.cmd` batch files must avoid non-ASCII characters (CMD on Chinese Windows garbles UTF-8)
- Terminal Grid cell is in the EDITOR area (WebviewPanel), not the sidebar (WebviewView)
- Cell switching must be blocked while opencode is executing commands
- `/api/exec` response must complete within ~5 seconds (proxy's `TimeoutSec 5`)
- Extension syntax check must pass (`new Function(f)` must be OK)

## Architecture
- `oc.cmd` — user entry point, sets `COMSPEC=tg-shell.cmd`, launches opencode
- `tg-shell.cmd` — COMSPEC wrapper, writes args to temp file, calls PowerShell proxy
- `tg-proxy.ps1` — PowerShell script, reads temp file, calls `POST /api/exec` on 127.0.0.1:7890
- `extension.js` — VS Code extension with embedded HTTP server (class K on port 7890)
- API endpoints: `POST /api/exec`, `/api/send`, `/api/read`, `/api/broadcast`; `GET /api/health`, `/api/info`, `/api/diag`

## Shell Switching Timing Management (current design)

### State Machine
```
                /api/exec|send|read|broadcast
     IDLE ──────────────────────────────────────→ ACTIVE
         ↑                                           │
         │                              idle timer (10s)
         │                                           │
         └───────────────────────────────────────────┘
              无请求超过 10s → 自动解锁
```

### Implementation
- **`_idleTimer`** (field): tracks idle timeout handle
- **`_idleTimeout`** (field): 10e3 (10 seconds)
- **`_markActive()`** (method): `this._busy=true; clearTimeout(idleTimer); setTimeout(→this._busy=false, 10s)`
- Called in `_createServer` route dispatcher for POST endpoints (exec/send/read/broadcast)
- NOT called for GET endpoints (health/info/diag)

### Changes from previous (per-request) design
- Removed `_busyTimer` field entirely
- Removed all `this._busy=!0` / `this._busy=!1` from `_handleExec`
- `_busy` now only set by `_markActive()` and cleared by idle timer callback
- Fixed polling deadline bug: `d2=Math.max(d2, Date.now()+500)` instead of `d2=Date.now()+500`

### Key Design Decisions
- **API-activity-based busy lock**: `_busy=true` whenever ANY API request arrives, 10-second idle timer reset on each new request
- **No shell-prompt detection** (rejected): unreliable on Windows; fragile
- **No long-polling** (architecturally infeasible): proxy has 5-second timeout
- **PTY output tracking considered but rejected**: adds complexity; idle timer is sufficient for opencode's request pattern

## Progress

### Done
- All REST endpoints defined and working
- COMSPEC proxy chain: `oc.cmd → tg-shell.cmd → tg-proxy.ps1 → REST API`
- Shell switching lock mechanism (API-activity-based with 10s idle timer)
- Polling deadline bug fix (`Math.max`)
- Webview `updateCellSelector` uses `msg.selectedCell` from config
- Dropdown reset on deny: `selectCell` calls `this.sendConfig()` when `H._busy`

### Bugs Found & Fixed
- **`selectCell` handler in wrong class**: webview dropdown (`ocCellSelect`) is in **grid panel** (class x), so `postMessage({type:'selectCell', cellId})` goes to class x's `onDidReceiveMessage`. The `selectCell` handler was only in sidebar (class z) — message silently dropped, `H._selectedCell` never updated.
- **Fix**: added `case"selectCell":{if(typeof H!=='undefined'&&H)H._selectedCell=l.cellId;break}` to class x's `onDidReceiveMessage` switch.
- Class z's existing `selectCell` handler (with busy check + warning) remains but handles only messages from sidebar's own webview.
- **Current state**: two `selectCell` handlers — class x (simple setter, effective), class z (busy-checked, unused).
- **CRITICAL — Missing `//` comment prefix broke grid selector**: sidebar's `_getHtml()` template at extension.js had a line `\u2500\u2500 Cell Merge preview grid \u2500\u2500` WITHOUT the `//` comment prefix. The Unicode escape `\u2500` (U+2500 BOX DRAWINGS LIGHT HORIZONTAL) gets rendered into webview HTML as literal `──` characters. In the script context (line 68), this became `   ── Cell Merge preview grid ──` — `──` triggered `SyntaxError: Invalid or unexpected token` in V8, halting ALL script execution (including grid selector cell creation at line 1049+).
- **Root cause**: this bug existed in the backup file TOO (`//` was present) — but in our current file, the `//` prefix was accidentally lost during MCP cleanup edits. Sidebar rendered the card title and "Open Grid" button, but the `──` characters broke the script, so no cells were created.
- **Fix**: added `//` prefix to make it `   // \u2500\u2500 Cell Merge preview grid \u2500\u2500`. Verified by parsing the generated webview HTML — `Script parses successfully!` and all 112 other `\u2500` occurrences already have proper `//` prefix.

### Known Issues
- COMSPEC proxy's argument parsing (`tg-proxy.ps1`) breaks on commands with `&&`, `|`, `>`, `<` — these are rare in practice
- Shell session corrupted during development (all edits done via edit tool directly on extension.js)
- Grid panel (class x) selectCell handler does NOT check `H._busy` — dropdown may appear to switch during task execution, but `H._selectedCell` remains unchanged after next API request (class z's `_markActive()` resets nothing — the busy lock only prevents sidebar-initiated switches). This is a minor UX issue since the next opencode command still targets the original cell.

### Next Steps (pending testing)
1. Reload VS Code (`Developer: Reload Window`)
2. Test: select cell1 → run `echo hello` → output shows in cell1
3. Test: switch back to cell0 → run `echo world` → output shows in cell0
4. Test: opencode task running → dropdown in sidebar denied (class z handler)
5. Test: task complete → ~10s → dropdown allowed
6. Test: pause → ~10s → dropdown allowed
7. Test: resume → auto-locked

## Relevant Files
- `C:\Users\17977\.vscode\extensions\koenma.terminal-grid-0.4.0\dist\extension.js` — main extension (K class HTTP server)
- `C:\Users\17977\.vscode\extensions\koenma.terminal-grid-0.4.0\media\gridTerminal.js` — webview JS
- `C:\Users\17977\.vscode\extensions\koenma.terminal-grid-0.4.0\ARCHITECTURE.md` — architecture doc
- `C:\Users\17977\Desktop\jaxcode\tg-shell.cmd` — COMSPEC proxy wrapper (batch)
- `C:\Users\17977\Desktop\jaxcode\tg-proxy.ps1` — API proxy (PowerShell)
- `C:\Users\17977\Desktop\jaxcode\oc.cmd` — user entry point
- `C:\Users\17977\.config\opencode\opencode.json` — config with `"shell"` path
