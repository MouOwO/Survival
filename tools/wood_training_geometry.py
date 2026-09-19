"""Timber practice courtyard modules; dimensions match the gold-room sockets.

Source units, +Z up, signs face -Y.  ``replacements`` overrides gold module
names without touching their placement grid.  Grain metadata is per original
face (parallel to ``f``): a normalized world-space fibre axis, or ``None``.
Keep/remap that metadata when triangulating.  ``wood_end`` already labels true
end cuts; its UV should be projected across the end face, not down the grain.
"""
import math

from mathutils import Matrix, Vector

from gold_room_geometry import GoldKit, PALETTE as GOLD_PALETTE


EXTRA_KEYS = ('wood_light', 'wood_end', 'iron', 'bark')
TIMBER_KEYS = {'wood', 'wood_light', 'bark'}


class WoodKit(GoldKit):
    def __init__(self, seed=1):
        super().__init__(seed)
        self.keys = list(GOLD_PALETTE) + [key for key in EXTRA_KEYS if key not in GOLD_PALETTE]
        self.grain_axis = []

    def mesh(self, verts, faces, mat='stone'):
        before = len(self.f)
        super().mesh(verts, faces, mat)
        self.grain_axis.extend([None] * (len(self.f) - before))

    def grain_since(self, first_face, axis, end_cuts=True):
        axis = Vector(axis).normalized()
        for index in range(first_face, len(self.f)):
            self.grain_axis[index] = tuple(axis)
            if not end_cuts or self.keys[self.m[index]] not in TIMBER_KEYS:
                continue
            face = self.f[index]
            a, b, c = (Vector(self.v[v]) for v in face[:3])
            normal = (b - a).cross(c - a).normalized()
            if abs(normal.dot(axis)) > .93:
                self.m[index] = self.keys.index('wood_end')

    def timber(self, center, size, mat='wood', bevel=1.4, rotation=None, axis=None):
        first = len(self.f)
        self.box(center, size, mat, bevel, rotation)
        if axis is None:
            long = max(range(3), key=lambda i: size[i])
            axis = Vector(tuple(1 if i == long else 0 for i in range(3)))
            if rotation is not None:
                axis = rotation @ axis
        self.grain_since(first, axis)

    def timber_beam(self, a, b, width=12, mat='wood_light'):
        a, b = Vector(a), Vector(b)
        axis = b - a
        rotation = axis.to_track_quat('Z', 'Y').to_matrix()
        self.timber((a + b) / 2, (width, width, axis.length), mat, 1.1, rotation, axis)

    def log(self, a, b, radius=18, mat='bark', bands=False):
        a, b = Vector(a), Vector(b)
        axis = (b - a).normalized()
        rotation = axis.to_track_quat('Z', 'Y').to_matrix()
        first = len(self.f)
        self.cone((a + b) / 2, radius, radius * .96, (b - a).length, mat, 12, rotation)
        self.grain_since(first, axis)
        # Ring-shaped straps have a hollow middle; no coincident cap polygons.
        if bands:
            for t in (.20, .80):
                self.ring(a.lerp(b, t), radius + .7, 1.6, 'iron', rotation, n=16)

    def bolt(self, center, normal=(0, -1, 0), radius=2.6):
        rotation = Vector(normal).to_track_quat('Z', 'Y').to_matrix()
        self.cone(center, radius, radius * .65, 2.1, 'iron', 8, rotation)

    def transform_since(self, start, angle=0, offset=(0, 0, 0)):
        super().transform_since(start, angle, offset)
        rotation = Matrix.Rotation(angle, 3, 'Z')
        for index, face in enumerate(self.f):
            if face and min(face) >= start and self.grain_axis[index] is not None:
                self.grain_axis[index] = tuple(rotation @ Vector(self.grain_axis[index]))

    def plank_floor(self, worn=False, variant=0):
        # The complete walking surface stays at Z=0; cracks have a backing.
        self.box((0, 0, -13), (256, 256, 4), 'wood', 0)
        for column in range(8):
            x = -112 + column * 32
            joint = (-48, 20, 68, -12)[(column + variant) % 4]
            for a, b in ((-128, joint), (joint, 128)):
                key = 'wood_light' if (column + variant) % 3 else 'wood'
                if worn and column == 5 and a == joint:
                    # Separate splinter edges, safely recessed below the floor.
                    points = [(x - 15, a + 1), (x - 2, a + 1), (x + 1, a + 23),
                              (x - 1, b - 1), (x - 15, b - 1)]
                    first = len(self.f)
                    self.polygon(points, -12, 11.7, key)
                    self.grain_since(first, (0, 1, 0))
                    self.timber((x + 8.5, (a + b) / 2, -6), (12, b - a - 2, 12), 'wood', .8, axis=(0, 1, 0))
                else:
                    self.timber((x, (a + b) / 2, -6), (30.4, b - a - 1.4, 12), key, .9, axis=(0, 1, 0))
                for y in (a + 6, b - 6):
                    # Nail heads are flush, so top surfaces never impede movement.
                    self.cone((x - 9, y, -.45), 1.6, 1.6, .5, 'iron', 6)

    def timber_wall(self, length=256):
        for index in range(round(length / 64)):
            self.stone((-length / 2 + (index + .5) * 64, 0, 8), (63, 49, 16))
        count = max(4, round(length / 25.6))
        pitch = length / count
        for index in range(count):
            x = -length / 2 + (index + .5) * pitch
            self.timber((x, 0, 91), (pitch - 1.2, 29, 150),
                        'wood_light' if index % 4 == 1 else 'wood', 1.3, axis=(0, 0, 1))
        # Two faces remain readable; module ends stay square and tile cleanly.
        for side in (-1, 1):
            for z in (42, 140):
                self.timber((0, side * 20, z), (length, 10, 17), 'wood_light', 1.0, axis=(1, 0, 0))
            for span in range(max(1, round(length / 128))):
                x0 = -length / 2 + span * 128 + 10
                x1 = min(length / 2 - 10, x0 + 108)
                self.timber_beam((x0, side * 22, 53), (x1, side * 22, 130), 8, 'wood')
                for x, z in ((x0, 43), (x1, 140)):
                    self.bolt((x, side * 27, z), (0, side, 0))
        self.timber((0, 0, 167), (length, 56, 18), 'wood_light', 1.8, axis=(1, 0, 0))

    def timber_pillar(self, badge=False):
        self.stone((0, 0, 10), (84, 84, 20), True)
        self.timber((0, 0, 108), (64, 64, 176), 'wood', 2.8, axis=(0, 0, 1))
        for z in (35, 184):
            for side in (-1, 1):
                self.box((0, side * 33, z), (68, 3.5, 13), 'iron', .6)
                self.box((side * 33, 0, z), (3.5, 63, 13), 'iron', .6)
                for x in (-23, 23):
                    self.bolt((x, side * 36, z), (0, side, 0))
        self.timber((0, 0, 202), (84, 84, 20), 'wood_light', 2.6, axis=(0, 0, 1))
        self.timber((0, 0, 220), (52, 52, 16), 'wood_light', 2.1, axis=(0, 0, 1))
        if badge:
            self.box((0, -34, 111), (43, 4, 102), 'iron', 1.5)
            for x, z in ((-10, 90), (10, 90), (0, 111)):
                self.log((x, -38, z), (x, -47, z), 9, 'wood_light')
            # Simple axe above the timber emblem, not the old coin symbol.
            self.timber_beam((-12, -41, 134), (12, -41, 154), 3, 'wood_light')
            self.box((8, -42, 151), (19, 3, 9), 'iron', .8)

    def timber_arc(self):
        count = 12
        for index in range(count):
            angle = math.radians(60 + (index + .5) * 60 / count)
            rotation = Matrix.Rotation(angle + math.pi / 2, 3, 'Z')
            self.timber((256 * math.cos(angle), 256 * math.sin(angle), 90),
                        (21.3, 36, 148), 'wood_light' if index % 4 == 0 else 'wood',
                        1.4, rotation, (0, 0, 1))
        for index in range(6):
            a = math.radians(60 + index * 10)
            b = a + math.radians(10)
            self.sector(231, 281, a, b, 0, 16, 'stone', steps=2)
            for z, inner, outer, height in ((40, 235, 277, 12), (138, 235, 277, 12), (158, 228, 284, 18)):
                first = len(self.f)
                self.sector(inner, outer, a, b, z, height, 'wood_light', steps=2)
                self.grain_since(first, (-math.sin((a + b) / 2), math.cos((a + b) / 2), 0), False)

    def lumber_badge(self, radius=250, z=.3):
        for ring_radius, thickness in ((radius, 3.2), (radius - 15, 1.6)):
            self.ring((0, 0, z), ring_radius, thickness, 'bronze', n=72)
        # Flat crossed axe emblem, with broad heads visible from the game camera.
        for angle in (-math.pi / 4, math.pi / 4):
            start = len(self.v)
            self.timber((0, 0, z + .7), (12, radius * 1.2, 1.2), 'wood_light', .25, axis=(0, 1, 0))
            self.polygon([(-6, radius * .35), (-55, radius * .33), (-66, radius * .56),
                          (-18, radius * .63), (-6, radius * .52)], z + 1, .7, 'iron')
            self.transform_since(start, angle)
        self.polygon([(-20, 0), (0, 22), (20, 0), (0, -22)], z + 1.8, .4, 'bronze')

    def timber_portal(self):
        self.cone((0, 0, 5), 184, 184, 10, 'wood', 48)
        self.cone((0, 0, 11), 141, 141, 8, 'teal', 48)
        for index in range(20):
            a, b = index * math.tau / 20 + .004, (index + 1) * math.tau / 20 - .004
            first = len(self.f)
            self.sector(143, 185, a, b, 0, 17, 'wood_light' if index % 3 else 'wood', steps=2)
            self.grain_since(first, (math.cos((a + b) / 2), math.sin((a + b) / 2), 0))
            self.bolt((168 * math.cos((a + b) / 2), 168 * math.sin((a + b) / 2), 17), (0, 0, 1), 2.2)
        for radius in (143, 184):
            self.ring((0, 0, 12), radius, 2.2, 'iron', n=64)
        self.crest(132, 15, True)

    def timber_sign_frame(self):
        for x in (-66, 66):
            self.stone((x, 0, 9), (33, 54, 18))
            self.timber((x, 0, 101), (22, 40, 178), 'wood', 2, axis=(0, 0, 1))
        for index in range(6):
            self.timber((-45 + index * 18, 4, 99), (17.2, 15, 142),
                        'wood_light' if index % 2 else 'wood', .8, axis=(0, 0, 1))
        for z in (22, 181):
            self.timber((0, -6, z), (154, 28, 23), 'wood_light', 1.8, axis=(1, 0, 0))
            for x in (-66, 66):
                self.box((x, -22, z), (22, 4, 24), 'iron', .6)
                self.bolt((x, -25, z))

    def timber_sign_relief(self):
        for x, z in ((-24, 65), (24, 65), (0, 107)):
            self.log((x, -22, z), (x, -48, z), 22, 'bark')
            # Shallow segmented cut rings give an unmistakable sawn-log silhouette.
            rotation = Matrix.Rotation(math.pi / 2, 3, 'X')
            self.ring((x, -49, z), 15, .8, 'wood', rotation, n=20)
            self.ring((x, -49, z), 8, .7, 'wood', rotation, n=16)
        self.timber_beam((-39, -28, 144), (35, -28, 164), 5, 'wood_light')
        self.box((24, -30, 163), (29, 5, 15), 'iron', 1.0)

    def timber_flag(self):
        self.timber_beam((-38, 0, 152), (38, 0, 152), 5, 'wood_light')
        self.beam((0, 0, 136), (0, 18, 153), 4, 'iron', True)
        vertices = []
        for row in range(9):
            t = row / 8
            for column in range(7):
                u = column / 6
                vertices.append(((u - .5) * 58, -4 + math.sin(u * math.tau * 1.4 + t * 2) * 2.2,
                                 145 - t * 124 - (12 * abs(u - .5) * 2 if row == 8 else 0)))
        self.mesh(vertices, [(r * 7 + c, r * 7 + c + 1, (r + 1) * 7 + c + 1, (r + 1) * 7 + c)
                             for r in range(8) for c in range(6)], 'teal')
        for side in (-1, 1):
            self.beam((side * 28, -7, 144), (side * 28, -7, 12), 1.3, 'bronze')
        for x, z in ((-8, 76), (8, 76), (0, 93)):
            self.log((x, -9, z), (x, -11, z), 7, 'wood_light')
        self.timber_beam((-14, -11, 110), (13, -11, 132), 2.3, 'wood_light')
        self.box((9, -12, 130), (17, 2, 8), 'iron', .6)


