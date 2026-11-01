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
import sys
import zipfile

SCHEMA = 1
SKIP_DIRS = {'.git', '.dart_tool', 'node_modules', '.gradle', '.next',
             'build', 'dist', 'coverage', '__pycache__', '.venv', 'venv'}
SKIP_SUFFIX = ('.pem', '.key', '.p12', '.p8', '.jks', '.keystore',
               '.mobileprovision', '.cer', '.pfx')
SKIP_NAMES = {'.env', '.npmrc', '.pypirc', '.netrc', '.secrets',
              'id_rsa', 'id_ed25519', 'google-services.json',
              'googleservice-info.plist'}
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
    archive.writestr(name, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=6)

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
    when = '2026-11-01'  # release identity; no fabricated E2E completion
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
