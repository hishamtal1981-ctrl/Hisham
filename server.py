from __future__ import annotations

import csv
import hashlib
import io
import json
import secrets
import os
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, field_validator

ROOT = Path(__file__).resolve().parent
DB_NAME = os.getenv("SQLSERVER_DATABASE", "Maintenance Contract")
DB_SERVER = os.getenv("SQLSERVER_HOST", "localhost")
SESSIONS: dict[str, dict[str, str]] = {}


class SqlCursor:
    def __init__(self, cursor):
        self.cursor = cursor

    def _row(self, row):
        if row is None:
            return None
        return dict(zip((column[0] for column in self.cursor.description), row))

    def fetchone(self):
        return self._row(self.cursor.fetchone())

    def __iter__(self):
        columns = [column[0] for column in self.cursor.description]
        for row in self.cursor:
            yield dict(zip(columns, row))

    @property
    def rowcount(self):
        return self.cursor.rowcount


class SqlConnection:
    def __init__(self, connection):
        self.connection = connection

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        self.connection.rollback() if exc_type else self.connection.commit()
        self.connection.close()

    def execute(self, sql, params=()):
        return SqlCursor(self.connection.cursor().execute(sql, params))


def db():
    import pyodbc
    installed = set(pyodbc.drivers())
    driver = next((name for name in ('ODBC Driver 18 for SQL Server', 'ODBC Driver 17 for SQL Server') if name in installed), None)
    if not driver:
        raise RuntimeError('Install Microsoft ODBC Driver 18 or 17 for SQL Server')
    connection_string = (
        f"DRIVER={{{driver}}};"
        f"SERVER={DB_SERVER};DATABASE={DB_NAME};"
        "Trusted_Connection=yes;Encrypt=no;TrustServerCertificate=yes;"
    )
    return SqlConnection(pyodbc.connect(connection_string))


