import hashlib
import importlib.util
import json
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'qualification', pathlib.Path(__file__).resolve().parents[2] / 'Scripts/check-qualification.py')
qualification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qualification)


class QualificationTests(unittest.TestCase):
    def artifact(self, root, kind='test-summary', name='proof.json', **overrides):
        payload = {
            'schemaVersion': 1, 'kind': kind, 'commit': 'current', 'result': 'passed',
            'generatedBy': 'fixture-runner', 'executedAt': '2026-09-21T12:00:00Z',
        }
        payload.update(overrides)
        path = root / name
        path.write_text(json.dumps(payload))
        return {'kind': kind, 'path': name,
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

    def row(self, evidence, **overrides):
        row = {'requirementID': 'R01', 'commit': 'current', 'result': 'passed',
               'evidence': [evidence]}
        row.update(overrides)
        return row

    def test_missing_stale_failed_duplicate_or_legacy_evidence_is_rejected(self):
        with tempfile.TemporaryDirectory() as value:
            root = pathlib.Path(value)
            artifact = self.artifact(root)
            valid = self.row(artifact)
            cases = [[], [dict(valid, commit='old')], [dict(valid, result='notRun')],
                     [valid, valid], [{'requirementID': 'R01', 'commit': 'current',
                                      'result': 'passed', 'evidencePaths': ['proof.json']}]]
            for rows in cases:
                with self.subTest(rows=rows):
                    self.assertTrue(qualification.validate(rows, {'R01'}, 'current', root))

    def test_wrong_kind_checksum_or_artifact_commit_is_rejected(self):
        with tempfile.TemporaryDirectory() as value:
            root = pathlib.Path(value)
            artifact = self.artifact(root)
            cases = [dict(artifact, kind='manual-signoff'), dict(artifact, sha256='0' * 64),
                     self.artifact(root, commit='old')]
            for evidence in cases:
                with self.subTest(evidence=evidence):
                    self.assertTrue(
                        qualification.validate([self.row(evidence)], {'R01'}, 'current', root))

    def test_structured_current_checksummed_evidence_passes(self):
        with tempfile.TemporaryDirectory() as value:
            root = pathlib.Path(value)
            artifact = self.artifact(root)
            self.assertEqual(
                qualification.validate([self.row(artifact)], {'R01'}, 'current', root), [])

    def test_device_and_media_reports_require_real_signoff_metadata(self):
        with tempfile.TemporaryDirectory() as value:
            root = pathlib.Path(value)
            camera = self.artifact(root, kind='camera-report')
            self.assertTrue(qualification.validate_artifact(
                camera, 'R02', 'current', root, {'camera-report'}))
            camera = self.artifact(
                root, kind='camera-report',
                device={'physical': True, 'model': 'iPhone 16 Pro',
                        'osVersion': '18.5', 'build': '22F76'})
            self.assertFalse(qualification.validate_artifact(
                camera, 'R02', 'current', root, {'camera-report'}))
            media = self.artifact(root, kind='media-report')
            self.assertTrue(qualification.validate_artifact(
                media, 'R17', 'current', root, {'media-report'}))

    def test_recognized_supplemental_evidence_does_not_invalidate_required_kind(self):
        with tempfile.TemporaryDirectory() as value:
            root = pathlib.Path(value)
            required = self.artifact(root, name='summary.json')
            supplemental = self.artifact(root, kind='privacy-report', name='privacy.json')
            row = self.row(required)
            row['evidence'].append(supplemental)
            self.assertEqual(
                qualification.validate([row], {'R01'}, 'current', root), [])

    def test_ledger_may_be_committed_after_the_source_it_qualifies(self):
        rows = [{'requirementID': 'R01', 'commit': 'source'}]
        evidence_only = lambda commit: ['docs/evidence/release.json', 'docs/evidence/r01.json']
        self.assertEqual(
            qualification.candidate_commit(rows, 'head', evidence_only), ('source', []))
        self.assertEqual(
            qualification.candidate_commit(
                [{'requirementID': 'R01', 'commit': 'head'}], 'head', lambda commit: None),
            ('head', []))

    def test_source_changes_or_unrelated_history_after_the_candidate_are_rejected(self):
        rows = [{'requirementID': 'R01', 'commit': 'source'}]
        cases = [
            lambda commit: ['docs/evidence/release.json', 'cubeguide/ContentView.swift'],
            lambda commit: None,
        ]
        for changed in cases:
            with self.subTest(changed=changed):
                commit, errors = qualification.candidate_commit(rows, 'head', changed)
                self.assertIsNone(commit)
                self.assertTrue(errors)
        mixed = [{'requirementID': 'R01', 'commit': 'a'}, {'requirementID': 'R02', 'commit': 'b'}]
        self.assertTrue(qualification.candidate_commit(mixed, 'head', lambda commit: [])[1])

    def test_archive_step_requires_every_release_row_except_the_archive_evidence(self):
        required = qualification.required_requirements('release-pre-archive')
        self.assertEqual(required, {f'R{i:02}' for i in range(1, 19)})
        self.assertEqual(
            qualification.required_requirements('release'), {f'R{i:02}' for i in range(1, 21)})


if __name__ == '__main__':
    unittest.main()
