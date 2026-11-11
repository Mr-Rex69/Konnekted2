#!/usr/bin/env python3
"""Prepare the unsigned iPhone release from an independently audited IPA.

Normal publication requires verified build, Flutter regressions, first launch
and the exact source/IPA/symbol audit. Extended simulator acceptance is opt-in
and must be reported accurately. Signing/device acceptance is never claimed.
This script does not send network requests or change package bytes.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

from ios_verify_engineering_release import verify
from ios_store_distribution import PUBLIC_IPA, release_notes, write_source


def validate_context(repo, environment):
    branch_push = environment.get('GITHUB_EVENT_NAME') == 'push' and re.fullmatch(
        r'release/ios-sideload-[a-zA-Z0-9._-]+', environment.get('GITHUB_REF_NAME', ''))
    manual_main = (environment.get('GITHUB_EVENT_NAME') == 'workflow_dispatch' and
                   environment.get('GITHUB_REF_NAME') == 'main' and
                   environment.get('LOKAL_IOS_PUBLISH') == 'true')
    if not (branch_push or manual_main):
        raise ValueError('Publishing requires a release branch push or an explicit manual main publication')
    commit = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
    if environment.get('GITHUB_SHA') != commit:
        raise ValueError('Release job source must equal its triggering commit')
    capability = (repo / 'ios/Runner/LokalTransferBridge.swift').read_text().split(
        'private final class LokalTransferReply', 1)[0]
    for feature in ('libraryImport', 'upload'):
        if len(re.findall(r'\blet\s+' + feature + r'\s*=\s*true\b', capability)) != 1:
            raise ValueError('Release capability is not enabled: ' + feature)
    for key in ('GITHUB_RUN_NUMBER', 'GITHUB_RUN_ATTEMPT'):
        if not re.fullmatch(r'[1-9][0-9]*', environment.get(key, '')):
            raise ValueError('Missing release run identity')
    return commit


def native_acceptance_qualification(environment):
    flag = environment.get('LOKAL_IOS_NATIVE_ACCEPTANCE', 'false')
    if flag not in ('true', 'false'):
        raise ValueError('Invalid native acceptance qualification flag')
    passed = flag == 'true'
    message = (
        'Apple SDK, Flutter regressions, production first launch and '
        'exact AOT IPA/source/symbol audit passed; '
        + ('installed iOS 18.6/26.0 native and background acceptance passed'
           if passed else 'extended simulator acceptance not run')
    )
    detail = {
        'requested': passed,
        'status': 'passed' if passed else 'not_run',
        'runtimes': ['18.6', '26.0'] if passed else [],
    }
    return message, detail


def prepare(artifact, repo, destination, environment):
    commit = validate_context(repo, environment)
    result = verify(artifact, repo)
    package = next(artifact.rglob('Lokal-unsigned.ipa')).parent
    manifest = json.loads((package / 'Lokal-unsigned.ipa.json').read_text())
    destination.mkdir(parents=True, exist_ok=False)
    for name in ('Lokal-unsigned.ipa', 'Lokal-unsigned.ipa.sha256',
                 'Lokal-unsigned.ipa.json', 'Lokal-source.tar.gz'):
        shutil.copyfile(package / name, destination / name.replace('Lokal-unsigned.ipa', PUBLIC_IPA))
    (destination / (PUBLIC_IPA + '.sha256')).write_text(f'{manifest["sha256"]}  {PUBLIC_IPA}\n')
    with tarfile.open(destination / 'Lokal-crash-symbols.tar.gz', 'w:gz') as symbols:
        symbols.add(package / 'Symbols', arcname='Symbols')
    for name in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
        shutil.copyfile(repo / name, destination / name)
    # The workflow requires both simulator matrices when requested. For the
    # regular path, never imply an unrun WebKit, transfer or playback suite passed.
    qualification, native_acceptance = native_acceptance_qualification(environment)
    report = {
        'source_commit': commit,
        'source_tree': manifest['source_tree'],
        'workflow_run': environment['GITHUB_RUN_ID'],
        'run_attempt': environment['GITHUB_RUN_ATTEMPT'],
        'qualification': qualification,
        'native_simulator_acceptance': native_acceptance,
        'physical_acceptance': 'User signing, installation/upgrade and real-iPhone acceptance remain required',
        'package_audit': result,
    }
    (destination / 'qualification.json').write_text(json.dumps(report, indent=2) + '\n')
    tag = 'ios'
    changes = environment.get('LOKAL_IOS_CHANGES', '* Updated Lokal for iPhone.')
    write_source(destination, description=changes)
    notes = release_notes(manifest, changes)
    (destination / 'RELEASE-NOTES.md').write_text(notes)
    return tag


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    tag = prepare(args.artifact, repo, args.destination, os.environ)
    with open(os.environ['GITHUB_OUTPUT'], 'a') as outputs:
        outputs.write('tag=' + tag + '\n')
    print('Prepared audited unsigned iPhone release: ' + tag)


if __name__ == '__main__':
    main()
