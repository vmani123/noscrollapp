#!/bin/bash
set -eu
task_guard_dir="$(cd "$(dirname "$0")" && pwd)"
python3 "$task_guard_dir/../build-packages.py"
python3 "$task_guard_dir/install.py"
printf '\nProtection is active. Save any browser work.\n'
printf 'If the extension is missing or disabled, Chrome closes after the grace period.\n'
read -r -p 'Press Return to close this setup window. '
