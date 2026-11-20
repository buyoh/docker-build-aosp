# aosp-rpi

Build AOSP on the rootless docker environment.

## Scripts

- setup-dockerimage.sh
  - Make and setup docker images for building AOSP.
- build-aosp.sh
  - Fetch and build AOSP on docker.
- make-image.sh
  - Make a SD card image from build output files.
  - `<outdir>/android-<version>-<arch>.img` will be generated.
- run-aosp.sh
  - Run the outputs for cuttlefish or the Android Emulator on the host.
- check-upstream.sh
  - Check if the upstream has been updated. See [UPSTREAM.md](UPSTREAM.md).

## Requirements

- Docker (rootless)
- Python 3.8 or later on the host. `build-aosp.sh` and `run-aosp.sh` are
  wrappers of `src/host/build_aosp.py` and `src/host/run_aosp.py`.

## Hands on

First you need to create a docker image (for example, `env-aosp/focal`):

```sh
$ ./setup-dockerimage.sh --apt-country jp
```

Next, prepare the working and output directories.
Copy the example configuration file, and edit it as needed.

```sh
$ mkdir -p ~/work/aosp/
$ cp build-aosp.example.ini ~/work/aosp/build-aosp.ini
$ cd ~/work/aosp/
$ mkdir -p var out
```

Next, fetch the AOSP repository and build them.
If you don't use rootless docker, add `--adduser` (deprecated).
With `--daemon`, the container runs in background.

```sh
$ ./build-aosp.sh --config ~/work/aosp/build-aosp.ini \
     fetch patch build
```

### SD card image for Raspberry Pi

Finally make image via outputs

```sh
$ ./make-image.sh --outdir ~/work/aosp/out -t android-14-arm
$ ls ~/work/aosp/out/*.img
```

The size of `/data` partition is 4096 MiB by default. Use `--data-size <MiB>`
to change it.

### Run AOSP on the host

If you built binaries for the emulator on the host, you can run them using `run-aosp.sh`.

```sh
$ run-aosp.sh --outdir out -t android-14-x86_64-emulator
```

## Limitation

- AOSP 10, 11, 12, 14 and 16 are supported.
  - The form factors other than TV, cuttlefish and the emulator are only for
    Android 14 and 16.
  - Android 16 supports only cuttlefish and the emulator. Raspberry Pi is not
    supported (android-rpi has no branch for Android 15 or later).
  - Android 12, 14 and 16 support is ongoing. See test.md for the tested
    status.
- Enabling wifi causes crashes.
  - RPi 4 has an ethernet adapter so we can use it.
- Supporting arm / arm32

## Info

### Form factors and platforms

Android 14 can be built for TV, phone and automotive (`--form-factor`), and
for Raspberry Pi 4, cuttlefish and the Android Emulator (`--platform`).

| `--form-factor` | `rpi4` | `cuttlefish` (default of non-RPi) | `emulator` |
|---|---|---|---|
| `tv` (default) | `rpi4_tv-userdebug` | `aosp_cf_x86_64_tv-trunk_staging-eng` | `sdk_atv_x86-trunk_staging-eng` (32-bit x86) |
| `phone` | not supported | `aosp_cf_x86_64_phone-trunk_staging-eng` | `sdk_phone64_x86_64-trunk_staging-eng` |
| `auto` | not supported | `aosp_cf_x86_64_auto-trunk_staging-eng` | `sdk_car_x86_64-trunk_staging-eng` |

```sh
$ ./build-aosp.sh --android 14 --platform cuttlefish --form-factor auto \
     --workdir ~/work/aosp/var-generic --outdir ~/work/aosp/out \
     fetch patch build
```

- Use different `--workdir` for RPi and the others. The AOSP tags differ
  (RPi: android-14.0.0_r17, the others: android-14.0.0_r74).
- `patch` is required for `--platform emulator --form-factor tv`. It adds the
  sample home app (TvSampleLeanbackLauncher) to `sdk_atv_x86`, and makes the
  list of the ramdisk kernel modules of goldfish fit the kernel in use. Run
  `patch-revert` before changing the AOSP tag by `fetch`, as for RPi.
- `sdk_atv_x86` is 32-bit, so the TV emulator uses the 6.1 kernel
  (`TARGET_KERNEL_USE=6.1`) instead of the default 6.6. With 6.6, bpfloader
  fails on 32-bit userspace and the device reboots in a loop. The other form
  factors and platforms keep their kernels.
