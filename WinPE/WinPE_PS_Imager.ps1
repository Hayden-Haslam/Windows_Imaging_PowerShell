<#
.SYNOPSIS
    Provides a GUI for applying Windows WIM images within WinPE.

.DESCRIPTION
    This script launches a Windows Forms application that detects available .wim files 
    in the \Stage directory, formats the largest available disk according to UEFI/GPT 
    standards, and applies the selected image using an asynchronous runspace to keep 
    the UI responsive.

.NOTES
    Author: Hayden Haslam
    Date: 05/05/2026
#>
#requires -RunAsAdministrator

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$WinPESourceDrive = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control"
$drive_letter = $WinPESourceDrive.PEBootRamdiskSourceDrive[0]
$log_file = "${drive_letter}:\Stage\ImagingLog.txt"
$log_format = (Get-Date -Format "[MM/dd-HH:mm:ss]")
"$log_format ########## START NEW LOG ##########" | Out-File $log_file -Append

# Create the form

$FORM_Main = New-Object System.Windows.Forms.Form
$FORM_Main.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$ScreenWidth = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
if ($ScreenWidth -ge 1920) {
    $FontSize = 12
}
else {
    $FontSize = 18
}
$FORM_Main.Font = New-Object System.Drawing.Font("", $FontSize)
$FORM_Main.TopMost = $true
$FORM_Main.Text = "PowerShell Imaging Utility"
$FORM_Main.BackColor = "#c8102e"
$FORM_Main.Width = 800
$FORM_Main.Height = 500
$FORM_Main.StartPosition = "CenterScreen"
$FORM_Main.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$FORM_Main.MinimizeBox = $false
$FORM_Main.MaximizeBox = $false
<#
#Bitmap of Icon
$iconBase64 = ''
$iconBytes = [Convert]::FromBase64String($iconBase64)
$stream = [System.IO.MemoryStream]::new($iconBytes, 0, $iconBytes.Length)
$FORM_Main.Icon = [System.Drawing.Icon]::FromHandle(([System.Drawing.Bitmap]::new($stream).GetHicon()))
#>

#region Panels

# Start Panel
# Instruction Label "Select and image:"
$START_LBL_Select = New-Object System.Windows.Forms.Label
$START_LBL_Select.Text = "Select an image:"
$START_LBL_Select.Location = New-Object System.Drawing.Point(50, 50)
$START_LBL_Select.Size = New-Object System.Drawing.Size(225, 50)

# Dropdown box containing all available images
$START_CB_Images = New-Object System.Windows.Forms.ComboBox
$START_CB_Images.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$START_CB_Images.Width = 450
$START_CB_Images.Location = New-Object System.Drawing.Point(275, 50)    

# Display disk information
$START_LBL_Disk = New-Object System.Windows.Forms.Label
$START_LBL_Disk.Text = "Selected disk:"
$START_LBL_Disk.Location = New-Object System.Drawing.Point(50, 150)
$START_LBL_Disk.Size = New-Object System.Drawing.Size(225, 150)

# Dropdown box containing all available disks
$START_TB_Disks = New-Object System.Windows.Forms.TextBox    
$START_TB_Disks.Width = 450
$START_TB_Disks.Location = New-Object System.Drawing.Point(275, 150)
$START_TB_Disks.ReadOnly = $true

# Next button to move on to applying the image
$START_BTN_Next = New-Object System.Windows.Forms.Button
$START_BTN_Next.Location = New-Object System.Drawing.Point(425, 300)
$START_BTN_Next.Size = New-Object System.Drawing.Size(300, 100)
$START_BTN_Next.Text = "Next"

# Cancel button to shutdown the computer
$START_BTN_Cancel = New-Object System.Windows.Forms.Button
$START_BTN_Cancel.Location = New-Object System.Drawing.Point(50, 300)
$START_BTN_Cancel.Size = New-Object System.Drawing.Size(300, 100)
$START_BTN_Cancel.Text = "Cancel"

