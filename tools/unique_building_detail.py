"""Second art pass: authored surface maps, UVs and building-specific construction detail."""
import bpy
import math
import numpy as np
from mathutils import Vector

def prepare_materials(materials, palette, directory, modeled_surfaces=False):
    size=512
    y,x=np.mgrid[0:size,0:size]/size
    rng=np.random.default_rng(160926)
    for key,m in materials.items():
        grain=rng.random((size,size))-.5
        broad=np.sin(x*math.tau*3+.8*np.sin(y*math.tau*2))*np.cos(y*math.tau*4)
        h=.48+grain*.10+broad*.065
        if key.startswith('wood'):
            wave=x*math.tau*7+1.2*np.sin(y*math.tau*2)+.4*np.sin(y*math.tau*5)
            h=.5+np.sin(wave)*.12+np.sin(wave*2)*.045+grain*.055
            if modeled_surfaces:
                wave=x*math.tau*21+.65*np.sin(y*math.tau*2)
                h=.5+np.sin(wave)*.045+np.sin(wave*2)*.018+grain*.04
        elif key in ('slate','teal'):
            h=.5+grain*.06+np.sin(x*math.tau*9+np.sin(y*math.tau*4))*.05+broad*.08
        elif key in ('brass','gold'):
            h=.5+grain*.045+np.sin(y*math.tau*71)*.017+broad*.025
        elif key in ('red','wheat','green'):
            h=.5+grain*.045+np.sin(x*math.tau*110)*np.sin(y*math.tau*110)*.018
        if key in ('stone','basalt','limestone','ivory') and not modeled_surfaces:
            # Broad broken stone joints survive the RTS camera's texture mips.
            px=(x*3+.08*np.sin(y*math.tau*3))%1
            py=(y*2+.05*np.sin(x*math.tau*4))%1
            seam=(np.minimum(px,1-px)<.035)|(np.minimum(py,1-py)<.032)
            h=.54+broad*.12+grain*.025-seam*.19
        if key in ('slate','teal') and not modeled_surfaces:
            seam=np.minimum((y*4)%1,1-(y*4)%1)<.025
            h=.54+broad*.08+grain*.02-seam*.16
        color=np.clip(np.array(palette[key])[None,None,:]*(.65+h[:,:,None]*.65),0,1)
        color*=np.clip(.8+(h[:,:,None]-.3)*.65,.58,1.12)
        # Soft, sparse mineral flecks / weathering; avoids painted black outlines.
        if key in ('stone','basalt','limestone','ivory','earth'):
            color*=np.where(grain[:,:,None]>.43,.86,1)
        strength=2.5 if modeled_surfaces else 7
        dx=(np.roll(h,-1,1)-np.roll(h,1,1))*strength
        dy=(np.roll(h,-1,0)-np.roll(h,1,0))*strength
        normal=np.stack((-dx,-dy,np.ones_like(h)),axis=-1)
        normal/=np.linalg.norm(normal,axis=-1,keepdims=True)
        normal=normal*.5+.5
        reflect=np.full((size,size,3),.32 if key in ('brass','gold') else .035)
        maps={}
        for suffix,data in [('color',color),('normal',normal),('reflectance',reflect)]:
            im=bpy.data.images.new(key+'_'+suffix,width=size,height=size,alpha=True)
            im.colorspace_settings.name='sRGB' if suffix=='color' else 'Non-Color'
            rgba=np.concatenate((data,np.ones((size,size,1))),axis=-1).astype(np.float32)
            im.pixels.foreach_set(rgba.ravel());im.filepath_raw=str(directory/(key+'_'+suffix+'.png'));im.file_format='PNG';im.save()
            maps[suffix]=im
        bs=m.node_tree.nodes.get('Principled BSDF')
        tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=maps['color']
        m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
        tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=maps['normal']
        n=m.node_tree.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=1
        m.node_tree.links.new(tex.outputs['Color'],n.inputs['Color']);m.node_tree.links.new(n.outputs['Normal'],bs.inputs['Normal'])
        bs.inputs['Roughness'].default_value=.42 if key in ('brass','gold','blue') else .82
        stem='materials/survival_buildings/'+key
        (directory/(key+'.vmat')).write_text('"Layer0"\n{\n "shader" "global_lit_simple.vfx"\n "F_NORMAL_MAP" "1"\n "F_SPECULAR" "1"\n "TextureColor" "'+stem+'_color.png"\n "TextureNormal" "'+stem+'_normal.png"\n "TextureReflectance" "'+stem+'_reflectance.png"\n "g_vColorTint" "[1 1 1 0]"\n}\n')

