@echo off
:: ============================================================
:: oc.cmd - opencode launcher with COMSPEC proxy
:: Sets COMSPEC=tg-shell.cmd and launches opencode
:: All shell calls from opencode are intercepted and routed
:: to selected Terminal Grid cell via REST API
:: ============================================================
set COMSPEC=%~dp0tg-shell.cmd
opencode %*
