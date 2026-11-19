#!/bin/bash

# Tests for make-image.sh. sudo, losetup, mount, umount and mkfs are replaced
# with fakes so that neither root nor loop devices are needed. sfdisk is real.

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

L_TMP=$(mktemp -d)
trap "rm -rf $L_TMP" EXIT

export FAKE_DIR=$L_TMP/fake
export FAKE_LOG=$L_TMP/fake.log
mkdir -p $FAKE_DIR/bin

fake() {
  cat > $FAKE_DIR/bin/$1
  chmod +x $FAKE_DIR/bin/$1
}

fake sudo <<'EOL'
#!/bin/bash
echo "$*" >> $FAKE_LOG
[[ "$1" == "${FAKE_FAIL:-}" ]] && exit 1
if [[ "$1" == "${FAKE_SLOW:-}" ]]; then
  touch $FAKE_DIR/slow
  sleep 2
fi
exec "$@"
EOL
# The fake partition devices are regular files.
fake test <<'EOL'
#!/bin/bash
[[ -z "${FAKE_NO_PARTITION:-}" && "$1" == -b && -f "$2" ]]
EOL
fake losetup <<'EOL'
#!/bin/bash
case "$1" in
  -f)
    for L_I in 1 2 3 4; do : > $FAKE_DIR/loop0p$L_I; done
    touch $FAKE_DIR/attached
    echo $FAKE_DIR/loop0
    ;;
  -d)
    [[ -n "${FAKE_FAIL_DETACH:-}" ]] && exit 1
    rm $FAKE_DIR/attached
    ;;
  -j)
    [[ -n "${FAKE_FAIL_QUERY:-}" ]] && exit 1
    [[ -f $FAKE_DIR/attached ]] && echo $FAKE_DIR/loop0
    ;;
esac
exit 0
EOL
# Keep what was copied into the mount point, like the real filesystem does.
fake umount <<'EOL'
#!/bin/bash
[[ -f $FAKE_DIR/mounted ]] || exit 32
rm $FAKE_DIR/mounted
rm -rf $FAKE_DIR/p1
cp -r "$1" $FAKE_DIR/p1
find "$1" -mindepth 1 -delete
EOL
fake mount <<'EOL'
#!/bin/bash
touch $FAKE_DIR/mounted
EOL
fake mountpoint <<'EOL'
#!/bin/bash
[[ -f $FAKE_DIR/mounted ]]
EOL
for L_CMD in mkfs.vfat mkfs.ext4 e2label udevadm; do
  fake $L_CMD <<'EOL'
#!/bin/bash
exit 0
EOL
done

# Make a build output: system.img is 3MiB + 1 byte, vendor.img is 2MiB.
L_SERIAL=0
new_outdir() {
  L_SERIAL=$((L_SERIAL + 1))
  OUT="$L_TMP/out $L_SERIAL"
  mkdir -p "$OUT/android-14-arm64/boot"
  head -c 3145729 /dev/urandom > "$OUT/android-14-arm64/system.img"
  head -c 2097152 /dev/urandom > "$OUT/android-14-arm64/vendor.img"
  echo dummy > "$OUT/android-14-arm64/boot/config.txt"
  echo hidden > "$OUT/android-14-arm64/boot/.hidden"
}

run() {
  : > $FAKE_LOG
  rm -f $FAKE_DIR/attached $FAKE_DIR/mounted
  PATH=$FAKE_DIR/bin:$PATH:/usr/sbin:/sbin bash $REPODIR/make-image.sh "$@" > $L_TMP/log 2>&1
}

no_leftovers() {
  [[ ! -f $FAKE_DIR/attached ]] && [[ ! -f $FAKE_DIR/mounted ]] && [[ -z "$(ls -A "$OUT" | grep '^\.make-image')" ]]
}

# umount (if mounted) comes before detach.
log_line() {
  grep -n "$1" $FAKE_LOG | head -n1 | cut -d: -f1
}
released_in_order() {
  [[ "$(log_line '^umount')" -lt "$(log_line '^losetup -d')" ]]
}

# Successful run

new_outdir
run --outdir "$OUT" -t android-14-arm64 --data-size 8
L_RC=$?
L_IMG="$OUT/android-14-arm64.img"
assert "success: exit status" [ $L_RC -eq 0 ]
assert "success: image exists" [ -f "$L_IMG" ]
assert "success: no leftovers" no_leftovers

