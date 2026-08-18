# The MT7902 firmware wedge: root cause and evidence

This documents *why* the MT7902 Bluetooth controller wedges, how to capture proof
of it on your own machine, and what was fixed upstream as a result.

For the practical "my Bluetooth is dead, what do I do" answer, see
[RECOVERY.md](RECOVERY.md).

---

## Root cause: an assert in mask ROM

When the controller fails it emits a firmware coredump. The kernel exposes that
dump through the `devcoredump` subsystem — but only for five minutes (see
[Capturing the dump](#capturing-the-dump) below). Once captured, the payload is
unambiguous:

```
; exception type: ASSERT      ;;[CONNSYS] coredump start ..
<ASSERT> system/rom/transport/tra_usb3.c #764 -
    rc=*, BTSYS, id=0x4 idle, isr=0x81A6F6, irq=0x11, lr=0x0, asr_t=54540991
;PC log(0..N)  ;LR log(0..N)  ;coredump end
Controller Name: 0x7902   Firmware Version: 0x8A00
```

Three things follow from this:

| Observation | Consequence |
|---|---|
| Path is `system/rom/...` | The assert lives in **mask ROM**, not in the firmware blob the kernel uploads |
| `id=0x4 idle` | The chip faults while **idle**, matching wedges that appear after the machine sits unused |
| Source file + line are MediaTek-internal | Only MediaTek can fix it; there is no host-side patch for this |

The ROM location is the single most useful fact here. It explains a result that
was confusing for months: **two different firmware blobs produced identical
failures.** Updating firmware could never have helped, because the faulting code
is not in the firmware.

It also explains why every reset path reachable from the host fails
([full list](RECOVERY.md#reset-paths-that-do-not-work)) — including the ACPI
`_RST` GPIO, which does execute and still does not revive the chip.

---

## Reproducing it on demand

The natural failure interval is roughly 12 days, which makes investigation
painful. It can be triggered deliberately in about one second:

```bash
echo 1 > /sys/class/bluetooth/hci0/device/coredump
```

> ### ⚠️ This is a one-way trip
>
> On this chip, requesting a coredump wedges the controller **exactly as the
> natural failure does** — same signature, same disappearance from the USB bus.
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
In both, a reset that had demonstrably failed was reported to the caller as
success. Merged into `bluetooth-next` (Luiz Augusto von Dentz):

### [`771e812f94b3`](https://git.kernel.org/pub/scm/linux/kernel/git/bluetooth/bluetooth-next.git/commit/?id=771e812f94b3) — Do not report success when subsys reset fails

The function verifies the reset by reading the chip id back. When that read
succeeded at the bus level but returned an id of **zero**, it logged
`"Can't get device id, subsys reset fail."` and then returned that zero — which
its caller reads as success. Now returns `-ENODEV`.

### [`54c03e6bc718`](https://git.kernel.org/pub/scm/linux/kernel/git/bluetooth/bluetooth-next.git/commit/?id=54c03e6bc718) — Do not discard the subsystem reset timeout

When the `MTK_BT_RST_DONE` poll timed out, the error was stored in `err` — and
then immediately overwritten by the return value of the following chip-id read,
so the timeout never reached the caller. This was a regression from commit
`3dcb122b3064`; the timeout is now kept in a separate variable and returned.

**Scope, honestly:** these fix error *reporting*. They make a failed reset
visible to the caller, which is a prerequisite for anything reacting to it. They
do **not** make this controller recoverable — that requires a ROM fix from
MediaTek.

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
