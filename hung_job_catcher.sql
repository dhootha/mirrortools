
/* 
	hung_job_catcher

	description
		a native T-SQL script that detects "hung" SQL Server Agent jobs and notifies any operators that
		are notified for job failure
	    
	author
		Zakir Durumeric
		Research Information Systems (RIS)
		Office of the Vice-President for Research
		The University of Iowa
		zakir - durumeric @ uiowa . edu 

	dependencies:
		Notification requires a configured SQL Server Agent Mail Profile that can be utilized for delivering emails
		
	necessary configuration:
		All necessary configuration can be completed by modifying the appropriate values 
		within the BEGIN PROCEDURE CONFIGURATION (USER EDITABLE) section of the file, several lines below 
		this notice. 

	version: 
		v1.21, 5/31/2011

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

DECLARE
	@mail_profile varchar(255),
	@hung_period tinyint;
	
SELECT
	@mail_profile = 'Alerts & Notification',
	@hung_period = 4; -- IN HOURS
	
/****************************************** END PROCEDURE CONFIGURATION (USER EDITABLE) **************************/

-- SCRIPT BODY -- 
CREATE TABLE #enum_job_results(
	[job_id] [uniqueidentifier] NOT NULL, 
	[last_run_date] [int] NOT NULL, 
	[last_run_time] [int] NOT NULL, 
	[next_run_date] [int] NOT NULL, 
	[next_run_time] [int] NOT NULL, 
	[next_run_schedule_id] [int] NOT NULL, 
	[requested_to_run] [int] NOT NULL, 
	[request_source] [int] NOT NULL, 
	[request_source_id] [sysname] NULL, 
	[running] [int] NOT NULL, 
	[current_step] [int] NOT NULL, 
	[current_retry_attempt] [int] NOT NULL, 
	[job_state] [int] NOT NULL);

DECLARE @job_owner sysname; 
SET @job_owner = SUSER_SNAME();

DECLARE @is_sysadmin tinyint; 
SET @is_sysadmin = IS_SRVROLEMEMBER('sysadmin');

INSERT INTO #enum_job_results 
EXECUTE master.dbo.xp_sqlagent_enum_jobs @is_sysadmin, @job_owner;

IF NOT EXISTS (SELECT * FROM [tempdb].[sys].[objects] WHERE [name] = 'dba_job_status' AND [type] ='U') BEGIN
	CREATE TABLE [tempdb].[dbo].[dba_job_status](
		[job_id] [uniqueidentifier] NOT NULL,
		[start_time] [datetime] NOT NULL,
		[last_checked] [datetime] NOT NULL,
		[notification_sent] [bit] NOT NULL);
