"""Exterior-only, non-emissive biome dressing for the ten square realms.

The arena and shoreline belong to ten_realm_geometry.  This module adds only
small authored assemblies; none provide navigation or collision.  All placement
centres are outside the 700-square wall, and each assembly's bounding rectangle
stays outside the 616-square combat keep-out.  Dense foliage is confined to a
few silhouettes, leaving large, readable stretches of shoreline between them.
"""
import math
import random

from mathutils import Matrix, Vector


TAU = math.tau
KEEP_OUT = 308.5
MAX_EXTENT = 579.0


def _place(k, label, fn, xy, scale=1.0, angle=0.0, z=None, top=None):
    """Place one local assembly and retain its actual bounds for validation."""
    x, y = xy
    assert max(abs(x), abs(y)) > 365, (label, xy)
    z = k.shore_height(x, y) if z is None else z
    v0, f0 = len(k.v), len(k.f)
    k.place(fn, (x, y, z), scale=scale, angle=angle)
    if len(k.v) == v0:
        return
    if top is not None:
        # Major silhouettes are measured against the arena floor, even where
        # their roots sit on a descending shore. Keep their horizontal spread
        # unchanged, and preserve fibre directions under the vertical stretch.
        old_top=max(p[2]for p in k.v[v0:])
        factor=(top-z)/max(.01,old_top-z)
        k.v[v0:]=[(px,py,z+(pz-z)*factor)for px,py,pz in k.v[v0:]]
        for index in range(f0,len(k.f)):
            axis=k.grain_axis[index]
            if axis is not None:
                k.grain_axis[index]=tuple(Vector((axis[0],axis[1],axis[2]*factor)).normalized())
    bounds = [[min(p[i] for p in k.v[v0:]) for i in range(3)],
              [max(p[i] for p in k.v[v0:]) for i in range(3)]]
    # A large tree crown may lean toward the walls. Move the whole assembly,
    # including its roots, outward instead of cropping or flattening branches.
    if not any(bounds[0][i] >= KEEP_OUT or bounds[1][i] <= -KEEP_OUT for i in (0, 1)):
        axis = 0 if abs(x) >= abs(y) else 1
        sign = 1 if (x, y)[axis] >= 0 else -1
        delta = KEEP_OUT-bounds[0][axis] if sign > 0 else -KEEP_OUT-bounds[1][axis]
        k.v[v0:] = [tuple(v+delta if i == axis else v for i, v in enumerate(p))
                    for p in k.v[v0:]]
        bounds[0][axis] += delta
        bounds[1][axis] += delta
    assert all(-MAX_EXTENT <= bounds[0][i] <= bounds[1][i] <= MAX_EXTENT for i in (0, 1)), (label, bounds)
    assert any(bounds[0][i] >= KEEP_OUT or bounds[1][i] <= -KEEP_OUT for i in (0, 1)), (label, bounds)
    if not hasattr(k, 'dressing_elements'):
        k.dressing_elements = []
    k.dressing_elements.append(dict(label=label, center=[x, y, z], bounds=bounds,
                                    vertices=[v0, len(k.v)], faces=[f0, len(k.f)],
                                    collision=False, emissive=False))


def _tube(k, points, radii, mat='bark', sides=8):
    """Continuous tapered branch: a single faceted tube, no joint spheres."""
    points = [Vector(p) for p in points]
    verts = []
    for i, p in enumerate(points):
        tangent = points[min(i+1, len(points)-1)]-points[max(0, i-1)]
        tangent.normalize()
        guide = Vector((0, 0, 1)) if abs(tangent.z) < .88 else Vector((0, 1, 0))
        u = tangent.cross(guide).normalized()
        v = tangent.cross(u).normalized()
        verts.extend(p+(u*math.cos(j*TAU/sides)+v*math.sin(j*TAU/sides))*radii[i]
                     for j in range(sides))
    faces = [tuple(reversed(range(sides))),
             tuple(range((len(points)-1)*sides, len(points)*sides))]
    faces += [(r*sides+j, r*sides+(j+1)%sides,
               (r+1)*sides+(j+1)%sides, (r+1)*sides+j)
              for r in range(len(points)-1) for j in range(sides)]
    first = len(k.f)
    k.mesh(verts, faces, mat)
    if mat in ('bark', 'wood', 'wood_light'):
        # End cuts have their own radial grain; curved side faces inherit the
        # local segment's fibre direction instead of a single vertical axis.
        k.grain_since(first, points[1]-points[0])
        for row in range(len(points)-1):
            direction = tuple((points[row+1]-points[row]).normalized())
            for j in range(sides):
                k.grain_axis[first+2+row*sides+j] = direction


