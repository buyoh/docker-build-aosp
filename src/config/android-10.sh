export ANDROID_VERSION=10
export BRANCH_AOSP_PLATFORM=android-10.0.0_r41
export BRANCH_ANDROID_RPI=arpi-10

if [[ -z "$ARG_ARCH" ]]; then
  export ARG_ARCH=arm
fi

if [[ "$ARG_ARCH" == arm ]]; then
  export ARCH=arm
  export CROSS_COMPILE=arm-linux-gnueabihf-
elif [[ "$ARG_ARCH" == arm64 ]]; then
  export ARCH=arm64
  export CROSS_COMPILE=aarch64-linux-gnu-
fi
