"""Offline assembly of the complete approved archive UI package.

Run: python render_preview.py
Only Pillow and files inside this package are required. This does not import
the UI into Dota 2, compile Panorama resources or modify real game data.
"""
from pathlib import Path
import argparse, hashlib, json
from PIL import Image, ImageDraw, ImageFont, ImageChops
from render_helpers import save_png, nine_slice, draw_text
from render_tooltip import render_tooltip, clamp_position


def read_json(path):return json.loads(path.read_text(encoding='utf-8'))


def load_image(package,asset):
    return Image.open(package/asset['file']).convert('RGBA')


def render_page(package,layout,data,include_preview_scene=True):
    canvas=Image.new('RGBA',tuple(layout['canvas']));fits=[]
    by_id={item['id']:item for item in data};font_cache={}
    for layer in layout['layers']:
        if layer.get('scope')=='preview_only' and not include_preview_scene:continue
        if layer['kind']=='fill':
            x0,y0,x1,y1=layer['bbox'];ImageDraw.Draw(canvas).rectangle((x0,y0,x1-1,y1-1),fill=layer['color'])
        elif layer['kind']=='image':
            asset=layout['assets'][layer['asset']];im=load_image(package,asset)
            if 'source_crop' in layer:im=im.crop(tuple(layer['source_crop']))
            size=(layer.get('width',im.width),layer.get('height',im.height))
            resample=Image.Resampling.BICUBIC if layer.get('resample')=='bicubic' else Image.Resampling.LANCZOS
            im=nine_slice(im,size,asset['nine_slice']) if 'nine_slice' in asset else im.resize(size,resample)
            canvas.alpha_composite(im,(layer['x'],layer['y']))
        elif layer['kind']=='text':
            text=layer['text']
            if layer.get('item_id') and layer.get('data_field'):
                text=str(by_id[layer['item_id']][layer['data_field']])
            font_key=(layer.get('font','cjk'),layer['size'])
            if font_key not in font_cache:
                font_cache[font_key]=ImageFont.truetype(str(package/layout['fonts'][font_key[0]]),font_key[1])
            fit=draw_text(canvas,text,layer['bbox'],font_cache[font_key],layer['color'],layer['align'],layer.get('shadow',False))
            fits.append({'id':layer['id'],**fit})
        else:raise ValueError('Unsupported layer kind: '+str(layer['kind']))
    return canvas,fits


def compare_pixels(actual,reference_path):
    if not reference_path.exists():return {'reference_exists':False,'matches':False}
    reference=Image.open(reference_path).convert('RGBA')
    if actual.size!=reference.size:return {'reference_exists':True,'matches':False,'actual_size':list(actual.size),'reference_size':list(reference.size)}
    difference=ImageChops.difference(actual,reference)
    channels=difference.split();combined=channels[0]
    for channel in channels[1:]:combined=ImageChops.lighter(combined,channel)
    mask=combined.point([0]+[255]*255)
    changed=sum(value!=0 for value in mask.get_flattened_data())
    max_difference=max(maximum for minimum,maximum in difference.getextrema())
    total=sum(sum(i*count for i,count in enumerate(channel.histogram())) for channel in channels)
    return {'reference_exists':True,'matches':changed==0,'changed_pixels':changed,'total_pixels':actual.width*actual.height,
            'max_channel_difference':max_difference,'mean_absolute_channel_difference':total/(actual.width*actual.height*4),
            'difference_bbox':mask.getbbox(),'actual_pixel_sha256':hashlib.sha256(actual.tobytes()).hexdigest(),
            'reference_pixel_sha256':hashlib.sha256(reference.tobytes()).hexdigest()}


def validate_assets(package,layout,tooltip_layout):
    manifest=read_json(package/'asset_manifest.json');missing=[];mismatch=[];not_local=[]
    for entry in manifest['assets']:
        file=package/entry['file']
        if not file.is_relative_to(package):not_local.append(entry['file']);continue
        if not file.exists():missing.append(entry['file']);continue
        if hashlib.sha256(file.read_bytes()).hexdigest()!=entry['sha256']:mismatch.append(entry['file'])
    for asset in [*layout['assets'].values(),*tooltip_layout['assets'].values()]:
        p=Path(asset['file'])
        if p.is_absolute() or '..' in p.parts:not_local.append(str(p))
        if not (package/p).is_file():missing.append(str(p))
    for path in layout['fonts'].values():
        if not (package/path).exists():missing.append(path)
    return {'manifest_asset_count':len(manifest['assets']),'missing_paths':sorted(set(missing)),
            'hash_mismatches':sorted(set(mismatch)),'external_runtime_paths':sorted(set(not_local)),
            'all_paths_exist':not missing,'all_copied_assets_match_hashes':not mismatch,'all_runtime_paths_inside_package':not not_local,
            'font_license_exists':(package/'fonts/LICENSE-SourceHanSans.txt').is_file()}


def hover_page(package,page,layout,tip):
    result=page.copy();hover=layout['hover_preview']
    result.alpha_composite(load_image(package,layout['assets'][hover['frame_asset']]),tuple(hover['frame_position']))
    result.alpha_composite(tip,tuple(hover['tooltip_sprite_position']))
    return result