def _blade(k, a, b, width, mat='leaf', curl=1.0):
    """A ridged, thin solid leaf, visible from both sides in Source 2."""
    a, b = Vector(a), Vector(b)
    d = b-a
    u = d.cross(Vector((0, 0, 1)))
    if u.length < .001:
        u = Vector((1, 0, 0))
    u.normalize()
    mid = a+d*.46
    ridge = mid+Vector((0, 0, width*.15*curl))
    top = [a, mid-u*width*.5, b, mid+u*width*.5, ridge]
    normal = (top[1]-a).cross(b-a).normalized()*.20
    verts = top+[p-normal for p in top]
    faces = [(0,1,4),(1,2,4),(2,3,4),(3,0,4),
             (9,6,5),(9,7,6),(9,8,7),(9,5,8),
             (0,5,6,1),(1,6,7,2),(2,7,8,3),(3,8,5,0)]
    k.mesh(verts, faces, mat)


def _roots(k, rng, count=6, reach=55, mat='bark'):
    for i in range(count):
        a = i*TAU/count+rng.uniform(-.18, .18)
        r = reach*rng.uniform(.65, 1)
        _tube(k, [(0,0,18),(math.cos(a)*r*.35,math.sin(a)*r*.35,8),
                  (math.cos(a+.1)*r*.75,math.sin(a+.1)*r*.75,2),
                  (math.cos(a+.2)*r,math.sin(a+.2)*r,-1)],
              [6,4,2,.55], mat, 6)


def _dead_tree(k, rng, marsh=False, size=1.0):
    trunk = [(0,0,0),(-9,-3,46),(7,1,101),(-5,8,158),(6,3,211),(0,12,264)]
    trunk = [tuple(v*size for v in p) for p in trunk]
    _tube(k, trunk, [13*size,11*size,8*size,6*size,3*size,.7*size])
    _roots(k, rng, 7 if marsh else 9, 54*size)
    for i in range(8):
        a = i*2.399
        height = (78+(i%4)*35)*size
        reach = (47 if marsh else 65)*size*rng.uniform(.65, 1)
        origin = (0, 3, height)
        tip = (math.cos(a)*reach, math.sin(a)*reach, height+48*size)
        mid = (tip[0]*.65, tip[1]*.65, height+13*size)
        _tube(k, [origin, mid, tip], [4.8*size,2.3*size,.5], 'bark', 6)
        branch = (mid[0]+math.cos(a+.7)*reach*.35,
                  mid[1]+math.sin(a+.7)*reach*.35, height+64*size)
        _tube(k, [mid, branch], [2*size,.3], 'wood', 6)


