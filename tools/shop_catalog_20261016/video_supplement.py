"""Full-width OCR for manually chosen shop evidence frames; no production edits."""
import argparse,json,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'output/video_shop_20261015/deps'))
import cv2
from rapidocr import RapidOCR
OUT=ROOT/'design_refs/shop_catalog_20261016/video'
parser=argparse.ArgumentParser();parser.add_argument('times',nargs='+',type=float);a=parser.parse_args()
engine=RapidOCR(params={'Global.log_level':'warning','EngineConfig.onnxruntime.intra_op_num_threads':2,'EngineConfig.onnxruntime.inter_op_num_threads':2,'Det.limit_side_len':1600})
c=cv2.VideoCapture(r'C:\Users\Administrator\Videos\2026-10-16 13-43-44.mp4')
records=[]
for t in a.times:
    c.set(cv2.CAP_PROP_POS_MSEC,t*1000);ok,frame=c.read();assert ok
    path=OUT/'frames'/f't{round(t*1000):06d}.jpg';cv2.imwrite(str(path),frame,[cv2.IMWRITE_JPEG_QUALITY,96])
    result=engine(frame[140:1020,400:1920]);r={'seconds':t,'frame':str(path.relative_to(ROOT)).replace('\\','/'),'ocr_crop':[400,140,1920,1020],'rows':result.to_json() or [],'text':'\n'.join(result.txts or [])}
    (OUT/f'supplement_{round(t*1000):06d}.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf8');records.append(r)
    print(f'full-width OCR {t}s',flush=True)
c.release()
(OUT/'supplement.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'supplement_transcript.txt').write_text('\n\n'.join(f'=== {r["seconds"]}s ===\n'+r['text'] for r in records),encoding='utf8')
