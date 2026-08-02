@echo off
setlocal
set "SQLCMD=C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\SQLCMD.EXE"
set "SCRIPT=%~dp0database_setup.sql"
echo Creating tables in [Maintenance Contract] on AMMHLITM01...
"%SQLCMD%" -S AMMHLITM01 -E -d "Maintenance Contract" -b -i "%SCRIPT%"
if errorlevel 1 (
  echo DATABASE SETUP FAILED. Please copy the error shown above.
  pause
  exit /b 1
)
echo Database setup completed. Tables:
"%SQLCMD%" -S AMMHLITM01 -E -d "Maintenance Contract" -Q "SET NOCOUNT ON; SELECT name FROM sys.tables ORDER BY name;"
pause
