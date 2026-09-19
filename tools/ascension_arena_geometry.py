"""Ten independent ascension arenas, inside the approved 1000 x 550 footprint.

Layers include the playable deck: rank N has exactly N courses, each 14 high.
Cloud courses are solid rounded/scalloped meshes, never fog or extra plinths.
``grain_axis`` and ``smooth_faces`` parallel the original ``f`` array and must
be inherited when the consumer triangulates the geometry.
"""
import math

from mathutils import Matrix, Vector

from ascension_arena_spec import PALETTE, FOOTPRINT, LAYER_HEIGHT, LAYER_INSET, stage
from wood_training_geometry import WoodKit


class ArenaKit(WoodKit):
    def __init__(self, seed):
        super().__init__(seed)
        self.keys = list(PALETTE)
        self.smooth_faces = []
        self.layers = []

    def mesh(self, verts, faces, mat='stone'):
        first = len(self.f)
        super().mesh(verts, faces, mat)
        self.smooth_faces.extend([False] * (len(self.f) - first))

    def rubble(self, center, radius, mat='stone'):
        # Small compressed pebbles remain inside the edge dressing zone.
        x, y, z = center
        n = 7
        ring = [(math.cos(i * math.tau / n) * radius * self.rng.uniform(.8, 1),
                 math.sin(i * math.tau / n) * radius * self.rng.uniform(.8, 1)) for i in range(n)]
        vertices = [(x + xx, y + yy, z) for xx, yy in ring]
        vertices += [(x + xx * .7, y + yy * .7, z + radius * .23) for xx, yy in ring]
        self.mesh(vertices, [tuple(reversed(range(n))), tuple(range(n, 2*n))] +
                  [(i, (i+1) % n, (i+1) % n+n, i+n) for i in range(n)], mat)

    def rim(self, width, depth, z, thickness=4, mat='bronze', inset=8, bevel=.4):
        # Horizontal trim is part of the current layer, not an extra platform.
        for sign in (-1, 1):
            self.box((0, sign * (depth/2-inset-thickness/2), z),
                     (width-2*inset, thickness, 1.3), mat, bevel)
            self.box((sign * (width/2-inset-thickness/2), 0, z),
                     (thickness, depth-2*inset-2*thickness, 1.3), mat, bevel)

    def course(self, index, rank, mat, rough=False):
        width = FOOTPRINT[0] - 2*index*LAYER_INSET
        depth = FOOTPRINT[1] - 2*index*LAYER_INSET
        z0, z1 = index*LAYER_HEIGHT, (index+1)*LAYER_HEIGHT
        first_vertex, first_face = len(self.v), len(self.f)
        # Recessed interior keeps the shadow seam visible between courses.
        self.box((0, 0, (z0+z1)/2), (width-5, depth-5, 11),
                 'earth_edge' if mat.startswith('earth') else 'mortar', 1)
        pitch = 73 if rough else 68
        for side in (-1, 1):
            for axis, length, cross in ((0, width, depth), (1, depth-31, width)):
                count = max(1, round(length / pitch))
                # Every course owns its top and bottom; fine seams do not add layers.
                edges = [-length/2 + i*length/count for i in range(count+1)]
                for part, (a, b) in enumerate(zip(edges, edges[1:])):
                    gap = 1.1 if rough else .65
                    across = 16.5
                    course_height = LAYER_HEIGHT-(.325 if index == 0 else .65)
                    course_center = z0+course_height/2 if index == 0 else (z0+z1)/2
                    c = ((a+b)/2, side*(cross/2-across/2), course_center)
                    s = (b-a-gap, across, course_height)
                    if axis:
                        c, s = (c[1], c[0], c[2]), (s[1], s[0], s[2])
                    chosen = mat
                    if rough and part % 5 == (index % 5):
                        chosen = 'stone_dark' if mat == 'stone' else mat
                    self.box(c, s, chosen, 1.9 if rough else 1.0)
        self.layers.append(dict(index=index+1, bounds=[[-width/2, -depth/2, z0],
                                                     [width/2, depth/2, z1]],
                                material=mat, vertices=[first_vertex, len(self.v)],
                                faces=[first_face, len(self.f)], shape='masonry course'))

    def cloud_course(self, index, rank, mat='cloud', jade_trim=False):
        width = FOOTPRINT[0] - 2*index*LAYER_INSET
        depth = FOOTPRINT[1] - 2*index*LAYER_INSET
        z0, z1 = index*LAYER_HEIGHT, (index+1)*LAYER_HEIGHT
        first_vertex, first_face = len(self.v), len(self.f)
        path = _rounded_path(width, depth, 18)
        count = len(path)
        # Rounded lobes are large enough to read at the game camera. Use whole
        # cycles around the perimeter so the closing seam cannot jump in phase.
        # The first/last ring still lies at exactly z0/z1; central top stays flat.
        profile = [(0, 5.1), (1.1, 4.1), (3.2, 1.5), (6.7, 0),
                   (10.0, .8), (12.4, 2.3), (14, 4.5)]
        # Keep the cloud lobes at their original world size as the deck grows.
        lobe_cycles = max(1, round((width+depth)/32.8125))
        broad_cycles = max(1, round((width+depth)/95.4545))
        vertices = []
        for height, inset in profile:
            for i, (x, y) in enumerate(path):
                before, after = Vector(path[(i-1) % count]), Vector(path[(i+1) % count])
                tangent = (after-before).normalized()
                outward = Vector((tangent.y, -tangent.x))
                phase = i*math.tau/count
                wave = .8 + 7.8*(.5+.5*math.sin(phase*lobe_cycles + index*.87))
                wave += 1.2*(.5+.5*math.sin(phase*broad_cycles-index*.47))
                q = Vector((x, y))-outward*(inset+wave)
                ripple = 1.1*math.sin(phase*lobe_cycles+index*.87)*math.sin(math.pi*height/LAYER_HEIGHT)
                vertices.append((q.x, q.y, z0+height+ripple))
        faces = [tuple(reversed(range(count))), tuple(range((len(profile)-1)*count, len(profile)*count))]
        face_materials = ['cloud_shadow', mat]
        for row in range(len(profile)-1):
            for i in range(count):
                faces.append((row*count+i, row*count+(i+1) % count,
                              (row+1)*count+(i+1) % count, (row+1)*count+i))
                face_materials.append('cloud_shadow' if row == 0 else mat)
        self.mesh(vertices, faces, mat)
        for i, key in enumerate(face_materials):
            self.m[first_face+i] = self.keys.index(key)
            self.smooth_faces[first_face+i] = i >= 2
        if jade_trim:
            # Thin corner ties leave the broad cloud side fully visible/countable.
            for sx in (-1, 1):
                for sy in (-1, 1):
                    self.box((sx*(width/2-22), sy*(depth/2-12), z1-3.3),
                             (25, 4, 4), 'jade_light', .7)
        self.layers.append(dict(index=index+1, bounds=[[-width/2, -depth/2, z0],
                                                     [width/2, depth/2, z1]],
                                material=mat, vertices=[first_vertex, len(self.v)],
                                faces=[first_face, len(self.f)], shape='rounded solid cloud course',
                                top_outline=[list(v[:2]) for v in vertices[-count:]]))

    def deck_tiles(self, width, depth, z, mat, rough=False, border=18):
        width, depth = width-2*border, depth-2*border
        # Add stones instead of stretching the old grid across the larger deck.
        # The original rough/dressed stone pitches were about 82x77 / 54x50.
        rows = max(1, round(depth/(77 if rough else 50)))
        columns = max(1, round(width/(82 if rough else 54)))
        pitch_y, pitch_x = depth/rows, width/columns
        for row in range(rows):
            offset = pitch_x*.5 if row % 2 else 0
            edges = sorted(set([-width/2, width/2] +
                               [-width/2+offset+i*pitch_x for i in range(columns+1)
                                if -width/2 < -width/2+offset+i*pitch_x < width/2]))
            for column, (a, b) in enumerate(zip(edges, edges[1:])):
                y = -depth/2 + (row+.5)*pitch_y
                key = mat
                if mat == 'stone' and (row*3+column) % 7 == 0:
                    key = 'stone_dark'
                elif mat == 'jade' and (row*7+column) % 9 == 0:
                    key = 'jade_light'
                self.box(((a+b)/2, y, z-2), (b-a-(1.35 if rough else .7), pitch_y-.75, 4),
                         key, 1.0 if rough else .50)

    def inlay_line(self, a, b, z, width=1.25, mat='gold'):
        # A thin flat solid keeps the fight area effectively flush to the deck.
        a, b = Vector((a[0], a[1], z)), Vector((b[0], b[1], z))
        delta = b-a
        angle = math.atan2(delta.y, delta.x)
        self.box((a+b)/2, (delta.length, width, .16), mat, .035,
                 Matrix.Rotation(angle, 3, 'Z'))

    def inlay_ring(self, center, radius, z, mat='gold', thickness=1.0, steps=64):
        points = [(center[0]+math.cos(i*math.tau/steps)*radius,
                   center[1]+math.sin(i*math.tau/steps)*radius) for i in range(steps)]
        for a, b in zip(points, points[1:]+points[:1]):
            self.inlay_line(a, b, z, thickness, mat)

    def crystal_gem(self, center, radius, height, mat='crystal'):
        x, y, z = center
        n = 6
        vertices = [(x+math.cos(i*math.tau/n)*radius*.8,
                     y+math.sin(i*math.tau/n)*radius*.8, z) for i in range(n)]
        vertices += [(x+math.cos(i*math.tau/n)*radius,
                      y+math.sin(i*math.tau/n)*radius, z+height*.42) for i in range(n)]
        vertices.append((x+radius*.15, y-radius*.12, z+height))
        self.mesh(vertices, [tuple(reversed(range(n)))] +
                  [(i, (i+1) % n, (i+1) % n+n, i+n) for i in range(n)] +
                  [(i+n, (i+1) % n+n, 2*n) for i in range(n)], mat)

    def corners(self, width, depth, z, rank):
        for sx in (-1, 1):
            for sy in (-1, 1):
                x, y = sx*(width/2-17), sy*(depth/2-17)
                if rank <= 3:
                    self.timber((x, y, z+8), (22, 22, 24), 'wood', 1.8, axis=(0, 0, 1))
                    for dy in (-11.5, 11.5):
                        self.box((x, y+dy, z+6), (24, 2, 5), 'iron', .5)
                    self.bolt((x, y-13, z+6), radius=1.6)
                elif rank <= 6:
                    stone = 'dressed_stone' if rank == 4 else 'ivory'
                    self.box((x, y, z+6), (28, 28, 17), stone, 2)
                    self.box((x, y, z+13), (24, 24, 3), 'bronze' if rank == 4 else 'gold', .5)
                    self.box((x, y, z+16), (18, 18, 5), 'jade' if rank == 6 else stone, 1.2)
                elif rank == 7:
                    self.box((x, y, z+5), (27, 27, 12), 'stone_dark', 1.9)
                    self.box((x, y, z+11), (25, 25, 2.2), 'silver', .5)
                    self.crystal_gem((x, y, z+12), 9, 19)
                else:
                    self.box((x, y, z+3), (22, 22, 8), 'gold', 2)
                    if rank == 8:
                        self.box((x, y, z+9), (17, 17, 7), 'jade_light', 2)
                    else:
                        self.crystal_gem((x, y, z+7), 6.5, 11, 'jade_light')

    def cloud_patch(self, center, radius_x, radius_y, z, mat='cloud', phase=0, relief=.08):
        # An opaque thin cloud-shaped insert, not an overlaid particle or alpha plane.
        points = []
        for i in range(56):
            angle = i*math.tau/56
            wave = .91+.065*math.sin(angle*7+phase)+.025*math.cos(angle*11-phase)
            points.append((center[0]+math.cos(angle)*radius_x*wave,
                           center[1]+math.sin(angle)*radius_y*wave))
        self.polygon(points, z-.2, .2+relief, mat)
        return abs(sum(a[0]*b[1]-a[1]*b[0] for a, b in zip(points, points[1:]+points[:1])))/2