$START_Panel = New-Object System.Windows.Forms.Panel
$START_Panel.Location = New-Object System.Drawing.Point(0, 0)
$START_Panel.Size = New-Object System.Drawing.Size(800, 500)
$START_Panel.Visible = $false

@(
    $START_LBL_Select,
    $START_CB_Images,
    $START_LBL_Disk,
    $START_TB_Disks,
    $START_BTN_Next,
    $START_BTN_Cancel
) | ForEach-Object { $START_Panel.Controls.Add($_) }

$FORM_Main.Controls.Add($START_Panel)
# End Panel

# Apply Image Panel
# Status label
$APPLY_LBL_Status = New-Object System.Windows.Forms.Label
$APPLY_LBL_Status.Location = New-Object System.Drawing.Point(50, 50)
$APPLY_LBL_Status.Size = New-Object System.Drawing.Size(700, 50)    

# Status Time label
$APPLY_LBL_Progress = New-Object System.Windows.Forms.Label
$APPLY_LBL_Progress.Location = New-Object System.Drawing.Point(50, 100)
$APPLY_LBL_Progress.Size = New-Object System.Drawing.Size(700, 50)

# Job Output
$APPLY_RTB_Status = New-Object System.Windows.Forms.RichTextBox
$APPLY_RTB_Status.Location = New-Object System.Drawing.Point(50, 150)
$APPLY_RTB_Status.Size = New-Object System.Drawing.Size(700, 100)
$APPLY_RTB_Status.Multiline = $true
$APPLY_RTB_Status.ReadOnly = $true
$APPLY_RTB_Status.Visible = $true

# Next button to move on to applying the image
$APPLY_BTN_Restart = New-Object System.Windows.Forms.Button
$APPLY_BTN_Restart.Location = New-Object System.Drawing.Point(425, 300)
$APPLY_BTN_Restart.Size = New-Object System.Drawing.Size(300, 100)
$APPLY_BTN_Restart.Text = "Next"
$APPLY_BTN_Restart.Enabled = $false

$APPLY_Panel = New-Object System.Windows.Forms.Panel
$APPLY_Panel.Location = New-Object System.Drawing.Point(0, 0)
$APPLY_Panel.Size = New-Object System.Drawing.Size(800, 500)
$APPLY_Panel.Visible = $false

@(
    $APPLY_LBL_Status,
    $APPLY_LBL_Progress,
    $APPLY_RTB_Status,
    $APPLY_BTN_Restart
) | ForEach-Object { $APPLY_Panel.Controls.Add($_) }

$FORM_Main.Controls.Add($APPLY_Panel)
# End Panel

