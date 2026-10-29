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

finish