# Offsets are in sectors. 1MiB + 128MiB, then 4MiB, 2MiB and 8MiB.
has_partition() {
  PATH=$PATH:/usr/sbin:/sbin sfdisk -d "$L_IMG" | grep -Eq "img$1 : start= *$2, size= *$3, type=$4$5"
}
assert "layout: p1 is 128MiB FAT32 and bootable" has_partition 1 2048 262144 c ", bootable"
assert "layout: p2 is system.img rounded up" has_partition 2 264192 8192 83
assert "layout: p3 is vendor.img" has_partition 3 272384 4096 83
assert "layout: p4 is --data-size" has_partition 4 276480 16384 83
assert "layout: image size is 1+128+p2+p3+data MiB" \
  [ "$(stat -c %s "$L_IMG")" -eq $(((1 + 128 + 4 + 2 + 8) * 1048576)) ]

same_size_prefix() {
  cmp -n "$(stat -c %s "$1")" "$1" "$2"
}
assert "write: system.img goes to p2" same_size_prefix "$OUT/android-14-arm64/system.img" $FAKE_DIR/loop0p2
assert "write: vendor.img goes to p3" same_size_prefix "$OUT/android-14-arm64/vendor.img" $FAKE_DIR/loop0p3
assert "write: boot files go to p1" [ -f $FAKE_DIR/p1/config.txt ]
assert "write: hidden boot files go to p1" [ -f $FAKE_DIR/p1/.hidden ]
assert "label: /data is formatted as userdata" grep -q "^mkfs.ext4 -L userdata $FAKE_DIR/loop0p4$" $FAKE_LOG
assert "label: p4 is not relabeled" bash -c "! grep -q 'e2label .*p4' $FAKE_LOG"
assert "label: p2 is system" grep -q "^e2label $FAKE_DIR/loop0p2 system$" $FAKE_LOG
assert "label: p3 is vendor" grep -q "^e2label $FAKE_DIR/loop0p3 vendor$" $FAKE_LOG
assert "release: umount before detach" released_in_order
assert "release: no double detach" [ "$(grep -c '^losetup -d' $FAKE_LOG)" -eq 1 ]

new_outdir
run --outdir "$OUT" -t android-14-arm64
assert "default --data-size is 4096MiB" \
  [ "$(stat -c %s "$OUT/android-14-arm64.img")" -eq $(((1 + 128 + 4 + 2 + 4096) * 1048576)) ]

# Paths

new_outdir
run --outdir "$OUT" -t android-14-arm64/ --data-size 8
assert "-t accepts a trailing slash" [ -f "$OUT/android-14-arm64.img" ]

new_outdir
L_NAME=$(basename "$OUT")
(cd $L_TMP && run --outdir "$L_NAME" -t android-14-arm64 --data-size 8)
assert "relative --outdir is based on the caller directory" [ -f "$OUT/android-14-arm64.img" ]

new_outdir
mkdir "$OUT/android-14-arm64.img"
run --outdir "$OUT" -t android-14-arm64 --data-size 8
assert "a directory at the output path is an error" [ $? -ne 0 ]

new_outdir
ln -s $REPODIR/make-image.sh $L_TMP/link.sh
: > $FAKE_LOG
PATH=$FAKE_DIR/bin:$PATH:/usr/sbin:/sbin $L_TMP/link.sh --outdir "$OUT" -t android-14-arm64 --data-size 8 > $L_TMP/log 2>&1
assert "works via a symlink" [ -f "$OUT/android-14-arm64.img" ]

new_outdir
mkdir "$OUT/tmp" && touch "$OUT/tmp/keep"
TMPDIR=/nonexistent run --outdir "$OUT" -t android-14-arm64 --data-size 8
assert "ignores TMPDIR in the environment" [ -f "$OUT/android-14-arm64.img" ]
assert "keeps the existing tmp directory" [ -f "$OUT/tmp/keep" ]

# Invalid arguments

new_outdir
for L_ARG in foo/bar . ..; do
  run --outdir "$OUT" -t $L_ARG
  assert "-t $L_ARG is rejected" [ $? -eq 2 ]
done
for L_ARG in 0 abc -1 1.5; do
  run --outdir "$OUT" -t android-14-arm64 --data-size $L_ARG
  assert "--data-size $L_ARG is rejected" [ $? -eq 2 ]
done
run --outdir "$OUT/nonexistent" -t android-14-arm64
assert "nonexistent --outdir is rejected" [ $? -eq 2 ]
run --help
assert "--help" [ $? -eq 0 ]

# Missing inputs are detected before touching anything

check_missing_input() {
  run --outdir "$OUT" -t android-14-arm64
  assert "$1: exit status" [ $? -eq 1 ]
  assert "$1: nothing is run as root" [ ! -s $FAKE_LOG ]
  assert "$1: no leftovers" no_leftovers
}

new_outdir
rm "$OUT/android-14-arm64/system.img"
check_missing_input "no system.img"

