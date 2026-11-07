"""Read defined public symbols directly from a thin arm64 Mach-O image."""
import struct

SOULSEEK_SYMBOLS = frozenset('_lokal_soulseek_' + suffix
                            for suffix in ('invoke', 'free', 'suspend', 'resume'))


def defined_symbols(binary):
    if len(binary) < 32:
        raise ValueError('Truncated Mach-O header')
    magic, cpu, _, _, count, size, _, _ = struct.unpack_from('<8I', binary)
    if magic != 0xfeedfacf or cpu != 0x100000c or size > len(binary) - 32:
        raise ValueError('Expected a thin arm64 Mach-O image')
    position = 32
    table = None
    for _ in range(count):
        if position + 8 > 32 + size:
            raise ValueError('Truncated Mach-O load command')
        command, length = struct.unpack_from('<II', binary, position)
        if length < 8 or position + length > 32 + size:
            raise ValueError('Invalid Mach-O load command bounds')
        if command == 2:
            if table is not None or length < 24:
                raise ValueError('Invalid Mach-O symbol command')
            table = struct.unpack_from('<4I', binary, position + 8)
        position += length
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
