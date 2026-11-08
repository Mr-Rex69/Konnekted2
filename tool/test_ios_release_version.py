import unittest
from ios_release_version import calculate


class IosReleaseVersionTests(unittest.TestCase):
    def test_each_bump_uses_published_ios_version(self):
        for bump, expected in [('patch', '1.2.4'), ('minor', '1.3.0'), ('major', '2.0.0')]:
            self.assertEqual(calculate('1.0.0', '1.2.3', 167, 168, bump), (expected, '168'))

    def test_explicit_110_and_monotonic_build(self):
        self.assertEqual(calculate('1.0.0', '1.0.0', 200, 168, requested='1.1.0'), ('1.1.0', '201'))

    def test_invalid_or_reused_versions_fail(self):
        for version in ('1.0.0', '0.9.0', '1.1', '1.1.0-beta', '01.1.0'):
            with self.subTest(version=version), self.assertRaises(ValueError):
                calculate('1.0.0', '1.0.0', 167, 168, requested=version)

    def test_pubspec_baseline_and_minor_reset(self):
        self.assertEqual(calculate('1.0.0', '', 0, 1, 'minor'), ('1.1.0', '1'))
        self.assertEqual(calculate('2.0.0', '1.9.9', 100, 101), ('2.0.1', '101'))
