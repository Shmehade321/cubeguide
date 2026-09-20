import unittest
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import analyze

SOLVED='UUUUUUUUURRRRRRRRRFFFFFFFFFDDDDDDDDDLLLLLLLLLBBBBBBBBB'

def case(i): return {'id':str(i),'state':SOLVED,'expectedValid':True}
def result(i,seconds=1): return {'id':str(i),'state':SOLVED,'outcome':'verified','solution':[],'elapsedSeconds':seconds,'visitedNodes':0,'resourceVersion':'v'}

class AnalysisTests(unittest.TestCase):
    def test_complete_results_and_outliers(self):
        report=analyze.analyze([case(i) for i in range(4)],[result(i,t) for i,t in enumerate([1,2,3,100])],'v',4)
        self.assertEqual(report['result'],'passed')
        self.assertEqual(report['count'],4)
        self.assertEqual(report['p95Seconds'],100)
        self.assertEqual(report['maximumSeconds'],100)

    def test_omitted_mismatched_or_wrong_solutions_fail(self):
        for rows in [[],[dict(result(0),id='different')],[dict(result(0),state='U')],[dict(result(0),solution=['R'])],[dict(result(0),solution=['U']*32)],[dict(result(0),solution=['u'])],[dict(result(0),resourceVersion='other')]]:
            with self.subTest(rows=rows):
                self.assertEqual(analyze.analyze([case(0)],rows,'v',1)['result'],'failed')

    def test_timeout_retained_and_not_called_invalidity(self):
        timed=dict(result(0,60),outcome='timedOut',solution=None)
        report=analyze.analyze([case(0)],[timed],'v',1)
        self.assertEqual(report['result'],'failed')
        self.assertEqual(report['timeouts'],1)
        self.assertEqual(report['maximumSeconds'],60)

    def test_invalid_measurements_fail(self):
        for value in [-1,float('nan'),float('inf')]:
            self.assertEqual(analyze.analyze([case(0)],[result(0,value)],'v',1)['result'],'failed')

    def test_cli_checks_manifest_and_expected_count(self):
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory)
            corpus=root/'corpus.jsonl';results=root/'results.jsonl';report=root/'report.json'
            resources=root/'tables.json';resources.write_text('{}')
            version=hashlib.sha256(resources.read_bytes()).hexdigest()
            corpus.write_text(json.dumps(case(0))+'\n')
            results.write_text(json.dumps(dict(result(0),resourceVersion=version))+'\n')
            manifest=corpus.with_suffix('.manifest.json')
            valid={'count':1,'sha256':hashlib.sha256(corpus.read_bytes()).hexdigest()}
            command=[sys.executable,str(pathlib.Path(analyze.__file__)),str(corpus),str(results),str(report),'--count','1','--resources',str(resources)]
            for metadata,expected in [(valid,0),(dict(valid,sha256='wrong'),1),(dict(valid,count=2),1)]:
                manifest.write_text(json.dumps(metadata))
                run=subprocess.run(command,capture_output=True,text=True)
                self.assertTrue(report.exists(),run.stderr)
                self.assertEqual(run.returncode,expected,run.stderr)
                self.assertEqual(json.loads(report.read_text())['result'],'passed' if expected==0 else 'failed')
                report.unlink()

    def test_duplicate_ids_fail(self):
        self.assertEqual(analyze.analyze([case(0),case(0)],[result(0),result(0)],'v',2)['result'],'failed')

    def test_invalid_node_measurements_fail(self):
        for nodes in [-1,None,1.5,True]:
            self.assertEqual(analyze.analyze([case(0)],[dict(result(0),visitedNodes=nodes)],'v',1)['result'],'failed')
