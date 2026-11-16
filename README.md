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
- src/check-upstream.sh
  - Check if the upstream has been updated. See [UPSTREAM.md](UPSTREAM.md).

## Requirements

- Docker (rootless)
- Python 3.8 or later on the host. `build-aosp.sh` and `run-aosp.sh` are
  wrappers of `src/build_aosp.py` and `src/run_aosp.py`.
- PyYAML on the host, only to use `--config` (`sudo apt install python3-yaml`
  or `pip install pyyaml`). With `sudo ./build-aosp.sh`, `/usr/bin/python3` is
  used, so PyYAML installed by pip for the user is not visible.

## Hands on

First you need to create a docker image (for example, `env-aosp/focal`):

```sh
$ ./setup-dockerimage.sh --apt-country jp
```

Next, fetch the AOSP repository and build them.
If you don't use rootless docker, add `--adduser` (deprecated).

```sh
$ mkdir -p var && mkdir -p out
$ ./build-aosp.sh --rpi --android 11 --arch arm --mount-same \
     --workdir ~/work/aosp/var --outdir ~/work/aosp/out \
     fetch patch build
```

Android 14 for RPi 4 supports only arm64.

```sh
$ ./build-aosp.sh --rpi --android 14 --arch arm64 \
     --workdir ~/work/aosp/var --outdir ~/work/aosp/out \
     fetch patch build
```

By default, `out` in the AOSP source directory is a symlink to
`<workdir>/gen/out.<arch>`. If `out` is a real directory (e.g. it was built
without this tool), the tasks stop. Add `--no-gen` to use the `out` directory
as it is.

With `--daemon`, the container runs in background and the console output is
written to `<outdir>/console-<timestamp>.log`. The container is removed after
it exits, so the exit status is written at the end of the log
(`exit status: <code>`).

### Config file

The parameters can be written in a YAML file instead of the command line.
See [build-aosp.example.yaml](build-aosp.example.yaml) for the keys and their
descriptions. Command line options override the values in the file.

```sh
$ cp build-aosp.example.yaml build-aosp.yaml   # and edit it
$ ./build-aosp.sh --config build-aosp.yaml fetch patch build
$ ./build-aosp.sh --config build-aosp.yaml --print-config   # show the resolved values
```

Each run writes the resolved configuration to
`<outdir>/build-config-<timestamp>.json` as a record.

### Form factors and platforms

Android 14 can be built for TV, phone and automotive (`--form-factor`), and
for Raspberry Pi 4, cuttlefish and the Android Emulator (`--platform`).
`--rpi` is the same as `--platform rpi4`.

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

- Raspberry Pi 4 supports only TV. For phone and automotive, use cuttlefish
  or the emulator.
- Use different `--workdir` for RPi and the others. The AOSP tags differ
  (RPi: android-14.0.0_r17, the others: android-14.0.0_r74).
- `patch` is required for `--platform emulator --form-factor tv`. It adds the
  sample home app (TvSampleLeanbackLauncher) to `sdk_atv_x86`. Run
  `patch-revert` before changing the AOSP tag by `fetch`, as for RPi.
- Android 14 for cuttlefish and the emulator supports only `--arch x86_64`
  (default). Before this change, the default arch of them was arm64 and the
  outputs were built in `<workdir>/gen/out.arm64`. To reuse it, rename it to
  `<workdir>/gen/out.x86_64` while no build is running.
- Android 10-12 support only the default (RPi: `rpi4`/`tv`, the others:
  `emulator`/`phone`).
- The output directory gets a suffix for each non-default value, e.g.
  `<outdir>/android-14-x86_64-emulator-auto`. Each one uses several GB.
  Remove unused ones by yourself.
- Switching the form factor or the platform in the same workdir rebuilds the
  differences (installclean of the product directory). The TV emulator is
  32-bit x86, so switching to it rebuilds more.
- Stop the running device (`run-aosp.sh --stop`) before building to the same
  output directory.

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

### SD card image for Raspberry Pi

Finally make image via outputs

```sh
$ ./make-image.sh --outdir ~/work/aosp/out -t android-11-arm
$ ls ~/work/aosp/out/*.img
```

The size of `/data` partition is 4096 MiB by default. Use `--data-size <MiB>`
to change it.

## Directories

- src
  - scripts and patches
- work
  - working directory for AOSP
- out
  - build outputs
- base
  - Dockerfile
- tests
  - tests for scripts (`bash tests/run-tests.sh`). The python tests are in
    `tests/py`. `TEST_IN_IMAGE=1` also runs them with the python of the
    docker image.

## Limitation

- AOSP 10, 11, 12 and 14 are supported.
  - The form factors other than TV, cuttlefish and the emulator are only for
    Android 14. Raspberry Pi supports only TV.
  - Android 12 and 14 support is ongoing. See test.md for the tested status.
- Enabling wifi causes crashes.
  - RPi 4 has an ethernet adapter so we can use it.
- Supporting arm / arm32

## 

Based on:
- https://github.com/android-rpi/device_arpi_rpi4 (See [UPSTREAM.md](UPSTREAM.md) for the followed upstream and intentional deviations)
- devenv-docker
