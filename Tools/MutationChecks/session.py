#!/usr/bin/env python3
"""Run alone: qualify session tests with seeded defects and restore every source edit."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'Packages/CubeKit/Sources/CubeSession'


def behavioral_failure(code, output):
    return code == 1 and bool(re.search(r'Test run with [1-9]\d* tests?[^\n]* failed', output))


def apply_mutation(path, old, new, execute):
    original = path.read_bytes()
    source = original.decode()
    if source.count(old) != 1:
        raise ValueError('Mutation target drift: ' + str(path))
    try:
        path.write_text(source.replace(old, new))
        return execute()
    finally:
        path.write_bytes(original)


MUTATIONS = [
    ('accept-stale-solve', 'Session.swift', 'response.revision == session.revision,', 'true,', 'checkedSolveResults'),
    ('accept-wrong-guide-save-id', 'Session.swift', 'guard let save = session.pendingSave, save.id == id else', 'guard let save = session.pendingSave else', 'acknowledgedSaveBarrier'),
    ('advance-before-ack-save', 'Session.swift', '_ = beginSave(.acknowledgement, progress: candidate)\n    case .persistFailed', 'next.guideProgress = candidate\n      _ = beginSave(.acknowledgement, progress: candidate)\n    case .persistFailed', 'acknowledgedSaveBarrier'),
    ('double-apply-acknowledgement', 'GuideProgress.swift', 'acknowledgedActions: acknowledgedActions + 1)', 'acknowledgedActions: acknowledgedActions + 2)', 'stableGuideProgress'),
    ('preview-advances-physical-state', 'Session.swift', 'next.preview = .finished\n      next.playbackID = nil', 'next.preview = .finished\n      if let id = next.pendingAction?.id { next.guideProgress = try? next.guideProgress?.acknowledging(id) }\n      next.playbackID = nil', 'playbackCannotAdvance'),
    ('play-without-alignment', 'Session.swift', 'guard session.phase == .guide, session.preparationDurable, session.aligned,', 'guard session.phase == .guide, session.preparationDurable,', 'durablePreparationBarrier'),
    ('trust-restored-alignment', 'Session.swift', 'self.init(revision: archive.progress.revision)', 'self.init(revision: archive.progress.revision)\n    aligned = true', 'archiveSessionRestore'),
    ('accept-wrong-draft-save-id', 'Session.swift', 'guard let request = session.pendingDraftSave, request.id == id else', 'guard let request = session.pendingDraftSave else', 'draftSaveBarrier'),
    ('lose-durable-recovery', 'Session.swift', 'recoveryRequired = archive.recoveryRequired', 'recoveryRequired = false', 'recoveryArchiveRoundTrip'),
    ('mislabel-entered-completion', 'Session.swift', 'kind = .enteredColorsSolved\n      } else', 'kind = .userConfirmed\n      } else', 'enteredColorsCompletion'),
    ('advance-scan-before-save', 'ScanWorkflow.swift', 'next.pendingSave = request\n      next.afterSave = phase', 'next.pendingSave = request\n      next.durable = scan\n      next.afterSave = phase', 'scanWorkflowSixFaces'),
    ('accept-stale-camera-frame', 'ScanWorkflow.swift', 'case .captured(let id, let face):\n        guard workflow.phase == .freezing, workflow.captureID == id else', 'case .captured(let id, let face):\n        guard workflow.phase == .freezing else', 'scanWorkflowCaptureFailures'),
    ('accept-old-camera-run-event', 'SessionController.swift',
     'guard let self, self.generation == expectedGeneration, self.cameraRun == run else { return }\n        switch event',
     'guard let self, self.generation == expectedGeneration else { return }\n        switch event', 'scanCoordinatorCameraGenerations'),
    ('retain-deleted-producer-lease', 'SessionStore.swift', 'self.lease = StorageLease(value: UUID())\n    try checkpoint(.beforeDelete)', 'try checkpoint(.beforeDelete)', 'storeDeletionLease'),
    ('lose-discard-revision-floor', 'Session.swift', 'public var latestInputRevision: UInt64 { max(revision, revisionFloor) }', 'public var latestInputRevision: UInt64 { revision }', 'draftDiscardManual'),
    ('lose-manual-fallback-overrides', 'ManualDraft.swift', 'cells[base + cell] = face.manualOverrides[cell]', 'cells[base + cell] = nil', 'manualFallbackModel'),
    ('trust-corrupt-archive-state', 'GuideArchive.swift', 'payload.state == progress.state, payload.pendingAction == progress.pending?.id,', 'payload.pendingAction == progress.pending?.id,', 'archiveSemanticGuards'),
]


def run_test(test):
    try:
        run = subprocess.run(['swift', 'test', '--package-path', 'Packages/CubeKit', '--filter', test],
                             cwd=ROOT, capture_output=True, text=True, timeout=120)
        return run.returncode, run.stdout + run.stderr
    except subprocess.TimeoutExpired as error:
        def text(value):
            return value.decode(errors='replace') if isinstance(value, bytes) else (value or '')
        return None, text(error.stdout) + text(error.stderr) + '\nTimed out; not a behavioral detection.\n'


def qualify(output):
    output.mkdir(parents=True, exist_ok=False)
    code, baseline = run_test('CubeSessionTests')
    (output / 'baseline.log').write_text(baseline)
    if code != 0 or not re.search(r'Test run with [1-9]\d* tests?[^\n]* passed', baseline):
        raise RuntimeError('Unmodified session baseline did not pass')
    results = []
    for name, filename, old, new, test in MUTATIONS:
        path = SOURCE / filename
        before = hashlib.sha256(path.read_bytes()).hexdigest()
        row = {'mutation': name, 'test': test, 'source': str(path.relative_to(ROOT)), 'sourceSHA256': before}
        try:
            code, log = apply_mutation(path, old, new, lambda: run_test(test))
            (output / (name + '.log')).write_text(log)
            row.update(killed=behavioral_failure(code, log), exitCode=code)
        except Exception as error:
            row.update(killed=False, error=str(error))
        row['sourceRestored'] = hashlib.sha256(path.read_bytes()).hexdigest() == before
        results.append(row)
        (output / 'summary.json').write_text(json.dumps(results, indent=2) + '\n')
        print(json.dumps(row), flush=True)
        if not row['sourceRestored']:
            raise RuntimeError('Source restoration failed')
    if not all(row['killed'] for row in results):
        raise RuntimeError('A mutation survived or lacked a completed behavioral failure')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    qualify(parser.parse_args().output)
