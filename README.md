# aosp-rpi

Build AOSP for Raspberry Pi 4 on the docker environment

## Scripts

- setup-dockerimage.sh
  - Make and setup docker images for building AOSP.
- build-aosp.sh
  - Fetch and build AOSP for RPi 4 on docker.
- make-image.sh
  - Make a SD card image from build output files.
  - `<outdir>/android-<version>-<arch>.img` will be generated.
- src/check-upstream.sh
  - Check if the upstream has been updated. See [UPSTREAM.md](UPSTREAM.md).

## Hands on

First we need to create a docker image:

```sh
$ ./setup-dockerimage.sh --apt-country jp
```

Next, fetch the AOSP repository and build them.

```sh
$ mkdir -p var && mkdir -p out
$ ./build-aosp.sh --rpi --android 11 --arch arm --mount-same \
     --workdir ~/work/aosp/var --outdir ~/work/aosp/out \
     fetch patch build
```

If you don't use rootless docker, add `--adduser`.

```sh
$ mkdir -p var && mkdir -p out
$ sudo ./build-aosp.sh --rpi --android 11 --arch arm --mount-same \
     --workdir ~/work/aosp/var --outdir ~/work/aosp/out --adduser \
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
  - tests for scripts (`bash tests/run-tests.sh`)

## Limitation

- AOSP 10, 11, 12 and 14 are supported.
  - Android 12 and 14 support is ongoing. See test.md for the tested status.
- Enabling wifi causes crashes.
  - RPi 4 has an ethernet adapter so we can use it.
- Supporting arm / arm32

## 

Based on:
- https://github.com/android-rpi/device_arpi_rpi4 (See [UPSTREAM.md](UPSTREAM.md) for the followed upstream and intentional deviations)
- devenv-docker
