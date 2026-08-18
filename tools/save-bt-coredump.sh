#!/usr/bin/env bash
# Persist a MediaTek Bluetooth firmware coredump before the kernel frees it.
#
# WHY THIS EXISTS — the timing is the whole point:
#
#   T+0s     coredump generated   -> devcoredump uevent fires (THIS SCRIPT RUNS HERE)
#                                    ...the device is still on the USB bus...
#   T+76s    USB disconnect       -> /sys/bus/usb/devices/<port>/* is gone for good
#   T+5min   DEVCD_TIMEOUT        -> kernel frees the dump, unrecoverable
#            (include/linux/devcoredump.h)
#
#   So there is a short window in which the chip has crashed but has not yet
#   fallen off the bus. Anything not collected in that window cannot be
#   collected afterwards -- no reboot needed, the disconnect alone is enough.
#
# DESIGN RULE: collect most-fragile first.
#   1) the dump itself      (5 min TTL)
#   2) live device sysfs    (~76 s, vanishes on disconnect)
#   3) journal / modinfo    (already persistent, most durable)
#   Every helper is wrapped in `timeout` so the udev event queue never blocks.
#
# Install:
#   sudo cp save-bt-coredump.sh /usr/local/bin/
#   sudo chmod +x /usr/local/bin/save-bt-coredump.sh
#   sudo cp 99-bt-coredump-save.rules /etc/udev/rules.d/
#   sudo udevadm control --reload-rules
#
# Manual run (against an existing entry):
#   sudo /usr/local/bin/save-bt-coredump.sh /sys/class/devcoredump/devcd0

set -uo pipefail

DEST="${BT_COREDUMP_DEST:-/var/log/bt-coredumps}"
DEV="${1:-}"

# Bluetooth USB id to look for. Override with BT_USB_ID=vvvv:pppp if your
# MediaTek controller enumerates differently.
BT_USB_ID="${BT_USB_ID:-13d3:3579}"
BT_VID="${BT_USB_ID%%:*}"
BT_PID="${BT_USB_ID##*:}"

mkdir -p "$DEST" 2>/dev/null
TS=$(date '+%Y%m%d-%H%M%S')

# No argument: sweep every present devcoredump entry.
if [ -z "$DEV" ]; then
  for d in /sys/class/devcoredump/devcd*; do [ -d "$d" ] && "$0" "$d"; done
  exit 0
fi
[ -d "$DEV" ] || exit 0
OUT="$DEST/${TS}-$(basename "$DEV")"

