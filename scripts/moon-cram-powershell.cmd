@echo off
REM Moon Cram emits a Bash-oriented shell protocol even when --shell points to
REM PowerShell. This wrapper starts the adapter that translates that protocol.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0moon-cram-powershell.ps1"
exit /b %ERRORLEVEL%
