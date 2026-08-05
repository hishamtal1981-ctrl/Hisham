@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0installer\Force-Update-Interface.ps1"
if errorlevel 1 (
  echo.
  echo The interface update failed. Send C:\MaintenanceContract\force-update.log.
  pause
)
