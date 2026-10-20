"""Switch the local archive UI study: 0 restores the pre-study appearance; 1..36 select a recorded version."""
import argparse,ctypes,datetime,json,re,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
RECORDS=ROOT/'output/popup_iterations_20261009'
CONTENT=ROOT.parents[2]/'content/dota_addons/survival'
RC=ROOT.parents[1]/'bin/win64/resourcecompiler.exe'
p=argparse.ArgumentParser(description=__doc__);p.add_argument('version',type=int,choices=range(37));a=p.parse_args()
assert (RECORDS/'original_ui.zip').is_file(), 'Original backup is missing'
# Validate the requested record before resetting live UI or touching source files.
if a.version:
 for extension in ('js','css'):
  candidate=RECORDS/f'v{a.version}.{extension}';assert candidate.is_file(),candidate

console=ROOT/'tools/map_c6/console.cjs'
node=Path('C:/Users/Administrator/AppData/Local/Programs/nodejs/node-v24.21.0-win-x64/node.exe')
engine_log=ROOT.parents[1]/'dota/console.log'
if node.is_file() and engine_log.is_file() and ctypes.windll.user32.FindWindowW(None,"Dota 2"):
 log=engine_log.read_text(encoding='utf-8',errors='replace')
 study=list(re.finditer(r'POPUP_STUDY_READY v[0-9]+ (popup_study_[0-9]+)',log))
 original=list(re.finditer(r'ARCHIVE_DIAGNOSTIC archive_view_dump_([0-9]+)',log))
 if study and original and study[-1].start()>original[-1].start():
  reset=subprocess.run([str(node),str(console),study[-1].group(1)+' reset','650'],cwd=ROOT,capture_output=True,timeout=15)
  reset_output=reset.stdout.decode('utf-8',errors='replace');print('\n'.join(line for line in reset_output.splitlines() if 'POPUP_STUDY_RESET_OK' in line))
  assert 'POPUP_STUDY_RESET_OK' in reset_output, 'UI cleanup was not confirmed; no files changed. Focus Dota and retry.'
activation=datetime.datetime.now().isoformat()
log_offset=engine_log.stat().st_size if engine_log.exists() else 0
for base,pre in [(ROOT,'panorama/src'),(CONTENT,'panorama')]:
 layout=base/pre/'layout/custom_game/archive.xml'
 text=layout.read_text(encoding='utf-8')
 # Remove only this study's includes; preserve all unrelated later layout edits.
 text=re.sub(r'<include\s+src="file://\{resources\}/(?:styles/custom_game/archive_popup_study\.css|scripts/custom_game/archive_popup_study\.js)"\s*/>','',text)
 if a.version:
  for kind,ext in [('scripts','js'),('styles','css')]:
   source=RECORDS/f'v{a.version}.{ext}';assert source.is_file(),source
   payload=source.read_bytes()+(('// Local activation '+activation+'\n').encode('utf8') if ext=='js' else b'')
   (base/pre/f'{kind}/custom_game/archive_popup_study.{ext}').write_bytes(payload)
   text=text.replace('</'+kind+'>','<include src="file://{resources}/'+kind+'/custom_game/archive_popup_study.'+ext+'" /></'+kind+'>')
  assets=base/pre/'images/custom_game/popup_study';assets.mkdir(parents=True,exist_ok=True)
  for item in (RECORDS/'assets').glob('*'):
   if item.is_file() and item.suffix.lower() in ('.png','.svg'):(assets/item.name).write_bytes(item.read_bytes())
  if a.version>=36:
   for item in (RECORDS/'sidebar_type_v1').rglob('*'):
    if item.is_file() and item.suffix.lower() in ('.png','.txt'):
     destination=base/pre/'images/custom_game/sidebar_type_v1'/item.relative_to(RECORDS/'sidebar_type_v1')
     destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(item.read_bytes())
 layout.write_text(text,encoding='utf-8')
result=subprocess.run([str(RC),'-i',str(CONTENT/'panorama/layout/custom_game/archive.xml'),'-game',str(ROOT.parents[1]/'dota'),'-fshallow','-nop4'],capture_output=True)
log=result.stdout.decode('utf-8',errors='replace')+result.stderr.decode('utf-8',errors='replace')
(RECORDS/f'switch_v{a.version}_compile.log').write_text(log,encoding='utf-8')
assert result.returncode==0 and '0 failed' in log and 'RESOURCE COMPILE ERROR' not in log,'Compile failed; inspect switch log'
if ctypes.windll.user32.FindWindowW(None,'Dota 2') and engine_log.exists():
 for attempt in range(40):
  with engine_log.open('rb') as stream:stream.seek(log_offset);fresh=stream.read().decode('utf8',errors='replace')
  ready=('POPUP_STUDY_READY v'+str(a.version)+' ') if a.version else 'ARCHIVE_DIAGNOSTIC archive_view_dump_'
  if ready in fresh:break
  time.sleep(.25)
 else:raise RuntimeError('Compiled, but live UI reload is not confirmed yet; inspect the engine log before recording.')
 print('Live UI reload confirmed.')
(RECORDS/'active_version.json').write_text(json.dumps({'version':a.version,'switched_at':datetime.datetime.now().isoformat()},indent=2),encoding='utf-8')
print('Archive UI version',a.version,'active. Other UI files and saved data were not changed.')
