"""Build the local Mac guard; does not install or start it."""
from pathlib import Path
import hashlib
import json
import plistlib
import subprocess

root = Path(__file__).resolve().parent
output = root.parent / 'build' / 'macos-guard'
app = output / 'Intentional Browsing Guard.app'
contents = app / 'Contents'
binary = contents / 'MacOS' / 'BrowserGuard'
binary.parent.mkdir(parents=True, exist_ok=True)
manifest = json.loads((root.parent / 'extension' / 'manifest.json').read_text())
extension_id = ''.join(chr(97 + int(c, 16)) for c in hashlib.sha256(
    str((root.parent / 'packages' / 'chromium').resolve()).encode()).hexdigest()[:32])
(root / 'extension-id.txt').write_text(extension_id + '\n')
subprocess.run(['/usr/bin/xcrun', 'swiftc', '-O', '-module-cache-path', '/private/tmp/intentional-swift-cache',
                str(root / 'GuardCore.swift'), str(root / 'main.swift'),
                '-o', str(binary)], check=True)
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
subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(app)], check=True)
subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(app)], check=True)
print(app)
