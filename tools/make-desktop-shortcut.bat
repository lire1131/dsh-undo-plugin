@echo off
rem Create a "DSH Undo Manager" shortcut on the desktop (one-click).
rem Run this after installing dsh-undo-savepoint; it locates the plugin
rem directory automatically (own folder, profile tree, or user node_modules).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0make-desktop-shortcut.ps1"
