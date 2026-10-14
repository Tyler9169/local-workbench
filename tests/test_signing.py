import importlib.util
from pathlib import Path
import json, plistlib, tempfile, unittest
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('sign_app',Path(__file__).resolve().parents[1]/'tools/shared/sign-app.py')
signing=importlib.util.module_from_spec(spec);spec.loader.exec_module(signing)
class SigningTests(unittest.TestCase):
    def test_missing_or_wrong_identity_cannot_fall_back(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); app=root/'Test.app';(app/'Contents').mkdir(parents=True)
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.tyler.framerecorder'}))
            with patch.object(signing.Path,'home',return_value=root), patch.object(signing,'run') as run:
                with self.assertRaises(RuntimeError):signing.sign(app)
                config=root/'Library/Application Support/LocalWorkbenchSigning/signing.json';config.parent.mkdir(parents=True)
                config.write_text(json.dumps({'apps':{'local.tyler.framerecorder':{'certificateSHA1':'wrong'}}}))
                with self.assertRaises(RuntimeError):signing.sign(app)
                run.assert_not_called()
