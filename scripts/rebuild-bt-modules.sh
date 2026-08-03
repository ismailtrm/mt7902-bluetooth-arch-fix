#!/bin/bash
#
# MediaTek MT7902 Bluetooth Module Rebuild Script
# Part of: https://github.com/ismailtrm/mt7902-bluetooth-arch-fix
#
# This script automatically rebuilds MT7902 Bluetooth kernel modules
# for newly installed kernels and restores firmware files from backup.
# It is triggered by a pacman hook after kernel updates.
#

set -e

#############################################################################
# Configuration - Can be overridden via environment variables
#############################################################################

# Source directory containing MT7902 Bluetooth driver code
# Default: ~/mt7902_temp/linux-6.18/drivers/bluetooth
SOURCE_DIR="${MT7902_SOURCE_DIR:-$HOME/mt7902_temp/linux-6.18/drivers/bluetooth}"

# Backup directory containing firmware files
# Default: /opt/bluetooth-firmware-backup
BACKUP_DIR="${MT7902_BACKUP_DIR:-/opt/bluetooth-firmware-backup}"

# Log file location
LOG_FILE="${MT7902_LOG_FILE:-/var/log/bt-module-rebuild.log}"

# Firmware files to restore
FIRMWARE_DIR="/lib/firmware/mediatek"
FIRMWARE_FILES=(
    "BT_RAM_CODE_MT7902_1_1_hdr.bin"
    "mtkbt0.dat"
)

# Module files to build
MODULE_FILES=(
    "btmtk.ko"
    "btusb.ko"
)

#############################################################################
# Functions
#############################################################################

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

validate_environment() {
    # Check if source directory exists
    if [ ! -d "$SOURCE_DIR" ]; then
        error_exit "Source directory not found: $SOURCE_DIR

Please ensure mt7902_temp repository is cloned:
  git clone https://github.com/OnlineLearningTutorials/mt7902_temp ~/mt7902_temp

Or set MT7902_SOURCE_DIR environment variable to the correct path."
    fi

    # Check if backup directory exists
    if [ ! -d "$BACKUP_DIR" ]; then
        error_exit "Backup directory not found: $BACKUP_DIR

Please run the installer or create backup directory with firmware files."
    fi

    # Check if firmware files exist in backup
    for fw_file in "${FIRMWARE_FILES[@]}"; do
        if [ ! -f "$BACKUP_DIR/$fw_file" ]; then
            error_exit "Firmware file not found in backup: $BACKUP_DIR/$fw_file

Please extract firmware from Windows and copy to backup directory."
        fi
    done

    # Check if at least one kernel with headers is installed
    local has_kernel=false
    for kdir in /lib/modules/*/build; do
        if [ -d "$kdir" ]; then
            has_kernel=true
            break
        fi
    done

    if [ ! "$has_kernel" = true ]; then
        error_exit "No kernel headers found. Please install linux-headers:
  sudo pacman -S linux-headers"
    fi
}

build_modules_for_kernel() {
    local KVER="$1"
    local KDIR="/lib/modules/$KVER/build"
    local UPDATES_DIR="/lib/modules/$KVER/updates"

    log "Building modules for kernel $KVER"

    # Create updates directory if needed
    mkdir -p "$UPDATES_DIR"

    # Clean previous build artifacts
    cd "$SOURCE_DIR"
    make -C "$KDIR" M="$SOURCE_DIR" clean 2>/dev/null || true

    # Build modules for this kernel version
    if make -C "$KDIR" M="$SOURCE_DIR" modules >> "$LOG_FILE" 2>&1; then
        log "Build successful for $KVER"

        # Copy modules to updates directory
        for module in "${MODULE_FILES[@]}"; do
            if [ -f "$SOURCE_DIR/$module" ]; then
                cp "$SOURCE_DIR/$module" "$UPDATES_DIR/"
                log "  Installed: $module"
            else
                log "  WARNING: Module not found after build: $module"
            fi
        done

        # Update module dependencies
        depmod "$KVER"
        log "Modules installed and dependencies updated for $KVER"
        return 0
    else
        log "ERROR: Build failed for $KVER (check log for details)"
        return 1
    fi
}

# linux-firmware-mediatek has shipped BT_RAM_CODE_MT7902_1_1_hdr.bin.zst since
# the 2026-06 release. The kernel firmware loader tries the plain .bin before
# the packaged .bin.zst, so restoring the Windows-extracted blob here silently
# shadows the official firmware -- and does so again after every kernel or
# linux-firmware update, which makes the shadowing very hard to notice.
# Verified 2026-08-03 on kernel 7.1.5: the official blob (build 20250826211444)
# is 14 months newer than the Windows one (20240611180935) and works.
official_bt_firmware_present() {
    [ -f "$FIRMWARE_DIR/BT_RAM_CODE_MT7902_1_1_hdr.bin.zst" ] || \
    [ -f "$FIRMWARE_DIR/BT_RAM_CODE_MT7902_1_1_hdr.bin.xz" ]
}

restore_firmware() {
    log "Restoring firmware files"

    # Ensure firmware directory exists
    mkdir -p "$FIRMWARE_DIR"

    # Copy firmware files from backup
    for fw_file in "${FIRMWARE_FILES[@]}"; do
        if [ "$fw_file" = "BT_RAM_CODE_MT7902_1_1_hdr.bin" ] && official_bt_firmware_present; then
            log "  Skipped: $fw_file (provided by linux-firmware, not shadowing it)"
            continue
        fi

        if [ -f "$BACKUP_DIR/$fw_file" ]; then
            cp -f "$BACKUP_DIR/$fw_file" "$FIRMWARE_DIR/"
            log "  Restored: $fw_file"
        else
            log "  WARNING: Firmware file not found in backup: $fw_file"
        fi
    done
}

#############################################################################
# Main Script
#############################################################################

log "=== Starting MT7902 Bluetooth module rebuild ==="

# Validate environment and prerequisites
validate_environment

# Find all installed kernel versions that have build directories (headers installed)
build_count=0
skip_count=0

for KDIR in /lib/modules/*/build; do
    [ -d "$KDIR" ] || continue

    KVER=$(basename $(dirname "$KDIR"))
    UPDATES_DIR="/lib/modules/$KVER/updates"

    # Check if modules already exist for this kernel
    all_modules_exist=true
    for module in "${MODULE_FILES[@]}"; do
        if [ ! -f "$UPDATES_DIR/$module" ]; then
            all_modules_exist=false
            break
        fi
    done

    if [ "$all_modules_exist" = true ]; then
        log "Modules already exist for $KVER, skipping"
        # Plain assignment, not ((skip_count++)): a post-increment from 0
        # returns exit status 1, which `set -e` treats as a fatal error.
        skip_count=$((skip_count + 1))
        continue
    fi

    # Build modules for this kernel
    if build_modules_for_kernel "$KVER"; then
        # Plain assignment, not ((build_count++)): a post-increment from 0
        # returns exit status 1, which `set -e` treats as a fatal error.
        build_count=$((build_count + 1))
    fi
done

# Restore firmware files
restore_firmware

# Summary
log "=== Bluetooth module rebuild complete ==="
log "Summary: Built for $build_count kernel(s), skipped $skip_count kernel(s)"

exit 0
