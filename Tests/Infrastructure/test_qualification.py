import importlib.util
import pathlib
import tempfile
import unittest
spec=importlib.util.spec_from_file_location('qualification', pathlib.Path(__file__).resolve().parents[2]/'Scripts/check-qualification.py')
qualification=importlib.util.module_from_spec(spec)
spec.loader.exec_module(qualification)

class QualificationTests(unittest.TestCase):
    def test_missing_stale_failed_or_unbacked_evidence(self):
        with tempfile.TemporaryDirectory() as root:
            root=pathlib.Path(root)
            row={'requirementID':'R01','commit':'current','result':'passed','evidencePaths':['proof.txt']}
            for rows in [[],[row],[dict(row,commit='old')],[dict(row,result='notRun')],[row,row]]:
                with self.subTest(rows=rows):
                    self.assertTrue(qualification.validate(rows,{'R01'},'current',root))

    def test_backed_current_evidence(self):
        with tempfile.TemporaryDirectory() as root:
            root=pathlib.Path(root)
            (root/'proof.txt').write_text('Test result fixture')
            row={'requirementID':'R01','commit':'current','result':'passed','evidencePaths':['proof.txt']}
            self.assertEqual(qualification.validate([row],{'R01'},'current',root),[])
