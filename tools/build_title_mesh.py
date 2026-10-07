"""Build real closed 3D title geometry in an isolated Blender background process."""
from pathlib import Path
import bpy,math,json,bmesh
from mathutils import Vector,Matrix
R=Path(__file__).resolve().parents[1];O=R/'art/titles/peak_perfection_3d';S=O/'source';M=S/'models/survival_titles';T=S/'materials/survival_titles'
for p in (O,M,T):p.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE_NEXT';scene.render.film_transparent=True
materials={}
for name,col,metal,rough in [('gold',(.70,.38,.12),.8,.24),('letters',(.94,.75,.42),.8,.23),('glint',(1,.97,.79),.6,.12),('edge',(1,.80,.29),.72,.2),('red',(.34,.006,.016),.5,.24),('bronze',(.29,.13,.018),.7,.29),('ruby',(.68,.008,.025),.6,.16),('black',(.015,.003,.001),.3,.35)]:
 path='materials/survival_titles/'+name+'.vmat';mat=bpy.data.materials.new(path);mat.use_nodes=True;bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Base Color'].default_value=(*col,1);bs.inputs['Metallic'].default_value=metal;bs.inputs['Roughness'].default_value=rough;materials[name]=mat
 img=bpy.data.images.new(name+'_color',width=8,height=8);img.generated_color=(*col,1);img.filepath_raw=str(T/(name+'.png'));img.file_format='PNG';img.save()
 (T/(name+'.vmat')).write_text('"Layer0"\n{\n "shader" "global_lit_simple.vfx"\n "F_SPECULAR" "1"\n "TextureColor" "materials/survival_titles/'+name+'.png"\n "TextureReflectance" "[0.38 0.38 0.38 0]"\n "g_vColorTint" "[1 1 1 0]"\n}\n')
parts=[]
def mesh(name,verts,faces,mat):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();ob=bpy.data.objects.new(name,me);scene.collection.objects.link(ob);ob.data.materials.append(materials[mat]);parts.append(ob);return ob
def tube(name,points,radius,mat):
 cu=bpy.data.curves.new(name,'CURVE');cu.dimensions='3D';cu.resolution_u=10;cu.bevel_depth=radius;cu.bevel_resolution=1;cu.use_fill_caps=True;sp=cu.splines.new('BEZIER');sp.bezier_points.add(len(points)-1)
 for bp,co in zip(sp.bezier_points,points):bp.co=co;bp.handle_left_type='AUTO';bp.handle_right_type='AUTO'
 ob=bpy.data.objects.new(name,cu);scene.collection.objects.link(ob);cu.materials.append(materials[mat]);parts.append(ob);return ob
def ellipsoid(name,loc,scale,mat):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,location=loc);ob=bpy.context.object;ob.name=name;ob.scale=scale;ob.data.materials.append(materials[mat]);parts.append(ob);return ob
def horn(name,a,b,r,mat):
 delta=Vector(b)-Vector(a);bpy.ops.mesh.primitive_cone_add(vertices=9,radius1=r,radius2=.18,depth=delta.length,location=(Vector(a)+Vector(b))/2);ob=bpy.context.object;ob.name=name;ob.rotation_euler=delta.to_track_quat('Z','Y').to_euler();ob.data.materials.append(materials[mat]);parts.append(ob);return ob
def plate(name,outline,z,depth,mat):
 n=len(outline);v=[(x,y,z)for x,y in outline]+[(x,y,z+depth)for x,y in outline];f=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n)for i in range(n)];return mesh(name,v,f,mat)
