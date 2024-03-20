#!/bin/sh

SCRIPT="$@"

if [ -z "$USER_" ] || [ -z "$UID_" ] || [ -z "$GID_" ]; then
  exec bash --login -c "$SCRIPT"
else
  # mkdir -p /home/$USER_
  groupadd -o -g $GID_ $USER_
  useradd -o -g $USER_ -m -s /bin/bash -u $UID_ $USER_
  chown $USER_.$USER_ /home/$USER_

  # TODO: workaround?
  # chown $USER_.$USER_ /mnt/*

  export HOME=/home/$USER_
  chroot --userspec=$UID_:$GID_ --skip-chdir / \
    bash --login -c "$SCRIPT"
fi


