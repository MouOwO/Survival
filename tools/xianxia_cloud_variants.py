"""Two independently shaped banks for the whole-map composition, same approved lighting."""
import os
ROOT=r'D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival'
source=open(os.path.join(ROOT,'tools','xianxia_cloud_revision.py'),encoding='utf8').read()
source=source[:source.index("jobs=[('c01_cloud_sea'")]
source=source.replace('for x,y,z,rx,ry,rz in primary:', '''primary=[(x+rng.uniform(-.8,.8),y+rng.uniform(-.65,.65),z+rng.uniform(-.6,.6),rx*rng.uniform(.84,1.13),ry*rng.uniform(.8,1.2),rz*rng.uniform(.7,1.25)) for x,y,z,rx,ry,rz in primary]
 for x,y,z,rx,ry,rz in primary:''')
exec(compile(source,'cloud_variant_setup','exec'))
scene.cycles.samples=128
scene.cycles.volume_step_rate=.6
OUT=os.path.join(ROOT,'output','xianxia_kit','cloud_revision_v2','variants');os.makedirs(OUT,exist_ok=True)
for name,seed,kind in [('c01_cloud_sea_b',708,'sea'),('c02_cliff_cloud_b',604,'bank')]:
 shape(seed,kind);c.location=(0,-19,21);aim(c,(0,0,.3))
 scene.render.filepath=os.path.join(OUT,name+'.png')
 bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,name+'.blend'))
 bpy.ops.render.render(write_still=True);print('VARIANT_DONE',name,flush=True)
