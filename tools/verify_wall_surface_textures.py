"""Blender: inspect actual compiled color/normal/specular textures, not VMAT flags alone."""
import bpy
import json
import os
import re
import subprocess
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/reference_walls'
DECODE=OUT/'decoded_surface_check';DECODE.mkdir(exist_ok=True)
VIEWER=Path(os.environ['LOCALAPPDATA'])/'Temp/source2viewer-cli/Source2Viewer-CLI.exe'
INSPECTOR=ROOT.parents[1]/'bin/win64/resourceinfo.exe'
results=[]
for stage in range(1,11):
    name=f'wall_lv{stage:02}'
    material=ROOT/'materials/survival_buildings'/(name+'.vmat_c')
    dump=subprocess.check_output([str(INSPECTOR),'-i',str(material),'-all']).decode('utf-8',errors='replace')
    maps={}
    for slot,kind in [('g_tColor','color'),('g_tNormal','normal'),('g_tSpecular','reflectance')]:
        dependency=re.search(r'm_name = "'+slot+r'"\s*m_pValue = resource:"([^"]+)"',dump)[1]
        # Source2Viewer chooses the resource basename even when -o names a file.
        png=DECODE/(Path(dependency).stem+'.png')
        run=subprocess.run([str(VIEWER),'-i',str(ROOT/(dependency+'_c')),'-o',str(png),'-d'],capture_output=True)
        assert run.returncode==0 and png.is_file(),(name,kind,run.stderr)
        im=bpy.data.images.load(str(png),check_existing=False);im.colorspace_settings.name='Non-Color'
        assert tuple(im.size)==(2048,2048),(name,kind,'resolution')
        data=np.empty(2048*2048*4,dtype=np.float32);im.pixels.foreach_get(data)
        maps[kind]=data.reshape(-1,4)[:,:3]
        bpy.data.images.remove(im)
    # Color padding extends beyond real UV islands. Use the unpadded bake to
    # exclude gutters so their default specular value cannot fake variation.
    rough_image=bpy.data.images.load(str(OUT/'source/materials/survival_buildings'/(name+'_roughness.png')),check_existing=False)
    rough_image.colorspace_settings.name='Non-Color'
    occupied=np.empty(2048*2048*4,dtype=np.float32);rough_image.pixels.foreach_get(occupied)
    mask=(maps['color'].mean(axis=1)>.06)&(occupied.reshape(-1,4)[:,0]>.05)
    bpy.data.images.remove(rough_image)
    color=maps['color'][mask];normal=maps['normal'][mask];reflectance=maps['reflectance'][mask]
    # Geometry fills only part of the atlas: exclude empty packing gutters.
    cspread=np.percentile(color.mean(axis=1),95)-np.percentile(color.mean(axis=1),5)
    nspread=np.std(normal[:,:2],axis=0)
    rspread=np.percentile(reflectance[:,0],95)-np.percentile(reflectance[:,0],5)
    assert cspread>.08,(name,'flat color',cspread)
    # A scalar roughness / neutral normal must fail; texture contrast is an art
    # review, not a requirement that every stone is as bumpy as split timber.
    assert max(nspread)>1/255,(name,'flat tangent normal',nspread)
    assert rspread>.003,(name,'uniform reflectance',rspread)
    results.append(dict(name=name,color_luminance_p95_minus_p05=float(cspread),normal_xy_std=nspread.tolist(),reflectance_p95_minus_p05=float(rspread),compiled_texture_pixels_checked=True))
report=dict(status='PASS',models=10,resolution=2048,maps_per_model=3,assets=results)
(OUT/'surface_verification.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('WALL_SURFACE_TEXTURE_PASS models=10 compiled_maps=30 nonflat_color_normal_reflectance')
