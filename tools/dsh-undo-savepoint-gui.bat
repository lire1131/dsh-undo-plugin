@echo off
rem Launch the DSH Undo Manager window (no console window).
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0dsh-undo-savepoint-gui.ps1"