def project_uv(o):
    # FBX exports the first layer. Never leave primitive UVMap before SurfaceUV.
    while o.data.uv_layers:o.data.uv_layers.remove(o.data.uv_layers[0])
    uv=o.data.uv_layers.new(name='SurfaceUV')
    uv.active_render=True
    for face in o.data.polygons:
        axis=max(range(3),key=lambda i:abs(face.normal[i]))
        axes=[i for i in range(3) if i!=axis]
        for loop in face.loop_indices:
            p=o.data.vertices[o.data.loops[loop].vertex_index].co
            uv.data[loop].uv=(p[axes[0]]/36,p[axes[1]]/36)

def refine(name,g):
    box,beam,cone,ring,mesh=[g[k] for k in ('box','beam','cone','ring','mesh')]
    def bolt(x,y,z,r=.65):
        o=cone('Forged rivet',(x,y,z),r,r,.65,'brass',8);o.rotation_euler.x=math.pi/2
    def blocks(cx,cy,w,h,z,side=False):
        for row in range(int(h/7)):
            for col in range(int(w/12)):
                q=-w/2+6+col*12+(3 if row%2 else 0)
                if q+6>w/2:continue
                c=(cx,cy+q,z+row*7) if side else (cx+q,cy,z+row*7)
                box('Individual dressed masonry',c,(1.2,11.4,6.3) if side else (11.4,1.2,6.3),'stone',.25)
    def barrel(x,y,z=9,r=5):
        cone('Coopered barrel',(x,y,z+7),r*.88,r,14,'wood',12)
        for zz in (z+2,z+11):ring('Iron barrel hoop',(x,y,zz),r,.55,'basalt')
        cone('Barrel lid',(x,y,z+14),r*.9,r*.9,.8,'wood_light',12)
        for dx in (-2,2):beam('Barrel lid seam',(x+dx,y-r*.65,z+14.5),(x+dx,y+r*.65,z+14.5),.25,'wood')
    def lantern(x,y,z):
        beam('Lantern bracket',(x,y+4,z+4),(x,y,z+4),.7,'basalt')
        box('Lantern warm glass',(x,y,z),(3,3,6),'gold',.3)
        for dx in (-1.8,1.8):beam('Lantern iron cage',(x+dx,y-1.8,z-3),(x+dx,y-1.8,z+3),.5,'basalt')
        cone('Lantern hood',(x,y,z+4),3,1,2,'basalt',4)
    # Cut paving blocks replace the broad unbroken slab appearance.
    round_base=name in ('hero_altar','challenge_arena')
    for ix in range(-4,5):
        for iy in range(-4,5):
            x,y=ix*12.5,iy*12.5
            if round_base and x*x+y*y>49**2:continue
            box('Cut foundation paver',(x,y,8.65),(12,12,.9),'limestone',.18)
    for x in (-51,51):
        for y in (-51,51):
            if not round_base:box('Foundation corner cap',(x,y,9.4),(12,12,1),'basalt',.3)
    if 'research_lab' in name:
        blocks(36.5,8,59,35,18,True);blocks(-36.5,8,59,35,18,True)
        blocks(0,40.7,67,35,18)
        for x in (-34,34):
            for y in (-22,38):
                for z in (17,35,48):box('Buttress collar',(x,y,z),(10,11,2),'basalt',.3)
        for x in (-22,0,22):
            box('Window projecting sill',(x,-28,22),(16,5,2),'ivory')
            for z in (30,37):beam('Leaded window crosspiece',(x-5,-27,z),(x+5,-27,z),.65,'brass')
        for i in range(16):
            a=i*math.tau/16
            x,y=29.5*math.cos(a),10+29.5*math.sin(a)
            beam('Observatory vertical rib',(x,y,55),(x,y,75),1.4,'brass')
            x,y=31*math.cos(a),10+31*math.sin(a)
            beam('Copper dome radial seam',(x,y,77.8),(14*math.cos(a),10+14*math.sin(a),86.8),.85,'brass')
        for i in range(24):
            a=i*math.tau/24
            beam('Astrolabe etched graduation',(24*math.cos(a),8.2,115+24*math.sin(a)),(26*math.cos(a),8.2,115+26*math.sin(a)),.7,'blue')
        for x in (-47,47):
            for z in (14,26,39,53):ring('Spire ashlar course',(x,25,z),10,.45,'basalt')
            for z,r in ((62,12),(69,8.5),(76,4.5)):ring('Spire roof course',(x,25,z),r,.55,'brass')
        # Functional desk: open pages, binding, quill and stacked books.
        for x in (-4.8,4.8):
            p=box('Open book page',(x,-40,29),(9,13,.65),'ivory',.1);p.rotation_euler.y=math.copysign(.12,x)
            for yy in range(-44,-35,2):beam('Inscribed page line',(x-3,yy,29.8),(x+3,yy,29.8),.2,'wood')
        for i in range(3):box('Stack of research tomes',(22,-35,11+i*2.1),(10,12,1.8),'slate' if i%2 else 'red',.15)
        for x in (-31,31):lantern(x,-28,43)
        if name.startswith('advanced'):
            for x in (-45,45):
                for z in (28,37,46):ring('Arcane conduit collar',(x,25,z),11,.7,'brass')
    elif name=='gold_mine':
        # Rougher rock surface with deliberately asymmetric displacement.
        for o in list(g['parts']):
            if o.name.startswith('Faceted ore rock'):
                mod=o.modifiers.new('Chiseled strata','SUBSURF');mod.subdivision_type='SIMPLE';mod.levels=1
                bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)
                for v in o.data.vertices:
                    p=v.co;v.co*=1+.045*math.sin(p.x*32+p.y*17+p.z*43)
        for x in (-23,23):
            for z in (17,44):
                for dx in (-2,2):bolt(x+dx,-30,z)
            beam('Portal diagonal brace',(x,-30,41),(x*.5,-30,51),3,'wood')
        for yy in (-50,-44,-38):box('Cart board joint',(0,yy,22),(24,.4,.7),'basalt',0)
        for x in (-11,11):
            for yy in (-50,-36):box('Cart iron corner',(x,yy,23),(2,2,13),'basalt',.1)
        for x in (-13,13):
            for yy in (-49,-37):
                for a in (0,math.pi/3,2*math.pi/3):beam('Wheel spokes',(x,yy-3*math.cos(a),14-3*math.sin(a)),(x,yy+3*math.cos(a),14+3*math.sin(a)),.65,'brass')
        for i in range(10):ring('Hoist chain link',(14,33,66+i*1.8),1.1,.3,'basalt',(math.pi/2,0,(i%2)*math.pi/2))
        barrel(-40,-36);barrel(39,-33,r=6)
        lantern(-29,-30,40);lantern(29,-30,40)
        beam('Pickaxe handle',(-42,-45,10),(-31,-45,32),1.1,'wood_light')
        beam('Pickaxe head',(-39,-45,30),(-26,-45,27),1.5,'basalt')
        for i in range(8):cone('Ore rubble',(-47+i*5,-3+(i%3)*5,10),2+i%3,1,3,'stone',7)
    elif name=='population_farm':
        blocks(-18,48.6,53,28,16);blocks(-45.7,17,59,28,16,True)
        # Each overlapping shingle is real geometry, follows the roof slope.
        for side in (-1,1):
            for row in range(6):
                t=(row+.5)/6
                for col in range(10):
                    yy=-16+col*7+(1 if row%2 else 0)
                    xx=-18+side*32.5*(1-t)
                    o=box('Overlapping roof shingle',(xx,yy,46+27*t+.6),(7.7,6.65,.85),'teal' if (row+col)%4 else 'slate',.2)
                    o.rotation_euler.y=side*math.atan2(27,32.5)
        for x in (-28,-8):
            for z in (18,32):box('Barn hinge strap',(x,-17.8,z),(5,1,1.5),'basalt',.15);bolt(x,-18.5,z,.45)
        for x in (-20,-16):ring('Barn door iron pull',(x,-18,25),1,.3,'basalt',(math.pi/2,0,0))
        for i in range(16):
            a=i*math.tau/16;beam('Silo stave seam',(39+15.1*math.cos(a),29+15.1*math.sin(a),12),(39+15.1*math.cos(a),29+15.1*math.sin(a),50),.35,'wood')
        for z in range(15,51,6):beam('Silo ladder rung',(28,13,z),(34,13,z),.8,'wood_light')
        for x in (27,35):beam('Silo ladder rail',(x,13,9),(x,13,53),1,'wood')
        for y in (-39,-30,-21,-12):
            for x in (16,28,40):
                for z in (21,24):
                    for side in (-1,1):beam('Wheat grain',(x,y,z),(x+side*2,y+1,z+2),.75,'gold')
        for x in (-52,52):
            for y in (-45,-15,15,46):bolt(x,y-1,19,.5)
        lantern(-38,-19,34);barrel(-40,-34,r=4)
    elif name=='hero_altar':
        for i in range(16):
            a=i*math.tau/16
            for r in (22,):
                x,y=r*math.cos(a),3+r*math.sin(a)
                beam('Inlaid sacred rune',(x,y,23.8),(x+2*math.cos(a+.7),y+2*math.sin(a+.7),23.8),.65,'blue')
            beam('Radial stone joint',(32*math.cos(a),3+32*math.sin(a),19),(38*math.cos(a),3+38*math.sin(a),19),.3,'basalt')
        for x in (-37,37):
            for i in range(8):
                a=i*math.tau/8;beam('Fluted pillar',(x+7.15*math.cos(a),24+7.15*math.sin(a),17),(x+7.15*math.cos(a),24+7.15*math.sin(a),59),.7,'limestone')
            for z in (18,57,60):ring('Pillar carved fillet',(x,24,z),7.8,.65,'brass')
        for z in range(90,103,2):ring('Sword leather grip wrap',(0,3,z),3.15,.4,'brass')
        for side in (-1,1):
            for i in range(4):
                a=(side*12,21,55-i*6);b=(side*(32+i*5),21,88-i*10)
                # Tapered feather volumes replace rectangular ray silhouettes.
                for o in list(g['parts']):
                    if o.name.startswith('Radiant wing'):
                        g['parts'].remove(o);bpy.data.objects.remove(o,do_unlink=True)
                v=Vector(b)-Vector(a)
                o=cone('Carved wing feather',(Vector(a)+Vector(b))/2,2.5,.3,v.length,'ivory',6)
                o.rotation_euler=v.to_track_quat('Z','Y').to_euler()
            for x in (side*20,):
                cone('Votive candle',(x,-24,24),1.2,1.2,8,'ivory',10)
                g['crystal']((x,-24,28),.8,3,'gold')
    else:
        for i in range(19):
            a=-math.pi/4+i*math.tau/24
            for z in (17,25,33):
                x,y=54.2*math.cos(a),54.2*math.sin(a)
                o=box('Arena masonry course',(x,y,z),(12.8,1.4,6.8),'stone',.25);o.rotation_euler.z=a+math.pi/2
            for r,z in ((44,14),(40,18),(36,22)):
                if 0<a<math.pi:
                    o=box('Tiered arena seating',(r*math.cos(a),r*math.sin(a),z),(11,5,3),'limestone',.3);o.rotation_euler.z=a+math.pi/2
        for x in (-33,33):
            for z in (16,24,32,40,48):
                box('Gate dressed stone course',(x,-43,z),(19,1.5,6.8),'stone',.3)
            box('Tower recessed arrow slit',(x,-44,40),(3,1,12),'shadow',.2)
            lantern(x,-45,24)
        for x in (-21,21):
            for a in range(8):
                q=a*math.tau/8
                beam('Brazier crown tine',(x+7*math.cos(q),-9+7*math.sin(q),31),(x+8*math.cos(q),-9+8*math.sin(q),37),.65,'basalt')
        for a in range(12):
            q=a*math.tau/12
            beam('Arena inlay',(20*math.cos(q),20*math.sin(q),13),(24*math.cos(q),24*math.sin(q),13),.7,'gold')
    # Give the banner cloth a gentle wave and stitched hem with volume.
    for o in list(g['parts']):
        if o.name.startswith('Pennant'):
            for v in o.data.vertices:v.co.y+=.8*math.sin(v.co.z*.24+v.co.x*.1)
