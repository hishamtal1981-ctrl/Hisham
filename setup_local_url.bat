@echo off
setlocal
set "HOSTS=%SystemRoot%\System32\drivers\etc\hosts"
findstr /I /C:"maintenance-contract.local" "%HOSTS%" >nul
if errorlevel 1 (
  echo.>>"%HOSTS%"
  echo 127.0.0.1 maintenance-contract.local>>"%HOSTS%"
)
ipconfig /flushdns >nul
echo Local address configured: http://maintenance-contract.local:8000
pause
