export ANDROID_VERSION=14
if [[ -n $ARG_RPI ]]; then
  # https://github.com/android-rpi/local_manifests/tree/arpi14-pi4
  export BRANCH_AOSP_PLATFORM=android-14.0.0_r17
else
  export BRANCH_AOSP_PLATFORM=android-14.0.0_r74
fi
export BRANCH_ANDROID_RPI=arpi14-pi4
export BRANCH_KERNEL_RPI=arpi14-6.1.62
# The kernel output directory (out/<BRANCH>/dist), BRANCH is defined in build.config
KERNEL_DIST_DIR=arpi14-6.1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/platform.sh"

if [[ -z "$ARG_ARCH" ]]; then
  if [[ -n $ARG_RPI ]]; then
    export ARG_ARCH=arm64
  else
    export ARG_ARCH=x86_64
  fi
fi

if [[ "$ARG_ARCH" == arm ]]; then
  export ARCH=arm
  export CROSS_COMPILE=arm-linux-gnueabihf-
elif [[ "$ARG_ARCH" == arm64 ]]; then
  export ARCH=arm64
  export CROSS_COMPILE=aarch64-linux-gnu-
elif [[ "$ARG_ARCH" == x86_64 ]]; then
  export ARCH=x86_64
else
  echo "error: unsupported arch: $ARG_ARCH" >&2
  exit 2
fi

# The kernel and lunch target decide the actual arch since Android 12.
if [[ -n $ARG_RPI ]] && [[ "$ARG_ARCH" != arm64 ]]; then
  echo "error: Android 14 for RPi supports only arm64." >&2
  exit 2
fi

# The lunch targets of non-RPi are always x86. Do not build x86_64 in
# gen/out.arm64.
if [[ -z $ARG_RPI ]] && [[ "$ARG_ARCH" != x86_64 ]]; then
  echo "error: Android 14 for $ARG_PLATFORM supports only x86_64." >&2
  exit 2
fi

export ALLOW_NINJA_ENV=1

# The lunch targets by platform and form factor. The non-RPi tree is r74, so
# the release config is required. All non-RPi variants are eng to avoid
# relinking (docs-ai/info/form-factor-build/05).
case "$ARG_PLATFORM/$ARG_FORM_FACTOR" in
  rpi4/tv)          LUNCH_CHOICE=rpi4_tv-userdebug ;;
  cuttlefish/phone) LUNCH_CHOICE=aosp_cf_x86_64_phone-trunk_staging-eng ;;
  cuttlefish/tv)    LUNCH_CHOICE=aosp_cf_x86_64_tv-trunk_staging-eng ;;
  cuttlefish/auto)  LUNCH_CHOICE=aosp_cf_x86_64_auto-trunk_staging-eng ;;
  emulator/phone)   LUNCH_CHOICE=sdk_phone64_x86_64-trunk_staging-eng ;;
  # r74 has no x86_64 TV product for the emulator.
  emulator/tv)
    LUNCH_CHOICE=sdk_atv_x86-trunk_staging-eng
    # sdk_atv_x86 is 32-bit. NetBpfLoad (tethering APEX) rejects 32-bit
    # userspace on 6.2+ kernels and init reboots (reboot,bpfloader-failed).
    # Use the 6.1 GKI instead of the default 6.6 of goldfish
    # (docs-ai/done-task/emulator-tv-boot-loop). Keep it the same as
    # EMULATOR_TV_KERNEL of src/aosp_build/versions.py.
    export TARGET_KERNEL_USE=6.1
    ;;
  emulator/auto)    LUNCH_CHOICE=sdk_car_x86_64-trunk_staging-eng ;;
  *)
    # Only rpi4/phone and rpi4/auto reach here.
    echo "error: Android 14 for RPi supports only form factor: tv. Use --platform cuttlefish or emulator for $ARG_FORM_FACTOR with another --workdir (the AOSP tag differs from RPi)." >&2
    exit 2
    ;;
esac
