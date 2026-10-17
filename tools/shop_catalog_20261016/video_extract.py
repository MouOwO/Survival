"""Offline extraction/OCR of the authorized 2026-10-16 shop recording."""
import argparse, hashlib, json, sys, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'output/video_shop_20261015/deps'))
import cv2
import numpy as np

SOURCE = Path(r'C:\Users\Administrator\Videos\2026-10-16 13-43-44.mp4')
OUT = ROOT / 'design_refs/shop_catalog_20261016/video'

def main():
    p=argparse.ArgumentParser();p.add_argument('--step',type=float,default=3);p.add_argument('--ocr',action='store_true');a=p.parse_args()
    OUT.mkdir(parents=True,exist_ok=True);(OUT/'frames').mkdir(exist_ok=True)
    c=cv2.VideoCapture(str(SOURCE));assert c.isOpened()
    fps=c.get(cv2.CAP_PROP_FPS);count=int(c.get(cv2.CAP_PROP_FRAME_COUNT));duration=count/fps
    meta={'source':str(SOURCE),'sha256':hashlib.file_digest(SOURCE.open('rb'),'sha256').hexdigest(),'fps':fps,'frames':count,'duration_seconds':duration,'width':int(c.get(cv2.CAP_PROP_FRAME_WIDTH)),'height':int(c.get(cv2.CAP_PROP_FRAME_HEIGHT)),'sample_step_seconds':a.step,'ocr_engine':'RapidOCR 3.10.0 ONNX local/offline' if a.ocr else None}
    (OUT/'metadata.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf8')
    if a.ocr:
        from rapidocr import RapidOCR
        engine=RapidOCR(params={'Global.log_level':'warning','EngineConfig.onnxruntime.intra_op_num_threads':2,'EngineConfig.onnxruntime.inter_op_num_threads':2,'Det.limit_side_len':1280})
    previous=None;records=[];thumbs=[];start=time.time()
    with (OUT/'ocr.jsonl').open('w',encoding='utf8') as f:
        for n,t in enumerate(np.arange(0,duration,a.step)):
            c.set(cv2.CAP_PROP_POS_MSEC,float(t)*1000);ok,frame=c.read()
            if not ok:continue
            crop=frame[140:1020,420:1515];small=cv2.resize(crop,(274,220)).astype(np.int16)
            delta=float(np.mean(np.abs(small-previous))) if previous is not None else 255.
            target=OUT/'frames'/f't{int(t*1000):06d}.jpg';cv2.imwrite(str(target),frame,[cv2.IMWRITE_JPEG_QUALITY,94])
            thumb=cv2.resize(frame,(384,216));cv2.putText(thumb,f'{t:.0f}s',(5,22),cv2.FONT_HERSHEY_SIMPLEX,.65,(0,255,255),2);thumbs.append(thumb)
            if delta<0.15:continue
            previous=small
            rec={'seconds':float(t),'frame':str(target.relative_to(ROOT)).replace('\\','/'),'ocr_crop':[420,140,1515,1020],'delta':delta}
            if a.ocr:
                result=engine(crop);rec['rows']=result.to_json() or [];rec['text']='\n'.join(result.txts or [])
            f.write(json.dumps(rec,ensure_ascii=False)+'\n');f.flush();records.append(rec)
            if n%20==0:print(f'{n+1} samples / {duration:.0f}s, {len(records)} changed screens, elapsed {time.time()-start:.1f}s',flush=True)
    c.release()
    (OUT/'ocr.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf8')
    (OUT/'transcript.txt').write_text('\n\n'.join(f'=== {r["seconds"]:07.1f}s ===\n'+r.get('text','') for r in records),encoding='utf8')
    for index in range(0,len(thumbs),25):
        batch=thumbs[index:index+25];canvas=np.zeros((216*5,384*5,3),dtype=np.uint8)
        for i,im in enumerate(batch):canvas[(i//5)*216:(i//5+1)*216,(i%5)*384:(i%5+1)*384]=im
        cv2.imwrite(str(OUT/f'contact_{index//25:02d}.jpg'),canvas,[cv2.IMWRITE_JPEG_QUALITY,93])
    print(json.dumps({'samples':len(thumbs),'changed_screens':len(records),'elapsed':round(time.time()-start,1),'output':str(OUT)},ensure_ascii=False),flush=True)

if __name__=='__main__':main()
