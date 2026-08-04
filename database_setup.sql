IF DB_ID(N'Maintenance Contract') IS NULL
BEGIN
    CREATE DATABASE [Maintenance Contract];
END;
GO
USE [Maintenance Contract];
GO
IF OBJECT_ID('dbo.properties','U') IS NULL CREATE TABLE dbo.properties(id INT IDENTITY(1,1) PRIMARY KEY,name NVARCHAR(200) UNIQUE NOT NULL,logo NVARCHAR(1000) NOT NULL DEFAULT '',active BIT NOT NULL DEFAULT 0);
GO
IF OBJECT_ID('dbo.groups_tbl','U') IS NULL CREATE TABLE dbo.groups_tbl(id INT IDENTITY(1,1) PRIMARY KEY,name NVARCHAR(200) UNIQUE NOT NULL,description NVARCHAR(1000) NOT NULL DEFAULT '');
GO
IF OBJECT_ID('dbo.users','U') IS NULL CREATE TABLE dbo.users(id INT IDENTITY(1,1) PRIMARY KEY,username NVARCHAR(200) UNIQUE NOT NULL,password_hash NVARCHAR(64) NOT NULL,role NVARCHAR(30) NOT NULL DEFAULT 'user',group_name NVARCHAR(200) NOT NULL DEFAULT '',property_name NVARCHAR(200) NOT NULL DEFAULT '');
GO
IF OBJECT_ID('dbo.contracts','U') IS NULL CREATE TABLE dbo.contracts(id INT IDENTITY(1,1) PRIMARY KEY,name NVARCHAR(500) NOT NULL,contractor_name NVARCHAR(500) NOT NULL,contractor_phone NVARCHAR(100) NOT NULL DEFAULT '',department NVARCHAR(200) NOT NULL DEFAULT '',value DECIMAL(18,2) NOT NULL DEFAULT 0,currency NVARCHAR(20) NOT NULL DEFAULT 'JD',tax_percent DECIMAL(8,2) NOT NULL DEFAULT 0,start_date DATE NULL,end_date DATE NULL,property_name NVARCHAR(200) NOT NULL DEFAULT '',notes NVARCHAR(MAX) NOT NULL DEFAULT '',archived BIT NOT NULL DEFAULT 0,created_at DATETIMEOFFSET NOT NULL,updated_at DATETIMEOFFSET NOT NULL);
GO
IF COL_LENGTH('dbo.contracts','attachment_name') IS NULL ALTER TABLE dbo.contracts ADD attachment_name NVARCHAR(500) NULL;
IF COL_LENGTH('dbo.contracts','attachment_content_type') IS NULL ALTER TABLE dbo.contracts ADD attachment_content_type NVARCHAR(200) NULL;
IF COL_LENGTH('dbo.contracts','attachment_data') IS NULL ALTER TABLE dbo.contracts ADD attachment_data VARBINARY(MAX) NULL;
IF COL_LENGTH('dbo.contracts','attachment_size') IS NULL ALTER TABLE dbo.contracts ADD attachment_size BIGINT NULL;
IF COL_LENGTH('dbo.contracts','archived_at') IS NULL ALTER TABLE dbo.contracts ADD archived_at DATETIMEOFFSET NULL;
IF COL_LENGTH('dbo.contracts','archive_exempt') IS NULL ALTER TABLE dbo.contracts ADD archive_exempt BIT NOT NULL DEFAULT 0;
UPDATE dbo.contracts SET archived_at=COALESCE(updated_at,created_at) WHERE archived=1 AND archived_at IS NULL;
IF OBJECT_ID('dbo.audit_logs','U') IS NULL CREATE TABLE dbo.audit_logs(id INT IDENTITY(1,1) PRIMARY KEY,username NVARCHAR(200) NOT NULL,action NVARCHAR(100) NOT NULL,entity_type NVARCHAR(100) NOT NULL,entity_id INT NULL,details NVARCHAR(1000) NOT NULL DEFAULT '',property_name NVARCHAR(200) NOT NULL DEFAULT '',created_at DATETIMEOFFSET NOT NULL);
IF OBJECT_ID('dbo.departments','U') IS NULL CREATE TABLE dbo.departments(id INT IDENTITY(1,1) PRIMARY KEY,name NVARCHAR(200) NOT NULL UNIQUE,description NVARCHAR(500) NOT NULL DEFAULT '',active BIT NOT NULL DEFAULT 1,created_at DATETIMEOFFSET NOT NULL);
IF OBJECT_ID('dbo.currencies','U') IS NULL CREATE TABLE dbo.currencies(code NVARCHAR(20) PRIMARY KEY,name NVARCHAR(100) NOT NULL,symbol NVARCHAR(20) NOT NULL DEFAULT '',active BIT NOT NULL DEFAULT 1,created_at DATETIMEOFFSET NOT NULL);
IF OBJECT_ID('dbo.system_settings','U') IS NULL CREATE TABLE dbo.system_settings(setting_key NVARCHAR(100) PRIMARY KEY,setting_value NVARCHAR(MAX) NOT NULL DEFAULT '',updated_at DATETIMEOFFSET NOT NULL);
IF OBJECT_ID('dbo.property_logos','U') IS NULL CREATE TABLE dbo.property_logos(id INT IDENTITY(1,1) PRIMARY KEY,property_name NVARCHAR(200) NOT NULL UNIQUE,logo_name NVARCHAR(500) NOT NULL,content_type NVARCHAR(100) NOT NULL,logo_data VARBINARY(MAX) NOT NULL,updated_at DATETIMEOFFSET NOT NULL,updated_by NVARCHAR(200) NOT NULL DEFAULT '');
IF OBJECT_ID('dbo.database_backups','U') IS NULL CREATE TABLE dbo.database_backups(id INT IDENTITY(1,1) PRIMARY KEY,backup_name NVARCHAR(500) NOT NULL,backup_data VARBINARY(MAX) NULL,backup_size BIGINT NOT NULL,backup_path NVARCHAR(1000) NULL,created_at DATETIMEOFFSET NOT NULL,created_by NVARCHAR(200) NOT NULL);
ALTER TABLE dbo.database_backups ALTER COLUMN backup_data VARBINARY(MAX) NULL;
IF COL_LENGTH('dbo.database_backups','backup_path') IS NULL ALTER TABLE dbo.database_backups ADD backup_path NVARCHAR(1000) NULL;
IF OBJECT_ID('dbo.database_backup_chunks','U') IS NULL CREATE TABLE dbo.database_backup_chunks(id INT IDENTITY(1,1) PRIMARY KEY,backup_id INT NOT NULL,chunk_index INT NOT NULL,chunk_data VARBINARY(MAX) NOT NULL);
DECLARE @master_now DATETIMEOFFSET=SYSDATETIMEOFFSET();
INSERT INTO dbo.departments(name,created_at) SELECT DISTINCT c.department,@master_now FROM dbo.contracts c WHERE c.department<>'' AND NOT EXISTS(SELECT 1 FROM dbo.departments d WHERE d.name=c.department);
INSERT INTO dbo.currencies(code,name,symbol,created_at) SELECT v.code,v.name,v.symbol,@master_now FROM (VALUES(N'JD',N'Jordanian Dinar',N'JD'),(N'USD',N'US Dollar',N'$'),(N'SAR',N'Saudi Riyal',N'SAR'),(N'EUR',N'Euro',N'€'))v(code,name,symbol) WHERE NOT EXISTS(SELECT 1 FROM dbo.currencies c WHERE c.code=v.code);
INSERT INTO dbo.currencies(code,name,symbol,created_at) SELECT DISTINCT c.currency,c.currency,c.currency,@master_now FROM dbo.contracts c WHERE c.currency<>'' AND NOT EXISTS(SELECT 1 FROM dbo.currencies d WHERE d.code=c.currency);
IF COL_LENGTH('dbo.contracts','department_id') IS NULL ALTER TABLE dbo.contracts ADD department_id INT NULL;
IF COL_LENGTH('dbo.contracts','currency_code') IS NULL ALTER TABLE dbo.contracts ADD currency_code NVARCHAR(20) NULL;
UPDATE c SET department_id=d.id FROM dbo.contracts c JOIN dbo.departments d ON d.name=c.department WHERE c.department_id IS NULL;
UPDATE dbo.contracts SET currency_code=currency WHERE currency_code IS NULL AND currency<>'';
GO
IF NOT EXISTS(SELECT 1 FROM dbo.properties WHERE name=N'Hilton Amman') INSERT INTO dbo.properties(name,active) VALUES(N'Hilton Amman',1);
IF NOT EXISTS(SELECT 1 FROM dbo.groups_tbl WHERE name=N'Administrators') INSERT INTO dbo.groups_tbl(name,description) VALUES(N'Administrators',N'System administrators');
IF NOT EXISTS(SELECT 1 FROM dbo.users WHERE username=N'admin') INSERT INTO dbo.users(username,password_hash,role,group_name,property_name) VALUES(N'admin',N'e86f78a8a3caf0b60d8e74e5942aa6d86dc150cd3c03338aef25b7d2d7e3acc7',N'admin',N'Administrators',N'Hilton Amman');
GO
