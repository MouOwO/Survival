import sys,json,time
from pathlib import Path
sys.path.insert(0,str(Path('output/video_shop_20261015/deps').resolve()))
from rapidocr import RapidOCR
engine=RapidOCR(params={'Global.log_level':'warning','EngineConfig.onnxruntime.intra_op_num_threads':2,'EngineConfig.onnxruntime.inter_op_num_threads':2,'Det.limit_side_len':1280})
p=Path('output/video_shop_20261015/video1_at10.png')
r=engine(str(p));rows=r.to_json()
Path('output/video_shop_20261015/initial_ocr.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf8')
print('\n'.join(r.txts or []))