def _rounded_path(width, depth, radius):
    """CCW rounded rectangular outline, sampled at approximately eight units."""
    hx, hy = width/2, depth/2
    corners = [(hx-radius, hy-radius, 0), (-hx+radius, hy-radius, math.pi/2),
               (-hx+radius, -hy+radius, math.pi), (hx-radius, -hy+radius, math.pi*1.5)]
    points = []
    for index, (cx, cy, a0) in enumerate(corners):
        for part in range(7):
            a = a0+part*math.pi/12
            points.append((cx+radius*math.cos(a), cy+radius*math.sin(a)))
        nx, ny, na = corners[(index+1) % 4]
        p = Vector(points[-1])
        q = Vector((nx+radius*math.cos(na), ny+radius*math.sin(na)))
        steps = max(1, round((q-p).length/8))
        for part in range(1, steps):
            points.append(tuple(p.lerp(q, part/steps)))
    return points


def _earth_deck(kit, width, depth, z, wood=False):
    margin = 32 if wood else 12
    kit.box((0, 0, z-3), (width-2*margin, depth-2*margin, 6), 'earth', 1.7)
    if wood:
        for sy in (-1, 1):
            kit.timber((0, sy*(depth/2-9), z-3), (width, 18, 6), 'wood', 1.1, axis=(1, 0, 0))
            kit.timber((0, sy*(depth/2-24), z-3), (width-52, 10.5, 6), 'wood_light', .7, axis=(1, 0, 0))
        for sx in (-1, 1):
            for offset in (8, 21):
                kit.timber((sx*(width/2-offset), 0, z-3), (11, depth-35, 6), 'wood_light', .9, axis=(0, 1, 0))
    else:
        columns, rows = max(1, round(width/50)), max(1, round(depth/50))
        for sy in (-1, 1):
            for i in range(columns):
                kit.box((-width/2+(i+.5)*width/columns, sy*(depth/2-6), z-2),
                        (width/columns-1.2, 11, 4), 'stone', 1.2)
        for sx in (-1, 1):
            for i in range(rows):
                kit.box((sx*(width/2-6), -depth/2+(i+.5)*depth/rows, z-2),
                        (11, depth/rows-1.2, 4), 'stone', 1.1)
    pebble_count = round((width+depth)/(47.7 if wood else 27.6))
    for i in range(pebble_count):
        sx, sy = kit.rng.choice((-1, 1)), kit.rng.choice((-1, 1))
        if i % 2:
            point = (kit.rng.uniform(-width/2+40, width/2-40), sy*(depth/2-margin-kit.rng.uniform(6, 17)), z-.25)
        else:
            point = (sx*(width/2-margin-kit.rng.uniform(6, 17)), kit.rng.uniform(-depth/2+40, depth/2-40), z-.25)
        kit.rubble(point, kit.rng.uniform(1.7, 3.3), 'stone_light' if i % 3 else 'earth_edge')


