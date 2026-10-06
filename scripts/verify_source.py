"""Validate syntax, cycle evidence and reproducible source hashes."""
import argparse, ast, hashlib, json, subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--manifest', action='store_true')
args = parser.parse_args()
files = subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
records = json.loads((root/'docs/improvement-cycles.json').read_text(encoding='utf-8'))
if [r['round'] for r in records] != list(range(1,21)) or any(r['failed'] or not r['passed'] for r in records):
    raise ValueError('All 20 improvement cycles must have passing evidence')
manifest = []
for name in filter(None,files):
    if name == 'SOURCE_MANIFEST.json':
        continue
    path = root/name
    data = subprocess.check_output(['git','show','HEAD:'+name],cwd=root)
    if path.suffix == '.py':
        ast.parse(data,filename=name)
    elif path.suffix in ['.js','.cjs']:
        subprocess.run(['node','--check',str(path)],check=True,capture_output=True)
    manifest.append({'path':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
if args.manifest:
    (root/'SOURCE_MANIFEST.json').write_text(json.dumps({'version':'2.2','cycle_count':20,'files':manifest},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if not args.manifest:
    recorded=json.loads((root/'SOURCE_MANIFEST.json').read_text(encoding='utf-8'))
    if recorded['files']!=manifest:
        raise ValueError('Committed sources differ from frozen source hashes')
print(f'Syntax and 20-cycle evidence verified: {len(manifest)} tracked files')
