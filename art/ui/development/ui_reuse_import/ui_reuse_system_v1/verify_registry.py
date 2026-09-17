"""Run from any cwd. Validates shipped resources/contracts; does not run the game."""
from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parent
registry=json.loads((root/'specs/resource_registry.json').read_text(encoding='utf-8'))
assets=registry['assets']
for aid,a in assets.items():
 p=(root/a['file']).resolve()
 assert p.is_relative_to(root),f'Unexpected path: {aid}'
 assert p.is_file(),f'Missing: {aid}'
 assert hashlib.sha256(p.read_bytes()).hexdigest()==a['source_sha256'],f'Changed bytes: {aid}'
aliases=json.loads((root/'specs/legacy_aliases.json').read_text(encoding='utf-8'))
for old,a in aliases.items():assert a['target'] in assets,f'Unknown target: {old}'
components=json.loads((root/'specs/component_contracts.json').read_text(encoding='utf-8'))
for name,c in components.items():
 for aid in c.get('asset_ids',[]):assert aid in assets,(name,aid)
 for aid in c.get('pending_asset_ids',[]):assert aid in registry['pending_assets'],(name,aid)
 if 'extends' in c:assert c['extends'] in components,name
pages=json.loads((root/'specs/page_compositions.json').read_text(encoding='utf-8'))
for name,p in pages.items():
 assert p['shell'] in components,name
 for c in p['components']:assert c in components,(name,c)
 if p.get('sceneId'):assert p['sceneId'] in assets,name
print(f'PASS: {len(assets)} resource IDs, {len(aliases)} aliases, {len(components)} components, {len(pages)} page configurations.')
print('Pending clean assets and engine runtime verification remain explicit in the documentation.')