# --- locate the hardware without hardcoding bus paths ----------------------
USBDEV=""
for d in /sys/bus/usb/devices/*; do
  [ -r "$d/idVendor" ] && [ -r "$d/idProduct" ] || continue
  if [ "$(cat "$d/idVendor" 2>/dev/null)" = "$BT_VID" ] &&
     [ "$(cat "$d/idProduct" 2>/dev/null)" = "$BT_PID" ]; then
    USBDEV="$d"; break
  fi
done

PORT=""
if [ -n "$USBDEV" ]; then
  # e.g. .../usb3/3-10 -> .../usb3/3-0:1.0/usb3-port10
  _b=$(basename "$USBDEV")            # 3-10
  _bus=${_b%%-*}                      # 3
  _pn=${_b##*-}                       # 10
  _cand="/sys/bus/usb/devices/usb${_bus}/${_bus}-0:1.0/usb${_bus}-port${_pn}"
  [ -d "$_cand" ] && PORT="$_cand"
fi

# WiFi half of the same combo chip (separate driver, same silicon)
PCIDEV=$(readlink -f /sys/bus/pci/drivers/mt7921e/0000:* 2>/dev/null | head -1)

# ===========================================================================
# 1) MOST FRAGILE: the firmware dump. Nothing else runs before this.
# ===========================================================================
SAVED=0
if [ -r "$DEV/data" ] && timeout 30 cp "$DEV/data" "$OUT.bin" 2>/dev/null; then
  SAVED=1; sync 2>/dev/null
fi
logger -t bt-coredump "MT7902 coredump: saved=$SAVED -> $OUT.bin" 2>/dev/null

# ===========================================================================
# 2) LIVE DEVICE STATE -- roughly 76 s until disconnect, collect it now
# ===========================================================================
{
  echo "########## LIVE STATE AT EVENT TIME -- $(date -Is) ##########"
  echo "### Bluetooth USB device ($BT_USB_ID) still present: $([ -n "$USBDEV" ] && [ -e "$USBDEV" ] && echo YES || echo NO-ALREADY-GONE)"
  if [ -n "$USBDEV" ] && [ -e "$USBDEV" ]; then
    echo "--- $(basename "$USBDEV") sysfs ---"
    for a in idVendor idProduct bcdDevice manufacturer product serial \
             bConfigurationValue bNumInterfaces bmAttributes bMaxPower \
             speed devnum devpath busnum authorized quirks removable version urbnum; do
      [ -r "$USBDEV/$a" ] && echo "  $a = $(timeout 2 cat "$USBDEV/$a" 2>/dev/null)"
    done
    echo "--- power/ ---"
    for f in "$USBDEV"/power/*; do
      [ -f "$f" ] && echo "  $(basename "$f") = $(timeout 2 cat "$f" 2>/dev/null)"
    done
    echo "--- interfaces ---"
    timeout 2 ls -1 "$USBDEV" 2>/dev/null | grep -E "^$(basename "$USBDEV"):"
  fi
  echo
  echo "### HCI state"
  timeout 2 ls -1 /sys/class/bluetooth/ 2>/dev/null
  for h in /sys/class/bluetooth/hci*; do
    [ -d "$h" ] || continue
    echo "  $(basename "$h"): $(timeout 2 cat "$h/address" 2>/dev/null)"
  done
  echo
  if [ -n "$PORT" ]; then
    echo "### USB port ($(basename "$PORT"))"
    for f in "$PORT"/*; do
      [ -f "$f" ] && echo "  $(basename "$f") = $(timeout 2 cat "$f" 2>/dev/null)"
    done
  fi
  echo
  if [ -n "$PCIDEV" ]; then
    echo "### PCIe half (WiFi) -- combo chip, same silicon"
    for a in enable power_state current_link_speed current_link_width reset_method; do
      [ -r "$PCIDEV/$a" ] && echo "  $a = $(timeout 2 cat "$PCIDEV/$a" 2>/dev/null)"
    done
  fi
  echo
  echo "### rfkill"; timeout 3 rfkill list 2>/dev/null
} > "$OUT.live-state.txt" 2>&1

# ===========================================================================
# 3) MOST DURABLE: metadata + journal (already in the persistent journal)
# ===========================================================================
{
  echo "=== captured: $(date -Is) ==="
  echo "source      : $DEV"
  echo "dump saved  : $([ "$SAVED" = 1 ] && stat -c '%s bytes' "$OUT.bin" 2>/dev/null || echo 'FAILED')"
  echo "kernel      : $(uname -r)"
  echo "uptime      : $(uptime -p 2>/dev/null)"
  echo "failing_dev : $(timeout 5 readlink -f "$DEV/failing_device" 2>/dev/null)"
  echo
  echo "--- loaded BT modules (in-tree vs out-of-tree) ---"
  timeout 5 modinfo btusb 2>/dev/null | grep -E "^filename|^vermagic"
  timeout 5 modinfo btmtk 2>/dev/null | grep -E "^filename"
  echo
  echo "--- firmware blob in use ---"
  timeout 10 journalctl -k -b --no-pager 2>/dev/null \
    | grep -E "hci[0-9]: HW/SW Version" | tail -2
  echo
  echo "--- recent BT/USB log lines ---"
  timeout 15 journalctl -k -b --no-pager 2>/dev/null \
    | grep -iE "hci[0-9]|btusb|btmtk|coredump|unable to enumerate|xhci" | tail -60
} > "$OUT.meta.txt" 2>&1

# Keep captures root-only: a controller coredump is raw device memory and may
# contain link keys or peer addresses. Read them with sudo.
chmod 700 "$DEST" 2>/dev/null
chmod 600 "$OUT".* 2>/dev/null
exit 0
