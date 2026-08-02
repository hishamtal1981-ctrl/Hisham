# Maintenance Contracts System

نسخة مستقلة من نظام إدارة عقود الصيانة، تعمل محليًا بقاعدة SQLite ولا تعتمد على CodeWords.

## التشغيل

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn server:app --reload
```

افتح `http://127.0.0.1:8000`.

- المستخدم الابتدائي: `admin`
- كلمة المرور الابتدائية: `Admin@123`

غيّر كلمة المرور قبل الاستخدام الفعلي. قاعدة البيانات محفوظة في `maintenance.db` وتُنشأ تلقائيًا.
