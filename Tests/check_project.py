"""Windows-safe resource and Xcode project checks; does not compile Swift."""
from pathlib import Path
import json
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise ValueError(message)


def parse_project(text):
    """Parse the OpenStep plist subset used by this conventional project."""
    tokens = []
    lexer = re.compile(r'\s+|//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,"/]+', re.S)
    position = 0
    for match in lexer.finditer(text):
        require(match.start() == position, 'Unrecognized project syntax')
        position = match.end()
        token = match.group()
        if not token.isspace() and not token.startswith(('//', '/*')):
            tokens.append(token)
    require(position == len(text), 'Unparsed project content')
    index = 0

    def take(expected=None):
        nonlocal index
        require(index < len(tokens), 'Unexpected end of project')
        token = tokens[index]
        index += 1
        require(expected is None or token == expected, f'Expected {expected}, got {token}')
        return token

    def value():
        token = take()
        if token == '{':
            result = {}
            while tokens[index] != '}':
                key = take()
                if key.startswith('"'):
                    key = json.loads(key)
                require(key not in result, f'Duplicate project key: {key}')
                take('=')
                result[key] = value()
                take(';')
            take('}')
            return result
        if token == '(':
            result = []
            while tokens[index] != ')':
                result.append(value())
                if tokens[index] != ')':
                    take(',')
            take(')')
            return result
        require(token not in '{}()=;,', 'Unexpected punctuation')
        return json.loads(token) if token.startswith('"') else token

    result = value()
    require(index == len(tokens), 'Extra project tokens')
    return result


def check_samples():
    for filename, answer_field in [('SampleWords', 'word'), ('SampleSentences', 'text')]:
        data = json.loads((ROOT / f'SpeakFlow/Resources/{filename}.json').read_text(encoding='utf-8'))
        require(10 <= len(data) <= 20, f'{filename}: expected 10–20 items')
        require(len({item['id'] for item in data}) == len(data), f'{filename}: duplicate IDs')
        lengths = []
        for item in data:
            require(isinstance(item['id'], str) and item['id'].strip(), 'Missing stable ID')
            require(isinstance(item[answer_field], str) and item[answer_field].strip(), 'Empty answer')
            answers = item['acceptedAnswers']
            require(isinstance(answers, list) and item[answer_field] in answers, 'Canonical answer not accepted')
            require(all(isinstance(answer, str) and answer.strip() for answer in answers), 'Empty accepted answer')
            require(len(set(answers)) == len(answers), 'Duplicate accepted answer')
            require(type(item['difficulty']) is int and 1 <= item['difficulty'] <= 3, 'Invalid difficulty')
            require(item['correctCount'] == item['wrongCount'] == item['mastery'] == 0, 'Samples already practiced')
            require(item['lastPracticedAt'] is None and item['pronunciation'] is None, 'Unexpected history/audio')
            if filename == 'SampleWords':
                require(isinstance(item['meaningZh'], str) and re.search(r'[\u4e00-\u9fff]', item['meaningZh']), 'Missing Chinese meaning')
                require({'phonetic', 'exampleSentence'} <= item.keys(), 'Missing reserved word fields')
            else:
                require('meaningZh' not in item, 'Sentence mode must not be a translation exercise')
                lengths.append(len(item['text'].split()))
        require(lengths == sorted(lengths), 'Sentences must progress from short to long')
        print(f'PASS: {filename}: {len(data)} usable items, stable IDs, pristine learning fields')


