#!/bin/bash

set -eu
THIS_SCRIPT=$(readlink -f "$0")

OUTDIR=
OUTSUBDIR=

ARG_OUTDIR=
ARG_OUTSUBDIR=
ARG_DATA_SIZE=4096

WORK_TMP=
TMP_OUTIMG=
TMP_MOUNT=
LOOP_DEV=

settle_udev() {
  if command -v udevadm > /dev/null; then sudo udevadm settle; fi
}

# A signal is handled after the running command exits, so that shell variables
# can not tell if an interrupted mount or losetup finished. Ask the system.
is_mounted() {
  [[ -n "$TMP_MOUNT" ]] && mountpoint -q "$TMP_MOUNT"
}

# Print the loop device. Fails if it can not be determined (e.g. sudo failed).
attached_loop() {
  local L_OUTPUT
  if [[ -n "$TMP_OUTIMG" && -f "$TMP_OUTIMG" ]]; then
    L_OUTPUT=$(sudo losetup -j "$TMP_OUTIMG" -O NAME -n) || return 1
    head -n1 <<< "$L_OUTPUT"
  fi
}

cleanup() {
  local rc=$?
  local L_LOOP
  trap '' INT TERM HUP
  set +e
  if is_mounted; then
    sudo umount "$TMP_MOUNT"
  fi
  if L_LOOP=$(attached_loop); then
    LOOP_DEV=$L_LOOP
  fi
  if [[ -n "$LOOP_DEV" ]]; then
    settle_udev
    sudo losetup -d "$LOOP_DEV"
  fi
  if [[ -n "$WORK_TMP" ]]; then
    if is_mounted || ! L_LOOP=$(attached_loop) || [[ -n "$L_LOOP" ]]; then
      echo "Failed to release resources. Leave '$WORK_TMP' for manual cleanup." >&2
    else
      rm -rf "$WORK_TMP"
    fi
  fi
  exit $rc
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

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
    ##  --data-size     : The size of /data partition in MiB (default: 4096)
    ##                  : The image does not grow to the size of the SD card.
    --data-size)
    ARG_DATA_SIZE=$2
    shift
    ;;
    ##  --help, -h      : Show help
    --help|-h)
    echo "Usage: $0 [OPTION...]"
    echo ""
    grep "^ *##" "$THIS_SCRIPT" | sed -e "s/^ *##//"
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

if [[ ! "$ARG_DATA_SIZE" =~ ^[1-9][0-9]*$ ]]; then
  echo "--data-size must be a positive integer (MiB): $ARG_DATA_SIZE"
  exit 2
fi

if [[ ! -d "$ARG_OUTDIR" ]]; then
  echo "The outdir '$ARG_OUTDIR' does not exist."
  exit 2
fi
OUTDIR=$(readlink -f "$ARG_OUTDIR")

OUTSUBDIR=${ARG_OUTSUBDIR%/}
if [[ "$OUTSUBDIR" == */* || "$OUTSUBDIR" == . || "$OUTSUBDIR" == .. || -z "$OUTSUBDIR" ]]; then
  echo "-t must be a directory name under --outdir: $ARG_OUTSUBDIR"
  exit 2
fi

TARGETDIR=$OUTDIR/$OUTSUBDIR
OUTFILENAME=$OUTSUBDIR.img

if [[ ! -d "$TARGETDIR" ]]; then
  echo "'$TARGETDIR' does not exist."
  for L_DIR in "$OUTDIR"/*/; do
    if [[ -f "$L_DIR/system.img" ]]; then
      echo "Do you forget '-t $(basename "$L_DIR")'?"
    fi
  done
  exit 1
fi

for L_FILE in system.img vendor.img; do
  if [[ ! -s "$TARGETDIR/$L_FILE" ]]; then
    echo "$L_FILE does not exist in '$TARGETDIR' or is empty. Is the build complete?"
    exit 1
  fi
done

if [[ ! -d "$TARGETDIR/boot" ]] || [[ -z "$(ls -A "$TARGETDIR/boot")" ]]; then
  echo "'$TARGETDIR/boot' does not exist or is empty."
  exit 1
fi

# Print the file size in MiB, rounded up.
size_mib() {
  local L_SIZE
  L_SIZE=$(stat -c %s "$1")
  echo $(((L_SIZE + 1048575) / 1048576))
}

#

set -x
WORK_TMP=$(mktemp -d -p "$OUTDIR" .make-image.XXXXXX)
TMP_OUTIMG=$WORK_TMP/$OUTFILENAME.tmp
TMP_MOUNT=$WORK_TMP/media
mkdir "$TMP_MOUNT"

#

# Follow "Prepare sd card" of device_arpi_rpi4. The sizes of p2 and p3 in the
# upstream are the sizes of system.img and vendor.img. (See UPSTREAM.md)
BOOT_MIB=128
SYSTEM_MIB=$(size_mib "$TARGETDIR/system.img")
VENDOR_MIB=$(size_mib "$TARGETDIR/vendor.img")
TMP_LAYOUT=$WORK_TMP/layout.sfdisk
cat > "$TMP_LAYOUT" <<EOL
label: dos
start=2048, size=${BOOT_MIB}MiB, type=c, bootable
size=${SYSTEM_MIB}MiB, type=83
size=${VENDOR_MIB}MiB, type=83
type=83
EOL

# Allocate image (The first 1MiB is for the partition table)
truncate -s $((1 + BOOT_MIB + SYSTEM_MIB + VENDOR_MIB + ARG_DATA_SIZE))M "$TMP_OUTIMG"

# Create partitions
sudo sfdisk "$TMP_OUTIMG" < "$TMP_LAYOUT"

LOOP_DEV=$(sudo losetup -f --show -P "$TMP_OUTIMG")

# Partition devices appear asynchronously
settle_udev
for L_I in 1 2 3 4; do
  for L_RETRY in $(seq 10); do
    if sudo test -b "${LOOP_DEV}p${L_I}"; then
      break
    fi
    sleep 0.5
  done
  if ! sudo test -b "${LOOP_DEV}p${L_I}"; then
    echo "${LOOP_DEV}p${L_I} did not appear."
    exit 1
  fi
done

# Write into pertitions
sudo mkfs.vfat -v -F 32 "${LOOP_DEV}p1"
sudo dd if="$TARGETDIR/system.img" of="${LOOP_DEV}p2" bs=1M conv=fsync
sudo dd if="$TARGETDIR/vendor.img" of="${LOOP_DEV}p3" bs=1M conv=fsync
sudo mkfs.ext4 -L userdata "${LOOP_DEV}p4"

# Label
sudo e2label "${LOOP_DEV}p2" system
sudo e2label "${LOOP_DEV}p3" vendor

# Write p1(boot)
sudo mount "${LOOP_DEV}p1" "$TMP_MOUNT"
sudo cp -r "$TARGETDIR/boot/." "$TMP_MOUNT/"
sudo umount "$TMP_MOUNT"

# Finalize
settle_udev
sudo losetup -d "$LOOP_DEV"
mv -T "$TMP_OUTIMG" "$OUTDIR/$OUTFILENAME"

set +ex
echo "Complete!"
echo "$OUTDIR/$OUTFILENAME"
