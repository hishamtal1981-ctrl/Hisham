@echo off
cd /d "%~dp0"
if not exist .venv (
  py -m venv .venv
  .venv\Scripts\python.exe -m pip install -r requirements.txt
)
if "%SQLSERVER_HOST%"=="" (
  sc query "MSSQL$SQLEXPRESS" | find "RUNNING" >nul
  if not errorlevel 1 set "SQLSERVER_HOST=%COMPUTERNAME%\SQLEXPRESS"
)
echo Open: http://localhost:8000
.venv\Scripts\python.exe -m uvicorn server:app --host 0.0.0.0 --port 8000
if errorlevel 1 (
  echo.
  echo SERVER FAILED TO START. Keep this window open and send a screenshot of the error.
  pause
)
