@echo off
cd /d "%~dp0"
if "%SQLSERVER_HOST%"=="" (
  set "SQLSERVER_HOST=.\SQLEXPRESS"
)
set "SQLSERVER_DATABASE=Maintenance Contract"
echo Open: http://localhost:8000
echo Starting server... Please keep this window open.
.venv\Scripts\python.exe -m uvicorn server:app --host 0.0.0.0 --port 8000 2>server-error.log
if errorlevel 1 (
  echo.
  echo SERVER FAILED TO START.
  echo Error details:
  type server-error.log
  echo.
  echo Send a screenshot of this window or the server-error.log file.
  pause
)
