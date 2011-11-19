USE [master]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[splitdetect]

AS

	/* 
		splitdetect

		description
			a native T-SQL stored procedure that detects if databases are split between two servers and sends
			out a notification e-mail. e.g. if database_a is primary on server_1, but database_b is primary 
			on server_2, but the databases should be running off of the same server. This can occur if you are
			utilizing automatic failover but only one database failsover not all of them. This was a necessary
			procedure for us since certain applications required multiple databases. 
		    
		author
			Zakir Durumeric
			Research Information Systems (RIS)
			Office of the Vice-President for Research
			The University of Iowa
			zakir - durumeric @ uiowa . edu 

		dependencies:
			A configured SQL Server Agent Mail Profile
		    
		necessary configuration:
			All necessary configuration can be completed by modifying the appropriate values within the 
			BEGIN PROCEDURE CONFIGURATION (USER EDITABLE) section of the file, several lines below this notice.
		        
		version: 
			v2.11, 5/31/2011

		disclaimer:
		
			Copyright (c) 2007 The University of Iowa
			
			Permission is hereby granted, free of charge, to any person obtaining a copy
			of this software and associated documentation files (the "Software"), to deal
			in the Software without restriction, including without limitation the rights
			to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
			copies of the Software, and to permit persons to whom the Software is
			furnished to do so, subject to the following conditions:

			The above copyright notice and this permission notice shall be included in
			all copies or substantial portions of the Software.

			THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
			IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
			FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
			AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
			LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
			OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
			THE SOFTWARE.

	*/
	
	
	/***************************************** BEGIN PROCEDURE CONFIGURATION (USER EDITABLE) *************************/

	-- name of the SQL Server Agent Profile that will be utilized to send e-mails
	DECLARE @mail_profile_name varchar(255); 
	SET @mail_profile_name = 'SET MAIL PROFILE NAME HERE';
	
	-- e-mail adderss to which notifications will be sent if a database split occurs
	DECLARE @recipients_address varchar(255);
	SET @recipients_address = 'your_email@your_domain.com'

	
	/****************************************** END PROCEDURE CONFIGURATION (USER EDITABLE) **************************/
	
	-- Create table in TempDB if it doesn't already exist and remove entries older than 1 week
	IF (OBJECT_ID('[TempDB].[dbo].[SPLIT_DETECT]') IS NULL) BEGIN
		CREATE TABLE [TempDB].[dbo].[SPLIT_DETECT](
			[STATUS] [int] NULL,
			[DT] [datetime] NULL CONSTRAINT [DF_SPLIT_DETECT_DT]  DEFAULT (getdate()),
			[NOTES] [nvarchar](max) NULL
		) ON [PRIMARY];
		INSERT [TempDB].[dbo].[split_detect](status) VALUES(-1)
	END; 

	DELETE FROM [TempDB].[dbo].[SPLIT_DETECT] WHERE ABS(DATEDIFF(dd,GETDATE(),DT)) > 7

-- Find if mirror_role is distinct. If not, then databases are split...
IF (SELECT COUNT(DISTINCT mirroring_role) FROM sys.database_mirroring WHERE mirroring_guid is not null) > 1 BEGIN
	DECLARE @lastsplit datetime; 
	 -- Find last time databases where split...
	SET @lastsplit = (SELECT TOP 1 dt from [TempDB].[DBO].[SPLIT_DETECT] ORDER BY DT DESC)
	
	DECLARE @laststatus int ; 
	 -- Find last time databases where split...
	SET @laststatus = (SELECT TOP 1 status from [TempDB].[DBO].[SPLIT_DETECT] ORDER BY DT DESC)

	-- If last split was > 1 minutes ago, then it is an actual issue... otherwise we might just be
	-- in the middle of a failover or other action
	IF ABS(DATEDIFF(n,@lastsplit,GETDATE())) > 1 AND @laststatus = 1 BEGIN
		declare @dt varchar(20); 
		set @dt = UPPER(CONVERT(varchar,getdate()));
		
		RAISERROR(N'DATABASE SPLIT ON %s AT %s.',16, 1, @@servername, @dt) WITH LOG
		
		DECLARE @mailbody varchar(400); 
		SET @mailbody = 'A DATABASE SPLIT HAS OCCURED ON ' + @@servername + ' AT ' + @dt + '.'
		
		DECLARE @mailsubj varchar(50); 
		SET @mailsubj = '[' + @@servername + '] DATABASE SPLIT'
		
		EXEC msdb.dbo.sp_send_dbmail 
			@recipients = @recipients_address, 
			@subject = @mailsubj, 
			@body = @mailbody, 
			@body_format = 'TEXT', 
			@profile_name = @mail_profile_name;

		INSERT [TempDB].[dbo].[split_detect](status) VALUES(2)
		
	END; ELSE BEGIN
		INSERT [TempDB].[dbo].[split_detect](status) VALUES(1)
	END; 
END; ELSE BEGIN
	INSERT [TempDB].[dbo].[split_detect](status) VALUES(0)
END;
