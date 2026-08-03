# Offline packages

Place optional offline installers here before packaging:

- `SQL2022-SSEI-Expr.exe` — official SQL Server 2022 Express installer.
- `python-3.12-amd64.exe` — official Python 3.12 x64 installer.
- `msodbcsql18.msi` — optional ODBC Driver 18 installer when SQL setup does not provide a supported driver.
- `wheels/` — Python wheel files for every package in `requirements.txt` and its dependencies.

When files are absent, the wizard downloads the SQL Express and Python installers. The wizard never downloads from non-official domains.
