#!/usr/bin/env python3
"""Qualify the compiled DEBUG app's isolated real iOS background URLSession.

An external HTTP fixture holds both task directions. The controller backgrounds
and SIGSTOPs the app, releases network responses, resumes it, then kills/relaunches
it and checks durable truth. A second case kills the process with tasks pending.
This is simulator/OS-daemon evidence, not physical-device or automatic OS-relaunch
acceptance. Shipping storage, Keychain and user music are never accessed.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import urllib.request
import uuid

from ios_transfer_fixture import serve_fixture

BUNDLE = 'app.lokal.mobile'


def command(*args, **kwargs):
    return subprocess.run(args, check=True, timeout=30, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kwargs).stdout


def eventually(read, predicate, description, timeout=90):
    end = time.monotonic() + timeout
    last = None
    while time.monotonic() < end:
        try:
            last = read()
            if isinstance(last, dict) and last.get('error'):
                raise RuntimeError('Native daemon probe failed: ' + str(last))
            if predicate(last):
                return last
        except (FileNotFoundError, json.JSONDecodeError, urllib.error.URLError):
            pass
        time.sleep(.25)
    raise RuntimeError(f'{description} timed out; last evidence: {last}')


def read_json(path):
    return json.loads(path.read_text())


def request(origin, path):
    with urllib.request.urlopen(origin + path, timeout=10) as response:
        return response.read()


def launch(device, environment):
    env = dict(os.environ)
    env.update({'SIMCTL_CHILD_LOKAL_IOS_DAEMON_PROBE_' + key: str(value)
                for key, value in environment.items()})
    # Pending background tasks can cause an unconfigured OS relaunch before
    # this explicit test launch. SIMCTL_CHILD variables apply to a new process,
    # so never reuse that process with stale/missing fixture coordinates.
    output = command('xcrun', 'simctl', 'launch', '--terminate-running-process',
                     device, BUNDLE, env=env)
    match = re.search(r'app\.lokal\.mobile:\s*(\d+)', output)
    if not match:
        raise RuntimeError('Cannot identify owned native probe process: ' + output)
    return int(match[1])


def stop_owned(pid, sig):
    try:
        os.kill(pid, sig)
    except ProcessLookupError:
        pass


def qualify_case(device, container, output, death_while_pending):
    run = str(uuid.uuid4())
    root = container / 'Library/Application Support' / ('IOSDaemonProbe-' + run)
    label = 'pending-process-death' if death_while_pending else 'suspended-delivery'
    evidence = output / label
    evidence.mkdir(parents=True, exist_ok=True)
    pid = None
    with serve_fixture(hold_timeout=180) as (origin, length, checksum):
        request(origin, '/__hold_storage')
        env = {'RUN': run, 'PORT': origin.rsplit(':', 1)[1], 'BYTES': length,
               'SHA256': checksum, 'DOWNLOAD': str(uuid.uuid4()), 'UPLOAD': str(uuid.uuid4())}
        state = lambda: json.loads(request(origin, '/__state'))
        try:
            pid = launch(device, env)
            eventually(lambda: read_json(root / 'state.json'),
                       lambda value: value.get('uploadProtocol') == 1,
                       'Native mixed admission')
            before = eventually(state,
                lambda value: value['requests'].get('storage-download-daemon') == 1 and
                              value['uploadRequests'].get('storage-upload-daemon') == 1,
                'Both actual background tasks reaching external fixture')
            command('xcrun', 'simctl', 'launch', device, 'com.apple.Preferences')
            eventually(lambda: (root / 'background.txt').read_text(),
                       lambda value: value == 'backgrounded', 'UIKit background notification')
            if death_while_pending:
                stop_owned(pid, signal.SIGKILL)
                pid = None
            else:
                stop_owned(pid, signal.SIGSTOP)
            request(origin, '/__release_storage')
            delivered = eventually(state, lambda value: len(value['storageResponses']) == 2,
                                   'External HTTP responses while app is stopped')
            if death_while_pending:
                env['RECOVER'] = 'true'
                pid = launch(device, env)
                result_name = 'recovered.json'
            else:
                stop_owned(pid, signal.SIGCONT)
                command('xcrun', 'simctl', 'launch', device, BUNDLE)
                result_name = 'state.json'
            completed = eventually(lambda: read_json(root / result_name),
                lambda value: value.get('download') == 'staged' and value.get('upload') == 'complete',
                'Verified native download staging and upload receipt')
            assert completed['processID'] == pid, completed
            assert completed['recovering'] == death_while_pending, completed
            assert completed['sessionIdentifier'] == 'app.lokal.mobile.integration-daemon.' + run
            assert completed['downloadBytes'] == length and completed['downloadSHA256'] == checksum
            assert completed['originalID'] == 'desktop-storage-upload-daemon'
            assert hashlib.sha256((root / 'Music/source.wav').read_bytes()).hexdigest() == checksum
            # Abrupt process exit, not app-switcher force-quit or graceful owner shutdown.
            stop_owned(pid, signal.SIGKILL)
            pid = None
            env['RECOVER'] = 'true'
            recovered_path = root / 'recovered.json'
            if recovered_path.exists():
                recovered_path.unlink()  # Only this run's previous test evidence.
            pid = launch(device, env)
            recovered = eventually(lambda: read_json(recovered_path),
                lambda value: value.get('download') == 'staged' and value.get('upload') == 'complete',
                'Exact journal recovery after completed process death')
            assert recovered['processID'] == pid and recovered['recovering'] is True, recovered
            assert recovered['sessionIdentifier'] == completed['sessionIdentifier'], recovered
            after = state()
            assert after['requests'] == {'storage-download-daemon': 1}, after
            assert after['uploadRequests'] == {'storage-upload-daemon': 1}, after
            assert after['uploadMetadataValid'] and not after['cookiesSeen'], after
            assert hashlib.sha256((root / 'Music/source.wav').read_bytes()).hexdigest() == checksum
            (evidence / 'acceptance.json').write_text(json.dumps({
                'scope': __doc__, 'case': label, 'before': before, 'delivered': delivered,
                'completed': completed, 'recovered': recovered, 'after': after,
                'original_sha256': checksum, 'passed': True,
            }, indent=2) + '\n')
            print(f'iOS daemon acceptance passed: {label}', flush=True)
        finally:
            if pid:
                stop_owned(pid, signal.SIGCONT)
                stop_owned(pid, signal.SIGKILL)
            request(origin, '/__release_storage')
            for filename in ('state.json', 'recovered.json', 'background.txt'):
                source = root / filename
                if source.exists():
                    (evidence / filename).write_bytes(source.read_bytes())


def main():
    if sys.platform != 'darwin':
        raise SystemExit('This acceptance requires macOS, Xcode and an installed iPhone simulator app.')
    device = os.environ['IOS_SIMULATOR_UDID']
    output = Path(os.environ.get('LOKAL_IOS_RUNTIME_EVIDENCE_DIR', os.environ['RUNNER_TEMP'])) / 'background-transfers'
    container = Path(command('xcrun', 'simctl', 'get_app_container', device, BUNDLE, 'data').strip())
    qualify_case(device, container, output, False)
    qualify_case(device, container, output, True)


if __name__ == '__main__':
    main()
