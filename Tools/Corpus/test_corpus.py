import collections
import unittest
import generate

class CorpusTests(unittest.TestCase):
    def test_strata_uniqueness_and_reproducibility(self):
        first=list(generate.records(80,12345))
        second=list(generate.records(80,12345))
        self.assertEqual(first,second)
        self.assertEqual(len(first),80)
        self.assertEqual(len({row['state'] for row in first}),80)
        self.assertEqual(collections.Counter(row['source'] for row in first), {'direct':40,'moves20':10,'moves40':10,'moves80':10,'moves200':10})
        for row in first:
            self.assertEqual(collections.Counter(row['state']),dict.fromkeys('URFDLB',9))
            self.assertEqual(''.join(row['state'][i] for i in [4,13,22,31,40,49]),'URFDLB')
            if row['source'].startswith('moves'):
                self.assertEqual(len(row['scramble'].split()),int(row['source'][5:]))
        self.assertNotEqual(first,list(generate.records(80,12346)))

    def test_invalid_budgets(self):
        for count in [-8,0,1,9,1000008]:
            with self.assertRaises(ValueError):
                list(generate.records(count,0))

    def test_shallow_counts(self):
        states,counts=generate.shallow()
        self.assertEqual(counts,[1,18,243,3240,43239])
        self.assertEqual(len(states),46741)
        self.assertEqual(len(set(states)),46741)

if __name__ == '__main__':
    unittest.main()
