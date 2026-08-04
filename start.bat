@echo off
setlocal
cd /d "%~dp0"
if "%SQLSERVER_HOST%"=="" (
  set "SQLSERVER_HOST=localhost"
)
if "%SQLSERVER_DATABASE%"=="" set "SQLSERVER_DATABASE=Maintenance Contract"
if not exist ".venv\Scripts\python.exe" (
  echo Preparing Python environment for first use...
  py -3 -m venv .venv 2>nul
  if errorlevel 1 python -m venv .venv
  if errorlevel 1 (
    echo Python 3 was not found. Install Python and enable Add Python to PATH.
    pause
    exit /b 1
  )
  .venv\Scripts\python.exe -m pip install --upgrade pip
  .venv\Scripts\python.exe -m pip install -r requirements.txt
  if errorlevel 1 (
    echo Could not install the required Python packages.
    pause
    exit /b 1
  )
)
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
