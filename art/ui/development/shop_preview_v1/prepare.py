import csv,json,sys
from pathlib import Path
root=Path(__file__).resolve().parents[4]
here=Path(__file__).resolve().parent
sys.path.insert(0,str(here/'vendor'))
import qrcode
from PIL import Image,ImageDraw
def rows(rel):
    return [r for r in csv.DictReader((root/rel).open(encoding='utf-8-sig')) if not next(iter(r.values())).startswith('#')]
cats=rows('data/csv/商店系统/shop_categories.csv')
entries=rows('data/csv/商店系统/shop_entries.csv')
icons=rows('data/csv/存档系统/archive_item_icons.csv')
demo_icons=[x for x in icons if x['category_id'] in ['shop','fragment','points']]
products=[]
for c in cats:
    choices=[r for r in entries if r['category_id']==c['category_id']]
    for i in range(8):
        r=choices[i%len(choices)] if choices else {}
        icon=next((x for x in icons if x['item_id']==r.get('content_id')),demo_icons[(len(products)+i)%len(demo_icons)])
        products.append(dict(id='preview_'+c['category_id']+'_'+str(i),item_id=icon['item_id'],category=c['category_id'],name=r.get('display_name','演示商品')+(' · 长名称展示测试' if i==1 else ''),image='file://{images}/'+icon['icon_path'],effect='演示道具效果：'+r.get('notes','用于预览布局，不发放真实权益。'),prices=[dict(amount=(i+1)*120 if i%2==0 else (i+1)*6,currencyName='积分' if i%2==0 else 'U币')],state='owned' if i==2 else 'soldout' if i==3 else 'normal',purchasable=i not in [2,3],min_quantity=1,max_quantity=9))
        products[-1]['name']=icon['display_name']+(' · 长名称展示测试' if i==1 else '')
        products[-1]['effect']='模拟效果：提升'+['攻击速度','资源获取','生命恢复','护甲'][i%4]+'，持续60秒。仅用于界面展示，不实际生效。'+('这是一段较长的模拟效果说明，用于检查悬停层内换行和滚动，购买不会改变角色属性或背包。' if i==1 else '')
bundles=[]
for i in range(4):
    bundles.append(dict(id='preview_bundle_'+str(i),category='bundles',name=['启程礼包','成长礼包','勇者礼包','典藏礼包'][i],effect='演示礼包，仅展示组合内容与模拟金额。',prices=[dict(amount=(i+1)*36,currencyName='U币')],state='normal',purchasable=True,min_quantity=1,max_quantity=5,items=[dict(products[j+i],quantity=j+1) for j in range(4)],image=products[i]['image']))
data=dict(categories=[dict(id=c['category_id'],label=c['name']) for c in cats]+[dict(id='bundles',label='礼包')],products=products,bundles=bundles)
(here/'catalog.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
out=root/'panorama/src/images/custom_game/shop_preview_v1';out.mkdir(parents=True,exist_ok=True)
qr=qrcode.QRCode(version=1,error_correction=qrcode.constants.ERROR_CORRECT_M,box_size=8,border=4)
qr.add_data('UI_PREVIEW_ONLY');qr.make(fit=True);qr.make_image(fill_color='black',back_color='white').save(out/'preview_qr.png')
(out/'shop.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><g fill="none" stroke="#e3ded0" stroke-width="3" stroke-linejoin="round"><path d="M16 24h32l4 29H12z"/><path d="M23 27V17a9 9 0 0 1 18 0v10"/><path d="M24 37h16M28 44h8"/></g></svg>',encoding='utf-8')
im=Image.new('RGBA',(256,256));d=ImageDraw.Draw(im);col='#e3ded0';d.line([(64,96),(192,96),(208,212),(48,212),(64,96)],fill=col,width=12,joint='curve');d.arc((92,32,164,104),180,360,fill=col,width=12);d.line((92,68,92,108),fill=col,width=12);d.line((164,68,164,108),fill=col,width=12);d.line((96,148,160,148),fill=col,width=12);d.line((112,176,144,176),fill=col,width=12);im.resize((64,64),Image.Resampling.LANCZOS).save(out/'shop.png')
print('PREVIEW_ASSETS: five configured categories, four bundles, local non-payment QR with four-module white border')
