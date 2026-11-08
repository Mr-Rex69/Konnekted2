#!/usr/bin/env python3
"""Maintain the two user-facing releases: android and ios (stdlib + gh).

Publish verified assets before removing superseded assets. Migration renames
an existing release without downloading/re-uploading its binaries. Cleanup is
explicit and limited to the known mobile tag namespaces.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time
from urllib.parse import quote

REPO = 'lokal-music/mobile'
LEGACY_ANDROID = re.compile(r'v\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?\Z')
LEGACY_IOS = re.compile(r'ios-sideload-beta-\d+-attempt\d+\Z')
SHA = re.compile(r'[0-9a-f]{40}\Z')


class GitHub:
    def __init__(self):
        self.last_write = 0.0

    def api(self, path, method='GET', payload=None, missing=False):
        if method != 'GET':
            # Bulk history cleanup stays below GitHub's secondary write limit.
            time.sleep(max(0, 1.0 - (time.monotonic() - self.last_write)))
            self.last_write = time.monotonic()
        args = ['gh', 'api', f'repos/{REPO}/{path}', '--method', method]
        if payload is not None:
            args += ['--input', '-']
        result = subprocess.run(args, input=json.dumps(payload) if payload is not None else None,
                                text=True, capture_output=True)
        if result.returncode:
            if missing and '(HTTP 404)' in result.stderr:
                return None
            raise RuntimeError(f'GitHub {method} {path} failed (exit {result.returncode})')
        return json.loads(result.stdout) if result.stdout.strip() else None

    def releases(self):
        releases = []
        page = 1
        while True:
            batch = self.api(f'releases?per_page=100&page={page}')
            releases.extend(batch)
            if len(batch) < 100:
                return releases
            page += 1

    def asset_json(self, asset):
        result = subprocess.run(['gh', 'api', f'repos/{REPO}/releases/assets/{asset["id"]}',
                                 '-H', 'Accept: application/octet-stream'],
                                check=True, capture_output=True, text=True)
        if len(result.stdout) > 1024 * 1024:
            raise ValueError('Release metadata exceeds 1 MiB')
        return json.loads(result.stdout)

    def upload(self, tag, files):
        # APK/IPA and symbols first; discovery metadata and checksums last.
        files = sorted(files, key=lambda f: (f.suffix == '.json' or f.name.startswith('SHA256'), f.name))
        for file in files:
            subprocess.run(['gh', 'release', 'upload', tag, str(file), '--clobber',
                            '--repo', REPO], check=True)

    def download(self, release, destination):
        for asset in release['assets']:
            if Path(asset['name']).name != asset['name']:
                raise ValueError('Unsafe release asset name')
        subprocess.run(['gh', 'release', 'download', release['tag_name'], '--repo', REPO,
                        '--dir', str(destination)], check=True)


def platform_of(release):
    names = {asset['name'] for asset in release.get('assets', [])}
    if 'Lokal-unsigned.ipa' in names and 'Lokal-unsigned.ipa.json' in names:
        return 'ios'
    if any(name.endswith('.apk') for name in names) and any(
            name in names for name in ('full-metadata.json', 'play-metadata.json')):
        return 'android'
    return None


def release_metadata(github, release, platform):
    names = {asset['name']: asset for asset in release['assets']}
    metadata_name = 'Lokal-unsigned.ipa.json' if platform == 'ios' else (
        'full-metadata.json' if 'full-metadata.json' in names else 'play-metadata.json')
    metadata = github.asset_json(names[metadata_name])
    version = str(metadata['version'])
    build = int(metadata['build' if platform == 'ios' else 'versionCode'])
    commit = metadata['source_commit' if platform == 'ios' else 'commit']
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?', version) or build <= 0 or not SHA.fullmatch(commit):
        raise ValueError('Invalid published platform metadata')
    if not re.fullmatch(r'[0-9a-fA-F]{64}', metadata.get('sha256', '')):
        raise ValueError('Published package has no valid checksum')
    if platform == 'ios':
        required = {'Lokal-source.tar.gz', 'Lokal-crash-symbols.tar.gz', 'qualification.json',
                    'LICENSE', 'THIRD_PARTY_NOTICES.md', 'Lokal-unsigned.ipa.sha256'}
        if not required <= names.keys():
            raise ValueError('Published IPA is missing source, symbols or qualification assets')
    else:
        flavor = metadata.get('flavor')
        prefix = f'Lokal-{version}' + ('-Play' if flavor == 'play' else '')
        if flavor not in ('full', 'play') or 'SHA256SUMS' not in names or not any(
                name in names for name in (prefix + '-arm64.apk', prefix + '-universal.apk')):
            raise ValueError('Published APK/variant/checksums are incomplete')
    return {'version': version, 'build': build, 'sha': commit}


def marker(platform, metadata):
    return f'<!-- lokal-platform:{platform} version:{metadata["version"]} build:{metadata["build"]} -->'


def title(platform, metadata):
    return f'Android — {metadata["version"]}' if platform == 'android' else f'iOS — Build {metadata["build"]} (unsigned)'


def move_tag(github, tag, sha):
    if tag not in ('android', 'ios') or not SHA.fullmatch(sha):
        raise ValueError('Only platform tags at full commit SHAs may be moved')
    current = github.api(f'git/ref/tags/{tag}', missing=True)
    if current is None:
        github.api('git/refs', 'POST', {'ref': f'refs/tags/{tag}', 'sha': sha})
    elif current['object']['sha'] != sha:
        # This intentional rolling tag never names a branch or a version tag.
        github.api(f'git/refs/tags/{tag}', 'PATCH', {'sha': sha, 'force': True})


def release_fields(platform, metadata, body):
    return {'tag_name': platform, 'target_commitish': metadata['sha'],
            'name': title(platform, metadata), 'body': marker(platform, metadata) + '\n\n' + body,
            'draft': False, 'prerelease': platform == 'ios',
            'make_latest': 'true' if platform == 'android' else 'false'}


def validated_files(directory, platform, sha):
    files = [file for file in directory.iterdir() if file.is_file()]
    by_name = {file.name: file for file in files}
    if platform == 'android':
        manifests = [by_name[name] for name in ('full-metadata.json', 'play-metadata.json') if name in by_name]
        if not manifests or 'SHA256SUMS' not in by_name:
            raise ValueError('Missing Android manifest/checksums')
        selected = None
        for manifest in manifests:
            data = json.loads(manifest.read_text())
            flavor = data['flavor']
            if flavor not in ('full', 'play') or data['commit'] != sha:
                raise ValueError('APK metadata source/flavor mismatch')
            prefix = f'Lokal-{data["version"]}' + ('-Play' if flavor == 'play' else '')
            apk = by_name.get(prefix + '-arm64.apk')
            if apk is None or hashlib.sha256(apk.read_bytes()).hexdigest() != data['sha256']:
                raise ValueError('APK SHA-256 does not match metadata')
            value = {'version': data['version'], 'build': int(data['versionCode']), 'sha': sha}
            if selected and value != selected:
                raise ValueError('Android variants must come from the same version/build/source')
            selected = value
        return files, selected
    required = {'Lokal-unsigned.ipa', 'Lokal-unsigned.ipa.json', 'Lokal-unsigned.ipa.sha256',
                'Lokal-source.tar.gz', 'Lokal-crash-symbols.tar.gz', 'qualification.json',
                'LICENSE', 'THIRD_PARTY_NOTICES.md'}
    if not required <= by_name.keys():
        raise ValueError('Missing audited iPhone release assets')
    data = json.loads(by_name['Lokal-unsigned.ipa.json'].read_text())
    qualification = json.loads(by_name['qualification.json'].read_text())
    if data['source_commit'] != sha or qualification['source_commit'] != sha:
        raise ValueError('IPA/qualification source mismatch')
    if hashlib.sha256(by_name['Lokal-unsigned.ipa'].read_bytes()).hexdigest() != data['sha256']:
        raise ValueError('IPA SHA-256 does not match audited manifest')
    return files, {'version': data['version'], 'build': int(data['build']), 'sha': sha}


def publish(github, platform, directory, sha, body):
    if platform not in ('android', 'ios') or not SHA.fullmatch(sha):
        raise ValueError('Invalid platform or source SHA')
    files, metadata = validated_files(directory, platform, sha)
    existing = github.api(f'releases/tags/{platform}', missing=True)
    if existing:
        old = release_metadata(github, existing, platform)
        if metadata['build'] < old['build']:
            raise ValueError('A rolling platform release must not downgrade its build')
        if metadata['build'] == old['build'] and metadata['sha'] != old['sha']:
            raise ValueError('A different source needs a newer platform build')
    else:
        move_tag(github, platform, sha)
        existing = github.api('releases', 'POST', {'tag_name': platform, 'target_commitish': sha,
                              'name': title(platform, metadata), 'draft': True})
    github.upload(platform, files)
    uploaded = github.api(f'releases/{existing["id"]}')
    expected = {file.name: file.stat().st_size for file in files}
    actual = {asset['name']: asset['size'] for asset in uploaded['assets']}
    if any(actual.get(name) != size for name, size in expected.items()):
        raise ValueError('Uploaded assets are incomplete; old assets were retained')
    move_tag(github, platform, sha)
    result = github.api(f'releases/{existing["id"]}', 'PATCH', release_fields(platform, metadata, body))
    for asset in uploaded['assets']:
        if asset['name'] not in expected:
            github.api(f'releases/assets/{asset["id"]}', 'DELETE')
    return result


def consolidate(github, cleanup=False, dry_run=False):
    releases = github.releases()
    plans = []
    for platform in ('android', 'ios'):
        candidates = [r for r in releases if not r['draft'] and platform_of(r) == platform
                      and (platform != 'android' or not r['prerelease'])]
        if not candidates:
            raise ValueError(f'No published {platform} download to retain')
        # Versioned legacy entries can be sorted without downloading 100+
        # metadata assets. Compare the newest legacy candidate with the rolling
        # release using their actual build counters before promoting either.
        legacy = [r for r in candidates if (LEGACY_ANDROID if platform == 'android' else LEGACY_IOS).fullmatch(r['tag_name'])]
        rolling = next((r for r in candidates if r['tag_name'] == platform), None)
        newest = max(legacy, key=lambda r: r['published_at'], default=None)
        choices = [(r, release_metadata(github, r, platform)) for r in (rolling, newest) if r]
        retained, metadata = max(choices, key=lambda pair: pair[1]['build'])
        if len({value['sha'] for _, value in choices if value['build'] == metadata['build']}) > 1:
            raise ValueError('Conflicting sources share the same published build counter')
        plans.append((platform, retained, metadata, rolling))
    # Validate both retained downloads before changing or deleting either
    # platform's history. A missing IPA/source/symbol set must fail closed.
    for platform, retained, metadata, rolling in plans:
        if dry_run:
            obsolete = [r['tag_name'] for r in releases if not r['draft'] and r['id'] != retained['id']
                        and (LEGACY_ANDROID if platform == 'android' else LEGACY_IOS).fullmatch(r['tag_name'])
                        and platform_of(r) == platform]
            print(f'{platform}: retain {retained["tag_name"]} ({metadata["version"]}+{metadata["build"]}); '
                  f'remove {len(obsolete)} superseded releases after canonical assets are retained')
            continue
        body = retained.get('body') or ''
        body = re.sub(r'<!-- lokal-platform:[^>]+ -->\s*', '', body)
        body = body.replace(f'/releases/download/{retained["tag_name"]}/', f'/releases/download/{platform}/')
        if retained['tag_name'] != platform:
            # Version tags are about to disappear; retain a durable source link
            # instead of a comparison that depends on those deleted refs.
            body = re.sub(r'(?m)^\*\*Full Changelog\*\*:.*\n?', '', body)
            body += f'\n\n[Source commit](https://github.com/{REPO}/commit/{metadata["sha"]})\n'
        if rolling and retained['id'] != rolling['id']:
            with tempfile.TemporaryDirectory(prefix='lokal-release-migration-') as temporary:
                directory = Path(temporary)
                github.download(retained, directory)
                # Legacy signed Android releases did not contain source tarballs;
                # retain their existing verified APKs/metadata as-is.
                retained = publish(github, platform, directory, metadata['sha'], body)
        else:
            move_tag(github, platform, metadata['sha'])
            fields = release_fields(platform, metadata, body)
            if any(retained.get(key) != value for key, value in fields.items() if key != 'make_latest'):
                retained = github.api(f'releases/{retained["id"]}', 'PATCH', fields)
        if platform_of(retained) != platform or not retained.get('assets'):
            raise ValueError('Canonical release has no matching download assets')
        print(f'Retained {platform}: {metadata["version"]}+{metadata["build"]} ({metadata["sha"][:8]})')
        if not cleanup:
            continue
        deleted = 0
        for release in releases:
            pattern = LEGACY_ANDROID if platform == 'android' else LEGACY_IOS
            if not release['draft'] and release['id'] != retained['id'] and pattern.fullmatch(release['tag_name']) and platform_of(release) == platform:
                github.api(f'releases/{release["id"]}', 'DELETE')
                deleted += 1
                if deleted % 25 == 0:
                    print(f'{platform}: removed {deleted} superseded releases', flush=True)
        # Re-read refs after publication; never delete branch refs or the two
        # canonical tags, including when a legacy workflow completed mid-run.
        pattern = LEGACY_ANDROID if platform == 'android' else LEGACY_IOS
        for ref in github.api('git/matching-refs/tags'):
            name = ref['ref'].removeprefix('refs/tags/')
            if pattern.fullmatch(name):
                # A newly published release not in our snapshot must survive
                # for the next reconciliation rather than losing its source tag.
                live = github.api(f'releases/tags/{quote(name, safe="")}', missing=True)
                if live is None:
                    github.api(f'git/refs/tags/{quote(name, safe="")}', 'DELETE')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('metadata', 'publish', 'consolidate'))
    parser.add_argument('--platform', choices=('android', 'ios'))
    parser.add_argument('--assets', type=Path)
    parser.add_argument('--sha')
    parser.add_argument('--notes', type=Path)
    parser.add_argument('--cleanup', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    github = GitHub()
    if args.command == 'consolidate':
        consolidate(github, args.cleanup, args.dry_run)
    elif args.command == 'metadata':
        release = github.api(f'releases/tags/{args.platform}', missing=True)
        values = release_metadata(github, release, args.platform) if release else {}
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            for key in ('version', 'build', 'sha'):
                output.write(f'published_{key}={values.get(key, "")}\n')
    else:
        result = publish(github, args.platform, args.assets, args.sha, args.notes.read_text())
        print(result['html_url'])


if __name__ == '__main__':
    main()
