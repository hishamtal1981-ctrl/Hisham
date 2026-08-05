from __future__ import annotations

import os
import sys
import time

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
        "Trusted_Connection=yes;Encrypt=no;TrustServerCertificate=yes;"
    )


def connect_with_retry(target_database: str, attempts: int = 60):
    last_error = None
    for attempt in range(1, attempts + 1):
        try:
            return pyodbc.connect(
                connection_string(target_database), autocommit=True, timeout=5
            )
        except pyodbc.Error as error:
            last_error = error
            if attempt < attempts:
                print(
                    f"Waiting for SQL Server {server} ({attempt}/{attempts})...",
                    flush=True,
                )
                time.sleep(2)
    raise SystemExit(
        f"Could not connect to SQL Server {server} after {attempts} attempts: "
        f"{last_error}"
    )


with connect_with_retry("master") as connection:
    database_exists = bool(connection.execute("SELECT DB_ID(?)", database).fetchone()[0])
    escaped_database = database.replace("]", "]]" )
    if database_exists:
        print(f"Existing database [{database}] found. Existing data will be preserved.", flush=True)
    else:
        print(f"Database [{database}] was not found. Creating it now...", flush=True)
        connection.execute(f"CREATE DATABASE [{escaped_database}]")
    connection.execute(
        "IF SUSER_ID(N'NT AUTHORITY\\SYSTEM') IS NULL "
        "CREATE LOGIN [NT AUTHORITY\\SYSTEM] FROM WINDOWS"
    )

with connect_with_retry(database) as connection:
    connection.execute(
        "IF USER_ID(N'NT AUTHORITY\\SYSTEM') IS NULL "
        "CREATE USER [NT AUTHORITY\\SYSTEM] FOR LOGIN [NT AUTHORITY\\SYSTEM]"
    )
    connection.execute(
        "IF IS_ROLEMEMBER(N'db_owner', N'NT AUTHORITY\\SYSTEM') <> 1 "
        "ALTER ROLE db_owner ADD MEMBER [NT AUTHORITY\\SYSTEM]"
    )

print("Applying additive schema updates only; no existing rows are deleted or replaced.", flush=True)
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import server as application  # noqa: E402,F401

result = "updated safely" if database_exists else "created"
print(f"Database [{database}] is ready on {server} ({result}).")
