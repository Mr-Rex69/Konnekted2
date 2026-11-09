"""Guard the release dependency graph and complete host-test partitioning."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import yaml

from ios_flutter_checks import command
from ios_prepare_ffmpeg import archive_path

ROOT = Path(__file__).resolve().parents[1]


class IosWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.workflow = yaml.safe_load((ROOT / '.github/workflows/ios-ci.yml').read_text())
        self.jobs = self.workflow['jobs']

    def ancestors(self, name):
        dependencies = self.jobs[name].get('needs', [])
        if isinstance(dependencies, str):
            dependencies = [dependencies]
        return set(dependencies).union(*(self.ancestors(dep) for dep in dependencies))

    def test_publication_still_requires_every_independent_gate_and_both_runtimes(self):
        needed = self.ancestors('publish_sideload_beta')
        self.assertTrue({'checks', 'iphone', 'production_launch', 'simulator_build',
                         'ios_acceptance', 'ios_release_audit'} <= needed)
        self.assertEqual(self.jobs['ios_acceptance']['strategy']['matrix']['ios'], ['18.6', '26.0'])
        self.assertFalse(self.jobs['ios_acceptance']['strategy']['fail-fast'])
        for job in needed:
            self.assertFalse(self.jobs[job].get('continue-on-error', False))
            self.assertTrue(all(not step.get('continue-on-error', False)
                                for step in self.jobs[job]['steps']))

    def test_device_production_and_test_compilation_are_not_serialized(self):
        for name in ('checks', 'iphone', 'production_launch', 'simulator_build'):
            self.assertFalse(self.jobs[name].get('needs'))
        self.assertEqual(self.jobs['ios_acceptance']['needs'], 'simulator_build')
        self.assertEqual(self.jobs['ios_release_audit']['needs'], 'iphone')
        self.assertEqual(self.jobs['checks']['runs-on'], 'ubuntu-24.04')

    def test_runtime_jobs_use_exact_compiled_apps_without_building_again(self):
        steps = self.jobs['ios_acceptance']['steps']
        scripts = '\n'.join(step.get('run', '') for step in steps)
        self.assertNotIn('flutter build', scripts)
        self.assertIn('ios_control_runner.py', scripts)
        self.assertIn('ios_smoke_runner.py', scripts)
        self.assertIn('ios_background_transfer_probe.py', scripts)
        download = next(step for step in steps if 'download-artifact@' in step.get('uses', ''))
        self.assertIn('needs.simulator_build.outputs.integration_artifact', download['with']['artifact-ids'])

    def test_native_cache_is_separated_by_sdk_and_keeps_cargo_dependency_fingerprints(self):
        keys = []
        for name in ('iphone', 'production_launch', 'simulator_build'):
            steps = self.jobs[name]['steps']
            cache = next(step for step in steps if step.get('id') == 'rust_cache')
            self.assertIn('rust/Cargo.lock', cache['with']['restore-keys'])
            self.assertNotIn("'rust/**/*.rs'", cache['with']['restore-keys'])
            self.assertIn("'rust/**/*.rs'", cache['with']['key'])
            self.assertNotIn('build/ios', cache['with']['path'])
            save = next(step for step in steps if 'cache/save@' in step.get('uses', ''))
            self.assertNotIn('steps.smoke', save['if'])
            self.assertNotIn('steps.background', save['if'])
            keys.append(cache['with']['key'])
        self.assertNotEqual(keys[0], keys[1])
        self.assertEqual(keys[1], keys[2])

    def test_only_the_publisher_receives_release_write_permission(self):
        self.assertEqual(self.workflow['permissions'], {'contents': 'read'})
        for name, job in self.jobs.items():
            if name == 'publish_sideload_beta':
                self.assertEqual(job['permissions'], {'contents': 'write'})
            else:
                self.assertNotIn('write', job.get('permissions', {}).values())

    def test_failed_job_reruns_keep_the_exact_successful_ipa_without_rebuilding(self):
        self.assertIn('steps.ipa_bundle.outputs.artifact-id', self.jobs['iphone']['outputs']['ipa_artifact'])
        for name in ('ios_release_audit', 'publish_sideload_beta'):
            download = next(step for step in self.jobs[name]['steps']
                            if 'download-artifact@' in step.get('uses', ''))
            self.assertIn('needs.iphone.outputs.ipa_artifact', download['with']['artifact-ids'])
            self.assertNotIn('name', download['with'])

    def test_selected_ios_version_reaches_the_actual_device_package(self):
        inputs = self.workflow['on']['workflow_dispatch']['inputs']
        self.assertEqual(inputs['bump']['options'], ['patch', 'minor', 'major'])
        build = next(step for step in self.jobs['iphone']['steps'] if step.get('id') == 'device_build')
        self.assertIn('--build-name "$IOS_BUILD_VERSION"', build['run'])
        self.assertIn('steps.ios_version.outputs.version', build['env']['IOS_BUILD_VERSION'])

    def test_shards_use_identical_complete_selection_and_valid_indices(self):
        first = command(0, 3)
        for index in (1, 2):
            other = command(index, 3)
            self.assertEqual(first[7:], other[7:])
        self.assertTrue(all((ROOT / path).exists() for path in first[7:]))
        for index, count in ((-1, 3), (3, 3), (0, 0)):
            with self.assertRaises(ValueError):
                command(index, count)

    def test_native_archive_cache_needs_no_runner_temp_and_creates_its_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'native'
            with patch.dict('os.environ', {'LOKAL_IOS_NATIVE_ARCHIVE_CACHE': str(root)}, clear=True):
                self.assertEqual(archive_path('framework.zip'), root / 'framework.zip')
                self.assertTrue(root.is_dir())

    def test_builds_only_start_from_explicit_manual_dispatch(self):
        self.assertEqual(set(self.workflow['on']), {'workflow_dispatch'})
        self.assertIn("github.event_name == 'workflow_dispatch'", self.jobs['publish_sideload_beta']['if'])
        self.assertIn("github.ref_name == 'main'", self.jobs['publish_sideload_beta']['if'])


if __name__ == '__main__':
    unittest.main()
