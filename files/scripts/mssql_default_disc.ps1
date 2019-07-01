## This script exists to grab all MSSQL instances running on
## a server, loop through them, and find the databases within
## them, returning a JSON string of the results.

$ErrorActionPreference = "Stop"

# This function converts from one encoding to another.
function convertto-encoding ([string]$from, [string]$to){
    begin{
        $encfrom = [system.text.encoding]::getencoding($from)
        $encto = [system.text.encoding]::getencoding($to)
    }
    process{
        $bytes = $encto.getbytes($_)
        $bytes = [system.text.encoding]::convert($encfrom, $encto, $bytes)
        $encto.getstring($bytes)
    }
}

# First, grab our hostname
$SQLServer = $(hostname.exe)
# Now, we find all services that start with MSSQL$ and loop through them
Get-Service | Where-Object {$_.Name -eq 'MSSQLSERVER'  -and $_.Status -eq 'Running'}| ForEach-Object{
    # Create a connection string to connect to this instance, on this server.
    # Turn on Integrated Security so we authenticate as the account running
    # the script without a prompt.
    $connectionString = "Server = $SQLServer; Integrated Security = True; Connection Timeout = 2"

    # Create a new connection object with that connection string
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $connectionString
    # Try to open our connection, if it fails we won't try to run any queries
    try{
        $connection.Open()
    }
    catch{
        #Write-Host "Error connecting to $fullInstance!"
        $DataSet = $null
        $connection = $null
  
    }
    try{
        # Only run our queries if connection isn't null
        if ($connection -ne $null){
                # Create a MSSQL request
                $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
                # Select all the database names within this instance  
                $SqlCmd.CommandText = "SELECT @@servicename as inst, name FROM  sysdatabases"
                $SqlCmd.Connection = $Connection
                $SqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
                $SqlAdapter.SelectCommand = $SqlCmd
                $DataSet = New-Object System.Data.DataSet
                $SqlAdapter.Fill($DataSet) > $null
                $Connection.Close()
        }
    }
    catch{
        # If our query failed, set our dataset to null
        #Write-Host "Error executing query on $fullInstance!"
        $DataSet = $null
    }

    # Since we're explicitly looking for the default instance here, make sure we didn't get a named instance.
    # (This is a hack workaround for one dev environment server where somehow a named instance answers first on 1433)
    if ($DataSet.Tables[0].Rows[0].inst -ne "MSSQLSERVER") {
        Write-Warning ("Expected instance name to be MSSQLSERVER, but got {0}." -f $DataSet.Tables[0].Rows[0].inst)
        exit
    }

    # We get a list of databases. Append to the basename variable.
    if ($DataSet -ne $null){
        $basename = $basename + $DataSet.Tables[0]
    }
}

# So now $basename is full of our instance and database name rows
# We loop through them and print the results as a JSON string
$idx = 1
write-host "{"
write-host " `"data`":[`n"
foreach ($name in $basename)
{
    if ($idx -lt $basename.Count)
        {
            $line= "{ `"{#INST}`" : `"" + $name.inst + "`", "  + "`"{#DBNAME}`" : `"" + $name.name + "`" }," | convertto-encoding "cp866" "utf-8"
            write-host $line
        }
    # If this is the last row, we print a slightly different string - one without the trailing comma
    # Although I don't think the trailing comma would technically break JSON, this is the right way
    # to do it.
    elseif ($idx -ge $basename.Count)
        {
            $line= "{ `"{#INST}`" : `"" + $name.inst + "`", "  + "`"{#DBNAME}`" : `"" + $name.name + "`" }" | convertto-encoding "cp866" "utf-8"
            write-host $line
        }
    $idx++;
}
# Write our closing JSON brackets
 write-host
write-host " ]"
write-host "}"
 