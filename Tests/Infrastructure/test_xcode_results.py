import importlib.util
import pathlib
import unittest
spec = importlib.util.spec_from_file_location('results', pathlib.Path(__file__).resolve().parents[2] / 'Scripts/check-xcode-results.py')
results = importlib.util.module_from_spec(spec)
spec.loader.exec_module(results)

class ResultTests(unittest.TestCase):
    def summary(self, **changes):
        return dict({'result':'Passed','totalTestCount':3,'passedTests':3,'failedTests':0,'skippedTests':0,'testFailures':[], 'expectedFailures':0}, **changes)

    def test_success(self):
        self.assertTrue(results.passed(self.summary()))

    def test_incomplete_or_bad_summary_rejected(self):
        cases = [{}, self.summary(result='Failed'), self.summary(expectedFailures=1), self.summary(totalTestCount=0,passedTests=0), self.summary(skippedTests=1), self.summary(failedTests=1), self.summary(testFailures=[{'message':'crash'}]), self.summary(passedTests=2)]
        for summary in cases:
            with self.subTest(summary=summary):
                self.assertFalse(results.passed(summary))
