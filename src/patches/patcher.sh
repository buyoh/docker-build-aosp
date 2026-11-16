#!/bin/bash

set -eu

# This script should be executed on aosp work dicrectory.

BASEDIR=$(cd $(dirname $0); pwd)
WORKDIR=$PWD

# The patch set: rpi (android-<version>.patch) or generic
# (android-<version>-generic.patch, for non-RPi). The file name distinguishes
# them because the directory of a patch file is where it is applied.
PATCHSET=rpi
ANDROID_VER=10
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
  ANDROID_VER=$2
  shift
  ;;
  --set)
  PATCHSET=$2
  shift
  ;;
  --make-patched)
  # The result will be same as make_patch.sh input format
  MODE_MAKE_PATCHED=yes
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


pushd $BASEDIR > /dev/null

for PATCHFILE in $(find . -name "*$PATCHNAME"); do
  PATCHDIR=$(dirname $PATCHFILE)
  if [[ ! -d $WORKDIR/$PATCHDIR ]]; then
    echo "$WORKDIR/$PATCHDIR does not exist"
    continue
  fi 

  pushd $WORKDIR/$PATCHDIR > /dev/null
  if [[ $MODE_MAKE_PATCHED == "yes" ]]; then
    # Save patched files as <file>.patched and keep the tree unchanged.
    if [[ -n "$REVERTFLG" ]]; then
      echo "error: --make-patched cannot be used with --revert." >&2
      exit 2
    fi
    if grep -q '^+++ /dev/null' $BASEDIR/$PATCHFILE; then
      echo "error: --make-patched does not support deleting files: $PATCHFILE" >&2
      exit 1
    fi
    if ! patch -p0 -f -N -F0 --dry-run < $BASEDIR/$PATCHFILE > /dev/null; then
      echo "error: $PATCHFILE cannot be applied cleanly." >&2
      exit 1
    fi
    L_TARGETS=$(sed -n 's/^+++ \([^[:space:]]*\).*/\1/p' $BASEDIR/$PATCHFILE)
    L_CREATED=
    for L_BASEFILE in $L_TARGETS; do
      if [[ ! -e $L_BASEFILE ]]; then L_CREATED="$L_CREATED $L_BASEFILE "; fi
    done
    SIMPLE_BACKUP_SUFFIX=.patched.orig patch -p0 -f -N -F0 -b < $BASEDIR/$PATCHFILE > /dev/null
    for L_BASEFILE in $L_TARGETS; do
      mv $L_BASEFILE $L_BASEFILE.patched
      if [[ "$L_CREATED" == *" $L_BASEFILE "* ]]; then
        # patch -b makes an empty backup for a created file. Keep it absent.
        rm -f $L_BASEFILE.patched.orig
      else
        mv $L_BASEFILE.patched.orig $L_BASEFILE
      fi
    done
  else
    # -f: never ask questions (e.g. "File to patch:") even if a tty exists.
    # -N: never treat a patch as reversed implicitly.
    PATCH_OPTS="-p0 -f -N --no-backup-if-mismatch"
    if [[ -n "$REVERTFLG" ]]; then INVERSEFLG=; else INVERSEFLG=-R; fi
    # Check both directions without fuzz. A patch may be applicable with an
    # offset even if it is already applied, so require exactly one of them.
    FORWARD_OK=yes
    patch $PATCH_OPTS -F0 $REVERTFLG --dry-run < $BASEDIR/$PATCHFILE >/dev/null || FORWARD_OK=no
    INVERSE_OK=yes
    patch $PATCH_OPTS -F0 $INVERSEFLG --dry-run < $BASEDIR/$PATCHFILE >/dev/null || INVERSE_OK=no
    if [[ $FORWARD_OK == yes ]] && [[ $INVERSE_OK == no ]]; then
      patch $PATCH_OPTS -F0 $REVERTFLG < $BASEDIR/$PATCHFILE
    elif [[ $FORWARD_OK == no ]] && [[ $INVERSE_OK == yes ]]; then
      if [[ -n "$REVERTFLG" ]]; then
        echo "Patch $PATCHFILE is already reverted."
      else
        echo "Patch $PATCHFILE is already applied."
      fi
    else
      echo "error: Cannot determine whether $PATCHFILE is applied or not." >&2
      echo "error: The tree may be partially patched or modified." >&2
      patch $PATCH_OPTS -F0 $REVERTFLG --dry-run < $BASEDIR/$PATCHFILE >&2 ||:
      exit 1
    fi
  fi
  popd > /dev/null
  echo "done: $PATCHFILE"
done

popd > /dev/null
