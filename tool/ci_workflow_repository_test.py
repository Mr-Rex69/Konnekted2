"""Prevent signed-release workflows from silently skipping after a repo transfer."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = "Lokal-music/lokal-mobile"
WORKFLOWS = (
    ".github/workflows/android-release.yml",
    ".github/workflows/android-nightly.yml",
    ".github/workflows/android-signed-build.yml",
)


class ReleaseRepositoryGuards(unittest.TestCase):
    def test_release_entrypoints_and_reusable_build_match_current_repository(self):
        guard = f"if: github.repository == '{REPOSITORY}'"
        for name in WORKFLOWS:
            with self.subTest(workflow=name):
                source = (ROOT / name).read_text(encoding="utf-8")
                self.assertEqual(source.count(guard), 1)
                self.assertNotIn(
                    "if: github.repository == 'Lokal-Konnekt/lokal-mobile'",
                    source,
                )


if __name__ == "__main__":
    unittest.main()
