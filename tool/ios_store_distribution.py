"""AltStore Classic/SideStore feed and user-facing iPhone release copy.

Generate permissions and version identity from the actual IPA, not a template.
The same permanent source URL is used by both stores and in-app prompts.
"""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct
from urllib.parse import urlencode
import zipfile

from ios_native_symbols import arm64_image, load_commands

REPO = 'lokal-music/mobile'
RELEASE_URL = f'https://github.com/{REPO}/releases/tag/ios'
DOWNLOAD_URL = f'https://github.com/{REPO}/releases/download/ios'
SOURCE_URL = DOWNLOAD_URL + '/altstore-source.json'
GUIDE_URL = f'https://github.com/{REPO}/blob/main/docs/IOS_STORE_UPDATES.md'
PUBLIC_IPA = 'Lokal.ipa'
LEGACY_IPA = 'Lokal-unsigned.ipa'


def ipa_name(names):
    return PUBLIC_IPA if PUBLIC_IPA in names else LEGACY_IPA


def entitlements(binary):
    binary = arm64_image(binary)
    for kind, command in load_commands(binary):
        if kind != 0x1d:  # LC_CODE_SIGNATURE
            continue
        if len(command) < 16:
            raise ValueError('Truncated code signature command')
        offset, size = struct.unpack_from('<II', command, 8)
        blob = binary[offset:offset + size]
        if len(blob) != size or len(blob) < 12:
            raise ValueError('Truncated code signature')
        magic, length, count = struct.unpack_from('>III', blob)
        if magic != 0xfade0cc0 or length > len(blob) or 12 + count * 8 > length:
            raise ValueError('Invalid code signature inventory')
        result, der = None, False
        for i in range(count):
            slot, position = struct.unpack_from('>II', blob, 12 + i * 8)
            if position + 8 > length:
                raise ValueError('Invalid code signature slot')
            if slot == 7:
                der = True
            if slot == 5:
                kind, end = struct.unpack_from('>II', blob, position)
                if kind != 0xfade7171 or end < 8 or position + end > length:
                    raise ValueError('Invalid entitlement plist')
                result = plistlib.loads(blob[position + 8:position + end])
        if der and result is None:
            raise ValueError('Cannot infer DER-only entitlements')
        return sorted(key for key in (result or {}) if key not in
                      ('application-identifier', 'com.apple.developer.team-identifier'))
    return []


def package_permissions(ipa, metadata):
    with zipfile.ZipFile(ipa) as archive:
        plists = [name for name in archive.namelist()
                  if re.fullmatch(r'Payload/[^/]+\.app/Info.plist', name)]
        if len(plists) != 1 or any('.appex/' in name for name in archive.namelist()):
            raise ValueError('Review store permissions before distributing app extensions')
        info = plistlib.loads(archive.read(plists[0]))
        for key, field in [('CFBundleIdentifier', 'bundle_id'),
                           ('CFBundleShortVersionString', 'version'),
                           ('CFBundleVersion', 'build'), ('MinimumOSVersion', 'minimum_ios')]:
            if info.get(key) != metadata.get(field):
                raise ValueError('Store metadata differs from IPA: ' + key)
        if info['CFBundleIdentifier'] != 'app.lokal.mobile':
            raise ValueError('Unexpected store app identity')
        executable = info['CFBundleExecutable']
        if Path(executable).name != executable:
            raise ValueError('Invalid executable name')
        binary = archive.read(plists[0].removesuffix('Info.plist') + executable)
        return {'entitlements': entitlements(binary),
                'privacy': {key: value for key, value in info.items()
                            if key.startswith('NS') and 'UsageDescription' in key}}


