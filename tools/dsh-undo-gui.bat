@echo off
rem Launch the dsh-undo manager window (no console window).
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0dsh-undo-gui.ps1"
