"""Exercise the actual double-click CMD -> Windows PowerShell -> Python chain."""
import json, os, subprocess, tempfile
from pathlib import Path
from tower_skin_presets import ROOT, combat_digest

original=json.loads((ROOT/'data/tower_visual_presets/active.json').read_text(encoding='utf8'))['preset']
protected=combat_digest()
env=dict(os.environ, TOWER_SWITCH_NO_PAUSE='1')
def launch(preset):
    entry=ROOT/'tools'/('switch_tower_'+preset+'.cmd')
    result=subprocess.run('cmd.exe /d /c call "'+str(entry)+'"',cwd=tempfile.gettempdir(),env=env,input='',text=True,encoding='utf8',errors='replace',capture_output=True,timeout=60)
    if result.returncode:
        raise AssertionError(result.stdout+'\n'+result.stderr)
    log=(ROOT/'output/tower_skin_trial'/('switch_'+preset+'.log')).read_text(encoding='utf-8-sig')
    assert 'TOWER_SKIN_PRESET_APPLIED '+preset in log,log
    assert 'Preset '+preset+' is ready.' in log,log
    assert 'Microsoft\\WindowsApps\\python.exe' not in log,log
    assert json.loads((ROOT/'data/tower_visual_presets/active.json').read_text(encoding='utf8'))['preset']==preset
    assert combat_digest()==protected
    print('DOUBLE_CLICK_SWITCH_PASS',preset,flush=True)
try:
    for preset in 'BCA':launch(preset)
finally:
    current=json.loads((ROOT/'data/tower_visual_presets/active.json').read_text(encoding='utf8'))['preset']
    if current!=original:launch(original)
print('TOWER_SWITCH_LAUNCHER_PASS: real CMD entry, external working directory, logs, all presets, combat unchanged; original preset restored')
