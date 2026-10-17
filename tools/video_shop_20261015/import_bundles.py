"""Idempotently import only the 15 reviewed 2026-10-15 video bundles."""
from pathlib import Path
import csv,hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'data/csv/商城兑换系统'
REPORT=ROOT/'output/video_shop_20261015/import'
PRICE_POLICY='half_current_20261017'
U_COIN_PER_YUAN=100
def read_csv(path):
 with path.open(encoding='utf-8-sig',newline='') as f:
  reader=csv.DictReader(f);all_rows=list(reader)
 return reader.fieldnames,all_rows

def dump(path,fields,records,bom=True):
 with path.open('w',encoding='utf-8-sig' if bom else 'utf8',newline='') as f:
  w=csv.DictWriter(f,fieldnames=fields,lineterminator='\n');w.writeheader();w.writerows(records)

def main():
 normal=json.loads((Path(__file__).parent/'reviewed_bundles.json').read_text(encoding='utf8'))
 vip=json.loads((Path(__file__).parent/'reviewed_vip.json').read_text(encoding='utf8'))
 assert len(normal['packs'])==5 and len(vip['packs'])==10
 pf,raw=read_csv(BASE/'commerce_products.csv');rf,rewards=read_csv(BASE/'commerce_rewards.csv')
 products=[p for p in raw if not p['sku'].startswith('#')]
 lookup={p['sku']:p for p in products}
 vip_rows={r['reward_id']:r for r in read_csv(ROOT/'data/csv/存档系统/archive_vip_rewards.csv')[1] if not r['reward_id'].startswith('#')}
 ids={f'video_bundle_b{i:03}' for i in range(1,6)}|{f'video_bundle_vip_{i:02}' for i in range(1,11)}
 REPORT.mkdir(parents=True,exist_ok=True)
 for p in [BASE/'commerce_products.csv',BASE/'commerce_rewards.csv',BASE/'commerce_bundle_members.csv']:
  backup=REPORT/('before_'+p.name)
  if p.exists() and not backup.exists():shutil.copyfile(p,backup)
 kept=[p for p in raw if p['sku'] not in ids]
 assert not any(r['sku'] in ids and not r['reward_id'].startswith('#') for r in rewards),'Bundles use member references, never duplicate flat rewards'
 members=[];views=[];new=[]
 for ordinal,source in enumerate(normal['packs']+vip['packs']):
  is_vip=ordinal>=5;level=int(source.get('vip_min',0));sku=f'video_bundle_vip_{level:02}' if is_vip else f'video_bundle_b{ordinal+1:03}'
  baseline=int(source['price']['current']);original=int(source['price']['original'])
  assert baseline*5==original*4 and baseline%10==0 and baseline>0
  # Recorded video prices stay evidence. Re-importing always derives the final
  # half price from that baseline, never from a previously discounted CSV row.
  current=baseline//2
  pending=[];lines=[];details=[]
  for index,item in enumerate(source['items'],1):
   count=int(item['quantity']);assert count==1
   if is_vip:
    target=f'vip_package_{level:02}' if index==1 else f'vip_medal_{level:02}';kind='vip_reward';row=vip_rows[target]
    desc=row['description'];icon='custom_game/commerce_jade_v1/gift_light.png' if index==1 else 'custom_game/reward_art_v5/lottery_hero_medal.png'
   else:
    mapping=item['project_mapping'];target=mapping.get('sku') or item['source_id'];kind='product' if mapping['status']=='mapped' else 'unavailable'
    row=lookup.get(target);desc=row['description'] if row else item['full_effect_text']
    icon=row['icon'] if row else 'custom_game/commerce_jade_v1/gift_light.png'
    if kind=='unavailable':pending.append({'source_id':item['source_id'],'name':item['name'],'reason':mapping['reason']})
   assert (ROOT/'panorama/src/images'/icon).is_file(),icon
   members.append(dict(member_id=sku+f'_{index:02}',bundle_sku=sku,member_type=kind,target_id=target,quantity=count,sort_order=index,enabled=1))
   # Keep recorded names as evidence; the project's medal catalog owns branding.
   display_name=item['name'].replace('*','·')
   if is_vip and row['group_id']=='medals':
    display_name=row['display_name']+('·永久' if '*永久' in item['name'] else '')
   lines.append(dict(kind=kind,id=target,quantity=count,label=display_name,icon=icon,description=desc))
   details.append(display_name+' ×1\n'+desc)
  assert len(lines)==(2 if is_vip else source['item_count'])
  condition=(f'达到VIP{level}可购买；' if is_vip else '')+'限购1次，与单品共用持有记录；重复领取不会重复加成。'
  reason='缺少完整外观资源：'+ '、'.join(p['name'].replace('*永久','') for p in pending) if pending else ''
  desc=condition+'\n'+'\n\n'.join(details)
  if pending:desc='待开放：'+reason+'。不可购买，不扣费、不发放部分奖励。\n'+desc
  row={k:'' for k in pf};row.update(sku=sku,display_name=source['title'],category_id='bundles',product_type='bundle',currency='u_coin',price=current,purchase_limit=1,enabled=0 if pending else 1,sort_order=ordinal+1,icon='custom_game/commerce_jade_v1/gift_light.png',description=desc,ownership_id='commerce_'+sku,source_id='VIPB'+str(level) if is_vip else f'B{ordinal+1:03}',source_current_price=baseline,source_original_price=original,source_time=source['price']['evidence']['time_seconds'],price_date='2026-10-15',description_date='2026-10-15',ownership_quantity=1,price_policy=PRICE_POLICY,price_baseline=baseline)
  new.append(row)
  views.append(dict(sku=sku,title=row['display_name'],category_id='bundles',product_type='bundle',currency='u_coin',currency_name='U币',price=current,u_coin_price=current,u_coin_per_yuan=U_COIN_PER_YUAN,amount_fen=current,price_policy=PRICE_POLICY,price_baseline=baseline,original_price=original,source_original_price=original,purchase_limit=1,purchase_method='cash',enabled=False,preview_only=True,required_vip_level=level,configured_enabled=not bool(pending),disabled_reason='bundle_pending_assets' if pending else 'payment_catalog_pending',disabled_message=reason if pending else '商品目录正在同步，请稍后重试。',owned=0,icon=row['icon'],description=desc,reward_lines=lines,source_time=row['source_time'],source_video=2 if is_vip else 1))
 mf=['member_id','bundle_sku','member_type','target_id','quantity','sort_order','enabled']
 typed=dict(zip(mf,['#types:string','string','string','string','number','number','boolean']))
 dump(BASE/'commerce_products.csv',pf,kept+new)
 dump(BASE/'commerce_bundle_members.csv',mf,[typed]+members)
 display={'version':1,'source':'reviewed local video OCR + manual frames, 2026-10-15','pricing':'1人民币=100U币；商品按2026-10-17改价前实际售价减半，原价仅展示，充值不打折','price_policy':PRICE_POLICY,'products':views}
 (ROOT/'data/ui/video_shop_bundles_20261015.json').write_text(json.dumps(display,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 (ROOT/'panorama/src/scripts/custom_game/video_shop_bundles.js').write_text('// Generated by tools/video_shop_20261015/import_bundles.py; display only, never grants or order authority.\nGameUI.CustomUIConfig().VideoShopBundleCatalog='+json.dumps(display,ensure_ascii=False,separators=(',',':'))+';\n',encoding='utf8')
 summary={'products':15,'configured_enabled':sum(int(p['enabled']) for p in new),'pending':2,'members':len(members),'original_single_rows_unchanged':True,'reward_rows_unchanged':True,'prices':[{'sku':p['sku'],'title':p['display_name'],'u_coin':p['price'],'original':p['source_original_price'],'fen':p['price'],'enabled':p['enabled']} for p in new]}
 (REPORT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
 print('VIDEO_BUNDLES_IMPORTED: 15 products, 39 members, 13 complete/2 pending, original singles/rewards preserved')
if __name__=='__main__':main()
