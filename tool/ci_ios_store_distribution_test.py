import hashlib
import json
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

from ios_store_distribution import (SOURCE_URL, make_source, release_notes,
                                    write_source, validate_source, entitlements)
from platform_releases import validated_files, refresh_ios_store
from ci_platform_releases_test import FakeGitHub


class StoreDistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.ipa = self.root / 'Lokal.ipa'
        self.info = {'CFBundleIdentifier': 'app.lokal.mobile', 'CFBundleShortVersionString': '1.0.0',
                     'CFBundleVersion': '162', 'MinimumOSVersion': '16.0', 'CFBundleExecutable': 'Runner',
                     'NSCameraUsageDescription': 'Scan a desktop pairing code.'}
        self.binary = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 0, 0, 0, 0)
        self.metadata = {'bundle_id': 'app.lokal.mobile', 'version': '1.0.0', 'build': '162',
                         'minimum_ios': '16.0', 'source_commit': 'a' * 40}
        self.package()

    def package(self, extra=False):
        with zipfile.ZipFile(self.ipa, 'w') as archive:
            archive.writestr('Payload/Runner.app/Info.plist', plistlib.dumps(self.info))
            archive.writestr('Payload/Runner.app/Runner', self.binary)
            if extra:
                archive.writestr('Payload/Runner.app/PlugIns/Extra.appex/Info.plist', b'fixture')
        self.metadata['sha256'] = hashlib.sha256(self.ipa.read_bytes()).hexdigest()
        self.ipa.with_suffix('.ipa.json').write_text(json.dumps(self.metadata))

    def test_source_matches_package_identity_size_permissions_and_classic_schema(self):
        source = write_source(self.root, date='2026-11-08T20:00:00Z')
        self.assertEqual(source['sourceURL'], SOURCE_URL)
        app = source['apps'][0]
        self.assertEqual(app['bundleIdentifier'], 'app.lokal.mobile')
        self.assertNotIn('marketplaceID', app)
        version = app['versions'][0]
        self.assertEqual((version['version'], version['buildVersion']), ('1.0.0', '162'))
        self.assertEqual(version['size'], self.ipa.stat().st_size)
        self.assertEqual(version['minOSVersion'], '16.0')
        self.assertTrue(version['downloadURL'].endswith('/Lokal.ipa?build=162'))
        self.assertEqual(app['appPermissions'], {'entitlements': [], 'privacy': {
            'NSCameraUsageDescription': self.info['NSCameraUsageDescription']}})
        validate_source(self.root)

    def test_same_version_new_build_has_distinct_store_identity_and_download_url(self):
        first = write_source(self.root)['apps'][0]['versions'][0]
        self.info['CFBundleVersion'] = self.metadata['build'] = '163'
        self.package()
        second = write_source(self.root)['apps'][0]['versions'][0]
        self.assertEqual(first['version'], second['version'])
        self.assertNotEqual(first['buildVersion'], second['buildVersion'])
        self.assertNotEqual(first['downloadURL'], second['downloadURL'])

    def test_tampered_source_is_rejected_before_publication(self):
        source = write_source(self.root)
        for key, value in [('buildVersion', '999'), ('downloadURL', 'https://example.invalid/other.ipa'), ('size', 1)]:
            modified = json.loads(json.dumps(source))
            modified['apps'][0]['versions'][0][key] = value
            (self.root / 'altstore-source.json').write_text(json.dumps(modified))
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_source(self.root)

    def test_mismatched_bundle_or_corrupt_package_is_rejected(self):
        self.info['CFBundleVersion'] = '161'
        self.package()
        with self.assertRaisesRegex(ValueError, 'CFBundleVersion'):
            write_source(self.root)
        self.ipa.write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'checksum'):
            write_source(self.root)

    def test_new_extensions_require_explicit_permission_review(self):
        self.package(extra=True)
        with self.assertRaisesRegex(ValueError, 'extensions'):
            write_source(self.root)

    def test_entitlements_are_extracted_from_actual_code_signature(self):
        plist = plistlib.dumps({'application-identifier': 'TEAM.app.lokal.mobile',
                               'com.apple.developer.networking.multicast': True})
        payload = struct.pack('>II', 0xfade7171, len(plist) + 8) + plist
        blob = struct.pack('>IIIII', 0xfade0cc0, 20 + len(payload), 1, 5, 20) + payload
        header = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 1, 16, 0, 0)
        binary = header + struct.pack('<4I', 0x1d, 16, 48, len(blob)) + blob
        self.assertEqual(entitlements(binary), ['com.apple.developer.networking.multicast'])
        with self.assertRaises(ValueError):
            entitlements(binary[:-5])

    def test_release_preamble_explains_setup_updates_refresh_and_preservation(self):
        notes = release_notes(self.metadata, '* Fixed playback.')
        self.assertLess(notes.index('Install and update'), notes.index("What's Changed"))
        for text in ('AltStore Classic', 'SideStore', SOURCE_URL, 'seven days', 'Do not uninstall',
                     'Refresh and Update', 'same Apple account', '* Fixed playback.'):
            self.assertIn(text, notes)
        self.assertNotIn('unsigned', notes.lower())
        self.assertNotIn('engineering', notes.lower())

    def test_publication_requires_source_matching_the_audited_package(self):
        for name in ('Lokal-source.tar.gz', 'Lokal-crash-symbols.tar.gz', 'LICENSE', 'THIRD_PARTY_NOTICES.md'):
            (self.root / name).write_bytes(b'audit fixture')
        (self.root / 'qualification.json').write_text(json.dumps({'source_commit': 'a' * 40}))
        (self.root / 'Lokal.ipa.sha256').write_text(self.metadata['sha256'] + '  Lokal.ipa\n')
        with self.assertRaises(FileNotFoundError):
            validated_files(self.root, 'ios', 'a' * 40)
        write_source(self.root)
        _, metadata = validated_files(self.root, 'ios', 'a' * 40)
        self.assertEqual(metadata['build'], 162)
        source = json.loads((self.root / 'altstore-source.json').read_text())
        source['apps'][0]['appPermissions']['privacy'] = {}
        (self.root / 'altstore-source.json').write_text(json.dumps(source))
        with self.assertRaises(ValueError):
            validated_files(self.root, 'ios', 'a' * 40)

    def published_fixture(self):
        github = FakeGitHub()
        row = github.add('ios', 'ios', 162, version='1.0.0')
        row['published_at'] = '2026-11-08T20:00:00Z'
        github.metadata[row['id'] * 10 + 1] = self.metadata.copy()
        github.metadata[row['id'] * 10 + 4] = {'source_commit': 'a' * 40}
        def download(release, destination, names=None):
            for name in names:
                content = json.dumps(self.metadata).encode() if name.endswith('.json') else self.ipa.read_bytes()
                (destination / name).write_bytes(content)
        github.download = download
        return github, row

    def test_refresh_repairs_missing_checksum_and_preserves_existing_package_id(self):
        github, row = self.published_fixture()
        original_id = row['assets'][0]['id']
        row['assets'] = [a for a in row['assets'] if not a['name'].endswith('.sha256')]
        refresh_ios_store(github)
        self.assertFalse(row['prerelease'], 'store refresh must retain a standard iOS release')
        assets = {a['name']: a for a in row['assets']}
        self.assertEqual(assets['Lokal.ipa']['id'], original_id)
        self.assertIn('Lokal.ipa.sha256', assets)
        self.assertIn('altstore-source.json', assets)
        self.assertNotIn('unsigned', row['body'].lower())
        source = github.metadata[assets['altstore-source.json']['id']]
        self.assertEqual(source['apps'][0]['versions'][0]['buildVersion'], '162')
        self.assertFalse(any(op[1].startswith('git/refs') for op in github.operations))

    def test_refresh_rejects_mismatched_ipa_before_any_remote_change(self):
        self.info['CFBundleVersion'] = '161'
        self.package()
        github, _ = self.published_fixture()
        with self.assertRaises(ValueError):
            refresh_ios_store(github)
        self.assertFalse(any(op[0] != 'GET' for op in github.operations))


if __name__ == '__main__':
    unittest.main()
