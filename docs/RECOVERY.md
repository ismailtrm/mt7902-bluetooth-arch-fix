# Recovering a wedged MT7902 Bluetooth controller

The MT7902's Bluetooth half can stop responding and **drop off the USB bus
entirely**. Once that happens, nothing you can do from a running Linux system
brings it back — this document says what does work, and shows the reset paths
that were tested and failed, so you don't spend a week rediscovering them.

Everything below was measured on an ASUS Vivobook (BT `13d3:3579`, WiFi
`14c3:7902`) running Arch Linux, kernels 7.1.3 – 7.1.7.

---

## Is this your problem?

All of these are true when the controller is wedged:

```bash
bluetoothctl show            # "No default controller available"  (may HANG — see note)
lsusb | grep 13d3:3579       # nothing — the device is gone from the bus
ls /sys/class/bluetooth/     # empty, no hci0
```

and `dmesg` shows the port trying and failing to enumerate:

```
usb 3-10: device descriptor read/64, error -110
usb 3-10: device descriptor read/64, error -62
usb 3-10: unable to enumerate USB device
```

> **Note:** `bluetoothctl` hangs rather than erroring when no controller exists.
> Use `bluetoothctl --timeout 5 show`, or just check `/sys/class/bluetooth/`.

### Side effect worth knowing

A wedged controller adds roughly **66 seconds to every boot** — initrd blocks
while the USB core retries the dead device. If your boots suddenly got much
slower, this is likely why.

---

## The fix: full power drain

Three escalation levels were measured independently. **Only level 3 works.**

| Level | Method | Result |
|---|---|---|
| 1 | `reboot` (warm reset) | ❌ device still absent |
| 2 | `poweroff`, then press power button (S5, AC still connected) | ❌ device still absent |
| 3 | `poweroff` → **unplug AC** → **hold power button 30 s** → replug → boot | ✅ **device returns** |

```bash
sudo poweroff
# unplug the AC adapter
# press and hold the power button for 30 seconds
# plug AC back in, power on
```

On a laptop with a non-removable battery, holding the power button with AC
disconnected is what actually drains the rails. A normal `poweroff` leaves S5
standby power on parts of the board, which is why level 2 fails.

### Verify it came back

```bash
lsusb -d 13d3:3579          # should list the device
ls /sys/class/bluetooth/    # should show hci0
systemctl status bluetooth
```

Expect the first `Device setup` after recovery to be slow — around 3.2 s, versus
a normal 145–223 ms. It settles on subsequent boots.

### You do NOT need to boot Windows

An earlier version of this document claimed a Windows boot was the only cure.
**That was wrong**, and it mattered: believing it stopped the full-drain path
from being tried until the next failure, twelve days later. Level 3 was then measured directly and worked with
no Windows involved.

---

## Reset paths that do NOT work

Each of these was executed against a live wedged controller. None recovered it.
They are listed so nobody has to repeat the work.

| Path | How | Result |
|---|---|---|
| `rfkill` block/unblock | `rfkill block bluetooth && rfkill unblock bluetooth` | no change |
| Driver reload | `modprobe -r btusb btmtk && modprobe btusb` | no-op — there is no device to bind |
| USB port power cycle (kernel's own, ~40 ms) | `echo 1 > .../port10/disable` then `0` | port re-powers, device still fails to enumerate |
| USB port power cycle (manual, 10 s) | same, held 250× longer | identical failure — duration is not the variable |
| ACPI `_PRR` → `_RST` | evaluate the reset power resource via `acpi_call` | `_RST` **ran** (returned 200 ms, MediaTek branch) — device never came back |
| WiFi-side chip reset | `echo 1 > .../mt7921/chip_reset` (debugfs) | WiFi subsystem reset and reloaded its firmware; **BT half unaffected** |
| PCIe FLR | `echo 1 > /sys/bus/pci/devices/…/reset` | no change |
| PCIe secondary bus reset (PERST#) | `reset_method=bus`, then reset | no change |

Two findings from that table are worth stating explicitly:

- **The ACPI reset really executes.** `_PRR` exists, `_RST` returns `0xc8` (200),
  meaning the firmware took its MediaTek-specific timing branch. The host-side
  reset lever is not missing — it simply does not revive the chip.
- **Resetting the WiFi half does not rescue the BT half.** The WiFi subsystem
  reset and firmware reload succeed while Bluetooth stays dead, so a shared-die
  reset is not reaching the Bluetooth block.

### A note on `_PRR`

Linux does not evaluate ACPI `_PRR` for MediaTek Bluetooth at all — the only
driver that uses it is `btintel.c`, for Intel controllers. Adding `_PRR` handling
to `btmtk` was considered and rejected here, because the manual experiment above
shows `_RST` does not recover this chip; wiring it into the driver would add code
that cannot fix the failure.

---

## Why nothing in-band works

The firmware asserts on its own while idle:

```
<ASSERT> ../bluetooth/system/debug/sys_log_interface_emi.c #811 - ... BTSYS, id=0x4 idle
```

The driver's reset works on a healthy chip. After the assert, the same sequence ends
with the chip id read timing out and the device leaving the bus. Why only cutting power
clears this state is unknown; the firmware is closed and the question is open with
MediaTek.

Full analysis, register comparison and a one-command reproducer:
[FIRMWARE-WEDGE.md](FIRMWARE-WEDGE.md).

---

## Frequency and triggers

- Observed interval: **irregular**, from 46 minutes after a cold boot to 17 days
- The chip was **idle** at the moment of failure (`id=0x4 idle` in the assert),
  consistent with wedges appearing after the machine sat unused
- **Powering off a Bluetooth keyboard does not trigger it** — that hypothesis was
  tested and ruled out
- **Firmware version is not a factor** — two different blobs produced identical
  failures
