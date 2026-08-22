@echo off
chcp 65001 >nul
rem dsh-undo-savepoint offline WebUI launcher (Windows).
rem Usage: launch-undo.bat [--profile <name>] [--no-open] [--lang en|zh]
setlocal
set "DIR=%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo [undo] Node.js not found. Please install Node.js ^>= 20 and add it to PATH.
  pause
  exit /b 1
)
node "%DIR%undo-server.mjs" %*
endlocal
