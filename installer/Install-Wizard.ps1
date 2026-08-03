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
    $fullMedia = Get-Package @('SQLEXPR_x64_ENU.exe','SQLEXPR_x64_2022.exe')
    if (-not $fullMedia) {
        $bootstrapper = Get-Package @('SQL2022-SSEI-Expr.exe')
        if (-not $bootstrapper) {
            $bootstrapper = Join-Path $env:TEMP 'SQL2022-SSEI-Expr.exe'
            Write-SetupLog 'Downloading the version-specific SQL Server 2022 Express bootstrapper...'
            Invoke-WebRequest 'https://download.microsoft.com/download/5/1/4/5145fe04-4d30-4b85-b0d1-39533663a2f1/SQL2022-SSEI-Expr.exe' -OutFile $bootstrapper -UseBasicParsing
        }
        $mediaPath = Join-Path $env:TEMP ("MaintenanceContract-SQLMedia-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $mediaPath -Force | Out-Null
        Write-SetupLog 'Downloading the complete SQL Server 2022 Express media...'
        $downloadArguments = '/ACTION=Download /MEDIATYPE=Core /MEDIAPATH="{0}" /QUIET' -f $mediaPath
        $download = Start-Process $bootstrapper -ArgumentList $downloadArguments -Wait -PassThru
        if ($download.ExitCode -notin @(0,3010)) { throw "SQL Server media download failed with exit code $($download.ExitCode)." }
        $fullMedia = Get-ChildItem $mediaPath -Recurse -File -Filter 'SQLEXPR*.exe' |
            Where-Object { $_.Name -notlike '*SSEI*' } |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $fullMedia) { throw 'SQL Server downloaded, but SQLEXPR_x64_ENU.exe was not found.' }
    }
    Write-SetupLog "Installing SQL Server Express instance MAINTENANCE from $fullMedia..."
    $arguments = '/Q /ACTION=Install /FEATURES=SQL /INSTANCENAME=MAINTENANCE /SQLSVCSTARTUPTYPE=Automatic /ADDCURRENTUSERASSQLADMIN=True /IACCEPTSQLSERVERLICENSETERMS /TCPENABLED=1 /NPENABLED=0'
    $process = Start-Process $fullMedia -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -notin @(0,3010)) { throw "SQL Server setup failed with exit code $($process.ExitCode)." }
    $sqlService = Get-Service 'MSSQL$MAINTENANCE' -ErrorAction Stop
    if ($sqlService.Status -ne 'Running') { Start-Service $sqlService }
    Write-SetupLog 'Waiting for SQL Server service to become ready...'
    $sqlService.WaitForStatus('Running',[TimeSpan]::FromMinutes(2))
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
    function Resolve-PythonExecutable([string]$Command, [string[]]$Arguments) {
        try {
            $candidate = & $Command @Arguments 2>$null
            if ($LASTEXITCODE -eq 0 -and $candidate) {
                $path = ([string]($candidate | Select-Object -First 1)).Trim()
                if ($path -and (Test-Path -LiteralPath $path)) { return $path }
            }
        } catch { return $null }
        return $null
    }

    $python = $null
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $python = Resolve-PythonExecutable 'py' @('-3.12','-c','import sys; print(sys.executable)')
        if (-not $python) { $python = Resolve-PythonExecutable 'py' @('-3','-c','import sys; print(sys.executable)') }
    }
    if (-not $python -and (Get-Command python -ErrorAction SilentlyContinue)) {
        $python = Resolve-PythonExecutable (Get-Command python).Source @('-c','import sys; print(sys.executable)')
    }
    if ($python) { return $python }
    $installer = Get-Package @('python-3.12-amd64.exe','python-installer.exe')
    if (-not $installer) {
        $installer = Join-Path $env:TEMP 'python-3.12-amd64.exe'
        Write-SetupLog 'Downloading Python 3.12 from python.org...'
        Invoke-WebRequest 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe' -OutFile $installer -UseBasicParsing
    }
    $process = Start-Process $installer -ArgumentList '/quiet InstallAllUsers=1 PrependPath=1 Include_test=0' -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Python setup failed with exit code $($process.ExitCode)." }
    foreach ($candidate in @(
        "$env:ProgramFiles\Python312\python.exe",
        "$env:LocalAppData\Programs\Python\Python312\python.exe",
        "$env:SystemRoot\py.exe"
    )) {
        if (-not (Test-Path -LiteralPath $candidate)) { continue }
        if ($candidate -like '*\py.exe') {
            $python = Resolve-PythonExecutable $candidate @('-3.12','-c','import sys; print(sys.executable)')
        } else {
            $python = Resolve-PythonExecutable $candidate @('-c','import sys; print(sys.executable)')
        }
        if ($python) { return $python }
    }
    throw 'Python was installed but its executable could not be located. Restart Windows and run the wizard again.'
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
        Write-SetupLog "Using Python: $python"
        Write-SetupLog 'Creating or repairing Python environment...'
        $venvPath = Join-Path $target '.venv'
        & $python -m venv --clear $venvPath 2>&1 | ForEach-Object { Write-SetupLog ([string]$_) }
        $venvExit = $LASTEXITCODE
        $venvPython = Join-Path $venvPath 'Scripts\python.exe'
        if ($venvExit -ne 0 -or -not (Test-Path -LiteralPath $venvPython)) {
            throw "Python environment creation failed (exit code $venvExit). Check antivirus permissions for $target."
        }
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
"$venvPython" -m uvicorn server:app --host 0.0.0.0 --port $port >> "$target\server.log" 2>&1
"@
        Set-Content -Path (Join-Path $target 'run-server.cmd') -Value $runner -Encoding ASCII
        $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument ('/c "{0}"' -f (Join-Path $target 'run-server.cmd')) -WorkingDirectory $target
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
        $principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName 'Maintenance Contract Server' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        $firewallRule = Get-NetFirewallRule -DisplayName 'Maintenance Contract Web' -ErrorAction SilentlyContinue
        if (-not $firewallRule) {
            New-NetFirewallRule -DisplayName 'Maintenance Contract Web' -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow | Out-Null
        } else {
            $firewallRule | Set-NetFirewallRule -Enabled True -Action Allow | Out-Null
            $firewallRule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -Protocol TCP -LocalPort $port | Out-Null
        }
        Start-ScheduledTask -TaskName 'Maintenance Contract Server'
        $serverStarted = $false
        $localUrl = "http://127.0.0.1:$port/"
        foreach ($attempt in 1..30) {
            Start-Sleep -Milliseconds 500
            try {
                $response = Invoke-WebRequest -Uri $localUrl -UseBasicParsing -TimeoutSec 5
                if ($response.StatusCode -eq 200) {
                    $serverStarted = $true
                    break
                }
            } catch {
                # The application can take a few seconds to initialize and answer HTTP requests.
            }
        }
        if (-not $serverStarted) {
            $serverLog = Join-Path $target 'server.log'
            $details = if (Test-Path $serverLog) { (Get-Content $serverLog -Tail 12) -join "`n" } else { 'No server log was created.' }
            throw "The web server did not start. Log:`n$details"
        }
        $config = @{sql_server=$sqlServer;database=$database;port=$port;installed_at=(Get-Date).ToString('o')} | ConvertTo-Json
        Set-Content -Path (Join-Path $target 'install-config.json') -Value $config -Encoding UTF8
        $networkAddress = Get-NetIPConfiguration |
            Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address } |
            Select-Object -First 1 -ExpandProperty IPv4Address |
            Select-Object -ExpandProperty IPAddress
        $networkUrl = if ($networkAddress) { "http://${networkAddress}:$port/" } else { "http://$($env:COMPUTERNAME):$port/" }
        $computerUrl = "http://$($env:COMPUTERNAME):$port/"
        Write-SetupLog "Installation completed. Local URL: $localUrl"
        Write-SetupLog "Network IP URL: $networkUrl"
        Write-SetupLog "Computer name URL: $computerUrl"
        Start-Process $localUrl
        [Windows.Forms.MessageBox]::Show("تم التثبيت وفتح البرنامج بنجاح.`nعلى هذا الجهاز: $localUrl`nمن أجهزة الشبكة: $networkUrl`nباسم الجهاز: $computerUrl",'Maintenance Contract') | Out-Null
    } catch {
        Write-SetupLog "ERROR: $($_.Exception.Message)"
        [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Setup failed','OK','Error') | Out-Null
    } finally {
        $installButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