def _deck_design(kit, meta):
    rank, z = meta['rank'], meta['deck_z']
    width, depth = meta['deck_size']
    if rank <= 2:
        _earth_deck(kit, width, depth, z, rank == 2)
    elif rank <= 7:
        material = {3:'stone', 4:'dressed_stone', 5:'ivory', 6:'jade', 7:'mineral_stone'}[rank]
        kit.deck_tiles(width, depth, z, material, rank == 3)
        if rank >= 4:
            kit.rim(width, depth, z-.4, 5 if rank == 4 else 2, 'stone_dark' if rank == 4 else 'gold', 17)
        if rank == 5:
            kit.inlay_ring((0, 0), 37, z+.1)
            kit.inlay_ring((0, 0), 31, z+.1, 'bronze')
            kit.polygon([(0,20), (15,0), (0,-20), (-15,0)], z-.06, .2, 'gold')
            for sign in (-1, 1):
                kit.inlay_line((sign*38,0), (sign*(width/2-23),0), z+.1)
                kit.inlay_line((0,sign*38), (0,sign*(depth/2-23)), z+.1)
        if rank == 6:
            kit.inlay_ring((0, 0), 42, z+.1)
            kit.inlay_ring((0, 0), 35, z+.1, 'ivory', 1.7)
            # One continuous three-leaf silhouette. Separate coplanar leaf solids
            # used to overlap at the stem and rendered as a black central patch.
            leaf = [(0,-25),(-5,-12),(-18,-14),(-29,-2),(-24,10),(-9,4),
                    (-13,19),(0,31),(13,19),(9,4),(24,10),(29,-2),(18,-14),(5,-12)]
            kit.polygon(leaf, z-.05, .18, 'jade_light')
            kit.inlay_line((0,-21),(0,24),z+.23,1.3,'gold')
            for sign in (-1,1):
                kit.inlay_line((0,-10),(sign*22,3),z+.23,1.2,'gold')
            for sign in (-1, 1):
                kit.inlay_line((sign*43, 0), (sign*(width/2-21), 0), z+.1, 1.3)
        if rank == 7:
            diamond = [(-58,0),(0,-37),(58,0),(0,37)]
            kit.polygon(diamond, z-.05, .18, 'crystal')
            for a,b in zip(diamond, diamond[1:]+diamond[:1]):
                kit.inlay_line(a, b, z+.16, 1.8, 'silver')
            for sx in (-1, 1):
                for sy in (-1, 1):
                    triangle = [(sx*(width/2-25), sy*(depth/2-25)),
                                (sx*(width/2-85), sy*(depth/2-25)),
                                (sx*(width/2-25), sy*(depth/2-75))]
                    kit.polygon(triangle, z-.05, .18, 'crystal')
                    for a,b in zip(triangle, triangle[1:]+triangle[:1]):
                        kit.inlay_line(a,b,z+.14,1.2,'silver')
    elif rank == 8:
        kit.deck_tiles(width, depth, z, 'jade_light', False, 15)
        cloud_area = 0
        # The approved four cloud inserts cover 30% of the playable deck.
        # Normalize only their outlines and placement, never the material UVs.
        for index, (sx,sy) in enumerate(((-1,-1),(1,-1),(-1,1),(1,1))):
            center = (sx*width*(173/679), sy*depth*(77/329))
            cloud_area += kit.cloud_patch(center, width*(128/679), depth*(50/329),
                                          z, 'cloud', index*.9)
        kit.inlay_ring((0,0), 38, z+.14, 'gold', 1.2)
        kit.inlay_ring((0,0), 31, z+.14, 'gold', 1.0)
        kit.rim(width, depth, z-.1, 2, 'gold', 12)
        meta['cloud_deck_area_fraction'] = round(cloud_area/(width*depth), 3)
    elif rank == 9:
        # Entire underlying deck is cloud. Small flat jade islands are edge-only.
        jade_area = 0
        edge_islands = ((-265/676,-92/326),(265/676,-92/326),
                        (-265/676,92/326),(265/676,92/326),
                        (-110/676,130/326),(110/676,-130/326))
        for index,(u,v) in enumerate(edge_islands):
            jade_area += kit.cloud_patch((u*width,v*depth), width*(36/676),
                                         depth*(19/326), z, 'jade_light', index*.8, .20)
        kit.rim(width, depth, z+.02, 4, 'jade_light', 12)
        kit.rim(width, depth, z+.07, 1.1, 'gold', 17)
        rim_area = (width-24)*(depth-24)-(width-32)*(depth-32)
        meta['cloud_deck_area_fraction'] = round(1-(jade_area+rim_area)/(width*depth), 3)
    else:
        # Full solid cloud top with scalloped boundary. No jade or stone floor.
        meta['cloud_deck_area_fraction'] = 1.0
        # Follow the actual wavy solid-cloud contour, not a rectangular frame.
        outline = kit.layers[-1]['top_outline']
        inset_outline = []
        for index, point in enumerate(outline):
            tangent = (Vector(outline[(index+1)%len(outline)])-
                       Vector(outline[(index-1)%len(outline)])).normalized()
            inward = Vector((-tangent.y,tangent.x))
            inset_outline.append(tuple(Vector(point)+inward*1.5))
        for a,b in zip(inset_outline,inset_outline[1:]+inset_outline[:1]):
            kit.inlay_line(a,b,z+.22,1.7,'gold')
        # A delicate corner flourish adds identity without introducing a stone rim.
        for sx in (-1,1):
            for sy in (-1,1):
                center=(sx*(width/2-32),sy*(depth/2-31))
                for i in range(15):
                    a=i*.16; b=(i+1)*.16
                    ra=3+i*.45;rb=3+(i+1)*.45
                    p=(center[0]+sx*math.cos(a)*ra,center[1]+sy*math.sin(a)*ra)
                    q=(center[0]+sx*math.cos(b)*rb,center[1]+sy*math.sin(b)*rb)
                    kit.inlay_line(p,q,z+.12,1.35,'gold')


