---
name: Bug Report or Issue
about: Report a problem with MT7902 Bluetooth fix
title: '[BUG] '
labels: bug
assignees: ''
---

## Description

<!-- Provide a clear and concise description of the problem -->

## System Information

**Kernel version:**
```bash
uname -r
# Paste output here
```

**Distribution:**
<!-- e.g., Arch Linux, Manjaro, EndeavourOS -->

**Installed packages:**
```bash
pacman -Q linux linux-headers base-devel
# Paste output here
```

## Installation Method

- [ ] Automated installer (`install.sh`)
- [ ] Manual installation (following README)
- [ ] Other (please specify)

## Problem Details

**What were you trying to do?**
<!-- e.g., Initial installation, kernel update, etc. -->

**What happened instead?**
<!-- Describe the unexpected behavior -->

**When did it start?**
<!-- e.g., After kernel update from 6.18.4 to 6.18.5 -->

## Diagnostic Information

**Bluetooth status:**
```bash
bluetoothctl show
# Paste output here
```

**Loaded modules:**
```bash
lsmod | grep -E '(btusb|btmtk|bluetooth)'
# Paste output here
```

**Kernel messages:**
```bash
dmesg | grep -i bluetooth | tail -20
# Paste output here
```

**Module files:**
```bash
ls -l /lib/modules/$(uname -r)/updates/bt*.ko
# Paste output here
```

**Firmware files:**
```bash
ls -l /lib/firmware/mediatek/BT* /lib/firmware/mediatek/mtkbt*
md5sum /lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin
md5sum /lib/firmware/mediatek/mtkbt0.dat
# Paste output here
```

**Rebuild log:**
```bash
tail -50 /var/log/bt-module-rebuild.log
# Paste output here
```

**Hook status:**
```bash
ls -l /etc/pacman.d/hooks/bluetooth-firmware.hook
cat /etc/pacman.d/hooks/bluetooth-firmware.hook
# Paste output here
```

## Steps to Reproduce

<!-- If applicable, provide steps to reproduce the issue -->

1. Step 1
2. Step 2
3. Step 3

## What I've tried

<!-- List troubleshooting steps you've already attempted -->

- [ ] Ran rebuild script manually: `sudo /opt/bluetooth-firmware-backup/rebuild-bt-modules.sh`
- [ ] Checked firmware checksums
- [ ] Reinstalled linux-headers
- [ ] Checked pacman hooks directory
- [ ] Other (please specify):

## Additional Context

<!-- Add any other context, screenshots, or information that might be helpful -->

## Checklist

Before submitting, please:

- [ ] I've read the [troubleshooting guide](docs/TROUBLESHOOTING.md)
- [ ] I've searched [existing issues](https://github.com/ismailtrm/mt7902-bluetooth-arch-fix/issues) for similar problems
- [ ] I've provided all requested diagnostic information above
- [ ] I've removed any personal/sensitive information from logs

---

**Thank you for taking the time to report this issue!**
