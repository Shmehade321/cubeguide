import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('session_mutations', Path(__file__).resolve().parents[2] / 'Tools/MutationChecks/session.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SessionMutationTests(unittest.TestCase):
    def test_only_completed_behavioral_failures_count(self):
        self.assertTrue(module.behavioral_failure(1, '✘ Test run with 2 tests in 0 suites failed after 0.1 seconds with 1 issue.'))
        for code, text in [(0, 'Test run with 2 tests failed'), (1, 'error: compiler failed'),
                           (1, 'Test run with 0 tests failed'), (-9, 'Test run with 2 tests failed'),
                           (1, 'Test run with 2 tests passed'), (None, 'timeout')]:
            self.assertFalse(module.behavioral_failure(code, text))

    def test_source_is_mutated_then_restored_even_after_exception(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'source.swift'
            original = b'guard revision == expected else { return }\n'
            path.write_bytes(original)
            def execute():
                self.assertIn('guard true', path.read_text())
                raise RuntimeError('test runner interrupted')
            with self.assertRaisesRegex(RuntimeError, 'interrupted'):
                module.apply_mutation(path, 'revision == expected', 'true', execute)
            self.assertEqual(path.read_bytes(), original)

    def test_target_drift_never_edits_source_or_runs_test(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'source.swift'
            path.write_text('same same')
            for target in ['absent', 'same']:
                with self.assertRaisesRegex(ValueError, 'target drift'):
                    module.apply_mutation(path, target, 'new', lambda: self.fail('must not run'))
                self.assertEqual(path.read_text(), 'same same')
