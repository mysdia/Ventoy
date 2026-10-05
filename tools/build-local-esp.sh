#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
repo=$PWD
mkdir -p GRUB2/SRC GRUB2/NBP
if [[ ! -f GRUB2/grub-2.04.tar.xz ]]; then
    curl --fail --location --retry 3 https://ftp.gnu.org/gnu/grub/grub-2.04.tar.xz -o GRUB2/grub-2.04.tar.xz
fi
 
# Record the downloaded source hash in the build log.
sha256sum GRUB2/grub-2.04.tar.xz
tar -xf GRUB2/grub-2.04.tar.xz -C GRUB2/SRC
cp -a GRUB2/MOD_SRC/grub-2.04/. GRUB2/SRC/grub-2.04/
cd GRUB2/SRC/grub-2.04
./autogen.sh
./configure --target=x86_64 --with-platform=efi --prefix="$repo/GRUB2/INSTALL" --disable-werror
make -j"${JOBS:-4}"
bash install.sh uefi
cd "$repo"
rm -rf INSTALL_LOCAL_ESP
mkdir -p INSTALL_LOCAL_ESP/EFI/Ventoy INSTALL_LOCAL_ESP/ventoy-local
# Secure Boot OFF: load the patched GRUB directly, without the upstream shim chain.
cp INSTALL/EFI/BOOT/grubx64_real.efi INSTALL_LOCAL_ESP/EFI/Ventoy/BOOTX64.EFI
cp INSTALL/EFI/BOOT/grubx64_real.efi INSTALL_LOCAL_ESP/EFI/Ventoy/grubx64_real.efi
cp -a INSTALL/grub INSTALL/ventoy INSTALL/tool INSTALL_LOCAL_ESP/ventoy-local/
printf 'VENTOY_LOCAL_ESP_V1\n' > INSTALL_LOCAL_ESP/ventoy-local/ventoy/ventoy.esp.marker
find INSTALL_LOCAL_ESP -type f -print0 | sort -z | xargs -0 sha256sum > local-esp.sha256
printf 'commit=%s\n' "$(git rev-parse HEAD)" > local-esp-build.txt
gcc --version >> local-esp-build.txt
cat /etc/os-release >> local-esp-build.txt
tar -czf ventoy-local-esp-x86_64.tar.gz INSTALL_LOCAL_ESP local-esp.sha256 local-esp-build.txt
