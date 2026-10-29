#!/bin/sh

apt-get clean autoclean
apt-get autoremove -y --purge
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
# Do not use brace expansion. This script is run by sh (dash).
rm -rf /var/cache/apt/* /var/log/apt/*
