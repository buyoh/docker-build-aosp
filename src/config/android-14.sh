export ANDROID_VERSION=14
export BRANCH_AOSP_PLATFORM=android-14.0.0_r74
export BRANCH_ANDROID_RPI=arpi14-pi4
export BRANCH_KERNEL_RPI=arpi14-6.1.62

if [[ -z "$ARG_ARCH" ]]; then
  export ARG_ARCH=arm64
fi

if [[ "$ARG_ARCH" == arm ]]; then
  export ARCH=arm
  export CROSS_COMPILE=arm-linux-gnueabihf-
elif [[ "$ARG_ARCH" == arm64 ]]; then
  export ARCH=arm64
  export CROSS_COMPILE=aarch64-linux-gnu-
fi

export ALLOW_NINJA_ENV=1