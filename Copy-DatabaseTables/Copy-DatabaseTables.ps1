<#
.SYNOPSIS
.DESCRIPTION
.PARAMETER SourceInstanceName
.EXAMPLE
.OUTPUTS
.NOTES
#>
param(
    [Parameter(Mandatory=$true)]  [string]$serverName,
    [Parameter(Mandatory=$false)] [string]$instanceName = "DEFAULT",
    [Parameter(Mandatory=$false)] [string]$databaseName,
	[Parameter(Mandatory=$true)]  [validateset('File','Database')] [string] $saveTo, 
    [Parameter(Mandatory=$false)] [string]$fileName,
    [Parameter(Mandatory=$false)] [string]$repoServerName, 
    [Parameter(Mandatory=$false)] [string]$repoInstanceName = "DEFAULT", 
    [Parameter(Mandatory=$false)] [string]$repoDatabaseName = "Admin",
    [Parameter(Mandatory=$false)] [string]$repoSchemaName = "Repo",
	[Parameter(Mandatory=$false)] [string]$repoTableName = "ObjectsRepository"
)
$scanDate = Get-Date
$timestamp = Get-Date -UFormat "%Y%m%d_%H%M%S"

if (!$fileName -and ($saveTo -eq "File" -or $saveTo -eq "Both")) {$fileName = "DatabaseObjects_$timestamp.sql"}
Write-Verbose "Starting script"
Write-Verbose "Creating database connection objects..."

