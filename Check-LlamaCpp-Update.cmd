@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-LlamaCpp.ps1" -CheckOnly
