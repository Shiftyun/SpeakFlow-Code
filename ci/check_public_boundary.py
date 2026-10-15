"""Reject private media or personal delivery data in the publicly tracked tree."""
from pathlib import Path
import json
import re
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode('utf-8').split('\0')
for name in filter(None, names):
    path = Path(name)
    assert path.suffix.lower() not in {'.m4a', '.mp3', '.wav', '.ipa', '.zip', '.p12', '.onnx', '.pt', '.bin'}, 'Private binary is tracked'
    assert not name.startswith(('.private-', 'build/', 'docs/previews/', 'docs/kokoro-preview/')), 'Private folder is tracked'
    assert not name.startswith('SpeakFlow/Resources/') or name == 'SpeakFlow/Resources/Info.plist', 'Private bank/audio resource is tracked'
    data = (ROOT / name).read_bytes()
    assert not re.search(br'-----BEGIN OPENSSH PRIVATE KEY-----\r?\n[A-Za-z0-9+/]', data), 'Private key is tracked'
workflow = json.loads((ROOT / '.github/workflows/ios-build.yml').read_text(encoding='utf-8'))
assert set(workflow['on']) == {'workflow_dispatch'}, 'Only owner manual builds are supported'
assert workflow['permissions'] == {'contents': 'read'}
job = workflow['jobs']['build']
assert 'github.actor == github.repository_owner' in job['if']
assert "github.ref == 'refs/heads/main'" in job['if']
assert 'github.event.repository.private == false' in job['if']
assert job['runs-on'] == 'macos-26'
assert not any('upload-artifact' in s.get('uses', '') for s in job['steps']), 'Public artifacts are forbidden'
assert any(s.get('if') == 'always()' and 'deliver' in s.get('run', '') for s in job['steps'])
print('PASS: public tree excludes private resources and all build outputs; owner-only standard macOS workflow has no public uploads')
