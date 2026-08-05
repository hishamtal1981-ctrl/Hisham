#requires -version 5.1
$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path $PSScriptRoot -Parent
$target = 'C:\MaintenanceContract'
Add-Type -AssemblyName System.Windows.Forms

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath)
    )
    exit
}

if (-not (Test-Path -LiteralPath $target)) {
    [Windows.Forms.MessageBox]::Show('C:\MaintenanceContract was not found. Run INSTALL-WIZARD.cmd first.','Maintenance Contract') | Out-Null
    exit 1
}

$logFile = Join-Path $target 'force-update.log'
Start-Transcript -Path $logFile -Append | Out-Null
try {
    Write-Host 'Stopping the old application...'
    Stop-ScheduledTask -TaskName 'Maintenance Contract Server' -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.ExecutablePath -and $_.ExecutablePath.StartsWith((Join-Path $target '.venv'),[StringComparison]::OrdinalIgnoreCase)) -or
            ($_.CommandLine -and $_.CommandLine.IndexOf($target,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $_.CommandLine -match 'uvicorn')
        } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2

    Write-Host 'Replacing the old application and interface files...'
    Copy-Item (Join-Path $sourceRoot 'server.py') (Join-Path $target 'server.py') -Force
    Copy-Item (Join-Path $sourceRoot 'requirements.txt') (Join-Path $target 'requirements.txt') -Force
    Copy-Item (Join-Path $sourceRoot 'database_setup.sql') (Join-Path $target 'database_setup.sql') -Force
    Copy-Item (Join-Path $sourceRoot 'static') $target -Recurse -Force
    Copy-Item (Join-Path $sourceRoot 'installer') $target -Recurse -Force
    Get-ChildItem -LiteralPath $target -Directory -Filter '__pycache__' -Recurse -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    $configPath = Join-Path $target 'install-config.json'
    $config = if (Test-Path -LiteralPath $configPath) { Get-Content -Raw $configPath | ConvertFrom-Json } else { $null }
    $sqlServer = if ($config.sql_server) { [string]$config.sql_server } else { '.\MAINTENANCE' }
    $database = if ($config.database) { [string]$config.database } else { 'Maintenance Contract' }
    $port = if ($config.port) { [int]$config.port } else { 8000 }
    $venvPython = Join-Path $target '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $venvPython)) { throw 'The installed Python environment was not found. Run INSTALL-WIZARD.cmd.' }

    Write-Host 'Updating Python packages and database objects...'
    & $venvPython -m pip install --no-cache-dir -r (Join-Path $target 'requirements.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Python package update failed.' }
    $env:SQLSERVER_HOST = $sqlServer
    $env:SQLSERVER_DATABASE = $database
    & $venvPython (Join-Path $target 'installer\configure_database.py')
    if ($LASTEXITCODE -ne 0) { throw 'Database update failed.' }

    $runner = @"
@echo off
cd /d "$target"
set "SQLSERVER_HOST=$sqlServer"
set "SQLSERVER_DATABASE=$database"
"$venvPython" -m uvicorn server:app --host 0.0.0.0 --port $port >> "$target\server.log" 2>&1
"@
    Set-Content -LiteralPath (Join-Path $target 'run-server.cmd') -Value $runner -Encoding ASCII
    $action = New-ScheduledTaskAction -Execute (Join-Path $target 'run-server.cmd') -WorkingDirectory $target
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName 'Maintenance Contract Server' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName 'Maintenance Contract Server'

    $url = "http://127.0.0.1:$port/?build=512c99a&refresh=$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
    $ready = $false
    foreach ($attempt in 1..90) {
        Start-Sleep -Seconds 1
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 -Headers @{'Cache-Control'='no-cache'}
            if ($response.StatusCode -eq 200 -and $response.Content -match 'login-hero' -and $response.Content -match 'app-sidebar') {
                $ready = $true
                break
            }
        } catch {}
    }
    if (-not $ready) { throw 'The updated interface did not start. Review C:\MaintenanceContract\server.log.' }
    Set-Content -LiteralPath (Join-Path $target 'interface-version.txt') -Value '512c99a - updated interface' -Encoding ASCII
    Start-Process $url
    [Windows.Forms.MessageBox]::Show('The new interface was installed and verified. Build: 512c99a','Maintenance Contract') | Out-Null
} catch {
    Write-Error $_
    [Windows.Forms.MessageBox]::Show("$($_.Exception.Message)`n`nLog: $logFile",'Update failed','OK','Error') | Out-Null
    exit 1
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
