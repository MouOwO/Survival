"""Evidence only: crop/align actual captures against supplied approvals; no runtime art is edited."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json

HERE = Path(__file__).resolve().parent
PACK = HERE.parent / 'ui_handoff_v1/received/ui_import_handoff_v1/pages'
OUT = HERE / 'evidence/comparisons'
OUT.mkdir(exist_ok=True)
FONT = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 19)
def rgb(path):
    im=Image.open(path).convert('RGBA')
    bg=Image.new('RGBA', im.size, '#263e48'); bg.alpha_composite(im)
    return bg.convert('RGB')
def crop(im, r):
    x,y,w,h=r; return im.crop((x,y,x+w,y+h))
entries=[
 ('pool_details','final_pool_map.png',(416,166,840,610),(416,166,840,610),'四列两行；真实奖品替代确认图占位；公共分片窗框'),
 ('lottery_history','final_history_map.png',(276,140,1120,660),(276,140,1120,660),'本局真实记录；非跨局持久化记录'),
 ('daily','final_daily_claimed.png',(164,94,1344,752),(164,94,1344,752),'实机已领取；实际规则为七次循环；高级装备待配置'),
 ('lottery','final_main_open.png',(0,0,1672,941),(0,0,1672,941),'沿用已接入主界面；实际券数和保底'),
 ('roguelike','rogue_first.png',(0,0,1672,941),(0,0,1672,941),'实际服务器调试候选；名称与效果来自配置'),
 ('shop','final_shop_empty.png',(0,0,1672,941),(0,0,1672,941),'仅组件空状态；缺少商品和支付接口，不能验收为商城完成'),
 ('shop_bundles','final_bundles_empty.png',(0,0,1672,941),(0,0,1672,941),'两列两行空状态；真实礼包目录待接入'),
]
records=[]
for page,shot,ref_rect,actual_rect,note in entries:
    ref=crop(rgb(PACK/page/'approved_preview.png'),ref_rect)
    actual=crop(rgb(HERE/'evidence'/shot),actual_rect)
    # Both crops have the same design dimensions. No independent X/Y fitting.
    assert ref.size==actual.size
    w,h=ref.size
    pair=Image.new('RGB',(w*2,h+78),'#182d36');d=ImageDraw.Draw(pair)
    d.text((12,8),'交接确认图',font=FONT,fill='#efdfb9')
    d.text((w+12,8),'实际游戏截图 · 1672×941',font=FONT,fill='#efdfb9')
    pair.paste(ref,(0,40));pair.paste(actual,(w,40))
    d.text((12,h+47),note,font=FONT,fill='#d0dce1')
    pair.save(OUT/(page+'_pair.png'))
    Image.blend(ref,actual,.5).save(OUT/(page+'_overlay.png'))
    records.append(dict(page=page,actual=shot,reference=str(PACK/page/'approved_preview.png'),referenceCrop=ref_rect,actualCrop=actual_rect,note=note))
(OUT/'manifest.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf8')
print('Evidence comparisons:',len(records),'pairs + overlays. Runtime assets unchanged.')
