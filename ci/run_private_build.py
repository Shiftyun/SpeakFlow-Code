"""Keep raw compiler/test diagnostics private; publish only fixed progress messages."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import threading

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
            process = subprocess.Popen([sys.executable, script], cwd=ROOT, env=environment,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, errors='replace', bufsize=1, start_new_session=True)
            timed_out = threading.Event()
            def stop_process():
                timed_out.set()
                try: os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError: pass
            timer = threading.Timer(20 * 60, stop_process)
            timer.daemon = True
            timer.start()
            reported_error = False
            try:
                for line in process.stdout:
                    log.write(line)
                    log.flush()
                    # Never forward an arbitrary line, filename, user text or test diagnostic.
                    if line.startswith('+ xcodebuild'):
                        label = 'Xcode project inspection started.' if ' -list ' in line else (
                            'Simulator XCTest started.' if ' test' in line else 'Device Release compilation started.')
                        print(label, flush=True)
                    elif '** TEST SUCCEEDED **' in line:
                        print('Simulator XCTest passed.', flush=True)
                    elif '** BUILD SUCCEEDED **' in line:
                        print('Device Release compilation passed.', flush=True)
                    elif (': error:' in line or '** TEST FAILED **' in line) and not reported_error:
                        print('Xcode reported an error; full diagnostics remain private.', flush=True)
                        reported_error = True
                result = process.wait()
            finally:
                timer.cancel()
            if result or timed_out.is_set():
                print(description + ' failed or reached the private diagnostic timeout. Saving results privately.', flush=True)
                sys.exit(result if result > 0 else 1)
        print(description + ' passed.', flush=True)