def _broad_tree(k, rng, blossom=False):
    _tube(k, [(0,0,0),(-8,2,51),(4,0,112),(-3,8,177),(12,5,211)],
          [17,14,10,6,3])
    _roots(k, rng, 8, 59)
    colors = ('pink','pink_light','pink_light') if blossom else ('leaf','leaf_light','leaf_dark')
    # Separate branch clusters preserve open holes in the canopy silhouette.
    for j in range(8):
        a = j*2.399
        reach = 38+(j%3)*15
        tip = Vector((math.cos(a)*reach, math.sin(a)*reach, 199+(j%3)*18))
        _tube(k, [(0,0,129+(j%3)*15), tip*.70+Vector((0,0,36)), tip], [6,3,.8])
        # Unequal leaf counts and heights keep the canopy's clustered gaps.
        count=44 if j%3 else 31
        for i in range(count):
            q = i*2.399+a
            r = 29*math.sqrt((i+.5)/count)
            p = tip+Vector((math.cos(q)*r, math.sin(q)*r*.77, rng.uniform(-13,14)))
            extent = 9 if blossom else 15
            direction = Vector((math.cos(q)*extent,math.sin(q)*extent,rng.uniform(-3,6)))
            _blade(k, p, p+direction, 7 if blossom else 10, rng.choice(colors))
            if blossom and i%3 == 0:
                _blade(k, p-Vector((4,0,0)), p+Vector((5,0,2)), 7, 'pink_light')


def _palm(k, rng):
    path = [(0,0,0),(5,2,61),(0,4,133),(10,8,194),(17,9,243)]
    _tube(k, path, [9,8,7,5.5,4], 'bark', 9)
    for i in range(17):
        z = i*14+6
        a,b=next((a,b)for a,b in zip(path,path[1:])if a[2]<=z<=b[2])
        t=(z-a[2])/(b[2]-a[2]);center=tuple(a[n]+(b[n]-a[n])*t for n in range(3))
        k.ring(center, 8.6-z*.018, .65, 'wood_light', n=10)
    top = Vector(path[-1])
    for j in range(9):
        a = j*TAU/9
        radial = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-radial.y, radial.x, 0))
        reach = rng.uniform(58,77)
        points = [top+radial*reach*t+Vector((0,0,27*math.sin(t*math.pi)-t*18)) for t in (0,.25,.5,.75,1)]
        _tube(k, points, [1.8,1.5,1.1,.7,.25], 'leaf_dark', 5)
        for i in range(1,11):
            t = i/12
            p = top+radial*reach*t+Vector((0,0,27*math.sin(t*math.pi)-t*18))
            for s in (-1,1):
                _blade(k, p, p+side*s*(21*(1-t)+6)+radial*9-Vector((0,0,5)),
                       5.4*(1-t*.55), 'leaf' if j%3 else 'leaf_light')


def _dry_shrub(k, rng, green=False):
    for i in range(9):
        a = i*2.399
        p = Vector((math.cos(a)*rng.uniform(12,23),math.sin(a)*rng.uniform(12,23),rng.uniform(17,34)))
        _tube(k, [(0,0,0),p*.55,p], [1.5,.9,.2], 'wood_light', 5)
        _tube(k, [p*.58,p*.6+Vector((math.cos(a+.8)*11,math.sin(a+.8)*11,8))], [.65,.16], 'wood', 5)
        if green:
            for side in (-1,1):
                _blade(k, p*.7, p*.7+Vector((math.cos(a+side)*12,math.sin(a+side)*12,3)), 6, 'leaf_dark')


def _reeds(k, rng):
    for i in range(17):
        a = i*2.399
        r = rng.uniform(2,19)
        x,y = math.cos(a)*r,math.sin(a)*r
        h = rng.uniform(24,65)
        _tube(k, [(x,y,0),(x+3,y,h*.6),(x+5,y+2,h)], [1,.7,.35], 'leaf_dark', 5)
        for s in (-1,1):
            _blade(k,(x,y,h*.2),(x+s*17,y+5,h*.68),3.2,'leaf_light')
        if i%3 == 0:
            k.cone((x+5,y+2,h-4),2,1.7,11,'wood',7)


def _stump(k, rng):
    n = 12
    verts=[]
    heights=[rng.uniform(30,48) for _ in range(n)]
    for radius,z0 in ((21,0),(18,None),(11,None),(9,17)):
        for j in range(n):
            a=j*TAU/n
            z=heights[j] if z0 is None else z0
            verts.append((math.cos(a)*radius,math.sin(a)*radius,z))
    faces=[]
    for row in range(3):
        faces += [(row*n+j,row*n+(j+1)%n,(row+1)*n+(j+1)%n,(row+1)*n+j)for j in range(n)]
    faces.append(tuple(range(3*n,4*n)))
    first=len(k.f);k.mesh(verts,faces,'bark');k.grain_since(first,(0,0,1))
    for j in range(n):k.m[first+n+j]=k.keys.index('wood_end')
    k.m[-1]=k.keys.index('peat')
    _roots(k,rng,5,37)


