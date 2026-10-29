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
