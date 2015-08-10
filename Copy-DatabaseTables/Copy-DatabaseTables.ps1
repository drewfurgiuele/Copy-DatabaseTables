﻿<#
.SYNOPSIS
    Allows for a synchronization of objects belonging to a particular schema or just one particular object inside that schema between two SQL Server instances.
.DESCRIPTION
    This script will attempt to synchronize a collection of table objects from a provided schema name (or one object inside the same schema). It can either compare all of the data inside each object and insert/update/delete rows as required or it can drop and recreate the objects each time.
    Please note that if the -rebuild parameter is provided the script will attempt to drop and create the objects first. Existing indexes and foreign key references will be maintained. The script will log all DDL statements to a .SQL file located in the provided -WorkingDirectory parameter
.PARAMETER SourceServerName
    Aliases: ssn, sourceserver
    The hostname of the SQL server you want to copy from. This is a required parameter.
.PARAMETER SourceInstanceName
    Aliases: sin, sourceinstance
    The instance name of the SQL server you want to copy from. Default value is "DEFAULT" for non-named SQL instances. This is an optional parameter.
.PARAMETER SourceDatabaseName
    Aliases: sdn, sourcedatabase
    The name of the database the schema/object you want to copy reside in. This is a required parameter.
.PARAMETER SourceSchemaName
    Aliases: sscn, sourceschema
    The name of the schema you want to synchronize. This is a required parameter.
.PARAMETER SourceTableName
    Aliases: stn, sourcetable
    Tha name of the table you want to synchronize. Providing this parameter will ONLY synchronize that table, ignoring all other tables in the schema. Only the table name should be provided, not schema and table name. This is an optional parameter.
.PARAMETER DestinationServerName
    Aliases: dsn, destinationserver
    The hostname of the SQL server you want to copy to. This is a required parameter.
.PARAMETER DestinationInstanceName
    Aliases: din, destinationinstance
    The instance name of the SQL server you want to copy to. Default value is "DEFAULT" for non-named SQL instances. This is an optional parameter.
.PARAMETER DestinationDatabaseName
    Aliases: ddn, destinationdatabase
    The name of the database the schema/object you want to copy the objects to. This is a required parameter.
.PARAMETER DestinationSchemaName
    Aliases: dscn, destinationschema
    The name of the schema you the copied objects to appear in. The schema must exist already. This is a required parameter.
.PARAMETER WorkingDirectory
    The path on your local computer where the DDL SQL statements will reside. Used during a rebuild to store object definitions. This is a required parameter.
.EXAMPLE
.OUTPUTS
    None, unless -VERBOSE is specified. In fact, -VERBOSE is reccomended so you can see what is happening and when.
.NOTES
#>
param(
    [Alias("ssn","sourceserver")]        [Parameter(Mandatory=$true)] [string]$SourceServerName,
    [Alias("sin","sourceinstance")]      [Parameter(Mandatory=$false)] [string]$SourceInstanceName = "DEFAULT",
    [Alias("sdn","sourcedatabase")]      [Parameter(Mandatory=$true)] [string]$SourceDatabaseName,
    [Alias("sscn","sourceschema")]       [Parameter(Mandatory=$true)] [string]$SourceSchemaName,
    [Alias("stn","sourcetable")]         [Parameter(Mandatory=$false)] [string]$SourceTableName = $null,
    [Alias("dsn","destinationserver")]   [Parameter(Mandatory=$true)] [string]$DestinationServerName,
    [Alias("din","destinationinstance")] [Parameter(Mandatory=$false)] [string]$DestinationInstanceName = "DEFAULT",
    [Alias("ddn","destinationdatabase")] [Parameter(Mandatory=$true)] [string]$DestinationDatabaseName,
    [Alias("dscn","destinationschema")]  [Parameter(Mandatory=$true)] [string]$DestinationSchemaName,
    [Parameter(Mandatory=$true)]         [string]$WorkingDirectory,
    [Parameter(Mandatory=$false)]        [switch]$compareOnly
)

