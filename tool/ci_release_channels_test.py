import unittest
from release_channels import calculate, EPOCH


class Channels(unittest.TestCase):
    spec = 'name: flick\nversion: 1.0.0+1000\n'
    def calc(self, channel, tags=(), **kwargs):
        return calculate(self.spec, channel, tags, '7', now=EPOCH+123456, **kwargs)
    def test_first_stable_and_nightly_share_an_updateable_code(self):
        stable=self.calc('stable');nightly=self.calc('nightly')
        self.assertEqual(stable['tag'],'android')
        self.assertEqual(nightly['tag'],'')
        self.assertEqual(stable['build_number'],nightly['build_number'])
        self.assertGreater(int(stable['build_number']),1000)
        self.assertEqual(stable['prerelease'],'false')
        self.assertEqual(nightly['prerelease'],'true')
    def test_desktop_bump_choices_and_prepared_first_release(self):
        for bump, expected in [('patch','1.0.1'), ('minor','1.1.0'), ('major','2.0.0')]:
            self.assertEqual(self.calc('stable', ['v1.0.0'], bump=bump)['version'], expected)
            self.assertEqual(self.calc('stable', bump=bump)['version'], '1.0.0')
    def test_follow_up_releases_use_latest_tag_without_pubspec_edit(self):
        tags=['v1.0.0','v1.2.3']
        self.assertEqual(self.calc('stable', tags)['version'], '1.2.4')
        self.assertEqual(self.calc('stable', tags, bump='major')['version'], '2.0.0')
        self.assertEqual(self.calc('nightly', tags)['version'], '1.2.4-nightly.7')
        for requested in ['0.9.0', '1.2.2', '1.2.3', '2.0.0-rc.1']:
            with self.subTest(requested=requested), self.assertRaises(ValueError):
                self.calc('stable', tags, requested=requested)
    def test_pushed_selected_tag_can_exceed_pubspec(self):
        self.assertEqual(self.calc('stable', ref='refs/tags/v2.0.0')['version'],'2.0.0')

    def test_explicit_replacement_keeps_version_and_advances_android_code(self):
        self.assertEqual(self.calc('stable',['v1.0.0'],replace=True)['version'], '1.0.0')
        self.assertEqual(self.calc('stable',['v1.0.0'],replace=True)['replace'], 'true')
        for kwargs in [dict(replace=True), dict(tags=['v1.0.0'], replace=True, requested='2.0.0')]:
            with self.assertRaises(ValueError): self.calc('stable', **kwargs)
        with self.assertRaises(ValueError): self.calc('nightly',['v1.0.0'],replace=True)

    def test_next_run_uses_clock_not_independent_workflow_counters(self):
        earlier=calculate(self.spec,'nightly',[],'700',now=EPOCH+123456)
        later=calculate(self.spec,'stable',[],'1',now=EPOCH+123457)
        self.assertGreater(int(later['build_number']),int(earlier['build_number']))
    def test_after_stable_nightly_targets_next_patch(self):
        result=self.calc('nightly',['v1.0.0','beta-60-1','v1.0.0-nightly.2'])
        self.assertEqual(result['version'],'1.0.1-nightly.7')
        self.assertEqual(result['previous'],'v1.0.0')
    def test_previous_notes_baseline_ignores_nightly_and_beta(self):
        self.assertEqual(self.calc('stable',['v0.9.0','v0.8.9','v0.9.1-nightly.7','beta-60-1'])['previous'],'v0.9.0')
    def test_retry_nightly_gets_a_distinct_artifact_version_without_a_tag(self):
        self.assertEqual(self.calc('nightly',attempt='2')['version'],'1.0.0-nightly.7.r2')
        self.assertEqual(self.calc('nightly',attempt='2')['tag'],'')

    def test_rolling_metadata_preserves_version_after_legacy_tags_are_removed(self):
        result = self.calc('stable', published_version='7.5.2', published_build='900000')
        self.assertEqual(result['version'], '7.5.3')
        self.assertEqual(result['tag'], 'android')
        self.assertEqual(result['build_number'], '900001')
        self.assertEqual(self.calc('stable', published_version='7.5.2', replace=True)['version'], '7.5.2')
        self.assertEqual(self.calc('nightly', published_version='7.5.2')['version'], '7.5.3-nightly.7')
        with self.assertRaises(ValueError):
            self.calc('stable', published_version='7.5.2', requested='1.0.0')
    def test_tag_must_match_pubspec_and_manual_runs_main(self):
        self.assertEqual(self.calc('stable',ref='refs/tags/v1.0.0')['version'],'1.0.0')
        for ref in ['refs/heads/feature','refs/tags/v0.9.0','refs/tags/v1.0.0-rc.1','refs/tags/v1.0.0\nsha=bad']:
            with self.subTest(ref=ref),self.assertRaises(ValueError): self.calc('stable',ref=ref)
        with self.assertRaises(ValueError): self.calc('nightly',ref='refs/tags/v1.0.0')
    def test_lower_codes_overflow_and_unmerged_versions_are_refused(self):
        for code in ['1','0','2100000001','100\nflavors=bad']:
            with self.subTest(code=code),self.assertRaises(ValueError): self.calc('stable',supplied=code)
        self.assertEqual(self.calc('stable',requested='2.0.0')['version'], '2.0.0')
        self.assertEqual(self.calc('stable',supplied='900000')['build_number'],'900000')


if __name__=='__main__':unittest.main()
