Introduction
============
mirrortools is a set of stored procedures that allows the easy manipulation and management of a collection of mirrored databases on Microsoft SQL Server 2005+. For example, if we wanted to setup a new mirrored database, we’d just need to run:

  mirrotools copy, database_name
  mirrortools mirror, database_name

or if we wanted to failover all the databases on the server, we could run::

  mirrortools failover

Commands
========

FAILOVER: failover group of databases to mirroring partner
FORCE: performs forced failover to group of databases
SUSPEND: suspends mirroring for group of databases
RESUME: resumes mirroring on group of suspended databases
COPY: copies database from principal to mirror in order to be mirrrored
MIRROR: mirrors database once copied to mirror using High Availability model
MIRNOWIT: mirrors database once copied to mirror using High Protection model
KILLMIR: removes mirroring session for group of databases
AUTO_FAILOVER_ON: Sets group of databases to High-Safety with Auto Failover
AUTO_FAILOVER_OFF: Sets group of databases to High-Safety without Auto Failover
RECOVER: sets databases in 'restoring...' mode to be usable
SYNCLOGIN: synchronizes group of logins from principal to mirror
PARTNERDO: Executes t-sql command on partner instance of sql server
PARTNERDROP: Drops particular (single) database on partner server
STATUS: Displays current database mirroring status
HELP: Shows this help file...