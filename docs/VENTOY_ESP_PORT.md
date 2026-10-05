# Local ESP port — implementation status

## Scope

Baseline: `029a0a9d16553f514f9f71ccea1ead4eebde88b8`.
Fork: https://github.com/mysdia/Ventoy
Branch: `ventoy-esp`.
Target: x86_64 UEFI, Secure Boot OFF, `/EFI/Ventoy` and `/ventoy-local`.
User explicitly changed the plan: this is a local-only fork; USB layout compatibility is not a requirement.

## Changes implemented (not yet compiled)

- Embedded GRUB bootstrap prefers the EFI loaded filesystem (`cmdpath`), then searches a local-specific marker.
- Runtime paths are independent of image paths; existing `vtoy_path` and `vtoy_efi_part` receive the relocated runtime root.
- Local mode bypasses upstream partition order, 32MiB, VTOYEFI label and private MBR checks.
- Runtime file availability is still checked; no marker-content, FAT-label or partition-number validation.
- Browser does not hide partition 2 on the runtime disk in local mode.
- Optional `grub/local-esp.cfg` can set `vtoy_image_uuid` for the initial image filesystem.
- Local menu provides an explicit disk-browser entry when the initial filesystem has no images.
- Build script compiles patched GRUB 2.04 only, reuses tracked upstream runtime binaries, and packages `INSTALL_LOCAL_ESP`.
- EFI/Ventoy/BOOTX64.EFI is patched GRUB itself, not the upstream Secure Boot shim.
- Dedicated GitHub Actions workflow builds on Ubuntu 22.04 and uploads package and logs.

## Dependency map

| File | Behavior | Local port action |
| --- | --- | --- |
| GRUB2/MOD_SRC/grub-2.04/install.sh | x64 prefix `(,2)/grub` | embedded bootstrap, `/ventoy-local/grub` |
| INSTALL/grub/grub.cfg | derives runtime p2 and image p1 from boot disk | explicit local runtime branch |
| GRUB2/MOD_SRC/grub-2.04/grub-core/ventoy/ventoy_cmd.c | `ventoy_load_part_table` invokes official disk check | local runtime file check instead |
| GRUB2/MOD_SRC/grub-2.04/grub-core/ventoy/ventoy_def.h | VTOY_CMD_CHECK requires p2 size 32MiB | local mode exempt |
| GRUB2/MOD_SRC/grub-2.04/grub-core/ventoy/ventoy_browser.c | hides p2 on boot disk | local mode shows all partitions |
| GRUB2/MOD_SRC/grub-2.04/grub-core/ventoy/ventoy_linux.c | cpio loads from explicit runtime argument | reuse existing interface |

## Known unfinished dependencies

Do not deploy to real ESP yet. Compilation and VM boot are NOT verified.

- `ventoy_get_disk_guid` reads a Ventoy private UUID at MBR offset 0x180 rather than a GPT disk GUID. Ordinary GPT disks may have zero bytes there. Linux initramfs and Windows helpers must be audited together before changing this identity format.
- Linux initramfs has further original-layout assumptions. Reaching the menu is not proof that Linux ISO boot works.
- Windows/Unix boot paths and auxiliary tools require separate validation; no compatibility claim is made.
- `localboot.cfg` searches Windows partitions using upstream ordering assumptions.
- Baseline upstream build, QEMU/OVMF layout A/B/C/D tests and an actual Linux ISO boot remain pending.
- Safe install/uninstall tooling must wait until VM boot passes, as required by the original plan.

## Current remote blocker

The supplied PAT can read repository metadata, but both Git push and REST ref creation return HTTP 403.
REST message: `Resource not accessible by personal access token`.
Required fine-grained repository permissions: Contents read/write, Workflows read/write (workflow changes), Actions read/write (dispatch/manage).
No credential is stored in repository files or Git remote configuration.
