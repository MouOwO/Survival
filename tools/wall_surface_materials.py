"""Weathered timber / masonry / metal surfaces, baked into each wall atlas.

Large grain, knots, splits and mineral patches survive strategy-camera mipmaps.
Roughness and normal detail derive from the same marks as the color, while
world-height grime and per-piece tint prevent a uniform tiled / plastic finish.
"""
import math
import bpy
import numpy as np
from wall_asset_spec import WEATHERING

SIZE=1024
METALS={'iron','brass','gold','bronze','copper','silver'}
GEMS={'crystal','purple','jade','azure','ruby'}

def field(rng,cells):
    """Periodic smooth value noise, without visible sine-wave bands."""
    grid=rng.random((cells,cells))
    axis=np.arange(SIZE,dtype=np.float32)*cells/SIZE
    index=axis.astype(int);t=axis-index;t=t*t*(3-2*t)
    a=grid[index[:,None]%cells,index[None,:]%cells]
    b=grid[index[:,None]%cells,(index[None,:]+1)%cells]
    c=grid[(index[:,None]+1)%cells,index[None,:]%cells]
    d=grid[(index[:,None]+1)%cells,(index[None,:]+1)%cells]
    return ((a*(1-t)+b*t)*(1-t[:,None])+(c*(1-t)+d*t)*t[:,None]).astype(np.float32)