# Error Panel
# Display Error message
$SHUTDOWN_LBL_Shutdown = New-Object System.Windows.Forms.Label
$SHUTDOWN_LBL_Shutdown.Text = "Press `"Shutdown`" to power off the computer."
$SHUTDOWN_LBL_Shutdown.Location = New-Object System.Drawing.Point(25, 50)
$SHUTDOWN_LBL_Shutdown.Size = New-Object System.Drawing.Size(700, 50) 

# Shutdown Button
$SHUTDOWN_BTN_Shutdown = New-Object System.Windows.Forms.Button
$SHUTDOWN_BTN_Shutdown.Text = "Shutdown"
$SHUTDOWN_BTN_Shutdown.Location = New-Object System.Drawing.Point(425, 300)
$SHUTDOWN_BTN_Shutdown.Size = New-Object System.Drawing.Size(300, 100)

$SHUTDOWN_Panel = New-Object System.Windows.Forms.Panel
$SHUTDOWN_Panel.Location = New-Object System.Drawing.Point(0, 0)
$SHUTDOWN_Panel.Size = New-Object System.Drawing.Size(800, 500)
$SHUTDOWN_Panel.Visible = $false

@(
    $SHUTDOWN_LBL_Shutdown,
    $SHUTDOWN_BTN_Shutdown
) | ForEach-Object { $SHUTDOWN_Panel.Controls.Add($_) }

$FORM_Main.Controls.Add($SHUTDOWN_Panel)
# End Panel

#endregion

#region Event Handlers

# Start Panel Logic
# Next Button
$START_BTN_Next.Add_Click({
        # Hide the start panel, Show apply panel
        $START_Panel.Visible = $false
        $APPLY_Panel.Visible = $true
        $Timer = [System.Diagnostics.Stopwatch]::StartNew()
        $Timer.Start()
        # Apply the image to the device
        $APPLY_LBL_Status.Text = "Applying image: $($AvailableImages[$START_CB_Images.SelectedIndex].ImageName)"
        $DiskIndex = $SelectedDisk.Number
        $ImagePath = $AvailableImages[$START_CB_Images.SelectedIndex].ImagePath
        $ImageIndex = $AvailableImages[$START_CB_Images.SelectedIndex].ImageIndex
        $ScriptBlock = {
            param (
                $DiskNumber,
                $Path,
                $Index
            )
            # -- Variables --
            # Partitions
            $System = [PSCustomObject]@{
                Size    = 260MB
                GptType = "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}"
                Letter  = "S"
                Label   = "System"
            }
            $MSR = [PSCustomObject]@{
                Size    = 16MB
                GptType = "{e3c9e316-0b5c-4db8-817d-f92df00215ae}"
                Letter  = $null
                Label   = $null
            }
            $Windows = [PSCustomObject]@{
                Size    = $null
                GptType = "{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}"
                Letter  = "W"
                Label   = "Windows"
            }
            $Recovery = [PSCustomObject]@{
                Size    = 20GB
                GptType = "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}"
                Letter  = "R"
                Label   = "Recovery"
            }
            # ============================
            # NUKE AND PAVE (FRESH BUILD)
            # ============================
            # 1. Wipe Disk
            Write-Output "Formatting Disk $DiskNumber..."
            Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
            Initialize-Disk -Number $DiskNumber -PartitionStyle GPT

            # 2. Create System Partition (EFI)
            Write-Output "Creating EFI Partition..."
            $SystemPartition = New-Partition -DiskNumber $DiskNumber -Size $System.Size -GptType $System.GptType
            $SystemPartition | Get-Partition | Set-Partition -NewDriveLetter $System.Letter
            $SystemPartition | Format-Volume -FileSystem FAT32 -NewFileSystemLabel $System.Label -Confirm:$false -Force | Out-Null
            $SystemPartition = Get-Partition -DiskNumber $DiskNumber | Where-Object DriveLetter -eq $System.Letter

            # 3. Create MSR Partition
            Write-Output "Creating MSR Partition..."
            New-Partition -DiskNumber $DiskNumber -Size $MSR.Size -GptType $MSR.GptType | Out-Null

            # 4. Create Windows Partition (minus 20GB for Recovery Partition)
            Write-Output "Creating Windows Partition..."
            $DiskData = Get-Disk -Number $DiskNumber
            $AvailableSize = $DiskData.LargestFreeExtent
            $Windows.Size = $AvailableSize - $Recovery.Size
            $WindowsPartition = New-Partition -DiskNumber $DiskNumber -Size $Windows.Size -GptType $Windows.GptType
            $WindowsPartition | Get-Partition | Set-Partition -NewDriveLetter $Windows.Letter
            $WindowsPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel $Windows.Label -Confirm:$false -Force | Out-Null
            $WindowsPartition = Get-Partition -DiskNumber $DiskNumber | Where-Object DriveLetter -eq $Windows.Letter

            # 5. Create Recovery Partition
            Write-Output "Creating Recovery Partition..."
            $RecoveryPartition = New-Partition -DiskNumber $DiskNumber -UseMaximumSize -GptType $Recovery.GptType
            $RecoveryPartition | Get-Partition | Set-Partition -NewDriveLetter $Recovery.Letter
            $RecoveryPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel $Recovery.Label -Confirm:$false -Force | Out-Null
            $RecoveryPartition = Get-Partition -DiskNumber $DiskNumber | Where-Object DriveLetter -eq $Recovery.Letter

            # 6. Configure Recovery Environment
            # Copy install.wim, local_recovery_boot.wim, and boot.sdi to Recovery Partition
            Write-Output "Configuring Recovery Environment..."
            $ImgRoot = Split-Path $Path
            $ImgFile = Split-Path $Path -Leaf
            Write-Output "Copying image files and recovery files to the Recovery Partition..."
            Start-Process -FilePath "robocopy.exe" -ArgumentList "${ImgRoot} $($RecoveryPartition.DriveLetter):\ ${ImgFile} /MT:16 /R:2 /W:1" -NoNewWindow -Wait

            # REPLACE MAVERIK FOLDER WITH STAGE FOLDER IN WINPE DRIVE
            if ((Test-Path -Path "X:\Stage\boot.sdi") -and (Test-Path -Path "X:\Stage\local_recovery_boot.wim")) {
                Start-Process -FilePath "robocopy.exe" -ArgumentList "X:\Stage $($RecoveryPartition.DriveLetter):\ boot.sdi /MT:16 /R:2 /W:1" -NoNewWindow -Wait
                Start-Process -FilePath "robocopy.exe" -ArgumentList "X:\Stage $($RecoveryPartition.DriveLetter):\ local_recovery_boot.wim /MT:16 /R:2 /W:1" -NoNewWindow -Wait
            }

            # 7. Apply Windows Image to Windows Partition
            Write-Output "Applying Windows Image to Windows Partition..."
            Expand-WindowsImage -ImagePath "$($RecoveryPartition.DriveLetter):\${ImgFile}" -ApplyPath "$($WindowsPartition.DriveLetter):\" -Index $Index

            # 8. Create Boot Configuration Data (BCD) store
            Write-Output "Creating Boot Configuration Data (BCD) store..."
            Start-Process -FilePath "$($WindowsPartition.DriveLetter):\Windows\System32\bcdboot.exe" -ArgumentList "$($WindowsPartition.DriveLetter):\Windows /s $($SystemPartition.DriveLetter): /f ALL" -NoNewWindow -Wait

            # 9. Remove Recovery Drive Letter
            Write-Output "Finalizing..."
            Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $RecoveryPartition.PartitionNumber -AccessPath "$($RecoveryPartition.DriveLetter):\"

            Write-Output "Imaging process completed."
        }

        # Create PowerShell runspace to apply image
        $install_Object = [powershell]::Create()
        $install_Object.AddScript($ScriptBlock)
        $install_Object.AddParameter('DiskNumber', $DiskIndex)
        $install_Object.AddParameter('Path', $ImagePath)
        $install_Object.AddParameter('Index', $ImageIndex)

        # Create shared input and output collections
        $SharedInput = New-Object System.Management.Automation.PSDataCollection[PSObject]
        $SharedOutput = New-Object System.Management.Automation.PSDataCollection[PSObject]

        # Begin the asynchronous job
        $install_Job = $install_Object.BeginInvoke($SharedInput, $SharedOutput)

        # Monitor the job progress
        while (-not $install_Job.IsCompleted) {
            [System.Windows.Forms.Application]::DoEvents()
            $Time = New-TimeSpan -Minutes $TIMER.Elapsed.Minutes -Seconds $TIMER.Elapsed.Seconds
            $APPLY_LBL_Progress.Text = "Elapsed time: $Time"
            $APPLY_LBL_Progress.Refresh()

            # Check for new output messages
            if ($SharedOutput.Count -gt 0) {
                # ReadAll() grabs the items and clears them from the collection
                $newMessages = $SharedOutput.ReadAll()
            
                # Append new messages to the RichTextBox
                $newMessages | ForEach-Object {
                    $APPLY_RTB_Status.AppendText("$_`r`n")
                    "$log_format $_" | Out-File $log_file -Append
                }

                # Scroll logic
                $APPLY_RTB_Status.SelectionStart = $APPLY_RTB_Status.Text.Length
                $APPLY_RTB_Status.ScrollToCaret()
                $APPLY_RTB_Status.Refresh()
            }
            Start-Sleep -Milliseconds 100
        }

        # Finalize
        $APPLY_LBL_Status.Text = "Success! Click `"Restart`" to restart the computer."
        $APPLY_LBL_Progress.Text = "Total elapsed time: $($Time)"
        $Timer.Stop()
        $APPLY_RTB_Status.Visible = $false

        # Ensure all remaining output is processed
        $install_Object.EndInvoke($install_Job)
        $install_Object.Dispose()
    
        # Enable the Restart button
        $APPLY_BTN_Restart.Text = "Restart"
        $APPLY_BTN_Restart.Enabled = $true
    })