def _strata(k, rng, desert=False):
    dark,light=('sandstone','sandstone_light')if desert else('redstone','redstone_light')
    base=rng.uniform(73,90)
    z=0
    for row in range(7 if desert else 8):
        h=rng.uniform(20,29)
        width=base*(1-row*(.072 if desert else .067))
        c=(math.sin(row*.8)*5,math.cos(row*.9)*3,z+h/2)
        k.rock(c,(width,width*.70,h+7),dark)
        # Weathered bed planes are geometry; not bright painted lava seams.
        if row%2==0:k.rock((c[0],c[1],z+h-1),(width*1.02,width*.73,5),light)
        z+=h*.84
    for i in range(3):
        k.rock((rng.uniform(-37,37),rng.uniform(-27,27),8),(25,19,19),dark)


def _cedar(k, rng):
    _tube(k,[(0,0,0),(0,1,128),(3,0,263)],[10,5,.6],'bark',8)
    for level in range(9):
        z=53+level*24
        reach=65-level*6.0
        for j in range(9):
            a=j*TAU/9+level*.39
            r=reach*rng.uniform(.82,1.06)
            tip=Vector((math.cos(a)*r,math.sin(a)*r,z-9))
            _tube(k,[(0,0,z+9),tip],[2,.3],'bark',5)
            for s in (-1,0,1):
                begin=Vector((math.cos(a)*r*.18,math.sin(a)*r*.18,z+8))
                end=tip+Vector((-math.sin(a)*s*10,math.cos(a)*s*10,2))
                _blade(k,begin,end,13 if not s else 9,'leaf_dark')
                if (j+level+s)%3 != 0:
                    _blade(k,begin+Vector((0,0,1.0)),end*.8+begin*.2+Vector((0,0,1.8)),
                           9 if not s else 6,'snow',.55)
    _roots(k,rng,5,29)


def _basalt_cluster(k, rng, bands=True):
    for i in range(12):
        a=i*2.399
        r=0 if i==0 else 17+9*(i%3)
        x,y=math.cos(a)*r,math.sin(a)*r
        h=(182 if i==0 else rng.uniform(47,146))
        radius=rng.uniform(12,18)
        k.cone((x,y,h/2),radius*1.05,radius*.84,h,'basalt',6)
        k.cone((x,y,h-1.2),radius*.84,radius*.80,2.4,'slate',6)
        if bands and i in (1,5):
            # Dark copper reinforcing straps are confined to two outer columns.
            k.ring((x,y,h*.58),radius*.96,1.6,'bronze',n=12)
            k.cone((x,y-radius-1,h*.58),2.4,2.4,2.0,'bronze',6,Matrix.Rotation(math.pi/2,3,'X'))


def _crystals(k, rng):
    k.rock((0,0,21),(92,74,55),'schist')
    for j in range(7):
        a=j*2.399
        r=0 if j==0 else 18+(j%2)*8
        x,y=math.cos(a)*r,math.sin(a)*r
        height=155 if j==0 else rng.uniform(47,112)
        radius=14 if j==0 else rng.uniform(8,13)
        first=len(k.v)
        k.crystal_gem((0,0,0),radius,height,'quartz' if j==5 else 'amethyst')
        tilt=Matrix.Rotation(.05 if j==0 else rng.uniform(.10,.33),3,'Y')
        turn=Matrix.Rotation(a,3,'Z')
        k.v[first:]=[tuple(turn@tilt@Vector(p)+Vector((x,y,27)))for p in k.v[first:]]


