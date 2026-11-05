#!/usr/bin/env python3
"""Test the production Soulseek C ABI module without the unrelated audio engine.

Uses the application's pinned protocol revision and lockfile. This is a host
contract check; it does not qualify iPhone linking, network or lifecycle behavior.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tomllib


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', type=Path, required=True,
                        help='Dedicated generated Cargo workspace and target cache')
    parser.add_argument('--cargo', default='cargo')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    work = args.work_dir.resolve()
    if work == root or root in work.parents:
        parser.error('Use a generated workspace outside the source checkout.')
    manifest = work / 'Cargo.toml'
    if work.exists() and any(work.iterdir()):
        if not manifest.is_file() or 'name = "lokal-soulseek-host-contract"' not in manifest.read_text():
            parser.error('The work directory contains unrelated files.')
    work.mkdir(parents=True, exist_ok=True)
    native = tomllib.loads((root / 'rust/Cargo.toml').read_text())
    packages = tomllib.loads((root / 'rust/Cargo.lock').read_text())['package']
    def version(name):
        matches = [entry['version'] for entry in packages if entry['name'] == name]
        if len(matches) != 1:
            raise ValueError(f'Expected one locked {name} version')
        return matches[0]
    engine = native['dependencies']['soulseek-rs-lib']
    manifest.write_text('\n'.join([
        '[package]', 'name = "lokal-soulseek-host-contract"',
        'version = "0.1.0"', 'edition = "2021"', '[lib]',
        'path = ' + json.dumps(str(root / 'rust/src/soulseek_ffi.rs')),
        '[dependencies]',
        'soulseek-rs-lib = { git = ' + json.dumps(engine['git']) +
        ', rev = ' + json.dumps(engine['rev']) + ' }',
        'serde_json = "=' + version('serde_json') + '"',
        'sha2 = "=' + version('sha2') + '"', '',
    ]))
    # Cargo removes the unrelated audio packages while retaining the app's
    # locked versions for the protocol module and its transitive dependencies.
    shutil.copyfile(root / 'rust/Cargo.lock', work / 'Cargo.lock')
    env = dict(os.environ)
    env.setdefault('CARGO_INCREMENTAL', '0')
    env.setdefault('CARGO_PROFILE_DEV_DEBUG', '0')
    subprocess.run([args.cargo, 'test', '--manifest-path', str(manifest)],
                   env=env, check=True)
    locked = {(p['name'], p['version'], p.get('source')) for p in packages}
    generated = tomllib.loads((work / 'Cargo.lock').read_text())['package']
    for package in generated:
        if package['name'] != 'lokal-soulseek-host-contract':
            identity = (package['name'], package['version'], package.get('source'))
            if identity not in locked:
                raise ValueError('Host check resolved a dependency outside the app lockfile: ' + str(identity))
    print('Production Soulseek host contracts passed using app-locked dependencies. Apple qualification remains separate.')


if __name__ == '__main__':
    main()
