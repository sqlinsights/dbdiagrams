DROP TABLE IF EXISTS #FK, #TableDefinitions, #Report

CREATE TABLE #Report
(
    ScriptLine NVARCHAR(max)
)

--GET ALL TABLE COLUMNS
SELECT DISTINCT 
     T.Name         AS TableName
    ,S.name         AS SchemaName
    ,c.column_id    
    ,t.object_id    AS ColumnID
    ,CONCAT(C.name, ' ', CASE WHEN T2.NAME IN (
                                                N'int'
                                                ,N'bit'
                                                ,N'smallint'
                                                ,N'tinyint'
                                                ,N'datetime'
                                                ,N'date'
                                                ,N'uniqueidentifier'
                                            ) THEN T2.name
                            ELSE CONCAT(T2.Name,'(',C.max_length,')')
                        END) AS TableDef
    ,CASE WHEN kc.unique_index_id IS NULL THEN '' ELSE '[pk]' END AS PrimaryKey
INTO #TableDefinitions
FROM sys.tables AS T
    INNER JOIN sys.columns AS C
        ON C.object_id = T.object_id
    INNER JOIN sys.schemas AS S 
        ON s.schema_id = t.schema_id
    INNER JOIN sys.types AS T2
        ON T2.user_type_id = C.user_type_id 
        AND t2.schema_id = 4
    LEFT JOIN sys.index_columns AS ic
        ON c.object_id = ic.object_id
        AND c.column_id = ic.column_id
    LEFT JOIN sys.key_constraints AS kc
        ON ic.object_id = kc.parent_object_id
        AND ic.index_id = kc.unique_index_id

WHERE(
    (T.is_ms_shipped = 0)
    AND
    (T2.name <> 'sysname')
)
ORDER BY    
     s.name
    ,T.name
    ,C.column_id

--GENERATE ALL RELATIONSHIPS
SELECT DISTINCT
     FK.name    AS ForeignKeyName
    ,S.name     AS SchemaName
    ,T.name     AS ForeignKeyTable
    ,SC.name    AS ForeignKeyColumn
    ,rs.name    AS ReferenceSchema
    ,TR.name    AS ReferenceTable
    ,C.name     AS ReferencedColumn
    ,DB_NAME(TR.parent_object_id) AS DB
INTO #FK
FROM sys.tables T
    INNER JOIN sys.foreign_keys AS FK
        ON T.object_id = FK.parent_object_id
    INNER JOIN sys.foreign_key_columns AS FKC
        ON FKC.constraint_object_id = FK.object_id
    INNER JOIN sys.columns AS SC
        ON SC.object_id = T.object_id
        AND FKC.parent_column_id = SC.column_id
    INNER JOIN sys.tables AS TR
        ON TR.object_id = FKC.referenced_object_id
    INNER JOIN sys.columns AS C
        ON C.object_id = TR.object_id
        AND FKC.referenced_column_id = C.column_id
    INNER JOIN sys.schemas AS S
        ON S.schema_id = T.schema_id
    INNER JOIN sys.schemas AS RS 
        ON rs.schema_id = TR.schema_id


SET NOCOUNT ON

DECLARE @Table NVARCHAR(500)
DECLARE DatabaseTables CURSOR FOR (
    SELECT DISTINCT CONCAT(s.name,'.',t.name)
    FROM sys.tables AS T 
        INNER JOIN sys.schemas AS S 
            ON s.schema_id = t.schema_id
    WHERE t.is_ms_shipped = 0)

OPEN DatabaseTables
FETCH NEXT FROM DatabaseTables INTO @Table
WHILE @@FETCH_STATUS = 0
BEGIN

    INSERT INTO #Report (ScriptLine)
    SELECT DISTINCT
        CONCAT(Cast('Table ' as nvarchar(max)), '"',s.name,'.', t.name,'"', ' {', CHAR(13) + CHAR(10), REPLACE(TT.x,',',CHAR(13) + CHAR(10)), CHAR(13) + CHAR(10), '}')
    FROM sys.tables T
        INNER JOIN sys.schemas S on s.schema_id = t.schema_id and t.is_ms_shipped = 0
        CROSS APPLY (
            SELECT DISTINCT CONCAT(',',TD.TableDef, ' ', TD.PrimaryKey)
            FROM #TableDefinitions TD
            WHERE CONCAT(TD.SchemaName,'.',TD.TableName) = @Table
            FOR XML PATH ('')
        ) TT (x)
    WHERE(
        CONCAT(s.name,'.',t.name) = @Table
    )

    INSERT INTO #Report (ScriptLine)
    SELECT DISTINCT
        CONCAT('ref: ', '"',FK.SchemaName,'.',FK.ForeignKeyTable, '".', FK.ForeignKeyColumn, ' > ', '"',FK.ReferenceSchema,'.',FK.ReferenceTable, '".' ,ReferencedColumn)
    FROM #FK AS FK
    WHERE(
        CONCAT(SchemaName,'.',ForeignKeyTable) = @Table
    )

    FETCH NEXT FROM DatabaseTables INTO @Table

END
CLOSE DatabaseTables
DEALLOCATE DatabaseTables


DECLARE @TablesDef  NVARCHAR(Max)
DECLARE @Input      NVARCHAR(max)
DECLARE OutCursor   CURSOR FOR (
    SELECT ScriptLine
    FROM #Report
    WHERE ScriptLine NOT LIKE 'ref%')

OPEN OutCursor
FETCH NEXT FROM OutCursor INTO @Input
WHILE @@FETCH_STATUS = 0
BEGIN

    SET @TablesDef = Concat(@TablesDef,CHAR(13),@Input)
    FETCH NEXT FROM OutCursor INTO @Input

END
CLOSE outCursor
DEALLOCATE OutCursor


DECLARE @FKInput NVARCHAR(max)
DECLARE FKCursor CURSOR FOR (
    SELECT ScriptLine
    FROM #Report
    WHERE ScriptLine LIKE 'ref%')

OPEN FKCursor
FETCH NEXT FROM FKCursor INTO @FKInput
WHILE @@FETCH_STATUS = 0
BEGIN

    SET @TablesDef = Concat(@TablesDef,CHAR(13),@FKInput)
    FETCH NEXT FROM FKCursor INTO @FKInput

END
CLOSE FKCursor
DEALLOCATE FKCursor

SELECT CONVERT(XML, '<INSTRUCTIONS>Replace encoded &gt; for greater than symbol. Copy output node and paste into https://dbdiagram.io</INSTRUCTIONS><OUTPUT>'+@TablesDef+'</OUTPUT>')
