#!/bin/bash

set -eux

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/preprocess.sh

# ==============================================================================
# Build kernel (Android <= 11)

if [[ $ANDROID_VERSION -le 11 ]]; then
  if [[ -n $ARG_RPI ]]; then
    # Build kernel for Raspberry Pi
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
fi

# ==============================================================================
# Build

# sdk_atv_x86 has no home app and does not boot without the generic patch
# (docs-ai/task/form-factor-and-run-targets/06).
if [[ "$ARG_PLATFORM/$ARG_FORM_FACTOR" == emulator/tv ]]; then
  L_SDK_ATV=device/google/atv/products/sdk_atv_x86.mk
  if [[ ! -f $L_SDK_ATV ]]; then
    echo "error: $L_SDK_ATV not found. Run the 'fetch' task." >&2
    exit 1
  fi
  if ! grep -q TvSampleLeanbackLauncher $L_SDK_ATV; then
    echo "error: emulator/tv requires the generic patch. Run the 'patch' task." >&2
    exit 1
  fi
  # The ramdisk modules of goldfish must fit the 6.1 kernel
  # (TARGET_KERNEL_USE of src/config/android-14.sh,
  # docs-ai/done-task/emulator-tv-boot-loop). Check the mark of the patch,
  # not the change itself, not to accept a manual change or an upstream one.
  L_GOLDFISH_KERNEL=device/generic/goldfish/board/kernel/x86_64.mk
  if [[ ! -f $L_GOLDFISH_KERNEL ]]; then
    echo "error: $L_GOLDFISH_KERNEL not found. Run the 'fetch' task." >&2
    exit 1
  fi
  if ! grep -q 'build-aosp-rpi' $L_GOLDFISH_KERNEL; then
    echo "error: emulator/tv requires the generic patch for $L_GOLDFISH_KERNEL. Run the 'patch' task." >&2
    exit 1
  fi
fi

set +u
source build/envsetup.sh  # TODO: OUT_DIR?
lunch $LUNCH_CHOICE
# Do not use get_build_var after this: lunch unsets BUILD_VAR_CACHE_READY and
# get_build_var refers to it, so it fails under set -u. lunch exports these.
PRODUCT_OUT_DIR=$ANDROID_PRODUCT_OUT
HOST_OUT_DIR=$ANDROID_HOST_OUT
if [[ -n $ARG_RPI ]]; then
  if [[ $ANDROID_VERSION -eq 14 ]]; then
    # The prebuilt ABI reference dump of libcrypto mismatches the build.
    # https://discussions.unity.com/t/major-bug-in-android-14-breaks-building-aosp-for-debian-ubuntu-users/931277/3
    # Skip ABI checks instead of regenerating the dumps in the source tree.
    export SKIP_ABI_CHECKS=true
  fi

  if [[ $ANDROID_VERSION -eq 14 ]]; then
    m -j $(nproc) ramdisk systemimage vendorimage
  else
    make -j $(nproc) ramdisk systemimage vendorimage
  fi
elif [[ $ANDROID_VERSION -ge 14 ]]; then
  # Keep the same as GENERIC_14_TARGETS in src/aosp_build/versions.py.
  case "$ARG_PLATFORM" in
    cuttlefish)
      # hosttar: cvd-host_package.tar.gz is not built by default.
      m droid hosttar
      ;;
    emulator)
      m droid emu_img_zip
      ;;
    *)
      echo "error: unknown platform: $ARG_PLATFORM" >&2
      exit 1
      ;;
  esac
else
# make -j $(nproc) emulator
m
fi
set -u

# ==============================================================================
# Build kernel (Android >= 12)

