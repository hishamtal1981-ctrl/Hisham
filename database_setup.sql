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
GO
IF NOT EXISTS(SELECT 1 FROM dbo.properties WHERE name=N'Hilton Amman') INSERT INTO dbo.properties(name,active) VALUES(N'Hilton Amman',1);
IF NOT EXISTS(SELECT 1 FROM dbo.groups_tbl WHERE name=N'Administrators') INSERT INTO dbo.groups_tbl(name,description) VALUES(N'Administrators',N'System administrators');
IF NOT EXISTS(SELECT 1 FROM dbo.users WHERE username=N'admin') INSERT INTO dbo.users(username,password_hash,role,group_name,property_name) VALUES(N'admin',N'e86f78a8a3caf0b60d8e74e5942aa6d86dc150cd3c03338aef25b7d2d7e3acc7',N'admin',N'Administrators',N'Hilton Amman');
GO
