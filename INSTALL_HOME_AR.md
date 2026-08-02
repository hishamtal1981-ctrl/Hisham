# تثبيت البرنامج على كمبيوتر المنزل

## البرامج المطلوبة

1. Python 3.12 أو أحدث، مع تفعيل خيار Add Python to PATH أثناء التثبيت.
2. Microsoft SQL Server 2022 Express أو Developer.
3. SQL Server Management Studio 22.
4. Microsoft ODBC Driver 17 أو 18 for SQL Server.

## إعداد قاعدة البيانات

1. افتح SSMS واتصل بخادم SQL Server الموجود على كمبيوتر المنزل.
2. أنشئ قاعدة بيانات جديدة باسم `Maintenance Contract`.
3. افتح الملف `database_setup.sql` داخل SSMS.
4. تأكد أن قاعدة البيانات المحددة هي `Maintenance Contract` ثم اضغط Execute أو F5.
5. حدّث مجلد Tables؛ يجب أن تظهر الجداول: `contracts`, `groups_tbl`, `properties`, `users`.

## تشغيل البرنامج

1. فك ضغط الحزمة في مجلد ثابت، مثل `C:\MaintenanceContract`.
2. انقر مرتين على `start.bat` واترك النافذة مفتوحة.
3. افتح `http://localhost:8000`.

بيانات الدخول الابتدائية:

- Username: `admin`
- Password: `Admin@123`

## إذا كان اسم SQL Server مختلفًا

افتح PowerShell داخل مجلد البرنامج ونفذ:

```powershell
$env:SQLSERVER_HOST = "اسم-السيرفر\اسم-instance"
.\start.bat
```

يمكن معرفة الاسم من أعلى Object Explorer في SSMS. لا تنقل ملف `maintenance.db` القديم؛ النسخة الجديدة تستخدم SQL Server.
