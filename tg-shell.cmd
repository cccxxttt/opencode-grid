@echo off
setlocal enabledelayedexpansion

:: tg-shell.cmd - intercept shell calls -> try API -> fallback to real cmd.exe

:: Step 0: determine our own directory (%~dp0 fails when invoked via PATH)
set "TG_DIR=%~dp0"
if not exist "%TG_DIR%tg-proxy.ps1" (
  for %%I in (tg-shell.cmd) do if not "%%~$PATH:I"=="" set "TG_DIR=%%~dp$PATH:I"
)
:: last resort fallback: ~dp0 resolved wrong and PATH lookup failed
if not exist "%TG_DIR%tg-proxy.ps1" set "TG_DIR=%CD%\"

:: Step 1: re-quote each arg to avoid parsing issues with & | > <
set "ARGS="
set "CMD="
set "ARGNUM=0"

:argloop
if "%~1"=="" goto :argdone
set /a ARGNUM+=1

if defined ARGS (set "ARGS=!ARGS! "%~1"") else (set "ARGS="%~1"")

:: first arg is flag (-c /c), rest is the command
if !ARGNUM! geq 2 (
  if defined CMD (set "CMD=!CMD! "%~1"") else (set "CMD="%~1"")
)

shift
goto :argloop
:argdone

:: Step 2: write args to temp file for PowerShell to read
> "%TEMP%\tg_args.txt" echo(!ARGS!

:: Step 3: call PowerShell API proxy (save/restore COMSPEC to avoid recursion)
set "SAVED_COMSPEC=%COMSPEC%"
set "COMSPEC=%SystemRoot%\System32\cmd.exe"
powershell -NoProfile -ExecutionPolicy Bypass -File "%TG_DIR%tg-proxy.ps1"
set "PS_EXIT=!ERRORLEVEL!"
set "COMSPEC=%SAVED_COMSPEC%"

:: Step 4: handle result
:: exit 0 = API handled (output via PS stdout)
if !PS_EXIT! equ 0 exit /b 0

:: exit 2 = run locally (opencode mode or API said so)
if !PS_EXIT! equ 2 goto :runlocal

:: exit 1 = API error, fallback to local

:runlocal
if defined CMD (
  %SystemRoot%\System32\cmd.exe /d /s /c !CMD!
  exit /b !ERRORLEVEL!
)

:: no command parsed, pass raw args
%SystemRoot%\System32\cmd.exe %*
exit /b !ERRORLEVEL!
