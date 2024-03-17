#!/bin/sh

if [ -z "$USER_" ] || [ -z "$UID_" ] || [ -z "$GID_" ]; then
  echo 'USER_ or UID_ or GID_ is not set'
  exit 2
fi

SCRIPT="$@"

# mkdir -p /home/$USER_
groupadd -g $GID_ $USER_
useradd -g $USER_ -m -s /bin/bash -u $UID_ $USER_
chown $USER_.$USER_ /home/$USER_

# TODO: workaround?
chown $USER_.$USER_ /mnt/*

export HOME=/home/$USER_
chroot --userspec=$UID_:$GID_ --skip-chdir / \
  bash --login -i -c "$SCRIPT"
