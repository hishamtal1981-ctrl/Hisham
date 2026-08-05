USE [Maintenance Contract];
GO
SET NOCOUNT ON;

SELECT DB_NAME() AS database_name,
       CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(256)) AS sql_server,
       CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)) AS sql_version;

SELECT t.name AS table_name,
       SUM(p.rows) AS row_count
FROM sys.tables t
JOIN sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1)
WHERE t.name IN (
    N'properties',N'groups_tbl',N'users',N'contracts',N'audit_logs',
    N'departments',N'currencies',N'system_settings',N'property_logos',
    N'database_backups',N'database_backup_chunks',N'schema_migrations',N'user_properties'
)
GROUP BY t.name
ORDER BY t.name;

SELECT version,description,applied_at
FROM dbo.schema_migrations
ORDER BY version;

SELECT name AS database_object,type_desc
FROM sys.objects
WHERE name IN (
    N'vw_contract_management',N'FK_database_backup_chunks_backup',
    N'IX_contracts_scope_status',N'IX_contracts_department',
    N'IX_audit_logs_created',N'IX_database_backups_created',
    N'UX_database_backup_chunks_order',N'FK_user_properties_user',
    N'IX_user_properties_property'
)
ORDER BY type_desc,name;
GO
