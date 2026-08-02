from __future__ import annotations

import csv
import hashlib
import io
import json
import secrets
import sqlite3
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from fastapi import FastAPI, File, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

ROOT = Path(__file__).resolve().parent
DB_PATH = ROOT / "maintenance.db"
SESSIONS: dict[str, str] = {}


def db() -> sqlite3.Connection:
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    return con


def password_hash(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def init_db() -> None:
    with db() as con:
        con.executescript("""
        CREATE TABLE IF NOT EXISTS properties(id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL, logo TEXT DEFAULT '', active INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS groups_tbl(id INTEGER PRIMARY KEY, name TEXT UNIQUE NOT NULL, description TEXT DEFAULT '');
        CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, password_hash TEXT NOT NULL, role TEXT DEFAULT 'user', group_name TEXT DEFAULT '', property_name TEXT DEFAULT '');
        CREATE TABLE IF NOT EXISTS contracts(
          id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, contractor_name TEXT NOT NULL,
          contractor_phone TEXT DEFAULT '', department TEXT DEFAULT '', value REAL DEFAULT 0,
          currency TEXT DEFAULT 'JD', tax_percent REAL DEFAULT 0, start_date TEXT, end_date TEXT,
          property_name TEXT DEFAULT '', notes TEXT DEFAULT '', archived INTEGER DEFAULT 0,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        );
        """)
        con.execute("INSERT OR IGNORE INTO properties(name,active) VALUES('Hilton Amman',1)")
        con.execute("INSERT OR IGNORE INTO groups_tbl(name,description) VALUES('Administrators','System administrators')")
        con.execute("INSERT OR IGNORE INTO users(username,password_hash,role,group_name,property_name) VALUES(?,?,?,?,?)",
                    ('admin', password_hash('Admin@123'), 'admin', 'Administrators', 'Hilton Amman'))


init_db()
app = FastAPI(title="Maintenance Contracts System")


def auth(authorization: str | None) -> sqlite3.Row:
    token = (authorization or '').removeprefix('Bearer ').strip()
    username = SESSIONS.get(token)
    if not username:
        raise HTTPException(401, 'Unauthorized')
    with db() as con:
        user = con.execute('SELECT id,username,role,group_name,property_name FROM users WHERE username=?',(username,)).fetchone()
    if not user:
        raise HTTPException(401, 'Unauthorized')
    return user


class Login(BaseModel):
    username: str
    password: str


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
    if not row or row['password_hash'] != password_hash(payload.password):
        raise HTTPException(401, 'Invalid username or password')
    token = secrets.token_urlsafe(32); SESSIONS[token] = row['username']
    return {'token': token, 'user': {'username': row['username'], 'role': row['role'], 'property_name': row['property_name']}}


@app.get('/api/me')
def me(authorization: str | None = Header(None)):
    return dict(auth(authorization))


def status_for(end_date: str) -> str:
    try: days = (date.fromisoformat(end_date) - date.today()).days
    except Exception: return 'active'
    return 'expired' if days < 0 else ('expiring_soon' if days <= 30 else 'active')


@app.get('/api/contracts')
def list_contracts(include_archived: bool = False, authorization: str | None = Header(None)):
    user = auth(authorization)
    sql, args = 'SELECT * FROM contracts WHERE archived=?', [1 if include_archived else 0]
    if user['role'] != 'admin' and user['property_name']:
        sql += ' AND property_name=?'; args.append(user['property_name'])
    sql += ' ORDER BY end_date'
    with db() as con: rows = [dict(x) for x in con.execute(sql,args)]
    for row in rows: row['status'] = status_for(row['end_date'])
    return rows


@app.post('/api/contracts')
def add_contract(payload: Contract, authorization: str | None = Header(None)):
    auth(authorization); now = datetime.now(timezone.utc).isoformat(); data = payload.model_dump()
    with db() as con:
        cur=con.execute('''INSERT INTO contracts(name,contractor_name,contractor_phone,department,value,currency,tax_percent,start_date,end_date,property_name,notes,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)''',(*data.values(),now,now))
    return {'success':True,'id':cur.lastrowid}


@app.put('/api/contracts/{contract_id}')
def edit_contract(contract_id: int, payload: Contract, authorization: str | None = Header(None)):
    auth(authorization); data=payload.model_dump(); now=datetime.now(timezone.utc).isoformat()
    with db() as con:
        con.execute('''UPDATE contracts SET name=?,contractor_name=?,contractor_phone=?,department=?,value=?,currency=?,tax_percent=?,start_date=?,end_date=?,property_name=?,notes=?,updated_at=? WHERE id=?''',(*data.values(),now,contract_id))
    return {'success':True}


@app.delete('/api/contracts/{contract_id}')
def archive_contract(contract_id:int, authorization: str | None = Header(None)):
    auth(authorization)
    with db() as con: con.execute('UPDATE contracts SET archived=1 WHERE id=?',(contract_id,))
    return {'success':True}


@app.get('/api/stats')
def stats(authorization: str | None = Header(None)):
    rows=list_contracts(False,authorization); counts={'total':len(rows),'active':0,'expiring_soon':0,'expired':0,'value':0}
    for r in rows: counts[r['status']]+=1; counts['value']+=r['value']
    return counts


def admin(authorization: str | None) -> sqlite3.Row:
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
    with db() as con: row=con.execute('SELECT * FROM properties WHERE active=1 LIMIT 1').fetchone()
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

