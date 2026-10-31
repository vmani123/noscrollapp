"""Build the local Mac guard; does not install or start it."""
from pathlib import Path
import hashlib
import json
import plistlib
import subprocess
import sys


def run_step(message, command, timeout):
    print(message, flush=True)
    try:
        subprocess.run(command, check=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        sys.exit(f'Timed out after {timeout}s: {message}\n'
                 'Check xcode-select -p and xcrun swiftc --version, then retry. '
                 'The installed guard has not been replaced.')
    except subprocess.CalledProcessError as error:
        sys.exit(f'{message} failed (exit {error.returncode}). See the error above.\n'
                 'For missing Apple headers or a compiler/SDK mismatch, update or reinstall '
                 'Apple Command Line Tools for your macOS version, then retry.')

root = Path(__file__).resolve().parent
output = root.parent / 'build' / 'macos-guard'
app = output / 'Intentional Browsing Guard.app'
contents = app / 'Contents'
binary = contents / 'MacOS' / 'BrowserGuard'
binary.parent.mkdir(parents=True, exist_ok=True)
print('Checking the selected Apple macOS SDK...', flush=True)
try:
    sdk = Path(subprocess.run(['/usr/bin/xcrun', '--sdk', 'macosx', '--show-sdk-path'],
                              check=True, capture_output=True, text=True, timeout=30).stdout.strip())
except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
    sys.exit(f'Cannot locate the Apple macOS SDK: {error}\n'
             'Check xcode-select -p and install/update Apple Command Line Tools.')
print(f'macOS SDK: {sdk}', flush=True)
carbon = sdk / 'System/Library/Frameworks/CoreServices.framework/Frameworks/CarbonCore.framework/Headers'
umbrella = carbon / 'CarbonCore.h'
if umbrella.exists() and '#include <CarbonCore/Folders.h>' in umbrella.read_text(errors='replace') \
        and not (carbon / 'Folders.h').exists():
    sys.exit('The selected Apple SDK is incomplete: CarbonCore.h references missing CarbonCore/Folders.h.\n'
             'Update or reinstall Apple Command Line Tools for your macOS version through '
             'Software Update or https://developer.apple.com/download/all/. '
             'The installed guard has not been changed.')
manifest = json.loads((root.parent / 'extension' / 'manifest.json').read_text())
extension_id = ''.join(chr(97 + int(c, 16)) for c in hashlib.sha256(
    str((root.parent / 'packages' / 'chromium').resolve()).encode()).hexdigest()[:32])
(root / 'extension-id.txt').write_text(extension_id + '\n')
run_step('Compiling the Mac guard (the first build can take several minutes)...',
         ['/usr/bin/xcrun', 'swiftc', '-O', '-module-cache-path', '/private/tmp/intentional-swift-cache',
                str(root / 'GuardCore.swift'), str(root / 'main.swift'),
                '-o', str(binary)], timeout=300)
(contents / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'com.intentional-browsing.guard',
    'CFBundleName': 'Intentional Browsing Guard',
    'CFBundleExecutable': 'BrowserGuard',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '0.2.0',
    'CFBundleVersion': '2',
    'LSMinimumSystemVersion': '14.0',
    'LSUIElement': True,
    'NSHighResolutionCapable': True,
    'IBExtensionID': extension_id,
}))
run_step('Signing the local guard...', ['/usr/bin/codesign', '--force', '--sign', '-', str(app)], timeout=30)
run_step('Verifying the signature...', ['/usr/bin/codesign', '--verify', '--strict', str(app)], timeout=30)
print(app, flush=True)
