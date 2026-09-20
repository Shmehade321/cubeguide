"""V17: logging must not turn failing, empty or skipped test runs green."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

class RunnerTests(unittest.TestCase):
    def run_fixture(self, message, status):
        with tempfile.TemporaryDirectory() as directory:
            log = pathlib.Path(directory) / 'run.log'
            result = subprocess.run(['bash', str(ROOT / 'Scripts/run-logged.sh'), str(log),
                                     'python3', '-c', f'print({message!r}); raise SystemExit({status})'],
                                    capture_output=True, text=True)
            self.assertTrue(log.exists(), result.stderr)
            self.assertIn(message, log.read_text())
            return result.returncode

    def test_failure_preserved_even_with_success_text(self):
        self.assertEqual(self.run_fixture('Test run with 1 test passed', 42), 42)

    def test_success_command_preserved(self):
        self.assertEqual(self.run_fixture('command completed', 0), 0)

class SwiftResultTests(unittest.TestCase):
    def check_log(self, message):
        with tempfile.TemporaryDirectory() as directory:
            log = pathlib.Path(directory) / 'swift.log'
            log.write_text(message)
            return subprocess.run(['python3', str(ROOT / 'Scripts/check-swift-results.py'), str(log)],
                                  capture_output=True).returncode

    def test_accepts_executed_suite(self):
        self.assertEqual(self.check_log('✔ Test run with 3 tests in 1 suite passed after 0.1 seconds.\n'), 0)

    def test_rejects_no_discovery(self):
        self.assertNotEqual(self.check_log('Build complete!\n'), 0)

    def test_rejects_zero_tests(self):
        self.assertNotEqual(self.check_log('✔ Test run with 0 tests passed after 0.1 seconds.\n'), 0)

    def test_rejects_skipped_test(self):
        self.assertNotEqual(self.check_log('↷ Test skipped\n✔ Test run with 3 tests passed after 0.1 seconds.\n'), 0)

    def test_rejects_failed_test(self):
        self.assertNotEqual(self.check_log('✘ Test failed\n✔ Test run with 3 tests passed after 0.1 seconds.\n'), 0)

if __name__ == '__main__':
    unittest.main()