def main(package,output,write_qa=True):
    layout=read_json(package/'layout.json');data=read_json(package/'data_preview.json')
    tip_layout=read_json(package/'tooltip_layout.json');tip_data=read_json(package/'tooltip_preview_data.json')
    normal,fits=render_page(package,layout,data)
    tip,tip_qa=render_tooltip(package,package,tip_data)
    hover=hover_page(package,normal,layout,tip)
    ui_only,_=render_page(package,layout,data,include_preview_scene=False)
    ui_hover=hover_page(package,ui_only,layout,tip)
    for name,image in [('page_normal',normal),('page_hover',hover),('page_normal_ui_only',ui_only),('page_hover_ui_only',ui_hover),('tooltip_assembled',tip)]:
        save_png(image,output/(name+'.png'))
    assets_qa=validate_assets(package,layout,tip_layout)
    sidebar_hits=[toggle['hit_bbox'] for toggle in layout['sidebar_toggles']]
    sidebar_hits_do_not_overlap=all(previous[3]<=following[1] for previous,following in zip(sidebar_hits,sidebar_hits[1:]))
    comparisons={state:compare_pixels(image,package/f'previews/approved_v10_{state}.png') for state,image in [('normal',normal),('hover',hover)]}
    tooltip_tests=[]
    for case,changes in [('owned',{}),('unowned',{'current':0}),('unknown',{'current':None}),('no_cap',{'cap':None}),
                          ('multiline',{'effects':['仅用于离线排版检查的长描述：确认同一 Tooltip 组件会随文本换行自动增高，并把持有数量保留在底部，不写入真实游戏配置。']})]:
        _,test=render_tooltip(package,package,{**tip_data,**changes});tooltip_tests.append({'case':case,**test})
    positions=[];bounds=layout['shared_regions']['tooltip_bounds']
    for anchor in [[834,247,954,367],[1388,247,1508,367],[1388,595,1508,715],[420,595,540,715]]:
        x,y=clamp_position(anchor,(tip_qa['width'],tip_qa['height']),bounds)
        positions.append({'anchor':anchor,'panel_position':[x,y],
                          'fits_bounds':bounds[0]<=x and x+tip_qa['width']<=bounds[2] and bounds[1]<=y and y+tip_qa['height']<=bounds[3],
                          'does_not_cover_anchor':x>=anchor[2] or x+tip_qa['width']<=anchor[0]})
    import PIL
    qa={'schema':'archive_ui_final_v1_qa','status':'approved_visual_v10; portable_offline_assembly_validated; game_import_pending',
        'canvas':layout['canvas'],'visual_approved_by_user':True,'user_visual_accepted':True,'game_imported':False,'backend_connected':False,
        'item_count':len(data),'preview_data_only':True,'other_category_data_supplied':False,'shared_layout_locked':True,
        'sidebar_hitboxes_non_overlapping':sidebar_hits_do_not_overlap,
        'grid':[8,8,7],'icon_size':[120,120],'row_y':[247,421,595],'row_step':174,
        'assets':assets_qa,'pixel_comparison_to_approved_v10':comparisons,'all_text_fits':all(f['fits'] for f in fits),
        'text_fit':fits,'tooltip_text_fits':tip_qa['all_text_fits'],'tooltip':tip_qa,'tooltip_layout_cases':tooltip_tests,
        'tooltip_placement_cases':positions,'preview_scene_runtime_use':False,'quantity_plates_used':False,
        'outer_vertical_frame_used':False,'renderer_dependencies':['Python 3','Pillow '+PIL.__version__],
        'requires_sibling_version_packages':False,
        'limits':['Offline pixel agreement does not substitute for Panorama in-game validation.',
                  'Font OTF and OFL license are included; font registration must be checked in the actual Dota project.',
                  'Virtual-shadow sample data and uncertain names/counts never overwrite actual game config or save data.']}
    qa['passed']=assets_qa['all_paths_exist'] and assets_qa['all_copied_assets_match_hashes'] and assets_qa['all_runtime_paths_inside_package'] and assets_qa['font_license_exists'] and sidebar_hits_do_not_overlap and qa['all_text_fits'] and qa['tooltip_text_fits'] and all(c['matches'] for c in comparisons.values())
    portable_report=package/'portable_verification.json'
    if portable_report.exists():qa['portable_rebuild']=read_json(portable_report)
    if write_qa:(package/'QA.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'passed':qa['passed'],'normal_changed_pixels':comparisons['normal'].get('changed_pixels'),
                      'hover_changed_pixels':comparisons['hover'].get('changed_pixels'),'asset_count':assets_qa['manifest_asset_count'],
                      'font_license_exists':assets_qa['font_license_exists'],'output':str(output)},ensure_ascii=False))
    return qa


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,help='Optional preview output directory; defaults to this package/previews.')
    parser.add_argument('--no-write-qa',action='store_true')
    args=parser.parse_args();package=Path(__file__).resolve().parent
    result=main(package,args.output.resolve() if args.output else package/'previews',not args.no_write_qa)
    raise SystemExit(0 if result['passed'] else 1)
