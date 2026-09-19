"""Independent periodic slate geometry, baked into separate engine maps."""
import bpy, math, random, os, json, time, traceback
OUT=r'D:\steam\steamapps\common\dota 2 beta\game\dota_addons\survival\output\basin_natural\materials'
os.makedirs(OUT,exist_ok=True)
def run():
    started=time.time(); rng=random.Random(915)
    scene=bpy.data.scenes.new('Natural_Slate_Periodic'); bpy.context.window.scene=scene
    scene.render.engine='CYCLES'; scene.cycles.samples=4
    try:
        p=bpy.context.preferences.addons['cycles'].preferences;p.compute_device_type='HIP';p.get_devices()
        for d in p.devices:d.use=d.type=='HIP'
        scene.cycles.device='GPU'
    except Exception:scene.cycles.device='CPU'
    scene.world=bpy.data.worlds.new('Slate bake neutral world'); scene.world.use_nodes=True
    scene.view_settings.view_transform='Standard'
    def lin(x):return ((x/255+.055)/1.055)**2.4
    mats=[]
    for i,rgb in enumerate([(131,153,162),(143,163,170),(119,143,156),(152,170,174),(132,155,164),(140,158,164)]):
        m=bpy.data.materials.new('Cool slate '+str(i));m.use_nodes=True;ns=m.node_tree.nodes;ls=m.node_tree.links;b=next(n for n in ns if n.type=='BSDF_PRINCIPLED')
        coord=ns.new('ShaderNodeTexCoord');noise=ns.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=.025;noise.inputs['Detail'].default_value=3
        ls.new(coord.outputs['Generated'],noise.inputs[0]);noise.inputs['Scale'].default_value=6
        ramp=ns.new('ShaderNodeValToRGB');base=tuple(lin(x)for x in rgb)
        ramp.color_ramp.elements[0].color=tuple(v*.83 for v in base)+(1,);ramp.color_ramp.elements[1].color=tuple(v*1.08 for v in base)+(1,)
        ls.new(noise.outputs['Fac'],ramp.inputs[0]);ls.new(ramp.outputs[0],b.inputs['Base Color'])
        bump=ns.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.22;bump.inputs['Distance'].default_value=.65
        ls.new(noise.outputs['Fac'],bump.inputs['Height']);ls.new(bump.outputs[0],b.inputs['Normal']);b.inputs['Roughness'].default_value=.48
        mats.append(m)
    dark=bpy.data.materials.new('Narrow slate joints');dark.use_nodes=True
    next(n for n in dark.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Base Color'].default_value=(.065,.095,.108,1)
    high=[]
    def solid(name,p,z,mat,bevel):
        n=len(p);v=[(x,y,-4)for x,y in p]+[(x,y,z)for x,y in p]
        f=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,n+(i+1)%n,n+i)for i in range(n)]
        me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.materials.append(mat);ob=bpy.data.objects.new(name,me);scene.collection.objects.link(ob);high.append(ob)
        if bevel:
            mod=ob.modifiers.new('Soft chipped edges','BEVEL');mod.width=bevel;mod.segments=2;ob.modifiers.new('Corner normals','WEIGHTED_NORMAL')
        return ob
    solid('Mortar bed',[(-100,-100),(2148,-100),(2148,2148),(-100,2148)],-1,dark,0)
    # Periodic jittered sites; clip each Voronoi polygon against every nearby site.
    sites=[((x+.5+rng.uniform(-.28,.28))*256,(y+.5+rng.uniform(-.28,.28))*256)for y in range(8)for x in range(8)]
    allsites=[(x+dx*2048,y+dy*2048,i)for dy in [-1,0,1]for dx in [-1,0,1]for i,(x,y)in enumerate(sites)]
    count=0
    for sx,sy,idx in allsites:
        if not -420<sx<2468 or not -420<sy<2468:continue
        poly=[(sx-500,sy-500),(sx+500,sy-500),(sx+500,sy+500),(sx-500,sy+500)]
        for tx,ty,j in allsites:
            if (sx==tx and sy==ty)or abs(sx-tx)>850 or abs(sy-ty)>850:continue
            nx,ny=tx-sx,ty-sy;d=(tx*tx+ty*ty-sx*sx-sy*sy)/2;out=[]
            for k,a in enumerate(poly):
                b=poly[(k+1)%len(poly)];da=d-nx*a[0]-ny*a[1];db=d-nx*b[0]-ny*b[1]
                if da>=0:out.append(a)
                if (da>=0)!=(db>=0):
                    w=da/(da-db);out.append((a[0]+(b[0]-a[0])*w,a[1]+(b[1]-a[1])*w))
            poly=out
            if not poly:break
        if not poly:continue
        poly=[(sx+(x-sx)*.980,sy+(y-sy)*.980)for x,y in poly]
        solid('Flagstone_%d_%d'%(idx,count),poly,5+(idx%4)*.65,mats[idx%len(mats)],2.6);count+=1
    me=bpy.data.meshes.new('Periodic UV target');me.from_pydata([(0,0,-12),(2048,0,-12),(2048,2048,-12),(0,2048,-12)],[],[(0,1,2,3)])
    uv=me.uv_layers.new()
    for l,p in zip(uv.data,[(0,0),(1,0),(1,1),(0,1)]):l.uv=p
    low=bpy.data.objects.new('Slate bake target',me);scene.collection.objects.link(low)
    mat=bpy.data.materials.new('Slate target');mat.use_nodes=True;low.data.materials.append(mat);node=mat.node_tree.nodes.new('ShaderNodeTexImage');mat.node_tree.nodes.active=node
    for ob in scene.objects:ob.select_set(False)
    for ob in high:ob.select_set(True)
    low.select_set(True);bpy.context.view_layer.objects.active=low
    bake=scene.render.bake;bake.use_selected_to_active=True;bake.cage_extrusion=44;bake.max_ray_distance=60;bake.margin=8;bake.use_pass_direct=False;bake.use_pass_indirect=False;bake.use_pass_color=True;bake.normal_space='TANGENT';bake.normal_g='NEG_Y'
    for kind,typ in [('color','DIFFUSE'),('normal','NORMAL'),('roughness','ROUGHNESS')]:
        im=bpy.data.images.new('natural_slate_'+kind,width=2048,height=2048,alpha=False)
        if kind!='color':im.colorspace_settings.name='Non-Color'
        node.image=im;bpy.ops.object.bake(type=typ);im.filepath_raw=os.path.join(OUT,'slate_'+kind+'.png');im.file_format='PNG';im.save()
        with open(os.path.join(OUT,'progress.json'),'w')as f:json.dump({'finished':kind,'seconds':time.time()-started},f)
    low.hide_render=True;bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'natural_slate.blend'))
    with open(os.path.join(OUT,'bake_report.json'),'w')as f:json.dump({'status':'complete','stones':count,'periodic':True,'size':2048,'normal':'+X -Y +Z','seconds':time.time()-started},f)
def task():
    try:run()
    except Exception:
        with open(os.path.join(OUT,'error.txt'),'w')as f:f.write(traceback.format_exc())
    return None
bpy.app.timers.register(task,first_interval=.3)
print('Periodic slate modeling and bake scheduled')
