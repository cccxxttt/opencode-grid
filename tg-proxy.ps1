param()

# tg-proxy.ps1 - read args from temp file -> call REST API -> return result or signal

# Step 1: read raw args from temp file
$rawArgs = Get-Content "$env:TEMP\tg_args.txt" -Raw -ErrorAction SilentlyContinue
if (-not $rawArgs) { exit 1 }

$rawArgs = $rawArgs.Trim()

# Step 2: parse command from args
# Format: "-c" "command"  or  "/d" "/s" "/c" "command"

$cmd = $null
$tokens = @()

$match = [regex]::Matches($rawArgs, '"([^"]*)"')
if ($match.Count -gt 0) {
    $tokens = $match | ForEach-Object { $_.Groups[1].Value }
}

if ($tokens.Count -eq 0) {
    $cmd = $rawArgs
} elseif ($tokens.Count -eq 1) {
    $cmd = $tokens[0]
} else {
    $firstFlag = $tokens[0].ToLower().Trim()
    $startIdx = 1
    if ($firstFlag -eq '/d' -and $tokens.Count -gt 3 -and $tokens[1].ToLower() -eq '/s') {
        $startIdx = 3
    } elseif ($firstFlag -eq '/s' -and $tokens.Count -gt 2 -and $tokens[1].ToLower() -eq '/c') {
        $startIdx = 2
    } elseif ($firstFlag -eq '/c' -or $firstFlag -eq '-c') {
        $startIdx = 1
    }
    if ($startIdx -lt $tokens.Count) {
        $cmd = $tokens[$startIdx..($tokens.Count - 1)] -join ' '
    }
}

# Ensure $cmd is a string (single-char regex may produce [System.Char])
if ($cmd -is [char]) { $cmd = [string]$cmd }
if (-not $cmd -or "$cmd".Trim() -eq '') {
    exit 1
}
$cmd = "$cmd".Trim()

# Step 2.5: discover API port (multi-instance isolation)
# Strategy (in order of robustness):
#   1. Read cache keyed by opencode ancestor pid (fast path)
#   2. Climb process tree from $PID, collect ancestor pids, match vs port files' vscodeWindowPid
#   3. Match by workspace path prefix
#   4. Most recent alive port file (heartbeat within 2 min)
#   5. Fallback to 7890
$apiPort = $null

function Get-ParentPid($procId) {
    try {
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$procId" -ErrorAction SilentlyContinue
        if ($p) { return [int]$p.ParentProcessId }
    } catch {}
    return 0
}

function Get-AncestorSet($startPid, $maxDepth = 20) {
    $set = @{}
    $cur = [int]$startPid
    for ($i = 0; $i -lt $maxDepth; $i++) {
        if (-not $cur -or $cur -le 0 -or $set.ContainsKey($cur)) { break }
        $set[$cur] = $true
        $next = Get-ParentPid $cur
        if ($next -le 0 -or $next -eq $cur) { break }
        $cur = $next
    }
    return $set
}

