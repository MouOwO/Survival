"""Generate display-only video ordering; backend remains commerce authority.

Default writes the JSON and reviewable JS append snippet only. --append-js opts
into updating a marked, independent block after the existing bundle catalogue.
The existing VideoShopBundleCatalog assignment is preserved byte for byte.
"""
import argparse,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
EVIDENCE=ROOT/'design_refs/shop_catalog_20261016/video/catalog_reviewed.json'
JSON_PATH=ROOT/'data/ui/shop_catalog_presentation_20261016.json'
JS_PATH=ROOT/'panorama/src/scripts/custom_game/video_shop_bundles.js'
BEGIN=b'// BEGIN SURVIVAL SHOP PRESENTATION 20261016'
END=b'// END SURVIVAL SHOP PRESENTATION 20261016'

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--append-js',action='store_true');a=parser.parse_args()
    review=json.loads(EVIDENCE.read_text(encoding='utf8'))
    singles=review['all_products']
    mapping={r['source_id']:r['project_sku'] for r in singles if r['project_sku']}
    # Both IDs are explicitly reserved for the two fully implemented imports in
    # this task. Unknown/incomplete items never become placeholder products.
    mapping.update(P140='video_p140',P151='video_p151')
    all_singles=[mapping[r['source_id']] for r in singles if r['source_id'] in mapping]
    bundles=review['groups']['bundles']['skus'];vip=review['groups']['vip']['skus']
    all_group=all_singles+bundles+vip
    assert len(all_singles)==110 and len(all_group)==125 and len(set(all_group))==125
    groups={'home':list(all_group),'bundles':list(bundles),'promotions':[mapping[s] for s in review['groups']['promotions']['sources'] if s in mapping],'vip':list(vip),'all':list(all_group)}
    result={
      'schema_version':1,
      'groups':groups,
      'metadata':{
        'scope':'Display ordering and grouping only; prices, rewards, limits, balances and purchase eligibility come from the authoritative commerce catalog.',
        'source_video_name':'2026-10-16 13-43-44.mp4',
        'source_video_sha256':review['source']['sha256'],
        'reviewed_at':'2026-10-16',
        'evidence_path':'design_refs/shop_catalog_20261016/video/catalog_reviewed.json',
        'navigation_order':['home','bundles','promotions','vip','all'],
        'navigation_labels':{'home':'首页','bundles':'礼包','promotions':'促销','vip':'VIP','all':'全部商品'},
        'all':{'video_single_count':151,'mapped_single_count':110,'video_single_order':'Four columns, left to right then top to bottom, matching the recording.', 'appended_pack_count':15,'appended_pack_order':'Five normal bundles followed by ten VIP bundles, each in its recorded tab order. This is project aggregation; the recording all-products page contains singles only.'},
        'home':{'observed_in_video':False,'fallback':'Use all order, including appended normal and VIP bundles, then apply the authoritative runtime visibility rules. This is project aggregation, not a claimed home-page ordering from the recording.'},
        'promotions':{'video_count':28,'mapped_count':len(groups['promotions']),'policy':'Grouping only. Existing authoritative prices and activity schedules are unchanged.'},
        'reserved_import_skus':['video_p140','video_p151'],
        'unmapped_sources_omitted':[r['source_id'] for r in singles if r['source_id'] not in mapping],
        'pack_sku_metadata':'Bundle and VIP arrays include catalog identifiers only. Runtime owns visibility and availability.'
      }
    }
    payload=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    JSON_PATH.parent.mkdir(parents=True,exist_ok=True);JSON_PATH.write_text(payload,encoding='utf8')
    block=BEGIN+b'\n'+b'GameUI.CustomUIConfig().SurvivalShopPresentation='+json.dumps(result,ensure_ascii=False,separators=(',',':')).encode('utf8')+b';\n'+END+b'\n'
    snippet=ROOT/'design_refs/shop_catalog_20261016/video/presentation_append.js';snippet.write_bytes(block)
    output={'json':str(JSON_PATH.relative_to(ROOT)),'group_sizes':{k:len(v) for k,v in groups.items()},'omitted_unmapped_sources':len(result['metadata']['unmapped_sources_omitted']),'js_modified':False}
    if a.append_js:
      original=JS_PATH.read_bytes();assert original.count(BEGIN)<=1 and original.count(END)<=1,'duplicate/corrupt presentation marker'
      if BEGIN in original:
        assert END in original,'missing presentation end marker'
        start=original.index(BEGIN);finish=original.index(END,start)+len(END)
        if original[finish:finish+2]==b'\r\n':finish+=2
        elif original[finish:finish+1]==b'\n':finish+=1
        before=original[:start];after=original[finish:];updated=before+block+after
        assert updated[:len(before)]==before and updated.endswith(after),'unrelated JS changed'
      else:
        assert END not in original,'orphan presentation end marker'
        before=original;after=b'';updated=before+(b'' if before.endswith(b'\n') else b'\n')+block
        assert updated.startswith(original),'original JS modified'
      JS_PATH.write_bytes(updated)
      output.update(js_modified=True,original_js_sha256=hashlib.sha256(original).hexdigest(),preserved_prefix_sha256=hashlib.sha256(before).hexdigest(),result_js_sha256=hashlib.sha256(updated).hexdigest())
    print(json.dumps(output,ensure_ascii=False))

if __name__=='__main__':main()
