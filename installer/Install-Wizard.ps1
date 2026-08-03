#requires -version 5.1
param([switch]$Elevated)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path $PSScriptRoot -Parent

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath), '-Elevated'
    )
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$form = [Windows.Forms.Form]@{
    Text = 'Maintenance Contract - Setup Wizard'
    Size = [Drawing.Size]::new(720, 610)
    StartPosition = 'CenterScreen'
    RightToLeft = 'Yes'
    RightToLeftLayout = $true
    Font = [Drawing.Font]::new('Segoe UI', 10)
}

$title = [Windows.Forms.Label]@{Text='معالج تثبيت نظام عقود الصيانة';AutoSize=$true;Location=[Drawing.Point]::new(230,20);Font=[Drawing.Font]::new('Segoe UI',16,[Drawing.FontStyle]::Bold)}
$pathLabel = [Windows.Forms.Label]@{Text='مجلد التثبيت';AutoSize=$true;Location=[Drawing.Point]::new(590,75)}
$pathBox = [Windows.Forms.TextBox]@{Text='C:\MaintenanceContract';Location=[Drawing.Point]::new(100,72);Size=[Drawing.Size]::new(470,28);RightToLeft='No'}
$serverLabel = [Windows.Forms.Label]@{Text='خادم SQL';AutoSize=$true;Location=[Drawing.Point]::new(590,115)}
$serverBox = [Windows.Forms.TextBox]@{Location=[Drawing.Point]::new(100,112);Size=[Drawing.Size]::new(470,28);RightToLeft='No'}
$databaseLabel = [Windows.Forms.Label]@{Text='قاعدة البيانات';AutoSize=$true;Location=[Drawing.Point]::new(590,155)}
$databaseBox = [Windows.Forms.TextBox]@{Text='Maintenance Contract';Location=[Drawing.Point]::new(100,152);Size=[Drawing.Size]::new(470,28);RightToLeft='No'}
$portLabel = [Windows.Forms.Label]@{Text='منفذ البرنامج';AutoSize=$true;Location=[Drawing.Point]::new(590,195)}
$portBox = [Windows.Forms.NumericUpDown]@{Value=8000;Minimum=1024;Maximum=65535;Location=[Drawing.Point]::new(450,192);Size=[Drawing.Size]::new(120,28)}
$installSql = [Windows.Forms.CheckBox]@{Text='تثبيت SQL Server Express تلقائيًا إذا لم يوجد';Checked=$true;AutoSize=$true;Location=[Drawing.Point]::new(345,235)}
$license = [Windows.Forms.CheckBox]@{Text='أوافق على شروط ترخيص Microsoft SQL Server وODBC عند التثبيت التلقائي';Checked=$false;AutoSize=$true;Location=[Drawing.Point]::new(170,270)}
$logBox = [Windows.Forms.TextBox]@{Multiline=$true;ReadOnly=$true;ScrollBars='Vertical';Location=[Drawing.Point]::new(35,315);Size=[Drawing.Size]::new(635,180);RightToLeft='No'}
$installButton = [Windows.Forms.Button]@{Text='تثبيت';Location=[Drawing.Point]::new(475,520);Size=[Drawing.Size]::new(120,36)}
$cancelButton = [Windows.Forms.Button]@{Text='إغلاق';Location=[Drawing.Point]::new(335,520);Size=[Drawing.Size]::new(120,36)}

$form.Controls.AddRange(@($title,$pathLabel,$pathBox,$serverLabel,$serverBox,$databaseLabel,$databaseBox,$portLabel,$portBox,$installSql,$license,$logBox,$installButton,$cancelButton))
$cancelButton.Add_Click({$form.Close()})

function Write-SetupLog([string]$Message) {
    $logBox.AppendText("$Message`r`n")
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
    [Windows.Forms.Application]::DoEvents()
}

function Find-SqlServer {
    if (Get-Service -Name 'MSSQLSERVER' -ErrorAction SilentlyContinue) { return 'localhost' }
    $named = Get-Service -Name 'MSSQL$*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($named) { return ".\$($named.Name.Substring(6))" }
    return $null
}

function Get-Package([string[]]$Names) {
    foreach ($name in $Names) {
        $candidate = Join-Path $PSScriptRoot "packages\$name"
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Install-SqlExpress {
    $installer = Get-Package @('SQL2022-SSEI-Expr.exe','SQL2022-Express.exe')
    if (-not $installer) {
        $installer = Join-Path $env:TEMP 'SQL2022-SSEI-Expr.exe'
        Write-SetupLog 'Downloading SQL Server 2022 Express from Microsoft...'
        Invoke-WebRequest 'https://go.microsoft.com/fwlink/?linkid=2216019' -OutFile $installer -UseBasicParsing
    }
    Write-SetupLog 'Installing SQL Server Express instance MAINTENANCE...'
    $arguments = '/ACTION=Install /FEATURES=SQLENGINE /INSTANCENAME=MAINTENANCE /SQLSVCSTARTUPTYPE=Automatic /ADDCURRENTUSERASSQLADMIN=True /IACCEPTSQLSERVERLICENSETERMS /Q'
    $process = Start-Process $installer -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0,3010)) { throw "SQL Server setup failed with exit code $($process.ExitCode)." }
    Start-Service 'MSSQL$MAINTENANCE' -ErrorAction SilentlyContinue
    return '.\MAINTENANCE'
}

