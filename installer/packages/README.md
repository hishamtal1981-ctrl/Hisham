# Offline packages

Place optional offline installers here before packaging:

- `SQLEXPR_x64_ENU.exe` — preferred full SQL Server 2022 Express media for a completely offline installation.
- `SQL2022-SSEI-Expr.exe` — optional bootstrapper; it still needs internet access to download the full media.
- `python-3.12-amd64.exe` — official Python 3.12 x64 installer.
- `msodbcsql18.msi` — optional ODBC Driver 18 installer when SQL setup does not provide a supported driver.
- `wheels/` — Python wheel files for every package in `requirements.txt` and its dependencies.

You can also add the official SQL Server Management Studio 22 bootstrapper as `vs_SSMS.exe`.

When files are absent, the wizard downloads the SQL Express, ODBC, SSMS, and Python installers. The wizard never downloads from non-official domains.
