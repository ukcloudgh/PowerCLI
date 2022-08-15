<#
.Synopsis
   Migrate NetworkAdapters between Virtual Distributed Portgroups
.DESCRIPTION
   In some environments the risk for transaction processing is too great and we cannot simply upgrade Distributed Switches.
   Instead, we opt to create a new VDS on the required (latest) version and migrate the adapters to the new distributed port groups.
   As part of the upgrade of DVS, this script migrates the NetworkAdapters from one VDP to another
.LINK
    https://github.com/ukcloudgh/PowerCLI/edit/main/Migrate-NetworkAdapters-VDP.ps1
.EXAMPLE
   Update the values of $oldVDPortgroup,$vmExclusions,$PPPath and run the script using existing connection to a vCenter
#>

# define vaiables
$oldVDPortgroup="portgroup1"
$newVDPortgroup=$oldVDPortgroup+"_v65-VDP"
# the following two lines remove characters which are not allowed in the port group names
$pattern = '[\\/]'
$newVDPortgroupE = $newVDPortgroup -replace $pattern, '_'
# I've added exclusions since we have VMs which require extra attention and cannot be manipulated while actively serving transactions - these can be done separately
$vmExclusions = "vm1","vm2","vm3"
$PPPath = "C:\Scripts\VMware\Transcripts\"
$currentTime = Get-Date -format "_yyyy-MM-dd_HH-mm-ss_"
$TranscriptPath = $PPPath + "MigrationTo_" + $newVDPortgroupE + $currentTime + ".log"
$myCountIgnore = 0
$myCountProcess = 0
$myCountScanned = 0

# dump all output to a file
Start-Transcript -Path $TranscriptPath -NoClobber
# process each cluster
Get-Cluster | ForEach-Object -Process {
    $clusName = $_.Name
    $clusName { 
        # for each VM
        Get-Cluster $clusName | Get-VM | ForEach-Object -Process {
            $myVMName = $_.Name
            if ( $vmExclusions -contains $myVMName ) {
                # if the VM should be excluded just add to stats
                $myCountIgnore++
            } else {
                # otherwise process VM and modify the portgroup for the NICs matching the old port group
                Get-NetworkAdapter -VM $myVMName | Where-Object {$_.NetworkName -eq $oldVDPortgroup} | ForEach-Object -Process {
                    Write-Host $_.Parent,$_.ConnectionState,$_.Name,$_.NetworkName
                    Get-NetworkAdapter -VM $myVMName | Where-Object {$_.NetworkName -eq $oldVDPortgroup} | Set-NetworkAdapter -Portgroup $newVDPortgroup -Confirm:$false -Verbose #-WhatIf 
                    # sleep is only required if you are processing SQL cluster nodes sequentially
                    Start-Sleep -Seconds 10
                    $myCountProcess++
                }
                $myCountScanned++
            }
        }
    }
}
# print some stats
Write-Host "Ignored" $myCountIgnore "VMs"
Write-Host "Processed" $myCountProcess "Network Adapters"
Write-Host "Scanned" $myCountScanned "VMs in Total"

# stop and write the transcript
Stop-Transcript
