# Upstream conformance

This tool follows the build procedure of
[android-rpi/device_arpi_rpi4](https://github.com/android-rpi/device_arpi_rpi4).
This document records which upstream is followed and where this tool
intentionally differs from it.

## Followed upstream

| Android | device_arpi_rpi4 | local_manifests | kernel_manifest | Wiki patch |
|---|---|---|---|---|
| 14 | [arpi-14](https://github.com/android-rpi/device_arpi_rpi4/tree/arpi-14) | [arpi14-pi4](https://github.com/android-rpi/local_manifests/tree/arpi14-pi4) | [arpi14-6.1.62](https://github.com/android-rpi/kernel_manifest/tree/arpi14-6.1.62) | none |
| 12 | [arpi-12](https://github.com/android-rpi/device_arpi_rpi4/tree/arpi-12) | [arpi-12](https://github.com/android-rpi/local_manifests/tree/arpi-12) | [arpi-5.10](https://github.com/android-rpi/kernel_manifest/tree/arpi-5.10) | [arpi-12](https://github.com/android-rpi/device_arpi_rpi4/wiki/arpi-12-:-framework-patch) |
| 11 | [arpi-11](https://github.com/android-rpi/device_arpi_rpi4/tree/arpi-11) | [arpi-11](https://github.com/android-rpi/local_manifests/tree/arpi-11) | none | [arpi-11](https://github.com/android-rpi/device_arpi_rpi4/wiki/arpi-11-:-framework-patch) |
| 10 | [arpi-10](https://github.com/android-rpi/device_arpi_rpi4/tree/arpi-10) | [arpi-10](https://github.com/android-rpi/local_manifests/tree/arpi-10) | none | [arpi-10](https://github.com/android-rpi/device_arpi_rpi4/wiki/arpi-10-:-framework-patch) |

The revisions of the upstream are recorded in:

- `src/manifests/android-<version>-pinned.xml`,
  `src/manifests/android-<version>-kernel-pinned.xml` and
  `src/manifests/android-<version>.meta` (not created yet)
- `UPSTREAM_WIKI_REV` in `src/config/upstream.sh`

## Deviations

| ID | Android | Upstream | This tool | Reason | Managed in |
|---|---|---|---|---|---|
| D1 | 14 | `lunch rpi4-eng` | `rpi4_tv-userdebug` (Android TV product, 1920x1080) | Android TV is a purpose of this tool. userdebug is for `adb root`. | `src/patches/android-14.patch`, `LUNCH_CHOICE` in `src/config/android-14.sh` |
| D2 | 14 | BoardConfig: system 1152MiB / vendor 128MiB / userdata 128MiB | 2048MiB / 256MiB / 256MiB | To avoid a build error. A later build (rpi4_tv-userdebug) uses about 1060MiB of system and 59MiB of vendor, so re-check whether it is still needed when following the upstream. The userdata value does not affect the size of p4. | `src/patches/android-14.patch` |
| D3 | 14 | No patch | Comment out `product_variables.pdk` in 3 files of frameworks/av | Unknown. `Pdk` is defined in soong of r17, so an undefined variable is not the reason. It may be unnecessary. | `src/patches/android-14.patch` |
| D4 | 14 | No patch | Add `"ninja": Log` to `paths/config.go` of soong | `external/mesa3d/android/mesa3d_cross.mk` runs ninja of the host, so it must be allowed in the path sandbox. Used with `ALLOW_NINJA_ENV=1`. | `src/patches/android-14.patch` |
| D5 | 14 | None | `SKIP_ABI_CHECKS=true` | The ABI dump of libcrypto does not match on Debian/Ubuntu hosts and the build fails. | `src/build.sh` |
| D6 | All | Install packages on the host | Build in docker (ubuntu focal, pinned digest). setuptools comes from get-pip.py. | Keep the host clean and make the build reproducible. | `base/Dockerfile` |
| D7 | 10, 11 | 10 is arm and 11 is arm64 | `--arch` also accepts arm64 for 10 and arm for 11 | Experimental. Not tested. | `src/config/android-10.sh`, `src/config/android-11.sh` |
| D8 | All | Partition the SD card by hand with fdisk | `make-image.sh` generates an image file. p2 and p3 are as large as system.img and vendor.img. p4 is `--data-size` MiB and does not grow to the card size (use growpart and resize2fs after writing if needed). `system` / `vendor` labels are added. | Automation. The labels are harmless. "mkfs.vfat -n" of the 10/11 README is read as an instruction for a vfat /data, which is not used here. | `make-image.sh` |
| D9 | 10, 11, 12 | Wiki deletes lines | `android-*.patch` comment out `emplace(...)` and `compile_multilib` instead of deleting them | Equivalent result. Changed lines stay visible. | `src/patches/` |
| D10 | All | `repo init` / `repo sync` without options | `repo init --depth=1 --repo-rev=<pinned>`, `repo sync --force-sync -f`, remove `shallow.lock` | Reduce the download, pin the repo tool, and allow resuming after an interruption. | `src/fetch.sh` |

## Rules

- A commit that adds or changes a difference from the upstream updates the
  deviations table in the same commit.
- When following the upstream, remove deviations whose reason no longer holds.

## Following the upstream

`src/check-upstream.sh` needs python3 and access to GitHub on the host. It
does not need docker. It exits with 0 if up to date, 1 if the upstream has
been updated, 2 if nothing is recorded for the version (for now, all versions
because `src/manifests/` does not exist yet), and 3 if the upstream cannot be
accessed.

1. Run `./src/check-upstream.sh --android 14`.
2. Read the changes on the printed compare URLs (README, BoardConfig, boot
   files, frameworks_av, ...) and update this document.
3. To follow them, update the tree and build it. After confirming that it
   works, regenerate the pinned manifests and update `UPSTREAM_WIKI_REV`.
