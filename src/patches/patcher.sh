#!/bin/bash

set -eu

# This script should be executed on aosp work dicrectory.

BASEDIR=$(cd $(dirname $0); pwd)
WORKDIR=$PWD

PATCHNAME=android-10.patch
REVERTFLG=
# REVERTFLG=-R
MODE_MAKE_PATCHED=no

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
  -R|--revert)
  REVERTFLG=-R
  ;;
  --android)
  PATCHNAME=android-$2.patch
  shift
  ;;
  --make-patched)
  # The result will be same as make_patch.sh input format
  # NOT TESTED
  MODE_MAKE_PATCHED=yes
  shift
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


pushd $BASEDIR > /dev/null

for PATCHFILE in $(find . -name "*$PATCHNAME"); do
  PATCHDIR=$(dirname $PATCHFILE)
  if [[ ! -d $WORKDIR/$PATCHDIR ]]; then
    echo "$WORKDIR/$PATCHDIR does not exist"
    continue
  fi 

  pushd $WORKDIR/$PATCHDIR > /dev/null
  if [[ $MODE_MAKE_PATCHED == "yes" ]]; then
    SIMPLE_BACKUP_SUFFIX=.patched.orig patch -p0 -N $REVERTFLG < $BASEDIR/$PATCHFILE ||:
    for L_ORIGFILE in $(find . -name "*.patched.orig"); do
      L_BASEFILE=${L_ORIGFILE%".patched.orig"}
      mv $L_BASEFILE $L_BASEFILE.patched
      mv $L_BASEFILE.patched.orig $L_BASEFILE
    done
  else
    patch -p0 -N $REVERTFLG < $BASEDIR/$PATCHFILE ||:
  fi
  popd > /dev/null
  echo "applied: $PATCHFILE"
done

popd > /dev/null
