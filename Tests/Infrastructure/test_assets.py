"""V14/V17: absent, empty or escaping production assets cannot pass release lint."""
import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('assets', ROOT / 'Scripts/validate-assets.py')
assets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assets)

class AssetTests(unittest.TestCase):
    def test_missing_inventory(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertTrue(assets.validate({'assets': []}, pathlib.Path(root), {'N01'}))

    def test_missing_empty_and_outside_files(self):
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            (root / 'empty.m4a').touch()
            for path in ['missing.m4a', 'empty.m4a', '../outside.m4a']:
                with self.subTest(path=path):
                    self.assertTrue(assets.validate({'assets': [{'id':'N01', 'path':path, 'source':'rights.md'}]}, root, {'N01'}))

    def test_complete_nonempty_inventory(self):
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            (root / 'tone.m4a').write_bytes(b'fixture bytes; codec checking is a separate media gate')
            (root / 'rights.md').write_text('Fixture rights record')
            self.assertEqual(assets.validate({'assets':[{'id':'E01','path':'tone.m4a','source':'rights.md'}]},root,{'E01'}), [])

    def test_duplicate_id_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            self.assertTrue(assets.validate({'assets':[{'id':'N01'},{'id':'N01'}]}, pathlib.Path(root), {'N01'}))
