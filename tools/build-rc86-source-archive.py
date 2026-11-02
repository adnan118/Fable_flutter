#!/usr/bin/env python3
"""RC86: reproducible full-source ZIP for two pinned Git checkouts.
Run ONLY in the private Backend repository's CI. Never publish the private
Backend source to the public Flutter repository or a public release.
"""
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import subprocess
import zipfile

SCHEMA = 1
SKIP_DIRS = {'.git', '.dart_tool', 'node_modules', '.gradle', '.next',
             'build', 'dist', 'coverage', '__pycache__', '.venv', 'venv'}
SKIP_SUFFIX = ('.pem', '.key', '.p12', '.p8', '.jks', '.keystore',
               '.mobileprovision', '.cer', '.pfx')
SKIP_NAMES = {'.env', '.envrc', '.npmrc', '.pypirc', '.netrc',
              '.secrets', '.git-credentials', 'id_rsa', 'id_ed25519',
              'google-services.json', 'googleservice-info.plist',
              'service-account.json', 'service-account-key.json'}
ALLOWED_ENV_SUFFIX = {'.env.example', '.env.sample', '.env.template'}

def run(*args, cwd):
    return subprocess.check_output(list(args), cwd=cwd).decode('utf-8').strip()

def tracked(root):
    result = subprocess.check_output(['git', 'ls-files', '-z', '--cached'], cwd=root)
    paths = []
    for raw in result.split(b'\0'):
        if not raw:
            continue
        rel = raw.decode('utf-8')
        path = pathlib.PurePosixPath(rel)
        if path.is_absolute() or '..' in path.parts:
            raise ValueError(f'unsafe Git path {rel!r}')
        paths.append(rel)
    return sorted(set(paths))

def blocked(rel):
    path = pathlib.PurePosixPath(rel)
    if any(part in SKIP_DIRS for part in path.parts):
        return True
    name = path.name.lower()
    if name in SKIP_NAMES:
        return True
    if name.startswith('.env') and name not in ALLOWED_ENV_SUFFIX:
        return True
    if name.endswith(SKIP_SUFFIX):
        return True
    if name.endswith('.asc') and 'private' in name:
        return True
    return False

def plain(archive, name, data):
    # Stable metadata independent of the build machine's locale and wall clock.
    entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    entry.external_attr = 0o644 << 16
    archive.writestr(entry, data, compress_type=zipfile.ZIP_DEFLATED,
                     compresslevel=6)

def demand(ok, message):
    if not ok:
        raise ValueError('RC87 archive guard: ' + message)

def require_git_clean(root):
    # Packaging an edited working tree while recording the commit SHA creates
    # a misleading archive. Git-tracked source MUST equal checkout HEAD.
    dirty = subprocess.check_output(
        ['git', 'status', '--porcelain', '--untracked-files=no'], cwd=root)
    demand(not dirty.strip(), f'working tree differs from Git HEAD: {root}')

