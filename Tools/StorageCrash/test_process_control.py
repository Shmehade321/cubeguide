import os
import signal
import subprocess
import sys
import unittest
from unittest.mock import patch

from qualify import stop_and_kill, validate_snapshots


def command(body):
    return [sys.executable, "-c", "import os,signal,time; " + body]


class ProcessControlTests(unittest.TestCase):
    def test_incorrect_guide_mutation_is_rejected(self):
        before = {"phase": "resumeCheck", "revision": 3, "hasWork": True, "hasPlan": True,
                  "aligned": False, "acknowledged": 0, "storedGuideAcknowledged": 0}
        wrong = {"phase": "editing", "revision": 4, "hasWork": True, "hasPlan": False,
                 "aligned": False, "storedGuideAcknowledged": 0}
        with self.assertRaisesRegex(RuntimeError, "operation contract"):
            validate_snapshots(before, wrong, "guide")

    def test_already_advanced_seed_is_rejected(self):
        wrong = {"phase": "resumeCheck", "revision": 3, "hasWork": True, "hasPlan": True,
                 "aligned": False, "acknowledged": 1, "storedGuideAcknowledged": 1}
        with self.assertRaisesRegex(RuntimeError, "seed contract"):
            validate_snapshots(wrong, wrong, "guide")

    def test_discard_must_clear_scan_and_preserve_revision_floor(self):
        before = {"phase": "resumeCheck", "revision": 3, "hasWork": True, "hasPlan": True,
                  "aligned": False, "acknowledged": 0, "storedGuideAcknowledged": 0,
                  "latestInputRevision": 5, "scanRevision": 5, "scanAcceptedCount": 1}
        correct = {key: value for key, value in before.items()
                   if key not in ("scanRevision", "scanAcceptedCount")}
        correct["latestInputRevision"] = 6
        validate_snapshots(before, correct, "discardScan")
        for wrong in (dict(before, latestInputRevision=6), dict(correct, latestInputRevision=3),
                      dict(correct, acknowledged=1), dict(correct, aligned=True)):
            with self.assertRaisesRegex(RuntimeError, "operation contract"):
                validate_snapshots(before, wrong, "discardScan")

    def test_discard_empty_entry_cannot_reopen_the_editor(self):
        before = {"phase": "editing", "revision": 4, "hasWork": True, "hasPlan": False,
                  "aligned": False, "storedGuideAcknowledged": 0}
        with self.assertRaisesRegex(RuntimeError, "operation contract"):
            validate_snapshots(before, dict(before, latestInputRevision=6), "discardEmpty")

    def test_confirmed_stop_is_killed(self):
        result = stop_and_kill(command('print("BOUNDARY test",flush=True); os.kill(os.getpid(),signal.SIGSTOP)'),
                               "BOUNDARY test")
        self.assertEqual(result["returncode"], -signal.SIGKILL)

    def test_clean_exit_is_not_a_crash_pass(self):
        with self.assertRaisesRegex(RuntimeError, "before the requested stop"):
            stop_and_kill(command('print("BOUNDARY test",flush=True)'), "BOUNDARY test")

    def test_wrong_boundary_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, "requested boundary"):
            stop_and_kill(command('print("BOUNDARY wrong",flush=True); os.kill(os.getpid(),signal.SIGSTOP)'),
                          "BOUNDARY test")

    def test_timeout_kills_and_reaps_child(self):
        children = []
        original = subprocess.Popen

        def track(*args, **kwargs):
            process = original(*args, **kwargs)
            children.append(process)
            return process

        with patch("qualify.subprocess.Popen", side_effect=track):
            with self.assertRaisesRegex(RuntimeError, "deadline"):
                stop_and_kill(command("time.sleep(60)"), "BOUNDARY test", timeout=0.1)
        self.assertEqual(len(children), 1)
        self.assertEqual(children[0].returncode, -signal.SIGKILL)
        with self.assertRaises(ChildProcessError):
            os.waitpid(children[0].pid, os.WNOHANG)


if __name__ == "__main__":
    unittest.main()
