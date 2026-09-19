"""Bake one UV atlas per building; same textures drive Blender and Source 2."""
import bpy
import numpy as np

def extend_empty_pixels(data,steps=6,normal=False):
    """Extend valid atlas texels into tiny unbaked faces and filtering gutters.

    Smart UV packing of thin bevels can leave a subpixel face without samples;
    black tangent normals there turn brass edges into dark strips at game mips.
    Only zero RGB texels are filled; authored dark paint remains untouched.
    """
    valid=np.max(data[:,:,:3],axis=2)>.0001
    for _ in range(steps):
        counts=np.zeros(valid.shape,dtype=np.float32)
        colors=np.zeros_like(data[:,:,:3])
        for axis,shift in ((0,1),(0,-1),(1,1),(1,-1)):
            mask=np.roll(valid,shift,axis)
            counts+=mask
            colors+=np.roll(data[:,:,:3],shift,axis)*mask[:,:,None]
        fill=(~valid)&(counts>0)
        data[fill,:3]=colors[fill]/counts[fill,None]
        valid|=fill
    if normal:data[~valid,:3]=(.5,.5,1)
    return data

def bake(o,name,directory,resolution=1024,color_gain=1.25,cavity_strength=.35,atlas_margin=.006):
    scene=bpy.context.scene
    scene.render.engine='CYCLES';scene.cycles.samples=8
    scene.render.bake.margin=4 if resolution>1024 else 8
    scene.render.bake.use_pass_direct=False;scene.render.bake.use_pass_indirect=False
    scene.render.bake.use_pass_color=True
    # Source nodes must keep using the explicit projected coordinates while baking.
    for slot in o.material_slots:
        m=slot.material
        uv=m.node_tree.nodes.new('ShaderNodeUVMap');uv.uv_map='SurfaceUV'
        for node in list(m.node_tree.nodes):
            if node.type=='TEX_IMAGE':m.node_tree.links.new(uv.outputs['UV'],node.inputs['Vector'])
    atlas=o.data.uv_layers.new(name='BuildingAtlas')
    o.data.uv_layers.active=atlas;atlas.active_render=True
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=1.15,island_margin=atlas_margin)
    bpy.ops.object.mode_set(mode='OBJECT')
    images={}
    for suffix,kind in [('color','DIFFUSE'),('normal','NORMAL'),('ao','AO'),('roughness','ROUGHNESS')]:
        im=bpy.data.images.new(name+'_'+suffix,width=resolution,height=resolution,alpha=True)
        im.colorspace_settings.name='sRGB' if suffix=='color' else 'Non-Color'
        nodes=[]
        for slot in o.material_slots:
            n=slot.material.node_tree.nodes.new('ShaderNodeTexImage');n.image=im
            slot.material.node_tree.nodes.active=n;nodes.append((slot.material,n))
        scene.render.bake.normal_g='NEG_Y' # Source 2 tangent normal convention.
        print('BAKE',name,suffix,flush=True)
        bpy.ops.object.bake(type=kind)
        for m,n in nodes:m.node_tree.nodes.remove(n)
        images[suffix]=im
    # Bake the cavity darkening into color as well, so it survives low graphics settings.
    def pixels(im):
        data=np.empty(resolution*resolution*4,dtype=np.float32);im.pixels.foreach_get(data)
        return data.reshape(-1,4)
    c=pixels(images['color']);ao=pixels(images['ao'])
    c[:,:3]*=(1-cavity_strength+cavity_strength*ao[:,:3])*color_gain;c[:,3]=1
    images['color'].pixels.foreach_set(c.ravel())
    rough=pixels(images['roughness'])
    refl=rough.copy();refl[:,:3]=.018+.24*(1-rough[:,:3])**2;refl[:,3]=1
    im=bpy.data.images.new(name+'_reflectance',width=resolution,height=resolution,alpha=True)
    im.colorspace_settings.name='Non-Color';im.pixels.foreach_set(refl.ravel());images['reflectance']=im
    for suffix,im in images.items():
        if resolution>1024 and suffix in ('color','normal'):
            p=pixels(im).reshape(resolution,resolution,4)
            extend_empty_pixels(p,normal=suffix=='normal')
            im.pixels.foreach_set(p.ravel())
        im.filepath_raw=str(directory/(name+'_'+suffix+'.png'));im.file_format='PNG';im.save()
    canonical='materials/survival_buildings/'+name+'.vmat'
    mat=bpy.data.materials.new(canonical);mat.use_nodes=True
    bs=mat.node_tree.nodes.get('Principled BSDF')
    for suffix,socket in [('color','Base Color'),('roughness','Roughness')]:
        n=mat.node_tree.nodes.new('ShaderNodeTexImage');n.image=images[suffix]
        mat.node_tree.links.new(n.outputs['Color'],bs.inputs[socket])
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=images['normal']
    # Convert Source 2's -Y normal back to +Y for the preview without another map.
    sep=mat.node_tree.nodes.new('ShaderNodeSeparateColor');combine=mat.node_tree.nodes.new('ShaderNodeCombineColor')
    invert=mat.node_tree.nodes.new('ShaderNodeMath');invert.operation='SUBTRACT';invert.inputs[0].default_value=1
    mat.node_tree.links.new(tex.outputs['Color'],sep.inputs['Color'])
    mat.node_tree.links.new(sep.outputs[0],combine.inputs[0]);mat.node_tree.links.new(sep.outputs[2],combine.inputs[2])
    mat.node_tree.links.new(sep.outputs[1],invert.inputs[1]);mat.node_tree.links.new(invert.outputs[0],combine.inputs[1])
    normal=mat.node_tree.nodes.new('ShaderNodeNormalMap')
    mat.node_tree.links.new(combine.outputs[0],normal.inputs['Color']);mat.node_tree.links.new(normal.outputs[0],bs.inputs['Normal'])
    o.data.materials.clear();o.data.materials.append(mat)
    for face in o.data.polygons:face.material_index=0
    o.data.uv_layers.remove(o.data.uv_layers['SurfaceUV'])
    o.data.uv_layers.active_index=0;o.data.uv_layers[0].active_render=True
    stem='materials/survival_buildings/'+name
    (directory/(name+'.vmat')).write_text('"Layer0"\n{\n "shader" "global_lit_simple.vfx"\n "F_NORMAL_MAP" "1"\n "F_SPECULAR" "1"\n "TextureColor" "'+stem+'_color.png"\n "TextureNormal" "'+stem+'_normal.png"\n "TextureReflectance" "'+stem+'_reflectance.png"\n "g_vColorTint" "[1 1 1 0]"\n}\n')

def rig(o):
    bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.object.armature_add(location=(0,0,0))
    arm=bpy.context.object;arm.name=o.name+'_rig'
    bpy.ops.object.mode_set(mode='EDIT')
    bone=arm.data.edit_bones[0];bone.name='root';bone.head=(0,0,0);bone.tail=(0,1,0);bone.roll=0
    bpy.ops.object.mode_set(mode='OBJECT')
    group=o.vertex_groups.new(name='root');group.add(list(range(len(o.data.vertices))),1,'REPLACE')
    mod=o.modifiers.new('Root skin','ARMATURE');mod.object=arm
    o.parent=arm
    o.select_set(True);arm.select_set(True);bpy.context.view_layer.objects.active=o
    return arm
