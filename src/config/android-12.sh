export ANDROID_VERSION=12
export BRANCH_AOSP_PLATFORM=android-12.1.0_r21
export BRANCH_ANDROID_RPI=arpi-12
export BRANCH_KERNEL_RPI=arpi-5.10
# The kernel output directory (out/<BRANCH>/dist), BRANCH is defined in build.config
KERNEL_DIST_DIR=arpi-5.10

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
  echo "error: Android 12 for RPi supports only arm64." >&2
  exit 2
fi

export ALLOW_NINJA_ENV=1

if [[ -n $ARG_RPI ]]; then
  LUNCH_CHOICE=rpi4-eng
else
  LUNCH_CHOICE=aosp_x86_64-eng
fi
