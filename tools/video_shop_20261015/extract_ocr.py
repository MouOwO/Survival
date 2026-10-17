"""Offline frame-by-frame OCR evidence for the user-provided shop recordings."""
import argparse,sys,json,time,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'output/video_shop_20261015/deps'))
import cv2,numpy as np
from rapidocr import RapidOCR
VIDEOS={1:r'D:\BaiduNetdiskDownload\bandicam 2026-10-15 12-39-48-362.mp4',2:r'D:\BaiduNetdiskDownload\bandicam 2026-10-15 12-42-43-408.mp4'}
def run(video,step):
    out=ROOT/'output/video_shop_20261015'/f'video{video}';(out/'frames').mkdir(parents=True,exist_ok=True)
    cap=cv2.VideoCapture(VIDEOS[video]);assert cap.isOpened(),VIDEOS[video]
    meta=(ROOT/'output/video_shop_20261015'/f'video{video}_metadata.txt').read_text(encoding='utf-8')
    m=re.search(r'Duration: (\d+):(\d+):(\d+\.\d+)',meta);duration=int(m[1])*3600+int(m[2])*60+float(m[3])
    engine=RapidOCR(params={'Global.log_level':'warning','EngineConfig.onnxruntime.intra_op_num_threads':2,'EngineConfig.onnxruntime.inter_op_num_threads':2,'Det.limit_side_len':1280})
    previous=None;records=[];samples=[];start=time.time()
    with (out/'ocr.jsonl').open('w',encoding='utf-8') as stream:
        for index,t in enumerate(np.arange(0,duration,step)):
            cap.set(cv2.CAP_PROP_POS_MSEC,float(t)*1000);ok,frame=cap.read()
            if not ok:continue
            relative=out/'frames'/f't{round(t*1000):06}.png';cv2.imwrite(str(relative),frame)
            # Only deduplicate essentially identical static pages, not changing descriptions.
            crop=frame[120:850,80:1072];thumb=cv2.resize(crop,(248,182)).astype(np.int16)
            delta=float(np.mean(np.abs(thumb-previous))) if previous is not None else 255
            samples.append({'time':round(float(t),3),'frame':str(relative.relative_to(ROOT)).replace('\\','/'),'delta':delta})
            if delta<0.08:continue
            previous=thumb
            result=engine(crop);rows=result.to_json() or []
            record={**samples[-1],'ocr_crop':[80,120,1072,850],'rows':rows,'text':'\n'.join(result.txts or [])}
            stream.write(json.dumps(record,ensure_ascii=False)+'\n');stream.flush();records.append(record)
            if len(records)%10==0:print(f'VIDEO {video}: {index+1} frames, {len(records)} changed screens OCR, {time.time()-start:.1f}s',flush=True)
    cap.release();(out/'ocr.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
    (out/'samples.json').write_text(json.dumps({'source':VIDEOS[video],'duration':duration,'step':step,'samples':samples,'ocr_screens':len(records),'engine':'RapidOCR 3.10.0 ONNX, Chinese; offline local'},ensure_ascii=False,indent=2),encoding='utf-8')
    (out/'transcript.txt').write_text('\n\n'.join(f'=== {r["time"]:07.2f}s | {r["frame"]} ===\n'+r['text'] for r in records),encoding='utf-8')
    print(f'VIDEO {video} COMPLETE: {len(samples)} samples, {len(records)} OCR screens, {time.time()-start:.1f}s',flush=True)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--video',type=int,choices=[1,2],required=True);p.add_argument('--step',type=float,default=1);a=p.parse_args();run(a.video,a.step)
