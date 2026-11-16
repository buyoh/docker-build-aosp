#!/bin/bash

# Tests for src/patches/patcher.sh

source $(cd $(dirname ${BASH_SOURCE[0]}) && pwd)/lib.sh

L_TMP=$(mktemp -d)
trap "rm -rf $L_TMP" EXIT

# Fixture: patcher.sh finds patches next to itself.
mkdir -p $L_TMP/patches
cp $REPODIR/src/patches/patcher.sh $L_TMP/patches/
PATCHER=$L_TMP/patches/patcher.sh

setup_tree() {
  rm -rf $L_TMP/work
  mkdir -p $L_TMP/work/a $L_TMP/work/b
  printf 'line1\nline2\nline3\n' > $L_TMP/work/a/x.txt
  printf 'foo\nbar\nbaz\n' > $L_TMP/work/b/y.txt
}

# Make android-99.patch: modify a/x.txt, b/y.txt and create a/new.txt
setup_tree
cp -r $L_TMP/work $L_TMP/orig
sed -i 's/line2/LINE2/' $L_TMP/work/a/x.txt
sed -i 's/bar/BAR/' $L_TMP/work/b/y.txt
printf 'new\n' > $L_TMP/work/a/new.txt
(
  cd $L_TMP
  for L_F in a/x.txt b/y.txt; do
    diff -U 3 --label ./$L_F --label ./$L_F orig/$L_F work/$L_F
  done
  diff -U 3 -N --label /dev/null --label ./a/new.txt /dev/null work/a/new.txt
) > $L_TMP/patches/android-99.patch
cp -r $L_TMP/work $L_TMP/patched

run_patcher() {
  (cd $L_TMP/work && bash $PATCHER --android 99 "$@") < /dev/null > $L_TMP/log 2>&1
}

fails_patcher() {
  ! run_patcher "$@"
}

same_as() {
  diff -r $L_TMP/work $L_TMP/$1 > /dev/null
}

no_backup_files() {
  [[ -z $(find $L_TMP/work -name '*.orig' -o -name '*.rej') ]]
}

# clean -> apply
setup_tree
assert "apply to a clean tree succeeds" run_patcher
assert "the tree is patched" same_as patched
assert "no .orig/.rej files" no_backup_files

# applied -> skip
assert "apply to a patched tree succeeds" run_patcher
assert "it reports already applied" grep -q "already applied" $L_TMP/log
assert "the tree is still patched" same_as patched

# applied -> revert
assert "revert succeeds" run_patcher -R
assert "the tree is reverted" same_as orig

# reverted -> revert
assert "revert of a clean tree succeeds" run_patcher -R
assert "it reports already reverted" grep -q "already reverted" $L_TMP/log
assert "the tree is still clean" same_as orig

# partially applied -> error
setup_tree
sed -i 's/line2/LINE2/' $L_TMP/work/a/x.txt
cp -r $L_TMP/work $L_TMP/partial
assert "apply to a partially patched tree fails" fails_patcher
assert "the partial tree is not modified" same_as partial
assert "revert of a partially patched tree fails" fails_patcher -R
assert "the partial tree is not modified (revert)" same_as partial
assert "no .orig/.rej files (partial)" no_backup_files
rm -rf $L_TMP/partial

# conflicting modification -> error
setup_tree
sed -i 's/bar/QUX/' $L_TMP/work/b/y.txt
assert "apply to a conflicting tree fails" fails_patcher

# --make-patched: patched files are saved as *.patched, and the tree is kept
setup_tree
make_patched_tree() {
  # The tree is unchanged except *.patched files.
  diff -r -x '*.patched' $L_TMP/work $L_TMP/orig > /dev/null || return 1
  for L_F in a/x.txt b/y.txt a/new.txt; do
    diff -q $L_TMP/work/$L_F.patched $L_TMP/patched/$L_F > /dev/null || return 1
  done
}
no_patched_orig() {
  [[ -z $(find $L_TMP/work -name '*.patched.orig') ]]
}
assert "make-patched: options after --make-patched are parsed" run_patcher --make-patched
assert "make-patched: *.patched files are created and the tree is kept" make_patched_tree
assert "make-patched: a created file is not left in the tree" test ! -e $L_TMP/work/a/new.txt
assert "make-patched: no *.patched.orig files" no_patched_orig

