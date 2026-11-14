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
- src/check-upstream.sh
  - Check if the upstream has been updated. See [UPSTREAM.md](UPSTREAM.md).

## Requirements

- Docker (rootless)
- Python 3.8 or later on the host. `build-aosp.sh` is a wrapper of `src/build_aosp.py`.
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
  - Android 12 and 14 support is ongoing. See test.md for the tested status.
- Enabling wifi causes crashes.
  - RPi 4 has an ethernet adapter so we can use it.
- Supporting arm / arm32

## 

Based on:
- https://github.com/android-rpi/device_arpi_rpi4 (See [UPSTREAM.md](UPSTREAM.md) for the followed upstream and intentional deviations)
- devenv-docker
