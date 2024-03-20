#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f $0)

cd $(dirname $0)
SCRIPTDIR=$PWD/src
OUTDIR=
OUTSUBDIR=
TMPDIR=

ARG_OUTDIR=
ARG_OUTSUBDIR=

while [[ $# > 0 ]]
do
arg="$1"
case $arg in
    ##  --outdir     : The directory that output binaries.
    ##                  : 
    --outdir)
    ARG_OUTDIR=$2
    shift
    ;;
    ##  -t              : Specify output subdirectory name
    ##                  : e.g. android-10-arm
    # TODO: わかりにくい
    -t)
    ARG_OUTSUBDIR=$2
    shift
    ;;
    ##  --help, -h      : Show help
    --help|-h)
    echo "Usage: $0 [OPTION...]"
    echo ""
    grep "^ *##" $THIS_SCRIPT | sed -e "s/^ *##//"
    exit 0
    ;;
    *)
    echo "Unknow option "$arg
    exit 2
    ;;
esac
shift
done

# 

if [[ -z "$ARG_OUTDIR" ]]; then
  echo "--outdir is required."
  exit 2
fi

if [[ -z "$ARG_OUTSUBDIR" ]]; then
  echo "-t is required."
  exit 2
fi

OUTDIR=$ARG_OUTDIR
OUTSUBDIR=$ARG_OUTSUBDIR
TMPDIR=$OUTDIR/tmp

cd $OUTDIR

pushd $OUTSUBDIR > /dev/null
REQUIEDFILES=$(cat <<EOL
system.img
vendor.img
EOL
)

for L_FILEPATH in $REQUIEDFILES; do
  if [[ ! -f $L_FILEPATH ]]; then
    echo "$L_FILEPATH does not exist. Is the build complete?"
    for LL_TRUEPATH in $(find $(dirname $L_FILEPATH) -name $(basename $L_FILEPATH)); do
      echo "Do you forgot '-t $(dirname $LL_TRUEPATH)'?"
    done
    exit 1
  fi
done
popd > /dev/null

#

set -x
TARGETDIR=$OUTDIR/$OUTSUBDIR
OUTFILENAME=$OUTSUBDIR.img
mkdir -p $TMPDIR

#

# Allocate image
TMP_OUTIMG=$TMPDIR/$OUTFILENAME.tmp
dd if=/dev/zero of=$TMP_OUTIMG bs=128M count=24  # 3G

# Create partitions
TMP_LOOPFILE=$(sudo losetup -f)
# TMP_LOOPFILE=/dev/loop97
sudo losetup $TMP_LOOPFILE $TMP_OUTIMG
trap "sudo losetup -d ${TMP_LOOPFILE} && sudo rm -f ${TMP_OUTIMG} ||:" EXIT

sudo sfdisk $TMP_LOOPFILE < $SCRIPTDIR/img.sfdisk

# Apply created partitions
sudo losetup -d $TMP_LOOPFILE
sudo losetup -P $TMP_LOOPFILE $TMP_OUTIMG

# Write into pertitions
sudo mkfs.vfat -v -F 32 ${TMP_LOOPFILE}p1
sudo dd if=$TARGETDIR/system.img of=${TMP_LOOPFILE}p2 bs=1M
sudo dd if=$TARGETDIR/vendor.img of=${TMP_LOOPFILE}p3 bs=1M
sudo mkfs -t ext4 ${TMP_LOOPFILE}p4

# Label
sudo e2label ${TMP_LOOPFILE}p2 system
sudo e2label ${TMP_LOOPFILE}p3 vendor
sudo e2label ${TMP_LOOPFILE}p4 data

# Write p1(boot)
TMP_MOUNT=$TMPDIR/media
mkdir -p $TMP_MOUNT
sudo mount ${TMP_LOOPFILE}p1 $TMP_MOUNT
trap "set +e; sudo losetup -d ${TMP_LOOPFILE}; sudo umount $TMP_MOUNT; sudo rm -f ${TMP_OUTIMG}; " EXIT
sudo cp -r $TARGETDIR/boot/* $TMP_MOUNT
sudo umount $TMP_MOUNT

# Finalize
sudo losetup -d ${TMP_LOOPFILE}
mv $TMP_OUTIMG $OUTDIR/$OUTFILENAME
rm -rf $TMPDIR

set +ex
echo "Complete!"
echo $(readlink -f $OUTDIR/$OUTFILENAME)