# Cancel Button
$START_BTN_Cancel.Add_Click({
        # Hide the start panel, Show cancel panel
        $START_Panel.Visible = $false
        $SHUTDOWN_Panel.Visible = $true
    })

# Apply Panel Logic
# Restart Button
$APPLY_BTN_Restart.Add_Click({
        # Hide the apply panel
        $APPLY_Panel.Visible = $false
        # Close the Form
        $FORM_Main.Close()
        # Add success message to log file
        "$log_format The imaging process completed successfully." | Out-File $log_file -Append
        # Restart the computer
        Restart-Computer -Force
    })

# Shutdown Panel Logic
# Shutdown Button
$SHUTDOWN_BTN_Shutdown.Add_Click({
        # Hide the shutdown panel
        $SHUTDOWN_Panel.Visible = $false
        # Close the Form
        $FORM_Main.Close()
        # Add shutdown message to log file
        "$log_format The computer was shutdown." | Out-File $log_file -Append
        # Shutdown the computer
        Stop-Computer -Force
    })
#endregion

#region Start
# Find the image file

if ($imageFilePath = Get-ChildItem -Path "${drive_letter}:\Stage\*.wim" -File) {
    # Find all available images
    $AvailableImages = (Get-Item $imageFilePath) | ForEach-Object { Get-WindowsImage -ImagePath $_ }
    $AvailableImages | ForEach-Object { $START_CB_Images.Items.Add($_.ImageName) }
    if ($AvailableImages.Count -eq 1) {
        $START_CB_Images.SelectedItem = $AvailableImages.ImageName
    }
    else {
        $START_CB_Images.SelectedItem = $AvailableImages.ImageName[0]
    }
    $START_CB_Images.Add_SelectedIndexChanged({ $START_CB_Images.SelectedItem })    
    # Find the primary disk on the device
    $AvailableDisks = Get-Disk | Where-Object { $_.BusType -ne 'USB' }
    $SelectedDisk = $AvailableDisks | Sort-Object Size -Descending | Select-Object -First 1
    $START_TB_Disks.Text = $SelectedDisk.FriendlyName
    # Show the start panel
    $START_Panel.Visible = $true
    # Start the form
    $FORM_Main.ShowDialog()
}
else {
    # Set the error message
    $error_message = "No images can be found in the .\Stage\ folder."
    # Add error to log file
    "$log_format $error_message `nFull Error: $($_.Exception.Message)" | Out-File $log_file -Append
    # Display error message box
    [System.Windows.Forms.MessageBox]::Show("$error_message", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    # Show the shutdown panel
    $SHUTDOWN_Panel.Visible = $true
    # Start the form
    $FORM_Main.ShowDialog()
}
#endregion