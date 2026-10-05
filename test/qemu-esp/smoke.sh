#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
repo=$PWD
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p test-results
code=/usr/share/OVMF/OVMF_CODE.fd
vars=/usr/share/OVMF/OVMF_VARS.fd
[[ -f $code && -f $vars ]]
for esp_part in 1 3; do
    stage="$work/stage-$esp_part"
    mkdir -p "$stage"
    cp -a INSTALL_LOCAL_ESP/. "$stage/"
    # The disposable test disk uses the firmware fallback path for unattended boot.
    # The distributed package still installs exclusively to EFI/Ventoy.
    mkdir -p "$stage/EFI/BOOT"
    cp "$stage/EFI/Ventoy/BOOTX64.EFI" "$stage/EFI/BOOT/BOOTX64.EFI"
    cat > "$stage/ventoy-local/grub/local-esp.cfg" <<'CFG'
set vtoy_display_mode=serial_console
set vtoy_serial_param="--unit=0 --speed=115200"
serial --unit=0 --speed=115200
terminal_input serial console
terminal_output serial console
echo "[ESP-TEST] runtime=$vtoy_runtime_dev prefix=$prefix"
CFG
    # Test-only instrumentation after the normal initialization and image scan.
    python3 - "$stage/ventoy-local/grub/grub.cfg" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
s = s.replace('#Main menu', '''# Test-only runtime read probe, before the original main menu.
vt_load_file_to_mem "nodecompress" $vtoy_path/ventoy.cpio esp_test_cpio
if [ "$esp_test_cpio_size" -gt 0 ]; then
    echo "[ESP-TEST] CPIO_READ_OK size=$esp_test_cpio_size"
fi
if [ "$VTOY_CHKDEV_RESULT_STRING" = "0" ]; then
    echo "[ESP-TEST] LOCAL_INIT_OK"
fi
echo "[ESP-TEST] MENU_READY"
#Main menu''')
p.write_text(s)
PY
    truncate -s 128M "$work/esp-$esp_part.img"
    mkfs.vfat -F 32 "$work/esp-$esp_part.img"
    mcopy -s -i "$work/esp-$esp_part.img" "$stage"/* ::/
    truncate -s 256M "$work/disk-$esp_part.img"
    sgdisk --clear --new="$esp_part:2048:+128M" --typecode="$esp_part:ef00" "$work/disk-$esp_part.img"
    dd if="$work/esp-$esp_part.img" of="$work/disk-$esp_part.img" bs=512 seek=2048 conv=notrunc status=none
    cp "$vars" "$work/vars-$esp_part.fd"
    log="$repo/test-results/esp-p$esp_part.log"
    set +e
    timeout 75 qemu-system-x86_64 -machine q35,accel=tcg -m 512 \
        -drive if=pflash,format=raw,readonly=on,file="$code" \
        -drive if=pflash,format=raw,file="$work/vars-$esp_part.fd" \
        -drive format=raw,file="$work/disk-$esp_part.img" \
        -display none -serial stdio -monitor none -net none -no-reboot > "$log" 2>&1
    rc=$?
    set -e
    [[ $rc == 0 || $rc == 124 ]]
    grep -F "runtime=hd0,gpt$esp_part" "$log"
    grep -F '[ESP-TEST] CPIO_READ_OK' "$log"
    grep -F '[ESP-TEST] LOCAL_INIT_OK' "$log"
    grep -F '[ESP-TEST] MENU_READY' "$log"
    echo "PASS: ESP p$esp_part, no dedicated VTOYEFI partition"
done