def surface_maps(key,col,age):
    rng=np.random.default_rng(20260917+sum((i+1)*ord(c) for i,c in enumerate(key)))
    y,x=np.mgrid[0:SIZE,0:SIZE].astype(np.float32)/SIZE
    broad=field(rng,5);medium=field(rng,19);fine=field(rng,70)
    speck=rng.random(x.shape,dtype=np.float32)
    h=.5+.13*(medium-.5)+.025*(fine-.5)
    base=np.asarray(col,dtype=np.float32)
    # Desaturate old timber; keep advanced stone bright without electric paint.
    if key.startswith('wood'):
        base=base*(1-age*.23)+np.asarray((.31,.265,.205))*age*.23
    if key in ('azure','purple','jade','ruby'):
        base=base*.72+np.mean(base)*.28
    if key=='gold':base=np.asarray((.64,.43,.16))
    if key=='brass':base=np.asarray((.47,.34,.17))
    color=np.broadcast_to(base,(SIZE,SIZE,3)).copy()
    cavity=np.zeros_like(x);wear=np.zeros_like(x)
    rough=np.full_like(x,.8)
    if key.startswith('wood'):
        # Distort the growth lines around knots, not uniform stripes.
        warp=x+.018*np.sin(y*math.tau*2)+.018*(broad-.5)
        knot_dark=np.zeros_like(x)
        for cx,cy,rx,ry in ((.24,.31,.10,.18),(.73,.78,.074,.13)):
            dx=x-cx;dy=y-cy
            radius=np.sqrt((dx/rx)**2+(dy/ry)**2)
            knot=np.exp(-radius*radius*2.8)
            knot_dark=np.maximum(knot_dark,knot)
            warp+=.035*np.sin(np.arctan2(dy/ry,dx/rx))*np.exp(-radius*.9)
            h+=.025*np.cos(radius*28)*np.exp(-radius*.65)
        grain=warp*math.tau*10+.38*np.sin(y*math.tau*5)
        growth=(.5+.5*np.sin(grain))**9
        fibre=(.5+.5*np.sin(grain*2.4+medium*2))**14
        split=np.zeros_like(x)
        for _ in range(19):
            cx,cy=rng.random(2);length=rng.uniform(.06,.25)
            path=cx+.003*np.sin(y*37+rng.random()*8)+.006*(broad-.5)
            width=rng.uniform(.0018,.0060)
            crack=np.clip(1-np.abs(x-path)/width,0,1)*np.clip(1-np.abs(y-cy)/length,0,1)
            split=np.maximum(split,crack)
        cavity=np.clip(growth*.47+fibre*.16+split*.85+knot_dark*.70,0,1)
        wear=np.clip((broad-.42)*1.8,0,.6)*age
        h+=.07*np.sin(grain)-.13*growth-.15*split-.08*knot_dark
        color*=((.75+.48*broad+.20*(medium-.5))*(1-cavity*.69))[:,:,None]
        color=color*(1-wear[:,:,None]*.42)+np.asarray((.46,.39,.28))*wear[:,:,None]*.42
        rough=np.clip(.73+.18*age+.07*broad+.06*cavity-.12*wear,.64,.98)
        if key=='wood_end':
            radius=np.sqrt(((x-.47)*1.04)**2+((y-.52)*.97)**2)
            rings=(.5+.5*np.sin(radius*190+broad*3))**7
            angle=np.arctan2(y-.52,x-.47)
            checks=np.clip(1-np.abs(np.sin(angle*3+.29))/.024,0,1)*(radius>.16)
            cavity=np.clip(rings*.55+checks*.8,0,1)
            h=.52+.06*np.sin(radius*190+broad*3)-checks*.18
            color=np.broadcast_to(base,(SIZE,SIZE,3)).copy()*(.90+.22*broad-cavity*.57)[:,:,None]
    elif key.startswith('wall_') or key in ('stone','limestone','basalt'):
        # Broken mineral planes, weathered chips and occasional branching cracks.
        planes=np.floor(medium*7)/7
        cavity=np.clip((.40-medium)*3.1,0,.62)
        cracks=np.zeros_like(x)
        for _ in range(5):
            cx,cy=rng.random(2);slope=rng.uniform(-1.2,1.2)
            path=cx+slope*(y-cy)+.045*(broad-.5)+.009*(medium-.5)
            segment=np.clip(1-np.abs(y-cy)/rng.uniform(.15,.42),0,1)
            crack=np.clip(1-np.abs(x-path)/(.0018+.0024*age),0,1)*segment
            cracks=np.maximum(cracks,crack)
        chips=np.clip((.28-fine)*5,0,.6)*(.3+.7*age)
        cavity=np.clip(cavity*.6+cracks*(.4+.5*age)+chips*.45,0,1)
        h+=.10*(planes-.5)-.19*cracks-.08*chips
        color*=((.85+.30*broad+.12*(planes-.5))*(1-cavity*(.28+.15*age)))[:,:,None]
        mineral=np.clip((broad-.56)*2.2,0,.5)
        color=color*(1-mineral[:,:,None]*.28)+np.asarray((.52,.45,.31))*mineral[:,:,None]*.28
        wear=np.clip((fine-.7)*2.8,0,.45)*(.25+.75*age)
        color+=wear[:,:,None]*.13
        rough=np.clip(.77+.11*age+.12*cavity-.09*wear,.67,.98)
        if key=='wall_ivory':rough=np.clip(.56+.19*age+.15*cavity,.52,.82)
    elif key in METALS:
        tarnish=np.clip((.59-broad)*2.7,0,.85)*(.24+.76*age)
        pits=np.clip((.28-fine)*4.2,0,.75)*age
        scratches=np.zeros_like(x)
        for _ in range(28):
            cx,cy=rng.random(2)
            scratch=np.clip(1-np.abs(x-cx-(y-cy)*.12)/.0009,0,1)*np.clip(1-np.abs(y-cy)/.09,0,1)
            scratches=np.maximum(scratches,scratch)
        patina=np.asarray((.14,.255,.205) if key in ('bronze','copper','brass') else (.39,.235,.10) if key=='iron' else (.24,.23,.20))
        color*= (.83+.32*broad)[:,:,None]
        color=color*(1-tarnish[:,:,None]*.79)+patina*tarnish[:,:,None]*.79
        color+=scratches[:,:,None]*(.10+.08*age)
        h+=.022*(fine-.5)-.10*pits-.035*scratches
        rough=np.clip(.24+.39*tarnish+.20*pits+.05*age-.10*scratches,.17,.88)
        cavity=tarnish*.38+pits*.5
    elif key in GEMS:
        veins=np.clip(1-np.abs(medium-.51)/.023,0,1)
        color*= (.76+.41*broad)[:,:,None]
        color+=veins[:,:,None]*.055
        h=.5+.023*(medium-.5)+.012*veins
        rough=np.clip(.28+.14*age+.13*(1-broad),.23,.57)
    else:
        color*= (.84+.25*broad)[:,:,None]
    # Height map derivatives retain large-scale grain and small pits after baking.
    strength=11 if key.startswith('wood') else 8 if key.startswith('wall_') else 5
    dx=(np.roll(h,-1,1)-np.roll(h,1,1))*strength
    dy=(np.roll(h,-1,0)-np.roll(h,1,0))*strength
    normal=np.stack((-dx,-dy,np.ones_like(h)),axis=-1)
    normal/=np.linalg.norm(normal,axis=-1,keepdims=True)
    # Third map packs roughness and broad dirt: authored, not a uniform scalar.
    properties=np.stack((rough,np.clip((.62-broad)*3,0,1),cavity),axis=-1)
    return np.clip(color,.008,.9),normal*.5+.5,properties

