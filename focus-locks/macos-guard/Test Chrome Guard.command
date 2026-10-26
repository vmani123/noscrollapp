#!/bin/bash
set -eu
task_guard_dir="$(cd "$(dirname "$0")" && pwd)"
python3 "$task_guard_dir/../build-packages.py"
python3 "$task_guard_dir/install.py" --observe
printf '\nObservation mode is running. Reload Intentional Browsing in chrome://extensions.\n'
printf 'Enable Allow in Incognito and access to all requested sites in every profile.\n'
printf 'Use the IB menu-bar item to check protection. Chrome stays open in this mode.\n'
read -r -p 'Press Return to close this setup window. '
