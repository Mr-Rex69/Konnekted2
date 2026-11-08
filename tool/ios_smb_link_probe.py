#!/usr/bin/env python3
"""Link the real pinned SMB framework before building the complete app.

Checks Apple device/simulator SDK links with a negative control. A Linux LLVM
mode is available for the actual arm64 Mach-O link only; it does not qualify
Apple SDKs, installed FFI lookup or runtime networking.
"""
import argparse
import json
from pathlib import Path
import subprocess
import struct
import tempfile
import urllib.parse

from ios_native_symbols import load_commands


def plugin_root():
    config = Path('.dart_tool/package_config.json').resolve()
    row = next(p for p in json.loads(config.read_text())['packages'] if p['name'] == 'dart_smb2')
    uri = urllib.parse.urlparse(urllib.parse.urljoin(config.as_uri(), row['rootUri']))
    if uri.scheme != 'file':
        raise ValueError('Expected the locked local SMB plugin')
    return Path(urllib.parse.unquote(uri.path))


def run_probe(clang, framework, target, directory, *, sdk=None, linker=None):
    directory.mkdir()
    source = directory / 'anchor.c'
    source.write_text('extern void *smb2_init_context(void);\n'
                      'void *lokal_smb_link_probe(void) { return smb2_init_context(); }\n')
    obj = directory / 'anchor.o'
    compiler = [clang, '-target', target]
    if sdk:
        compiler += ['-isysroot', sdk]
    subprocess.run([*compiler, '-c', str(source), '-o', str(obj)], check=True)
    output = directory / 'SmbProbe'
    if linker:
        # This Linux cross-link has no Apple libSystem SDK. Permit only its
        # known lazy binder, while SMB references still require real exports.
        base = [linker, '-dylib', '-arch', 'arm64', '-platform_version', 'ios', '16.0', '26.0',
                '-U', 'dyld_stub_binder', '-u', '_smb2_init_context', '-o', str(output), str(obj)]
    else:
        base = [*compiler, '-dynamiclib', '-Wl,-u,_smb2_init_context', str(obj), '-o', str(output)]
    negative = subprocess.run(base, capture_output=True, text=True)
    if negative.returncode == 0 or 'smb2_init_context' not in negative.stderr:
        raise ValueError('The missing-framework negative control did not reject SMB linkage')
    (directory / 'missing-framework.log').write_text(negative.stderr)
    subprocess.run([*base, '-F', str(framework.parent), '-framework', 'libsmb2'], check=True)
    # A real dependency command is required, not a symbol spelling found in
    # strings/debug metadata. The existing framework inspector checks all FFI.
    found = []
    for kind, command in load_commands(output.read_bytes()):
        if kind == 0xc:
            offset = struct.unpack_from('<I', command, 8)[0]
            found.append(command[offset:].split(b'\0', 1)[0])
    if b'@rpath/libsmb2.framework/libsmb2' not in found:
        raise ValueError('Linked probe did not retain the native SMB load command')
    return {'target': target, 'missing_framework_refused': True,
            'actual_framework_linked': True, 'native_load_command_retained': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--portable-clang')
    parser.add_argument('--portable-linker')
    args = parser.parse_args()
    if bool(args.portable_clang) != bool(args.portable_linker):
        parser.error('Pass both portable LLVM tools, or neither for Apple SDK qualification')
    framework = plugin_root() / 'ios/dart_smb2/Frameworks/libsmb2.xcframework'
    with tempfile.TemporaryDirectory(prefix='lokal-smb-link-') as work:
        root = Path(work)
        if args.portable_clang:
            results = [run_probe(args.portable_clang,
                framework / 'ios-arm64/libsmb2.framework', 'arm64-apple-ios16.0', root / 'device',
                linker=args.portable_linker)]
        else:
            results = []
            for name, sdk, target, slice_name in [
                ('device', 'iphoneos', 'arm64-apple-ios16.0', 'ios-arm64'),
                ('simulator', 'iphonesimulator', 'arm64-apple-ios16.0-simulator', 'ios-arm64_x86_64-simulator'),
            ]:
                clang = subprocess.check_output(['xcrun', '--sdk', sdk, '--find', 'clang'], text=True).strip()
                sdk_path = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], text=True).strip()
                results.append(run_probe(clang, framework / slice_name / 'libsmb2.framework',
                                         target, root / name, sdk=sdk_path))
        print(json.dumps({'apple_sdk_qualified': not bool(args.portable_clang),
                          'runtime_qualified': False, 'links': results}, indent=2))


if __name__ == '__main__':
    main()
