

--===========================================
--- 1. CREATING PROCEDURES NEEDED--==========
--===========================================
--Helping procedure to produce the results from the FILELISTONLY
IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND name = 'BACKUP_FILE_NAMES')
	DROP PROCEDURE [dbo].[BACKUP_FILE_NAMES]
GO

CREATE PROC dbo.BACKUP_FILE_NAMES
(@BACKUP_FILE NVARCHAR(MAX))
AS
SET NOCOUNT ON
RESTORE FILELISTONLY   
FROM DISK = @BACKUP_FILE

GO


--Main procedure - creates the new database in the same location
IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND name = 'BACKUP_RESTORE_TO_ANOTHER_DB')
	DROP PROCEDURE [dbo].BACKUP_RESTORE_TO_ANOTHER_DB
GO

CREATE PROC BACKUP_RESTORE_TO_ANOTHER_DB
(
	@BACKUP_FILE NVARCHAR(MAX),
	@NEW_DB NVARCHAR(MAX),
	@NEW_LOCATION NVARCHAR(MAX)
)
AS
SET NOCOUNT ON

DECLARE @SQL NVARCHAR(MAX) = '',
		@LOGICAL_NAME NVARCHAR(MAX),
		@PHYSICAL_NAME NVARCHAR(MAX)

DECLARE @TEMP_FILENAMES TABLE
		(LogicalName nvarchar(128),
		PhysicalName nvarchar(260),
		[Type] char(1),
		FileGroupName nvarchar(128) NULL,
		Size numeric(20,0),
		MaxSize numeric(20,0),
		FileID bigint,
		CreateLSN numeric(25,0),
		DropLSN numeric(25,0) NULL,
		UniqueID uniqueidentifier,
		ReadOnlyLSN numeric(25,0) NULL,
		ReadWriteLSN numeric(25,0) NULL,
		BackupSizeInBytes bigint,
		SourceBlockSize int,
		FileGroupID int,
		LogGroupGUID uniqueidentifier NULL,
		DifferentialBaseLSN numeric(25,0) NULL,
		DifferentialBaseGUID uniqueidentifier NULL,
		IsReadOnly bit,
		IsPresent bit,
		TDEThumbprint varbinary(32) NULL,
		SnapshotURL nvarchar(360) NULL)


INSERT @TEMP_FILENAMES
EXEC dbo.BACKUP_FILE_NAMES @BACKUP_FILE = @BACKUP_FILE

SET @SQL += 'USE MASTER;' + CHAR(10)
SET @SQL += 'CREATE DATABASE ' + @NEW_DB + CHAR(10)
SET @SQL += 'ALTER DATABASE ' + @NEW_DB + ' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;' + CHAR(10)
SET @SQL += 'RESTORE DATABASE  ' + @NEW_DB + ' FROM  DISK = N''' + @BACKUP_FILE + '''' + CHAR(10)
SET @SQL += 'WITH' + CHAR(10)


WHILE (SELECT COUNT(*) FROM @TEMP_FILENAMES) > 0
	BEGIN
	
		SELECT TOP 1 @LOGICAL_NAME = LOGICALNAME, @PHYSICAL_NAME = PHYSICALNAME FROM @TEMP_FILENAMES ORDER BY FileID
		SET @SQL += 'MOVE ''' + @LOGICAL_NAME + ''' TO ''' + @NEW_LOCATION + @NEW_DB + '_' + @LOGICAL_NAME + '.' + REVERSE(left(REVERSE(@PHYSICAL_NAME),CHARINDEX('.',REVERSE(@PHYSICAL_NAME))-1)) + ''',' + CHAR(10)
		DELETE FROM @TEMP_FILENAMES WHERE LOGICALNAME = @LOGICAL_NAME

	END

SET @SQL += 'FILE = 1,  NOUNLOAD,  REPLACE,  STATS = 5;' + CHAR(10)
SET @SQL += 'ALTER DATABASE ' + @NEW_DB + ' SET MULTI_USER'

PRINT @SQL + CHAR(10) + CHAR(10)

EXEC DBO.SP_EXECUTESQL @SQL

GO


--=============2. YOUR INPUT HERE  ================
DECLARE @MY_BAK_FILE NVARCHAR(MAX) = N'R:\MANUAL_BACKUP\DEV_RDS\20210517\Optimine_DWH.bak' ,
		@NEW_DB NVARCHAR(MAX) = 'AN_Optimine_DWH_PF' ,
		@NEW_LOCATION NVARCHAR(MAX) = 'S:\Data\'  --always with slash in the end
--==============================================
--Execution
EXEC dbo.BACKUP_RESTORE_TO_ANOTHER_DB @BACKUP_FILE = @MY_BAK_FILE ,  @NEW_DB = @NEW_DB, @NEW_LOCATION = @NEW_LOCATION
--================================================

--=========================
-- 3. DROPPING PROCEDURES
--=========================
IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND name = 'BACKUP_FILE_NAMES')
	DROP PROCEDURE [dbo].[BACKUP_FILE_NAMES]
GO

IF EXISTS (SELECT * FROM sys.objects WHERE type = 'P' AND name = 'BACKUP_RESTORE_TO_ANOTHER_DB')
	DROP PROCEDURE [dbo].BACKUP_RESTORE_TO_ANOTHER_DB
GO