$serverPath = "SQLSERVER:\SQL\$serverName\$instanceName\databases"
$smoServerName = $serverName
if ($instanceName -ne "DEFAULT") {$smoServerName = $serverName + "\" + $instanceName}
$databases = Get-ChildItem -Path $serverPath
if ($databaseName) {$databases = $databases | Where-Object {$_.Name -eq $databaseName}}

Write-Verbose "Setting SqlServer.Management.SMO.Scripter options..."
$scriptingSrv = New-Object Microsoft.SqlServer.Management.Smo.Server ($smoServerName)
$scriptingOptions = New-Object Microsoft.SqlServer.Management.Smo.Scripter ($scriptingSrv)
$scriptingOptions.Options.BatchSize = 1
$scriptingOptions.Options.ScriptBatchTerminator = $true
$scriptingOptions.options.DriPrimaryKey = $true
if ($saveTo -eq "File") { $scriptingOptions.options.FileName = $fileName }
$scriptingOptions.Options.AppendToFile = $true

Write-Verbose "Server name that contains objects to collect: $serverName\$instanceName"

$objectsTable = New-Object System.Data.DataTable
$objectsTable.Columns.Add("ServerName") | Out-Null
$objectsTable.Columns.Add("DBContext") | Out-Null
$objectsTable.Columns.Add("ObjectFullName") | Out-Null
$objectsTable.Columns.Add("ObjectSchemaName") | Out-Null
$objectsTable.Columns.Add("ObjectID") | Out-Null
$objectsTable.Columns.Add("ObjectName") | Out-Null
$objectsTable.Columns.Add("ObjectType") | Out-Null
$objectsTable.Columns.Add("ObjectCode") | Out-Null
$objectsTable.Columns.Add("CaptureDate") | Out-Null
$objectsTable.Columns.Add("ObjectCreateDate") | Out-Null
$objectsTable.Columns.Add("ObjectModifiedDate") | Out-Null


function ScriptObjects($dbn, $scanType, $objects, $typeName, $previousScanDate) 
{
    $scannedObjectNames = @()
    $totalObjects = 0;
    if ($objects.length -ne $null) { $totalObjects = $objects.length }
    $statusMessage = "Scripting: " + $typename + " which has " + $totalObjects + " objects"
    Write-Verbose $statusMessage
	foreach ($o in $objects) 
    { 
    	if ($o -ne $null) 
        {
            if ($o.Properties["DateLastModified"].Value) { $lastModDate = Get-Date $o.Properties["DateLastModified"].Value }
            $objectCode = $scriptingOptions.Script($o)
			if ($saveTo -eq "Database")
			{
				$objectCodeString = [string]$objectCode
				$row = $objectsTable.NewRow()
				$row["ServerName"] = $serverName
				$row["DBContext"] = $dbn
				$objectFullName = $o.Schema + '.' + $o.Name
				if ($typeName -eq "Schema") { $objectFullName = $o.Name }
				$row["ObjectFullName"] = $objectFullName
				$row["ObjectSchemaName"] = $o.Schema
				$row["ObjectFullName"] = $objectFullName
                $row["ObjectID"] = $o.ID				
                $row["ObjectName"] = $o.Name
				$row["ObjectType"] = $typeName
				$row["CaptureDate"] = $scanDate.ToString();
				$row["ObjectCreateDate"] = $o.Properties["CreateDate"].Value
				$row["ObjectModifiedDate"] = $o.Properties["DateLastModified"].Value
				$row["ObjectCode"] = $objectCodeString
		        $objectsTable.Rows.Add($row)
			}
		}
	}
}


foreach ($d in $databases)
{
    $currentDatabase = $d.Name
    Write-Verbose "Scanning database: $currentDatabase"
        
    ScriptObjects $currentDatabase $scanType ($d.Schemas | Where-object { -not $_.IsSystemObject }) "Schema" $lastScan
	ScriptObjects $currentDatabase $scanType ($d.Users | Where-object { -not $_.IsSystemObject }) "Users" $lastScan
    ScriptObjects $currentDatabase $scanType ($d.UserDefinedTableTypes | Where-object { -not $_.IsSystemObject }) "User-Defined Table Type" $lastScan.LastScan
    ScriptObjects $currentDatabase $scanType ($d.UserDefinedTypes | Where-object { -not $_.IsSystemObject }) "User-Defined Type" $lastScan
    ScriptObjects $currentDatabase $scanType ($d.UserDefinedDataTypes | Where-object { -not $_.IsSystemObject }) "User-Defined Data Type" $lastScan
    ScriptObjects $currentDatabase $scanType ($d.UserDefinedFunctions | Where-object { -not $_.IsSystemObject }) "Functions" $lastScan.LastScan
    ScriptObjects $currentDatabase $scanType ($d.StoredProcedures | Where-object { -not $_.IsSystemObject }) "Stored Procedures" $lastScan.LastScan
    ScriptObjects $currentDatabase $scanType ($d.tables | Where-object { -not $_.IsSystemObject }) "Table" $lastScan.LastScan
	ScriptObjects $currentDatabase $scanType ($d.tables.indexes | Where-object { -not $_.IsSystemObject -and ($_.IndexKeyType.ToString()) -ne "DriPrimaryKey"}) "Indexes" $lastScan.LastScan
	ScriptObjects $currentDatabase $scanType ($d.tables.foreignKeys | Where-object { -not $_.IsSystemObject }) "Foreign Keys" $lastScan.LastScan
    ScriptObjects $currentDatabase $scanType ($d.Views | Where-object { -not $_.IsSystemObject }) "Views" $lastScan.LastScan
}
if ($saveTo -eq "Database")
{
	Write-Verbose "Target Repository SQL Server Database: $repoServername\$repoInstanceName"
	Write-Verbose "Connecting to server instance..."
	$adminConnection = New-Object System.Data.SqlClient.SqlConnection
	if ($repoInstanceName -ne "DEFAULT") { $repoServerName = "$repoServerName\$repoInstanceName" }
	$adminConnectionString = "Server={0};Database={1};Trusted_Connection=True;Connection Timeout=15" -f $repoServerName,$repoDatabaseName
	$bcp = New-Object System.Data.SqlClient.SqlBulkCopy($adminConnectionString)
	$bcp.DestinationTableName = "$RepoSchemaName.$RepoTableName"
	$bcp.BatchSize = 1000

	$mapObj = New-Object System.Data.SqlClient.SqlBulkCopyColumnMapping("ServerName","ServerName")
	[void]$bcp.ColumnMappings.Add($mapObj)
	$mapObj = New-Object System.Data.SqlClient.SqlBulkCopyColumnMapping("DBContext","DBContext")
	[void]$bcp.ColumnMappings.Add($mapObj)
	$mapObj = New-Object System.Data.SqlClient.SqlBulkCopyColumnMapping("ObjectFullName","ObjectFullName")
	[void]$bcp.ColumnMappings.Add($mapObj)
	$mapObj = New-Object System.Data.SqlClient.SqlBulkCopyColumnMapping("ObjectSchemaName","ObjectSchemaName")
	[void]$bcp.ColumnMappings.Add($mapObj)
	$mapObj = New-Object System.Data.SqlClient.SqlBulkCopyColumnMapping("ObjectID","ObjectID")
	[void]$bcp.ColumnMappings.Add($mapObj)
	$mapObj = New-Object System.Data.SqlClient.SqlBulkCopyColumnMapping("ObjectName","ObjectName")
	[void]$bcp.ColumnMappings.Add($mapObj)
	$mapObj = New-Object System.Data.SqlClient.SqlBulkCopyColumnMapping("ObjectType","ObjectType")
	[void]$bcp.ColumnMappings.Add($mapObj)
	$mapObj = New-Object System.Data.SqlClient.SqlBulkCopyColumnMapping("ObjectCode","ObjectCode")
	[void]$bcp.ColumnMappings.Add($mapObj)
	$mapObj = New-Object System.Data.SqlClient.SqlBulkCopyColumnMapping("CaptureDate","CaptureDate")
	[void]$bcp.ColumnMappings.Add($mapObj)
	$mapObj = New-Object System.Data.SqlClient.SqlBulkCopyColumnMapping("ObjectCreateDate","ObjectCreateDate")
	[void]$bcp.ColumnMappings.Add($mapObj)
	$mapObj = New-Object System.Data.SqlClient.SqlBulkCopyColumnMapping("ObjectModifiedDate","ObjectModifiedDate")
	[void]$bcp.ColumnMappings.Add($mapObj)


	Write-Verbose "Beginning BCP to repository on $repoServername\$repoInstanceName.$repoDatabaseName.$repoSchemaName.$repoTableName..."
	$bcp.WriteToServer($objectsTable)
	Write-Verbose "BCP Complete!"
}