outline=[(-141,-26),(-115,-35),(-64,-32),(0,-38),(64,-32),(115,-35),(141,-26),(130,0),(141,26),(115,35),(64,32),(0,38),(-64,32),(-115,35),(-141,26),(-130,0)]
plate('Solid crimson backing',outline,-7,5,'red')
tube('Raised gold frame',[(x,y,-.5)for x,y in outline+[outline[0]]],2.0,'gold')
# Each glyph is a true extruded closed mesh, with red metal behind its gold face.
font=bpy.data.fonts.load('C:/Windows/Fonts/simkai.ttf')
for idx,char in enumerate('登峰造极'):
 x=(idx-1.5)*62
 for layer,z,extrude,offset,bevel,mat in [('red_outline',2,6,1.0,.5,'red'),('gold_face',8.4,3.2,0,.8,'letters')]:
  cu=bpy.data.curves.new('glyph_'+str(idx)+'_'+layer,'FONT');cu.body=char;cu.font=font;cu.size=64;cu.align_x='CENTER';cu.align_y='CENTER';cu.extrude=extrude;cu.bevel_depth=bevel;cu.bevel_resolution=1;cu.resolution_u=4;cu.offset=offset;cu.fill_mode='BOTH'
  ob=bpy.data.objects.new('Character_'+str(idx)+'_'+layer,cu);scene.collection.objects.link(ob);ob.location=(x,0,z);cu.materials.append(materials[mat]);parts.append(ob)
# Sculpted mirrored dragons: solid coils, articulated heads, horns, fins, eyes and whiskers.
for side in (-1,1):
 def p(x,y,z=0):return (side*x,y,z)
 tube('Dragon coiled body', [p(112,-34,-1),p(155,-35,-1),p(175,-15,0),p(173,15,2),p(154,27,3),p(143,22,5)],8,'gold')
 tube('Dragon belly ridge',[p(123,-31,5),p(151,-29,7),p(165,-12,8),p(164,12,9),p(148,22,10)],2.6,'edge')
 ellipsoid('Dragon skull',p(142,23,6),(15,10,7),'gold');ellipsoid('Dragon muzzle',p(128,18,10),(11,5.5,5.5),'edge')
 ellipsoid('Dragon mouth',p(126,13,10),(9,1.8,3.5),'black');ellipsoid('Dragon lower jaw',p(128,10.4,8),(10,3,4),'gold')
 ellipsoid('Ruby dragon eye',p(139,26,12.8),(2.2,1.6,1.8),'ruby')
 tube('Brow crest',[p(150,29,10),p(141,31,14),p(133,27,14)],2.4,'gold')
 for dx,dy in [(0,0),(9,-4)]:
  tube('Swept antler',[p(145+dx,30+dy,8),p(155+dx,42+dy,10),p(160+dx,49+dy,9)],1.8,'edge')
  horn('Antler fork',p(153+dx,39+dy,10),p(151+dx,48+dy,10),1.5,'gold')
 for i in range(8):
  a=-1.45+i*.37;x=155+19*math.cos(a);y=24*math.sin(a)
  horn('Spine fin',p(x,y,2),p(x+6,y+8,2),3.0,'gold')
 tube('Dragon whisker',[p(121,19,12),p(112,24,15),p(109,36,13)],.8,'edge')
 tube('Lower whisker',[p(123,11,10),p(113,6,13),p(109,-4,12)],.65,'gold')
 for i in range(3):horn('Dragon tooth',p(122+i*4,14,13),p(122+i*4,10,13),.7,'edge')
 # Scale rings are solid ribs visible from the side, not a painted dragon image.
 for i in range(10):
  a=-1.4+i*.24;x=155+15*math.cos(a);y=24*math.sin(a)
  tube('Scale rib',[p(x-4,y-1,6),p(x,y+1,8),p(x+4,y+3,6)],.55,'bronze')
for y in (-39,40):
 gem=[(0,y+10,3),(8,y,3),(0,y-10,3),(-8,y,3),(0,y,13),(0,y,-1)]
 mesh('Faceted red gem',gem,[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(1,0,5),(2,1,5),(3,2,5),(0,3,5)],'ruby')
 tube('Gem gold rim',[(x,y2,z)for x,y2,z in gem[:4]+gem[:1]],1.1,'edge')
# Convert/export actual mesh geometry, triangulate, and assign UVs to constant material swatches.
bpy.ops.object.select_all(action='DESELECT')
for ob in parts:ob.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.convert(target='MESH')
# Cut the gold letters into twelve physical horizontal material bands. Skin
# groups light these bands from top to bottom, on the real mesh including bevels.
bands=[]
for i in range(12):
 name='letters_%02d'%i;mat=materials['letters'].copy();mat.name='materials/survival_titles/'+name+'.vmat';bands.append(mat)
 (T/(name+'.vmat')).write_text((T/'letters.vmat').read_text())
