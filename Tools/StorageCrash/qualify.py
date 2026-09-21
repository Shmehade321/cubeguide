#!/usr/bin/env python3
"""Kill real host store writers, then reopen their files in independent processes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import shutil
import subprocess
import time

BOUNDARIES = ("beforeWrite", "temporarySynced", "beforeReplace", "afterReplace")
CASES = [(kind, boundary) for kind in ("guide", "turn", "draft", "manual") for boundary in BOUNDARIES]
CASES.append(("delete", "beforeDelete"))


def stop_and_kill(command, announcement, timeout=10):
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            pid, status = os.waitpid(process.pid, os.WNOHANG | os.WUNTRACED)
            if pid:
                if not os.WIFSTOPPED(status) or os.WSTOPSIG(status) != signal.SIGSTOP:
                    if os.WIFEXITED(status):
                        process.returncode = os.WEXITSTATUS(status)
                    elif os.WIFSIGNALED(status):
                        process.returncode = -os.WTERMSIG(status)
                    raise RuntimeError("Writer exited or received an unexpected signal before the requested stop")
                os.kill(process.pid, signal.SIGKILL)
                output, errors = process.communicate(timeout=5)
                if process.returncode != -signal.SIGKILL:
                    raise RuntimeError("Writer was not terminated by SIGKILL")
                if output.decode().strip() != announcement or errors:
                    raise RuntimeError("Stopped writer did not report the requested boundary cleanly")
                return {"stoppedSignal": "SIGSTOP", "terminationSignal": "SIGKILL",
                        "returncode": process.returncode, "announcement": announcement}
            time.sleep(0.005)
        raise RuntimeError("Writer never reached its requested boundary before the deadline")
    finally:
        if process.returncode is None:
            process.kill()
        process.communicate(timeout=5)


def invoke(probe, *arguments):
    return subprocess.run([str(probe), *map(str, arguments)], capture_output=True,
                          check=True, timeout=15).stdout


def snapshot(probe, directory):
    return json.loads(invoke(probe, "inspect", directory))


def hashes(directory):
    return {file.name: hashlib.sha256(file.read_bytes()).hexdigest()
            for file in sorted(directory.iterdir()) if file.is_file()}


def validate_snapshots(before, after, kind):
    seed = {"phase": "resumeCheck", "revision": 3, "hasWork": True, "hasPlan": True,
            "aligned": False, "acknowledged": 0, "storedGuideAcknowledged": 0}
    if kind == "turn":
        seed.update(acknowledged=1, storedGuideAcknowledged=1)
    if before != seed:
        raise RuntimeError("Writer did not produce the fixed seed contract")
    if kind == "guide":
        expected = dict(seed, acknowledged=1, storedGuideAcknowledged=1)
    elif kind == "turn":
        expected = dict(seed, phase="expectedSolved", acknowledged=2, storedGuideAcknowledged=2)
    elif kind in ("draft", "manual"):
        expected = {"phase": "editing", "revision": 4, "hasWork": True, "hasPlan": False,
                    "aligned": False, "storedGuideAcknowledged": 0}
        if kind == "draft":
            cells = [None] * 54
            for face, color in enumerate(("green", "white", "orange", "blue", "yellow", "red")):
                cells[face * 9 + 4] = color
            cells[18] = "red"
            expected.update(draftRevision=4, draftCells=cells)
    elif kind == "delete":
        expected = {"phase": "home", "revision": 0, "hasWork": False,
                    "hasPlan": False, "aligned": False}
    else:
        raise RuntimeError("Unknown operation contract")
    if after != expected:
        raise RuntimeError("Writer did not produce the fixed operation contract")


def qualify(probe, output):
    probe = probe.resolve(strict=True)
    output.mkdir(parents=True, exist_ok=False)
    results = []
    for kind, boundary in CASES:
        case = output / (kind + "-" + boundary)
        working, baseline = case / "interrupted", case / "uninterrupted"
        working.mkdir(parents=True)
        baseline.mkdir()
        entry = {"operation": kind, "boundary": boundary, "result": "failed"}
        try:
            seed_arguments = ["turn"] if kind == "turn" else []
            invoke(probe, "seed", working, *seed_arguments)
            invoke(probe, "seed", baseline, *seed_arguments)
            before = snapshot(probe, working)
            invoke(probe, "mutate", baseline, kind, "none")
            after = snapshot(probe, baseline)
            validate_snapshots(before, after, kind)
            termination = stop_and_kill([str(probe), "mutate", str(working), kind, boundary],
                                        "BOUNDARY " + boundary)
            recovered = snapshot(probe, working)
            expected = after if boundary == "afterReplace" else before
            if recovered != expected:
                raise RuntimeError("Fresh process recovered an unexpected or partially advanced state")
            if recovered.get("aligned"):
                raise RuntimeError("Relaunch must not trust physical alignment")
            entry.update(termination)
            entry.update(before=before, uninterrupted=after, expected=expected, recovered=recovered,
                         interruptedFileSHA256=hashes(working))
            shutil.copytree(working, case / "files-at-interruption")
            # An abandoned temporary file must not block the next explicit write/delete.
            invoke(probe, "mutate", working, kind, "none")
            retried = snapshot(probe, working)
            if retried != after:
                raise RuntimeError("Retry did not recover to the complete expected state")
            entry["retried"] = retried
            entry["result"] = "passed"
        except Exception as error:
            entry["error"] = str(error)
        results.append(entry)
    report = {"result": "passed" if all(r["result"] == "passed" for r in results) else "failed",
              "scope": "macOS host process termination; not power loss or physical iOS qualification",
              "host": platform.platform(), "python": platform.python_version(),
              "harnessSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "probeSHA256": hashlib.sha256(probe.read_bytes()).hexdigest(),
              "caseCount": len(results), "cases": results}
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("probe", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    report = qualify(arguments.probe, arguments.output)
    print(json.dumps({"result": report["result"], "caseCount": report["caseCount"]}))
    raise SystemExit(0 if report["result"] == "passed" else 1)