def make_materials(palette,stage,height):
    age=WEATHERING[stage-1];materials={}
    for key,col in palette.items():
        m=bpy.data.materials.new(f'wall_author_{stage:02}_{key}');m.use_nodes=True
        nodes=m.node_tree.nodes;links=m.node_tree.links
        bs=nodes.get('Principled BSDF')
        maps=surface_maps(key,col,age);texnodes=[]
        for suffix,pixels in zip(('color','normal','surface'),maps):
            im=bpy.data.images.new(f'wall_surface_{stage:02}_{key}_{suffix}',SIZE,SIZE,alpha=True)
            im.colorspace_settings.name='sRGB' if suffix=='color' else 'Non-Color'
            rgba=np.concatenate((pixels,np.ones((SIZE,SIZE,1),dtype=np.float32)),axis=-1).astype(np.float32)
            im.pixels.foreach_set(rgba.ravel());im.pack()
            tex=nodes.new('ShaderNodeTexImage');tex.image=im;texnodes.append(tex)
        color,normal,surface=texnodes
        nm=nodes.new('ShaderNodeNormalMap');nm.uv_map='SurfaceUV'
        links.new(normal.outputs['Color'],nm.inputs['Color']);links.new(nm.outputs[0],bs.inputs['Normal'])
        separate=nodes.new('ShaderNodeSeparateColor');links.new(surface.outputs['Color'],separate.inputs[0]);links.new(separate.outputs[0],bs.inputs['Roughness'])
        tint=nodes.new('ShaderNodeVertexColor');tint.layer_name='WallPieceTint'
        multiply=nodes.new('ShaderNodeMixRGB');multiply.blend_type='MULTIPLY';multiply.inputs[0].default_value=1
        links.new(color.outputs['Color'],multiply.inputs[1]);links.new(tint.outputs['Color'],multiply.inputs[2])
        # Ground splash/moss gathers at the wall foot. Higher stages retain less.
        geometry=nodes.new('ShaderNodeNewGeometry');xyz=nodes.new('ShaderNodeSeparateXYZ');links.new(geometry.outputs['Position'],xyz.inputs[0])
        ramp=nodes.new('ShaderNodeMapRange');ramp.clamp=True
        ramp.inputs['From Min'].default_value=0;ramp.inputs['From Max'].default_value=height*.36
        ramp.inputs['To Min'].default_value=.16+.48*age;ramp.inputs['To Max'].default_value=0
        links.new(xyz.outputs['Z'],ramp.inputs['Value'])
        mask=nodes.new('ShaderNodeMath');mask.operation='MULTIPLY';links.new(ramp.outputs[0],mask.inputs[0]);links.new(separate.outputs[1],mask.inputs[1])
        dirt=nodes.new('ShaderNodeMixRGB');links.new(mask.outputs[0],dirt.inputs[0]);links.new(multiply.outputs[0],dirt.inputs[1])
        dirt.inputs[2].default_value=(.13,.16,.061,1) if key not in METALS|GEMS else (.15,.12,.075,1)
        links.new(dirt.outputs[0],bs.inputs['Base Color'])
        materials[key]=m
    return materials

def project_surfaces(obj,parts,stage):
    """Follow each timber's long axis; vary masonry per block, not per triangle."""
    from mathutils import Vector
    uv=obj.data.uv_layers['SurfaceUV']
    tint=obj.data.color_attributes.new(name='WallPieceTint',type='FLOAT_COLOR',domain='CORNER')
    rng=np.random.default_rng(4900+stage);age=WEATHERING[stage-1]
    for v0,v1,f0,f1,key in parts:
        coords=np.array([obj.data.vertices[i].co[:] for i in range(v0,v1)])
        center=coords.mean(axis=0)
        _,axes=np.linalg.eigh(np.cov(coords.T));long_axis=Vector(axes[:,-1])
        variation=rng.uniform(.76,1.08) if key.startswith('wood') else rng.uniform(.84,1.06)
        warmth=rng.uniform(-.04,.04)*(.3+age)
        offset=rng.uniform(0,4,2)
        for face in list(obj.data.polygons)[f0:f1]:
            axis=max(range(3),key=lambda i:abs(face.normal[i]));other=[i for i in range(3) if i!=axis]
            wooden=key in ('wood','wood_light')
            end=wooden and abs(face.normal.dot(long_axis))>.85
            if end:face.material_index=list(obj.data.materials).index(obj.data.materials['wall_author_%02d_wood_end'%stage])
            across=face.normal.cross(long_axis).normalized()
            for loop in face.loop_indices:
                p=obj.data.vertices[obj.data.loops[loop].vertex_index].co
                if end:
                    extent=np.maximum(np.ptp(coords,axis=0),1)
                    uv.data[loop].uv=((p[other[0]]-center[other[0]])/extent[other[0]]+.5,(p[other[1]]-center[other[1]])/extent[other[1]]+.5)
                elif wooden:
                    uv.data[loop].uv=(p.dot(across)/29+offset[0],p.dot(long_axis)/235+offset[1])
                else:
                    uv.data[loop].uv=(p[other[0]]/58+offset[0],p[other[1]]/58+offset[1])
                tint.data[loop].color=(variation+warmth,variation,variation-warmth,1)
