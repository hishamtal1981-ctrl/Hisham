# Maintenance Contracts System

نسخة مستقلة من نظام إدارة عقود الصيانة، تعمل مع Microsoft SQL Server ولا تعتمد على CodeWords.

## التشغيل

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn server:app --reload
```

افتح `http://127.0.0.1:8000`.

للتثبيت السريع على Windows، شغّل `setup_database.bat` مرة واحدة ثم `start.bat`. ينشئ ملف التشغيل بيئة Python ويثبت المتطلبات تلقائيًا في أول مرة.

للتثبيت على خادم Windows جديد، شغّل `INSTALL-WIZARD.cmd`. يكتشف المعالج SQL Server أو يثبت SQL Server 2022 Express، وينشئ قاعدة البيانات، ويسجل تشغيل البرنامج تلقائيًا عند بدء الخادم. يدعم التثبيت دون إنترنت عند إضافة المثبتات الرسمية إلى `installer\packages`.

- المستخدم الابتدائي: `admin`
- كلمة المرور الابتدائية: `Admin@123`

غيّر كلمة المرور قبل الاستخدام الفعلي. يستخدم البرنامج Windows Authentication. عند التشغيل اليدوي يتصل افتراضيًا بالخادم `localhost`، بينما يستخدم `start.bat` الخادم `.\SQLEXPRESS` المناسب عادةً لـ SQL Server Express. قاعدة البيانات الافتراضية هي `[Maintenance Contract]`، ويمكن تغيير الإعدادات من متغيري البيئة `SQLSERVER_HOST` و`SQLSERVER_DATABASE`.