def _box(center, size):
    return dict(center=center, size=size)


def _niche_floor():
    kit = WoodKit(1604)
    # Exact semicircle footprint avoids square decking projecting outside the wall.
    radius = 254
    for row in range(8):
        a, b = row * 32 + .6, min(254, (row + 1) * 32 - .6)
        xa, xb = math.sqrt(radius * radius - a * a), math.sqrt(max(0, radius * radius - b * b))
        points = [(-xa, a), (xa, a), (xb, b)]
        if xb > .001:
            points.append((-xb, b))
        first = len(kit.f)
        kit.polygon(points, -14, 14, 'wood_light' if row % 3 else 'wood')
        kit.grain_since(first, (1, 0, 0))
        for x in (-xb * .8, xb * .8):
            kit.cone((x, (a + b) / 2, -.4), 1.7, 1.7, .5, 'iron', 6)
    return kit


def replacements():
    """Mapping of existing gold module names to compatible timber jobs."""
    jobs = {}
    def add(name, label, kit, collision=None):
        jobs[name] = dict(kit=kit, label=label, collision=collision or [])

    for variant, name in enumerate(('b01_floor_a', 'b01_floor_b', 'b02_floor_worn')):
        kit = WoodKit(1600 + variant)
        kit.plank_floor(variant == 2, variant)
        add(name, ('错缝木板 A', '错缝木板 B', '磨损开裂木板')[variant], kit)
    add('b01_niche_floor', '传送壁龛半圆木地板', _niche_floor())
    for length in (256, 128):
        kit = WoodKit(1632 + length)
        kit.timber_wall(length)
        add(f'b03_wall_{length}', f'横梁斜撑木围墙 {length}', kit, [_box((0, 0, 88), (length, 48, 176))])
    for badge in (False, True):
        kit = WoodKit(1643 + badge)
        kit.timber_pillar(badge)
        add('b04_pillar' + ('_coin' if badge else ''), '木材徽记铁箍柱' if badge else '铁箍木柱', kit,
            [_box((0, 0, 114), (78, 78, 228))])
    kit = WoodKit(1655)
    for angle in (0, math.pi / 2):
        start = len(kit.v)
        kit.timber_wall(128)
        kit.transform_since(start, angle, (math.cos(angle) * 64, math.sin(angle) * 64, 0))
    add('b05_corner', '直角木围墙', kit, [_box((64, 0, 88), (128, 48, 176)), _box((0, 64, 88), (48, 128, 176))])
    kit = WoodKit(1666)
    kit.timber_arc()
    hulls = []
    for index in range(5):
        a = math.radians(60 + index * 12)
        b = a + math.radians(12)
        hulls.append(dict(vertices=[(r * math.cos(angle), r * math.sin(angle), z)
                                   for z in (0, 176) for r, angle in ((232, a), (280, a), (280, b), (232, b))]))
    add('b06_arc_60', '60 度立板木弧墙', kit, hulls)
    for name, label, function in (
        ('b07_teleport_base', '木边传送底座与金属嵌件（无光）', 'timber_portal'),
        ('b08_spawn_inlay', '中央交叉斧木材地纹（无光）', 'lumber_badge'),
        ('b09_coin_stele', '木材标识木框', 'timber_sign_frame'),
        ('b09_coin_relief', '圆木堆与斧具标识', 'timber_sign_relief'),
        ('b16_banner', '木支架木材徽记挂旗', 'timber_flag'),
    ):
        kit = WoodKit(1670 + len(jobs))
        getattr(kit, function)()
        collision = [_box((0, 0, 98), (152, 54, 196))] if name == 'b09_coin_stele' else []
        add(name, label, kit, collision)
    # Wall lamps also gain wooden joinery instead of retaining a stone pedestal.
    kit = WoodKit(1710)
    kit.timber((0, 0, 28), (63, 63, 56), 'wood', 2, axis=(0, 0, 1))
    kit.timber((0, 0, 60), (74, 74, 12), 'wood_light', 1.6, axis=(0, 0, 1))
    for side in (-1, 1):
        kit.box((0, side * 32, 17), (65, 3, 10), 'iron', .5)
        kit.box((side * 32, 0, 17), (3, 62, 10), 'iron', .5)
    add('b10_brazier_plinth', '铁箍木灯台', kit)
    return jobs