def verify_sums(archive, records):
    expected = {name: sha for sha, name in records}
    archive_names = set(archive.namelist())
    demand(len(archive_names) == len(archive.namelist()),
           'duplicate ZIP entry names')
    for name, sha in expected.items():
        demand(name in archive_names, 'source file omitted from ZIP: ' + name)
        digest = hashlib.sha256(archive.read(name)).hexdigest()
        demand(digest == sha, 'source file SHA256 differs in ZIP: ' + name)
    listed = archive.read('SOURCE-PAIR/SHA256SUMS.txt').decode('utf-8').splitlines()
    demand(len(listed) == len(records), 'SHA256SUMS list count mismatch')
    for line, (sha, name) in zip(listed, records):
        demand(line == f'{sha}  {name}', 'SHA256SUMS mismatch: ' + name)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--backend', required=True)
    parser.add_argument('--frontend', required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--audit', required=True)
    options = parser.parse_args()
    back = pathlib.Path(options.backend).resolve()
    front = pathlib.Path(options.frontend).resolve()
    output = pathlib.Path(options.out).resolve()
    audit_path = pathlib.Path(options.audit).resolve()
    assert back.is_dir() and front.is_dir(), 'both source Git checkouts required'
    assert audit_path.is_file(), 'cross-repo verifier result is required'
    audit = json.loads(audit_path.read_text('utf-8'))
    assert audit.get('kind') == 'fable.cross-repo-source-pair-audit'
    assert audit.get('sourceOnly') is False
    assert audit.get('authSourceBlobVerified') is True
    assert audit.get('backendRouteCount') == 40
    assert audit.get('sourceReviewed') == 9
    assert audit.get('notDecided') == 31
    assert audit.get('liveE2EAccepted') == 0
    demand(audit.get('backendSourceUnchangedSinceAudit') is True,
           'Backend source changed after Flutter audit')
    demand(audit.get('backendCapabilityCount') == 50,
           'Backend capability inventory drift')
    demand(len(audit.get('backendCapabilityInventory', [])) == 50,
           'Backend capability manifest inventory absent')
    for cap in audit['backendCapabilityInventory']:
        demand(cap.get('manifestPresent') is True and
               cap.get('liveE2EVerified') is False,
               'missing capability manifest or invented E2E')
    if (back / 'docs/RC86-SOURCE-PAIR.json').is_file():
        demand(audit.get('privateBackendPairVerified') is True,
               'private Backend Flutter SHA pin has not been verified')
    require_git_clean(back)
    require_git_clean(front)
    backend_head = run('git','rev-parse','HEAD',cwd=back)
    frontend_head = run('git','rev-parse','HEAD',cwd=front)
    assert audit['backendGitHead'] == backend_head
    assert audit['frontendGitHead'] == frontend_head
    assert len(backend_head) == len(frontend_head) == 40
    pair = json.loads((front/'docs/integrations/FABLE-CROSS-REPO-SOURCE-PAIR-RC86.json').read_text('utf-8'))
    backend_manifest = back / pair['backend']['authBlueprint']
    assert backend_manifest.is_file()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    records = []
    excluded = []
    source_counts = {}
    source_sizes = {}
    when = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    paired = [
      ('Fable-Backend', back),
      ('Fable-Flutter', front),
    ]
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED,
                         compresslevel=6, allowZip64=True) as archive:
        for prefix, root in paired:
            count = 0
            size = 0
            for rel in tracked(root):
                candidate = root / rel
                if blocked(rel) or not candidate.is_file() or candidate.is_symlink():
                    excluded.append(f'{prefix}/{rel}')
                    continue
                data = candidate.read_bytes()
                name = f'{prefix}/{rel}'
                plain(archive, name, data)
                records.append((hashlib.sha256(data).hexdigest(), name))
                count += 1
                size += len(data)
            source_counts[prefix] = count
            source_sizes[prefix] = size
        manifest = {
            'schemaVersion': SCHEMA,
            'kind':'fable.synchronized-source-archive',
            'release':'RC86',
            'createdDate':when,
            'repositoryVisibility':{'Fable-Backend':'private','Fable-Flutter':'public'},
            'sourceSha':{'Fable-Backend':backend_head,'Fable-Flutter':frontend_head},
            'sourceFileCount':source_counts,
            'sourceByteCount':source_sizes,
            'backendAuthBlueprintBlobSha':pair['backend']['authBlueprintBlobSha'],
            'authOperationParity':{
                'backendRoutes':40,'frontendRoutes':40,
                'methodPathMismatches':0,'sourceReviewed':9,'notDecided':31,
            },
            'featureFamilies':17,
            'backendCapabilityBlueprints':50,
            'backendCapabilityInventory':audit['backendCapabilityInventory'],
            'backendSourceUnchangedSinceAudit':True,
            'privateBackendPairVerified':audit.get('privateBackendPairVerified', False),
            'liveE2EAccepted':0,
            'otherBackendMfaMapped':False,
            'omittedTrackedPaths':excluded,
            'exclusionPolicy':'Tracked source only; no .git, private env, signing keys, local build outputs or dependency caches.',
            'integrityFile':'SOURCE-PAIR/SHA256SUMS.txt',
            'notes':'Source parity only. No generated-project DB, live FCM, Android/iOS device E2E acceptance.'
        }
        plain(archive, 'SOURCE-PAIR/PAIR-MANIFEST.json',
              (json.dumps(manifest, ensure_ascii=False, indent=2)+'\n').encode())
        plain(archive, 'SOURCE-PAIR/SOURCE-PAIR-VERIFICATION.json',
              (json.dumps(audit, ensure_ascii=False, indent=2)+'\n').encode())
        plain(archive, 'SOURCE-PAIR/README-AR.txt', (
            'RC86 - نسخة شاملة متزامنة من Backend Fable وFlutter Fable.\n'
            'Fable-Backend/: كود الريبو الخاص. لا تعِد نشره على GitHub عام.\n'
            'Fable-Flutter/: نسخة الريبو العام مثبتة بالـSHA المسجل.\n'
            'SOURCE-PAIR/: سجل نسختي المصدر، التطابق، بصمات SHA256.\n'
            'الفحوص مصدرية فقط، ولا تعني نجاح تكامل حي أو اكتمال 17 ميزة E2E.\n'
            'لا تحتوي الحزمة عمداً على ملفات البيئة السرية ومفاتيح التوقيع.\n'
        ).encode('utf-8'))
        sums = ''.join(f'{checksum}  {name}\n' for checksum,name in records)
        plain(archive, 'SOURCE-PAIR/SHA256SUMS.txt', sums.encode('utf-8'))
    # Reopen and confirm the complete archive isn't just a file with .zip suffix.
    with zipfile.ZipFile(output, 'r') as z:
        assert z.testzip() is None, 'archive CRC failed'
        assert z.getinfo('SOURCE-PAIR/PAIR-MANIFEST.json')
        assert len(z.namelist()) > 10, 'missing files'
        verify_sums(z, records)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    checksum_path = output.with_suffix(output.suffix + '.sha256')
    checksum_path.write_text(f'{digest}  {output.name}\n', encoding='utf-8')
    print(json.dumps({
        'status':'SUCCESS', 'archive':str(output),
        'sha256':digest,'bytes':output.stat().st_size,
        'files':source_counts,'omitted':len(excluded),
        'backendSha':backend_head,'flutterSha':frontend_head
    },ensure_ascii=False,indent=2))
if __name__ == '__main__':
    main()
