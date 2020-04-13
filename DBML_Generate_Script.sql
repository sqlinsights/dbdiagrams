Drop Table if exists #FK, #TableDefinitions, #Report

CREATE TABLE #Report
(
    ScriptLine NVARCHAR(max)
)



--GET ALL TABLE COLUMNS
SELECT DISTINCT T.Name as TableName, S.name as SchemaName, c.column_id, t.object_id as ColumnID, CONCAT(
               C.name,' '
              , CASE
			  WHEN T2.NAME IN
(
N'int',
N'bit',
N'smallint',
N'tinyint',
N'datetime',
N'date',
N'uniqueidentifier'
) THEN T2.name
ELSE CONCAT(T2.Name,'(',C.max_length,')')
end) TableDef
into #TableDefinitions
FROM sys.tables AS T
    JOIN sys.columns AS C
    ON C.object_id = T.object_id
    join sys.schemas S on s.schema_id = t.schema_id
    JOIN sys.types AS T2
    ON T2.user_type_id = C.user_type_id and t2.schema_id = 4


WHERE       T.is_ms_shipped = 0
    AND T2.name <> 'sysname'
ORDER BY    s.name
              ,T.name
              , C.column_id

--GENERATE ALL RELATIONSHIPS
SELECT DISTINCT
    FK.name AS ForeignKeyName
                      , S.name AS SchemaName
                      , T.name AS ForeignKeyTable
                      , SC.name AS ForeignKeyColumn
                      , rs.name as ReferenceSchema
                      , TR.name AS ReferenceTable
                      , C.name AS ReferencedColumn
                      , DB_NAME(TR.parent_object_id) DB
INTO #FK
FROM sys.tables T
    JOIN sys.foreign_keys FK
    ON T.object_id = FK.parent_object_id
    JOIN sys.foreign_key_columns FKC
    ON FKC.constraint_object_id = FK.object_id
    JOIN sys.columns SC
    ON SC.object_id = T.object_id
        AND FKC.parent_column_id = SC.column_id
    JOIN sys.tables TR
    ON TR.object_id = FKC.referenced_object_id
    JOIN sys.columns C
    ON C.object_id = TR.object_id
        AND FKC.referenced_column_id = C.column_id
    JOIN sys.schemas S
    ON S.schema_id = T.schema_id
    join sys.schemas RS on rs.schema_id = TR.schema_id


SET NOCOUNT ON
DECLARE @Table NVARCHAR(500)
DECLARE DatabaseTables CURSOR FOR (SELECT DISTINCT Concat(s.name,'.',t.name)
from sys.tables T join sys.schemas S on s.schema_id = t.schema_id
where t.is_ms_shipped = 0)
OPEN DatabaseTables
FETCH NEXT FROM DatabaseTables INTO @Table
WHILE @@FETCH_STATUS = 0
begin

    INSERT INTO #Report
        (ScriptLine)
    SELECT DISTINCT
        CONCAT(Cast('Table ' as nvarchar(max)), '"',s.name,'.', t.name,'"', ' {', CHAR(13) + CHAR(10), Replace(TT.x,',',CHAR(13) + CHAR(10)), CHAR(13) + CHAR(10), '}')
    FROM sys.tables T
        join sys.schemas S on s.schema_id = t.schema_id and t.is_ms_shipped = 0
        cross APPLY (
            SELECT distinct Concat(',',TD.TableDef)
        FROM #TableDefinitions TD
        WHERE Concat(TD.SchemaName,'.',TD.TableName) = @Table
        for xml path ('')
        ) TT (x)
    WHERE            Concat(s.name,'.',t.name) = @Table

    INSERT INTO #Report
        (ScriptLine)
    SELECT DISTINCT
        CONCAT('ref: ', '"',FK.SchemaName,'.',FK.ForeignKeyTable, '".', FK.ForeignKeyColumn, ' > ', '"',FK.ReferenceSchema,'.',FK.ReferenceTable, '".' ,ReferencedColumn)
    FROM #FK FK
    WHERE            Concat(SchemaName,'.',ForeignKeyTable) = @Table

    FETCH NEXT FROM DatabaseTables INTO @Table
END
CLOSE DatabaseTables
DEALLOCATE DatabaseTables


DECLARE @TablesDef NVARCHAR(Max)
        ,@Input NVARCHAR(max)
DECLARE OutCursor CURSOR FOR (SELECT ScriptLine
FROM #Report
where ScriptLine not like 'ref%')
OPEN OutCursor

FETCH NEXT FROM OutCursor INTO @Input
WHILE @@FETCH_STATUS = 0
BEGIN
    set @TablesDef = Concat(@TablesDef,CHAR(13),@Input)
    FETCH NEXT FROM OutCursor INTO @Input
end
CLOSE outCursor
DEALLOCATE OutCursor



DECLARE  @FKInput NVARCHAR(max)
DECLARE FKCursor CURSOR FOR (SELECT ScriptLine
FROM #Report
where ScriptLine  like 'ref%')
OPEN FKCursor

FETCH NEXT FROM FKCursor INTO @FKInput
WHILE @@FETCH_STATUS = 0
BEGIN
    set @TablesDef = Concat(@TablesDef,CHAR(13),@FKInput)
    FETCH NEXT FROM FKCursor INTO @FKInput
end
CLOSE FKCursor
DEALLOCATE FKCursor
select Convert(XML, '<INSTRUCTIONS>Replace encoded &gt; for greater than symbol. Copy output node and paste into https://dbdiagram.io</INSTRUCTIONS><OUTPUT>'+@TablesDef+'</OUTPUT>')


