if object_id('tempdb..##errors') is not null drop table ##errors
create table ##errors ( script_name nvarchar(150), error_description nvarchar(max) )
-- скрипт проверяет, что:
--		происходит обновление с нужной версии
--		установлен правильный уровень совместимости БД
--		версию sql server

-- ================= таблица соответствия версий =================
declare @versionsCompatibility as table
(
	versionFrom varchar(25),		-- версия, с которой разрешён переход на versionTo
	versionTo varchar(25)			-- версия, на которую разрешён переход с versionFrom
)

insert into @versionsCompatibility values ('9.2.20.31','15.0.0') 
insert into @versionsCompatibility values ('9.2.20.32','15.0.0') 
insert into @versionsCompatibility values ('9.2.22.0','15.0.0') 
insert into @versionsCompatibility values ('9.2.23.0','15.0.0') 
insert into @versionsCompatibility values ('11.3.31','15.0.0') 
insert into @versionsCompatibility values ('11.3.32','15.0.0') 
insert into @versionsCompatibility values ('11.4.0','15.0.0') 
insert into @versionsCompatibility values ('11.5.0','15.0.0') 
insert into @versionsCompatibility values ('15.0.0','15.0.1') 
insert into @versionsCompatibility values ('15.0.0','15.1.0') 
insert into @versionsCompatibility values ('15.0.1','15.1.0') 
insert into @versionsCompatibility values ('9.2.20.31','15.2.0') 
insert into @versionsCompatibility values ('9.2.20.32','15.2.0') 
insert into @versionsCompatibility values ('9.2.22.0','15.2.0') 
insert into @versionsCompatibility values ('9.2.23.0','15.2.0') 
insert into @versionsCompatibility values ('11.3.31','15.2.0') 
insert into @versionsCompatibility values ('11.3.32','15.2.0') 
insert into @versionsCompatibility values ('11.4.0','15.2.0') 
insert into @versionsCompatibility values ('11.5.0','15.2.0') 
insert into @versionsCompatibility values ('15.0.0','15.2.0') 
insert into @versionsCompatibility values ('15.0.1','15.2.0') 
insert into @versionsCompatibility values ('15.1.0','15.2.0') 
insert into @versionsCompatibility values ('9.2.20.31','15.3.0') 
insert into @versionsCompatibility values ('9.2.20.32','15.3.0') 
insert into @versionsCompatibility values ('9.2.22.0','15.3.0') 
insert into @versionsCompatibility values ('9.2.23.0','15.3.0') 
insert into @versionsCompatibility values ('11.3.31','15.3.0') 
insert into @versionsCompatibility values ('11.3.32','15.3.0') 
insert into @versionsCompatibility values ('11.4.0','15.3.0') 
insert into @versionsCompatibility values ('11.5.0','15.3.0') 
insert into @versionsCompatibility values ('15.0.0','15.3.0') 
insert into @versionsCompatibility values ('15.0.1','15.3.0') 
insert into @versionsCompatibility values ('15.1.0','15.3.0') 
insert into @versionsCompatibility values ('15.2.0','15.3.0') 


-- =====================  1. скрипт для проверки релиза МТ ===================== 
-- переменная, в которую билд скриптом будет проставлена версия ПО, на которую обновляемся
-- ожидаемый формат: версия.релиз.сп
declare @newVersion as varchar(20), @curVersion as varchar(20)
set @newVersion = '15.3.0'
select top 1 @curVersion = st_version from setting

if @newVersion <> @curVersion and not exists (select * from @versionsCompatibility 
				where versionFrom = @curVersion
					and versionTo = @newVersion)
begin
	declare @fromVersions as varchar(max)
	set @fromVersions = null

	select @fromVersions = coalesce(@fromVersions + ', ', '') + rtrim(versionFrom)
	from @versionsCompatibility 
	where versionTo = @newVersion

	declare @errMessage as nvarchar(max)
	set @errMessage = 'Попытка обновления с версии БД ' + rtrim(@curVersion) + ' на версию ' + rtrim(@newVersion) + ' неуспешна. '
	
	if len(@fromVersions) > 0
	begin
		set @errMessage = @errMessage + 'Доступно обновление только со следующих версий БД: ' + @fromVersions
	end
	else
	begin
		set @errMessage = @errMessage + 'Нет разрешённых версий, с которых можно обновиться на текущую версию БД.'
	end

	insert into ##errors values ('!checkVersion.sql', @errMessage)
end

-- =====================  2. скрипт для проверки совместимости БД ===================== --
DECLARE @Message varchar (500)
DECLARE @CurrentVer nvarchar(128)
DECLARE @SUSER_NAME nvarchar(128) = (SELECT SUSER_NAME())
DECLARE @HOST_NAME nvarchar(128) = (SELECT HOST_NAME())	

--*--непосредственно обработка и сравнение --*--
SET @CurrentVer = (SELECT compatibility_level FROM sys.databases WHERE name = (SELECT DB_NAME()))
IF (@CurrentVer < 100)
BEGIN
	SET @Message = 'Режим совместимости базы данных - ' + (SELECT DB_NAME()) + ' указан (' + @CurrentVer + '), для корректного обновления и работы ПК "Мастер-Тур" нужен режим совместимости 2008 (100) и выше.'
	insert into ##errors values ('!checkVersion.sql', @Message)
END

-- =====================  3. скрипт для проверки версии SQL-сервера. Маска версии: [мажорная версия](2 символа).[минорная версия](2 символа).[релизная версия](4 символа) ===================== 
DECLARE @CurrentSQLVersion nvarchar(128)
DECLARE @MinimalSQLVersion nvarchar(128)
DECLARE @curver varchar(20) = null
DECLARE @minver varchar(20) = null
--*--непосредственно обработка и сравнение версий SQL --*--
SET @CurrentSQLVersion = CAST(serverproperty('ProductVersion') AS nvarchar)
SET @MinimalSQLVersion = '10.50.1600.0'
	
---------------------------------------
IF(@CurrentSQLVersion != @MinimalSQLVersion)
BEGIN
	WHILE LEN(@CurrentSQLVersion) > 0
	BEGIN               
		WHILE LEN(@MinimalSQLVersion) > 0
		BEGIN
			IF PATINDEX('%.%',@CurrentSQLVersion) > 0
			BEGIN
				SET @curver = SUBSTRING(@CurrentSQLVersion, 0, PATINDEX('%.%',@CurrentSQLVersion))
				SET @CurrentSQLVersion = SUBSTRING(@CurrentSQLVersion, LEN(@curver + '.') + 1, LEN(@CurrentSQLVersion))
				SET @minver = SUBSTRING(@MinimalSQLVersion, 0, PATINDEX('%.%',@MinimalSQLVersion))
				SET @MinimalSQLVersion = SUBSTRING(@MinimalSQLVersion, LEN(@minver + '.') + 1, LEN(@MinimalSQLVersion))
				--------в мажорных, минорных и релиз версиях смотрим любое отклонение от 0---------- 
				IF(convert(int, @curver) - convert(int, @minver)) < 0
				BEGIN
						-- обнуляем и выходим из цикла, т.к. уже ошибка
						SET @Message = 'Используемая версия MS SQL Server — ' + CAST(serverproperty('ProductVersion') AS nvarchar)
						+ ', для корректного обновления и работы ПК "Мастер-Тур" нужна версия не ниже MS SQL Server 2008 R2 (10.50.1600.0).'
						insert into ##errors values ('!checkVersion.sql', @Message)
				END   
				ELSE IF(convert(int, @curver) - convert(int, @minver)) > 0
				BEGIN
						SET @CurrentSQLVersion = NULL
						SET @MinimalSQLVersion = NULL
				END
			END
			ELSE IF (PATINDEX('%.%',@CurrentSQLVersion) < PATINDEX('%.%',@MinimalSQLVersion))
			BEGIN
				SET @curver = @CurrentSQLVersion
				SET @minver = SUBSTRING(@MinimalSQLVersion, 0, PATINDEX('%.%',@MinimalSQLVersion))
				IF(convert(int, @curver) - convert(int, @minver)) < 0
				BEGIN
					-- обнуляем и выходим из цикла, т.к. уже ошибка
					SET @Message = 'Используемая версия MS SQL Server — ' + CAST(serverproperty('ProductVersion') AS nvarchar)
						+ ', для корректного обновления и работы ПК "Мастер-Тур" нужна версия не ниже MS SQL Server 2008 R2 (10.50.1600.0).'
					insert into ##errors values ('!checkVersion.sql', @Message)
				END
	                                            
				-- обнуляем
				SET @CurrentSQLVersion = NULL
				SET @MinimalSQLVersion = NULL     
			END
			ELSE
			BEGIN
				-- обнуляем, т.к. на этом шаге уже идет проверка SP, а нам достаточно до релиза
				SET @CurrentSQLVersion = NULL
				SET @MinimalSQLVersion = NULL    
			END
		END
	END
END

print '############ begin of file ListNvarcharValue.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists (select * from sys.table_types where name = ''ListNvarcharValue'')
begin

	CREATE TYPE [dbo].[ListNvarcharValue] AS TABLE(
		[value] [nvarchar](128) NULL
	)

end
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('ListNvarcharValue.sql', error_message())
END CATCH
end

print '############ end of file ListNvarcharValue.sql ################'

print '############ begin of file RecreateDependentObjects.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists(select top 1 1 from sys.objects where name = ''RecreateDependentObjects'' and type = ''P'')
	drop procedure RecreateDependentObjects
')
END TRY
BEGIN CATCH
insert into ##errors values ('RecreateDependentObjects.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

create procedure RecreateDependentObjects
-- выполняет указанный скрипт после удаления и до создания зависимых от колонки @ColumnName объектов
-- сейчас в качестве зависимых объектов поддерживаются только некластеризованные и кластеризованные индексы
--<VERSION>9.2.21</VERSION>
--<DATE>2014-02-28</DATE>
(
	@TableName sysname,				-- имя таблицы, колонка которой удаляется
	@ColumnNames ListNvarcharValue readonly,			-- список имен колонок, от которых будут искаться зависимые объекты
	@CustomScript nvarchar(max),	-- скрипт, выполняемый между созданием и удалением зависимых объектов
	@recreateWithoutColumn bit = 0	-- флаг, указывающий, что в зависимые объекты надо пересоздавать без переданной колонки
)
as
begin
	-- ANSI_PADDING OFF setting is incompatible with xml data types, used in this stored procedure
	SET ANSI_PADDING ON;

	declare @errorMessage nvarchar(max)

	-- check arguments
	if not exists (select top 1 1 from sys.tables where name = @TableName)
	begin
		set @errorMessage = ''Table '' + @TableName + '' was not found in database.''
		RAISERROR(@errorMessage, 16, 1)
		return
	end

	if exists (select top 1 1 
				from @ColumnNames 
				where value not in (select col.name 
							from sys.columns col 
							left join sys.tables tab on col.object_id = tab.object_id
							where tab.name = @TableName)
				)
	begin
		select @errorMessage = coalesce(@errorMessage + '', '', '''') + value 
		from @ColumnNames 
		where value not in (select col.name 
							from sys.columns col 
							left join sys.tables tab on col.object_id = tab.object_id
							where tab.name = @TableName)

		set @errorMessage = ''Next columns was not found in table '' + @TableName + '': '' + @errorMessage
		RAISERROR(@errorMessage, 16, 1)
		return
	end

	-- признак, что пересоздание ссылающихся на колонку объектов прошло успешно
	declare @updateReferencesComplete as bit
	declare @errmsg as nvarchar(max)

	-- обработка индексов
	declare @ixName sysname
	declare @ixType tinyint
	declare @ixIsPrimaryKey bit

	declare @totalSql as nvarchar(max)
	declare @dropIndexSql as nvarchar(max)
	declare @createIndexSql as nvarchar(max)
	set @dropIndexSql = ''''
	set @createIndexSql = ''''

	declare indexesCursor cursor for
	select ix.name, ix.type, is_primary_key
	from sys.tables tab
	left join sys.indexes ix on ix.object_id = tab.object_id
	where tab.name = @TableName
		and exists (select top 1 1 
					from sys.index_columns ic
					left join sys.columns col on col.column_id = ic.column_id and col.object_id = tab.object_id
					where ic.index_id = ix.index_id 
						and ic.object_id = tab.object_id
						and col.name in (select value from @ColumnNames)
					)

	open indexesCursor

	-- удаление статистики по текущему столбцу. Удалим только пользовательскую статистику, т.к. 
	-- автоматически создаваемая при создании индекса статистика удаляется тоже автоматически
	declare @statisticsName nvarchar(max), @statColumnName nvarchar(max), @statName nvarchar(max)
	declare statisticsCursor cursor for
		select distinct OBJECT_NAME(c.object_id) + ''.'' + s.name, c.name, s.name
			from sys.stats s with(nolock)
			INNER JOIN sys.stats_columns sc with(nolock) ON sc.stats_id = s.stats_id
			INNER JOIN sys.columns c with(nolock) ON c.column_id = sc.column_id
			INNER JOIN sys.tables t with(nolock) ON c.object_id = t.object_id
			WHERE c.name in (select value from @ColumnNames)
			and OBJECT_NAME(c.object_id) = @TableName
			and OBJECT_NAME(sc.object_id) = @TableName
			and OBJECT_NAME(s.object_id) = @TableName
			and t.[type] = ''U''
			and s.user_created = 1
	open statisticsCursor
	fetch next from statisticsCursor into @statisticsName, @statColumnName, @statName
		while @@FETCH_STATUS = 0
		begin
			declare @dropStat nvarchar(max)
			set @dropStat = CHAR(10) + CHAR(13) + ''IF EXISTS (select top 1 1 from sys.stats s with(nolock)
				INNER JOIN sys.stats_columns sc with(nolock) ON sc.stats_id = s.stats_id
				INNER JOIN sys.columns c with(nolock) ON c.column_id = sc.column_id
				INNER JOIN sys.tables t with(nolock) ON c.object_id = t.object_id
				WHERE c.name = '''''' + @statColumnName + ''''''
				and OBJECT_NAME(c.object_id) = '''''' + @TableName + ''''''
				and OBJECT_NAME(sc.object_id) = '''''' + @TableName + ''''''
				and OBJECT_NAME(s.object_id) = '''''' + @TableName + ''''''
				and s.name = '''''' + @statName + ''''''
				and t.[type] = ''''U'''') DROP STATISTICS '' + @statisticsName
			set @dropIndexSql = @dropIndexSql + @dropStat
			
			print @TableName
			print @statColumnName
			print @statName
			
			fetch next from statisticsCursor into @statisticsName, @statColumnName, @statName
		end
	close statisticsCursor
	deallocate statisticsCursor
	
	begin try
		fetch next from indexesCursor into @ixName, @ixType, @ixIsPrimaryKey
		while @@FETCH_STATUS = 0
		begin
			if @ixType <> 2 and @ixType <> 1
			begin
				select @errorMessage = coalesce(@errorMessage + '', '', '''') + value from @ColumnNames 

				set @errorMessage = ''Not supported index type is dependent on specified columns '' + @errorMessage + ''
				This stored procedure supports only nonclustered and clustered indexes recreation! Not supported index name: '' 
					+ @ixName + '' on table: '' + @TableName
				RAISERROR(@errorMessage, 16, 1)
			end

			if @ixIsPrimaryKey = 1
			begin
				set @errorMessage = ''Cannot recreate index name: '' + @ixName + '' on table: '' + @TableName + ''. It is being used for PRIMARY KEY constraint enforcement.''
				RAISERROR(@errorMessage, 16, 1)
			end

			declare @indexColumns nvarchar(max)
			declare @includedColumns nvarchar(max)

			set @indexColumns = ''''
			set @indexColumns = stuff((select '','' + col.name + 
					case
						when ic.is_descending_key = 1 then '' desc''
						else '' asc''
					end
					from sys.tables tab
					left join sys.indexes ix on ix.object_id = tab.object_id
					left join sys.index_columns ic on ic.object_id = tab.object_id and ic.index_id = ix.index_id
					left join sys.columns col on col.column_id = ic.column_id and col.object_id = tab.object_id
					where ic.index_id = ix.index_id 
						and ic.object_id = tab.object_id
						and ic.is_included_column = 0
						and ((@recreateWithoutColumn = 1 and col.name not in (select value value from @ColumnNames)) or @recreateWithoutColumn = 0)
						and tab.name = @TableName
						and ix.name = @ixName
					for xml path(''''), type
					).value(''.'', ''varchar(max)''),1,1,'''')

			set @includedColumns = stuff((select '','' + col.name
					from sys.tables tab
					left join sys.indexes ix on ix.object_id = tab.object_id
					left join sys.index_columns ic on ic.object_id = tab.object_id and ic.index_id = ix.index_id
					left join sys.columns col on col.column_id = ic.column_id and col.object_id = tab.object_id
					where ic.index_id = ix.index_id 
						and ic.object_id = tab.object_id
						and ic.is_included_column = 1
						and ((@recreateWithoutColumn = 1 and col.name not in (select value value from @ColumnNames)) or @recreateWithoutColumn = 0)
						and tab.name = @TableName
						and ix.name = @ixName
					for xml path(''''), type
					).value(''.'', ''varchar(max)''),1,1,'''')

			set @dropIndexSql = @dropIndexSql + ''
				drop index [@ixName] on [@TableName]''

			if @indexColumns is not null
			begin
				set @createIndexSql = @createIndexSql + 
				''
				create @indexType index [@ixName] on [@TableName]
				(
					@indexColumns
				)''

				if @includedColumns is not null
				begin
					set @createIndexSql = @createIndexSql + 
					''
					include
					(
						@includedColumns
					)
					''
					set @createIndexSql = replace(@createIndexSql, ''@includedColumns'', isnull(@includedColumns, ''''))
				end
				set @createIndexSql = @createIndexSql + 
				''
				WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, 
					ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 70) ON [PRIMARY]
				''
				set @createIndexSql = replace(@createIndexSql, ''@indexColumns'', @indexColumns)
				set @createIndexSql = replace(@createIndexSql, ''@indexType'', case when @ixType = 2 then ''nonclustered'' when @ixType = 1 then ''clustered'' end)
			end

			set @createIndexSql = replace(@createIndexSql, ''@ixName'', @ixName)
			set @createIndexSql = replace(@createIndexSql, ''@TableName'', @TableName)
			set @dropIndexSql = replace(@dropIndexSql, ''@ixName'', @ixName)
			set @dropIndexSql = replace(@dropIndexSql, ''@TableName'', @TableName)

			fetch next from indexesCursor into @ixName, @ixType, @ixIsPrimaryKey
		end
	end try
	begin catch 
		set @errmsg = error_message()
		set @updateReferencesComplete = 0
	end catch

	close indexesCursor
	deallocate indexesCursor

	if @updateReferencesComplete = 0
	begin
		RAISERROR(@errmsg, 16, 1)
		return
	end

	-- execute custom script between drop and recreate dependent objects
	set @totalSql = ''
	begin transaction dropAndCreate
	'' + @dropIndexSql + ''
	'' + @customScript + ''
	'' + @createIndexSql + ''
	commit transaction dropAndCreate
	''

	exec sp_executesql @totalSql
end

')
END TRY
BEGIN CATCH
insert into ##errors values ('RecreateDependentObjects.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on RecreateDependentObjects to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('RecreateDependentObjects.sql', error_message())
END CATCH
end

print '############ end of file RecreateDependentObjects.sql ################'

print '############ begin of file GeoCustomPointClass.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- 21.01.2015 Создание таблицы с классами кастомных точек

if not exists(select 1 from systables where name = ''GeoCustomPointClass'')

begin

create table [dbo].[GeoCustomPointClass](

	[GCPC_Id] [int] identity(1,1) not null,

	[GCPC_Name] [nvarchar](255) not null, -- название класса (порт/ж-д вокзал и т.д.)

	[GCPC_NameLat] [nvarchar](255) null -- англоязычный вариант

constraint [PK_GeoCustomPointClass] primary key clustered 

(

	[GCPC_Id] asc

)with (pad_index = off, STATISTICS_NORECOMPUTE  = off, ignore_dup_key = off, allow_row_locks = on, allow_page_locks = on) on [primary]

) on [primary]

grant select, insert, delete, update on [dbo].[GeoCustomPointClass] to public

end

')
END TRY
BEGIN CATCH
insert into ##errors values ('GeoCustomPointClass.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('GeoCustomPointClass.sql', error_message())
END CATCH
end

print '############ end of file GeoCustomPointClass.sql ################'

print '############ begin of file GeoCustomPoint.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- 22.01.2015 Создание таблицы с кастомными точками

if not exists(select 1 from systables where name = ''GeoCustomPoint'')

begin

create table [dbo].[GeoCustomPoint](

	[GCP_Id] [int] identity(1,1) not null,

	[GCP_GCPCId] [int] not null, -- ключ на класс кастомной точки

	[GCP_Name] [nvarchar](255) not null, -- название кастомной точки (например Финляндский вокзал)

	[GCP_NameLat] [nvarchar](255) null, -- англоязычный вариант

	[GCP_CnKey] [int] not null, -- ключ страны точки

	[GCP_CtKey] [int] not null -- ключ города точки

constraint [PK_GeoCustomPoint] primary key clustered 

(

	[GCP_Id] asc

)with (pad_index = off, STATISTICS_NORECOMPUTE  = off, ignore_dup_key = off, allow_row_locks = on, allow_page_locks = on) on [primary]

) on [primary]

grant select, insert, delete, update on [dbo].[GeoCustomPoint] to public



ALTER TABLE [dbo].[GeoCustomPoint] ADD CONSTRAINT [FK_GeoCustomPointClass_Id] 

FOREIGN KEY([GCP_GCPCId]) REFERENCES [dbo].[GeoCustomPointClass] ([GCPC_Id]) ON DELETE CASCADE



ALTER TABLE [dbo].[GeoCustomPoint] ADD CONSTRAINT [FK_Tbl_Country_Key] 

FOREIGN KEY([GCP_CnKey]) REFERENCES [dbo].[Tbl_Country] ([CN_Key]) ON DELETE NO ACTION



ALTER TABLE [dbo].[GeoCustomPoint] ADD CONSTRAINT [FK_CityDictionary_Key] 

FOREIGN KEY([GCP_CtKey]) REFERENCES [dbo].[CityDictionary] ([CT_Key]) ON DELETE CASCADE



end

')
END TRY
BEGIN CATCH
insert into ##errors values ('GeoCustomPoint.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('GeoCustomPoint.sql', error_message())
END CATCH
end

print '############ end of file GeoCustomPoint.sql ################'

print '############ begin of file GeoServicePointsLink.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- 27.03.2015 Создание таблицы связей услуг с точками

if not exists(select 1 from systables where name = ''GeoServicePointsLink'')

begin

create table [dbo].[GeoServicePointsLink](

	[GSPL_Id] [int] identity(1,1) not null,

	[GSPL_SvKey] [int] not null, -- ключ класса услуги

	[GSPL_ServiceId] [int] not null, -- ключ услуги в соответсвующей таблице (например transfer)

	[GSPL_PointFromType] [int] not null, -- тип точки отправления ( определяет таблицу аэропорт/ отель/ кастомная точка)

	[GSPL_PointFromId] [int] not null, -- ключ точки отправления в соотв. таблице

	[GSPL_PointToType] [int] not null, -- тип точки прибытия ( определяет таблицу аэропорт/ отель/ кастомная точка)

	[GSPL_PointToId] [int] not null -- ключ точки прибытия в соотв. таблице

constraint [PK_GeoServicePointsLink] primary key clustered 

( 

	[GSPL_Id] asc

)with (pad_index = off, STATISTICS_NORECOMPUTE  = off, ignore_dup_key = off, allow_row_locks = on, allow_page_locks = on) on [primary]

) on [primary]

grant select, insert, delete, update on [dbo].[GeoServicePointsLink] to public

end

')
END TRY
BEGIN CATCH
insert into ##errors values ('GeoServicePointsLink.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



if not exists (select * from sys.foreign_keys fk

	join sys.tables tab on fk.parent_object_id = tab.object_id

	where fk.name = ''FK_Service_Key'' 

		and tab.name = ''GeoServicePointsLink'')

begin

	ALTER TABLE [dbo].[GeoServicePointsLink] ADD CONSTRAINT [FK_Service_Key] 

	FOREIGN KEY([GSPL_SvKey]) REFERENCES [dbo].[Service] ([SV_Key]) ON DELETE CASCADE

end

')
END TRY
BEGIN CATCH
insert into ##errors values ('GeoServicePointsLink.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



IF  EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N''[dbo].[GeoServicePointsLink]'') AND name = N''UC_GeoServicePointsLink_SvKey_ServiceId'')

ALTER TABLE [dbo].[GeoServicePointsLink] DROP CONSTRAINT [UC_GeoServicePointsLink_SvKey_ServiceId]



')
END TRY
BEGIN CATCH
insert into ##errors values ('GeoServicePointsLink.sql', error_message())
END CATCH
end

print '############ end of file GeoServicePointsLink.sql ################'

print '############ begin of file ToursSearch.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- 18.06.2014 Создание таблицы поиска туров.

if not exists (select 1 from systables where name = ''ToursSearch'')

begin

create table [dbo].[ToursSearch](

	[TS_Id] [int] identity(100000000,1) not null,

	[TS_Name] [nvarchar](128) not null, 			--название

	[TS_CTDepartureKeys] [nvarchar](max) not null, 	--городa прибытия

	[TS_CTKeys] [nvarchar](max) not null,			--города отправления

	[TS_TPKeys] [nvarchar](max) not null,			--типы тура

	[TS_Status] [int] not null,						--статус

	[TS_IsDeleted] [bit] not null,

	TS_CNDepartureKeys NVARCHAR(MAX) NOT NULL default '''',

	TS_CNKeys NVARCHAR(MAX) NOT NULL default ''''

constraint [PK_ToursSearch] primary key clustered 

(

	[TS_Id] asc

)with (pad_index = off, STATISTICS_NORECOMPUTE  = off, ignore_dup_key = off, allow_row_locks = on, allow_page_locks = on) on [primary]

) on [primary]

grant select, insert, delete, update on dbo.ToursSearch to public

end

')
END TRY
BEGIN CATCH
insert into ##errors values ('ToursSearch.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



IF NOT EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''TS_CNDepartureKeys'' and id = object_id(N''[dbo].[ToursSearch]''))

	ALTER TABLE [dbo].ToursSearch ADD TS_CNDepartureKeys NVARCHAR(MAX) NOT NULL default ''''

	

')
END TRY
BEGIN CATCH
insert into ##errors values ('ToursSearch.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



IF NOT EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''TS_CNKeys'' and id = object_id(N''[dbo].[ToursSearch]''))

	ALTER TABLE [dbo].ToursSearch ADD TS_CNKeys NVARCHAR(MAX) NOT NULL default ''''

	

')
END TRY
BEGIN CATCH
insert into ##errors values ('ToursSearch.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('ToursSearch.sql', error_message())
END CATCH
end

print '############ end of file ToursSearch.sql ################'

print '############ begin of file TourPrograms.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- 18.06.2014 Создание таблицы с настройками тура

if not exists(select 1 from systables where name = ''TourPrograms'')

begin

create table [dbo].[TourPrograms](

	[TP_Id] [int] not null,

	[TP_Settings] [nvarchar](max) not null, -- настройки тура

	TP_XmlSettings [xml]

constraint [PK_TourPrograms] primary key clustered 

(

	[TP_Id] asc

)with (pad_index = off, STATISTICS_NORECOMPUTE  = off, ignore_dup_key = off, allow_row_locks = on, allow_page_locks = on) on [primary]

) on [primary]

grant select, insert, delete, update on dbo.TourPrograms to public



ALTER TABLE [dbo].[TourPrograms] ADD CONSTRAINT [FK_ToursSearch_TourSettings] 

FOREIGN KEY([TP_Id]) REFERENCES [dbo].[ToursSearch] ([TS_Id]) ON DELETE CASCADE



end

')
END TRY
BEGIN CATCH
insert into ##errors values ('TourPrograms.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



if not exists (select 1 from dbo.syscolumns where name = ''TP_XmlSettings'' and id = object_id(N''[dbo].[TourPrograms]''))

	ALTER TABLE [dbo].TourPrograms ADD TP_XmlSettings xml

')
END TRY
BEGIN CATCH
insert into ##errors values ('TourPrograms.sql', error_message())
END CATCH
end

print '############ end of file TourPrograms.sql ################'

print '############ begin of file TourMarginDurations.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- Создание таблицы с продолжительностями для наценок

if not exists(select 1 from systables where name = ''TourMarginDurations'')

begin

create table [dbo].[TourMarginDurations](

	[TD_Key] [int] identity(1,1) not null,

	[TD_TMKEY] [int] not null, 
	
	[TD_Value] [int] not null

constraint [PK_TourMarginDurations] primary key clustered 

(

	[TD_Key] asc

)with (pad_index = off, STATISTICS_NORECOMPUTE  = off, ignore_dup_key = off, allow_row_locks = on, allow_page_locks = on) on [primary]

) on [primary]

grant select, insert, delete, update on [dbo].[TourMarginDurations] to public


ALTER TABLE [dbo].[TourMarginDurations] ADD CONSTRAINT [FK_TourMarginDurations_TURMARGIN] 

FOREIGN KEY([TD_TMKEY]) REFERENCES [dbo].[TURMARGIN] ([TM_Key]) ON DELETE CASCADE


end

')
END TRY
BEGIN CATCH
insert into ##errors values ('TourMarginDurations.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('TourMarginDurations.sql', error_message())
END CATCH
end

print '############ end of file TourMarginDurations.sql ################'

print '############ begin of file Specials.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[Specials]'') AND type in (N''U''))
BEGIN
    CREATE TABLE [dbo].[Specials](
        [SP_Key] [int] IDENTITY(-2147483647,1) NOT NULL,
        [SP_Name] [nvarchar](160) NOT NULL,
        [SP_Type] [tinyint] NOT NULL,
        [SP_IsActive] [bit] NOT NULL,
        [SP_DateActive] [datetime2](7) NULL,
        [SP_Content] [xml] NOT NULL,
        [SP_CreateDate] [datetime2](7) NOT NULL,

        CONSTRAINT [PK_Specials] PRIMARY KEY CLUSTERED 
        (
            [SP_Key] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 70) ON [PRIMARY]) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

    ALTER TABLE [dbo].[Specials] ADD CONSTRAINT [DF_Specials_SP_IsActive]  DEFAULT (0) FOR [SP_IsActive]
    ALTER TABLE [dbo].[Specials] ADD CONSTRAINT [DF_Specials_CreateDate]  DEFAULT (getdate()) FOR [SP_CreateDate]
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('Specials.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
GRANT SELECT, INSERT, UPDATE, DELETE ON [dbo].[Specials] TO PUBLIC
')
END TRY
BEGIN CATCH
insert into ##errors values ('Specials.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[SpecialsRelations]'') AND type in (N''U''))
BEGIN
    CREATE TABLE [dbo].[SpecialsRelations](
        [SPR_Key] [int] IDENTITY(-2147483647,1) NOT NULL,
        [SPR_SpecialKey] [int] NOT NULL,
        [SPR_EntityKey] [int] NOT NULL,
        [SPR_EntityType] [tinyint] NOT NULL,

        CONSTRAINT [PK_SpecialsRelations] PRIMARY KEY CLUSTERED 
        (
            [SPR_Key] ASC 
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 70) ON [PRIMARY]) ON [PRIMARY]

    ALTER TABLE [dbo].[SpecialsRelations]  WITH CHECK ADD  CONSTRAINT [FK_SpecialsRelations_Specials] FOREIGN KEY([SPR_SpecialKey]) REFERENCES [dbo].[Specials] ([SP_Key]) ON DELETE CASCADE
    ALTER TABLE [dbo].[SpecialsRelations] CHECK CONSTRAINT [FK_SpecialsRelations_Specials]
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('Specials.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF  EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N''[dbo].[SpecialsRelations]'') AND name = N''X_SpecialKey'')
    DROP INDEX [X_SpecialKey] ON [dbo].[SpecialsRelations] WITH ( ONLINE = OFF )
')
END TRY
BEGIN CATCH
insert into ##errors values ('Specials.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE NONCLUSTERED INDEX [X_SpecialKey] ON [dbo].[SpecialsRelations]
(
    [SPR_SpecialKey] ASC
)
INCLUDE 
( 
    [SPR_Key],
    [SPR_EntityKey],
    [SPR_EntityType]
) 
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 70) ON [PRIMARY]
')
END TRY
BEGIN CATCH
insert into ##errors values ('Specials.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
GRANT SELECT, INSERT, UPDATE, DELETE ON [dbo].[SpecialsRelations] TO PUBLIC
')
END TRY
BEGIN CATCH
insert into ##errors values ('Specials.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[SpecialsDates]'') AND type in (N''U''))
BEGIN
    CREATE TABLE [dbo].[SpecialsDates](
        [SD_Key] [int] IDENTITY(1,1) NOT NULL,
        [SD_SpecialKey] [int] NOT NULL,
        [SD_DateFrom] [date] NULL,
        [SD_DateTo] [date] NULL,
        [SD_CheckInDateFrom] [date] NULL,
        [SD_CheckInDateTo] [date] NULL,
        [SD_SellDateFrom] [date] NULL,
        [SD_SellDateTo] [date] NULL,

        CONSTRAINT [PK_SpecialsDates] PRIMARY KEY CLUSTERED 
        (
            [SD_Key] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 70) ON [PRIMARY]) ON [PRIMARY]

    ALTER TABLE [dbo].[SpecialsDates]  WITH CHECK ADD  CONSTRAINT [FK_SpecialsDates_Specials] FOREIGN KEY([SD_SpecialKey]) REFERENCES [dbo].[Specials] ([SP_Key]) ON DELETE CASCADE
    ALTER TABLE [dbo].[SpecialsDates] CHECK CONSTRAINT [FK_SpecialsDates_Specials]
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('Specials.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''SD_AddCostContent'' and id = object_id(N''[dbo].[SpecialsDates]''))
    ALTER TABLE [dbo].SpecialsDates ADD SD_AddCostContent XML NULL
')
END TRY
BEGIN CATCH
insert into ##errors values ('Specials.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF  EXISTS (SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID(N''[dbo].[SpecialsDates]'') AND name = N''X_SpecialKey'')
    DROP INDEX [X_SpecialKey] ON [dbo].[SpecialsDates] WITH ( ONLINE = OFF )
')
END TRY
BEGIN CATCH
insert into ##errors values ('Specials.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE NONCLUSTERED INDEX [X_SpecialKey] ON [dbo].[SpecialsDates]
(
    [SD_SpecialKey] ASC
)
INCLUDE 
(     
    [SD_Key],
    [SD_DateFrom],
    [SD_DateTo],
    [SD_CheckInDateFrom],
    [SD_CheckInDateTo],
    [SD_SellDateFrom],
    [SD_SellDateTo]
) 
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 70) ON [PRIMARY]
')
END TRY
BEGIN CATCH
insert into ##errors values ('Specials.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
GRANT SELECT, INSERT, UPDATE, DELETE ON [dbo].[SpecialsDates] TO PUBLIC
')
END TRY
BEGIN CATCH
insert into ##errors values ('Specials.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[SpecialsHistory]'') AND type in (N''U''))
BEGIN
    CREATE TABLE [dbo].[SpecialsHistory](
        [SH_Key] [int] IDENTITY(-2147483647,1) NOT NULL,
        [SH_SpecialKey] [int] NOT NULL,
        [SH_SpecialSnapshot] [xml] NOT NULL,
        [SH_UserName] varchar(30) NOT NULL,
        [SH_CreateDate] [datetime2](7) NOT NULL
        PRIMARY KEY CLUSTERED 
        (
            [SH_Key] ASC
        )
        WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 70) ON [PRIMARY]) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

    ALTER TABLE [dbo].[SpecialsHistory]  WITH CHECK ADD  CONSTRAINT [FK_SpecialsHistory_Specials] FOREIGN KEY([SH_SpecialKey]) REFERENCES [dbo].[Specials] ([SP_Key])
    ALTER TABLE [dbo].[SpecialsHistory] CHECK CONSTRAINT [FK_SpecialsHistory_Specials]
    ALTER TABLE [dbo].[SpecialsHistory] ADD CONSTRAINT [DF_SpecialsHistory_CreateDate]  DEFAULT (getdate()) FOR [SH_CreateDate]
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('Specials.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
GRANT SELECT, INSERT, UPDATE, DELETE ON [dbo].[SpecialsHistory] TO PUBLIC
')
END TRY
BEGIN CATCH
insert into ##errors values ('Specials.sql', error_message())
END CATCH
end

print '############ end of file Specials.sql ################'

print '############ begin of file _drop_mw_all.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
declare @killSql as nvarchar(max), @killSqlConcrete as nvarchar(max)



declare @droppedTables as table

(

	dropOrder smallint,

	tableName sysname

)



insert into @droppedTables (dropOrder, tableName)

select row_number() over (order by (select NULL)), name

from sys.tables

where name like ''mwPriceDataTable%''



declare @order as smallint

select @order = max(dropOrder) + 1

from @droppedTables



insert into @droppedTables values (@order, ''mwTourLog'')

set @order = @order + 1



insert into @droppedTables values (@order, ''mwPriceDurations'')

set @order = @order + 1



insert into @droppedTables values (@order, ''mwReplQueueHistory'')

set @order = @order + 1



insert into @droppedTables values (@order, ''mwReplQueue'')

set @order = @order + 1



insert into @droppedTables values (@order, ''mwPriceTablesList'')

set @order = @order + 1



insert into @droppedTables values (@order, ''mwReplTours'')

set @order = @order + 1



insert into @droppedTables values (@order, ''mwSpoDataHotelTable'')

set @order = @order + 1



insert into @droppedTables values (@order, ''mwDeleted'')

set @order = @order + 1



insert into @droppedTables values (@order, ''mwSpoDataTable'')

set @order = @order + 1



insert into @droppedTables values (@order, ''mwPriceHotels'')

set @order = @order + 1



insert into @droppedTables values (@order, ''mwHotelDetails'')

set @order = @order + 1



insert into @droppedTables values (@order, ''mwReplDeletedPricesTemp'')

set @order = @order + 1



insert into @droppedTables values (@order, ''mwReplDirections'')

set @order = @order + 1



insert into @droppedTables values (@order, ''CacheQuotas'')

set @order = @order + 1



insert into @droppedTables values (@order, ''mwCurrentDate'')

set @order = @order + 1



set @killSql = ''if exists (select top 1 1 from sys.tables where name = ''''#tableName'''')

	begin

		TRUNCATE TABLE [dbo].[#tableName]

		DROP TABLE [dbo].[#tableName]

	end''



declare killCursor cursor for

select tableName

from @droppedTables

order by dropOrder asc



declare @tableName as sysname



open killCursor



fetch next from killCursor into @tableName

while @@fetch_status = 0

begin

	

	set @killSqlConcrete = replace(@killSql, ''#tableName'', @tableName)



	begin try

		

		print ''drop table '' + @tableName

		exec (@killSqlConcrete)

		print ''drop table '' + @tableName + '' complete''



	end try

	begin catch

		declare @errMessage as nvarchar(max)

		set @errMessage = ''There is error during '' + @tableName + '' table drop: '' + error_message()

		print @errMessage



		raiserror(@errMessage, 16, 1)

		break

	end catch



	fetch next from killCursor into @tableName

end



close killCursor

deallocate killCursor
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('_drop_mw_all.sql', error_message())
END CATCH
end

print '############ end of file _drop_mw_all.sql ################'

print '############ begin of file _drop_tp_all.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
declare @killSql as nvarchar(max), @killSqlConcrete as nvarchar(max)



declare @droppedTables as table

(

	dropOrder smallint,

	tableName sysname

)



insert into @droppedTables values (0, ''TP_TourMarginActualDate'')

insert into @droppedTables values (1, ''TP_ServiceTours'')

insert into @droppedTables values (2, ''TP_QueueAddCosts'')

insert into @droppedTables values (3, ''TP_PricesUpdated'')

insert into @droppedTables values (4, ''TP_PricesCleaner'')

insert into @droppedTables values (5, ''TP_PriceDetails'')

insert into @droppedTables values (6, ''TP_PricesHash'')

insert into @droppedTables values (7, ''TP_Prices'')

insert into @droppedTables values (8, ''TP_Flights'')

insert into @droppedTables values (9, ''TP_Services'')

insert into @droppedTables values (10, ''TP_ServiceLists'')

insert into @droppedTables values (11, ''TP_TourParametrs'')

insert into @droppedTables values (12, ''TP_PricesDeleted'')

insert into @droppedTables values (13, ''TP_TurDates'')

insert into @droppedTables values (14, ''TP_ServicePriceActualDate'')

insert into @droppedTables values (15, ''TP_ServicePriceNextDate'')

insert into @droppedTables values (16, ''TP_PriceComponents'')

insert into @droppedTables values (17, ''TP_ServiceCalculateParametrs'')

insert into @droppedTables values (18, ''TP_ServiceComponents'')

insert into @droppedTables values (19, ''TP_Lists'')

insert into @droppedTables values (20, ''CalculatingPriceLists'')

insert into @droppedTables values (21, ''TP_Tours'')



set @killSql = ''if exists (select top 1 1 from sys.tables where name = ''''#tableName'''')

	begin

		TRUNCATE TABLE [dbo].[#tableName]

		DROP TABLE [dbo].[#tableName]

	end''



declare killCursor cursor for

select tableName

from @droppedTables

order by dropOrder asc



declare @tableName as sysname



open killCursor



fetch next from killCursor into @tableName

while @@fetch_status = 0

begin

	

	set @killSqlConcrete = replace(@killSql, ''#tableName'', @tableName)



	begin try

		

		print ''drop table '' + @tableName

		exec (@killSqlConcrete)

		print ''drop table '' + @tableName + '' complete''



	end try

	begin catch

		declare @errMessage as nvarchar(max)

		set @errMessage = ''There is error during '' + @tableName + '' table drop: '' + error_message()

		print @errMessage



		raiserror(@errMessage, 16, 1)

		break

	end catch



	fetch next from killCursor into @tableName

end



close killCursor

deallocate killCursor
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('_drop_tp_all.sql', error_message())
END CATCH
end

print '############ end of file _drop_tp_all.sql ################'

print '############ begin of file FlightsGroups.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- 31.10.2015 Создание таблицы с группами рейсов

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[FlightsGroup]'') AND type in (N''U''))

BEGIN

	CREATE TABLE [dbo].[FlightsGroup](

		[FG_Id] [int] IDENTITY(1,1) NOT NULL,

		[FG_Name] [nvarchar](1023) NOT NULL,				-- Название группы рейсов

	CONSTRAINT [PK_FlightsGroup] PRIMARY KEY CLUSTERED 

	(

		[FG_Id] ASC

	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

	) ON [PRIMARY]

	GRANT SELECT, INSERT, DELETE, UPDATE ON [dbo].[FlightsGroup] TO PUBLIC

END

')
END TRY
BEGIN CATCH
insert into ##errors values ('FlightsGroups.sql', error_message())
END CATCH
end

print '############ end of file FlightsGroups.sql ################'

print '############ begin of file FlightsGroupTariffs.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- 31.10.2015 Создание таблицы связи группы рейсов и тарифов

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[FlightsGroupTariffRel]'') AND type in (N''U''))

BEGIN

	CREATE TABLE [dbo].[FlightsGroupTariffRel](

		[FGT_Id] [int] IDENTITY(1,1) NOT NULL,

		[FGT_FGId] [int] NOT NULL,

		[FGT_ASKey] [int] NOT NULL,

	CONSTRAINT [PK_FlightsGroupTariffRel] PRIMARY KEY CLUSTERED 

	(

		[FGT_Id] ASC

	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

	) ON [PRIMARY];

	

	GRANT SELECT, INSERT, DELETE, UPDATE ON [dbo].[FlightsGroupTariffRel] TO PUBLIC;



	ALTER TABLE [dbo].[FlightsGroupTariffRel] ADD CONSTRAINT [FK_FlightsGroupTariffRel_AirService] 

	FOREIGN KEY([FGT_ASKey]) REFERENCES [dbo].[AirService] ([AS_KEY]) ON DELETE CASCADE;



	ALTER TABLE [dbo].[FlightsGroupTariffRel] ADD CONSTRAINT [FK_FlightsGroupTariffRel_FlightsGroup] 

	FOREIGN KEY([FGT_FGId]) REFERENCES [dbo].[FlightsGroup] ([FG_Id]) ON DELETE CASCADE;

END	

')
END TRY
BEGIN CATCH
insert into ##errors values ('FlightsGroupTariffs.sql', error_message())
END CATCH
end

print '############ end of file FlightsGroupTariffs.sql ################'

print '############ begin of file FlightsGroupCharters.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- 31.10.2015 Создание таблицы связи группы рейсов и чатеров

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[FlightsGroupCharterRel]'') AND type in (N''U''))

BEGIN

	CREATE TABLE [dbo].[FlightsGroupCharterRel](

		[FGC_Id] [int] IDENTITY(1,1) NOT NULL,

		[FGC_FGId] [int] NOT NULL,

		[FGC_CHKey] [int] NOT NULL,

	CONSTRAINT [PK_FlightsGroupCharterRel] PRIMARY KEY CLUSTERED 

	(

		[FGC_Id] ASC

	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]

	) ON [PRIMARY];

	

	GRANT SELECT, INSERT, DELETE, UPDATE ON [dbo].[FlightsGroupCharterRel] TO PUBLIC;



	ALTER TABLE [dbo].[FlightsGroupCharterRel] ADD CONSTRAINT [FK_FlightsGroupCharterRel_Charter] 

	FOREIGN KEY([FGC_CHKey]) REFERENCES [dbo].[Charter] ([CH_KEY]) ON DELETE CASCADE;



	ALTER TABLE [dbo].[FlightsGroupCharterRel] ADD CONSTRAINT [FK_FlightsGroupCharterRel_FlightsGroup] 

	FOREIGN KEY([FGC_FGId]) REFERENCES [dbo].[FlightsGroup] ([FG_Id]) ON DELETE CASCADE;

END

')
END TRY
BEGIN CATCH
insert into ##errors values ('FlightsGroupCharters.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('FlightsGroupCharters.sql', error_message())
END CATCH
end

print '############ end of file FlightsGroupCharters.sql ################'

print '############ begin of file HotelsAddcostsGroups.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- 31.10.2015 Создание таблицы с группами рейсов

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[HotelsAddcostsGroups]'') AND type in (N''U''))

BEGIN

	CREATE TABLE [dbo].[HotelsAddcostsGroups](

		[HAG_ID] [int] IDENTITY(1,1) NOT NULL,
		[HAG_NAME] [nvarchar](1024) NULL,				-- Название группы отелей

	CONSTRAINT [PK_HAG_ID] PRIMARY KEY CLUSTERED([HAG_ID] ASC)
	
	WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]) ON [PRIMARY]

	GRANT SELECT, INSERT, DELETE, UPDATE ON [dbo].[HotelsAddcostsGroups] TO PUBLIC

END

')
END TRY
BEGIN CATCH
insert into ##errors values ('HotelsAddcostsGroups.sql', error_message())
END CATCH
end

print '############ end of file HotelsAddcostsGroups.sql ################'

print '############ begin of file HotelsAddcostsParamsCombinations.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- 31.10.2015 Создание таблицы с группами рейсов

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[HotelsAddcostsParamsCombinations]'') AND type in (N''U''))

BEGIN

	CREATE TABLE [dbo].[HotelsAddcostsParamsCombinations](
		[HAPC_ID] [int] IDENTITY(1,1) NOT NULL,
		[HAPC_HDKEY] [int] NOT NULL,
		[HAPC_HRKEY] [int] NOT NULL,
		[HAPC_RMKEY] [int] NOT NULL,
		[HAPC_RCKEY] [int] NOT NULL,
		[HAPC_ACKEY] [int] NOT NULL,
		[HAPC_PNKEY] [int] NOT NULL
		CONSTRAINT [PK_HAPC_ID] PRIMARY KEY CLUSTERED
		(
			[HAPC_ID] ASC
		)
		WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY],
		CONSTRAINT [UC_HAPC_ID_HD_HR_RM_RC_AC_PN] UNIQUE 
		(
			[HAPC_ID],
			[HAPC_HDKEY],
			[HAPC_HRKEY],
			[HAPC_RMKEY],
			[HAPC_RCKEY],
			[HAPC_ACKEY],
			[HAPC_PNKEY]
		)
		WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
	) ON [PRIMARY]

END

')
END TRY
BEGIN CATCH
insert into ##errors values ('HotelsAddcostsParamsCombinations.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT SELECT, INSERT, UPDATE, DELETE ON [dbo].[HotelsAddcostsParamsCombinations] TO PUBLIC

')
END TRY
BEGIN CATCH
insert into ##errors values ('HotelsAddcostsParamsCombinations.sql', error_message())
END CATCH
end

print '############ end of file HotelsAddcostsParamsCombinations.sql ################'

print '############ begin of file HotelsAddcostsGroupsParamsCombinations.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[HotelsAddcostsGroupsParamsCombinations]'') AND type in (N''U''))

BEGIN

	CREATE TABLE [dbo].[HotelsAddcostsGroupsParamsCombinations](

		[HAGPC_ID] [int] IDENTITY(1,1) NOT NULL,
		[HAGPC_HAGID] [int] NOT NULL,
		[HAGPC_HAPCID] [int] NOT NULL,	
		
		CONSTRAINT [PK_HAGPC_ID] PRIMARY KEY CLUSTERED([HAGPC_ID] ASC)	
		WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]) ON [PRIMARY]	
				
		ALTER TABLE [dbo].[HotelsAddcostsGroupsParamsCombinations]  WITH NOCHECK ADD  CONSTRAINT [HAGPC_HAGID] FOREIGN KEY([HAGPC_HAGID])
		REFERENCES [dbo].[HotelsAddcostsGroups] ([HAG_ID])
		ON DELETE CASCADE

		ALTER TABLE [dbo].[HotelsAddcostsGroupsParamsCombinations] CHECK CONSTRAINT [HAGPC_HAGID]
		
		ALTER TABLE [dbo].[HotelsAddcostsGroupsParamsCombinations]  WITH NOCHECK ADD  CONSTRAINT [HAGPC_HAPCID] FOREIGN KEY([HAGPC_HAPCID])
		REFERENCES [dbo].[HotelsAddcostsParamsCombinations] ([HAPC_ID])
		ON DELETE CASCADE

		ALTER TABLE [dbo].[HotelsAddcostsGroupsParamsCombinations] CHECK CONSTRAINT [HAGPC_HAPCID]

	GRANT SELECT, INSERT, DELETE, UPDATE ON [dbo].[HotelsAddcostsGroupsParamsCombinations] TO PUBLIC

END

')
END TRY
BEGIN CATCH
insert into ##errors values ('HotelsAddcostsGroupsParamsCombinations.sql', error_message())
END CATCH
end

print '############ end of file HotelsAddcostsGroupsParamsCombinations.sql ################'

print '############ begin of file BusTransfers.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists(select 1 from systables where name = ''BusTransfers'')
begin

	CREATE TABLE [dbo].[BusTransfers](
		[BT_KEY] [int] IDENTITY(1,1) NOT NULL,
		[BT_NAME] [varchar](100) NOT NULL,
		[BT_CNKEYFROM] [int] NOT NULL,
		[BT_CTKEYFROM] [int] NOT NULL,
		[BT_CNKEYTO] [int] NOT NULL,
		[BT_CTKEYTO] [int] NOT NULL,	
		[BT_DATEFROM] [datetime] NULL,
		[BT_DATETO] [datetime] NULL,
		[BT_TIMEFROM] [datetime] NULL,
		[BT_TIMETO] [datetime] NULL,	
		[BT_WEEK] [varchar](7) NULL,
		[BT_DAYS] [smallint] NULL	
	PRIMARY KEY CLUSTERED 
	(
		[BT_KEY] ASC
	)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [PRIMARY]
	) ON [PRIMARY]

	grant select, insert, delete, update on dbo.BusTransfers to public
end

')
END TRY
BEGIN CATCH
insert into ##errors values ('BusTransfers.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('BusTransfers.sql', error_message())
END CATCH
end

print '############ end of file BusTransfers.sql ################'

print '############ begin of file BusTransferPoints.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists(select 1 from systables where name = ''BusTransferPoints'')
begin

	CREATE TABLE [dbo].[BusTransferPoints](
		[BP_KEY] [int] IDENTITY(1,1) NOT NULL,
		[BP_BTKEY] [int] NOT NULL,
		[BP_CNKEYFROM] [int] NOT NULL,
		[BP_CTKEYFROM] [int] NOT NULL,
		[BP_CNKEYTO] [int] NOT NULL,
		[BP_CTKEYTO] [int] NOT NULL,		
		[BP_TIMEFROM] [datetime] NULL,
		[BP_TIMETO] [datetime] NULL,		
		[BP_DAYFROM] [smallint] NULL,
		[BP_DAYTO] [smallint] NULL	
	PRIMARY KEY CLUSTERED 
	(
		[BP_KEY] ASC
	)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [PRIMARY]
	) ON [PRIMARY]

	grant select, insert, delete, update on dbo.BusTransferPoints to public
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('BusTransferPoints.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N''[dbo].[BP_BTKEY]'') AND parent_object_id = OBJECT_ID(N''[dbo].[BusTransferPoints]''))
BEGIN
	ALTER TABLE [dbo].[BusTransferPoints]  WITH NOCHECK ADD  CONSTRAINT [BP_BTKEY] FOREIGN KEY([BP_BTKEY])
	REFERENCES [dbo].[BusTransfers] ([BT_KEY])
	ON DELETE CASCADE
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('BusTransferPoints.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N''[dbo].[BP_CTKEYFROM]'') AND parent_object_id = OBJECT_ID(N''[dbo].[BusTransferPoints]''))
BEGIN
	ALTER TABLE [dbo].[BusTransferPoints]  WITH NOCHECK ADD  CONSTRAINT [BP_CTKEYFROM] FOREIGN KEY([BP_CTKEYFROM])
	REFERENCES [dbo].[CityDictionary] ([CT_KEY])
	ON DELETE CASCADE
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('BusTransferPoints.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('





')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('BusTransferPoints.sql', error_message())
END CATCH
end

print '############ end of file BusTransferPoints.sql ################'

print '############ begin of file DescTypes.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS (SELECT 1 FROM DescTypes WHERE DT_KEY = 136) 
BEGIN
	INSERT INTO DescTypes (DT_KEY, DT_NAME, DT_TableID) 
	VALUES (136, ''Настройки услуги фиксированной комиссии'', 102)
END

IF NOT EXISTS (SELECT 1 FROM DescTypes WHERE DT_KEY = 137) 
BEGIN
	INSERT INTO DescTypes (DT_KEY, DT_NAME, DT_TableID) 
	VALUES (137, ''Настройки сообщения об отсутствии актуального договора ТА с ТО'', 75)
END

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('DescTypes.sql', error_message())
END CATCH
end

print '############ end of file DescTypes.sql ################'

print '############ begin of file Descriptions.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS (SELECT 1 FROM DESCRIPTIONS WHERE DS_TABLEID = 75 AND DS_DTKEY = 137) 
BEGIN
	IF EXISTS (SELECT 1 FROM DESCTYPES WHERE DT_KEY = 137) 	
		
		DECLARE @DSID INT		
		EXEC GetNKeys ''Descriptions'', 1, @DSID output
	
		INSERT INTO DESCRIPTIONS (DS_KEY, DS_VALUE, DS_TABLEID, DS_DTKEY) 
			VALUES (@DSID , ''Договор с туроператором не заключен или срок его действия истек. Вы можете связаться с туроператором или перезаключить договор в своем личном кабинете http://????/MasterWeb/PartnerRegistration.aspx'',
			75, 137)				
		
END
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('Descriptions.sql', error_message())
END CATCH
end

print '############ end of file Descriptions.sql ################'

print '############ begin of file RemoteProviders.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''RemoteProviders'')
BEGIN
  CREATE TABLE [dbo].[RemoteProviders](
	[RP_Id] [int] IDENTITY(1,1) NOT NULL,
	[RP_Name] [varchar](50) NOT NULL,
	[RP_Adapter] [varchar](100) NOT NULL,
	[RP_BasicApiAdress] [varchar](100) NOT NULL,
	[RP_Login] [varchar](50) NOT NULL,
	[RP_Password] [varchar](50) NULL,
	[RP_IsFlightSign] [bit] NOT NULL,
	[RP_IsHotelSign] [bit] NOT NULL,
 CONSTRAINT [PK_RemoteProviders] PRIMARY KEY CLUSTERED 
(
	[RP_Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GRANT SELECT, INSERT, DELETE, UPDATE ON [dbo].[RemoteProviders] TO PUBLIC

END
')
END TRY
BEGIN CATCH
insert into ##errors values ('RemoteProviders.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''RP_UserId'' AND id = OBJECT_ID(N''[dbo].[RemoteProviders]''))
BEGIN
	ALTER TABLE [dbo].RemoteProviders ADD RP_UserId INT NULL
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('RemoteProviders.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''RP_AuthToken'' AND id = OBJECT_ID(N''[dbo].[RemoteProviders]''))
BEGIN
	ALTER TABLE [dbo].RemoteProviders ADD RP_AuthToken nvarchar (max)
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('RemoteProviders.sql', error_message())
END CATCH
end

print '############ end of file RemoteProviders.sql ################'

print '############ begin of file GDSMappings.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS(SELECT 1 FROM systables WHERE name = ''GDSMappings'')
BEGIN

	CREATE TABLE [dbo].[GDSMappings](
		[GM_ID] [int] IDENTITY(1,1) NOT NULL,
		[GM_RPID] [int] NOT NULL,
		[GM_DICTIONARYID] [int] NOT NULL,
		[GM_PROVIDERDICTIONARYITEMID] [varchar](128) NOT NULL,
		[GM_MTDICTIONARYITEMID] [int] NOT NULL,		
		[GM_CREATEDATE] [datetime] NOT NULL		
	PRIMARY KEY CLUSTERED 
	(
		[GM_ID] ASC
	)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [PRIMARY]
	) ON [PRIMARY]
	
		ALTER TABLE [dbo].[GDSMappings]  WITH NOCHECK ADD  CONSTRAINT [GM_RPID] FOREIGN KEY([GM_RPID])
		REFERENCES [dbo].[RemoteProviders] ([RP_ID])
		ON DELETE CASCADE

		ALTER TABLE [dbo].[GDSMappings] CHECK CONSTRAINT [GM_RPID]

	GRANT SELECT, INSERT, DELETE, UPDATE ON dbo.GDSMappings TO PUBLIC
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('GDSMappings.sql', error_message())
END CATCH
end

print '############ end of file GDSMappings.sql ################'

print '############ begin of file RemoteFlightsBooksRelations.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = N''dbo'' AND TABLE_NAME = N''RemoteFlightsBooksRelations'')
BEGIN
	CREATE TABLE [dbo].[RemoteFlightsBooksRelations](
		[RFBR_ID] [int] IDENTITY(1,1) NOT NULL,
		[RFBR_TUIDKEY] [int] NOT NULL,
		[RFBR_BOOKID] [bigint] NOT NULL,
		CONSTRAINT [PK_RFBR_ID] PRIMARY KEY CLUSTERED 
		(
			[RFBR_ID] ASC
		) WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]) ON [PRIMARY]

	ALTER TABLE [dbo].[RemoteFlightsBooksRelations]  WITH NOCHECK ADD  CONSTRAINT [RFBR_TUIDKEY] FOREIGN KEY([RFBR_TUIDKEY])
		REFERENCES [dbo].[TuristService] ([TU_IDKEY])
	ON DELETE CASCADE

	ALTER TABLE [dbo].[RemoteFlightsBooksRelations] CHECK CONSTRAINT [RFBR_TUIDKEY]
	
	GRANT SELECT, INSERT, DELETE, UPDATE ON [dbo].[RemoteFlightsBooksRelations] TO PUBLIC

END

')
END TRY
BEGIN CATCH
insert into ##errors values ('RemoteFlightsBooksRelations.sql', error_message())
END CATCH
end

print '############ end of file RemoteFlightsBooksRelations.sql ################'

print '############ begin of file enable_Change_Tracking.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- включение слежения за изменениями на уровне БД
if not exists (select top 1 1 from sys.change_tracking_databases where database_id = DB_ID())
begin
	declare @sql nvarchar(max)
	set @sql = ''ALTER DATABASE ['' + DB_NAME() + ''] SET CHANGE_TRACKING = ON (CHANGE_RETENTION = 2 DAYS, AUTO_CLEANUP = ON)''	
	exec (@sql)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

-- включение слежения за изменениями на уровне таблицы
if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''tbl_Costs''))
begin
	ALTER TABLE tbl_Costs ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on tbl_costs to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''CostOffers''))
begin
	ALTER TABLE CostOffers ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on CostOffers to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''tbl_TurList''))
begin
	ALTER TABLE tbl_TurList ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on tbl_TurList to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''TurService''))
begin
	ALTER TABLE TurService ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on TurService to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''tbl_Country''))
begin
	ALTER TABLE tbl_Country ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on tbl_Country to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''CityDictionary''))
begin
	ALTER TABLE CityDictionary ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on CityDictionary to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Accmdmentype''))
begin
	ALTER TABLE Accmdmentype ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on Accmdmentype to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''AirSeason''))
begin
	ALTER TABLE AirSeason ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on AirSeason to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''AirService''))
begin
	ALTER TABLE AirService ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on AirService to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Charter''))
begin
	ALTER TABLE Charter ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on Charter to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''HotelDictionary''))
begin
	ALTER TABLE HotelDictionary ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on HotelDictionary to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''HotelRooms''))
begin
	ALTER TABLE HotelRooms ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on HotelRooms to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Pansion''))
begin
	ALTER TABLE Pansion ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on Pansion to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Resorts''))
begin
	ALTER TABLE Resorts ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on Resorts to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Rooms''))
begin
	ALTER TABLE Rooms ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on Rooms to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''RoomsCategory''))
begin
	ALTER TABLE RoomsCategory ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on RoomsCategory to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''TourPrograms''))
begin
	ALTER TABLE TourPrograms ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on TourPrograms to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''ToursSearch''))
begin
	ALTER TABLE ToursSearch ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on ToursSearch to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Service''))
begin
	ALTER TABLE [Service] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [Service] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Courses''))
begin
	ALTER TABLE Courses ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on Courses to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''TURMARGIN''))
begin
	ALTER TABLE TURMARGIN ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on TURMARGIN to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''TourMarginDurations''))
begin
	ALTER TABLE TourMarginDurations ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on TourMarginDurations to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''SystemSettings''))
begin
	ALTER TABLE SystemSettings ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on SystemSettings to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''AddCosts''))
begin
	ALTER TABLE AddCosts ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on AddCosts to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''RealCourses''))
begin
	ALTER TABLE RealCourses ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on RealCourses to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Airline''))
begin
	ALTER TABLE Airline ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on Airline to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Airport''))
begin
	ALTER TABLE Airport ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on Airport to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Aircraft''))
begin
	ALTER TABLE Aircraft ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on Aircraft to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Quotas''))
begin
	ALTER TABLE Quotas ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on Quotas to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''QuotaObjects''))
begin
	ALTER TABLE QuotaObjects ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on QuotaObjects to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''QuotaDetails''))
begin
	ALTER TABLE QuotaDetails ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on QuotaDetails to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''QuotaParts''))
begin
	ALTER TABLE QuotaParts ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on QuotaParts to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''StopSales''))
begin
	ALTER TABLE StopSales ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on StopSales to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Transfer''))
begin
	ALTER TABLE [Transfer] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [Transfer] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Transport''))
begin
	ALTER TABLE [Transport] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [Transport] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''GeoCustomPoint''))
begin
	ALTER TABLE [GeoCustomPoint] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [GeoCustomPoint] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''GeoCustomPointClass''))
begin
	ALTER TABLE [GeoCustomPointClass] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [GeoCustomPointClass] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''GeoServicePointsLink''))
begin
	ALTER TABLE [GeoServicePointsLink] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [GeoServicePointsLink] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''ServiceList''))
begin
	ALTER TABLE [ServiceList] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [ServiceList] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''CategoriesOfHotel''))
begin
	ALTER TABLE [CategoriesOfHotel] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [CategoriesOfHotel] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''ExcurDictionary''))
begin
	ALTER TABLE [ExcurDictionary] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [ExcurDictionary] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Ship''))
begin
	ALTER TABLE [Ship] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [Ship] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Cabine''))
begin
	ALTER TABLE [Cabine] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [Cabine] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''AddDescript1''))
begin
	ALTER TABLE [AddDescript1] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [AddDescript1] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''AddDescript2''))
begin
	ALTER TABLE [AddDescript2] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [AddDescript2] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''tbl_Partners''))
begin
	ALTER TABLE [tbl_Partners] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [tbl_Partners] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''dup_user''))
begin
	ALTER TABLE [dup_user] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [dup_user] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Rates''))
begin
	ALTER TABLE [Rates] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [Rates] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''PrtDogs''))
begin
	ALTER TABLE [PrtDogs] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [PrtDogs] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''UserList''))
begin
	ALTER TABLE [UserList] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [UserList] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''FlightsGroupCharterRel''))
begin
	ALTER TABLE [FlightsGroupCharterRel] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [FlightsGroupCharterRel] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''FlightsGroup''))
begin
	ALTER TABLE [FlightsGroup] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [FlightsGroup] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''FlightsGroupTariffRel''))
begin
	ALTER TABLE [FlightsGroupTariffRel] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [FlightsGroupTariffRel] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''HotelsAddcostsGroups''))
begin
	ALTER TABLE [HotelsAddcostsGroups] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [HotelsAddcostsGroups] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''HotelsAddcostsGroupsParamsCombinations''))
begin
	ALTER TABLE [HotelsAddcostsGroupsParamsCombinations] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [HotelsAddcostsGroupsParamsCombinations] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''HotelsAddcostsParamsCombinations''))
begin
	ALTER TABLE [HotelsAddcostsParamsCombinations] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [HotelsAddcostsParamsCombinations] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Discounts''))
begin
	ALTER TABLE [Discounts] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [Discounts] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Clients''))
begin
	ALTER TABLE [Clients] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [Clients] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''FixedDiscounts''))
begin
	ALTER TABLE [FixedDiscounts] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [FixedDiscounts] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''CARDS''))
begin
	ALTER TABLE [CARDS] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [CARDS] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Discount_Client''))
begin
	ALTER TABLE [Discount_Client] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [Discount_Client] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Descriptions''))
begin
	ALTER TABLE [Descriptions] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [Descriptions] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''HotelTypes''))
begin
	ALTER TABLE [HotelTypes] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [HotelTypes] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''HotelTypeRelations''))
begin
	ALTER TABLE [HotelTypeRelations] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [HotelTypeRelations] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''PrtTypes''))
begin
	ALTER TABLE [PrtTypes] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [PrtTypes] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''PrtTypesToPartners''))
begin
	ALTER TABLE [PrtTypesToPartners] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [PrtTypesToPartners] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''BusTransfers''))
begin
	ALTER TABLE [BusTransfers] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [BusTransfers] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''BusTransferPoints''))
begin
	ALTER TABLE [BusTransferPoints] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [BusTransferPoints] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''Vehicle''))
begin
	ALTER TABLE [Vehicle] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [Vehicle] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''VehiclePlan''))
begin
	ALTER TABLE [VehiclePlan] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [VehiclePlan] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''VehicleIllegalPlan''))
begin
	ALTER TABLE [VehicleIllegalPlan] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [VehicleIllegalPlan] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''tbl_DogovorList''))
begin
	ALTER TABLE [tbl_DogovorList] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [tbl_DogovorList] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''TuristService''))
begin
	ALTER TABLE [TuristService] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = OFF)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [TuristService] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''SpecialsHistory''))
begin
	ALTER TABLE [SpecialsHistory] ENABLE CHANGE_TRACKING WITH (TRACK_COLUMNS_UPDATED = ON)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
grant view change tracking on [SpecialsHistory] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('enable_Change_Tracking.sql', error_message())
END CATCH
end

print '############ end of file enable_Change_Tracking.sql ################'

print '############ begin of file UpdateMaintenanceTable.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists(select id from sysobjects where xtype=''p'' and name=''UpdateMaintenanceTable'')
 DROP PROCEDURE [dbo].[UpdateMaintenanceTable]
')
END TRY
BEGIN CATCH
insert into ##errors values ('UpdateMaintenanceTable.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

/****** Object:  StoredProcedure [dbo].[UpdateMaintenanceTable]    Script Date: 03.10.2016 17:45:33 ******/
SET ANSI_NULLS ON
')
END TRY
BEGIN CATCH
insert into ##errors values ('UpdateMaintenanceTable.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

SET QUOTED_IDENTIFIER ON
')
END TRY
BEGIN CATCH
insert into ##errors values ('UpdateMaintenanceTable.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

-- =============================================
-- Author:		Dpetrov
-- Create date: 18-04-17
-- Description:	Процедура заполнения таблицы для обслуживания БД
-- =============================================
CREATE PROCEDURE [dbo].[UpdateMaintenanceTable]
	@DefaultFillFactor smallint = 95
AS
BEGIN

	--drop table #temptablelist1
	--drop table maintenance
	--drop table #work_to_do

	DECLARE @objectid int;
	DECLARE @indexid int;
	DECLARE @partitioncount bigint;
	DECLARE @schemaname nvarchar(130); 
	DECLARE @objectname nvarchar(130); 
	DECLARE @indexname nvarchar(130); 
	DECLARE @partitionnum bigint;
	DECLARE @partitions bigint;
	DECLARE @frag float;
	DECLARE @fillfactor int;
	DECLARE @index_type smallint;
	DECLARE @avg_page_space_used_in_percent int;
	DECLARE @cdate datetime;
	DECLARE @LastBildTime datetime;
	

	DECLARE @db_id int
	SET @db_id = DB_ID()

	if exists(select 1 from sys.tables where name = ''Maintenance'')
	    BEGIN
			drop table Maintenance
	    END
	-- Создаем основную таблицу с данными для обслуживания.
		CREATE TABLE Maintenance
		(
			MTM_Id int NOT NULL IDENTITY (1, 1),
			MTM_TableName nvarchar(250) NOT NULL,
			MTM_partitionnum smallint NULL,
			MTM_IndexId int NULL,
			MTM_IndexType smallint NULL,
			MTM_IndexName nvarchar(250) NULL,
			MTM_IndexUsageSpaceCur smallint NULL,
			MTM_IndexUsageSpaceOld smallint NULL,
			MTM_IndexfragOld smallint NULL,
			MTM_IndexfragCur smallint NULL,
			MTM_IndexfragAft smallint NULL,
			MTM_IndexFillFactor smallint NULL,
			MTM_IndexFillFactorManual smallint NULL,
			MTM_IndexFillFactorOld smallint NULL,
			MTM_IndexFillFactorCur smallint NULL,
			MTM_IndexFillFactorAft smallint NULL,
			MTM_ReindexTime	int default(0) NULL,
			MTM_LastCleaner datetime NULL,
			MTM_LastReindex datetime NULL,
			MTM_LastStat datetime NULL,
			MTM_TablePriority smallint NULL,
			MTM_CurrentRun nvarchar(40) NULL
		)


	-- Создаем временную таблицу для хранения промежуточного результата статистикие IO по таблицам.
	create table #temptablelist1
	(
		table_name nvarchar(150) collate database_default,
		rw bigint,
		table_priority int default 10
	)

	insert into #temptablelist1 (table_name,rw)
	select table_name,ttable2.[Reads&Writes] as rw
		 from 
	 (select TABLE_NAME from INFORMATION_SCHEMA.TABLES where TABLE_TYPE = ''BASE TABLE'' and TABLE_CATALOG = DB_NAME() and table_schema = ''dbo'' ) as ttable1 
	  left outer join (
		SELECT  OBJECT_NAME(ddius.object_id) AS TableName ,
			SUM(ddius.user_seeks + ddius.user_scans + ddius.user_lookups
				+ ddius.user_updates) AS [Reads&Writes] 
		FROM    sys.dm_db_index_usage_stats ddius
			INNER JOIN sys.indexes i ON ddius.object_id = i.object_id
										 AND i.index_id = ddius.index_id
		WHERE    OBJECTPROPERTY(ddius.object_id, ''IsUserTable'') = 1
			AND ddius.database_id = DB_ID()
		GROUP BY OBJECT_NAME(ddius.object_id)
		) as ttable2  on ttable1.TABLE_NAME = ttable2.TableName
		order by rw desc

		--Заполняем основную таблицу строками со спискам таблиц
		insert into Maintenance (mtm_TableName,mtm_TablePriority) 
		select table_name,table_priority from #temptablelist1 left outer join Maintenance on table_name = MTM_TableName where Maintenance.MTM_TableName is null

		--Копируем старые значения фрагментации для истории
		update Maintenance set MTM_IndexfragOld = MTM_indexfragCur
		-- Обновляем для истории старое значение fillfactor
		update Maintenance set MTM_IndexFillFactorOld=MTM_IndexFillFactorCur
	 ------------------
		--drop table #work_to_do
		--Собираем статистику фрагментации индексов
		SELECT s.object_id AS objectid, s.index_id AS indexid, s.partition_number AS partitionnum, s.avg_fragmentation_in_percent as frag,avg_page_space_used_in_percent,i.Type as Index_type,fill_factor as indexcurfill
		INTO #work_to_do
		--FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL , NULL, ''detailed'') s inner join sys.indexes i on i.object_id=s.object_id and i.index_id = s.index_id 
		FROM sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL , NULL, NULL) s inner join sys.indexes i on i.object_id=s.object_id and i.index_id = s.index_id 
		WHERE s.avg_fragmentation_in_percent > 10.0 AND s.index_id > 0 AND s.index_level = 0 --and s.page_count > 10
		--GROUP BY s.object_id, s.index_id, s.partition_number,s.avg_page_space_used_in_percent,i.Type
	
		--Заполняем основную таблицу.
		DECLARE partitions CURSOR READ_ONLY FAST_FORWARD LOCAL FOR SELECT * FROM #work_to_do  order by frag desc;
		OPEN partitions;
		WHILE (1 = 1)
			BEGIN
				FETCH NEXT
				   FROM partitions
				   INTO @objectid, @indexid, @partitionnum, @frag, @avg_page_space_used_in_percent,@index_type,@fillfactor;
				IF @@FETCH_STATUS < 0 BREAK;
				SELECT @objectname = o.name, @schemaname = s.name 
					FROM sys.objects AS o JOIN sys.schemas as s ON s.schema_id = o.schema_id
				WHERE o.object_id = @objectid;
				SELECT @indexname = name
				FROM sys.indexes
				WHERE  object_id = @objectid AND index_id = @indexid;
				SELECT @partitioncount = count (*)
				FROM sys.partitions
				WHERE object_id = @objectid AND index_id = @indexid;

				if not exists(select 1 from Maintenance where mtm_IndexName = @indexname and MTM_TableName = @objectname)
				Begin
					insert into Maintenance 
					(MTM_TableName,
					MTM_partitionnum,
					MTM_indexName,
					MTM_indexId,
					MTM_IndexType,
					MTM_indexfragCur,
					MTM_IndexUsageSpaceCur,
					MTM_IndexFillFactorCur,
					MTM_IndexFillFactor)
					select 
						t.name,
						t.partition,
						t.indexname,
						t.indexid,
						t.indextype,
						t.frag,
						t.indexused,
						t.indexcurfill,
						t.DefaultFillFactor
					from (select
						 @objectname as name,
						 @partitioncount as partition,
						 @indexname as indexname,
						 @indexid as indexid,
						 @index_type as indextype,
						 @frag as frag,
						 @avg_page_space_used_in_percent as indexused,
						 @fillfactor as indexcurfill,
						 @DefaultFillFactor as DefaultFillFactor) as t --left outer join Maintenance on t.indexname = MTM_IndexName where  Maintenance.MTM_IndexName is null and MTM_TableName = t.name
				End
				Else
				Begin
				    Update Maintenance set  MTM_IndexfragCur = @frag,
											MTM_IndexUsageSpaceCur=@avg_page_space_used_in_percent,
											MTM_IndexFillFactor=@DefaultFillFactor,
											MTM_IndexFillFactorCur=@fillfactor
											 where MTM_IndexName = @indexname and MTM_TableName = @objectname
				End

		END;
		CLOSE partitions;
		DEALLOCATE partitions;

		-- На основе имени таблиц и кол-ву операций IO ставим приоритет таблицы.
		update Maintenance set MTM_tablepriority=ttable3.table_priority
		from (select table_name,
					table_priority=case
						when (table_name like N''tp_%'') then 50 
						when (table_name like N''mw%'') then 60
						when (table_name like N''tbl_%'') then 40 
						when (#temptablelist1.rw>(select avg(#temptablelist1.rw) from #temptablelist1)) then 30
						when (#temptablelist1.rw<(select avg(#temptablelist1.rw) from #temptablelist1)) then 20
						else 10
						end
		from #temptablelist1 ) as ttable3
		where Maintenance.MTM_tableName = ttable3.table_name



	drop table #temptablelist1
	drop table #work_to_do

		-- Добавляем или обновляем в основной таблице строку с отметкой времени когда таблица формировалась.

	select @LastBildTime= isnull(convert(datetime,SS_ParmValue,20), null) from systemsettings where SS_ParmName = ''MTMLastBildTime''

	if @LastBildTime is null
	begin
		insert into systemsettings (SS_ParmName,SS_ParmValue) values (''MTMLastBildTime'',getdate())
	end
	else
	begin
		update systemsettings set SS_ParmValue = getdate() where SS_ParmName = ''MTMLastBildTime''
	end

	Update Maintenance set MTM_CurrentRun = null where MTM_CurrentRun like ''Reindex start:%''

	GRANT INSERT ON [dbo].[Maintenance] TO [public]

	GRANT SELECT ON [dbo].[Maintenance] TO [public]

	GRANT UPDATE ON [dbo].[Maintenance] TO [public]


END

')
END TRY
BEGIN CATCH
insert into ##errors values ('UpdateMaintenanceTable.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on dbo.UpdateMaintenanceTable to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('UpdateMaintenanceTable.sql', error_message())
END CATCH
end

print '############ end of file UpdateMaintenanceTable.sql ################'

print '############ begin of file Maintenance_reindex_job.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists(select id from sysobjects where xtype=''p'' and name=''Maintenance_reindex_job'')
 DROP PROCEDURE [dbo].[Maintenance_reindex_job]
')
END TRY
BEGIN CATCH
insert into ##errors values ('Maintenance_reindex_job.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

/****** Object:  StoredProcedure [dbo].[Maintenance_reindex_job]    Script Date: 04.10.2016 12:16:00 ******/
SET ANSI_NULLS ON
')
END TRY
BEGIN CATCH
insert into ##errors values ('Maintenance_reindex_job.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

SET QUOTED_IDENTIFIER ON
')
END TRY
BEGIN CATCH
insert into ##errors values ('Maintenance_reindex_job.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

-- =============================================
-- Author:		Dpetrov
-- Create date: 03-10-16
-- Description:	Процедура вызова обслуживания реиндекс по таблице для обслуживания БД
-- =============================================
CREATE PROCEDURE [dbo].[Maintenance_reindex_job] 
	
AS
BEGIN
DECLARE @UpdateTable bit = 0;
DECLARE @UseTable bit = 0;
DECLARE @LastBildTime datetime;
DECLARE @BeginJob time ;
DECLARE @EndJob time;
Declare @CurTime time


-- Установка времени в которое можно производить обслуживание.
set @BeginJob = ''21:00:00''
set @EndJob = ''09:00:00''


-- Проверяем существование таблицы, обновляем данные для обслуживания если их обновляли больше суток назад.
if exists(select 1 from sys.tables where name = ''Maintenance'')
 begin
	select @LastBildTime = (isnull(SS_ParmValue, null)) from systemsettings with(nolock) where SS_ParmName = ''MTMLastBildTime''
		if (@LastBildTime > dateadd(day,-1,getdate()) and @UpdateTable=0)
		begin
			set @usetable=1	
		end
		else
		begin
			exec UpdateMaintenanceTable
			select @LastBildTime = (isnull(SS_ParmValue, null)) from systemsettings with(nolock) where SS_ParmName = ''MTMLastBildTime''
		end
 end
else
 begin	
	exec UpdateMaintenanceTable
	select @LastBildTime = (isnull(SS_ParmValue, null)) from systemsettings with(nolock) where SS_ParmName = ''MTMLastBildTime''
 end

 set @CurTime = CONVERT (time, GETDATE())

 -- Уходим в цикл обработки таблицы обслуживания опираясь на поле MTM_LastReindex.
 if  (@EndJob > (select CONVERT (time, GETDATE()))) 
 begin
	while exists(select 1 from Maintenance where MTM_IndexName is not null and (MTM_LastReindex < dateadd(day,-1,getdate()) or MTM_LastReindex is null) and (@EndJob > @curtime or @CurTime > @BeginJob))
		begin
			exec Maintenance_reindex_Run @EndJob
			set @CurTime = CONVERT (time, GETDATE())
		end
 end

END

')
END TRY
BEGIN CATCH
insert into ##errors values ('Maintenance_reindex_job.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on dbo.Maintenance_reindex_job to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('Maintenance_reindex_job.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('Maintenance_reindex_job.sql', error_message())
END CATCH
end

print '############ end of file Maintenance_reindex_job.sql ################'

print '############ begin of file Maintenance_reindex_Run.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists(select id from sysobjects where xtype=''p'' and name=''Maintenance_reindex_Run'')
 DROP PROCEDURE [dbo].[Maintenance_reindex_Run]
')
END TRY
BEGIN CATCH
insert into ##errors values ('Maintenance_reindex_Run.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

/****** Object:  StoredProcedure [dbo].[Maintenance_reindex_Run]    Script Date: 03.10.2016 17:44:24 ******/
SET ANSI_NULLS ON
')
END TRY
BEGIN CATCH
insert into ##errors values ('Maintenance_reindex_Run.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

SET QUOTED_IDENTIFIER ON
')
END TRY
BEGIN CATCH
insert into ##errors values ('Maintenance_reindex_Run.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

-- =============================================
-- Author:		Dpetrov
-- Create date: 03-10-16
-- Description:	Процедура обслуживания реиндексом.
-- =============================================
CREATE PROCEDURE [dbo].[Maintenance_reindex_Run] 
	@EndJob time
AS
BEGIN

declare @currentindexrun sysname;
declare @tablename sysname;
declare @indexid int;
declare @fillfactor smallint;
declare @fillfactorCur smallint;
declare @fillfactorAft smallint;
declare @fillfactorOld smallint;
declare @fillfactorMan smallint;
declare @IndexfragOld smallint;
declare @IndexfragCur smallint;
declare @IndexfragAft smallint;
declare @Indextype nvarchar(30);
declare @sql nvarchar(max);
declare @startRun datetime;
declare @endRun datetime;

Begin try
-- Находим строку которую надо обработать. С учетом:
-- MTM_CurrentRun. Строка должна быть не занята другим процессом.
-- mtm_indexfragCur+mtm_tablePriority. Сумма процента фрагментации и приоритета таблицы.
-- (MTM_LastReindex < dateadd(day,-1,getdate()) or MTM_LastReindex is null). Со времени последней обработки прошло больше суток или данных о проверке нет вообще.
-- (dateadd(mi,MTM_ReindexTime,CONVERT (time, GETDATE()))<@EndJob. На основе последнего времени затраченного на выполнение обслуживания, пытаемся понять, не заденем ли мы рабочий день.


SELECT top(1) 
		@currentindexrun= mtm_indexname,
		@indexid=mtm_indexid,
		@tablename=mtm_tablename,
		@Indextype=mtm_indextype,
		@fillfactor=MTM_IndexFillFactor,
		@fillfactorCur=MTM_IndexFillFactorCur,
		@fillfactorAft=MTM_IndexFillFactorAft,
		@fillfactorOld=MTM_IndexFillFactorOld,
		@fillfactorMan=MTM_IndexFillFactorManual,
		@IndexfragCur=mtm_indexfragCur,
		@IndexfragOld=MTM_IndexfragOld,
		@IndexfragAft=mtm_indexfragAft
	 FROM Maintenance
	where MTM_CurrentRun is null and mtm_indexfragCur+mtm_tablePriority is not null and (MTM_LastReindex < dateadd(day,-1,getdate()) or MTM_LastReindex is null) and (dateadd(mi,MTM_ReindexTime,CONVERT (time, GETDATE()))<@EndJob)
  order by mtm_tablepriority desc,MTM_ReindexTime desc, mtm_indexfragCur+mtm_tablePriority desc
--print @currentindexrun

-- Формируем итоговый sql для обработки.
if @currentindexrun is not null
	Begin
	set @sql = null
	if @IndexfragCur < 30
		begin
			set @sql=''ALTER INDEX [''+ @currentindexrun +''] ON [dbo].['' + @tablename + ''] REORGANIZE WITH ( LOB_COMPACTION = ON )''
		end
	else
		begin
			-- Если руками задан филлфактор, то используем его всегда.
			If @fillfactorMan is not null 
				begin
				 set @fillfactor=@fillfactorMan
				 set @sql = ''ALTER INDEX [''+ @currentindexrun +''] ON [dbo].['' + @tablename + ''] REBUILD PARTITION = ALL WITH (FILLFACTOR = '' + ltrim(str(@fillfactor)) + '' )''
				end
			else
				begin
					if @Indextype is null set @fillfactor = @fillfactor
					--Если это PK, то fillfactor = 100
					if (@Indextype = 1) 
						begin
							 set @fillfactor=100
							 set @sql = ''ALTER INDEX [''+ @currentindexrun +''] ON [dbo].['' + @tablename + ''] REBUILD PARTITION = ALL WITH (FILLFACTOR = '' + ltrim(str(@fillfactor)) + '' )''
						end
						else
						begin
							set @sql = ''ALTER INDEX [''+ @currentindexrun +''] ON [dbo].['' + @tablename + ''] REBUILD PARTITION = ALL WITH (FILLFACTOR = '' + ltrim(str(@fillfactor)) + '' )''		
						end
				end
	end

	--print @sql
	-- Ставим маркер начала обслуживания и выполняем запрос на обслуживание.
	
	set @startrun=getdate()
	update Maintenance set MTM_CurrentRun = ''Reindex start: '' + CONVERT(nvarchar(30), @startrun, 20) where mtm_indexname = @currentindexrun and mtm_tablename = @tablename
	exec (@sql)
	set @endrun=getdate()
	
	-- Вычисляем то что получилось после обслуживания и записываем для истории.
	update Maintenance set mtm_indexfragAft=tt.frag,MTM_LastReindex= getdate(),MTM_ReindexTime=datediff(mi,@startrun,@endrun),MTM_CurrentRun= null from
			(SELECT object_id AS objectid, index_id AS indexid, avg_fragmentation_in_percent as frag
			FROM sys.dm_db_index_physical_stats (DB_ID(),object_id(@tablename), @indexid , NULL, null)) as tt
			 where mtm_indexid = tt.indexid and mtm_tablename = object_name(tt.objectid)
		
end	
end try
begin catch
	begin
		-- Обрабатываем ошибки.
		update Maintenance set MTM_LastReindex= getdate(),MTM_CurrentRun= null where mtm_indexname = @currentindexrun and mtm_tablename = @tablename
		declare @errormsg nvarchar(max)
		set @errormsg = ''Maintenance_reindex_Run: ''+ ERROR_MESSAGE() + ''. TableName= '' + @tablename + '', Current Index Name= '' + @currentindexrun
		if @errormsg is not null
			begin
				insert into SystemLog (SL_Type, SL_Date, SL_Message, SL_AppID) values(1, GETDATE(), @errormsg, 88)
			end
		else
			begin 
				insert into SystemLog (SL_Type, SL_Date, SL_Message, SL_AppID) values(1, GETDATE(), ''Maintenance_reindex_Run: Index for maintenance not found'', 88)
			end
	end
end catch

END

')
END TRY
BEGIN CATCH
insert into ##errors values ('Maintenance_reindex_Run.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on dbo.Maintenance_reindex_Run to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('Maintenance_reindex_Run.sql', error_message())
END CATCH
end

print '############ end of file Maintenance_reindex_Run.sql ################'

print '############ begin of file ClearUnusedAddCostsWithFK.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- Task 47689: из-за отсутствия каскадного удаления и переноса, приходится чистить доплаты, 
-- для которых уже удалены различные классы услуг и тд

--проверка городов
DELETE FROM AddCosts  
WHERE ADC_Id IN(  
		SELECT ADC_Id FROM AddCosts ac
		LEFT OUTER JOIN cityDictionary cd ON (ac.ADC_CityKey = cd.CT_KEY)
		WHERE ac.ADC_CityKey is not null and ac.ADC_CityKey > 0 and cd.CT_KEY is null
		)

--проверка авиаперелетов
DELETE FROM AddCosts  
WHERE ADC_Id IN(  
	SELECT ADC_Id FROM AddCosts ac
	LEFT OUTER JOIN charter ch ON (ac.ADC_Code = ch.CH_KEY)
	WHERE ac.ADC_Code is not null and ac.ADC_Code > 0 and ac.ADC_SVKey = 1 and ch.CH_KEY is null
	)

--проверка классов авиаперелетов
DELETE FROM AddCosts  
WHERE ADC_Id IN(  
	SELECT ADC_Id FROM AddCosts ac
	LEFT OUTER JOIN AirService airs ON (ac.ADC_SubCode1 = airs.AS_KEY)
	WHERE ac.ADC_SubCode1 is not null and ac.ADC_SubCode1 > 0 and ac.ADC_SVKey = 1 and airs.AS_KEY is null
	)

--проверка партнеров
DELETE FROM AddCosts  
WHERE ADC_Id IN(  
	SELECT ADC_Id FROM AddCosts ac
	LEFT OUTER JOIN tbl_Partners p ON (ac.ADC_PartnerKey = p.PR_KEY)
	WHERE ac.ADC_PartnerKey is not null and ac.ADC_PartnerKey > 0 and p.PR_KEY is null
	)

--проверка отелей
DELETE FROM AddCosts  
WHERE ADC_Id IN(  
	SELECT ADC_Id FROM AddCosts ac
	LEFT OUTER JOIN hotelDictionary hd ON (ac.ADC_Code = hd.HD_KEY)
	WHERE ac.ADC_Code is not null and ac.ADC_Code > 0 and ac.ADC_SVKey = 3 and hd.HD_KEY is null
	)

--проверка питания
DELETE FROM AddCosts  
WHERE ADC_Id IN(  
	SELECT ADC_Id FROM AddCosts ac
	LEFT OUTER JOIN pansion p ON (ac.ADC_PansionKey = p.PN_KEY)
	WHERE ac.ADC_PansionKey is not null and ac.ADC_PansionKey > 0 and p.PN_KEY is null
	)

--проверка типов номеров
DELETE FROM AddCosts  
WHERE ADC_Id IN(  
	SELECT ADC_Id FROM AddCosts ac
	LEFT OUTER JOIN Rooms r ON (ac.ADC_SubCode1 = r.RM_KEY)
	WHERE ac.ADC_SubCode1 is not null and ac.ADC_SubCode1 > 0 and ac.ADC_SVKey = 3 and r.RM_KEY is null
	)

--проверка категорий номеров
DELETE FROM AddCosts  
WHERE ADC_Id IN(  
	SELECT ADC_Id FROM AddCosts ac
	LEFT OUTER JOIN RoomsCategory rc ON (ac.ADC_SubCode2 = rc.RC_KEY)
	WHERE ac.ADC_SubCode2 is not null and ac.ADC_SubCode2 > 0 and ac.ADC_SVKey = 3 and rc.RC_KEY is null
	)
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('ClearUnusedAddCostsWithFK.sql', error_message())
END CATCH
end

print '############ end of file ClearUnusedAddCostsWithFK.sql ################'

print '############ begin of file MoveAllCOSvKeyFrom13To12.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--скрипт ищет все цены с svKey = 12, которые находятся в ЦБ с svKey = 13 и заменяет
UPDATE co SET co.CO_SVKey = c.CS_SVKEY
  FROM tbl_Costs c JOIN CostOffers co ON c.CS_COID = co.CO_Id
  where c.CS_SVKEY = 12 and co.CO_SVKey = 13
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('MoveAllCOSvKeyFrom13To12.sql', error_message())
END CATCH
end

print '############ end of file MoveAllCOSvKeyFrom13To12.sql ################'

print '############ begin of file SynchronizeKeyTables.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- 1. удаление из таблицы Keys лишних записей (для которых есть таблица типа Key_ )
declare @tables table(
	tablekey nvarchar(50),
	tablename nvarchar(50)
)

insert into @tables
select key_table, name
from sys.objects 
inner join keys on key_table like replace(name, ''key_'', '''') 
where name like ''key_%'' order by name

declare @sql nvarchar(max)
declare @tablekey nvarchar(50)
declare @tablename nvarchar(50)
declare cur cursor fast_forward read_only
for select tablekey, tablename from @tables

open cur

fetch next from cur into @tablekey, @tablename
while @@fetch_status = 0
begin
	set @sql = ''
		declare @id int

		select @id = id from keys where key_table like '''''' + @tablekey + ''''''

		update '' + @tablename + ''
		set id = @id
		where id < @id

		delete from keys where key_table like '''''' + @tablekey + ''''''
	''
	exec(@sql)
	fetch next from cur into @tablekey, @tablename
end

close cur
deallocate cur

')
END TRY
BEGIN CATCH
insert into ##errors values ('SynchronizeKeyTables.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

-- 2. приводим в соотетствие ключи таблиц и их записи в Keys
update keys
set id = (select isnull(max(rc_key), 0) from RealCourses)
where key_table = ''RealCourses''
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('SynchronizeKeyTables.sql', error_message())
END CATCH
end

print '############ end of file SynchronizeKeyTables.sql ################'

print '############ begin of file CheckQuotaExist.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[CheckQuotaExist]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[CheckQuotaExist]
')
END TRY
BEGIN CATCH
insert into ##errors values ('CheckQuotaExist.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE procedure [dbo].[CheckQuotaExist] 
(
--<DATE>2014-02-20</VERSION>
--<VERSION>2009.2.25</VERSION>
	@SVKey int,
	@Code int,
	@SubCode1 int,
	@DateBeg datetime, 
	@DateEnd datetime,
	@DateFirst datetime,
	@PRKey int,
	@AgentKey int,
	@TourDuration smallint,
	@FilialKey int,				--пока не обрабатывается 
	@CityDepartment int,		--пока не обрабатывается 
	--возвращаемые параметры
	--при наличии Stop-Sale возвращаем

--	Убрал, не нужны более
--	@StopExist int output, --ключ стопа
--	@StopDate smalldatetime output, --дата стопа 

	--переехали из [CheckQuotaInfo]
	@TypeOfResult smallint =null,			
	/*	тип результата 
			0-возвращение полной таблицы данных (без фильтров) используется в экране проверки мест, 
			1-информация о первой подходящей квоте, 
			2-максимальное доступное число мест по всем квотам */	
	@Pax smallint =null,					--кол-во туристов по услуге
	--возвращаемые параметры, в случае @TypeOfResult=2 (попытка проверить возможность постановки услуги на квоту)
	@Wait smallint =null, --в случае не надо снимать квоту,
	@Quota_CheckState smallint =null output,
	/*	0 - RQ (можно бронировать только под запрос)
		1 - OK (можно посадить на квоту)
		2 - STOP (стоп, мест на сущ.квотах недостаточно)
		3 - RELEASE (стопа нет, есть релиз, мест на сущ.квотах недостаточно)	*/
	@Quota_CheckDate smalldatetime =null output,
	/*  если @Quota_Check=2, то в этом поле дата на которую стоит стоп */
	@Quota_CheckInfo smallint =null output,
	/*  если @Quota_Check in (0,3), то в этом поле сколько мест не хватает */

	--возвращаемые параметры, в случае @TypeOfResult=1 (возвращаем характеристики оптимальной квоты)
	@Quota_Count int =null output,
	@Quota_AgentKey int =null output,
	@Quota_Type smallint =null output,
	@Quota_ByRoom bit =null output,
	@Quota_PRKey int =null output, 
	@Quota_FilialKey int =null output,
	@Quota_CityDepartments int =null output,
	@Quota_Duration smallint =null output,
	@Quota_SubCode1 int =null output,
	@Quota_SubCode2 int =null output
	
) AS

if (@SVKey=14)
BEGIN
	select @Code = BP_BTKEY from BusTransferPoints where BP_KEY = @Code
	set @SubCode1 = -1
	set @DateEnd = @DateBeg
end

if (@Wait=1 AND @TypeOfResult=2)
BEGIN
	set @Quota_CheckState=0
	return 0
end
declare @quoted smallint
select @quoted = isnull(SV_Quoted, 0) from Service where SV_Key = @SVKEY
if (@quoted = 0)
BEGIN
	set @Quota_CheckState=1
	return 0
end
Set @DateFirst=ISNULL(@DateFirst,@DateBeg)

declare @LimitAgentQuote bit, @LimitQuoteLong bit
set @LimitAgentQuote = 0
set @LimitQuoteLong = 0

IF EXISTS(SELECT top 1 1 FROM dbo.SystemSettings WHERE SS_ParmName=''SYSLimitAgentQuote'' and SS_ParmValue = 1)
	set @LimitAgentQuote = 1
IF EXISTS(SELECT top 1 1 FROM dbo.SystemSettings WHERE SS_ParmName=''SYSLimitQuoteLong'' and SS_ParmValue = 1)
	set @LimitQuoteLong = 1

--Проверка отсутствия Стопа
declare @StopExist int, @StopDate smalldatetime

exec CheckStopInfo 1,null,@SVKey,@Code,@SubCode1,@PRKey,@DateBeg,@DateEnd,@StopExist output,@StopDate output

declare @Q_QTID int, @Q_Partner int, @Q_ByRoom int, @Q_Type int, @Q_Release int, 
		@Q_FilialKey int, @Q_CityDepartments int, @Q_AgentKey int, @Q_Duration smallint,
		@Q_Places smallint, @ServiceWithDuration bit, @SubQuery varchar(5000), @Query varchar(5000),
		@Q_SubCode1 int, @Q_SubCode2 int, @Q_QTID_Prev int, @DaysCount int, @Q_IsByCheckIn smallint

SET @DaysCount=DATEDIFF(DAY,@DateBeg,@DateEnd)+1
SET @Q_QTID_Prev=0

SELECT @ServiceWithDuration=ISNULL(SV_IsDuration,0) FROM [Service] WHERE SV_Key=@SVKey
IF @ServiceWithDuration=1
	SET @TourDuration=DATEDIFF(DAY,@DateBeg,@DateEnd)+1

-- karimbaeva 28-04-2012 чтобы не выводилось сообщение о недостатке квоты на дополнительное место, если квота последняя и размещение на номер 
IF @SVKey = 3
begin
	if exists(SELECT TOP 1 1 FROM QuotaObjects, Quotas, QuotaDetails, QuotaParts, HotelRooms WHERE QD_QTID=QT_ID and QD_ID=QP_QDID and QO_QTID=QT_ID
	and HR_Key=@SubCode1 and HR_MAIN=0 and QT_ByRoom = 1 and (QP_AgentKey=@AgentKey or QP_AgentKey is null)
	and (QT_PRKey=@PRKey or QT_PRKey=0) and QO_Code=@Code and QD_Date between @DateBeg and @DateEnd and QP_Date = QD_Date
	and QP_ID in (select SD_QPID
					from ServiceByDate as SBD2 join RoomPlaces as RP2 on SBD2.SD_RPID = RP2.RP_ID
					where RP2.RP_Type = 0))
	begin
		set @Quota_CheckInfo = 0
		Set @Quota_CheckState = 1
		If @StopExist > 0
		BEGIN
			Set @Quota_CheckState = 2						
			Set @Quota_CheckDate = @StopDate
		END
		return 0
	end
end

-- создаем таблицу со стопами
CREATE TABLE #StopSaleTemp
(SST_Code int, SST_SubCode1 int, SST_SubCode2 int, SST_QOID int, SST_PRKey int, SST_Date smalldatetime,
SST_QDID int, SST_Type smallint, SST_State smallint, SST_Comment varchar(255)
)

-- Task 9148 31.10.2012 ошибка при преобразовании datetime в smalldatetime
if @DateBeg<''1900-01-01''
	set @DateBeg=''1900-01-01''
--
INSERT INTO #StopSaleTemp exec dbo.GetTableQuotaDetails NULL, @Q_QTID, @DateBeg, @DaysCount, null, null, @SVKey, @Code, @SubCode1, @PRKey

IF @SVKey = 3
BEGIN
	declare CheckQuotaExistСursor cursor for 
		select	DISTINCT QT_ID, QT_PRKey, QT_ByRoom, 
				QD_Type, 
				QP_FilialKey, QP_CityDepartments, QP_AgentKey, CASE WHEN QP_Durations='''' THEN 0 ELSE @TourDuration END, QP_FilialKey, QP_CityDepartments, 
				QO_SubCode1, QO_SubCode2, QT_IsByCheckIn
		from	QuotaObjects, Quotas, QuotaDetails, QuotaParts, HotelRooms
		where	QO_SVKey=@SVKey and QO_Code=@Code and HR_Key=@SubCode1 and (QO_SubCode1=HR_RMKey or QO_SubCode1=0) and (QO_SubCode2=HR_RCKey or QO_SubCode2=0) and QO_QTID=QT_ID
			and QD_QTID=QT_ID and QD_Date between @DateBeg and @DateEnd
			and QP_Date = QD_Date
			and QP_QDID = QD_ID
			and (QP_AgentKey=@AgentKey or QP_AgentKey is null) 
			and (QT_PRKey=@PRKey or QT_PRKey=0)
			and QP_IsDeleted is null and QD_IsDeleted is null	
			and (QP_Durations = '''' or @TourDuration in (Select QL_Duration From QuotaLimitations Where QL_QPID=QP_ID))
			and not exists(select top 1 1
							from #StopSaleTemp 
							where SST_PRKey = QT_PRKey
							and SST_QOID = QO_ID
							and SST_QDID = QD_ID
							and SST_Date = QD_Date
							and SST_State is not null)
		group by QT_ID, QT_PRKey, QT_ByRoom, QD_Type, QP_FilialKey, QP_CityDepartments, QP_AgentKey, QP_Durations, QO_SubCode1, QO_SubCode2, QT_IsByCheckIn
		--having Count(*) = (@Days+1)
		order by QP_AgentKey DESC, QT_PRKey DESC
END
ELSE
BEGIN
	declare CheckQuotaExistСursor cursor for 
		select	DISTINCT QT_ID, QT_PRKey, QT_ByRoom, 
				QD_Type, 
				QP_FilialKey, QP_CityDepartments, QP_AgentKey, CASE WHEN QP_Durations='''' THEN 0 ELSE @TourDuration END, QP_FilialKey, QP_CityDepartments, 
				QO_SubCode1, QO_SubCode2, QT_IsByCheckIn
		from	QuotaObjects, Quotas, QuotaDetails, QuotaParts
		where	
			QO_SVKey = @SVKey and QO_Code = @Code and (QO_SubCode1=@SubCode1 or QO_SubCode1=0) and QO_QTID=QT_ID
			and QD_QTID = QT_ID and QD_Date between @DateBeg and @DateEnd
			and QP_QDID = QD_ID
			and QP_Date = QD_Date
			and (QP_AgentKey=@AgentKey or QP_AgentKey is null) 
			and (QT_PRKey=@PRKey or QT_PRKey=0)
			and QP_IsDeleted is null and QD_IsDeleted is null	
			and (QP_Durations = '''' or @TourDuration in (Select QL_Duration From QuotaLimitations Where QL_QPID=QP_ID))
			and not exists(select top 1 1
							from #StopSaleTemp 
							where SST_PRKey = QT_PRKey
							and SST_QOID = QO_ID
							and SST_QDID = QD_ID
							and SST_Date = QD_Date
							and SST_State is not null)
		group by QT_ID, QT_PRKey, QT_ByRoom, QD_Type, QP_FilialKey, QP_CityDepartments, QP_AgentKey, QP_Durations, QO_SubCode1, QO_SubCode2, QT_IsByCheckIn
		order by QP_AgentKey DESC, QT_PRKey DESC
END
open CheckQuotaExistСursor
fetch CheckQuotaExistСursor into	@Q_QTID, @Q_Partner, @Q_ByRoom, 
									@Q_Type, 
									@Q_FilialKey, @Q_CityDepartments, @Q_AgentKey, @Q_Duration, @Q_FilialKey, @Q_CityDepartments, 
									@Q_SubCode1, @Q_SubCode2, @Q_IsByCheckIn

CREATE TABLE #Tbl (	TMP_Count int, TMP_QTID int, TMP_AgentKey int, TMP_Type smallint, TMP_Date datetime, 
					TMP_ByRoom bit, TMP_Release smallint, TMP_Partner int, TMP_Durations nvarchar(25) COLLATE Cyrillic_General_CI_AS, TMP_FilialKey int, 
					TMP_CityDepartments int, TMP_SubCode1 int, TMP_SubCode2 int, TMP_IsByCheckIn smallint, TMP_DurationsCheckIn nvarchar(25))

While (@@fetch_status = 0)
BEGIN
	SET @SubQuery = ''QD_QTID = QT_ID and QP_QDID = QD_ID 
		and QT_ID='' + CAST(@Q_QTID as varchar(10)) + ''
		and QT_ByRoom='' + CAST(@Q_ByRoom as varchar(1)) + '' 
		and QD_Type='' + CAST(@Q_Type as varchar(1)) + '' 
		and QO_SVKey='' + CAST(@SVKey as varchar(10)) + ''
		and QO_Code='' + CAST(@Code as varchar(10)) + '' 
		and QO_SubCode1='' + CAST(@Q_SubCode1 as varchar(10)) + '' 
		and QO_SubCode2='' + CAST(@Q_SubCode2 as varchar(10)) + ''	
		and (QD_Date between '''''' + CAST((@DateBeg) as varchar(20)) + '''''' and '''''' + CAST(@DateEnd as varchar(20)) + '''''') and QD_IsDeleted is null''

	IF @Q_FilialKey is null
		SET @SubQuery = @SubQuery + '' and QP_FilialKey is null''
	ELSE
		SET @SubQuery = @SubQuery + '' and QP_FilialKey='' + CAST(@Q_FilialKey as varchar(10))
	IF @Q_CityDepartments is null
		SET @SubQuery = @SubQuery + '' and QP_CityDepartments is null''
	ELSE
		SET @SubQuery = @SubQuery + '' and QP_CityDepartments='' + CAST(@Q_CityDepartments as varchar(10))
	IF @Q_AgentKey is null
		SET @SubQuery = @SubQuery + '' and QP_AgentKey is null''
	ELSE
		SET @SubQuery = @SubQuery + '' and QP_AgentKey='' + CAST(@Q_AgentKey as varchar(10))		
	IF @Q_Duration=0
		SET @SubQuery = @SubQuery + '' and QP_Durations = '''''''' ''
	ELSE
		SET @SubQuery = @SubQuery + '' and QP_ID in (Select QL_QPID From QuotaLimitations Where QL_Duration='' + CAST(@Q_Duration as varchar(5)) + '') ''
	IF @Q_Partner =''''
		SET @SubQuery = @SubQuery + '' and QT_PRKey = '''''''' ''
	ELSE
		SET @SubQuery = @SubQuery + '' and QT_PRKey='' + CAST(@Q_Partner as varchar(10))
	IF @Q_IsByCheckIn is null
		SET @SubQuery = @SubQuery + '' and QT_IsByCheckIn is null''
	ELSE
		SET @SubQuery = @SubQuery + '' and QT_IsByCheckIn='' + CAST(@Q_IsByCheckIn as varchar(10))

	declare @SubCode2 int

	IF (@Q_IsByCheckIn = 0 or @Q_IsByCheckIn is null)
		SET @Query = 
		''
		INSERT INTO #Tbl (	TMP_Count, TMP_QTID, TMP_AgentKey, TMP_Type, TMP_Date, 
							TMP_ByRoom, TMP_Release, TMP_Partner, TMP_Durations, TMP_FilialKey, 
							TMP_CityDepartments, TMP_SubCode1, TMP_SubCode2, TMP_IsByCheckIn, TMP_DurationsCheckIn)
			SELECT	DISTINCT QP_Places-QP_Busy as d1, QT_ID, QP_AgentKey, QD_Type, QD_Date, 
					QT_ByRoom, QD_Release, QT_PRKey, QP_Durations, QP_FilialKey,
					QP_CityDepartments, QO_SubCode1, QO_SubCode2, QT_IsByCheckIn, '''''''' 
			FROM	Quotas QT1, QuotaDetails QD1, QuotaParts QP1, QuotaObjects QO1, #StopSaleTemp
			WHERE	QO_ID = SST_QOID and QD_ID = SST_QDID and SST_State is null and '' + @SubQuery
	
	IF @Q_IsByCheckIn = 1
		SET @Query = 
		''
		INSERT INTO #Tbl (	TMP_Count, TMP_QTID, TMP_AgentKey, TMP_Type, TMP_Date, 
							TMP_ByRoom, TMP_Release, TMP_Partner, TMP_Durations, TMP_FilialKey, 
							TMP_CityDepartments, TMP_SubCode1, TMP_SubCode2, TMP_IsByCheckIn, TMP_DurationsCheckIn)
			SELECT	DISTINCT QP_Places-QP_Busy as d1, QT_ID, QP_AgentKey, QD_Type, QD_Date, 
					QT_ByRoom, QD_Release, QT_PRKey, QP_Durations, QP_FilialKey,
					QP_CityDepartments, QO_SubCode1, QO_SubCode2, QT_IsByCheckIn, convert(nvarchar(max) ,QD_LongMin) + ''''-'''' + convert(nvarchar(max) ,QD_LongMax)
			FROM	Quotas QT1, QuotaDetails QD1, QuotaParts QP1, QuotaObjects QO1, #StopSaleTemp
			WHERE	QO_ID = SST_QOID and QD_ID = SST_QDID and SST_State is null and '' + @SubQuery
			
	--print @Query

	exec (@Query)
	
	SET @Q_QTID_Prev=@Q_QTID
	fetch CheckQuotaExistСursor into	@Q_QTID, @Q_Partner, @Q_ByRoom, 
										@Q_Type, 
										@Q_FilialKey, @Q_CityDepartments, @Q_AgentKey, @Q_Duration, @Q_FilialKey, @Q_CityDepartments, 
										@Q_SubCode1, @Q_SubCode2, @Q_IsByCheckIn	
END

--select * from #tbl

/*
Обработаем настройки
						При наличии квоты на агенство, запретить бронирование из общей квоты
						При наличии квоты на продолжительность, запретить бронировать из квоты без продолжительности
*/

-- если стоят 2 настройки и параметры пришли и на продолжительность и на агенство и есть такая квота сразу на агенство и на продолжительность,
-- то удалим остальные
if ((@LimitAgentQuote = 1) and (@LimitQuoteLong = 1))
begin
	if ((isnull(@AgentKey, 0) != 0) and (isnull(@TourDuration, 0) != 0) and (exists (select top 1 1 from #Tbl where isnull(TMP_AgentKey, 0) = @AgentKey and isnull(TMP_Durations, 0) = @TourDuration)))
	begin
		delete #Tbl where isnull(TMP_AgentKey, 0) != @AgentKey or isnull(TMP_Durations, 0) != @TourDuration
	end
	
	--бывают случаии когда обе настройки включены, но найти нужно только по одному из параметров
	if (exists (select top 1 1 from #Tbl where isnull(TMP_AgentKey, 0) = @AgentKey))
	begin
		delete #Tbl where isnull(TMP_AgentKey, 0) != @AgentKey
	end
	if (exists (select top 1 1 from #Tbl where isnull(TMP_Durations, 0) = @TourDuration))
	begin
		delete #Tbl where isnull(TMP_Durations, 0) != @TourDuration
	end
end
-- если стоит настройка только на агенство и нам пришол параметром агенство и квота на агенство есть,
-- то удалим остальные
else if ((@LimitAgentQuote = 1) and (@LimitQuoteLong = 0) and (isnull(@AgentKey, 0) != 0) and (exists (select top 1 1 from #Tbl where isnull(TMP_AgentKey, 0) = @AgentKey)))
begin
	delete #Tbl where isnull(TMP_AgentKey, 0) != @AgentKey
end
-- если есть настройка на продолжительность, и нам пришол параметр продолжительность и есть квота на продолжительность,
-- то удалим остальные
else if ((@LimitAgentQuote = 0) and (@LimitQuoteLong = 1) and (isnull(@TourDuration, 0) != 0) and (exists (select top 1 1 from #Tbl where isnull(TMP_Durations, 0) = @TourDuration)))
begin
	delete #Tbl where isnull(TMP_Durations, 0) != @TourDuration	
end

DELETE FROM #Tbl WHERE exists 
		(SELECT top 1 1  FROM QuotaParts QP2, QuotaDetails QD2, Quotas QT2 
		WHERE	QT_ID=QD_QTID and QP_QDID=QD_ID
				and QD_Type=TMP_Type and QT_ByRoom=TMP_ByRoom
				and QD_IsDeleted is null and QP_IsDeleted is null
				and QT_ID=TMP_QTID
				and ISNULL(QP_FilialKey,-1)=ISNULL(TMP_FilialKey,-1) and ISNULL(QP_CityDepartments,-1)=ISNULL(TMP_CityDepartments,-1)
				and ISNULL(QP_AgentKey,-1)=ISNULL(TMP_AgentKey,-1) and ISNULL(QT_PRKey,-1)=ISNULL(TMP_Partner,-1)
				and QP_Durations=TMP_Durations and ISNULL(QD_Release,-1)=ISNULL(TMP_Release,-1)
				and QD_Date=@DateFirst and (QP_IsNotCheckIn=1 or QP_CheckInPlaces-QP_CheckInPlacesBusy <= 0))

close CheckQuotaExistСursor
deallocate CheckQuotaExistСursor

DECLARE @Tbl_DQ Table 
 		(TMP_Count smallint, TMP_AgentKey int, TMP_Type smallint, TMP_ByRoom bit, 
				TMP_Partner int, TMP_Duration smallint, TMP_FilialKey int, TMP_CityDepartments int,
				TMP_SubCode1 int, TMP_SubCode2 int, TMP_ReleaseIgnore bit, TMP_IsByCheckIn smallint, TMP_DurationsCheckIn nvarchar(25))

DECLARE @DATETEMP datetime
SET @DATETEMP = GetDate()
-- Разрешим посадить в квоту с релиз периодом 0 текущим числом
set @DATETEMP = DATEADD(day, -1, @DATETEMP)
if exists (select top 1 1 from systemsettings where SS_ParmName=''SYSAddQuotaPastPermit'' and SS_ParmValue=1 and @DateBeg < @DATETEMP)
	SET @DATETEMP=''01-JAN-1900''
INSERT INTO @Tbl_DQ
	SELECT	MIN(d1) as TMP_Count, TMP_AgentKey, TMP_Type, TMP_ByRoom, TMP_Partner, 
			d2 as TMP_Duration, TMP_FilialKey, TMP_CityDepartments, TMP_SubCode1, TMP_SubCode2, 0 as TMP_ReleaseIgnore, TMP_IsByCheckIn, TMP_DurationsCheckIn FROM
		(SELECT	SUM(TMP_Count) as d1, TMP_Type, TMP_ByRoom, TMP_AgentKey, TMP_Partner, 
				TMP_FilialKey, TMP_CityDepartments, TMP_Date, CASE WHEN TMP_Durations='''' THEN 0 ELSE @TourDuration END as d2, TMP_SubCode1, TMP_SubCode2, TMP_IsByCheckIn, TMP_DurationsCheckIn
		FROM	#Tbl
		WHERE	(TMP_Date >= @DATETEMP + ISNULL(TMP_Release,0) OR (TMP_Date < GETDATE() - 1))
		GROUP BY	TMP_Type, TMP_ByRoom, TMP_AgentKey, TMP_Partner,
					TMP_FilialKey, TMP_CityDepartments, TMP_Date, CASE WHEN TMP_Durations='''' THEN 0 ELSE @TourDuration END, TMP_SubCode1, TMP_SubCode2, TMP_IsByCheckIn, TMP_DurationsCheckIn) D
	GROUP BY	TMP_Type, TMP_ByRoom, TMP_AgentKey, TMP_Partner,
				TMP_FilialKey, TMP_CityDepartments, d2, TMP_SubCode1, TMP_SubCode2, TMP_IsByCheckIn, TMP_DurationsCheckIn
	HAVING count(*)=DATEDIFF(day,@DateBeg,@DateEnd)+1
	UNION
	SELECT	MIN(d1) as TMP_Count, TMP_AgentKey, TMP_Type, TMP_ByRoom, TMP_Partner, 
			d2 as TMP_Duration, TMP_FilialKey, TMP_CityDepartments, TMP_SubCode1, TMP_SubCode2, 1 as TMP_ReleaseIgnore, TMP_IsByCheckIn, TMP_DurationsCheckIn FROM
		(SELECT	SUM(TMP_Count) as d1, TMP_Type, TMP_ByRoom, TMP_AgentKey, TMP_Partner, 
				TMP_FilialKey, TMP_CityDepartments, TMP_Date, CASE WHEN TMP_Durations='''' THEN 0 ELSE @TourDuration END as d2, TMP_SubCode1, TMP_SubCode2, TMP_IsByCheckIn, TMP_DurationsCheckIn
		FROM	#Tbl
		GROUP BY	TMP_Type, TMP_ByRoom, TMP_AgentKey, TMP_Partner,
					TMP_FilialKey, TMP_CityDepartments, TMP_Date, CASE WHEN TMP_Durations='''' THEN 0 ELSE @TourDuration END, TMP_SubCode1, TMP_SubCode2, TMP_IsByCheckIn, TMP_DurationsCheckIn) D
	GROUP BY	TMP_Type, TMP_ByRoom, TMP_AgentKey, TMP_Partner,
				TMP_FilialKey, TMP_CityDepartments, d2, TMP_SubCode1, TMP_SubCode2, TMP_IsByCheckIn, TMP_DurationsCheckIn
	HAVING count(*)=DATEDIFF(day,@DateBeg,@DateEnd)+1

/*
Комментарии к запросу выше!!!
Заполняем таблицу квот, которые могут нам подойти (группируя квоты по всем разделяемым параметрам, кроме релиз-периода
Все строки в таблице дублируются (важно! 11-ый параметр): 
	квоты с учетом релиз-периода (0) --TMP_ReleaseIgnore
	квоты без учета релиз-периода (1)--TMP_ReleaseIgnore
При выводе всех доступных квот требуется отсекать строки без учета релиз-периода и с количеством мест <=0 
*/

DECLARE @IsCommitmentFirst bit
IF Exists (SELECT SS_ID FROM dbo.SystemSettings WHERE SS_ParmName=''SYS_Commitment_First'' and SS_ParmValue=''1'')
	SET @IsCommitmentFirst=1

If @TypeOfResult is null or @TypeOfResult=0
BEGIN
	IF @IsCommitmentFirst=1
		select * from @Tbl_DQ order by TMP_IsByCheckIn DESC
	ELSE
		select * from @Tbl_DQ order by TMP_IsByCheckIn DESC
END

DECLARE @Priority int;
SELECT @Priority=QPR_Type FROM   QuotaPriorities 
WHERE  QPR_Date=@DateFirst and QPR_SVKey = @SVKey and QPR_Code=@Code and QPR_PRKey=@PRKey

IF @Priority is not null
	SET @IsCommitmentFirst=@Priority-1

If @TypeOfResult=1 --(возвращаем характеристики оптимальной квоты)
BEGIN
	If exists (SELECT top 1 1 FROM @Tbl_DQ)
	BEGIN
		IF @Quota_Type=1 or @IsCommitmentFirst=1
			select	TOP 1 @Quota_Count=TMP_Count, 
					@Quota_AgentKey=TMP_AgentKey, @Quota_Type=TMP_Type, @Quota_ByRoom=TMP_ByRoom,
					@Quota_PRKey=TMP_Partner, @Quota_FilialKey=TMP_FilialKey, @Quota_CityDepartments=TMP_CityDepartments, 
					@Quota_Duration=TMP_Duration, @Quota_SubCode1=TMP_SubCode1, @Quota_SubCode2=TMP_SubCode2
			from	@Tbl_DQ 
			where	TMP_Count>0 and TMP_ReleaseIgnore=0
			order by TMP_ReleaseIgnore, TMP_Type DESC, TMP_Partner DESC, TMP_AgentKey DESC, TMP_SubCode1 DESC, TMP_SubCode2 DESC, TMP_Duration DESC
		ELSE
			select	TOP 1 @Quota_Count=TMP_Count, 
					@Quota_AgentKey=TMP_AgentKey, @Quota_Type=TMP_Type, @Quota_ByRoom=TMP_ByRoom,
					@Quota_PRKey=TMP_Partner, @Quota_FilialKey=TMP_FilialKey, @Quota_CityDepartments=TMP_CityDepartments, 
					@Quota_Duration=TMP_Duration, @Quota_SubCode1=TMP_SubCode1, @Quota_SubCode2=TMP_SubCode2
			from	@Tbl_DQ 
			where	TMP_Count>0 and TMP_ReleaseIgnore=0
			order by TMP_ReleaseIgnore, TMP_Type, TMP_Partner DESC, TMP_AgentKey DESC, TMP_SubCode1 DESC, TMP_SubCode2 DESC, TMP_Duration DESC
	END
END

	--Проверим на стоп	
	--если есть два стопа, то это либо общий стоп, либо два отдельных стопа
	if @StopExist > 1
		and exists(select 1 from #StopSaleTemp where SST_State is not null and SST_Date between @DateBeg and @DateEnd and SST_Type=1)
		and exists(select 1 from #StopSaleTemp where SST_State is not null and SST_Date between @DateBeg and @DateEnd and SST_Type=2)
	BEGIN
		Set @Quota_CheckState = 2
		Set @Quota_CheckDate = @StopDate
		return
	END
	
	--если существуют стоп на один тип квот, а другой тип квот заведен неполностью или не заведен вовсе
	if (@StopExist > 0
			and
			(
				exists(select 1 from #StopSaleTemp where SST_Date between @DateBeg and @DateEnd and SST_Type=1 and SST_State is not null)
				and (select count (distinct TMP_Date) from #Tbl where TMP_QTID not in (select TMP_QTID from #Tbl,#StopSaleTemp where TMP_Date=SST_Date and SST_State=2 and SST_Type=1) and TMP_Type=1) > 0
				and (select count (distinct TMP_Date) from #Tbl where TMP_QTID not in (select TMP_QTID from #Tbl,#StopSaleTemp where TMP_Date=SST_Date and SST_State=2 and SST_Type=2) and TMP_Type=2) < @DaysCount
				or
				exists(select 1 from #StopSaleTemp where SST_Date between @DateBeg and @DateEnd and SST_Type=2 and SST_State is not null)
				and (select count (distinct TMP_Date) from #Tbl where TMP_QTID not in (select TMP_QTID from #Tbl,#StopSaleTemp where TMP_Date=SST_Date and SST_State=2 and SST_Type=2) and TMP_Type=2) > 0
				and (select count (distinct TMP_Date) from #Tbl where TMP_QTID not in (select TMP_QTID from #Tbl,#StopSaleTemp where TMP_Date=SST_Date and SST_State=2 and SST_Type=1) and TMP_Type=1) < @DaysCount
			)
		)
	BEGIN
		Set @Quota_CheckState = 2
		Set @Quota_CheckDate = @StopDate
		return
	END

	--если существуют два стопа и нет дней с незаведенными квотами
	if (@StopExist > 0 and
		exists(select 1 from #StopSaleTemp where SST_Date between @DateBeg and @DateEnd and SST_Type=1 and SST_State is not null) and
		exists(select 1 from #StopSaleTemp where SST_Date between @DateBeg and @DateEnd and SST_Type=2 and SST_State is not null) and
		((select COUNT(distinct SST_Date) from #StopSaleTemp where SST_Type=1) = @DaysCount) and
			((select COUNT(distinct SST_Date) from #StopSaleTemp where SST_Type=2) = @DaysCount))
	BEGIN
		Set @Quota_CheckState = 2
		Set @Quota_CheckDate = @StopDate
		return
	END

	--если есть стоп на commitment и закончился релиз-период на alotment, или наоборот...
	if (not exists(select 1 from #Tbl where TMP_Type=2 and TMP_Date = @DateBeg and dateadd(day, -1, GETDATE()) < (@DateBeg - ISNULL(TMP_Release, 0)))
		and
		(select count (distinct TMP_Date) from #Tbl where TMP_QTID not in (select TMP_QTID from #Tbl,#StopSaleTemp where TMP_Date=SST_Date and SST_State=2 and SST_Type=TMP_Type) and TMP_Type=1) < @DaysCount
		or
		not exists(select 1 from #Tbl where TMP_Type=1 and TMP_Date = @DateBeg and dateadd(day, -1, GETDATE()) < (@DateBeg - ISNULL(TMP_Release, 0)))
		and
		(select count (distinct TMP_Date) from #Tbl where TMP_QTID not in (select TMP_QTID from #Tbl,#StopSaleTemp where TMP_Date=SST_Date and SST_State=2 and SST_Type=TMP_Type) and TMP_Type=2) < @DaysCount)
	begin
		if exists(select 1 from #Tbl where TMP_Release is not null and TMP_Release!=0 and TMP_Date = @DateBeg AND dateadd(day, -1, GETDATE()) >= (@DateBeg - ISNULL(TMP_Release, 0)))
		begin
			set @Quota_CheckState = 3	-- наступил РЕЛИЗ-Период
			return
		end
	end
	
	--если существует стоп и на первый день нет квот
	If @StopExist > 0 and not exists (select 1 from #Tbl where TMP_Count > 0 and TMP_Date = @DateBeg)
	BEGIN
		Set @Quota_CheckState = 2						--Возвращаем "Внимание STOP"
		Set @Quota_CheckDate = @StopDate
		return
	END
	
	--Проверим на наличие квот
	if not exists (select 1 from #Tbl where TMP_Count > 0)
	begin
		Set @Quota_CheckState = 0
		return
	end

If @TypeOfResult=2 --(попытка проверить возможность постановки услуги на квоту)
BEGIN
	DECLARE @Places_Count int, @Rooms_Count int,		 --доступное количество мест/номеров в квотах
			@Places_Count_ReleaseIgnore int, @Rooms_Count_ReleaseIgnore int,		 --доступное количество мест/номеров в квотах
			@PlacesNeed_Count smallint,					-- количество мест, которых недостаточно для оформления услуги
			@PlacesNeed_Count_ReleaseIgnore smallint					-- количество мест, которых недостаточно для оформления услуги
	
	If exists (SELECT top 1 1 FROM @Tbl_DQ)
	BEGIN
		set @PlacesNeed_Count = 0
		set @PlacesNeed_Count_ReleaseIgnore = 0
		
		select @Places_Count = SUM(TMP_Count) from @Tbl_DQ where TMP_Count > 0 and TMP_ByRoom = 0 and TMP_ReleaseIgnore = 0
		select @Places_Count_ReleaseIgnore = SUM(TMP_Count) from @Tbl_DQ where TMP_Count > 0 and TMP_ByRoom = 0 and TMP_ReleaseIgnore = 1
		
		If (@SVKey in (3) or (@SVKey=8 and EXISTS(SELECT TOP 1 1 FROM [Service] WHERE SV_KEY=@SVKey AND SV_QUOTED=1)))
		begin
			select @Rooms_Count = SUM(TMP_Count) from @Tbl_DQ where TMP_Count > 0 and TMP_ByRoom = 1 and TMP_ReleaseIgnore = 0
			select @Rooms_Count_ReleaseIgnore = SUM(TMP_Count) from @Tbl_DQ where TMP_Count > 0 and TMP_ByRoom = 1 and TMP_ReleaseIgnore = 1
		end
		
		Set @Places_Count = ISNULL(@Places_Count,0)
		Set @Rooms_Count = ISNULL(@Rooms_Count,0)
		Set @Places_Count_ReleaseIgnore = ISNULL(@Places_Count_ReleaseIgnore,0)
		Set @Rooms_Count_ReleaseIgnore = ISNULL(@Rooms_Count_ReleaseIgnore,0)
		
		SET @StopExist = ISNULL(@StopExist, 0)
		
		--проверяем достаточно ли будет текущего кол-ва мест для бронирования, если нет устанавливаем статус бронирования под запрос
		declare @nPlaces smallint, @nRoomsService smallint
		If ((@SVKey in (3) OR (@SVKey=8 and EXISTS(SELECT TOP 1 1 FROM [Service] WHERE SV_KEY=@SVKey AND SV_QUOTED=1))) and @Rooms_Count > 0)
		BEGIN
			Set @nRoomsService = 1
			
			if (@SVKey = 3)
				exec GetServiceRoomsCount @Code, @SubCode1, @Pax, @nRoomsService output
			
			If @nRoomsService > @Rooms_Count
			begin
				Set @PlacesNeed_Count = @nRoomsService - @Rooms_Count
				Set @Quota_CheckState = 0
			end
			
			If @nRoomsService > @Rooms_Count_ReleaseIgnore
			begin
				Set @PlacesNeed_Count_ReleaseIgnore = @nRoomsService - @Rooms_Count_ReleaseIgnore
				Set @Quota_CheckState = 0
			end
		END
		ELSE
		begin
			If @Pax > @Places_Count
			begin
				Set @PlacesNeed_Count = @Pax - @Places_Count
				Set @Quota_CheckState = 0
			end 
			
			If @Pax > @Places_Count_ReleaseIgnore
			begin
				Set @PlacesNeed_Count_ReleaseIgnore = @Pax - @Places_Count_ReleaseIgnore
				Set @Quota_CheckState = 0
			end
		end
		
		-- проверим на релиз
		If @PlacesNeed_Count_ReleaseIgnore <= 0 --мест в квоте хватило
			Set @Quota_CheckState = 3						--Возвращаем "Release" (мест не достаточно, но наступил РЕЛИЗ-Период)"
		
		If @PlacesNeed_Count <= 0 --мест в квоте хватило
			Set @Quota_CheckState = 1						--Возвращаем "Ok (квоты есть)"
		else
			set @Quota_CheckInfo = @PlacesNeed_Count
	END
	else
	begin
		-- если выборка пустая
		Set @Quota_CheckState = 0
	end
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('CheckQuotaExist.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on [dbo].[CheckQuotaExist] to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('CheckQuotaExist.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('CheckQuotaExist.sql', error_message())
END CATCH
end

print '############ end of file CheckQuotaExist.sql ################'

print '############ begin of file CheckTourProgramCountry.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[CheckTourProgramCountry]'') AND type in (N''FN''))
DROP FUNCTION [dbo].[CheckTourProgramCountry]

')
END TRY
BEGIN CATCH
insert into ##errors values ('CheckTourProgramCountry.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

create function [dbo].[CheckTourProgramCountry] (@tourkey int, @countryKey int)
RETURNS bit 
as
begin

declare @val varchar (200)

select @val = convert(varchar(200),isnull(TP_XmlSettings.query(N''/TourProgram/TourConsistencyViewModel/Countries[int=sql:variable("@countryKey")]''),'''') )from TourPrograms where TP_Id = @tourkey

if (isnull(@val,'''') = '''')
	return 0 
else 
	return 1

return 0
end

')
END TRY
BEGIN CATCH
insert into ##errors values ('CheckTourProgramCountry.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on [dbo].[CheckTourProgramCountry] to public 
')
END TRY
BEGIN CATCH
insert into ##errors values ('CheckTourProgramCountry.sql', error_message())
END CATCH
end

print '############ end of file CheckTourProgramCountry.sql ################'

print '############ begin of file CheckUserForDisable.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[CheckUserForDisable]'') AND type in (N''P'', N''PC''))
	DROP PROCEDURE [dbo].[CheckUserForDisable]
')
END TRY
BEGIN CATCH
insert into ##errors values ('CheckUserForDisable.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


CREATE PROCEDURE [dbo].[CheckUserForDisable] 

	@userId varchar(20)
AS
BEGIN

	SELECT is_disabled FROM sys.sql_logins WHERE name = @userId

END
')
END TRY
BEGIN CATCH
insert into ##errors values ('CheckUserForDisable.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT EXECUTE on [dbo].[CheckUserForDisable] TO PUBLIC
')
END TRY
BEGIN CATCH
insert into ##errors values ('CheckUserForDisable.sql', error_message())
END CATCH
end

print '############ end of file CheckUserForDisable.sql ################'

print '############ begin of file CheckUserRolesForServerAdmin.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[CheckUserRolesForServerAdmin]'') AND type in (N''P'', N''PC''))
	DROP PROCEDURE [dbo].[CheckUserRolesForServerAdmin]
')
END TRY
BEGIN CATCH
insert into ##errors values ('CheckUserRolesForServerAdmin.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


CREATE PROCEDURE [dbo].[CheckUserRolesForServerAdmin] 

	@userId varchar(30)
AS
BEGIN
			
	SELECT IS_SRVROLEMEMBER(''sysadmin'', @userId)		

END
')
END TRY
BEGIN CATCH
insert into ##errors values ('CheckUserRolesForServerAdmin.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT EXECUTE on [dbo].[CheckUserRolesForServerAdmin] TO PUBLIC
')
END TRY
BEGIN CATCH
insert into ##errors values ('CheckUserRolesForServerAdmin.sql', error_message())
END CATCH
end

print '############ end of file CheckUserRolesForServerAdmin.sql ################'

print '############ begin of file cleanSystemLog.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[cleanSystemLog]'') AND type in (N''P'', N''PC''))
	DROP PROCEDURE [dbo].[cleanSystemLog]
')
END TRY
BEGIN CATCH
insert into ##errors values ('cleanSystemLog.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE PROCEDURE [dbo].[cleanSystemLog]
as
begin
	declare @counter as bigint
	declare @today as datetime
	set @today = getdate()

	declare @deletedRowCount bigint

	-- Удаляем неактуальные логи (остаются логи за последние 7 дней)
	set @counter = 0
	while(1 = 1)
	begin
		delete top (50000) from dbo.SystemLog with(rowlock) where SL_DATE < DATEADD(day, -7, @today)
		set @deletedRowCount = @@ROWCOUNT
		if @deletedRowCount = 0
		begin
			insert into SystemLog (SL_Type, SL_Date, SL_Message, SL_AppID) values(1, GETDATE(), ''Удаление systemLog завершено. Удалено '' + ltrim(str(@counter)) + '' записей'', 1)
			break
		end
		else
			set @counter = @counter + @deletedRowCount
	end

	insert into SystemLog (SL_Type, SL_Date, SL_Message, SL_AppID) values(1, GETDATE(), ''Окончание выполнения CleanSystemLog'', 1)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('cleanSystemLog.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant execute on [dbo].[cleanSystemLog] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('cleanSystemLog.sql', error_message())
END CATCH
end

print '############ end of file cleanSystemLog.sql ################'

print '############ begin of file CostOfferChange.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from sys.procedures where name = ''CostOfferChange'')
begin
	drop procedure CostOfferChange
end

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOfferChange.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE PROCEDURE [dbo].[CostOfferChange]
	(
		-- хранимка активирует деактивирует и публикует ЦБ
		-- ключ ЦБ
		@coId int,
		-- ключ операции 1 - активировать, 2 - деактивировать, 3 - публиковать
		@operationId smallint
	)
AS
BEGIN

	-- временная таблица для цен
	declare @spadIdTable table
	(
		spadId bigint		
	)
	
	-- временная таблица для цен на будущие даты
	declare @spndIdTable table
	(
		spndId bigint
	)

	-- активация ценового блока или деактивация
	if (@operationId = 1 or @operationId = 2)
	begin		
		
		insert into @spadIdTable (spadId)
		select spad.SPAD_Id
		from (dbo.TP_ServicePriceActualDate as spad with (nolock)
				join dbo.TP_ServiceCalculateParametrs as scp with (nolock) on spad.SPAD_SCPId = scp.SCP_Id
				join dbo.TP_ServiceComponents as sc with (nolock) on scp.SCP_SCId = sc.SC_Id)
				cross join
			(CostOffers as [co] with (nolock)
				join dbo.CostOfferServices as [cos] with (nolock) on co.CO_Id = [cos].COS_COID
				join dbo.Seasons as seas with (nolock) on co.CO_SeasonId = seas.SN_Id)
		where
			[co].CO_Id = @coId
			-- должны публиковаться только последние актуальные цены
			and spad.SPAD_SaleDate is null
			and seas.SN_IsActive = 1			
			and SC_SVKey = co.CO_SVKey
			and sc.SC_Code = [cos].COS_CODE
			and scp.SCP_PKKey = co.CO_PKKey
			and SC_PRKey = co.CO_PartnerKey
			-- и только если он ранее был неактивирован или мы его деактивируем
			and (co.CO_State = 0 or co.CO_State = 1)
			--mv 13102012 для индекса	
			and scp.SCP_SvKey = co.CO_SVKey
			--mv 13102012 дата заезда при отборе должна быть ограничена датами заезда в ценах
			and scp.SCP_DateCheckIn between  
						(SELECT MIN(ISNULL(CS_CHECKINDATEBEG,DATEADD(DAY,-1,GetDate()))) FROM dbo.tbl_costs with (nolock) WHERE CS_COID = co.CO_Id and CS_CODE = sc.SC_Code and CS_SVKEY = co.CO_SVKey) 
					and (SELECT MAX(ISNULL(CS_CHECKINDATEEND,''01-01-2100'')) FROM dbo.tbl_costs with (nolock) WHERE CS_COID = co.CO_Id and CS_CODE = sc.SC_Code and CS_SVKEY = co.CO_SVKey)
			--mv 13102012 дата заезда должна быть больше текущей даты
			and scp.SCP_DateCheckIn >= DATEADD(DAY,-1,GetDate())
			--mv 13102012 дата заезда не можеть быть больше максимальной даты в ценах
			and scp.SCP_DateCheckIn <= (SELECT MAX(ISNULL(CS_DATEEND,''01-01-2100'')) FROM dbo.tbl_costs with (nolock) WHERE CS_COID = co.CO_Id and CS_CODE = sc.SC_Code and CS_SVKEY = co.CO_SVKey)
			--mv 13102012 дата заезда + продолжительность тура не можеть быть меньше, чем минимальная дата в ценах
			and DATEADD(DAY, scp.SCP_TourDays, scp.SCP_DateCheckIn) >= (SELECT MIN(ISNULL(CS_DATE,DATEADD(DAY,-1,GetDate()))) FROM dbo.tbl_costs with (nolock) WHERE CS_COID = co.CO_Id and CS_CODE = sc.SC_Code and CS_SVKEY = co.CO_SVKey)
		
		-- в ценах которые расчитали на будущее, тоже нужно пересчитать	
		insert into @spndIdTable (spndId)
		select spnd.SPND_Id
		from (dbo.TP_ServicePriceNextDate as spnd with (nolock)
				join dbo.TP_ServiceCalculateParametrs as scp with (nolock) on spnd.SPND_SCPId = scp.SCP_Id
				join dbo.TP_ServiceComponents as sc with (nolock) on scp.SCP_SCId = sc.SC_Id)
				cross join
			(CostOffers as [co] with (nolock)
				join dbo.CostOfferServices as [cos] with (nolock) on [co].CO_Id = [cos].COS_COID
				join dbo.Seasons as seas with (nolock) on [co].CO_SeasonId = seas.SN_Id)
		where	
			[co].CO_Id = @coId		
			and seas.SN_IsActive = 1
			and SC_SVKey = [co].CO_SVKey
			and sc.SC_Code = [cos].COS_CODE
			and scp.SCP_PKKey = [co].CO_PKKey
			and SC_PRKey = [co].CO_PartnerKey
			-- и только если он ранее был неактивирован или мы его деактивировали
			and ([co].CO_State = 0)
			--mv 13102012 для индекса	
			and scp.SCP_SvKey = [co].CO_SVKey
			--mv 13102012 дата заезда при отборе должна быть ограничена датами заезда в ценах
			and scp.SCP_DateCheckIn between  
						(SELECT MIN(ISNULL(CS_CHECKINDATEBEG,DATEADD(DAY,-1,GetDate()))) FROM dbo.tbl_costs with (nolock) WHERE CS_COID = [co].CO_Id and CS_CODE = sc.SC_Code and CS_SVKEY = [co].CO_SVKey) 
					and (SELECT MAX(ISNULL(CS_CHECKINDATEEND,''01-01-2100'')) FROM dbo.tbl_costs with (nolock) WHERE CS_COID = [co].CO_Id and CS_CODE = sc.SC_Code and CS_SVKEY = [co].CO_SVKey)
			--mv 13102012 дата заезда должна быть больше текущей даты
			and scp.SCP_DateCheckIn >= DATEADD(DAY,-1,GetDate())
			--mv 13102012 дата заезда не можеть быть больше максимальной даты в ценах
			and scp.SCP_DateCheckIn <= (SELECT MAX(ISNULL(CS_DATEEND,''01-01-2100'')) FROM dbo.tbl_costs with (nolock) WHERE CS_COID = [co].CO_Id and CS_CODE = sc.SC_Code and CS_SVKEY = [co].CO_SVKey)
			--mv 13102012 дата заезда + продолжительность тура не можеть быть меньше, чем минимальная дата в ценах
			and DATEADD(DAY, scp.SCP_TourDays, scp.SCP_DateCheckIn) >= (SELECT MIN(ISNULL(CS_DATE,DATEADD(DAY,-1,GetDate()))) FROM dbo.tbl_costs with (nolock) WHERE CS_COID = [co].CO_Id and CS_CODE = sc.SC_Code and CS_SVKEY = [co].CO_SVKey)
			
		while(exists (select top 1 1 from @spadIdTable))
		begin			
			update top (10000) spad
			set 
			spad.SPAD_NeedApply = 1,
			spad.SPAD_DateLastChange = getdate()
			from dbo.TP_ServicePriceActualDate as spad join @spadIdTable on spad.SPAD_Id = spadId
			
			delete @spadIdTable 
			where exists (	select top 1 1 
							from dbo.TP_ServicePriceActualDate as spad with(nolock) 
							where spad.SPAD_Id = spadId 
							and (spad.SPAD_NeedApply = 1))
		end
			
		while(exists (select top 1 1 from @spndIdTable))
		begin			
			update top (10000) spnd
			set spnd.SPND_NeedApply = 1,
			spnd.SPND_DateLastChange = getdate()
			from dbo.TP_ServicePriceNextDate as spnd join @spndIdTable on spnd.SPND_Id = spndId
			
			delete @spndIdTable 
			where exists (	select top 1 1 
							from dbo.TP_ServicePriceNextDate as spnd with(nolock) 
							where spnd.SPND_Id = spndId
							and spnd.SPND_NeedApply = 1)
		end
		
		-- временная затычка что бы не запускать тригер
		insert into Debug (db_Date, db_Mod, db_n1)
		values (getdate(), ''COS'', @coId)

		if (@operationId = 1)
		begin
			-- переводим ЦБ в активное состояние					
			update CostOffers
			set CO_State = 1, CO_DateActive = getdate()
			where CO_Id = @coId
		end
		else if (@operationId = 2)
		begin
			-- переводим ЦБ в закрытое состояние					
			update CostOffers
			set CO_State = 2, CO_DateClose = getdate()
			where CO_Id = @coId
		end
	end	
	-- публикация ценового блока
	else if (@operationId = 3)
	begin
		insert into @spadIdTable (spadId)
		select spad.SPAD_Id
		from (dbo.TP_ServicePriceActualDate as spad with (nolock)
				join dbo.TP_ServiceCalculateParametrs as scp with (nolock) on spad.SPAD_SCPId = scp.SCP_Id
				join dbo.TP_ServiceComponents as sc with (nolock) on scp.SCP_SCId = sc.SC_Id)
				cross join
			(CostOffers as [co] with (nolock)
				join dbo.CostOfferServices as [cos] with (nolock) on [co].CO_Id = [cos].COS_COID
				join dbo.Seasons as seas with (nolock) on [co].CO_SeasonId = seas.SN_Id)
		where
			[co].CO_Id = @coId
			-- должны публиковаться только последние актуальные цены
			and spad.SPAD_SaleDate is null
			and seas.SN_IsActive = 1			
			and SC_SVKey = [co].CO_SVKey
			and sc.SC_Code = [cos].COS_CODE
			and scp.SCP_PKKey = [co].CO_PKKey
			and SC_PRKey = [co].CO_PartnerKey
			-- и дата продажи ценового блока должна быть вокруг текущей даты
			and getdate() between isnull([co].CO_SaleDateBeg, ''1900-01-01'') and isnull([co].CO_SaleDateEnd, ''2072-01-01'')
			--mv 13102012 для индекса	
			and scp.SCP_SvKey = [co].CO_SVKey
			--mv 13102012 дата заезда при отборе должна быть ограничена датами заезда в ценах
			and scp.SCP_DateCheckIn between  
						(SELECT MIN(ISNULL(CS_CHECKINDATEBEG,DATEADD(DAY,-1,GetDate()))) FROM dbo.tbl_costs with (nolock) WHERE CS_COID = [co].CO_Id and CS_CODE = sc.SC_Code and CS_SVKEY = [co].CO_SVKey) 
					and (SELECT MAX(ISNULL(CS_CHECKINDATEEND,''01-01-2100'')) FROM dbo.tbl_costs with (nolock) WHERE CS_COID = [co].CO_Id and CS_CODE = sc.SC_Code and CS_SVKEY = [co].CO_SVKey)
			--mv 13102012 дата заезда должна быть больше текущей даты
			and scp.SCP_DateCheckIn >= DATEADD(DAY,-1,GetDate())
			--mv 13102012 дата заезда не можеть быть больше максимальной даты в ценах
			and scp.SCP_DateCheckIn <= (SELECT MAX(ISNULL(CS_DATEEND,''01-01-2100'')) FROM dbo.tbl_costs with (nolock) WHERE CS_COID = [co].CO_Id and CS_CODE = sc.SC_Code and CS_SVKEY = [co].CO_SVKey)
			--mv 13102012 дата заезда + продолжительность тура не можеть быть меньше, чем минимальная дата в ценах
			and DATEADD(DAY, scp.SCP_TourDays, scp.SCP_DateCheckIn) >= (SELECT MIN(ISNULL(CS_DATE,DATEADD(DAY,-1,GetDate()))) FROM dbo.tbl_costs with (nolock) WHERE CS_COID = [co].CO_Id and CS_CODE = sc.SC_Code and CS_SVKEY = [co].CO_SVKey)
			
		while(exists (select top 1 1 from @spadIdTable))
		begin			
			update top (10000) spad
			set 			
			spad.SPAD_AutoOnline = 1,
			spad.SPAD_DateLastChange = getdate()
			from dbo.TP_ServicePriceActualDate as spad join @spadIdTable on spad.SPAD_Id = spadId
			
			delete @spadIdTable 
			where exists (	select top 1 1 
							from dbo.TP_ServicePriceActualDate as spad with(nolock) 
							where spad.SPAD_Id = spadId 
							and (spad.SPAD_AutoOnline = 1))
		end
		
		-- временная затычка что бы не запускать тригер
		insert into Debug (db_Date, db_Mod, db_n1)
		values (getdate(), ''COS'', @coId)
	end
	
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOfferChange.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on [dbo].[CostOfferChange] to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOfferChange.sql', error_message())
END CATCH
end

print '############ end of file CostOfferChange.sql ################'

print '############ begin of file CurrentUser.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/****** Object:  StoredProcedure [dbo].[CurrentUser]    Script Date: 05/16/2018 16:59:12 ******/
SET ANSI_NULLS ON
')
END TRY
BEGIN CATCH
insert into ##errors values ('CurrentUser.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
SET QUOTED_IDENTIFIER OFF
')
END TRY
BEGIN CATCH
insert into ##errors values ('CurrentUser.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
ALTER PROCEDURE [dbo].[CurrentUser] 
(
--<VERSION>2005.4.21</VERSION>
	@sUser varchar(50) output	
)
AS
	declare @sUserID varchar(255)
	declare @nUserKey int
	declare @nUserPRKey int
	declare @nUserDepartmentKey int
	declare @sUserLat varchar(50)

	--Set @sUserID = dbo.fn_GetUserAlias(USER)
	select @sUserID = SYSTEM_USER
	Exec dbo.GetUserInfo @sUserID, @nUserKey, @sUser output, @nUserPRKey, @nUserDepartmentKey, @sUserLat output
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('CurrentUser.sql', error_message())
END CATCH
end

print '############ end of file CurrentUser.sql ################'

print '############ begin of file deleteUnusedScriptsWithSPPrefix.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_AddPartnerOld]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_AddPartnerOld]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_ChangeIvalidReservationState]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_ChangeIvalidReservationState]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_CollapsePartner]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_CollapsePartner]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_CollapsePartnerUpdateSearchTables]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_CollapsePartnerUpdateSearchTables]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_DelClient]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_DelClient]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_DelPartner]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_DelPartner]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_GetClientEMailList]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_GetClientEMailList]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_GetClientFaxList]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_GetClientFaxList]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_GetClientList]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_GetClientList]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_GetClientTypeList]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_GetClientTypeList]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_GetPartnerEMailList]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_GetPartnerEMailList]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_GetPartnerFaxList]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_GetPartnerFaxList]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_GetPartnerList]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_GetPartnerList]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_GetPartnerTypeList]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_GetPartnerTypeList]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_is_member]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_is_member]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_MovePartner]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_MovePartner]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_UpdatePartnerOld]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_UpdatePartnerOld]



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[sp_VerifyEMailSubscription]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[sp_VerifyEMailSubscription]



')
END TRY
BEGIN CATCH
insert into ##errors values ('deleteUnusedScriptsWithSPPrefix.sql', error_message())
END CATCH
end

print '############ end of file deleteUnusedScriptsWithSPPrefix.sql ################'

print '############ begin of file dogListToQuotas.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[DogListToQuotas]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[DogListToQuotas]
')
END TRY
BEGIN CATCH
insert into ##errors values ('dogListToQuotas.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE PROCEDURE [dbo].[DogListToQuotas]
(
	--<VERSION>9.20.11</VERSION>
	--<DATA>21.10.2015</DATA>
	@DLKey int,
	@SetQuotaCheck bit = null,			--если передается этот признак, то по услуге проверяются актуальные квоты, и в случае не актуальности номер/место снимается с квоты целиком и пытается поставиться на квоту заново
										--остальные квоты занимаемые услугой не снимаются, остаются как есть
	@SetQuotaRLKey int = null,
	@SetQuotaRPKey int = null,
	@SetQuotaQPID int = null,			--передается только из руч.режима (только для одной даты!!!!!!)	
	@SetQuotaDateBeg datetime = null,
	@SetQuotaDateEnd datetime = null,
	@SetQuotaAgentKey int = null, 
	@SetQuotaType smallint = null,		--при переходе на 2008.1 в этот параметр передается отрицательное число (-1 Allotment, -2 Коммитемент)
	@SetQuotaByRoom bit = null, 
	@SetQuotaPartner int = null, 
	@SetQuotaDuration smallint = null,
	@SetQuotaSubCode1 int = null,
	@SetQuotaSubCode2 int = null,
	@SetQuotaFilialKey int = null, 
	@SetQuotaCityDepartments int = null,
	@SetQuotaDateFirst datetime = null,
	@SetOkIfRequest bit = 0, -- запуск из тригера T_UpdDogListQuota
	@OldSetToQuota bit = 0, -- запустить старый механизм посадки
	@ToSetQuotaDateFrom datetime = null,
	@ToSetQuotaDateTo datetime = null
) 
AS

--insert into Debug (db_n1, db_n2, db_n3) values (@DLKey, @SetQuotaType, 999)
declare @SVKey int, @Code int, @SubCode1 int, @PRKey int, @AgentKey int, @DgKey int,
		@TourDuration int, @FilialKey int, @CityDepartment int,
		@ServiceDateBeg datetime, @ServiceDateEnd datetime, @Pax smallint, @IsWait smallint,@SVQUOTED smallint,
		@SubCode2IsUsed smallint, @SdStateOld int, @SdStateNew int, @nHIID int, @dgCode nvarchar(10), @dlName nvarchar(max), @Long smallint
		
declare @sOldValue nvarchar(max), @sNewValue nvarchar(max)
-- сохраним старое значение квотируемости
select @SdStateOld = MAX(SD_State) from ServiceByDate with(nolock) where SD_DLKey = @DLKey

SELECT	@SVKey=DL_SVKey, @Code=DL_Code, @SubCode1=DL_SubCode1, @PRKey=DL_PartnerKey, 
		@ServiceDateBeg=DL_DateBeg, @ServiceDateEnd=DL_DateEnd, @Pax=DL_NMen,
		@AgentKey=DG_PartnerKey, @TourDuration=DG_NDay, @FilialKey=DG_FilialKey, @CityDepartment=DG_CTDepartureKey, @IsWait=ISNULL(DL_Wait,0),
		@DgKey = DL_DGKEY,
		@dgCode = DG_CODE,
		@dlName = DL_NAME
FROM	DogovorList join Dogovor on DL_DGKey = DG_Key
WHERE	DL_Key = @DLKey

if @IsWait=1 and (@SetQuotaType in (1,2) or @SetQuotaType is null)  --Установлен признак "Не снимать квоту при бронировании". На квоту не ставим
BEGIN
	UPDATE ServiceByDate SET SD_State=4 WHERE SD_DLKey=@DLKey and SD_State is null	-- изменение
	-- Хранимка в зависисмости от статусов, основных мест в комнате устанавливает статус квотирования на доп местах
	if @SetQuotaByRoom = 0 and @SVKey = 3
	begin
		exec SetStatusInRoom @dlkey
	end
	return 0
END

SELECT @SVQUOTED=isnull(SV_Quoted,0) from [service] with(nolock) where sv_key=@SVKEY
if @SVQUOTED=0
BEGIN
	UPDATE ServiceByDate SET SD_State=3 WHERE SD_DLKey=@DLKey	
	-- Хранимка в зависисмости от статусов, основных мест в комнате устанавливает статус квотирования на доп местах
	if @SetQuotaByRoom = 0 and @SVKey = 3
	begin
		exec SetStatusInRoom @dlkey
	end
	return 0
END

-- ДОБАВЛЕНА НАСТРОЙКА ЗАПРЕЩАЮЩАЯ СНЯТИЕ КВОТЫ ДЛЯ УСЛУГИ, 
-- ТАК КАК В КВОТАХ НЕТ РЕАЛЬНОЙ ИНФОРМАЦИИ, А ТОЛЬКО ПРИЗНАК ИХ НАЛИЧИЯ (ПЕРЕДАЕТСЯ ИЗ INTERLOOK)
IF (@SetQuotaType in (1,2) or @SetQuotaType is null) and @SVKey = 3 and EXISTS (SELECT 1 FROM dbo.SystemSettings WHERE SS_ParmName=''IL_SyncILPartners'' and SS_ParmValue LIKE ''%/'' + CAST(@PRKey as varchar(255)) + ''/%'')
Begin
	UPDATE ServiceByDate SET SD_State=4 WHERE SD_DLKey=@DLKey and SD_State is null
	-- Хранимка в зависисмости от статусов, основных мест в комнате устанавливает статус квотирования на доп местах
	if @SetQuotaByRoom = 0 and @SVKey = 3
	begin
		exec SetStatusInRoom @dlkey
	end
	return 0
End

DECLARE @dlControl int
-- если включена настройка то отрабатывает новый метод посадки и рассадки в квоту
if exists (select top 1 1 from SystemSettings where SS_ParmName = ''NewSetToQuota'' and SS_ParmValue = 1) and @OldSetToQuota = 0
begin
	-- вставляет в таблицу для дальнейшей рассадки в квоту
	insert into DogovorListNeedQuoted (DLQ_DLKey, DLQ_Date, DLQ_State, DLQ_Host, DLQ_User)
			values (@dlkey, getdate(), 0, host_name(), user_name())

	-- запись в историю, только если статус услуги поменялся
	if exists(select top 1 1 from SystemSettings where SS_ParmName like ''SYSServiceStatusToHistory'' and SS_ParmValue = ''1'')
	begin
		IF ISNULL(@SdStateOld, 0) = 0
			SET @sOldValue = ''''
		ELSE IF @SdStateOld = 1
			SET @sOldValue = ''Allotment''
		ELSE IF @SdStateOld = 2
			SET @sOldValue = ''Commitment''
		ELSE IF @SdStateOld = 3
			SET @sOldValue = ''Confirmed''
		ELSE IF @SdStateOld = 4
			SET @sOldValue = ''Wait''

		IF ISNULL(@SdStateNew, 0) = 0
			SET @sNewValue = ''''
		ELSE IF @SdStateNew = 1
			SET @sNewValue = ''Allotment''
		ELSE IF @SdStateNew = 2
			SET @sNewValue = ''Commitment''
		ELSE IF @SdStateNew = 3
			SET @sNewValue = ''Confirmed''
		ELSE IF @SdStateNew = 4
			SET @sNewValue = ''Wait''

		EXEC @nHIID = dbo.InsHistory @dgCode, @DgKey, 19, '''', ''UPD'', @dlName, '''', 0, ''''
		EXECUTE dbo.InsertHistoryDetail @nHIID, 19001, @sOldValue, @sNewValue, @SdStateOld, @SdStateNew, '''', '''', 0
	end

	return;
end

-- проверим если это доп место в комнате, то ее нельзя посадить в квоты, сажаем внеквоты и эта квота за человека
if exists(select 1 from systemsettings where ss_parmname=''SYSSetQuotaForAddPlaces'' and SS_ParmValue=1)
begin
	if ( exists (select top 1 1 from ServiceByDate with(nolock) join RoomPlaces with(nolock) on SD_RPID = RP_ID where SD_DLKey = @DLKey and RP_Type = 1) and (@SetQuotaByRoom = 0))
	begin
		set @SetQuotaType = 3
	end
end

declare @Q_Count smallint, @Q_AgentKey int, @Q_Type smallint, @Q_ByRoom bit, 
		@Q_PRKey int, @Q_FilialKey int, @Q_CityDepartments int, @Q_Duration smallint, @Q_DateBeg datetime, @Q_DateEnd datetime, @Q_DateFirst datetime, @Q_SubCode1 int, @Q_SubCode2 int,
		@Query nvarchar(max), @SubQuery varchar(1500), @Current int, @CurrentString varchar(50), @QTCount_Need smallint, @n smallint, @Result_Exist bit, @nTemp smallint, @Quota_CheckState smallint, @dTemp datetime

--karimbaeva 19-04-2012  по умолчанию если не хватает квот на всех туристов, то ставим их всех на запрос, если установлена настройка 
-- SYSSetQuotaToTourist - 1 - ставим туристов на запрос, 0- снимаем квоты на кого хватает, остальных ставим на запрос
if not exists(select 1 from systemsettings where ss_parmname=''SYSSetQuotaToTourist'' and SS_ParmValue=0)
begin
	If exists (SELECT top 1 1 FROM ServiceByDate with(nolock) WHERE SD_DLKey=@DLKey and SD_State is null)
	BEGIN
	declare @QT_ByRoom_1 bit
	create table #DlKeys_1
	(
		dlKey int
	)

	insert into #DLKeys_1
		select dl_key 
		from dogovorlist with(nolock)
		where dl_dgkey in (
							select dl_dgkey 
							from dogovorlist with(nolock) 
							where dl_key = @DLKey
						   )
		and dl_svkey = 3
		
		SELECT @QT_ByRoom_1=QT_ByRoom FROM Quotas with(nolock),QuotaDetails with(nolock),QuotaParts with(nolock) WHERE QD_QTID=QT_ID and QD_ID=QP_QDID 
		and QP_ID = (select top 1 SD_QPID
					from ServiceByDate with(nolock) join RoomPlaces with(nolock) on SD_RLID = RP_RLID  
					where RP_Type = 0 and sd_dlkey in (select dlKey from #DlKeys_1) and SD_RLID = (select TOP 1 SD_RLID from ServiceByDate with(nolock) where sd_dlkey=@DlKey))
		
		
		if (@QT_ByRoom_1=0 or @QT_ByRoom_1 is null)
		begin	
		SET @Q_DateBeg=@ServiceDateBeg
		SET @Q_DateEnd=@ServiceDateEnd
		SET @Q_DateFirst=@ServiceDateBeg
	
		EXEC dbo.[CheckQuotaExist] @SVKey, @Code, @SubCode1, @Q_DateBeg,
				@Q_DateEnd, @Q_DateFirst, @PRKey, @AgentKey, @TourDuration, 
				@FilialKey,	@CityDepartment, 2, @Pax,@IsWait, 
				@Quota_CheckState output, @dTemp output, @nTemp output,
				@Q_Count output, @Q_AgentKey output, @Q_Type output, @Q_ByRoom output, @Q_PRKey output, 
				@Q_FilialKey output, @Q_CityDepartments output,	@Q_Duration output, @Q_SubCode1 output, @Q_SubCode2 output
						
		if @Quota_CheckState = 0	
		begin
			UPDATE ServiceByDate SET SD_State=4 WHERE SD_DLKey=@DLKey and SD_State is null
			-- Хранимка в зависисмости от статусов, основных мест в комнате устанавливает статус квотирования на доп местах
			if @SetQuotaByRoom = 0 and @SVKey = 3
			begin
				exec SetStatusInRoom @dlkey
			end
			-- хранимка простановки статусов у услуг
			EXEC dbo.SetServiceStatusOk @DlKey,@dlControl
			return 0
		end	
		end	
END
end 

--Если идет полная постановка услуги на квоту (@SetQuotaType is null) обычно после бронирования
--Или прошло удаление какой-то квоты и сейчас требуется освободить эту квоту и занять другую
--То требуется найти оптимально подходящую квоту и ее использовать

If @SetQuotaType is null or @SetQuotaType<0 --! @SetQuotaType<0 <--при переходе на 2008.1
BEGIN
	IF @SetQuotaCheck=1 
	begin
		UPDATE ServiceByDate SET SD_State=null, SD_QPID=null where SD_DLKey=@DLKey
			and SD_RPID in (SELECT DISTINCT SD_RPID FROM QuotaDetails with(nolock),QuotaParts with(nolock),ServiceByDate with(nolock)
							WHERE SD_QPID=QP_ID and QP_QDID=QD_ID and QD_IsDeleted=1 and SD_DLKey=@DLKey)
	end
	ELSE
	BEGIN
		IF @SetQuotaRLKey is not null
			UPDATE ServiceByDate SET SD_State=null, SD_QPID=null where SD_DLKey=@DLKey and SD_RLID=@SetQuotaRLKey
		ELSE IF @SetQuotaRPKey is not null
			UPDATE ServiceByDate SET SD_State=null, SD_QPID=null where SD_DLKey=@DLKey and SD_RPID=@SetQuotaRPKey
		ELSE
			UPDATE ServiceByDate SET SD_State=null, SD_QPID=null where SD_DLKey=@DLKey
	END
	SET @Q_DateBeg=@ServiceDateBeg
	SET @Q_DateEnd=@ServiceDateEnd
	SET @Q_DateFirst=@ServiceDateBeg
	IF @SetQuotaType=-1
		SET @Q_Type=1
	ELSE IF @SetQuotaType=-2
		SET @Q_Type=2
	
	EXEC dbo.[CheckQuotaExist] @SVKey, @Code, @SubCode1, @Q_DateBeg,
						@Q_DateEnd, @Q_DateFirst, @PRKey, @AgentKey, @TourDuration, 
						@FilialKey,	@CityDepartment, 1, @Pax, @IsWait,
						@nTemp output, @dTemp output, @nTemp output,
						@Q_Count output, @Q_AgentKey output, @Q_Type output, @Q_ByRoom output, @Q_PRKey output, 
						@Q_FilialKey output, @Q_CityDepartments output,	@Q_Duration output, @Q_SubCode1 output, @Q_SubCode2 output
END
ELSE
BEGIN
	IF @SetQuotaType=4 or @SetQuotaType=3  --если новый статус Wait-list или Ok(вне квоты), то меняем статус и выходим из хранимки
		Set @Q_Type=@SetQuotaType
	Else If @SetQuotaQPID is not null
	BEGIN
		If @SetQuotaType is not null and @SetQuotaType>=0
			Set @Q_Type=@SetQuotaType
		Else
			Select @Q_Type=QD_Type from QuotaDetails with(nolock),QuotaParts with(nolock) Where QP_QDID=QD_ID and QP_ID=@SetQuotaQPID
	END
	Else
		Set @Q_Type=null		
	--@SetQuotaQPID это конкретная квота, ее заполнение возможно только из режима ручного постановки услуги на квоту
	IF @SetQuotaByRoom=1 and @SVKey=3
	BEGIN
		if @SetQuotaRLKey is null
		begin
			UPDATE ServiceByDate SET SD_State=@Q_Type, SD_QPID=@SetQuotaQPID where SD_DLKey=@DLKey and SD_Date between @SetQuotaDateBeg and @SetQuotaDateEnd
		end
		else
		begin
			UPDATE ServiceByDate SET SD_State=@Q_Type, SD_QPID=@SetQuotaQPID where SD_DLKey=@DLKey and SD_RLID=@SetQuotaRLKey and SD_Date between @SetQuotaDateBeg and @SetQuotaDateEnd
		end
	END
	ELSE
	BEGIN
		if @SetQuotaRPKey is null
		begin
			UPDATE ServiceByDate SET SD_State=@Q_Type, SD_QPID=@SetQuotaQPID where SD_DLKey=@DLKey and SD_Date between @SetQuotaDateBeg and @SetQuotaDateEnd
		end
		else
		begin
			UPDATE ServiceByDate SET SD_State=@Q_Type, SD_QPID=@SetQuotaQPID where SD_DLKey=@DLKey and SD_RPID=@SetQuotaRPKey and SD_Date between @SetQuotaDateBeg and @SetQuotaDateEnd
		end
	END
	IF @SetQuotaType=4 or @SetQuotaType=3 or @SetQuotaQPID is not null --собственно выход (либо не надо ставить на квоту либо квота конкретная)
	begin
		-- Хранимка в зависисмости от статусов, основных мест в комнате устанавливает статус квотирования на доп местах
		if @SetQuotaByRoom = 0 and @SVKey = 3
		begin
			exec SetStatusInRoom @dlkey
		end
		-- запускаем хранимку на установку статуса путевки
		--exec SetReservationStatus @DgKey
		-- хранимка простановки статусов у услуг
		EXEC dbo.SetServiceStatusOk @DlKey,@dlControl
		return 0
	end

	--	select * from ServiceByDate where SD_DLKey=202618 and SD_RLID=740
	SET @Q_AgentKey=@SetQuotaAgentKey
	SET @Q_Type=@SetQuotaType
	SET @Q_ByRoom=@SetQuotaByRoom
	SET @Q_PRKey=@SetQuotaPartner
	SET @Q_FilialKey=@SetQuotaFilialKey
	SET @Q_CityDepartments=@SetQuotaCityDepartments
	SET @Q_Duration=@SetQuotaDuration
	SET @Q_SubCode1=@SetQuotaSubCode1
	SET @Q_SubCode2=@SetQuotaSubCode2
	SET @Q_DateBeg=@SetQuotaDateBeg
	SET @Q_DateEnd=@SetQuotaDateEnd
	SET @Q_DateFirst=ISNULL(@SetQuotaDateFirst,@Q_DateBeg)
	SET @Result_Exist=0	
END

set @n=0

If not exists (SELECT top 1 1 FROM ServiceByDate with(nolock) WHERE SD_DLKey=@DLKey and SD_State is null)
	print ''WARNING_DogListToQuotas_1''
If @Q_Count is null
	print ''WARNING_DogListToQuotas_2''
If @Result_Exist > 0
	print ''WARNING_DogListToQuotas_3''

CREATE table #StopSales (SS_QDID int,SS_QOID int,SS_DATE dateTime)
CREATE table #Quotas1(QP_ID int,QD_QTID int,QD_ID int,QO_ID int,QD_Release smallint,QP_Durations varchar(20),
	QD_Date DateTime,QP_IsNotCheckIn bit,QP_CheckInPlaces smallint,QP_CheckInPlacesBusy smallint,
	QP_Places smallint,QP_Busy smallint,QT_ID int,QO_QTID int,QO_SVKey int,QO_Code int,QO_SubCode1 int,QO_SubCode2 int)

DECLARE @DATETEMP datetime
SET @DATETEMP = GetDate()
-- Разрешим посадить в квоту с релиз периодом 0 текущим числом
set @DATETEMP = DATEADD(day, -1, @DATETEMP)

if exists (select top 1 1 from systemsettings where SS_ParmName=''SYSCheckQuotaRelease'' and SS_ParmValue=1) OR exists (select top 1 1 from systemsettings where SS_ParmName=''SYSAddQuotaPastPermit'' and SS_ParmValue=1 and @Q_DateFirst < @DATETEMP)
	SET @DATETEMP=''10-JAN-1900''

WHILE (exists(SELECT top 1 1 FROM ServiceByDate with(nolock) WHERE SD_DLKey=@DLKey and SD_State is null) and @n<5 and (@Q_Count is not null or @Result_Exist=0))
BEGIN
	set @n=@n+1

	SET @Long=DATEDIFF(DAY,@Q_DateBeg,@Q_DateEnd)+1
	
	DECLARE @n1 smallint, @n2 smallint, @prev bit, @durations_prev varchar(25), @release_prev smallint, @QP_ID int, @SK_Current int, @Temp smallint, @Error bit
	DECLARE @ServiceKeys Table (SK_ID int identity(1,1), SK_Key int, SK_QPID int, SK_Date smalldatetime)

	IF (@SetQuotaType is null or @SetQuotaType < 0) --! @SetQuotaType<0 <--при переходе на 2008.1
	BEGIN
		IF (@Q_ByRoom = 1)
			INSERT INTO @ServiceKeys (SK_Key,SK_Date) SELECT DISTINCT SD_RLID, SD_Date FROM ServiceByDate with(nolock) WHERE SD_DLKey=@DLKey and SD_State is null
		ELSE
			INSERT INTO @ServiceKeys (SK_Key,SK_Date) SELECT DISTINCT SD_RPID, SD_Date FROM ServiceByDate with(nolock) WHERE SD_DLKey=@DLKey and SD_State is null
		end
		ELSE IF @Q_ByRoom=1
		BEGIN
			INSERT INTO @ServiceKeys (SK_Key,SK_Date) SELECT DISTINCT SD_RLID, SD_Date FROM ServiceByDate with(nolock) WHERE SD_DLKey=@DLKey and SD_RLID=@SetQuotaRLKey and SD_State is null
		END
		ELSE IF @Q_ByRoom=0
		BEGIN
			INSERT INTO @ServiceKeys (SK_Key,SK_Date) SELECT DISTINCT SD_RPID, SD_Date FROM ServiceByDate with(nolock) WHERE SD_DLKey=@DLKey and SD_RPID=@SetQuotaRPKey and SD_State is null
		END

		SET @Error=0
		SELECT @SK_Current=MIN(SK_Key) FROM @ServiceKeys WHERE SK_QPID is null
		
		Set @prev = null
		
		WHILE @SK_Current is not null and @Error=0
		BEGIN
			SET @n1=1
			
			WHILE @n1<=@Long and @Error=0
			BEGIN
				SET @QP_ID=null
				SET @n2=0
				
				WHILE (@QP_ID is null) and @n2<2
				BEGIN
					truncate table #Quotas1
					truncate table #StopSales
					
					insert into #Quotas1 (QP_ID,QD_QTID,QD_ID,QO_ID,QD_Release,QP_Durations,QD_Date,QP_IsNotCheckIn,QP_CheckInPlaces,QP_CheckInPlacesBusy,QP_Places,QP_Busy,QT_ID,QO_QTID,QO_SVKey,QO_Code,QO_SubCode1,QO_SubCode2)
						select QP_ID,QD_QTID,QD_ID,QO_ID,QD_Release,QP_Durations,QD_Date,QP_IsNotCheckIn,QP_CheckInPlaces,QP_CheckInPlacesBusy,QP_Places,QP_Busy,QT_ID,QO_QTID,QO_SVKey,QO_Code,QO_SubCode1,QO_SubCode2
						FROM QuotaParts as QP1 with(nolock)
						inner join QuotaDetails as QD1 with(nolock) on QP_QDID=QD_ID and QD_Date = QP_Date
						inner join Quotas with(nolock) on QT_ID=QD_QTID
						inner join QuotaObjects with(nolock) on QO_QTID=QT_ID
						WHERE QD_Type=@Q_Type
						and QT_ByRoom=@Q_ByRoom
						and QD_IsDeleted is null
						and QP_IsDeleted is null
						and QO_SVKey=@SVKey
						and QO_Code=@Code
						and QO_SubCode1=@Q_SubCode1
						and QO_SubCode2=CASE
											WHEN @SVKey=3 THEN @Q_SubCode2
											WHEN @SVKey<>3 AND EXISTS(SELECT TOP 1 1 FROM [Service] WHERE SV_KEY=@SVKey AND SV_ISSUBCODE2=1)
												THEN (SELECT DL_Subcode2 FROM tbl_DogovorList WITH(NOLOCK) WHERE DL_Key=@DLKey)
											ELSE QO_SubCode2 END
						and ISNULL(QP_FilialKey, -100) = ISNULL(@Q_FilialKey, -100)
						and ISNULL(QP_CityDepartments, -100) = ISNULL(@Q_CityDepartments, -100)
						and ISNULL(QP_AgentKey, -100) = ISNULL(@Q_AgentKey, -100)
						and ISNULL(QT_PRKey, -100) = ISNULL(@Q_PRKey, -100)
						and QP_Durations = CASE WHEN @Q_Duration=0 THEN '''' ELSE QP_Durations END
						and QD_Date between @Q_DateBeg and DATEADD(DAY,@Long,@Q_DateBeg)
						and (QP_Places-QP_Busy) > 0
						and (isnull(QP_Durations, '''') = ''''
						or (isnull(QP_Durations, '''') != '''' and (QP_IsNotCheckIn = 1 or QP_CheckInPlaces - QP_CheckInPlacesBusy > 0))
						or (isnull(QP_Durations, '''') != '''' and (QP_IsNotCheckIn = 0 or QP_Places - QP_Busy > 0))
						or (isnull(QP_Durations, '''') != '''' and QD_Date = @Q_DateFirst))
						and (QD1.QD_Date > @DATETEMP + ISNULL(QD1.QD_Release,-1) OR (QD1.QD_Date < getdate() - 1))
						and ((QP_IsNotCheckIn = 0) or (QP_IsNotCheckIn = 1 and exists (select top 1 1 from QuotaDetails as tblQD with(nolock)
																							inner join QuotaParts as tblQP with(nolock)
																							on tblQP.QP_QDID = tblQD.QD_ID and tblQP.QP_Date = tblQD.QD_Date
																							where tblQP.QP_IsNotCheckIn = 0
																							and tblQD.QD_Date=@Q_DateFirst
																							and tblQD.QD_QTID=QD1.QD_QTID)))
						and QP_ID not in
						(SELECT QP_ID FROM QuotaParts QP2 with(nolock)
								inner join QuotaDetails QD2 with(nolock) on QP_QDID=QD_ID and QD_Date=QP_Date
								inner join Quotas QT2 with(nolock) on QT_ID=QD_QTID
								WHERE QD2.QD_Type=@Q_Type
								and QT2.QT_ByRoom=@Q_ByRoom
								and QD2.QD_IsDeleted is null
								and QP2.QP_IsDeleted is null
								and ISNULL(QP2.QP_FilialKey, -100) = ISNULL(@Q_FilialKey, -100)
								and ISNULL(QP2.QP_CityDepartments, -100) = ISNULL(@Q_CityDepartments, -100)
								and ISNULL(QP2.QP_AgentKey, -100) = ISNULL(@Q_AgentKey, -100)
								and ISNULL(QT2.QT_PRKey, -100) = ISNULL(@Q_PRKey, -100)
								and ((@Q_Duration=0 and QP2.QP_Durations = '''') or (@Q_Duration <> 0 and QP2.QP_ID in (Select QL_QPID From QuotaLimitations with(nolock) Where QL_Duration = @Q_Duration)))
								and QD2.QD_Date=@Q_DateFirst
								and (QP2.QP_IsNotCheckIn=1 or QP2.QP_CheckInPlaces-QP2.QP_CheckInPlacesBusy <= 0)
								and QO_QTID=QT2.QT_ID
								and ISNULL(QD2.QD_Release,0)=ISNULL(QD1.QD_Release,0)
								and QP2.QP_Durations COLLATE DATABASE_DEFAULT = QP1.QP_Durations COLLATE DATABASE_DEFAULT)

						if (@Q_Duration<>0)
						begin
							delete from #Quotas1 where QP_ID not in (Select QL_QPID From QuotaLimitations with(nolock) Where QL_Duration=@Q_Duration)
						end

						insert into #StopSales SELECT SS_QDID, SS_QOID, SS_Date FROM StopSales with(nolock) inner join #Quotas1 on SS_QOID=#Quotas1.QO_ID and SS_QDID=#Quotas1.QD_ID WHERE isnull(SS_IsDeleted, 0) = 0

						delete from #Quotas1 where exists (SELECT top 1 1 FROM #StopSales WHERE SS_QDID=QD_ID and SS_QOID=QO_ID and SS_Date=QD_Date)
					
					IF @prev=1
					begin
						SELECT TOP 1 @QP_ID=QP_ID, @durations_prev=QP_Durations, @release_prev=QD_Release
						FROM #Quotas1 AS Q1
						WHERE QD_Date=DATEADD(DAY,@n1-1,@Q_DateBeg) and QP_Durations=@durations_prev and QD_Release=@release_prev
						ORDER BY ISNULL(QD_Release,0) DESC, (select count(distinct QD_QTID) from QuotaDetails as QDP with(nolock)
								join QuotaParts as QPP with(nolock) on QDP.QD_ID = QPP.QP_QDID and QDP.QD_Date = QPP.QP_Date
								where exists (select top 1 1 from @ServiceKeys as SKP
												where SKP.SK_QPID = QPP.QP_ID)
								and QDP.QD_QTID = Q1.QD_QTID) DESC
					end
					ELSE
					begin
						SELECT TOP 1 @QP_ID=QP_ID, @durations_prev=QP_Durations, @release_prev=QD_Release
						FROM #Quotas1 as Q1
						WHERE QD_Date=DATEADD(DAY,@n1-1,@Q_DateBeg)
						ORDER BY ISNULL(QD_Release,0) DESC, (select count(distinct QD_QTID) from QuotaDetails as QDP with(nolock)
								join QuotaParts as QPP on QDP.QD_ID = QPP.QP_QDID and QDP.QD_Date = QPP.QP_Date
								where exists (select top 1 1 from @ServiceKeys as SKP
												where SKP.SK_QPID = QPP.QP_ID)
								and QDP.QD_QTID = Q1.QD_QTID) DESC
					end
					
					SET @n2=@n2+1
					
					IF @QP_ID is null
					BEGIN
						SET @prev=1
					END
					ELSE
						UPDATE @ServiceKeys SET SK_QPID=@QP_ID WHERE SK_Key=@SK_Current and SK_Date=DATEADD(DAY,@n1-1,@Q_DateBeg)
					END
					
					If @QP_ID is null
						SET @Error=1
					
					SET @n1=@n1+1
				END

				IF @Error=0
				begin
					IF @Q_ByRoom = 1
					begin
						if exists(select 1 from systemsettings where ss_parmname=''SYSSetQuotaToTourist'' and SS_ParmValue=0)
						begin
							UPDATE ServiceByDate SET SD_State=@Q_Type, SD_QPID=(SELECT MIN(SK_QPID) FROM @ServiceKeys join QuotaParts on SK_QPID=QP_ID WHERE SK_Date=SD_Date and SK_Key=SD_RLID and QP_Places-QP_Busy>0)
								WHERE SD_DLKey=@DLKey and SD_RLID=@SK_Current and SD_State is null and SD_Date between @ServiceDateBeg and @ServiceDateEnd
						end
						else
						begin
							UPDATE ServiceByDate SET SD_State=@Q_Type, SD_QPID=(SELECT MIN(SK_QPID) FROM @ServiceKeys WHERE SK_Date=SD_Date and SK_Key=SD_RLID)
								WHERE SD_DLKey=@DLKey and SD_RLID=@SK_Current and SD_State is null and SD_Date between @ServiceDateBeg and @ServiceDateEnd
						end
					end
					ELSE
					begin
						if exists(select 1 from systemsettings where ss_parmname=''SYSSetQuotaToTourist'' and SS_ParmValue=0)
						begin
							UPDATE ServiceByDate SET SD_State=@Q_Type, SD_QPID=(SELECT MIN(SK_QPID) FROM @ServiceKeys join QuotaParts on SK_QPID=QP_ID WHERE SK_Date=SD_Date and SK_Key=SD_RPID and QP_Places-QP_Busy>0)
								WHERE SD_DLKey=@DLKey and SD_RPID=@SK_Current and SD_State is null and SD_Date between @ServiceDateBeg and @ServiceDateEnd
						end
						else
						begin
							UPDATE ServiceByDate SET SD_State=@Q_Type, SD_QPID=(SELECT MIN(SK_QPID) FROM @ServiceKeys WHERE SK_Date=SD_Date and SK_Key=SD_RPID)
								WHERE SD_DLKey=@DLKey and SD_RPID=@SK_Current and SD_State is null and SD_Date between @ServiceDateBeg and @ServiceDateEnd
						end
					end
				end
				
				SET @SK_Current=null
				SELECT @SK_Current=MIN(SK_Key) FROM @ServiceKeys WHERE SK_QPID is null
			END

	declare @QTByRoom bit
	
	SELECT top 1 @QTByRoom = QT_ByRoom 
		FROM Quotas with(nolock)
		join QuotaObjects with(nolock) on QT_ID = QO_QTID
		where QO_Code = @Code
		and QO_SVKey = 3
	
	-- Хранимка в зависисмости от статусов, основных мест в комнате устанавливает статус квотирования на доп местах
	if @SetQuotaByRoom = 0 and @SVKey = 3 and @QTByRoom = 0
	begin
		exec SetStatusInRoom @dlkey
	end
	
	--если @SetQuotaType is null -значит это начальная постановка услги на квоту и ее надо делать столько раз
	--сколько номеров или людей в услуге.
	If @SetQuotaType is null or @SetQuotaType<0 --! @SetQuotaType<0 <--при переходе на 2008.1
	BEGIN
		If exists (SELECT top 1 1 FROM ServiceByDate with(nolock) WHERE SD_DLKey=@DLKey and SD_State is null)
		BEGIN
			EXEC dbo.[CheckQuotaExist] @SVKey, @Code, @SubCode1, @Q_DateBeg,
				@Q_DateEnd, @Q_DateFirst, @PRKey, @AgentKey, @TourDuration, 
				@FilialKey,	@CityDepartment, 1, @Pax,@IsWait, 
				@nTemp output, @dTemp output, @nTemp output,
				@Q_Count output, @Q_AgentKey output, @Q_Type output, @Q_ByRoom output, @Q_PRKey output, 
				@Q_FilialKey output, @Q_CityDepartments output,	@Q_Duration output, @Q_SubCode1 output, @Q_SubCode2 output
		END
	END	
	ELSE --а если @SetQuotaType is not null -значит ставим на услугу конкретное место, а раз так то оно должно встать на квоту должно было с первого раза, устанавливаем бит выхода.	
		SET @Result_Exist=1		--бит выхода
END

--все квоты уже заняты (такие услуги попали в условие QP_Places-QP_Busy>0), для оставшихся проставляем статус запрос
IF @SetQuotaByRoom=1 and @SVKey=3
BEGIN
	IF @SetQuotaRLKey is null
	BEGIN
		UPDATE ServiceByDate SET SD_State = 4 where SD_DLKey = @DLKey and SD_QPID is null
	END
	ELSE
	BEGIN
		UPDATE ServiceByDate SET SD_State = 4 where SD_DLKey = @DLKey and SD_RLID = @SetQuotaRLKey and SD_QPID is null
	END
END
ELSE
BEGIN
	IF @SetQuotaRPKey is null
	BEGIN
		UPDATE ServiceByDate SET SD_State = 4 where SD_DLKey = @DLKey and SD_QPID is null
	END
	ELSE
	BEGIN
		UPDATE ServiceByDate SET SD_State = 4 where SD_DLKey = @DLKey and SD_RPID = @SetQuotaRPKey and SD_QPID is null
	END
END

if exists(select top 1 1 from ServiceByDate with(nolock) where SD_DLKey=@DLKey and SD_State is null) and @SVKey = 3
begin
	exec SetStatusInRoom @dlkey
end

drop table #StopSales
drop table #Quotas1

UPDATE ServiceByDate SET SD_State=4 WHERE SD_DLKey=@DLKey and SD_State is null

-- сохраним новое значение квотируемости
select @SdStateNew = MAX(SD_State) from ServiceByDate with(nolock) where SD_DLKey = @DLKey

-- запись в историю
if exists(select top 1 1 from SystemSettings where SS_ParmName like ''SYSServiceStatusToHistory'' and SS_ParmValue = ''1'')
begin
	IF ISNULL(@SdStateOld, 0) = 0
		SET @sOldValue = ''''
	ELSE IF @SdStateOld = 1
		SET @sOldValue = ''Allotment''
	ELSE IF @SdStateOld = 2
		SET @sOldValue = ''Commitment''
	ELSE IF @SdStateOld = 3
		SET @sOldValue = ''Confirmed''
	ELSE IF @SdStateOld = 4
		SET @sOldValue = ''Wait''

	IF ISNULL(@SdStateNew, 0) = 0
		SET @sNewValue = ''''
	ELSE IF @SdStateNew = 1
		SET @sNewValue = ''Allotment''
	ELSE IF @SdStateNew = 2
		SET @sNewValue = ''Commitment''
	ELSE IF @SdStateNew = 3
		SET @sNewValue = ''Confirmed''
	ELSE IF @SdStateNew = 4
		SET @sNewValue = ''Wait''

	EXEC @nHIID = dbo.InsHistory @dgCode, @DgKey, 19, '''', ''UPD'', @dlName, '''', 0, ''''
	EXECUTE dbo.InsertHistoryDetail @nHIID, 19001, @sOldValue, @sNewValue, @SdStateOld, @SdStateNew, '''', '''', 0
end

-- 2012-10-12 tkachuk, task 8473 - меняем статус для услуг, привязанных к изменившимся квотам

EXEC dbo.SetServiceStatusOk @DlKey,@dlControl
')
END TRY
BEGIN CATCH
insert into ##errors values ('dogListToQuotas.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT EXEC ON [dbo].[DogListToQuotas] TO PUBLIC
')
END TRY
BEGIN CATCH
insert into ##errors values ('dogListToQuotas.sql', error_message())
END CATCH
end

print '############ end of file dogListToQuotas.sql ################'

print '############ begin of file DogovorMonitor.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[DogovorMonitor]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[DogovorMonitor]
')
END TRY
BEGIN CATCH
insert into ##errors values ('DogovorMonitor.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE PROCEDURE [dbo].[DogovorMonitor]
--<VERSION>2009.2.20.11</VERSION>
--<DATE>2014-03-28</DATE>
	@dtStartDate datetime,			-- начальная дата просмотра изменений
	@dtEndDate datetime,			-- конечная дата просмотра изменений
	@nCountryKey int,				-- ключ страны
	@nCityKey int,					-- ключ города
	@nDepartureCityKey int,			-- ключ города вылета
	@nCreatorKey int,				-- ключ создателя
	@nOwnerKey int,					-- ключ ведущего менеджера
	@nViewProceed smallint,			-- не показывать обработанные: 0 - показывать, 1 - не показывать
	@sFilterKeys varchar(255),		-- ключи выбранных фильтров
	@nFilialKey int,				-- ключ филиала
	@nBTKey int,					-- ключ типа бронирования: -1 - все, 0 - офис, 1 - онлайн
	@sLang varchar(10)				-- язык (если en, селектим поля NameLat, а не Name)	       
AS
BEGIN

CREATE TABLE #DogovorMonitorTable
(
	DM_CreateDate datetime, -- DM_HistoryDate
	DM_FirstProcDate datetime, -- NEW
	DM_LastProcDate datetime, -- DM_ProcDate
	DM_DGCODE nvarchar(10),
	DM_CREATOR nvarchar(25),
	DM_TurDate datetime,
	DM_TurName nvarchar(160),
	DM_PartnerName nvarchar(80),
	DM_FilterName nvarchar(1024),
	DM_NotesCount int,
	DM_PaymentStatus nvarchar(4),
	DM_IsBilled bit,
	DM_MessageCount int,
    DM_MessageCountRead int,
	DM_MessageCountUnRead int,
	DM_ParnerMessageCount int,					-- Kirillov 24081: подсчет значений прочитанных/не прочитанных сообщений от партнеров
    DM_ParnerMessageCountRead int,				-- Kirillov 24081: подсчет значений прочитанных/не прочитанных сообщений от партнеров
	DM_ParnerMessageCountUnRead int,			-- Kirillov 24081: подсчет значений прочитанных/не прочитанных сообщений от партнеров
	DM_AnnulReason varchar(60),
	DM_AnnulDate datetime,
	DM_PriceToPay money,
	DM_Payed money,
	DM_OrderStatus varchar(20)
)

CREATE TABLE #TempTable
(
	#dogovorCreateDate datetime,
	#lastDogovorActionDate datetime,
	#sDGCode varchar(10),
	#sCreator varchar(25),
	#dtTurDate datetime,
	#sTurName nvarchar(160),
	#sPartnerName nvarchar(80),
	#dgKey int,
	#sPaymentStatus nvarchar(4),
	#AnnulReason varchar(60),
	#PriceToPay money,
	#Payed money
)

declare @nObjectAliasFilter int, @sFilterType varchar(3)

DECLARE @dogovorCreateDate datetime, @lastDogovorActionDate datetime -- @dtHistoryDate
declare @sDGCode varchar(10), @nDGKey int
declare @sCreator varchar(25), @dtTurDate datetime, @sTurName varchar(160)
declare @sPartnerName varchar(80), @sFilterName varchar(255), @nHIID int
declare @sHistoryMod varchar(3), @sPaymentStatus as varchar(4)
declare @AnnulReason AS varchar(60), @AnnulDate AS datetime, @PriceToPay AS money, @Payed AS money

set @sHistoryMod = ''DMP''

declare @nFilterKey int, @nLastPos int

while len(@sFilterKeys) > 0
begin
	set @nLastPos = 0
	set @nLastPos = charindex('','', @sFilterKeys, @nLastPos)
	if @nLastPos = 0
		set @nLastPos = len(@sFilterKeys) + 1
	
	set @nFilterKey = cast(substring(@sFilterKeys, 0, @nLastPos) as int)
	if @nLastPos <> len(@sFilterKeys) + 1
		set @sFilterKeys = substring(@sFilterKeys, @nLastPos + 1, len(@sFilterKeys) - @nLastPos)
	else
		set @sFilterKeys = ''''
	
	select @sFilterName = DS_Value from Descriptions where DS_KEY = @nFilterKey


	declare filterCursor cursor local fast_forward for
	select OF_OAId, OF_Type
	from ObjectAliasFilters
	where OF_DSKey = @nFilterKey
	order by OF_OAId
	
	open filterCursor
	fetch next from filterCursor into @nObjectAliasFilter, @sFilterType
	while(@@fetch_status = 0)
	begin
		
		declare @sql varchar(max)

		set @sql = N''insert into #TempTable
				select DISTINCT 
				(SELECT MIN(HI_DATE) FROM history h2 WHERE h2.HI_DGCOD = DG_CODE) AS DOGOVOR_CREATE_DATE, 
				(SELECT MAX(HI_DATE) FROM history h2 WHERE h2.HI_DGCOD = DG_CODE) AS LAST_DOGOVOR_ACTION_DATE, 
				DG_CODE, ISNULL(US_FullName,''''''''), DG_TurDate, [dbo].[GetTourName](dg_trkey), PR_NAME, DG_KEY,
				CASE
					WHEN DG_PRICE = 0 AND DG_PAYED = DG_PRICE THEN ''''OK''''
					WHEN DG_PAYED = 0 THEN ''''NONE''''
					WHEN DG_PAYED < DG_PRICE THEN ''''LOW''''
					WHEN DG_PAYED = DG_PRICE THEN ''''OK''''
					WHEN DG_PAYED > DG_PRICE THEN ''''OVER''''
					ELSE '''''''' 
				END AS DM_PAYMENTSTATUS, AR_Name, 
				CASE
					WHEN DG_PDTTYPE = 1 THEN DG_PRICE + DG_DISCOUNTSUM
					ELSE DG_PRICE					
				END AS DM_PriceToPay, DG_PAYED
			from dogovor with(nolock) 
			join  history with(nolock) on HI_DGCOD = DG_CODE
			join historydetail with(nolock) on HI_ID = HD_HIID
			join Partners with(nolock) on PR_KEY = DG_PARTNERKEY 
			join AnnulReasons with(nolock) on AR_Key = DG_ARKEY
			left join userlist with(nolock) on US_KEY = DG_CREATOR
			where 
				HI_DATE BETWEEN '''''' + convert(varchar, @dtStartDate, 120) + '''''' and dateadd(day, 1, '''''' + convert(varchar, @dtEndDate, 120) + '''''') and
				(('' + str(@nCountryKey) + '' < 0 and DG_CNKEY in (select CN_KEY from Country with(nolock))) OR ('' + str(@nCountryKey) + '' >= 0 and DG_CNKEY = '' + str(@nCountryKey) + '')) and
				('' + str(@nCityKey) + '' < 0 OR DG_CTKEY = '' + str(@nCityKey) + '') and
				('' + str(@nDepartureCityKey) + '' < 0 OR DG_CTDepartureKey = '' + str(@nDepartureCityKey) + '') and
				('' + str(@nCreatorKey) + '' < 0 OR DG_CREATOR = '' + str(@nCreatorKey) + '') and
				('' + str(@nOwnerKey) + '' < 0 OR DG_OWNER = '' + str(@nOwnerKey) + '') and
				('' + str(@nFilialKey) + '' < 0 OR DG_FILIALKEY = '' + str(@nFilialKey) + '') and
				('' + str(@nBTKey) + '' < 0 OR ('' + str(@nBTKey) + '' = 0 AND DG_BTKEY is NULL) OR DG_BTKEY = '' + str(@nBTKey) + '')''
			
			
				
-----------------------------------------------------------------------------------------------
-- MEG00037288 06.09.2011 Kolbeshkin: добавил алиасы 41-43 для проверки корректности путевки --
-----------------------------------------------------------------------------------------------
		DECLARE @sNotAnnuled varchar(max)
		SET @sNotAnnuled = '' and DG_TURDATE <> ''''1899-12-30 00:00:00.000'''' ''
		SET @sql = @sql + 
		CASE 
		WHEN (@nObjectAliasFilter = 41) -- Путевка без услуг
			THEN '' and not exists (select 1 from dogovorlist where dl_dgkey = dg_key)'' + @sNotAnnuled
		WHEN (@nObjectAliasFilter = 42) -- Путевка без туристов
			THEN '' and not exists (select 1 from Turist where TU_DGKEY = DG_KEY)'' + @sNotAnnuled
		WHEN (@nObjectAliasFilter = 43) -- Услуги с непривязанными туристами
			THEN '' and exists (select 1 from dogovorlist where dl_dgkey = dg_key and not exists (select 1 from TuristService where tu_dlkey = dl_key))'' + @sNotAnnuled
		--o.omelchenko 10391 добавила фильтр по новым сообщениям пришедшым из веба
		-- Kirillov 19267 Заменил тип сообщения с WWW на MTM
		WHEN (@nObjectAliasFilter = 12005) -- новые сообщения от агенств
		     THEN '' and DG_CODE in (select distinct  HI_DGCOD from History
					where HI_MessEnabled >=2
					and HI_MOD like ''''MTM'''' 
					and HI_DATE BETWEEN '''''' + convert(varchar, @dtStartDate, 120) + '''''' and dateadd(day, 1, '''''' + convert(varchar, @dtEndDate, 120) + '''''') ) ''
		-- Kirillov 24081: добавил новый фильтр по переписки с партнерами
		WHEN (@nObjectAliasFilter = 12006) -- Новые сообщения от партнеров
		     THEN '' and DG_CODE in (select distinct  HI_DGCOD from History
					where HI_MessEnabled >=2
					and HI_MOD like ''''MFP'''' 
					and HI_DATE BETWEEN '''''' + convert(varchar, @dtStartDate, 120) + '''''' and dateadd(day, 1, '''''' + convert(varchar, @dtEndDate, 120) + '''''') ) ''
		
		--------- Отсутствуют обязательные(неудаляемые) услуги решено пока не делать, потому что нет прямой связи DogovorList c TurService
		--WHEN (@nObjectAliasFilter = 44) -- Отсутствуют обязательные(неудаляемые) услуги
		--	THEN '' and ((select (
		--	(select COUNT(1) from TurService ts where TS_TRKEY=dg.DG_TRKEY and TS_ATTRIBUTE % 2 = 0) -- Кол-во неудаляемых услуг в туре
		--	-
		--	(select COUNT(1) from Dogovorlist dl join TurService ts on -- Кол-во услуг попавших в путевку из неудаляемых в туре
		--	(ts.TS_TRKEY = dg.DG_TRKEY and ts.TS_ATTRIBUTE % 2 = 0
		--	and dl.DL_SVKEY = ts.TS_SVKEY and dl.DL_CODE = ts.TS_CODE
		--	) where dl.DL_DGKEY = dg.DG_Key and dl.DL_TRKEY = dg.DG_TRKEY )))
		--	> 0) '' 
		ELSE 
			 '' and (HD_OAId = '' + str(@nObjectAliasFilter) + '') 
			 and ('''''' + @sFilterType + ''''''= '''''''' OR HI_MOD = '''''' + @sFilterType + '''''')''
		END
		
-------------------------------------------------------------------------------------
-- MEG00037288 07.09.2011 Kolbeshkin: локализация. Если язык En, селектим поля LAT --
-------------------------------------------------------------------------------------
		IF @sLang like ''en''
		BEGIN
		set @sql = REPLACE(@sql,''US_FullName'',''US_FullNameLat'')
		--set @sql = REPLACE(@sql,''TL_NAME'',''TL_NAMELAT'')
		set @sql = REPLACE(@sql,''PR_NAME'',''PR_NAMEENG'')
		set @sql = REPLACE(@sql,''AR_Name'',''AR_NameLat'')
		END
		--print @sql
		--select @sql
		exec (@sql)
		
		declare dogovorsCursor cursor local fast_forward for
		select * from #TempTable

		--нашли путевки
		open dogovorsCursor
		fetch next from dogovorsCursor into @dogovorCreateDate, @lastDogovorActionDate, @sDGCode, @sCreator, @dtTurDate, @sTurName, @sPartnerName, @nDGKey, @sPaymentStatus, @AnnulReason, @PriceToPay, @Payed
		while(@@fetch_status = 0)
		begin
			--if not exists (select * from #DogovorMonitorTable where datediff(mi, DM_HistoryDate, @dtHistoryDate) = 0 and DM_DGCODE = @sDGCode and DM_FilterName LIKE @sFilterName)
			--begin
				DECLARE @firstDogovorProcessDate datetime 
				DECLARE @lastDogovorProcessDate datetime -- @hiDate

				SET @firstDogovorProcessDate = (select MIN(HI_DATE) from history where HI_DGCOD = @sDGCode and HI_MOD LIKE @sHistoryMod)
				SET @lastDogovorProcessDate = (select MAX(HI_DATE) from history where HI_DGCOD = @sDGCode and HI_MOD LIKE @sHistoryMod)

--				--select @hiDate = HI_DATE from history where HI_DGCOD = @sDGCode and HI_MOD LIKE @sHistoryMod
--				if exists (select HI_DATE from history where HI_DGCOD = @sDGCode and HI_MOD LIKE @sHistoryMod)
--					select @hiDate = HI_DATE from history where HI_DGCOD = @sDGCode and HI_MOD LIKE @sHistoryMod
--				else
--					set @hiDate = NULL


				------ Получение даты тура до аннуляции ------
				IF (@dtTurDate = ''12/30/1899'')
				BEGIN
					SELECT @dtTurDate = DG_TURDATEBFRANNUL
					FROM Dogovor
					WHERE DG_Code = @sDGCode
				END
				----------------------------------------------

				SET @AnnulDate = NULL;
				------ Получение даты аннуляции ------
				SELECT @AnnulDate = History.HI_DATE
				FROM HistoryDetail
				JOIN History 
					ON HI_ID = HD_HIID
				WHERE HistoryDetail.HD_Alias = ''DG_Annulate'' AND History.HI_DgCod = @sDGCode
				--------------------------------------
				
				DECLARE @notesCount int 
				SET @notesCount =0
				SELECT @notesCount = COUNT(HI_TEXT) FROM HISTORY
				WHERE HI_DGCOD = @sDGCode AND HI_MOD = ''MTM''

				DECLARE @isBilled bit
				SET @isBilled = 0
				IF EXISTS(SELECT AC_KEY FROM ACCOUNTS WHERE AC_DGCOD = @sDGCode)
					SET @isBilled = 1

				DECLARE @messageCount int , @MessageCountRead int, @MessageCountUnRead int 
				SET @messageCount = 0
				SET @MessageCountRead  = 0
				SET @MessageCountUnRead  = 0
				SELECT @messageCount = COUNT(HI_TEXT)
			          ,@MessageCountRead = SUM(case when HI_MessEnabled <= 1 then 1 else 0 end)
			          ,@MessageCountUnRead = SUM(case when HI_MessEnabled >= 2 then 1 else 0 end)
			    FROM HISTORY
				-- Kirillov 19267 Заменил тип сообщения с WWW на MTM
				WHERE HI_DGCOD = @sDGCode AND HI_MOD = ''MTM''
				--AND HI_TEXT NOT LIKE ''От агента: %'' -- notes from web (copies of ''WWW'' moded notes)
				
				-- Kirillov 24081: подсчет значений прочитанных/не прочитанных сообщений от партнеров
				DECLARE @PartnerMessageCount int , @PartnerMessageCountRead int, @PartnerMessageCountUnRead int 
				SET @PartnerMessageCount = 0
				SET @PartnerMessageCountRead  = 0
				SET @PartnerMessageCountUnRead  = 0
				SELECT @PartnerMessageCount = COUNT(HI_TEXT)
			          ,@PartnerMessageCountRead = SUM(case when HI_MessEnabled <= 1 then 1 else 0 end)
			          ,@PartnerMessageCountUnRead = SUM(case when HI_MessEnabled >= 2 then 1 else 0 end)
			    FROM HISTORY
				WHERE HI_DGCOD = @sDGCode AND HI_MOD = ''MFP'' 
				
				--узнаем статус путевки
				DECLARE @orderStatus varchar(20);
				select @orderStatus  = case when @sLang=''en'' then o.OS_NameLat else o.OS_NAME_RUS end
				from Order_Status o
				left join Dogovor d on d.DG_SOR_CODE=o.OS_CODE
				where d.DG_Key = @nDGKey

				DECLARE @includeRecord bit
				SET @includeRecord = 0

				if (@nViewProceed = 0) OR (@lastDogovorProcessDate IS NULL)
				begin
					--insert into #DogovorMonitorTable (DM_HistoryDate, DM_ProcDate, DM_DGCODE, DM_CREATOR, DM_TurDate, DM_TurName, DM_PartnerName, DM_FilterName, DM_NotesCount, DM_PaymentStatus, DM_IsBilled, DM_MessageCount)
					--values (@dtHistoryDate, @hiDate, @sDGCode, @sCreator, @dtTurDate, @sTurName, @sPartnerName, @sFilterName, @notesCount, @sPaymentStatus, @isBilled, @messageCount)
					SET @includeRecord = 1
				end
				else
				begin
					--if @dtHistoryDate > @hiDate
					if @lastDogovorActionDate > @lastDogovorProcessDate
					begin
						--insert into #DogovorMonitorTable (DM_HistoryDate, DM_ProcDate, DM_DGCODE, DM_CREATOR, DM_TurDate, DM_TurName, DM_PartnerName, DM_FilterName, DM_NotesCount, DM_PaymentStatus, DM_IsBilled, DM_MessageCount) 
						--values (@dtHistoryDate, @hiDate, @sDGCode, @sCreator, @dtTurDate, @sTurName, @sPartnerName, @sFilterName, @notesCount, @sPaymentStatus, @isBilled, @messageCount)
						SET @includeRecord = 1
					end
				end
              
				-------------------
				IF @includeRecord = 1
				BEGIN
					IF EXISTS (SELECT dm_dgcode FROM #DogovorMonitorTable WHERE dm_dgcode = @sDGCode)
					BEGIN
						IF NOT EXISTS (SELECT 1 FROM #DogovorMonitorTable WHERE dm_dgcode = @sDGCode AND dm_filtername LIKE ''%'' + @sFilterName + ''%'')
							UPDATE #DogovorMonitorTable SET DM_FilterName = DM_FilterName + '', '' + @sFilterName WHERE dm_dgcode = @sDGCode
					END
					ELSE
					BEGIN
						INSERT INTO #DogovorMonitorTable
						VALUES (@dogovorCreateDate, @firstDogovorProcessDate, @lastDogovorProcessDate, @sDGCode, @sCreator, @dtTurDate, @sTurName, @sPartnerName, @sFilterName, @notesCount, @sPaymentStatus, @isBilled, @messageCount, @MessageCountRead , @MessageCountUnRead, @PartnerMessageCount, @PartnerMessageCountRead , @PartnerMessageCountUnRead, @AnnulReason, @AnnulDate, @PriceToPay, @Payed,@orderStatus);
					END
				END
				-------------------

			--end
			fetch next from dogovorsCursor into @dogovorCreateDate, @lastDogovorActionDate, @sDGCode, @sCreator, @dtTurDate, @sTurName, @sPartnerName, @nDGKey, @sPaymentStatus, @AnnulReason, @PriceToPay, @Payed
		end
			
		close dogovorsCursor
		deallocate dogovorsCursor
		delete from #TempTable

		fetch next from filterCursor into @nObjectAliasFilter, @sFilterType
	end

	close filterCursor
	deallocate filterCursor
end
	SELECT *
	FROM #DogovorMonitorTable
	ORDER BY DM_CreateDate
	
	DROP TABLE #TempTable
	DROP TABLE #DogovorMonitorTable

END

')
END TRY
BEGIN CATCH
insert into ##errors values ('DogovorMonitor.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on [dbo].[DogovorMonitor] to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('DogovorMonitor.sql', error_message())
END CATCH
end

print '############ end of file DogovorMonitor.sql ################'

print '############ begin of file fn_GetLastDogovorFixationDate.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[GetLastDogovorFixationDate]'') AND type in (N''FN''))
DROP FUNCTION [dbo].[GetLastDogovorFixationDate]

')
END TRY
BEGIN CATCH
insert into ##errors values ('fn_GetLastDogovorFixationDate.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE function [dbo].[GetLastDogovorFixationDate]
(
    @dogovorCode varchar(10),
    @onDate datetime,            -- дата, на которую будет искаться последний курс фиксации
	@isOnlySuccessfulTimes bit   -- брать при поиске только удачные фиксации (когда был курс, только HD_OAID = 20, иначе HD_OAID IN (20, 21))
)
returns datetime

as
begin
    declare @date datetime
    declare @result datetime
    declare @notSuccessfulTimeObjectAliasId int

    set @date = isnull(@onDate, ''20500101'')
    set @notSuccessfulTimeObjectAliasId = -1;
    if (@isOnlySuccessfulTimes = 0)
    begin
        set @notSuccessfulTimeObjectAliasId = 21;
    end

    select top 1 @result = HD_DateTimeValueNew
    from HistoryDetail with(nolock) inner join History with(nolock) on HI_ID = HD_HIID 
    where HI_DGCOD = @dogovorCode and 
          (HI_OAID = 20 or HI_OAID = @notSuccessfulTimeObjectAliasId) and 
          HD_OAID = 1151 and
          HI_DATE <= @date
    order by HD_ID desc

    -- Для обратной совместимости с прошлыми релизами, когда дата фиксации хранилась не в HistoryDetail,
    -- а как дата вставки в таблицу истории, то есть HI_DATE
    if (@result is null)
    begin
        select @result = MAX(HI_DATE)
        from History with(nolock)
        where HI_DGCOD = @dogovorCode and
              (HI_OAID = 20 or HI_OAID = @notSuccessfulTimeObjectAliasId) and
              HI_DATE <= @date
    end
    
    return (@result)
end

')
END TRY
BEGIN CATCH
insert into ##errors values ('fn_GetLastDogovorFixationDate.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT EXEC ON [dbo].[GetLastDogovorFixationDate] TO PUBLIC

')
END TRY
BEGIN CATCH
insert into ##errors values ('fn_GetLastDogovorFixationDate.sql', error_message())
END CATCH
end

print '############ end of file fn_GetLastDogovorFixationDate.sql ################'

print '############ begin of file fn_GetServiceLink.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[fn_GetServiceLink]'') AND type in (N''FN''))
DROP FUNCTION [dbo].[fn_GetServiceLink]

')
END TRY
BEGIN CATCH
insert into ##errors values ('fn_GetServiceLink.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE FUNCTION [dbo].[fn_GetServiceLink](@sv_key int)
RETURNS int
AS
BEGIN
	if ISNULL((SELECT ST_VERSION FROM Setting),'''') like ''7.2%'' or ISNULL((SELECT ST_VERSION FROM Setting),'''') like ''8.1%'' or ISNULL((SELECT ST_VERSION FROM Setting),'''') like ''9.2%''
	BEGIN
		-- если старая версия то проверяем только эти связи
		if (	EXISTS (SELECT dl_key FROM dbo.tbl_DogovorList WHERE dl_svkey = @sv_key) OR
				EXISTS (SELECT to_key FROM dbo.TourServiceList WHERE to_svkey = @sv_key) OR
				EXISTS (SELECT sr_id FROM dbo.StatusRules WHERE SR_ExcludeServiceId = @sv_key)
			)	
		BEGIN
			RETURN(1)
		END
	END
	ELSE
	BEGIN
		-- если версия новее то проверяем все связи
		if (	EXISTS (SELECT dl_key FROM dbo.tbl_DogovorList WHERE dl_svkey = @sv_key) OR
				EXISTS (SELECT to_key FROM dbo.TourServiceList WHERE to_svkey = @sv_key) OR			
				EXISTS (SELECT co_id FROM dbo.CostOffers WHERE co_svkey = @sv_key) OR
				EXISTS (SELECT cos_id FROM dbo.CostOfferServices WHERE cos_svkey = @sv_key) OR				
				EXISTS (SELECT st_id FROM dbo.ServiceTariffs WHERE st_svkey = @sv_key) OR
				EXISTS (SELECT sr_id FROM dbo.StatusRules WHERE SR_ExcludeServiceId = @sv_key)
			)	
		BEGIN
			RETURN(1)
		END
	END

	RETURN(0)
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('fn_GetServiceLink.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT EXEC ON [dbo].[fn_GetServiceLink] TO PUBLIC

')
END TRY
BEGIN CATCH
insert into ##errors values ('fn_GetServiceLink.sql', error_message())
END CATCH
end

print '############ end of file fn_GetServiceLink.sql ################'

print '############ begin of file fn_GetTurListTourProgramKeysNames.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[GetTurListTourProgramKeysNames]'') AND type in (N''TF''))
	DROP FUNCTION [dbo].[GetTurListTourProgramKeysNames]
')
END TRY
BEGIN CATCH
insert into ##errors values ('fn_GetTurListTourProgramKeysNames.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE FUNCTION [dbo].[GetTurListTourProgramKeysNames] (@countryKey INT, @cityKey INT = NULL)
	
	RETURNS @turListTourProgramsTable TABLE(t_key INT, t_name VARCHAR(200))
AS
BEGIN
	INSERT INTO @turListTourProgramsTable (t_name, t_key)
		SELECT (CASE WHEN TL_KEY > 0 THEN TL_NAME 
					ELSE ''Индивидуально'' END) AS name, TL_KEY AS id 
					FROM Turlist 
						WHERE TL_Deleted = 0 and TL_KEY = 0 
						OR (TL_KEY IN (SELECT DISTINCT TD_TRKEY FROM TurDate) 
							AND TL_KEY IN (SELECT DISTINCT TS_TRKEY FROM TurService WHERE TS_CNKEY = @countryKey AND (ISNULL(@cityKey, 0) = 0 OR TS_CTKEY = @cityKey)))
		UNION
		SELECT (CASE WHEN TS_ID > 0 THEN TS_NAME
			ELSE ''Индивидуально'' END) AS name, TS_ID as id 
			FROM Tourssearch
				WHERE TS_IsDeleted = 0 and (TS_ID = 0 OR (ISNULL(CHARINDEX ('';'' + CONVERT(NVARCHAR(256), @countryKey) + '';'' , '';'' + TS_CNKeys + '';'' ), 1) > 0
									AND (ISNULL(@cityKey, 0) = 0 OR ISNULL(CHARINDEX ('';'' + CONVERT(NVARCHAR(256),@cityKey) + '';'' , '';'' + TS_CTKeys + '';''), 1) > 0)))								
	RETURN 
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('fn_GetTurListTourProgramKeysNames.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT SELECT ON [dbo].[GetTurListTourProgramKeysNames] TO PUBLIC 
')
END TRY
BEGIN CATCH
insert into ##errors values ('fn_GetTurListTourProgramKeysNames.sql', error_message())
END CATCH
end

print '############ end of file fn_GetTurListTourProgramKeysNames.sql ################'

print '############ begin of file getChangedTableNames.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from sys.objects where name = ''getChangedTableNames'' and type = ''P'')

begin

	drop procedure getChangedTableNames

end



')
END TRY
BEGIN CATCH
insert into ##errors values ('getChangedTableNames.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



create procedure getChangedTableNames

	(@changeTrackingVersion int)

as

begin

	declare @ChangedTables as ListNvarcharValue

	

	-- We want to check for changes since the previous version

	--declare @prevTrackingVersion int = INSERT_YOUR_PREV_VERSION_HERE

	-- Comment out this line if you know the previous version

	declare @prevTrackingVersion int = @changeTrackingVersion



	-- Get a list of table with change tracking enabled

	declare @trackedTables as table (name nvarchar(1000));

	insert into @trackedTables (name)

	select sys.tables.name from sys.change_tracking_tables 

	join sys.tables ON tables.object_id = change_tracking_tables.object_id



	-- For each table name in tracked tables

	declare @tableName nvarchar(1000)

	while exists(select top 1 * from @trackedTables)

	begin

	  -- Set the current table name

	  set @tableName = (select top 1 name from @trackedTables order by name asc);



	  -- Determine if the table has changed since the previous version

	  declare @sql nvarchar(250)

	  declare @retVal int 

	  set @sql = ''select @retVal = count(*) from changetable(changes '' + @tableName + '', '' + cast(@prevTrackingVersion as varchar) + '') as changedTable''

	  exec sp_executesql @sql, N''@retVal int output'', @retVal output 

	  if @retval > 0

	  begin

		insert into @changedTables (value)

		select @tableName

	  end



	  -- Delete the current table name 

	  delete from @trackedTables where name = @tableName;  

	end



	select * from @ChangedTables

end

')
END TRY
BEGIN CATCH
insert into ##errors values ('getChangedTableNames.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on [dbo].[getChangedTableNames] to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('getChangedTableNames.sql', error_message())
END CATCH
end

print '############ end of file getChangedTableNames.sql ################'

print '############ begin of file GetFinalPriceByNCRate.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists(select id from sysobjects where xtype=''p'' and name=''GetFinalPriceByNCRate'')
	drop proc dbo.GetFinalPriceByNCRate
')
END TRY
BEGIN CATCH
insert into ##errors values ('GetFinalPriceByNCRate.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE PROCEDURE [dbo].[GetFinalPriceByNCRate]
(
@dogovor_code varchar(100),
@currency varchar(5),
@old_currency varchar(5),
@price money,
@old_price money,
@nationalCourseDate datetime = null,
@final_price money output,
@national_currency_rate decimal(19,9) output
)
AS
BEGIN
   --<DATE>2014-12-01</DATE>
   --<VERSION>2009.2.21.1</VERSION>

    set @final_price = null
	set @national_currency_rate = null

	declare @national_currency varchar(5)
	select top 1 @national_currency = RA_CODE from Rates where RA_National = 1

	declare @course decimal(19,9)
	declare @fixedCourseCurrency varchar(5)

	set @course = -1
	set @fixedCourseCurrency = ''''

	declare @dogovorDate datetime
	select @dogovorDate = dg_crdate from tbl_Dogovor with (nolock) where DG_Code = @dogovor_code

	select top 1 @course = cast(isnull(HI_TEXT, -1) as decimal(19,9)), @fixedCourseCurrency = ISNULL(HI_REMARK,'''') from History with (nolock)
	where HI_DGCOD = @dogovor_code and HI_OAId=20 
	and HI_DATE >= @dogovorDate
	order by HI_DATE desc

	if @currency = @national_currency
	begin
		set @national_currency_rate = 1
	end	
	else if @nationalCourseDate is null and @currency = @old_currency and @course <> -1 and 
			@fixedCourseCurrency = @currency -- 10558 tfs neupokoev 28.12.2012 Брать старый только в том случае, если валюты равны
	begin
		set @national_currency_rate = @course
	end
	else
	begin
		declare @rc_course decimal(19,9)
		set @rc_course = -1		
		
		select top 1 @rc_course = cast(isnull(RC_COURSE, -1) as decimal(19,9)) from RealCourses
		where
		RC_RCOD1 = @national_currency and RC_RCOD2 = @currency
		and convert(char(10), RC_DATEBEG, 102) = convert(char(10), ISNULL(@nationalCourseDate, getdate()), 102)

		if @rc_course <> -1
		begin
			set @national_currency_rate = @rc_course
		end
		else
		begin
			set @national_currency_rate = null
		end
	end

	if @national_currency_rate is not null
	begin
		set @final_price = ROUND(@national_currency_rate * @price, 2)

		-- пересчитываем цену, если надо
		declare @tmp_final_price money
		set @tmp_final_price = null
		exec [dbo].[CalcPriceByNationalCurrencyRate] @dogovor_code, @currency, @old_currency, @national_currency, @price, @old_price, '''', '''', @tmp_final_price output, @national_currency_rate, null

		if @tmp_final_price is not null
		begin
			set @final_price = @tmp_final_price
		end
		--
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('GetFinalPriceByNCRate.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on dbo.GetFinalPriceByNCRate to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('GetFinalPriceByNCRate.sql', error_message())
END CATCH
end

print '############ end of file GetFinalPriceByNCRate.sql ################'

print '############ begin of file GetNKeys.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[GetNKeys]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[GetNKeys]

')
END TRY
BEGIN CATCH
insert into ##errors values ('GetNKeys.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

create PROCEDURE [dbo].[GetNKeys]
(
	@sTable varchar(50) = null,
	@nKeyCount int,
	@nNewKey int = null output
)
AS
--<SUMMARY>Возвращает опред. количество ключей для таблицы</SUMMARY>
declare @nID int
declare @keyTable varchar(100)
declare @query nvarchar (600)

set nocount on

if @nKeyCount is null
	set @nKeyCount = 0
	
if @sTable like ''TP_TOURDATES''
	set @sTable = ''TP_TURDATES''

set nocount on

if (@sTable like ''key_%'')
begin
	set @keyTable = @sTable
end
else begin
	select @keyTable = 
		case 
			when @sTable like ''TP_TURDATES'' then ''Key_TPTurDates''
			when @sTable like ''TP_Lists'' then ''Key_TPLists''
			when @sTable like ''TP_Services'' then ''Key_TPServices''
			when @sTable like ''TP_Tours'' then ''Key_TPTours''
			when @sTable like ''TP_ServiceLists'' then ''Key_TPServiceLists''
			when @sTable like ''TP_Prices'' then ''Key_TPPrices''
			when @sTable like ''Accmdmentype'' then ''Key_Accmdmentype''
			when @sTable like ''AddDescript1'' then ''Key_AddDescript1''
			when @sTable like ''AddDescript2'' then ''Key_AddDescript2''
			when @sTable like ''Advertise'' then ''Key_Advertise''
			when @sTable like ''Aircraft'' then ''Key_Aircraft''
			when @sTable like ''AirService'' then ''Key_AirService''
			when @sTable like ''AllHotelOption'' then ''Key_AllHotelOption''
			when @sTable like ''AnkFields'' then ''Key_AnkFields''
			when @sTable like ''AnnulReasons'' then ''Key_AnnulReasons''
			when @sTable like ''Bills'' then ''Key_Bills''
			when @sTable like ''Cabine'' then ''Key_Cabine''
			when @sTable like ''CauseDiscounts'' then ''Key_CauseDiscounts''
			when @sTable like ''Charter'' then ''Key_Charter''
			when @sTable like ''CityDictionary'' then ''Key_CityDictionary''
			when @sTable like ''Clients'' then ''Key_Clients''
			when @sTable like ''Discount'' then ''Key_Discount''
			when @sTable like ''DOCUMENTSTATUS'' then ''KEY_DOCUMENTSTATUS''
			when @sTable like ''Dogovor'' then ''Key_Dogovor''
			when @sTable like ''DogovorList'' then ''Key_DogovorList''
			when @sTable like ''EventList'' then ''Key_EventList''
			when @sTable like ''Events'' then ''Key_Events''
			when @sTable like ''ExcurDictionar'' then ''Key_ExcurDictionar''
			when @sTable like ''Factura'' then ''Key_Factura''
			when @sTable like ''HotelDictionar'' then ''Key_HotelDictionar''
			when @sTable like ''HotelRooms'' then ''Key_HotelRooms''
			when @sTable like ''KindOfPay'' then ''Key_KindOfPay''
			when @sTable like ''Locks'' then ''Key_Locks''
			when @sTable like ''Order_Status'' then ''Key_Order_Status''
			when @sTable like ''Orders'' then ''Key_Orders''
			when @sTable like ''Pansion'' then ''Key_Pansion''
			when @sTable like ''Partners'' then ''Key_Partners''
			when @sTable like ''PartnerStatus'' then ''Key_PartnerStatus''
			when @sTable like ''PaymentType'' then ''Key_PaymentType''
			when @sTable like ''PriceList'' then ''Key_PriceList''
			when @sTable like ''PriceServiceLink'' then ''Key_PriceServiceLink''
			when @sTable like ''Profession'' then ''Key_Profession''
			when @sTable like ''PrtDeps'' then ''Key_PrtDeps''
			when @sTable like ''PrtDogs'' then ''Key_PrtDogs''
			when @sTable like ''PrtGroups'' then ''Key_PrtGroups''
			when @sTable like ''PrtWarns'' then ''Key_PrtWarns''
			when @sTable like ''Rep_Options'' then ''Key_Rep_Options''
			when @sTable like ''Rep_Profiles'' then ''Key_Rep_Profiles''
			when @sTable like ''Resorts'' then ''Key_Resorts''
			when @sTable like ''Rooms'' then ''Key_Rooms''
			when @sTable like ''RoomsCategory'' then ''Key_RoomsCategory''
			when @sTable like ''RoomType'' then ''Key_RoomType''
			when @sTable like ''Service'' then ''Key_Service''
			when @sTable like ''ServiceList'' then ''Key_ServiceList''
			when @sTable like ''Ship'' then ''Key_Ship''
			when @sTable like ''TOURSERVLIST'' then ''KEY_TOURSERVLIST''
			when @sTable like ''Transfer'' then ''Key_Transfer''
			when @sTable like ''Transport'' then ''Key_Transport''
			when @sTable like ''Turist'' then ''Key_Turist''
			when @sTable like ''Turlist'' then ''Key_Turlist''
			when @sTable like ''TURMARGIN'' then ''Key_TURMARGIN''
			when @sTable like ''TurService'' then ''Key_TurService''
			when @sTable like ''TypeAdvertise'' then ''Key_TypeAdvertise''
			when @sTable like ''UserList'' then ''Key_UserList''
			when @sTable like ''Vehicle'' then ''Key_Vehicle''
			when @sTable like ''WarningList'' then ''Key_WarningList''
			when @sTable like ''HotelTypes'' then ''Key_HotelTypes''
		end
end

if @keyTable is not null
begin
	set @query = N''
	declare @maxKeyFromTable int
	begin try
	set @maxKeyFromTable = isnull((Select id from @keyTable with (xlock, rowlock, holdlock)), 1)
	Set @nNewKeyOut = @maxKeyFromTable + @nKeyCount

	update @keyTable with (xlock, rowlock) set Id = @nNewKeyOut
	end try
	begin catch
		DECLARE @ErrorMessage NVARCHAR(4000);
		DECLARE @ErrorSeverity INT;
		DECLARE @ErrorState INT;
		SELECT
			@ErrorMessage=ERROR_MESSAGE(),
			@ErrorSeverity=ERROR_SEVERITY(),
			@ErrorState=ERROR_STATE();
		RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
	end catch''
	set @query = REPLACE(@query, ''@keyTable'', @keyTable)
	begin tran
		EXECUTE sp_executesql @query, N''@nNewKeyOut int output, @nKeyCount int'', @nNewKeyOut = @nNewKey  output,  @nKeyCount = @nKeyCount
	commit tran
end
else
begin	
	begin tran
		begin try
			if exists (select top 1 1 from Keys where Key_Table = @sTable)
			begin
				Select @nNewKey = id + @nKeyCount from Keys WITH (xlock, rowlock, holdlock) where Key_Table = @sTable
				update Keys with (xlock, rowlock) set Id = @nNewKey where Key_Table = @sTable
			end
			else
			begin
				insert into Keys (Key_Table, Id) values (@sTable, @nKeyCount)
				set @nNewKey=@nKeyCount
			end
		end try
		begin catch
			DECLARE @ErrorMessage NVARCHAR(4000);
			DECLARE @ErrorSeverity INT;
			DECLARE @ErrorState INT;
			SELECT
				@ErrorMessage=ERROR_MESSAGE(),
				@ErrorSeverity=ERROR_SEVERITY(),
				@ErrorState=ERROR_STATE();
			RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
		end catch
	commit tran
end

return 0

')
END TRY
BEGIN CATCH
insert into ##errors values ('GetNKeys.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT EXECUTE ON dbo.GetNKeys TO public 

')
END TRY
BEGIN CATCH
insert into ##errors values ('GetNKeys.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('GetNKeys.sql', error_message())
END CATCH
end

print '############ end of file GetNKeys.sql ################'

print '############ begin of file GetServerGuid.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[GetServerGuid]'') AND type in (N''P'', N''PC''))
	DROP PROCEDURE [dbo].[GetServerGuid]
')
END TRY
BEGIN CATCH
insert into ##errors values ('GetServerGuid.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


CREATE PROCEDURE [dbo].[GetServerGuid]
AS
BEGIN
			
	SELECT HASHBYTES(''md5'', CAST(hw.cpu_count AS NVARCHAR(10)) + CAST(hw.hyperthread_ratio AS VARCHAR(10)) + @@version + @@servername)
	FROM sys.dm_os_sys_info hw

END
')
END TRY
BEGIN CATCH
insert into ##errors values ('GetServerGuid.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT EXECUTE on [dbo].[GetServerGuid] TO PUBLIC
')
END TRY
BEGIN CATCH
insert into ##errors values ('GetServerGuid.sql', error_message())
END CATCH
end

print '############ end of file GetServerGuid.sql ################'

print '############ begin of file GetServiceList.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[GetServiceList]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[GetServiceList]
')
END TRY
BEGIN CATCH
insert into ##errors values ('GetServiceList.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE procedure [dbo].[GetServiceList] 
(
--<VERSION>2009.2.20.8</VERSION>
--<DATE>2014-02-11</DATE>
@TypeOfRelult int, -- 1-список по услугам, 2-список по туристам на услуге
@SVKey int, 
@Codes varchar(100), 
@SubCode1 int=null,
@Date datetime =null, 
@QDID int =null,
@QPID int =null,
@ShowHotels bit =null,
@ShowFligthDep bit =null,
@ShowDescription bit =null,
@State smallint=null,
@SubCode2 int = null,
@PrKey int = null
)
as 

--koshelev
--2012-07-19 TFS 6699 блокировки на базе мешали выполнению хранимки, вынужденная мера
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

if (@SVKey=14)
	set @SubCode1 = null

declare @Query varchar(8000)
 
CREATE TABLE #Result
(
	DG_Code nvarchar(max), DG_Key int, DG_DiscountSum money, DG_Price money, DG_Payed money,
	DG_PriceToPay money, DG_Rate nvarchar(3), DG_NMen int, PR_Name nvarchar(max), PR_Name_Lat nvarchar(max), CR_Name nvarchar(max), CR_Name_Lat nvarchar(max),
	DL_Key int, DL_NDays int, DL_NMen int, DL_Reserved int, DL_CTKeyTo int, DL_CTKeyFrom int, DL_CNKEYFROM int,
	DL_SubCode1 int, TL_Key int, TL_Name nvarchar(max), TL_Name_Lat nvarchar(max),  TUCount int, TU_NameRus nvarchar(max), TU_NameLat nvarchar(max),
	TU_FNameRus nvarchar(max), TU_FNameLat nvarchar(max), TU_Key int, TU_Sex Smallint, TU_PasportNum nvarchar(max),
	TU_PasportType nvarchar(max), TU_PasportDateEnd datetime, TU_BirthDay datetime, TU_Hotels nvarchar(max), TU_Hotels_Lat nvarchar(max),
	Request smallint, Commitment smallint, Allotment smallint, Ok smallint, TicketNumber nvarchar(max),
	FlightDepDLKey int, FligthDepDate datetime, FlightDepNumber nvarchar(max), ServiceDescription nvarchar(max), ServiceDescription_Lat nvarchar(max),
	ServiceDateBeg datetime, ServiceDateEnd datetime, RM_Name nvarchar(max), RC_Name nvarchar(max), SD_RLID int,
	TU_SNAMERUS nvarchar(max), TU_SNAMELAT nvarchar(max), TU_IDKEY int
)
 
if @TypeOfRelult = 2
begin
	--- создаем таблицу в которой пронумируем незаполненых туристов
	CREATE TABLE #TempServiceByDate
	(
		SD_ID int identity(1,1) not null,
		SD_Date datetime,
		SD_DLKey int,
		SD_RLID int,
		SD_QPID int,
		SD_TUKey int,
		SD_RPID int,
		SD_State int
	)

	-- вносим все записи которые нам могут подойти
	if (@SVKey =14)
	BEGIN
		insert into #TempServiceByDate(SD_Date, SD_DLKey, SD_RLID, SD_QPID,	SD_TUKey, SD_RPID, SD_State)
		select SD_Date, SD_DLKey, SD_RLID, SD_QPID,	SD_TUKey, SD_RPID, SD_State
		from ServiceByDate as SSD join Dogovorlist on DL_KEY = SD_DLKey
			join BusTransferPoints on DL_CODE = BP_KEY
			join BusTransfers on BT_KEY = BP_BTKEY
		where DL_SVKEY = @SVKey
		and BP_BTKEY = convert(int, @Codes)
		and ((BT_CTKEYFROM = BP_CTKEYFROM and SSD.SD_Date = @Date) or (BT_CTKEYFROM != BP_CTKEYFROM and BP_DAYTO is not null and SSD.SD_Date = DATEADD(day, BP_DAYTO - 1,@Date)))
		and ((@SubCode1 is null) or (DL_SUBCODE1 = @SubCode1))
		and ((@QPID is null) or (SD_QPID = @QPID))
		and ((@State is null) or (SD_State = @State))
		--mv 24.10.2012 не понячл зачем нужен был подзапрос, но точно он приводил к следущей проблеме
		-- если отбираем с фильтром по статусу, то статус проверял на любой из дней, а не тот на который формируется список
		and (@PrKey is null or DL_PARTNERKEY = @PrKey)
	END
	ELSE
	BEGIN
		insert into #TempServiceByDate(SD_Date, SD_DLKey, SD_RLID, SD_QPID,	SD_TUKey, SD_RPID, SD_State)
		select SD_Date, SD_DLKey, SD_RLID, SD_QPID,	SD_TUKey, SD_RPID, SD_State
		from ServiceByDate as SSD join Dogovorlist on DL_KEY = SD_DLKey
		where DL_SVKEY = @SVKey
		and DL_CODE = convert(int, @Codes)
		and ((@SubCode1 is null) or (DL_SUBCODE1 = @SubCode1))
		and ((@QPID is null) or (SD_QPID = @QPID))
		and ((@State is null) or (SD_State = @State))
		--mv 24.10.2012 не понячл зачем нужен был подзапрос, но точно он приводил к следущей проблеме
		-- если отбираем с фильтром по статусу, то статус проверял на любой из дней, а не тот на который формируется список
		and SSD.SD_Date = @Date and (@PrKey is null or DL_PARTNERKEY = @PrKey)
	END	
	
	declare @Id int, @SDDate datetime, @SDDLKey int, @SDTUKey int,
	@oldDlKey int, @oldDate datetime, @i int

	set @i = -1
	 
	DECLARE noBodyTurists CURSOR FOR 
	select SD_ID, SD_Date, SD_DLKey, SD_TUKey
	from #TempServiceByDate
	where SD_TUKey is null
	order by SD_DLKey, SD_Date

	OPEN noBodyTurists
	FETCH NEXT FROM noBodyTurists INTO @Id, @SDDate, @SDDLKey, @SDTUKey
	WHILE @@FETCH_STATUS = 0
	BEGIN
		-- если мы встретили новую дату или услугу то сбрасываем счетчик
		if @oldDlKey != @SDDLKey or @oldDate != @SDDate
		begin
			set @i = -1
		end
			
		update #TempServiceByDate
		set SD_TUKey = @i
		where SD_ID = @Id
		
		set @i = @i - 1

		set @oldDlKey = @SDDLKey
		set @oldDate = @SDDate
		
		FETCH NEXT FROM noBodyTurists INTO @Id, @SDDate, @SDDLKey, @SDTUKey
	END
	CLOSE noBodyTurists
	DEALLOCATE noBodyTurists 

	--select * from #TempServiceByDate

	-- 29.10.13 Гусак изменил привязку покупателя
	-- с left join Partners on dl_agent = pr_key
	-- на 		left join Partners on dg_partnerkey = pr_key
	if (@SVKey =14)
	BEGIN
		SET @Query = ''
		INSERT INTO #Result (DG_Code, DG_Key, DG_DiscountSum, DG_Price, DG_Payed, 
		DG_PriceToPay, DG_Rate, DG_NMen, 
		PR_Name, PR_Name_Lat, CR_Name,  CR_Name_Lat,
		DL_Key, DL_NDays, DL_NMen, DL_Reserved, DL_CTKeyTo, DL_CTKeyFrom, DL_SubCode1, ServiceDateBeg, ServiceDateEnd, 
		TL_KEY, TUCount, TU_NameRus, TU_NameLat, TU_FNameRus, TU_FNameLat, TU_Key, 
		TU_Sex, TU_PasportNum, TU_PasportType, TU_PasportDateEnd, TU_BirthDay, TicketNumber, TU_SNAMERUS, TU_SNAMELAT, TU_IDKEY)
		SELECT	  DG_CODE, DG_KEY, DG_DISCOUNTSUM, DG_PRICE, DG_PAYED, 
		(case DG_PDTTYPE when 1 then DG_PRICE+DG_DISCOUNTSUM else DG_PRICE end ), DG_RATE, DG_NMEN, 
		PR_NAME, PR_NAMEENG, CR_NAME, CR_NameLat, DL_KEY, DL_NDays, DL_NMEN, DL_RESERVED, DL_CTKey, DL_SubCode2, DL_SubCode1, 
		DL_DateBeg, CASE WHEN '' + CAST(@SVKey as varchar(10)) + ''=3 THEN DATEADD(DAY,1,DL_DateEnd) ELSE DL_DateEnd END,
		DG_TRKey, 0, TU_NAMERUS, TU_NAMELAT, TU_FNAMERUS, TU_FNAMELAT, SD_TUKey, case when SD_TUKey > 0 then isnull(TU_SEX,0) else null end, TU_PASPORTTYPE + ''''№'''' + TU_PASPORTNUM, TU_PASPORTTYPE, 
		TU_PASPORTDATEEND, TU_BIRTHDAY, TU_NumDoc, TU_SNAMERUS, TU_SNAMELAT, TU_IDKEY
		FROM  Dogovor join Dogovorlist on dl_dGKEY = DG_KEY
		join BusTransferPoints on DL_CODE = BP_KEY
		join BusTransfers on BT_KEY = BP_BTKEY
		left join Partners on dg_partnerkey = pr_key
		join Controls on dl_control = cr_key
		join #TempServiceByDate on SD_DLKey = DL_KEY
		left join TuristService on tu_dlkey = dl_key and TU_TUKEY = SD_TUKey
		left join Turist on tu_key = tu_tukey
		WHERE ''
		
		SET @Query=@Query + ''
				DL_SVKEY='' + CAST(@SVKey as varchar(20)) + '' AND BP_BTKEY in ('' + @Codes + '') AND '' +				
				+ ''((BT_CTKEYFROM = BP_CTKEYFROM and '''''' + CAST(@Date as varchar(20)) + '''''' BETWEEN DL_DATEBEG AND DL_DATEEND)'' + 
				+ ''or (BT_CTKEYFROM != BP_CTKEYFROM and BP_DAYTO is not null and DATEADD(day, BP_DAYTO - 1, '''''' + CAST(@Date as varchar(20)) + '''''') BETWEEN DL_DATEBEG AND DL_DATEEND))''			
	END
	ELSE
	BEGIN
		SET @Query = ''
		INSERT INTO #Result (DG_Code, DG_Key, DG_DiscountSum, DG_Price, DG_Payed, 
		DG_PriceToPay, DG_Rate, DG_NMen, 
		PR_Name, PR_Name_Lat, CR_Name,  CR_Name_Lat,
		DL_Key, DL_NDays, DL_NMen, DL_Reserved, DL_CTKeyTo, DL_CTKeyFrom, DL_SubCode1, ServiceDateBeg, ServiceDateEnd, 
		TL_KEY, TUCount, TU_NameRus, TU_NameLat, TU_FNameRus, TU_FNameLat, TU_Key, 
		TU_Sex, TU_PasportNum, TU_PasportType, TU_PasportDateEnd, TU_BirthDay, TicketNumber, TU_SNAMERUS, TU_SNAMELAT, TU_IDKEY)
		SELECT	  DG_CODE, DG_KEY, DG_DISCOUNTSUM, DG_PRICE, DG_PAYED, 
		(case DG_PDTTYPE when 1 then DG_PRICE+DG_DISCOUNTSUM else DG_PRICE end ), DG_RATE, DG_NMEN, 
		PR_NAME, PR_NAMEENG, CR_NAME, CR_NameLat, DL_KEY, DL_NDays, DL_NMEN, DL_RESERVED, DL_CTKey, DL_SubCode2, DL_SubCode1, 
		DL_DateBeg, CASE WHEN '' + CAST(@SVKey as varchar(10)) + ''=3 THEN DATEADD(DAY,1,DL_DateEnd) ELSE DL_DateEnd END,
		DG_TRKey, 0, TU_NAMERUS, TU_NAMELAT, TU_FNAMERUS, TU_FNAMELAT, SD_TUKey, case when SD_TUKey > 0 then isnull(TU_SEX,0) else null end, TU_PASPORTTYPE + ''''№'''' + TU_PASPORTNUM, TU_PASPORTTYPE, 
		TU_PASPORTDATEEND, TU_BIRTHDAY, TU_NumDoc, TU_SNAMERUS, TU_SNAMELAT, TU_IDKEY
		FROM  Dogovor join Dogovorlist on dl_dGKEY = DG_KEY
--		left join Partners on dl_agent = pr_key
		left join Partners on dg_partnerkey = pr_key
		join Controls on dl_control = cr_key
		join #TempServiceByDate on SD_DLKey = DL_KEY
		left join TuristService on tu_dlkey = dl_key and TU_TUKEY = SD_TUKey
		left join Turist on tu_key = tu_tukey
		WHERE ''
		
		SET @Query=@Query + ''
				DL_SVKEY='' + CAST(@SVKey as varchar(20)) + '' AND DL_CODE in ('' + @Codes + '') AND '''''' + CAST(@Date as varchar(20)) + '''''' BETWEEN DL_DATEBEG AND DL_DATEEND ''			
	end
		IF @QPID is not null or @QDID is not null
		BEGIN
			IF @QPID is not null
				SET @Query=@Query + ''and SD_QPID IN ('' + CAST(@QPID as varchar(20)) + '')''
			ELSE
				--buryak
				--2013-02-20 TFS 11520 MT.Экран "Список на услугу".Не отображались путевки без туристов.
				SET @Query=@Query + ''and exists (SELECT top 1 SD_DLKEY FROM #TempServiceByDate, QuotaParts WHERE SD_QPID=QP_ID and QP_QDID IN ('' + CAST(@QDID as varchar(20)) + '') and SD_DLKEY=DL_Key and (tu_tukey is null or sd_tukey = tu_tukey))''
		END
				
		if (@SubCode1 != ''0'')
			SET @Query=@Query + '' AND DL_SUBCODE1 in ('' + CAST(@SubCode1 as varchar(20)) + '')''
		IF @State is not null
			SET @Query=@Query + '' and SD_State='' + CAST(@State as varchar(1))
		if (@SubCode2 != ''0'')
			SET @Query=@Query + '' AND DL_SUBCODE2 in ('' + CAST(@SubCode2 as varchar(20)) + '')''
		SET @Query=@Query + '' 
		group by DG_CODE, DG_KEY, DG_DISCOUNTSUM, DG_PRICE, DG_PAYED, DG_PDTTYPE, DG_RATE, DG_NMEN, 
		PR_NAME, PR_NAMEENG, CR_NAME, CR_NameLat, DL_KEY, DL_NDays, DL_NMEN, DL_RESERVED, DL_CTKey, DL_SubCode2, DL_SubCode1, DL_DateBeg,
		DL_DateEnd, DG_TRKey, TU_NAMERUS, TU_NAMELAT, TU_FNAMERUS,
		TU_FNAMELAT, SD_TUKey, TU_SEX, TU_PASPORTNUM, TU_PASPORTTYPE, TU_PASPORTDATEEND, TU_BIRTHDAY, TU_NumDoc, TU_SNAMERUS, TU_SNAMELAT, TU_IDKEY''
end
else
begin
	-- 29.10.13 Гусак изменил привязку покупателя
	-- с left join Partners on dl_agent = pr_key
	-- на 		left join Partners on dg_partnerkey = pr_key
	if (@SVKey =14)
	BEGIN
		SET @Query = ''
		INSERT INTO #Result (DG_Code, SD_RLID, RM_Name, RC_Name, DG_KEY, DG_DISCOUNTSUM, DG_PRICE, DG_PAYED,
		DG_PriceToPay, DG_RATE, DG_NMEN,
		PR_NAME, PR_Name_Lat, CR_NAME, CR_NAME_Lat, DL_NDays, DL_NMEN, DL_RESERVED, DL_CTKeyTo, DL_SubCode1,
		ServiceDateBeg, ServiceDateEnd, TL_Key, TUCount, DL_Key, DL_CTKeyFrom)
		select DG_CODE, SD_RLID, RM_Name, RC_Name, DG_KEY, DG_DISCOUNTSUM, DG_PRICE, DG_PAYED,
		(case when DG_PDTTYPE = 1 then DG_PRICE+DG_DISCOUNTSUM else DG_PRICE end ), DG_RATE, DG_NMEN,
		PR_NAME, PR_NAMEENG, CR_NAME, CR_NAMELat, DL_NDays, 
		--mv 24.10.2012 -убрал очень странный код - в поле кол-во человек выводилосб количество комнат, сделал количество мест хотя бы
		--case when QT_ByRoom = 1 then count(distinct SD_RLID) else count(distinct SD_RPID) end as DL_NMEN,
		COUNT(SD_RPID),
		DL_RESERVED, DL_CTKey, DL_SubCode1, DL_DateBeg, DL_DateEnd, DG_TRKey, Count(distinct SD_TUKey), DL_KEY, DL_SubCode2
		from ServiceByDate left join RoomNumberLists on sd_rlid = rl_id
		left join Rooms on rl_rmkey = rm_key
		left join RoomsCategory on rl_rckey = rc_key
		left join QuotaParts on sd_qpid = qp_id
		left join QuotaDetails on QP_QDID = QD_ID and QP_Date = QD_Date
		left join Quotas on QT_ID = QD_QTID
		join Dogovorlist on sd_dlkey = dl_key
		join Controls on dl_control = cr_key
		join BusTransferPoints on DL_CODE = BP_KEY
		join BusTransfers on BT_KEY = BP_BTKEY
		join Dogovor on dl_dGKEY = DG_KEY
		left join Partners on dg_partnerkey = pr_key
		where DL_SVKEY='' + CAST(@SVKey as varchar(20)) + '' 
			AND BP_BTKEY in ('' + @Codes + '') 
			and ((BT_CTKEYFROM = BP_CTKEYFROM and '''''' + CAST(@Date as varchar(20)) + '''''' BETWEEN DL_DATEBEG AND DL_DATEEND AND SD_Date = '''''' + CAST(@Date as varchar(20)) + '''''' ) 
				or (BT_CTKEYFROM != BP_CTKEYFROM and BP_DAYTO is not null and DATEADD(day,BP_DAYTO - 1, '''''' + CAST(@Date as varchar(20)) + '''''') BETWEEN DL_DATEBEG AND DL_DATEEND
				AND SD_Date = DATEADD(day,BP_DAYTO - 1, '''''' + CAST(@Date as varchar(20)) + '''''')))''
		if (@SubCode2 != ''0'' and @SubCode2 is not NULL)
			SET @Query=@Query + '' AND DL_SUBCODE2 in ('' + CAST(@SubCode2 as varchar(20)) + '')''
	END
	ELSE
	BEGIN
	SET @Query = ''
		INSERT INTO #Result (DG_Code, SD_RLID, RM_Name, RC_Name, DG_KEY, DG_DISCOUNTSUM, DG_PRICE, DG_PAYED,
		DG_PriceToPay, DG_RATE, DG_NMEN,
		PR_NAME, PR_Name_Lat, CR_NAME, CR_NAME_Lat, DL_NDays, DL_NMEN, DL_RESERVED, DL_CTKeyTo, DL_SubCode1,
		ServiceDateBeg, ServiceDateEnd, TL_Key, TUCount, DL_Key, DL_CTKeyFrom)
		select DG_CODE, SD_RLID, RM_Name, RC_Name, DG_KEY, DG_DISCOUNTSUM, DG_PRICE, DG_PAYED,
		(case when DG_PDTTYPE = 1 then DG_PRICE+DG_DISCOUNTSUM else DG_PRICE end ), DG_RATE, DG_NMEN,
		PR_NAME, PR_NAMEENG, CR_NAME, CR_NAMELat, DL_NDays, 
		--mv 24.10.2012 -убрал очень странный код - в поле кол-во человек выводилосб количество комнат, сделал количество мест хотя бы
		--case when QT_ByRoom = 1 then count(distinct SD_RLID) else count(distinct SD_RPID) end as DL_NMEN,
		COUNT(SD_RPID),
		DL_RESERVED, DL_CTKey, DL_SubCode1, DL_DateBeg, CASE WHEN '' + CAST(@SVKey as varchar(10)) + '' = 3 THEN DATEADD(DAY,1,DL_DateEnd) ELSE DL_DateEnd END, DG_TRKey, Count(distinct SD_TUKey), DL_KEY, DL_SubCode2
		from ServiceByDate left join RoomNumberLists on sd_rlid = rl_id
		left join Rooms on rl_rmkey = rm_key
		left join RoomsCategory on rl_rckey = rc_key
		left join QuotaParts on sd_qpid = qp_id
		left join QuotaDetails on QP_QDID = QD_ID and QP_Date = QD_Date
		left join Quotas on QT_ID = QD_QTID
		join Dogovorlist on sd_dlkey = dl_key
		join Controls on dl_control = cr_key
--		left join Partners on dl_agent = pr_key
		join Dogovor on dl_dGKEY = DG_KEY
		left join Partners on dg_partnerkey = pr_key
		where DL_SVKEY='' + CAST(@SVKey as varchar(20)) + '' 
			AND (('' + CAST(@SVKey as varchar(20)) + '' = 14 and dl_code in (select BP_KEY from BusTransferPoints where BP_BTKEY = '' + @Codes + '')) or DL_CODE in ('' + @Codes + '')) 
			AND '''''' + CAST(@Date as varchar(20)) + '''''' BETWEEN DL_DATEBEG AND DL_DATEEND
			--mv 24.10.2012 добавил фильтр по дате SD, так как просмотр идет относительно этой даты
			AND SD_Date = '''''' + CAST(@Date as varchar(20)) + '''''' ''
	END	
		
	if @QDID is not null
		SET @Query = @Query + '' and qp_qdid = '' + CAST(@QDID as nvarchar(max))
	if @QPID is not null
		SET @Query = @Query + '' and qp_id = '' + CAST(@QPID as nvarchar(max))
	IF @State is not null
		SET @Query=@Query + '' and SD_State='' + CAST(@State as varchar(1))
	-- mv 24.10.2012 - не было фильтра по услуге, в список попадали лишние
	IF @SubCode1 is not null
		SET @Query=@Query + '' and DL_SUBCODE1 = '' + CAST(@SubCode1 as varchar(20))
	
	SET @Query = @Query + ''
		group by DG_CODE, SD_RLID, DG_KEY, DG_DISCOUNTSUM, DG_PRICE, DG_PAYED,
		DG_PDTTYPE, DG_DISCOUNTSUM, DG_RATE, DG_NMEN,
		PR_NAME, PR_NAMEENG, CR_NAME,CR_NAMELat, DL_NDays, DL_RESERVED, DL_CTKey, DL_SubCode1, DL_SubCode2,
		DL_DateBeg, DL_DateEnd, DG_TRKey, RM_Name, RC_Name, DL_KEY''
end

--PRINT @Query
EXEC (@Query)
 
UPDATE #Result SET #Result.TL_Name=dbo.GetTourName(#Result.TL_Key)
UPDATE #Result SET TL_Name_Lat = (SELECT top 1 res1.TL_Name FROM #Result res1 WHERE TL_Key=res1.TL_Key)

--select * from  #Result

if @TypeOfRelult=1
BEGIN
	UPDATE #Result SET #Result.Request=(SELECT COUNT(*) FROM ServiceByDate WHERE SD_DLKey = #Result.DL_Key AND SD_State=4)
	UPDATE #Result SET #Result.Commitment=(SELECT COUNT(*) FROM ServiceByDate WHERE SD_DLKey = #Result.DL_Key AND SD_State=2)
	UPDATE #Result SET #Result.Allotment=(SELECT COUNT(*) FROM ServiceByDate WHERE SD_DLKey = #Result.DL_Key AND SD_State=1)
	UPDATE #Result SET #Result.Ok=(SELECT COUNT(*) FROM ServiceByDate WHERE SD_DLKey = #Result.DL_Key AND SD_State=3)
END
else
BEGIN
	UPDATE #Result SET #Result.Request=(SELECT COUNT(*) FROM #TempServiceByDate WHERE SD_DLKey=#Result.DL_Key AND SD_TUKey=#Result.TU_Key and SD_State=4)
	UPDATE #Result SET #Result.Commitment=(SELECT COUNT(*) FROM #TempServiceByDate WHERE SD_DLKey=#Result.DL_Key AND SD_TUKey=#Result.TU_Key and SD_State=2)
	UPDATE #Result SET #Result.Allotment=(SELECT COUNT(*) FROM #TempServiceByDate WHERE SD_DLKey=#Result.DL_Key AND SD_TUKey=#Result.TU_Key and SD_State=1)
	UPDATE #Result SET #Result.Ok=(SELECT COUNT(*) FROM #TempServiceByDate WHERE SD_DLKey=#Result.DL_Key AND SD_TUKey=#Result.TU_Key and SD_State=3)
END
 
IF @ShowHotels=1
BEGIN
	IF @TypeOfRelult = 2
	BEGIN
		DECLARE @HD_Name varchar(100), @HD_Name2_Lat varchar(100),  @HD_Stars varchar(25), @PR_Name varchar(100), @PR_Name_Lat varchar(100), @TU_Key int, @HD_Key int, @PR_Key int, @TU_KeyPrev int, @TU_Hotels varchar(255), @TU_Hotels_Lat varchar(255)
		DECLARE curServiceList CURSOR FOR 
			SELECT	  DISTINCT HD_Name, HD_NAMELAT, HD_Stars, PR_Name, PR_NAMEENG, TU_TUKey, HD_Key, PR_Key 
			FROM  HotelDictionary, DogovorList, TuristService, Partners
			WHERE	  PR_Key=DL_PartnerKey and HD_Key=DL_Code and TU_DLKey=DL_Key and TU_TUKey in (SELECT TU_Key FROM #Result) and dl_SVKey=3 
			ORDER BY TU_TUKey
		OPEN curServiceList
		FETCH NEXT FROM curServiceList INTO	  @HD_Name,@HD_Name2_Lat, @HD_Stars,@PR_Name, @PR_Name_Lat, @TU_Key, @HD_Key, @PR_Key
		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF @TU_Key!=@TU_KeyPrev or @TU_KeyPrev is null
			begin
			  Set @TU_Hotels=@HD_Name+'' ''+@HD_Stars+'' (''+@PR_Name+'')''
			  Set @TU_Hotels_Lat=@HD_Name2_Lat+'' ''+@HD_Stars+'' (''+@PR_Name_Lat+'')''
			end
			ELSE
			begin
			  Set @TU_Hotels=@TU_Hotels+'', ''+@HD_Name+'' ''+@HD_Stars+'' (''+@PR_Name+'')''
			  Set @TU_Hotels_Lat=@TU_Hotels_Lat+'', ''+@HD_Name2_Lat+'' ''+@HD_Stars+'' (''+@PR_Name_Lat+'')''
			end
			UPDATE #Result SET TU_Hotels=@TU_Hotels WHERE TU_Key=@TU_Key
			UPDATE #Result SET TU_Hotels_Lat=@TU_Hotels_Lat WHERE TU_Key=@TU_Key
			SET @TU_KeyPrev=@TU_Key
			FETCH NEXT FROM curServiceList INTO	   @HD_Name,@HD_Name2_Lat, @HD_Stars, @PR_Name, @PR_Name_Lat, @TU_Key, @HD_Key, @PR_Key
		END
		CLOSE curServiceList
		DEALLOCATE curServiceList
	END
	IF @TypeOfRelult = 1
	BEGIN
		DECLARE @HD_Name1 varchar(100), @HD_Name1_lat varchar(100), @HD_Stars1 varchar(25), @PR_Name1 varchar(100), @PR_Name1_Lat varchar(100), @DL_Key1 int, @HD_Key1 int, 
				@PR_Key1 int, @DL_KeyPrev1 int, @TU_Hotels1 varchar(255), @TU_Hotels1_Lat varchar(255), @DG_Key int, @DG_KeyPrev int
		DECLARE curServiceList CURSOR FOR 
			--SELECT DISTINCT HD_Name, HD_Stars, P.PR_Name, DogList.DL_Key, HD_Key, PR_Key--, DG_Key
			--FROM HotelDictionary, DogovorList DogList, TuristService, Partners P
			--WHERE P.PR_Key = DogList.DL_PartnerKey and HD_Key = DogList.DL_Code and TU_DLKey = DogList.DL_Key and
			--TU_TUKey in (SELECT TU_TUKEY FROM TuristService WHERE TU_DLKEY in (SELECT DL_KEY FROM #Result)) 
			--and DL_SVKey=3 
			--ORDER BY DogList.DL_Key
			SELECT DISTINCT HD_Name, HD_NameLat, HD_Stars, HD_Key, P.PR_Name, PR_NAMEENG, P.PR_Key, DogList.DL_Key, R.DG_Key
			FROM HotelDictionary, DogovorList DogList, Partners P, #Result R
			WHERE P.PR_Key = DogList.DL_PartnerKey and HD_Key = DogList.DL_Code and DogList.DL_DGKey = R.DG_Key			
				  and DogList.DL_SVKey=3 
			ORDER BY R.DG_Key
		OPEN curServiceList
		FETCH NEXT FROM curServiceList INTO @HD_Name1, @HD_Name1_lat, @HD_Stars1, @HD_Key1, @PR_Name1, @PR_Name1_Lat, @PR_Key1, @DL_Key1, @DG_Key
		WHILE @@FETCH_STATUS = 0
		BEGIN
			IF @DG_Key != @DG_KeyPrev or @DG_KeyPrev is null  
			BEGIN
			  Set @TU_Hotels1=@HD_Name1+'' ''+@HD_Stars1+'' (''+@PR_Name1+'')''
			  Set @TU_Hotels1_Lat=@HD_Name1_lat+'' ''+@HD_Stars1+'' (''+@PR_Name1_Lat+'')''
			END
			ELSE
			BEGIN
			  Set @TU_Hotels1=@TU_Hotels1+'', ''+@HD_Name1+'' ''+@HD_Stars1+'' (''+@PR_Name1+'')''
			  Set @TU_Hotels1=@TU_Hotels1_Lat+'', ''+@HD_Name1_lat+'' ''+@HD_Stars1+'' (''+@PR_Name1_Lat+'')''
			END
			UPDATE #Result SET TU_Hotels=@TU_Hotels1 WHERE DG_Key=@DG_Key --DL_Key=@DL_Key1
			UPDATE #Result SET TU_Hotels_Lat=@TU_Hotels1_Lat WHERE DG_Key=@DG_Key --DL_Key=@DL_Key1
			SET @DG_KeyPrev = @DG_Key
			FETCH NEXT FROM curServiceList INTO @HD_Name1, @HD_Name1_lat, @HD_Stars1, @HD_Key1, @PR_Name1, @PR_Name1_Lat, @PR_Key1, @DL_Key1, @DG_Key
		END
		CLOSE curServiceList
		DEALLOCATE curServiceList
	END
END
 
IF @ShowFligthDep=1 and @SVKey=1
BEGIN
	IF @TypeOfRelult = 2
	BEGIN
		Update #Result SET FlightDepDLKey=(Select TOP 1 DL_Key From DogovorList,TuristService Where TU_DLKey=DL_Key and DL_DGKey=#Result.DG_Key and DL_CTKey=#Result.DL_CTKeyFrom and DL_SubCode2=#Result.DL_CTKeyTo and TU_TUKey=#Result.TU_Key and DL_DGKey=#Result.DG_Key and dl_svkey=1 order by dl_datebeg desc)
		if exists (select 1 from #Result Where FlightDepDLKey is null)
			Update #Result SET FlightDepDLKey=(Select TOP 1 DL_Key From DogovorList,TuristService Where TU_DLKey=DL_Key and DL_DGKey=#Result.DG_Key and DL_CTKey=#Result.DL_CTKeyFrom and TU_TUKey=#Result.TU_Key and DL_DGKey=#Result.DG_Key and dl_svkey=1 order by dl_datebeg desc) where FlightDepDLKey is null
		--если по городу не нашли ишем по стране
		if exists (select 1 from #Result Where FlightDepDLKey is null)     
		begin
			update #Result set DL_CNKEYFROM = (select top 1 ct_cnkey from citydictionary where ct_key =#Result.DL_CTKEYFROM)
			Update #Result SET FlightDepDLKey=(Select TOP 1 DL_Key From DogovorList,TuristService Where TU_DLKey=DL_Key and DL_DGKey=#Result.DG_Key and DL_CNKey=#Result.DL_CNKeyFrom and TU_TUKey=#Result.TU_Key and DL_DGKey=#Result.DG_Key and dl_svkey=1 order by dl_datebeg desc)	where FlightDepDLKey is null	  
		end
	END
	ELSE
	BEGIN
		Update #Result SET FlightDepDLKey=(Select TOP 1 DL_Key From DogovorList Where DL_DGKey=#Result.DG_Key and DL_CTKey=#Result.DL_CTKeyFrom and DL_SubCode2=#Result.DL_CTKeyTo and DL_DGKey=#Result.DG_Key and dl_svkey=1 order by dl_datebeg desc)
		if exists (select 1 from #Result Where FlightDepDLKey is null)
			Update #Result SET FlightDepDLKey=(Select TOP 1 DL_Key From DogovorList Where DL_DGKey=#Result.DG_Key and DL_CTKey=#Result.DL_CTKeyFrom and DL_DGKey=#Result.DG_Key and dl_svkey=1 order by dl_datebeg desc) where FlightDepDLKey is null
		--если по городу не нашли ишем по стране
		if exists (select 1 from #Result Where FlightDepDLKey is null)     
		begin
			update #Result set DL_CNKEYFROM = (select top 1 ct_cnkey from citydictionary where ct_key =#Result.DL_CTKEYFROM)
			Update #Result SET FlightDepDLKey=(Select TOP 1 DL_Key From DogovorList,TuristService Where TU_DLKey=DL_Key and DL_DGKey=#Result.DG_Key and DL_CNKey=#Result.DL_CNKeyFrom and TU_TUKey=#Result.TU_Key and DL_DGKey=#Result.DG_Key and dl_svkey=1 order by dl_datebeg desc)	where FlightDepDLKey is null	  
		end
	END
	Update #Result set FligthDepDate = (select dl_dateBeg From DogovorList where DL_Key=#Result.FlightDepDLKey)
	Update #Result set FlightDepNumber = (select CH_AirLineCode + '' '' + CH_Flight From DogovorList, Charter where DL_Code=CH_Key and DL_Key=#Result.FlightDepDLKey)
END

IF @ShowDescription=1
BEGIN
	IF @SVKey=1
		Update #Result SET ServiceDescription=LEFT((SELECT ISNUll(AS_Code, '''') + ''-'' + AS_NameRus FROM AirService WHERE AS_Key=DL_SubCode1),80),
		ServiceDescription_Lat=LEFT((SELECT ISNUll(AS_Code, '''') + ''-'' + AS_NAMELAT FROM AirService WHERE AS_Key=DL_SubCode1),80)
	ELSE IF (@SVKey=2 or @SVKey=4)
		Update #Result SET ServiceDescription=LEFT((SELECT TR_Name FROM Transport WHERE TR_Key=DL_SubCode1),80),
							ServiceDescription_Lat=LEFT((SELECT TR_NAMELAT FROM Transport WHERE TR_Key=DL_SubCode1),80)
	ELSE IF (@SVKey=3 or @SVKey=8)
	BEGIN
		Update #Result SET ServiceDescription=LEFT((SELECT RM_Name + ''('' + RC_Name + '')'' + AC_Name FROM Rooms,RoomsCategory,AccMdMenType,HotelRooms WHERE HR_Key=DL_SubCode1 and HR_RMKey=RM_Key and HR_RCKey=RC_Key and HR_ACKey=AC_Key),80),
							ServiceDescription_Lat=LEFT((SELECT RM_NAMELAT + ''('' + RC_NAMELAT + '')'' + AC_NAMELAT FROM Rooms,RoomsCategory,AccMdMenType,HotelRooms WHERE HR_Key=DL_SubCode1 and HR_RMKey=RM_Key and HR_RCKey=RC_Key and HR_ACKey=AC_Key),80)
		IF @SVKey=8
			Update #Result SET ServiceDescription=''All accommodations'' where DL_SubCode1=0
	END
	ELSE IF (@SVKey=7 or @SVKey=9)
	BEGIN
		Update #Result SET ServiceDescription=LEFT((SELECT ISNULL(CB_Code,'''') + '','' + ISNULL(CB_Category,'''') + '','' + ISNULL(CB_Name,'''') FROM Cabine WHERE CB_Key=DL_SubCode1),80),
							ServiceDescription_Lat=LEFT((SELECT ISNULL(CB_Code,'''') + '','' + ISNULL(CB_Category,'''') + '','' + ISNULL(CB_NAMELAT,'''') FROM Cabine WHERE CB_Key=DL_SubCode1),80)
		IF @SVKey=9
			Update #Result SET ServiceDescription=''All accommodations'' where DL_SubCode1=0
	END
	ELSE
		Update #Result SET ServiceDescription=LEFT((SELECT A1_Name FROM AddDescript1 WHERE A1_Key=DL_SubCode1),80), 
							ServiceDescription_Lat=LEFT((SELECT A1_NAMELAT FROM AddDescript1 WHERE A1_Key=DL_SubCode1),80) WHERE ISNULL(DL_SubCode1,0)>0
END

--print @Query
SELECT * FROM #Result

')
END TRY
BEGIN CATCH
insert into ##errors values ('GetServiceList.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on [dbo].[GetServiceList] to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('GetServiceList.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('GetServiceList.sql', error_message())
END CATCH
end

print '############ end of file GetServiceList.sql ################'

print '############ begin of file GetServiceLoadListData.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[GetServiceLoadListData]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[GetServiceLoadListData]
')
END TRY
BEGIN CATCH
insert into ##errors values ('GetServiceLoadListData.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE procedure [dbo].[GetServiceLoadListData]
(
--<VERSION>2009.2.20</VERSION>
--<DATE>2017-04-18</DATE>
@SVKey int,
@Code int,
@PRKey int =null,-- @PRKEY=null все
@DateStart smalldatetime = null,
@DaysCount int,
@CityDepartureKey int = null,-- город вылета
@bShowByRoom     bit =null,  -- показывать информацию по номерам (по умолчанию по людям)
@bShowByPartner  bit =null,  -- информацию разделять по партнерам
@bShowState      bit =null,  -- показать статус бронирования (запрос, на квоте, Ok) 
@bShowCommonInfo bit =null,  -- показывать общую информацию по загрузке услуги
@nGridFilter int = 0              -- фильтр в зависимости от экрана / 1-английский вариант экранов
)
as 
/*
insert into debug (db_date,db_n1,db_n2,db_n3) values (@DateStart,@DaysCount,@SVKey,89)
insert into debug (db_date,db_n1,db_n2,db_n3) values (@DateStart,@PRKey,@bShowByRoom,88)
insert into debug (db_date,db_n1,db_n2,db_n3) values (@DateStart,@bShowByPartner,@bShowState,87)
insert into debug (db_date,db_n1,db_n2,db_n3) values (@DateStart,@bShowCommonInfo,@Code,86)
*/
if @SVKey!=3
	Set @bShowByRoom=0

if @SVKey = 14
	SELECT @Code = BP_BTKEY from BusTransferPoints WHERE BP_KEY = @Code

DECLARE @DateEnd smalldatetime
Set @DateEnd = DATEADD(DAY, @DaysCount-1, @DateStart)

CREATE TABLE #ServiceLoadList
(
SL_ID INT IDENTITY(1,1) NOT NULL, 
SL_ServiceName nvarchar(100), SL_State smallint,
SL_SubCode1 int, SL_SubCode2 int, SL_PRKey int
/*SL_DataType это мнимая колонка, есть только при выводе результата 
содержит тип информации для записей с итогами
(1 - общий итог, 2 - данные по услуге)
*/
)
DECLARE @n int, @nMax int, @str nvarchar(max),@SL_SubCode1 int, @SL_SubCode2 int, @s nvarchar(1000), @ServiceName nvarchar(255), @ServiceName_1 nvarchar(255)
set @n=1 

WHILE @n <= @DaysCount
BEGIN
	set @str = ''ALTER TABLE #ServiceLoadList ADD SL_'' + CAST(@n as nvarchar(3)) + '' nvarchar(20)''
	exec (@str)
	set @n = @n + 1
END

if @SVKey != 8
begin
	if @bShowByPartner =1 and @bShowState=1
	BEGIN
		if @SVKey = 14
		BEGIN
			insert into #ServiceLoadList (SL_SubCode1, SL_PRKey, SL_State)
			select distinct DL_SubCode2, DL_PartnerKey, ISNULL(SD_State,0) 
			from DogovorList join ServiceByDate on SD_DLKey = DL_KEY
						join Dogovor on DG_Key=DL_DGKey 
						join BusTransferPoints on DL_CODE = BP_KEY
						join BusTransfers on BT_KEY = BP_BTKEY
			where DL_SVKey=@SVKey and BT_KEY=@Code and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
				and SD_Date >= (case WHEN BT_CTKEYFROM != BP_CTKEYFROM AND BP_DAYTO is not null THEN DATEADD(day, 1 - BP_DAYTO,@DateStart) ELSE @DateStart END)
				and	SD_Date <= (case WHEN BT_CTKEYFROM != BP_CTKEYFROM AND BP_DAYTO is not null THEN DATEADD(day, BP_DAYTO - 1,@DateEnd) ELSE @DateEnd END)
		END
		ELSE
		BEGIN
			insert into #ServiceLoadList (SL_SubCode1, SL_PRKey, SL_State)
			select distinct DL_SubCode1, DL_PartnerKey, ISNULL(SD_State,0) from DogovorList, ServiceByDate, Dogovor
			where	SD_DLKey=DL_Key and DG_Key=DL_DGKey and DL_SVKey=@SVKey and DL_Code=@Code and SD_Date between @DateStart and @DateEnd and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
		END
	END	
else if @bShowByPartner =0 and @bShowState=1
BEGIN
	if @SVKey = 14
	BEGIN
		insert into #ServiceLoadList (SL_SubCode1, SL_State)
		select distinct DL_SubCode2, ISNULL(SD_State,0) 
		from DogovorList join ServiceByDate on SD_DLKey = DL_KEY
						join Dogovor on DG_Key=DL_DGKey 
						join BusTransferPoints on DL_CODE = BP_KEY
						join BusTransfers on BT_KEY = BP_BTKEY
			where DL_SVKey=@SVKey and BT_KEY=@Code and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
				and SD_Date >= (case WHEN BT_CTKEYFROM != BP_CTKEYFROM AND BP_DAYTO is not null THEN DATEADD(day, 1 - BP_DAYTO,@DateStart) ELSE @DateStart END)
				and	SD_Date <= (case WHEN BT_CTKEYFROM != BP_CTKEYFROM AND BP_DAYTO is not null THEN DATEADD(day, BP_DAYTO - 1,@DateEnd) ELSE @DateEnd END)
	END
	ELSE
	BEGIN
		insert into #ServiceLoadList (SL_SubCode1, SL_State)
		select distinct DL_SubCode1, ISNULL(SD_State,0) from DogovorList, ServiceByDate, Dogovor
		where	SD_DLKey=DL_Key and DG_Key=DL_DGKey and DL_SVKey=@SVKey and DL_Code=@Code and SD_Date between @DateStart and @DateEnd and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
	END	
END
else if @bShowByPartner =1 and @bShowState=0
BEGIN
	if @SVKey = 14
	BEGIN
		insert into #ServiceLoadList (SL_SubCode1, SL_PRKey)
		select distinct DL_SubCode2, DL_PartnerKey
		from DogovorList join ServiceByDate on SD_DLKey = DL_KEY
						join Dogovor on DG_Key=DL_DGKey 
						join BusTransferPoints on DL_CODE = BP_KEY
						join BusTransfers on BT_KEY = BP_BTKEY
			where DL_SVKey=@SVKey and BT_KEY=@Code and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
				and SD_Date >= (case WHEN BT_CTKEYFROM != BP_CTKEYFROM AND BP_DAYTO is not null THEN DATEADD(day, 1 - BP_DAYTO,@DateStart) ELSE @DateStart END)
				and	SD_Date <= (case WHEN BT_CTKEYFROM != BP_CTKEYFROM AND BP_DAYTO is not null THEN DATEADD(day, BP_DAYTO - 1,@DateEnd) ELSE @DateEnd END)
	END
	ELSE
	BEGIN
		insert into #ServiceLoadList (SL_SubCode1, SL_PRKey)
		select distinct DL_SubCode1, DL_PartnerKey from DogovorList, Dogovor
		where	DL_SVKey=@SVKey and DG_Key=DL_DGKey and DL_Code=@Code and ((DL_DateBeg between @DateStart and @DateEnd) or (DL_DateEnd between @DateStart and @DateEnd)) and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
	END	
END	
else
begin
	if @SVKey = 14
	BEGIN
		insert into #ServiceLoadList (SL_SubCode1)
		select distinct DL_SubCode2
		from DogovorList join ServiceByDate on SD_DLKey = DL_KEY
						join Dogovor on DG_Key=DL_DGKey 
						join BusTransferPoints on DL_CODE = BP_KEY
						join BusTransfers on BT_KEY = BP_BTKEY
			where DL_SVKey=@SVKey and BT_KEY=@Code and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
				and SD_Date >= (case WHEN BT_CTKEYFROM != BP_CTKEYFROM AND BP_DAYTO is not null THEN DATEADD(day, 1 - BP_DAYTO,@DateStart) ELSE @DateStart END)
				and	SD_Date <= (case WHEN BT_CTKEYFROM != BP_CTKEYFROM AND BP_DAYTO is not null THEN DATEADD(day, BP_DAYTO - 1,@DateEnd) ELSE @DateEnd END)
	END
	ELSE
	BEGIN
		insert into #ServiceLoadList (SL_SubCode1)
		select distinct DL_SubCode1 from DogovorList, Dogovor
		where	DL_SVKey=@SVKey and DG_Key=DL_DGKey and DL_Code=@Code and ((DL_DateBeg between @DateStart and @DateEnd) or (DL_DateEnd between @DateStart and @DateEnd)) and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
	END
end
end if @SVKey = 8
begin 
	if @bShowByPartner =1 and @bShowState=1
		insert into #ServiceLoadList (SL_SubCode1, SL_SubCode2, SL_PRKey, SL_State)
			select distinct DL_SubCode1, DL_SubCode2, DL_PartnerKey, ISNULL(SD_State,0) from DogovorList, ServiceByDate, Dogovor
			where	SD_DLKey=DL_Key and DG_Key=DL_DGKey and DL_SVKey=@SVKey and DL_Code=@Code and SD_Date between @DateStart and @DateEnd and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
	else if @bShowByPartner =0 and @bShowState=1
		insert into #ServiceLoadList (SL_SubCode1, SL_SubCode2, SL_State)
			select distinct DL_SubCode1, DL_SubCode2, ISNULL(SD_State,0) from DogovorList, ServiceByDate, Dogovor
			where	SD_DLKey=DL_Key and DG_Key=DL_DGKey and DL_SVKey=@SVKey and DL_Code=@Code and SD_Date between @DateStart and @DateEnd and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
	else if @bShowByPartner =1 and @bShowState=0
		insert into #ServiceLoadList (SL_SubCode1, SL_SubCode2, SL_PRKey)
			select distinct DL_SubCode1, DL_SubCode2, DL_PartnerKey from DogovorList, Dogovor
			where	DL_SVKey=@SVKey and DG_Key=DL_DGKey and DL_Code=@Code and ((DL_DateBeg between @DateStart and @DateEnd) or (DL_DateEnd between @DateStart and @DateEnd)) and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
	else
		insert into #ServiceLoadList (SL_SubCode1, SL_SubCode2)
			select distinct DL_SubCode1, DL_SubCode2 from DogovorList, Dogovor
			where	DL_SVKey=@SVKey and DG_Key=DL_DGKey and DL_Code=@Code and ((DL_DateBeg between @DateStart and @DateEnd) or (DL_DateEnd between @DateStart and @DateEnd)) and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
end
 
while exists(select SL_SubCode1 from #ServiceLoadList where SL_ServiceName is null)
BEGIN
	if @SVKey != 8
	begin
		select @SL_SubCode1=SL_SubCode1 from #ServiceLoadList where SL_ServiceName is null
		if (@nGridFilter=1)
			begin
				--для англ версии
				exec GetSvCode1Name @SVKey, @SL_SubCode1, @s output,@s output,@s output,@ServiceName output
			end
		else
			begin
				--для русской версии
				exec GetSvCode1Name @SVKey,@SL_SubCode1,@s output,@ServiceName output,@s output,@s output
			end
		UPDATE #ServiceLoadList SET SL_ServiceName = LEFT(COALESCE(@ServiceName, ''''),100) where SL_SubCode1=@SL_SubCode1
	end if @SVKey = 8
	begin
		select @SL_SubCode1=SL_SubCode1, @SL_SubCode2=SL_SubCode2 from #ServiceLoadList where SL_ServiceName is null
		exec GetSvCode1Name @SVKey,@SL_SubCode1,@s output,@ServiceName output,@s output,@s output
		exec dbo.GetSvCode2Name @SVKey, @SL_SubCode2, @ServiceName_1 output, @s output
		UPDATE #ServiceLoadList SET SL_ServiceName = LEFT(COALESCE(@ServiceName, '''') + N'','' + COALESCE(@ServiceName_1, ''''),100) where SL_SubCode1=@SL_SubCode1 and SL_SubCode2=@SL_SubCode2
	end 
END

CREATE TABLE #ServiceByDateLoadList
(
SLD_Date datetime, 
SLD_SubCode2 int, 
SLD_PartnerKey int,
SLD_State smallint, 
SLD_CountPlaces int
)

if (@SVKey = 14)
BEGIN			
	insert into #ServiceByDateLoadList (SLD_Date, SLD_SubCode2, SLD_PartnerKey, SLD_State, SLD_CountPlaces)
	select (case WHEN (BT_CTKEYFROM != BP_CTKEYFROM and BP_DAYTO is not null)
					 											   THEN DATEADD(day, 1 - BP_DAYTO,SD_Date) 
					 											   ELSE SD_Date END) date1, DL_SubCode2, DL_PartnerKey, SD_State, Count(Distinct SD_ID)
	from	DogovorList join ServiceByDate on SD_DLKey = DL_KEY
	join Dogovor on DG_Key=DL_DGKey
	join BusTransferPoints on DL_CODE = BP_KEY
	join BusTransfers on BT_KEY = BP_BTKEY  
	where DL_SVKey=@SVKey and BT_KEY=@Code 
	and SD_Date >= (case WHEN BT_CTKEYFROM != BP_CTKEYFROM AND BP_DAYTO is not null THEN DATEADD(day, 1 - BP_DAYTO,@DateStart) ELSE @DateStart END)
	and	SD_Date <= (case WHEN BT_CTKEYFROM != BP_CTKEYFROM AND BP_DAYTO is not null THEN DATEADD(day, BP_DAYTO - 1,@DateEnd) ELSE @DateEnd END)
	and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
	group by case WHEN BT_CTKEYFROM != BP_CTKEYFROM and BP_DAYTO is not null
					 											   THEN DATEADD(day, 1 - BP_DAYTO,SD_Date)
					 											   ELSE SD_Date END, DL_SubCode2,DL_PartnerKey,SD_State
					 											   							
	DECLARE curSLoadList CURSOR FOR SELECT
	''UPDATE #ServiceLoadList SET SL_'' + CAST(CAST(SLD_Date-@DateStart+1 as int) as nvarchar(5)) + ''= ISNULL(SL_'' + CAST(CAST(SLD_Date-@DateStart+1 as int) as nvarchar(5)) + '',0)+'' + CAST(SLD_CountPlaces as nvarchar(5)) + '' WHERE SL_SubCode1='' + CAST(SLD_SubCode2 as nvarchar(10)) + CASE WHEN @bShowByPartner=1 THEN '' AND SL_PRKey='' + CAST(SLD_PartnerKey as nvarchar(10)) ELSE '''' END + CASE WHEN @bShowState=1 THEN '' AND SL_State='' + CAST(ISNULL(SLD_State,0) as nvarchar(10)) ELSE '''' END
	from #ServiceByDateLoadList WHERE SLD_Date<=@DateEnd and SLD_Date>=@DateStart
END
else 
BEGIN
	If @bShowByRoom=1
	begin
		DECLARE curSLoadList CURSOR FOR SELECT
			''UPDATE #ServiceLoadList SET SL_'' + CAST(CAST(SD_Date-@DateStart+1 as int) as nvarchar(5)) + ''= ISNULL(SL_'' + CAST(CAST(SD_Date-@DateStart+1 as int) as nvarchar(5)) + '',0)+'' + CAST(Count(Distinct SD_RLID) as nvarchar(5)) + '' WHERE SL_SubCode1='' + CAST(DL_SubCode1 as nvarchar(10)) + CASE WHEN @bShowByPartner=1 THEN '' AND SL_PRKey='' + CAST(DL_PartnerKey as nvarchar(10)) ELSE '''' END + CASE WHEN @bShowState=1 THEN '' AND SL_State='' + CAST(ISNULL(SD_STATE,0) as nvarchar(10)) ELSE '''' END
			from	DogovorList,ServiceByDate, Dogovor 
			where	SD_DLKey=DL_Key and DG_Key=DL_DGKey
					and DL_SVKey=@SVKey and DL_Code=@Code 
					and DL_DateBeg<=@DateEnd and DL_DateEnd>=@DateStart
					and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
					and SD_Date<=@DateEnd and SD_Date>=@DateStart
			group by SD_Date,DL_SubCode1,DL_PartnerKey,SD_State
	end
	Else
	begin
		DECLARE curSLoadList CURSOR FOR SELECT
			''UPDATE #ServiceLoadList SET SL_'' + CAST(CAST(SD_Date-@DateStart+1 as int) as nvarchar(5)) + ''= ISNULL(SL_'' + CAST(CAST(SD_Date-@DateStart+1 as int) as nvarchar(5)) + '',0)+'' + CAST(Count(SD_ID) as nvarchar(5)) + '' WHERE SL_SubCode1='' + CAST(DL_SubCode1 as nvarchar(10)) + CASE WHEN @SVKey=8 THEN ''AND SL_SubCode2='' + CAST(DL_SUBCODE2 as nvarchar(10)) ELSE '''' END + CASE WHEN @bShowByPartner=1 THEN '' AND SL_PRKey='' + CAST(DL_PartnerKey as nvarchar(10)) ELSE '''' END + CASE WHEN @bShowState=1 THEN '' AND SL_State='' + CAST(ISNULL(SD_STATE,0) as nvarchar(10)) ELSE '''' END
			from	DogovorList,ServiceByDate, Dogovor 
			where	SD_DLKey=DL_Key and DG_Key=DL_DGKey
					and DL_SVKey=@SVKey and DL_Code=@Code
					and DL_DateBeg<=@DateEnd and DL_DateEnd>=@DateStart
					and ((DL_PartnerKey=@PRKEY) or (@PRKEY is null)) 
					and ((DG_CTDepartureKey=@CityDepartureKey) or (@CityDepartureKey is null))
					and SD_Date<=@DateEnd and SD_Date>=@DateStart
			group by SD_Date,DL_SubCode1,DL_PartnerKey,SD_State, DL_SVKey, DL_SUBCODE2
	end
END	

OPEN curSLoadList
FETCH NEXT FROM curSLoadList INTO	@str
WHILE @@FETCH_STATUS = 0
BEGIN
	exec (@str)
	FETCH NEXT FROM curSLoadList INTO	@str
END
CLOSE curSLoadList
DEALLOCATE curSLoadList

Set @str = ''''
set @n=1
set @str = @str + ''SELECT SL_ServiceName, SL_State, SL_SubCode1, '' + CASE WHEN @SVKey=8 THEN ''SL_SubCode2, '' ELSE '''' END + '' SL_PRKey ''
WHILE @n <= @DaysCount
BEGIN
	set @str = @str + '', SL_'' + CAST(@n as nvarchar(3)) 
	set @n = @n + 1
END

Set @str = @str + '' from #ServiceLoadList order by SL_ServiceName, SL_SubCode1, '' + CASE WHEN @SVKey=8 THEN ''SL_SubCode2,'' ELSE '''' END + '' SL_PRKey, SL_State''

exec (@str)

')
END TRY
BEGIN CATCH
insert into ##errors values ('GetServiceLoadListData.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on [dbo].[GetServiceLoadListData] to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('GetServiceLoadListData.sql', error_message())
END CATCH
end

print '############ end of file GetServiceLoadListData.sql ################'

print '############ begin of file GetSvCode1Name.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists(select id from sysobjects where xtype=''p'' and name=''GetSvCode1Name'')
	drop proc dbo.GetSvCode1Name
')
END TRY
BEGIN CATCH
insert into ##errors values ('GetSvCode1Name.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE    PROCEDURE [dbo].[GetSvCode1Name]
(
--<VERSION>2009.2.18.2</VERSION>
--<DATA>06.12.2013</DATA>
	@nSvKey INT,
	@nCode1 INT,
	@sTitle VARCHAR(800) OUTPUT,
	@sName VARCHAR(800) OUTPUT,
	@sTitleLat VARCHAR(800) OUTPUT,
	@sNameLat VARCHAR(800) OUTPUT,
	@bIsQuote bit = null
) AS
DECLARE 
	@nRoom INT,
	@nCategory INT,
	@sNameCategory VARCHAR(800),
	@sNameCategoryLat VARCHAR(800),
	@nHrMain INT,
	@nAgeFrom INT,
	@nAgeTo INT,
	@sAcCode VARCHAR(800),
	@sAcCodeLat VARCHAR(800),
	@sTmp VARCHAR(800),
	@bTmp INT,

	@TYPE_FLIGHT INT, 
	@TYPE_TRANSFER INT,
	@TYPE_BUSTRANSFER INT,
	@TYPE_HOTEL INT,
	@TYPE_EXCUR INT,
	@TYPE_VISA INT,
	@TYPE_INSUR INT,
	@TYPE_SHIP INT,
	@TYPE_HOTELADDSRV INT,
	@TYPE_SHIPADDSRV INT,
	@TYPE_FLIGHTADDCSOTSSRV INT,
	@TYPE_HOTELADDCOSTSSRV INT

	
	Set @TYPE_FLIGHT = 1
	Set @TYPE_TRANSFER = 2
	Set @TYPE_HOTEL = 3
	Set @TYPE_BUSTRANSFER = 14
	Set @TYPE_EXCUR = 4
	Set @TYPE_VISA = 5
	Set @TYPE_INSUR = 6
	Set @TYPE_SHIP = 7
	Set @TYPE_HOTELADDSRV = 8
	Set @TYPE_SHIPADDSRV = 9
	Set @TYPE_FLIGHTADDCSOTSSRV = 12
	Set @TYPE_HOTELADDCOSTSSRV = 13
		
	Set @sName = ''''

	IF @nSvKey = @TYPE_FLIGHT
	BEGIN
		SET @sTitle = ''Тариф''
		SET @sName = ''Любой''
		SET @sTitleLat = ''Tariff''
		SET @sNameLat = ''Any''

		IF EXISTS(SELECT * FROM dbo.AirService WHERE AS_Key = @nCode1) and (@nCode1 <> -1)
			SELECT	@sName = IsNull(AS_Code, '''') + ''-'' + AS_NameRus,
				@sNameLat = IsNull(AS_Code, '''') + ''-'' + IsNull(AS_NameLat, AS_NameRus)
			FROM 	dbo.AirService 
			WHERE	AS_Key = @nCode1
	END
	ELSE
	IF (@nSvKey = @TYPE_TRANSFER) or (@nSvKey = @TYPE_EXCUR) or (@nSvKey = @TYPE_BUSTRANSFER)
	BEGIN
		SET @sTitle = ''Транспорт''
		SET @sName = ''Любой''
		SET @sTitleLat = ''Transport''
		SET @sNameLat = ''Any''
		
		IF EXISTS(SELECT * FROM dbo.Transport WHERE TR_Key = @nCode1)
			SELECT 	@sName = TR_Name + '','' + CAST(IsNull(TR_NMen, 0) AS varchar(5)),
				@sNameLat = IsNull(TR_NameLat, TR_Name) + '','' + CAST(IsNull(TR_NMen, 0) AS varchar(5))
			FROM 	dbo.Transport 
			WHERE 	TR_Key = @nCode1		
	END
	ELSE
	IF (@nSvKey = @TYPE_HOTELADDSRV or @nSvKey = @TYPE_HOTEL)
	BEGIN
		IF @nCode1 = 0
			IF ISNULL(@bIsQuote,0) = 1
			BEGIN
				SET @sTitle = ''Тип номера''
				SET @sName = ''Все типы номеров''
				SET @sTitleLat = ''Room type''
				SET @sNameLat = ''All room types''
			END
			ELSE
			BEGIN
				SET @sTitle = ''Размещение''
				SET @sName = ''Все размещения''
				SET @sTitleLat = ''Accommodation''
				SET @sNameLat = ''All accommodations''
			END
		ELSE	
			IF ISNULL(@bIsQuote,0) = 1
			BEGIN
				EXEC GetRoomName @nCode1, @sName output, @sNameLat output

				Set @sTitle = ''Тип номера''
				Set @sTitleLat = ''Room type''
			END
			ELSE
			BEGIN
				EXEC GetRoomKey @nCode1, @nRoom output
				EXEC GetRoomCategoryKey @nCode1, @nCategory output
				
				if (@nRoom is null and @nSvKey=@TYPE_HOTELADDSRV)
				begin
					Set @sName = ''''
					Set @sNameLat = ''''
				end
				else
					EXEC GetRoomName @nRoom, @sName output, @sNameLat output
				
				if (@nCategory is null and @nSvKey=@TYPE_HOTELADDSRV)
				begin
					Set @sNameCategory = ''''
					Set @sNameCategoryLat = ''''
				end
				else
					EXEC GetRoomCtgrName @nCategory, @sNameCategory output, @sNameCategoryLat output

				if (@sNameCategory <> '''')
					Set @sName = @sName + ''('' + @sNameCategory + '')''
				
				if (@sNameCategoryLat <> '''')
					Set @sNameLat = @sNameLat + ''('' + @sNameCategoryLat + '')''
				
				Set @sTitle = ''Размещение''
				Set @sTitleLat = ''Accommodation''
			END
			
			if isnull((select SS_ParmValue from SystemSettings where SS_ParmName = ''CartAccmdMenTypeView''), 0) = 0
			begin
				SELECT @nHrMain = IsNull(HR_Main, 0), @nAgeFrom = IsNull(HR_AgeFrom, 0), @nAgeTo = IsNull(HR_AgeTo, 0), @sAcCode = IsNull(AC_Name, ''''),  @sAcCodeLat = IsNull(AC_NameLat, '''') FROM dbo.HotelRooms, dbo.AccmdMenType WHERE (HR_Key = @nCode1) AND (HR_AcKey = AC_Key)				
			end
			else
			begin
				SELECT @nHrMain = IsNull(HR_Main, 0), @nAgeFrom = IsNull(HR_AgeFrom, 0), @nAgeTo = IsNull(HR_AgeTo, 0), @sAcCode = IsNull(AC_Code, '''') FROM dbo.HotelRooms, dbo.AccmdMenType WHERE (HR_Key = @nCode1) AND (HR_AcKey = AC_Key)
			end
	END
	ELSE
	if (@nSvKey = @TYPE_SHIPADDSRV or @nSvKey = @TYPE_SHIP)
	BEGIN
		IF @nCode1 = 0
		BEGIN
			Set @sTitle = ''Каюта''
			Set @sName = ''Все каюты''
			SET @sTitleLat = ''Cabin''
			SET @sNameLat = ''All cabins''
		END
		ELSE
		BEGIN
			SET @sTitle = ''Каюта''
			SET @sName = ''Любая''
			SET @sTitleLat = ''Cabin''
			SET @sNameLat = ''Any''

			IF EXISTS( SELECT * FROM dbo.Cabine WHERE CB_Key = @nCode1 )
				SELECT	@sName = CB_Code + '','' + CB_Category + '','' + CB_Name,
					@sNameLat = CB_Code + '','' + CB_Category + '','' + ISNULL(CB_NameLat,CB_Name)
				FROM dbo.Cabine 
				WHERE CB_Key = @nCode1
		END
	END
	ELSE
	if (@nSvKey = @TYPE_HOTELADDCOSTSSRV)
	BEGIN
		SET @sTitle = ''Группа отелей''
		SET @sName = ''Любая''
		SET @sTitleLat = ''Hotels group''
		SET @sNameLat = ''Any''
		
		IF EXISTS(SELECT * FROM dbo.HotelsAddcostsGroups WHERE HAG_ID = @nCode1)
			SELECT 	@sName = SUBSTRING(ISNULL(HAG_NAME,''''), 1, 800), @sNameLat = SUBSTRING(ISNULL(HAG_NAME,''''), 1, 800)
				FROM 	dbo.HotelsAddcostsGroups WHERE 	HAG_ID = @nCode1		
	END
	ELSE
	if (@nSvKey = @TYPE_FLIGHTADDCSOTSSRV)
	BEGIN
		SET @sTitle = ''Группа перелетов''
		SET @sName = ''Любая''
		SET @sTitleLat = ''Flights group''
		SET @sNameLat = ''Any''
		
		IF EXISTS(SELECT * FROM dbo.FlightsGroup WHERE FG_Id = @nCode1)
			SELECT 	@sName = SUBSTRING(ISNULL(FG_NAME,''''), 1, 800), @sNameLat = SUBSTRING(ISNULL(FG_NAME,''''), 1, 800)
				FROM 	dbo.FlightsGroup WHERE 	FG_Id = @nCode1		
	END
	ELSE
	BEGIN
		Set @sTmp = ''CODE1''
		EXEC dbo.GetSvListParm @nSvKey, @sTmp, @bTmp output
	
		IF @bTmp > 0
		BEGIN
			SET @sTitle = ''Доп.описание''
			SET @sName = ''Любое''
			SET @sTitleLat = ''Add.description''
			SET @sNameLat = ''Any''
			
			IF EXISTS( SELECT * FROM dbo.AddDescript1 WHERE A1_Key = @nCode1 )
				SELECT	@sName = A1_Name + 
						(CASE 
							WHEN ( LEN(IsNull(A1_Code, '''')) > 0 ) THEN ('',''+ A1_Code) 
							ELSE ('''') 
						END), 
					@sNameLat = ISNULL(A1_NameLat,A1_Name) + 
						(CASE 
							WHEN ( LEN(IsNull(A1_Code, '''')) > 0 ) THEN ('',''+ A1_Code) 
							ELSE ('''') 
						END)
				FROM dbo.AddDescript1 
				WHERE A1_Key = @nCode1
		END
		ELSE
		BEGIN
			SET @sTitle = ''''
			SET @sTitleLat = ''''
		END
	END


	IF @nCode1 > 0 and ((@nSvKey = @TYPE_HOTEL) or (@nSvKey = @TYPE_HOTELADDSRV))
	BEGIN
		if @sAcCode is not null
			begin
				Set @sName = @sName + '','' + isnull(@sAcCode, '''')
			end
		if @sAcCodeLat is not null
			begin
                Set @sNameLat = @sNameLat + '','' + isnull(@sAcCodeLat, '''')  
             end
                       

		SET @sTmp = isnull(CAST(@nAgeFrom as varchar(5)), ''0'') + ''-'' + isnull(cast(@nAgeTo as varchar(5)), '''')
		-- Task 10655 09.01.2013 kolbeshkin: исправил задвоение размещения, если оно не основное
		If @nHrMain <= 0 and charindex(isnull(@sAcCode, ''''), @sName) = 0
		begin				
			  Set @sName = @sName + '','' + isnull(@sAcCode, '''')
              Set @sNameLat = @sNameLat + '','' + isnull(@sAcCodeLat, '''')
                      
		END
		ELSE IF ((@nAgeFrom > 0) or (@nAgeTo > 0)) and charindex(''('' + @sTmp + '')'', @sName) = 0
			BEGIN
			-- Task 8610 05.10.2012 kolbeshkin: если возраст уже есть в названии размещения, то второй раз не добавляем
				SET @sName =  @sName + '' ('' + @sTmp + '')''
				SET @sNameLat = @sNameLat + '' ('' + @sTmp + '')''				
			END
	END

')
END TRY
BEGIN CATCH
insert into ##errors values ('GetSvCode1Name.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on [dbo].[GetSvCode1Name] to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('GetSvCode1Name.sql', error_message())
END CATCH
end

print '############ end of file GetSvCode1Name.sql ################'

print '############ begin of file GetTourName.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[GetTourName]'') AND type in (N''FN''))
DROP FUNCTION [dbo].[GetTourName]

')
END TRY
BEGIN CATCH
insert into ##errors values ('GetTourName.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

create function [dbo].[GetTourName] (@tourkey int)
RETURNS varchar(200) 
as
begin

if isnull(@tourkey,0) = 0
	return ''Индивидуально''

declare @name varchar (200)

select @name = tl_name from Turlist where TL_KEY = @tourkey

if @name is null
select @name = convert(varchar(200), isnull(TP_XmlSettings.query(N''/TourProgram/TourSettingsViewModel/TourName/text()''),'''')) from TourPrograms where TP_Id = @tourkey

return isnull(@name,'''')
end

')
END TRY
BEGIN CATCH
insert into ##errors values ('GetTourName.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on [dbo].[GetTourName] to public 
')
END TRY
BEGIN CATCH
insert into ##errors values ('GetTourName.sql', error_message())
END CATCH
end

print '############ end of file GetTourName.sql ################'

print '############ begin of file GetUserInfo.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/****** Object:  StoredProcedure [dbo].[GetUserInfo]    Script Date: 05/16/2018 17:02:31 ******/
SET ANSI_NULLS ON
')
END TRY
BEGIN CATCH
insert into ##errors values ('GetUserInfo.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
SET QUOTED_IDENTIFIER OFF
')
END TRY
BEGIN CATCH
insert into ##errors values ('GetUserInfo.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

ALTER  PROCEDURE [dbo].[GetUserInfo]
(
	@sUserID varchar(255) output, 	
	@nUserKey int output,
	@sUserName varchar(50) output,
	@nUserPRKey int output,
	@nUserDepartmentKey int output,
	@sUserNameLat varchar(50) output
)
AS
	declare @sUS_NAME varchar(20)
	declare @sUS_SHORTNAME varchar(4)

	If @sUserID is not null and @sUserID != ''''
		SELECT 	@sUserName = US_FULLNAME,
			@sUserNameLat = US_FULLNAMELAT,
			@nUserPRKey = US_PRKey,
			@nUserDepartmentKey = US_DepartmentKey, 
			@nUserKey = US_Key		
		FROM dbo.UserList
		WHERE  US_USERID = @sUserID 
	Else
		If @nUserKey is not null
			SELECT 	@sUserName = US_FULLNAME,
				@sUserNameLat = US_FULLNAMELAT,
				@nUserPRKey = US_PRKey,
				@nUserDepartmentKey = US_DepartmentKey, 
				@sUserID = US_USERID				
			FROM dbo.UserList
			WHERE  US_Key = @nUserKey

	-- no such user in dbo.UserList (e.g, sa)
	IF (@sUserName IS NULL AND @sUserNameLat IS NULL)
	BEGIN
		SET @sUserName = USER
		SET @sUserNameLat = USER
	END
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('GetUserInfo.sql', error_message())
END CATCH
end

print '############ end of file GetUserInfo.sql ################'

print '############ begin of file getUserListRoles.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[GetUserListRoles]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[GetUserListRoles]

')
END TRY
BEGIN CATCH
insert into ##errors values ('getUserListRoles.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('





CREATE PROCEDURE [dbo].[GetUserListRoles] 



	@userId varchar(30)

AS

BEGIN



	DECLARE @result AS TABLE

	(

		roleName varchar(256)

	)

	

	INSERT INTO @result

		

	SELECT Roles.NAME ROLENAME FROM sys.database_role_members RoleMembers 

		join sys.database_principals Members 

			ON RoleMembers.MEMBER_PRINCIPAL_ID = Members.PRINCIPAL_ID 

		join sys.database_principals Roles ON RoleMembers.ROLE_PRINCIPAL_ID = Roles.PRINCIPAL_ID

			WHERE Members.NAME = @userId

			

	SELECT * FROM @result		



END

')
END TRY
BEGIN CATCH
insert into ##errors values ('getUserListRoles.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



GRANT EXECUTE on [dbo].[GetUserListRoles] TO PUBLIC

')
END TRY
BEGIN CATCH
insert into ##errors values ('getUserListRoles.sql', error_message())
END CATCH
end

print '############ end of file getUserListRoles.sql ################'

print '############ begin of file InsHistory.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/****** Object:  StoredProcedure [dbo].[InsHistory]    Script Date: 05/16/2018 09:56:44 ******/
SET ANSI_NULLS ON
')
END TRY
BEGIN CATCH
insert into ##errors values ('InsHistory.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
SET QUOTED_IDENTIFIER ON
')
END TRY
BEGIN CATCH
insert into ##errors values ('InsHistory.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

--<DATE>2015-04-23</DATE>
--<VERSION>2009.2.21.1</VERSION>
ALTER PROCEDURE [dbo].[InsHistory]
(
	@sDGCod varchar(10),
	@nDGKey int,
	@nOAId int,
	@nTypeCode int,
	@sMod varchar(3),
	@sText varchar(254),
	@sRemark varchar(25),
	@nInvisible int,
	@sDocumentNumber varchar(255),
	@bMessEnabled bit=0,
	@nSVKey int=null,
	@nCode int=null,
	@nHiId int=null output,
	@DLKey int=null
)
AS
	declare @sWho varchar(50)   --CRM-10886-K9G0 20180516 увеличина длина переменной с 25 на 50
	declare @sType varchar(32)
	declare @nHI_USERID int		--MEG00040421 tkachuk 15.03.2011 Id пользователя, внесшего изменения
	
	Set @nHI_USERID = null
	
	EXEC dbo.CurrentUser @sWho output
	EXEC dbo.GetUserKey @nHI_USERID output
	
	select @sType = left(OA_Alias, 32) from ObjectAliases where OA_Id = @nOAId
	
	IF @nDGKey IS NULL AND @sDGCod IS NOT NULL
	BEGIN
		SELECT @nDGKey = DG_KEY 
		FROM dbo.tbl_Dogovor with(nolock)
		WHERE DG_CODE = @sDGCod
	END
	
	INSERT INTO dbo.History (
		HI_DGCOD, HI_DGKEY, HI_OAId, HI_DATE, HI_WHO, 
		HI_TEXT, HI_MOD, HI_REMARK, HI_TYPE, HI_TYPECODE, 
		HI_INVISIBLE, HI_DOCUMENTNAME, HI_MessEnabled, HI_SVKey, HI_Code, HI_USERID, HI_DLKEY)
	VALUES (
		@sDGCod, @nDGKey, @nOAId, GETDATE(), @sWho, 
		@sText, @sMod, @sRemark, @sType, @nTypeCode, 
		@nInvisible, @sDocumentNumber, @bMessEnabled, @nSVKey, @nCode, @nHI_USERID, @DLKey)

		Set @nHiId = SCOPE_IDENTITY()

	RETURN SCOPE_IDENTITY()
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('InsHistory.sql', error_message())
END CATCH
end

print '############ end of file InsHistory.sql ################'

print '############ begin of file MakeFullSVName.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists(select id from sysobjects where xtype=''p'' and name=''MakeFullSVName'')
	drop proc dbo.MakeFullSVName
')
END TRY
BEGIN CATCH
insert into ##errors values ('MakeFullSVName.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE    PROCEDURE [dbo].[MakeFullSVName]
(
--<VERSION>2005.2.41 (2007.2.17)</VERSION>
	@nCountry INT,
	@nCity INT,
	@nSvKey INT,
	@nCode INT,
	@nNDays INT,
	@nCode1 INT,
	@nCode2 INT,
	@nPartner INT,
	@dServDate DATETIME,
	@sServiceByHand VARCHAR(800),	
	@sResult VARCHAR(800) OUTPUT,
	@sResultLat VARCHAR(800) OUTPUT,
	@dTimeBeg DateTime =null OUTPUT,
	@dTimeEnd DateTime =null OUTPUT
) AS
	DECLARE @nTempNumber INT

	DECLARE @sName VARCHAR(800)
	DECLARE @sNameLat VARCHAR(800)
	DECLARE @sText VARCHAR(800)
	DECLARE @sTextLat VARCHAR(800)
	DECLARE @sTempString VARCHAR(800)
	DECLARE @sTempStringLat VARCHAR(800)

	DECLARE @nMain INT
	DECLARE @nAgeFrom INT
	DECLARE @nAgeTo INT

/*
       	DECLARE @n INT
	DECLARE @sSelect VARCHAR(800)
	DECLARE @sTempString2 VARCHAR(800)
	DECLARE @sTempString3 VARCHAR(800)

	DECLARE @nTmp INT
	DECLARE @sTmp VARCHAR(800)
*/
	DECLARE 
	@TYPE_FLIGHT INT, 
	@TYPE_TRANSFER INT,
	@TYPE_HOTEL INT,
	@TYPE_EXCUR INT,
	@TYPE_VISA INT,
	@TYPE_INSUR INT,
	@TYPE_SHIP INT,
	@TYPE_HOTELADDSRV INT,
	@TYPE_SHIPADDSRV INT,
	@TYPE_FLIGHTADDCSOTSSRV INT,
	@TYPE_HOTELADDCOSTSSRV INT,
	@TYPE_BUSTRANSFER INT,
	@bIsCruise INT

	DECLARE @sTextCity VARCHAR(800)
	DECLARE @sTextCityLat VARCHAR(800)
	
	Set @TYPE_FLIGHT = 1
	Set @TYPE_TRANSFER = 2
	Set @TYPE_HOTEL = 3
	Set @TYPE_EXCUR = 4
	Set @TYPE_VISA = 5
	Set @TYPE_INSUR = 6
	Set @TYPE_SHIP = 7
	Set @TYPE_HOTELADDSRV = 8
	Set @TYPE_SHIPADDSRV = 9
	Set @TYPE_FLIGHTADDCSOTSSRV = 12
	Set @TYPE_HOTELADDCOSTSSRV = 13
	Set @TYPE_BUSTRANSFER = 14
	Set @bIsCruise = 0
	Set @dTimeBeg=null
	Set @dTimeEnd=null

	Set @nTempNumber = 1
	EXEC dbo.GetServiceName @nSvKey, @nTempNumber, @sName output, @sNameLat output

	If @sName != ''''
		Set @sName = @sName + ''::''
	If @sNameLat != ''''
		Set @sNameLat = @sNameLat + ''::''

	If @nSvKey = @TYPE_FLIGHT
	BEGIN
		Set @sText = ''  ''
		Set @sTextLat = ''  ''
		If @nCode2>0
			SELECT  @sText = CT_Name,
				@sTextLat = isnull(CT_NameLat, CT_Name)
			FROM	dbo.CityDictionary 
			WHERE	CT_Key = @nCode2
		Set @sName = @sName + @sText + ''/''
		Set @sNameLat = @sNameLat + @sTextLat + ''/''

		Set @sText = ''  ''
		Set @sTextLat = ''  ''
		If @nCity>0
			SELECT 	@sText = CT_Name,
				@sTextLat = isnull(CT_NameLat, CT_Name)
			FROM	dbo.CityDictionary 
			WHERE	CT_Key = @nCity
		Set @sName = @sName + @sText + ''/''
		Set @sNameLat = @sNameLat + @sTextLat + ''/''

		Set @sText = isnull(@sServiceByHand, '''')
		Set @sTextLat = isnull(@sServiceByHand, '''')	

		-- День недели в формате 1 - пон, 7 - вс
		Declare @nday int
		Set @nday = DATEPART(dw, @dServDate)  + @@DATEFIRST - 1
		If @nday > 7 
	    		set @nday = @nday - 7
	
		If @nCode>0
		BEGIN
			SELECT	@sText = isnull(CH_AirLineCode, '''') + CH_Flight + '', '' + isnull(CH_PortCodeFrom, '''') + ''-'' + isnull(CH_PortCodeTo, ''''),
					@sTextLat = isnull(CH_AirLineCode, '''') + CH_Flight + '', '' + isnull(CH_PortCodeFrom, '''') + ''-'' + isnull(CH_PortCodeTo, '''')
			FROM 	dbo.Charter
			WHERE 	CH_Key=@nCode

			SELECT	TOP 1 
					@dTimeBeg=AS_TimeFrom,
					@dTimeEnd=AS_TimeTo
			FROM 	dbo.AirSeason
			WHERE 	AS_CHKey=@nCode 
					and CHARINDEX(CAST(@nday as varchar(1)),AS_Week)>0
					and @dServDate between AS_DateFrom and AS_DateTo
			ORDER BY AS_TimeFrom DESC
			IF @dTimeBeg is not null and @dTimeEnd is not null
			BEGIN
				Set @sText=@sText+'', ''+LEFT(CONVERT(varchar, @dTimeBeg, 8),5) + ''-'' + LEFT(CONVERT(varchar, @dTimeEnd, 8),5)
				Set @sTextLat=@sTextLat+'', ''+LEFT(CONVERT(varchar, @dTimeBeg, 8),5) + ''-'' + LEFT(CONVERT(varchar, @dTimeEnd, 8),5)
			END
		END
		
		Set @sName = @sName + @sText + ''/''
		Set @sNameLat = @sNameLat + @sTextLat + ''/''

		Set @sText = ''  ''
		Set @sTextLat = ''  ''
		If @nCode1>0
			SELECT	@sText = isnull(AS_Code, '''') + '' '' + isnull(AS_NameRus, ''''),
				@sTextLat = isnull(AS_Code, '''') + '' '' + isnull(AS_NameLat, AS_NameRus)
			FROM 	dbo.AirService 
			WHERE 	AS_Key = @nCode1
		Set @sName = @sName + @sText 
		Set @sNameLat = @sNameLat + @sTextLat 
	END
	ELSE If (@nSvKey = @TYPE_HOTEL or @nSvKey = @TYPE_HOTELADDSRV)
	BEGIN
		Set @sText = ''  ''
		Set @sTextLat = ''  ''
		If @nCity>0
			SELECT 	@sTextCity = CT_Name,
				@sTextCityLat = isnull(CT_NameLat, CT_Name)
			FROM	dbo.CityDictionary 
			WHERE	CT_Key = @nCity		      

		Set @sText = isnull(@sServiceByHand, '''')
		
		Set @sTextCity = ISNULL(@sTextCity,'''')
		Set @sTextCityLat = ISNULL(@sTextCityLat,'''')

		If @nCode>0
		      	SELECT	@sText = isnull(HD_Name,'''') + ''-'' + isnull(HD_Stars, ''''), @bIsCruise = HD_IsCruise 
			FROM 	dbo.HotelDictionary 
			WHERE	HD_Key = @nCode
		Set @sTextLat = @sText
		If @bIsCruise = 1
			If @nSvKey = @TYPE_HOTEL
			BEGIN
				Set @sName = ''Круиз::''
				Set @sNameLat = ''Cruise::''
			END
			Else If @nSvKey = @TYPE_HOTELADDSRV
				Set @sName = ''ADCruise::''

		Set @sName = @sName + @sTextCity + ''/''  + @sText
		Set @sNameLat = @sNameLat + @sTextCityLat + ''/'' + @sTextLat

		If @nNDays>0
		BEGIN
			Set @nTempNumber = 0
			EXEC dbo.SetNightString @nNDays, @nTempNumber, @sTempString output, @sTempStringLat output
			Set @sName = @sName + '','' + isnull(cast(@nNDays as varchar (4)), '''') + '' '' + @sTempString
			Set @sNameLat = @sNameLat + '','' + isnull(cast(@nNDays as varchar (4)), '''') + '' '' + @sTempStringLat
		END
		Set @sName = @sName + ''/''
		Set @sNameLat = @sNameLat + ''/''

		Set @sText = ''  ''
		Set @sTextLat = ''  ''

/*
		SELECT  @sText = RM_Name + '','' + RC_Name + '','' + isnull(AC_Code, ''''), 
			@sTextLat = isnull(RM_NameLat,RM_Name) + '','' + isnull(RC_NameLat,RC_Name) + '','' + isnull(AC_Code, ''''),
			@nMain = AC_Main, 
			@nAgeFrom = AC_AgeFrom, 
			@nAgeTo = AC_AgeTo 
		FROM 	dbo.HotelRooms,dbo.Rooms,dbo.RoomsCategory,dbo.AccmdMenType 
		WHERE	HR_Key = @nCode1 and RM_Key = HR_RmKey and RC_Key = HR_RcKey and AC_Key = HR_AcKey
				
		If @nMain > 0
		BEGIN
			Set @sText = @sText + '',Осн''
			Set @sTextLat = @sTextLat + '',Main''
		END
		ELSE
		BEGIN
			Set @sText = @sText + '',доп.''
			Set @sTextLat = @sTextLat + '',ex.b''
			If @nAgeFrom >= 0
			BEGIN
	       	        	     Set @sTempString = ''('' + isnull(cast(@nAgeFrom as varchar (10)), '''')  + ''-'' +  isnull(cast(@nAgeTo as varchar(10)), '''')  + '')''
       			             Set @sText = @sText + @sTempString
       			             Set @sTextLat = @sTextLat + @sTempString
			END
		END
*/

	      	EXEC dbo.GetSvCode1Name @nSvKey, @nCode1, @sText output, @sTempString output, @sTextLat output, @sTempStringLat output
       		Set @sName = @sName + isnull(@sTempString, '''') + ''/''
		Set @sNameLat = @sNameLat + isnull(@sTempStringLat, '''') + ''/''

		Set @sText = ''  ''
              	EXEC dbo.GetSvCode2Name @nSvKey, @nCode2, @sTempString output, @sTempStringLat output
             
             	Set @sName = @sName + isnull(@sTempString, '''')
		Set @sNameLat = @sNameLat + isnull(@sTempStringLat, '''') 
	END
	ELSE If (@nSvKey = @TYPE_EXCUR or @nSvKey = @TYPE_TRANSFER)
	BEGIN
		Set @sText = ''  ''
		Set @sTextLat = ''  ''
		If @nCity>0
			SELECT 	@sText = CT_Name,
				@sTextLat = isnull(CT_NameLat, CT_Name)
			FROM	dbo.CityDictionary 
			WHERE	CT_Key = @nCity	
		Set @sName = @sName + @sText + ''/''
		Set @sNameLat = @sNameLat + @sTextLat + ''/''

		Set @sText = isnull(@sServiceByHand, '''')
		Set @sTextLat = isnull(@sServiceByHand, '''')
		If @nCode>0
			If @nSvKey = @TYPE_EXCUR
				SELECT 	@sText = ED_Name +'', '' + isnull(ED_Time, ''''),
					@sTextLat = isnull(ED_NameLat,ED_Name) +'', '' + isnull(ED_Time, '''')
				FROM	dbo.ExcurDictionary 
				WHERE	ED_Key = @nCode
			ELSE
				SELECT 	@sText = TF_Name + '', '' + isnull (Left (Convert (varchar, TF_TimeBeg, 8), 5), '''')  + '', '' + isnull(TF_TIME, ''''),
					@sTextLat = isnull(TF_NameLat,TF_Name) + '', '' + isnull (Left (Convert (varchar, TF_TimeBeg, 8), 5), '''')  + '', '' + isnull(TF_TIME, '''')  
				FROM	dbo.Transfer 
				WHERE	TF_Key = @nCode
		Set @sName = @sName + @sText +  ''/''
		Set @sNameLat = @sNameLat + @sTextLat + ''/''

		Set @sText = ''  ''
		Set @sTextLat = ''  ''
		If @nCode1>0
			SELECT 	@sText = TR_Name + (case  when (TR_NMen>0)  then ('',''+ CAST ( TR_NMen  AS VARCHAR(10) )+ '' чел.'')  else '' '' end),
				@sTextLat = isnull(TR_NameLat,TR_Name) + (case  when (TR_NMen>0)  then ('',''+ CAST ( TR_NMen  AS VARCHAR(10) )+ '' pax.'')  else '' '' end) 
			FROM	dbo.Transport  
			WHERE	TR_Key = @nCode1
		Set @sName = @sName + @sText
		Set @sNameLat = @sNameLat + @sTextLat 
	END
	ELSE If (@nSvKey = @TYPE_SHIP or @nSvKey = @TYPE_SHIPADDSRV)
	BEGIN
		Set @sText = ''  ''
		Set @sTextLat = ''  ''
		If @nCountry>0
	                        SELECT	@sText = CN_Name,
					@sTextLat = isnull(CN_NameLat, CN_Name)
				FROM	Country 
				WHERE	CN_Key = @nCountry
		Set @sName = @sName + @sText + ''/''
		Set @sNameLat = @sNameLat + @sTextLat + ''/''
		
		Set @sText = isnull(@sServiceByHand, '''')
		If @nCode>0
		      	SELECT	@sText = SH_Name + ''-'' + isnull(SH_Stars, '''') 
			FROM	dbo.Ship 
			WHERE	SH_Key = @nCode
		Set @sTextLat = @sText
				
		Set @sName = @sName + @sText
		Set @sNameLat = @sNameLat + @sTextLat
		
		If @nNDays>0
		BEGIN
			Set @sName = @sName + '','' + isnull(cast(@nNDays as varchar (10)), '''') + '' '' + ''дней''
			Set @sNameLat = @sNameLat + '','' + isnull(cast(@nNDays as varchar (10)), '''') + '' '' + ''days''
		END					
		Set @sName = @sName + ''/''
		Set @sNameLat = @sNameLat + ''/''

		Set @sText = ''  ''
		Set @sTextLat = ''  ''
		
	      	EXEC dbo.GetSvCode1Name @nSvKey, @nCode1, @sText output, @sTempString output, @sTextLat output, @sTempStringLat output
		Set @sName = @sName + isnull(@sTempString, '''') + ''/''
		Set @sNameLat = @sNameLat + isnull(@sTempStringLat, '''') + ''/''

		Set @sText = ''  ''
              	EXEC dbo.GetSvCode2Name @nSvKey, @nCode2, @sTempString output, @sTempStringLat output
		
		Set @sName = @sName + isnull(@sTempString, '''')
		Set @sNameLat = @sNameLat + isnull(@sTempStringLat, '''') 
	END
	ELSE If @nSvKey = @TYPE_BUSTRANSFER
	BEGIN
		Set @sText = ''  ''
		Set @sTextLat = ''  ''
		If @nCode1>0
			SELECT  @sText = CT_Name,
				@sTextLat = isnull(CT_NameLat, CT_Name)
			FROM	dbo.CityDictionary 
			WHERE	CT_Key = @nCode1
		Set @sName = @sName + @sText + ''/''
		Set @sNameLat = @sNameLat + @sTextLat + ''/''	

		Set @sText = ''  ''
		Set @sTextLat = ''  ''
		If @nCity>0
			SELECT 	@sText = CT_Name,
				@sTextLat = isnull(CT_NameLat, CT_Name)
			FROM	dbo.CityDictionary 
			WHERE	CT_Key = @nCity
		Set @sName = @sName + @sText + ''/''
		Set @sNameLat = @sNameLat + @sTextLat + ''/''

		Set @sText = isnull(@sServiceByHand, '''')
		Set @sTextLat = isnull(@sServiceByHand, '''')	

		If @nCode>0
		BEGIN							
			DECLARE @days smallint, @dayTo smallint, @btName varchar(800), @btTimeFrom datetime, @btTimeTo datetime, @bpTimeFrom datetime, @bpTimeTo datetime, @cityFrom int
			SELECT @btName = BT_NAME, @btTimeFrom = BT_TIMEFROM, @btTimeTo = BT_TIMETO, @cityFrom = BT_CTKEYFROM,
					@bpTimeFrom = BP_TIMEFROM, @bpTimeTo = BP_TIMETO, @days = BT_DAYS, @dayTo = BP_DAYTO
			FROM 	dbo.BusTransferPoints JOIN dbo.BusTransfers ON BP_BTKEY = BT_KEY
			WHERE 	BP_KEY = @nCode 			
			
			if (@bpTimeTo is not null and @btTimeTo is not null and @nCode1 != @cityFrom)
				SELECT @sText = isnull(@btName, '''') + '','' + isnull (Left (Convert (varchar, @bpTimeTo, 8), 5), '''') + ''-'' + isnull (Left (Convert (varchar, @btTimeTo, 8), 5), '''')
			else if (@btTimeFrom is not null and @btTimeTo is not null)
				SELECT @sText = isnull(@btName, '''') + '','' + isnull (Left (Convert (varchar, @btTimeFrom, 8), 5), '''') + ''-'' + isnull (Left (Convert (varchar, @btTimeTo, 8), 5), '''')
			else
				SELECT @sText = isnull(@btName, '''')
				
			if @days is NOT NULL
			BEGIN	
				if @nCode1 = @cityFrom
					SET @days = @days
				ELSE if @dayTo is not NULL
					SET @days = @days - @dayTo + 1			
				
				if (@days = 1)
					SET @sText = @sText + '','' + cast(@days as varchar (10)) + '' день'' 
				else
					SET @sText = @sText + '','' + cast(@days as varchar (10)) + '' дня'' 
			END		
				
			Set @sTextLat = @sText;	
		END
		
		Set @sName = @sName + @sText + ''/''
		Set @sNameLat = @sNameLat + @sTextLat + ''/''	
		
		Set @sText = ''  ''
		Set @sTextLat = ''  ''
		If @nCode2>0
			SELECT 	@sText = TR_Name + (case  when (TR_NMen>0)  then (CAST ( TR_NMen  AS VARCHAR(10) )+ '' чел.'')  else '' '' end),
				@sTextLat = isnull(TR_NameLat,TR_Name) + (case  when (TR_NMen>0)  then (CAST ( TR_NMen  AS VARCHAR(10) )+ '' pax.'')  else '' '' end) 
			FROM	dbo.Transport  
			WHERE 	TR_KEY = @nCode2
		Set @sName = @sName + @sText 
		Set @sNameLat = @sNameLat + @sTextLat 
	END
	ELSE
	BEGIN
		Set @sText = ''  ''
		Set @sTextLat = ''  ''
		Set @sTempString = ''CITY''
		EXEC dbo.GetSvListParm @nSvKey, @sTempString, @nTempNumber output
		
		If @nTempNumber>0
		BEGIN
			If @nCity>0
				SELECT 	@sText = CT_Name,
					@sTextLat = isnull(CT_NameLat, CT_Name)
				FROM	dbo.CityDictionary 
				WHERE	CT_Key = @nCity	
			Set @sName = @sName + @sText + ''/''
			Set @sNameLat = @sNameLat + @sTextLat + ''/''
		END
		ELSE
		BEGIN
			If @nCountry>0
	                        SELECT	@sText = CN_Name,
					@sTextLat = isnull(CN_NameLat, CN_Name)
				FROM	Country 
				WHERE	CN_Key = @nCountry
			Else If @nCode>0
	             	        SELECT	@sText = CN_Name,
					@sTextLat = isnull(CN_NameLat, CN_Name)
				FROM	dbo.ServiceList, Country 
				WHERE	SL_Key = @nCode and CN_Key = SL_CnKey
			Set @sName = @sName + @sText + ''/''
			Set @sNameLat = @sNameLat + @sTextLat + ''/''
		END
		Set @sText = @sServiceByHand
		Set @sTextLat = @sServiceByHand
		If @nCode>0
		BEGIN
/*
			if @nSvKey = @TYPE_HOTELADDSRV
			BEGIN
				SELECT	@sText = HD_Name + ''-'' + isnull(HD_Stars, '''') 
				FROM	dbo.HotelDictionary 
				WHERE	HD_Key = @nCode
				Set @sTextLat = @sText
			END
			ELSE if @nSvKey = @TYPE_SHIPADDSRV
			BEGIN
				SELECT	@sText = SH_Name + ''-'' + isnull(SH_Stars, '''') 
				FROM	dbo.Ship
				WHERE	SH_Key = @nCode
				Set @sTextLat = @sText
			END
			ELSE 
*/
		    	SELECT	@sText = SL_Name,
				@sTextLat = isnull(SL_NameLat, SL_Name)
			FROM	dbo.ServiceList
			WHERE	SL_Key = @nCode
		END
		Set @sName = @sName + @sText
		Set @sNameLat = @sNameLat + @sTextLat

		If @nNDays>0
		BEGIN
			Set @nTempNumber = 1
			exec SetNightString @nNDays, @nTempNumber, @sTempString output, @sTempStringLat output
			Set @sName = @sName + '','' + isnull(cast(@nNDays as varchar (10)), '''')  + '' '' + @sTempString
			Set @sNameLat = @sNameLat + '','' + isnull(cast(@nNDays as varchar (10)), '''')  + '' '' + @sTempStringLat
		END
		Set @sName = @sName + ''/''
		Set @sNameLat = @sNameLat + ''/''

		Set @sText = ''  ''
		Set @sTextLat = ''  ''
		Set @sTempString = ''CODE1''
		exec dbo.GetSvListParm @nSvKey, @sTempString, @nTempNumber output

		If @nTempNumber>0
		BEGIN
			If @nCode1>0 and not (@nSvKey = @TYPE_HOTELADDSRV 
			or @nSvKey = @TYPE_SHIPADDSRV 
			or @nSvKey = @TYPE_FLIGHTADDCSOTSSRV 
			or @nSvKey = @TYPE_HOTELADDCOSTSSRV)
			BEGIN
				
				SELECT	@sText = A1_Name,
					@sTextLat = isnull(A1_NameLat, A1_Name)
				FROM	dbo.AddDescript1
				WHERE	A1_Key = @nCode1
				END
					
			ELSE
			BEGIN
				
				EXEC dbo.GetSvCode1Name @nSvKey, @nCode1, @sText output, @sTempString output, @sTextLat output, @sTempStringLat output
				set @sText = @sTempString
				set @sTextLat = @sTempStringLat		
						
			END
	
			Set @sName = @sName + @sText + ''/''
			Set @sNameLat = @sNameLat + @sTextLat + ''/''
			Set @sTempString = ''CODE2''
			exec dbo.GetSvListParm @nSvKey, @sTempString, @nTempNumber output

			If @nTempNumber>0
			BEGIN
				If @nCode2>0
				SELECT	@sText = A2_Name,
					@sTextLat = isnull(A2_NameLat, A2_Name)
				FROM	dbo.AddDescript2
				WHERE	A2_Key = @nCode2
				Set @sName = @sName + @sText 
				Set @sNameLat = @sNameLat + @sTextLat 
			END
		END
	END
	Set @sResult = @sName
	Set @sResultLat = @sNameLat


')
END TRY
BEGIN CATCH
insert into ##errors values ('MakeFullSVName.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on [dbo].[MakeFullSVName] to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('MakeFullSVName.sql', error_message())
END CATCH
end

print '############ end of file MakeFullSVName.sql ################'

print '############ begin of file MakePutName.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists(select top 1 1 from sys.objects where name = ''MakePutName'' and type = ''P'')
	drop procedure MakePutName
')
END TRY
BEGIN CATCH
insert into ##errors values ('MakePutName.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

create procedure [dbo].[MakePutName]
@date datetime, 
@countryKey int, 
@cityKey int, 
@tourKey int, 
@partnerKey int, 
@sFormat0 varchar(10),
@name varchar(10) output
as
--<VERSION>2009.2.17.1</VERSION>
--<DATE>2012-05-12</DATE>
-- 1. Добавил усечение пробелов 

SET CONCAT_NULL_YIELDS_NULL OFF 
	set @name = ''''
	declare @nullDate datetime
	set @nullDate = ''1899-12-30''

	declare @notAllowedSymbols varchar(100)
	select @notAllowedSymbols = Upper(SS_ParmValue) from SystemSettings where SS_ParmName = ''SYSDogovorNumberDigits''

	declare @firstDigit char(1)
	set @firstDigit = dbo.NextDigit(@notAllowedSymbols, ASCII(''0''))

	declare @selectDate datetime
	set @selectDate = DATEADD(day, -180, GETDATE())
	
	declare @format varchar(50), @constFormat varchar(50)
	select @format = REPLACE(ST_FormatDogovor, '' '', ''('') from Setting
	set @constFormat = @format
	
	declare @curPos int
	set @curPos = 1

	set @format = @format

	declare @chPrev varchar(1)
	set @chPrev = substring(@format, 1, 1)
	set @format = substring(@format, 2, len(@format) - 1)

	declare @number_part_length int
	set @number_part_length = 0
	declare @number_part_start_point int
	set @number_part_start_point = -1
	declare @len int
	set @len = 1
	
	declare @temp varchar(50), @ch varchar(1), @str varchar(50)		
	set @ch = substring(@format, 1, 1)
	
	while @ch != ''''
	begin
		set @str = ''''
		set @ch = substring(@format, 1, 1)
		
		if @format != ''''
			set @format = substring(@format, 2, len(@format) - 1)
		
		set @temp = @temp + @chPrev

		--if (@ch != @chPrev or @format = '''') and (LEN(@ch) > 0 or (@chPrev = ''9'' or @chPrev = ''#''))
		if (@ch != @chPrev)
		begin
			if @format = '''' and (@ch = @chPrev) --and (@ch != ''9'' and @ch != ''#'')
				set @len = LEN(@temp) + 1
			else
				set @len = LEN(@temp)
			
			if @chPrev = ''N''
			begin
				select @str = UPPER(LEFT(LTRIM(TS_Name), @len)) from dbo.ToursSearch where TS_Id = @tourKey -- 1. 
				exec dbo.FillString @str output, @len, ''n''
			end 
			else if @chPrev = ''T''
			begin
				select @str = UPPER(isnull(LEFT(LTRIM(CT_Code), @len), '''')) from CityDictionary where CT_Key = @cityKey -- 1.
				exec dbo.FillString @str output, @len, ''t''				
			end
			else if @chPrev = ''C''
			begin
				select @str = UPPER(isnull(LEFT(LTRIM(CN_Code), @len),isnull(LEFT(LTRIM(CN_NameLat), @len), ''''))) from Country where CN_Key = @countryKey -- 1.
				exec dbo.FillString @str output, @len, ''c''
			end
			else if @chPrev = ''P''
			begin
				select @str = UPPER(isnull(LEFT(LTRIM(PR_Cod), @len),'''')) from Partners where PR_Key = @partnerKey -- 1.
				exec dbo.FillString @str output, @len, ''p''
			end
			else if @chPrev = ''Y''
				set @str = RIGHT(STR(YEAR(@date)), @len)
			else if @chPrev = ''D''
			begin
				set @temp = LTRIM(STR(DATEPART(dd, @date)))
				if LEN(@temp) < 2
					set @temp = ''0'' + @temp
				set @str = @temp
			end
			else if @chPrev = ''M''
			begin
				set @temp = LTRIM(STR(DATEPART(mm, @date)))
				if LEN(@temp) < 2
					set @temp = ''0'' + @temp
				set @str = @temp	
			end
			else if @chPrev = ''(''
			begin
				set @str = '' ''
			end
			if (@chPrev = ''9'' or @chPrev = ''#'') 
			begin
				if(@chPrev = ''9'')
					set @temp = REPLICATE(''[0-9]'', @len)
				else
					set @temp = REPLICATE(''_'', @len)
				declare @searchName varchar(50)
				
				set @searchName = @name + @temp + ''%''
				select @str = max(DG_Code) from tbl_Dogovor where LEN(DG_Code) = LEN(@constFormat) and upper(DG_Code) like upper(@searchName) and ((DG_TurDate >= @selectDate) or (DG_TurDate is null) or (DG_TurDate = @nullDate))
				
				if @str is null
					set @str = ''''
				if @str != ''''
				begin
					set @str = substring(@str, LEN(@name) + 1, @len)
				end
				
				--set @number_part_length = @number_part_length + 1
				set @number_part_length = @len
				
				if (@number_part_start_point < 0)
					set @number_part_start_point = LEN(@name) + 1

				if @chPrev = ''9''
				begin
					if dbo.IsStrNumber(LTRIM(RTRIM(@str))) > 0
					begin
						set @str = dbo.NextNumber(@notAllowedSymbols, LTRIM(STR(CAST(@str as bigint) + 1)))
						exec dbo.FillString @str output, @number_part_length, @firstDigit
					end
					else
					begin
						set @str = dbo.NextNumber(@notAllowedSymbols, ''1'')
						exec dbo.FillString @str output, @number_part_length, @firstDigit
					end
				end
				else
				begin					
					set @str = Upper(dbo.NextStr(@str, @len))
				end
				-- чтобы номер не увеличивался сверх длины шаблона, когда заканчиваются числа для нумерации
				set @str = substring(@str, 1, @len)
			end
			set @temp = ''''
		end
		
 		set @name = @name + @str
		set @chPrev = @ch
		--select @name
	end

	set @name = Upper(@name)
	declare @int int
	set @int = 0
	while exists(select DG_Code from tbl_Dogovor where DG_Code = @name) and @int < 1005
	begin
		if @chPrev = ''9''
		begin
			set @str = substring(@name, @number_part_start_point, @number_part_length)
			set @str = RIGHT(dbo.NextNumber(@notAllowedSymbols, LTRIM(STR(CAST(@str as bigint) + 1))),@number_part_length)
			exec dbo.FillString @str output, @number_part_length, @firstDigit
			--set @name = LEFT(@name, @number_part_start_point - 1) + @str + RIGHT(@name, 10 - @number_part_start_point - @number_part_length + 1)
			set @name = LEFT(@name, @number_part_start_point - 1) + @str
		end
		else
		begin
			set @str = substring(@name, @number_part_start_point, @number_part_length)
			set @str = Upper(dbo.NextStr(@str, @number_part_length))
			set @name = LEFT(@name, @number_part_start_point - 1) + @str
		end
		set @int = @int + 1
		--print @name
	end
	SET CONCAT_NULL_YIELDS_NULL ON 

')
END TRY
BEGIN CATCH
insert into ##errors values ('MakePutName.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on [dbo].[MakePutName] to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('MakePutName.sql', error_message())
END CATCH
end

print '############ end of file MakePutName.sql ################'

print '############ begin of file mwGetServiceVariants.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists(select id from sysobjects where xtype=''p'' and name=''mwGetServiceVariants'')
	drop proc dbo.mwGetServiceVariants
')
END TRY
BEGIN CATCH
insert into ##errors values ('mwGetServiceVariants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

--<VERSION>9.2.19</VERSION>
--<DATE>2013-03-20</DATE>

create procedure [dbo].[mwGetServiceVariants]
	@serviceDays int,
	@svKey	int,
	@pkKey int,
	@dateBegin varchar(10),
	@tourNDays smallint,
	@cityFromKey	int,
	@cityToKey	int,
	@additionalFilter varchar(1024),
	@tourKey int,
	@showCalculatedCostsOnly int
as
begin
	
	if (isnull(@serviceDays, 0)<=0 and @svKey != 3 and @svKey != 8)
		Set @serviceDays = 1
		
	-- 7693 neupokoev 29.08.2012
	-- Заточка под ДЦ
	declare @selectClause varchar(300)
	declare @fromClause varchar(300)
	declare @whereClause varchar(6000)
	declare @isNewReCalculatePrice bit

	-- Проверка на режим динамического ценообразования
	set @isNewReCalculatePrice = 0
	if (exists( select top 1 1 from SystemSettings with(nolock) where SS_ParmName = ''NewReCalculatePrice'' and SS_ParmValue = 1))
		set @isNewReCalculatePrice = 1
	
	if (@isNewReCalculatePrice = 0)
	begin
		-- CRM04241L4F2 20.03.2012 kolbeshkin сделал distinct по CS_ID, т.к. были случаи дублирования одних и тех же записей в результирующем наборе
		set	@selectClause = '' SELECT CS_Code, CS_SubCode1, CS_SubCode2, CS_PrKey, CS_PkKey, CS_Profit, CS_Type, CS_Discount, CS_Creator, CS_Rate, CS_Cost 
		from costs
		where CS_ID in (select distinct cs1.cs_id ''
		set	@fromClause   = '' FROM COSTS cs1 WITH(NOLOCK) ''
		set	@whereClause  = ''''
	end
	else
	begin 
		set	@selectClause = '' SELECT cs1.CS_Code, cs1.CS_SubCode1, cs1.CS_SubCode2, cs1.CS_PrKey, cs1.CS_PkKey, cs1.CS_Profit, cs1.CS_Type, cs1.CS_Discount, cs1.CS_Creator, cs1.CS_Rate, cs1.CS_Cost, CO_DateActive ''
		set	@fromClause   = '' FROM COSTS cs1 WITH(NOLOCK) INNER JOIN COSTOFFERS WITH(NOLOCK) ON cs1.CS_Coid = CO_Id INNER JOIN Seasons WITH(NOLOCK) ON CO_SeasonId = SN_Id''
		set	@whereClause  = '' CO_State = 3 AND GETDATE() BETWEEN ISNULL(CO_SaleDateBeg, ''''1900-01-01'''') AND ISNULL(CO_SaleDateEnd, ''''2050-01-01'''') AND ISNULL(SN_IsActive, 0) = 1 AND ''
	end
	
	set		@additionalFilter = replace(@additionalFilter, ''CS_'', ''cs1.CS_'')
		
	declare @orderClause varchar(100)
		set @orderClause  = ''CS_long''
	
	--MEG00027493 Paul G 15.07.2010
	if (@showCalculatedCostsOnly = 1)
	begin
		set @whereClause = @whereClause +
			''EXISTS(SELECT 1 FROM TP_SERVICES WITH(NOLOCK) WHERE TS_CODE=cs1.CS_CODE 
				AND TS_SVKEY=cs1.CS_SVKEY 
				AND TS_SUBCODE1=cs1.CS_SUBCODE1 
				AND TS_SUBCODE2=cs1.CS_SUBCODE2 
				AND TS_OPPARTNERKEY=cs1.CS_PRKEY
				AND TS_OPPACKETKEY=cs1.CS_PKKEY
				AND TS_TOKEY=(SELECT TO_KEY FROM TP_TOURS WITH(NOLOCK) WHERE TO_TRKEY=''+ convert(varchar(50), @tourKey) +'')) AND 
			''
	end
	
	set @whereClause = @whereClause + '' cs1.CS_SVKEY = '' + cast(@svKey as varchar)
	set @whereClause = @whereClause + '' AND cs1.CS_PKKEY = '' + cast(@pkKey as varchar)
	
	-- 8233 tfs neupokoev 
	-- При подборе вариантов не учитывались даты начала и окончания продаж
	if (@isNewReCalculatePrice = 0)
		set @whereClause = @whereClause + '' AND '' + ''GETDATE()'' + '' BETWEEN ISNULL(cs1.CS_DATESELLBEG, ''''1900-01-01'''') AND ISNULL(cs1.CS_DATESELLEND, ''''9000-01-01'''') ''
	
	set @whereClause = @whereClause + '' AND '''''' + @dateBegin + '''''' BETWEEN ISNULL(cs1.CS_CHECKINDATEBEG, ''''1900-01-01'''') AND ISNULL(cs1.CS_CHECKINDATEEND, ''''9000-01-01'''') '' + @additionalFilter
	
	if (@svKey=1)
	begin			
		set @whereClause = @whereClause + '' AND '' + cast(@tourNDays as varchar) + '' between isnull(cs1.CS_longmin, -1) and isnull(cs1.CS_LONG, 10000) ''-- MEG00029229 Paul G 13.10.2010
				
		set @whereClause = @whereClause + '' AND EXISTS (SELECT CH_KEY FROM CHARTER WITH(NOLOCK)'' 
										+ '' WHERE CH_KEY = cs1.CS_CODE AND CH_CITYKEYFROM = '' + cast(@cityFromKey as varchar) + '' AND CH_CITYKEYTO = '' + cast(@cityToKey as varchar)+'')''
		-- Filter on day of week
		set @whereClause = @whereClause + '' AND (cs1.CS_WEEK is null or cs1.CS_WEEK = '''''''' or cs1.CS_WEEK like dbo.GetWeekDays('''''' + @dateBegin + '''''','''''' + @dateBegin + ''''''))''
		-- Filter on CHECKIN DATE		
	end
	else 
	begin
		if (@serviceDays > 1)
		begin			
			-- Спорный момент, но иначе не работает вариант, когда изначально берется цена с cs_long < @serviceDays, а потом добивается другими квотами с конца
			--set @whereClause = @whereClause + '' AND '' + cast(@serviceDays as varchar) + '' between isnull(cs1.CS_longmin, -1) and isnull(cs1.CS_long, 10000)''
			set @whereClause = @whereClause + '' AND '' + cast(@serviceDays as varchar) + '' >= isnull(cs1.CS_longmin, -1)''
			
			-- Exclude services that not have cost at last service day
			set @fromClause = @fromClause + '' INNER JOIN COSTS cs2 WITH(NOLOCK) ON cs1.CS_CODE = cs2.CS_CODE AND cs1.CS_SUBCODE1 = cs2.CS_SUBCODE1 AND cs1.CS_SUBCODE2 = cs2.CS_SUBCODE2''
			set @whereClause = @whereClause + '' AND '' + replace(@whereClause, ''cs1.'', ''cs2.'')
			set @whereClause = @whereClause + '' AND ISNULL(cs2.CS_DATE,    ''''1900-01-01'''') <= '''''' + cast(dateadd(day, @serviceDays - 1, cast(@dateBegin as datetime)) as varchar) + ''''''''
			set @whereClause = @whereClause + '' AND ISNULL(cs2.CS_DATEEND, ''''9000-01-01'''') >= '''''' + cast(DATEADD(day, @serviceDays - 1, cast(@dateBegin as datetime)) as varchar) + ''''''''
						
			if (len(@orderClause) > 0)
				set @orderClause = @orderClause + '', ''
			set @orderClause = @orderClause + ''CS_UPDDATE DESC''
		end
		else
		begin				
			set @whereClause = @whereClause + '' AND '' + cast(@serviceDays as varchar) + '' between isnull(cs1.CS_longmin, -1) and isnull(cs1.CS_long, 10000)''
		end
		-- 7443 tfs neupokoev 22.08.2012
		-- Фильтруем цены по дням неделии у других услуг тоже
	set @whereClause = @whereClause + '' AND (cs1.CS_WEEK is null or cs1.CS_WEEK = '''''''' or cs1.CS_WEEK like dbo.GetWeekDays('''''' + @dateBegin + '''''','''''' + @dateBegin + ''''''))''	
	end	
	
	set @whereClause = @whereClause + '' AND ISNULL(cs1.CS_DATE,    ''''1900-01-01'''') <= '''''' + @dateBegin + ''''''''
	set @whereClause = @whereClause + '' AND ISNULL(cs1.CS_DATEEND, ''''9000-01-01'''') >= '''''' + @dateBegin + ''''''''

	-- neupokoev 29.08.2012
	-- Заточка под ДЦ
	if (@isNewReCalculatePrice = 0)
		begin
			exec (@selectClause + @fromClause + '' WHERE '' + @whereClause + '') ORDER BY ''+ @orderClause)
		end
	else
		begin
			exec (''WITH SERVICEINFO AS ('' + 
					@selectClause + @fromClause + '' WHERE '' + @whereClause +
					'') 
					SELECT * FROM SERVICEINFO AS si1
						WHERE si1.CO_DateActive = 
							(
								SELECT MAX(si2.CO_DateActive) 
								FROM SERVICEINFO AS si2 
								WHERE si1.CS_Code = si2.CS_Code and si1.CS_SubCode1 = si2.CS_SubCode1 and 
								      si1.CS_SubCode2 = si2.cs_SubCode2 and si1.CS_PRKey = si2.CS_PRKey
							)'')
		end	
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('mwGetServiceVariants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant exec on dbo.mwGetServiceVariants to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('mwGetServiceVariants.sql', error_message())
END CATCH
end

print '############ end of file mwGetServiceVariants.sql ################'

print '############ begin of file NationalCurrencyPrice2.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists(select id from sysobjects where id = object_id(N''[dbo].[NationalCurrencyPrice2]'') and OBJECTPROPERTY(id, N''IsProcedure'') = 1)
	drop proc [dbo].[NationalCurrencyPrice2]
')
END TRY
BEGIN CATCH
insert into ##errors values ('NationalCurrencyPrice2.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE PROCEDURE [dbo].[NationalCurrencyPrice2]
@sRate varchar(5), -- валюта пересчета
@sRateOld varchar(5), -- старая валюта
@sDogovor varchar(100), -- код договора
@nPrice money, -- новая цена в указанной валюте
@nPriceOld money, -- старая цена
@nDiscountSum money, -- новая скидка в указанной валюте
@date DateTime, -- действие
@order_status smallint, -- null OR passing the new value for dg_sor_code from the trigger when it''s (dg_sor_code) updated
@isAddToHistory bit = 1
AS
BEGIN
	--<VERSION>9.2.20.0</VERSION>
	--<DATE>2013-06-17</DATE>

	declare @national_currency varchar(5)
    declare @currencyKey int	
    declare @rc_courseStr char(30)
	declare @dogovor_key int -- Task 10558 tfs neupokoev 26.12.2012: будем писать в историю и его тоже, чтобы потом не зморачиваться, а вдргуг сменили имя путевки
	declare @nHIID int
	declare @dateAsString varchar(10)
	declare @course decimal(19,9)
	
	set @dateAsString = CONVERT(char(10), @date, 104)

	select top 1 @currencyKey = RA_KEY, @national_currency = RA_CODE from Rates where RA_National = 1
	select @dogovor_key = dg_key from Dogovor where DG_CODE=@sDogovor

	IF @sRate = @national_currency
    BEGIN
        SET @rc_courseStr = ''1''
        SET @course = 1
    END   
	ELSE
		BEGIN
			SELECT TOP 1 @course = RC_COURSE FROM RealCourses
						WHERE RC_RCOD1 = @sRate AND RC_RCOD2 = @national_currency
							AND CONVERT(CHAR(10), RC_DATEBEG, 102) = CONVERT(CHAR(10), @date, 102)
		
			SET @course = CAST(ISNULL(@course, -1) AS DECIMAL(19,9))					
					
			IF @course <> -1
				BEGIN 				
					SET @course = 1 / @course					
				END
			ELSE
				BEGIN
					SELECT TOP 1 @course = RC_COURSE FROM RealCourses
						WHERE RC_RCOD1 = @national_currency AND RC_RCOD2 = @sRate
							AND CONVERT(CHAR(10), RC_DATEBEG, 102) = CONVERT(CHAR(10), @date, 102)						
							
					SET @course = CAST(ISNULL(@course, -1) AS DECIMAL(19,9))			
				END
		END		
	
	if @course <> -1
    begin
    
		set @rc_courseStr = CONVERT(varchar(20),@course, 126) 		
		
        declare @final_price money
        /*
        select @course
        select @course * @nPrice
        */
		set @final_price = ROUND(@course * @nPrice, 2)		

		declare @sys_setting varchar(5)
		set @sys_setting = null
		select @sys_setting = SS_ParmValue from SystemSettings where SS_ParmName = ''RECALC_NATIONAL_PRICE''

		-- пересчитываем цену, если надо
		if (@sys_setting <> ''-1'')
		begin
			declare @sHI_WHO varchar(25)
			exec dbo.CurrentUser @sHI_WHO output
	
			declare @tmp_final_price money
			set @tmp_final_price = null
			exec [dbo].[CalcPriceByNationalCurrencyRate] @sDogovor, @sRate, @sRateOld, @national_currency, @nPrice, @nPriceOld, @sHI_WHO, ''INSERT_TO_HISTORY'', @tmp_final_price output, @course, @order_status

			if @tmp_final_price is not null
			begin
				set @final_price = @tmp_final_price
			end
		end
		--
		
		if(@isAddToHistory=1)
		begin
			EXEC @nHIID = dbo.InsHistory @sDogovor, @dogovor_key, 20, null, ''UPD'', @rc_courseStr, @sRate, null, null, 1										
			EXEC dbo.InsertHistoryDetail @nHIID, 1151, null, @dateAsString, null, null, null, @date
		end
	    
		if(@isAddToHistory=1)
		begin
			update dbo.tbl_Dogovor
			set
				DG_NATIONALCURRENCYPRICE = @final_price,
				DG_NATIONALCURRENCYDISCOUNTSUM = @course * @nDiscountSum,
				DG_CurrencyRate = @course, 
				DG_CurrencyKey =  @currencyKey 
			where
				DG_CODE = @sDogovor
		end
		else
		begin
			update dbo.tbl_Dogovor
			set
			    DG_NATIONALCURRENCYPRICE = @final_price,
				DG_NATIONALCURRENCYDISCOUNTSUM = @course * @nDiscountSum
			where
			    DG_CODE = @sDogovor
		end                  
      end
      else
      begin
		update dbo.tbl_Dogovor
		set
			DG_NATIONALCURRENCYPRICE = null,
			DG_NATIONALCURRENCYDISCOUNTSUM = null
		where
			  DG_CODE = @sDogovor
			  and (DG_NATIONALCURRENCYPRICE is not null or DG_NATIONALCURRENCYDISCOUNTSUM is not null)
		
		if(@isAddToHistory=1)
		begin
			EXEC @nHIID = dbo.InsHistory @sDogovor, @dogovor_key, 21, null, ''UPD'', ''Курс отсутствует'', @sRate, null, null, 1
			EXEC dbo.InsertHistoryDetail @nHIID, 1151, null, @dateAsString, null, null, null, @date
		end
      end
END
return 0
')
END TRY
BEGIN CATCH
insert into ##errors values ('NationalCurrencyPrice2.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT EXEC ON [dbo].[NationalCurrencyPrice2] TO PUBLIC
')
END TRY
BEGIN CATCH
insert into ##errors values ('NationalCurrencyPrice2.sql', error_message())
END CATCH
end

print '############ end of file NationalCurrencyPrice2.sql ################'

print '############ begin of file ReCalculateNationalRatePrice.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[ReСalculateNationalRatePrice]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[ReСalculateNationalRatePrice]
')
END TRY
BEGIN CATCH
insert into ##errors values ('ReCalculateNationalRatePrice.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
CREATE PROCEDURE [dbo].[ReСalculateNationalRatePrice]
(
	@DG_KEY INT,
	@NDG_RATE VARCHAR(3),
	@ODG_RATE VARCHAR(3),
	@ODG_CODE VARCHAR(10),
	@NDG_PRICE FLOAT,
	@ODG_PRICE FLOAT,
	@NDG_DISCOUNTSUM FLOAT,
	@NDG_SOR_CODE INT
)
AS
BEGIN
    --<VERSION>9.2.21.1</VERSION>
    --<DATE>2014-12-11</DATE>
    -- Task 10558. Повторная фиксация курса валюты, в случае если он не зафиксировался
	DECLARE @LastNationalCurrencyFixationDate DATETIME    
    SELECT @LastNationalCurrencyFixationDate = dbo.GetLastDogovorFixationDate (@ODG_CODE, getdate(), 0)
    EXEC DBO.NationalCurrencyPrice2 @NDG_RATE, @ODG_RATE, @ODG_CODE, @NDG_PRICE, @ODG_PRICE, @NDG_DISCOUNTSUM, @LastNationalCurrencyFixationDate, @NDG_SOR_CODE
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('ReCalculateNationalRatePrice.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT EXEC ON [dbo].[ReСalculateNationalRatePrice] TO PUBLIC
')
END TRY
BEGIN CATCH
insert into ##errors values ('ReCalculateNationalRatePrice.sql', error_message())
END CATCH
end

print '############ end of file ReCalculateNationalRatePrice.sql ################'

print '############ begin of file UpdateAirlineCodeInTourProgramms.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[UpdateAirlineCodeInTourProgramms]'') AND type in (N''P'', N''PC''))
    DROP PROCEDURE [dbo].[UpdateAirlineCodeInTourProgramms]
')
END TRY
BEGIN CATCH
insert into ##errors values ('UpdateAirlineCodeInTourProgramms.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE PROCEDURE [dbo].[UpdateAirlineCodeInTourProgramms] 
    @oldCode varchar(4),
    @newCode varchar(4)
AS
BEGIN
    DECLARE @tpId int
    DECLARE @tpAirlinesCount int
    DECLARE @lnkRulesAirlinesCount int
    DECLARE @i int

    DECLARE cur_airlinesKeyValuePairsCount CURSOR FOR
        SELECT TP_Id,
               TP_XmlSettings.value(''count(/TourProgram/TourConsistencyViewModel/ServiceTemplates/ServiceTemplate/FlightData/FlightGroups/FlightGroup/Flights/Flight/SelectedAirlines/StringStringElement/Key)'', ''int''),
               TP_XmlSettings.value(''count(/TourProgram/LinkingFlightsRulesViewModel/NotCombineDifferentAirlineRule/Airlines/string)'', ''int'')
        FROM TourPrograms
    OPEN cur_airlinesKeyValuePairsCount

    FETCH NEXT FROM cur_airlinesKeyValuePairsCount INTO @tpId, @tpAirlinesCount, @lnkRulesAirlinesCount
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @i = 1
        WHILE (@i <= @tpAirlinesCount)
        BEGIN
            UPDATE TourPrograms SET TP_XmlSettings.modify(''
                replace value of (/TourProgram/TourConsistencyViewModel/ServiceTemplates/ServiceTemplate/FlightData/FlightGroups/FlightGroup/Flights/Flight/SelectedAirlines/StringStringElement/Key/text())[.=sql:variable("@oldCode")][1]
                with sql:variable("@newCode")
                '')
            WHERE TP_Id = @tpId

            SET @i = @i + 1
        END

        SET @i = 1
        WHILE (@i <= @lnkRulesAirlinesCount)
        BEGIN
            UPDATE TourPrograms SET TP_XmlSettings.modify(''
                replace value of (/TourProgram/LinkingFlightsRulesViewModel/NotCombineDifferentAirlineRule/Airlines/string/text())[.=sql:variable("@oldCode")][1]
                with sql:variable("@newCode")
                '')
            WHERE TP_Id = @tpId

            SET @i = @i + 1
        END

        FETCH NEXT FROM cur_airlinesKeyValuePairsCount INTO @tpId, @tpAirlinesCount, @lnkRulesAirlinesCount
    END

    CLOSE cur_airlinesKeyValuePairsCount
    DEALLOCATE cur_airlinesKeyValuePairsCount
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('UpdateAirlineCodeInTourProgramms.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT EXECUTE on [dbo].[UpdateAirlineCodeInTourProgramms] TO PUBLIC
')
END TRY
BEGIN CATCH
insert into ##errors values ('UpdateAirlineCodeInTourProgramms.sql', error_message())
END CATCH
end

print '############ end of file UpdateAirlineCodeInTourProgramms.sql ################'

print '############ begin of file UpdateAirportCodeInTourProgramms.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[UpdateAirportCodeInTourProgramms]'') AND type in (N''P'', N''PC''))
    DROP PROCEDURE [dbo].[UpdateAirportCodeInTourProgramms]
')
END TRY
BEGIN CATCH
insert into ##errors values ('UpdateAirportCodeInTourProgramms.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE PROCEDURE [dbo].[UpdateAirportCodeInTourProgramms] 
    @oldCode varchar(4),
    @newCode varchar(4)
AS
BEGIN
    DECLARE @tpId int
    DECLARE @departureAirportsCount int
    DECLARE @arrivalAirportsCount int
    DECLARE @i int

    DECLARE cur_airportsKeyValuePairsCount CURSOR FOR
        SELECT TP_Id,
               TP_XmlSettings.value(''count(/TourProgram/TourConsistencyViewModel/ServiceTemplates/ServiceTemplate/FlightData/FlightGroups/FlightGroup/Flights/Flight/SelectedDepartureAirports/StringStringElement/Key)'', ''int''),
               TP_XmlSettings.value(''count(/TourProgram/TourConsistencyViewModel/ServiceTemplates/ServiceTemplate/FlightData/FlightGroups/FlightGroup/Flights/Flight/SelectedArrivalAirports/StringStringElement/Key)'',''int'')
        FROM TourPrograms
    OPEN cur_airportsKeyValuePairsCount

    FETCH NEXT FROM cur_airportsKeyValuePairsCount INTO @tpId, @departureAirportsCount, @arrivalAirportsCount
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @i = 1
        WHILE (@i <= @departureAirportsCount)
        BEGIN
            UPDATE TourPrograms SET TP_XmlSettings.modify(''
                replace value of (/TourProgram/TourConsistencyViewModel/ServiceTemplates/ServiceTemplate/FlightData/FlightGroups/FlightGroup/Flights/Flight/SelectedDepartureAirports/StringStringElement/Key/text())[.=sql:variable("@oldCode")][1]
                with sql:variable("@newCode")
                '')
            WHERE TP_Id = @tpId

            SET @i = @i + 1
        END

        SET @i = 1
        WHILE (@i <= @arrivalAirportsCount)
        BEGIN
            print @i
            UPDATE TourPrograms SET TP_XmlSettings.modify(''
                replace value of (/TourProgram/TourConsistencyViewModel/ServiceTemplates/ServiceTemplate/FlightData/FlightGroups/FlightGroup/Flights/Flight/SelectedArrivalAirports/StringStringElement/Key/text())[.=sql:variable("@oldCode")][1]
                with sql:variable("@newCode")
                '')
            WHERE TP_Id = @tpId

            SET @i = @i + 1
        END
        
        FETCH NEXT FROM cur_airportsKeyValuePairsCount INTO @tpId, @departureAirportsCount, @arrivalAirportsCount
    END

    CLOSE cur_airportsKeyValuePairsCount
    DEALLOCATE cur_airportsKeyValuePairsCount
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('UpdateAirportCodeInTourProgramms.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT EXECUTE on [dbo].[UpdateAirportCodeInTourProgramms] TO PUBLIC
')
END TRY
BEGIN CATCH
insert into ##errors values ('UpdateAirportCodeInTourProgramms.sql', error_message())
END CATCH
end

print '############ end of file UpdateAirportCodeInTourProgramms.sql ################'

print '############ begin of file _delete_all_mw_stored_procedures.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
declare @killSql as nvarchar(max), @killSqlConcrete as nvarchar(max)



declare @droppedSP as table

(

	dropOrder smallint,

	tableName sysname,

	spType varchar(5)

)



insert into @droppedSP values (0, ''FillMasterWebSearchFields'', ''P'')

insert into @droppedSP values (1, ''fillAllTourPriceListsFields'', ''P'')

insert into @droppedSP values (2, ''fillPriceListFields'', ''P'')

insert into @droppedSP values (3, ''fillTourPriceListsFields'', ''P'')

insert into @droppedSP values (4, ''fillTourPriceName'', ''P'')

insert into @droppedSP values (5, ''mwAutobusQuotes'', ''P'')

insert into @droppedSP values (6, ''mwCacheQuotaInsert'', ''P'')

insert into @droppedSP values (7, ''mwCacheQuotaSearch'', ''P'')

insert into @droppedSP values (8, ''mwCheckFlightGroupsQuote'', ''P'')

insert into @droppedSP values (9, ''mwCheckFlightGroupsQuotesWithInnerFlights'', ''P'')

insert into @droppedSP values (10, ''mwCheckPriceTables'', ''P'')

insert into @droppedSP values (11, ''mwCheckQuotaOneResult'', ''P'')

insert into @droppedSP values (12, ''mwCheckQuotesCycle'', ''P'')

insert into @droppedSP values (13, ''mwCleanerQuotes'', ''P'')

insert into @droppedSP values (14, ''mwCreateAllPriceTablesIndexes'', ''P'')

insert into @droppedSP values (15, ''mwCreateCleanerJob'', ''P'')

insert into @droppedSP values (16, ''mwCreateNewPriceTable'', ''P'')

insert into @droppedSP values (17, ''mwCreatePriceHotelIndex'', ''P'')

insert into @droppedSP values (18, ''mwCreatePriceTable'', ''P'')

insert into @droppedSP values (19, ''mwCreatePriceTableIndexes'', ''P'')

insert into @droppedSP values (20, ''mwCreatePriceView'', ''P'')

insert into @droppedSP values (21, ''mwDropAllPriceTablesIndexes'', ''P'')

insert into @droppedSP values (22, ''mwEnablePriceTour'', ''P'')

insert into @droppedSP values (23, ''mwEnablePriceTourNewSinglePrice'', ''P'')

insert into @droppedSP values (24, ''mwFillPriceListDetails'', ''P'')

insert into @droppedSP values (25, ''mwFillPriceTable'', ''P'')

insert into @droppedSP values (26, ''mwFillTP'', ''P'')

insert into @droppedSP values (27, ''mwGetCalculatedPriceInfo'', ''P'')

insert into @droppedSP values (28, ''mwGetHotelTypeImageHtml'', ''P'')

insert into @droppedSP values (29, ''mwGetMinNearestTourPrices'', ''P'')

insert into @droppedSP values (30, ''mwGetPricePagingKeys'', ''P'')

insert into @droppedSP values (31, ''mwGetSearchFilter'', ''P'')

insert into @droppedSP values (32, ''mwGetSearchFilterDates'', ''P'')

insert into @droppedSP values (33, ''mwGetSearchFilterDirectionData'', ''P'')

insert into @droppedSP values (34, ''mwGetSearchFilterNights'', ''P'')

insert into @droppedSP values (35, ''mwGetServiceIsEditableAttribute'', ''P'')

insert into @droppedSP values (36, ''mwGetServiceVariants'', ''P'')

insert into @droppedSP values (37, ''mwGetSpoList'', ''P'')

insert into @droppedSP values (38, ''mwGetSubscriptions'', ''P'')

insert into @droppedSP values (39, ''mwGetTourInfo'', ''P'')

insert into @droppedSP values (40, ''mwGetTourMonthesQuotas'', ''P'')

insert into @droppedSP values (41, ''mwHotelQuotes'', ''P'')

insert into @droppedSP values (42, ''mwMakeFullSVName'', ''P'')

insert into @droppedSP values (43, ''mwParseHotelDetails'', ''P'')

insert into @droppedSP values (44, ''mwPriceListCleaner'', ''P'')

insert into @droppedSP values (45, ''mwReindex'', ''P'')

insert into @droppedSP values (46, ''mwRemoveDeleted'', ''P'')

insert into @droppedSP values (47, ''mwReplDeletePriceTour'', ''P'')

insert into @droppedSP values (48, ''mwReplDisableDeletedPrices'', ''P'')

insert into @droppedSP values (49, ''mwReplDisablePriceTour'', ''P'')

insert into @droppedSP values (50, ''mwReplProcessQueue'', ''P'')

insert into @droppedSP values (51, ''mwReplProcessQueueDivide'', ''P'')

insert into @droppedSP values (52, ''mwReplProcessQueueUpdate'', ''P'')

insert into @droppedSP values (53, ''mwReplSync'', ''P'')

insert into @droppedSP values (54, ''mwReplUpdatePriceEnabledAndValue'', ''P'')

insert into @droppedSP values (55, ''mwReplUpdatePriceTourDateValid'', ''P'')

insert into @droppedSP values (56, ''mwSetOnline'', ''P'')

insert into @droppedSP values (57, ''mwSimpleTourInfo'', ''P'')

insert into @droppedSP values (58, ''mwSyncDictionaryData'', ''P'')

insert into @droppedSP values (59, ''mwTourInfo'', ''P'')

insert into @droppedSP values (60, ''mwTruncatePriceTable'', ''P'')

insert into @droppedSP values (61, ''mwUpdateHotelDetails'', ''P'')

insert into @droppedSP values (62, ''Paging'', ''P'')

insert into @droppedSP values (63, ''PagingPax'', ''P'')

insert into @droppedSP values (64, ''PagingSelect'', ''P'')

insert into @droppedSP values (65, ''SPOListResults'', ''P'')

insert into @droppedSP values (66, ''mwCheckQuotesEx'', ''TF'')

insert into @droppedSP values (67, ''mwCheckQuotesEx2'', ''TF'')

insert into @droppedSP values (68, ''mwCheckQuotesFlights'', ''TF'')

insert into @droppedSP values (69, ''mwCheckQuotes'', ''FN'')

insert into @droppedSP values (70, ''mwCheckTourQuotes'', ''FN'')

insert into @droppedSP values (71, ''mwConcatFlightsGroupsQuotas'', ''FN'')

insert into @droppedSP values (72, ''mwFirstTourDate'', ''FN'')

insert into @droppedSP values (73, ''mwGetFullHotelNames'', ''FN'')

insert into @droppedSP values (74, ''mwGetNotCalculatedSvNames'', ''FN'')

insert into @droppedSP values (75, ''mwGetPriceTableName'', ''FN'')

insert into @droppedSP values (76, ''mwGetPriceViewName'', ''FN'')

insert into @droppedSP values (77, ''mwGetServiceClasses'', ''FN'')

insert into @droppedSP values (78, ''mwGetServiceClassesNames'', ''FN'')

insert into @droppedSP values (79, ''mwGetServiceClassesNamesExtended'', ''FN'')

insert into @droppedSP values (80, ''mwGetServices'', ''FN'')

insert into @droppedSP values (81, ''mwGetSpoHotelNames'', ''FN'')

insert into @droppedSP values (82, ''mwGetSpoRegionNames'', ''FN'')

insert into @droppedSP values (83, ''mwGetTiHotelKeys'', ''FN'')

insert into @droppedSP values (84, ''mwGetTiHotelNights'', ''FN'')

insert into @droppedSP values (85, ''mwGetTiHotelRoomKeys'', ''FN'')

insert into @droppedSP values (86, ''mwGetTiHotelStars'', ''FN'')

insert into @droppedSP values (87, ''mwGetTiNights'', ''FN'')

insert into @droppedSP values (88, ''mwGetTiPansionKeys'', ''FN'')

insert into @droppedSP values (89, ''mwGetTourCharterAttribute'', ''FN'')

insert into @droppedSP values (90, ''mwGetTourCharters'', ''FN'')

insert into @droppedSP values (91, ''mwGetTourHotels'', ''FN'')

insert into @droppedSP values (92, ''mwIsTourAllowedForPublish'', ''FN'')

insert into @droppedSP values (93, ''mwReplIsPublisher'', ''FN'')

insert into @droppedSP values (94, ''mwReplIsSubscriber'', ''FN'')

insert into @droppedSP values (95, ''mwReplPublisherDB'', ''FN'')

insert into @droppedSP values (96, ''mwReplSubscriberDB'', ''FN'')

insert into @droppedSP values (97, ''mwTourChKeys'', ''FN'')

insert into @droppedSP values (98, ''mwTourChNames'', ''FN'')

insert into @droppedSP values (99, ''mwTourHotelCtKeys'', ''FN'')

insert into @droppedSP values (100, ''mwTourHotelCtNames'', ''FN'')

insert into @droppedSP values (101, ''mwTourHotelKeys'', ''FN'')

insert into @droppedSP values (102, ''mwTourHotelNights'', ''FN'')

insert into @droppedSP values (103, ''mwTourHotelRsKeys'', ''FN'')

insert into @droppedSP values (104, ''mwTourHotelStars'', ''FN'')



set @killSql = ''if exists (select top 1 1 from sys.objects where name = ''''#procName'''' and type = ''''#spType'''')

	begin

		DROP #dropToken [dbo].[#procName]

	end''



declare killCursor cursor for

select tableName, spType

from @droppedSP

order by dropOrder asc



declare @procName as sysname, @spType as varchar(5)



open killCursor



fetch next from killCursor into @procName, @spType

while @@fetch_status = 0

begin

	

	set @killSqlConcrete = replace(@killSql, ''#procName'', @procName)

	set @killSqlConcrete = replace(@killSqlConcrete, ''#spType'', @spType)

	if @spType = ''P''

		set @killSqlConcrete = replace(@killSqlConcrete, ''#dropToken'', ''procedure'')

	if @spType = ''TF'' or @spType = ''FN''

		set @killSqlConcrete = replace(@killSqlConcrete, ''#dropToken'', ''function'')



	begin try

		

		print ''drop '' + @procName

		print @killSqlConcrete

		exec (@killSqlConcrete)

		print ''drop '' + @procName + '' complete''



	end try

	begin catch

		declare @errMessage as nvarchar(max)

		set @errMessage = ''There is error during '' + @procName + '' table drop: '' + error_message()

		print @errMessage



		raiserror(@errMessage, 16, 1)

		break

	end catch



	fetch next from killCursor into @procName, @spType

end



close killCursor

deallocate killCursor
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('_delete_all_mw_stored_procedures.sql', error_message())
END CATCH
end

print '############ end of file _delete_all_mw_stored_procedures.sql ################'

print '############ begin of file _delete_all_wcf_stored_procedures.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
declare @killSql as nvarchar(max), @killSqlConcrete as nvarchar(max)



declare @droppedSP as table

(

	dropOrder smallint,

	tableName sysname

)



insert into @droppedSP values (0, ''WcfCheckQuotaCycle'')

insert into @droppedSP values (1, ''WcfGetActualPrice'')

insert into @droppedSP values (2, ''WcfGetQuotas'')

insert into @droppedSP values (3, ''WcfQuotaCheckOneResult'')

insert into @droppedSP values (4, ''WcfReCalculateAddCosts'')

insert into @droppedSP values (5, ''WcfReCalculateAddCostsByCount'')

insert into @droppedSP values (6, ''WcfReCalculateCosts'')

insert into @droppedSP values (7, ''WcfReCalculateCostsByCount'')

insert into @droppedSP values (8, ''WcfReCalculateCostsByServiceKey'')

insert into @droppedSP values (9, ''WcfReCalculateMargin'')

insert into @droppedSP values (10, ''WcfReCalculateNextCostsByCount'')

insert into @droppedSP values (11, ''WcfSetServiceToQuota'')

insert into @droppedSP values (12, ''WcfTransferServicesInDatePeriod'')



set @killSql = ''if exists (select top 1 1 from sys.procedures where name = ''''#procName'''')

	begin

		DROP procedure [dbo].[#procName]

	end''



declare killCursor cursor for

select tableName

from @droppedSP

order by dropOrder asc



declare @procName as sysname



open killCursor



fetch next from killCursor into @procName

while @@fetch_status = 0

begin

	

	set @killSqlConcrete = replace(@killSql, ''#procName'', @procName)



	begin try

		

		print ''drop procedure '' + @procName

		exec (@killSqlConcrete)

		print ''drop procedure '' + @procName + '' complete''



	end try

	begin catch

		declare @errMessage as nvarchar(max)

		set @errMessage = ''There is error during '' + @procName + '' table drop: '' + error_message()

		print @errMessage



		raiserror(@errMessage, 16, 1)

		break

	end catch



	fetch next from killCursor into @procName

end



close killCursor

deallocate killCursor
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('_delete_all_wcf_stored_procedures.sql', error_message())
END CATCH
end

print '############ end of file _delete_all_wcf_stored_procedures.sql ################'

print '############ begin of file _delete_AutoPlacesQuotes.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--удаление хранимки AutoPlacesQuotes

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[AutoPlacesQuotes]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[AutoPlacesQuotes]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_AutoPlacesQuotes.sql', error_message())
END CATCH
end

print '############ end of file _delete_AutoPlacesQuotes.sql ################'

print '############ begin of file _delete_Calculate_stored_procedures.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
declare @killSql as nvarchar(max), @killSqlConcrete as nvarchar(max)



declare @droppedSP as table

(

	dropOrder smallint,

	tableName sysname

)



insert into @droppedSP values (0, ''CalculatePriceList'')

insert into @droppedSP values (1, ''CalculatePriceListDynamic'')

insert into @droppedSP values (2, ''CalculatePriceListFinish'')

insert into @droppedSP values (3, ''CalculatePriceListInit'')



set @killSql = ''if exists (select top 1 1 from sys.tables where name = ''''#procName'''')

	begin

		DROP procedure [dbo].[#procName]

	end''



declare killCursor cursor for

select tableName

from @droppedSP

order by dropOrder asc



declare @procName as sysname



open killCursor



fetch next from killCursor into @procName

while @@fetch_status = 0

begin

	

	set @killSqlConcrete = replace(@killSql, ''#procName'', @procName)



	begin try

		

		print ''drop procedure '' + @procName

		exec (@killSqlConcrete)

		print ''drop procedure '' + @procName + '' complete''



	end try

	begin catch

		declare @errMessage as nvarchar(max)

		set @errMessage = ''There is error during '' + @procName + '' table drop: '' + error_message()

		print @errMessage



		raiserror(@errMessage, 16, 1)

		break

	end catch



	fetch next from killCursor into @procName

end



close killCursor

deallocate killCursor
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('_delete_Calculate_stored_procedures.sql', error_message())
END CATCH
end

print '############ end of file _delete_Calculate_stored_procedures.sql ################'

print '############ begin of file _delete_ClearMasterWebSearchFields.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[ClearMasterWebSearchFields]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[ClearMasterWebSearchFields]

')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_ClearMasterWebSearchFields.sql', error_message())
END CATCH
end

print '############ end of file _delete_ClearMasterWebSearchFields.sql ################'

print '############ begin of file _delete_CorrectionCalculatedPrice_Run.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[CorrectionCalculatedPrice_Run]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[CorrectionCalculatedPrice_Run]

')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_CorrectionCalculatedPrice_Run.sql', error_message())
END CATCH
end

print '############ end of file _delete_CorrectionCalculatedPrice_Run.sql ################'

print '############ begin of file _delete_CorrectionCalculatedPrice_RunSubscriber.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[CorrectionCalculatedPrice_RunSubscriber]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[CorrectionCalculatedPrice_RunSubscriber]

')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_CorrectionCalculatedPrice_RunSubscriber.sql', error_message())
END CATCH
end

print '############ end of file _delete_CorrectionCalculatedPrice_RunSubscriber.sql ################'

print '############ begin of file _delete_CostOfferChangeState.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--<DATE>2014-09-30</DATE>
--удаление хранимки CostOfferChangeState

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[CostOfferChangeState]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[CostOfferChangeState]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_CostOfferChangeState.sql', error_message())
END CATCH
end

print '############ end of file _delete_CostOfferChangeState.sql ################'

print '############ begin of file _delete_DS_GetCalendarTourDates.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[DS_GetCalendarTourDates]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[DS_GetCalendarTourDates]

')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_DS_GetCalendarTourDates.sql', error_message())
END CATCH
end

print '############ end of file _delete_DS_GetCalendarTourDates.sql ################'

print '############ begin of file _delete_GetCalendarTourDates.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[GetCalendarTourDates]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[GetCalendarTourDates]

')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_GetCalendarTourDates.sql', error_message())
END CATCH
end

print '############ end of file _delete_GetCalendarTourDates.sql ################'

print '############ begin of file _delete_MarginChange.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--удаление хранимки MarginChange

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[MarginChange]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[MarginChange]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_MarginChange.sql', error_message())
END CATCH
end

print '############ end of file _delete_MarginChange.sql ################'

print '############ begin of file _delete_mwCleaner.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[mwCleaner]'') AND type in (N''P'', N''PC''))

	DROP PROCEDURE [dbo].[mwCleaner]

')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_mwCleaner.sql', error_message())
END CATCH
end

print '############ end of file _delete_mwCleaner.sql ################'

print '############ begin of file _delete_ProcessCharterDeleteQueue.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[ProcessCharterDeleteQueue]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[ProcessCharterDeleteQueue]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_ProcessCharterDeleteQueue.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('_delete_ProcessCharterDeleteQueue.sql', error_message())
END CATCH
end

print '############ end of file _delete_ProcessCharterDeleteQueue.sql ################'

print '############ begin of file _delete_QuotaDetailsAfterDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--удаление хранимки QuotaDetailsAfterDelete

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[QuotaDetailsAfterDelete]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[QuotaDetailsAfterDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_QuotaDetailsAfterDelete.sql', error_message())
END CATCH
end

print '############ end of file _delete_QuotaDetailsAfterDelete.sql ################'

print '############ begin of file _delete_QuotaPartsAfterDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--удаление хранимки QuotaPartsAfterDelete

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[QuotaPartsAfterDelete]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[QuotaPartsAfterDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_QuotaPartsAfterDelete.sql', error_message())
END CATCH
end

print '############ end of file _delete_QuotaPartsAfterDelete.sql ################'

print '############ begin of file _delete_ReCalculate_CreateNextSaleDate.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--<DATE>2014-09-30</DATE>
--удаление хранимки ReCalculate_CreateNextSaleDate
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[ReCalculate_CreateNextSaleDate]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[ReCalculate_CreateNextSaleDate]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_ReCalculate_CreateNextSaleDate.sql', error_message())
END CATCH
end

print '############ end of file _delete_ReCalculate_CreateNextSaleDate.sql ################'

print '############ begin of file _delete_SetServiceQuotasStatus.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--удаление хранимки SetServiceQuotasStatus

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[SetServiceQuotasStatus]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[SetServiceQuotasStatus]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_SetServiceQuotasStatus.sql', error_message())
END CATCH
end

print '############ end of file _delete_SetServiceQuotasStatus.sql ################'

print '############ begin of file _delete_TPPriceChange.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--удаление хранимки TPPriceChange

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[TPPriceChange]'') AND type in (N''P'', N''PC''))
DROP PROCEDURE [dbo].[TPPriceChange]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_delete_TPPriceChange.sql', error_message())
END CATCH
end

print '############ end of file _delete_TPPriceChange.sql ################'

print '############ begin of file _delete_tp_all_stored_procedures.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
declare @killSql as nvarchar(max), @killSqlConcrete as nvarchar(max)



declare @droppedSP as table

(

	dropOrder smallint,

	tableName sysname,

	spType varchar(5)

)



insert into @droppedSP values (0, ''CalculatePriceList'', ''P'')

insert into @droppedSP values (1, ''CalculatePriceListDynamic'', ''P'')

insert into @droppedSP values (2, ''CalculatePriceListFinish'', ''P'')

insert into @droppedSP values (3, ''CalculatePriceListInit'', ''P'')

insert into @droppedSP values (4, ''ReCalculate_CheckActualPrice'', ''P'')

insert into @droppedSP values (5, ''ReCalculate_CreateServiceCalculateParametrs'', ''P'')

insert into @droppedSP values (6, ''ReCalculate_Delete'', ''P'')

insert into @droppedSP values (7, ''ReCalculate_MigrateToPrice'', ''P'')

insert into @droppedSP values (8, ''ReCalculate_TakeOff'', ''P'')

insert into @droppedSP values (9, ''ReCalculate_ViewHotelCost'', ''P'')

insert into @droppedSP values (10, ''ReCalculateAddCosts'', ''P'')

insert into @droppedSP values (11, ''ReCalculateAll'', ''P'')

insert into @droppedSP values (12, ''RecalculateByTime'', ''P'')

insert into @droppedSP values (13, ''ReCalculateCleaner'', ''P'')

insert into @droppedSP values (14, ''ReCalculateCosts'', ''P'')

insert into @droppedSP values (15, ''ReCalculateCosts_CalculatePriceList'', ''P'')

insert into @droppedSP values (16, ''ReCalculateCosts_GrossMigrate'', ''P'')

insert into @droppedSP values (17, ''ReCalculateCosts_MarginMigrate'', ''P'')

insert into @droppedSP values (18, ''ReCalculateCosts_MarginMigrateTRKey'', ''P'')

insert into @droppedSP values (19, ''ReCalculateCosts_MarginMigrateTRKey2'', ''P'')

insert into @droppedSP values (20, ''ReCalculateMargin'', ''P'')

insert into @droppedSP values (21, ''ReCalculateMargins_CalculatePriceList'', ''P'')

insert into @droppedSP values (22, ''ReCalculateNextCosts'', ''P'')

insert into @droppedSP values (23, ''RecalculatePriceListScheduler'', ''P'')

insert into @droppedSP values (24, ''ReCalculateSaleDate'', ''P'')

insert into @droppedSP values (25, ''sp_GetPricePage'', ''P'')

insert into @droppedSP values (26, ''sp_GetPricePage_VP'', ''P'')

insert into @droppedSP values (27, ''fn_mwGetFlightAndCommissionServicesCosts'', ''TF'')



set @killSql = ''if exists (select top 1 1 from sys.objects where name = ''''#procName'''' and type = ''''#spType'''')

	begin

		DROP #dropToken [dbo].[#procName]

	end''



declare killCursor cursor for

select tableName, spType

from @droppedSP

order by dropOrder asc



declare @procName as sysname, @spType as varchar(5)



open killCursor



fetch next from killCursor into @procName, @spType

while @@fetch_status = 0

begin

	

	set @killSqlConcrete = replace(@killSql, ''#procName'', @procName)

	set @killSqlConcrete = replace(@killSqlConcrete, ''#spType'', @spType)

	if @spType = ''P''

		set @killSqlConcrete = replace(@killSqlConcrete, ''#dropToken'', ''procedure'')

	if @spType = ''TF'' or @spType = ''FN''

		set @killSqlConcrete = replace(@killSqlConcrete, ''#dropToken'', ''function'')



	begin try

		

		print ''drop procedure '' + @procName

		exec (@killSqlConcrete)

		print ''drop procedure '' + @procName + '' complete''



	end try

	begin catch

		declare @errMessage as nvarchar(max)

		set @errMessage = ''There is error during '' + @procName + '' table drop: '' + error_message()

		print @errMessage



		raiserror(@errMessage, 16, 1)

		break

	end catch



	fetch next from killCursor into @procName, @spType

end



close killCursor

deallocate killCursor
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('_delete_tp_all_stored_procedures.sql', error_message())
END CATCH
end

print '############ end of file _delete_tp_all_stored_procedures.sql ################'

print '############ begin of file Accmdmentype.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


UPDATE Accmdmentype SET AC_PERROOM = 1 WHERE  ISNULL(AC_PERROOM, 0) = 0


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('Accmdmentype.sql', error_message())
END CATCH
end

print '############ end of file Accmdmentype.sql ################'

print '############ begin of file Actions_constants.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
declare @allGroupIds as ListIntValue

insert into @allGroupIds

select gid from sysusers where uid = gid



--переимнновали экшин Гл. меню -> Конструктор туров на:

IF EXISTS (SELECT 1 FROM Actions WHERE ac_key = 2) 

BEGIN

	UPDATE dbo.Actions 

	SET AC_Name = ''Гл. меню -> Программы туров''

	where ac_key = 2

END



--удалить экшин Гл. меню -> Даты заездов

IF EXISTS (SELECT 1 FROM Actions WHERE ac_key = 3) 

BEGIN

	DELETE FROM dbo.Actions 

	where ac_key = 3

END



IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 32) 

BEGIN

	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 

	VALUES (32, ''Гл.меню->Цены на услугу'', ''Разрешить редактирование цен на услуги'',  ''Main menu->Service costs'', 0)



	insert into GroupAuth (gra_ackey, gra_grkey) 

	select 32, value

	from @allGroupIds

END



IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 33) 

BEGIN

	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 

	VALUES (33, ''Гл.меню->Ценовые блоки'', ''Разрешить редактирование ценовых блоков'',  ''Main menu->Cost offers'', 0)



	insert into GroupAuth (gra_ackey, gra_grkey) 

	select 33, value

	from @allGroupIds

END



--переимнновали экшин (Разрешить просмотр цен на отели) на:

IF EXISTS (SELECT 1 FROM Actions WHERE ac_key = 56) 

BEGIN

	UPDATE dbo.Actions 

	SET AC_Name = ''Гл. меню -> Цены на отели''

	where ac_key = 56

END



--добавление action список классов точек отправления/прибытия

IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 164) 

BEGIN

	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 

	VALUES (164, ''Редактирование списка классов точек отправления/прибытия'', ''Разрешить редактирование списка классов точек отправления/прибытия'', null, 0)

END



--переимнновали экшин (Разрешить просмотр цен на отели) на:

IF EXISTS (SELECT 1 FROM Actions WHERE ac_key = 164) 

BEGIN

	UPDATE dbo.Actions 

	SET AC_Name = ''Справочники -> Скрыть справочник классов точек отправления/прибытия'',

		AC_Description = ''Разрешить/Запретить редактирование классов точек отправления/прибытия''

	where ac_key = 164

END



--добавление action список точек отправления/прибытия

IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 165) 

BEGIN

	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 

	VALUES (165, ''Редактирование списка точек отправления/прибытия'', ''Разрешить редактирование списка точек отправления/прибытия'', null, 0)

END

--переименовать содержимо action 165

IF EXISTS (SELECT 1 FROM Actions WHERE ac_key = 164) 

BEGIN

	UPDATE dbo.Actions 

	SET AC_Name = ''Справочники -> Скрыть справочник классов точек отправления/прибытия'',

		AC_Description = ''Разрешить/Запретить редактирование классов точек отправления/прибытия''

	where ac_key = 164

END




--переимнновали экшин Гл. меню -> Конструктор туров на:

IF EXISTS (SELECT 1 FROM Actions WHERE ac_key = 165) 

BEGIN

	UPDATE dbo.Actions 

	SET AC_Name = ''Справочники -> Скрыть справочник точек отправления/прибытия'',

	AC_Description = ''Разрешить/Запретить редактирование списка точек отправления/прибытия''

	where ac_key = 165

END



--добавить экшин Справочники -> Скрыть справочник типов туров"

IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 166) 

BEGIN

	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 

	VALUES (166, ''Справочники -> Скрыть справочник типов туров'', ''Справочники -> Скрыть справочник типов туров'',  ''Dictionaries->Hide tour types dictionary'', 0)

END
ELSE
BEGIN
    UPDATE Actions SET AC_Name = ''Справочники -> Скрыть справочник типов туров'', AC_Description =  ''Справочники -> Скрыть справочник типов туров" в экране "Работа менеджеров"'', AC_NameLat =''Dictionaries->Hide tour types dictionary''
        WHERE ac_key = 166
END



--добавить экшин Справочники -> Скрыть справочник партнеров"

IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 167) 

BEGIN

	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 

	VALUES (167, ''Справочники -> Скрыть справочник партнеров'', ''Справочники -> Скрыть справочник партнеров'',  ''Dictionaries->Hide partners dictionary'', 0)

END

--добавить экшин Постоянные клиенты -> Разрешить просмотр регистрационных данных пользователя"

IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 176) 

BEGIN

	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 

	VALUES (176, N''Постоянные клиенты -> Разрешить просмотр регистрационных данных пользователя'', N''Разрешить просмотр регистрационных данных пользователя'',  ''Allow view users credentials'', 0)

END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 150) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (150, ''Скрыть колонку -> "Полная стоимость путевки"'', ''Скрывать колонку "Полная стоимость путевки"'', ''Hide columns -> "Dogovor total price"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 151) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (151, ''Скрыть колонку -> "Стоимость в национальной валюте"'', ''Скрывать колонку "Стоимость в национальной валюте"'', ''Hide columns -> "National price"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 152) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (152, ''Скрыть колонку -> "Оплата в национальной валюте"'', ''Скрывать колонку "Оплата в национальной валюте"'', ''Hide columns -> "Payment in national price"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 153) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (153, ''Скрыть колонку -> "Стоимость за вычетом скидки"'', ''Скрывать колонку "Стоимость за вычетом скидки"'', ''Hide columns -> "Price without discount"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 154) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (154, ''Скрыть колонку -> "Сумма к оплате"'', ''Скрывать колонку "Сумма к оплате"'', ''Hide columns -> "Payment amount"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 155) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (155, ''Скрыть колонку -> "Скидка на 1 человека"'', ''Скрывать колонку "Скидка на одного человека"'', ''Hide columns -> "Discount per person"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 156) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (156, ''Скрыть колонку -> "Оплата"'', ''Скрывать колонку "Оплата"'', ''Hide columns -> "Payment"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 157) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (157, ''Скрыть колонку -> "Нетто планируемое"'', ''Скрывать колонку "Нетто планируемое"'', ''Hide columns -> "Net planned"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 158) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (158, ''Скрыть колонку -> "Нетто по платежам партнеру"'', ''Скрывать колонку "Нетто по платежам партнеру"'', ''Hide columns -> "Net on payed to partner"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 159) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (159, ''Скрыть колонку -> "Нетто реальное"'', ''Скрывать колонку "Нетто реальное"'', ''Hide columns -> "Net real"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 160) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (160, ''"Работа менеджеров" -> Скрыть колонку "Прибыль планируемая"'', ''Скрывать колонку "Прибыль планируемая" в экране "Работа менеджеров"'', ''Window "Manager work" -> Hide columns "Profit planned"'', 1)
END
ELSE
BEGIN
    UPDATE Actions SET AC_Name = ''"Работа менеджеров" -> Скрыть колонку "Прибыль планируемая"'', AC_Description =  ''Скрывать колонку "Прибыль планируемая" в экране "Работа менеджеров"'', AC_NameLat = ''Window "Manager work" -> Hide columns "Profit planned"''
        WHERE ac_key = 160
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 161) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (161, ''"Работа менеджеров" -> Скрыть колонку "Прибыль планируемая, %"'', ''Скрывать колонку "Прибыль планируемая %" в экране "Работа менеджеров"'', ''Window "Manager work" -> Hide columns "Profit planned %"'', 1)
END
BEGIN
    UPDATE Actions SET AC_Name = ''"Работа менеджеров" -> Скрыть колонку "Прибыль планируемая, %"'', AC_Description =  ''Скрывать колонку "Прибыль планируемая %" в экране "Работа менеджеров"'', AC_NameLat =''Window "Manager work" -> Hide columns "Profit planned %"''
        WHERE ac_key = 161
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 162) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (162, ''"Работа менеджеров" -> Скрыть колонку "Прибыль реальная"'', ''Скрывать колонку "Прибыль реальная" в экране  "Работа менеджеров"'', ''Window "Manager work" -> Hide columns "Profit real"'', 1)
END
BEGIN
    UPDATE Actions SET AC_Name = ''"Работа менеджеров" -> Скрыть колонку "Прибыль реальная"'', AC_Description =  ''Скрывать колонку "Прибыль реальная" в экране  "Работа менеджеров"'', AC_NameLat =  ''Window "Manager work" -> Hide columns "Profit real"''
        WHERE ac_key = 162
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 163) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (163, ''Скрыть строку итогов экрана "Работа менеджеров"'', ''Скрыть строку итогов экрана "Работа менеджеров"'', ''Hide summary table'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 168) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (168, ''Скрытие колонок -> "Недоплата"'', 
		''Скрывать колонку "Недоплата"'', 
		''Hide columns -> "Rest Payment"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 169) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (169, ''Скрытие колонок -> "Недоплата в национальной валюте"'', 
		''Скрывать колонку "Недоплата в национальной валюте"'', 
		''Hide columns -> "Rest Payment in national price"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 170) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (170, ''"Турпутевка" и "Оформление клиентов" -> Скрыть колонку "Прибыль планируемая"'', ''Скрывать колонку "Прибыль планируемая" в экранах "Турпутевка" и "Оформление клиентов"'', ''Window "Dogovor" and "Tour sale" -> Hide columns -> "Profit planned"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 171) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (171, ''"Турпутевка" и "Оформление клиентов" -> Скрыть колонку "Прибыль планируемая, %"'', ''Скрывать колонку "Прибыль планируемая %" в экранах "Турпутевка" и "Оформление клиентов"'', ''Window "Dogovor" and "Tour sale" -> Hide columns -> "Profit planned %"'', 1)
END


IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 172) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (172, ''"Турпутевка" и "Оформление клиентов" -> Скрыть колонку "Прибыль реальная"'', ''Скрывать колонку "Прибыль реальная" в экранах "Турпутевка" и "Оформление клиентов"'', ''Window "Dogovor" and "Tour sale" -> Hide columns -> "Profit real"'', 1)
END

IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 179) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (179, ''Касса -> Запретить осуществлять проводки на прошедшие даты'', ''Запретить осуществлять проводки на прошедшие даты'', ''Сash -> Deny create payment on past date'', 1)
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('Actions_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS (SELECT 1 FROM Actions WHERE ac_key = 180) 
BEGIN
	INSERT INTO Actions (AC_Key, AC_Name, AC_Description, AC_NameLat, AC_IsActionForRestriction) 
	VALUES (180, ''Касса -> Запретить редактирование платежных операций на прошедшие даты'', ''Запретить редактирование платежных операций на прошедшие даты'', ''Cash -> Deny edit payment operation with past date payment'', 1)
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('Actions_constants.sql', error_message())
END CATCH
end

print '############ end of file Actions_constants.sql ################'

print '############ begin of file AddCosts.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (  SELECT 1

    FROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS 

    WHERE CONSTRAINT_NAME=''FK_AddCosts_tbl_TurList'')

	

  alter table [AddCosts] drop FK_AddCosts_tbl_TurList

')
END TRY
BEGIN CATCH
insert into ##errors values ('AddCosts.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



if not exists (select 1 from dbo.syscolumns where name = ''ADC_CityKey'' and id = object_id(N''[dbo].[AddCosts]''))

	ALTER TABLE [dbo].AddCosts ADD ADC_CityKey INT NOT NULL DEFAULT(0)

')
END TRY
BEGIN CATCH
insert into ##errors values ('AddCosts.sql', error_message())
END CATCH
end

print '############ end of file AddCosts.sql ################'

print '############ begin of file CityDictionary.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists (select 1 from dbo.syscolumns where name = ''CT_Timezone'' and id = object_id(N''[dbo].[CityDictionary]''))

	ALTER TABLE [dbo].[CityDictionary] Add CT_Timezone nvarchar(150)

')
END TRY
BEGIN CATCH
insert into ##errors values ('CityDictionary.sql', error_message())
END CATCH
end

print '############ end of file CityDictionary.sql ################'

print '############ begin of file CityDictionary_constants.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
UPDATE CityDictionary SET CT_ISDEPARTURE = 1 where CT_KEY != 0



IF NOT EXISTS( SELECT * FROM dbo.sysobjects  WHERE id = object_id(N''[dbo].[DF_CITYDICTIONARY_CT_ISDEPARTURE]'') ) 

	ALTER TABLE [dbo].[CityDictionary] ADD  CONSTRAINT [DF_CITYDICTIONARY_CT_ISDEPARTURE]  DEFAULT (1) FOR [CT_ISDEPARTURE]

')
END TRY
BEGIN CATCH
insert into ##errors values ('CityDictionary_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('CityDictionary_constants.sql', error_message())
END CATCH
end

print '############ end of file CityDictionary_constants.sql ################'

print '############ begin of file Clients.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists (select 1 from dbo.syscolumns where name = ''CL_Creator'' and id = object_id(N''[dbo].[Clients]''))
	ALTER TABLE [dbo].[Clients] ADD [CL_Creator] [int] NULL
')
END TRY
BEGIN CATCH
insert into ##errors values ('Clients.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from dbo.syscolumns where name = ''CL_CreateDate'' and id = object_id(N''[dbo].[Clients]''))
	ALTER TABLE [dbo].[Clients] ADD [CL_CreateDate] [datetime] NULL
')
END TRY
BEGIN CATCH
insert into ##errors values ('Clients.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
	
if not exists (select 1 from dbo.syscolumns where name = ''CL_Login'' and id = object_id(N''[dbo].[Clients]''))
	ALTER TABLE [dbo].[Clients] ADD CL_Login varchar(128)
')
END TRY
BEGIN CATCH
insert into ##errors values ('Clients.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from dbo.syscolumns where name = ''CL_Password'' and id = object_id(N''[dbo].[Clients]''))
	ALTER TABLE [dbo].[Clients] ADD CL_Password nvarchar(max)
')
END TRY
BEGIN CATCH
insert into ##errors values ('Clients.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if exists (select 1 from dbo.syscolumns where name = ''CL_IsOnline'' and id = object_id(N''[dbo].[Clients]''))
	EXEC sp_rename ''dbo.Clients.CL_IsOnline'', ''CL_IsOnlineUser'', ''COLUMN''; 
')
END TRY
BEGIN CATCH
insert into ##errors values ('Clients.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from dbo.syscolumns where name = ''CL_IsOnlineUser'' and id = object_id(N''[dbo].[Clients]''))
	ALTER TABLE [dbo].[Clients] ADD CL_IsOnlineUser bit
')
END TRY
BEGIN CATCH
insert into ##errors values ('Clients.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from dbo.syscolumns where name = ''CL_CitizenID'' and id = object_id(N''[dbo].[Clients]''))
	ALTER TABLE [dbo].[Clients] ADD CL_CitizenID VARCHAR(14) NULL
')
END TRY
BEGIN CATCH
insert into ##errors values ('Clients.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



-- 35506. Скрипт на добавление создателя и даты создания постоянного клиента
----------------------------------------------------------------------------
grant exec on [dbo].[GetUserId] to public

-- если нужно добавляем колонки в Clients
if not exists (select * from syscolumns where name=''CL_Creator'' and id=object_id(''dbo.Clients''))
	alter table dbo.Clients add [CL_Creator] [int] NULL; -- ведущий менеджер по первой заявке туриста. что если нет?	

if not exists (select * from syscolumns where name=''CL_CreateDate'' and id=object_id(''dbo.Clients''))
	alter table dbo.Clients add [CL_CreateDate] [datetime] NULL; -- дата первой заявки туриста. что если заявок нет?

')
END TRY
BEGIN CATCH
insert into ##errors values ('Clients.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

-- пробуем обновить создателя, у кого не стоит (ведущий менеджер по первой заявке туриста)
-- пробуем обновить дату создания, у кого не стоит (дата создания первой заявки туриста)
create table #clientDogovors ( cl_key int, dg_key int, dg_crdate datetime, dg_owner int) 

insert into #clientDogovors (cl_key, dg_key, dg_crdate, dg_owner) 
(
	select cl_key, dg_key, dg_crdate, dg_owner
	from Clients inner join tbl_Turist on tu_id = CL_KEY inner join tbl_Dogovor with(nolock) on TU_DGKEY = dg_key
	where CL_CreateDate is null or CL_Creator is null
)

create table #data ( clkey int, dg_crdate datetime, dg_owner int) 

insert into #data (clkey, dg_crdate, dg_owner) 
(
	select cl_key, dg_crdate, dg_owner from #clientDogovors where dg_key in (select MIN(dg_key) from #clientDogovors group by cl_key)
)

update Clients set CL_CreateDate = dg_crdate, CL_Creator = dg_owner 
from Clients join #data cd on cl_key = clkey

drop table #clientDogovors
drop table #data

if not exists( select * from dbo.sysobjects  where id = object_id(N''[dbo].[DF_Clients_Creator]'') ) 
	ALTER TABLE [dbo].[Clients] ADD CONSTRAINT [DF_Clients_Creator] DEFAULT (dbo.GetUserId()) FOR [CL_Creator]

if not exists( select * from dbo.sysobjects  where id = object_id(N''[dbo].[DF_Clients_CreateDate]'') ) 
	ALTER TABLE [dbo].[Clients] ADD CONSTRAINT [DF_Clients_CreateDate] DEFAULT (getdate()) FOR [CL_CreateDate]
')
END TRY
BEGIN CATCH
insert into ##errors values ('Clients.sql', error_message())
END CATCH
end

print '############ end of file Clients.sql ################'

print '############ begin of file Communications.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- create table (if not exists)
if not exists (select * from sys.tables where name = ''Communications'')
begin

	CREATE TABLE [dbo].[Communications](
		[CM_Id] [int] IDENTITY(1,1) NOT NULL,
		[CM_DGKey] [int] NOT NULL,
		[CM_PRKey] [int] NOT NULL,
		[CM_LastState] [int] NOT NULL,
		[CM_LastDate] [datetime] NOT NULL,
		[CM_Descriptions] [varchar](255) NOT NULL,
		[CM_Price] [money] NOT NULL,
		[CM_ConfirmationDate] [datetime] NULL,
		[CM_ChangeLevel] [smallint] NULL,
		[CM_ChangeDate] [datetime] NULL,
		[CM_CreateUser] [int] NOT NULL,
		[CM_CreateDate] [datetime] NOT NULL,
		[CM_StatusConfirmed] [smallint] NULL,
		[CM_StatusNotConfirmed] [smallint] NULL,
		[CM_StatusWait] [smallint] NULL,
		[CM_StatusUnknown] [smallint] NULL,
		[CM_CN_ID] [int] NULL,
		[CM_CT_ID] [int] NULL,
		[CM_SumNettoPlan] [money] NULL,
		[CM_SumNettoProvider] [money] NULL,
		[CM_Info] [varchar](1000) NULL,
	 CONSTRAINT [PK_Communications] PRIMARY KEY CLUSTERED 
	(
		[CM_Id] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
	) ON [PRIMARY]

	-- create constraints etc.
	SET ANSI_PADDING OFF

	ALTER TABLE [dbo].[Communications] ADD  DEFAULT (0) FOR [CM_Price]
	ALTER TABLE [dbo].[Communications] ADD  CONSTRAINT [DF_Communications_CM_CreateDate]  DEFAULT (getdate()) FOR [CM_CreateDate]
	ALTER TABLE [dbo].[Communications] ADD  DEFAULT (0) FOR [CM_StatusConfirmed]
	ALTER TABLE [dbo].[Communications] ADD  DEFAULT (0) FOR [CM_StatusNotConfirmed]
	ALTER TABLE [dbo].[Communications] ADD  DEFAULT (0) FOR [CM_StatusWait]
	ALTER TABLE [dbo].[Communications] ADD  DEFAULT (0) FOR [CM_StatusUnknown]
	ALTER TABLE [dbo].[Communications] ADD  DEFAULT (0) FOR [CM_CN_ID]
	ALTER TABLE [dbo].[Communications] ADD  DEFAULT (0) FOR [CM_CT_ID]

	ALTER TABLE [dbo].[Communications]  WITH CHECK ADD  CONSTRAINT [Communications_Partner] FOREIGN KEY([CM_PRKey])
	REFERENCES [dbo].[tbl_Partners] ([PR_KEY])
	ON DELETE CASCADE

	ALTER TABLE [dbo].[Communications] CHECK CONSTRAINT [Communications_Partner]

	ALTER TABLE [dbo].[Communications]  WITH CHECK ADD  CONSTRAINT [FK_Communications_Dogovor] FOREIGN KEY([CM_DGKey])
	REFERENCES [dbo].[tbl_Dogovor] ([DG_Key])
	ON DELETE CASCADE

	ALTER TABLE [dbo].[Communications] CHECK CONSTRAINT [FK_Communications_Dogovor]
	grant select, insert, delete, update on dbo.Communications to public
	
end

')
END TRY
BEGIN CATCH
insert into ##errors values ('Communications.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

-- add column
IF NOT EXISTS (SELECT * FROM dbo.syscolumns WHERE NAME = ''CM_Info'' AND ID = object_id(N''[dbo].[Communications]''))
begin
  alter table Communications add CM_Info varchar(1000)
end
 
-- add index
if not exists (select * from sys.indexes ind join sys.tables tab on ind.object_id = tab.object_id where tab.name = ''Communications'' and ind.name = ''X_Communications'')
begin
	CREATE NONCLUSTERED INDEX [X_Communications] ON [dbo].[Communications]
	(
		[CM_DGKey] ASC,
		[CM_PRKey] ASC
	)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, SORT_IN_TEMPDB = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
end
 
')
END TRY
BEGIN CATCH
insert into ##errors values ('Communications.sql', error_message())
END CATCH
end

print '############ end of file Communications.sql ################'

print '############ begin of file CostOffers.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select 1 from dbo.syscolumns where name = ''CO_DateLastPublish'' and id = object_id(N''[dbo].[CostOffers]''))

	ALTER TABLE [dbo].[CostOffers] DROP COLUMN CO_DateLastPublish

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOffers.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



if not exists (select 1 from dbo.syscolumns where name = ''CO_DatePredActive'' and id = object_id(N''[dbo].[CostOffers]''))

	ALTER TABLE [dbo].[CostOffers] ADD CO_DatePredActive DateTime NULL

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOffers.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



if not exists (select 1 from dbo.syscolumns where name = ''CO_DateActiveForNetto'' and id = object_id(N''[dbo].[CostOffers]''))

	ALTER TABLE [dbo].[CostOffers] ADD CO_DateActiveForNetto DateTime NULL

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOffers.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



if not exists (select 1 from dbo.syscolumns where name = ''CO_CreatedByUserKey'' and id = object_id(N''[dbo].[CostOffers]''))

	ALTER TABLE [dbo].[CostOffers] ADD CO_CreatedByUserKey Int

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOffers.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



if not exists (select 1 from dbo.syscolumns where name = ''CO_DeactivatedByUserKey'' and id = object_id(N''[dbo].[CostOffers]''))

	ALTER TABLE [dbo].[CostOffers] ADD CO_DeactivatedByUserKey Int

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOffers.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



if not exists (select 1 from dbo.syscolumns where name = ''CO_ActivatedByUserKey'' and id = object_id(N''[dbo].[CostOffers]''))

	ALTER TABLE [dbo].[CostOffers] ADD CO_ActivatedByUserKey Int

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOffers.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



if not exists (select 1 from dbo.syscolumns where name = ''CO_PredactivatedByUserKey'' and id = object_id(N''[dbo].[CostOffers]''))

	ALTER TABLE [dbo].[CostOffers] ADD CO_PredactivatedByUserKey Int

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOffers.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



if not exists (select 1 from dbo.syscolumns where name = ''CO_ActivatedForNettoByUserKey'' and id = object_id(N''[dbo].[CostOffers]''))

	ALTER TABLE [dbo].[CostOffers] ADD CO_ActivatedForNettoByUserKey Int

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOffers.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



if not exists (select 1 from dbo.syscolumns where name = ''CO_Rate'' and id = object_id(N''[dbo].[CostOffers]''))

	ALTER TABLE [dbo].[CostOffers] ADD CO_Rate varchar(2) default('''') NOT NULL

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOffers.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



-- удаление внешнего ключа, перед удалением колонки CO_RAKey

declare @nameConstr sysname

declare @sql as nvarchar(max)



declare curs cursor for

select constr.name

	from sys.tables tab

	join sys.sysconstraints ix on ix.id = tab.object_id

	join sys.columns col on ix.colid = col.column_id 

	join sys.default_constraints constr on constr.object_id = col.default_object_id

	where tab.name = ''CostOffers'' and col.name = ''CO_RAKey''

	

open curs

	

fetch next from curs into @nameConstr

	

while @@fetch_status = 0

begin

	set @sql = ''ALTER TABLE [dbo].[CostOffers] DROP CONSTRAINT ['' + @nameConstr + '']''



	exec (@sql)



	fetch next from curs into @nameConstr



end



close curs

deallocate curs

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOffers.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



if exists (select 1 from dbo.syscolumns where name = ''CO_RAKey'' and id = object_id(N''[dbo].[CostOffers]''))

begin

	alter table dbo.CostOffers drop column CO_RAKey 

end

')
END TRY
BEGIN CATCH
insert into ##errors values ('CostOffers.sql', error_message())
END CATCH
end

print '############ end of file CostOffers.sql ################'

print '############ begin of file CountrySettings.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists (select * from sys.columns as col inner join sys.tables as tab on col.object_id = tab.object_id
	where tab.name = ''CountrySettings''
		and col.name = ''CS_Id'')
begin
	alter table CountrySettings add cs_id int not null IDENTITY(1, 1) PRIMARY KEY CLUSTERED 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('CountrySettings.sql', error_message())
END CATCH
end

print '############ end of file CountrySettings.sql ################'

print '############ begin of file CriticalChanges.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF EXISTS (SELECT * FROM dbo.syscolumns WHERE NAME = ''CC_Creator'' AND ID = object_id(N''[dbo].[CriticalChanges]'') AND length < 50)
BEGIN
	ALTER TABLE dbo.CriticalChanges ALTER COLUMN[CC_Creator] VARCHAR(50)		
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('CriticalChanges.sql', error_message())
END CATCH
end

print '############ end of file CriticalChanges.sql ################'

print '############ begin of file Discounts.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS(SELECT TOP 1 1 FROM SYS.COLUMNS COLMN INNER JOIN SYS.TABLES TABL ON COLMN.object_id = TABL.object_id

				    WHERE TABL.NAME = ''Discounts''

				        AND COLMN.NAME = ''DS_FILIAL'')

BEGIN

	ALTER TABLE dbo.Discounts ADD DS_FILIAL INT NOT NULL DEFAULT 0

END



')
END TRY
BEGIN CATCH
insert into ##errors values ('Discounts.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



IF  EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N''[dbo].[DS_TLKEY]'') AND parent_object_id = OBJECT_ID(N''[dbo].[Discounts]''))

BEGIN 

	ALTER TABLE [dbo].[Discounts] DROP CONSTRAINT [DS_TLKEY]

END	

')
END TRY
BEGIN CATCH
insert into ##errors values ('Discounts.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('Discounts.sql', error_message())
END CATCH
end

print '############ end of file Discounts.sql ################'

print '############ begin of file ExcurDictionary.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF EXISTS (SELECT * FROM dbo.syscolumns WHERE NAME = ''ED_Url'' AND ID = object_id(N''[dbo].[ExcurDictionary]''))
BEGIN
	ALTER TABLE [dbo].[ExcurDictionary] ALTER COLUMN [ED_Url] [varchar](999) NULL;  
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('ExcurDictionary.sql', error_message())
END CATCH
end

print '############ end of file ExcurDictionary.sql ################'

print '############ begin of file ExcurtionStartHotels.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists(select 1 from systables where name = ''ExcurtionStartHotels'')
begin

	CREATE TABLE [dbo].[ExcurtionStartHotels](
		[esh_id] [int] IDENTITY(1,1) NOT NULL,
		[esh_edkey] [int] NULL,
		[esh_hdkey] [int] NULL	
	PRIMARY KEY CLUSTERED 
	(
		[esh_id] ASC
	)WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [PRIMARY]
	) ON [PRIMARY]

	grant select, insert, delete, update on dbo.ExcurtionStartHotels to public

end

')
END TRY
BEGIN CATCH
insert into ##errors values ('ExcurtionStartHotels.sql', error_message())
END CATCH
end

print '############ end of file ExcurtionStartHotels.sql ################'

print '############ begin of file HistoryCost.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF EXISTS (SELECT * FROM dbo.syscolumns WHERE NAME = ''HC_WHO'' AND ID = object_id(N''[dbo].[HistoryCost]''))
BEGIN
	ALTER TABLE dbo.HistoryCost ALTER COLUMN HC_WHO varchar(50) NULL
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('HistoryCost.sql', error_message())
END CATCH
end

print '############ end of file HistoryCost.sql ################'

print '############ begin of file HistoryPartner.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF EXISTS (SELECT * FROM dbo.syscolumns WHERE NAME = ''HP_Who'' AND ID = object_id(N''[dbo].[HistoryPartner]''))
BEGIN
	ALTER TABLE dbo.HistoryPartner ALTER COLUMN HP_Who char(50) NULL
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('HistoryPartner.sql', error_message())
END CATCH
end

print '############ end of file HistoryPartner.sql ################'

print '############ begin of file HistoryQuote.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF EXISTS (SELECT * FROM dbo.syscolumns WHERE NAME = ''HQ_WHO'' AND ID = object_id(N''[dbo].[HistoryQuote]''))
BEGIN
	ALTER TABLE dbo.HistoryQuote ALTER COLUMN HQ_WHO varchar(50) NULL
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('HistoryQuote.sql', error_message())
END CATCH
end

print '############ end of file HistoryQuote.sql ################'

print '############ begin of file HotelRooms.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = ''HotelRooms'')

BEGIN

	CREATE TABLE [dbo].[HotelRooms](
		[HR_KEY] [int] NOT NULL,
		[HR_RMKEY] [int] NOT NULL,
		[HR_RCKEY] [int] NOT NULL,
		[HR_MAIN] [smallint] NOT NULL,
		[HR_AGEFROM] [smallint] NULL,
		[HR_AGETO] [smallint] NULL,
		[HR_ACKEY] [int] NOT NULL,
		[HR_StdKey] [char](10) NULL,
		[HR_CINNUM] [int] NULL,
		[HR_DoNotGetILCosts] [smallint] NULL,
		[HR_Unicode] [varchar](125) NULL,
		CONSTRAINT [PK__HOTELROOMS__3493CFA7] PRIMARY KEY CLUSTERED 
		(
			[HR_KEY] ASC
		)
		WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 90) ON [PRIMARY]
	) ON [PRIMARY]

	ALTER TABLE [dbo].[HotelRooms]  WITH NOCHECK ADD  CONSTRAINT [HR_ACKey] FOREIGN KEY([HR_ACKEY])
	REFERENCES [dbo].[Accmdmentype] ([AC_KEY])
	ON DELETE CASCADE

	ALTER TABLE [dbo].[HotelRooms] CHECK CONSTRAINT [HR_ACKey]

	ALTER TABLE [dbo].[HotelRooms]  WITH CHECK ADD  CONSTRAINT [HR_CINNum] FOREIGN KEY([HR_CINNUM])
	REFERENCES [dbo].[CostsInsertNumber] ([CIN_Num])
	ON DELETE CASCADE

	ALTER TABLE [dbo].[HotelRooms] CHECK CONSTRAINT [HR_CINNum]

	ALTER TABLE [dbo].[HotelRooms]  WITH NOCHECK ADD  CONSTRAINT [HR_RCKEY] FOREIGN KEY([HR_RCKEY])
	REFERENCES [dbo].[RoomsCategory] ([RC_KEY])
	ON DELETE CASCADE

	ALTER TABLE [dbo].[HotelRooms] CHECK CONSTRAINT [HR_RCKEY]

	ALTER TABLE [dbo].[HotelRooms]  WITH NOCHECK ADD  CONSTRAINT [HR_RMKEY] FOREIGN KEY([HR_RMKEY])
	REFERENCES [dbo].[Rooms] ([RM_KEY])
	ON DELETE CASCADE

	ALTER TABLE [dbo].[HotelRooms] CHECK CONSTRAINT [HR_RMKEY]

END

')
END TRY
BEGIN CATCH
insert into ##errors values ('HotelRooms.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

GRANT SELECT, INSERT, UPDATE, DELETE ON [dbo].[HotelRooms] TO PUBLIC

')
END TRY
BEGIN CATCH
insert into ##errors values ('HotelRooms.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

-- раньше колонка HR_ACKEY была nullable, сделаем её не позволяющей null
if exists (select * from sys.columns col
left join sys.tables tab on col.object_id = tab.object_id
where tab.name = ''HotelRooms''
	and col.name = ''HR_ACKEY''
	and col.is_nullable = 1)
begin
	delete from HotelRooms
	where hr_ackey is null

	declare @sql as nvarchar(max)
	set @sql = ''alter table HotelRooms alter column hr_ackey int not null''
	
	declare @columns as ListNvarcharValue
	insert into @columns values (''hr_ackey'')

	exec RecreateDependentObjects ''HotelRooms'', @columns, @sql

end
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('HotelRooms.sql', error_message())
END CATCH
end

print '############ end of file HotelRooms.sql ################'

print '############ begin of file HotelTypes.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from sys.columns col left join sys.tables tab on col.object_id = tab.object_id where tab.name = ''HotelTypes'' and col.name = ''htt_namelat'' and col.is_nullable = 1)
begin
	ALTER TABLE HotelTypes DROP COLUMN htt_namelat
end

if exists (select * from sys.columns col left join sys.tables tab on col.object_id = tab.object_id where tab.name = ''HotelTypes'' and col.name = ''htt_cssClass'' and col.is_nullable = 1)
begin
	ALTER TABLE HotelTypes DROP COLUMN htt_cssClass
end

if exists (select * from sys.columns col left join sys.tables tab on col.object_id = tab.object_id where tab.name = ''HotelTypes'' and col.name = ''htt_imageName'' and col.is_nullable = 1)
begin
	ALTER TABLE HotelTypes DROP COLUMN htt_imageName
end
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('HotelTypes.sql', error_message())
END CATCH
end

print '############ end of file HotelTypes.sql ################'

print '############ begin of file Keys.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists(select 1 from sys.tables where name = ''Keys'')
begin
CREATE TABLE [dbo].[Keys](
	[KEY_TABLE] [varchar](40) NOT NULL,
	[ID] [int] NOT NULL
	) ON [PRIMARY]
end
else 
begin
	DECLARE @id int
	SELECT @id = max(US_Key) FROM DUP_USER

	if @id is null
		set @id = 0
	
	if not exists(select 1 from Keys WHERE KEY_TABLE = ''Dup_User'')
	begin
		insert into Keys (KEY_TABLE, ID) values (''Dup_User'', @id)
	end
	ELSE
	BEGIN
		UPDATE Keys Set ID = @id
		WHERE KEY_TABLE = ''Dup_User''
	END	
end

')
END TRY
BEGIN CATCH
insert into ##errors values ('Keys.sql', error_message())
END CATCH
end

print '############ end of file Keys.sql ################'

print '############ begin of file Key_HotelTypes.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists(select top 1 1 from sys.objects where name=''Key_HotelTypes'' and type=''U'')
begin
	CREATE TABLE [dbo].[Key_HotelTypes]([ID] [int] NULL) ON [PRIMARY]
	
	declare @maxId int
	SELECT @maxId=IDENT_CURRENT(TABLE_NAME) FROM INFORMATION_SCHEMA.TABLES WHERE OBJECTPROPERTY(OBJECT_ID(TABLE_NAME), ''TableHasIdentity'') = 1 AND TABLE_TYPE = ''BASE TABLE'' AND TABLE_NAME = ''HotelTypes''
	print @maxId
	insert into Key_HotelTypes(ID) values(@maxId)
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('Key_HotelTypes.sql', error_message())
END CATCH
end

print '############ end of file Key_HotelTypes.sql ################'

print '############ begin of file LicenseData.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists(select 1 from systables where name = ''LicenseData'')
begin
	create table [dbo].[LicenseData](
	[LD_Key] [int] identity(1,1) not null, 
	[LD_Data] [varbinary](max) not null, 
	[LD_UpdateDate] [datetime] not null, 
	CONSTRAINT [PK_LicenseData] PRIMARY KEY CLUSTERED (LD_Key ASC)) ON [PRIMARY]
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('LicenseData.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant select, insert, delete, update on dbo.LicenseData to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('LicenseData.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

use master grant view server state to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('LicenseData.sql', error_message())
END CATCH
end

print '############ end of file LicenseData.sql ################'

print '############ begin of file MasterTourServiceHosts.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[MasterTourServiceHosts]'') AND type in (N''U''))

BEGIN

	create table MasterTourServiceHosts

	(

		MTS_Key int not null primary key identity(1, 1),

		MTS_URL nvarchar(500) not null,

		MTS_Name nvarchar(2000) not null,

		MTS_Priority int not null default(0),

		MTS_UpdateTime datetime not null

	)

END

')
END TRY
BEGIN CATCH
insert into ##errors values ('MasterTourServiceHosts.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



grant select, insert, update, delete on MasterTourServiceHosts to public

')
END TRY
BEGIN CATCH
insert into ##errors values ('MasterTourServiceHosts.sql', error_message())
END CATCH
end

print '############ end of file MasterTourServiceHosts.sql ################'

print '############ begin of file ObjectAliases.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM ObjectAliases WHERE OA_ID = 310008)
BEGIN
	INSERT INTO ObjectAliases (OA_ID, OA_ALIAS, OA_NAME, OA_NAMELAT, OA_TABLEID)
	VALUES (310008, '''', ''Платежная система Epay'', ''Payment system Epay'', 63)
END

IF NOT EXISTS (SELECT 1 FROM ObjectAliases WHERE OA_ID = 310009)
BEGIN
	INSERT INTO ObjectAliases (OA_ID, OA_ALIAS, OA_NAME, OA_NAMELAT, OA_TABLEID)
	VALUES (310009, '''', ''Платежная система Uniteller'', ''Payment system Uniteller'', 63)
END

IF NOT EXISTS (SELECT 1 FROM ObjectAliases WHERE OA_ID = 310010)
BEGIN
	INSERT INTO ObjectAliases (OA_ID, OA_ALIAS, OA_NAME, OA_NAMELAT, OA_TABLEID)
	VALUES (310010, '''', ''Платежная система Облако'', ''Payment system Oblako'', 63)
END


IF NOT EXISTS (SELECT 1 FROM ObjectAliases WHERE OA_ID = 310011)
BEGIN
	INSERT INTO ObjectAliases (OA_ID, OA_ALIAS, OA_NAME, OA_NAMELAT, OA_TABLEID)
	VALUES (310011, '''', ''Платежная система Contact'', ''Payment system Contact'', 63)
END


IF NOT EXISTS (SELECT 1 FROM ObjectAliases WHERE OA_ID = 310012)
BEGIN
	INSERT INTO ObjectAliases (OA_ID, OA_ALIAS, OA_NAME, OA_NAMELAT, OA_TABLEID)
	VALUES (310012, '''', ''Платежная система Appex'', ''Payment system Appex'', 63)
END

IF NOT EXISTS (SELECT 1 FROM ObjectAliases WHERE OA_ID = 310013)
BEGIN
	INSERT INTO ObjectAliases (OA_ID, OA_ALIAS, OA_NAME, OA_NAMELAT, OA_TABLEID)
	VALUES (310013, '''', ''Платежная система Сбербанк'', ''Payment system Sberbank'', 63)
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('ObjectAliases.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM ObjectAliases WHERE OA_ID = 310014)
BEGIN
	INSERT INTO ObjectAliases (OA_ID, OA_ALIAS, OA_NAME, OA_NAMELAT, OA_TABLEID)
	VALUES (310014, '''', ''Уникальный номер заказа в платежных системах'', ''PaymentSystems_Unique_orderId'', 63)
END
ELSE BEGIN
	UPDATE ObjectAliases
	SET OA_NAME = ''Уникальный номер заказа в платежных системах'', OA_NAMELAT = ''PaymentSystems_Unique_orderId''
	WHERE OA_ID = 310014 and OA_TABLEID = 63
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('ObjectAliases.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM ObjectAliases WHERE OA_ID = 310015)
BEGIN
	INSERT INTO ObjectAliases (OA_ID, OA_ALIAS, OA_NAME, OA_NAMELAT, OA_TABLEID)
	VALUES (310015, '''', ''URL адрес для оплаты в платежной системе Сбербанк'', ''PaymentSystem_Sberbank_formUrl'', 63)
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('ObjectAliases.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM ObjectAliases WHERE OA_ID = 310016)
BEGIN
	INSERT INTO ObjectAliases (OA_ID, OA_ALIAS, OA_NAME, OA_NAMELAT, OA_TABLEID)
	VALUES (310016, '''', ''Сбербанк. Терминалы'', ''SberbankTerminals'', 63)
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('ObjectAliases.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM ObjectAliases WHERE OA_ID = 310017)
BEGIN
	INSERT INTO ObjectAliases (OA_ID, OA_ALIAS, OA_NAME, OA_NAMELAT, OA_TABLEID)
	VALUES (310017, '''', ''Платежная система LiqPay'', ''Payment system LiqPay'', 63)
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('ObjectAliases.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM ObjectAliases WHERE OA_ID = 310020)
BEGIN
	INSERT INTO ObjectAliases (OA_ID, OA_ALIAS, OA_NAME, OA_NAMELAT, OA_TABLEID)
	VALUES (310020, '''', ''Альфабанк. Терминалы'', ''AlfabankFinanceTerminals'', 63)
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('ObjectAliases.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM ObjectAliases WHERE OA_ID = 320001)
BEGIN
	INSERT INTO ObjectAliases (OA_ID, OA_ALIAS, OA_NAME, OA_NAMELAT, OA_TABLEID)
	VALUES (320001, ''DL_RemoteReservationId'', ''Номер бронирования в удаленной системе'', ''Remote system book number'', 60)
END
ELSE BEGIN
	UPDATE ObjectAliases
	SET OA_NAME = ''Номер бронирования в удаленной системе''
	WHERE OA_ID = 320001 and OA_TABLEID = 60
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('ObjectAliases.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM ObjectAliases WHERE OA_ID = 320002)
BEGIN
	INSERT INTO ObjectAliases (OA_ID, OA_ALIAS, OA_NAME, OA_NAMELAT, OA_TABLEID)
	VALUES (320002, ''TU_RemoteReservationId'', ''Номер бронирования в удаленной системе'', ''Remote system book number'', 37)
END
ELSE BEGIN
	UPDATE ObjectAliases
	SET OA_NAME = ''Номер бронирования в удаленной системе''
	WHERE OA_ID = 320002 and OA_TABLEID = 37
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('ObjectAliases.sql', error_message())
END CATCH
end

print '############ end of file ObjectAliases.sql ################'

print '############ begin of file ObjectTypes.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from ObjectTypes where ot_id = 1001 and ot_code = ''ManagerGroups'')
	insert into ObjectTypes	values (1001, ''ManagerGroups'', ''Группы менеджеров по туру'', NULL, NULL)
')
END TRY
BEGIN CATCH
insert into ##errors values ('ObjectTypes.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select 1 from ObjectTypes where ot_id = 1003 and ot_code = ''DepositPayments'')
	insert into ObjectTypes	values (1003, ''DepositPayments'', ''Депозитные платежи'', NULL, NULL)
')
END TRY
BEGIN CATCH
insert into ##errors values ('ObjectTypes.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select 1 from ObjectTypes where ot_id = 1004 and ot_code = ''TransferCityMapping'')
	insert into ObjectTypes	values (1004, ''TransferCityMapping'', ''Привязка трансферов к городам'', NULL, NULL)
')
END TRY
BEGIN CATCH
insert into ##errors values ('ObjectTypes.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from ObjectTypes where ot_id = 1005 and ot_code = ''RemoteProviders'')
	insert into ObjectTypes	values (1005, ''RemoteProviders'', ''Удаленные поставщики'', NULL, NULL)
')
END TRY
BEGIN CATCH
insert into ##errors values ('ObjectTypes.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('ObjectTypes.sql', error_message())
END CATCH
end

print '############ end of file ObjectTypes.sql ################'

print '############ begin of file PaymentDetails.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--<VERSION>9.2.21</VERSION>
--<DATE>2014-01-14</DATE>
if not exists (select 1 from dbo.syscolumns where name = ''PD_Signature'' and id = object_id(N''[dbo].[PaymentDetails]''))
	alter table dbo.PaymentDetails add PD_Signature varbinary(max)
')
END TRY
BEGIN CATCH
insert into ##errors values ('PaymentDetails.sql', error_message())
END CATCH
end

print '############ end of file PaymentDetails.sql ################'

print '############ begin of file Rates.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists (select 1 from dbo.syscolumns where name = ''RA_ShowInSearch'' and id = object_id(N''[dbo].[Rates]''))
BEGIN
	ALTER TABLE [dbo].Rates ADD RA_ShowInSearch smallint NOT NULL DEFAULT(0)
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('Rates.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

update [dbo].Rates SET RA_ShowInSearch = 1 WHERE RA_National = 1 OR RA_MAIN = 1

')
END TRY
BEGIN CATCH
insert into ##errors values ('Rates.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

update [dbo].Rates set RA_ISOCode = ''RUB'' where RA_ISOCode = ''RUR''

')
END TRY
BEGIN CATCH
insert into ##errors values ('Rates.sql', error_message())
END CATCH
end

print '############ end of file Rates.sql ################'

print '############ begin of file Service.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''SV_ISROUTE'' and id = object_id(N''[dbo].[Service]''))
	ALTER TABLE [dbo].Service ADD SV_ISROUTE SMALLINT NOT NULL DEFAULT(0)	
')
END TRY
BEGIN CATCH
insert into ##errors values ('Service.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
UPDATE Service SET SV_ISROUTE = 1 WHERE SV_KEY = 2
UPDATE Service SET SV_ISROUTE = 1 WHERE SV_KEY = 1
UPDATE Service SET SV_ISROUTE = 1 WHERE SV_KEY = 3
UPDATE Service SET SV_ISROUTE = 1 WHERE SV_KEY = 14
UPDATE Service set sv_isduration = 0 where sv_isduration is null

')
END TRY
BEGIN CATCH
insert into ##errors values ('Service.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM Service WHERE SV_KEY=12 AND SV_Code=''ADFLIGHT'')
BEGIN
	INSERT INTO Service (SV_KEY,SV_NAME,SV_NAMELAT,SV_TYPE,SV_CONTROL, SV_ISSUBCODE1, SV_StdKey,SV_Code,SV_IsDuration,SV_UseManualInput)
	VALUES (12,''Доплаты к авиаперелетам'',''Add.service in flight'',0,0, 1, ''addFlight'',''ADFLIGHT'',0,0);
END
ELSE
	BEGIN
		
		UPDATE Service SET SV_ISSUBCODE1 = 1 WHERE SV_KEY = 12 AND ISNULL(SV_ISSUBCODE1, 0) = 0
		UPDATE Service SET SV_NAMELAT = ''Add.service in flight'', SV_StdKey = ''addFlight'' WHERE SV_KEY = 12
	END
')
END TRY
BEGIN CATCH
insert into ##errors values ('Service.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM Service WHERE SV_KEY=13 AND SV_Code=''ADHOTEL'')
BEGIN
	INSERT INTO Service (SV_KEY,SV_NAME,SV_NAMELAT,SV_TYPE,SV_CONTROL, SV_ISSUBCODE1, SV_StdKey,SV_Code,SV_IsDuration,SV_UseManualInput)
	VALUES (13,''Доплаты к отелям'',''Add.service in hotel'',0,0, 1, ''addHotel'',''ADHOTEL'',0,0);
END

IF NOT EXISTS (SELECT 1 FROM Service WHERE SV_KEY=14 AND SV_Code=''BUS'')
BEGIN
	INSERT INTO Service (SV_KEY,SV_NAME,SV_NAMELAT,SV_TYPE,SV_CONTROL, SV_ISCITY, SV_ISSUBCODE1, SV_ISSUBCODE2, SV_ROUNDBRUTTO, SV_StdKey,SV_Code,SV_IsDuration,SV_UseManualInput, SV_QUOTED)
	VALUES (14,''Автобусный переезд'',''Bus transfer'',1,2,1,1,1,0,''bus'',''BUS'',1,0,0);
END

IF NOT EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''SV_ISPARTNERBASEDON'' AND id = OBJECT_ID(N''[dbo].[Service]''))

	BEGIN

		ALTER TABLE [dbo].Service ADD SV_ISPARTNERBASEDON SMALLINT NOT NULL DEFAULT(0)	
		
	END		

')
END TRY
BEGIN CATCH
insert into ##errors values ('Service.sql', error_message())
END CATCH
end

print '############ end of file Service.sql ################'

print '############ begin of file ServiceByDate.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
-- add index
if not exists (select * from sys.indexes ind join sys.tables tab on ind.object_id = tab.object_id where tab.name = ''ServiceByDate'' and ind.name = ''X_SD_RLId'')
begin

	CREATE NONCLUSTERED INDEX [X_SD_RLId] ON [dbo].[ServiceByDate] 
	(
		[SD_RLID] ASC
	)
	WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, SORT_IN_TEMPDB = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON, FILLFACTOR = 80) ON [PRIMARY]

end
')
END TRY
BEGIN CATCH
insert into ##errors values ('ServiceByDate.sql', error_message())
END CATCH
end

print '############ end of file ServiceByDate.sql ################'

print '############ begin of file Ship.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''SH_CNKey'' and id = object_id(N''[dbo].[Ship]''))

	ALTER TABLE [dbo].Ship ADD SH_CNKey INT NULL

	

')
END TRY
BEGIN CATCH
insert into ##errors values ('Ship.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('Ship.sql', error_message())
END CATCH
end

print '############ end of file Ship.sql ################'

print '############ begin of file SpecialsHistory.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF EXISTS (SELECT * FROM dbo.syscolumns WHERE NAME = ''SH_UserName'' AND ID = object_id(N''[dbo].[SpecialsHistory]''))
BEGIN
	ALTER TABLE dbo.SpecialsHistory ALTER COLUMN SH_UserName varchar(50) NULL
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('SpecialsHistory.sql', error_message())
END CATCH
end

print '############ end of file SpecialsHistory.sql ################'

print '############ begin of file SystemSettings.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''SystemSettings''))

begin

	alter table SystemSettings DISABLE CHANGE_TRACKING

end

')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if exists (select * from sys.sysobjects where name like ''FK_CS_SSParmName'')

begin

	alter table [dbo].[CountrySettings]

	drop constraint [FK_CS_SSParmName]

end

')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if exists (select * from sys.sysobjects where name like ''PK_SystemSettings'' and xtype = ''PK'')

begin

	alter table [dbo].[SystemSettings]

	drop constraint [PK_SystemSettings]

end

')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

alter table [dbo].[SystemSettings] 

add constraint [PK_SystemSettings] primary key ([SS_ID])

')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select * from sys.sysobjects where name like ''UQ_SystemSettings'' and xtype = ''UQ'')

begin

	alter table [dbo].[SystemSettings]

	add constraint [UQ_SystemSettings] unique ([SS_ParmName])

end

')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select top 1 1 from  sys.change_tracking_tables where object_id = OBJECT_ID(''SystemSettings''))


begin

	alter table SystemSettings ENABLE CHANGE_TRACKING


end

')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings.sql', error_message())
END CATCH
end

print '############ end of file SystemSettings.sql ################'

print '############ begin of file SystemSettings_constants.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS (SELECT 1 FROM SYSTEMSETTINGS WHERE SS_PARMNAME=''NewSetToQuota'')
BEGIN
	INSERT INTO SYSTEMSETTINGS(SS_PARMNAME,SS_PARMVALUE, SS_NAME)
	VALUES (''NewSetToQuota'', ''1'', ''Проверка квот через сервисы MTS'')
END
ELSE
BEGIN
	update SystemSettings
	set ss_parmvalue = 1
	where SS_PARMNAME=''NewSetToQuota''
END

IF NOT EXISTS (SELECT 1 FROM SYSTEMSETTINGS WHERE SS_PARMNAME=''SYSQuotaCheckAlgorithm'')
BEGIN
	INSERT INTO SYSTEMSETTINGS(SS_PARMNAME,SS_PARMVALUE, SS_NAME)
	VALUES (''SYSQuotaCheckAlgorithm'', ''1'', ''Новый алгоритм проверки квот'')
END
ELSE
BEGIN
	update SystemSettings
	set ss_parmvalue = 1
	where SS_PARMNAME=''SYSQuotaCheckAlgorithm''
END

IF NOT EXISTS (SELECT 1 FROM SYSTEMSETTINGS WHERE SS_PARMNAME=''NewCalculationCosts'')
BEGIN
	INSERT INTO SYSTEMSETTINGS(SS_PARMNAME,SS_PARMVALUE, SS_NAME)
	VALUES (''NewCalculationCosts'', ''1'', ''Новый механизм расчета цены'')
END
ELSE
BEGIN
	update SystemSettings
	set ss_parmvalue = 1
	where SS_PARMNAME=''NewCalculationCosts''
END

IF NOT EXISTS (SELECT 1 FROM SYSTEMSETTINGS WHERE SS_PARMNAME=''NewReCalculatePrice'')
BEGIN
	INSERT INTO SYSTEMSETTINGS(SS_PARMNAME,SS_PARMVALUE, SS_NAME)
	VALUES (''NewReCalculatePrice'', ''1'', ''Новый механизм ценообразования'')
END
ELSE
BEGIN
	update SystemSettings
	set ss_parmvalue = 1
	where SS_PARMNAME=''NewReCalculatePrice''
END

IF NOT EXISTS (SELECT 1 FROM SYSTEMSETTINGS WHERE SS_PARMNAME=''SYSStatusToQuotaTransfer'')
BEGIN
	INSERT INTO SYSTEMSETTINGS(SS_PARMNAME,SS_PARMVALUE, SS_NAME)
	VALUES (''SYSStatusToQuotaTransfer'', null, ''Значения статусов путевок, которые подлежат пересадке в приоритетные квоты'')
END
ELSE
BEGIN
	update SystemSettings
	set ss_parmvalue = null
	where SS_PARMNAME=''SYSStatusToQuotaTransfer''
END

IF NOT EXISTS (SELECT 1 FROM SYSTEMSETTINGS WHERE SS_PARMNAME=''SYSServiceKeyToTransfer'')
BEGIN
	INSERT INTO SYSTEMSETTINGS(SS_PARMNAME,SS_PARMVALUE, SS_NAME)
	VALUES (''SYSServiceKeyToTransfer'', null, ''Классы услуг для которых будет работать пересадка в приоритетные квоты'')
END
ELSE
BEGIN
	update SystemSettings
	set ss_parmvalue = null
	where SS_PARMNAME=''SYSServiceKeyToTransfer''
END

IF NOT EXISTS (SELECT 1 FROM SYSTEMSETTINGS WHERE SS_PARMNAME=''OnlineFindByAdultChild'')
BEGIN
	INSERT INTO SYSTEMSETTINGS(SS_PARMNAME,SS_PARMVALUE, SS_NAME)
	VALUES (''OnlineFindByAdultChild'', ''1'', ''Поиск по осн./доп. местам (0) или взр./дет. местам (1)'')
END
ELSE
BEGIN
	update SystemSettings
	set ss_parmvalue = 1
	where SS_PARMNAME=''OnlineFindByAdultChild''
END

if not exists (select * from SystemSettings where ss_parmname = ''MaxTourDuration'')
begin
	INSERT INTO SYSTEMSETTINGS(SS_PARMNAME,SS_PARMVALUE, SS_NAME)
	VALUES (''MaxTourDuration'', ''40'', ''Максимальная продолжительность тура в Оформлении клиентов, в Программе туров, в Поиске (при отключенных актуальных фильтрах)'')
end

if not exists (select * from SystemSettings where ss_parmname = ''SYSCheckChildAge'')
begin
	INSERT INTO SYSTEMSETTINGS(SS_PARMNAME,SS_PARMVALUE, SS_NAME)
	VALUES (''SYSCheckChildAge'', ''16'', ''Максимальный возраст ребенка'')
end
else
begin
	update SYSTEMSETTINGS
	set SS_NAME = ''Максимальный возраст ребенка''
	where ss_parmname = ''SYSCheckChildAge''
	
	if exists (select * from SystemSettings where ss_parmname = ''SYSCheckChildAge'' and SS_ParmValue = ''0'')
	begin
		update SYSTEMSETTINGS
		set SS_ParmValue = ''16''
		where ss_parmname = ''SYSCheckChildAge''
	end
end

if not exists (select 1 from SystemSettings where SS_ParmName=''SYSDogovorSignStartDate'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue, SS_Name)
	values (''SYSDogovorSignStartDate'', '''', ''Дата, с которой проверяем подписи платежей'')
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


if not exists (select 1 from SystemSettings where SS_ParmName=''signDogovorsPayInfo'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue)
	values (''signDogovorsPayInfo'', ''1'')
end
else
begin
	update SYSTEMSETTINGS
	set SS_ParmValue = ''1''
	where ss_parmname = ''signDogovorsPayInfo''
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from SystemSettings where SS_ParmName=''SYSShowCitizenAuthTourist'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue, SS_Name)
	values (''SYSShowCitizenAuthTourist'', ''0'', ''Запрашивать гражданство при регистрации частника'')
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM SystemSettings WHERE SS_ParmName=''ForwardMonthCount'')
BEGIN
	INSERT INTO SystemSettings(SS_ParmName, SS_ParmValue, SS_Name)
	VALUES (''ForwardMonthCount'', ''6'', ''На сколько месяцев вперёд выдавать в поиске туры в актуальных фильтрах'')
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM SystemSettings WHERE SS_ParmName=''ForwardAviaDaysCount'')
BEGIN
	INSERT INTO SystemSettings(SS_ParmName, SS_ParmValue, SS_Name)
	VALUES (''ForwardAviaDaysCount'', ''30'', ''Максимальная продолжительность от вылета до возврата для поиска авиабилетов'')
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from SystemSettings where SS_ParmName=''SYSNoPlacesQuotaResult'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue, SS_Name)
	values (''SYSNoPlacesQuotaResult'', ''1'', ''Отображать «Нет мест», если закончились свободные места в квоте, иначе отображать «Запрос»'')
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from SystemSettings where SS_ParmName=''SYSShowFewCountPlaces'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue, SS_Name)
	values (''SYSShowFewCountPlaces'', ''0'', ''Отображать числовое значение оставшихся мест, в случае, когда достигнуто значение «Мало»'')
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from SystemSettings where SS_ParmName=''SYSShowBusTransferPlaces'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue, SS_Name)
	values (''SYSShowBusTransferPlaces'', ''0'', ''Отображать фильтр наличие мест на автобусный переезд в поиске'')
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from SystemSettings where SS_ParmName=''SYSUseBusSeatChecks'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue, SS_Name)
	values (''SYSUseBusSeatChecks'', ''1'', ''Включить правила рассадки пассажиров для автобусных переездов'')
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from SystemSettings where SS_ParmName=''SYSTourSearchMode'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue, SS_Name)
	values (''SYSTourSearchMode'', ''0'', ''В чем осуществлять поиск на главной странице'')
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from SystemSettings where SS_ParmName=''SYSUseTransferSeatChecks'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue, SS_Name)
	values (''SYSUseTransferSeatChecks'', ''0'', ''Включить правила рассадки пассажиров для трансферов'')
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from SystemSettings where SS_ParmName=''SYSShowCitiesFilter'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue, SS_Name)
	values (''SYSShowCitiesFilter'', ''0'', ''Отображать фильтр по городам на главной странице поиска'')
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from SystemSettings where SS_ParmName=''SYSCheckRealCourses'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue, SS_Name)
	values (''SYSCheckRealCourses'', ''1'', ''Поиск. Проверка наличия курсов валют'')
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from SystemSettings where SS_ParmName=''PartnerAgreementRelevance'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue, SS_Name)
	values (''PartnerAgreementRelevance'', ''0'', ''Проверять наличие активного договора при авторизации ТА'')
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

update SystemSettings set ss_parmvalue = ''0'' where ss_parmname = ''SYSAllowInfantBooking''


if not exists(select top 1 1 from SystemSettings where SS_ParmName=''ImagesFolderPath'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue,SS_Name) values(''ImagesFolderPath'','''',''Папка для хранения изображений'')
end

if not exists(select top 1 1 from SystemSettings where SS_ParmName=''UseFastSearchAlgoritm'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue,SS_Name) values(''UseFastSearchAlgoritm'',''0'',''Использовать быстрый алгоритм поиска'')
end

if not exists(select top 1 1 from SystemSettings where SS_ParmName=''UseApplyFiltersButton'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue,SS_Name) values(''UseApplyFiltersButton'',''0'',''Отображать кнопку применить фильтры'')
end

if not exists(select top 1 1 from SystemSettings where SS_ParmName=''AutoSearchFiltersTimeout'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue,SS_Name) values(''AutoSearchFiltersTimeout'',''1'',''Время, через которое происходит автоматический поиск'')
end

if not exists(select top 1 1 from SystemSettings where SS_ParmName=''SYSAdvertisement'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue,SS_Name) values(''SYSAdvertisement'',''0'',''Источник рекламы при бронировании онлайн'')
end

IF NOT EXISTS (SELECT 1 FROM SYSTEMSETTINGS WHERE SS_PARMNAME=''SYSSpecialsUrl'')
BEGIN
	/* Настройка для импорта акций из интерлука */
	INSERT INTO SYSTEMSETTINGS(SS_PARMNAME,SS_PARMVALUE, SS_NAME) VALUES (''SYSSpecialsUrl'', '''', ''URL адрес к плагину акций.'')
END

if not exists(select top 1 1 from SystemSettings where SS_ParmName=''MaxSearchDatesCountInAPI'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue,SS_Name) values(''MaxSearchDatesCountInAPI'',''0'',''Максимальное количество дат, которое будет обрабатываться в API для поисковых систем'')
end

if not exists(select top 1 1 from SystemSettings where SS_ParmName=''MaxSearchDatesCountClient'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue,SS_Name) values(''MaxSearchDatesCountClient'',''0'',''Максимальное количество дат, которое будет обрабатываться в клиенте поиска'')
end

if not exists(select top 1 1 from SystemSettings where SS_ParmName=''MaxDurationsCountClient'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue,SS_Name) values(''MaxDurationsCountClient'',''0'',''Максимальное количество продолжительностей, которое будет обрабатываться в клиенте поиска'')
end

if not exists(select top 1 1 from SystemSettings where SS_ParmName=''MaxDurationsCountInAPI'')
begin
	insert into SystemSettings(SS_ParmName,SS_ParmValue,SS_Name) values(''MaxDurationsCountInAPI'',''0'',''Максимальное количество продолжительностей, которое будет обрабатываться в API для поисковых систем'')
end

if not exists(select 1 from dbo.SystemSettings where SS_ParmName = ''UsePansionGlobalCode'')
begin
	insert into dbo.SystemSettings(SS_ParmName, SS_ParmValue, SS_Name)
	values(''UsePansionGlobalCode'', ''0'', ''Использовать глобальные коды питаний в поиске'');
end

if not exists(select 1 from dbo.SystemSettings where SS_ParmName = ''UseHotelCatGlobalCode'') begin
	insert into dbo.SystemSettings(SS_ParmName, SS_ParmValue, SS_Name)
	values(''UseHotelCatGlobalCode'', ''0'', ''Использовать глобальные коды категорий отелей в поиске'');
end

')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


/**************************************************/
/*************begin AMO CRM************************/
/**************************************************/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_UserLogin''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''логин пользователя для отсылки запросов в систему АМО СРМ''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,'''',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_Subdomain''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''поддомен клиентского модуля АМО СРМ''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,'''',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_UserHash''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''соответствующий хеш-пароль, который указан в профиле клиентского АМО СРМ''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,'''',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_IdStatus''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''id статуса, под которым будут приходить сделки в CRM, берется из раздела custom_fields->leads_statuses''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,''0'',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_IdOrderNumber''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''id поля Номер заказа из раздела custom_fields->leads''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,''0'',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_IdRoistat''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''id поля roistatID из раздела custom_fields->leads''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,''0'',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_IdCheckIn''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''id поля Дата заезда из раздела custom_fields->leads''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,''0'',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_IdCheckOut''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''id поля Дата выезда из раздела custom_fields->leads''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,''0'',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_IdDuration''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''id поля Длительность из раздела custom_fields->leads''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,''0'',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_IdCountry''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''id поля Страна из раздела custom_fields->leads''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,''0'',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_IdPurchaser''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''id поля Покупатель из раздела custom_fields->leads''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,''0'',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_IdTourName''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''id поля Название тура из раздела custom_fields->leads''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,''0'',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_IdTouristsCount''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''id поля Кол-во людей из раздела custom_fields->leads''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,''0'',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_IdEmail''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''id поля Email из раздела custom_fields->contacts''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,''0'',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_Email''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''любой enum для поля Email из раздела custom_fields->contacts, например OTHER''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,'''',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_IdPhone''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''id поля Телефон из раздела custom_fields->contacts''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,''0'',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
/***AMO CRM***/
declare @AMO_CRM_SettingName nvarchar(200) = ''AMO_CRM_Phone''
declare @AMO_CRM_SettingDesc nvarchar(200) = ''любой enum для поля Телефон из раздела custom_fields->contacts, например OTHER''

if not exists(select 1 from [SystemSettings] where [SS_ParmName] = @AMO_CRM_SettingName)
begin
	insert into [SystemSettings] ([SS_ParmName],[SS_ParmValue],[SS_Name]) values (@AMO_CRM_SettingName,'''',@AMO_CRM_SettingDesc) 
end
')
END TRY
BEGIN CATCH
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

/**************************************************/
/***************end AMO CRM************************/
/**************************************************/
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('SystemSettings_constants.sql', error_message())
END CATCH
end

print '############ end of file SystemSettings_constants.sql ################'

print '############ begin of file tbl_costs.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists (select 1 from dbo.syscolumns where name = ''CS_AgeMin'' and id = object_id(N''[dbo].[tbl_Costs]''))
	ALTER TABLE [dbo].tbl_Costs ADD CS_AgeMin INT NULL
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_costs.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from dbo.syscolumns where name = ''CS_AgeMax'' and id = object_id(N''[dbo].[tbl_Costs]''))
	ALTER TABLE [dbo].tbl_Costs ADD CS_AgeMax INT NULL
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_costs.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from dbo.syscolumns where name = ''CS_PaxMin'' and id = object_id(N''[dbo].[tbl_Costs]''))
	ALTER TABLE [dbo].tbl_Costs ADD CS_PaxMin INT NULL
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_costs.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if not exists (select 1 from dbo.syscolumns where name = ''CS_PaxMax'' and id = object_id(N''[dbo].[tbl_Costs]''))
	ALTER TABLE [dbo].tbl_Costs ADD CS_PaxMax INT NULL
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_costs.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

if exists (select 1 from dbo.syscolumns where name = ''CS_UPDUSER'' and id = object_id(N''[dbo].[tbl_Costs]''))
	ALTER TABLE [dbo].tbl_Costs ALTER COLUMN CS_UPDUSER varchar(50) NULL

exec RefreshViewForAll Costs
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_costs.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

-- удалим индексы кеша квот 9-ки
if exists (select * from sys.tables tab inner join sys.indexes ind on tab.object_id = ind.object_id
		where tab.name = ''tbl_costs''
			and ind.name = ''x_mwCheckFlightQuotes''
		)
begin
	drop index [tbl_costs].[x_mwCheckFlightQuotes]
end

if exists (select * from sys.tables tab inner join sys.indexes ind on tab.object_id = ind.object_id
		where tab.name = ''tbl_costs''
			and ind.name = ''x_mwCheckQuotes''
		)
begin
	drop index [tbl_costs].[x_mwCheckQuotes]
end

-- создадим новые индексы

-- x_byPartnerKeys: ПТ. Состав тура. Проживание. Выбор поставщика.
if not exists (select * from sys.tables tab inner join sys.indexes ind on tab.object_id = ind.object_id
		where tab.name = ''tbl_costs''
			and ind.name = ''x_byPartnerKeys''
		)
begin
	CREATE NONCLUSTERED INDEX [x_byPartnerKeys] ON [dbo].[tbl_Costs]
	(
		[CS_SVKEY], [CS_PKKEY], [CS_PRKEY]
	)
	include
	(
		[CS_DATEEND], [CS_CHECKINDATEEND], [CS_COID]
	)
end

-- X_COID: TourSearchApi, кеш цен, загрузка по ценовым блокам
if exists (select * from sys.tables tab inner join sys.indexes ind on tab.object_id = ind.object_id
		where tab.name = ''tbl_costs''
			and ind.name = ''X_COID'')
begin
	DROP INDEX [X_COID] ON [dbo].[tbl_Costs]
end

if not exists (select * from sys.tables tab inner join sys.indexes ind on tab.object_id = ind.object_id
		where tab.name = ''tbl_costs''
			and ind.name = ''X_COID'')
begin
	CREATE NONCLUSTERED INDEX X_COID
	ON [dbo].[tbl_Costs] 
	(
		[CS_COID]
	)
	INCLUDE 
	(
		[CS_SVKEY],[CS_CODE],[CS_SUBCODE1],[CS_SUBCODE2],[CS_PRKEY],
		[CS_PKKEY],[CS_DATE],[CS_DATEEND],[CS_WEEK],[CS_COSTNETTO],[CS_COST],
		[CS_DISCOUNT],[CS_TYPE],[CS_CREATOR],[CS_RATE],[CS_UPDDATE],
		[CS_LONG],[CS_BYDAY],[CS_FIRSTDAYNETTO],[CS_FIRSTDAYBRUTTO],[CS_PROFIT],[ROWID],
		[CS_CINNUM],[CS_TypeCalc],[cs_DateSellBeg],[cs_DateSellEnd],[CS_ID],
		[CS_CHECKINDATEBEG],[CS_CHECKINDATEEND],[CS_LONGMIN],[CS_TypeDivision],
		[CS_UPDUSER],[CS_TRFId],[CS_AgeMin],[CS_AgeMax],[CS_PaxMin],[CS_PaxMax]
	)
end

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('tbl_costs.sql', error_message())
END CATCH
end

print '############ end of file tbl_costs.sql ################'

print '############ begin of file tbl_Dogovor.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
declare @temp ListNvarcharValue

insert into @temp (value) values (''DG_ARKEY'')

exec RecreateDependentObjects ''tbl_Dogovor'',@temp,''alter table tbl_Dogovor alter column DG_ARKEY int not null''

')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_Dogovor.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''DG_CLIENTKEY'' AND id = OBJECT_ID(N''[dbo].[tbl_Dogovor]''))
BEGIN
	ALTER TABLE [dbo].tbl_Dogovor ADD DG_CLIENTKEY INT NULL	
END		

')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_Dogovor.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF NOT Exists (
	select s.name, *
	from sys.columns col
	inner join sys.views v
		on v.object_id = col.object_id
	inner join sys.schemas s
		on v.schema_id = s.schema_id
	where v.name = ''Dogovor''
		and col.name = ''DG_CLIENTKEY''
		and s.name = ''dbo'')
begin
	exec refreshviewforall ''dogovor''
end

')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_Dogovor.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''DG_CodePartner'' AND id = OBJECT_ID(N''[dbo].[tbl_Dogovor]''))
BEGIN
	ALTER TABLE [dbo].tbl_Dogovor ALTER COLUMN DG_CodePartner VARCHAR(60) NULL	
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_Dogovor.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

begin
	exec refreshviewforall ''dogovor''
end

')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_Dogovor.sql', error_message())
END CATCH
end

print '############ end of file tbl_Dogovor.sql ################'

print '############ begin of file tbl_DogovorList.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''DL_ShowOrder'' AND id = OBJECT_ID(N''[dbo].[tbl_DogovorList]''))

	BEGIN

		ALTER TABLE [dbo].tbl_DogovorList ADD DL_ShowOrder SMALLINT NOT NULL DEFAULT(0)

	

		EXECUTE RefreshViewForAll ''DogovorList''

	END		

')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_DogovorList.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('tbl_DogovorList.sql', error_message())
END CATCH
end

print '############ end of file tbl_DogovorList.sql ################'

print '############ begin of file tbl_DogovorSignatures.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
SET ANSI_NULLS ON
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_DogovorSignatures.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

SET QUOTED_IDENTIFIER ON
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_DogovorSignatures.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

SET ANSI_PADDING ON
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_DogovorSignatures.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

--<VERSION>9.2.18.0</VERSION>
--<DATE>2013-01-16</DATE>	
IF Not EXISTS (SELECT * FROM sysobjects WHERE id = OBJECT_ID(N''[dbo].[tbl_DogovorSignatures]'') AND OBJECTPROPERTY(id, N''IsUserTable'') = 1)
BEGIN
    CREATE TABLE [dbo].[tbl_DogovorSignatures](
	    [DG_Key] [int] NOT NULL,
	    [DG_Sign] [varbinary](max) NOT NULL,
	CONSTRAINT [PK_tbl_DogovorSigns] PRIMARY KEY CLUSTERED 
    (
	    [DG_Key] ASC
    )WITH (PAD_INDEX  = OFF, STATISTICS_NORECOMPUTE  = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS  = ON, ALLOW_PAGE_LOCKS  = ON) ON [PRIMARY]
    ) ON [PRIMARY]
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_DogovorSignatures.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

SET ANSI_PADDING OFF
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_DogovorSignatures.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

grant select, update, delete, insert on [dbo].[tbl_DogovorSignatures] to public
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_DogovorSignatures.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('tbl_DogovorSignatures.sql', error_message())
END CATCH
end

print '############ end of file tbl_DogovorSignatures.sql ################'

print '############ begin of file tbl_partners.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists (select 1 from dbo.syscolumns where name = ''PR_EMPHONE'' and id = object_id(N''[dbo].[tbl_Partners]''))
	ALTER TABLE [dbo].tbl_Partners ADD PR_EMPHONE varchar(254) NULL
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_partners.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
exec RefreshViewForAll ''Partners''
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_partners.sql', error_message())
END CATCH
end

print '############ end of file tbl_partners.sql ################'

print '############ begin of file tbl_Turist.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if not exists (select 1 from dbo.syscolumns where name = ''TU_CitizenID'' and id = object_id(N''[dbo].[tbl_Turist]''))
	ALTER TABLE [dbo].[tbl_Turist] ADD TU_CitizenID VARCHAR(14) NULL
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_Turist.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

exec RefreshViewForAll ''Turist''
')
END TRY
BEGIN CATCH
insert into ##errors values ('tbl_Turist.sql', error_message())
END CATCH
end

print '############ end of file tbl_Turist.sql ################'

print '############ begin of file tbl_Turlist_FixTurlistData.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
update Turlist set TL_NAME = ''_'' where TL_NAME = ''''
update Turlist set TL_NameLat = ''_'' where TL_NameLat = ''''

declare @countryKey int

set @countryKey = (select top 1 cn_key from tbl_Country where CN_NAME = ''россия'')

if @countryKey is null
	begin
		
		set @countryKey = (select top 1 cn_key from tbl_Country where CN_KEY != 0)		
		
	end

update Turlist set TL_CNKEY = @countryKey where TL_CNKEY = 0 or TL_CNKEY is null
')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('tbl_Turlist_FixTurlistData.sql', error_message())
END CATCH
end

print '############ end of file tbl_Turlist_FixTurlistData.sql ################'

print '############ begin of file Transport.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''TR_NAME'' AND id = OBJECT_ID(N''[dbo].[Transport]''))
BEGIN
	ALTER TABLE [dbo].Transport ALTER COLUMN TR_NAME VARCHAR(100) NOT NULL	
END		


IF EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''TR_NAMELAT'' AND id = OBJECT_ID(N''[dbo].[Transport]''))
BEGIN
	ALTER TABLE [dbo].Transport ALTER COLUMN TR_NAMELAT VARCHAR(100) NULL	
END		

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('Transport.sql', error_message())
END CATCH
end

print '############ end of file Transport.sql ################'

print '############ begin of file Turmargin.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N''[dbo].[FK__TURMARGIN__TM_Tl__11564BB9]'') AND parent_object_id = OBJECT_ID(N''[dbo].[TURMARGIN]''))

ALTER TABLE [dbo].[TURMARGIN] DROP CONSTRAINT [FK__TURMARGIN__TM_Tl__11564BB9]

')
END TRY
BEGIN CATCH
insert into ##errors values ('Turmargin.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF EXISTS (SELECT * FROM dbo.syscolumns WHERE NAME = ''TM_LONG'' AND ID = object_id(N''[dbo].[TURMARGIN]''))
BEGIN
	declare @temp ListNvarcharValue

	insert into @temp (value) values (''TM_LONG'')

	exec RecreateDependentObjects ''TURMARGIN'',@temp,''ALTER TABLE TURMARGIN DROP COLUMN TM_LONG'',1

END
')
END TRY
BEGIN CATCH
insert into ##errors values ('Turmargin.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


--IF  EXISTS (SELECT * FROM dbo.sysobjects WHERE id = OBJECT_ID(N''[DF__TURMARGIN__Chang__2D8A0CC1]'') AND type = ''D'')

--BEGIN

--ALTER TABLE [dbo].[TURMARGIN] DROP CONSTRAINT [DF__TURMARGIN__Chang__2D8A0CC1]

--END



--GO



--IF  EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''ChangeId'' and id = object_id(N''[dbo].[TURMARGIN]''))

--	ALTER TABLE [dbo].[TURMARGIN] DROP COLUMN ChangeId

--GO



--IF  EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''TM_DateSellBeg'' and id = object_id(N''[dbo].[TURMARGIN]''))

--	ALTER TABLE [dbo].[TURMARGIN] DROP COLUMN TM_DateSellBeg

--GO



--IF  EXISTS (SELECT 1 FROM dbo.syscolumns WHERE name = ''TM_DateSellEnd'' and id = object_id(N''[dbo].[TURMARGIN]''))

--	ALTER TABLE [dbo].[TURMARGIN] DROP COLUMN TM_DateSellEnd

--GO





')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('Turmargin.sql', error_message())
END CATCH
end

print '############ end of file Turmargin.sql ################'

print '############ begin of file Userlist.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF NOT EXISTS (SELECT * FROM dbo.syscolumns WHERE NAME = ''US_SmtpEnableSsl'' AND ID = object_id(N''[dbo].[UserList]''))
BEGIN
	ALTER TABLE dbo.UserList ADD
		US_SmtpEnableSsl bit NOT NULL CONSTRAINT DF_UserList_US_SmtpEnableSsl DEFAULT 0
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('Userlist.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF EXISTS (SELECT * FROM dbo.syscolumns WHERE NAME = ''US_FullName'' AND ID = object_id(N''[dbo].[UserList]''))
BEGIN
	ALTER TABLE dbo.UserList ALTER COLUMN US_FullName varchar(50) NOT NULL
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('Userlist.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

IF EXISTS (SELECT * FROM dbo.syscolumns WHERE NAME = ''US_FullNameLat'' AND ID = object_id(N''[dbo].[UserList]''))
BEGIN
	ALTER TABLE dbo.UserList ALTER COLUMN US_FullNameLat varchar(50) NOT NULL
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('Userlist.sql', error_message())
END CATCH
end

print '############ end of file Userlist.sql ################'

print '############ begin of file _drop_CostOfferActivations.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select 1 from dbo.sysobjects where name = ''CostOfferActivations'')

	DROP TABLE [dbo].[CostOfferActivations]

')
END TRY
BEGIN CATCH
insert into ##errors values ('_drop_CostOfferActivations.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('_drop_CostOfferActivations.sql', error_message())
END CATCH
end

print '############ end of file _drop_CostOfferActivations.sql ################'

print '############ begin of file _drop_DUP_KEY_USER.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N''[dbo].[DUP_KEY_USER]'') AND type in (N''U''))
	DROP TABLE [dbo].[DUP_KEY_USER]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_drop_DUP_KEY_USER.sql', error_message())
END CATCH
end

print '############ end of file _drop_DUP_KEY_USER.sql ################'

print '############ begin of file trg_DelCharter.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[trg_DelCharter]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[trg_DelCharter]
')
END TRY
BEGIN CATCH
insert into ##errors values ('trg_DelCharter.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[trg_DelCharter]
   ON [dbo].[Charter]
   AFTER DELETE
AS
	declare @key int
	declare curDelete cursor for select ch_key from deleted
	open curDelete 
	Fetch Next From curDelete INTO @key
	WHILE @@FETCH_STATUS = 0
	BEGIN
		Delete from tourservicelist Where TO_SvKey = 1 AND TO_Code = @key

		-- Task 47689: каскадное удаление доплат addCosts
		delete from AddCosts  Where ADC_SVKey = 1 and ADC_Code = @key
		
		Fetch Next From curDelete INTO @key
	END
close curDelete
deallocate curDelete
')
END TRY
BEGIN CATCH
insert into ##errors values ('trg_DelCharter.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('trg_DelCharter.sql', error_message())
END CATCH
end

print '############ end of file trg_DelCharter.sql ################'

print '############ begin of file T_AccmdmentypeDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_AccmdmentypeDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_AccmdmentypeDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AccmdmentypeDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_AccmdmentypeDelete]
   ON [dbo].[Accmdmentype]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>
	
	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Accmdmentype'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''AC_Key, AC_Name'', AC_Key, AC_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AccmdmentypeDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_AccmdmentypeDelete.sql', error_message())
END CATCH
end

print '############ end of file T_AccmdmentypeDelete.sql ################'

print '############ begin of file T_AddDescript1Delete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_AddDescript1Delete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_AddDescript1Delete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AddDescript1Delete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_AddDescript1Delete]
   ON [dbo].[AddDescript1]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>
	
	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''AddDescript1'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''A1_Key, A1_Name'', A1_Key, A1_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AddDescript1Delete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_AddDescript1Delete.sql', error_message())
END CATCH
end

print '############ end of file T_AddDescript1Delete.sql ################'

print '############ begin of file T_AddDescript2Delete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_AddDescript2Delete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_AddDescript2Delete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AddDescript2Delete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_AddDescript2Delete]
   ON [dbo].[AddDescript2]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''AddDescript2'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''A2_Key, A2_Name'', A2_Key, A2_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AddDescript2Delete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_AddDescript2Delete.sql', error_message())
END CATCH
end

print '############ end of file T_AddDescript2Delete.sql ################'

print '############ begin of file T_AdvertiseDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_AdvertiseDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_AdvertiseDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AdvertiseDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_AdvertiseDelete]
   ON [dbo].[Advertise]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2014-04-14</DATE>
	
	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Advertise'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''AD_Key, AD_Name'', AD_Key, AD_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AdvertiseDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_AdvertiseDelete.sql', error_message())
END CATCH
end

print '############ end of file T_AdvertiseDelete.sql ################'

print '############ begin of file T_AircraftDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_AircraftDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_AircraftDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AircraftDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_AircraftDelete]
   ON [dbo].[Aircraft]
   AFTER DELETE
AS 
BEGIN
	--удаляем маппинги из таблицы GDSMappings
	delete from GDSMappings 
	where GM_DICTIONARYID = 6 and GM_MTDICTIONARYITEMID in (select deleted.AC_KEY from deleted)
	
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Aircraft'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''AC_Key, AC_Name'', AC_Key, AC_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AircraftDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_AircraftDelete.sql', error_message())
END CATCH
end

print '############ end of file T_AircraftDelete.sql ################'

print '############ begin of file T_AirlineDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_AirlineDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_AirlineDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AirlineDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_AirlineDelete]
   ON [dbo].[Airline]
   AFTER DELETE
AS 
BEGIN
	--удаляем маппинги из таблицы GDSMappings
	delete from GDSMappings 
	where GM_DICTIONARYID = 4 and GM_MTDICTIONARYITEMID in (select deleted.al_key from deleted)
	
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Airline'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''AL_Key, AL_Name'', AL_Key, AL_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AirlineDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_AirlineDelete.sql', error_message())
END CATCH
end

print '############ end of file T_AirlineDelete.sql ################'

print '############ begin of file T_AirportDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_AirportDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)

drop trigger [dbo].[T_AirportDelete]

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AirportDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('



CREATE TRIGGER [dbo].[T_AirportDelete]

   ON [dbo].[Airport]

   AFTER DELETE

AS 

BEGIN
	--удаляем маппинги из таблицы GDSMappings
	delete from GDSMappings 
	where GM_DICTIONARYID = 5 and GM_MTDICTIONARYITEMID in (select deleted.ap_key from deleted)
	
	--<VERSION>9.2.20.12</VERSION>

	--<DATE>2015-11-12</DATE>



	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''

	begin

		declare @nHiId int

		

		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)

		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Airport'', 0, 400000, 0)

		set @nHiId = SCOPE_IDENTITY()

		

		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)

		select @nHiId, 400000, '''', ''AP_Key, AP_Name'', AP_Key, AP_Name, 1 from DELETED

	end

END



')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AirportDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('





')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_AirportDelete.sql', error_message())
END CATCH
end

print '############ end of file T_AirportDelete.sql ################'

print '############ begin of file T_AirSeasonDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_AirSeasonDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_AirSeasonDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AirSeasonDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_AirSeasonDelete]
   ON [dbo].[AirSeason]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''AirSeason'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''AS_ID'', AS_ID, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AirSeasonDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_AirSeasonDelete.sql', error_message())
END CATCH
end

print '############ end of file T_AirSeasonDelete.sql ################'

print '############ begin of file T_AirServiceDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_AirServiceDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_AirServiceDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AirServiceDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_AirServiceDelete]
   ON [dbo].[AirService]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	-- Task 47689: каскадное удаление доплат addCosts
	if @@ROWCOUNT > 0
	begin
		DELETE FROM AddCosts  
		WHERE ADC_SVKey = 1 and ADC_SubCode1 IN (SELECT DELETED.AS_KEY FROM DELETED)
	end
	
	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''AirService'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''AS_Key, AS_NameRus'', AS_Key, AS_NameRus, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AirServiceDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_AirServiceDelete.sql', error_message())
END CATCH
end

print '############ end of file T_AirServiceDelete.sql ################'

print '############ begin of file T_Ank_CasesDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_Ank_CasesDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_Ank_CasesDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_Ank_CasesDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_Ank_CasesDelete]
   ON [dbo].[Ank_Cases]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Ank_Cases'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''AC_AFKey, AC_Name'', AC_AFKey, AC_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_Ank_CasesDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_Ank_CasesDelete.sql', error_message())
END CATCH
end

print '############ end of file T_Ank_CasesDelete.sql ################'

print '############ begin of file T_Ank_FieldsDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_Ank_FieldsDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_Ank_FieldsDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_Ank_FieldsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_Ank_FieldsDelete]
   ON [dbo].[Ank_Fields]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Ank_Fields'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''AF_Key, AF_Name'', AF_Key, AF_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_Ank_FieldsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_Ank_FieldsDelete.sql', error_message())
END CATCH
end

print '############ end of file T_Ank_FieldsDelete.sql ################'

print '############ begin of file T_AnnulReasonsDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_AnnulReasonsDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_AnnulReasonsDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AnnulReasonsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_AnnulReasonsDelete]
   ON [dbo].[AnnulReasons]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''AnnulReasons'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''AR_Key, AR_Name'', AR_Key, AR_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_AnnulReasonsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_AnnulReasonsDelete.sql', error_message())
END CATCH
end

print '############ end of file T_AnnulReasonsDelete.sql ################'

print '############ begin of file T_BanksDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_BanksDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_BanksDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_BanksDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_BanksDelete]
   ON [dbo].[Banks]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Banks'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''BN_Key, BN_Name'', BN_Key, BN_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_BanksDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_BanksDelete.sql', error_message())
END CATCH
end

print '############ end of file T_BanksDelete.sql ################'

print '############ begin of file T_CabineDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_CabineDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_CabineDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_CabineDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_CabineDelete]
   ON [dbo].[Cabine]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Cabine'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''CB_Key, CB_Name'', CB_Key, CB_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_CabineDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_CabineDelete.sql', error_message())
END CATCH
end

print '############ end of file T_CabineDelete.sql ################'

print '############ begin of file T_CategoriesOfHotelDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_CategoriesOfHotelDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_CategoriesOfHotelDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_CategoriesOfHotelDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_CategoriesOfHotelDelete]
   ON [dbo].[CategoriesOfHotel]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''CategoriesOfHotel'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''COH_Id, COH_Name'', COH_Id, COH_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_CategoriesOfHotelDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_CategoriesOfHotelDelete.sql', error_message())
END CATCH
end

print '############ end of file T_CategoriesOfHotelDelete.sql ################'

print '############ begin of file T_CauseDiscountsDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_CauseDiscountsDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_CauseDiscountsDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_CauseDiscountsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_CauseDiscountsDelete]
   ON [dbo].[CauseDiscounts]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''CauseDiscounts'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''CD_Key, CD_Name'', CD_Key, CD_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_CauseDiscountsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_CauseDiscountsDelete.sql', error_message())
END CATCH
end

print '############ end of file T_CauseDiscountsDelete.sql ################'

print '############ begin of file T_CharterDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_CharterDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_CharterDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_CharterDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_CharterDelete]
   ON [dbo].[Charter]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Charter'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''CH_Key'', CH_Key, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_CharterDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_CharterDelete.sql', error_message())
END CATCH
end

print '############ end of file T_CharterDelete.sql ################'

print '############ begin of file T_CityDictionaryDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_CityDictionaryDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_CityDictionaryDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_CityDictionaryDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_CityDictionaryDelete]
   ON [dbo].[CityDictionary]
   AFTER DELETE
AS 
BEGIN
	--удаляем маппинги из таблицы GDSMappings
	delete from GDSMappings 
	where GM_DICTIONARYID = 2 and GM_MTDICTIONARYITEMID in (select deleted.CT_KEY from deleted)

	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	-- Task 47689: каскадное удаление доплат addCosts
	if @@ROWCOUNT > 0
	begin
		DELETE FROM AddCosts  
		WHERE ADC_CityKey IN(SELECT DELETED.CT_KEY FROM DELETED)
	end

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''CityDictionary'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''CT_Key, CT_Name'', CT_Key, CT_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_CityDictionaryDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_CityDictionaryDelete.sql', error_message())
END CATCH
end

print '############ end of file T_CityDictionaryDelete.sql ################'

print '############ begin of file T_ClientDel.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_ClientDel]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_ClientDel]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ClientDel.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_ClientDel] ON [dbo].[Clients] 
FOR DELETE 
AS
--<DATE>2015-11-12</DATE>
---<VERSION>9.2.20.12</VERSION>
IF @@ROWCOUNT > 0
BEGIN
	DECLARE @n_ClKey INT
	DECLARE curClientDel cursor for SELECT CL_KEY FROM DELETED
	OPEN curClientDel
	FETCH NEXT FROM curClientDel INTO @n_ClKey
	WHILE @@FETCH_STATUS = 0
	BEGIN
		UPDATE tbl_TURIST SET tu_id = null WHERE tu_id = @n_ClKey
		FETCH NEXT FROM curClientDel INTO @n_ClKey
	END
	CLOSE curClientDel
	DEALLOCATE curClientDel
	
	if APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Clients'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''CL_Key, CL_NameRus'', CL_Key, CL_NameRus, 1 from DELETED
	end		
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ClientDel.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_ClientDel.sql', error_message())
END CATCH
end

print '############ end of file T_ClientDel.sql ################'

print '############ begin of file T_ControlsDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_ControlsDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_ControlsDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ControlsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_ControlsDelete]
   ON [dbo].[Controls]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Controls'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''CR_Key, CR_Name'', CR_Key, CR_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ControlsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_ControlsDelete.sql', error_message())
END CATCH
end

print '############ end of file T_ControlsDelete.sql ################'

print '############ begin of file T_DiscountsDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_DiscountsDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_DiscountsDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_DiscountsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_DiscountsDelete]
   ON [dbo].[Discounts]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Discounts'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''DS_Key'', DS_Key, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_DiscountsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_DiscountsDelete.sql', error_message())
END CATCH
end

print '############ end of file T_DiscountsDelete.sql ################'

print '############ begin of file T_Discount_ClientDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_Discount_ClientDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_Discount_ClientDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_Discount_ClientDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


CREATE TRIGGER [dbo].[T_Discount_ClientDelete]
   ON [dbo].[Discount_Client]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Discount_Client'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''DS_Key, DS_Name'', DS_Key, DS_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_Discount_ClientDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_Discount_ClientDelete.sql', error_message())
END CATCH
end

print '############ end of file T_Discount_ClientDelete.sql ################'

print '############ begin of file T_DocumentStatusDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_DocumentStatusDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_DocumentStatusDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_DocumentStatusDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_DocumentStatusDelete]
   ON [dbo].[DocumentStatus]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''DocumentStatus'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''DS_Key, DS_Name'', DS_Key, DS_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_DocumentStatusDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_DocumentStatusDelete.sql', error_message())
END CATCH
end

print '############ end of file T_DocumentStatusDelete.sql ################'

print '############ begin of file T_DogovorListUpdate.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_DogovorListUpdate]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_DogovorListUpdate]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_DogovorListUpdate.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [T_DogovorListUpdate]
ON [dbo].[tbl_DogovorList]
FOR UPDATE, INSERT, DELETE
AS
IF @@ROWCOUNT > 0
BEGIN
--<VERSION>2009.2.17.2</VERSION>
--<DATE>2012-12-12</DATE>
  DECLARE @ODL_DgCod varchar(10)
  DECLARE @ODL_Key int
  DECLARE @ODL_SvKey int
  DECLARE @ODL_Code int
  DECLARE @ODL_SubCode1 int
  DECLARE @ODL_SubCode2 int
  DECLARE @ODL_CnKey int
  DECLARE @ODL_CtKey int
  DECLARE @ODL_NMen smallint
  DECLARE @ODL_Day smallint
  DECLARE @ODL_NDays smallint
  DECLARE @ODL_PartnerKey int
  DECLARE @ODL_Cost money
  DECLARE @ODL_Brutto money
  DECLARE @ODL_Discount money
  DECLARE @ODL_Wait smallint
  DECLARE @ODL_Control int
  DECLARE @ODL_sDateBeg varchar(10)
  DECLARE @ODL_DateBeg datetime
  DECLARE @ODL_sDateEnd varchar(10)
  DECLARE @ODL_DateEnd datetime
  DECLARE @ODL_RealNetto money
  DECLARE @ODL_Attribute int
  DECLARE @ODL_PaketKey int
  DECLARE @ODL_Name varchar(250)
  DECLARE @ODL_Payed money
  DECLARE @ODL_DGKey int
  DECLARE @ODL_QuoteKey int
  DECLARE @ODL_TimeBeg datetime
  DECLARE @ODL_TimeEnd datetime

  DECLARE @NDL_DgCod varchar(10)
  DECLARE @NDL_Key int
  DECLARE @NDL_SvKey int
  DECLARE @NDL_Code int
  DECLARE @NDL_SubCode1 int
  DECLARE @NDL_SubCode2 int
  DECLARE @NDL_CnKey int
  DECLARE @NDL_CtKey int
  DECLARE @NDL_NMen smallint
  DECLARE @NDL_Day smallint
  DECLARE @NDL_NDays smallint
  DECLARE @NDL_PartnerKey int
  DECLARE @NDL_Cost money
  DECLARE @NDL_Brutto money
  DECLARE @NDL_Discount money
  DECLARE @NDL_Wait smallint
  DECLARE @NDL_Control int
  DECLARE @NDL_sDateBeg varchar(10)
  DECLARE @NDL_DateBeg datetime
  DECLARE @NDL_sDateEnd varchar(10)
  DECLARE @NDL_DateEnd datetime
  DECLARE @NDL_RealNetto money
  DECLARE @NDL_Attribute int
  DECLARE @NDL_PaketKey int
  DECLARE @NDL_Name varchar(250)
  DECLARE @NDL_Payed money
  DECLARE @NDL_DGKey int
  DECLARE @NDL_QuoteKey int
  DECLARE @NDL_TimeBeg datetime
  DECLARE @NDL_TimeEnd datetime

  DECLARE @sMod varchar(3)
  DECLARE @nDelCount int
  DECLARE @nInsCount int
  DECLARE @nHIID int
  DECLARE @sHI_Text varchar(254)
  DECLARE @DL_Key int
  DECLARE @nDGSorGlobalCode_Old int, @nDGSorGlobalCode_New int,  @nDGSorCode_New int, @dDGTourDate datetime, @nDGKey int
  DECLARE @bNeedCommunicationUpdate smallint
  DECLARE @nSVKey int
  DECLARE @sDisableDogovorStatusChange varchar(254), @sUpdateMainDogovorStatuses varchar(254)

  DECLARE @dg_key INT

  SELECT @nDelCount = COUNT(*) FROM DELETED
  SELECT @nInsCount = COUNT(*) FROM INSERTED

  -- При вставке все что связано со вставкой реализовано в .Net
  IF (@nDelCount = 0)
      RETURN

  IF (@nDelCount = 0)
  BEGIN
	SET @sMod = ''INS''
    DECLARE cur_DogovorList CURSOR FOR 
    SELECT 	N.DL_Key,
			null, null, null, null, null, null, null, null, null, null, null,
			null, null, null, null, null, null, null, null, 
			null, null, null, null, null, null, null,
			N.DL_DgCod, N.DL_DGKey, N.DL_SvKey, N.DL_Code, N.DL_SubCode1, N.DL_SubCode2, N.DL_CnKey, N.DL_CtKey, N.DL_NMen, N.DL_Day, N.DL_NDays, 
			N.DL_PartnerKey, N.DL_Cost, N.DL_Brutto, N.DL_Discount, N.DL_Wait, N.DL_Control, N.DL_DateBeg, N.DL_DateEnd,
			N.DL_RealNetto, N.DL_Attribute, N.DL_PaketKey, N.DL_Name, N.DL_Payed, N.DL_QuoteKey, N.DL_TimeBeg
			
      FROM INSERTED N 
  END
  ELSE IF (@nInsCount = 0)
  BEGIN
	SET @sMod = ''DEL''
    DECLARE cur_DogovorList CURSOR FOR 
    SELECT 	O.DL_Key,
			O.DL_DgCod, O.DL_DGKey, O.DL_SvKey, O.DL_Code, O.DL_SubCode1, O.DL_SubCode2, O.DL_CnKey, O.DL_CtKey, O.DL_NMen, O.DL_Day, O.DL_NDays, 
			O.DL_PartnerKey, O.DL_Cost, O.DL_Brutto, O.DL_Discount, O.DL_Wait, O.DL_Control, O.DL_DateBeg, O.DL_DateEnd,
			O.DL_RealNetto, O.DL_Attribute, O.DL_PaketKey, O.DL_Name, O.DL_Payed, O.DL_QuoteKey, O.DL_TimeBeg, 
			null, null, null, null, null, null, null, null, null, null, null,
			null, null, null, null, null, null, null, null, 
			null, null, null, null, null, null, null
    FROM DELETED O
  END
  ELSE 
  BEGIN
  	SET @sMod = ''UPD''
    DECLARE cur_DogovorList CURSOR FOR 
    SELECT 	N.DL_Key,
			O.DL_DgCod, O.DL_DGKey, O.DL_SvKey, O.DL_Code, O.DL_SubCode1, O.DL_SubCode2, O.DL_CnKey, O.DL_CtKey, O.DL_NMen, O.DL_Day, O.DL_NDays, 
			O.DL_PartnerKey, O.DL_Cost, O.DL_Brutto, O.DL_Discount, O.DL_Wait, O.DL_Control, O.DL_DateBeg, O.DL_DateEnd,
			O.DL_RealNetto, O.DL_Attribute, O.DL_PaketKey, O.DL_Name, O.DL_Payed, O.DL_QuoteKey, O.DL_TimeBeg,
	  		N.DL_DgCod, N.DL_DGKey, N.DL_SvKey, N.DL_Code, N.DL_SubCode1, N.DL_SubCode2, N.DL_CnKey, N.DL_CtKey, N.DL_NMen, N.DL_Day, N.DL_NDays, 
			N.DL_PartnerKey, N.DL_Cost, N.DL_Brutto, N.DL_Discount, N.DL_Wait, N.DL_Control, N.DL_DateBeg, N.DL_DateEnd,
			N.DL_RealNetto, N.DL_Attribute, N.DL_PaketKey, N.DL_Name, N.DL_Payed, N.DL_QuoteKey, N.DL_TimeBeg
    FROM DELETED O, INSERTED N 
    WHERE N.DL_Key = O.DL_Key
  END

    OPEN cur_DogovorList
    FETCH NEXT FROM cur_DogovorList INTO 
		@DL_Key, 
			@ODL_DgCod, @ODL_DGKey, @ODL_SvKey, @ODL_Code, @ODL_SubCode1, @ODL_SubCode2, @ODL_CnKey, @ODL_CtKey, @ODL_NMen, @ODL_Day, @ODL_NDays, 
			@ODL_PartnerKey, @ODL_Cost, @ODL_Brutto, @ODL_Discount, @ODL_Wait, @ODL_Control, @ODL_DateBeg, @ODL_DateEnd, 
			@ODL_RealNetto, @ODL_Attribute, @ODL_PaketKey, @ODL_Name, @ODL_Payed, @ODL_QuoteKey, @ODL_TimeBeg,
			@NDL_DgCod, @NDL_DGKey, @NDL_SvKey, @NDL_Code, @NDL_SubCode1, @NDL_SubCode2, @NDL_CnKey, @NDL_CtKey, @NDL_NMen, @NDL_Day, @NDL_NDays, 
			@NDL_PartnerKey, @NDL_Cost, @NDL_Brutto, @NDL_Discount, @NDL_Wait, @NDL_Control, @NDL_DateBeg, @NDL_DateEnd, 
			@NDL_RealNetto, @NDL_Attribute, @NDL_PaketKey, @NDL_Name, @NDL_Payed, @NDL_QuoteKey, @NDL_TimeBeg
    WHILE @@FETCH_STATUS = 0
	BEGIN
		SET @NDL_sDateBeg=CONVERT( char(10), @NDL_DateBeg, 104)
		SET @ODL_sDateBeg=CONVERT( char(10), @ODL_DateBeg, 104)
		SET @NDL_sDateEnd=CONVERT( char(10), @NDL_DateEnd, 104)
		SET @ODL_sDateEnd=CONVERT( char(10), @ODL_DateEnd, 104)

    	------------Проверка, надо ли что-то писать в историю квот-------------------------------------------   
		If ISNULL(@ODL_QuoteKey, 0) != ISNULL(@NDL_QuoteKey, 0) and (ISNULL(@NDL_QuoteKey, 0)>1 or ISNULL(@ODL_QuoteKey, 0)>1)
		BEGIN
			declare @sOper varchar(25)
			EXEC dbo.CurrentUser @sOper output
			if ISNULL(@ODL_QuoteKey, 0)!=0
				INSERT INTO HistoryQuote (HQ_Date, HQ_Mod, HQ_Who, HQ_Text, HQ_QTKey, HQ_DLKey)
					VALUES (GETDATE(), ''DEL'', @sOper, @sHI_Text, @ODL_QuoteKey, @DL_Key)
			if ISNULL(@NDL_QuoteKey, 0)!=0
				INSERT INTO HistoryQuote (HQ_Date, HQ_Mod, HQ_Who, HQ_Text, HQ_QTKey, HQ_DLKey)
					VALUES (GETDATE(), ''INS'', @sOper, @sHI_Text, @NDL_QuoteKey, @DL_Key)
		END

    	------------Проверка, надо ли что-то писать в историю-------------------------------------------   
		If (
			ISNULL(@ODL_DgCod, '''') != ISNULL(@NDL_DgCod, '''')  OR
			ISNULL(@ODL_DGKey, '''') != ISNULL(@NDL_DGKey, '''')  OR
			ISNULL(@ODL_SvKey, '''') != ISNULL(@NDL_SvKey, '''')  OR
			ISNULL(@ODL_Code, '''') != ISNULL(@NDL_Code, '''')  OR
			ISNULL(@ODL_SubCode1, '''') != ISNULL(@NDL_SubCode1, '''')  OR
			ISNULL(@ODL_SubCode2, '''') != ISNULL(@NDL_SubCode2, '''')  OR
			ISNULL(@ODL_CnKey, '''') != ISNULL(@NDL_CnKey, '''')  OR
			ISNULL(@ODL_CtKey, '''') != ISNULL(@NDL_CtKey, '''')  OR
			ISNULL(@ODL_NMen, '''') != ISNULL(@NDL_NMen, '''')  OR
			ISNULL(@ODL_Day, '''') != ISNULL(@NDL_Day, '''')  OR
			ISNULL(@ODL_NDays, '''') != ISNULL(@NDL_NDays, '''')  OR
			ISNULL(@ODL_PartnerKey, '''') != ISNULL(@NDL_PartnerKey, '''')  OR
			ISNULL(@ODL_Cost, 0) != ISNULL(@NDL_Cost, 0)  OR
			ISNULL(@ODL_Brutto, 0) != ISNULL(@NDL_Brutto, 0)  OR
			ISNULL(@ODL_Discount, 0) != ISNULL(@NDL_Discount, 0)  OR
			ISNULL(@ODL_Wait, '''') != ISNULL(@NDL_Wait, '''')  OR
			ISNULL(@ODL_Control, '''') != ISNULL(@NDL_Control, '''')  OR
			ISNULL(@ODL_sDateBeg, '''') != ISNULL(@NDL_sDateBeg, '''')  OR
			ISNULL(@ODL_sDateEnd, '''') != ISNULL(@NDL_sDateEnd, '''')  OR
			ISNULL(@ODL_RealNetto, 0) != ISNULL(@NDL_RealNetto, 0)  OR
			ISNULL(@ODL_Attribute, '''') != ISNULL(@NDL_Attribute, '''')  OR
			ISNULL(@ODL_PaketKey, '''') != ISNULL(@NDL_PaketKey, '''') OR
			ISNULL(@ODL_Name, '''') != ISNULL(@NDL_Name, '''') OR 
			ISNULL(@ODL_Payed, 0) != ISNULL(@NDL_Payed, 0) OR 
			ISNULL(@ODL_TimeBeg, 0) != ISNULL(@NDL_TimeBeg, 0)
		)
		BEGIN
		  	------------Запись в историю--------------------------------------------------------------------
			if (@sMod = ''INS'')
			BEGIN
				SET @sHI_Text = ISNULL(@NDL_Name, '''')
				SET @nDGKey=@NDL_DGKey
				SET @nSVKey=@NDL_SvKey
			END
			else if (@sMod = ''DEL'')
				BEGIN
				SET @sHI_Text = ISNULL(@ODL_Name, '''')
				SET @NDL_DgCod = @ODL_DgCod
				SET @nDGKey=@ODL_DGKey
				SET @nSVKey=@ODL_SvKey
				END
			else if (@sMod = ''UPD'')
			BEGIN
				SET @sHI_Text = ISNULL(@NDL_Name, '''')
				SET @nDGKey=@NDL_DGKey
				SET @nSVKey=@NDL_SvKey
			END
			EXEC @nHIID = dbo.InsHistory @NDL_DgCod, @nDGKey, 2, @DL_Key, @sMod, @sHI_Text, '''', 0, '''', 0, @nSVKey
			--SELECT @nHIID = IDENT_CURRENT(''History'')		
			--------Детализация--------------------------------------------------

			DECLARE @sText_Old varchar(100)
			DECLARE @sText_New varchar(100)
    
    			DECLARE @sText_AllTypeRooming varchar(20)
			SET @sText_AllTypeRooming  = ''Все типы размещения''

			If (ISNULL(@ODL_Code, '''') != ISNULL(@NDL_Code, ''''))
			BEGIN
				/*
				IF @NDL_SvKey=1
				BEGIN
					-- mv26.04.2010
					-- Перенес вниз см. начиная с "-- ИНДИВИДУАЛЬНАЯ ОБРАБОТКА АВИАПЕРЕЛЕТОВ"
				END
				*/
				IF @NDL_SvKey!=1
				BEGIN
					exec dbo.GetSVCodeName @ODL_SvKey, @ODL_Code, @sText_Old output, null
					exec dbo.GetSVCodeName @NDL_SvKey, @NDL_Code, @sText_New output, null
					IF @NDL_SvKey = 2
						EXECUTE dbo.InsertHistoryDetail @nHIID , 1028, @sText_Old, @sText_New, @ODL_Code, @NDL_Code, null, null, 0, @bNeedCommunicationUpdate output
					ELSE IF (@NDL_SvKey = 3 or @NDL_SvKey = 8)
						EXECUTE dbo.InsertHistoryDetail @nHIID , 1029, @sText_Old, @sText_New, @ODL_Code, @NDL_Code, null, null, 0, @bNeedCommunicationUpdate output
					ELSE IF @NDL_SvKey = 4
						EXECUTE dbo.InsertHistoryDetail @nHIID , 1030, @sText_Old, @sText_New, @ODL_Code, @NDL_Code, null, null, 0, @bNeedCommunicationUpdate output
					ELSE IF (@NDL_SvKey = 7 or @NDL_SvKey = 9)
						EXECUTE dbo.InsertHistoryDetail @nHIID , 1031, @sText_Old, @sText_New, @ODL_Code, @NDL_Code, null, null, 0, @bNeedCommunicationUpdate output
					ELSE 
						EXECUTE dbo.InsertHistoryDetail @nHIID , 1032, @sText_Old, @sText_New, @ODL_Code, @NDL_Code, null, null, 0, @bNeedCommunicationUpdate output
				END
			END

			If (ISNULL(@ODL_SubCode1, '''') != ISNULL(@NDL_SubCode1, ''''))
				IF @NDL_SvKey = 1 or @ODL_SvKey = 1
				BEGIN
					Select @sText_Old = AS_Code + '' '' + AS_NameRus from AirService where AS_Key = @ODL_SubCode1
					Select @sText_New = AS_Code + '' '' + AS_NameRus from AirService where AS_Key = @NDL_SubCode1
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1033, @sText_Old, @sText_New, @ODL_SubCode1, @NDL_SubCode1, null, null, 0, @bNeedCommunicationUpdate output
				END
				ELSE IF @NDL_SvKey = 2 or @NDL_SvKey = 4 or @ODL_SvKey = 2 or @ODL_SvKey = 4
				BEGIN
					Select @sText_Old = TR_Name from Transport where TR_Key = @ODL_SubCode1
					Select @sText_New = TR_Name from Transport where TR_Key = @NDL_SubCode1
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1034, @sText_Old, @sText_New, @ODL_SubCode1, @NDL_SubCode1, null, null, 0, @bNeedCommunicationUpdate output
				END
				ELSE IF @NDL_SvKey = 3 or @NDL_SvKey = 8 or @ODL_SvKey = 3 or @ODL_SvKey = 8
				BEGIN
					Select @sText_Old = RM_Name + '','' + RC_Name + '','' + AC_Code from HotelRooms,Rooms,RoomsCategory,AccmdMenType where HR_Key = @ODL_SubCode1 and RM_Key=HR_RmKey and RC_Key=HR_RcKey and AC_Key=HR_AcKey
					Select @sText_New = RM_Name + '','' + RC_Name + '','' + AC_Code from HotelRooms,Rooms,RoomsCategory,AccmdMenType where HR_Key = @NDL_SubCode1 and RM_Key=HR_RmKey and RC_Key=HR_RcKey and AC_Key=HR_AcKey
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1035, @sText_Old, @sText_New, @ODL_SubCode1, @NDL_SubCode1, null, null, 0, @bNeedCommunicationUpdate output
				END
				ELSE IF @NDL_SvKey = 7 or @NDL_SvKey = 9 or @ODL_SvKey = 7 or @ODL_SvKey = 9
				BEGIN
					IF @ODL_SubCode1 = 0
						Set @sText_Old = @sText_AllTypeRooming
					Else
						Select @sText_Old = ISNULL(CB_Code,'''') + '','' + ISNULL(CB_Category,'''') + '','' + ISNULL(CB_Name,'''') from Cabine where CB_Key = @ODL_SubCode1
					IF @NDL_SubCode1 = 0
						Set @sText_New = @sText_AllTypeRooming
					Else
						Select @sText_New = ISNULL(CB_Code,'''') + '','' + ISNULL(CB_Category,'''') + '','' + ISNULL(CB_Name,'''') from Cabine where CB_Key = @NDL_SubCode1
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1035, @sText_Old, @sText_New, @ODL_SubCode1, @NDL_SubCode1, null, null, 0, @bNeedCommunicationUpdate output
				END
				ELSE
				BEGIN
					Select @sText_Old = A1_Name from AddDescript1 where A1_Key = @ODL_SubCode1
					Select @sText_New = A1_Name from AddDescript1 where A1_Key = @NDL_SubCode1
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1036, @sText_Old, @sText_New, @ODL_SubCode1, @NDL_SubCode1, null, null, 0, @bNeedCommunicationUpdate output
				END
	
			If (ISNULL(@ODL_SubCode2, '''') != ISNULL(@NDL_SubCode2, ''''))
				IF @NDL_SvKey = 3 or @NDL_SvKey = 7 or @ODL_SvKey = 3 or @ODL_SvKey = 7
				BEGIN
					Select @sText_Old = PN_Name from Pansion where PN_Key = @ODL_SubCode2
					Select @sText_New = PN_Name from Pansion where PN_Key = @NDL_SubCode2
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1037, @sText_Old, @sText_New, @ODL_SubCode2, @NDL_SubCode2, null, null, 0, @bNeedCommunicationUpdate output
				END
				ELSE
				BEGIN
					Select @sText_Old = A2_Name from AddDescript2 where A2_Key = @ODL_SubCode2
					Select @sText_New = A2_Name from AddDescript2 where A2_Key = @NDL_SubCode2
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1038, @sText_Old, @sText_New, @ODL_SubCode2, @NDL_SubCode2, null, null, 0, @bNeedCommunicationUpdate output
				END

			If (ISNULL(@ODL_PartnerKey, '''') != ISNULL(@NDL_PartnerKey, ''''))
			BEGIN
				Select @sText_Old = PR_Name from Partners where PR_Key = @ODL_PartnerKey
				Select @sText_New = PR_Name from Partners where PR_Key = @NDL_PartnerKey
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1039, @sText_Old, @sText_New, @ODL_PartnerKey, @NDL_PartnerKey, null, null, 0, @bNeedCommunicationUpdate output
			END
			If (ISNULL(@ODL_Control, '''') != ISNULL(@NDL_Control, ''''))
			BEGIN
				Select @sText_Old = CR_Name from Controls where CR_Key = @ODL_Control
				Select @sText_New = CR_Name from Controls where CR_Key = @NDL_Control
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1040, @sText_Old, @sText_New, @ODL_Control, @NDL_Control, null, null, 0, @bNeedCommunicationUpdate output
			END
			If (ISNULL(@ODL_CtKey, '''') != ISNULL(@NDL_CtKey, ''''))
			BEGIN
				Select @sText_Old = CT_Name from CityDictionary where CT_Key = @ODL_CtKey
				Select @sText_New = CT_Name from CityDictionary where CT_Key = @NDL_CtKey
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1041, @sText_Old, @sText_New, @ODL_CtKey, @NDL_CtKey, null, null, 0, @bNeedCommunicationUpdate output
			END
			If (ISNULL(@ODL_CnKey, '''') != ISNULL(@NDL_CnKey, ''''))
			BEGIN
				Select @sText_Old = CN_Name from Country where CN_Key = @ODL_CnKey
				Select @sText_New = CN_Name from Country where CN_Key = @NDL_CnKey
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1042, @sText_Old, @sText_New, @ODL_CnKey, @NDL_CnKey, null, null, 0, @bNeedCommunicationUpdate output
			END

		 	If (ISNULL(@ODL_NMen  , '''') != ISNULL(@NDL_NMen, ''''))
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1043, @ODL_NMen  , @NDL_NMen, '''', '''', null, null, 0, @bNeedCommunicationUpdate output
			If (ISNULL(@ODL_Cost, 0) != ISNULL(@NDL_Cost, 0))
			BEGIN	
				Set @sText_Old = CAST(@ODL_Cost as varchar(100))
				Set @sText_New = CAST(@NDL_Cost as varchar(100))				
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1044, @sText_Old, @sText_New, '''', '''', null, null, 0, @bNeedCommunicationUpdate output
			END
			If (ISNULL(@ODL_Brutto, 0) != ISNULL(@NDL_Brutto, 0))
			BEGIN	
				Set @sText_Old = CAST(@ODL_Brutto as varchar(100))
				Set @sText_New = CAST(@NDL_Brutto as varchar(100))				
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1045, @sText_Old, @sText_New, '''', '''', null, null, 0, @bNeedCommunicationUpdate output
			END
			If (ISNULL(@ODL_sDateBeg, 0) != ISNULL(@NDL_sDateBeg, 0))
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1046, @ODL_sDateBeg, @NDL_sDateBeg, null, null, @ODL_DateBeg, @NDL_DateBeg, 0, @bNeedCommunicationUpdate output
			If (ISNULL(@ODL_sDateEnd, 0) != ISNULL(@NDL_sDateEnd, 0))
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1047, @ODL_sDateEnd, @NDL_sDateEnd, null, null, @ODL_DateEnd, @NDL_DateEnd, 0, @bNeedCommunicationUpdate output
			If (ISNULL(@ODL_NDays, 0) != ISNULL(@NDL_NDays, 0))
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1048, @ODL_NDays, @NDL_NDays, null, null, null, null, 0, @bNeedCommunicationUpdate output

			If (ISNULL(@ODL_Wait, '''') != ISNULL(@NDL_Wait, '''')) 
			BEGIN
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1049, @ODL_Wait, @NDL_Wait, @ODL_Wait, @NDL_Wait, null, null, 0, @bNeedCommunicationUpdate output
			END
			
			If (ISNULL(@ODL_Name, 0) != ISNULL(@NDL_Name, 0))
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1050, @ODL_Name, @NDL_Name, null, null, null, null, 0, @bNeedCommunicationUpdate output
			If (ISNULL(@ODL_RealNetto, 0) != ISNULL(@NDL_RealNetto, 0))
			BEGIN
				Set @sText_Old = left(convert(varchar, @ODL_RealNetto), 10)
				Set @sText_New = left(convert(varchar, @NDL_RealNetto), 10)				
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1119, @sText_Old, @sText_New, '''', '''', null, null, 0, @bNeedCommunicationUpdate output
			END
			If (ISNULL(@ODL_Payed, 0) != ISNULL(@NDL_Payed, 0))
			BEGIN
				Set @sText_Old = CAST(@ODL_Payed as varchar(10))
				Set @sText_New = CAST(@NDL_Payed as varchar(10))				
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1120, @sText_Old, @sText_New, '''', '''', null, null, 0, @bNeedCommunicationUpdate output
			END
			If @ODL_TimeBeg!=@NDL_TimeBeg
			BEGIN
				Set @sText_Old=ISNULL(CONVERT(char(5), @ODL_TimeBeg, 114), 0)
				Set @sText_New=ISNULL(CONVERT(char(5), @NDL_TimeBeg, 114), 0)
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1125, @sText_Old, @sText_New, null, null, @ODL_TimeBeg, @NDL_TimeBeg, 0, @bNeedCommunicationUpdate output
			END
			
			If (ISNULL(@ODL_Control, '''') != ISNULL(@NDL_Control, '''')  OR ISNULL(@ODL_Wait, '''') != ISNULL(@NDL_Wait, ''''))
			BEGIN
				If exists (SELECT 1 FROM Communications WHERE CM_DGKey=@nDGKey and CM_PRKey in (@ODL_PartnerKey,@NDL_PartnerKey) )
					UPDATE Communications SET 
						CM_StatusConfirmed=(SELECT Count(1) FROM DogovorList, Controls WHERE DL_Control=CR_Key AND CR_GlobalState=1 AND DL_PartnerKey=CM_PRKey AND DL_DGKey=CM_DGKey),
						CM_StatusNotConfirmed=(SELECT Count(1) FROM DogovorList, Controls WHERE DL_Control=CR_Key AND CR_GlobalState=3 AND DL_PartnerKey=CM_PRKey AND DL_DGKey=CM_DGKey),
						CM_StatusWait=(SELECT Count(1) FROM DogovorList, Controls WHERE DL_Control=CR_Key AND CR_GlobalState=2 AND DL_PartnerKey=CM_PRKey AND DL_DGKey=CM_DGKey),
						CM_StatusUnknown=(SELECT Count(1) FROM DogovorList, Controls WHERE DL_Control=CR_Key AND CR_GlobalState is null AND DL_PartnerKey=CM_PRKey AND DL_DGKey=CM_DGKey)
					WHERE CM_DGKey=@nDGKey and CM_PRKey in (@ODL_PartnerKey,@NDL_PartnerKey)
			END
			If ( ( ISNULL(@ODL_Cost, 0) != ISNULL(@NDL_Cost, 0) ) or ( ISNULL(@ODL_RealNetto, 0) != ISNULL(@NDL_RealNetto, 0) ) )
			BEGIN	
				If exists (SELECT 1 FROM Communications WHERE CM_DGKey=@nDGKey and CM_PRKey in (@ODL_PartnerKey,@NDL_PartnerKey) )
					UPDATE Communications SET 
						CM_SumNettoPlan=(SELECT SUM(DL_Cost) FROM DogovorList WHERE DL_PartnerKey=CM_PRKey AND DL_DGKey=CM_DGKey),
						CM_SumNettoProvider=(SELECT SUM(DL_RealNetto) FROM DogovorList WHERE DL_PartnerKey=CM_PRKey AND DL_DGKey=CM_DGKey)
					WHERE CM_DGKey=@nDGKey and CM_PRKey in (@ODL_PartnerKey,@NDL_PartnerKey)
			END
			-- ИНДИВИДУАЛЬНАЯ ОБРАБОТКА АВИАПЕРЕЛЕТОВ
			If (@NDL_SvKey = 1 AND ((ISNULL(@ODL_Code, '''') != ISNULL(@NDL_Code, '''')) OR (ISNULL(@ODL_sDateBeg, 0) != ISNULL(@NDL_sDateBeg, 0)) OR ((ISNULL(@ODL_Name, 0) != ISNULL(@NDL_Name, 0)))))
			BEGIN
				DECLARE @APFrom_Old varchar(50), @APTo_Old varchar(50), @AL_Old varchar(50)
				IF ISNULL(@ODL_Code, '''') != ''''
				BEGIN
					SELECT 
						@sText_Old=CH_AirLineCode + '' '' + CH_Flight,
						@APFrom_Old=(SELECT TOP 1 AP_Name FROM AirPort WHERE AP_Code=CH_PortCodeFrom), 
						@APTo_Old=(SELECT TOP 1 AP_Name FROM AirPort WHERE AP_Code=CH_PortCodeTo), 
						@AL_Old=(SELECT TOP 1 AL_Name FROM AirLine WHERE AL_Code=CH_AirLineCode) 
						FROM Charter WHERE CH_Key=@ODL_Code
				END
				DECLARE @APFrom_New varchar(50), @APTo_New varchar(50), @AL_New varchar(50)
				IF ISNULL(@NDL_Code, '''') != ''''
				BEGIN
					SELECT 
						@sText_New=CH_AirLineCode + '' '' + CH_Flight,
						@APFrom_New=(SELECT TOP 1 AP_Name FROM AirPort WHERE AP_Code=CH_PortCodeFrom), 
						@APTo_New=(SELECT TOP 1 AP_Name FROM AirPort WHERE AP_Code=CH_PortCodeTo), 
						@AL_New=(SELECT TOP 1 AL_Name FROM AirLine WHERE AL_Code=CH_AirLineCode) 
						FROM Charter WHERE CH_Key=@NDL_Code
				END
				If (ISNULL(@ODL_Code, '''') != ISNULL(@NDL_Code, ''''))
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1027, @sText_Old, @sText_New, @ODL_Code, @NDL_Code, null, null, 0, @bNeedCommunicationUpdate output
				If (ISNULL(@APFrom_Old, '''') != ISNULL(@APFrom_New, ''''))
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1135, @APFrom_Old, @APFrom_New, null, null, null, null, 0, @bNeedCommunicationUpdate output
				If (ISNULL(@APTo_Old, '''') != ISNULL(@APTo_New, ''''))
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1136, @APTo_Old, @APTo_New, null, null, null, null, 0, @bNeedCommunicationUpdate output
				If (ISNULL(@AL_Old, '''') != ISNULL(@AL_New, ''''))
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1139, @AL_Old, @AL_New, null, null, null, null, 0, @bNeedCommunicationUpdate output

				DECLARE @sTimeBeg_Old varchar(5), @sTimeEnd_Old varchar(5), @sTimeBeg_New varchar(5), @sTimeEnd_New varchar(5)
				Declare @nday int
				IF (ISNULL(@ODL_Code, '''') != '''')
				BEGIN
					Set @nday = DATEPART(dw, @ODL_DateBeg)  + @@DATEFIRST - 1
					If @nday > 7 
		    			set @nday = @nday - 7
					SELECT	TOP 1 
						@sTimeBeg_Old=LEFT(CONVERT(varchar, AS_TimeFrom, 8),5),
						@sTimeEnd_Old=LEFT(CONVERT(varchar, AS_TimeTo, 8),5)
					FROM 	dbo.AirSeason
					WHERE 	AS_CHKey=@ODL_Code
						and CHARINDEX(CAST(@nday as varchar(1)),AS_Week)>0
						and @ODL_DateBeg between AS_DateFrom and AS_DateTo
					ORDER BY AS_TimeFrom DESC
				END

				IF (ISNULL(@NDL_Code, '''') != '''')
				BEGIN
					Set @nday = DATEPART(dw, @NDL_DateBeg)  + @@DATEFIRST - 1
					If @nday > 7 
						set @nday = @nday - 7
					SELECT	TOP 1 
						@sTimeBeg_New=LEFT(CONVERT(varchar, AS_TimeFrom, 8),5),
						@sTimeEnd_New=LEFT(CONVERT(varchar, AS_TimeTo, 8),5)
					FROM 	dbo.AirSeason
					WHERE 	AS_CHKey=@NDL_Code
						and CHARINDEX(CAST(@nday as varchar(1)),AS_Week)>0
						and @NDL_DateBeg between AS_DateFrom and AS_DateTo
					ORDER BY AS_TimeFrom DESC
				END
				If (ISNULL(@sTimeBeg_Old, '''') != ISNULL(@sTimeBeg_New, ''''))
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1137, @sTimeBeg_Old, @sTimeBeg_New, null, null, null, null, 0, @bNeedCommunicationUpdate output
				If (ISNULL(@sTimeEnd_Old, '''') != ISNULL(@sTimeEnd_New, ''''))
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1138, @sTimeEnd_Old, @sTimeEnd_New, null, null, null, null, 0, @bNeedCommunicationUpdate output
			END
		END
		
		/*Запись о том что нужно квотировать услугу*/
		-- только при измении этих полей нужно перезапустить механиз квотирования
		if ((isnull(@ODL_SvKey, '''') != isnull(@NDL_SvKey, '''')
			or isnull(@ODL_Code, '''') != isnull(@NDL_Code, '''')
			or isnull(@ODL_SubCode1, '''') != isnull(@NDL_SubCode1, '''')
			or isnull(@ODL_PartnerKey, '''') != isnull(@NDL_PartnerKey, '''')
			or isnull(@ODL_sDateBeg, '''') != isnull(@NDL_sDateBeg, '''')
			or isnull(@ODL_sDateEnd, '''') != isnull(@NDL_sDateEnd, '''')
			or isnull(@ODL_NMen, '''') != isnull(@NDL_NMen, ''''))
			and (exists (select top 1 1 from [Service] where SV_KEY = @NDL_SvKey and SV_QUOTED = 1))
			and (@sMod = ''UPD''))
		begin
			-- создаем запись о необходимости произвести рассадку в квоту
			insert into DogovorListNeedQuoted (DLQ_DLKey, DLQ_Date, DLQ_State, DLQ_Host, DLQ_User)
			values (@DL_Key, getdate(), 0, host_name(), user_name())
		end
		
		If @bNeedCommunicationUpdate=1
		BEGIN
			If @nSVKey=1 and ( 
					(ISNULL(@ODL_Code, '''') != ISNULL(@NDL_Code, '''')) or 
					(ISNULL(@ODL_sDateBeg, 0) != ISNULL(@NDL_sDateBeg, 0))
					 )
			BEGIN
				If exists (SELECT 1 FROM Communications WHERE CM_DGKey=@nDGKey)
					UPDATE Communications SET CM_ChangeDate=GetDate() WHERE CM_DGKey=@nDGKey
			END
			
			ELSE
			BEGIN
				If exists (SELECT 1 FROM Communications WHERE CM_DGKey=@nDGKey and CM_PRKey in (@ODL_PartnerKey,@NDL_PartnerKey) )
					UPDATE Communications SET CM_ChangeDate=GetDate() WHERE CM_DGKey=@nDGKey and CM_PRKey in (@ODL_PartnerKey,@NDL_PartnerKey)
			END
		END
		------------Аннуляция полиса при удаления услуги----------------------------------
		if (@sMod = ''DEL'')
		BEGIN
			UPDATE InsPolicy
			SET IP_ARKEY = 0, IP_AnnulDate = GetDate()
			WHERE IP_DLKey = @DL_KEY AND IP_ARKEY IS NULL AND IP_ANNULDATE IS NULL
		END

    	------------Для поддержки совместимости-------------------------------------------   

			If 	(ISNULL(@ODL_Code, '''') != ISNULL(@NDL_Code, '''')) or
				(ISNULL(@ODL_SubCode1, '''') != ISNULL(@NDL_SubCode1, '''')) or
				(ISNULL(@ODL_SubCode2, '''') != ISNULL(@NDL_SubCode2, '''')) or
				(ISNULL(@ODL_NDays, 0) != ISNULL(@NDL_NDays, 0)) or 
				(ISNULL(@ODL_Day, '''') != ISNULL(@NDL_Day, ''''))
				EXECUTE dbo.InsHistory @NDL_DgCod, @NDL_DGKey, 2, @DL_Key, ''MOD'', @ODL_Name, '''', 1, '''', 0, @nSVKey

			If 	(ISNULL(@ODL_Wait, '''') != ISNULL(@NDL_Wait, '''')) 
			BEGIN
				If (@NDL_Wait = 1)
					EXECUTE dbo.InsHistory @NDL_DgCod, @NDL_DGKey, 2, @DL_Key, ''+WL'', @ODL_Name, '''', 0, '''', 0, @nSVKey
				else
					EXECUTE dbo.InsHistory @NDL_DgCod, @NDL_DGKey, 2, @DL_Key, ''-WL'', @ODL_Name, '''', 0, '''', 0, @nSVKey
			END

		    FETCH NEXT FROM cur_DogovorList INTO 
		@DL_Key, 
			@ODL_DgCod, @ODL_DGKey, @ODL_SvKey, @ODL_Code, @ODL_SubCode1, @ODL_SubCode2, @ODL_CnKey, @ODL_CtKey, @ODL_NMen, @ODL_Day, @ODL_NDays, 
			@ODL_PartnerKey, @ODL_Cost, @ODL_Brutto, @ODL_Discount, @ODL_Wait, @ODL_Control, @ODL_DateBeg, @ODL_DateEnd, 
			@ODL_RealNetto, @ODL_Attribute, @ODL_PaketKey, @ODL_Name, @ODL_Payed, @ODL_QuoteKey, @ODL_TimeBeg,
			@NDL_DgCod, @NDL_DGKey, @NDL_SvKey, @NDL_Code, @NDL_SubCode1, @NDL_SubCode2, @NDL_CnKey, @NDL_CtKey, @NDL_NMen, @NDL_Day, @NDL_NDays, 
			@NDL_PartnerKey, @NDL_Cost, @NDL_Brutto, @NDL_Discount, @NDL_Wait, @NDL_Control, @NDL_DateBeg, @NDL_DateEnd, 
			@NDL_RealNetto, @NDL_Attribute, @NDL_PaketKey, @NDL_Name, @NDL_Payed, @NDL_QuoteKey, @NDL_TimeBeg
	END
  CLOSE cur_DogovorList
  DEALLOCATE cur_DogovorList
 END
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_DogovorListUpdate.sql', error_message())
END CATCH
end

print '############ end of file T_DogovorListUpdate.sql ################'

print '############ begin of file T_DogovorUpdate.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N''[dbo].[T_DogovorUpdate]''))
DROP TRIGGER [dbo].[T_DogovorUpdate]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_DogovorUpdate.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_DogovorUpdate]
ON [dbo].[tbl_Dogovor] 
FOR UPDATE, INSERT, DELETE
AS
--<VERSION>9.2</VERSION>
--<DATE>2014-04-04</DATE>
IF @@ROWCOUNT > 0
BEGIN
    DECLARE @sMod varchar(3)
    DECLARE @nDelCount int
    DECLARE @nInsCount int
	
    SELECT @nDelCount = COUNT(*) FROM DELETED
    SELECT @nInsCount = COUNT(*) FROM INSERTED
	
     -- При вставке все что связано со вставкой реализовано в .Net
    IF (@nDelCount = 0)
        RETURN

    DECLARE @ODG_Code		varchar(10)
    DECLARE @ODG_Price		float
    DECLARE @ODG_Rate		varchar(3)
    DECLARE @ODG_DiscountSum	float
    DECLARE @ODG_PartnerKey		int
    DECLARE @ODG_TRKey		int
    DECLARE @ODG_TurDate		datetime
    DECLARE @ODG_CTKEY		int
    DECLARE @ODG_NMEN		int
    DECLARE @ODG_NDAY		int
    DECLARE @ODG_PPaymentDate	varchar(16)
    DECLARE @ODG_PaymentDate	varchar(10)
    DECLARE @ODG_RazmerP		float
    DECLARE @ODG_Procent		int
    DECLARE @ODG_Locked		int
    DECLARE @ODG_SOR_Code	int
    DECLARE @ODG_IsOutDoc		int
    DECLARE @ODG_VisaDate		varchar(10)
    DECLARE @ODG_CauseDisc		int
    DECLARE @ODG_OWNER		int
    DECLARE @ODG_LEADDEPARTMENT	int
    DECLARE @ODG_DupUserKey	int
    DECLARE @ODG_MainMen		varchar(50)
    DECLARE @ODG_MainMenEMail	varchar(50)
    DECLARE @ODG_MAINMENPHONE	varchar(50)
    DECLARE @ODG_CodePartner	varchar(50)
    DECLARE @ODG_Creator		int
	DECLARE @ODG_CTDepartureKey int
	DECLARE @ODG_Payed money
	DECLARE @ODG_ProTourFlag int
	DECLARE @NDG_ProTourFlag int
    
    DECLARE @NDG_Code		varchar(10)
    DECLARE @NDG_Price		float
    DECLARE @NDG_Rate		varchar(3)
    DECLARE @NDG_DiscountSum	float
    DECLARE @NDG_PartnerKey		int
    DECLARE @NDG_TRKey		int
    DECLARE @NDG_TurDate		datetime
    DECLARE @NDG_CTKEY		int
    DECLARE @NDG_NMEN		int
    DECLARE @NDG_NDAY		int
    DECLARE @NDG_PPaymentDate	varchar(16)
    DECLARE @NDG_PaymentDate	varchar(10)
    DECLARE @NDG_RazmerP		float
    DECLARE @NDG_Procent		int
    DECLARE @NDG_Locked		int
    DECLARE @NDG_SOR_Code	int
    DECLARE @NDG_IsOutDoc		int
    DECLARE @NDG_VisaDate		varchar(10)
    DECLARE @NDG_CauseDisc		int
    DECLARE @NDG_OWNER		int
    DECLARE @NDG_LEADDEPARTMENT	int
    DECLARE @NDG_DupUserKey	int
    DECLARE @NDG_MainMen		varchar(50)
    DECLARE @NDG_MainMenEMail	varchar(50)
    DECLARE @NDG_MAINMENPHONE	varchar(50)
    DECLARE @NDG_CodePartner	varchar(50)
	DECLARE @NDG_Creator		int
	DECLARE @NDG_CTDepartureKey int
	DECLARE @NDG_Payed money

    DECLARE @sText_Old varchar(255)
    DECLARE @sText_New varchar(255)

    DECLARE @nValue_Old int
    DECLARE @nValue_New int

    DECLARE @DG_Key int
    
    DECLARE @nHIID int
    DECLARE @sHI_Text varchar(254)
	DECLARE @bNeedCommunicationUpdate smallint

	DECLARE @bUpdateNationalCurrencyPrice bit

	DECLARE @sUpdateMainDogovorStatuses varchar(254)
	
	DECLARE @nReservationNationalCurrencyRate smallint
	DECLARE @bReservationCreated smallint
	DECLARE @bCurrencyChangedPrevFixDate smallint
	DECLARE @bCurrencyChangedDate smallint
	DECLARE @bPriceChanged smallint
	DECLARE @bFeeChanged smallint
	DECLARE @bStatusChanged smallint
	DECLARE @statusChangedMultiplicity smallint
	DECLARE @changedDate datetime
	declare @dtCurrentDate datetime
	
    SELECT @nReservationNationalCurrencyRate = SS_PARMVALUE 
      FROM SystemSettings 
     WHERE SS_PARMNAME LIKE ''SYSReservationNCRate''
    SET @bReservationCreated = @nReservationNationalCurrencyRate & 1
    SET @bCurrencyChangedPrevFixDate = @nReservationNationalCurrencyRate & 2
    SET @bCurrencyChangedDate = @nReservationNationalCurrencyRate & 4
    SET @bPriceChanged = @nReservationNationalCurrencyRate & 8
    SET @bFeeChanged = @nReservationNationalCurrencyRate & 16
    SET @bStatusChanged = @nReservationNationalCurrencyRate & 32	
	SET @changedDate = getdate()
	set @dtCurrentDate = GETDATE()

  IF (@nDelCount = 0)
  BEGIN
	SET @sMod = ''INS''
    DECLARE cur_Dogovor CURSOR LOCAL FOR 
      SELECT N.DG_Key, 
		N.DG_Code, null, null, null, null, null, null, null, null, null,
		null, null, null, null, null, null, null, null, null, null, 
		null, null, null, null, null, null, null, null, null, null,
		N.DG_Code, N.DG_Price, N.DG_Rate, N.DG_DiscountSum, N.DG_PartnerKey, N.DG_TRKey, N.DG_TurDate, N.DG_CTKEY, N.DG_NMEN, N.DG_NDAY, 
		CONVERT( char(11), N.DG_PPaymentDate, 104) + CONVERT( char(5), N.DG_PPaymentDate, 108), CONVERT( char(10), N.DG_PaymentDate, 104), N.DG_RazmerP, N.DG_Procent, N.DG_Locked, N.DG_SOR_Code, N.DG_IsOutDoc, CONVERT( char(10), N.DG_VisaDate, 104), N.DG_CauseDisc, N.DG_OWNER, 
		N.DG_LEADDEPARTMENT, N.DG_DupUserKey, N.DG_MainMen, N.DG_MainMenEMail, N.DG_MAINMENPHONE, N.DG_CodePartner, N.DG_Creator, N.DG_CTDepartureKey, N.DG_Payed, N.DG_ProTourFlag
      FROM INSERTED N 
  END
  ELSE IF (@nInsCount = 0)
  BEGIN
	SET @sMod = ''DEL''
    DECLARE cur_Dogovor CURSOR LOCAL FOR 
      SELECT O.DG_Key,
		O.DG_Code, O.DG_Price, O.DG_Rate, O.DG_DiscountSum, O.DG_PartnerKey, O.DG_TRKey, O.DG_TurDate, O.DG_CTKEY, O.DG_NMEN, O.DG_NDAY, 
		CONVERT( char(11), O.DG_PPaymentDate, 104) + CONVERT( char(5), O.DG_PPaymentDate, 108), CONVERT( char(10), O.DG_PaymentDate, 104), O.DG_RazmerP, O.DG_Procent, O.DG_Locked, O.DG_SOR_Code, O.DG_IsOutDoc, CONVERT( char(10), O.DG_VisaDate, 104), O.DG_CauseDisc, O.DG_OWNER, 
		O.DG_LEADDEPARTMENT, O.DG_DupUserKey, O.DG_MainMen, O.DG_MainMenEMail, O.DG_MAINMENPHONE, O.DG_CodePartner, O.DG_Creator, O.DG_CTDepartureKey, O.DG_Payed, O.DG_ProTourFlag,
		null, null, null, null, null, null, null, null, null, null,
		null, null, null, null, null, null, null, null, null, null, 
		null, null, null, null, null, null, null, null, null, null
      FROM DELETED O 
  END
ELSE 
  BEGIN
  	SET @sMod = ''UPD''
    DECLARE cur_Dogovor CURSOR LOCAL FOR 
      SELECT N.DG_Key,
		O.DG_Code, O.DG_Price, O.DG_Rate, O.DG_DiscountSum, O.DG_PartnerKey, O.DG_TRKey, O.DG_TurDate, O.DG_CTKEY, O.DG_NMEN, O.DG_NDAY, 
		CONVERT( char(11), O.DG_PPaymentDate, 104) + CONVERT( char(5), O.DG_PPaymentDate, 108), CONVERT( char(10), O.DG_PaymentDate, 104), O.DG_RazmerP, O.DG_Procent, O.DG_Locked, O.DG_SOR_Code, O.DG_IsOutDoc, CONVERT( char(10), O.DG_VisaDate, 104), O.DG_CauseDisc, O.DG_OWNER, 
		O.DG_LEADDEPARTMENT, O.DG_DupUserKey, O.DG_MainMen, O.DG_MainMenEMail, O.DG_MAINMENPHONE, O.DG_CodePartner, O.DG_Creator, O.DG_CTDepartureKey, O.DG_Payed, O.DG_ProTourFlag,
		N.DG_Code, N.DG_Price, N.DG_Rate, N.DG_DiscountSum, N.DG_PartnerKey, N.DG_TRKey, N.DG_TurDate, N.DG_CTKEY, N.DG_NMEN, N.DG_NDAY, 
		CONVERT( char(11), N.DG_PPaymentDate, 104) + CONVERT( char(5), N.DG_PPaymentDate, 108),  CONVERT( char(10), N.DG_PaymentDate, 104), N.DG_RazmerP, N.DG_Procent, N.DG_Locked, N.DG_SOR_Code, N.DG_IsOutDoc,  CONVERT( char(10), N.DG_VisaDate, 104), N.DG_CauseDisc, N.DG_OWNER, 
		N.DG_LEADDEPARTMENT, N.DG_DupUserKey, N.DG_MainMen, N.DG_MainMenEMail, N.DG_MAINMENPHONE, N.DG_CodePartner, N.DG_Creator, N.DG_CTDepartureKey, N.DG_Payed, N.DG_ProTourFlag
      FROM DELETED O, INSERTED N 
      WHERE N.DG_Key = O.DG_Key
  END
  
    OPEN cur_Dogovor
    FETCH NEXT FROM cur_Dogovor INTO @DG_Key,
		@ODG_Code, @ODG_Price, @ODG_Rate, @ODG_DiscountSum, @ODG_PartnerKey, @ODG_TRKey, @ODG_TurDate, @ODG_CTKEY, @ODG_NMEN, @ODG_NDAY, 
		@ODG_PPaymentDate, @ODG_PaymentDate, @ODG_RazmerP, @ODG_Procent, @ODG_Locked, @ODG_SOR_Code, @ODG_IsOutDoc, @ODG_VisaDate, @ODG_CauseDisc, @ODG_OWNER, 
		@ODG_LEADDEPARTMENT, @ODG_DupUserKey, @ODG_MainMen, @ODG_MainMenEMail, @ODG_MAINMENPHONE, @ODG_CodePartner, @ODG_Creator, @ODG_CTDepartureKey, @ODG_Payed, @ODG_ProTourFlag,
		@NDG_Code, @NDG_Price, @NDG_Rate, @NDG_DiscountSum, @NDG_PartnerKey, @NDG_TRKey, @NDG_TurDate, @NDG_CTKEY, @NDG_NMEN, @NDG_NDAY, 
		@NDG_PPaymentDate, @NDG_PaymentDate, @NDG_RazmerP, @NDG_Procent, @NDG_Locked, @NDG_SOR_Code, @NDG_IsOutDoc, @NDG_VisaDate, @NDG_CauseDisc, @NDG_OWNER, 
		@NDG_LEADDEPARTMENT, @NDG_DupUserKey, @NDG_MainMen, @NDG_MainMenEMail, @NDG_MAINMENPHONE, @NDG_CodePartner, @NDG_Creator, @NDG_CTDepartureKey, @NDG_Payed, @NDG_ProTourFlag

    WHILE @@FETCH_STATUS = 0
    BEGIN	    
		DECLARE @ODG_TurDateS		varchar(10)
		Set @ODG_TurDateS = CONVERT( char(10), @ODG_TurDate, 104)
		DECLARE @NDG_TurDateS		varchar(10)
		Set @NDG_TurDateS = CONVERT( char(10), @NDG_TurDate, 104)
    	  ------------Проверка, надо ли что-то писать в историю-------------------------------------------   
	  If (
			ISNULL(@ODG_Code, '''') != ISNULL(@NDG_Code, '''') OR
			ISNULL(@ODG_Rate, '''') != ISNULL(@NDG_Rate, '''') OR
			ISNULL(@ODG_MainMen, '''') != ISNULL(@NDG_MainMen, '''') OR
			ISNULL(@ODG_MainMenEMail, '''') != ISNULL(@NDG_MainMenEMail, '''') OR
			ISNULL(@ODG_MAINMENPHONE, '''') != ISNULL(@NDG_MAINMENPHONE, '''') OR
			ISNULL(@ODG_Price, 0) != ISNULL(@NDG_Price, 0) OR
			ISNULL(@ODG_DiscountSum, 0) != ISNULL(@NDG_DiscountSum, 0) OR
			ISNULL(@ODG_PartnerKey, 0) != ISNULL(@NDG_PartnerKey, 0) OR
			ISNULL(@ODG_TRKey, 0) != ISNULL(@NDG_TRKey, 0) OR
			ISNULL(@ODG_TurDate, 0) != ISNULL(@NDG_TurDate, 0) OR
			ISNULL(@ODG_CTKEY, 0) != ISNULL(@NDG_CTKEY, 0) OR
			ISNULL(@ODG_NMEN, 0) != ISNULL(@NDG_NMEN, 0) OR
			ISNULL(@ODG_NDAY, 0) != ISNULL(@NDG_NDAY, 0) OR
			ISNULL(@ODG_PPaymentDate, 0) != ISNULL(@NDG_PPaymentDate, 0) OR
			ISNULL(@ODG_PaymentDate, 0) != ISNULL(@NDG_PaymentDate, 0) OR
			ISNULL(@ODG_RazmerP, 0) != ISNULL(@NDG_RazmerP, 0) OR
			ISNULL(@ODG_Procent, 0) != ISNULL(@NDG_Procent, 0) OR
			ISNULL(@ODG_Locked, 0) != ISNULL(@NDG_Locked, 0) OR
			ISNULL(@ODG_SOR_Code, 0) != ISNULL(@NDG_SOR_Code, 0) OR
			ISNULL(@ODG_IsOutDoc, 0) != ISNULL(@NDG_IsOutDoc, 0) OR
			ISNULL(@ODG_VisaDate, 0) != ISNULL(@NDG_VisaDate, 0) OR
			ISNULL(@ODG_CauseDisc, 0) != ISNULL(@NDG_CauseDisc, 0) OR
			ISNULL(@ODG_OWNER, 0) != ISNULL(@NDG_OWNER, 0) OR
			ISNULL(@ODG_LEADDEPARTMENT, 0) != ISNULL(@NDG_LEADDEPARTMENT, 0) OR
			ISNULL(@ODG_DupUserKey, 0) != ISNULL(@NDG_DupUserKey, 0) OR
			ISNULL(@ODG_CodePartner, '''') != ISNULL(@NDG_CodePartner, '''') OR
			ISNULL(@ODG_Creator, 0) != ISNULL(@NDG_Creator, 0) OR
			ISNULL(@ODG_CTDepartureKey, 0) != ISNULL(@NDG_CTDepartureKey, 0) OR
			ISNULL(@ODG_Payed, 0) != ISNULL(@NDG_Payed, 0)OR
			ISNULL(@ODG_ProTourFlag, 0) != ISNULL(@NDG_ProTourFlag, 0)
		)
	  BEGIN
	  	------------Запись в историю--------------------------------------------------------------------
		EXEC dbo.InsMasterEvent 4, @DG_Key

		if (@sMod = ''INS'')
			SET @sHI_Text = ISNULL(@NDG_Code, '''')
		else if (@sMod = ''DEL'')
			SET @sHI_Text = ISNULL(@ODG_Code, '''')
		else if (@sMod = ''UPD'')
			SET @sHI_Text = ISNULL(@NDG_Code, '''')

		EXEC @nHIID = dbo.InsHistory @sHI_Text, @DG_Key, 1, @DG_Key, @sMod, @sHI_Text, '''', 0, ''''
		--SELECT @nHIID = IDENT_CURRENT(''History'')
		IF(@sMod = ''INS'')
		BEGIN
			DECLARE @PrivatePerson int;
			EXEC @PrivatePerson = [dbo].[CheckPrivatePerson] @NDG_code;
			IF(@PrivatePerson = 0)
				IF(ISNULL(@NDG_DUPUSERKEY,-1) >= 0)
					EXEC [dbo].[UpdateReservationMainManByPartnerUser] @NDG_code;
		END
		--------Детализация--------------------------------------------------
		if (ISNULL(@ODG_Code, '''') != ISNULL(@NDG_Code, ''''))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1001, @ODG_Code, @NDG_Code, null, null, null, null, 0, @bNeedCommunicationUpdate output
		if (ISNULL(@ODG_Rate, '''') != ISNULL(@NDG_Rate, ''''))
			BEGIN
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1002, @ODG_Rate, @NDG_Rate, null, null, null, null, 0, @bNeedCommunicationUpdate output
				IF @bCurrencyChangedPrevFixDate > 0 OR @bCurrencyChangedDate > 0
					SET @bUpdateNationalCurrencyPrice = 1
				IF @bCurrencyChangedPrevFixDate > 0
					select @changedDate = dbo.GetLastDogovorFixationDate (@ODG_CODE, getdate(), 1)
			END
		if (ISNULL(@ODG_MainMen, '''') != ISNULL(@NDG_MainMen, ''''))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1003, @ODG_MainMen, @NDG_MainMen, null, null, null, null, 0, @bNeedCommunicationUpdate output
		if (ISNULL(@ODG_MainMenEMail, '''') != ISNULL(@NDG_MainMenEMail, ''''))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1004, @ODG_MainMenEMail, @NDG_MainMenEMail, null, null, null, null, 0, @bNeedCommunicationUpdate output
		if (ISNULL(@ODG_MAINMENPHONE, '''') != ISNULL(@NDG_MAINMENPHONE, ''''))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1005, @ODG_MAINMENPHONE, @NDG_MAINMENPHONE, null, null, null, null, 0, @bNeedCommunicationUpdate output
		if (ISNULL(@ODG_Price, 0) != ISNULL(@NDG_Price, 0))
			BEGIN
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1006, @ODG_Price, @NDG_Price, null, null, null, null, 0, @bNeedCommunicationUpdate output
				IF @bPriceChanged > 0
					SET @bUpdateNationalCurrencyPrice = 1
			END
		if (ISNULL(@ODG_DiscountSum, 0) != ISNULL(@NDG_DiscountSum, 0))
		BEGIN
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1007, @ODG_DiscountSum, @NDG_DiscountSum, null, null, null, null, 0, @bNeedCommunicationUpdate output
			IF @bFeeChanged > 0 
				SET @bUpdateNationalCurrencyPrice = 1
		END
		if (ISNULL(@ODG_PartnerKey, 0) != ISNULL(@NDG_PartnerKey, 0))
			BEGIN
				Select @sText_Old = PR_Name from Partners where PR_Key = @ODG_PartnerKey
				Select @sText_New = PR_Name from Partners where PR_Key = @NDG_PartnerKey
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1008, @sText_Old, @sText_New, @ODG_PartnerKey, @NDG_PartnerKey, null, null, 0, @bNeedCommunicationUpdate output
			END
		if (ISNULL(@ODG_TRKey, 0) != ISNULL(@NDG_TRKey, 0))
			BEGIN
				Select @sText_Old = TL_Name from Turlist where TL_Key = @ODG_TRKey
				Select @sText_New = TL_Name from Turlist where TL_Key = @NDG_TRKey
				If @NDG_TRKey is not null
					Update DogovorList set DL_TRKey=@NDG_TRKey where DL_DGKey=@DG_Key
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1009, @sText_Old, @sText_New, @ODG_TRKey, @NDG_TRKey, null, null, 0, @bNeedCommunicationUpdate output
			END
		if (ISNULL(@ODG_TurDate, '''') != ISNULL(@NDG_TurDate, ''''))
			BEGIN
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1010, @ODG_TurDateS, @NDG_TurDateS, null, null, null, null, 0, @bNeedCommunicationUpdate output

				Update DogovorList set DL_TURDATE = @NDG_TurDate where DL_DGKey = @DG_Key
				Update tbl_Turist set TU_TURDATE = @NDG_TurDate where TU_DGKey = @DG_Key

				--Путевка разаннулируется
				IF (ISNULL(@ODG_SOR_Code, 0) = 2)
				BEGIN
					DECLARE @nDGSorCode_New int, @sDisableDogovorStatusChange int

					SELECT @sDisableDogovorStatusChange = SS_ParmValue FROM SystemSettings WHERE SS_ParmName like ''SYSDisDogovorStatusChange''
					IF (@sDisableDogovorStatusChange is null or @sDisableDogovorStatusChange = ''0'')
					BEGIN
						exec dbo.SetReservationStatus @DG_Key
						-- 20611:CRM05885G9M9 Вызов перенесен в триггрер T_DogovorUpdate
						exec dbo.CreatePPaymentDate @NDG_Code, @NDG_TurDate, @dtCurrentDate
					END
				END
			END
		if (ISNULL(@ODG_CTKEY, 0) != ISNULL(@NDG_CTKEY, 0))
			BEGIN
				Select @sText_Old = CT_Name from CityDictionary  where CT_Key = @ODG_CTKEY
				Select @sText_New = CT_Name from CityDictionary  where CT_Key = @NDG_CTKEY
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1011, @sText_Old, @sText_New, @ODG_CTKEY, @NDG_CTKEY, null, null, 0, @bNeedCommunicationUpdate output
			END
		if (ISNULL(@ODG_NMEN, 0) != ISNULL(@NDG_NMEN, 0))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1012, @ODG_NMEN, @NDG_NMEN, null, null, null, null, 0, @bNeedCommunicationUpdate output
		if (ISNULL(@ODG_NDAY, 0) != ISNULL(@NDG_NDAY, 0))
		begin
			-- если изменилась продолжительность путевки, то нужно пересадить все услуги которые сидят на квотах 
			-- на продолжительность и сами не имеют продолжительности
			declare @DLKey int, @DLDateBeg datetime, @DLDateEnd datetime
			
			declare curSetQuoted CURSOR FORWARD_ONLY for
						select DL_KEY, DL_DATEBEG, DL_DATEEND
						from Dogovorlist join [Service] on SV_KEY = DL_SVKEY
						where DL_DGKEY = @DG_Key
						and isnull(SV_IsDuration, 0) = 0
			OPEN curSetQuoted
			FETCH NEXT FROM curSetQuoted INTO @DLKey, @DLDateBeg, @DLDateEnd

			WHILE @@FETCH_STATUS = 0
			BEGIN
				-- услуга сидит на квоте на продолжительность
				if (exists(select 1 from QuotaParts with(nolock) where LEN(ISNULL(QP_Durations, '''')) > 0 and QP_ID in (select SD_QPID from ServiceByDate with(nolock) where SD_DLKey = @DLKey)))
					EXEC DogListToQuotas @DLKey, null, null, null, null, @DLDateBeg, @DLDateEnd, null, null
			
				FETCH NEXT FROM curSetQuoted INTO @DLKey, @DLDateBeg, @DLDateEnd
			end
			CLOSE curSetQuoted
			DEALLOCATE curSetQuoted
			
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1013, @ODG_NDAY, @NDG_NDAY, null, null, null, null, 0, @bNeedCommunicationUpdate output
		end
		if (ISNULL(@ODG_PPaymentDate, 0) != ISNULL(@NDG_PPaymentDate, 0))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1014, @ODG_PPaymentDate, @NDG_PPaymentDate, null, null, null, null, 0, @bNeedCommunicationUpdate output
		if (ISNULL(@ODG_PaymentDate, 0) != ISNULL(@NDG_PaymentDate, 0))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1015, @ODG_PaymentDate, @NDG_PaymentDate, null, null, null, null, 0, @bNeedCommunicationUpdate output
		if (ISNULL(@ODG_RazmerP, 0) != ISNULL(@NDG_RazmerP, 0))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1016, @ODG_RazmerP, @NDG_RazmerP, null, null, null, null, 0, @bNeedCommunicationUpdate output
		if (ISNULL(@ODG_Procent, 0) != ISNULL(@NDG_Procent, 0))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1017, @ODG_Procent, @NDG_Procent, null, null, null, null, 0, @bNeedCommunicationUpdate output
		if (ISNULL(@ODG_Locked, 0) != ISNULL(@NDG_Locked, 0))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1018, @ODG_Locked, @NDG_Locked, null, null, null, null, 0, @bNeedCommunicationUpdate output
		
		--MEG00040358 вынесла запись истории из условия if (ISNULL(@ODG_SOR_Code, 0) != ISNULL(@NDG_SOR_Code, 0)),
		-- так как условие на вставку в этом блоке никогда не срабатывало, потому что в новой путевке @NDG_SOR_Code всегда нул , а @ODG_SOR_Code всегда ноль
		------путевка была создана--------------
		if (ISNULL(@ODG_SOR_Code, 0) = 0 and @sMod = ''INS'')
		begin
			EXECUTE dbo.InsertHistoryDetail @nHIID, 1122, null, null, null, null, null, null, 1, @bNeedCommunicationUpdate output
			-- 20611:CRM05885G9M9 Вызов перенесен в триггрер T_DogovorUpdate
			exec dbo.CreatePPaymentDate @NDG_Code, @NDG_TurDate, @dtCurrentDate
		end

		
		if (ISNULL(@ODG_SOR_Code, 0) != ISNULL(@NDG_SOR_Code, 0))
			BEGIN
				Select @sText_Old = OS_Name_Rus, @nValue_Old = OS_Global from Order_Status Where OS_Code = @ODG_SOR_Code
				Select @sText_New = OS_Name_Rus, @nValue_New = OS_Global from Order_Status Where OS_Code = @NDG_SOR_Code
				If @nValue_New = 7 and @nValue_Old != 7
					UPDATE [dbo].[tbl_Dogovor] SET DG_ConfirmedDate = GetDate() WHERE DG_Key = @DG_Key
				If @nValue_New != 7 and @nValue_Old = 7
					UPDATE [dbo].[tbl_Dogovor] SET DG_ConfirmedDate = NULL WHERE DG_Key = @DG_Key
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1019, @sText_Old, @sText_New, @ODG_SOR_Code, @NDG_SOR_Code, null, null, 0, @bNeedCommunicationUpdate output
				
				------путевка была аннулирована--------------
				if (@NDG_SOR_Code = 2 and @sMod = ''UPD'')
					EXECUTE dbo.InsertHistoryDetail @nHIID, 1123, null, null, null, null, null, null, 1, @bNeedCommunicationUpdate output
				
				if @bStatusChanged > 0 and exists(select NC_Id from NationalCurrencyReservationStatuses with(nolock) where NC_OrderStatus = ISNULL(@NDG_SOR_Code, 0))
				begin
					-- Получаем кратность 
					select @statusChangedMultiplicity = NC_Multiplicity from NationalCurrencyReservationStatuses with(nolock) where NC_OrderStatus = ISNULL(@NDG_SOR_Code, 0)
					if (@statusChangedMultiplicity = 1 OR @bCurrencyChangedPrevFixDate > 0) -- Кратность: только один раз 
					begin -- либо включена опция, что при смене валюты стоимость пересчитывается по дате предыдущей фиксации
						-- пытаемя получить дату первой установки нужного статуса, либо текущую дату, если еще не фиксировали
						set @changedDate = ISNULL(dbo.GetFirstDogovorStatusDate (@DG_Key, @NDG_SOR_Code), GetDate())
					end
					if (@statusChangedMultiplicity = 2)	-- Кратность: каждый раз при смене статуса, берем текущую дату 
					begin
						set @changedDate = GetDate()
					end
					SET @bUpdateNationalCurrencyPrice = 1
				end
				-- 20611:CRM05885G9M9 Вызов перенесен в триггрер T_DogovorUpdate
				exec dbo.CreatePPaymentDate @NDG_Code, @NDG_TurDate, @dtCurrentDate
			END
		if (ISNULL(@ODG_IsOutDoc, 0) != ISNULL(@NDG_IsOutDoc, 0))
			BEGIN
				Select @sText_Old = DS_Name from DocumentStatus Where DS_Key = @ODG_IsOutDoc
				Select @sText_New = DS_Name from DocumentStatus Where DS_Key = @NDG_IsOutDoc
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1020, @sText_Old, @sText_New, @ODG_IsOutDoc, @NDG_IsOutDoc, null, null, 0, @bNeedCommunicationUpdate output
			END
		if (ISNULL(@ODG_VisaDate, 0) != ISNULL(@NDG_VisaDate, 0))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1021, @ODG_VisaDate, @NDG_VisaDate, null, null, null, null, 0, @bNeedCommunicationUpdate output
		if (ISNULL(@ODG_CauseDisc, 0) != ISNULL(@NDG_CauseDisc, 0))
			BEGIN
				Select @sText_Old = CD_Name from CauseDiscounts Where CD_Key = @ODG_CauseDisc
				Select @sText_New = CD_Name from CauseDiscounts Where CD_Key = @NDG_CauseDisc
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1022, @sText_Old, @sText_New, @ODG_CauseDisc, @NDG_CauseDisc, null, null, 0, @bNeedCommunicationUpdate output
			END
		if (ISNULL(@ODG_OWNER, 0) != ISNULL(@NDG_OWNER, 0))
			BEGIN
				Select @sText_Old = US_FullName from UserList Where US_Key = @ODG_Owner
				Select @sText_New = US_FullName from UserList Where US_Key = @NDG_Owner
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1023, @sText_Old, @sText_New, @ODG_Owner, @NDG_Owner, null, null, 0, @bNeedCommunicationUpdate output
			END
		if (ISNULL(@ODG_Creator, 0) != ISNULL(@NDG_Creator, 0))
			BEGIN
				Select @sText_Old = US_FullName from UserList Where US_Key = @ODG_Creator
				Select @sText_New = US_FullName from UserList Where US_Key = @NDG_Creator
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1117, @sText_Old, @sText_New, @ODG_Creator, @NDG_Creator, null, null, 0, @bNeedCommunicationUpdate output
				Select @nValue_Old = US_DepartmentKey from UserList Where US_Key = @ODG_Creator
				Select @nValue_New = US_DepartmentKey from UserList Where US_Key = @NDG_Creator
				if (@nValue_Old is not null OR @nValue_New is not null)
					EXECUTE dbo.InsertHistoryDetail @nHIID , 1134, @nValue_Old, @nValue_New, null, null, null, null, 0, @bNeedCommunicationUpdate output
			END
		if (ISNULL(@ODG_LEADDEPARTMENT, 0) != ISNULL(@NDG_LeadDepartment, 0))
			BEGIN
				Select @sText_Old = PDP_Name from PrtDeps where PDP_Key = @ODG_LeadDepartment
				Select @sText_New = PDP_Name from PrtDeps where PDP_Key = @NDG_LeadDepartment
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1024, @sText_Old, @sText_New, @ODG_LeadDepartment, @NDG_LeadDepartment, null, null, 0, @bNeedCommunicationUpdate output
			END
		if (ISNULL(@ODG_DupUserKey, 0) != ISNULL(@NDG_DupUserKey, 0))
			BEGIN
				Select @sText_Old = US_FullName FROM Dup_User WHERE US_Key = @ODG_DupUserKey
				Select @sText_New = US_FullName FROM Dup_User WHERE US_Key = @NDG_DupUserKey
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1025, @sText_Old, @sText_New, @ODG_DupUserKey, @NDG_DupUserKey, null, null, 0, @bNeedCommunicationUpdate output
			END
		if (ISNULL(@ODG_CTDepartureKey, 0) != ISNULL(@NDG_CTDepartureKey, 0))
			BEGIN
				Select @sText_Old = CT_Name FROM CityDictionary WHERE CT_Key = @ODG_CTDepartureKey
				Select @sText_New = CT_Name FROM CityDictionary WHERE CT_Key = @NDG_CTDepartureKey
				EXECUTE dbo.InsertHistoryDetail @nHIID , 1121, @sText_Old, @sText_New, @ODG_CTDepartureKey, @NDG_CTDepartureKey, null, null, 0, @bNeedCommunicationUpdate output
			END
		if (ISNULL(@ODG_CodePartner, '''') != ISNULL(@NDG_CodePartner, ''''))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 1026, @ODG_CodePartner, @NDG_CodePartner, null, null, null, null, 0, @bNeedCommunicationUpdate output

		if (ISNULL(@ODG_Payed, 0) != ISNULL(@NDG_Payed, 0))
		begin
			declare @varcharODGPayed varchar(255), @varcharNDGPayed varchar(255)
			set @varcharODGPayed = cast(@ODG_Payed as varchar(255))
			set @varcharNDGPayed = cast(@NDG_Payed as varchar(255))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 5, @varcharODGPayed, @varcharNDGPayed, null, null, null, null, 0, @bNeedCommunicationUpdate output
		end
		IF (ISNULL(@ODG_ProTourFlag, 0) != ISNULL(@NDG_ProTourFlag, 0))
			EXECUTE dbo.InsertHistoryDetail @nHIID , 399999, @ODG_ProTourFlag, @NDG_ProTourFlag, null, null, null, null, 0, @bNeedCommunicationUpdate output

		If @bNeedCommunicationUpdate=1
			If exists (SELECT 1 FROM Communications WHERE CM_DGKey=@DG_Key)
				UPDATE Communications SET CM_ChangeDate=GetDate() WHERE CM_DGKey=@DG_Key

		
		-- $$$ PRICE RECALCULATION $$$ --
		IF (@bUpdateNationalCurrencyPrice = 1 AND @sMod = ''UPD'') OR (@sMod = ''INS'' AND @bReservationCreated > 0)
		BEGIN
			--если не удалось определить дату, на которую рассчитывается и стоит настройка брать жату создания путевки, то ее и берем
			if @changedDate is null and @bReservationCreated > 0				
				select @changedDate = DG_CrDate from inserted i where i.dg_key = @DG_Key				   
				
			EXEC dbo.NationalCurrencyPrice2 @NDG_Rate, @ODG_Rate, @ODG_Code, @NDG_Price, @ODG_Price, @NDG_DiscountSum, @changedDate, @NDG_SOR_Code
		END
	  END

		-- recalculate if exchange rate changes (another table) & saving from frmDogovor (tour.apl)
		-- + force-drop #RecalculateAction table in case hasn''t been
		/*IF OBJECT_ID(''tempdb..#RecalculateAction'') IS NOT NULL
		BEGIN
            DECLARE @AlwaysRecalcPrice int 
            SELECT  @AlwaysRecalcPrice = isnull(SS_ParmValue,0) FROM dbo.systemsettings  
            WHERE SS_ParmName = ''SYSAlwaysRecalcNational'' 

			SELECT @DGCODE  = [DGCODE] FROM #RecalculateAction
			if @DGCODE = @NDG_Code
			begin
				SELECT @sAction = [Action] FROM #RecalculateAction
				DROP TABLE #RecalculateAction
				if @AlwaysRecalcPrice > 0
					EXEC dbo.NationalCurrencyPrice @ODG_Rate, @NDG_Rate, @ODG_Code, @NDG_Price, @ODG_Price, @NDG_DiscountSum, @sAction, @NDG_SOR_Code
		    end
		END*/
		-- $$$ ------------------- $$$ --

        -- Task 7613. rozin. 27.08.2012. Добавление Предупреждений и Комментариев (таблица PrtWarns) по партнеру в историю при создании путевки
		IF(@sMod = ''INS'')
		BEGIN
			DECLARE @warningTextPattern varchar(128)        
			DECLARE @warningText varchar(256)       
			DECLARE @warningType varchar(256)       
			DECLARE @warningMessage varchar(256) 
			DECLARE @partnerName varchar(256)
			DECLARE cur_PrtWarns CURSOR LOCAL FOR
				SELECT PW_Text, PW_Type
				FROM PrtWarns 
				WHERE PW_PRKey = @NDG_PartnerKey AND PW_IsAddToHistory = 1
	        
			SET @warningTextPattern = ''Прошу обратить внимание, что по заявке [1] у партнера [2] имеется [3]: [4]''
	        
			OPEN cur_PrtWarns
			FETCH NEXT FROM cur_PrtWarns INTO @warningText, @warningType
	        
			WHILE @@FETCH_STATUS = 0
			BEGIN 		
				SET @warningMessage = REPLACE(@warningTextPattern, ''[1]'', @NDG_Code)
				
				select @partnerName = pr_name from tbl_Partners where pr_key = @NDG_PartnerKey
				SET @warningMessage = REPLACE(@warningMessage, ''[2]'', @partnerName)
				
				IF (@warningType = 2)
					SET @warningMessage = REPLACE(@warningMessage, ''[3]'', ''предупреждение'')
				ELSE IF (@warningType = 3)
					SET @warningMessage = REPLACE(@warningMessage, ''[3]'', ''комментарий'')
				ELSE
					SET @warningMessage = REPLACE(@warningMessage, ''[3]'', '''') -- таких сутуаций быть не должно
				
				SET @warningMessage = REPLACE(@warningMessage, ''[4]'', @warningText)
				
				EXEC dbo.InsHistory @NDG_Code, @DG_Key, NULL, NULL, ''MTM'', @warningMessage, '''', 0, '''', 1
				FETCH NEXT FROM cur_PrtWarns INTO @warningText, @warningType
			END
	        
			CLOSE cur_PrtWarns
			DEALLOCATE cur_PrtWarns
		END
        -- END Task 7613
        
		DECLARE @DG_NATIONALCURRENCYPRICE money
	    DECLARE @DG_NATIONALCURRENCYDISCOUNTSUM money
		SET @DG_NATIONALCURRENCYPRICE = NULL
		SET @DG_NATIONALCURRENCYDISCOUNTSUM = NULL

		SELECT @DG_NATIONALCURRENCYPRICE = DG_NATIONALCURRENCYPRICE, @DG_NATIONALCURRENCYDISCOUNTSUM = DG_NATIONALCURRENCYDISCOUNTSUM FROM DOGOVOR 
		WHERE DG_KEY=@DG_Key
		 --Task 12886 04/04/2013 o.omelchenko - если идет инсерт и нац валюта не просчиталась, то считаем её на текущую дату
        if(@sMod = ''INS'' and (@DG_NATIONALCURRENCYPRICE IS NULL OR @DG_NATIONALCURRENCYDISCOUNTSUM  IS NULL))
        BEGIN
            SET @changedDate = GETDATE()
            EXEC dbo.NationalCurrencyPrice2 @NDG_Rate, @ODG_Rate, @ODG_Code, @NDG_Price, @ODG_Price, @NDG_DiscountSum, @changedDate, @NDG_SOR_Code, 0 
        END
		-- Task 10558 tfs neupokoev 26.12.2012
		-- Повторная фиксация курса валюты, в случае если он не зафиксировался
		IF(@sMod = ''UPD'')
			BEGIN			

				IF(@DG_NATIONALCURRENCYPRICE IS NULL OR @DG_NATIONALCURRENCYDISCOUNTSUM  IS NULL)
					BEGIN
						EXEC dbo.ReСalculateNationalRatePrice @DG_KEY, @NDG_Rate, @ODG_Rate, @ODG_Code, @NDG_Price, @ODG_Price, @NDG_DiscountSum, @NDG_SOR_Code
					END 
					
			    -- Если нету фиксации, то перерасчитываем на текущую дату
				IF not exists(select * from History where HI_DGKEY =@DG_KEY and (HI_OAId = 20 or HI_OAId = 21))
				BEGIN					     
					  EXEC dbo.NationalCurrencyPrice2 @NDG_Rate, @ODG_Rate, @ODG_Code, @NDG_Price, @ODG_Price, @NDG_DiscountSum, @changedDate, @NDG_SOR_Code, 0            
				END 
			END
		-- end Task 10558
        
    	  FETCH NEXT FROM cur_Dogovor INTO @DG_Key,
		@ODG_Code, @ODG_Price, @ODG_Rate, @ODG_DiscountSum, @ODG_PartnerKey, @ODG_TRKey, @ODG_TurDate, @ODG_CTKEY, @ODG_NMEN, @ODG_NDAY, 
		@ODG_PPaymentDate, @ODG_PaymentDate, @ODG_RazmerP, @ODG_Procent, @ODG_Locked, @ODG_SOR_Code, @ODG_IsOutDoc, @ODG_VisaDate, @ODG_CauseDisc, @ODG_OWNER, 
		@ODG_LEADDEPARTMENT, @ODG_DupUserKey, @ODG_MainMen, @ODG_MainMenEMail, @ODG_MAINMENPHONE, @ODG_CodePartner, @ODG_Creator, @ODG_CTDepartureKey, @ODG_Payed, @ODG_ProTourFlag,
		@NDG_Code, @NDG_Price, @NDG_Rate, @NDG_DiscountSum, @NDG_PartnerKey, @NDG_TRKey, @NDG_TurDate, @NDG_CTKEY, @NDG_NMEN, @NDG_NDAY, 
		@NDG_PPaymentDate, @NDG_PaymentDate, @NDG_RazmerP, @NDG_Procent, @NDG_Locked, @NDG_SOR_Code, @NDG_IsOutDoc, @NDG_VisaDate, @NDG_CauseDisc, @NDG_OWNER, 
		@NDG_LEADDEPARTMENT, @NDG_DupUserKey, @NDG_MainMen, @NDG_MainMenEMail, @NDG_MAINMENPHONE, @NDG_CodePartner, @NDG_Creator, @NDG_CTDepartureKey, @NDG_Payed, @NDG_ProTourFlag
    END
  CLOSE cur_Dogovor
  DEALLOCATE cur_Dogovor
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_DogovorUpdate.sql', error_message())
END CATCH
end

print '############ end of file T_DogovorUpdate.sql ################'

print '############ begin of file T_DUP_USERDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_DUP_USERDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_DUP_USERDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_DUP_USERDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_DUP_USERDelete]
   ON [dbo].[DUP_USER]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''DUP_USER'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''US_Key, US_FullName'', US_Key, US_FullName, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_DUP_USERDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_DUP_USERDelete.sql', error_message())
END CATCH
end

print '############ end of file T_DUP_USERDelete.sql ################'

print '############ begin of file T_ExcurDictionaryDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_ExcurDictionaryDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_ExcurDictionaryDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ExcurDictionaryDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_ExcurDictionaryDelete]
   ON [dbo].[ExcurDictionary]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''ExcurDictionary'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''ED_Key, ED_Name'', ED_Key, ED_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ExcurDictionaryDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_ExcurDictionaryDelete.sql', error_message())
END CATCH
end

print '############ end of file T_ExcurDictionaryDelete.sql ################'

print '############ begin of file T_HotelDictionaryDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_HotelDictionaryDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
DROP TRIGGER [dbo].[T_HotelDictionaryDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_HotelDictionaryDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_HotelDictionaryDelete]
   ON [dbo].[HotelDictionary]
   AFTER DELETE
AS 
BEGIN
	--<DATE>2015-11-12</DATE>
	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''HotelDictionary'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''HD_Key, HD_Name'', HD_Key, HD_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_HotelDictionaryDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_HotelDictionaryDelete.sql', error_message())
END CATCH
end

print '############ end of file T_HotelDictionaryDelete.sql ################'

print '############ begin of file T_HotelTypesDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_HotelTypesDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_HotelTypesDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_HotelTypesDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_HotelTypesDelete]
   ON [dbo].[HotelTypes]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''HotelTypes'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''HTT_ID, HTT_Name'', HTT_ID, HTT_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_HotelTypesDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_HotelTypesDelete.sql', error_message())
END CATCH
end

print '############ end of file T_HotelTypesDelete.sql ################'

print '############ begin of file T_Order_StatusDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_Order_StatusDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_Order_StatusDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_Order_StatusDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_Order_StatusDelete]
   ON [dbo].[Order_Status]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Order_Status'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''OS_CODE, OS_Name_Rus'', OS_CODE, OS_Name_Rus, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_Order_StatusDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_Order_StatusDelete.sql', error_message())
END CATCH
end

print '############ end of file T_Order_StatusDelete.sql ################'

print '############ begin of file T_PansionDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_PansionDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_PansionDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_PansionDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_PansionDelete]
   ON [dbo].[Pansion]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Pansion'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''PN_Key, PN_Name'', PN_Key, PN_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_PansionDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_PansionDelete.sql', error_message())
END CATCH
end

print '############ end of file T_PansionDelete.sql ################'

print '############ begin of file T_ProfessionDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_ProfessionDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_ProfessionDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ProfessionDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_ProfessionDelete]
   ON [dbo].[Profession]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Profession'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''PF_Key, PF_Name'', PF_Key, PF_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ProfessionDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_ProfessionDelete.sql', error_message())
END CATCH
end

print '############ end of file T_ProfessionDelete.sql ################'

print '############ begin of file T_PrtDepsDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_PrtDepsDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_PrtDepsDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_PrtDepsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_PrtDepsDelete]
   ON [dbo].[PrtDeps]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''PrtDeps'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''PDP_Key, PDP_Name'', PDP_Key, PDP_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_PrtDepsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_PrtDepsDelete.sql', error_message())
END CATCH
end

print '############ end of file T_PrtDepsDelete.sql ################'

print '############ begin of file T_PrtDogTypesDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_PrtDogTypesDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_PrtDogTypesDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_PrtDogTypesDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_PrtDogTypesDelete]
   ON [dbo].[PrtDogTypes]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-12</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''PrtDogTypes'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''PDT_ID, PDT_Name'', PDT_ID, PDT_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_PrtDogTypesDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_PrtDogTypesDelete.sql', error_message())
END CATCH
end

print '############ end of file T_PrtDogTypesDelete.sql ################'

print '############ begin of file T_PrtGroupsDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_PrtGroupsDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_PrtGroupsDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_PrtGroupsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_PrtGroupsDelete]
   ON [dbo].[PrtGroups]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''PrtGroups'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''PG_Key, PG_Name'', PG_Key, PG_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_PrtGroupsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_PrtGroupsDelete.sql', error_message())
END CATCH
end

print '############ end of file T_PrtGroupsDelete.sql ################'

print '############ begin of file T_PrtTypesDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_PrtTypesDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_PrtTypesDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_PrtTypesDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_PrtTypesDelete]
   ON [dbo].[PrtTypes]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''PrtTypes'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''PT_ID, PT_Name'', PT_ID, PT_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_PrtTypesDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_PrtTypesDelete.sql', error_message())
END CATCH
end

print '############ end of file T_PrtTypesDelete.sql ################'

print '############ begin of file T_RatesDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_RatesDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_RatesDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_RatesDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_RatesDelete]
   ON [dbo].[Rates]
   AFTER DELETE
AS 
BEGIN
	--удаляем маппинги из таблицы GDSMappings
	delete from GDSMappings 
	where GM_DICTIONARYID = 8 and GM_MTDICTIONARYITEMID in (select deleted.ra_key from deleted)

	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Rates'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''RA_Key, RA_Name'', RA_Key, RA_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_RatesDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_RatesDelete.sql', error_message())
END CATCH
end

print '############ end of file T_RatesDelete.sql ################'

print '############ begin of file T_ResortsDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_ResortsDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_ResortsDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ResortsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_ResortsDelete]
   ON [dbo].[Resorts]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Resorts'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''RS_Key, RS_Name'', RS_Key, RS_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ResortsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_ResortsDelete.sql', error_message())
END CATCH
end

print '############ end of file T_ResortsDelete.sql ################'

print '############ begin of file T_RoomsCategoryDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_RoomsCategoryDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_RoomsCategoryDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_RoomsCategoryDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_RoomsCategoryDelete]
   ON [dbo].[RoomsCategory]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''RoomsCategory'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''RC_Key, RC_Name'', RC_Key, RC_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_RoomsCategoryDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_RoomsCategoryDelete.sql', error_message())
END CATCH
end

print '############ end of file T_RoomsCategoryDelete.sql ################'

print '############ begin of file T_RoomsDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_RoomsDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_RoomsDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_RoomsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_RoomsDelete]
   ON [dbo].[Rooms]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Rooms'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''RM_Key, RM_Name'', RM_Key, RM_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_RoomsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_RoomsDelete.sql', error_message())
END CATCH
end

print '############ end of file T_RoomsDelete.sql ################'

print '############ begin of file T_Service.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N''[dbo].[T_Service]''))
DROP TRIGGER [dbo].[T_Service]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_Service.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_Service]
   ON  [dbo].[Service]
   AFTER UPDATE
AS
BEGIN
--<DATE>2017-07-14</DATE>
		--if (EXISTS (SELECT * FROM deleted join inserted on deleted.sv_key = inserted.sv_key AND (deleted.SV_ISCITY <> inserted.SV_ISCITY OR deleted.SV_ISSUBCODE1 <> inserted.SV_ISSUBCODE1 OR deleted.SV_ISSUBCODE2 <> inserted.SV_ISSUBCODE2) AND (dbo.fn_GetServiceLink(inserted.sv_key) = 1)))
		--BEGIN
		--	ROLLBACK TRANSACTION
		--	RAISERROR(''Нельзя изменить привязку местоположения и описание, если по классу услуг есть зависимости'',16,1)
		--END
		if (EXISTS (SELECT * FROM deleted join inserted on deleted.sv_key = inserted.sv_key AND inserted.sv_key = 14 AND deleted.SV_QUOTED <> inserted.SV_QUOTED ))
		BEGIN
			UPDATE SystemSettings set SS_ParmValue = ''0'' where SS_ParmName=''SYSShowBusTransferPlaces''
		END
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_Service.sql', error_message())
END CATCH
end

print '############ end of file T_Service.sql ################'

print '############ begin of file T_ServiceByDateChanged.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists(select id from sysobjects where xtype=''TR'' and name=''T_ServiceByDateChanged'')
	-- удал¤ю лишний триггер
	drop trigger dbo.T_ServiceByDateChanged
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ServiceByDateChanged.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_ServiceByDateChanged] ON [dbo].[ServiceByDate]
AFTER INSERT, UPDATE, DELETE
AS
--<DATE>2014-10-16</DATE>
--<VERSION>2009.2.20.23</VERSION>
DECLARE @sMod varchar(3), @nHIID int, @sDGCode varchar(10), @nDGKey int, @sDLName varchar(150), @sTemp varchar(25), @sTemp2 varchar(255), @sTuristName varchar(55)
DECLARE @sOldValue varchar(255), @sNewValue varchar(255), @nOldValue int, @nNewValue int, @SDDate datetime
DECLARE @nRowsCount int, @sServiceStatusToHistory varchar(255)

DECLARE @SDID int, @N_SD_DLKey int, @N_SD_RLID int, @N_SD_TUKEY int, @N_SD_QPID int, @N_SD_State int, @N_SD_Date datetime,
		@O_SD_DLKey int, @O_SD_RLID int, @O_SD_TUKEY int, @O_SD_QPID int, @O_SD_State int, @O_SD_Date datetime, @QT_ByRoom bit,
		@nDelCount int, @nInsCount int, @DLDateBeg datetime, @DLNDays int, @QState int, @NewQState int, @QD_ID int

SELECT @nDelCount = COUNT(*) FROM DELETED
SELECT @nInsCount = COUNT(*) FROM INSERTED
IF (@nInsCount = 0)
BEGIN
    DECLARE cur_ServiceByDateChanged CURSOR local FAST_FORWARD FOR 
    SELECT 	O.SD_ID,
			O.SD_DLKey, O.SD_RLID, O.SD_TUKey, O.SD_QPID, O.SD_State, O.SD_Date,
			null, null, null, null, null, null
    FROM DELETED O
END
ELSE IF (@nDelCount = 0)
BEGIN
    DECLARE cur_ServiceByDateChanged CURSOR local FAST_FORWARD FOR 
    SELECT 	N.SD_ID,
			null, null, null, null, null, null,
			N.SD_DLKey, N.SD_RLID, N.SD_TUKey, N.SD_QPID, N.SD_State, N.SD_Date
			--DL_DateBeg, DL_NDays
    FROM	INSERTED N
	--LEFT OUTER JOIN tbl_DogovorList ON N.SD_DLKey = DL_Key
	-- CRM01871H3T9 30.05.2012 kolbeshkin: отсеиваем неквотируемые услуги, дл¤ них триггер не должен отрабатывать
	where exists (select 1 from DogovorList,[Service] where DL_KEY=N.SD_DLKey and DL_SVKEY=SV_KEY 
    and ISNULL(SV_QUOTED,0)<>0)
END
ELSE 
BEGIN
    DECLARE cur_ServiceByDateChanged CURSOR local FAST_FORWARD FOR 
    SELECT 	N.SD_ID,
			O.SD_DLKey, O.SD_RLID, O.SD_TUKey, O.SD_QPID, O.SD_State, O.SD_Date,
	  		N.SD_DLKey, N.SD_RLID, N.SD_TUKey, N.SD_QPID, N.SD_State, N.SD_Date
			--DL_DateBeg, DL_NDays
    FROM DELETED O, INSERTED N
	--LEFT OUTER JOIN tbl_DogovorList ON N.SD_DLKey = DL_Key 
    WHERE N.SD_ID = O.SD_ID
	-- CRM01871H3T9 30.05.2012 kolbeshkin: отсеиваем неквотируемые услуги, дл¤ них триггер не должен отрабатывать
	and exists (select 1 from DogovorList,[Service] where DL_KEY=N.SD_DLKey and DL_SVKEY=SV_KEY 
    and ISNULL(SV_QUOTED,0)<>0)
END

select @sServiceStatusToHistory = SS_ParmValue from SystemSettings where SS_ParmName like ''SYSServiceStatusToHistory''

declare @RLIDCount int

OPEN cur_ServiceByDateChanged
FETCH NEXT FROM cur_ServiceByDateChanged 
	INTO @SDID, @O_SD_DLKey, @O_SD_RLID, @O_SD_TUKEY, @O_SD_QPID, @O_SD_State, @O_SD_Date,
				@N_SD_DLKey, @N_SD_RLID, @N_SD_TUKEY, @N_SD_QPID, @N_SD_State, @N_SD_Date
				--@DLDateBeg, @DLNDays
WHILE @@FETCH_STATUS = 0
BEGIN
	IF ISNULL(@O_SD_QPID,0)!=ISNULL(@N_SD_QPID,0) OR ISNULL(@O_SD_RLID,0)!=ISNULL(@N_SD_RLID,0)
	BEGIN
		If @O_SD_QPID is not null
		BEGIN			
			SELECT @QT_ByRoom=QT_ByRoom FROM Quotas inner join QuotaDetails on QD_QTID=QT_ID inner join QuotaParts on QD_ID=QP_QDID where QP_ID=@O_SD_QPID
			IF @QT_ByRoom = 1
			BEGIN
				set @RLIDCount = (SELECT COUNT(DISTINCT SD_RLID) FROM ServiceByDate WITH (NOLOCK) WHERE SD_QPID=@O_SD_QPID)
				UPDATE QuotaParts SET QP_LastUpdate = GetDate(), QP_Busy=@RLIDCount WHERE QP_ID=@O_SD_QPID
				
				select @QD_ID = QP_QDID from QuotaParts where QP_ID = @O_SD_QPID
				set @RLIDCount = (SELECT COUNT(DISTINCT SD_RLID) FROM ServiceByDate WITH (NOLOCK) inner join QuotaParts on SD_QPID=QP_ID inner join QuotaDetails on QP_QDID=QD_ID where QP_QDID=@QD_ID)				
				UPDATE QuotaDetails SET QD_Busy=@RLIDCount WHERE QD_ID = @QD_ID
				
				set @RLIDCount = (SELECT COUNT(DISTINCT SD_RLID) FROM ServiceByDate WITH (NOLOCK) inner join tbl_DogovorList on SD_DATE=DL_DATEBEG AND SD_DLKey = DL_Key inner join [Service] on DL_SVKey = SV_KEY
					WHERE SD_QPID=@O_SD_QPID AND isnull(SV_IsDuration, 0) = 1)
				UPDATE QuotaParts SET QP_CheckInPlacesBusy=@RLIDCount WHERE QP_ID=@O_SD_QPID AND QP_CheckInPlaces IS NOT NULL
			END
			ELSE
			BEGIN
				set @RLIDCount = (SELECT COUNT(*) FROM ServiceByDate WITH (NOLOCK) WHERE SD_QPID=@O_SD_QPID)
				UPDATE QuotaParts SET QP_LastUpdate = GetDate(), QP_Busy=@RLIDCount WHERE QP_ID=@O_SD_QPID
				
				select @QD_ID = QP_QDID from QuotaParts where QP_ID = @O_SD_QPID
				set @RLIDCount = (SELECT COUNT(*) FROM ServiceByDate WITH (NOLOCK) inner join QuotaParts on SD_QPID=QP_ID inner join QuotaDetails on QP_QDID=QD_ID where QP_QDID=@QD_ID)				
				UPDATE QuotaDetails SET QD_Busy=(@RLIDCount) WHERE QD_ID = @QD_ID
				
				set @RLIDCount = (SELECT COUNT(*) FROM ServiceByDate WITH (NOLOCK) inner join tbl_DogovorList on SD_DATE=DL_DATEBEG AND SD_DLKey = DL_Key inner join [Service] on DL_SVKey = SV_KEY
					WHERE SD_QPID=@O_SD_QPID and isnull(SV_IsDuration, 0) = 1)
				UPDATE QuotaParts SET QP_CheckInPlacesBusy=@RLIDCount WHERE QP_ID=@O_SD_QPID AND QP_CheckInPlaces IS NOT NULL
			END
		END
		
		If @N_SD_QPID is not null
		BEGIN
			SELECT @QT_ByRoom=QT_ByRoom FROM Quotas,QuotaDetails,QuotaParts WHERE QD_QTID=QT_ID and QD_ID=QP_QDID and QP_ID=@N_SD_QPID
			IF @QT_ByRoom = 1
			BEGIN
				set @RLIDCount=(SELECT COUNT(DISTINCT SD_RLID) FROM ServiceByDate WITH (NOLOCK) WHERE SD_QPID=@N_SD_QPID)
				UPDATE QuotaParts SET QP_LastUpdate = GetDate(), QP_Busy=@RLIDCount WHERE QP_ID=@N_SD_QPID
				
				select @QD_ID = QP_QDID from QuotaParts where QP_ID = @N_SD_QPID
				set @RLIDCount= (SELECT COUNT(DISTINCT SD_RLID) FROM ServiceByDate WITH (NOLOCK) inner join QuotaParts on SD_QPID=QP_ID inner join QuotaDetails on QP_QDID=QD_ID where QP_QDID=@QD_ID)
				UPDATE QuotaDetails SET QD_Busy=@RLIDCount WHERE QD_ID = @QD_ID
				
				set @RLIDCount = (SELECT COUNT(DISTINCT SD_RLID) FROM ServiceByDate WITH (NOLOCK) inner join tbl_DogovorList on SD_DATE=DL_DATEBEG AND SD_DLKey = DL_Key inner join [Service] on DL_SVKey = SV_KEY
					WHERE SD_QPID=@N_SD_QPID AND isnull(SV_IsDuration, 0) = 1)
				UPDATE QuotaParts SET QP_CheckInPlacesBusy=@RLIDCount WHERE QP_ID=@N_SD_QPID AND QP_CheckInPlaces IS NOT NULL
			END
			ELSE
			BEGIN
				set @RLIDCount=(SELECT COUNT(*) FROM ServiceByDate WITH (NOLOCK) WHERE SD_QPID=@N_SD_QPID)
				UPDATE QuotaParts SET QP_LastUpdate = GetDate(), QP_Busy=@RLIDCount WHERE QP_ID=@N_SD_QPID
				
				select @QD_ID = QP_QDID from QuotaParts where QP_ID = @N_SD_QPID
				set @RLIDCount = (SELECT COUNT(*) FROM ServiceByDate WITH (NOLOCK) inner join QuotaParts on SD_QPID=QP_ID inner join QuotaDetails on QP_QDID=QD_ID where QP_QDID=@QD_ID)				
				UPDATE QuotaDetails SET QD_Busy=@RLIDCount WHERE QD_ID = @QD_ID
				
				set @RLIDCount=(SELECT COUNT(*) FROM ServiceByDate WITH (NOLOCK) inner join tbl_DogovorList on SD_DATE=DL_DATEBEG AND SD_DLKey = DL_Key inner join [Service] on DL_SVKey = SV_KEY
					WHERE SD_QPID=@N_SD_QPID and isnull(SV_IsDuration, 0) = 1)
				UPDATE QuotaParts SET QP_CheckInPlacesBusy=@RLIDCount WHERE QP_ID=@N_SD_QPID AND QP_CheckInPlaces IS NOT NULL
			END
		END
	END
	
	IF (ISNULL(@O_SD_STATE, 0) != ISNULL(@N_SD_STATE, 0) or 
		ISNULL(@O_SD_TUKEY,0)!=ISNULL(@N_SD_TUKEY,0)) and ISNULL(@sServiceStatusToHistory, ''0'') != ''0''
	BEGIN
		Select @QState = QS_STATE from QuotedState where QS_DLID = @N_SD_DLKey and ISNULL(QS_TUID,0) = ISNULL(@N_SD_TUKEY,0)
		IF @QState is NULL and @N_SD_DLKey is not NULL
		BEGIN
			Set @QState = 4
			Insert into QuotedState (QS_DLID, QS_TUID, QS_STATE) values (@N_SD_DLKey, @N_SD_TUKEY, @QState)
		END

		Select @NewQState = MAX(SD_STATE) from ServiceByDate WITH (NOLOCK) where SD_DLKey = @N_SD_DLKey and ISNULL(SD_TUKEY,0) = ISNULL(@N_SD_TUKEY,0)
		
		if @NewQState is null
		 	set @NewQState = 4
		IF @QState <> @NewQState
			IF @N_SD_DLKey is not NULL
				Update QuotedState set QS_STATE = @NewQState where QS_DLID=@N_SD_DLKey and ISNULL(QS_TUID,0)=ISNULL(@N_SD_TUKEY,0)
			ELSE
				IF @O_SD_DLKey is not NULL
					Update QuotedState set QS_STATE = @NewQState where QS_DLID=@O_SD_DLKey and ISNULL(QS_TUID,0)=ISNULL(@N_SD_TUKEY,0)
	END
	FETCH NEXT FROM cur_ServiceByDateChanged 
		INTO @SDID, @O_SD_DLKey, @O_SD_RLID, @O_SD_TUKEY, @O_SD_QPID, @O_SD_State, @O_SD_Date,
					@N_SD_DLKey, @N_SD_RLID, @N_SD_TUKEY, @N_SD_QPID, @N_SD_State, @N_SD_Date
					--@DLDateBeg, @DLNDays
END
CLOSE cur_ServiceByDateChanged
DEALLOCATE cur_ServiceByDateChanged

IF EXISTS(SELECT top 1 1 FROM RoomNumberLists WITH (NOLOCK) WHERE RL_ID NOT IN (SELECT DISTINCT SD_RLID FROM ServiceByDate WITH (NOLOCK)))
BEGIN
	DELETE FROM RoomNumberLists WHERE RL_ID not in (SELECT DISTINCT SD_RLID FROM ServiceByDate WITH (NOLOCK))
END	

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ServiceByDateChanged.sql', error_message())
END CATCH
end

print '############ end of file T_ServiceByDateChanged.sql ################'

print '############ begin of file T_ServiceDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_ServiceDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_ServiceDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ServiceDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_ServiceDelete]
   ON [dbo].[Service]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Service'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''SV_Key, SV_Name'', SV_Key, SV_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ServiceDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_ServiceDelete.sql', error_message())
END CATCH
end

print '############ end of file T_ServiceDelete.sql ################'

print '############ begin of file T_ShipDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_ShipDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_ShipDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ShipDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_ShipDelete]
   ON [dbo].[Ship]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Ship'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''SH_Key, SH_Name'', SH_Key, SH_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_ShipDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_ShipDelete.sql', error_message())
END CATCH
end

print '############ end of file T_ShipDelete.sql ################'

print '############ begin of file T_tbl_CountryDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_tbl_CountryDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_tbl_CountryDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_tbl_CountryDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_tbl_CountryDelete]
   ON [dbo].[tbl_Country]
   AFTER DELETE
AS 
BEGIN
	--удаляем маппинги из таблицы GDSMappings
	delete from GDSMappings 
	where GM_DICTIONARYID = 1 and GM_MTDICTIONARYITEMID in (select deleted.CN_KEY from deleted)
	
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''tbl_Country'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''CN_Key, CN_Name'', CN_Key, CN_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_tbl_CountryDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_tbl_CountryDelete.sql', error_message())
END CATCH
end

print '############ end of file T_tbl_CountryDelete.sql ################'

print '############ begin of file T_tbl_DiscountActionsDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_tbl_DiscountActionsDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_tbl_DiscountActionsDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_tbl_DiscountActionsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_tbl_DiscountActionsDelete]
   ON [dbo].[tbl_DiscountActions]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''tbl_DiscountActions'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''DA_Key, DA_Name'', DA_Key, DA_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_tbl_DiscountActionsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_tbl_DiscountActionsDelete.sql', error_message())
END CATCH
end

print '############ end of file T_tbl_DiscountActionsDelete.sql ################'

print '############ begin of file T_TipTurDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_TipTurDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_TipTurDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_TipTurDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_TipTurDelete]
   ON [dbo].[TipTur]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''TipTur'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''TP_Key, TP_Name'', TP_Key, TP_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_TipTurDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_TipTurDelete.sql', error_message())
END CATCH
end

print '############ end of file T_TipTurDelete.sql ################'

print '############ begin of file T_TitleTypeClientDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_TitleTypeClientDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_TitleTypeClientDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_TitleTypeClientDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_TitleTypeClientDelete]
   ON [dbo].[TitleTypeClient]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''TitleTypeClient'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''TL_Key, TL_Title'', TL_Key, TL_Title, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_TitleTypeClientDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_TitleTypeClientDelete.sql', error_message())
END CATCH
end

print '############ end of file T_TitleTypeClientDelete.sql ################'

print '############ begin of file T_TitleTypeImpressDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_TitleTypeImpressDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_TitleTypeImpressDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_TitleTypeImpressDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_TitleTypeImpressDelete]
   ON [dbo].[TitleTypeClient]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''TitleTypeImpress'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''TL_Key, TL_Title'', TL_Key, TL_Title, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_TitleTypeImpressDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_TitleTypeImpressDelete.sql', error_message())
END CATCH
end

print '############ end of file T_TitleTypeImpressDelete.sql ################'

print '############ begin of file T_TransferDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_TransferDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_TransferDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_TransferDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_TransferDelete]
   ON [dbo].[Transfer]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Transfer'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''TF_Key, TF_Name'', TF_Key, TF_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_TransferDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_TransferDelete.sql', error_message())
END CATCH
end

print '############ end of file T_TransferDelete.sql ################'

print '############ begin of file T_TransportDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_TransportDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_TransportDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_TransportDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_TransportDelete]
   ON [dbo].[Transport]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%'' 
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''Transport'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''TR_Key, TR_Name'', TR_Key, TR_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_TransportDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_TransportDelete.sql', error_message())
END CATCH
end

print '############ end of file T_TransportDelete.sql ################'

print '############ begin of file T_TuristUpdate.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N''[dbo].[T_TuristUpdate]''))
DROP TRIGGER [dbo].[T_TuristUpdate]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_TuristUpdate.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_TuristUpdate]
ON [dbo].[tbl_Turist] 
FOR UPDATE, INSERT, DELETE
AS
--<DATE>2014-07-10</DATE>
--<VERSION>2009.2.20.17</VERSION>
IF @@ROWCOUNT > 0
BEGIN
    DECLARE @OTU_DGCod varchar(10)
    DECLARE @OTU_NameRus varchar(25)
    DECLARE @OTU_NameLat varchar(25)
    DECLARE @OTU_FNameRus varchar(15)
    DECLARE @OTU_FNameLat varchar(15)
    DECLARE @OTU_SNameRus varchar(15)
    DECLARE @OTU_SNameLat varchar(15)
    DECLARE @OTU_BirthDay varchar(10)
    DECLARE @OTU_PasportType varchar(10)
    DECLARE @OTU_PasportNum varchar(20)
    DECLARE @OTU_PaspRuSer varchar(10)
    DECLARE @OTU_PaspRuNum varchar(20)
    DECLARE @OTU_PasportDate varchar(10)
    DECLARE @OTU_PasportDateEnd varchar(10)
    DECLARE @OTU_PasportByWhoM varchar(20)
    DECLARE @OTU_PaspRuDate varchar(10)
    DECLARE @OTU_PaspRuByWhoM varchar(50)
    DECLARE @OTU_Sex int
    DECLARE @OTU_RealSex int
    DECLARE @OTU_DGKey int
-- 
    DECLARE @OTU_BIRTHCOUNTRY varchar(25)
    DECLARE @OTU_BIRTHCITY varchar(25)
    DECLARE @OTU_CITIZEN varchar(50)
    DECLARE @OTU_POSTINDEX varchar(8)
    DECLARE @OTU_POSTCITY varchar(15)
    DECLARE @OTU_POSTSTREET varchar(25)
    DECLARE @OTU_POSTBILD varchar(6)
    DECLARE @OTU_POSTFLAT varchar(4)

    DECLARE @OTU_ISMAIN smallint
    DECLARE @OTU_PHONE varchar(30)
    DECLARE @OTU_EMAIL varchar(50)
    
    DECLARE @NTU_DGCod varchar(10)
    DECLARE @NTU_NameRus varchar(25)
    DECLARE @NTU_NameLat varchar(25)
    DECLARE @NTU_FNameRus varchar(15)
    DECLARE @NTU_FNameLat varchar(15)
    DECLARE @NTU_SNameRus varchar(15)
    DECLARE @NTU_SNameLat varchar(15)
    DECLARE @NTU_BirthDay varchar(10)
    DECLARE @NTU_PasportType varchar(10)
    DECLARE @NTU_PasportNum varchar(20)
    DECLARE @NTU_PaspRuSer varchar(10)
    DECLARE @NTU_PaspRuNum varchar(20)
    DECLARE @NTU_PasportDate varchar(10)
    DECLARE @NTU_PasportDateEnd varchar(10)
    DECLARE @NTU_PasportByWhoM varchar(20)
    DECLARE @NTU_PaspRuDate varchar(10)
    DECLARE @NTU_PaspRuByWhoM varchar(50)
    DECLARE @NTU_Sex int
    DECLARE @NTU_RealSex int
    DECLARE @NTU_DGKey int
--
    DECLARE @NTU_BIRTHCOUNTRY varchar(25)
    DECLARE @NTU_BIRTHCITY varchar(25)
    DECLARE @NTU_CITIZEN varchar(50)
    DECLARE @NTU_POSTINDEX varchar(8)
    DECLARE @NTU_POSTCITY varchar(15)
    DECLARE @NTU_POSTSTREET varchar(25)
    DECLARE @NTU_POSTBILD varchar(6)
    DECLARE @NTU_POSTFLAT varchar(4)

    DECLARE @NTU_ISMAIN smallint
    DECLARE @NTU_PHONE varchar(30)
    DECLARE @NTU_EMAIL varchar(50)

    DECLARE @TU_Key int

    DECLARE @sTU_ShortName varchar(8)
    DECLARE @sMod varchar(3)
    DECLARE @nDelCount int
    DECLARE @nInsCount int
    DECLARE @nHIID int
    DECLARE @sHI_Text varchar(254)

    DECLARE @sText_Old varchar(254)
    DECLARE @sText_New varchar(254)
    DECLARE @bNeedCommunicationUpdate smallint
    DECLARE @nDGKey int
    DECLARE @sDGCod varchar(10)

  SELECT @nDelCount = COUNT(*) FROM DELETED
  SELECT @nInsCount = COUNT(*) FROM INSERTED
  IF (@nDelCount = 0)
  BEGIN
    SET @sMod = ''INS''
    DECLARE cur_Turist CURSOR FOR 
      SELECT N.TU_Key, N.TU_ShortName,
             N.TU_DGCod, N.TU_DGKey, null, null, null, null, 
               null, null, null, null, null, null,
             null, null, null, null, null, null,
             null, null,
             null, null, null, null,
             null, null, null, null, null, null, null,
               N.TU_DGCod, N.TU_DGKey, N.TU_NameRus, N.TU_NameLat, N.TU_FNameRus, N.TU_FNameLat,
             N.TU_SNameRus, N.TU_SNameLat, CONVERT( char(10),N.TU_BirthDay, 104), N.TU_PasportType, N.TU_PasportNum, N.TU_PaspRuSer,
             N.TU_PaspRuNum, CONVERT( char(10),N.TU_PasportDate, 104), CONVERT( char(10),N.TU_PasportDateEnd, 104), N.TU_PasportByWhoM, CONVERT( char(10),N.TU_PaspRuDate, 104), N.TU_PaspRuByWhoM,
             N.TU_Sex, N.TU_RealSex, 
                N.TU_BIRTHCOUNTRY,
                N.TU_BIRTHCITY,
                N.TU_CITIZEN,
                N.TU_POSTINDEX,
                N.TU_POSTCITY,
                N.TU_POSTSTREET,
                N.TU_POSTBILD,
                N.TU_POSTFLAT,
                N.TU_ISMAIN,
                N.TU_PHONE,
                N.TU_EMAIL
      FROM INSERTED N 
  END
  ELSE IF (@nInsCount = 0)
  BEGIN
    SET @sMod = ''DEL''
    DECLARE cur_Turist CURSOR FOR 
      SELECT O.TU_Key, O.TU_ShortName,
             O.TU_DGCod, O.TU_DGKey, O.TU_NameRus, O.TU_NameLat, O.TU_FNameRus, O.TU_FNameLat,
             O.TU_SNameRus, O.TU_SNameLat, CONVERT( char(10),O.TU_BirthDay, 104), O.TU_PasportType, O.TU_PasportNum, O.TU_PaspRuSer,
             O.TU_PaspRuNum, CONVERT( char(10), O.TU_PasportDate, 104), CONVERT( char(10), O.TU_PasportDateEnd, 104), O.TU_PasportByWhoM, CONVERT( char(10), O.TU_PaspRuDate, 104), O.TU_PaspRuByWhoM, 
             O.TU_Sex, O.TU_RealSex, 
                O.TU_BIRTHCOUNTRY,
                O.TU_BIRTHCITY,
                O.TU_CITIZEN,
                O.TU_POSTINDEX,
                O.TU_POSTCITY,
                O.TU_POSTSTREET,
                O.TU_POSTBILD,
                O.TU_POSTFLAT,
                O.TU_ISMAIN,
                O.TU_PHONE,
                O.TU_EMAIL,
               O.TU_DGCod, O.TU_DGKey, null, null, null, null,
             null, null, null, null, null, null,
             null, null, null, null, null, null,
             null, null,
             null, null, null, null,
             null, null, null, null, null, null, null
      FROM DELETED O 
  END
  ELSE 
  BEGIN
    SET @sMod = ''UPD''
    DECLARE cur_Turist CURSOR FOR 
      SELECT N.TU_Key, N.TU_ShortName,
             O.TU_DGCod, O.TU_DGKey, O.TU_NameRus, O.TU_NameLat, O.TU_FNameRus, O.TU_FNameLat,
             O.TU_SNameRus, O.TU_SNameLat, CONVERT( char(10),O.TU_BirthDay, 104), O.TU_PasportType, O.TU_PasportNum, O.TU_PaspRuSer,
             O.TU_PaspRuNum, CONVERT( char(10), O.TU_PasportDate, 104), CONVERT( char(10), O.TU_PasportDateEnd, 104), O.TU_PasportByWhoM, CONVERT( char(10), O.TU_PaspRuDate, 104), O.TU_PaspRuByWhoM, 
             O.TU_Sex, O.TU_RealSex, 
                O.TU_BIRTHCOUNTRY,
                O.TU_BIRTHCITY,
                O.TU_CITIZEN,
                O.TU_POSTINDEX,
                O.TU_POSTCITY,
                O.TU_POSTSTREET,
                O.TU_POSTBILD,
                O.TU_POSTFLAT,
                O.TU_ISMAIN,
                O.TU_PHONE,
                O.TU_EMAIL,
               N.TU_DGCod, N.TU_DGKey, N.TU_NameRus, N.TU_NameLat, N.TU_FNameRus, N.TU_FNameLat, 
             N.TU_SNameRus, N.TU_SNameLat, CONVERT( char(10),N.TU_BirthDay, 104), N.TU_PasportType, N.TU_PasportNum, N.TU_PaspRuSer,
             N.TU_PaspRuNum, CONVERT( char(10),N.TU_PasportDate, 104), CONVERT( char(10),N.TU_PasportDateEnd, 104), N.TU_PasportByWhoM, CONVERT( char(10),N.TU_PaspRuDate, 104), N.TU_PaspRuByWhoM,
             N.TU_Sex, N.TU_RealSex, 
                N.TU_BIRTHCOUNTRY,
                N.TU_BIRTHCITY,
                N.TU_CITIZEN,
                N.TU_POSTINDEX,
                N.TU_POSTCITY,
                N.TU_POSTSTREET,
                N.TU_POSTBILD,
                N.TU_POSTFLAT,
                N.TU_ISMAIN,
                N.TU_PHONE,
                N.TU_EMAIL
      FROM DELETED O, INSERTED N 
      WHERE N.TU_Key = O.TU_Key
  END

  OPEN cur_Turist
    FETCH NEXT FROM cur_Turist INTO @TU_Key, @sTU_ShortName,
                @OTU_DGCod, @OTU_DGKey, @OTU_NameRus, @OTU_NameLat, @OTU_FNameRus, @OTU_FNameLat,
                @OTU_SNameRus, @OTU_SNameLat, @OTU_BirthDay, @OTU_PasportType, @OTU_PasportNum,    @OTU_PaspRuSer,
                @OTU_PaspRuNum, @OTU_PasportDate, @OTU_PasportDateEnd, @OTU_PasportByWhoM, @OTU_PaspRuDate, @OTU_PaspRuByWhoM, 
                @OTU_Sex, @OTU_RealSex, 
                @OTU_BIRTHCOUNTRY,
                @OTU_BIRTHCITY,
                @OTU_CITIZEN,
                @OTU_POSTINDEX,
                @OTU_POSTCITY,
                @OTU_POSTSTREET,
                @OTU_POSTBILD,
                @OTU_POSTFLAT,
                @OTU_ISMAIN,
                @OTU_PHONE,
                @OTU_EMAIL,
                @NTU_DGCod, @NTU_DGKey, @NTU_NameRus, @NTU_NameLat,    @NTU_FNameRus, @NTU_FNameLat,
                @NTU_SNameRus, @NTU_SNameLat, @NTU_BirthDay, @NTU_PasportType, @NTU_PasportNum,    @NTU_PaspRuSer,
                @NTU_PaspRuNum, @NTU_PasportDate, @NTU_PasportDateEnd, @NTU_PasportByWhoM, @NTU_PaspRuDate, @NTU_PaspRuByWhoM,
                @NTU_Sex, @NTU_RealSex,
                @NTU_BIRTHCOUNTRY,
                @NTU_BIRTHCITY,
                @NTU_CITIZEN,
                @NTU_POSTINDEX,
                @NTU_POSTCITY,
                @NTU_POSTSTREET,
                @NTU_POSTBILD,
                @NTU_POSTFLAT,
                @NTU_ISMAIN,
                @NTU_PHONE,
                @NTU_EMAIL
    WHILE @@FETCH_STATUS = 0
    BEGIN     
      If ((((@sMod = ''UPD'') AND (@OTU_DGCod = @NTU_DGCod)) OR (@sMod = ''INS'') OR (@sMod = ''DEL'')) AND
        (
            ISNULL(@OTU_NameRus, '''') != ISNULL(@NTU_NameRus, '''') OR
            ISNULL(@OTU_NameLat, '''') != ISNULL(@NTU_NameLat, '''') OR
            ISNULL(@OTU_FNameRus, '''') != ISNULL(@NTU_FNameRus, '''') OR
            ISNULL(@OTU_FNameLat, '''') != ISNULL(@NTU_FNameLat, '''') OR
            ISNULL(@OTU_SNameRus, '''') != ISNULL(@NTU_SNameRus, '''') OR
            ISNULL(@OTU_SNameLat, '''') != ISNULL(@NTU_SNameLat, '''') OR
            ISNULL(@OTU_BirthDay, 0) != ISNULL(@NTU_BirthDay, 0) OR
            ISNULL(@OTU_PasportType, 0) != ISNULL(@NTU_PasportType, 0) OR
            ISNULL(@OTU_PasportNum, 0) != ISNULL(@NTU_PasportNum, 0) OR
            ISNULL(@OTU_PaspRuSer, 0) != ISNULL(@NTU_PaspRuSer, 0) OR
            ISNULL(@OTU_PaspRuNum, 0) != ISNULL(@NTU_PaspRuNum, 0) OR
            ISNULL(@OTU_PasportDate, 0) != ISNULL(@NTU_PasportDate, 0) OR
            ISNULL(@OTU_PasportDateEnd, 0) != ISNULL(@NTU_PasportDateEnd, 0) OR
            ISNULL(@OTU_PasportByWhoM, 0) != ISNULL(@NTU_PasportByWhoM, 0) OR
            ISNULL(@OTU_PaspRuDate, 0) != ISNULL(@NTU_PaspRuDate, 0) OR
            ISNULL(@OTU_PaspRuByWhoM, 0) != ISNULL(@NTU_PaspRuByWhoM, 0)  OR
            ISNULL(@OTU_Sex, 0) != ISNULL(@NTU_Sex, 0)  OR
            ISNULL(@OTU_RealSex, 0) != ISNULL(@NTU_RealSex, 0) OR
--
            ISNULL(@OTU_BIRTHCOUNTRY, '''') != ISNULL(@NTU_BIRTHCOUNTRY, '''') OR
            ISNULL(@OTU_BIRTHCITY, '''') != ISNULL(@NTU_BIRTHCITY, '''') OR
            ISNULL(@OTU_CITIZEN, '''') != ISNULL(@NTU_CITIZEN, '''') OR
            ISNULL(@OTU_POSTINDEX, '''') != ISNULL(@NTU_POSTINDEX, '''') OR
            ISNULL(@OTU_POSTCITY, '''') != ISNULL(@NTU_POSTCITY, '''') OR
            ISNULL(@OTU_POSTSTREET, '''') != ISNULL(@NTU_POSTSTREET, '''') OR
            ISNULL(@OTU_POSTBILD, '''') != ISNULL(@NTU_POSTBILD, '''') OR
            ISNULL(@OTU_POSTFLAT, '''') != ISNULL(@NTU_POSTFLAT, '''') OR
            ISNULL(@OTU_ISMAIN, 0) != ISNULL(@NTU_ISMAIN, 0) OR 
            ISNULL(@OTU_EMAIL, '''') != ISNULL(@NTU_EMAIL, '''') OR 
            ISNULL(@OTU_PHONE, '''') != ISNULL(@NTU_PHONE, '''')
        ))
      BEGIN
    
        
        SET @nDGKey=@NTU_DGKey
        SET @sHI_Text = ISNULL(@NTU_NameRus, '''') + '' '' + ISNULL(@sTU_ShortName, '''')
        SET @sDGCod=@NTU_DGCod
        if (@sMod = ''DEL'')
        BEGIN
            SET @nDGKey=@OTU_DGKey
            SET @sHI_Text = ISNULL(@OTU_NameRus, '''') + '' '' + ISNULL(@sTU_ShortName, '''')
            SET @sDGCod=@OTU_DGCod
        END
        EXEC @nHIID = dbo.InsHistory @sDGCod, @nDGKey, 3, @TU_Key, @sMod, @sHI_Text, '''', 0, ''''    
        if (ISNULL(@OTU_NameRus, '''') != ISNULL(@NTU_NameRus, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1051, @OTU_NameRus, @NTU_NameRus, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_NameLat, '''') != ISNULL(@NTU_NameLat, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1052, @OTU_NameLat, @NTU_NameLat, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_FNameRus, '''') != ISNULL(@NTU_FNameRus, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1053, @OTU_FNameRus, @NTU_FNameRus, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_FNameLat, '''') != ISNULL(@NTU_FNameLat, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1054, @OTU_FNameLat, @NTU_FNameLat, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_SNameRus, '''') != ISNULL(@NTU_SNameRus, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1055, @OTU_SNameRus, @NTU_SNameRus, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_SNameLat, '''') != ISNULL(@NTU_SNameLat, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1056, @OTU_SNameLat, @NTU_SNameLat, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_BirthDay, 0) != ISNULL(@NTU_BirthDay, 0))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1057, @OTU_BirthDay, @NTU_BirthDay, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_PasportType, '''') != ISNULL(@NTU_PasportType, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1058, @OTU_PasportType, @NTU_PasportType, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_PasportNum, '''') != ISNULL(@NTU_PasportNum, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1059, @OTU_PasportNum, @NTU_PasportNum, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_PaspRuSer, '''') != ISNULL(@NTU_PaspRuSer, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1060, @OTU_PaspRuSer, @NTU_PaspRuSer, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_PaspRuNum, '''') != ISNULL(@NTU_PaspRuNum, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1061, @OTU_PaspRuNum, @NTU_PaspRuNum, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_PasportDate, 0) != ISNULL(@NTU_PasportDate, 0))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1062, @OTU_PasportDate, @NTU_PasportDate, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_PasportDateEnd, 0) != ISNULL(@NTU_PasportDateEnd, 0))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1063, @OTU_PasportDateEnd, @NTU_PasportDateEnd, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_PasportByWhoM, '''') != ISNULL(@NTU_PasportByWhoM, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1064, @OTU_PasportByWhoM, @NTU_PasportByWhoM, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_PaspRuDate, 0) != ISNULL(@NTU_PaspRuDate, 0))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1065, @OTU_PaspRuDate, @NTU_PaspRuDate, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_PaspRuByWhoM, '''') != ISNULL(@NTU_PaspRuByWhoM, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1066, @OTU_PaspRuByWhoM, @NTU_PaspRuByWhoM, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_Sex, 0) != ISNULL(@NTU_Sex, 0))
            BEGIN
                IF not ((ISNULL(@OTU_Sex, 0) = 1 and ISNULL(@NTU_Sex, 0) = 0) or (ISNULL(@OTU_Sex, 0) = 0 and ISNULL(@NTU_Sex, 0) = 1))
                BEGIN
                    IF @sMod != ''INS''
                        SELECT @sText_Old = CASE ISNULL(@OTU_Sex, 0)
                                WHEN 0 THEN ''Adult''
                                WHEN 1 THEN ''Adult''
                                WHEN 2 THEN ''Child''
                                WHEN 3 THEN ''Infant''
                                END
                    ELSE
                        SET @sText_Old = ''''
                    IF @sMod != ''DEL''
                        SELECT @sText_New = CASE ISNULL(@NTU_Sex, 0)
                                WHEN 0 THEN ''Adult''
                                WHEN 1 THEN ''Adult''
                                WHEN 2 THEN ''Child''
                                WHEN 3 THEN ''Infant''
                                END
                    ELSE
                        SET @sText_New = ''''
                    EXECUTE dbo.InsertHistoryDetail @nHIID , 1067, @sText_Old, @sText_New, @OTU_Sex, @NTU_Sex, null, null, 0, @bNeedCommunicationUpdate output
                END
            END
        if (ISNULL(@OTU_RealSex, 0) != ISNULL(@NTU_RealSex, 0))
        BEGIN
                IF @sMod != ''INS''
                    SELECT @sText_Old = CASE ISNULL(@OTU_RealSex, 0)
                            WHEN 0 THEN ''Male''
                            WHEN 1 THEN ''Female''
                            END
                ELSE
                    Set @sText_Old = ''''
                IF @sMod != ''DEL''
                    SELECT @sText_New = CASE ISNULL(@NTU_RealSex, 0)
                            WHEN 0 THEN ''Male''
                            WHEN 1 THEN ''Female''
                            END
                ELSE
                    Set    @sText_New = ''''
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1068, @sText_Old, @sText_New, @OTU_RealSex, @NTU_RealSex, null, null, 0, @bNeedCommunicationUpdate output
        END

        if (ISNULL(@OTU_BIRTHCOUNTRY, '''') != ISNULL(@NTU_BIRTHCOUNTRY, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1126, @OTU_BIRTHCOUNTRY, @NTU_BIRTHCOUNTRY, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_BIRTHCITY, '''') != ISNULL(@NTU_BIRTHCITY, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1127, @OTU_BIRTHCITY, @NTU_BIRTHCITY, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_CITIZEN, '''') != ISNULL(@NTU_CITIZEN, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1128, @OTU_CITIZEN, @NTU_CITIZEN, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_POSTINDEX, '''') != ISNULL(@NTU_POSTINDEX, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1129, @OTU_POSTINDEX, @NTU_POSTINDEX, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_POSTCITY, '''') != ISNULL(@NTU_POSTCITY, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1130, @OTU_POSTCITY, @NTU_POSTCITY, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_POSTSTREET, '''') != ISNULL(@NTU_POSTSTREET, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1131, @OTU_POSTSTREET, @NTU_POSTSTREET, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_POSTBILD, '''') != ISNULL(@NTU_POSTBILD, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1132, @OTU_POSTBILD, @NTU_POSTBILD, null, null, null, null, 0, @bNeedCommunicationUpdate output
        if (ISNULL(@OTU_POSTFLAT, '''') != ISNULL(@NTU_POSTFLAT, ''''))
            EXECUTE dbo.InsertHistoryDetail @nHIID , 1133, @OTU_POSTFLAT, @NTU_POSTFLAT, null, null, null, null, 0, @bNeedCommunicationUpdate output
        --

        DECLARE @PrivatePerson int;
        DECLARE @NewMainTourist int;
        DECLARE @HaveMainMan int, @MainManSex int;
        DECLARE @Name varchar(35),
                @FName varchar(15),
                @SName varchar(15),
                @Phone varchar(60),
                @Email varchar(50),
                @PostIndex varchar(8),
                @PostCity varchar(60),
                @PostStreet varchar(25),
                @PostBuilding varchar(10),
                @PostFlat varchar(4),
                @PassportSeries varchar(10),
                @PassportNumber varchar(10);
        DECLARE @dogovorClient int;

        IF (@sMod = ''UPD'')
        BEGIN
            IF ISNULL(@OTU_ISMAIN, 0) != ISNULL(@NTU_ISMAIN, 0)
                BEGIN
                    IF(ISNULL(@NTU_ISMAIN,0) >= 1)
                        BEGIN
                            UPDATE [dbo].[TBL_TURIST]
                            SET TU_ISMAIN = 0
                            WHERE TU_KEY <> @TU_Key AND TU_DGCOD = @NTU_DGCod;

                            UPDATE [dbo].[TBL_TURIST]
                            SET TU_ISMAIN = 1
                            WHERE TU_KEY = @TU_Key

                            EXEC @PrivatePerson = dbo.CheckPrivatePerson @NTU_DGCOD;
                            IF(@PrivatePerson = 1)
                            BEGIN
                                SELECT @dogovorClient = DG_CLIENTKEY FROM [dbo].[tbl_Dogovor] WHERE DG_CODE = @sDGCod
                                IF @dogovorClient IS NULL
                                BEGIN
                                    EXEC [dbo].[UpdateReservationMainManByTourist] @NTU_NAMERUS, @NTU_FNAMERUS, @NTU_SNAMERUS, @NTU_PHONE, @NTU_EMAIL
                                                                             , @NTU_POSTINDEX, @NTU_POSTCITY, @NTU_POSTSTREET
                                                                             , @NTU_POSTBILD, @NTU_POSTFLAT, @NTU_PASPRUSER
                                                                             , @NTU_PASPRUNUM, @NTU_DGCOD;
                                END
                            END
                        END
                    ELSE
                        BEGIN
                            SELECT @HaveMainMan = TU_KEY, @MainManSex = TU_SEX
                                FROM [dbo].[TBL_TURIST] WITH(NOLOCK)
                                WHERE TU_KEY <> @TU_Key AND TU_DGCOD = @NTU_DGCOD AND TU_ISMAIN = 1
                            IF @HaveMainMan IS NULL
                            BEGIN
                                SELECT @NewMainTourist = TU_KEY 
                                FROM [dbo].[TBL_TURIST] WITH(NOLOCK)
                                WHERE TU_KEY <> @TU_Key AND TU_SEX < 2 AND TU_DGCOD = @NTU_DGCOD;
                                IF(@NewMainTourist IS NULL)
                                BEGIN
                                    SELECT @NewMainTourist = TU_KEY 
                                    FROM [dbo].[TBL_TURIST] WITH(NOLOCK)
                                    WHERE TU_KEY <> @TU_Key AND TU_DGCOD = @NTU_DGCOD;
                                END
                                ELSE IF(@NewMainTourist IS NOT NULL)
                                BEGIN
                                    UPDATE [dbo].[TBL_TURIST]
                                    SET TU_ISMAIN = 0
                                    WHERE TU_KEY <> @NewMainTourist AND TU_DGCOD = @NTU_DGCod;
                                
                                    UPDATE [dbo].[TBL_TURIST]
                                    SET TU_ISMAIN = 1
                                    WHERE TU_KEY = @NewMainTourist;
                                
                                    EXEC @PrivatePerson = dbo.CheckPrivatePerson @OTU_DGCOD;
                                    IF(@PrivatePerson = 1)
                                    BEGIN
                                        SELECT @Name = TU_NAMERUS, @FName = TU_FNAMERUS, @SName = TU_SNAMERUS, @Phone = TU_PHONE, @Email=TU_EMAIL
                                             , @PostIndex = TU_POSTINDEX, @PostCity = TU_POSTCITY, @PostStreet = TU_POSTSTREET
                                             , @PostBuilding = TU_POSTBILD, @PostFlat = TU_POSTFLAT, @PassportSeries = TU_PASPRUSER
                                             , @PassportNumber = TU_PASPRUNUM
                                        FROM [dbo].[tbl_turist]
                                        WHERE TU_KEY = @NewMainTourist;
                            
                                        SELECT @dogovorClient = DG_CLIENTKEY FROM [dbo].[tbl_Dogovor] WHERE DG_CODE = @sDGCod
                                        IF @dogovorClient IS NULL
                                        BEGIN
                                            EXEC [dbo].[UpdateReservationMainManByTourist] @Name, @FName, @SName, @Phone, @Email
                                                                             , @PostIndex, @PostCity, @PostStreet
                                                                             , @PostBuilding, @PostFlat, @PassportSeries
                                                                             , @PassportNumber, @OTU_DGCOD;
                                        END
                                    END
                                END
                            END    
                        END
                END    
            ELSE IF ISNULL(@OTU_ISMAIN, 0) = ISNULL(@NTU_ISMAIN, 0) 
                    AND  ISNULL(@NTU_ISMAIN, 0) >= 1                    
                    AND (ISNULL(@OTU_NameRus, '''') != ISNULL(@NTU_NameRus, '''') 
                        OR ISNULL(@OTU_FNameRus, '''') != ISNULL(@NTU_FNameRus, '''')
                        OR ISNULL(@OTU_SNameRus, '''') != ISNULL(@NTU_SNameRus, '''')
                        OR ISNULL(@OTU_PHONE, '''') != ISNULL(@NTU_PHONE, '''')
                        OR ISNULL(@OTU_EMAIL, '''') != ISNULL(@NTU_EMAIL, '''')
                        OR ISNULL(@OTU_POSTINDEX, '''') != ISNULL(@NTU_POSTINDEX, '''')
                        OR ISNULL(@OTU_POSTCITY, '''') != ISNULL(@NTU_POSTCITY, '''')
                        OR ISNULL(@OTU_POSTSTREET, '''') != ISNULL(@NTU_POSTSTREET, '''')
                        OR ISNULL(@OTU_POSTBILD, '''') != ISNULL(@NTU_POSTBILD, '''')
                        OR ISNULL(@OTU_POSTFLAT, '''') != ISNULL(@NTU_POSTFLAT, '''')
                        OR ISNULL(@OTU_PASPRUSER, '''') != ISNULL(@NTU_PASPRUSER, '''')
                        OR ISNULL(@OTU_PASPRUNUM, '''') != ISNULL(@NTU_PASPRUNUM, '''')
                        OR ISNULL(@OTU_DGCOD, '''') != ISNULL(@NTU_DGCOD, ''''))    
                BEGIN
                    SELECT @HaveMainMan = TU_KEY, @MainManSex = TU_SEX
                    FROM [dbo].[TBL_TURIST] WITH(NOLOCK)
                    WHERE TU_KEY <> @TU_Key AND TU_DGCOD = @NTU_DGCOD AND TU_ISMAIN = 1
                    
                    IF @HaveMainMan IS NULL 
                    BEGIN
                        EXEC @PrivatePerson = dbo.CheckPrivatePerson @NTU_DGCOD;
                        IF(@PrivatePerson = 1)
                        BEGIN
                            SELECT @dogovorClient = DG_CLIENTKEY FROM [dbo].[tbl_Dogovor] WHERE DG_CODE = @sDGCod
                            IF @dogovorClient IS NULL
                            BEGIN
                                EXEC [dbo].[UpdateReservationMainManByTourist] @NTU_NAMERUS, @NTU_FNAMERUS, @NTU_SNAMERUS, @NTU_PHONE, @NTU_EMAIL
                                                                     , @NTU_POSTINDEX, @NTU_POSTCITY, @NTU_POSTSTREET
                                                                     , @NTU_POSTBILD, @NTU_POSTFLAT, @NTU_PASPRUSER
                                                                     , @NTU_PASPRUNUM, @NTU_DGCOD;
                            END
                        END
                    END
                END
        END
        ELSE IF (@sMod = ''DEL'')
        BEGIN
            DECLARE @MainTouristExists int;
            SELECT @MainTouristExists = TU_KEY 
            FROM [dbo].[TBL_TURIST] WITH(NOLOCK)
            WHERE TU_KEY <> @TU_Key AND TU_DGCOD = @OTU_DGCOD AND TU_ISMAIN = 1;
        
            IF @MainTouristExists IS NULL
                BEGIN
                    SELECT @NewMainTourist = TU_KEY 
                    FROM [dbo].[TBL_TURIST] WITH(NOLOCK)
                    WHERE TU_KEY <> @TU_Key AND TU_SEX < 2 AND TU_DGCOD = @OTU_DGCOD;

                    IF (@NewMainTourist IS NULL)
                    BEGIN
                        SELECT @NewMainTourist = TU_KEY 
                        FROM [dbo].[TBL_TURIST] WITH(NOLOCK)
                        WHERE TU_KEY <> @TU_Key AND TU_DGCOD = @OTU_DGCOD;
                    END
                    ELSE IF (@NewMainTourist IS NOT NULL)
                    BEGIN
                        UPDATE [dbo].[TBL_TURIST] SET TU_ISMAIN = 1 WHERE TU_KEY = @NewMainTourist;

                        EXEC @PrivatePerson = dbo.CheckPrivatePerson @OTU_DGCOD;
                        IF(@PrivatePerson = 1)
                        BEGIN
                            SELECT @Name = TU_NAMERUS, @FName = TU_FNAMERUS, @SName = TU_SNAMERUS, @Phone = TU_PHONE, @Email=TU_EMAIL
                                 , @PostIndex = TU_POSTINDEX, @PostCity = TU_POSTCITY, @PostStreet = TU_POSTSTREET
                                 , @PostBuilding = TU_POSTBILD, @PostFlat = TU_POSTFLAT, @PassportSeries = TU_PASPRUSER
                                 , @PassportNumber = TU_PASPRUNUM
                            FROM [dbo].[tbl_turist]
                            WHERE TU_KEY = @NewMainTourist;
                             
                            SELECT @dogovorClient = DG_CLIENTKEY FROM [dbo].[tbl_Dogovor] WHERE DG_CODE = @sDGCod
                            IF @dogovorClient IS NULL
                            BEGIN
                                EXEC [dbo].[UpdateReservationMainManByTourist] @Name, @FName, @SName, @Phone, @Email
                                                                         , @PostIndex, @PostCity, @PostStreet
                                                                         , @PostBuilding, @PostFlat, @PassportSeries
                                                                         , @PassportNumber, @OTU_DGCOD;
                            END
                        END
                        ELSE
                        BEGIN
                            EXEC [dbo].[UpdateReservationMainMan] '''','''','''','''','''',@OTU_DGCOD;
                        END
                    END
                END    
            END    
        ELSE IF(@sMod = ''INS'')
        BEGIN
            SELECT @HaveMainMan = TU_KEY, @MainManSex = TU_SEX
            FROM [dbo].[TBL_TURIST] WITH(NOLOCK)
            WHERE TU_KEY <> @TU_Key AND TU_DGCOD = @NTU_DGCOD AND TU_ISMAIN = 1

            IF(@HaveMainMan IS NULL OR ((ISNULL(@MainManSex,0) >= 2) AND ISNULL(@NTU_SEX,99) < 2 AND ISNULL(@NTU_ISMAIN,0) = 1))
            BEGIN
                IF(@HaveMainMan IS NULL)
                BEGIN
                    UPDATE [dbo].[TBL_TURIST] SET TU_ISMAIN = 1 WHERE TU_KEY = @TU_Key;
                END
                ELSE
                BEGIN
                    UPDATE [dbo].[TBL_TURIST] SET TU_ISMAIN = 0 WHERE TU_KEY = @HaveMainMan;
                END
                
                EXEC @PrivatePerson = dbo.CheckPrivatePerson @NTU_DGCOD;
                IF(@PrivatePerson = 1)
                BEGIN
                    SELECT @dogovorClient = DG_CLIENTKEY FROM [dbo].[tbl_Dogovor] WHERE DG_CODE = @sDGCod
                    IF @dogovorClient IS NULL
                    BEGIN
                        EXEC [dbo].[UpdateReservationMainManByTourist] @NTU_NAMERUS, @NTU_FNAMERUS, @NTU_SNAMERUS, @NTU_PHONE, @NTU_EMAIL
                                                                     , @NTU_POSTINDEX, @NTU_POSTCITY, @NTU_POSTSTREET
                                                                     , @NTU_POSTBILD, @NTU_POSTFLAT, @NTU_PASPRUSER
                                                                     , @NTU_PASPRUNUM, @NTU_DGCOD;
                    END
                END
            END
            ELSE IF(@HaveMainMan IS NOT NULL AND ISNULL(@NTU_ISMAIN,0) = 1)
            BEGIN
                UPDATE [dbo].[TBL_TURIST] SET TU_ISMAIN = 0 WHERE TU_KEY = @HaveMainMan; 
                
                EXEC @PrivatePerson = dbo.CheckPrivatePerson @NTU_DGCOD;
                IF(@PrivatePerson = 1)
                BEGIN
                    SELECT @dogovorClient = DG_CLIENTKEY FROM [dbo].[tbl_Dogovor] WHERE DG_CODE = @sDGCod
                    IF @dogovorClient IS NULL
                    BEGIN
                        EXEC [dbo].[UpdateReservationMainManByTourist] @NTU_NAMERUS, @NTU_FNAMERUS, @NTU_SNAMERUS, @NTU_PHONE, @NTU_EMAIL
                                                                     , @NTU_POSTINDEX, @NTU_POSTCITY, @NTU_POSTSTREET
                                                                     , @NTU_POSTBILD, @NTU_POSTFLAT, @NTU_PASPRUSER
                                                                     , @NTU_PASPRUNUM, @NTU_DGCOD;
                    END
                END
            END
        END
        
        If @bNeedCommunicationUpdate=1
            If exists (SELECT 1 FROM Communications WHERE CM_DGKey=@nDGKey)
                UPDATE Communications SET CM_ChangeDate=GetDate() WHERE CM_DGKey=@nDGKey

      ------------------------------------------------------------------------------------------------
      END
    FETCH NEXT FROM cur_Turist INTO @TU_Key, @sTU_ShortName,
                @OTU_DGCod, @OTU_DGKey, @OTU_NameRus, @OTU_NameLat, @OTU_FNameRus, @OTU_FNameLat,
                @OTU_SNameRus, @OTU_SNameLat, @OTU_BirthDay, @OTU_PasportType, @OTU_PasportNum,    @OTU_PaspRuSer,
                @OTU_PaspRuNum, @OTU_PasportDate, @OTU_PasportDateEnd, @OTU_PasportByWhoM, @OTU_PaspRuDate, @OTU_PaspRuByWhoM, 
                @OTU_Sex, @OTU_RealSex, 
                @OTU_BIRTHCOUNTRY,
                @OTU_BIRTHCITY,
                @OTU_CITIZEN,
                @OTU_POSTINDEX,
                @OTU_POSTCITY,
                @OTU_POSTSTREET,
                @OTU_POSTBILD,
                @OTU_POSTFLAT,
                @OTU_ISMAIN,
                @OTU_PHONE,
                @OTU_EMAIL,
                @NTU_DGCod, @NTU_DGKey, @NTU_NameRus, @NTU_NameLat,    @NTU_FNameRus, @NTU_FNameLat,
                @NTU_SNameRus, @NTU_SNameLat, @NTU_BirthDay, @NTU_PasportType, @NTU_PasportNum,    @NTU_PaspRuSer,
                @NTU_PaspRuNum, @NTU_PasportDate, @NTU_PasportDateEnd, @NTU_PasportByWhoM, @NTU_PaspRuDate, @NTU_PaspRuByWhoM,
                @NTU_Sex, @NTU_RealSex,
                @NTU_BIRTHCOUNTRY,
                @NTU_BIRTHCITY,
                @NTU_CITIZEN,
                @NTU_POSTINDEX,
                @NTU_POSTCITY,
                @NTU_POSTSTREET,
                @NTU_POSTBILD,
                @NTU_POSTFLAT,
                @NTU_ISMAIN,
                @NTU_PHONE,
                @NTU_EMAIL
    END
  CLOSE cur_Turist
  DEALLOCATE cur_Turist
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_TuristUpdate.sql', error_message())
END CATCH
end

print '############ end of file T_TuristUpdate.sql ################'

print '############ begin of file T_UpdateAirline.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_UpdateAirline]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
    drop trigger [dbo].[T_UpdateAirline]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_UpdateAirline.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_UpdateAirline]
    ON [dbo].[Airline]
    AFTER UPDATE
AS
BEGIN
    IF (@@ROWCOUNT <= 0 OR NOT UPDATE(AL_Code))
        RETURN

    DECLARE @sCodeIns varchar(4)
    DECLARE @sCodeDel varchar(4)

    DECLARE cur_ALInsert CURSOR FOR SELECT AL_Code FROM inserted OPEN cur_ALInsert
    DECLARE cur_ALDelete CURSOR FOR SELECT AL_Code FROM deleted OPEN cur_ALDelete

    FETCH NEXT FROM cur_ALInsert INTO @sCodeIns
    FETCH NEXT FROM cur_ALDelete INTO @sCodeDel

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- В TourPrograms коды авикомпаний используются и храняться как первичные ключи
        exec UpdateAirlineCodeInTourProgramms @sCodeDel, @sCodeIns

        FETCH NEXT FROM cur_ALInsert INTO @sCodeIns
        FETCH NEXT FROM cur_ALDelete INTO @sCodeDel
    END

    CLOSE cur_ALInsert
    CLOSE cur_ALDelete
    DEALLOCATE cur_ALInsert
    DEALLOCATE cur_ALDelete
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_UpdateAirline.sql', error_message())
END CATCH
end

print '############ end of file T_UpdateAirline.sql ################'

print '############ begin of file T_UpdateAirport.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_UpdateAirport]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
    drop trigger [dbo].[T_UpdateAirport]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_UpdateAirport.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_UpdateAirport]
    ON [dbo].[Airport]
    AFTER UPDATE
AS
BEGIN
    IF (@@ROWCOUNT <= 0 OR NOT UPDATE(AP_Code))
        RETURN

    DECLARE @sCodeIns varchar(4)
    DECLARE @sCodeDel varchar(4)

    DECLARE cur_APInsert CURSOR FOR SELECT AP_Code FROM inserted OPEN cur_APInsert
    DECLARE cur_APDelete CURSOR FOR SELECT AP_Code FROM deleted OPEN cur_APDelete

    FETCH NEXT FROM cur_APInsert INTO @sCodeIns
    FETCH NEXT FROM cur_APDelete INTO @sCodeDel

    WHILE @@FETCH_STATUS = 0
    BEGIN
        UPDATE Charter SET CH_PORTCODEFROM = @sCodeIns WHERE CH_PORTCODEFROM = @sCodeDel
        UPDATE Charter SET CH_PORTCODETO = @sCodeIns WHERE CH_PORTCODETO = @sCodeDel

        -- В TourPrograms коды аэропортов используются и храняться как первичные ключи
        exec UpdateAirportCodeInTourProgramms @sCodeDel, @sCodeIns

        FETCH NEXT FROM cur_APInsert INTO @sCodeIns
        FETCH NEXT FROM cur_APDelete INTO @sCodeDel
    END

    CLOSE cur_APInsert
    CLOSE cur_APDelete
    DEALLOCATE cur_APInsert
    DEALLOCATE cur_APDelete
END
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_UpdateAirport.sql', error_message())
END CATCH
end

print '############ end of file T_UpdateAirport.sql ################'

print '############ begin of file T_VehicleDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
IF  EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N''[dbo].[T_VehicleDelete]''))
DROP TRIGGER [dbo].[T_VehicleDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_VehicleDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_VehicleDelete] ON [dbo].[Vehicle] 
FOR DELETE 
AS
--<DATE>2017-08-14</DATE>
BEGIN
	DECLARE	@VH_HOSTKEY	int

	DECLARE cur_Deleted CURSOR FOR SELECT VH_HOSTKEY FROM deleted

	OPEN cur_Deleted

	FETCH NEXT FROM cur_Deleted INTO @VH_HOSTKEY

	WHILE @@FETCH_STATUS = 0
	BEGIN
		-- Снимаем туристов c удаленного транспорта		
		UPDATE TuristService SET TU_SEAT = null, TU_AREA = null
		from DogovorList join TuristService on TU_DLKEY = DL_KEY
			WHERE TU_SEAT is not null and TU_AREA is not null 
			and case when Dl_SVKey = 14 then DL_SUBCODE2 else DL_SUBCODE1 end 
			= @VH_HOSTKEY

		FETCH NEXT FROM cur_Deleted INTO @VH_HOSTKEY
	END

	CLOSE cur_Deleted

	DEALLOCATE cur_Deleted
END


')
END TRY
BEGIN CATCH
insert into ##errors values ('T_VehicleDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_VehicleDelete.sql', error_message())
END CATCH
end

print '############ end of file T_VehicleDelete.sql ################'

print '############ begin of file T_VisaDocumentsDelete.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from dbo.sysobjects where id = object_id(N''[dbo].[T_VisaDocumentsDelete]'') and OBJECTPROPERTY(id, N''IsTrigger'') = 1)
drop trigger [dbo].[T_VisaDocumentsDelete]
')
END TRY
BEGIN CATCH
insert into ##errors values ('T_VisaDocumentsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('

CREATE TRIGGER [dbo].[T_VisaDocumentsDelete]
   ON [dbo].[VisaDocuments]
   AFTER DELETE
AS 
BEGIN
	--<VERSION>9.2.20.12</VERSION>
	--<DATE>2015-11-11</DATE>

	if @@ROWCOUNT > 0 and APP_NAME() not like ''%Master%Tour%''
	begin
		declare @nHiId int
		
		insert into dbo.History with(rowlock) (HI_DGCOD, HI_DATE, HI_WHO, HI_TEXT, HI_MOD, HI_Type, HI_MessEnabled, HI_OAId, HI_USERID)
		values ('''', GETDATE(), SYSTEM_USER, APP_NAME(), ''DEL'', ''VisaDocuments'', 0, 400000, 0)
		set @nHiId = SCOPE_IDENTITY()
		
		insert into dbo.HistoryDetail with (rowlock) (HD_HIID, HD_OAId, HD_Alias, HD_Text, HD_IntValueOld, HD_ValueOld, HD_Invisible)
		select @nHiId, 400000, '''', ''VD_ID, VD_Name'', VD_ID, VD_Name, 1 from DELETED
	end
END

')
END TRY
BEGIN CATCH
insert into ##errors values ('T_VisaDocumentsDelete.sql', error_message())
END CATCH
end

if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('


')
END TRY
BEGIN CATCH
select error_message()
insert into ##errors values ('T_VisaDocumentsDelete.sql', error_message())
END CATCH
end

print '############ end of file T_VisaDocumentsDelete.sql ################'

print '############ begin of file _drop_AddCostsReCalculate.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select * from sys.triggers where object_id = object_id(N''[dbo].[T_AddCostsReCalculate]''))
	drop trigger [dbo].[T_AddCostsReCalculate]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_drop_AddCostsReCalculate.sql', error_message())
END CATCH
end

print '############ end of file _drop_AddCostsReCalculate.sql ################'

print '############ begin of file _drop_mwUpdateHotel.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--<DATE>2014-09-30</DATE>
--удаление триггера mwUpdateHotel
if exists ( select  * from    sys.triggers where   object_id = object_id(N''[dbo].[mwUpdateHotel]'') )
    drop trigger [dbo].[mwUpdateHotel]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_drop_mwUpdateHotel.sql', error_message())
END CATCH
end

print '############ end of file _drop_mwUpdateHotel.sql ################'

print '############ begin of file _drop_TPServicesDelete_Log.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
if exists (select top 1 1 from sys.triggers tr
left join sys.tables tab on tab.object_id = tr.parent_id
where tr.name = ''TPServicesDelete_Log''
	and tab.name = ''TP_Services'')
begin

	DROP TRIGGER [dbo].[TPServicesDelete_Log]

end

')
END TRY
BEGIN CATCH
insert into ##errors values ('_drop_TPServicesDelete_Log.sql', error_message())
END CATCH
end

print '############ end of file _drop_TPServicesDelete_Log.sql ################'

print '############ begin of file _drop_T_CostOfferServicesReCalculate.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--<DATE>2014-09-30</DATE>
--удаление триггера T_CostOfferServicesReCalculate
if exists ( select  * from    sys.triggers where   object_id = object_id(N''[dbo].[T_CostOfferServicesReCalculate]'') )
    drop trigger [dbo].[T_CostOfferServicesReCalculate]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_drop_T_CostOfferServicesReCalculate.sql', error_message())
END CATCH
end

print '############ end of file _drop_T_CostOfferServicesReCalculate.sql ################'

print '############ begin of file _drop_T_CostOffersReCalculate.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--<DATE>2014-09-30</DATE>
--удаление триггера T_CostOffersReCalculate
IF  EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N''[dbo].[T_CostOffersReCalculate]''))
DROP TRIGGER [dbo].[T_CostOffersReCalculate]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_drop_T_CostOffersReCalculate.sql', error_message())
END CATCH
end

print '############ end of file _drop_T_CostOffersReCalculate.sql ################'

print '############ begin of file _drop_T_MarginChange.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--<DATE>2016-01-27</DATE>
--удаление триггера T_MarginChange
IF  EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N''[dbo].[T_MarginChange]''))
DROP TRIGGER [dbo].[T_MarginChange]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_drop_T_MarginChange.sql', error_message())
END CATCH
end

print '############ end of file _drop_T_MarginChange.sql ################'

print '############ begin of file _drop_T_PriceChange.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--<DATE>2014-09-30</DATE>
--удаление триггера T_PriceChange
IF  EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N''[dbo].[T_PriceChange]''))
DROP TRIGGER [dbo].[T_PriceChange]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_drop_T_PriceChange.sql', error_message())
END CATCH
end

print '############ end of file _drop_T_PriceChange.sql ################'

print '############ begin of file _drop_T_TourMarginChange.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--<DATE>2016-01-27</DATE>
--удаление триггера T_TourMarginChange
IF  EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N''[dbo].[T_TourMarginChange]''))
DROP TRIGGER [dbo].[T_TourMarginChange]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_drop_T_TourMarginChange.sql', error_message())
END CATCH
end

print '############ end of file _drop_T_TourMarginChange.sql ################'

print '############ begin of file _drop_T_TourMarginReCalculate.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--<DATE>2016-01-27</DATE>
--удаление триггера T_TourMarginReCalculate
IF  EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N''[dbo].[T_TourMarginReCalculate]''))
DROP TRIGGER [dbo].[T_TourMarginReCalculate]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_drop_T_TourMarginReCalculate.sql', error_message())
END CATCH
end

print '############ end of file _drop_T_TourMarginReCalculate.sql ################'

print '############ begin of file _drop_UPD_Margin.sql ################'
if not exists (select * from ##errors)
begin
BEGIN TRY
EXEC ('
--<DATE>2016-01-27</DATE>
--удаление триггера UPD_Margin
IF  EXISTS (SELECT * FROM sys.triggers WHERE object_id = OBJECT_ID(N''[dbo].[UPD_Margin]''))
DROP TRIGGER [dbo].[UPD_Margin]
')
END TRY
BEGIN CATCH
insert into ##errors values ('_drop_UPD_Margin.sql', error_message())
END CATCH
end

print '############ end of file _drop_UPD_Margin.sql ################'

if exists (select * from ##errors)
begin
select * from ##errors
print 'Во время выполнения скрипта произошла ошибка. Выполнение прервано. Версия не обновлена.'
end
else
begin
print 'Скрипт выполнен успешно.'
-- скрипт устанавливает версию ПО в таблицу Setting
-- шаблон 15.3.0 подставляется билд скриптом
update setting 
set st_version = '15.3.0',
	ST_MODULEDATE = convert(datetime, '2018-06-29', 120),
	ST_FINANCEVERSION = '15.3.0',
	ST_FINANCEDATE = convert(datetime, '2018-06-29', 120)


UPDATE [dbo].[SYSTEMSETTINGS] 
SET SS_ParmValue = '2018-06-29' WHERE SS_ParmName='SYSScriptDate'
end
drop table ##errors

