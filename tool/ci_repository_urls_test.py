"""Guard canonical repository identities after Lokal repository renames.

Kept dependency-free so the first Android CI step catches release regressions
before signing secrets are accessed.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class RenamedRepositoryContract(unittest.TestCase):
    def test_publishing_guards_are_current(self):
        for path in (
            ".github/workflows/android-release.yml",
            ".github/workflows/android-nightly.yml",
            ".github/workflows/android-signed-build.yml",
        ):
            with self.subTest(path=path):
                text = read(path)
                self.assertIn("if: github.repository == 'lokal-music/Mobile'", text)
                self.assertNotIn("if: github.repository == 'Lokal-music/lokal-mobile'", text)

    def test_update_api_and_native_apk_validator(self):
        dart = read("lib/features/updates/github_update_service.dart")
        kotlin = read(
            "android/app/src/main/kotlin/com/mossapps/flick/LokalAppUpdater.kt"
        )
        self.assertIn("static const _repo = 'lokal-music/Mobile';", dart)
        self.assertIn("https://github.com/lokal-music/Mobile/releases", dart)
        self.assertIn("'lokal-music/mobile'", dart)
        self.assertIn("'lokal-music/lokal-mobile'", dart)
        self.assertIn('"lokal-music/mobile"', kotlin)
        self.assertIn('"lokal-music/lokal-mobile"', kotlin)
        self.assertIn('"lokal-konnekt/lokal-mobile"', kotlin)

    def test_outbound_release_and_desktop_links(self):
        self.assertIn("/repos/lokal-music/Mobile/releases/tags/",
            read("lib/features/whats_new/data/lokal_minor_release_notes.dart"))
        self.assertIn("https://github.com/lokal-music/Mobile/releases",
            read("lib/features/settings/lokal/groups/about_group.dart"))
        self.assertIn("https://github.com/lokal-music/Desktop",
            read("README.md"))
        self.assertIn("https://github.com/lokal-music/Mobile/releases",
            read("README.md"))

    def test_builtin_radio_catalog_follows_renamed_desktop(self):
        self.assertIn(
            "https://raw.githubusercontent.com/lokal-music/Desktop/refs/heads/main/radios.json",
            read("lib/features/internet_radio/radio_catalog.dart"),
        )
        self.assertIn(
            "/repos/lokal-music/Desktop/contents/radios.json",
            read("lib/features/internet_radio/radio_providers.dart"),
        )


if __name__ == "__main__":
    unittest.main()
