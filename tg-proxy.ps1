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

# split by quotes: "arg1" "arg2" -> arg1, arg2
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

if (-not $cmd -or $cmd.Trim() -eq '') {
    exit 1
}

$cmd = $cmd.Trim()

# Step 3: call API
$body = @{ command = $cmd; submit = $true } | ConvertTo-Json -Compress

try {
    $oldComspec = $env:ComSpec
    $env:ComSpec = "C:\Windows\System32\cmd.exe"
    $r = Invoke-RestMethod -Uri 'http://127.0.0.1:7890/api/exec' -Method POST -Body $body -ContentType 'application/json' -TimeoutSec 3600 -ErrorAction Stop
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
