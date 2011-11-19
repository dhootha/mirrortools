USE [master]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sync_logins] 

	@login_name varchar(max) = '*',
	@destination_server varchar(255),
	@disable_on_destination bit = 'false'

AS

	/* 
		sync_logins

		description
			a native T-SQL procedure that allows the synchronization of local SQL Server and Windows logins between
            multiple servers. The tool is mostly based on Microsoft's sp_help_login procedure, but allows execution
            on a different server and also supports the synchronization of system role membership.

		author
			Zakir Durumeric
			Research Information Systems (RIS)
			Office of the Vice-President for Research
			The University of Iowa
			zakir - durumeric @ uiowa . edu 

		dependencies:
			The procedure utilizes xp_cmdshell in order to execute commands on the destination server and also requires
            the stored procedure sp_hexadecimal which is distributed by Microsoft. 

		version: 
			v2.01, 5/31/2011

		disclaimer:
		
			THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
			IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
			FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
			AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
			LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
			OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
			THE SOFTWARE.

	*/

	DECLARE 
		@name sysname,
		@type varchar(1),
		@defaultdb sysname,
		@hasaccess int,
		@denylogin int,
		@is_disabled int,
		@PWD_varbinary  varbinary (256),
		@PWD_string  varchar (514),
		@SID_varbinary varbinary (85),
		@SID_string varchar (514),
		@is_policy_checked varchar (3),
		@is_expiration_checked varchar (3),
		@sysadmin int,
		@serveradmin int,
		@securityadmin int,
		@setupadmin int,
		@processadmin int,
		@diskadmin int,
		@dbcreator int,
		@bulkadmin int,
		@tmpstr varchar(max),
		@error varchar(max);
		
	DECLARE @logins_table TABLE(login_name sysname)
	SET @login_name = REPLACE(@login_name,' ','')

	IF (@login_name = '*') begin -- find all users if a specified user was not defined...
		DECLARE login_curs CURSOR FOR SELECT 
            p.sid,
            p.name,
            p.[type], 
            p.is_disabled, 
            p.default_database_name,
            I.hasaccess, 
            I.denylogin, 
            I.sysadmin, 
            I.serveradmin,
            I.securityadmin,
            I.setupadmin, 
            I.processadmin,
            I.diskadmin,
            I.dbcreator,
            I.bulkadmin 
        FROM sys.server_principals p LEFT JOIN sys.syslogins I ON ( I.name = p.name )
        WHERE p.type IN ( 'S', 'G', 'U' ) AND p.name NOT in ('sa','NT AUTHORITY\SYSTEM')

	end; ELSE /* if there is a list of users */ begin
		IF right(@Login_name, 1) <> ',' 
			SET @login_name = @login_name + ','; -- Add a comma to the end of the of lists of databases for parsing.

		DECLARE 
			@current_position int,
			@next_comma int, -- Declare some necessary variables for parsing through the list.
			@current_login_name varchar(2000);
			
		SET @current_position = 1; 
		SET @next_comma = charindex (',', @login_name, @current_position) 
		
		WHILE (@next_comma) <> 0 BEGIN
			SET @current_login_name = substring(@login_name, @current_position, @next_comma - @current_position)
			IF @current_login_name NOT IN (SELECT name FROM sys.syslogins) BEGIN
				declare @msg varchar(4000);
				set @msg = 'The login ' + @current_login_name + ' is invalid.';
			    raiserror(@msg, 16,1)
			END
			INSERT INTO @logins_table VALUES (@current_login_name)
			SET @current_position = @next_comma + 1 ; 
			SET @next_comma = charindex (',', @login_name, @current_position)
		END
		
		DECLARE login_curs CURSOR FOR SELECT 
            p.sid, 
            p.name,
            p.type, 
            p.is_disabled,
            p.default_database_name,
            I.hasaccess,
            I.denylogin,
            I.sysadmin,
            I.serveradmin,
            I.securityadmin,
            I.setupadmin,
            I.processadmin, 
            I.diskadmin, 
            I.dbcreator,
            I.bulkadmin 
		FROM sys.server_principals p LEFT JOIN sys.syslogins I ON I.name = p.name
		WHERE p.type IN ( 'S', 'G', 'U' ) 
			AND p.name IN (SELECT * FROM @logins_table) 
			AND p.name NOT IN ('sa','NT AUTHORITY\SYSTEM')
	END; 

	OPEN login_curs; FETCH NEXT FROM login_curs INTO
        @SID_varbinary,
        @name,
        @type, 
        @is_disabled,
        @defaultdb, 
        @hasaccess,
        @denylogin, 
        @sysadmin, 
        @serveradmin,
        @securityadmin,
        @setupadmin, 
        @processadmin, 
        @diskadmin,
        @dbcreator,
        @bulkadmin;

	WHILE (@@fetch_status <> -1) BEGIN
		IF (@type IN ('G','U')) BEGIN -- Windows Authentication
			SET @tmpstr = 'CREATE LOGIN ' + QUOTENAME(@name) + ' FROM WINDOWS WITH DEFAULT_DATABASE = [master]'
		END; ELSE BEGIN -- SQL Server authentication
			SET @PWD_varbinary = CAST(LOGINPROPERTY(@name, 'PasswordHash') AS varbinary (256))
			EXEC sp_hexadecimal @PWD_varbinary, @PWD_string OUT;
			EXEC sp_hexadecimal @SID_varbinary,@SID_string OUT;
			
			SELECT @is_policy_checked = CASE is_policy_checked 
				WHEN 1 THEN 'ON' 
				WHEN 0 THEN 'OFF' 
				ELSE NULL END 
			FROM sys.sql_logins WHERE name = @name
			
			SELECT @is_expiration_checked = CASE is_expiration_checked 
				WHEN 1 THEN 'ON' 
				WHEN 0 THEN 'OFF' 
				ELSE NULL END 
			FROM sys.sql_logins WHERE name = @name
	        
			SET @tmpstr = 'CREATE LOGIN ' + QUOTENAME(@name) + ' WITH PASSWORD = ' + @PWD_string + ' HASHED, SID = ' + @SID_string + ', DEFAULT_DATABASE = [master]'
			
			IF ( @is_policy_checked IS NOT NULL ) 
				SET @tmpstr = @tmpstr + ', CHECK_POLICY = ' + @is_policy_checked
			IF ( @is_expiration_checked IS NOT NULL ) 
				SET @tmpstr = @tmpstr + ', CHECK_EXPIRATION = ' + @is_expiration_checked
		END

		IF (@denylogin = 1) 
			SET @tmpstr = @tmpstr + '; DENY CONNECT SQL TO ' + QUOTENAME(@name)

		IF (@hasaccess = 0) 
			SET @tmpstr = @tmpstr + '; REVOKE CONNECT SQL TO ' + QUOTENAME(@name)

		IF (@is_disabled = 1) 
			SET @tmpstr = @tmpstr + '; ALTER LOGIN ' + QUOTENAME(@name) + ' DISABLE'

		IF (@sysadmin = 1 ) 
			SET @tmpstr = @tmpstr +'; EXEC sys.sp_addsrvrolemember @loginame = ' + QUOTENAME(@name) + ', @rolename = sysadmin'

		IF (@serveradmin = 1) 
			SET @tmpstr = @tmpstr +'; EXEC sys.sp_addsrvrolemember @loginame = ' + QUOTENAME(@name) + ', @rolename = serveradmin'

		IF (@securityadmin = 1) 
			SET @tmpstr = @tmpstr +'; EXEC sys.sp_addsrvrolemember @loginame = ' + QUOTENAME(@name) + ', @rolename = securityadmin'

		IF (@dbcreator = 1) 
			SET @tmpstr = @tmpstr +'; EXEC sys.sp_addsrvrolemember @loginame = ' + QUOTENAME(@name) + ', @rolename = dbcreator'

		IF (@bulkadmin = 1) 
			SET @tmpstr = @tmpstr +'; EXEC sys.sp_addsrvrolemember @loginame = ' + QUOTENAME(@name) + ', @rolename = bulkadmin'

		IF (@processadmin = 1) 
			SET @tmpstr = @tmpstr +'; EXEC sys.sp_addsrvrolemember @loginame = ' + QUOTENAME(@name) + ', @rolename = processadmin'

		IF (@diskadmin = 1) 
			SET @tmpstr = @tmpstr +'; EXEC sys.sp_addsrvrolemember @loginame = ' + QUOTENAME(@name) + ', @rolename = diskadmin'

		IF (@setupadmin = 1) 
			SET @tmpstr = @tmpstr +'; EXEC sys.sp_addsrvrolemember @loginame = ' + QUOTENAME(@name) + ', @rolename = setupadmin'

		DECLARE @command varchar(5000); 

		DECLARE @dropstr varchar(max); 
		SET @dropstr = 'DROP LOGIN [' + @name + ']' 
		set @command = '"sqlcmd -E -S ' + @destination_server + ' -Q "' + @dropstr + '""'
		exec xp_cmdshell @command
		SET @error = @@error;
		
		set @command = '"sqlcmd -E -S ' + @destination_server + ' -Q "' + @tmpstr + '""'
		exec xp_cmdshell @command
		SET @error = @@error; 
		
		IF @error = 0 BEGIN
			PRINT @name + ' successfully synchronized to ' + @destination_server
		END
		
		FETCH NEXT FROM login_curs INTO 
            @SID_varbinary, 
            @name,
            @type, 
            @is_disabled,
            @defaultdb, 
            @hasaccess, 
            @denylogin, 
            @sysadmin, 
            @serveradmin,
            @securityadmin, 
            @setupadmin, 
            @processadmin, 
            @diskadmin,
            @dbcreator,
            @bulkadmin;
	END;
	
	CLOSE login_curs; 
	DEALLOCATE login_curs;
	print '-- Login Synchronization Complete -- '

