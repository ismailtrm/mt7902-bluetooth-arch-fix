# How It Works - Technical Deep Dive

This document provides a detailed technical explanation of the MT7902 Bluetooth fix for Arch Linux.

## Table of Contents

1. [MT7902 Hardware Overview](#mt7902-hardware-overview)
2. [The Problem](#the-problem)
3. [The Three Components](#the-three-components)
4. [Firmware Extraction](#firmware-extraction)
5. [Kernel Module Compilation](#kernel-module-compilation)
6. [Pacman Hook System](#pacman-hook-system)
7. [The Rebuild Script Flow](#the-rebuild-script-flow)

## MT7902 Hardware Overview

The **MediaTek MT7902** is a modern wireless chipset that provides both Wi-Fi and Bluetooth connectivity. It's commonly found in laptops manufactured in 2023-2024.

**Key specifications:**
- Manufacturer: MediaTek (Vendor ID: 0x0046)
- Bluetooth version: 5.3
- USB interface: Uses `btusb` driver
- Chipset-specific driver: Requires `btmtk` (MediaTek Bluetooth) module

**Linux Kernel Support Status:**
- The mainline Linux kernel includes basic `btmtk` and `btusb` drivers
- However, MT7902 support requires patches not yet in mainline (as of kernel 6.18)
- The stock drivers don't properly load firmware or initialize the MT7902 hardware
- Specific header file (`net/bluetooth/hci_drv.h`) requirements changed between kernel versions

## The Problem

When using Arch Linux with MT7902 Bluetooth, users face two main challenges:

### 1. Missing/Incomplete Firmware

The MT7902 requires specific firmware files to initialize the Bluetooth hardware:
- `BT_RAM_CODE_MT7902_1_1_hdr.bin` - Main Bluetooth firmware
- `mtkbt0.dat` - Configuration/calibration data

These files are **not included** in the `linux-firmware` package as of early 2024.

### 2. Kernel Module Compatibility

The upstream kernel's `btmtk` and `btusb` drivers don't fully support MT7902:
- Missing device ID entries
- Incompatible firmware loading routines
- Hardware initialization sequences not implemented

**What happens during kernel updates:**

```
Before update:               After update:
/lib/modules/6.18.4/         /lib/modules/6.18.5/
└── updates/                 └── [empty - no modules!]
    ├── btmtk.ko
    └── btusb.ko

Result: Bluetooth stops working!
```

The custom modules stay in the old kernel directory and aren't available for the new kernel.

## The Three Components

Our solution consists of three integrated components:

```
┌─────────────────────────────────────────────────────────────┐
│                     Pacman Hook                              │
│  Triggers on: linux, linux-headers, linux-firmware updates  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
        ┌────────────────────────────────┐
        │     Rebuild Script              │
        │  1. Detect new kernel           │
        │  2. Compile modules             │
        │  3. Install modules             │
        │  4. Restore firmware            │
        └───┬────────────────┬────────────┘
            │                │
            ▼                ▼
    ┌───────────────┐  ┌──────────────┐
    │ Source Code   │  │  Firmware    │
    │ mt7902_temp   │  │  Backup      │
    └───────────────┘  └──────────────┘
```

### Component 1: Firmware Files

**Location:** `/lib/firmware/mediatek/`
- `BT_RAM_CODE_MT7902_1_1_hdr.bin` (510,594 bytes)
- `mtkbt0.dat` (1,504 bytes)

**Backup location:** `/opt/bluetooth-firmware-backup/`

**Purpose:**
- Loaded by the kernel during Bluetooth initialization
- Contains hardware-specific code and calibration data
- Must match the exact version expected by the kernel module

**MD5 Checksums (for validation):**
- `BT_RAM_CODE_MT7902_1_1_hdr.bin`: `900a342bf03d5b844947aebe854af55d`
- `mtkbt0.dat`: `bf4087994e011245aec5c76e7d938e07`

### Component 2: Kernel Modules

**Files:**
- `btmtk.ko` - MediaTek-specific Bluetooth driver (925 KB compiled)
- `btusb.ko` - USB Bluetooth driver with MT7902 support (1.3 MB compiled)

**Installation location:** `/lib/modules/$KERNEL_VERSION/updates/`

The `updates/` directory takes precedence over the stock modules in `kernel/drivers/bluetooth/`, allowing our patched versions to be used.

**Source:** [mt7902_temp repository](https://github.com/OnlineLearningTutorials/mt7902_temp)
- Contains patched source code for kernels 6.14-6.18
- Based on upstream kernel code with MT7902-specific modifications

### Component 3: Automation

**Pacman Hook:** `/etc/pacman.d/hooks/bluetooth-firmware.hook`
- Monitors package operations
- Triggers on kernel-related package updates
- Executes rebuild script automatically

**Rebuild Script:** `/opt/bluetooth-firmware-backup/rebuild-bt-modules.sh`
- Detects new kernel versions
- Compiles modules against new kernel headers
- Installs modules to correct location
- Restores firmware files
- Logs all operations

## Firmware Extraction

Firmware files must be extracted from Windows drivers (legal for personal use on the same hardware).

### Step-by-Step Extraction

1. **Locate Windows partition:**
   ```bash
   lsblk -f | grep ntfs
   ```

2. **Mount Windows (read-only):**
   ```bash
   sudo mount -t ntfs3 -o ro /dev/nvme0n1p3 /mnt/windows
   ```

3. **Find firmware files:**
   ```
   Windows location:
   C:\Windows\System32\drivers\

   Linux mounted path:
   /mnt/windows/Windows/System32/drivers/
   ```

4. **Copy files:**
   ```bash
   cp /mnt/windows/Windows/System32/drivers/BT_RAM_CODE_MT7902_1_1_hdr.bin ./
   cp /mnt/windows/Windows/System32/drivers/mtkbt0.dat ./
   ```

5. **Verify checksums:**
   ```bash
   md5sum BT_RAM_CODE_MT7902_1_1_hdr.bin
   # Should be: 900a342bf03d5b844947aebe854af55d
   ```

### Why These Specific Files?

Windows drivers are in the **DriverStore** and active drivers directory:
- `C:\Windows\System32\drivers\` - Active drivers
- `C:\Windows\System32\DriverStore\FileRepository\mtkbtfilter.inf_*\` - Driver packages

Multiple versions may exist in DriverStore. We use the one from `System32/drivers/` as it's the actively-used version.

## Kernel Module Compilation

### Prerequisites

```bash
sudo pacman -S linux-headers base-devel
```

- `linux-headers` - Kernel headers for the target kernel version
- `base-devel` - Build tools (gcc, make, etc.)

### Build Process

The build uses the kernel's module build system (kbuild):

```bash
# Location: ~/mt7902_temp/linux-6.18/drivers/bluetooth/

# Makefile specifies:
obj-m += btusb.o
obj-m += btmtk.o

# Build command:
make -C /lib/modules/$(uname -r)/build M=$(pwd) modules
```

**What happens:**
1. Kernel build system is invoked with `-C /lib/modules/$KVER/build`
2. `M=$(pwd)` specifies the module source directory
3. `modules` target compiles all `obj-m` entries
4. Output: `btmtk.ko` and `btusb.ko` in the source directory

### Module Installation

```bash
# Copy to updates directory (takes precedence over stock modules)
cp btmtk.ko /lib/modules/6.18.5-arch1-1/updates/
cp btusb.ko /lib/modules/6.18.5-arch1-1/updates/

# Update module dependencies
depmod 6.18.5-arch1-1
```

The `depmod` command generates `/lib/modules/$KVER/modules.dep` and related files, which the kernel uses to resolve module dependencies.

## Pacman Hook System

Pacman hooks allow automatic actions during package operations.

### Hook Execution Flow

```
1. User runs: pacman -Syu
   ↓
2. Pacman downloads updates
   ↓
3. Pacman installs packages
   (linux 6.18.5 installed)
   ↓
4. PostTransaction hooks triggered
   ↓
5. bluetooth-firmware.hook matches
   (Target: linux detected)
   ↓
6. Execute: rebuild-bt-modules.sh
   ↓
7. Script rebuilds modules for 6.18.5
   ↓
8. Pacman operation complete
   ↓
9. User reboots to new kernel
   ↓
10. Bluetooth works!
```

### Hook File Structure

```ini
[Trigger]
Operation = Install | Upgrade
Type = Package
Target = linux
Target = linux-headers
Target = linux-firmware

[Action]
Description = Rebuilding modules...
When = PostTransaction
Exec = /path/to/script.sh
```

**Key points:**
- `PostTransaction` ensures new kernel headers are installed before building
- Multiple `Target` entries create OR logic (any one triggers the hook)
- Hook runs with root privileges

### Hook Location

Pacman searches for hooks in:
1. `/usr/share/libalpm/hooks/` - Package-provided hooks
2. `/etc/pacman.d/hooks/` - **User/admin hooks** (our location)

User hooks in `/etc/pacman.d/hooks/` persist across package updates.

## The Rebuild Script Flow

Detailed flowchart of `rebuild-bt-modules.sh`:

```
START
  ↓
┌─────────────────────────────┐
│ Validate Environment        │
│ - Check source directory    │
│ - Check firmware backup     │
│ - Check kernel headers      │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│ Scan /lib/modules/*/build   │
│ Find all installed kernels  │
└──────────┬──────────────────┘
           │
           ▼
      ┌─────────┐
      │ For each│
      │ kernel  │
      └────┬────┘
           │
           ▼
┌─────────────────────────────┐
│ Check if modules exist      │
│ in updates/ directory       │
└──────────┬──────────────────┘
           │
      ┌────┴────┐
      │         │
     Yes       No
      │         │
      │         ▼
      │    ┌─────────────────┐
      │    │ Clean old build │
      │    └────────┬────────┘
      │             │
      │             ▼
      │    ┌─────────────────┐
      │    │ make modules    │
      │    └────────┬────────┘
      │             │
      │        ┌────┴────┐
      │        │         │
      │     Success   Failure
      │        │         │
      │        ▼         ▼
      │    ┌─────┐  ┌──────┐
      │    │Copy │  │ Log  │
      │    │.ko  │  │error │
      │    └──┬──┘  └──────┘
      │       │
      │       ▼
      │    ┌─────────┐
      │    │ depmod  │
      │    └─────────┘
      │
      ▼
┌─────────────────────────────┐
│ Restore Firmware Files      │
│ - BT_RAM_CODE*.bin          │
│ - mtkbt0.dat                │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│ Log Summary                 │
│ - Kernels built             │
│ - Kernels skipped           │
└──────────┬──────────────────┘
           │
           ▼
          END
```

### Error Handling

The script uses several strategies for robustness:

1. **Validation before action:** Check all prerequisites before starting
2. **Per-kernel error isolation:** If build fails for one kernel, continue with others
3. **Detailed logging:** All operations logged to `/var/log/bt-module-rebuild.log`
4. **Non-blocking failures:** Script exits with 0 even if some kernels fail (allows pacman to complete)

### Environment Variables

The script supports customization via environment variables:

```bash
MT7902_SOURCE_DIR="~/custom/path" \
MT7902_BACKUP_DIR="/custom/backup" \
MT7902_LOG_FILE="/custom/log.log" \
rebuild-bt-modules.sh
```

Defaults:
- `MT7902_SOURCE_DIR`: `$HOME/mt7902_temp/linux-6.18/drivers/bluetooth`
- `MT7902_BACKUP_DIR`: `/opt/bluetooth-firmware-backup`
- `MT7902_LOG_FILE`: `/var/log/bt-module-rebuild.log`

## Complete System Interaction Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                         User Action                          │
│                      sudo pacman -Syu                        │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │    Pacman    │
                  └──────┬───────┘
                         │
         ┌───────────────┴───────────────┐
         │                               │
         ▼                               ▼
  ┌─────────────┐              ┌─────────────────┐
  │ Install     │              │ PostTransaction │
  │ linux 6.19  │              │ Hooks           │
  └─────┬───────┘              └────────┬────────┘
        │                               │
        │                               ▼
        │                      ┌──────────────────┐
        │                      │ bluetooth-       │
        │                      │ firmware.hook    │
        │                      └────────┬─────────┘
        │                               │
        │                               ▼
        │                      ┌──────────────────┐
        │                      │ rebuild-bt-      │
        │                      │ modules.sh       │
        │                      └────────┬─────────┘
        │                               │
        │              ┌────────────────┼────────────────┐
        │              │                │                │
        │              ▼                ▼                ▼
        │      ┌─────────────┐  ┌────────────┐  ┌────────────┐
        │      │ Compile     │  │ Install    │  │ Restore    │
        │      │ modules     │  │ to updates/│  │ firmware   │
        │      └─────────────┘  └────────────┘  └────────────┘
        │              │                │                │
        └──────────────┴────────────────┴────────────────┘
                                │
                                ▼
                         ┌──────────────┐
                         │   depmod     │
                         └──────┬───────┘
                                │
                                ▼
                         ┌──────────────┐
                         │ Pacman Done  │
                         └──────┬───────┘
                                │
                                ▼
                         ┌──────────────┐
                         │ User Reboots │
                         └──────┬───────┘
                                │
                                ▼
                    ┌──────────────────────┐
                    │ Kernel 6.19 Loads    │
                    │ - Finds btmtk.ko in  │
                    │   updates/           │
                    │ - Loads firmware     │
                    │ - Bluetooth works!   │
                    └──────────────────────┘
```

## Debugging

### Check if modules are being used

```bash
# List loaded bluetooth modules
lsmod | grep bt

# Check which btusb is loaded
modinfo btusb | grep filename
# Should show: /lib/modules/$(uname -r)/updates/btusb.ko
```

### Verify module loading

```bash
# Kernel messages during boot
dmesg | grep -i bluetooth

# Look for:
# - "Bluetooth: HCI socket layer initialized"
# - "Bluetooth: hci0: HW/SW Version: ..."
# - "Bluetooth: hci0: Device setup in XXXX usecs"
```

### Check firmware loading

```bash
# Firmware requests in kernel log
dmesg | grep -i firmware | grep -i mt7902

# Should see successful firmware loading:
# bluetooth hci0: Direct firmware load for mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin succeeded
```

### Rebuild script diagnostics

```bash
# View full rebuild log
cat /var/log/bt-module-rebuild.log

# Run rebuild script manually (with verbose output)
sudo /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh

# Check rebuild script configuration
grep -E "^(SOURCE_DIR|BACKUP_DIR|LOG_FILE)" /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh
```
