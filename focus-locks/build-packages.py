"""Package the same local content scripts for Chromium and Firefox, without installs."""
import json
from pathlib import Path
import shutil
import zipfile

root = Path(__file__).resolve().parent
source = root / 'extension'
output = root / 'packages'
output.mkdir(exist_ok=True)
for browser in ('chromium', 'firefox'):
    target = output / browser
    target.mkdir(exist_ok=True)
    for path in source.iterdir():
        if path.suffix in ('.js', '.css', '.json'):
            shutil.copy2(path, target / path.name)
    if browser == 'firefox':
        manifest = json.loads((target / 'manifest.json').read_text())
        # The native guard currently supports Google Chrome on macOS only.
        for key in ('background', 'key', 'minimum_chrome_version', 'permissions', 'host_permissions', 'incognito'):
            manifest.pop(key, None)
        manifest['permissions'] = ['storage']
        manifest['background'] = {'scripts': ['linkedin-policy.js', 'linkedin-background.js']}
        (target / 'guard-background.js').unlink(missing_ok=True)
        (target / 'background.js').unlink(missing_ok=True)
        manifest['browser_specific_settings'] = {'gecko': {
            'id': 'intentional-browsing@local.invalid', 'strict_min_version': '109.0'
        }}
        (target / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    with zipfile.ZipFile(output / f'{browser}.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(target.iterdir()):
            archive.write(path, path.name)
print('Created Chromium and Firefox packages. No browser settings changed.')
