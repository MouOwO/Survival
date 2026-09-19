import bpy,os
out=os.path.dirname(os.path.abspath(__file__))
for o in bpy.context.scene.objects:
    if o.name.startswith(('Rose carved rim','Rose glass','Rose centre','Rose tracery')):
        o.location.y-=0
bpy.context.scene.name='Gothic Keep Preview'
bpy.ops.object.select_all(action='DESELECT')
for o in bpy.data.collections['GOTHIC_KEEP_ASSET.001'].objects if 'GOTHIC_KEEP_ASSET.001' in bpy.data.collections else bpy.data.collections['GOTHIC_KEEP_ASSET'].objects:
    o.select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out,'gothic_keep_v1.blend'))
bpy.ops.export_scene.gltf(filepath=os.path.join(out,'gothic_keep_v1.glb'),export_format='GLB',use_selection=True,export_apply=True)

