@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0installer\Recover-Existing-Data.ps1"
if errorlevel 1 (
  echo.
  echo Recovery was not completed. Review C:\MaintenanceContract\data-recovery.log.
  pause
)
