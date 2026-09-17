"""Extend atlas gutters on already exported assets, refresh real-mesh previews."""
import bpy
import sys
import json
import numpy as np
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from unique_building_bake import extend_empty_pixels
OUT=ROOT/'output/unique_buildings'
manifest=json.loads((OUT/'manifest.json').read_text())
results=[]
for entry in manifest:
    name=entry['name'];result={'name':name}
    for suffix in ('color','normal'):
        path=OUT/'source/materials/survival_buildings'/(name+'_'+suffix+'.png')
        im=bpy.data.images.load(str(path),check_existing=False)
        im.colorspace_settings.name='sRGB' if suffix=='color' else 'Non-Color'
        w,h=im.size;p=np.empty(w*h*4,dtype=np.float32);im.pixels.foreach_get(p);p=p.reshape(h,w,4)
        before=int(np.sum(np.max(p[:,:,:3],axis=2)<=.0001))
        extend_empty_pixels(p,steps=6,normal=suffix=='normal')
        im.pixels.foreach_set(p.ravel());im.filepath_raw=str(path);im.file_format='PNG';im.save()
        result[suffix+'_empty_before']=before
        bpy.data.images.remove(im)
    results.append(result);print('ATLAS_GUTTERS_EXTENDED',name,flush=True)
bpy.ops.wm.open_mainfile(filepath=str(OUT/'survival_buildings.blend'))
scene=bpy.context.scene;camera=scene.camera
for im in bpy.data.images:
    if im.source=='FILE':
        try:im.reload()
        except RuntimeError:pass
scene.render.engine='CYCLES';scene.cycles.samples=32
objects=[]
for entry in manifest:
    obj=bpy.data.objects[entry['name']];objects.append((entry,obj,obj.parent,tuple(obj.parent.location)))
    obj.hide_render=True;obj.hide_set(True)
for entry,obj,arm,location in objects:
    arm.location=(0,0,0);obj.hide_render=False;obj.hide_set(False)
    height=entry['dimensions'][2];target=Vector((0,0,height*.44))
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=max(161,height*1.47)
    scene.render.filepath=str(OUT/'previews'/(entry['name']+'.png'))
    bpy.ops.render.render(write_still=True)
    obj.hide_render=True;obj.hide_set(True);arm.location=location
    print('REFERENCE_PREVIEW_REFRESHED',entry['name'],flush=True)
for entry,obj,arm,location in objects:obj.hide_render=False;obj.hide_set(False)
staged=OUT/'survival_buildings_finalized.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(staged));staged.replace(OUT/'survival_buildings.blend')
(OUT/'atlas_padding_report.json').write_text(json.dumps(results,indent=2))
print('REFERENCE_TEXTURES_FINALIZED',len(results),flush=True)
