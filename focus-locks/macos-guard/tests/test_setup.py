import contextlib
import io
import json
from pathlib import Path
import runpy
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


class SetupFailures(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.guard = self.base / 'focus-locks/macos-guard'
        self.guard.mkdir(parents=True)
        source = Path(__file__).resolve().parents[1]
        for name in ('install.py', 'build.py'):
            shutil.copy2(source / name, self.guard / name)
        self.home = self.base / 'account'
        self.marker = self.home / 'Applications/Intentional Browsing Guard.app/existing'
        self.marker.parent.mkdir(parents=True)
        self.marker.write_text('existing installation')

    def install(self, runner):
        with patch.object(Path, 'home', return_value=self.home), \
                patch.object(sys, 'argv', ['install.py', '--observe']), \
                patch('subprocess.run', side_effect=runner), \
                contextlib.redirect_stdout(io.StringIO()):
            runpy.run_path(str(self.guard / 'install.py'), run_name='__main__')

    def test_compile_failure_keeps_existing_installation(self):
        def runner(command, **kwargs):
            raise subprocess.CalledProcessError(1, command)
        with self.assertRaisesRegex(SystemExit, 'Build failed'):
            self.install(runner)
        self.assertEqual(self.marker.read_text(), 'existing installation')
        self.assertFalse((self.home / 'Library/LaunchAgents').exists())

    def test_stop_timeout_keeps_existing_installation(self):
        def runner(command, **kwargs):
            if command[0] == sys.executable:
                return subprocess.CompletedProcess(command, 0)
            self.assertEqual(command[1], 'bootout')
            self.assertEqual(kwargs['timeout'], 30)
            raise subprocess.TimeoutExpired(command, kwargs['timeout'])
        with self.assertRaisesRegex(SystemExit, 'Timed out stopping'):
            self.install(runner)
        self.assertEqual(self.marker.read_text(), 'existing installation')

    def test_incomplete_sdk_fails_before_compiling(self):
        sdk = self.base / 'SDK'
        headers = sdk / 'System/Library/Frameworks/CoreServices.framework/Frameworks/CarbonCore.framework/Headers'
        headers.mkdir(parents=True)
        (headers / 'CarbonCore.h').write_text('#include <CarbonCore/Folders.h>\n')
        def runner(command, **kwargs):
            self.assertEqual(command, ['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'])
            return subprocess.CompletedProcess(command, 0, stdout=str(sdk) + '\n')
        with patch('subprocess.run', side_effect=runner), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(SystemExit, 'SDK is incomplete'):
                runpy.run_path(str(self.guard / 'build.py'), run_name='__main__')
        self.assertEqual(self.marker.read_text(), 'existing installation')

    def test_observation_install_registers_observation_only(self):
        source = self.guard.parent / 'build/macos-guard/Intentional Browsing Guard.app/Contents/MacOS'
        source.mkdir(parents=True)
        (source / 'BrowserGuard').write_text('test binary')
        (self.guard / 'extension-id.txt').write_text('test-extension\n')
        def runner(command, **kwargs):
            if command[0] == sys.executable:
                return subprocess.CompletedProcess(command, 0)
            self.assertEqual(command[0], '/bin/launchctl')
            self.assertIn(command[1], ['bootout', 'print', 'bootstrap'])
            return subprocess.CompletedProcess(command, 1 if command[1] == 'print' else 0)
        self.install(runner)
        agent = self.home / 'Library/LaunchAgents/com.intentional-browsing.guard.plist'
        config = plistlib.loads(agent.read_bytes())
        self.assertEqual(config['ProgramArguments'][-1], '--observe')
        self.assertTrue(config['KeepAlive'])
        native = self.home / 'Library/Application Support/Google/Chrome/NativeMessagingHosts/com.intentional_browsing.guard.json'
        self.assertEqual(json.loads(native.read_text())['allowed_origins'], ['chrome-extension://test-extension/'])


if __name__ == '__main__':
    unittest.main()