- If the workdir was patched by an older version of this tool, run `patch`
  again after updating the tool (the old patch is "already applied", and the
  new goldfish patch is applied). Otherwise `build` of emulator/tv stops
  before make. The emulator/tv outputs built before this change (6.6 kernel)
  do not boot; run `build` again. `run-aosp.sh` re-extracts the updated zip
  and recreates the AVD, so `--wipe` is not needed.
- Before this change, the default arch of cuttlefish and the emulator of
  Android 14 was arm64 and the outputs were built in
  `<workdir>/gen/out.arm64`. To reuse it, rename it to
  `<workdir>/gen/out.x86_64` while no build is running.
- Each output directory (e.g. `<outdir>/android-14-x86_64-emulator-auto`) uses
  several GB. Remove unused ones by yourself.
- Switching the form factor or the platform in the same workdir rebuilds the
  differences (installclean of the product directory). The TV emulator is
  32-bit x86, so switching to it rebuilds more.
- Stop the running device (`run-aosp.sh --stop`) before building to the same
  output directory.

Android 16 (`android-16.0.0_r4`) has the same form factors and platforms
except `rpi4`. The release config is `bp4a` (the release of r4), not
`trunk_staging`: `sdk_atv_x86-bp4a-eng`, `aosp_cf_x86_64_tv-bp4a-eng` and so
on.

- `patch` is required for `--platform emulator --form-factor tv` as for 14.
  It adds only the home app and the IME: the upstream of 16 pins the 6.1
  kernel for the TV emulator, so the goldfish patch and `TARGET_KERNEL_USE`
  are not needed.
- To reuse a workdir of Android 14 for cuttlefish and the emulator, revert
  the patches of 14 with the version of 14 first: the patches are found by
  the version, and the goldfish patch exists only for 14.

  ```sh
  $ ./build-aosp.sh --android 14 --no-rpi --workdir <dir> --outdir <dir> patch-revert
  $ ./build-aosp.sh --android 16 --platform emulator --form-factor tv \
       --workdir <dir> --outdir <dir> fetch patch build
  ```
- Do not use a workdir of RPi (any version) for cuttlefish and the emulator.
  `fetch` fails for them if `.repo/local_manifests` (of RPi) exists in the
  workdir. This check applies to every android version.

The outputs of cuttlefish and the emulator are copied to the output directory
with `build-info.json`:

- cuttlefish: `images/` and `cvd-host_package.tar.gz`
- emulator: `sdk-repo-linux-system-images.zip`

### Run on the host

`run-aosp.sh` runs the outputs. The target is decided by the platform of the
build (`--target cf-host` for cuttlefish, `--target emulator` for the
emulator).

```sh
# cuttlefish (GPU: gfxstream by default, see --gpu-mode)
$ ./run-aosp.sh --outdir ~/work/aosp/out -t android-14-x86_64-auto --allow-remote
$ ./run-aosp.sh --outdir ~/work/aosp/out -t android-14-x86_64-auto --stop

# the Android Emulator (GPU: host)
$ ./run-aosp.sh --outdir ~/work/aosp/out -t android-14-x86_64-emulator-phone
```

- `--wipe` discards the previous userdata. The options after `--` are passed
  to `launch_cvd` or `emulator` (e.g. `-- --cpus=4 --memory_mb=8192`).
- The state of the device is kept in `<outdir>/<subdir>/run-<target>/`.
- cuttlefish requires `/dev/kvm` and `/dev/vhost-vsock` (the `kvm` group), the
  render node (`render` group) for the host GPU, and
  [cuttlefish-base](https://github.com/google/android-cuttlefish) for the
  network of the device (`cvdnetwork` group). The screen is
  `https://localhost:8443` (WebRTC). If gfxstream does not work, try
  `--gpu-mode drm_virgl` or `--gpu-mode guest_swiftshader`.
- **Security**: cuttlefish exposes adb on all interfaces (port 6520). On eng
  builds it is a root shell without authentication, and user / userdebug do
  not enable the authentication on cuttlefish either. `--allow-remote` is
  required to start. Use it only on a trusted network, or block the ports
  (6520, 8443 and 15550-15599) by a firewall.
- The emulator is found in `--emulator`, `$ANDROID_HOME`,
  `$ANDROID_SDK_ROOT`, `~/Android/Sdk` and `PATH` in this order. It runs in
  the foreground; close the window to stop it.
- To use the image on another PC, extract
  `sdk-repo-linux-system-images.zip` to
  `<sdk>/system-images/android-34/<tag>/` (`default`, `android-tv` or
  `android-automotive`) and create an AVD by the AVD Manager of Android Studio.

## References

Based on:
- https://github.com/android-rpi/device_arpi_rpi4 (See [UPSTREAM.md](UPSTREAM.md) for the followed upstream and intentional deviations)
- devenv-docker
