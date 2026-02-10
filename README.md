# MT7902 Bluetooth Fix for Arch Linux

> **Automated solution for MediaTek MT7902 Bluetooth on Arch Linux**
> Survives kernel updates without manual intervention

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?logo=arch-linux&logoColor=fff)](https://archlinux.org/)

## The Problem

The MediaTek MT7902 Bluetooth adapter requires custom firmware and patched kernel modules that aren't included in the standard Linux kernel. When you run `pacman -Syu` and the kernel updates, your custom modules are left in the old kernel directory, causing Bluetooth to stop working.

**Common symptoms:**
- Bluetooth adapter not detected after kernel update
- `bluetoothctl` shows "No default controller available"
- `dmesg` shows firmware loading errors for MT7902

## The Solution

This repository provides an **automated pacman hook** that:
1. Detects kernel updates (`linux`, `linux-headers`, `linux-firmware`)
2. Automatically rebuilds custom kernel modules for the new kernel
3. Restores firmware files from backup
4. Ensures Bluetooth continues working after every system update

> 📖 **Interested in the journey?** Read [The Development Story](docs/DEVELOPMENT-STORY.md) to see how this solution was discovered through debugging, failed attempts, and eventual automation.

## Requirements

- **Arch Linux** or derivatives (Manjaro, EndeavourOS, etc.)
- **MediaTek MT7902 Bluetooth adapter**
- Packages: `linux`, `linux-headers`, `base-devel`, `git`
- **Firmware files** (extract from Windows dual-boot or existing installation)

## Quick Installation

### Option 1: Automated Installer (Recommended)

```bash
# Clone the repository
git clone https://github.com/ismailtrm/mt7902-bluetooth-arch-fix
cd mt7902-bluetooth-arch-fix

# Run the installer
sudo ./scripts/install.sh
```

The installer will:
- Check prerequisites
- Clone the MT7902 driver source
- Prompt you for firmware files (with extraction instructions)
- Set up the pacman hook
- Test the configuration

### Option 2: Manual Installation

<details>
<summary>Click to expand manual installation steps</summary>

#### Step 1: Install Prerequisites

```bash
sudo pacman -S linux-headers base-devel git
```

#### Step 2: Clone MT7902 Driver Source

```bash
cd ~
git clone https://github.com/OnlineLearningTutorials/mt7902_temp
```

#### Step 3: Extract Firmware from Windows

If you have Windows dual-boot:

```bash
# Mount Windows partition (adjust /dev/nvme0n1p3 to your partition)
sudo mkdir -p /mnt/windows
sudo mount -t ntfs3 -o ro /dev/nvme0n1p3 /mnt/windows

# Create backup directory
sudo mkdir -p /opt/bluetooth-firmware-backup

# Copy firmware files
sudo cp /mnt/windows/Windows/System32/drivers/BT_RAM_CODE_MT7902_1_1_hdr.bin /opt/bluetooth-firmware-backup/
sudo cp /mnt/windows/Windows/System32/drivers/mtkbt0.dat /opt/bluetooth-firmware-backup/

# Unmount Windows
sudo umount /mnt/windows
```

**Verify firmware checksums:**
```bash
md5sum /opt/bluetooth-firmware-backup/BT_RAM_CODE_MT7902_1_1_hdr.bin
# Should be: 900a342bf03d5b844947aebe854af55d

md5sum /opt/bluetooth-firmware-backup/mtkbt0.dat
# Should be: bf4087994e011245aec5c76e7d938e07
```

#### Step 4: Install Rebuild Script

```bash
cd ~/mt7902-bluetooth-arch-fix
sudo cp scripts/rebuild-bt-modules.sh /opt/bluetooth-firmware-backup/
sudo chmod +x /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh
```

#### Step 5: Install Pacman Hook

```bash
sudo cp hooks/bluetooth-firmware.hook /etc/pacman.d/hooks/
```

#### Step 6: Initial Build

```bash
sudo /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh
```

Check the log for success:
```bash
tail -20 /var/log/bt-module-rebuild.log
```

</details>

## How It Works

The solution consists of three components:

1. **Firmware Files** (`BT_RAM_CODE_MT7902_1_1_hdr.bin`, `mtkbt0.dat`)
   - Extracted from Windows drivers
   - Backed up to `/opt/bluetooth-firmware-backup/`
   - Restored after updates

2. **Kernel Modules** (`btmtk.ko`, `btusb.ko`)
   - Patched versions from [mt7902_temp](https://github.com/OnlineLearningTutorials/mt7902_temp)
   - Compiled against current kernel headers
   - Installed to `/lib/modules/$KERNEL_VERSION/updates/`

3. **Pacman Hook** (automatic trigger)
   - Runs after `linux`, `linux-headers`, or `linux-firmware` updates
   - Executes rebuild script
   - Logs to `/var/log/bt-module-rebuild.log`

See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) for technical deep-dive.

## Verification

### Test Bluetooth

```bash
bluetoothctl show
```

Expected output:
```
Controller XX:XX:XX:XX:XX:XX (public)
	Manufacturer: 0x0046 (70)
	Name: archlinux
	Powered: yes
```

### Test After Kernel Update

```bash
# Update system
sudo pacman -Syu

# Check the rebuild log
tail -20 /var/log/bt-module-rebuild.log

# Look for:
# - "Build successful for 6.x.x"
# - "Modules installed for 6.x.x"
# - "Bluetooth module rebuild complete"

# Reboot to new kernel
reboot

# Verify Bluetooth works
bluetoothctl show
```

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues and solutions.

**Quick diagnostics:**

```bash
# Check if modules are loaded
lsmod | grep bt

# Check kernel messages
dmesg | grep -i bluetooth | tail -20

# Check rebuild log
cat /var/log/bt-module-rebuild.log

# Verify firmware files exist
ls -l /lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin
ls -l /lib/firmware/mediatek/mtkbt0.dat
```

## Uninstallation

```bash
# Remove pacman hook
sudo rm /etc/pacman.d/hooks/bluetooth-firmware.hook

# Remove backup directory
sudo rm -rf /opt/bluetooth-firmware-backup

# Remove source (optional)
rm -rf ~/mt7902_temp
```

## Credits

- **Solution developed by:** [ismailtrm](https://github.com/ismailtrm)
- **MT7902 kernel drivers:** [OnlineLearningTutorials/mt7902_temp](https://github.com/OnlineLearningTutorials/mt7902_temp)
- **Firmware source:** MediaTek Windows drivers
- **Inspired by:** Community efforts to support MediaTek hardware on Linux

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

**Note:** The firmware files themselves are proprietary and copyrighted by MediaTek. This repository provides tools to use your own legally-obtained firmware from Windows installations.

## Contributing

Issues and pull requests are welcome! Please see the [issue tracker](https://github.com/ismailtrm/mt7902-bluetooth-arch-fix/issues).

## References

- [Arch Linux Pacman Hooks Documentation](https://man.archlinux.org/man/alpm-hooks.5)
- [Linux Kernel Bluetooth Subsystem](https://www.kernel.org/doc/html/latest/networking/bluetooth.html)
- [MT7902 Driver Source](https://github.com/OnlineLearningTutorials/mt7902_temp)
