"""Calculate iOS marketing versions independently of Android releases."""
import os
import re
from pathlib import Path

from ci_release import metadata
from platform_releases import GitHub, release_metadata


def parts(value):
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', value):
        raise ValueError('iOS version must be MAJOR.MINOR.PATCH')
    return tuple(map(int, value.split('.')))


def calculate(baseline, published, published_build, run_number, bump='patch', requested=''):
    if bump not in ('patch', 'minor', 'major'):
        raise ValueError('Choose patch, minor or major')
    current = max(parts(baseline), parts(published or baseline))
    major, minor, patch = current
    version = requested or {
        'patch': f'{major}.{minor}.{patch + 1}',
        'minor': f'{major}.{minor + 1}.0',
        'major': f'{major + 1}.0.0',
    }[bump]
    if parts(version) < current or (published and parts(version) <= parts(published)):
        raise ValueError('Choose a version newer than the published iOS version')
    build = max(int(run_number), int(published_build or 0) + 1)
    if build <= 0:
        raise ValueError('Invalid iOS build number')
    return version, str(build)


def main():
    github = GitHub()
    release = github.api('releases/tags/ios', missing=True)
    published = release_metadata(github, release, 'ios') if release else {}
    version, build = calculate(metadata(Path('pubspec.yaml').read_text())['version'],
        published.get('version', ''), published.get('build', 0), os.environ['GITHUB_RUN_NUMBER'],
        os.environ.get('IOS_VERSION_BUMP') or 'patch', os.environ.get('IOS_VERSION') or '')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'version={version}\nbuild={build}\n')
    print(f'iOS {version} (build {build})')


if __name__ == '__main__':
    main()
