USE [master]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[execute_job]
	@job_name varchar(255)
	
AS

	/* 
		execute_job

		description
			a native T-SQL stored procedure that executes a SQL Server Agent job and terminates when
            the job completes. (treats asynchronous job execution as a synchronous call)

		author
			Zakir Durumeric
			Research Information Systems (RIS)
			Office of the Vice-President for Research
			The University of Iowa
			zakir - durumeric @ uiowa . edu 

		dependencies:
		    NONE

		necessary configuration:
		    NONE

		version: 
			v1.00, 5/31/2011

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

	DECLARE @job_owner SYSNAME; 
	SET @job_owner = SUSER_SNAME();
	
	DECLARE @is_sysadmin TINYINT; 
	SET @is_sysadmin = IS_SRVROLEMEMBER('sysadmin');
	
	DECLARE @job_id UNIQUEIDENTIFIER; 
	SET @job_id = (SELECT TOP 1 job_id FROM [msdb].[dbo].[sysjobs] WHERE [name] = @job_name)
	
	IF @job_id IS NULL BEGIN
		RAISERROR('The specified job does not exist.',15,1)
	END
	
	exec msdb.dbo.sp_start_job 
		@job_id = @job_id;
	
	WAITFOR DELAY '00:00:01'; 
	
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

	
	INSERT INTO #enum_job_results 
		EXECUTE master.dbo.xp_sqlagent_enum_jobs @is_sysadmin, @job_owner;

	WHILE (SELECT [running] FROM #enum_job_results WHERE [job_id] = @job_id) <> 0 BEGIN
		declare @v int; set @v = (SELECT [running] FROM #enum_job_results WHERE [job_id] = @job_id)
		print @v
		WAITFOR DELAY '00:00:01'; 

		DELETE FROM #enum_job_results;
		INSERT INTO #enum_job_results 
			EXECUTE master.dbo.xp_sqlagent_enum_jobs @is_sysadmin, @job_owner;
	END

	DROP TABLE #enum_job_results