def build_arenas():
    jobs=[]
    for rank in range(1,11):
        meta=stage(rank)
        kit=ArenaKit(28900+rank)
        for index in range(rank):
            if rank>=9:
                kit.cloud_course(index,rank,'cloud' if index%3 else 'cloud_pearl',rank==9)
            elif rank==8:
                kit.cloud_course(index,rank,'cloud') if index==0 else kit.course(index,rank,'jade_light')
            elif rank==1:
                kit.course(index,rank,'earth_edge',True)
            elif rank==2:
                kit.course(index,rank,'stone',True) if index==0 else kit.course(index,rank,'earth_edge')
                if index==1:
                    width=FOOTPRINT[0]-2*index*LAYER_INSET;depth=FOOTPRINT[1]-2*index*LAYER_INSET
                    for sy in (-1,1):
                        kit.timber((0,sy*(depth/2-3.2),(index+.5)*LAYER_HEIGHT),(width-2,6,10),'wood',.7,axis=(1,0,0))
            else:
                material={3:'stone',4:'dressed_stone',5:'ivory',6:'jade',7:'stone_dark'}[rank]
                kit.course(index,rank,material,rank==3)
                if rank>=5:
                    width=FOOTPRINT[0]-2*index*LAYER_INSET;depth=FOOTPRINT[1]-2*index*LAYER_INSET
                    kit.rim(width,depth,(index+1)*LAYER_HEIGHT-1.5,1.7,
                            'silver' if rank==7 else 'ivory' if rank==6 else 'bronze',1.8)
        _deck_design(kit,meta)
        kit.corners(*meta['deck_size'],meta['deck_z'],rank)
        for layer in kit.layers:
            vertices=kit.v[layer['vertices'][0]:layer['vertices'][1]]
            layer['actual_bounds']=[[min(p[axis] for p in vertices) for axis in range(3)],
                                    [max(p[axis] for p in vertices) for axis in range(3)]]
        meta['layer_bounds']=[layer['bounds'] for layer in kit.layers]
        meta['layer_geometry']=kit.layers
        meta['notes']=f'Exactly one solid counted course per rank; no extra foundation. Decoration is contained in the {FOOTPRINT[0]}x{FOOTPRINT[1]} footprint. Central deck is flat; thin flush inlays are not steps.'
        meta['cloud_deck_area_fraction']=meta.get('cloud_deck_area_fraction',0.0)
        collision=[dict(center=[0,0,(i+.5)*LAYER_HEIGHT],
                        size=[FOOTPRINT[0]-2*i*LAYER_INSET,FOOTPRINT[1]-2*i*LAYER_INSET,LAYER_HEIGHT]) for i in range(rank)]
        jobs.append(dict(name=meta['name'],kit=kit,meta=meta,collision=collision))
    return jobs
