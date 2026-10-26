"""Fault-test the installed native connection; refuses to run with closure enabled."""
import json
import os
from pathlib import Path
import signal
import subprocess
import time

root = Path.home() / 'Library/Application Support/Intentional Browsing Guard'

def status():
    value = json.loads((root / 'status.json').read_text())
    assert value.get('observing') is True, 'This test only runs in observation mode.'
    assert 0 <= time.monotonic() - value['checkedAt'] < 75, 'Guard status is stale.'
    return value

before = status()
assert before['running'] and not before.get('problem'), 'Chrome must be healthy before the fault test.'
reports = [json.loads(p.read_text()) for p in (root / 'health').glob('*.json')]
live = [r for r in reports if 0 <= time.monotonic() - r['uptime'] < 75]
assert live, 'No native host is connected.'
report = live[0]
pid = report['hostPID']
command = subprocess.check_output(['/bin/ps', '-p', str(pid), '-o', 'command='], text=True)
assert '/Intentional Browsing Guard.app/Contents/MacOS/BrowserGuard chrome-extension://' in command

try:
    os.kill(pid, signal.SIGSTOP)
    deadline = time.monotonic() + 240
    while time.monotonic() < deadline:
        failure = status()
        if failure.get('problem') and failure.get('secondsRemaining') == 0:
            print('PASS: a stopped native connection reaches the closure deadline in observation mode, with Chrome still open.')
            break
        time.sleep(0.5)
    else:
        raise AssertionError('Guard did not detect the stopped native connection.')
    os.kill(report['browserPID'], 0)
finally:
    try:
        os.kill(pid, signal.SIGCONT)
    except ProcessLookupError:
        pass

deadline = time.monotonic() + 150
while time.monotonic() < deadline:
    if not status().get('problem'):
        print('PASS: the native connection recovers and Chrome protection becomes healthy again.')
        break
    time.sleep(0.5)
else:
    raise AssertionError('Protection did not recover after resuming the host.')