$sourceSQLCmdServerInstance = $SourceServerName
$destinationSQLCmdServerInstance = $DestinationServerName
if ($SourceInstanceName -ne "DEFAULT") { $sourceSQLCmdServerInstance += "\" + $SourceInstanceName }
if ($DestinationInstanceName -ne "DEFAULT") { $destinationSQLCmdServerInstance += "\" + $DestinationInstanceName }

Write-Verbose "Getting existing table information from $destinationServerName, instance name $destinationInstanceName"
$destinationPath = "SQLSERVER:\SQL\" + $destinationServerName + "\" + $destinationInstanceName + "\Databases\" + $destinationDatabaseName + "\tables"
$sourcePath = "SQLSERVER:\SQL\" + $sourceServerName + "\" + $sourceInstanceName + "\Databases\" + $sourceDatabaseName + "\tables"
$destinationDB = Get-ChildItem -Path ("SQLSERVER:\SQL\" + $destinationServerName + "\" + $destinationInstanceName + "\Databases") | Where-Object {$_.Name -eq $DestinationDatabaseName}
$sourceDB = Get-ChildItem -Path ("SQLSERVER:\SQL\" + $sourceServerName + "\" + $sourceInstanceName + "\Databases") | Where-Object {$_.Name -eq $SourceDatabaseName}
$destinationDB.Tables.Refresh()
$tables = Get-ChildItem -Path $destinationPath
foreach ($t in $tables)
{
	$t.ForeignKeys.Refresh()
}
$tables = $tables | Where-Object {$_.Schema -eq $DestinationSchemaName}
$sourceTables = Get-ChildItem -Path $sourcePath | Where-Object {$_.Schema -eq $sourceSchemaName}

if ($SourceTableName)
{
    Write-Verbose "Selecting table $sourceSchemaName.$sourcetablename only"
    $tables = $tables | Where-Object {$_.Name -eq $SourceTableName -and $_.Schema -eq $SourceSchemaName}
    $sourceTables = $sourceTables | Where-Object {$_.Name -eq $SourceTableName -and $_.Schema -eq $SourceSchemaName}
}
if (!$compareOnly)
{
    $permissions = @()
    $foreignKeys = @()
    $indexes = @()
    $timestamp = Get-Date -UFormat "%Y%m%d_%H%M%S"
    $workFileName = $WorkingDirectory + "\RequestMDMData_WorkFile_" + $timestamp + ".sql"
    $scriptingSrv = New-Object Microsoft.SqlServer.Management.Smo.Server($sourceSQLCmdServerInstance)
    $dropOptions = New-Object Microsoft.SqlServer.Management.Smo.Scripter($scriptingSrv)
    $dropOptions.options.ScriptDrops = $true
    $dropOptions.options.IncludeIfNotExists = $true
    $scriptingOptions = New-Object Microsoft.SqlServer.Management.Smo.Scripter($scriptingSrv)
    $scriptingOptions.options.IncludeIfNotExists = $true
    $scriptingOptions.options.DriPrimaryKey = $true

    Write-Verbose "Using script file: $workFileName"
    foreach ($st in $sourceTables)
    {
        $currentTable = $st.Schema + "." + $st.Name
        Write-Verbose "Scripting table $currentTable..."
        $dropCode = $dropOptions.Script($st)
        $tblCode = $scriptingOptions.Script($st)
        $dropCode | Out-File $workFileName -Append
        $tblCode | Out-File $workFileName -Append
    }
    Write-Verbose "Finding and saving any existing foreign key and index information.."
    ForEach ($t in $tables) 
    {
		$t.ForeignKeys.Refresh()
        $objectPermissions += $t.EnumObjectPermissions()
        $foreignKeys += $t.ForeignKeys
        $indexes += $t.Indexes | Where-Object {$_.IndexKeyType -ne "DriPrimaryKey"}
    }
    $foreignKeys += (Get-ChildItem -Path $destinationPath | Where-Object {$_.ForeignKeys.ReferencedTableSchema -eq $DestinationSchemaName}).ForeignKeys | Where-Object {$_.ReferencedTableSchema -eq $DestinationSchemaName -and $foreignKeys -notcontains $_}
    Write-Verbose "Capturing Permissions..."
    ForEach ($p in $objectPermissions)
    {
        $permissionsString =  ($p.PermissionState).ToString() + " " + ($p.PermissionType).ToString() + " ON [" + ($p.ObjectSchema).ToString() + "].[" + ($p.ObjectName).ToString() + "] TO [" + ($p.Grantee).ToString() + "]";
        Write-Verbose "Capturing object permission: $permissionsString"
        $permissionsString | Out-File $workFileName -Append
    }

    $totalForeignKeys = $foreignKeys.Count
    $totalIndexes = $indexes.Count
    Write-Verbose "There are $totalIndexes indexes to script out..."
    ForEach ($in in $indexes)
    {
        $currentIndex = $in.name
        Write-Verbose "Scripting index $currentIndex..."
        $inCode =  $in.Script()
        $inCode | Out-File $workFileName -Append
    }
    Write-Verbose "There are $totalForeignKeys foreign keys to script out..."

    foreach ($fk in $foreignKeys)
    {
        (Get-ChildItem -Path $destinationPath | Where-Object {$_.Name -eq $fk.ReferencedTable -and $_.Schema -eq $fk.ReferencedTableSchema}).ForeignKeys.Refresh()
        $fkObject = (Get-ChildItem -Path $destinationPath | Where-Object {$_.Name -eq $fk.Parent.Name -and $_.Schema -eq $fk.Parent.Schema}).ForeignKeys | Where-Object {$_.name -eq $fk.Name}
        $currentFKName = $fkObject.name
        Write-Verbose "Scripting foriegn key $currentFKName..."
        $fkCode =  $fkObject.Script()
        $fkCode | Out-File $workFileName -Append
        Write-Verbose "Dropping foriegn key $currentFKName..."
        $fkObject.Drop()
    }

    Write-Verbose "Applying workfile $workfilename"
    Invoke-Sqlcmd -ServerInstance $destinationSQLCmdServerInstance -Database $DestinationDatabaseName -InputFile $workfilename -Verbose
}

ForEach ($st in $sourceTables)
{
    $currentTable = $st.Schema + "." + $st.Name
    if (Get-ChildItem -Path $destinationPath | Where-Object {$_.Name -eq $st.Name -and $_.Schema -eq $st.Schema})
    {
        Write-Verbose "----------------------------"
        Write-Verbose "Current table: $currentTable"
        $masterData = Invoke-Sqlcmd -Query ("SELECT * FROM " + $currentTable) -ServerInstance $sourceSQLCmdServerInstance -Database $SourceDatabaseName
        $currentData = Invoke-Sqlcmd -Query ("SELECT * FROM " + $currentTable) -ServerInstance $destinationSQLCmdServerInstance -Database $DestinationDatabaseName
		$properties = $st.Columns | Where-Object {$_.Computed -eq $false}
        $dataTable = New-Object System.Data.DataTable
        ForEach ($p in $properties)
        {
            $dataTable.Columns.Add($p.Name) | Out-Null
			if ($p.DataType.SqlDataType -eq "uniqueidentifier") {$dataTable.Columns[$p.name].DataType = "guid"}
        }
        if ($currentData)
        {
            $primaryKey = $st.indexes | Where-Object {$_.IndexKeyType -eq "DriPrimaryKey"}
            $primaryKeyColumns = $primaryKey.IndexedColumns.Name
            Write-Verbose "Primary key column is $primaryKeyColumns"
            Write-Verbose "Comparing source and destination..."
            $dataDiff = Compare-Object -ReferenceObject $masterData -DifferenceObject $currentData -Property $primaryKeyColumns -IncludeEqual
            $inserts = $dataDiff | Where-Object {$_.SideIndicator -eq "<="}
            if ($inserts)
            {
                $targetConnection = New-Object System.Data.SqlClient.SqlConnection
                $targetConnectionString = "Server={0};Database={1};Trusted_Connection=True;Connection Timeout=15" -f $destinationSQLCmdServerInstance, $DestinationDatabaseName
                $bcp = New-Object System.Data.SqlClient.SqlBulkCopy($targetConnectionString, [System.Data.SqlClient.SqlBulkCopyOptions]::KeepIdentity)
                $bcp.DestinationTableName = "{0}.{1}" -f  $st.Schema, $st.Name
                $bcp.BatchSize = 1000
                ForEach ($p in $properties)
                {
                    $mapObj = New-Object System.Data.SqlClient.SqlBulkCopyColumnMapping($p.Name,$p.Name)
                    [void]$bcp.ColumnMappings.Add($mapObj)
                }

                ForEach ($i in $inserts)
                {
                    $missingRow = $i.$primaryKeyColumns
                    $rowData = $masterData | Where-Object {$_.$primaryKeyColumns -eq $missingRow}
                    Write-Verbose "There is no row with primary key value $missingRow in the destination; it will be inserted"
                    $newRow = $dataTable.NewRow()
                    ForEach ($p in $properties)
                    {
                        $newRow[$p.Name] = $rowData.($p.Name)
                    }
                    $dataTable.Rows.Add($newRow)
                }

                $bcp.WriteToServer($dataTable)
            }
            $deletes = $dataDiff | Where-Object {$_.SideIndicator -eq "=>"}
            ForEach ($d in $deletes)
            {
                $missingRow = $d.$primaryKeyColumns
                Write-Verbose "There is no row with primary key value $missingRow in the source; it will be removed"
                if ($missingRow.GetType().Name -eq "String") {$missingRow = "'" + $missingRow + "'"}
                $code = "DELETE FROM " + $currentTable + " WHERE " + $primaryKeyColumns + " = " + $missingRow
                Write-Verbose "SQL Code: $code"
                Invoke-Sqlcmd -Query $code -ServerInstance $destinationSQLCmdServerInstance -Database $DestinationDatabaseName
            }
            $compares = $dataDiff | Where-Object {$_.SideIndicator -eq "=="}
            ForEach ($c in $compares)
            {
                $keyValue = $c.$primaryKeyColumns
                $leftHash = $masterData | Where-Object {$_.$primaryKeyColumns -eq $keyValue}
                $rightHash = $currentData | Where-Object {$_.$primaryKeyColumns -eq $keyValue}
                ForEach ($p in $properties)
                {
                    $leftVal = ($leftHash.($p.Name)).ToString()
                    $rightVal = ($rightHash.($p.Name)).ToString()
                
                    if (($leftHash.($p.Name)).ToString() -ne ($rightHash.($p.Name)).ToString())
                    {
                        Write-Verbose "Rows with key value $keyvalue do not match in source and destination; the row will be refreshed"
                        $newValue = Select-Object -InputObject $leftHash -ExpandProperty $p.Name
                        if ($newValue.GetType().Name -eq "String") {$newValue = "'" + $newValue + "'"}
                        $code = "UPDATE " + $currentTable + " SET " + $p.Name + " = " + $newValue + " WHERE " + $primaryKeyColumns + " = " + $keyValue
                        Write-Verbose "SQL Code: $code"
                        Invoke-Sqlcmd -Query $code -ServerInstance $destinationSQLCmdServerInstance -Database $DestinationDatabaseName
                     }
                }
            }
        } else {
            Write-Verbose "No data exists in the destination tables; doing a bulk insert from the source."
            $targetConnection = New-Object System.Data.SqlClient.SqlConnection
            $targetConnectionString = "Server={0};Database={1};Trusted_Connection=True;Connection Timeout=15" -f $destinationSQLCmdServerInstance, $DestinationDatabaseName
            $bcp = New-Object System.Data.SqlClient.SqlBulkCopy($targetConnectionString, [System.Data.SqlClient.SqlBulkCopyOptions]::KeepIdentity)
            $bcp.DestinationTableName = "{0}.{1}" -f  $st.Schema, $st.Name
            $bcp.BatchSize = 1000
            $bcp.SqlRowsCopied
            ForEach ($p in $properties)
            {
                $mapObj = New-Object System.Data.SqlClient.SqlBulkCopyColumnMapping($p.Name,$p.Name)
                [void]$bcp.ColumnMappings.Add($mapObj)
            }
            ForEach ($m in $masterData)
            {
                $newRow = $dataTable.NewRow()
                ForEach ($p in $properties)
                {
                    $newRow[$p.Name] = $m.($p.Name)
                }
                $dataTable.Rows.Add($newRow)
            }
            $bcp.WriteToServer($dataTable)
        }
    } else {
        Write-Warning "The table $currentTable doesn't exist at the destination; use -REBUILD to copy the table"
    }
}