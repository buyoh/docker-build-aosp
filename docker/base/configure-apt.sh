#!/bin/sh

echo "deb $UBUNTU_APT_URL $DIST_CODENAME main restricted universe multiverse" > /etc/apt/sources.list
echo "deb $UBUNTU_APT_URL $DIST_CODENAME-updates main restricted universe multiverse" >> /etc/apt/sources.list
echo "deb $UBUNTU_APT_URL $DIST_CODENAME-backports main restricted universe multiverse" >> /etc/apt/sources.list
echo "deb $UBUNTU_APT_URL $DIST_CODENAME-security main restricted universe multiverse" >> /etc/apt/sources.list
