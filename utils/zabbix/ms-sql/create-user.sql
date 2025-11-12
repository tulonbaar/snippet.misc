USE master;
CREATE LOGIN zabbix WITH PASSWORD = '<password>'
GRANT VIEW SERVER PERFORMANCE STATE TO zabbix
USE msdb
CREATE USER zabbix FOR LOGIN zabbix
GRANT EXECUTE ON msdb.dbo.agent_datetime TO zabbix
GRANT SELECT ON msdb.dbo.sysjobactivity TO zabbix
GRANT SELECT ON msdb.dbo.sysjobservers TO zabbix
GRANT SELECT ON msdb.dbo.sysjobs TO zabbix
GO