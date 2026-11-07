"""Read loaded images and public symbols from the actual arm64 Mach-O slice."""
import struct

SOULSEEK_SYMBOLS = frozenset('_lokal_soulseek_' + suffix
                            for suffix in ('invoke', 'free', 'suspend', 'resume'))


def arm64_image(binary):
    if len(binary) < 8:
        raise ValueError('Truncated Mach-O image')
    magic, count = struct.unpack_from('>II', binary)
    if magic not in (0xcafebabe, 0xcafebabf):
        return binary
    width = 20 if magic == 0xcafebabe else 32
    if count < 1 or count > 32 or 8 + count * width > len(binary):
        raise ValueError('Invalid universal Mach-O inventory')
    selected = []
    for i in range(count):
        fields = struct.unpack_from('>IIIII' if width == 20 else '>IIQQII', binary, 8 + i * width)
        cpu, subtype, offset, size = fields[:4]
        if offset < 8 + count * width or size < 32 or offset + size > len(binary):
            raise ValueError('Invalid universal Mach-O slice bounds')
        if cpu == 0x100000c and subtype & 0xffffff == 0:
            selected.append(binary[offset:offset + size])
    if len(selected) != 1:
        raise ValueError('Expected one generic arm64 Mach-O slice')
    return selected[0]


def load_commands(binary):
    binary = arm64_image(binary)
    if len(binary) < 32:
        raise ValueError('Truncated Mach-O header')
    magic, cpu, _, _, count, size, _, _ = struct.unpack_from('<8I', binary)
    if magic != 0xfeedfacf or cpu != 0x100000c or size > len(binary) - 32:
        raise ValueError('Expected a thin arm64 Mach-O image')
    position = 32
    for _ in range(count):
        if position + 8 > 32 + size:
            raise ValueError('Truncated Mach-O load command')
        command, length = struct.unpack_from('<II', binary, position)
        if length < 8 or position + length > 32 + size:
            raise ValueError('Invalid Mach-O load command bounds')
        yield command, binary[position:position + length]
        position += length


def loaded_images(executable, paths, read):
    installed = {'@rpath/' + path[len('Frameworks/'):]: path
                 for path in paths if path.startswith('Frameworks/')}
    pending, seen = [executable], set()
    while pending:
        path = pending.pop()
        if path in seen:
            continue
        seen.add(path)
        for kind, command in load_commands(read(path)):
            if kind in (0xc, 0x80000018, 0x8000001f, 0x80000023):
                if len(command) < 24:
                    raise ValueError('Truncated Mach-O dylib command')
                offset = struct.unpack_from('<I', command, 8)[0]
                end = command.find(b'\0', offset)
                if offset < 24 or offset >= len(command) or end < 0:
                    raise ValueError('Invalid Mach-O dylib name')
                name = command[offset:end].decode('utf-8')
                if name in installed:
                    pending.append(installed[name])
    return seen


def defined_symbols(binary):
    binary = arm64_image(binary)
    table = None
    for kind, command in load_commands(binary):
        if kind == 2:
            if table is not None or len(command) < 24:
                raise ValueError('Invalid Mach-O symbol command')
            table = struct.unpack_from('<4I', command, 8)
    if table is None:
        raise ValueError('Missing Mach-O public symbol inventory')
    offset, count, strings, strings_size = table
    if offset + count * 16 > len(binary) or strings + strings_size > len(binary):
        raise ValueError('Invalid Mach-O symbol/string inventory bounds')
    result = set()
    for i in range(count):
        index, flags, _, _, _ = struct.unpack_from('<IBBHQ', binary, offset + i * 16)
        # External, defined, non-private, non-debug symbols only. An undefined
        # import with the right spelling is not proof that the app bundles FFI.
        if flags & 0xe0 or flags & 0x10 or not flags & 1 or flags & 0xe == 0:
            continue
        if index >= strings_size:
            raise ValueError('Invalid Mach-O symbol string index')
        end = binary.find(b'\0', strings + index, strings + strings_size)
        if end < 0:
            raise ValueError('Unterminated Mach-O symbol name')
        result.add(binary[strings + index:end].decode('utf-8'))
    return result


def inspect_soulseek(binary):
    missing = SOULSEEK_SYMBOLS - defined_symbols(binary)
    if missing:
        raise ValueError('Missing bundled Soulseek FFI exports: ' + ', '.join(sorted(missing)))
    return {'defined_exports': sorted(SOULSEEK_SYMBOLS), 'engine_version': '20.0.0'}


def inspect_soulseek_images(executable, paths, read):
    framework = 'Frameworks/rust_lib_flick_player.framework/rust_lib_flick_player'
    defining = framework if framework in paths else executable
    if defining not in loaded_images(executable, paths, read):
        raise ValueError('Bundled Rust image is not loaded for process FFI lookup')
    result = inspect_soulseek(read(defining))
    result.update(binary=defining, ffi_load_reachable=True)
    return result
