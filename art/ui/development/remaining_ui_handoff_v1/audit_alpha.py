raise SystemExit('RETIRED_UI_WORKFLOW: this historical alpha audit depends on superseded art removed on 2026-10-21. Inspect maintained art/ui/sources and current UI resources instead; do not restore the candidate copy.')
from pathlib import Path
from PIL import Image
import json
root=Path(__file__).resolve().parent
result=[]
for asset in json.loads((root/'asset_audit.json').read_text(encoding='utf8')):
    im=Image.open(root/'candidate/panorama'/asset['runtime'])
    alpha=im.getchannel('A') if 'A' in im.getbands() else None
    result.append({'file':asset['runtime'],'source':asset['original_path'],'size':im.size,'mode':im.mode,'alphaRange':alpha.getextrema() if alpha else None})
(root/'alpha_report.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
print('Inspected',len(result),'mapped images;',sum(r['alphaRange'] is not None and r['alphaRange'][0]==0 for r in result),'contain real transparent pixels. Runtime files unchanged.')
