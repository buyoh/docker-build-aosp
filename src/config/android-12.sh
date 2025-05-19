export ANDROID_VERSION=12
export BRANCH_AOSP_PLATFORM=android-12.1.0_r21
export BRANCH_ANDROID_RPI=arpi-12
export BRANCH_KERNEL_RPI=arpi-5.10

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
fi

export ALLOW_NINJA_ENV=1
