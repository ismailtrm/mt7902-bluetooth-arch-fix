# The Journey: Solving MT7902 Bluetooth on Arch Linux

This document chronicles the debugging journey, failed attempts, and eventual solution for getting MediaTek MT7902 Bluetooth working reliably on Arch Linux.

## Table of Contents

- [The Initial Problem](#the-initial-problem)
- [First Attempts](#first-attempts)
- [The Breakthrough](#the-breakthrough)
- [The Kernel Update Disaster](#the-kernel-update-disaster)
- [Building the Automation](#building-the-automation)
- [Why This Approach](#why-this-approach)
- [Lessons Learned](#lessons-learned)

---

## The Initial Problem

**The Setup:**
- Fresh Arch Linux installation on a laptop with MediaTek MT7902 chipset
- Bluetooth worked perfectly on Windows
- On Linux: completely dead

**Initial symptoms:**
```bash
$ bluetoothctl show
No default controller available
```

**Kernel messages:**
```bash
$ dmesg | grep -i bluetooth
bluetooth hci0: Direct firmware load for mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin failed with error -2
bluetooth hci0: Failed to load firmware mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin
```

The kernel couldn't find the firmware file. MT7902 was too new - not in `linux-firmware` package.

---

## First Attempts

### Attempt 1: Standard Troubleshooting

**What we tried:**
```bash
# Check if bluetooth service is running
systemctl status bluetooth

# Try loading modules manually
modprobe btusb
modprobe bluetooth

# Check for hardware
lsusb | grep -i bluetooth
lspci | grep -i bluetooth
```

**Result:** Hardware detected, service running, but no firmware = no functionality.

### Attempt 2: Search Arch Wiki and Forums

- Checked [Arch Wiki - Bluetooth](https://wiki.archlinux.org/title/Bluetooth)
- Searched forums for "MT7902"
- Found some mentions but no clear solution
- Most suggestions: "Install linux-firmware-git from AUR"

**Tried:**
```bash
paru -S linux-firmware-git
```

**Result:** Still no MT7902 firmware. This chipset is too recent.

### Attempt 3: Check linux-firmware Repository

Looked at the [official linux-firmware git](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/):

```bash
# Clone and search
git clone git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
cd linux-firmware
find . -name "*7902*"
# No results
```

**Discovery:** MT7921 and MT7922 firmware existed, but not MT7902. Our chipset is newer and not yet mainlined.

---

## The Breakthrough

### Finding the Solution

While searching GitHub, found: [mt7902_temp repository](https://github.com/OnlineLearningTutorials/mt7902_temp)

**What it contained:**
- Patched `btusb.c` and `btmtk.c` kernel drivers
- Support for kernel versions 6.14 through 6.18
- Instructions for extracting firmware from Windows
- WiFi driver development (in progress)

### Getting the Firmware

**Dual-boot advantage:** Had Windows installed, so firmware was available.

**Extraction process:**
```bash
# Mount Windows partition
sudo mount -t ntfs3 -o ro /dev/nvme0n1p3 /mnt/windows

# Find the firmware
ls /mnt/windows/Windows/System32/drivers/BT*
# Found: BT_RAM_CODE_MT7902_1_1_hdr.bin, mtkbt0.dat

# Copy to Linux firmware directory
sudo cp /mnt/windows/Windows/System32/drivers/BT_RAM_CODE_MT7902_1_1_hdr.bin /lib/firmware/mediatek/
sudo cp /mnt/windows/Windows/System32/drivers/mtkbt0.dat /lib/firmware/mediatek/

# Verify with checksums (important!)
md5sum /lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin
# 900a342bf03d5b844947aebe854af55d

sudo umount /mnt/windows
```

### Compiling the Kernel Modules

```bash
# Clone the driver source
git clone https://github.com/OnlineLearningTutorials/mt7902_temp
cd mt7902_temp/linux-6.18/drivers/bluetooth

# Build modules
make -C /lib/modules/$(uname -r)/build M=$(pwd) modules

# Install to updates directory (takes precedence over stock modules)
sudo mkdir -p /lib/modules/$(uname -r)/updates
sudo cp btmtk.ko btusb.ko /lib/modules/$(uname -r)/updates/

# Update module dependencies
sudo depmod -a
```

**Result:** 🎉 **Bluetooth worked!**

```bash
$ bluetoothctl show
Controller CC:47:40:24:D3:7D (public)
	Manufacturer: 0x0046 (70)
	Name: archlinux
	Powered: yes
```

Success... or so we thought.

---

## The Kernel Update Disaster

### The Problem Resurfaces

A few days later, ran `pacman -Syu`:

```
Packages to upgrade:
  linux 6.18.4.arch1-1 -> 6.18.5.arch1-1
```

After update and reboot:

```bash
$ bluetoothctl show
No default controller available
```

**Bluetooth was dead again.** 😱

### Understanding What Happened

**The root cause:**

```
Before update:                After update:
/lib/modules/6.18.4-arch1-1/  /lib/modules/6.18.5-arch1-1/
└── updates/                  └── [empty!]
    ├── btmtk.ko
    └── btusb.ko
```

The custom modules stayed in the **old kernel directory**. The new kernel had no custom modules.

**Why this happens:**
- Pacman installs new kernel to new directory
- Old kernel directory remains (for rollback)
- Custom modules in old directory aren't copied over
- New kernel uses stock modules (which don't support MT7902)

### Quick Fix (Manual Rebuild)

```bash
cd ~/mt7902_temp/linux-6.18/drivers/bluetooth
make clean
make -C /lib/modules/$(uname -r)/build M=$(pwd) modules
sudo cp btmtk.ko btusb.ko /lib/modules/$(uname -r)/updates/
sudo depmod -a
reboot
```

Bluetooth worked again. But this wasn't sustainable - manual rebuilds after every kernel update?

---

## Building the Automation

### Requirements for a Real Solution

1. **Detect kernel updates** automatically
2. **Rebuild modules** for new kernel
3. **Restore firmware** (in case linux-firmware package overwrites it)
4. **No manual intervention** required
5. **Persist across reboots**

### Considered Approaches

#### Option 1: DKMS (Dynamic Kernel Module Support)

**Pros:**
- Standard solution for out-of-tree modules
- Automatic rebuilding on kernel updates
- Used by nvidia-dkms, virtualbox-dkms, etc.

**Cons:**
- Complex setup (dkms.conf, module source packaging)
- Another system to maintain
- Overkill for two simple kernel modules

**Decision:** Too complex for our needs.

#### Option 2: Custom Kernel with Patches

**Pros:**
- Most "proper" solution
- Full control over kernel

**Cons:**
- Must rebuild entire kernel on updates (30+ minutes)
- High maintenance burden
- Lose benefits of official Arch kernel packages

**Decision:** Too much maintenance overhead.

#### Option 3: Pacman Hooks

**Pros:**
- Native to Arch Linux
- Simple, clean integration
- Runs automatically during updates
- Minimal code needed

**Cons:**
- Arch-specific (not portable to other distros)

**Decision:** ✅ **Perfect for Arch users!**

### Implementing the Pacman Hook

**Created:** `/etc/pacman.d/hooks/bluetooth-firmware.hook`

```ini
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = linux
Target = linux-headers
Target = linux-firmware

[Action]
Description = Rebuilding MediaTek MT7902 Bluetooth modules...
When = PostTransaction
Exec = /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh
```

**Key decisions:**
- **PostTransaction timing:** Ensures new kernel headers are installed before building
- **Multiple targets:** Triggers on kernel, headers, or firmware updates
- **External script:** Keeps complex logic out of hook file

### The Rebuild Script

**Created:** `/opt/bluetooth-firmware-backup/rebuild-bt-modules.sh`

**Core logic:**
1. Loop through all installed kernel versions
2. Check if modules already exist (skip if yes)
3. Build modules against kernel headers
4. Install to `/lib/modules/$KVER/updates/`
5. Run `depmod` to update dependencies
6. Restore firmware from backup

**Key features:**
- Handles multiple kernel versions (useful if linux-lts is also installed)
- Validates source directory exists
- Logs everything to `/var/log/bt-module-rebuild.log`
- Non-blocking failures (one kernel fails, others continue)

### Firmware Backup

**Problem:** What if a future `linux-firmware` update includes MT7902 firmware?

It might overwrite our working Windows-extracted firmware with a potentially different version.

**Solution:** Keep backup and restore it:

```bash
# Backup location
/opt/bluetooth-firmware-backup/
├── BT_RAM_CODE_MT7902_1_1_hdr.bin
├── mtkbt0.dat
└── rebuild-bt-modules.sh

# Restore after updates
cp /opt/bluetooth-firmware-backup/*.bin /lib/firmware/mediatek/
cp /opt/bluetooth-firmware-backup/*.dat /lib/firmware/mediatek/
```

---

## Testing the Solution

### Test 1: Manual Trigger

```bash
sudo /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh
```

**Log output:**
```
2026-01-14 20:36:15 - === Starting Bluetooth module rebuild ===
2026-01-14 20:36:15 - Building modules for kernel 6.18.4-arch1-1
2026-01-14 20:36:30 - Build successful for 6.18.4-arch1-1
2026-01-14 20:36:31 - Modules installed for 6.18.4-arch1-1
2026-01-14 20:36:31 - Restoring firmware files
2026-01-14 20:36:31 - === Bluetooth module rebuild complete ===
```

**Verification:**
```bash
md5sum /lib/modules/6.18.4-arch1-1/updates/btmtk.ko
# Checksum matches original: 2e26dc7bb1245d643921ebc0ef28414f
```

✅ Script works, produces identical modules.

### Test 2: Kernel Update Simulation

Temporarily moved modules to test rebuild:

```bash
sudo mv /lib/modules/6.18.4-arch1-1/updates/btmtk.ko{,.backup}
sudo mv /lib/modules/6.18.4-arch1-1/updates/btusb.ko{,.backup}

sudo /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh
```

**Result:** Modules rebuilt successfully, identical checksums. ✅

### Test 3: Real Kernel Update

```bash
sudo pacman -Syu
```

**Pacman output:**
```
(10/13) Rebuilding MediaTek MT7902 Bluetooth modules and restoring firmware...
2026-01-14 20:48:27 - === Starting Bluetooth module rebuild ===
2026-01-14 20:48:27 - Building modules for kernel 6.18.5-arch1-1
2026-01-14 20:48:30 - Build successful for 6.18.5-arch1-1
2026-01-14 20:48:31 - Modules installed for 6.18.5-arch1-1
2026-01-14 20:48:31 - Restoring firmware files
2026-01-14 20:48:31 - === Bluetooth module rebuild complete ===
```

**After reboot:**
```bash
$ bluetoothctl show
Controller CC:47:40:24:D3:7D (public)
	Manufacturer: 0x0046 (70)
	Name: archlinux
	Powered: yes
```

✅ **Perfect!** Bluetooth works seamlessly after kernel update.

### Cleanup: Removing Linux-LTS

Initially had both `linux` and `linux-lts` installed. The rebuild script tried to build for LTS kernel (6.12.x) but failed:

```
ERROR: Build failed for 6.12.65-1-lts
fatal error: net/bluetooth/hci_drv.h: No such file or directory
```

**Reason:** mt7902_temp only supports kernels 6.14+. LTS was too old.

**Decision:** Remove LTS, use Timeshift snapshots for rollback instead:

```bash
sudo pacman -Rns linux-lts linux-lts-headers
```

Simplified the setup - only one kernel to maintain.

---

## Why This Approach?

### Advantages of Pacman Hooks

1. **Arch-native:** Uses built-in pacman functionality
2. **Zero maintenance:** Runs automatically, no user intervention
3. **Transparent:** User sees rebuild happening during update
4. **Reliable:** Runs after packages installed, before reboot
5. **Simple:** ~100 lines of shell script, one hook file

### Why Not DKMS?

DKMS would require:
- Creating `dkms.conf` file
- Packaging source properly
- Managing version numbers
- Installing dkms package

For two kernel modules, pacman hooks are simpler and more direct.

### Why Not Custom Kernel?

Custom kernel would require:
- Downloading kernel source (2+ GB)
- Applying patches manually
- Configuring kernel (500+ options)
- Compiling entire kernel (30-60 minutes)
- Updating GRUB configuration
- Repeating on every kernel update

Pacman hooks rebuild just the two needed modules in ~5 seconds.

### Trade-offs

**What we give up:**
- Portability (Arch-specific solution)
- If mt7902_temp repo disappears, solution breaks

**What we gain:**
- Simplicity (plug-and-play for Arch users)
- Maintainability (minimal code to maintain)
- Reliability (proven pacman hook system)

---

## Lessons Learned

### 1. Always Verify with Checksums

When dealing with firmware files:
- Different versions can have the same filename
- Wrong version = mysterious failures
- Checksums catch this immediately

```bash
md5sum firmware.bin  # Always verify!
```

### 2. The `/updates/` Directory Trick

Kernel modules in `/lib/modules/$KVER/updates/` take precedence over stock modules in `kernel/drivers/`. This allows:
- Replacing stock modules without modifying them
- Easy rollback (just delete from updates/)
- Clean separation of custom vs. stock

### 3. Pacman Hooks Are Powerful

Many Arch users don't know about pacman hooks. They're incredibly useful for:
- Running scripts after package updates
- Automating system maintenance
- Integrating custom solutions with package management

**Reading `/var/log/pacman.log` helped understand hook execution:**
```bash
grep -i bluetooth /var/log/pacman.log
```

### 4. Document the Journey

This entire solution took hours of debugging, failed attempts, and research. Documenting it:
- Helps others facing similar issues
- Provides learning material for Linux troubleshooting
- Makes the solution reproducible

### 5. Backup Everything That Works

Before trying fixes:
```bash
# Backup working modules
cp /lib/modules/$(uname -r)/updates/*.ko /safe/location/

# Backup working firmware
cp /lib/firmware/mediatek/*.bin /safe/location/
```

Made recovery much easier when experiments failed.

### 6. Test Incrementally

Breaking the solution into steps:
1. Get firmware working (test)
2. Build modules (test)
3. Create rebuild script (test)
4. Add pacman hook (test)

Each step validated before moving to the next. Easier to debug.

### 7. Logs Are Your Friend

The rebuild script logs everything. When things break:
```bash
tail -50 /var/log/bt-module-rebuild.log
```

Saved hours of debugging.

---

## Future Considerations

### When Mainline Support Arrives

Eventually, MT7902 support will likely be mainlined:
- Firmware added to `linux-firmware`
- Drivers updated in stock kernel

**What happens then:**
- Hook continues to run (harmless)
- Modules already exist → script skips rebuild
- Firmware backup → still restored (might be same file)

**Migration path:**
1. Test stock kernel support
2. If working, remove hook and backup
3. Uninstall custom source

### For Other MediaTek Chipsets

This approach works for:
- MT7921, MT7922 (if you need specific firmware versions)
- Future MT79xx chipsets
- Any hardware requiring custom firmware + modules

Just replace:
- Firmware file names
- Module names
- Source repository

### Contributing Upstream

The ultimate solution: get MT7902 support merged upstream.

**What that would require:**
- Submit patches to kernel mailing list
- Get firmware redistribution permission from MediaTek
- Add firmware to linux-firmware repository

That's a longer-term project, but would benefit the entire Linux community.

---

## Conclusion

This journey taught us:
- **Linux hardware support** requires patience and research
- **Automation** turns fragile hacks into reliable solutions
- **Understanding the problem** (kernel modules, firmware loading, pacman) leads to elegant solutions
- **Documenting the process** helps the community

The MT7902 Bluetooth fix evolved from:
- Manual rebuilds after every kernel update (fragile)
- To automated, zero-maintenance solution (reliable)

**Final validation:** Kernel updates from 6.18.4 → 6.18.5 → 6.18.6, Bluetooth works every time. ✅

If you're facing similar hardware compatibility issues on Arch Linux, this workflow applies:
1. Find the firmware/drivers (Windows, vendor site, GitHub)
2. Test manually first
3. Build automation (pacman hooks)
4. Document and share

---

**Questions or improvements?** Open an issue on [GitHub](https://github.com/ismailtrm/mt7902-bluetooth-arch-fix/issues).

**Found this helpful?** Star the repo and share with others facing MT7902 issues!
