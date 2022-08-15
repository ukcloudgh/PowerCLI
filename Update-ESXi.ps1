<#
.Synopsis
    Update ESXi host(s) unattended
.DESCRIPTION
    Used to update the ESXi hosts using VUM, either individually or on a per cluster basis.
.NOTES
    Please modify the following variables before running this script: $ScriptPath
.LINK
    https://github.com/ukcloudgh/PowerCLI/blob/main/Update-ESXi.ps1
    https://ukconsult.cloud/
.EXAMPLE
    .\Update-ESXi.ps1 -vCenterCluster clusterA -ESXiHost hostA
    where -vCenterCluster is a mandatory parameter
    if -ESXiHost is specified, only that host will be updated and not the cluster it belongs to
#>

# this is the definition of our parameters
param (
    [Parameter(Mandatory)][string]$vCenterCluster,
    [string]$ESXiHost
)

# setting up some variables
$ScriptPath = "C:\Scripts\VMware\"
$sName = "Update-ESXi"
$TPath = $ScriptPath + "Transcripts\"
$currentTime = Get-Date -format "_yyyy-MM-dd_HH-mm-ss_"
$TranscriptPath = $TPath + $sName + $currentTime + ".log"
$emailAttachmentclHTML = $ScriptPath + "Hosts_part_of_cluster_$vCenterCluster.html"
$emailAttachmentHTML = $ScriptPath + "VMs_running_on_$ESXiHost.html"

# this function adds the time to a message and standardizes how text is diplayed making it easier to trace back events
function LogMessage {
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true, Position=0)][string]$LogMessage
    )
    Write-Output "$(Get-Date -Format "dd/MM/yyyy HH:mm:ss") $LogMessage"
}

