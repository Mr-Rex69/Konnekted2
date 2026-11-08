"""Stable/nightly metadata. No signing secrets or dependency downloads."""
import os
from pathlib import Path
import re
import subprocess
import time
from ci_release import metadata, positive_number, semantic_version

EPOCH = 1_577_836_800  # 2020-01-01; shared by both workflows, not per-workflow counters.


def calculate(pubspec, channel, tags, run_number, *, now=None, ref='refs/heads/main', supplied='', requested='', attempt='1', bump='patch', replace=False, published_version='', published_build=''):
    baseline = metadata(pubspec)
    base = baseline['version']
    if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', base):
        raise ValueError('pubspec must contain the next stable MAJOR.MINOR.PATCH version')
    if channel not in ('stable', 'nightly'):
        raise ValueError('Unknown release channel')
    tags = list(tags)
    if published_version:
        semantic_version(published_version)
        if '-' in published_version:
            raise ValueError('The published Android baseline must be stable')
        tags.append(f'v{published_version}')
    stable_tags = [tag for tag in tags if re.fullmatch(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', tag)]
    parts = lambda value: tuple(map(int, value.removeprefix('v').split('.')))
    latest = max(stable_tags, key=parts, default='')
    current = max([base] + ([latest[1:]] if latest else []), key=parts)
    if replace and (channel != 'stable' or ref != 'refs/heads/main'):
        raise ValueError('Replacement requires a manual stable run from main')
    if ref.startswith('refs/tags/') and channel == 'stable':
        version = ref.removeprefix('refs/tags/v')
        if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version) or parts(version) < parts(base):
            raise ValueError('Stable tag must be a version at least as new as pubspec')
        if requested and requested.removeprefix('v') != version:
            raise ValueError('Requested version must match the pushed tag')
    elif ref != 'refs/heads/main':
        raise ValueError('Dispatch from main')
    elif channel == 'stable':
        if bump not in ('patch', 'minor', 'major'):
            raise ValueError('Version bump must be patch, minor or major')
        if requested:
            version = requested.removeprefix('v')
            semantic_version(version)
            if '-' in version or parts(version) < parts(current):
                raise ValueError('Stable version must not go backwards')
        elif replace:
            version = current
        elif f'v{base}' not in tags and parts(base) >= parts(current):
            # Desktop parity: release an already-prepared version first (1.0.0).
            version = base
        else:
            major, minor, patch = parts(current)
            version = {'patch': f'{major}.{minor}.{patch + 1}',
                       'minor': f'{major}.{minor + 1}.0',
                       'major': f'{major + 1}.0.0'}[bump]
        if f'v{version}' in tags and not replace:
            raise ValueError('This stable version already exists; choose a newer version or enable replacement')
        if replace and f'v{version}' not in tags:
            raise ValueError('Replacement needs an existing stable tag')
    else:
        base = current
        if f'v{base}' in tags:
            major, minor, patch = parts(base)
            base = f'{major}.{minor}.{patch + 1}'
        version = f'{base}-nightly.{positive_number(run_number)}'
        if positive_number(attempt) > 1:
            version += f'.r{attempt}'
    base = version.split('-')[0]
    semantic_version(version)
    # Main/nightly share a signed package: independent run counters cause
    # INSTALL_FAILED_VERSION_DOWNGRADE. Serialize flows and use one UTC clock.
    default = max(int(baseline['build_number']), int(time.time() if now is None else now) - EPOCH + 100_000)
    if published_build:
        default = max(default, positive_number(published_build) + 1)
    code = positive_number(supplied) if supplied else positive_number(default)
    if code < default:
        raise ValueError('Explicit versionCode must be at least the current time-based default')
    stable = [tag for tag in tags if re.fullmatch(r'v\d+\.\d+\.\d+', tag)
              and tuple(map(int, tag[1:].split('.'))) < tuple(map(int, base.split('.')))]
    previous = max(stable, key=lambda t: tuple(map(int, t[1:].split('.'))), default='')
    return {'version': version, 'build_number': str(code), 'tag': 'android' if channel == 'stable' else '',
            'prerelease': str(channel == 'nightly').lower(), 'previous': previous,
            'replace': str(replace).lower()}


def main():
    channel = os.environ['RELEASE_CHANNEL']
    tags = subprocess.check_output(['git', 'tag', '--list'], text=True).splitlines()
    result = calculate(Path('pubspec.yaml').read_text(), channel, tags, os.environ['GITHUB_RUN_NUMBER'],
        ref=os.environ['GITHUB_REF'], supplied=os.environ.get('RELEASE_BUILD_NUMBER', ''),
        requested=os.environ.get('RELEASE_VERSION', ''), attempt=os.environ['GITHUB_RUN_ATTEMPT'], bump=os.environ.get('RELEASE_BUMP', 'patch'),
        replace=os.environ.get('RELEASE_REPLACE', 'false') == 'true',
        published_version=os.environ.get('RELEASE_PUBLISHED_VERSION', ''),
        published_build=os.environ.get('RELEASE_PUBLISHED_BUILD', ''))
    flavor = os.environ.get('RELEASE_FLAVOR', 'full')
    result['flavors'] = metadata(Path('pubspec.yaml').read_text(), flavor=flavor)['flavors']
    result['sha'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip()
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        for key, value in result.items(): output.write(f'{key}={value}\n')
    print(f"{result['version']} · versionCode {result['build_number']} · {result['sha'][:8]}")


if __name__ == '__main__':
    main()
