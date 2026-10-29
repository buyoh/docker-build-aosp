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

if [[ -z "$ARG_ARCH" ]]; then
  export ARG_ARCH=arm64
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

export ALLOW_NINJA_ENV=1

if [[ -n $ARG_RPI ]]; then
  LUNCH_CHOICE=rpi4_tv-userdebug
else
  LUNCH_CHOICE=aosp_cf_x86_64_tv-trunk_staging-eng
fi
