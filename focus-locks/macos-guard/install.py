"""Install a per-user, launchd-restarted Chrome guard. Run after loading the extension."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import time

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--observe', action='store_true', help='Report failures without closing Chrome.')
parser.add_argument('--uninstall', action='store_true', help='Remove the per-user guard (not the extension).')
args = parser.parse_args()
home = Path.home()
app = home / 'Applications' / 'Intentional Browsing Guard.app'
binary = app / 'Contents' / 'MacOS' / 'BrowserGuard'
label = 'com.intentional-browsing.guard'
agent = home / 'Library' / 'LaunchAgents' / f'{label}.plist'
native = home / 'Library' / 'Application Support' / 'Google' / 'Chrome' / 'NativeMessagingHosts' / 'com.intentional_browsing.guard.json'
domain = f'gui/{os.getuid()}'

if not args.uninstall:
    print('Building the guard before changing its installation...', flush=True)
    try:
        subprocess.run([sys.executable, '-u', str(root / 'build.py')], check=True, timeout=400)
    except subprocess.TimeoutExpired:
        sys.exit('The build did not finish within 400s. The installed guard has not been replaced.')
    except subprocess.CalledProcessError:
        sys.exit('Build failed. The installed guard has not been replaced. See the error above.')
    if not args.observe:
        try:
            status = json.loads((home / 'Library/Application Support/Intentional Browsing Guard/status.json').read_text())
            # macOS monotonic time and ProcessInfo.systemUptime both use the uptime clock.
            age = time.monotonic() - status['checkedAt']
            if not 0 <= age < 75 or status.get('problem'):
                raise ValueError('Protection is not yet healthy in observation mode.')
        except (OSError, ValueError, KeyError) as error:
            sys.exit(f'Not enabling closure: {error}\nRun install.py --observe, reload the extension in each profile, and check the IB status first.')
# Boot out only this guard, never another blocker or Chrome itself.
print('Stopping the previous guard (up to 30 seconds)...', flush=True)
try:
    subprocess.run(['/bin/launchctl', 'bootout', f'{domain}/{label}'], timeout=30,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
except subprocess.TimeoutExpired:
    sys.exit('Timed out stopping the old guard. Its app was not replaced. '
             'The stop may still have taken effect; retry after a few seconds.')
stop_deadline = time.monotonic() + 10
while time.monotonic() < stop_deadline:
    try:
        unloaded = subprocess.run(['/bin/launchctl', 'print', f'{domain}/{label}'], timeout=3,
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        sys.exit('Timed out checking whether the old guard stopped. Its app was not replaced.')
    if unloaded.returncode != 0:
        break
    time.sleep(0.25)
else:
    sys.exit('The old guard is still stopping. Its app was not replaced; retry installation shortly.')
if args.uninstall:
    agent.unlink(missing_ok=True)
    native.unlink(missing_ok=True)
    if app.exists():
        shutil.rmtree(app)
    print('Removed Intentional Browsing Guard. The feed extension is unchanged.')
    sys.exit(0)

source = root.parent / 'build' / 'macos-guard' / app.name
print('Installing the app and registering Chrome native messaging...', flush=True)
app.parent.mkdir(parents=True, exist_ok=True)
if app.exists():
    shutil.rmtree(app)
shutil.copytree(source, app)
native.parent.mkdir(parents=True, exist_ok=True)
extension_id = (root / 'extension-id.txt').read_text().strip()
native.write_text(json.dumps({
    'name': 'com.intentional_browsing.guard',
    'description': 'Checks that Intentional Browsing is running in Chrome.',
    'path': str(binary), 'type': 'stdio',
    'allowed_origins': [f'chrome-extension://{extension_id}/'],
}, indent=2) + '\n')
agent.parent.mkdir(parents=True, exist_ok=True)
agent.write_bytes(plistlib.dumps({
    'Label': label,
    'ProgramArguments': [str(binary)] + (['--observe'] if args.observe else []),
    'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 3,
    'LimitLoadToSessionType': 'Aqua',
    'ProcessType': 'Interactive',
}))
print('Starting the guard in observation mode...' if args.observe else 'Starting the guard in enforcement mode...', flush=True)
for attempt in range(1, 4):
    try:
        started = subprocess.run(['/bin/launchctl', 'bootstrap', domain, str(agent)],
                                 capture_output=True, text=True, timeout=10)
    except subprocess.TimeoutExpired:
        sys.exit('Timed out starting the guard. It may still have started; '
                 f'check its status with "{binary}" --status before retrying.')
    if started.returncode == 0:
        break
    print(f'Start attempt {attempt}/3 failed: {started.stderr.strip()}', flush=True)
    time.sleep(0.5)
else:
    sys.exit(f'Could not start the guard: {started.stderr.strip()}')
print('Installed in observation mode.' if args.observe else
      'Protection enabled. The guard and native helper check every 60 seconds. Closure occurs at a scheduled check after the grace period.')
print(f'Extension folder: {root.parent / "packages" / "chromium"}')
print('Enable Allow in Incognito and all requested site access in every Chrome profile you use.')
print(f'Status: {binary} --status')
