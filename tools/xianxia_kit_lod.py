"""Run in connected Blender after the model builder. Optional simplified variants."""
import bpy,os,json,math
from mathutils import Matrix
k=bpy.app.driver_namespace['xxkit'];lod=[]
for name,src in k['objects'].items():
 o=src.copy();o.data=src.data.copy();k['scene'].collection.objects.link(o);o.location=(0,0,0)
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
 if len(o.data.polygons)>500:
  mod=o.modifiers.new('LOD reduction','DECIMATE');mod.ratio=.45;bpy.ops.object.modifier_apply(modifier=mod.name)
 o.data.transform(Matrix.Rotation(-math.pi/2,4,'Z'))
 bpy.ops.export_scene.fbx(filepath=os.path.join(k['MODELS'],name+'_lod1.fbx'),use_selection=True,object_types={'MESH'},axis_forward='X',axis_up='Z',add_leaf_bones=False,bake_anim=False)
 lod.append({'name':name,'baseTriangles':len(src.data.polygons),'lod1Triangles':len(o.data.polygons)})
 bpy.data.objects.remove(o,do_unlink=True)
json.dump(lod,open(os.path.join(k['OUT'],'lod_manifest.json'),'w'),indent=2)
