# MT7902 Bluetooth on Linux

> ## ⚠️ DEPRECATED — do not install the custom modules
>
> **Since Linux 7.1 the mainline kernel supports MT7902 Bluetooth out of the box.**
> The out-of-tree modules, the Windows firmware extraction and the pacman hook that
> this repository used to install are **no longer needed, and installing them today
> can shadow the working in-tree driver.**
>
> If you followed the old instructions, see [Removing the old setup](#removing-the-old-setup).
>
> **The repository is now a troubleshooting reference** for the failure mode that
> remains: the controller wedging after a firmware coredump. That part is still
> unsolved upstream and is documented here because nothing else documents it.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?logo=arch-linux&logoColor=fff)](https://archlinux.org/)

---

## Do I need anything from this repo?

| Your kernel | What you need |
|---|---|
| **≥ 7.1** | **Nothing.** Stock `btusb`/`btmtk` drive MT7902. Do not install custom modules. |
| < 7.1 | Upgrade your kernel. That is easier and safer than the old workaround. |
| Any version, BT died and won't come back | → [Recovery](docs/RECOVERY.md) |

In-tree support landed in commit
[`51c4173b89fe`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=51c4173b89fe)
("Bluetooth: btusb: Add new VID/PID 13d3/3579 for MT7902", Sean Wang, Feb 2026),
first released in **v7.1-rc1**.

### Verify it yourself

```bash
# Is the device bound to the in-tree driver?
readlink -f /sys/bus/usb/devices/*/driver | grep btusb

# Which module file is actually loaded? (should be under kernel/, NOT updates/)
modinfo -n btusb

# Is the controller up?
bluetoothctl show
```

If `modinfo -n btusb` points at `/lib/modules/<ver>/updates/`, you are still running
an out-of-tree module — see [Removing the old setup](#removing-the-old-setup).

---

## The remaining problem: the controller wedges and disappears

This is a real, still-unfixed bug and the reason this repository is still here.

**Symptoms**

- Bluetooth works fine, then stops — often after the machine has been idle
- `bluetoothctl show` prints `No default controller available`
- The USB device is **gone from the bus entirely**: `lsusb` no longer lists `13d3:3579`
- `dmesg` shows the controller failing to enumerate:
  `-110` → `-62` → `unable to enumerate USB device`
- `bluetoothctl` **hangs** when no controller is present
- Every subsequent boot takes ~66 s longer, because initrd keeps retrying the dead device

**What actually fixes it**

Only a full power drain. Reboot does not work; neither does a normal power-off.

| Level | Method | Works? |
|---|---|---|
| 1 | `reboot` (warm) | ❌ |
| 2 | `poweroff`, then power button (S5, AC still connected) | ❌ |
| 3 | **`poweroff` → unplug AC → hold power button 30 s → replug → boot** | ✅ |

Full details, plus every in-band reset path that was measured and ruled out
(rfkill, USB port power cycling, ACPI `_RST`, WiFi-side chip reset, PCIe FLR and
secondary bus reset): **[docs/RECOVERY.md](docs/RECOVERY.md)**

**Why no software fix exists**

The controller asserts inside its own **ROM**, not in the loadable firmware blob:

```
<ASSERT> system/rom/transport/tra_usb3.c #764 - rc=*, BTSYS, id=0x4 idle
```

That is why swapping firmware blobs never helped, and why no reset path reachable
from the host brings it back. Analysis, the captured coredump, and a deterministic
one-command reproducer: **[docs/FIRMWARE-WEDGE.md](docs/FIRMWARE-WEDGE.md)**

---

## Upstream patches from this investigation

Reading the reset path turned up two bugs in `btmtk_usb_subsys_reset()`: a failed
subsystem reset was reported to the caller as success. Both are merged into
`bluetooth-next`:

| Commit | Fix |
|---|---|
| [`771e812f94b3`](https://git.kernel.org/pub/scm/linux/kernel/git/bluetooth/bluetooth-next.git/commit/?id=771e812f94b3) | Do not report success when subsys reset fails |
| [`54c03e6bc718`](https://git.kernel.org/pub/scm/linux/kernel/git/bluetooth/bluetooth-next.git/commit/?id=54c03e6bc718) | Do not discard the subsystem reset timeout |

These make the failure **visible** to the caller. They do not fix the wedge — the
root cause is in the closed-source ROM and only MediaTek can address that.

---

## Removing the old setup

If you previously installed the pacman hook and custom modules from this repo:

```bash
# 1. Stop the hook from rebuilding out-of-tree modules on every kernel update
sudo rm -f /etc/pacman.d/hooks/bluetooth-firmware.hook

# 2. Disable the out-of-tree modules so the in-tree ones win
sudo find /lib/modules/*/updates \
  \( -name 'btusb.ko*' -o -name 'btmtk.ko*' \) ! -name '*.disabled' \
  -exec mv -v {} {}.disabled \;
sudo depmod -a

# 3. Remove the Windows-extracted blob if it shadows the packaged one
#    (the loader prefers .bin over .bin.zst — see docs/HOW-IT-WORKS.md)
ls -l /lib/firmware/mediatek/BT_RAM_CODE_MT7902_1_1_hdr.bin*

# 4. Reboot, then confirm which firmware is in use
journalctl -k | grep "hci0: HW/SW Version"
```

Keep the `.disabled` copies until you have confirmed Bluetooth works on stock
modules; then remove `/opt/bluetooth-firmware-backup` and `~/mt7902_temp`.

---

## Historical: the original pacman-hook workaround

<details>
<summary>What this repo used to do (kernels &lt; 7.1) — kept for reference, do not use</summary>

Before in-tree support existed, MT7902 Bluetooth needed patched `btusb`/`btmtk`
modules built from an out-of-tree source, plus firmware extracted from a Windows
installation. Because `pacman -Syu` installs a new kernel into a new module
directory, the custom modules had to be rebuilt on every update — which this
repository automated with a pacman hook.

The scripts and hook are still in `scripts/` and `hooks/`, and the design is
described in [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md). They are kept so the
old behaviour stays auditable, **not** because they should be run.

The write-up of how that solution was originally found is in
[docs/DEVELOPMENT-STORY.md](docs/DEVELOPMENT-STORY.md); it is still a decent
account of debugging an unsupported device, and remains accurate about that period.

</details>

---

## Documentation

| Document | Contents |
|---|---|
| [docs/RECOVERY.md](docs/RECOVERY.md) | Getting a wedged controller back; every reset path that was tested |
| [docs/FIRMWARE-WEDGE.md](docs/FIRMWARE-WEDGE.md) | Root cause, coredump capture, reproducer, upstream patches |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Issues with the legacy setup (historical) |
| [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md) | Design of the legacy hook + firmware precedence (historical) |
| [docs/DEVELOPMENT-STORY.md](docs/DEVELOPMENT-STORY.md) | How the original workaround was found (historical) |
| [docs/REFERENCES.md](docs/REFERENCES.md) | External links and sources |

## Hardware this was tested on

ASUS Vivobook, MediaTek MT7902 combo chip:

- Bluetooth: USB `13d3:3579` — `btusb` + `btmtk`
- WiFi: PCIe `14c3:7902` — `mt7921e` (a separate driver stack; the BT wedge does not affect it)

## Credits

- Investigation and documentation: [ismailtrm](https://github.com/ismailtrm)
- In-tree MT7902 support: Sean Wang and the linux-bluetooth maintainers
- Legacy out-of-tree driver source: [OnlineLearningTutorials/mt7902_temp](https://github.com/OnlineLearningTutorials/mt7902_temp)

## License

MIT — see [LICENSE](LICENSE).

Firmware files are proprietary to MediaTek and are not distributed here.

## Contributing

If you have an MT7902 and hit the wedge, a report is genuinely useful — especially
the output of `docs/FIRMWARE-WEDGE.md`'s coredump capture. Please open an
[issue](https://github.com/ismailtrm/mt7902-bluetooth-arch-fix/issues).
