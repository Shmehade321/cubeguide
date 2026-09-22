#!/usr/bin/env python3
"""Run line-oriented qualification tools in isolated ordered process shards."""
import argparse
import pathlib
import subprocess
import sys
import tempfile


class WorkerFailure(RuntimeError):
    pass


def _split(source, directory, workers):
    if workers <= 0:
        raise ValueError('workers must be positive')
    with source.open('rb') as incoming:
        line_count = sum(1 for _ in incoming)
    if line_count == 0:
        raise ValueError('input must contain at least one line')
    worker_count = min(workers, line_count)
    base, extra = divmod(line_count, worker_count)
    paths = [directory / f'input-{index:03}.txt' for index in range(worker_count)]
    with source.open('rb') as incoming:
        for index, path in enumerate(paths):
            count = base + (1 if index < extra else 0)
            with path.open('xb') as shard:
                for _ in range(count):
                    line = incoming.readline()
                    if not line:
                        raise RuntimeError('input changed while it was being partitioned')
                    shard.write(line)
        if incoming.read(1):
            raise RuntimeError('input changed while it was being partitioned')
    return paths, line_count


def _publish(parts, output):
    if output.exists():
        raise FileExistsError(f'output already exists: {output}')
    temporary = output.with_name(output.name + '.partial')
    try:
        with temporary.open('xb') as combined:
            for part in parts:
                with part.open('rb') as source:
                    while chunk := source.read(1024 * 1024):
                        combined.write(chunk)
        temporary.replace(output)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def _execute(source, output, command, workers, mode):
    source = pathlib.Path(source)
    output = pathlib.Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise FileExistsError(f'output already exists: {output}')
    with tempfile.TemporaryDirectory(prefix='cubeguide-shards-') as value:
        directory = pathlib.Path(value)
        inputs, line_count = _split(source, directory, workers)
        processes = []
        handles = []
        outputs = []
        for index, shard in enumerate(inputs):
            result = directory / f'output-{index:03}.txt'
            log = directory / f'worker-{index:03}.log'
            stdin = shard.open('rb')
            log_handle = log.open('wb')
            handles.extend([stdin, log_handle])
            if mode == 'benchmark':
                process = subprocess.Popen(
                    [*command, str(result)], stdin=stdin, stdout=log_handle, stderr=subprocess.STDOUT)
            else:
                result_handle = result.open('xb')
                handles.append(result_handle)
                process = subprocess.Popen(
                    command, stdin=stdin, stdout=result_handle, stderr=log_handle)
            processes.append((index, process, log))
            outputs.append(result)
        failures = []
        for index, process, log in processes:
            code = process.wait()
            if code:
                failures.append((index, code, log.read_text(errors='replace')))
        for handle in handles:
            handle.close()
        if failures:
            details = '\n'.join(
                f'worker {index} exited {code}:\n{log}' for index, code, log in failures)
            raise WorkerFailure(details)
        _publish(outputs, output)
        with output.open('rb') as combined:
            actual = sum(1 for _ in combined)
        if actual != line_count:
            output.unlink(missing_ok=True)
            raise WorkerFailure(f'expected {line_count} results, found {actual}')
        for index, _, log in processes:
            content = log.read_text(errors='replace').strip()
            if content:
                print(f'[worker {index}] {content}', file=sys.stderr)
        print(f'Parallel {mode} completed {line_count} lines across {len(inputs)} workers.')


def run_benchmark(source, output, command, workers):
    _execute(source, output, command, workers, 'benchmark')


def run_stdio(source, output, command, workers):
    _execute(source, output, command, workers, 'stdio')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('benchmark', 'stdio'))
    parser.add_argument('--workers', type=int, required=True)
    parser.add_argument('--input', type=pathlib.Path, required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args, command = parser.parse_known_args()
    command = command[1:] if command[:1] == ['--'] else command
    if not command:
        parser.error('a worker command is required after --')
    if args.mode == 'benchmark':
        run_benchmark(args.input, args.output, command, args.workers)
    else:
        run_stdio(args.input, args.output, command, args.workers)


if __name__ == '__main__':
    main()