def password_hash(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def init_db() -> None:
    with db() as con:
        con.execute("""IF OBJECT_ID('properties','U') IS NULL CREATE TABLE properties(
          id INT IDENTITY(1,1) PRIMARY KEY, name NVARCHAR(200) UNIQUE NOT NULL,
          logo NVARCHAR(1000) NOT NULL DEFAULT '', active BIT NOT NULL DEFAULT 0)""")
        con.execute("""IF OBJECT_ID('groups_tbl','U') IS NULL CREATE TABLE groups_tbl(
          id INT IDENTITY(1,1) PRIMARY KEY, name NVARCHAR(200) UNIQUE NOT NULL,
          description NVARCHAR(1000) NOT NULL DEFAULT '')""")
        con.execute("""IF OBJECT_ID('users','U') IS NULL CREATE TABLE users(
          id INT IDENTITY(1,1) PRIMARY KEY, username NVARCHAR(200) UNIQUE NOT NULL,
          password_hash NVARCHAR(64) NOT NULL, role NVARCHAR(30) NOT NULL DEFAULT 'user',
          group_name NVARCHAR(200) NOT NULL DEFAULT '', property_name NVARCHAR(200) NOT NULL DEFAULT '')""")
        con.execute("""IF OBJECT_ID('contracts','U') IS NULL CREATE TABLE contracts(
          id INT IDENTITY(1,1) PRIMARY KEY, name NVARCHAR(500) NOT NULL,
          contractor_name NVARCHAR(500) NOT NULL, contractor_phone NVARCHAR(100) NOT NULL DEFAULT '',
          department NVARCHAR(200) NOT NULL DEFAULT '', value DECIMAL(18,2) NOT NULL DEFAULT 0,
          currency NVARCHAR(20) NOT NULL DEFAULT 'JD', tax_percent DECIMAL(8,2) NOT NULL DEFAULT 0,
          start_date DATE NULL, end_date DATE NULL, property_name NVARCHAR(200) NOT NULL DEFAULT '',
          notes NVARCHAR(MAX) NOT NULL DEFAULT '', archived BIT NOT NULL DEFAULT 0,
          created_at DATETIMEOFFSET NOT NULL, updated_at DATETIMEOFFSET NOT NULL)""")
        con.execute("IF NOT EXISTS(SELECT 1 FROM properties WHERE name=?) INSERT INTO properties(name,active) VALUES(?,1)", ('Hilton Amman','Hilton Amman'))
        con.execute("IF NOT EXISTS(SELECT 1 FROM groups_tbl WHERE name=?) INSERT INTO groups_tbl(name,description) VALUES(?,?)", ('Administrators','Administrators','System administrators'))
        con.execute("IF NOT EXISTS(SELECT 1 FROM users WHERE username=?) INSERT INTO users(username,password_hash,role,group_name,property_name) VALUES(?,?,?,?,?)",
                    ('admin','admin', password_hash('Admin@123'), 'admin', 'Administrators', 'Hilton Amman'))


init_db()
app = FastAPI(title="Maintenance Contracts System")


def auth(authorization: str | None) -> dict[str, Any]:
    token = (authorization or '').removeprefix('Bearer ').strip()
    session = SESSIONS.get(token)
    if not session:
        raise HTTPException(401, 'Unauthorized')
    with db() as con:
        user = con.execute('SELECT id,username,role,group_name,property_name FROM users WHERE username=?',(session['username'],)).fetchone()
    if not user:
        raise HTTPException(401, 'Unauthorized')
    result = dict(user)
    result['property_name'] = session['property_name']
    return result


class Login(BaseModel):
    username: str
    password: str
    property_name: str = ''


class Contract(BaseModel):
    name: str
    contractor_name: str
    contractor_phone: str = ''
    department: str = ''
    value: float = 0
    currency: str = 'JD'
    tax_percent: float = 0
    start_date: str = ''
    end_date: str = ''
    property_name: str = ''
    notes: str = ''

    @field_validator('name', 'contractor_name')
    @classmethod
    def required_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError('This field is required')
        return value

    @field_validator('value', 'tax_percent')
    @classmethod
    def non_negative_number(cls, value: float) -> float:
        if value < 0:
            raise ValueError('Value cannot be negative')
        return value

    @field_validator('start_date', 'end_date')
    @classmethod
    def valid_date(cls, value: str) -> str:
        if value:
            date.fromisoformat(value)
        return value


class UserPayload(BaseModel):
    username: str
    password: str = ''
    role: str = 'user'
    group_name: str = ''
    property_name: str = ''


class NamedPayload(BaseModel):
    name: str
    description: str = ''
    logo: str = ''


@app.post('/api/auth/login')
def login(payload: Login):
    with db() as con:
        row = con.execute('SELECT * FROM users WHERE username=?',(payload.username,)).fetchone()
        selected_property = con.execute('SELECT name FROM properties WHERE name=?',(payload.property_name,)).fetchone() if payload.property_name else None
    if not row or row['password_hash'] != password_hash(payload.password):
        raise HTTPException(401, 'Invalid username or password')
    if row['role'] != 'admin' and not selected_property:
        raise HTTPException(400, 'Please select a valid property')
    if row['role'] != 'admin' and row['property_name'] and row['property_name'] != payload.property_name:
        raise HTTPException(403, 'This user is not assigned to the selected property')
    token = secrets.token_urlsafe(32)
    selected_name = payload.property_name if selected_property else ''
    SESSIONS[token] = {'username': row['username'], 'property_name': selected_name}
    return {'token': token, 'user': {'username': row['username'], 'role': row['role'], 'property_name': selected_name}}


@app.post('/api/auth/logout')
def logout(authorization: str | None = Header(None)):
    token = (authorization or '').removeprefix('Bearer ').strip()
    SESSIONS.pop(token, None)
    return {'success': True}


@app.get('/api/auth/properties')
def login_properties():
    with db() as con:
        return [dict(x) for x in con.execute('SELECT name,logo FROM properties ORDER BY name')]


@app.get('/api/me')
def me(authorization: str | None = Header(None)):
    return dict(auth(authorization))


def status_for(end_date: str) -> str:
    try:
        parsed = end_date if isinstance(end_date, date) else date.fromisoformat(str(end_date))
        days = (parsed - date.today()).days
    except Exception: return 'active'
    return 'expired' if days < 0 else ('expiring_soon' if days <= 30 else 'active')


@app.get('/api/contracts')
def list_contracts(include_archived: bool = False, authorization: str | None = Header(None)):
    user = auth(authorization)
    sql, args = '''SELECT id,name,contractor_name,contractor_phone,department,value,currency,
        tax_percent,start_date,end_date,property_name,notes,archived,
        CONVERT(NVARCHAR(40),created_at,127) AS created_at,
        CONVERT(NVARCHAR(40),updated_at,127) AS updated_at
        FROM contracts WHERE archived=?''', [1 if include_archived else 0]
    if user['property_name']:
        sql += ' AND property_name=?'; args.append(user['property_name'])
    sql += ' ORDER BY end_date'
    with db() as con: rows = [dict(x) for x in con.execute(sql,args)]
    for row in rows: row['status'] = status_for(row['end_date'])
    return rows


@app.post('/api/contracts')
def add_contract(payload: Contract, authorization: str | None = Header(None)):
    user = auth(authorization)
    data = payload.model_dump()
    if user['property_name']:
        data['property_name'] = user['property_name']
    if not data['property_name']:
        raise HTTPException(400, 'Please select a property for this contract')
    with db() as con:
        property_exists = con.execute('SELECT id FROM properties WHERE name=?',(data['property_name'],)).fetchone()
    if not property_exists:
        raise HTTPException(400, 'The selected property does not exist')
    data['start_date'] = data['start_date'] or None
    data['end_date'] = data['end_date'] or None
    now = datetime.now(timezone.utc).isoformat()
    with db() as con:
        cur=con.execute('''INSERT INTO contracts(name,contractor_name,contractor_phone,department,value,currency,tax_percent,start_date,end_date,property_name,notes,created_at,updated_at) OUTPUT INSERTED.id VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)''',(
            data['name'],data['contractor_name'],data['contractor_phone'],data['department'],data['value'],data['currency'],data['tax_percent'],data['start_date'],data['end_date'],data['property_name'],data['notes'],now,now))
        contract_id=cur.fetchone()['id']
    return {'success':True,'id':contract_id,'property_name':data['property_name']}


def contract_access(user: dict[str, Any], contract_id: int) -> dict[str, Any]:
    with db() as con:
        contract = con.execute('SELECT id,property_name FROM contracts WHERE id=?',(contract_id,)).fetchone()
    if not contract:
        raise HTTPException(404, 'Contract not found')
    if user['property_name'] and contract['property_name'] != user['property_name']:
        raise HTTPException(403, 'You cannot modify a contract from another property')
    return contract


@app.put('/api/contracts/{contract_id}')
def edit_contract(contract_id: int, payload: Contract, authorization: str | None = Header(None)):
    user=auth(authorization); contract_access(user,contract_id); data=payload.model_dump(); now=datetime.now(timezone.utc).isoformat()
    if user['property_name']:
        data['property_name']=user['property_name']
    if not data['property_name']:
        raise HTTPException(400, 'Please select a property for this contract')
    with db() as con:
        if not con.execute('SELECT id FROM properties WHERE name=?',(data['property_name'],)).fetchone():
            raise HTTPException(400, 'The selected property does not exist')
    data['start_date']=data['start_date'] or None; data['end_date']=data['end_date'] or None
    with db() as con:
        con.execute('''UPDATE contracts SET name=?,contractor_name=?,contractor_phone=?,department=?,value=?,currency=?,tax_percent=?,start_date=?,end_date=?,property_name=?,notes=?,updated_at=? WHERE id=?''',(
            data['name'],data['contractor_name'],data['contractor_phone'],data['department'],data['value'],data['currency'],data['tax_percent'],data['start_date'],data['end_date'],data['property_name'],data['notes'],now,contract_id))
    return {'success':True}


@app.delete('/api/contracts/{contract_id}')
def archive_contract(contract_id:int, authorization: str | None = Header(None)):
    user=auth(authorization); contract_access(user,contract_id)
    with db() as con: con.execute('UPDATE contracts SET archived=1 WHERE id=?',(contract_id,))
    return {'success':True}


@app.get('/api/stats')
def stats(authorization: str | None = Header(None)):
    rows=list_contracts(False,authorization); counts={'total':len(rows),'active':0,'expiring_soon':0,'expired':0,'value':0}
    for r in rows: counts[r['status']]+=1; counts['value']+=r['value']
    return counts


def admin(authorization: str | None) -> dict[str, Any]:
    user=auth(authorization)
    if user['role']!='admin': raise HTTPException(403,'Admin required')
    return user


@app.get('/api/users')
def users(authorization: str | None = Header(None)):
    admin(authorization)
    with db() as con: return [dict(x) for x in con.execute('SELECT id,username,role,group_name,property_name FROM users ORDER BY username')]


@app.post('/api/users')
def add_user(p:UserPayload, authorization: str | None = Header(None)):
    admin(authorization)
    with db() as con: con.execute('INSERT INTO users(username,password_hash,role,group_name,property_name) VALUES(?,?,?,?,?)',(p.username,password_hash(p.password or 'Welcome@123'),p.role,p.group_name,p.property_name))
    return {'success':True}


@app.get('/api/groups')
def groups(authorization: str | None = Header(None)):
    auth(authorization)
    with db() as con: return [dict(x) for x in con.execute('SELECT * FROM groups_tbl ORDER BY name')]


@app.post('/api/groups')
def add_group(p:NamedPayload, authorization: str | None = Header(None)):
    admin(authorization)
    with db() as con: con.execute('INSERT INTO groups_tbl(name,description) VALUES(?,?)',(p.name,p.description))
    return {'success':True}


@app.get('/api/properties')
def properties(authorization: str | None = Header(None)):
    auth(authorization)
    with db() as con: return [dict(x) for x in con.execute('SELECT * FROM properties ORDER BY name')]


@app.post('/api/properties')
def add_property(p:NamedPayload, authorization: str | None = Header(None)):
    admin(authorization)
    with db() as con: con.execute('INSERT INTO properties(name,logo) VALUES(?,?)',(p.name,p.logo))
    return {'success':True}


@app.post('/api/properties/{name}/activate')
def activate_property(name:str, authorization: str | None = Header(None)):
    admin(authorization)
    with db() as con:
        con.execute('UPDATE properties SET active=0'); con.execute('UPDATE properties SET active=1 WHERE name=?',(name,))
    return {'success':True}


@app.get('/api/active-property')
def active_property(authorization: str | None = Header(None)):
    auth(authorization)
    with db() as con: row=con.execute('SELECT TOP 1 * FROM properties WHERE active=1').fetchone()
    return dict(row) if row else {'name':'Maintenance Contracts','logo':''}


@app.get('/api/export')
def export_csv(authorization: str | None = Header(None)):
    rows=list_contracts(False,authorization); output=io.StringIO(); fields=list(Contract.model_fields)
    writer=csv.DictWriter(output,fieldnames=fields); writer.writeheader(); writer.writerows([{k:r.get(k,'') for k in fields} for r in rows])
    return StreamingResponse(iter([output.getvalue()]),media_type='text/csv',headers={'Content-Disposition':'attachment; filename=contracts.csv'})


@app.post('/api/import')
async def import_csv(file:UploadFile=File(...), authorization: str | None = Header(None)):
    auth(authorization); text=(await file.read()).decode('utf-8-sig'); count=0
    for row in csv.DictReader(io.StringIO(text)):
        add_contract(Contract(**row),authorization); count+=1
    return {'success':True,'imported':count}


app.mount('/static',StaticFiles(directory=ROOT/'static'),name='static')

@app.get('/')
def home(): return FileResponse(ROOT/'static/index.html')
