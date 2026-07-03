@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0LocalLlamaGUI.ps1"
set "exitcode=%ERRORLEVEL%"
if not "%exitcode%"=="0" (
  echo llamacppWindowAutoRun GUI exited with code %exitcode%.
  echo See "%~dp0logs\latest-gui.log"
  pause
)
exit /b %exitcode%