rm -rf $L_TMP/work && cp -r $L_TMP/patched $L_TMP/work
assert "make-patched: a patched tree fails" fails_patcher --make-patched
assert "make-patched: a patched tree is not modified" same_as patched
assert "make-patched: with --revert fails" fails_patcher --make-patched -R

# The patch is applicable with an offset even after applied.
setup_tree
printf 'l1\nl2\nl3\nl4\nl5\nl6\nl1\nl2\nl3\nl4\nl5\nl6\n' > $L_TMP/work/a/x.txt
rm -rf $L_TMP/orig && cp -r $L_TMP/work $L_TMP/orig
sed -i '3a INS' $L_TMP/work/a/x.txt
(
  cd $L_TMP
  diff -U 3 --label ./a/x.txt --label ./a/x.txt orig/a/x.txt work/a/x.txt
) > $L_TMP/patches/android-99.patch
cp -r $L_TMP/work $L_TMP/applied
# It is ambiguous, so the patcher must stop instead of applying it twice.
assert "repeated context: apply to a patched tree fails" fails_patcher
assert "repeated context: it reports the ambiguity" grep -q "Cannot determine" $L_TMP/log
assert "repeated context: the tree is not patched twice" same_as applied

# No interactive prompt even if a tty exists (docker run -it).
# A missing target file makes patch ask "File to patch:" without -f.
setup_tree
rm $L_TMP/work/a/x.txt
run_patcher_with_tty() {
  (cd $L_TMP/work && \
    timeout 10 script -qec "bash $PATCHER --android 99" /dev/null) > $L_TMP/log 2>&1
  [[ $? -ne 124 ]]
}
if command -v script > /dev/null; then
  assert "no prompt with a tty" run_patcher_with_tty
else
  echo "skip: script command is not available"
fi

# --set: rpi (android-<v>.patch, default) and generic (android-<v>-generic.patch)
setup_tree
rm -rf $L_TMP/orig && cp -r $L_TMP/work $L_TMP/orig
(
  cd $L_TMP
  sed 's/line2/RPI/' orig/a/x.txt > $L_TMP/x.rpi
  diff -U 3 --label ./a/x.txt --label ./a/x.txt orig/a/x.txt $L_TMP/x.rpi
) > $L_TMP/patches/android-98.patch
(
  cd $L_TMP
  sed 's/bar/GENERIC/' orig/b/y.txt > $L_TMP/y.generic
  diff -U 3 --label ./b/y.txt --label ./b/y.txt orig/b/y.txt $L_TMP/y.generic
) > $L_TMP/patches/android-98-generic.patch
run_patcher_98() {
  (cd $L_TMP/work && bash $PATCHER "$@") < /dev/null > $L_TMP/log 2>&1
}
only_rpi_applied() {
  grep -qx RPI $L_TMP/work/a/x.txt && grep -qx bar $L_TMP/work/b/y.txt
}
only_generic_applied() {
  grep -qx line2 $L_TMP/work/a/x.txt && grep -qx GENERIC $L_TMP/work/b/y.txt
}
assert "set: rpi is the default" run_patcher_98 --android 98
assert "set: only android-98.patch is applied" only_rpi_applied
assert "set: rpi revert" run_patcher_98 -R --android 98 --set rpi
assert "set: rpi revert restores the tree" same_as orig
assert "set: generic" run_patcher_98 --set generic --android 98
assert "set: only android-98-generic.patch is applied" only_generic_applied
assert "set: generic revert (options in another order)" \
  run_patcher_98 --android 98 -R --set generic
assert "set: generic revert restores the tree" same_as orig
unknown_set_fails() {
  run_patcher_98 --set foo --android 98
  [[ $? -eq 2 ]]
}
assert "set: unknown set fails with 2" unknown_set_fails
assert "set: unknown set does not modify the tree" same_as orig

finish
