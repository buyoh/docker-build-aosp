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
elif [[ "$ARG_ARCH" == x86_64 ]]; then
  export ARCH=x86_64
else
  echo "error: unsupported arch: $ARG_ARCH" >&2
  exit 2
fi

if [[ -n $ARG_RPI ]] && [[ "$ARG_ARCH" == x86_64 ]]; then
  echo "error: Android 10 for RPi supports only arm and arm64." >&2
  exit 2
fi

if [[ -z $ARG_RPI ]]; then
  # TODO: Retest this
  ln -sf /usr/bin/python2 /usr/bin/python
fi

if [[ -n $ARG_RPI ]]; then
  LUNCH_CHOICE=rpi4-eng
else
  LUNCH_CHOICE=aosp_x86_64-eng
fi
