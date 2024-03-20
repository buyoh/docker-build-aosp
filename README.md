# aosp-rpi

Build AOSP for Raspberry Pi 4 on the docker environment

## Scripts

- setup-dockerimage.sh
  - Make and setup docker images for building AOSP.
- build-aosp.sh
  - Fetch and build AOSP for RPi 4 on docker.
- make-image.sh
  - Make a SD card image from build output files.
  - `out/aosp10-rpi.img` will be generated.

## Hands on

First we need to create a docker image:

```sh
$ ./setup-dockerimage.sh --apt-country jp
```

Next, fetch the AOSP repository and build them.

```sh
$ mkdir -p var && mkdir -p out
$ ./build-aosp.sh --android 11 --arch arm --label android11 \
     --workdir ~/work/aosp/var --outdir ~/work/aosp/out \
     fecth build
```

If you don't use rootless docker, add `--adduser`.

```sh
$ mkdir -p var && mkdir -p out
$ sudo ./build-aosp.sh --android 11 --arch arm --label android11 \
     --workdir ~/work/aosp/var --outdir ~/work/aosp/out --adduser \
     fecth build
```

Finally make image via outputs

```sh
$ ./make-image.sh --outdir ~/work/aosp/out -t android-11-arm
$ ls ~/work/aosp/out/*.img
```

## Directories

- src
  - scripts and patches
- work
  - working directory for AOSP
- out
  - build outputs
- base
  - Dockerfile
- user
  - Dockerfile

## Limitation

- Only AOSP 10, 11 supported.
  - Android 12 support is ongoing...
- Enabling wifi causes crashes.
  - RPi 4 has an ethernet adapter so we can use it.
- Supporting arm / arm32

## 

Based on:
- https://github.com/android-rpi/device_arpi_rpi4/tree/arpi-10
- devenv-docker