def check_xcode():
    project = parse_project((ROOT / 'SpeakFlow.xcodeproj/project.pbxproj').read_text(encoding='utf-8'))
    objects = project['objects']
    require(objects[project['rootObject']]['isa'] == 'PBXProject', 'Missing project root')
    single_refs = {'fileRef', 'mainGroup', 'productRefGroup', 'buildConfigurationList', 'productReference',
                   'target', 'targetProxy', 'containerPortal', 'remoteGlobalIDString', 'TestTargetID'}
    list_refs = {'children', 'files', 'buildPhases', 'dependencies', 'targets', 'buildConfigurations'}

    def walk(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key in single_refs:
                    require(item in objects, f'Dangling project reference: {key}={item}')
                if key in list_refs:
                    require(all(ref in objects for ref in item), f'Dangling list reference: {key}')
                walk(item)
        elif isinstance(value, list):
            for item in value:
                walk(item)
    walk(objects)

    files = {key: obj for key, obj in objects.items() if obj['isa'] == 'PBXFileReference' and obj['sourceTree'] == 'SOURCE_ROOT'}
    for obj in files.values():
        path = ROOT / obj['path']
        require(path.is_dir() if obj.get('lastKnownFileType') == 'folder' else path.is_file(), f'Missing file: {obj["path"]}')
    swift_paths = {str(path.relative_to(ROOT)).replace('\\', '/') for path in ROOT.glob('SpeakFlow/**/*.swift')}
    require(swift_paths == {obj['path'] for obj in files.values() if obj['path'].startswith('SpeakFlow/') and obj['path'].endswith('.swift')}, 'App Swift file references incomplete')
    targets = {obj['name']: obj for obj in objects.values() if obj['isa'] == 'PBXNativeTarget'}
    require(set(targets) == {'SpeakFlow', 'SpeakFlowTests'}, 'App/test targets missing')
    for name, target in targets.items():
        phases = {objects[ref]['isa']: objects[ref] for ref in target['buildPhases']}
        require({'PBXSourcesBuildPhase', 'PBXResourcesBuildPhase', 'PBXFrameworksBuildPhase'} <= phases.keys(), 'Missing build phase')
        def phase_paths(phase):
            refs = [objects[objects[ref]['fileRef']]['path'] for ref in phases[phase]['files']]
            require(len(set(refs)) == len(refs), 'Duplicate build input')
            return set(refs)
        expected_sources = swift_paths if name == 'SpeakFlow' else {str(p.relative_to(ROOT)).replace('\\', '/') for p in ROOT.glob('Tests/*.swift')}
        require(phase_paths('PBXSourcesBuildPhase') == expected_sources, f'{name}: wrong source membership')
        expected_resources = {str(p.relative_to(ROOT)).replace('\\', '/') for p in ROOT.glob('SpeakFlow/Resources/*.json')}
        expected_resources.add('SpeakFlow/Resources/ContentLicenses.txt')
        expected_resources.add('SpeakFlow/Resources/HeartAudio')
        expected_resources.add('SpeakFlow/Resources/ChineseAudio')
        expected_resources.update(str(p.relative_to(ROOT)).replace('\\', '/') for p in ROOT.glob('SpeakFlow/Resources/Audio/*'))
        require(phase_paths('PBXResourcesBuildPhase') == expected_resources, f'{name}: content resources not bundled')
        configs = objects[target['buildConfigurationList']]['buildConfigurations']
        for config in configs:
            settings = objects[config]['buildSettings']
            require(settings['TARGETED_DEVICE_FAMILY'] == '1', 'Expected iPhone target')
            require('DEVELOPMENT_TEAM' not in settings, 'Personal signing identity must not be committed')
            if name == 'SpeakFlow':
                require(settings['PRODUCT_BUNDLE_IDENTIFIER'] == 'com.speakflow.personal', 'Bundle ID drift')
                require((ROOT / settings['INFOPLIST_FILE']).is_file(), 'Missing Info.plist')
            else:
                require(settings['BUNDLE_LOADER'] == '$(TEST_HOST)', 'Missing hosted test loader')
        if name == 'SpeakFlowTests':
            require(len(target['dependencies']) == 1, 'Test target must depend on app')
            dependency = objects[target['dependencies'][0]]
            require(objects[dependency['target']]['name'] == 'SpeakFlow', 'Wrong test dependency')
    scheme = ET.parse(ROOT / 'SpeakFlow.xcodeproj/xcshareddata/xcschemes/SpeakFlow.xcscheme')
    for ref in scheme.findall('.//BuildableReference'):
        require(ref.attrib['BlueprintIdentifier'] in objects, 'Scheme points to missing target')
        require(ref.attrib['ReferencedContainer'] == 'container:SpeakFlow.xcodeproj', 'Wrong scheme container')
    require(len(scheme.findall('.//TestableReference')) == 1, 'Test target not in scheme')
    ET.parse(ROOT / 'SpeakFlow.xcodeproj/project.xcworkspace/contents.xcworkspacedata')
    info = plistlib.loads((ROOT / 'SpeakFlow/Resources/Info.plist').read_bytes())
    require(info['CFBundleDisplayName'] == 'SpeakFlow', 'Incorrect product name')
    require(info['CFBundleIdentifier'] == '$(PRODUCT_BUNDLE_IDENTIFIER)', 'Info.plist Bundle ID drift')
    require(all(info.get(key) for key in ('NSMicrophoneUsageDescription', 'NSSpeechRecognitionUsageDescription')), 'Speech privacy descriptions missing')
    print('PASS: project syntax, all file/object references, target membership, resources, scheme, workspace and plist')


def check_document_links():
    for path in [ROOT / 'README.md', *ROOT.glob('docs/*.md')]:
        for target in re.findall(r'\]\(([^)]+)\)', path.read_text(encoding='utf-8')):
            if not target.startswith(('https://', 'http://')):
                require((path.parent / target).is_file(), f'Broken link: {path.name} → {target}')
    print('PASS: local documentation links')


def check_formal_banks():
    manifest = json.loads((ROOT / 'SpeakFlow/Resources/ContentSources.json').read_text(encoding='utf-8'))
    entries = manifest['entries']
    for name, count, field in [('CuratedWords', 3000, 'word'), ('CuratedSentences', 1200, 'text')]:
        items = json.loads((ROOT / f'SpeakFlow/Resources/{name}.json').read_text(encoding='utf-8'))
        require(len(items) == count, f'{name}: wrong full-bank count')
        require(len({v['id'] for v in items}) == count, f'{name}: duplicate IDs')
        normalized = [' '.join(re.findall(r'[a-z0-9]+', v[field].lower())) for v in items]
        require(len(set(normalized)) == count, f'{name}: duplicate normalized prompts')
        for item in items:
            require(item[field] in item['acceptedAnswers'], 'Canonical answer not accepted')
            require(item['id'] in entries, 'Missing source provenance')
            require(1 <= item['difficulty'] <= 3, 'Invalid difficulty')
            require(item['correctCount'] == item['wrongCount'] == 0, 'Shipped learning history')
            if field == 'word':
                require(re.search(r'[\u4e00-\u9fff]', item['meaningZh']), 'Missing Chinese meaning')
                require(bool(item.get('phonetic', '').strip()), 'Missing American pronunciation guide')
                require(len(item['meaningZh'].split('；')) <= 2, 'Word prompt has too many senses')
            else:
                require('meaningZh' not in item, 'Sentence mode is listening, not translation')
        print(f'PASS: {name}: {count} unique usable entries with source provenance')


if __name__ == '__main__':
    try:
        check_samples()
        check_formal_banks()
        check_xcode()
        check_document_links()
    except (ValueError, KeyError, IndexError, OSError, ET.ParseError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
    print('Static checks only. Swift/XCTest compilation and iPhone behavior remain unverified.')