def _porous_reef(k, rng):
    k.rock((0,0,21),(92,70,52),'coral')
    # Actual open windows between rough stone arches, not dark painted circles.
    for x,y,z,rr in [(-21,1,42,22),(23,3,50,24),(1,5,89,22)]:
        k.ring((x,y,z),rr,9.2,'coral_light',Matrix.Rotation(math.pi/2,3,'X'),n=11)
    for i in range(8):
        a=i*TAU/8
        k.rock((math.cos(a)*29,math.sin(a)*16,9),(17,14,20),'coral')


def _shell(k):
    # Thick fan shell with separate radial ribs. The scalloped lip is a real edge.
    n=12
    points=[(-5,0,0)]+[(math.cos(math.pi*i/n)*23,4+math.sin(math.pi*i/n)*28,2+math.sin(math.pi*i/n)*5)
                      for i in range(n+1)]+[(5,0,0)]
    verts=points+[(x,y,z-2)for x,y,z in points]
    count=len(points)
    faces=[tuple(range(count)),tuple(reversed(range(count,count*2)))]
    faces += [(j,(j+1)%count,(j+1)%count+count,j+count)for j in range(count)]
    k.mesh(verts,faces,'coral_light')
    for p in points[2:-2]:_tube(k,[(0,2,1),Vector(p)*.5+Vector((0,0,3)),p],[.9,.8,.3],'ivory',5)


def _bone_spine(k, rng):
    for offset,h,sign in [(-16,77,1),(18,103,-1)]:
        points=[(offset,0,0),(offset+sign*6,-2,h*.28),(offset+sign*13,-11,h*.64),
                (offset+sign*9,-28,h*.86),(offset+sign*3,-42,h)]
        _tube(k,points,[8,8,6,3,.3],'bone',7)
    k.rock((0,0,9),(62,42,26),'slate')


def _fountain(k, rng, dire=False):
    stone='slate' if dire else 'ivory'
    trim='bone' if dire else 'gold'
    # A low dry stone basin with still dark water; never a beam or emissive disc.
    k.cone((0,0,4),51,51,8,stone,16)
    for j in range(12):
        k.sector(39,52,j*TAU/12+.014,(j+1)*TAU/12-.014,6,14,stone,1)
    k.cone((0,0,9),38,38,1,'slate_wet' if dire else 'teal',32)
    k.cone((0,11,29),15,12,39,stone,8)
    k.cone((0,11,52),22,27,9,stone,12)
    k.cone((0,11,57),23,23,.8,'slate_wet' if dire else 'teal',16)
    k.ring((0,11,57),26,1.0,trim,n=24)
    if dire:
        for i in range(3):
            a=i*TAU/3
            _tube(k,[(math.cos(a)*13,11+math.sin(a)*13,55),
                      (math.cos(a)*9,11+math.sin(a)*9,79),(math.cos(a)*4,11+math.sin(a)*4,92)],
                  [4,2,.5],'slate',6)
    else:
        k.crystal_gem((0,11,59),7,20,'ivory_light')


