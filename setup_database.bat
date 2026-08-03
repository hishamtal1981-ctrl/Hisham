@echo off
setlocal
if "%SQLSERVER_HOST%"=="" set "SQLSERVER_HOST=.\SQLEXPRESS"
set "SCRIPT=%~dp0database_setup.sql"
where sqlcmd >nul 2>nul
if errorlevel 1 (
  echo sqlcmd was not found. Install SQL Server command-line utilities or run database_setup.sql in SSMS.
  pause
  exit /b 1
)
echo Creating [Maintenance Contract] and its tables on %SQLSERVER_HOST%...
sqlcmd -S "%SQLSERVER_HOST%" -E -b -i "%SCRIPT%"
if errorlevel 1 (
  echo DATABASE SETUP FAILED. Please copy the error shown above.
  pause
  exit /b 1
)
echo Database setup completed. Tables:
sqlcmd -S "%SQLSERVER_HOST%" -E -d "Maintenance Contract" -Q "SET NOCOUNT ON; SELECT name FROM sys.tables ORDER BY name;"
pause
