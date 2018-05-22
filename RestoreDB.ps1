<#
====================================================================================
  File:     RestoreDB.ps1
  Author:   Changyong Xu
  Version:  SQL Server 2014, PowerShell V4
  Comment:  Get full backup Files and restore them automately.
            Run Powershell as Administrator,And execute like this:
            .\ResotreDB.ps1 "ALWAYSON3\TESTSTANDBY","F:\backupdata"
====================================================================================
#>

Function RestoreDB
{
    Param(
        [String]$Instance,
        [String]$BackupDirectory,
        [String]$UpgradeFlag = "After"
    )

    Begin
    {
        $Log = Join-Path $Home "Documents/FTP.log"
        Write-Debug $Log
    }

    Process
    {
        Try
        {
            $timestamp = Get-Date -format yyyyMMdd
            if ($UpgradeFlag -eq "After")
            {
                $FullBackupFiles = $BackupDirectory + "\*_" + $timestamp + "_sjh.bak"
            }
            elseif ($UpgradeFlag -eq "Before")
            {
                $FullBackupFiles = $BackupDirectory + "\*_" + $timestamp + "_sjq.bak"
            }
            else {

                $FullBackupFiles = $BackupDirectory + "\*_" + $timestamp + "_sjh.bak"
            }

            #list backup files
            $properties = @(
                'Name'
                'Directory'
                'LastWriteTime'
                @{
                    Label = 'Size'
                    Expression = {
                        if ($_.Length -ge 1GB)
                        {
                            '{0:F2} GB' -f ($_.Length / 1GB)
                        }
                        elseif ($_.Length -ge 1MB)
                        {
                            '{0:F2} MB' -f ($_.Length / 1MB)
                        }
                        elseif ($_.Length -ge 1KB)
                        {
                            '{0:F2} KB' -f ($_.Length / 1KB)
                        }
                        else
                        {
                            '{0} bytes' -f $_.Length
                        }
                    }
                }
            )

            Set-Location -Path $BackupDirectory
            Get-ChildItem -Path $FullBackupFiles -Force -ErrorAction Continue |
            Sort-Object -Property Length -Descending |
            Format-Table -Property $properties -AutoSize

            #confirm the action
            Write-Warning "This script is used to drop current databases, and restore them with backups"
            Write-Host "Yes to confirm,Ctrl+c to cancel"
            While($true)
            {
                $confirm = Read-Host
                if($confirm -ne 'Yes')
                {
                    Write-Host "Yes to confirm,Ctrl+c to cancel"
                    continue
                }
                else {
                    Write-Host "action confirmed,start to work..."
                    break
                }
            }

            #import SQL Server module
            Import-Module SQLPS -DisableNameChecking -Force

            #get default data file directory and backup directory
            $DBServer = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $Instance
            $DBServer.ConnectionContext.StatementTimeout = 0

            $RelocatePath = $DBServer.Settings.DefaultFile
            Write-Debug $RelocatePath

            #restore database
            foreach ($FullBackupFile in Get-ChildItem -Path $FullBackupFiles -Force -ErrorAction Continue)
            {
                Write-Debug $FullBackupFile.FullName
                $SmoRestore = New-Object Microsoft.SqlServer.Management.Smo.Restore
                $SmoRestore.Devices.AddDevice($FullBackupFile.FullName, [Microsoft.SqlServer.Management.Smo.DeviceType]::File)

                #get the db name from backup File
                $DBRestoreDetails = $SmoRestore.ReadBackupHeader($DBServer)
                $DBName = $DBRestoreDetails.Rows[0].DatabaseName
                Write-Debug $DBName

                #get the File list
                $FileList = $SmoRestore.ReadFileList($DBServer)
                $RelocateFileList = @()

                foreach($File in $FileList)
                {
                    $RelocateFile = Join-Path $RelocatePath (Split-Path $File.PhysicalName -Leaf)
                    $RelocateFileList += New-Object Microsoft.SqlServer.Management.Smo.RelocateFile($File.LogicalName, $RelocateFile)
                }

                if($DBServer.Databases.Item($DBName))
                {
                    $DBServer.KillAllProcesses($DBName)
                    $DBServer.Databases.Item($DBName).Drop()
                }

                Restore-SqlDatabase `
                -ReplaceDatabase `
                -ServerInstance $Instance `
                -Database $DBName.ToString() `
                -BackupFile $FullBackupFile.FullName `
                -RelocateFile $RelocateFileList

                Write-Host "########### $DBName is restored successfully.###########" -ForegroundColor Green
            }

            #list data files
            Set-Location -Path $RelocatePath
            Get-ChildItem -Path $RelocatePath -Force -ErrorAction Continue |
            Sort-Object -Property Length -Descending |
            Format-Table -Property $properties -AutoSize
        }
        Catch
        {
            $ErrorMessage = $_.Exception.Message
            "The error message was $ErrorMessage" | Out-File $Log -Append
            Break
        }
        Finally
        {
            $Time=Get-Date -format yyyy-MM-dd-HHmmss
            "$Time : This script is executed." | Out-File $Log -Append
        }
    }

    End{}
}

#$DebugPreference = "Continue"
#$DebugPreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"
RestoreDB -Instance $args[0] -BackupDirectory $args[1] -UpgradeFlag $args[2]
Read-Host -Prompt "Press Enter to continue"