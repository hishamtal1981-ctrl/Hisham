#requires -version 5.1
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$form = [Windows.Forms.Form]@{
    Text = 'معالج التحقق من خادم نظام عقود الصيانة'
    Size = [Drawing.Size]::new(720, 590)
    StartPosition = 'CenterScreen'
    RightToLeft = 'Yes'
    RightToLeftLayout = $true
    Font = [Drawing.Font]::new('Segoe UI', 10)
    FormBorderStyle = 'FixedDialog'
    MaximizeBox = $false
}

$title = [Windows.Forms.Label]@{Text='التحقق من اتصال السيرفر';AutoSize=$true;Location=[Drawing.Point]::new(245,20);Font=[Drawing.Font]::new('Segoe UI',16,[Drawing.FontStyle]::Bold)}
$hint = [Windows.Forms.Label]@{Text='هذا الفحص آمن ولا يغيّر ملفات النظام أو قاعدة البيانات.';AutoSize=$true;Location=[Drawing.Point]::new(190,58);ForeColor=[Drawing.Color]::DimGray}
$hostLabel = [Windows.Forms.Label]@{Text='عنوان السيرفر';AutoSize=$true;Location=[Drawing.Point]::new(560,105)}
$hostBox = [Windows.Forms.TextBox]@{Text=$env:COMPUTERNAME;Location=[Drawing.Point]::new(280,102);Size=[Drawing.Size]::new(260,28);RightToLeft='No';TextAlign='Left'}
$webLabel = [Windows.Forms.Label]@{Text='منفذ النظام';AutoSize=$true;Location=[Drawing.Point]::new(560,145)}
$webPort = [Windows.Forms.NumericUpDown]@{Value=8000;Minimum=1;Maximum=65535;Location=[Drawing.Point]::new(420,142);Size=[Drawing.Size]::new(120,28);TextAlign='Left'}
$sqlLabel = [Windows.Forms.Label]@{Text='منفذ SQL';AutoSize=$true;Location=[Drawing.Point]::new(560,185)}
$sqlPort = [Windows.Forms.NumericUpDown]@{Value=1433;Minimum=1;Maximum=65535;Location=[Drawing.Point]::new(420,182);Size=[Drawing.Size]::new(120,28);TextAlign='Left'}
$logBox = [Windows.Forms.TextBox]@{Multiline=$true;ReadOnly=$true;ScrollBars='Vertical';Location=[Drawing.Point]::new(35,235);Size=[Drawing.Size]::new(635,235);RightToLeft='Yes';BackColor=[Drawing.Color]::White}
$testButton = [Windows.Forms.Button]@{Text='بدء التحقق';Location=[Drawing.Point]::new(400,500);Size=[Drawing.Size]::new(125,38);BackColor=[Drawing.Color]::FromArgb(31,157,138);ForeColor=[Drawing.Color]::White;FlatStyle='Flat'}
$openButton = [Windows.Forms.Button]@{Text='فتح النظام';Location=[Drawing.Point]::new(260,500);Size=[Drawing.Size]::new(125,38);Enabled=$false}
$closeButton = [Windows.Forms.Button]@{Text='إغلاق';Location=[Drawing.Point]::new(120,500);Size=[Drawing.Size]::new(125,38)}
$form.Controls.AddRange(@($title,$hint,$hostLabel,$hostBox,$webLabel,$webPort,$sqlLabel,$sqlPort,$logBox,$testButton,$openButton,$closeButton))

function Write-Result([string]$Text,[bool]$Success=$true) {
    $mark = if ($Success) {'[نجاح]'} else {'[تنبيه]'}
    $logBox.AppendText("$mark $Text`r`n")
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
    [Windows.Forms.Application]::DoEvents()
}

function Test-TcpPort([string]$Computer,[int]$Port,[int]$Timeout=2500) {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $async = $client.BeginConnect($Computer,$Port,$null,$null)
        if (-not $async.AsyncWaitHandle.WaitOne($Timeout,$false)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch { return $false } finally { $client.Dispose() }
}

$testButton.Add_Click({
    $hostName = $hostBox.Text.Trim()
    $appPort = [int]$webPort.Value
    $databasePort = [int]$sqlPort.Value
    if (-not $hostName) {
        [Windows.Forms.MessageBox]::Show('أدخل عنوان السيرفر أولاً.','بيانات ناقصة','OK','Warning') | Out-Null
        return
    }
    $testButton.Enabled = $false
    $openButton.Enabled = $false
    $logBox.Clear()
    Write-Result "بدء فحص السيرفر $hostName ..."

    try {
        $resolved = [Net.Dns]::GetHostAddresses($hostName) | Select-Object -First 1
        Write-Result "تم التعرف على العنوان: $resolved"
    } catch {
        Write-Result "تعذر التعرف على عنوان السيرفر: $($_.Exception.Message)" $false
    }

    $pingOk = $false
    try {
        $pingOk = Test-Connection -ComputerName $hostName -Count 1 -Quiet -ErrorAction Stop
    } catch {}
    if ($pingOk) { Write-Result 'السيرفر يستجيب لاختبار الشبكة Ping.' }
    else { Write-Result 'لا توجد استجابة Ping. قد يكون Ping محجوباً بالجدار الناري؛ سيستمر فحص المنافذ.' $false }

    $webTcp = Test-TcpPort $hostName $appPort
    if ($webTcp) { Write-Result "منفذ النظام $appPort مفتوح." }
    else { Write-Result "منفذ النظام $appPort مغلق أو غير قابل للوصول." $false }

    $url = "http://${hostName}:$appPort/"
    $httpOk = $false
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8
        $httpOk = $response.StatusCode -ge 200 -and $response.StatusCode -lt 400
        if ($httpOk) { Write-Result "النظام يعمل ويستجيب عبر $url (HTTP $($response.StatusCode))." }
        else { Write-Result "وصلنا إلى النظام لكنه أعاد HTTP $($response.StatusCode)." $false }
    } catch {
        Write-Result "لم نحصل على استجابة HTTP من $url" $false
    }

    $sqlTcp = Test-TcpPort $hostName $databasePort
    if ($sqlTcp) { Write-Result "منفذ SQL Server $databasePort مفتوح." }
    else { Write-Result "منفذ SQL Server $databasePort مغلق. إذا كانت قاعدة البيانات محلية أو تستخدم منفذاً ديناميكياً فقد يكون ذلك طبيعياً." $false }

    Write-Result 'انتهى الفحص. راجع النتائج أعلاه.' $true
    $openButton.Enabled = $httpOk
    $testButton.Enabled = $true
})

$openButton.Add_Click({
    $url = 'http://{0}:{1}/' -f $hostBox.Text.Trim(),[int]$webPort.Value
    Start-Process $url
})
$closeButton.Add_Click({$form.Close()})
[void]$form.ShowDialog()
