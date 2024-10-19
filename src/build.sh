#!/bin/bash

set -eux

# We never push commits
git config --global user.email "user@example.com"
git config --global user.name "user.name"

SCRIPTDIR=$(cd $(dirname $0) && pwd)

source $SCRIPTDIR/config/android-$ARG_ANDROID_VERSION.sh
OUTDIR=/mnt/out/android-$ARG_ANDROID_VERSION-$ARCH
mkdir -p $OUTDIR

cd /mnt/work
mkdir -p /mnt/gen/out.$ARCH
rm out ||:
ln -s /mnt/gen/out.$ARCH/ out

# ==============================================================================
# Build kernel

if [[ $ANDROID_VERSION -le 11 ]]; then
  cd kernel/arpi

  if [[ $ARCH == "arm" ]]; then
    scripts/kconfig/merge_config.sh \
      arch/$ARCH/configs/bcm2711_defconfig \
      kernel/configs/android-base.config \
      kernel/configs/android-recommended.config
    make zImage
    make dtbs
  elif [[ $ARCH == "arm64" ]]; then
    scripts/kconfig/merge_config.sh \
      arch/$ARCH/configs/bcm2711_defconfig \
      kernel/configs/android-base.config \
      kernel/configs/android-recommended.config
    make Image.gz
    DTC_FLAGS="-@" make broadcom/bcm2711-rpi-4-b.dtb
    DTC_FLAGS="-@" make overlays/vc4-kms-v3d-pi4.dtbo
  else
    echo "error: unknown pattern: android-version=$ANDROID_VERSION, arch=$ARCH"
    exit 1
  fi
  cd -
fi

# ==============================================================================
# Build

set +u
source build/envsetup.sh
lunch rpi4-eng
if [[ $ANDROID_VERSION -eq 12 ]]; then
  export ALLOW_NINJA_ENV=1  # TODO: can be removed?
fi
make ramdisk systemimage vendorimage
set -u

# ==============================================================================
# Build kernel

if [[ $ANDROID_VERSION -eq 12 ]]; then
  cd /mnt/kernel_work
  mkdir -p /mnt/kernel_gen/out.$ARCH
  rm out ||:
  ln -s /mnt/kernel_gen/out.$ARCH/ out

  set +u
  build/build.sh
  set -u

  cd -
fi

# ==============================================================================
# Copy outputs

set -x

cp ./out/target/product/rpi4/system.img $OUTDIR
cp ./out/target/product/rpi4/vendor.img $OUTDIR

rm -rf $OUTDIR/boot
mkdir -p $OUTDIR/boot
mkdir -p $OUTDIR/boot/overlays


if [[ $ANDROID_VERSION -eq 12 ]]; then
    cp \
      /mnt/kernel_work/out/arpi-5.10/dist/Image.gz \
      /mnt/kernel_work/out/arpi-5.10/dist/bcm2711-rpi-*.dtb \
      $OUTDIR/boot
    cp \
      /mnt/kernel_work/out/arpi-5.10/dist/vc4-kms-v3d-pi4.dtbo \
      $OUTDIR/boot/overlays

else
  if [[ $ARCH == "arm" ]]; then
    cp \
      ./device/arpi/rpi4/boot/* \
      ./kernel/arpi/arch/$ARCH/boot/zImage \
      ./kernel/arpi/arch/$ARCH/boot/dts/bcm2711-rpi-4-b.dtb \
      ./out/target/product/rpi4/ramdisk.img \
      $OUTDIR/boot
    cp \
      ./kernel/arpi/arch/$ARCH/boot/dts/overlays/vc4-kms-v3d-pi4.dtbo \
      $OUTDIR/boot/overlays

  elif [[ $ARCH == "arm64" ]]; then
    cp \
      ./device/arpi/rpi4/boot/* \
      ./kernel/arpi/arch/$ARCH/boot/Image.gz \
      ./kernel/arpi/arch/$ARCH/boot/dts/broadcom/bcm2711-rpi-4-b.dtb \
      ./out/target/product/rpi4/ramdisk.img \
      $OUTDIR/boot
    cp \
      ./kernel/arpi/arch/$ARCH/boot/dts/overlays/vc4-kms-v3d-pi4.dtbo \
      $OUTDIR/boot/overlays
  fi
fi