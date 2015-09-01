# Copy-DatabaseTables

Let's face it: copying a database table from one SQL Server to another is not an overly complex task. But what if the table you want to copy already exists at the destination? What about indexes? User permissions? And (gasp!) foreign keys on the target table (and all the related tables)?

Now, expand that to an entire schema. Sure, you can write an ETL that copies tables, but what if the number of tables changes? That's probably a code change, and a deployment to production. Nobody wants that!

Instead, we can leverage PowerShell to copy a table and all its data all while perserving the existing table's dependancies. The following script will take an entire schema's tables (or a specific table) and:

1. Find and save all existing indexes on the table at the destination,
2. Find and save all existing permissions on the table at the destination,
3. Find and save all existing foreign keys on the target table (and any related tables at the destination),
4. Drop and recreate the tables from the DDL statements used to create the tables from the source,
5. Reapply all indexes and user permissions,
6. Bulk copy the data from the source to the destination
7. Reapply all foreign keys

Please note that this script requires the SQLPS module. As always, don't just run something in your production environment without testing it first. This script was written in Visual Studio, so if you don't want the entire solution, just dig into the directories to get the .PS1 file.

Did you like this script? Me too! You should send me a shout-out via twitter @pittfurg
