"""Verify the selected Mandarin voice covers current prompts without stale assets."""
import hashlib, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
folder = ROOT / 'SpeakFlow/Resources/ChineseAudio'
manifest = json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
assert manifest['voice'] == 'zf_003' and manifest['language'] == 'zh-CN'
assert manifest['offline_generation'] is True
expected = {x['id']: x['meaningZh'] for x in json.loads((ROOT/'SpeakFlow/Resources/CuratedWords.json').read_text(encoding='utf-8'))}
expected.update({'status.'+str(n): text for n,text in enumerate(['练习已暂停，准备好后点继续','没有听到声音，请再试一次','本轮练习完成'])})
assert len(manifest['entries']) == len(expected) == 3003
assert {x['id'] for x in manifest['entries']} == set(expected)
for entry in manifest['entries']:
    assert entry['text'] == expected[entry['id']]
    assert Path(entry['file']).name == entry['file'] and entry['file'].endswith('.m4a')
    assert 0.04 < entry['seconds'] < 60
    data = (folder/entry['file']).read_bytes()
    assert len(data) == entry['bytes'] and b'ftyp' in data[:32]
    assert hashlib.sha256(data).hexdigest() == entry['sha256']
assert {p.name for p in folder.glob('*.m4a')} == {x['file'] for x in manifest['entries']}
assert manifest['total_bytes'] == sum(x['bytes'] for x in manifest['entries'])
print(f"PASS: 3000 Mandarin word prompts and 3 status prompts; {manifest['total_bytes']/1e6:.2f} MB before duplicate sharing")