def _scatter(k, rng, rank):
    roles=k.spec['roles']
    # Biased distributions have little gaps and a few busy coves; not a fence
    # made of equally spaced props. Half of the pebbles are partially submerged.
    for i in range(48):
        side=rng.randrange(4)
        along=rng.uniform(-455,455)
        across=rng.uniform(403,476)
        xy=[(along,across),(across,along),(along,-across),(-across,along)][side]
        size=rng.uniform(8,24)
        mat=roles['wet'] if across>429 else roles['rock']
        _place(k,'shore pebble',lambda s=size,m=mat:k.rock((0,0,s*.27),(s,s*.77,s*.66),m),xy,angle=rng.random()*TAU)
    # Near-wall vegetation differs by ecology; two opposite edges stay sparse.
    for i in range(24):
        side=rng.choices(range(4),[3,1,2,1])[0]
        along=rng.uniform(-315,315)
        across=rng.uniform(378,402)
        xy=[(along,across),(across,along),(along,-across),(-across,along)][side]
        if rank in (1,4,7):
            def fn():
                _dry_shrub(k,rng)
                k.place(lambda:_dry_shrub(k,rng), (16,-5,0),.64,.9)
            scale=.58 if rank==7 else .77
        elif rank==3:
            def fn():
                _reeds(k,rng)
                k.place(lambda:_reeds(k,rng), (15,-6,-1),.61,.7)
            scale=.78
        elif rank==5:
            fn=lambda:k.rock((0,0,3),(27,20,7),'snow');scale=1
        elif rank==6:
            fn=lambda:_shell(k);scale=.35
        elif rank==8:
            def fn():
                _dry_shrub(k,rng,True)
                k.crystal_gem((-12,8,0),3.2,12,'quartz')
            scale=.68
        elif rank==10:
            def fn():
                _dry_shrub(k,rng)
                _tube(k,[(-19,0,0),(-5,-4,7),(17,3,2)],[2,3,.4],'bark',6)
            scale=.78
        else:
            def fn():
                k.fern()
                k.place(lambda:k.shrub(rank==9),(25,-11,1),.58,.9)
            scale=.54 if rank==2 else .44
        _place(k,'small edge growth',fn,xy,scale,rng.random()*TAU)


