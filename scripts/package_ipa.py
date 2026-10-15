"""Package an unsigned device .app for later re-signing; never signs an app."""
import argparse
import hashlib
import json
import plistlib
import stat
import zipfile
from pathlib import Path


def package_app(app_path, output_path):
    app = Path(app_path).resolve()
    output = Path(output_path).resolve()
    if app.suffix != '.app' or not app.is_dir():
        raise ValueError('Expected an existing .app directory')
    if app in output.parents:
        raise ValueError('Output must be outside the app directory')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('Expected an iPhoneOS device app, not a simulator build')
    if info.get('CFBundleIdentifier') != 'com.speakflow.personal':
        raise ValueError('Unexpected Bundle Identifier')
    executable_name = info.get('CFBundleExecutable', '')
    if not executable_name or Path(executable_name).name != executable_name:
        raise ValueError('Invalid app executable name')
    executable = app / executable_name
    if not executable.is_file() or executable.stat().st_size == 0:
        raise ValueError('Missing app executable')
    if (app / 'embedded.mobileprovision').exists() or (app / '_CodeSignature').exists():
        raise ValueError('Expected unsigned output without a provisioning profile or signature directory')
    for resource in ('SampleWords.json', 'SampleSentences.json'):
        if not (app / resource).is_file():
            raise ValueError(f'Missing bundled resource: {resource}')
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(app.rglob('*')):
            if path.is_symlink():
                raise ValueError('Unexpected symlink in minimal app bundle')
            if path.is_file():
                name = 'Payload/' + app.name + '/' + path.relative_to(app).as_posix()
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                mode = 0o755 if path == executable else 0o644
                entry.external_attr = (stat.S_IFREG | mode) << 16
                archive.writestr(entry, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED)
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError('IPA ZIP integrity check failed')
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.ipa.sha256').write_text(f'{digest}  {output.name}\n', encoding='utf-8')
    return dict(bundle_identifier=info['CFBundleIdentifier'],
                version=info.get('CFBundleShortVersionString'),
                build=info.get('CFBundleVersion'), sha256=digest,
                signing='unsigned; requires AltStore/AltServer re-signing and device verification')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app')
    parser.add_argument('output')
    arguments = parser.parse_args()
    print(json.dumps(package_app(arguments.app, arguments.output), indent=2))