if [[ -n $ARG_RPI ]]; then
  if [[ $ANDROID_VERSION -ge 12 ]]; then
    cd /mnt/kernel_work
    if [[ "$ARG_NO_GEN" == "false" ]]; then
      if [[ -e out ]] && [[ ! -L out ]]; then
        echo "The 'out' directory already exists and is not a symlink."
        exit 1
      fi
      mkdir -p /mnt/kernel_gen/out.$ARCH
      if [[ -e out ]]; then
        rm out
      fi
      ln -s /mnt/kernel_gen/out.$ARCH/ out
    fi

    set +u
    build/build.sh
    set -u

    # KERNEL_DIST_DIR must match BRANCH in build.config of the kernel.
    if [[ ! -d out/$KERNEL_DIST_DIR/dist ]]; then
      echo "error: out/$KERNEL_DIST_DIR/dist not found. Check KERNEL_DIST_DIR." >&2
      exit 1
    fi

    cd -
  fi
fi

# ==============================================================================
# Copy outputs

set -x

# build-info.json is written after all copies succeed. run-aosp.sh uses it as
# the mark of a complete OUTDIR.
rm -f $OUTDIR/build-info.json

if [[ -n $ARG_RPI ]]; then
  cp ./out/target/product/rpi4/system.img $OUTDIR
  cp ./out/target/product/rpi4/vendor.img $OUTDIR

  rm -rf $OUTDIR/boot
  mkdir -p $OUTDIR/boot
  mkdir -p $OUTDIR/boot/overlays


  if [[ $ANDROID_VERSION -ge 12 ]]; then
    cp \
      ./device/arpi/rpi4/boot/* \
      ./out/target/product/rpi4/ramdisk.img \
      $OUTDIR/boot
    cp \
      /mnt/kernel_work/out/$KERNEL_DIST_DIR/dist/Image.gz \
      /mnt/kernel_work/out/$KERNEL_DIST_DIR/dist/bcm2711-rpi-*.dtb \
      $OUTDIR/boot
    cp \
      /mnt/kernel_work/out/$KERNEL_DIST_DIR/dist/vc4-kms-v3d-pi4.dtbo \
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

elif [[ $ANDROID_VERSION -ge 14 ]]; then
  case "$ARG_PLATFORM" in
    cuttlefish)
      # The images that launch_cvd needs are listed in required_images.
      # A command substitution in the list of "for" does not stop on failure
      # under set -e, so check the file first.
      if [[ ! -s $PRODUCT_OUT_DIR/required_images ]]; then
        echo "error: $PRODUCT_OUT_DIR/required_images not found or empty" >&2
        exit 1
      fi
      mapfile -t L_IMGS < $PRODUCT_OUT_DIR/required_images
      rm -rf $OUTDIR/images
      mkdir -p $OUTDIR/images
      for L_IMG in "${L_IMGS[@]}" android-info.txt; do
        cp --sparse=always $PRODUCT_OUT_DIR/$L_IMG $OUTDIR/images/
      done
      cp $HOST_OUT_DIR/cvd-host_package.tar.gz $OUTDIR/
      ;;
    emulator)
      cp $PRODUCT_OUT_DIR/sdk-repo-linux-system-images.zip $OUTDIR/
      ;;
  esac
else
  echo "warning: Copying results for non-RPI is not implemented." >&2
  echo "warning: The results are in out/target/product/ of the AOSP source directory." >&2
  echo "warning: It is <workdir>/gen/out.$ARCH/target/product/ on the host unless --no-gen is given." >&2
fi

# Android 10-12 for non-RPi copy nothing, so they have no build-info.json
# (run-aosp.sh must not accept them).
if [[ -n $ARG_RPI ]] || [[ $ANDROID_VERSION -ge 14 ]]; then
  cat > $OUTDIR/build-info.json <<EOT
{
  "schema": 1,
  "android_version": "$ANDROID_VERSION",
  "platform": "$ARG_PLATFORM",
  "form_factor": "$ARG_FORM_FACTOR",
  "arch": "$ARCH",
  "lunch_choice": "$LUNCH_CHOICE",
  "aosp_branch": "$BRANCH_AOSP_PLATFORM"
}
EOT
  echo "The outputs are in $OUTDIR"
fi