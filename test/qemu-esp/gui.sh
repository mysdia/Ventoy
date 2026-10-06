#!/usr/bin/env bash
# Unmodified runtime, graphical output, explicit EFI/Ventoy chainload.
set -euo pipefail
cd "$(dirname "$0")/../.."
repo=$PWD
work=$(mktemp -d)
trap '[[ -z ${pid:-} ]] || kill "$pid" 2>/dev/null || true; rm -rf "$work"' EXIT
mkdir -p test-results
for part in 1 3; do
    mkdir -p "$work/stage/EFI/BOOT"
    cp -a INSTALL_LOCAL_ESP/. "$work/stage/"
    printf 'search --file --set=root /EFI/Ventoy/BOOTX64.EFI\nchainloader /EFI/Ventoy/BOOTX64.EFI\nboot\n' > "$work/launcher.cfg"
    # Stock GRUB is only a disposable firmware launcher, not the tested Ventoy.
    grub-mkstandalone -O x86_64-efi -o "$work/stage/EFI/BOOT/BOOTX64.EFI" "boot/grub/grub.cfg=$work/launcher.cfg"
    truncate -s 128M "$work/esp.img"
    mkfs.vfat -F32 "$work/esp.img"
    mcopy -s -i "$work/esp.img" "$work/stage"/* ::/
    truncate -s 256M "$work/disk.img"
    sgdisk --clear --new="$part:2048:+128M" --typecode="$part:ef00" "$work/disk.img"
    dd if="$work/esp.img" of="$work/disk.img" bs=512 seek=2048 conv=notrunc status=none
    cp /usr/share/OVMF/OVMF_VARS.fd "$work/vars.fd"
    qemu-system-x86_64 -machine q35,accel=tcg -m 512 \
        -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \
        -drive if=pflash,format=raw,file="$work/vars.fd" \
        -drive format=raw,file="$work/disk.img" -display none \
        -serial file:"$repo/test-results/gui-p$part.log" \
        -qmp unix:"$work/qmp",server=on,wait=off -monitor none -net none -no-reboot &
    pid=$!
    sleep 60
    python3 - "$work/qmp" "$repo/test-results/gui-p$part.ppm" <<'PY'
import json, socket, sys
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
f = s.makefile('rwb', buffering=0)
print(f.readline().decode())
def command(name, args=None):
    f.write((json.dumps({'execute': name, 'arguments': args or {}})+'\n').encode())
    while True:
        r = json.loads(f.readline())
        if 'error' in r: raise RuntimeError(r)
        if 'return' in r: return r
command('qmp_capabilities')
command('screendump', {'filename': sys.argv[2]})
command('quit')
PY
    wait "$pid"
    pid=
    rm -f "$work/qmp" "$work/disk.img" "$work/esp.img"
done
