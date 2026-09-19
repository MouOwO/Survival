"""Non-emissive attribute-room landmarks, compatible with the gold room kit.

The shared courtyard module interfaces and collision envelopes remain intact.
Only per-instance material keys are extended: importing this file never mutates
gold_room_geometry.PALETTE.  Attribute uses a jade growing-leaf insignia;
greater_attribute uses a three-crystal crown and faceted mineral ornaments.
"""
import math

from mathutils import Matrix, Vector
from gold_room_geometry import GoldKit


EXTRA_KEYS = ('mineral', 'mineral_dark', 'metal_light')
THEMES = ('attribute', 'greater_attribute')


class AttributeKit(GoldKit):
    def __init__(self, theme, seed=1):
        if theme not in THEMES:
            raise ValueError('Unknown attribute-room theme: ' + str(theme))
        super().__init__(seed)
        self.keys.extend(EXTRA_KEYS)
        self.theme = theme
        self.greater = theme == 'greater_attribute'

    def flat_outline(self, points, z, width=2.0, mat='metal_light'):
        for a, b in zip(points, points[1:] + points[:1]):
            self.beam((*a, z), (*b, z), width, mat)

    def relief(self, points, depth=3.0, mat='mineral', center=(0, 0, 0)):
        """A closed pointed relief in XY; its faceted front faces positive Z."""
        cx, cy, cz = center
        n = len(points)
        vertices = [(cx + x, cy + y, cz) for x, y in points]
        vertices.append((cx, cy, cz + depth))
        self.mesh(vertices, [tuple(reversed(range(n)))] +
                  [(i, (i + 1) % n, n) for i in range(n)], mat)

    def crystal_prism(self, base, radius, height, tilt=(0, 0), mat='mineral'):
        """Closed six-sided mineral prism, with a real point and dark facets."""
        bx, by, bz = base
        n = 6
        verts = []
        for level, factor in ((0, .72), (.13, 1), (.74, .91)):
            for i in range(n):
                a = math.tau * i / n + math.pi / 6
                verts.append((bx + math.cos(a) * radius * factor + tilt[0] * level,
                              by + math.sin(a) * radius * factor + tilt[1] * level,
                              bz + height * level))
        verts.append((bx + tilt[0], by + tilt[1], bz + height))
        faces = [tuple(reversed(range(n)))]
        for row in range(2):
            faces.extend((row*n+i, row*n+(i+1)%n,
                          (row+1)*n+(i+1)%n, (row+1)*n+i) for i in range(n))
        faces.extend((2*n+i, 2*n+(i+1)%n, 3*n) for i in range(n))
        start = len(self.m)
        self.mesh(verts, faces, mat)
        # Physical facets are darkened sparingly; the material owns the actual
        # normal/specular response. No emissive or painted rim illumination.
        for index in (3, 8, 15):
            self.m[start + index] = self.keys.index('mineral_dark')

    def insignia(self, scale=1.0, z=0.0):
        """Local XY icon, centered at the origin. Attribute: leaf growth;
        greater attribute: a central rhombus, two satellites and a crown."""
        s = scale
        if not self.greater:
            self.beam((0, -47*s, z), (0, 43*s, z), 3.3*s, 'metal_light')
            petals = [([(0, -19), (30, -3), (39, 22), (13, 16)], 'mineral'),
                      ([(0, -19), (-30, -3), (-39, 22), (-13, 16)], 'mineral'),
                      ([(0, 7), (14, 33), (0, 57), (-14, 33)], 'mineral')]
            for points, mat in petals:
                points = [(x*s, y*s) for x, y in points]
                # Fan center must lie inside each petal, not at room origin.
                cx = sum(x for x, _ in points) / len(points)
                cy = sum(y for _, y in points) / len(points)
                self.relief([(x-cx, y-cy) for x, y in points], 2.4*s, mat, (cx, cy, z))
                self.flat_outline(points, z+.4*s, 1.65*s, 'gold')
            self.beam((-17*s, -34*s, z), (0, -47*s, z), 2.4*s, 'metal_light')
            self.beam((0, -47*s, z), (17*s, -34*s, z), 2.4*s, 'metal_light')
        else:
            central = [(0, -52), (25, 0), (0, 58), (-25, 0)]
            points = [(x*s, y*s) for x, y in central]
            self.relief(points, 7*s, 'mineral', (0, 0, z))
            self.flat_outline(points, z+.5*s, 2.6*s, 'metal_light')
            self.beam((0, -48*s, z+1*s), (0, 51*s, z+7*s), 1.25*s, 'gold')
            for side in (-1, 1):
                cx, cy = 35*side*s, -3*s
                leaf = [(0, -24*s), (12*s, 0), (0, 28*s), (-12*s, 0)]
                self.relief(leaf, 4*s, 'mineral_dark', (cx, cy, z))
                self.flat_outline([(x+cx, y+cy) for x, y in leaf], z+.5*s, 1.8*s, 'gold')
                self.beam((side*8*s, -49*s, z), (side*44*s, -31*s, z), 3*s, 'metal_light')
                self.beam((side*44*s, -31*s, z), (side*50*s, -12*s, z), 3*s, 'gold')

    def place_icon_front(self, center, scale=1):
        start = len(self.v)
        self.insignia(scale)
        rotation = Matrix.Rotation(math.pi/2, 3, 'X')
        offset = Vector(center)
        self.v[start:] = [tuple(rotation @ Vector(p) + offset) for p in self.v[start:]]

    def themed_pillar(self):
        self.pillar(False)
        self.box((0, -36, 109), (40, 5, 123), 'metal_light', 2)
        self.box((0, -40, 109), (32, 3, 114), 'mineral_dark', 1)
        self.place_icon_front((0, -43, 105), .34)
        # A short independent inlay on the cap remains within Z=228.
        self.box((0, 0, 227.65), (22, 22, .7), 'mineral', .2)
        if self.greater:
            for side in (-1, 1):
                self.box((side*33.9, 0, 111), (2.4, 27, 118), 'metal_light', .7)
                self.box((side*35.4, 0, 111), (1.1, 10, 93), 'mineral_dark', .3)

    def themed_stele(self):
        self.stele()
        self.box((0, -27.7, 96), (112, 2.2, 146), 'mineral_dark', 3)
        for x in (-55, 55):
            self.beam((x, -30, 29), (x, -30, 163), 2.5, 'metal_light')
        for z in (29, 163):
            self.beam((-55, -30, z), (55, -30, z), 2.5, 'gold')
        if self.greater:
            # Inset chevrons give the upper-tier framing a distinct silhouette.
            for side in (-1, 1):
                self.beam((side*60, -40, 165), (side*44, -40, 177), 3.3, 'metal_light')
                self.beam((side*60, -40, 28), (side*44, -40, 16), 3.3, 'metal_light')

    def spawn_inlay(self):
        z = .45
        self.ring((0, 0, z), 308, 2.8, 'metal_light', n=96)
        self.ring((0, 0, z), 294, 1.8, 'gold', n=96)
        if self.greater:
            outer = [(math.cos(math.pi/6 + i*math.tau/6)*270,
                      math.sin(math.pi/6 + i*math.tau/6)*270) for i in range(6)]
            self.flat_outline(outer, z, 3.5, 'mineral_dark')
            for i in range(6):
                angle = math.pi/6 + i*math.tau/6
                r = 277
                diamond = [(-6, 0), (0, 13), (6, 0), (0, -13)]
                points = [(r*math.cos(angle)+x*math.cos(angle)-y*math.sin(angle),
                           r*math.sin(angle)+x*math.sin(angle)+y*math.cos(angle)) for x, y in diamond]
                self.polygon(points, z, .7, 'mineral')
            # Thin floor geometry only, no crystal spires in the fighting area.
            start = len(self.v)
            self.insignia(4.3, z)
            self.v[start:] = [(x, y, z + (zz-z)*.095) for x, y, zz in self.v[start:]]
        else:
            self.ring((0, 0, z), 260, 1.7, 'mineral_dark', n=96)
            for i in range(12):
                angle = i*math.tau/12
                self.beam((math.cos(angle)*273, math.sin(angle)*273, z),
                          (math.cos(angle)*288, math.sin(angle)*288, z), 2.2, 'metal_light')
            start = len(self.v)
            self.insignia(4.15, z)
            self.v[start:] = [(x, y, z + (zz-z)*.16) for x, y, zz in self.v[start:]]

    def themed_banner(self):
        self.beam((-37, 0, 152), (37, 0, 152), 4.2, 'metal_light', True)
        self.beam((0, 0, 136), (0, 18, 153), 4, 'bronze', True)
        for x in (-37, 37):
            self.cone((x, 0, 152), 6, 6, 5, 'gold', 12, Matrix.Rotation(math.pi/2, 3, 'Y'))
        verts = []
        for row in range(9):
            t = row/8
            for col in range(7):
                u = col/6
                z = 145-t*124-(12*abs(u-.5)*2 if row == 8 else 0)
                verts.append(((u-.5)*58, -4+math.sin(u*math.tau*1.4+t*2)*2.2, z))
        self.mesh(verts, [(r*7+c, r*7+c+1, (r+1)*7+c+1, (r+1)*7+c)
                          for r in range(8) for c in range(6)], 'teal')
        for side in (-1, 1):
            self.beam((side*28, -5, 144), (side*28, -5, 12), 1.6, 'metal_light')
        self.place_icon_front((0, -9, 91), .47 if self.greater else .53)


