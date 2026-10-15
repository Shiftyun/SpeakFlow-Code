"""Keep compiler, test and resource diagnostics out of public Actions logs."""
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / 'build/private-diagnostics'
folder.mkdir(parents=True, exist_ok=True)
environment = os.environ.copy()
environment.pop('GITHUB_STEP_SUMMARY', None)
environment['PYTHONUNBUFFERED'] = '1'
environment['SPEAKFLOW_RUN_NUMBER'] = str(1000 + int(os.environ['GITHUB_RUN_NUMBER']))
steps = [
    ('Project and resource checks', ['Tests/check_project.py', 'Tests/check_install_channel.py',
                                    'Tests/check_heart_audio.py', 'Tests/check_chinese_audio.py',
                                    'ci/check_public_boundary.py']),
    ('Xcode tests, screenshots and device compilation', ['scripts/build_ios.py'])
]
with (folder / 'build.log').open('w', encoding='utf-8') as log:
    for description, scripts in steps:
        print(description + ' started. Detailed output is private.', flush=True)
        for script in scripts:
            result = subprocess.run([sys.executable, script], cwd=ROOT, env=environment, stdout=log, stderr=log)
            if result.returncode:
                print(description + ' failed. Diagnostics will be saved privately.', flush=True)
                sys.exit(result.returncode)
        print(description + ' passed.', flush=True)
