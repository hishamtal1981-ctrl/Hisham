from __future__ import annotations

import os
import sys

import pyodbc


server = os.environ.get("SQLSERVER_HOST", r".\MAINTENANCE")
database = os.environ.get("SQLSERVER_DATABASE", "Maintenance Contract")
drivers = set(pyodbc.drivers())
driver = next(
    (name for name in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server") if name in drivers),
    None,
)
if not driver:
    raise SystemExit("Microsoft ODBC Driver 18 or 17 for SQL Server is required.")


def connection_string(target_database: str) -> str:
    return (
        f"DRIVER={{{driver}}};SERVER={server};DATABASE={target_database};"
        "Trusted_Connection=yes;Encrypt=Optional;TrustServerCertificate=yes;"
    )


with pyodbc.connect(connection_string("master"), autocommit=True) as connection:
    escaped_database = database.replace("]", "]]" )
    connection.execute(
        f"IF DB_ID(?) IS NULL EXEC('CREATE DATABASE [{escaped_database}]')", database
    )
    connection.execute(
        "IF SUSER_ID(N'NT AUTHORITY\\SYSTEM') IS NULL "
        "CREATE LOGIN [NT AUTHORITY\\SYSTEM] FROM WINDOWS"
    )

with pyodbc.connect(connection_string(database), autocommit=True) as connection:
    connection.execute(
        "IF USER_ID(N'NT AUTHORITY\\SYSTEM') IS NULL "
        "CREATE USER [NT AUTHORITY\\SYSTEM] FOR LOGIN [NT AUTHORITY\\SYSTEM]"
    )
    connection.execute(
        "IF IS_ROLEMEMBER(N'db_owner', N'NT AUTHORITY\\SYSTEM') <> 1 "
        "ALTER ROLE db_owner ADD MEMBER [NT AUTHORITY\\SYSTEM]"
    )

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server as application  # noqa: E402,F401

print(f"Database [{database}] is ready on {server}.")
