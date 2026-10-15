"""Verify shipped offline speech covers the exact current bank, with intact assets."""
import hashlib, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / 'SpeakFlow/Resources/HeartAudio'
manifest = json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
assert manifest['voice'] == 'af_heart' and manifest['language'] == 'en-US'
assert manifest['offline_generation'] is True
expected = {}
for kind, name, field in [('word','CuratedWords','word'),('sentence','CuratedSentences','text')]:
    for item in json.loads((ROOT/f'SpeakFlow/Resources/{name}.json').read_text(encoding='utf-8')):
        expected[item['id']] = (kind,item[field])
assert len(expected) == 4200 and len(manifest['entries']) == 4200
assert {x['id'] for x in manifest['entries']} == set(expected)
for entry in manifest['entries']:
    assert (entry['kind'],entry['text']) == expected[entry['id']], entry['id']
    assert Path(entry['file']).name == entry['file'] and entry['file'].endswith('.m4a')
    assert 0.04 < entry['seconds'] < 60, entry['id']
    data = (folder/entry['file']).read_bytes()
    assert len(data) == entry['bytes'] and b'ftyp' in data[:32]
    assert hashlib.sha256(data).hexdigest() == entry['sha256'], entry['id']
assert {p.name for p in folder.glob('*.m4a')} == {x['file'] for x in manifest['entries']}
assert manifest['total_bytes'] == sum(x['bytes'] for x in manifest['entries'])
print(f"PASS: all 4200 Heart audio mappings and hashes; {manifest['total_bytes']/1e6:.2f} MB")
