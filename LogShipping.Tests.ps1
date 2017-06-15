<#
.SYNOPSIS 
Collection of tests to see of log shipping is still working

.DESCRIPTION
Collection of tests to see of log shipping is still working.
The overall test only looks at the status for the database.
The detailed test will go into the backup, copy en restore times.

.PARAMETER SqlServer
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -Credential parameter. 
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER Database
Supply the name(s) to filter out specfic databases

.PARAMETER Detailed
Shows more specific tests to find what has gone wrong.

#>

param(
    [Parameter(Mandatory = $true)]
    [object]$SqlServer,

    [Alias("SqlCredential")]
    [System.Management.Automation.PSCredential]
    $Credential,

    [object[]]$Database,

    [switch]$Detailed
)


# Check if the modules are present
if ((Get-Module -ListAvailable -Name dbatools, Pester).Count -eq 2) {
    try {
        # Import the modules
        Import-Module dbatools
        Import-Module Pester

        # test the connections to the instance
        $result = Test-SqlConnection -SqlServer $SqlServer -SqlCredential $Credential

        # If the connection was succesfull
        if ($result[-1].ConnectSuccess) {
            Describe "Testing Log Shipping State" {
                # Set up the query
                $query = "EXEC sp_help_log_shipping_monitor"

                # Get the results from the log shippingmonitor procedure
                $result = Invoke-Sqlcmd2 -ServerInstance $SqlServer -Database master -Query $query -Credential $Credential

                # Split the results in the primary and secondary databases
                if ($Database) {
                    $primary = $result | Where-Object {$_.is_primary -eq $true -and $Database -contains $_.database_name}
                    $secondary = $result | Where-Object {$_.is_primary -eq $false -and $Database -contains $_.database_name}
                }
                else {
                    $primary = $result | Where-Object {$_.is_primary -eq $true}
                    $secondary = $result | Where-Object {$_.is_primary -eq $false}
                }

                # Check if detailed tests are needed
                if ($Detailed) {
                    Context "Primary Databases" {
                        # Loop through the primary rows
                        foreach ($p in $primary) {
                            It "[$($p.database_name)]: Time since last backup should be less than ($($p.backup_threshold))" {
                                $p.time_since_last_backup  | Should BeLessThan $p.backup_threshold
                            }
                        }
                    }
        
                    Context "Secondary Databases" {
                        # Loop through the secondary rows
                        foreach ($s in $secondary) {
                            It "[$($s.database_name)]: Time since last restore should be less than ($($s.restore_threshold))" {
                                $s.time_since_last_restore | Should BeLessThan $s.restore_threshold
                            }

                            It "[$($s.database_name)]: Restore latency should be less than ($($s.restore_threshold))" {
                                $s.last_restored_latency | Should BeLessThan $s.restore_threshold
                            }
                        }
                    }
                }
                else {
                    Context "Overall Log Shipping Status" {
                        # Loop through each of the databases
                        foreach ($p in $primary) {
                            It "Log shipping status primary $($p.database_name) should be healthy (0)" {
                                $p.status | Should Be 0
                            }
                        }

                        foreach ($s in $secondary) {
                            It "Log shipping status secondary $($s.database_name) should be healthy (0)" {
                                $s.status | Should Be 0
                            }
                        }
                    }
                } # if detailed
            } # describe
        } # if connection
        else {
            Write-Warning "Couldn't connect to instance $SqlServer"
        }
    }
    catch {
        Write-Warning "Something went wrong.`n$($_)."
    }
}
else {
    Write-Warning "Please check if the module dbatools or Pester is installed!"
}