def decorate(k, rank):
    """Append deterministic themed exterior assemblies to a RealmKit."""
    assert 1<=rank<=10
    rng=random.Random(9481+rank*171)
    v0,f0=len(k.v),len(k.f)
    corner=[(-407,-411),(409,-398),(-399,414),(410,407)]
    rock=k.spec['roles']['rock']
    for i,xy in enumerate(corner):
        if rank in (1,4):
            fn=lambda:_strata(k,rng,rank==1)
        elif rank==7:
            fn=lambda:_basalt_cluster(k,rng)
        elif rank==8:
            fn=lambda:_crystals(k,rng)
        elif rank==6:
            fn=lambda:_porous_reef(k,rng)
        else:
            def fn():
                k.rock((0,0,70),(95,82,154),rock)
                k.rock((38,-22,32),(57,48,83),rock)
                k.rock((-27,-28,13),(39,38,38),rock)
                if rank==5:k.rock((0,0,143),(78,68,13),'snow')
        _place(k,'corner outcrop',fn,xy,.87 if i==1 else 1.0,i*.83,
               top=(146,108,163,131)[i] if rank!=6 else (124,96,141,111)[i])
    if rank==1:
        for xy,s,a,top in [((-443,112),.89,.3,242),((405,318),.65,-.6,201)]:
            _place(k,'desert palm',lambda:_palm(k,rng),xy,s,a,top=top)
        for xy in [(-384,-184),(394,107),(168,396)]:
            _place(k,'wind-eroded stack',lambda:_strata(k,rng,True),xy,.62,rng.random()*TAU)
    elif rank==2:
        for xy,s,a,top in [((-423,336),1.0,.5,252),((418,-320),.94,1.4,233),((160,429),.76,2.6,196)]:
            _place(k,'rooted broadleaf tree',lambda:_broad_tree(k,rng),xy,s,a,top=top)
        for xy in [(-407,-140),(407,84),(-211,-401)]:
            _place(k,'large fern',lambda:k.fern(),xy,.7,rng.random()*TAU)
    elif rank==3:
        for xy,s,a,top in [((-421,312),.98,.4,246),((405,-334),.87,2,224),((155,407),.76,-1,193)]:
            _place(k,'marsh snag',lambda:_dead_tree(k,rng,True),xy,s,a,top=top)
        for xy in [(-389,-188),(394,130),(-87,-397)]:
            _place(k,'rotted hollow stump',lambda:_stump(k,rng),xy,.82,rng.random()*TAU)
        for xy in [(-442,-95),(448,240),(-195,444)]:
            _place(k,'wet reeds',lambda:_reeds(k,rng),xy,.82,rng.random()*TAU)
    elif rank==4:
        for xy,s,a in [((-399,71),1.1,0),((419,-84),.8,.7),((-202,397),.8,1.4),((147,-408),.7,.3)]:
            _place(k,'sedimentary butte',lambda:_strata(k,rng),xy,s,a)
    elif rank==5:
        for xy,s,a,top in [((-420,322),1.02,0,256),((421,-309),.88,.7,231),((140,412),.68,1.8,187)]:
            _place(k,'snow cedar',lambda:_cedar(k,rng),xy,s,a,top=top)
        for xy in [(-480,-220),(467,127),(-215,480),(277,-478),(-471,311),(457,-367)]:
            _place(k,'shore ice floe',lambda:k.rock((0,0,0),(57,39,9),'ice'),xy,
                   rng.uniform(.55,1),rng.random()*TAU,z=k.spec['water_z']+.8)
    elif rank==6:
        for xy,s,a,top in [((-428,308),.92,.3,247),((429,-315),.80,-.8,219)]:
            _place(k,'coastal palm',lambda:_palm(k,rng),xy,s,a,top=top)
        for xy in [(-411,-42),(177,414),(-193,-416)]:
            _place(k,'weathered coral arch',lambda:_porous_reef(k,rng),xy,.65,rng.random()*TAU)
        for xy in [(-401,-234),(402,144),(232,407)]:
            _place(k,'shell fossil',lambda:_shell(k),xy,.74,rng.random()*TAU)
    elif rank==7:
        for xy,s,a in [((-412,127),.81,.3),((411,-111),.69,.9),((-148,416),.7,1.6),((238,-424),.58,.4)]:
            _place(k,'basalt organ pipes',lambda:_basalt_cluster(k,rng,False),xy,s,a)
    elif rank==8:
        for xy,s,a in [((-409,107),.73,.1),((410,-144),.60,1.7),((-161,402),.54,2.9),((200,-418),.64,2)]:
            _place(k,'amethyst seam cluster',lambda:_crystals(k,rng),xy,s,a)
        for xy in [(-454,-201),(459,264),(-138,-450)]:
            _place(k,'pale quartz scatter',lambda:k.crystal_gem((0,0,0),7,17,'quartz'),xy,1,rng.random()*TAU)
    elif rank==9:
        _place(k,'pink flowering tree',lambda:_broad_tree(k,rng,True),(-426,320),.93,.4,top=247)
        _place(k,'radiant broadleaf tree',lambda:_broad_tree(k,rng),(429,-299),.86,1.6,top=225)
        _place(k,'still radiant fountain',lambda:_fountain(k,rng),(0,426),.94)
        for xy,a in [((-399,-237),.20),((406,253),math.pi+.2)]:
            _place(k,'small teal banner',lambda:k.flag(),xy,.72,a)
        for xy in [(-388,100),(392,-109),(-201,-389),(234,389)]:
            _place(k,'flowering shore shrub',lambda:k.shrub(True),xy,.58,rng.random()*TAU)
    else:
        for xy,s,a,top in [((-424,319),1.0,.3,252),((428,-326),.9,1.9,229),((-184,411),.69,-.6,192)]:
            _place(k,'twisted dire tree',lambda:_dead_tree(k,rng),xy,s,a,top=top)
        for xy,a in [((-382,-184),-math.pi/2),((382,175),math.pi/2),((-164,-382),math.pi),((168,382),0)]:
            _place(k,'bone-white thorn braces',lambda:_bone_spine(k,rng),xy,.94,a)
        _place(k,'ruined still fountain',lambda:_fountain(k,rng,True),(26,435),1.0)
    _scatter(k,rng,rank)
    if hasattr(k,'smooth_faces'):
        assert len(k.smooth_faces)==len(k.f)
    assert len(k.grain_axis)==len(k.f)
    k.dressing_summary=dict(rank=rank,vertices=len(k.v)-v0,faces=len(k.f)-f0,
                            estimated_triangles=sum(max(0,len(f)-2)for f in k.f[f0:]),
                            keep_out_half_extent=KEEP_OUT,max_extent=MAX_EXTENT)
    return k.dressing_summary
