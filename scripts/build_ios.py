"""Run on a GitHub-hosted macOS runner with Xcode. Requires no signing secrets."""
import json
import os
import platform
import subprocess
import shutil
import time
from pathlib import Path

from package_ipa import package_app

ROOT = Path(__file__).resolve().parents[1]


def run(*command, capture=False):
    print('+ ' + ' '.join(command), flush=True)
    result = subprocess.run(command, cwd=ROOT, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else None


def choose_simulator(devices):
    candidates = []
    for runtime, entries in devices.items():
        if 'SimRuntime.iOS-' not in runtime:
            continue
        version = tuple(int(part) for part in runtime.rsplit('iOS-', 1)[1].split('-'))
        for device in entries:
            if device.get('isAvailable') and device.get('name', '').startswith('iPhone'):
                candidates.append((version, device['name'], device['udid']))
    if not candidates:
        raise RuntimeError('No available iPhone Simulator; record image/runtime details and repair before continuing')
    return max(candidates)[2]


def main():
    if platform.system() != 'Darwin':
        raise RuntimeError('Xcode build requires macOS; Windows checks cannot replace it')
    build_number = os.environ.get('SPEAKFLOW_RUN_NUMBER', '1')
    if not build_number.isdigit() or int(build_number) < 1:
        raise ValueError('Build number must be a positive integer')
    xcode_version = run('xcodebuild', '-version', capture=True)
    print(xcode_version, flush=True)
    run('xcodebuild', '-list', '-project', 'SpeakFlow.xcodeproj')
    devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json', capture=True))
    simulator = choose_simulator(devices['devices'])
    common = ['xcodebuild', '-project', 'SpeakFlow.xcodeproj', '-scheme', 'SpeakFlow',
              'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO',
              f'CURRENT_PROJECT_VERSION={build_number}']
    run(*common, '-configuration', 'Debug', '-sdk', 'iphonesimulator',
        '-destination', f'platform=iOS Simulator,id={simulator}',
        '-derivedDataPath', 'build/Simulator', '-resultBundlePath', 'build/TestResults.xcresult', 'test')
    # Capture the installed simulator app for visual review of UI changes.
    preview = ROOT / 'build/HomePreview.png'
    word_preview = ROOT / 'build/WordPreview.png'
    try:
        # XCTest may use a cloned device; explicitly boot/install on our chosen preview device.
        subprocess.run(['xcrun', 'simctl', 'boot', simulator], cwd=ROOT,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        subprocess.run(['xcrun', 'simctl', 'bootstatus', simulator, '-b'], cwd=ROOT, check=True, timeout=60)
        subprocess.run(['xcrun', 'simctl', 'install', simulator,
                       str(ROOT / 'build/Simulator/Build/Products/Debug-iphonesimulator/SpeakFlow.app')],
                       cwd=ROOT, check=True, timeout=120)
        subprocess.run(['xcrun', 'simctl', 'launch', simulator, 'com.speakflow.personal'],
                       cwd=ROOT, check=True, timeout=120)
        time.sleep(2)
        subprocess.run(['xcrun', 'simctl', 'io', simulator, 'screenshot', str(preview)],
                       cwd=ROOT, check=True, timeout=120)
        subprocess.run(['xcrun', 'simctl', 'terminate', simulator, 'com.speakflow.personal'], cwd=ROOT, timeout=120)
        subprocess.run(['xcrun', 'simctl', 'launch', simulator, 'com.speakflow.personal', '--preview-word'],
                       cwd=ROOT, check=True, timeout=120)
        time.sleep(2)
        subprocess.run(['xcrun', 'simctl', 'io', simulator, 'screenshot', str(word_preview)],
                       cwd=ROOT, check=True, timeout=120)
        subprocess.run(['xcrun', 'simctl', 'terminate', simulator, 'com.speakflow.personal'], cwd=ROOT, timeout=120)
        subprocess.run(['xcrun', 'simctl', 'launch', simulator, 'com.speakflow.personal', '--preview-sentence'], cwd=ROOT, check=True, timeout=120)
        time.sleep(2)
        subprocess.run(['xcrun', 'simctl', 'io', simulator, 'screenshot', str(ROOT/'build/SentencePreview.png')], cwd=ROOT, check=True, timeout=120)
        for name, flags in [('WaveformPreview', ['--preview-word', '--preview-waveform']),
                            ('SilencePreview', ['--preview-word', '--preview-waveform', '--preview-silence']),
                            ('SentenceWaveformPreview', ['--preview-sentence', '--preview-waveform']),
                            ('WordAnswerPreview', ['--preview-word', '--preview-answer']),
                            ('SentenceAnswerPreview', ['--preview-sentence', '--preview-answer']),
                            ('WordCorrectPreview', ['--preview-word', '--preview-correct']),
                            ('CompletedPreview', ['--preview-word', '--preview-completed'])]:
            subprocess.run(['xcrun', 'simctl', 'terminate', simulator, 'com.speakflow.personal'], cwd=ROOT, timeout=120)
            subprocess.run(['xcrun', 'simctl', 'launch', simulator, 'com.speakflow.personal', *flags], cwd=ROOT, check=True, timeout=120)
            time.sleep(2)
            subprocess.run(['xcrun', 'simctl', 'io', simulator, 'screenshot', str(ROOT/'build'/f'{name}.png')], cwd=ROOT, check=True, timeout=120)
    except (subprocess.SubprocessError, OSError) as error:
        print('Optional UI screenshot unavailable:', type(error).__name__, flush=True)
    run(*common, '-configuration', 'Release', '-sdk', 'iphoneos',
        '-destination', 'generic/platform=iOS', '-derivedDataPath', 'build/Device', 'build')
    app = ROOT / 'build/Device/Build/Products/Release-iphoneos/SpeakFlow.app'
    run('xcrun', 'lipo', str(app / 'SpeakFlow'), '-verify_arch', 'arm64')
    output = ROOT / 'build/output'
    details = package_app(app, output / 'SpeakFlow-unsigned.ipa')
    if preview.exists():
        shutil.copyfile(preview, output / 'HomePreview.png')
    if word_preview.exists():
        shutil.copyfile(word_preview, output / 'WordPreview.png')
    if (ROOT/'build/SentencePreview.png').exists():
        shutil.copyfile(ROOT/'build/SentencePreview.png', output/'SentencePreview.png')
    for name in ['WaveformPreview', 'SilencePreview', 'SentenceWaveformPreview', 'WordAnswerPreview', 'SentenceAnswerPreview', 'WordCorrectPreview', 'CompletedPreview']:
        if (ROOT/'build'/f'{name}.png').exists():
            shutil.copyfile(ROOT/'build'/f'{name}.png', output/f'{name}.png')
    details.update(commit=os.environ.get('SPEAKFLOW_COMMIT', 'local'),
                   run_url=os.environ.get('SPEAKFLOW_RUN_URL', ''),
                   xcode=xcode_version.strip(), simulator=simulator,
                   tests='XCTest command completed successfully',
                   installation='not verified; user must confirm launch and refresh')
    (output / 'BUILD_INFO.json').write_text(json.dumps(details, indent=2) + '\n', encoding='utf-8')
    (output / 'READ_ME.txt').write_text(
        'SpeakFlow: unsigned device build. This is not a signed installation package.\n'
        'AltStore Classic / AltServer must re-sign it with your free Apple Account.\n'
        'Cloud build success does not prove installation, launch or refresh success.\n'
        'See docs/INSTALL_WINDOWS_IPHONE.md in the project repository.\n', encoding='utf-8')
    summary_path = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary_path:
        with open(summary_path, 'a', encoding='utf-8') as summary:
            summary.write('## SpeakFlow\n\nXCTest and unsigned device build succeeded.\n\n'
                          'Download the artifact, extract it, then use AltStore Classic to re-sign the IPA. '
                          '**iPhone installation and refresh are still unverified.**\n')


if __name__ == '__main__':
    main()
