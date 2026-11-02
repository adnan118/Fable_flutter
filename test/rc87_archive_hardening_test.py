#!/usr/bin/env python3
"""RC87: test archive integrity and clean Git provenance without private code."""
import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools' / 'build-rc86-source-archive.py'
spec = importlib.util.spec_from_file_location('rc87_archiver', SCRIPT)
archiver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archiver)

def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.PIPE).decode().strip()

def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')

def init(root):
    git(root, 'init', '-q')
    git(root, 'config', 'user.name', 'RC87 tests')
    git(root, 'config', 'user.email', 'rc87@example.invalid')

def commit(root):
    git(root, 'add', '.')
    git(root, 'commit', '-qm', 'source baseline')
    return git(root, 'rev-parse', 'HEAD')

class ArchiveHardeningTests(unittest.TestCase):
    def test_sensitive_path_policy(self):
        for name in ('.env', '.env.production', '.envrc', '.git-credentials',
                     'google-services.json', 'GoogleService-Info.plist',
                     'keys/release.jks', 'src/node_modules/token.js',
                     'secrets/private.pem', 'id_ed25519'):
            self.assertTrue(archiver.blocked(name), name)
        for name in ('src/app.dart', '.env.example', 'lib/config.dart',
                     'docs/RC86-SOURCE-PAIR.json'):
            self.assertFalse(archiver.blocked(name), name)

    def test_source_must_match_git_commit(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            init(root)
            write(root/'hello.txt', 'expected')
            commit(root)
            archiver.require_git_clean(root)
            write(root/'hello.txt', 'modified after commit')
            with self.assertRaisesRegex(ValueError, 'working tree differs'):
                archiver.require_git_clean(root)

    def test_sha256_check_detects_altered_source_and_checksums(self):
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / 'test.zip'
            source = b'original source'
            checksum = hashlib.sha256(source).hexdigest()
            records = [(checksum, 'Fable-Backend/hello.txt')]
            with zipfile.ZipFile(path, 'w') as out:
                archiver.plain(out, records[0][1], source)
                archiver.plain(out, 'SOURCE-PAIR/SHA256SUMS.txt',
                               (checksum + '  Fable-Backend/hello.txt\n').encode())
            with zipfile.ZipFile(path) as zipped:
                archiver.verify_sums(zipped, records)
                with self.assertRaisesRegex(ValueError, 'source file SHA256'):
                    archiver.verify_sums(zipped, [('0'*64, records[0][1])])
            with zipfile.ZipFile(path, 'w') as out:
                archiver.plain(out, records[0][1], source)
                archiver.plain(out, 'SOURCE-PAIR/SHA256SUMS.txt', b'forged sum\n')
            with zipfile.ZipFile(path) as zipped:
                with self.assertRaisesRegex(ValueError, 'SHA256SUMS mismatch'):
                    archiver.verify_sums(zipped, records)

    def test_end_to_end_private_archive_contains_both_commits_but_no_keys(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            back, front = root/'backend', root/'frontend'
            back.mkdir()
            front.mkdir()
            init(back)
            init(front)
            blueprint = 'Fable-Backend-RC66/blueprints/capabilities/auth/manifest.json'
            write(back/blueprint, '{"name":"auth","version":"4.6.0","routes":[]}\n')
            for i in range(5):
                write(back/f'docs/sample-{i}.txt', 'private source '+str(i))
                write(front/f'lib/sample-{i}.dart', '// public source '+str(i))
            write(back/'.env.production', 'SECRET=do-not-archive\n')
            write(front/'google-services.json', '{"secret":"do-not-archive"}\n')
            write(front/'docs/integrations/FABLE-CROSS-REPO-SOURCE-PAIR-RC86.json',
                  json.dumps({'backend':{'authBlueprint':blueprint,
                    'authBlueprintBlobSha':'1'*40}},indent=2)+'\n')
            back_sha = commit(back)
            front_sha = commit(front)
            inventory = [{'name':f'cap-{i}','manifestPresent':True,
                          'liveE2EVerified':False} for i in range(50)]
            audit = {'kind':'fable.cross-repo-source-pair-audit',
                     'sourceOnly':False,'authSourceBlobVerified':True,
                     'backendSourceUnchangedSinceAudit':True,
                     'backendCapabilityCount':50,
                     'backendCapabilityInventory':inventory,
                     'backendRouteCount':40, 'sourceReviewed':9,
                     'notDecided':31, 'liveE2EAccepted':0,
                     'backendGitHead':back_sha, 'frontendGitHead':front_sha}
            report_path = root/'audit.json'
            write(report_path, json.dumps(audit))
            output = root/'full.zip'
            result = subprocess.run([sys.executable,str(SCRIPT),'--backend',str(back),
               '--frontend',str(front),'--audit',str(report_path),'--out',str(output)],
                text=True,capture_output=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertTrue(output.is_file())
            self.assertTrue(output.with_suffix('.zip.sha256').is_file())
            with zipfile.ZipFile(output) as zipped:
                self.assertIsNone(zipped.testzip())
                manifest=json.loads(zipped.read('SOURCE-PAIR/PAIR-MANIFEST.json'))
                self.assertEqual(manifest['sourceSha']['Fable-Backend'], back_sha)
                self.assertEqual(manifest['sourceSha']['Fable-Flutter'], front_sha)
                self.assertEqual(manifest['backendCapabilityBlueprints'],50)
                self.assertEqual(manifest['liveE2EAccepted'],0)
                self.assertNotIn('Fable-Backend/.env.production',zipped.namelist())
                self.assertNotIn('Fable-Flutter/google-services.json',zipped.namelist())
                self.assertIn('Fable-Backend/docs/sample-0.txt',zipped.namelist())
                self.assertIn('Fable-Flutter/lib/sample-0.dart',zipped.namelist())
                self.assertIn('Fable-Backend/.env.production',
                              manifest['omittedTrackedPaths'])
                self.assertIn('Fable-Flutter/google-services.json',
                              manifest['omittedTrackedPaths'])

if __name__ == '__main__':
    unittest.main()
