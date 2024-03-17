#!/bin/bash

set -eu

# This script should be executed on aosp work dicrectory.
# - - -
# This script is a maintenance tool for creating patches.
# 1. Fetch the android repository.
# 2. Copy and edit the files that make the difference. For example,
#    if system/bt/hci/src/hci_layer.cc needs change, copy the file to 
#    system/bt/hci/src/hci_layer.cc.patched and edit hci_layer_cc.patched.
# 3. run bash ../../src/patches/make_patch.sh

BASEDIR=$(cd $(dirname $0); pwd)
WORKDIR=$PWD

PATCHNAME=android-99.patch
MOD_SUFFIX=.patched
REMOVE_PATCHFILE=

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
    --android)
    PATCHNAME=android-$2.patch
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