def extra_modules():
    """Optional perimeter props. Keep them outside the clear battle rectangle."""
    jobs = []
    kit = WoodKit(1810)
    for z, offsets in ((23, (-42, 0, 42)), (58, (-21, 21)), (93, (0,))):
        for y in offsets:
            kit.log((-108, y, z), (108 + kit.rng.uniform(-9, 9), y, z), 20, bands=True)
    for x in (-75, 75):
        kit.timber((x, 0, 7), (24, 133, 14), 'wood', 1, axis=(0, 1, 0))
    jobs.append(dict(name='w17_log_stack', label='外围捆扎原木垛', category='nature', kit=kit,
                     collision=[_box((0, 0, 57), (224, 123, 114))]))
    kit = WoodKit(1811)
    for x in (-65, 65):
        kit.timber_beam((x, -33, 0), (x, 32, 87), 12, 'wood_light')
        kit.timber_beam((x, 33, 0), (x, -32, 87), 12, 'wood_light')
        kit.bolt((x - 7, 0, 44), (-1, 0, 0), 4)
    kit.timber_beam((-74, 0, 28), (74, 0, 28), 9, 'wood')
    kit.log((-111, 0, 82), (111, 0, 82), 21, 'bark')
    # A narrow hand-saw leaning along the front support: blade, teeth and handle.
    kit.box((9, -28, 46), (111, 3, 12), 'iron', .2)
    for x in range(-42, 63, 7):
        vertices = [(xx, y, z) for y in (-29.5, -26.5)
                    for xx, z in ((x, 40), (x + 5, 40), (x + 1, 35))]
        kit.mesh(vertices, [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)], 'iron')
    kit.timber((75, -28, 46), (22, 9, 25), 'wood_light', 2, axis=(0, 0, 1))
    jobs.append(dict(name='w18_sawhorse', label='外围锯木架与原木', category='nature', kit=kit,
                     collision=[_box((0, 0, 52), (224, 82, 104))]))
    return jobs
