# The MT7902 firmware wedge: root cause and evidence

This documents *why* the MT7902 Bluetooth controller wedges, how to capture proof
of it on your own machine, and what was fixed upstream as a result.

For the practical "my Bluetooth is dead, what do I do" answer, see
[RECOVERY.md](RECOVERY.md).

---

## Root cause: a firmware assert, then a reset that cannot recover

When the controller fails it emits a firmware coredump. The kernel exposes that
dump through the `devcoredump` subsystem, but only for five minutes (see
[Capturing the dump](#capturing-the-dump) below). Twelve natural failures were
logged from 2026-08-03 to 2026-10-25. Ten were captured, on kernels 7.1.8 to 7.2.11,
and all ten carry the same assert:

```
<ASSERT> ../bluetooth/system/debug/sys_log_interface_emi.c #811 -
    0, 0x6455, 0x1010707, 0xFF150001, rc=0, BTSYS, id=0x4 idle,
    irq=0x2, isr=0x929A5C (five dumps) / 0x929EEA (five dumps)
```

The chip is idle (`id=0x4 idle`) and nothing on the host side precedes the assert.

Comparing the driver's reset on a healthy chip with four natural failures, through
the same `btusb_mtk_reset()` path:

| | Healthy chip | After natural assert |
|---|---|---|
| WDT `0x740003a0` | `0x0` | `0x1` |
| SUBSYS_RST `0x70002610` | `0x0` | `0x0` |
| MISC `0x70002510` | `0x500` | `0x500` |
| Chip id read `0x70010200` | returns | times out (5.1 s) |
| Result | re-enumerates, setup 121 ms | descriptor read -110, port gone |

What follows from this:

- The generic reset sequence works on a healthy MT7902, so a missing MT7902 branch
  in the driver is an unlikely cause.
- `MTK_BT_RST_DONE` in MISC reads the same in both cases, so the driver's completion
  check cannot tell a failed reset from a good one here.
- The roughly 10 s between `Mediatek coredump end` and `Can't get device id` is two
  USB control timeouts: `usb_driver_release_interface()` on the ISO interface (5.35 s)
  and the chip id read (5.1 s). This adds latency and does not change the outcome.
- Two firmware blobs (build times 20240611 and 20250826) failed the same way, so
  moving between them does not help.
- Every reset path reachable from the host fails
  ([full list](RECOVERY.md#reset-paths-that-do-not-work)), including the ACPI `_RST`
  GPIO, which does execute and still does not revive the chip.

The question for MediaTek is open: once the WDT register reads 1, is there a sequence
that recovers the Bluetooth MCU without removing power?
[Full report on linux-bluetooth](https://lore.kernel.org/linux-bluetooth/20261025120328.1312536-1-ismailtarim7@gmail.com/).

> **Correction:** this document used to say the assert lives in mask ROM, based on
> `system/rom/transport/tra_usb3.c #764`. That assert comes from triggering a coredump
> by hand (2 of 2 manual triggers). The natural failures assert in
> `sys_log_interface_emi.c #811`. The ROM conclusion was an artifact of the trigger.

---

## Reproducing it on demand

Natural failures come at irregular intervals, from 46 minutes after a cold boot to
17 days, which makes investigation painful. The same outcome can be triggered
deliberately in about one second:

```bash
echo 1 > /sys/class/bluetooth/hci0/device/coredump
```

> ### ⚠️ This is a one-way trip
>
> On this chip, requesting a coredump wedges the controller **with the same
> outcome as a natural failure**: same reset failure, same disappearance from the USB
> bus. The assert differs (`tra_usb3.c #764`), so use this to study the reset, not the
> cause of the natural assert.
> Recovering requires a full power drain
> ([RECOVERY.md](RECOVERY.md#the-fix-full-power-drain)). Do not run this on a
> machine you cannot power-cycle, and make sure you are not depending on a
> Bluetooth keyboard or mouse at the time.

Why it wedges: `btmtk` asks the controller for a reset once the dump completes
(`btmtk_coredump_notify(DONE)` → `btmtk_reset_sync()` → `btusb_mtk_reset()`).
That reset is the path that fails.

This reproducer was confirmed with **stock in-tree modules**, not the out-of-tree
ones — so it is a genuine upstream bug, not an artifact of this repository's
legacy setup.

---

## Capturing the dump

The kernel frees `devcoredump` entries automatically after `DEVCD_TIMEOUT`,
which is **5 minutes** (`include/linux/devcoredump.h`). That is why these dumps
were never available for analysis: by the time anyone noticed Bluetooth was
broken, the evidence was gone.

There is a second, tighter deadline. Observed timeline of one real failure:

```
09:02:09   coredump generated      -> devcoredump uevent fires
                                      ...device is still on the USB bus...
09:03:25   USB disconnect          -> /sys/bus/usb/devices/<port>/* gone forever
09:07:09   DEVCD_TIMEOUT (5 min)   -> kernel frees the dump, unrecoverable
```

So there is a **~76 second window** in which the chip has crashed but has not yet
fallen off the bus. Anything not collected in that window cannot be collected
later — no reboot required, the disconnect alone is enough.

A udev rule catches the uevent and writes everything to disk immediately:

```bash
sudo cp tools/save-bt-coredump.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/save-bt-coredump.sh
sudo cp tools/99-bt-coredump-save.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
```

Output lands in `/var/log/bt-coredumps/`:

| File | Contents |
|---|---|
| `<timestamp>-devcdN.bin` | Raw firmware coredump (~1 MB) |
| `<timestamp>-devcdN.meta.txt` | Kernel log, module info, device identity |
| `<timestamp>-devcdN.live-state.txt` | USB/PCI sysfs state while the device is still present |

The script collects in order of fragility — dump first (5 min TTL), then live
sysfs state (~76 s), then journal data (already persistent). Every helper command
is wrapped in `timeout` so the udev event queue is never blocked.

Inspect a captured dump with:

```bash
strings /var/log/bt-coredumps/*.bin | grep -A3 ASSERT
```

---

## Upstream patches from this investigation

Reading the failing reset path turned up two bugs in `btmtk_usb_subsys_reset()`.
In both, a failed reset could be reported to the caller as success. Applied by Luiz
Augusto von Dentz, in Linux 7.3 and the 7.2, 6.18 and 6.12 stable trees:

### [`59c3ee19ca88`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=59c3ee19ca88) Do not report success when subsys reset fails

The function verifies the reset by reading the chip id back. When that read
succeeded at the bus level but returned an id of **zero**, it logged
`"Can't get device id, subsys reset fail."` and then returned that zero, which
its caller reads as success. Now returns `-ENODEV`.

In the natural failures the id read times out instead, and that branch already
returned an error before this patch. The patch is correct for the zero-id case, but
that case was not observed here, and the log line is the same for both.

### [`21b50c24843b`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=21b50c24843b) Do not discard the subsystem reset timeout

When the `MTK_BT_RST_DONE` poll timed out, the error was stored in `err` and then
immediately overwritten by the return value of the following chip-id read,
so the timeout never reached the caller. This was a regression from commit
`3dcb122b3064`; the timeout is now kept in a separate variable and returned.

### [`btmtk_usb_isointf_init()` error handling](https://lore.kernel.org/linux-bluetooth/20261029224022.1233751-1-ismailtarim7@gmail.com/)

A separate fix, accepted into `bluetooth-next`: stop the ISO RX URB when the `0xfd98`
write fails and check the result of `__set_mtk_intr_interface()`. Those error paths
never fired in 245 setups on this machine, so it was verified with fault injection.

**Scope, honestly:** these fix error handling. They make a failed reset visible to
the caller, which is a prerequisite for anything reacting to it. They do **not**
make this controller recoverable; that needs a firmware fix or a recovery sequence
from MediaTek.

---

## If you have this hardware

A second data point would genuinely help, especially from a different laptop
model or firmware revision. Useful to report:

- Output of `strings <dump>.bin | grep -A3 ASSERT` — is it the same file and line?
- `journalctl -k | grep "hci0: HW/SW Version"` — firmware build timestamp
- Whether the full power drain recovers your device too
- Your observed interval between wedges

Open an [issue](https://github.com/ismailtrm/mt7902-bluetooth-arch-fix/issues).
MediaTek engineers are copied on the upstream thread, so corroborating reports
have somewhere to go.
