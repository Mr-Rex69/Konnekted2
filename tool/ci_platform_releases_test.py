"""Exercise publication/migration failure paths without touching GitHub."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from platform_releases import consolidate, publish, move_tag


class FakeGitHub:
    def __init__(self):
        self.rows = {}
        self.refs = {}
        self.metadata = {}
        self.operations = []
        self.fail_upload = False
        self.serial = 100

    def add(self, tag, platform, build, *, draft=False, sha='a' * 40, version='7.5.2'):
        self.serial += 1
        identifier = self.serial
        names = (['Lokal-unsigned.ipa', 'Lokal-unsigned.ipa.json', 'Lokal-source.tar.gz',
                  'Lokal-crash-symbols.tar.gz', 'qualification.json', 'LICENSE',
                  'THIRD_PARTY_NOTICES.md', 'Lokal-unsigned.ipa.sha256'] if platform == 'ios'
                 else [f'Lokal-{version}-arm64.apk', 'full-metadata.json', 'SHA256SUMS'])
        row = {'id': identifier, 'tag_name': tag, 'draft': draft, 'prerelease': platform == 'ios',
               'name': tag, 'body': 'Release notes', 'published_at': f'2026-11-{identifier - 100:02d}',
               'assets': [{'id': identifier * 10 + n, 'name': name, 'size': 1} for n, name in enumerate(names)]}
        self.rows[identifier] = row
        self.refs[f'refs/tags/{tag}'] = sha
        self.metadata[identifier * 10 + 1] = {
            'version': version, 'build': str(build), 'versionCode': build,
            'commit': sha, 'source_commit': sha, 'flavor': 'full',
            'sha256': 'c' * 64,
        }
        return row

    def releases(self):
        return copy.deepcopy(list(self.rows.values()))

    def asset_json(self, asset):
        return copy.deepcopy(self.metadata[asset['id']])

    def api(self, path, method='GET', payload=None, missing=False):
        self.operations.append((method, path, copy.deepcopy(payload)))
        if path == 'git/matching-refs/tags':
            return [{'ref': ref, 'object': {'sha': sha}} for ref, sha in self.refs.items()]
        if path.startswith('git/ref/tags/'):
            sha = self.refs.get('refs/tags/' + path.split('/')[-1])
            return {'object': {'sha': sha}} if sha else None
        if path == 'git/refs' and method == 'POST':
            self.refs[payload['ref']] = payload['sha']
            return None
        if path.startswith('git/refs/tags/'):
            ref = 'refs/tags/' + path.split('/')[-1]
            if method == 'DELETE':
                del self.refs[ref]
            else:
                self.refs[ref] = payload['sha']
            return None
        if path.startswith('releases/tags/'):
            return next((copy.deepcopy(row) for row in self.rows.values()
                         if row['tag_name'] == path.split('/')[-1]), None)
        if path == 'releases' and method == 'POST':
            self.serial += 1
            row = {'id': self.serial, 'assets': [], 'html_url': 'fixture', **payload}
            self.rows[self.serial] = row
            return copy.deepcopy(row)
        if path.startswith('releases/assets/') and method == 'DELETE':
            identifier = int(path.split('/')[-1])
            for row in self.rows.values():
                row['assets'] = [a for a in row['assets'] if a['id'] != identifier]
            return None
        if path.startswith('releases/assets/') and method == 'PATCH':
            identifier = int(path.split('/')[-1])
            asset = next(a for row in self.rows.values() for a in row['assets'] if a['id'] == identifier)
            asset.update(payload)
            return copy.deepcopy(asset)
        identifier = int(path.split('/')[-1])
        if method == 'DELETE':
            del self.rows[identifier]
            return None
        if method == 'PATCH':
            self.rows[identifier].update(payload)
        return copy.deepcopy(self.rows[identifier])

    def upload(self, tag, files):
        self.operations.append(('UPLOAD', tag, None))
        if self.fail_upload:
            raise RuntimeError('Upload failed')
        row = next(row for row in self.rows.values() if row['tag_name'] == tag)
        for file in files:
            self.serial += 1
            row['assets'] = [a for a in row['assets'] if a['name'] != file.name]
            asset = {'id': self.serial * 10, 'name': file.name, 'size': file.stat().st_size}
            row['assets'].append(asset)
            if file.name.endswith('.json'):
                self.metadata[asset['id']] = json.loads(file.read_text())


class PlatformReleases(unittest.TestCase):
    def setUp(self):
        self.github = FakeGitHub()
        self.old = self.github.add('v7.5.1', 'android', 200)
        self.current = self.github.add('v7.5.2', 'android', 201)
        self.ios = self.github.add('ios-sideload-beta-143-attempt1', 'ios', 143, version='1.0.0')

    def test_migration_preserves_current_asset_ids_and_source_commits(self):
        expected_android = copy.deepcopy(self.current['assets'])
        expected_ios = copy.deepcopy(self.ios['assets'])
        consolidate(self.github, cleanup=True)
        self.assertEqual({r['tag_name'] for r in self.github.rows.values()}, {'android', 'ios'})
        self.assertEqual(self.current['assets'], expected_android)
        self.assertEqual(self.ios['assets'], expected_ios)
        self.assertEqual(set(self.github.refs), {'refs/tags/android', 'refs/tags/ios'})
        self.assertFalse(self.current['prerelease'])
        self.assertFalse(self.ios['prerelease'])
        self.assertEqual(self.ios['make_latest'], 'false')
        self.assertEqual(self.current['make_latest'], 'true')
        self.assertIn('lokal-platform:android version:7.5.2 build:201', self.current['body'])

    def test_dry_run_never_changes_releases_or_refs(self):
        consolidate(self.github, cleanup=True, dry_run=True)
        self.assertFalse(any(method != 'GET' for method, _, _ in self.github.operations))
        self.assertIn(self.old['id'], self.github.rows)

    def test_drafts_and_unrelated_tag_names_survive_cleanup(self):
        draft = self.github.add('v7.5.3', 'android', 202, draft=True)
        self.github.refs['refs/tags/source-backup'] = 'b' * 40
        consolidate(self.github, cleanup=True)
        self.assertIn(draft['id'], self.github.rows)
        self.assertIn('refs/tags/v7.5.3', self.github.refs)
        self.assertIn('refs/tags/source-backup', self.github.refs)

    def test_invalid_published_metadata_refuses_deletion(self):
        self.github.metadata[self.current['id'] * 10 + 1]['commit'] = 'main'
        with self.assertRaises(ValueError):
            consolidate(self.github, cleanup=True)
        self.assertFalse(any(method == 'DELETE' for method, _, _ in self.github.operations))

    def test_missing_iphone_symbols_blocks_all_migration_and_cleanup(self):
        self.ios['assets'] = [a for a in self.ios['assets'] if a['name'] != 'Lokal-crash-symbols.tar.gz']
        with self.assertRaises(ValueError):
            consolidate(self.github, cleanup=True)
        self.assertFalse(any(method != 'GET' for method, _, _ in self.github.operations))

    def test_only_two_explicit_tag_names_can_be_moved(self):
        for tag in ('main', 'refs/heads/main', 'v7.5.2', '../main'):
            with self.assertRaises(ValueError):
                move_tag(self.github, tag, 'a' * 40)

    def directory(self, build=202, sha='b' * 40):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        apk = root / 'Lokal-7.5.3-arm64.apk'
        apk.write_bytes(b'verified-apk-fixture')
        digest = hashlib.sha256(apk.read_bytes()).hexdigest()
        (root / 'full-metadata.json').write_text(json.dumps({
            'version': '7.5.3', 'versionCode': build, 'flavor': 'full', 'commit': sha, 'sha256': digest}))
        (root / 'SHA256SUMS').write_text(f'{digest}  {apk.name}\n')
        return root

    def test_successful_publication_keeps_one_release_and_prunes_after_upload(self):
        consolidate(self.github, cleanup=True)
        result = publish(self.github, 'android', self.directory(), 'b' * 40, 'New notes')
        self.assertEqual(result['id'], self.current['id'])
        self.assertIn('Lokal-7.5.3-arm64.apk', {a['name'] for a in self.current['assets']})
        self.assertNotIn('Lokal-7.5.2-arm64.apk', {a['name'] for a in self.current['assets']})
        self.assertEqual(self.github.refs['refs/tags/android'], 'b' * 40)
        upload_index = next(i for i, op in enumerate(self.github.operations) if op[0] == 'UPLOAD')
        asset_deletes = [i for i, op in enumerate(self.github.operations) if op[0] == 'DELETE' and op[1].startswith('releases/assets/')]
        self.assertTrue(all(i > upload_index for i in asset_deletes))

    def test_failed_upload_does_not_prune_existing_assets_or_move_the_tag(self):
        consolidate(self.github, cleanup=True)
        original = copy.deepcopy(self.current)
        self.github.fail_upload = True
        with self.assertRaises(RuntimeError):
            publish(self.github, 'android', self.directory(), 'b' * 40, 'New notes')
        self.assertEqual(self.current, original)
        self.assertEqual(self.github.refs['refs/tags/android'], 'a' * 40)

    def test_corrupt_apk_and_source_mismatch_fail_before_any_api_mutation(self):
        root = self.directory()
        (root / 'Lokal-7.5.3-arm64.apk').write_bytes(b'corrupt')
        with self.assertRaises(ValueError):
            publish(self.github, 'android', root, 'b' * 40, 'New notes')
        with self.assertRaises(ValueError):
            publish(self.github, 'android', self.directory(), 'c' * 40, 'New notes')
        self.assertEqual(self.github.operations, [])

    def test_lower_build_or_same_counter_with_different_source_is_refused(self):
        consolidate(self.github, cleanup=True)
        for build in (200, 201):
            with self.assertRaises(ValueError):
                publish(self.github, 'android', self.directory(build), 'b' * 40, 'New notes')
        self.assertFalse(any(op[0] == 'UPLOAD' for op in self.github.operations))

    def test_incomplete_iphone_package_is_never_published(self):
        with self.assertRaises(ValueError):
            publish(self.github, 'ios', self.directory(), 'b' * 40, 'New notes')
        self.assertEqual(self.github.operations, [])


if __name__ == '__main__':
    unittest.main()
