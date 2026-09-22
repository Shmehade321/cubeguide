import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import parallel_run


class ParallelRunTests(unittest.TestCase):
    def test_benchmark_mode_preserves_input_order_across_workers(self):
        with tempfile.TemporaryDirectory() as value:
            root = pathlib.Path(value)
            source = root / 'input.jsonl'
            output = root / 'output.jsonl'
            worker = root / 'worker.py'
            source.write_text(''.join(f'{index}\n' for index in range(11)))
            worker.write_text(
                'import pathlib,sys\n'
                'path=pathlib.Path(sys.argv[1])\n'
                'path.write_text("".join(line.strip()+"-done\\n" for line in sys.stdin))\n')

            parallel_run.run_benchmark(
                source, output, [sys.executable, str(worker)], workers=3)

            self.assertEqual(
                output.read_text(), ''.join(f'{index}-done\n' for index in range(11)))

    def test_stdio_mode_propagates_a_worker_failure_without_publishing_output(self):
        with tempfile.TemporaryDirectory() as value:
            root = pathlib.Path(value)
            source = root / 'input.txt'
            output = root / 'output.txt'
            worker = root / 'worker.py'
            source.write_text('ok\nfail\nok-again\n')
            worker.write_text(
                'import sys\n'
                'lines=list(sys.stdin)\n'
                'raise SystemExit(7 if any("fail" in line for line in lines) else 0)\n')

            with self.assertRaises(parallel_run.WorkerFailure):
                parallel_run.run_stdio(
                    source, output, [sys.executable, str(worker)], workers=3)
            self.assertFalse(output.exists())

    def test_empty_input_is_rejected(self):
        with tempfile.TemporaryDirectory() as value:
            root = pathlib.Path(value)
            source = root / 'empty.txt'
            source.touch()
            with self.assertRaises(ValueError):
                parallel_run.run_stdio(source, root / 'output.txt', ['cat'], workers=2)


if __name__ == '__main__':
    unittest.main()