END; ELSE BEGIN
	DELETE FROM [tempdb].[dbo].[dba_job_status] WHERE [job_id] IN (SELECT [job_id] FROM #enum_job_results WHERE [job_state] NOT IN (1,3,7));

	DELETE FROM [tempdb].[dbo].[dba_job_status] 
		WHERE [job_id] IN (SELECT [tempdb].[dbo].[dba_job_status].[job_id] FROM #enum_job_results
			INNER JOIN [tempdb].[dbo].[dba_job_status] ON #enum_job_results.[job_id] = [tempdb].[dbo].[dba_job_status].[job_id] 
			WHERE convert(datetime,STUFF(STUFF([last_run_date],5,0,'-'),8,0,'-') + ' ' + STUFF(STUFF((CASE 
				WHEN LEN(convert(varchar,[last_run_time]))=4 THEN '12'+convert(varchar,[last_run_time])
				ELSE REPLICATE('0',6-LEN(convert(varchar,[last_run_time])))+convert(varchar,[last_run_time]) END
			),3,0,':'),6,0,':'),121) > [start_time])

	UPDATE [tempdb].[dbo].[dba_job_status] SET [last_checked] = getdate()
END

INSERT INTO [tempdb].[dbo].[dba_job_status]([job_id],[start_time],[last_checked],[notification_sent]) 
	SELECT [job_id], getdate(), getdate(), 'false' FROM #enum_job_results WHERE [job_id] NOT IN (SELECT [job_id] FROM [tempdb].[dbo].[dba_job_status]) AND [job_state] IN (1,3,7);

DROP TABLE #enum_job_results;

DECLARE 
	@job_id uniqueidentifier,
	@start_time datetime,
	@name varchar(255),
	@notify_level_eventlog tinyint,
	@notify_level_email tinyint,
	@notify_level_page tinyint,
	@notify_email_operator_id tinyint,
	@notify_page_operator_id tinyint,
	@email_subject varchar(50),
	@email_body varchar(255),
	@pager_mail varchar(50); 

DECLARE crs_jobs CURSOR LOCAL FORWARD_ONLY FOR SELECT 
	[tempdb].[dbo].[dba_job_status].[job_id], 
	[start_time], [name], 
	[notify_level_eventlog], 
	[notify_level_email], 
	[notify_level_page], 
	[notify_email_operator_id], 
	[notify_page_operator_id] 
FROM [msdb].[dbo].[sysjobs] INNER JOIN [tempdb].[dbo].[dba_job_status] ON [msdb].[dbo].[sysjobs].[job_id] = [tempdb].[dbo].[dba_job_status].[job_id] 
WHERE dateadd(hh,@hung_period,[start_time]) <= getdate() AND notification_sent = 'false';

OPEN crs_jobs; 
FETCH NEXT FROM crs_jobs INTO 
	@job_id, 
	@start_time, 
	@name, 
	@notify_level_eventlog, 
	@notify_level_email, 
	@notify_level_page, 
	@notify_email_operator_id, 
	@notify_page_operator_id;

WHILE (@@fetch_status) <> -1 BEGIN
	/* 
		bitmask values for when to alert for @notify_level_eventlog, @notify_level_email, @notify_level_page
			0 = never
			1 = success
			2 = failure
			3 = completion 
	*/
	SET @email_subject = '[' + @@servername + ']' + ' Hung Job: ' + @name;

	IF @notify_level_eventlog in (2,3) BEGIN
		DECLARE @str_date varchar(255);
		SET @str_date = (convert(varchar,@start_time));
		raiserror('The job %s has been flagged as a hung job since it has been running since %s which is more than %i hours ago.',10,1,@name,@str_date,@hung_period) WITH LOG;
	END;
	IF @notify_level_email in (2,3) BEGIN
		SET @email_body = 'The job ' + @name + ' has been running since ' + convert(varchar,@start_time) + ' which is more than ' + convert(varchar,@hung_period) + ' hours (the specified hang time) on ' + @@servername + '.';
		exec [msdb].[dbo].[sp_notify_operator]
			@profile_name = @mail_profile,
			@id = @notify_email_operator_id,
			@subject = @email_subject,
			@body = @email_body;
	END
	IF @notify_level_page in (2,3) BEGIN
		SET @email_body = 'The job ' + @name + ' is hung on ' + @@servername + '.';
		SET @pager_mail = (SELECT pager_address FROM [msdb].[dbo].[sysoperators] WHERE id = @notify_page_operator_id);
		IF (SELECT enabled FROM [msdb].[dbo].[sysoperators] WHERE id = @notify_page_operator_id) = 1 BEGIN
			exec msdb.dbo.sp_send_dbmail
				@recipients = @pager_mail,
				@subject = @email_subject,
				@body = @email_body,
				@profile_name = @mail_profile;
		END;
	END;
	UPDATE [tempdb].[dbo].[dba_job_status] SET [notification_sent] = 'true' WHERE [job_id] = @job_id;
	FETCH NEXT FROM crs_jobs INTO @job_id, @start_time, @name, @notify_level_eventlog, @notify_level_email, @notify_level_page, @notify_email_operator_id, @notify_page_operator_id;
	
END; 
CLOSE crs_jobs;
DEALLOCATE crs_jobs;