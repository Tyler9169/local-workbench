#!/usr/bin/env python3
"""Sign using an explicit identity or this machine's pinned local identity.

Private keys remain outside the repository. Once configured, missing or mismatched
local identity is a hard failure, never an implicit fallback to ad-hoc signing.
"""
import json
import os
from pathlib import Path
import plistlib
import shlex
import subprocess
import sys


def run(*args, capture=False):
    return subprocess.run(args, check=True, text=True, capture_output=capture)


def sign(app):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    bundle = info['CFBundleIdentifier']
    config = Path.home() / 'Library/Application Support/LocalWorkbenchSigning/signing.json'
    settings = json.loads(config.read_text()) if config.exists() else {}
    pinned = settings.get('apps', {}).get(bundle)
    explicit = os.environ.get('CODE_SIGN_IDENTITY')
    if bundle == 'local.tyler.framerecorder':
        expected = '6EAFE237D7C3691674166F8D8446ADF51F6CDE9A'
        if not pinned or pinned.get('certificateSHA1', '').upper() != expected:
            raise RuntimeError('Frame Recorder release requires its pinned signing identity; refusing ad-hoc or another certificate.')
    if pinned and explicit and explicit != pinned['certificateSHA1']:
        raise RuntimeError('Pinned identity exists; refusing to replace it with a different signer.')
    if pinned:
        keychain = Path(settings['keychain'])
        if not keychain.is_file():
            raise RuntimeError('Configured signing keychain is missing; ad-hoc fallback refused.')
        password_file = settings.get('passwordFile')
        if password_file:
            secret_path = Path(password_file)
            if secret_path.stat().st_mode & 0o077:
                raise RuntimeError('Signing password file must be private (0600).')
            unlocked = subprocess.run(['security', 'unlock-keychain', '-p', secret_path.read_text().strip(), str(keychain)], capture_output=True)
            if unlocked.returncode:
                raise RuntimeError('Could not unlock the configured signing keychain.')
        original = shlex.split(run('security', 'list-keychains', '-d', 'user', capture=True).stdout)
        try:
            run('security', 'list-keychains', '-d', 'user', '-s', *original, str(keychain))
            run('codesign', '--force', '--keychain', str(keychain), '--sign', pinned['certificateSHA1'], str(app))
        finally:
            run('security', 'list-keychains', '-d', 'user', '-s', *original)
        requirement = 'identifier "{}" and certificate leaf = H"{}"'.format(bundle, pinned['certificateSHA1'])
        run('codesign', '--verify', '--deep', '--strict', '-R=' + requirement, str(app))
    else:
        run('codesign', '--force', '--sign', explicit or '-', str(app))
        run('codesign', '--verify', '--deep', '--strict', str(app))
    print('Signed: ' + bundle + (' (pinned local identity)' if pinned else ''))


if __name__ == '__main__':
    sign(Path(sys.argv[1]).resolve())
