# Windows PE Preparation Guide

This guide outlines the steps required to build a custom Windows Preinstallation Environment (WinPE) that includes PowerShell support, necessary drivers, and automatically launches the PowerShell Imaging Utility upon boot.

## Prerequisites & Downloads

Before beginning, you will need to install the Windows Assessment and Deployment Kit (ADK) and the corresponding Windows PE add-on.

1. **Download the Windows ADK**: [Download Windows ADK](https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install)
2. **Download the Windows PE Add-on**: Available on the same page as the ADK. Ensure the versions match your target OS build.

*Note: During the ADK installation, you only need to select the "Deployment Tools" feature for this process.*

---

## 1. Creating the WinPE Working Files

Open the **Deployment and Imaging Tools Environment** command prompt as an Administrator. This shortcut is created in your Start Menu when you install the ADK.

Run the following command to copy the base WinPE files to a working directory (e.g., `C:\WinPE_amd64`):

```cmd
copype amd64 C:\WinPE_amd64
```

---

## 2. Mounting the WinPE Image

To modify the WinPE environment, you must mount its base image (`boot.wim`). This extracts the contents so they can be modified.

```cmd
Dism /Mount-Image /ImageFile:"C:\WinPE_amd64\media\sources\boot.wim" /index:1 /MountDir:"C:\WinPE_amd64\mount"
```

---

## 3. Adding Drivers (Optional but Recommended)

By default, WinPE includes generic drivers. If you are deploying to modern hardware (like NVMe storage controllers or specific network adapters), you will need to inject drivers into the image so WinPE can see the local disks and network.

To add drivers (ensure you have the `.inf` and `.sys` files extracted):

```cmd
Dism /Add-Driver /Image:"C:\WinPE_amd64\mount" /Driver:"C:\Path\To\Your\Extracted\Drivers" /Recurse
```

---

## 4. Adding PowerShell Support and the Utility

To use the PowerShell Imaging Utility, we must inject the optional components (OCs) required to run PowerShell scripts in WinPE.

### Injecting PowerShell Optional Components
Run these commands in order to add WMI, .NET Framework, Scripting, and PowerShell support:

```cmd
Dism /Add-Package /Image:"C:\WinPE_amd64\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-WMI.cab"
Dism /Add-Package /Image:"C:\WinPE_amd64\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-NetFX.cab"
Dism /Add-Package /Image:"C:\WinPE_amd64\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-Scripting.cab"
Dism /Add-Package /Image:"C:\WinPE_amd64\mount" /PackagePath:"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\WinPE_OCs\WinPE-PowerShell.cab"
```
*(Paths may vary slightly depending on your ADK installation directory).*

### Copying the Imaging Script
Create a folder for the script within the mounted image and copy your script into it.

```cmd
mkdir C:\WinPE_amd64\mount\Scripts
copy "C:\Path\To\WinPE_PS_Imager.ps1" "C:\WinPE_amd64\mount\Scripts\"
```

---

## 5. Modifying startnet.cmd

When WinPE boots, it automatically runs `X:\Windows\System32\startnet.cmd`. By default, this file only contains `wpeinit` (which initializes Plug and Play devices and networking). We will modify it to launch our PowerShell GUI automatically.

Open `C:\WinPE_amd64\mount\Windows\System32\startnet.cmd` in a text editor (like Notepad) and append the command to run your script:

```cmd
wpeinit
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File X:\Scripts\WinPE_PS_Imager.ps1
```

---

## 6. Unmounting and Committing Changes

Once your modifications are complete, unmount the image and commit the changes to save them back to the `boot.wim` file.

```cmd
Dism /Unmount-Image /MountDir:"C:\WinPE_amd64\mount" /Commit
```

---

## 7. Creating Bootable Media

Now that your custom WinPE environment is ready, you need to apply it to a bootable medium. 

### Option A: Creating a Bootable USB Drive (Physical Hardware)
Using the Deployment and Imaging Tools Environment, run the `MakeWinPEMedia` command to format a USB drive (e.g., Drive `F:`) and apply the WinPE files:

```cmd
MakeWinPEMedia /UFD C:\WinPE_amd64 F:
```
**Warning:** *This will completely format the USB drive. Ensure you select the correct drive letter.*

### Option B: Creating a Bootable ISO (Virtual Machines)
If you are testing the script in Hyper-V, VirtualBox, or VMware, an ISO file is required. Create an ISO with the following command:

```cmd
MakeWinPEMedia /ISO C:\WinPE_amd64 C:\WinPE_amd64\WinPE_Custom.iso
```
You can then mount this ISO to your Virtual Machine's virtual DVD drive to boot into WinPE.

### Option C: Creating a Bootable USB via Rufus (For Large `.wim` Files)
When using the native `MakeWinPEMedia /UFD` command (Option A), the USB drive is typically formatted as FAT32, which has a strict maximum file size limit of 4GB. If your custom Windows `.wim` images are larger than 4GB, you will need to format the drive as NTFS.

1. First, generate an ISO file using the command from **Option B**.
2. Download and launch a utility like [Rufus](https://rufus.ie/).
3. Select your target USB drive from the "Device" dropdown.
4. Click the "SELECT" button and choose your newly created `WinPE_Custom.iso`.
5. Under "File system", ensure that **NTFS** is selected.
6. Click "START" to write the ISO to the USB drive.

---

## Next Steps
The `WinPE_PS_Imager.ps1` script looks for images inside a `\Stage` directory. Make sure you create a `Stage` folder on the root of your bootable USB drive (or a secondary drive/VHD if testing virtually) and place your `.wim` files inside so the script can detect them upon boot.