new_outdir
: > "$OUT/android-14-arm64/vendor.img"
check_missing_input "empty vendor.img"

new_outdir
rm "$OUT/android-14-arm64/boot/"*
rm "$OUT/android-14-arm64/boot/.hidden"
check_missing_input "empty boot"

new_outdir
run --outdir "$OUT" -t android-14
assert "wrong -t: exit status" [ $? -eq 1 ]
assert "wrong -t: suggests the right one" grep -q -- "-t android-14-arm64" $L_TMP/log

# Failures

new_outdir
FAKE_FAIL=cp run --outdir "$OUT" -t android-14-arm64 --data-size 8
assert "failure after mount: exit status" [ $? -ne 0 ]
assert "failure after mount: released in order" released_in_order
assert "failure after mount: no leftovers" no_leftovers
assert "failure after mount: no image" [ ! -f "$OUT/android-14-arm64.img" ]

new_outdir
FAKE_FAIL=mkfs.vfat run --outdir "$OUT" -t android-14-arm64 --data-size 8
assert "failure before mount: exit status" [ $? -ne 0 ]
assert "failure before mount: not unmounted" bash -c "! grep -q '^umount' $FAKE_LOG"
assert "failure before mount: no leftovers" no_leftovers

new_outdir
FAKE_FAIL=umount run --outdir "$OUT" -t android-14-arm64 --data-size 8
assert "umount failure: exit status" [ $? -ne 0 ]
assert "umount failure: reports it" grep -q "manual cleanup" $L_TMP/log
assert "umount failure: leaves the work directory" \
  bash -c "ls -A '$OUT' | grep -q '^\.make-image'"

new_outdir
FAKE_FAIL=sfdisk run --outdir "$OUT" -t android-14-arm64 --data-size 8
assert "sfdisk failure: exit status" [ $? -ne 0 ]
assert "sfdisk failure: no leftovers" no_leftovers

new_outdir
FAKE_NO_PARTITION=1 run --outdir "$OUT" -t android-14-arm64 --data-size 8
assert "no partition device: exit status" [ $? -ne 0 ]
assert "no partition device: reports it" grep -q "did not appear" $L_TMP/log
assert "no partition device: no leftovers" no_leftovers

new_outdir
FAKE_FAIL_DETACH=1 run --outdir "$OUT" -t android-14-arm64 --data-size 8
assert "detach failure: exit status" [ $? -ne 0 ]
assert "detach failure: reports it" grep -q "manual cleanup" $L_TMP/log
assert "detach failure: no image" [ ! -f "$OUT/android-14-arm64.img" ]

new_outdir
FAKE_FAIL=mkfs.vfat FAKE_FAIL_QUERY=1 run --outdir "$OUT" -t android-14-arm64 --data-size 8
assert "unknown loop state: exit status" [ $? -ne 0 ]
assert "unknown loop state: reports it" grep -q "manual cleanup" $L_TMP/log
assert "unknown loop state: leaves the work directory" \
  bash -c "ls -A '$OUT' | grep -q '^\.make-image'"

# Send a signal while the command runs. The trap runs after the command exits.
interrupt_during() {
  new_outdir
  rm -f $FAKE_DIR/slow $FAKE_DIR/attached $FAKE_DIR/mounted
  : > $FAKE_LOG
  # A background job starts with SIGINT ignored.
  FAKE_SLOW=$1 PATH=$FAKE_DIR/bin:$PATH:/usr/sbin:/sbin env --default-signal=INT \
    bash $REPODIR/make-image.sh \
    --outdir "$OUT" -t android-14-arm64 --data-size 8 > $L_TMP/log 2>&1 &
  local L_PID=$!
  local L_RETRY
  for L_RETRY in $(seq 300); do
    [[ -f $FAKE_DIR/slow ]] && break
    sleep 0.1
  done
  kill -$2 $L_PID
  wait $L_PID
  assert "$2 during $1: exit status" [ $? -eq $3 ]
  assert "$2 during $1: no leftovers" no_leftovers
  assert "$2 during $1: no false report" bash -c "! grep -q 'manual cleanup' $L_TMP/log"
}

interrupt_during cp TERM 143
assert "TERM during cp: released in order" released_in_order
interrupt_during cp INT 130
interrupt_during cp HUP 129
interrupt_during mount TERM 143
assert "TERM during mount: released in order" released_in_order
interrupt_during umount TERM 143
assert "TERM during umount: umount once" [ "$(grep -c '^umount' $FAKE_LOG)" -eq 1 ]
interrupt_during losetup TERM 143

assert "sfdisk files are removed" \
  bash -c "! find $REPODIR/src -name '*.sfdisk' | grep -q ."

finish
