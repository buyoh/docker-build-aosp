#!/bin/bash

set -eux

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/preprocess.sh

# ==============================================================================
# Apply patches

if [[ -z "$ARG_RPI" ]]; then
  echo "Patches are only available for RPI."
  exit 1
fi

$SCRIPTDIR/patches/patcher.sh --android $ANDROID_VERSION
