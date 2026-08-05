#requires -version 5.1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$target = 'C:\MaintenanceContract'
$database = 'Maintenance Contract'

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoLogo','-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath))
    exit
}
if (-not (Test-Path -LiteralPath $target)) {
    [Windows.Forms.MessageBox]::Show('C:\MaintenanceContract was not found.','Data recovery','OK','Error') | Out-Null
    exit 1
}

$logFile = Join-Path $target 'data-recovery.log'
Start-Transcript -Path $logFile -Append | Out-Null
try {
    [string[]]$candidates = @()
    if (Get-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue) { $candidates += 'localhost' }
    Get-Service -Name 'MSSQL$*' -ErrorAction SilentlyContinue | ForEach-Object {
        $candidates += [string]('.\' + $_.Name.Substring(6))
    }
    $configPath = Join-Path $target 'install-config.json'
    $config = if (Test-Path -LiteralPath $configPath) { Get-Content -Raw $configPath | ConvertFrom-Json } else { $null }
    $configuredServer = if ($config -and $config.sql_server) { [Convert]::ToString($config.sql_server) } else { '' }
    if ($configuredServer -and $configuredServer -notin $candidates) { $candidates += $configuredServer }

    $found = @()
    foreach ($serverItem in @($candidates | Sort-Object -Unique)) {
        [string]$server = [Convert]::ToString($serverItem)
        Write-Host "Checking $server ..."
        $builder = [Data.SqlClient.SqlConnectionStringBuilder]::new()
        $builder['Data Source'] = $server
        $builder['Initial Catalog'] = $database
        $builder['Integrated Security'] = $true
        $builder['Encrypt'] = $false
        $builder['TrustServerCertificate'] = $true
        $builder['Connect Timeout'] = 6
        $connection = [Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
        try {
            $connection.Open()
            $command = $connection.CreateCommand()
            $command.CommandText = @"
SELECT
  COALESCE(SUM(CASE WHEN t.name=N'contracts' AND p.index_id IN (0,1) THEN p.rows ELSE 0 END),0) AS contracts,
  COALESCE(SUM(CASE WHEN t.name=N'users' AND p.index_id IN (0,1) THEN p.rows ELSE 0 END),0) AS users,
  COUNT(DISTINCT t.object_id) AS tables_count
FROM sys.tables AS t
LEFT JOIN sys.partitions AS p ON p.object_id=t.object_id
"@
            $reader = $command.ExecuteReader()
            if ($reader.Read()) {
                $found += @{
                    Server = [string]$server
                    Contracts = [Convert]::ToInt64($reader.GetValue(0))
                    Users = [Convert]::ToInt64($reader.GetValue(1))
                    Tables = [Convert]::ToInt32($reader.GetValue(2))
                }
            }
            $reader.Close()
        } catch {
            Write-Host "$server unavailable: $($_.Exception.Message)"
        } finally {
            $connection.Dispose()
        }
    }

    if (-not $found) { throw 'No readable [Maintenance Contract] database was found on local SQL Server instances.' }
    [string]$current = if ($configuredServer) { $configuredServer } else { '(not configured)' }
    $best = @($found | Sort-Object @{Expression={[long]$_['Contracts']};Descending=$true},@{Expression={[long]$_['Users']};Descending=$true},@{Expression={[int]$_['Tables']};Descending=$true})[0]
    [string]$bestServer = [Convert]::ToString($best['Server'])
    [long]$bestContracts = [Convert]::ToInt64($best['Contracts'])
    [string]$lines = (@($found | ForEach-Object { "Server: $($_['Server']) | Contracts: $($_['Contracts']) | Users: $($_['Users']) | Tables: $($_['Tables'])" })) -join "`r`n"
    $answer = [Windows.Forms.MessageBox]::Show(
        [string]"Databases found:`r`n`r`n$lines`r`n`r`nCurrent server: $current`r`nSuggested data server: $bestServer`r`n`r`nSwitch the application to this database?",
        [string]'Recover existing Maintenance Contract data',
        [Windows.Forms.MessageBoxButtons]::YesNo,
        [Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -ne 'Yes') {
        Write-Host 'Cancelled without changing the application or database.'
        exit 0
    }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($name in @('install-config.json','run-server.cmd')) {
        $path = Join-Path $target $name
        if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination "$path.before-data-recovery-$stamp" }
    }

    # Permit the persistent Windows SYSTEM task to use the selected database.
    $masterBuilder = [Data.SqlClient.SqlConnectionStringBuilder]::new()
    $masterBuilder.ConnectionString = "Data Source=$bestServer;Initial Catalog=master;Integrated Security=True;Encrypt=False;TrustServerCertificate=True;Connect Timeout=10"
    $master = [Data.SqlClient.SqlConnection]::new($masterBuilder.ConnectionString)
    $master.Open()
    $cmd = $master.CreateCommand()
    $cmd.CommandText = "IF SUSER_ID(N'NT AUTHORITY\SYSTEM') IS NULL CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS"
    [void]$cmd.ExecuteNonQuery()
    $master.Dispose()
    $dbBuilder = [Data.SqlClient.SqlConnectionStringBuilder]::new()
    $dbBuilder.ConnectionString = "Data Source=$bestServer;Initial Catalog=$database;Integrated Security=True;Encrypt=False;TrustServerCertificate=True;Connect Timeout=10"
    $dbConnection = [Data.SqlClient.SqlConnection]::new($dbBuilder.ConnectionString)
    $dbConnection.Open()
    $cmd = $dbConnection.CreateCommand()
    $cmd.CommandText = "IF USER_ID(N'NT AUTHORITY\SYSTEM') IS NULL CREATE USER [NT AUTHORITY\SYSTEM] FOR LOGIN [NT AUTHORITY\SYSTEM]; IF IS_ROLEMEMBER(N'db_owner',N'NT AUTHORITY\SYSTEM') <> 1 ALTER ROLE db_owner ADD MEMBER [NT AUTHORITY\SYSTEM]"
    [void]$cmd.ExecuteNonQuery()
    $dbConnection.Dispose()

    $port = if ($config.port) { [int]$config.port } else { 8000 }
    $venvPython = Join-Path $target '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $venvPython)) { throw 'Installed Python environment was not found.' }
    Stop-ScheduledTask -TaskName 'Maintenance Contract Server' -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandLine -and $_.CommandLine.IndexOf($target,[StringComparison]::OrdinalIgnoreCase) -ge 0 -and $_.CommandLine -match 'uvicorn'
    } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    $runner = @"
@echo off
cd /d "$target"
set "SQLSERVER_HOST=$bestServer"
set "SQLSERVER_DATABASE=$database"
"$venvPython" -m uvicorn server:app --host 0.0.0.0 --port $port >> "$target\server.log" 2>&1
"@
    Set-Content -LiteralPath (Join-Path $target 'run-server.cmd') -Value $runner -Encoding ASCII
    @{sql_server=$bestServer;database=$database;port=$port;recovered_at=(Get-Date).ToString('o')} | ConvertTo-Json |
        Set-Content -LiteralPath $configPath -Encoding UTF8
    $action = New-ScheduledTaskAction -Execute (Join-Path $target 'run-server.cmd') -WorkingDirectory $target
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName 'Maintenance Contract Server' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName 'Maintenance Contract Server'
    Start-Sleep -Seconds 5
    $url = "http://127.0.0.1:$port/?recovered=$stamp"
    Start-Process $url
    [Windows.Forms.MessageBox]::Show("Application connected to $bestServer.`nContracts found: $bestContracts`nNo records were deleted or copied.",'Data recovery completed') | Out-Null
} catch {
    Write-Error $_
    [Windows.Forms.MessageBox]::Show("$($_.Exception.Message)`n`nLog: $logFile",'Data recovery failed','OK','Error') | Out-Null
    exit 1
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
