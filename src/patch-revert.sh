#!/bin/bash

set -eux

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/preprocess.sh

# ==============================================================================
# Apply patches

if [[ -n "$ARG_RPI" ]]; then
  $SCRIPTDIR/patches/patcher.sh -R --android $ANDROID_VERSION
elif [[ $ANDROID_VERSION -ge 14 ]]; then
  # The generic patch set for non-RPi. The source tree is shared by
  # cuttlefish and emulator, so it is applied regardless of the platform.
  $SCRIPTDIR/patches/patcher.sh -R --set generic --android $ANDROID_VERSION
else
  echo "Patches are only available for RPI or Android 14."
  exit 1
fi
