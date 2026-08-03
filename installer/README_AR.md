# معالج تثبيت نظام عقود الصيانة

شغّل `INSTALL-WIZARD.cmd` كمسؤول. يقوم المعالج بما يلي:

1. يكتشف SQL Server الافتراضي أو أي Instance مثبتة.
2. يثبت SQL Server 2022 Express باسم `MAINTENANCE` إذا لم يجد خادمًا.
3. يثبت Python 3.12 عند الحاجة.
4. ينشئ قاعدة `[Maintenance Contract]` والجداول والمستخدم الابتدائي.
5. يسجل مهمة Windows باسم `Maintenance Contract Server` لتشغيل النظام عند بدء الخادم.
6. يفتح منفذ البرنامج في Windows Firewall.

## التثبيت دون إنترنت

ضع مثبتات Microsoft وPython الرسمية داخل `installer\packages`، وضع حزم Python داخل `installer\packages\wheels`. راجع ملف `packages\README.md` للأسماء المطلوبة.

SQL Server Express مجاني ومتاح لإعادة التوزيع، لكن يجب على المستخدم الموافقة على شروط Microsoft داخل المعالج. لا تُرفع ملفات التثبيت الكبيرة إلى GitHub؛ يمكن إضافتها إلى نسخة Offline خارج المستودع.