function Ensure-OdbcDriver {
    $driverKeys = @(
        'HKLM:\SOFTWARE\ODBC\ODBCINST.INI\ODBC Driver 18 for SQL Server',
        'HKLM:\SOFTWARE\ODBC\ODBCINST.INI\ODBC Driver 17 for SQL Server'
    )
    if ($driverKeys | Where-Object { Test-Path $_ }) { return }
    $installer = Get-Package @('msodbcsql18.msi','msodbcsql.msi')
    if (-not $installer) {
        $installer = Join-Path $env:TEMP 'msodbcsql18.msi'
        Write-SetupLog 'Downloading Microsoft ODBC Driver 18...'
        Invoke-WebRequest 'https://go.microsoft.com/fwlink/?linkid=2358430' -OutFile $installer -UseBasicParsing
    }
    Write-SetupLog 'Installing Microsoft ODBC Driver 18...'
    $process = Start-Process msiexec.exe -ArgumentList @('/i',('"{0}"' -f $installer),'/qn','IACCEPTMSODBCSQLLICENSETERMS=YES','ADDLOCAL=ALL') -Wait -PassThru
    if ($process.ExitCode -notin @(0,3010)) { throw "ODBC Driver setup failed with exit code $($process.ExitCode)." }
}

function Ensure-Python {
    $python = $null
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $candidate = & py -3.12 -c 'import sys; print(sys.executable)' 2>$null
        if ($LASTEXITCODE -eq 0) { $python = $candidate }
    }
    if (-not $python -and (Get-Command python -ErrorAction SilentlyContinue)) { $python = (Get-Command python).Source }
    if ($python) { return $python }
    $installer = Get-Package @('python-3.12-amd64.exe','python-installer.exe')
    if (-not $installer) {
        $installer = Join-Path $env:TEMP 'python-3.12-amd64.exe'
        Write-SetupLog 'Downloading Python 3.12 from python.org...'
        Invoke-WebRequest 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe' -OutFile $installer -UseBasicParsing
    }
    $process = Start-Process $installer -ArgumentList '/quiet InstallAllUsers=1 PrependPath=1 Include_test=0' -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Python setup failed with exit code $($process.ExitCode)." }
    $candidate = & "$env:SystemRoot\py.exe" -3.12 -c 'import sys; print(sys.executable)'
    return $candidate
}

$detected = Find-SqlServer
if ($detected) { $serverBox.Text = $detected } else { $serverBox.Text = '.\MAINTENANCE' }

$installButton.Add_Click({
    try {
        if ($installSql.Checked -and -not $license.Checked) { throw 'يجب الموافقة على شروط Microsoft قبل التثبيت التلقائي.' }
        $installButton.Enabled = $false
        $target = $pathBox.Text.Trim()
        $database = $databaseBox.Text.Trim()
        $port = [int]$portBox.Value
        if (-not $target -or -not $database) { throw 'مجلد التثبيت واسم قاعدة البيانات مطلوبان.' }
        $sqlServer = Find-SqlServer
        if (-not $sqlServer) {
            if (-not $installSql.Checked) { $sqlServer = $serverBox.Text.Trim() }
            else { $sqlServer = Install-SqlExpress }
        } elseif ($serverBox.Text.Trim()) { $sqlServer = $serverBox.Text.Trim() }
        Write-SetupLog "Using SQL Server: $sqlServer"
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Write-SetupLog "Copying application to $target..."
        foreach ($item in @('server.py','requirements.txt','database_setup.sql','static','installer')) {
            Copy-Item (Join-Path $sourceRoot $item) $target -Recurse -Force
        }
        Ensure-OdbcDriver
        $python = Ensure-Python
        Write-SetupLog 'Creating Python environment...'
        & $python -m venv (Join-Path $target '.venv')
        $venvPython = Join-Path $target '.venv\Scripts\python.exe'
        $wheelhouse = Join-Path $PSScriptRoot 'packages\wheels'
        if (Test-Path $wheelhouse) {
            & $venvPython -m pip install --no-index --find-links $wheelhouse -r (Join-Path $target 'requirements.txt')
        } else {
            & $venvPython -m pip install -r (Join-Path $target 'requirements.txt')
        }
        if ($LASTEXITCODE -ne 0) { throw 'Python package installation failed.' }
        $env:SQLSERVER_HOST = $sqlServer
        $env:SQLSERVER_DATABASE = $database
        Write-SetupLog 'Creating database and application tables...'
        & $venvPython (Join-Path $target 'installer\configure_database.py')
        if ($LASTEXITCODE -ne 0) { throw 'Database configuration failed.' }
        $runner = @"
@echo off
cd /d "$target"
set "SQLSERVER_HOST=$sqlServer"
set "SQLSERVER_DATABASE=$database"
"$venvPython" -m uvicorn server:app --host 0.0.0.0 --port $port
"@
        Set-Content -Path (Join-Path $target 'run-server.cmd') -Value $runner -Encoding ASCII
        $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c "{0}"' -f (Join-Path $target 'run-server.cmd')) -WorkingDirectory $target
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName 'Maintenance Contract Server' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        if (-not (Get-NetFirewallRule -DisplayName 'Maintenance Contract Web' -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName 'Maintenance Contract Web' -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
        }
        Start-ScheduledTask -TaskName 'Maintenance Contract Server'
        $config = @{sql_server=$sqlServer;database=$database;port=$port;installed_at=(Get-Date).ToString('o')} | ConvertTo-Json
        Set-Content -Path (Join-Path $target 'install-config.json') -Value $config -Encoding UTF8
        Write-SetupLog "Installation completed. Open http://$($env:COMPUTERNAME):$port"
        [Windows.Forms.MessageBox]::Show("تم التثبيت بنجاح.`nhttp://$($env:COMPUTERNAME):$port",'Maintenance Contract') | Out-Null
    } catch {
        Write-SetupLog "ERROR: $($_.Exception.Message)"
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Setup failed','OK','Error') | Out-Null
    } finally {
        $installButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
