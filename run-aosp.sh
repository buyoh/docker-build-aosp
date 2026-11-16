#!/bin/bash
exec python3 "$(dirname "$(readlink -f "$0")")/src/run_aosp.py" "$@"
