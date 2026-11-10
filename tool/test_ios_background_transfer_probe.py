import signal
import subprocess
import unittest
from unittest.mock import patch

import ios_background_transfer_probe as probe


class ProbeLaunchTests(unittest.TestCase):
    def run_result(self, code=0, output=''):
        return subprocess.CompletedProcess(['xcrun', 'simctl', 'terminate'], code, output)

    def test_launch_terminates_separately_and_supplies_fresh_environment(self):
        with patch.object(probe.subprocess, 'run', return_value=self.run_result()) as stop, \
                patch.object(probe, 'command', return_value='app.lokal.mobile: 42') as launch:
            self.assertEqual(probe.launch('device', {'RUN': 'new', 'RECOVER': 'true'}), 42)
        self.assertEqual(stop.call_args.args[0],
                         ['xcrun', 'simctl', 'terminate', 'device', probe.BUNDLE])
        self.assertEqual(launch.call_args.args,
                         ('xcrun', 'simctl', 'launch', 'device', probe.BUNDLE))
        self.assertEqual(launch.call_args.kwargs['env']['SIMCTL_CHILD_LOKAL_IOS_DAEMON_PROBE_RUN'], 'new')
        self.assertEqual(launch.call_args.kwargs['env']['SIMCTL_CHILD_LOKAL_IOS_DAEMON_PROBE_RECOVER'], 'true')

    def test_already_dead_process_can_launch_but_other_termination_failures_stop(self):
        for output, allowed in [('found nothing to terminate', True), ('not running', True),
                                ('device unavailable', False)]:
            with self.subTest(output=output), \
                    patch.object(probe.subprocess, 'run', return_value=self.run_result(3, output)), \
                    patch.object(probe, 'command', return_value='app.lokal.mobile: 42') as launch:
                if allowed:
                    self.assertEqual(probe.launch('device', {}), 42)
                else:
                    with self.assertRaises(subprocess.CalledProcessError):
                        probe.launch('device', {})
                    launch.assert_not_called()

    def test_owned_kill_waits_for_process_exit(self):
        with patch.object(probe.os, 'kill', side_effect=[None, None, ProcessLookupError()]) as kill, \
                patch.object(probe.time, 'sleep'):
            probe.stop_owned(42, signal.SIGKILL)
        self.assertEqual(kill.call_args_list[-1].args, (42, 0))
        self.assertEqual(kill.call_count, 3)

    def test_launch_must_identify_the_new_owned_process(self):
        with patch.object(probe.subprocess, 'run', return_value=self.run_result()), \
                patch.object(probe, 'command', return_value='no process identifier'):
            with self.assertRaisesRegex(RuntimeError, 'Cannot identify'):
                probe.launch('device', {})


if __name__ == '__main__':
    unittest.main()
