# Troubleshooting Guide

This guide covers common issues and their solutions when using the MT7902 Bluetooth fix.

## Table of Contents

- [Build Issues](#build-issues)
- [Bluetooth Issues](#bluetooth-issues)
- [Hook Issues](#hook-issues)
- [Firmware Issues](#firmware-issues)
- [Kernel Compatibility](#kernel-compatibility)
- [General Diagnostics](#general-diagnostics)

---

## Build Issues

### Module compilation failed

**Symptoms:**
```
ERROR: Build failed for 6.x.x
```

**Diagnosis:**
```bash
cat /var/log/bt-module-rebuild.log
```

**Common causes and solutions:**

#### 1. Missing linux-headers

**Error in log:**
```
make: *** /lib/modules/6.x.x/build: No such file or directory
```

**Solution:**
```bash
sudo pacman -S linux-headers
```

**Verify:**
```bash
ls -ld /lib/modules/$(uname -r)/build
```

#### 2. Incomplete kernel headers installation

**Error in log:**
```
fatal error: linux/module.h: No such file or directory
```

**Solution:**
```bash
# Reinstall headers
sudo pacman -S --force linux-headers

# Or if using multiple kernels:
sudo pacman -S linux-lts-headers
```

#### 3. Source directory not found

**Error in log:**
```
ERROR: Source directory not found: /home/user/mt7902_temp/...
```

**Solution:**
```bash
# Clone the source repository
cd ~
git clone https://github.com/OnlineLearningTutorials/mt7902_temp

# Or update MT7902_SOURCE_DIR in rebuild script
sudo nano /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh
# Change: SOURCE_DIR="/path/to/your/mt7902_temp/linux-6.18/drivers/bluetooth"
```

#### 4. Build system errors (kernel API changes)

**Error in log:**
```
error: 'struct hci_dev' has no member named 'xyz'
```

**Solution:**

This usually means the kernel version is too new for the current patches. Check if newer patches are available:

```bash
cd ~/mt7902_temp
git pull origin main

# Check for newer kernel version directories
ls -ld linux-6.*

# If your kernel is 6.19 but only linux-6.18 exists,
# try using the latest available:
cd ~/mt7902_temp
ls -d linux-6.* | tail -1
# Update SOURCE_DIR in rebuild script to point to this
```

---

## Bluetooth Issues

### Bluetooth not detected after reboot

**Symptoms:**
```bash
$ bluetoothctl show
No default controller available
```

**Diagnosis:**
```bash
# Check if modules are loaded
lsmod | grep btusb
lsmod | grep btmtk

# Check kernel messages
dmesg | grep -i bluetooth | tail -20

# Check if modules exist
ls -l /lib/modules/$(uname -r)/updates/bt*.ko
```

**Solutions:**

#### 1. Modules not loaded

```bash
# Try loading manually
sudo modprobe btusb

# Check for errors
dmesg | grep -i bluetooth | tail -10
```

If manual loading works, the issue is with module auto-loading. Check:
```bash
# Ensure modules are in the correct location
ls -l /lib/modules/$(uname -r)/updates/

# Rebuild module dependencies
sudo depmod -a
```

#### 2. Wrong firmware version

**Error in dmesg:**
```
bluetooth hci0: Direct firmware load for mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin failed
```

**Solution:**
```bash
# Check firmware exists
ls -l /lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin

# If missing, restore from backup
sudo cp /opt/bluetooth-firmware-backup/BT_RAM_CODE_MT7902_1_1_hdr.bin /lib/firmware/mediatek/
sudo cp /opt/bluetooth-firmware-backup/mtkbt0.dat /lib/firmware/mediatek/

# Verify checksums
md5sum /lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin
# Should be: 900a342bf03d5b844947aebe854af55d
```

#### 3. Modules from wrong kernel version

```bash
# Check module version matches kernel
modinfo /lib/modules/$(uname -r)/updates/btusb.ko | grep vermagic

# Should match current kernel:
uname -r

# If mismatch, rebuild:
sudo /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh
```

### Bluetooth works initially but stops after suspend/resume

**Symptoms:**
- Bluetooth works after boot
- Stops working after suspend or hibernation

**Solution:**

This is usually a power management issue. Create a systemd service to reset Bluetooth after resume:

```bash
sudo nano /etc/systemd/system/bluetooth-resume.service
```

Add:
```ini
[Unit]
Description=Reset Bluetooth after suspend
After=suspend.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bluetoothctl power off
ExecStart=/bin/sleep 2
ExecStart=/usr/bin/bluetoothctl power on

[Install]
WantedBy=suspend.target
```

Enable:
```bash
sudo systemctl enable bluetooth-resume.service
```

### Bluetooth device not pairing

**Symptoms:**
- Bluetooth controller detected
- Devices found but won't pair

**Diagnosis:**
```bash
bluetoothctl
[bluetooth]# scan on
# Wait for devices to appear

[bluetooth]# pair XX:XX:XX:XX:XX:XX
# Check error messages
```

**Common issues:**

1. **Authentication timeout** - Move device closer, try again
2. **Device already paired elsewhere** - Remove pairing from other devices first
3. **Bluetooth service issues** - Restart service:
   ```bash
   sudo systemctl restart bluetooth
   ```

---

## Hook Issues

### Hook didn't trigger after kernel update

**Diagnosis:**
```bash
# Check hook file exists and has correct permissions
ls -l /etc/pacman.d/hooks/bluetooth-firmware.hook

# Check hook syntax
cat /etc/pacman.d/hooks/bluetooth-firmware.hook

# Check pacman log for hook execution
grep -i bluetooth /var/log/pacman.log | tail -5
```

**Solutions:**

#### 1. Hook file missing or wrong location

```bash
# Reinstall hook
sudo cp ~/mt7902-bluetooth-arch-fix/hooks/bluetooth-firmware.hook /etc/pacman.d/hooks/

# Verify
ls -l /etc/pacman.d/hooks/bluetooth-firmware.hook
```

#### 2. Hook file syntax error

```bash
# Validate hook syntax (alpm-hooks doesn't provide validation tool,
# but you can check for common issues)

# Must have both [Trigger] and [Action] sections
grep -E '^\[(Trigger|Action)\]' /etc/pacman.d/hooks/bluetooth-firmware.hook

# Check Exec path is correct
grep '^Exec' /etc/pacman.d/hooks/bluetooth-firmware.hook
# Should point to: /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh
```

#### 3. Script not executable

```bash
# Make script executable
sudo chmod +x /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh

# Verify
ls -l /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh
# Should show: -rwxr-xr-x
```

### Script errors during hook execution

**Check the log:**
```bash
tail -50 /var/log/bt-module-rebuild.log
```

**Common errors:**

#### Permission denied

```bash
# Hooks run as root, but if script has wrong ownership:
sudo chown root:root /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh
sudo chmod 755 /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh
```

#### Script path issues

```bash
# Verify script location
which rebuild-bt-modules.sh
# Or check absolute path:
ls -l /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh
```

---

## Firmware Issues

### Firmware loading failed

**Error in dmesg:**
```
bluetooth hci0: Direct firmware load for mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin failed with error -2
```

**Error -2 means:** File not found

**Diagnosis:**
```bash
# Check if firmware exists
ls -l /lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin
ls -l /lib/firmware/mediatek/mtkbt0.dat

# Check permissions
ls -la /lib/firmware/mediatek/
```

**Solution:**
```bash
# Restore firmware from backup
sudo cp /opt/bluetooth-firmware-backup/*.bin /lib/firmware/mediatek/
sudo cp /opt/bluetooth-firmware-backup/*.dat /lib/firmware/mediatek/

# Set correct permissions
sudo chmod 644 /lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin
sudo chmod 644 /lib/firmware/mediatek/mtkbt0.dat
```

### Wrong firmware version / checksum mismatch

**Symptoms:**
- Firmware loads but Bluetooth doesn't work
- Unusual errors in dmesg

**Diagnosis:**
```bash
# Verify firmware checksums
md5sum /lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin
# Expected: 900a342bf03d5b844947aebe854af55d

md5sum /lib/firmware/mediatek/mtkbt0.dat
# Expected: bf4087994e011245aec5c76e7d938e07
```

**If mismatch:**
```bash
# Extract fresh firmware from Windows
# See: docs/HOW-IT-WORKS.md#firmware-extraction

# Or if you have backup:
sudo cp /opt/bluetooth-firmware-backup/BT_RAM_CODE_MT7902_1_1_hdr.bin /lib/firmware/mediatek/
```

---

## Kernel Compatibility

### Build fails on kernel 6.x

**Error in log:**
```
fatal error: net/bluetooth/hci_drv.h: No such file or directory
```

**Explanation:**

The mt7902_temp repository has patches for specific kernel versions:
- `linux-6.14/`
- `linux-6.15/`
- `linux-6.16/`
- `linux-6.17/`
- `linux-6.18/`

Kernel APIs change between versions. If you're running kernel 6.19 or newer, the 6.18 patches may not work.

**Solutions:**

#### Option 1: Check for updated patches

```bash
cd ~/mt7902_temp
git pull origin main

# Check for new kernel version directories
ls -ld linux-6.*

# If linux-6.19 exists, update SOURCE_DIR in rebuild script
```

#### Option 2: Use LTS kernel

If you need stability, consider using linux-lts (if patches exist for that version):

```bash
# Check LTS kernel version
pacman -Si linux-lts | grep Version

# If LTS kernel is 6.17 or earlier, you can use it:
sudo pacman -S linux-lts linux-lts-headers

# Update grub to boot LTS by default
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

#### Option 3: Wait for patches

Check the [mt7902_temp issues](https://github.com/OnlineLearningTutorials/mt7902_temp/issues) to see if patches for your kernel version are in progress.

### LTS kernel support

**Current status:** Only kernels 6.14 and newer are supported.

If you're using `linux-lts` with kernel < 6.14:
- The mt7902_temp patches won't compile
- You'll see header file errors during build
- **Solution:** Switch to regular `linux` package (6.14+)

```bash
# Remove LTS kernel
sudo pacman -R linux-lts linux-lts-headers

# Ensure regular kernel is installed
sudo pacman -S linux linux-headers

# Update grub
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Reboot to new kernel
```

---

## General Diagnostics

### Complete diagnostic script

Save this as `diagnose-bt.sh` and run with `bash diagnose-bt.sh`:

```bash
#!/bin/bash

echo "=== MT7902 Bluetooth Diagnostics ==="
echo ""

echo "1. Kernel version:"
uname -r
echo ""

echo "2. Loaded bluetooth modules:"
lsmod | grep -E '(btusb|btmtk|bluetooth)'
echo ""

echo "3. Module files in updates/:"
ls -lh /lib/modules/$(uname -r)/updates/bt*.ko 2>/dev/null || echo "No modules found"
echo ""

echo "4. Firmware files:"
ls -lh /lib/firmware/mediatek/BT* /lib/firmware/mediatek/mtkbt* 2>/dev/null || echo "No firmware found"
echo ""

echo "5. Firmware checksums:"
md5sum /lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin 2>/dev/null
md5sum /lib/firmware/mediatek/mtkbt0.dat 2>/dev/null
echo ""

echo "6. Pacman hook:"
ls -l /etc/pacman.d/hooks/bluetooth-firmware.hook 2>/dev/null || echo "Hook not found"
echo ""

echo "7. Rebuild script:"
ls -l /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh 2>/dev/null || echo "Script not found"
echo ""

echo "8. Recent kernel bluetooth messages:"
dmesg | grep -i bluetooth | tail -15
echo ""

echo "9. Bluetooth controller status:"
bluetoothctl show 2>/dev/null || echo "Bluetooth not available"
echo ""

echo "10. Last rebuild log entries:"
tail -20 /var/log/bt-module-rebuild.log 2>/dev/null || echo "No log found"
echo ""

echo "=== End Diagnostics ==="
```

### Getting help

If you're still having issues:

1. **Run the diagnostic script above** and save output
2. **Check existing issues:** [GitHub Issues](https://github.com/ismailtrm/mt7902-bluetooth-arch-fix/issues)
3. **Create a new issue** with:
   - Output from diagnostic script
   - Your kernel version (`uname -r`)
   - Output from `/var/log/bt-module-rebuild.log`
   - Description of the problem

### Useful commands reference

```bash
# Check Bluetooth status
bluetoothctl show

# List paired devices
bluetoothctl devices

# Check loaded modules
lsmod | grep bt

# Check kernel messages
dmesg | grep -i bluetooth

# Check rebuild log
tail -f /var/log/bt-module-rebuild.log

# Manually run rebuild
sudo /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh

# Restart Bluetooth service
sudo systemctl restart bluetooth

# Check Bluetooth service status
systemctl status bluetooth
```
