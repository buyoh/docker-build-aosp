export ANDROID_VERSION=11
export BRANCH_AOSP_PLATFORM=android-11.0.0_r37
export BRANCH_ANDROID_RPI=arpi-11

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
