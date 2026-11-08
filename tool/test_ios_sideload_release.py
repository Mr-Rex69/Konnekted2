"""Negative controls for the public release boundary; never publishes assets."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from ios_sideload_release import validate_context


class ReleaseBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        self.bridge = self.repo / 'ios/Runner/LokalTransferBridge.swift'
        self.bridge.parent.mkdir(parents=True)
        self.bridge.write_text('let libraryImport = true\nlet upload = true\nprivate final class LokalTransferReply {}\n')
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True)
        subprocess.run(['git', '-C', str(self.repo), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.repo), '-c', 'user.name=Fixture', '-c',
                        'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture'], check=True)
        self.commit = subprocess.check_output(['git', '-C', str(self.repo), 'rev-parse', 'HEAD'], text=True).strip()
        self.environment = {'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF_NAME': 'release/ios-sideload-fixture',
                            'GITHUB_SHA': self.commit, 'GITHUB_RUN_NUMBER': '1', 'GITHUB_RUN_ATTEMPT': '1'}

    def test_exact_release_context_is_required(self):
        self.assertEqual(validate_context(self.repo, self.environment), self.commit)
        for key, value in [('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_REF_NAME', 'main'),
                           ('GITHUB_SHA', '0' * 40), ('GITHUB_RUN_NUMBER', '')]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_context(self.repo, {**self.environment, key: value})

    def test_disabled_or_absent_product_capability_refuses_publication(self):
        self.bridge.write_text('let libraryImport = false\nlet upload = false\n')
        with self.assertRaisesRegex(ValueError, 'not enabled'):
            validate_context(self.repo, self.environment)
        self.bridge.write_text('let libraryImport = true\n// upload still pending\n')
        with self.assertRaisesRegex(ValueError, 'upload'):
            validate_context(self.repo, self.environment)

    def test_manual_main_publication_is_explicit_and_never_accepts_a_pr(self):
        manual = {**self.environment, 'GITHUB_EVENT_NAME': 'workflow_dispatch',
                  'GITHUB_REF_NAME': 'main', 'LOKAL_IOS_PUBLISH': 'true'}
        self.assertEqual(validate_context(self.repo, manual), self.commit)
        for change in ({'LOKAL_IOS_PUBLISH': 'false'}, {'GITHUB_REF_NAME': 'feature/test'},
                       {'GITHUB_EVENT_NAME': 'pull_request'}):
            with self.assertRaises(ValueError):
                validate_context(self.repo, {**manual, **change})
