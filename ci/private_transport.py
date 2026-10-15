"""Owner-only CI transport. Private key and private file bytes are never printed."""
import contextlib
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def git(*args, cwd, env):
    result = subprocess.run(['git', *args], cwd=cwd, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError('Private repository operation failed; no credential or private log was printed')
    return result.stdout.decode('utf-8', errors='strict').strip()


@contextlib.contextmanager
def authentication():
    secret = os.environ.pop('PRIVATE_RESOURCE_SSH_KEY', '')
    repository = os.environ.get('PRIVATE_RESOURCE_REPOSITORY', '')
    if repository != 'Shiftyun/SpeakFlow-Resources' or not secret.startswith('-----BEGIN OPENSSH PRIVATE KEY-----'):
        raise RuntimeError('Private repository credentials unavailable')
    # The environment variable is removed before spawning git, and the key is outside the workspace.
    with tempfile.TemporaryDirectory(prefix='speakflow-key-', dir=os.environ.get('RUNNER_TEMP')) as folder:
        key = Path(folder) / 'deploy-key'
        key.write_text(secret.rstrip() + '\n', encoding='utf-8')
        key.chmod(0o600)
        secret = ''
        env = os.environ.copy()
        env['GIT_TERMINAL_PROMPT'] = '0'
        env['GIT_SSH_COMMAND'] = (
            f'ssh -i "{key}" -o IdentitiesOnly=yes -o BatchMode=yes '
            f'-o StrictHostKeyChecking=yes -o UserKnownHostsFile="{ROOT / "ci/github_known_hosts"}"'
        )
        yield env, f'git@github.com:{repository}.git'


def validate_entry(entry):
    path = PurePosixPath(entry['path'])
    if (path.is_absolute() or '..' in path.parts or '\\' in entry['path']
            or not str(path).startswith('SpeakFlow/Resources/')
            or str(path) == 'SpeakFlow/Resources/Info.plist'):
        raise ValueError('Invalid private resource path')
    if not isinstance(entry['bytes'], int) or entry['bytes'] < 0:
        raise ValueError('Invalid private resource length')
    if len(entry['sha256']) != 64 or any(c not in '0123456789abcdef' for c in entry['sha256']):
        raise ValueError('Invalid private resource hash')
    return path


def hydrate():
    lock = json.loads((ROOT / 'ci/resource-lock.json').read_text(encoding='utf-8'))
    destination = ROOT / '.private-resources'
    if destination.exists():
        raise RuntimeError('Resource staging folder must be new')
    with authentication() as (env, remote):
        git('clone', '--depth=1', '--single-branch', '--branch=main', remote, str(destination), cwd=ROOT, env=env)
        if git('rev-parse', 'HEAD', cwd=destination, env=env) != lock['commit']:
            raise RuntimeError('Private resource commit differs from the approved lock')
    manifest_bytes = (destination / 'manifest.json').read_bytes()
    if hashlib.sha256(manifest_bytes).hexdigest() != lock['manifest_sha256']:
        raise RuntimeError('Private manifest differs from the approved lock')
    entries = json.loads(manifest_bytes)['files']
    if len({entry['path'] for entry in entries}) != len(entries):
        raise RuntimeError('Duplicate private resource path')
    # Verify every resource before copying any of them into the build tree.
    for entry in entries:
        relative = validate_entry(entry)
        source = destination / 'payload' / str(relative)
        if source.is_symlink() or source.resolve() != (destination / 'payload').joinpath(*relative.parts).absolute():
            raise RuntimeError('Unsafe resource source')
        data = source.read_bytes()
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise RuntimeError('Private resource verification failed')
    for entry in entries:
        relative = validate_entry(entry)
        target = ROOT.joinpath(*relative.parts)
        if target.exists() or target.is_symlink():
            raise RuntimeError('Refusing to overwrite a public or existing file')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(destination / 'payload' / str(relative), target)
    print('Private resources verified and prepared; audio files remain excluded from public Git history.', flush=True)


def deliver():
    # Resource fetch failure must not copy any credentials or partial private checkout.
    output = ROOT / 'build/output'
    diagnostics = ROOT / 'build/private-diagnostics'
    delivery = ROOT / '.private-delivery'
    run_id = os.environ.get('GITHUB_RUN_ID', '')
    if not run_id.isdigit() or delivery.exists():
        raise RuntimeError('Invalid private delivery staging')
    with authentication() as (env, remote):
        # Branch contents are generated deliveries only; the resource main branch is untouched.
        git('clone', '--depth=1', '--single-branch', '--branch=deliveries', remote, str(delivery), cwd=ROOT, env=env)
        latest = delivery / 'latest'
        latest.mkdir(exist_ok=True)
        # Clear only this generated directory, after confirming it is inside our new clone.
        if latest.is_symlink() or latest.resolve().parent != delivery.resolve():
            raise RuntimeError('Unsafe delivery target')
        for old in latest.iterdir():
            if old.is_file() and not old.is_symlink():
                old.unlink()
            else:
                raise RuntimeError('Unexpected private delivery item')
        for folder in [output, diagnostics]:
            if not folder.exists():
                continue
            for source in folder.iterdir():
                if not source.is_file() or source.is_symlink():
                    continue
                if source.stat().st_size >= 99_000_000:
                    raise RuntimeError('Private delivery file exceeds the supported Git file budget')
                shutil.copyfile(source, latest / source.name)
        metadata = {
            'public_commit': os.environ.get('GITHUB_SHA'), 'run_id': run_id,
            'run_url': os.environ.get('SPEAKFLOW_RUN_URL'),
            'build_succeeded': (output / 'SpeakFlow-unsigned.ipa').is_file(),
            'files': [{'name': p.name, 'bytes': p.stat().st_size,
                       'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                      for p in sorted(latest.iterdir()) if p.is_file()]
        }
        (latest / 'DELIVERY.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
        git('config', 'user.name', 'SpeakFlow Build', cwd=delivery, env=env)
        git('config', 'user.email', 'speakflow@users.noreply.github.com', cwd=delivery, env=env)
        git('add', '--', 'latest', cwd=delivery, env=env)
        git('commit', '-m', f'Private build delivery {run_id}', cwd=delivery, env=env)
        git('push', 'origin', 'HEAD:deliveries', cwd=delivery, env=env)
    print('Build files and diagnostics saved to the private delivery repository. No public artifacts uploaded.', flush=True)


if __name__ == '__main__':
    try:
        {'hydrate': hydrate, 'deliver': deliver}[sys.argv[1]]()
    except Exception:
        # Even subprocess errors must not include a private key, URL credentials or a raw log.
        print('Private resource/delivery operation failed. No private output was published.', file=sys.stderr)
        sys.exit(1)