for piece in list(bpy.context.selected_objects):
 if 'gold_face' not in piece.name:continue
 bm=bmesh.new();bm.from_mesh(piece.data)
 for y in range(-30,36,6):
  bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.00001,plane_co=(0,y,0),plane_no=(0,1,0),clear_inner=False,clear_outer=False)
 piece.data.materials.clear()
 for mat in bands:piece.data.materials.append(mat)
 for f in bm.faces:f.material_index=max(0,min(11,int((36-f.calc_center_median().y)/6)))
 bm.to_mesh(piece.data);bm.free()
bpy.ops.object.join();ob=bpy.context.object;ob.name='peak_perfection_3d'
bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
bm=bmesh.new();bm.from_mesh(ob.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
uv=ob.data.uv_layers.new(name='MaterialUV')
for f in ob.data.polygons:
 for li in f.loop_indices:uv.data[li].uv=(.5,.5)
ob.data.transform(Matrix.Rotation(-math.pi/2,4,'Z'))
bpy.ops.export_scene.fbx(filepath=str(M/'peak_perfection.fbx'),use_selection=True,object_types={'MESH'},axis_forward='-Y',axis_up='Z',bake_anim=False,add_leaf_bones=False)
ob.data.transform(Matrix.Rotation(math.pi/2,4,'Z'))
header='<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc28:version{fb63b6ca-f435-4aa0-a2c7-c66ddc651dca} -->\n'
remaps=','.join('{from="'+m.name+'" to="'+m.name+'"}'for m in ob.data.materials)
groups=['{_class="DefaultMaterialGroup" name="default" remaps=['+remaps+'] use_global_default=false}']
for i in range(12):groups.append('{_class="MaterialGroup" name="sweep_%02d" remaps=[{from="materials/survival_titles/letters_%02d.vmat" to="materials/survival_titles/glint.vmat"}]}'%(i+1,i))
(M/'peak_perfection.vmdl').write_text(header+'{rootNode={_class="RootNode" children=[{_class="RenderMeshList" children=[{_class="RenderMeshFile" filename="models/survival_titles/peak_perfection.fbx" import_scale=0.01}]},{_class="MaterialGroupList" children=['+','.join(groups)+']}]}}')

bounds=[[min(v.co[i]for v in ob.data.vertices)for i in range(3)],[max(v.co[i]for v in ob.data.vertices)for i in range(3)]]
(O/'manifest.json').write_text(json.dumps({'mesh_vertices':len(ob.data.vertices),'triangles':len(ob.data.polygons),'bounds':bounds,'text':'登峰造极','font_source':'Windows KaiTi; glyph geometry only','collision':False,'real_mesh':True,'front_face':'local +Z','export_axis_compensation_degrees':-90},ensure_ascii=False,indent=2),encoding='utf-8')
# Save editable mesh plus two renders to inspect actual thickness.
scene.world=bpy.data.worlds.new('Studio');scene.world.use_nodes=True;next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.12,.12,.12,1)
for name,loc,power,size in [('key',(-100,120,240),350000,160),('fill',(130,-35,160),160000,130),('rim',(0,70,-70),220000,100)]:
 d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size;l=bpy.data.objects.new(name,d);scene.collection.objects.link(l);l.location=loc;l.rotation_euler=(-l.location).to_track_quat('-Z','Y').to_euler()
cam_data=bpy.data.cameras.new('Inspection camera');cam=bpy.data.objects.new('Inspection camera',cam_data);scene.collection.objects.link(cam);scene.camera=cam;cam_data.type='ORTHO';cam_data.ortho_scale=400
scene.render.resolution_x=1600;scene.render.resolution_y=700;scene.render.resolution_percentage=100
for name,pos in [('front',(0,-30,500)),('side',(150,-210,380))]:
 cam_data.ortho_scale=480 if name=='side' else 400
 cam.location=pos;cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(O/(name+'.png'));bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(O/'peak_perfection.blend'))
print('REAL_TITLE_MESH_READY',len(ob.data.polygons),bounds,flush=True)
