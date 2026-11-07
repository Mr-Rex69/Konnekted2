import struct
import unittest
from ios_native_symbols import defined_symbols, inspect_soulseek, SOULSEEK_SYMBOLS


def image(names, flags=0xf):
    strings = b'\0'
    records = b''
    for name in names:
        records += struct.pack('<IBBHQ', len(strings), flags, 1, 0, 4096)
        strings += name.encode() + b'\0'
    return (struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0) +
            struct.pack('<6I', 2, 24, 56, len(names), 56 + len(records), len(strings)) +
            records + strings)


class NativeSymbolTests(unittest.TestCase):
    def test_actual_defined_inventory(self):
        binary = image(sorted(SOULSEEK_SYMBOLS))
        self.assertEqual(defined_symbols(binary), SOULSEEK_SYMBOLS)
        self.assertEqual(inspect_soulseek(binary)['engine_version'], '20.0.0')

    def test_undefined_private_debug_or_missing_are_not_exports(self):
        for flags in [1, 0x1f, 0xef]:
            with self.subTest(flags=flags), self.assertRaises(ValueError):
                inspect_soulseek(image(sorted(SOULSEEK_SYMBOLS), flags))
        with self.assertRaises(ValueError):
            inspect_soulseek(image(['_lokal_soulseek_invoke']))

    def test_truncation_and_invalid_table_fail(self):
        binary = image(sorted(SOULSEEK_SYMBOLS))
        for truncated in [binary[:10], binary[:40], binary[:-1]]:
            with self.assertRaises(ValueError):
                inspect_soulseek(truncated)
        broken = bytearray(binary)
        struct.pack_into('<I', broken, 56, 0xffffffff)
        with self.assertRaises(ValueError):
            inspect_soulseek(broken)