# this function prepares the attachment for one of the notifications and creates an HTML file detailing the ESXi hosts in the cluster
function GetClusterMembers {
# grab the list of hosts in the cluster
$ClusterMember = Get-Cluster $vCenterCluster | Get-VMHost | Select-Object Name,ConnectionState,PowerState,Version | Sort-Object Name
# define the formatting for the HTML report
$header=@"
<style>
@charset "UTF-8";
body {Font-Family: Arial;Font-Size: 11pt;}
</style>
"@
#Write HTML doc header
(@"
<!DOCTYPE html>
<head>
    <title>Hosts_part_of_cluster_$vCenterCluster</title>
    <style>
        @charset "UTF-8";
        body {Font-Family: Arial;Font-Size: 11pt;}
    </style>
</head>
<body>
<h2>Hosts_part_of_cluster_$vCenterCluster</h2><hr>
"@) | Out-File $emailAttachmentclHTML
(@"
<table>
<tr>
    <th>Name</th>
    <th>ConnectionState</th>
    <th>PowerState</th>
    <th>Version</th>
</tr>
"@) | Out-File $emailAttachmentclHTML -Append
$ClusterMember | % {
(@"
<tr>
    <td>$($_.Name)</td>
    <td style="text-align:center">$($_.ConnectionState)</td>
    <td style="text-align:center">$($_.PowerState)</td>
    <td style="text-align:center">$($_.Version)</td>
</tr>
"@) | Out-File $emailAttachmentclHTML -Append }
(@"
</table>
</body>
</html>
"@) | Out-File $emailAttachmentclHTML -Append
}

# this function prepares the attachment for one of the notifications and creates an HTML file detailing the VMs running on a host
function GetRunningVMs {
# grab the list of VMs running on the host
$vmList = Get-VMHost -Name $ESXiHost | Get-VM | Select-Object Name,PowerState,VMHost,NumCpu,MemoryGB,Notes | Sort-Object Name
# define the formatting for the HTML report
$header=@"
<style>
@charset "UTF-8";
body {Font-Family: Arial;Font-Size: 11pt;}
</style>
"@
#Write HTML doc header
(@"
<!DOCTYPE html>
<head>
    <title>VMs_running_on_$ESXiHost</title>
    <style>
        @charset "UTF-8";
        body {Font-Family: Arial;Font-Size: 11pt;}
    </style>
</head>
<body>
<h2>VMs running on $ESXiHost</h2><hr>
"@) | Out-File $emailAttachmentHTML
(@"
<table>
<tr>
    <th>Name</th>
    <th>PowerState</th>
    <th>VMHost</th>
    <th>NumCpu</th>
    <th>MemoryGB</th>
    <th>Notes</th>
</tr>
"@) | Out-File $emailAttachmentHTML -Append
$vmList | % {
(@"
<tr>
    <td>$($_.Name)</td>
    <td style="text-align:center">$($_.PowerState)</td>
    <td style="text-align:center">$($_.VMHost)</td>
    <td style="text-align:center">$($_.NumCpu)</td>
    <td style="text-align:center">$($_.MemoryGB)</td>
    <td>$($_.Notes)</td>
</tr>
"@) | Out-File $emailAttachmentHTML -Append }
(@"
</table>
</body>
</html>
"@) | Out-File $emailAttachmentHTML -Append
}

# this function handles communications to various teams where $notificationType dictates what e-mail is sent
function Notification {
    Param (
        [Parameter(Mandatory = $true)][string]$notificationType = "Dictates where the report should be sent"
    )
    $fromaddress = "ESXi_update_job@domain.com"
    $smtpserver = "inframailrelay.domain.com"
    $message = New-Object System.Net.Mail.MailMessage
    $smtp = New-Object Net.Mail.SmtpClient($smtpServer)
    $message.From = $fromaddress
    $emailBodyHTML = "C:\Scripts\VMware\UE_body.html"
    switch ($notificationType) {
        cluster {
            $toaddress = "ESXi_Host_Update_Job_Recipients@domain.com"
            $message.Subject = "VMware vCenter cluster $vCenterCluster - Update job about to commence"
            $eBody = "<p>Please note that the VMware ESXi hosts part of this cluster are about to be updated.</p>
            <p>Individual notifications will be sent on a per host basis if the host requires any patches and is about to be processed. 
            Additionally a timeline of the whole job will be communicated at the end.</p>
            <br>
            <p>Generating Script: Update-ESXi.ps1</p>"
            GetClusterMembers
            $attachment = $emailAttachmentclHTML
        }
        host {
            $toaddress = "ESXi_Host_Update_Recipients@domain.com"
            $message.Subject = "VMware ESXi host $ESXiHost - Update job about to commence"
            $eBody = "<p>Please note that VMware ESXi host $ESXiHost is about to be placed into Maintenance mode, 
            and as a result the attached list of VMs will be migrated to other ESXi hosts.</p>
            <p>Please review the list of VMs and inspect any DB servers as needed.</p>
            <p>Please note that the server will reboot as part of this process and the reboot itself takes between 15 and 20 minutes - please ignore any alerts.</p>
            <br>
            <p>Generating Script: Update-ESXi.ps1</p>"
            GetRunningVMs
            $attachment = $emailAttachmentHTML
        }
        hostComplete {
            $toaddress = "ESXi_Host_Update_Job_Recipients@domain.com"
            $message.Subject = "VMware ESXi host $ESXiHost - Update job about completed"
            $eBody = "<p>Please note that VMware ESXi host $ESXiHost has been updated and is back in production.</p>
            <p>Please resume responding to alerts.</p>
            <br>
            <p>Generating Script: Update-ESXi.ps1</p>"
            GetRunningVMs
            $attachment = $emailAttachmentHTML
        }
        ReviewHost {
            $toaddress = "ESXi_Host_Update_Job_Recipients@domain.com"
            $message.Subject = "VMware ESXi host $ESXiHost - Review why the host failed to enter maintenance mode"
            $eBody = "<p>The update job for VMware ESXi host $ESXiHost cannot continue.</p>
            <p>Please investigate.</p>
            <br>
            <p>Update-ESXi.ps1</p>"
            GetRunningVMs
            $attachment = $emailAttachmentHTML
        }
        endofjob {
            $toaddress = "ESXi_Host_Update_Job_Recipients@domain.com"
            $attachment = $TranscriptPath
            if ($PSBoundParameters.ContainsKey('ESXiHost') -eq $true) {
                $message.Subject = "VMware ESXi host $ESXiHost - Update job is now complete"
                $eBody = "<p>The update job for VMware ESXi host $ESXiHost is now complete.</p>
                <p>The transcript for the job is attached to this e-mail.</p>
                <br>
                <p>Update-ESXi.ps1</p>"
            } else {
                $message.Subject = "VMware vCenter cluster $vCenterCluster - Update job is now complete"
                $eBody = "<p>The update job for vCenter cluster $vCenterCluster is now complete.</p>
                <p>The transcript for the job is attached to this e-mail.</p>
                <br>
                <p>Update-ESXi.ps1</p>"
            }
        }
    }

    $message.To.Add($toaddress)
    $message.IsBodyHTML = $true

    ConvertTo-Html -Head $header -Body $eBody `
        | out-string `
        | Out-File $emailBodyHTML

    # ensure the file is present at location
    while ((Test-Path $emailBodyHTML) -eq $False) { Start-Sleep -s 1}

    # Fetch the files generated above and use them as e-mail body and attachment
    $message.Body = Get-Content $emailBodyHTML
    $mailAttachment = new-object Net.Mail.Attachment($attachment)
    $message.Attachments.Add($mailAttachment) 

    # send the e-mail
    $smtp.Send($message)

    # Cleanup - delete the HTML file from the file system
    $message.Dispose()
    If (Test-Path $emailBodyHTML){
        Remove-Item $emailBodyHTML
    }

}

# this function archives the host settings into a temporary profile which is useful if they haven't applied profiles at cluster level
function CreateHostProfile {
    LogMessage "Creating host profile for $ESXiHost"
    $myHost = Get-VMHost $ESXiHost
    try {
        New-VMHostProfile -Name $ESXiHost -Description "pre-update profile copy" -ReferenceHost $myHost | Out-Null
        LogMessage "Host profile created for $ESXiHost"
    }
    catch {
        LogMessage "There was a problem creating the host profile for $ESXiHost"
    }
}

<# when there are a lot of VM Overrides for DRS on cluster level, I find it easier to control when the host enters
maintenance mode and Get/Invoke DRS recommendations so that the host can sucesfuly enter maintenance mode.
this function places the hosts into Maintenance Mode #>
function EnterMaintenanceMode {
    LogMessage "Attempting to place ESXi host $ESXiHost into Maintenance mode"
    try {
        # place the host into Maintenance Mode
        Get-VMHost -Name $ESXiHost | Set-VMHost -State Maintenance -Confirm:$false -RunAsync -Evacuate | Out-Null
        $j = 0
        # wait/loop until all VMs migrate to other hosts in the cluster
        do {
            LogMessage "Waiting for the VMs to migrate off ESXi host $ESXiHost"
            Start-Sleep 60
            $j++
            # if there are any VMs with DRS overrides (PartiallyAutomated) this will allow them to migrate
            Get-Cluster -Name $vCenterCluster | Get-DrsRecommendation | Invoke-DrsRecommendation          
            $VMHostState = (Get-VMHost $ESXiHost).State
            # if the host has not entered maintenance mode in 30min skip it and send a notification out
            if ($j>29) {
                if ($VMHostState -ne 'Maintenance') {
                    LogMessage "ESXi host $ESXiHost was not able to enter Maintenance mode"
                    Notification -NotificationType ReviewHost
                    break
                }
            }
        } while ($VMHostState -ne 'Maintenance')
        LogMessage "Successfully placed ESXi host $ESXiHost into Maintenance mode"
    }
    catch {
        LogMessage "ESXi host $ESXiHost was not able to enter Maintenance mode"
    }
}

# this function will scan the host and report back the compliance status of the baselines
function CheckForUpdates {
    $baselines = Get-Baseline -BaselineType Patch
    Get-Inventory -Name $ESXiHost | Test-Compliance -UpdateType HostPatch,HostThirdParty
    $esxiCompliance = (Get-Compliance -Entity $ESXiHost -Baseline $baselines).Status
    return $esxiCompliance
}

# this function installs the required updates
function InstallUpdates {
    LogMessage "Starting remediation against ESXi host $ESXiHost"
    # start the update task
    $updateTask = Update-Entity -Entity $ESXiHost -Baseline $baselines -Confirm:$False -RunAsync
    # check task status periodically
    For ($i = 0; $i -lt 45; $i++) {
        LogMessage "Waiting for the remediation task to complete on ESXi host $ESXiHost"
        # Get the current task status
        try {
            $tskRunning = Get-Task -Id $updateTask.Id #-Server $vCenter
        }
        catch {
            LogMessage "No Task / Error finding the update tools task for ESXi host $ESXiHost"
        }
        If ($tskRunning.State -in 'Success', 'Error') {Break}
        Start-Sleep -Seconds 60
    }
    # Output task results
    Switch ($tskRunning.State) {
        'Queued' { LogMessage "The remediation task is in the queue waiting to be executed but the timeout for this script has been exceeded." }
        'Running' { LogMessage "The remediation task is still running on ESXi host $ESXiHost but the timeout for this script has been exceeded." }
        'Success' { LogMessage "The remediation task for ESXi host $ESXiHost has been completed successfully" }
        'Error' {
            LogMessage "The remediation task for ESXi host $ESXiHost has not been successful. Please investigate the error generated"
            # Exit with error
            #Exit 1
        }
    }
    if ($tskRunning.State -eq 'Success') {
        Notification -NotificationType hostComplete
    }
}

# this function will place the host back in production after the updates have been applied
function ExitMaintenanceMode {
    LogMessage "ESXi host $ESXiHost - attempting to exit Maintenance mode"
    try {
        Get-VMHost -Name $ESXiHost | Set-VMHost -State Connected -Confirm:$false -RunAsync | Out-Null
        do {
            LogMessage "ESXi host $ESXiHost - waiting for exit Maintenance mode task to complete"
            Start-Sleep 5       
            $VMHostState = (Get-VMHost $ESXiHost).State
        } while ($VMHostState -ne 'Connected')
        LogMessage "ESXi host $ESXiHost successfully exited Maintenance mode"
    }
    catch {
        LogMessage "ESXi host $ESXiHost failed to exit Maintenance mode"
    }
}

# in this function we have the order of the whole process and calling most other functions
function ProcessESXiHost {
    # exclude hosts which should not be processed outside of rare special maintenance windows
    if ($ESXiHost -in 'host_hostname1', 'host_hostname2') {
        LogMessage "This ESXi host $ESXiHost will not be processed as it is running sensitive VMs (Postilion Realtime, F5 etc.)"
    } else {
        LogMessage "Checking the compliance of ESXi host $ESXiHost against the existing Baseline (type patch)"
        # validate if updates are needed - "$complianceFlag -eq 1" will cause the updates to be installed
        $complianceFlag = 0
        foreach ($complianceStatus in CheckForUpdates) {
            if ($complianceStatus -eq 'NotCompliant') {
                $complianceFlag = 1
            }
        }
        # if there are non compliant baselines, process the host
        if ($complianceFlag -eq 1) {
            LogMessage "There are pending updates for ESXi host $ESXiHost"
            Notification -NotificationType host
            CreateHostProfile
            EnterMaintenanceMode
            if ((Get-VMHost $ESXiHost).State -eq "Maintenance") {
                LogMessage "ESXi host $ESXiHost is in Maintenance mode and ready to commence installing updates"
                InstallUpdates
                ExitMaintenanceMode
            } else {
                # if the host did not manage to enter into maintenance mode I choose to pause here but another action can be defined here too
                LogMessage "Update sequence cannot continue on $ESXiHost"
            }
        } else {
            LogMessage "Presently, there are no updates pending for ESXi host $ESXiHost - skipping host"
        }
    }
}

# redirect output to a temp transcript log
Start-Transcript -Path $TranscriptPath -NoClobber

# if $ESXiHost has been specified when calling the script, only that host will be updated
if ($PSBoundParameters.ContainsKey('ESXiHost') -eq $true) {
    LogMessage "Updating a single host $ESXiHost"
    ProcessESXiHost
    LogMessage "ESXi host $ESXiHost processing complete"
} else {
    LogMessage "Updating the ESXI hosts in vCenter cluster $vCenterCluster"
    Notification -NotificationType cluster
    # iterate through the hosts in the cluster
    (Get-Cluster $vCenterCluster | Get-VMHost).Name | ForEach {
        $ESXiHost = $_
        ProcessESXiHost
        LogMessage "ESXi host $ESXiHost processing complete"
    }
    LogMessage "vCenter cluster $vCenterCluster processing complete"
}

# Stop the transcript recording
Stop-Transcript

# wait for a bit, in case the enpoint security client has a lock on the transcript which will be used as attachment
Start-Sleep 10
# send a notification for job competion and attach the transcript generated
Notification -NotificationType endofjob
