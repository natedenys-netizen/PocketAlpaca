#!/bin/zsh
# Double-click in Finder: hands the stored Live token and Signals settings to
# the PocketAlpaca app running in the iOS simulator. Leaves the window open so
# the result can be read.
cd "$(dirname "$0")" || exit 1
/usr/bin/python3 ./simulator_provision.py apply --env live
echo
echo "Press any key to close."
read -k1
