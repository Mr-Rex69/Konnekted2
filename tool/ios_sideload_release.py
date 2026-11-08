#!/usr/bin/env python3
"""Prepare a pre-device iPhone beta from the exact independently audited IPA.

Called by an explicit release-branch push or manual main publication after both
installed simulator suites and external background tests pass. Signing/device acceptance is deliberately not
claimed. This script does not send network requests or change package bytes.
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


def prepare(artifact, repo, destination, environment):
    commit = validate_context(repo, environment)
    result = verify(artifact, repo)
    package = next(artifact.rglob('Lokal-unsigned.ipa')).parent
    manifest = json.loads((package / 'Lokal-unsigned.ipa.json').read_text())
    destination.mkdir(parents=True, exist_ok=False)
    for name in ('Lokal-unsigned.ipa', 'Lokal-unsigned.ipa.sha256',
                 'Lokal-unsigned.ipa.json', 'Lokal-source.tar.gz'):
        shutil.copyfile(package / name, destination / name)
    with tarfile.open(destination / 'Lokal-crash-symbols.tar.gz', 'w:gz') as symbols:
        symbols.add(package / 'Symbols', arcname='Symbols')
    for name in ('LICENSE', 'THIRD_PARTY_NOTICES.md'):
        shutil.copyfile(repo / name, destination / name)
    report = {
        'source_commit': commit,
        'source_tree': manifest['source_tree'],
        'workflow_run': environment['GITHUB_RUN_ID'],
        'run_attempt': environment['GITHUB_RUN_ATTEMPT'],
        'qualification': 'Apple SDK, installed iOS18.6/26 mixed-transfer/playback and external background/process-recovery suites passed; exact AOT IPA/source/symbol audit passed',
        'physical_acceptance': 'User signing, installation/upgrade and real-iPhone acceptance remain required',
        'package_audit': result,
    }
    (destination / 'qualification.json').write_text(json.dumps(report, indent=2) + '\n')
    tag = 'ios'
    repository = environment['GITHUB_REPOSITORY']
    notes = (
        '# Unsigned iPhone beta — ready for device testing\n\n'
        'iOS 16+. Install from Windows using your own signing tool and Apple ID. '
        'This IPA is unsigned; physical signing, installation/upgrade and device acceptance remain your next step.\n\n'
        'The Apple build, installed iOS 18.6 and 26 suites, mixed/background transfer and '
        'process-recovery checks, and independent release/AOT package audit passed for this exact source. '
        'Live P2P accounts, private add-ons, casting receivers and physical audio routes still need your acceptance.\n\n'
        'Soulseek requires Lokal in the foreground. Desktop peers without the durable upload protocol '
        'use the existing foreground copy flow. The durable receiver continuation is '
        'https://github.com/lokal-music/desktop/pull/728. Home Screen widgets and Android direct USB audio are excluded.\n\n'
        f'- Source: `{commit}`\n- IPA SHA-256: `{manifest["sha256"]}`\n'
        f'- Qualification: https://github.com/{repository}/actions/runs/{environment["GITHUB_RUN_ID"]}\n'
        f'- Windows installation: https://github.com/{repository}/blob/{commit}/docs/IOS_SIDELOADING.md\n\n'
        'Matching source, license notices, package manifest, qualification report and crash symbols are attached.\n'
    )
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
    print('Prepared audited unsigned iPhone beta: ' + tag)


if __name__ == '__main__':
    main()
