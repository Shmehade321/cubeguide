import unittest
import compare

SOLVED='UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB'
R='UUFUUFUUFRRRRRRRRRFFDFFDFFDDDBDDBDDBLLLLLLLLLUBBUBBUBB'

class ReferenceTests(unittest.TestCase):
    def test_real_sequence_and_empty_solved(self):
        report=compare.compare([{'state':SOLVED,'expectedValid':True},{'state':R,'expectedValid':True}], [SOLVED+'\t\n',R+"\tR'\n"])
        self.assertEqual(report['result'],'passed')
        self.assertEqual(report['count'],2)

    def test_missing_wrong_mismatched_or_reference_limit_results_fail(self):
        for rows in [[],[SOLVED+'\tR\n'],['U\t\n'],[SOLVED+'\tError 8\n'],[SOLVED+'\tError 7\n'],[SOLVED+'\tError 1\n'],[SOLVED+'\t'+'U '*32+'\n']]:
            with self.subTest(rows=rows):
                self.assertEqual(compare.compare([{'state':SOLVED,'expectedValid':True}],rows)['result'],'failed')

    def test_invalidity_requires_actual_validation_error(self):
        for error in ['Error 1','Error 2','Error 3','Error 4','Error 5','Error 6']:
            self.assertEqual(compare.compare([{'state':'bad','expectedValid':False}],['bad\t'+error+'\n'])['result'],'passed')
        for result in ['Error 7','Error 8','',"R'"]:
            with self.subTest(result=result):
                self.assertEqual(compare.compare([{'state':'bad','expectedValid':False}],['bad\t'+result+'\n'])['result'],'failed')