try {
    $portsDir = Join-Path $PSScriptRoot "data\ports"
    $cwd = (Get-Location).Path

    # --- Cache fast path: keyed by opencode ancestor pid ---
    # Climb 2 levels up: powershell -> tg-shell.cmd (cmd.exe) -> opencode
    $shellParent = Get-ParentPid $PID
    $opencodePid = if ($shellParent -gt 0) { Get-ParentPid $shellParent } else { 0 }
    if ($opencodePid -gt 0) {
        $cacheFile = Join-Path $env:TEMP "tg-port-opencode-$opencodePid.txt"
        try {
            if (Test-Path $cacheFile) {
                $cachedAge = [int]([DateTimeOffset]::Now.ToUnixTimeSeconds() - (Get-Item $cacheFile).LastWriteTime.TotalSeconds)
                # Adjust: LastWriteTime is a DateTime; compute age properly
                $cachedAge = [int]([DateTimeOffset]::Now.UtcDateTime - (Get-Item $cacheFile).LastWriteTime).TotalSeconds
                if ($cachedAge -lt 120) {
                    $cachedPort = [int](Get-Content $cacheFile -Raw -ErrorAction SilentlyContinue)
                    if ($cachedPort -gt 0) {
                        # Verify the cached port still has an alive port file
                        if (Test-Path $portsDir) {
                            $portFiles = Get-ChildItem -Path $portsDir -Filter "win-*.json" -ErrorAction SilentlyContinue
                            foreach ($pf in $portFiles) {
                                try {
                                    $info = Get-Content $pf.FullName -Raw | ConvertFrom-Json
                                    if ($info.port -eq $cachedPort) {
                                        $apiPort = $cachedPort
                                        break
                                    }
                                } catch { continue }
                            }
                        }
                    }
                }
            }
        } catch {}
    }

    # --- Full discovery path ---
    if (-not $apiPort -and (Test-Path $portsDir)) {
        $portFiles = Get-ChildItem -Path $portsDir -Filter "win-*.json" -ErrorAction SilentlyContinue
        if ($portFiles) {
            $ancestors = Get-AncestorSet $PID
            $now = [DateTimeOffset]::Now.UtcDateTime
            $bestMatch = $null
            $bestScore = -1
            $fallbackRecent = $null
            $fallbackRecentTs = 0
            $fallbackWs = $null
            $fallbackWsScore = -1

            foreach ($pf in $portFiles) {
                try {
                    $info = Get-Content $pf.FullName -Raw | ConvertFrom-Json
                    if (-not $info.port) { continue }

                    # Heartbeat liveness check (skip stale files >2min)
                    $ts = [int64]$info.ts
                    $age = [int]([DateTimeOffset]::Now.ToUnixTimeMilliseconds() - $ts)
                    $isAlive = ($age -lt 120000)

                    # Score by process chain match (primary path)
                    $score = 0
                    $chainMatch = $false
                    if ($info.vscodeWindowPid -and $ancestors.ContainsKey([int]$info.vscodeWindowPid)) {
                        $chainMatch = $true
                        $score = 10000
                    }

                    # Boost: workspace path prefix match
                    if ($info.workspace -and $cwd -and $cwd.ToLower().StartsWith($info.workspace.ToLower())) {
                        $wsScore = 1000 + $info.workspace.Length
                        if (-not $chainMatch) { $score = $wsScore }
                        elseif ($fallbackWs -eq $null -or $wsScore -gt $fallbackWsScore) {
                            $fallbackWs = $info; $fallbackWsScore = $wsScore
                        }
                    }

                    # Boost: alive + recent
                    if ($isAlive) { $score += 200 }
                    if ($age -lt 60000) { $score += 100 }

                    if ($score -gt $bestScore) {
                        $bestScore = $score
                        $bestMatch = $info
                    }
                    if ($isAlive -and $ts -gt $fallbackRecentTs) {
                        $fallbackRecent = $info
                        $fallbackRecentTs = $ts
                    }
                } catch { continue }
            }

            if ($bestMatch -and $bestScore -ge 10000) {
                $apiPort = [int]$bestMatch.port
            } elseif ($fallbackWs) {
                $apiPort = [int]$fallbackWs.port
            } elseif ($fallbackRecent) {
                $apiPort = [int]$fallbackRecent.port
            }
        }
    }

    # Write cache for future fast path
    if ($apiPort -and $opencodePid -gt 0) {
        $cacheFile = Join-Path $env:TEMP "tg-port-opencode-$opencodePid.txt"
        try { Set-Content -Path $cacheFile -Value $apiPort -Encoding ascii -ErrorAction SilentlyContinue } catch {}
    }
} catch {}
if (-not $apiPort) { $apiPort = 7890 }

# Step 3: call API
$body = @{ command = $cmd; submit = $true } | ConvertTo-Json -Compress

try {
    $oldComspec = $env:ComSpec
    $env:ComSpec = "C:\Windows\System32\cmd.exe"
    $r = Invoke-RestMethod -Uri "http://127.0.0.1:$apiPort/api/exec" -Method POST -Body $body -ContentType 'application/json' -TimeoutSec 3600 -ErrorAction Stop
    $env:ComSpec = $oldComspec

    if ($r.opencode) {
        # opencode mode -> signal batch to run locally
        exit 2
    }

    if ($r.error) {
        # API returned an error (no grid, invalid cell, etc.) -> fallback to local
        exit 1
    }

    # cell mode -> output to stdout (opencode captures this as tool result)
    if ($r.output) {
        Write-Output $r.output
    }
    exit 0
}
catch {
    # API unreachable or error -> run locally
    exit 1
}