@echo off
:: ============================================================
:: oc.cmd — opencode 启动器（COMSPEC 传统方式）
:: 设置 COMSPEC=tg-shell.cmd 并启动 opencode
:: 所有来自 opencode 的 shell 调用被拦截并路由到
:: OpenCode Grid 单元格（通过 REST API）
::
:: 注意：当前架构优先使用 opencode.json 的 shell 配置，
:: 此文件仅供兼容保留。
:: ============================================================
set COMSPEC=%~dp0tg-shell.cmd
opencode %*
