#!/bin/bash

set -eu

# This script should be executed on aosp work dicrectory.
# - - -
# This script is a maintenance tool for creating patches.
# 1. Fetch the android repository.
# 2. Copy and edit the files that make the difference. For example,
#    if system/bt/hci/src/hci_layer.cc needs change, copy the file to 
#    system/bt/hci/src/hci_layer.cc.patched and edit hci_layer_cc.patched.
# 3. Change current directory to the root of the repository and 
#    run bash /TOOLPATH/src/patches/make_patch.sh

BASEDIR=$(cd $(dirname $0); pwd)
WORKDIR=$PWD

PATCHSET=rpi
ANDROID_VER=99
MOD_SUFFIX=.patched
REMOVE_PATCHFILE=

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
    --android)
    ANDROID_VER=$2
    shift
    ;;
    --set)
    PATCHSET=$2
    shift
    ;;
    --mod-suffix)
    MOD_SUFFIX=$2
    shift
    ;;
    -D)
    REMOVE_PATCHFILE=yes
    ;;
    # --help|-h)
    # usage
    # exit 0
    # ;;
    *)
    echo "Unknow option "$arg
    exit 2
    ;;
esac
shift
done

case "$PATCHSET" in
  rpi) PATCHNAME=android-$ANDROID_VER.patch ;;
  generic) PATCHNAME=android-$ANDROID_VER-generic.patch ;;
  *)
  echo "Unknown patch set: $PATCHSET"
  exit 2
  ;;
esac

PATCHPATH=$BASEDIR/$PATCHNAME

rm -f $PATCHPATH

pushd $WORKDIR > /dev/null

for L_PATCHFILE in $(find . -name "*$MOD_SUFFIX"); do
  L_BASEFILE=${L_PATCHFILE%"$MOD_SUFFIX"}
  if [[ ! -e $L_BASEFILE ]]; then continue; fi
  echo $L_BASEFILE
  diff -U 5 \
    $L_BASEFILE --label $L_BASEFILE \
    $L_PATCHFILE --label $L_BASEFILE >> $PATCHPATH ||:
  if [[ $REMOVE_PATCHFILE == "yes" ]]; then
    rm $L_PATCHFILE ||:
  fi
done

popd > /dev/null
