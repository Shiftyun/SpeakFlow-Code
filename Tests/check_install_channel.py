"""Verify manual workflow controls and IPA packaging with synthetic fixtures."""
import importlib.util
import json
import plistlib
import stat
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('package_ipa', ROOT / 'scripts/package_ipa.py')
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class InstallChannelTests(unittest.TestCase):
    def fixture(self, directory, platform='iPhoneOS'):
        app = Path(directory) / 'SpeakFlow.app'
        app.mkdir()
        (app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.speakflow.personal',
            'CFBundleExecutable': 'SpeakFlow', 'CFBundleSupportedPlatforms': [platform],
            'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1',
        }))
        (app / 'SpeakFlow').write_bytes(b'synthetic executable, not a real iOS build')
        for name in ('SampleWords.json', 'SampleSentences.json'):
            (app / name).write_text('[]', encoding='utf-8')
        return app

    def test_device_bundle_layout_executable_permissions_and_checksum(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.fixture(directory)
            output = Path(directory) / 'output/SpeakFlow-unsigned.ipa'
            details = packager.package_app(app, output)
            with zipfile.ZipFile(output) as archive:
                self.assertIsNone(archive.testzip())
                executable = archive.getinfo('Payload/SpeakFlow.app/SpeakFlow')
                self.assertTrue((executable.external_attr >> 16) & stat.S_IXUSR)
                self.assertIn('Payload/SpeakFlow.app/Info.plist', archive.namelist())
                self.assertEqual(len(archive.namelist()), 4)
            self.assertIn(details['sha256'], output.with_suffix('.ipa.sha256').read_text())
            self.assertIn('unsigned', details['signing'])

    def test_simulator_bundle_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.fixture(directory, 'iPhoneSimulator')
            with self.assertRaisesRegex(ValueError, 'device app'):
                packager.package_app(app, Path(directory) / 'output.ipa')

    def test_missing_executable_and_signed_bundle_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.fixture(directory)
            (app / '_CodeSignature').mkdir()
            with self.assertRaisesRegex(ValueError, 'unsigned output'):
                packager.package_app(app, Path(directory) / 'output.ipa')
            (app / '_CodeSignature').rmdir()
            (app / 'SpeakFlow').unlink()
            with self.assertRaisesRegex(ValueError, 'Missing app executable'):
                packager.package_app(app, Path(directory) / 'output.ipa')

    def test_output_inside_app_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            app = self.fixture(directory)
            with self.assertRaisesRegex(ValueError, 'outside'):
                packager.package_app(app, app / 'output.ipa')

    def test_workflow_is_manual_and_requires_free_usage_checks(self):
        # JSON is a valid YAML subset, so this workflow needs no third-party parser.
        workflow = json.loads((ROOT / '.github/workflows/ios-build.yml').read_text(encoding='utf-8'))
        self.assertEqual(set(workflow['on']), {'workflow_dispatch'})
        input_config = workflow['on']['workflow_dispatch']['inputs']['free_usage_confirmed']
        self.assertEqual(input_config['type'], 'boolean')
        self.assertFalse(input_config['default'])
        self.assertEqual(workflow['permissions'], {'contents': 'read'})
        job = workflow['jobs']['build']
        self.assertIn("vars.FREE_ACTIONS_CONFIRMED == 'true'", job['if'])
        self.assertIn('inputs.free_usage_confirmed', job['if'])
        self.assertEqual(job['runs-on'], 'macos-26')
        self.assertLessEqual(job['timeout-minutes'], 30)
        for step in job['steps']:
            if 'uses' in step:
                action, commit = step['uses'].split('@')
                self.assertIn(action, ['actions/checkout', 'actions/upload-artifact'])
                self.assertEqual(len(commit), 40)
            if step.get('uses', '').startswith('actions/upload-artifact@'):
                self.assertEqual(step['with']['retention-days'], 1)
        # Private transport is owner-triggered; private outputs must never be uploaded here.
        self.assertIn('github.actor == github.repository_owner', job['if'])
        self.assertIn("github.ref == 'refs/heads/main'", job['if'])
        self.assertIn('github.event.repository.private == false', job['if'])
        self.assertFalse(any('upload-artifact' in step.get('uses', '') for step in job['steps']))
        self.assertTrue(any(step.get('if') == 'always()' and 'deliver' in step.get('run', '') for step in job['steps']))


if __name__ == '__main__':
    unittest.main(verbosity=2)