def replacements(theme):
    """Dictionary keyed by existing module names, ready for job.update()."""
    result = {}
    greater = theme == 'greater_attribute'
    label = '高阶紫晶' if greater else '翠玉成长'
    k = AttributeKit(theme, 1501)
    k.themed_pillar()
    result['b04_pillar_coin'] = dict(kit=k, label=label+'纹章墙柱')
    k = AttributeKit(theme, 1502)
    k.spawn_inlay()
    result['b08_spawn_inlay'] = dict(kit=k, label=label+'中央嵌纹（无光）')
    k = AttributeKit(theme, 1503)
    k.themed_stele()
    result['b09_coin_stele'] = dict(kit=k, label=label+'标识碑框')
    k = AttributeKit(theme, 1504)
    k.place_icon_front((0, -35, 95), 1.05)
    result['b09_coin_relief'] = dict(kit=k, label='三晶冠浮雕' if greater else '翠玉生长叶浮雕')
    k = AttributeKit(theme, 1505)
    k.themed_banner()
    result['b16_banner'] = dict(kit=k, label=label+'纹章挂旗')
    return result


def extra_modules(theme):
    """Optional perimeter ornaments; no colliders and no gameplay placement.

    Both meshes are grounded at Z=0. Place outside the enclosed combat floor,
    e.g. alongside the room's existing outer rock groups, never at spawn markers.
    """
    greater = theme == 'greater_attribute'
    result = []
    for index, small in enumerate((False, True)):
        k = AttributeKit(theme, 1601+index)
        size = 100 if small else 172
        k.rock((0, 0, 14), (size, size*.73, 33), 'rock')
        if greater:
            crystals = [(-24, 5, 26, 187, -14, 5),
                        (28, 16, 23, 145, 25, 13),
                        (20, -26, 18, 95, 24, -17),
                        (-44, -25, 14, 75, -20, -13)]
        else:
            crystals = [(-23, 8, 32, 127, -10, 8),
                        (27, 14, 28, 96, 19, 7),
                        (2, -26, 24, 71, 9, -15)]
        factor = .58 if small else 1
        for x, y, radius, height, tx, ty in crystals:
            k.crystal_prism((x*factor, y*factor, 17), radius*factor,
                            height*factor, (tx*factor, ty*factor))
            if greater and height > 120:
                k.cone((x*factor+tx*.10*factor, y*factor+ty*.10*factor, 17+height*.11*factor),
                       radius*1.02*factor, radius*1.02*factor, 7*factor, 'metal_light', 6)
        for side in (-1, 1):
            k.rock((side*size*.36, -size*.21, 9), (size*.3, size*.22, 21), 'stone_cool')
        lowest = min(p[2] for p in k.v)
        k.v = [(x, y, z-lowest) for x, y, z in k.v]
        result.append(dict(name='a17_mineral_cluster_'+('small' if small else 'large'),
                           label=('紫晶冠矿簇' if greater else '翠玉矿簇')+('·小' if small else '·大'),
                           kit=k, category='nature', collision=[]))
    return result
