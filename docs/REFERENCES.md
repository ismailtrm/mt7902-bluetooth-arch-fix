# References

This document provides links to all relevant sources, documentation, and related resources for the MT7902 Bluetooth fix.

## Primary Sources

### MT7902 Driver Source Code

- **Repository:** [OnlineLearningTutorials/mt7902_temp](https://github.com/OnlineLearningTutorials/mt7902_temp)
- **Description:** Patched Linux kernel Bluetooth drivers for MediaTek MT7902
- **Kernel versions supported:** 6.14, 6.15, 6.16, 6.17, 6.18
- **License:** GPL-2.0 (Linux kernel module license)
- **Contains:**
  - Patched `btusb.c` and `btmtk.c` source code
  - Makefile for kernel module compilation
  - WiFi driver development (in progress)
  - Firmware extraction tools

### MediaTek Windows Drivers

- **Official Source:** MediaTek Driver Downloads
- **Version used in this guide:** 3.3.0.633 (W11x64)
- **Location in Windows:** `C:\Windows\System32\drivers\`
- **Note:** Firmware files (`BT_RAM_CODE_MT7902_1_1_hdr.bin`) are proprietary and copyrighted by MediaTek

## Arch Linux Documentation

### Pacman Hooks

- **Man page:** [alpm-hooks(5)](https://man.archlinux.org/man/alpm-hooks.5)
- **Arch Wiki:** [Pacman#Hooks](https://wiki.archlinux.org/title/Pacman#Hooks)
- **Description:** Documentation for creating and managing pacman hooks
- **Relevant sections:**
  - Hook file format (`[Trigger]` and `[Action]` sections)
  - Trigger types and operations
  - Execution timing (PreTransaction vs PostTransaction)

### Kernel Modules

- **Arch Wiki:** [Kernel module](https://wiki.archlinux.org/title/Kernel_module)
- **Relevant sections:**
  - Module loading and unloading
  - Module dependencies (`depmod`)
  - Module parameters
  - Troubleshooting module loading

### DKMS (Dynamic Kernel Module Support)

- **Arch Wiki:** [Dynamic Kernel Module Support](https://wiki.archlinux.org/title/Dynamic_Kernel_Module_Support)
- **Description:** Alternative approach using DKMS for automatic module rebuilding
- **Note:** This solution uses pacman hooks instead of DKMS for simplicity

## Linux Kernel Documentation

### Bluetooth Subsystem

- **Kernel Docs:** [Bluetooth](https://www.kernel.org/doc/html/latest/networking/bluetooth.html)
- **Description:** Official Linux kernel Bluetooth documentation
- **Relevant sections:**
  - Bluetooth architecture
  - HCI (Host Controller Interface)
  - Firmware loading mechanism

### Module Building

- **Kernel Docs:** [Building External Modules](https://www.kernel.org/doc/html/latest/kbuild/modules.html)
- **Description:** How to build external kernel modules
- **Relevant sections:**
  - Kbuild system overview
  - Module Makefiles
  - Building against specific kernel versions

### Firmware Loading

- **Kernel Docs:** [Firmware](https://www.kernel.org/doc/html/latest/driver-api/firmware/index.html)
- **Description:** How Linux loads firmware files
- **Relevant paths:**
  - `/lib/firmware/` - Standard firmware location
  - Request firmware API

## MediaTek Hardware

### MT7902 Specifications

- **Chipset:** MediaTek MT7902
- **Connectivity:** Wi-Fi 6E + Bluetooth 5.3
- **USB Vendor ID:** 0x0489 (Foxconn)
- **USB Product ID:** 0xe0e2
- **PCI Vendor ID:** 0x14c3 (MediaTek)
- **Bluetooth Manufacturer ID:** 0x0046 (70 decimal)

### Related MediaTek Chipsets

- **MT7921:** Predecessor to MT7902, Wi-Fi 6 + BT 5.2
- **MT7922:** Similar generation, different configuration
- **MT7961:** Earlier model with partial Linux support

**Linux Firmware Repository:** [linux-firmware.git](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/)
- Contains firmware for MT7921 and MT7922
- MT7902 firmware **not yet included** (as of early 2024)

## Community Resources

### Forum Threads and Discussions

#### Arch Linux Forums

- **Search:** [Arch Linux Forums - MT7902](https://bbs.archlinux.org/search.php?keywords=mt7902)
- **Relevant topics:**
  - Bluetooth issues on new laptops
  - MediaTek driver discussions
  - Kernel update problems

#### Reddit

- **r/archlinux:** [MT7902 discussions](https://www.reddit.com/r/archlinux/search/?q=mt7902)
- **r/linux:** [MediaTek Bluetooth Linux support](https://www.reddit.com/r/linux/search/?q=mediatek+bluetooth)

#### Stack Overflow / Unix & Linux Stack Exchange

- **Search:** [Unix Stack Exchange - MT7902](https://unix.stackexchange.com/search?q=mt7902)

### Bug Reports

#### Kernel Bugzilla

- **Search:** [Bugzilla - MediaTek Bluetooth](https://bugzilla.kernel.org/buglist.cgi?quicksearch=mediatek%20bluetooth)

#### Distribution Trackers

- **Arch Linux:** [bugs.archlinux.org](https://bugs.archlinux.org/)
- **Ubuntu Launchpad:** [Bluetooth bugs](https://bugs.launchpad.net/ubuntu/+source/linux/+bugs?field.tag=bluetooth)

## Similar Solutions

### Other MediaTek Bluetooth Fixes

- **MT7921 fix for older kernels:** Similar approach using patched modules
- **rtl8xxxu Bluetooth fixes:** Realtek chipset fixes using similar methodology

### Alternative Approaches

1. **DKMS-based solutions:**
   - Automatically rebuild on kernel updates
   - More complex setup than pacman hooks
   - Example: [nvidia-dkms](https://archlinux.org/packages/extra/x86_64/nvidia-dkms/)

2. **Backported kernel modules:**
   - Use newer module versions with older kernels
   - Requires careful version management

3. **Custom kernel compilation:**
   - Compile entire kernel with patches
   - More control but significantly more complex

## Related Tools

### Bluetooth Management

- **bluetoothctl:** CLI tool for managing Bluetooth (part of bluez)
  - [Arch Wiki - Bluetooth](https://wiki.archlinux.org/title/Bluetooth)

- **bluez:** Linux Bluetooth protocol stack
  - [Official site](http://www.bluez.org/)
  - [GitHub](https://github.com/bluez/bluez)

### Firmware Tools

- **fwupd:** Firmware update daemon
  - [Arch Wiki - fwupd](https://wiki.archlinux.org/title/Fwupd)
  - Not applicable for MT7902 (no LVFS support yet)

### Diagnostics

- **dmesg:** Kernel ring buffer messages
- **lsusb:** List USB devices
- **lspci:** List PCI devices
- **lsmod:** List loaded kernel modules
- **modinfo:** Show module information

## Development Resources

### Building Kernel Modules

- **Tutorial:** [Linux Device Drivers, Third Edition](https://lwn.net/Kernel/LDD3/)
- **Modern guide:** [The Linux Kernel Module Programming Guide](https://sysprog21.github.io/lkmpg/)

### Bluetooth Development

- **BlueZ Development:** [Developer documentation](https://git.kernel.org/pub/scm/bluetooth/bluez.git/tree/doc)
- **Bluetooth Core Specification:** [bluetooth.com](https://www.bluetooth.com/specifications/specs/)

## Legal and Licensing

### Firmware Copyright

- **MediaTek firmware files** are proprietary and copyrighted
- **Personal use:** Extracting from your own Windows installation for the same hardware is generally considered legal
- **Redistribution:** Cannot legally redistribute firmware binaries
- **This repository:** Provides tools to use your own legally-obtained firmware

### Code Licenses

- **mt7902_temp repository:** GPL-2.0 (Linux kernel modules)
- **This repository (mt7902-bluetooth-arch-fix):** MIT License
  - Scripts and documentation: MIT
  - Kernel module source: GPL-2.0 (from mt7902_temp)

### GPL Compliance

When distributing modified kernel modules:
- Must provide source code
- Must use GPL-compatible license
- Cannot add additional restrictions

References:
- [GPL-2.0 License](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)
- [Kernel Licensing Rules](https://www.kernel.org/doc/html/latest/process/license-rules.html)

## Additional Reading

### Bluetooth on Linux

- **Arch Wiki:** [Bluetooth](https://wiki.archlinux.org/title/Bluetooth)
- **Ubuntu Wiki:** [Bluetooth](https://help.ubuntu.com/community/BluetoothSetup)

### Kernel Module Development

- **Linux Kernel Documentation:** [Driver Model](https://www.kernel.org/doc/html/latest/driver-api/driver-model/)
- **Device Tree:** [devicetree.org](https://www.devicetree.org/)

### Firmware Development

- **Linux Firmware Guide:** [firmware_class](https://www.kernel.org/doc/html/latest/driver-api/firmware/firmware_class.html)

## Project Links

### This Repository

- **GitHub:** [ismailtrm/mt7902-bluetooth-arch-fix](https://github.com/ismailtrm/mt7902-bluetooth-arch-fix)
- **Issues:** [Issue Tracker](https://github.com/ismailtrm/mt7902-bluetooth-arch-fix/issues)
- **License:** [MIT License](https://github.com/ismailtrm/mt7902-bluetooth-arch-fix/blob/main/LICENSE)

### Contributing

We welcome contributions! If you have:
- Improved documentation
- Bug fixes
- Support for additional kernel versions
- Better error handling

Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## Credits

- **Solution developed by:** [ismailtrm](https://github.com/ismailtrm)
- **MT7902 kernel drivers:** [OnlineLearningTutorials](https://github.com/OnlineLearningTutorials)
- **Arch Linux community:** For documentation and support
- **MediaTek:** For hardware and Windows drivers

---

**Last Updated:** February 2026

**Note:** This document will be updated as new resources become available and as the MT7902 support situation evolves in the Linux kernel.

If you find additional useful resources, please submit a pull request or open an issue!
