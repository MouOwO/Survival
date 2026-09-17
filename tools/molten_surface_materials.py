"""Matched albedo/normal/roughness for non-emissive basalt, aged copper and cooled lava."""
import numpy as np
from wall_surface_materials import surface_maps,field,SIZE

def mineral_cells(seed,cells=6):
    rng=np.random.default_rng(seed);y,x=np.mgrid[0:SIZE,0:SIZE].astype(np.float32)/SIZE
    nearest=np.full_like(x,10);second=nearest.copy();tone=np.zeros_like(x)
    for j in range(cells):
        for i in range(cells):
            cx,cy=(i+rng.uniform(.16,.84))/cells,(j+rng.uniform(.16,.84))/cells
            dx=np.abs(x-cx);dy=np.abs(y-cy);dx=np.minimum(dx,1-dx);dy=np.minimum(dy,1-dy)
            d=np.sqrt(dx*dx+dy*dy);closer=d<nearest
            second=np.where(closer,nearest,np.minimum(second,d));nearest=np.minimum(nearest,d)
            tone=np.where(closer,rng.uniform(.15,.85),tone)
    return np.clip(1-(second-nearest)/.009,0,1),tone

def room_surface_maps(key,col,age=.75):
    rocky=key.startswith('stone')or key in('rock','charred')
    source='wall_basalt_'+key if rocky else 'bronze'if key=='patina' else key
    color,normal,props=surface_maps(source,col,age)
    rng=np.random.default_rng(75000+sum(ord(c)for c in key));broad=field(rng,8);fine=field(rng,96)
    if rocky or key=='lava':
        seam,tone=mineral_cells(1800+sum(ord(c)for c in key),6 if rocky else 8)
        pores=np.clip((.26-fine)*6,0,.75)
        if key=='lava':
            # Warm color only: cooled crust and restrained terracotta cracks.
            color=np.broadcast_to(np.asarray((.14,.135,.13)),color.shape).copy()*(.72+.45*tone)[:,:,None]
            hot=np.clip(seam*1.8,0,1)
            color=color*(1-hot[:,:,None])+np.asarray(col)*hot[:,:,None]
            props[:,:,0]=.78-.20*hot
            h=.5-seam*.12+tone*.028
        else:
            color*=((.90+.18*tone)*(1-seam*.33-pores*.22))[:,:,None]
            worn=np.clip(1-np.abs(seam-.18)/.18,0,1)*.028
            color+=worn[:,:,None]*np.asarray((1.0,.88,.72))
            h=.5-seam*.10-pores*.055+tone*.024
            props[:,:,0]=np.clip(props[:,:,0]+pores*.06,.65,.97)
        dx=(np.roll(h,-1,1)-np.roll(h,1,1))*7;dy=(np.roll(h,-1,0)-np.roll(h,1,0))*7
        n=(normal*2-1);n[:,:,0]-=dx;n[:,:,1]-=dy;n/=np.linalg.norm(n,axis=-1,keepdims=True)
        normal=n*.5+.5
    elif key=='patina':
        mask=np.clip((broad-.3)*2.8,0,.87)
        color=color*(1-mask[:,:,None])+np.asarray(col)*mask[:,:,None]
        props[:,:,0]=np.clip(.42+.36*mask,.35,.88)
    elif key in('ash','earth'):
        color*= (.8+.35*broad)[:,:,None];props[:,:,0]=.96
    elif key=='teal':props[:,:,0]=.66+.18*broad
    return np.clip(color,.008,.88),normal,props
