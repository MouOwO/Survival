from pathlib import Path
import json,io,os
from PIL import Image

root=Path(__file__).resolve().parent
m=json.loads((root/'reference/assembly.json').read_text(encoding='utf-8'))
image=Image.open(root/m['base']).convert('RGBA')
for layer in m['layers']:
    image.alpha_composite(Image.open(root/layer['file']).convert('RGBA'),(layer['x'],layer['y']))
target=root/'previews/reassembled_reference.png';buffer=io.BytesIO();image.save(buffer,format='PNG')
staging=target.with_suffix('.writing');staging.write_bytes(buffer.getvalue());os.replace(staging,target)
print('Reference rebuilt from exported slices. Original-source verification is recorded in QA.json.')
