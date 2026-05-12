# WinPE PowerShell Imager Guide

## Overview
The `WinPE_PS_Imager.ps1` script is a utility designed to provide a graphical user interface (GUI) within the Windows Preinstallation Environment (WinPE). It simplifies the process of wiping a system's primary drive, partitioning it according to modern UEFI/GPT standards, and applying a selected Windows image (`.wim`).

### Prerequisites
- Must be executed in WinPE with **Administrator privileges**.
- Expects a `\Stage` directory on the WinPE boot drive containing the `.wim` files (e.g., `X:\Stage\install.wim`).

---

## Architecture & Flow

The script is built entirely in PowerShell using `System.Windows.Forms` to generate the GUI. It uses a single-form, multi-panel design to guide the user through the imaging process without needing multiple windows.

1. **Initialization:** The script locates the WinPE boot drive, sets up a log file (`ImagingLog.txt`), and initializes the main form (`$FORM_Main`).
2. **Panel Swapping:** Instead of opening new windows, the script toggles the visibility of different "Panels" (`$START_Panel`, `$APPLY_Panel`, `$SHUTDOWN_Panel`). 
3. **Detection:** Before showing the UI, it scans for available `.wim` files and the primary physical disk (excluding USB drives).
4. **Execution:** Once the user clicks "Next", the imaging process begins in the background, updating the UI with status messages and a timer.

---

## Deep Dive: Key Concepts

### 1. Asynchronous Execution (PowerShell Runspaces)
One of the most critical design choices in this script is the use of a **PowerShell Runspace** (`[powershell]::Create()`). 

If the imaging commands (which take 10+ minutes) were run directly inside the "Next" button's click event, the GUI would completely freeze, and Windows would likely report the application as "Not Responding." 

By placing the "Nuke and Pave" script block into a separate runspace, the heavy lifting is offloaded to a background thread. A loop in the main thread then periodically checks `$SharedOutput` to stream log messages back to the RichTextBox (`$APPLY_RTB_Status`) while keeping the UI responsive.

```powershell
# Create PowerShell runspace to apply image asynchronously
$install_Object = [powershell]::Create()
$install_Object.AddScript($ScriptBlock)

# Create shared collections to capture output back to the GUI
$SharedInput = New-Object System.Management.Automation.PSDataCollection[PSObject]
$SharedOutput = New-Object System.Management.Automation.PSDataCollection[PSObject]

$install_Job = $install_Object.BeginInvoke($SharedInput, $SharedOutput)
```

### 2. The "Nuke and Pave" Partition Layout
When formatting the disk, the script adheres strictly to UEFI/GPT requirements. It creates four specific partitions:

* **System (EFI):** 260MB (FAT32) - Holds the bootloader files.
* **MSR:** 16MB - Microsoft Reserved partition.
* **Windows:** Remaining space minus 20GB (NTFS) - Where the OS is applied.
* **Recovery:** 20GB (NTFS) - Houses the Windows RE environment.

```powershell
# Example: Creating the EFI Partition
$SystemPartition = New-Partition -DiskNumber $DiskNumber -Size $System.Size -GptType $System.GptType
$SystemPartition | Get-Partition | Set-Partition -NewDriveLetter $System.Letter
$SystemPartition | Format-Volume -FileSystem FAT32 -NewFileSystemLabel $System.Label -Confirm:$false -Force
```

### 3. Applying the Image
Instead of relying on `dism.exe` executables and parsing string output, the script utilizes native PowerShell cmdlets (`Expand-WindowsImage`) to apply the selected `.wim` index to the newly created Windows partition. Finally, `bcdboot.exe` is called to write the boot configuration data, making the system bootable.

---

## Troubleshooting & Logs
All actions and errors are logged to `\Stage\ImagingLog.txt` on the WinPE boot drive. If the script fails to start, check this log for errors related to missing `.wim` files or undetected drives.
