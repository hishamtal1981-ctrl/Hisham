# تثبيت البرنامج على كمبيوتر المنزل

## البرامج المطلوبة

1. Python 3.12 أو أحدث، مع تفعيل خيار Add Python to PATH أثناء التثبيت.
2. Microsoft SQL Server 2022 Express أو Developer.
3. SQL Server Management Studio 22.
4. Microsoft ODBC Driver 17 أو 18 for SQL Server.

## إعداد قاعدة البيانات

1. افتح SSMS واتصل بخادم SQL Server الموجود على كمبيوتر المنزل.
2. انقر مرتين على `setup_database.bat`؛ سيُنشئ قاعدة البيانات والجداول تلقائيًا.
3. إذا لم يكن `sqlcmd` مثبتًا، افتح الملف `database_setup.sql` داخل SSMS واضغط Execute أو F5.
4. حدّث مجلد Tables؛ يجب أن تظهر الجداول: `contracts`, `groups_tbl`, `properties`, `users`.

## تشغيل البرنامج

1. فك ضغط الحزمة في مجلد ثابت، مثل `C:\MaintenanceContract`.
2. انقر مرتين على `start.bat` واترك النافذة مفتوحة. في أول تشغيل سيُنشئ بيئة Python ويثبت المتطلبات تلقائيًا.
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
