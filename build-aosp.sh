#!/bin/bash
exec python3 "$(dirname "$(readlink -f "$0")")/src/host/build_aosp.py" "$@"