def make_source(ipa, metadata, date, description):
    datetime.fromisoformat(date.replace('Z', '+00:00'))
    if not re.fullmatch(r'\d+\.\d+\.\d+', metadata['version']) or not re.fullmatch(r'[1-9]\d*', metadata['build']):
        raise ValueError('Invalid iOS version/build')
    if hashlib.sha256(ipa.read_bytes()).hexdigest() != metadata['sha256']:
        raise ValueError('Store package checksum mismatch')
    icon = f'https://raw.githubusercontent.com/{REPO}/main/assets/branding/lokal_icon.png'
    return {
        'name': 'Lokal', 'identifier': 'app.lokal.source', 'sourceURL': SOURCE_URL,
        'subtitle': 'Your music. Everywhere you go.', 'website': RELEASE_URL,
        'iconURL': icon, 'tintColor': '#DFFF00', 'news': [],
        'apps': [{
            'name': 'Lokal', 'bundleIdentifier': metadata['bundle_id'],
            'developerName': 'Lokal Music', 'subtitle': 'Your music. Everywhere you go.',
            'localizedDescription': 'Play your music, explore online sources, follow synchronized lyrics and connect your Lokal desktop.',
            'iconURL': icon, 'tintColor': '#DFFF00', 'category': 'entertainment',
            'appPermissions': package_permissions(ipa, metadata),
            'versions': [{
                'version': metadata['version'], 'buildVersion': metadata['build'],
                'date': date, 'localizedDescription': description,
                # A build-specific URL prevents stores reusing a cached older IPA
                # after the permanent iOS release is updated in place.
                'downloadURL': DOWNLOAD_URL + '/' + ipa.name + '?' + urlencode({'build': metadata['build']}),
                'size': ipa.stat().st_size, 'minOSVersion': metadata['minimum_ios'],
            }],
        }],
    }


def write_source(directory, *, date=None, description='Latest Lokal for iPhone.'):
    name = ipa_name({p.name for p in directory.iterdir()})
    metadata = json.loads((directory / (name + '.json')).read_text())
    source = make_source(directory / name, metadata,
                         date or datetime.now(timezone.utc).isoformat(), description)
    (directory / 'altstore-source.json').write_text(json.dumps(source, indent=2) + '\n')
    return source


def validate_source(directory):
    source = json.loads((directory / 'altstore-source.json').read_text())
    version = source['apps'][0]['versions'][0]
    name = ipa_name({p.name for p in directory.iterdir()})
    metadata = json.loads((directory / (name + '.json')).read_text())
    expected = make_source(directory / name, metadata, version['date'], version['localizedDescription'])
    if source != expected:
        raise ValueError('Store source does not match the verified IPA')


def release_notes(metadata, changes):
    return f'''**Lokal Mobile {metadata['version']}** · iOS 16+ · Build {metadata['build']}

## Install and update with AltStore or SideStore

1. Install [AltStore Classic](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows) or [SideStore](https://docs.sidestore.io/docs/installation/prerequisites). Follow your store's setup instructions first. AltStore Classic uses AltServer on your computer; SideStore uses its pairing and VPN setup for on-device signing.
2. In your store, open **Sources**, tap **+**, and add this permanent Lokal source URL:

   `{SOURCE_URL}`

3. Find **Lokal** in the source and install it. For an existing installation, keep the same Apple account and app identity and install over it. Do not uninstall Lokal to update; that can remove your library and settings.
4. For future releases, refresh the source and choose **Update** for Lokal in **My Apps**. Each published iPhone build updates this source automatically. Builds with the same app version still have distinct build numbers.
5. Keep **Automatic update checks** enabled in Lokal to receive an in-app prompt when a newer build is published. The prompt opens AltStore or SideStore; complete the update there. Older Lokal builds need one update through the store before they can show these prompts.

**Refresh and Update are different:** Refresh renews the installed app's signing; Update installs a newer Lokal build. Free-account installations normally expire after seven days, so keep your store's refresh setup working. Source checks and refreshes follow your store's connectivity and background settings; a new release does not silently install itself.

See the [step-by-step setup and update guide]({GUIDE_URL}). This source is for **AltStore Classic and SideStore**.

## What's Changed
{changes.strip()}

This iOS download page and source URL stay the same for future releases. Matching source, checksums, license notices and crash symbols are attached.

[Source commit](https://github.com/{REPO}/commit/{metadata['source_commit']})
'''
