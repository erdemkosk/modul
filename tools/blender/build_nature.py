"""The taiga round the town: Scots pines, spruces and birches, a dead snag, fallen trunks, stumps and a
heap of lopped branches, juniper and willow scrub, ferns, mossy boulders and pieces of cliff. Made as
the buildings and props are (tools/blender/build_buildings.py): no textures, the colours painted into
the vertices, the shade of the crown's inside and of the ground baked into them.

    blender --background --factory-startup --python tools/blender/build_nature.py [-- --only=pine_a,rock_b] [-- --raw]

(--raw: without the baked occlusion, a quick look at shapes.)

Blender: +Z up, the ground at 0, the origin at the foot of the trunk (or the middle of a rock's or
log's footprint). Trunks, roots and rocks go on down under 0, so on a slope nothing shows a gap under
its low side.

Each model is two objects: "LOD0", the full one, and "LOD1", the same silhouette in a few hundred
triangles for far off (scripts/world_props.gd crossfades between them, and the LOD1 casts the shadows).
Each object has one material per stuff, named for what the game does with it (scripts/world_props.gd,
shaders/nature.gdshader): Bark, BirchBark, DeadWood, Wood (bark and cut wood: rigid but bending with
the trunk), Needles, Leaves, FernLeaf (foliage: fluttering; Leaves turn in the autumn and fall), Rock,
Earth.

Output: assets/nature/<id>.glb, and assets/nature/nature.json (per id: kind, species, height,
collision hints in Godot axes, triangle counts).

  spruce_a..e   Norway spruce: drooping tiers of branches with hanging fringes, a narrow spire
  pine_a..e     Scots pine: grey furrowed bark below, flaking orange above, a high flat clumped crown
  birch_a..e    silver birch: white bark marked black, dark and fissured at the foot, airy drooping crown
  dead_tree(_b) a grey snag broken off, stubs of branches; a leaning one with a few bare limbs left
  log, log_b    a fallen trunk with its root plate torn up; a long-dead one, broken, mossed over
  branches      a heap of lopped branches, the needles gone brown
  stump(_b,_c)  a sawn stump, its rings showing; one broken off jagged; an old one rotting and mossy
  bush_a..c     juniper; a willow shrub; a low juniper spread
  fern(_b)      a clump of bracken fronds; a smaller one
  rock_a..e     granite boulders, glacier-rounded and split, mossed and lichened on top; a flat slab; a
                group of three
  cliff_a, _b   rock outcrops in ledges, bedded and split, mossed on the ledges, fallen blocks at the foot
"""

import json
import math
import os
import random
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector, noise  # noqa: E402

import build_buildings as B  # noqa: E402

B.OUT = os.path.join(B.ROOT, "assets", "nature")
TAU = math.tau
Z = Vector((0, 0, 1))
RAW = False

# --- colours (the buildings' value range: a colour here reads in the game as B.BARK does) ----------

SPRUCE_N = (0.17, 0.25, 0.13)
PINE_N = (0.2, 0.26, 0.12)
BIRCH_L = (0.3, 0.37, 0.15)
JUNIPER = (0.21, 0.27, 0.15)
WILLOW = (0.34, 0.39, 0.19)
FERN_C = (0.38, 0.45, 0.17)
BARK_SPRUCE = (0.33, 0.27, 0.22)
BARK_PINE = (0.35, 0.28, 0.22)
BARK_PINE_TOP = (0.52, 0.38, 0.27)
BIRCH_W = (0.83, 0.81, 0.75)
BIRCH_MARK = (0.14, 0.12, 0.11)
BIRCH_FOOT = (0.25, 0.23, 0.2)
TWIG = (0.3, 0.22, 0.17)
DEAD = (0.55, 0.52, 0.47)
DEAD_BARK = (0.32, 0.26, 0.21)
DRY_NEEDLE = (0.42, 0.33, 0.22)
ROCK = (0.52, 0.51, 0.48)
ROCK_WARM = (0.56, 0.52, 0.46)
LICHEN = (0.74, 0.72, 0.62)
MOSS = (0.32, 0.38, 0.16)
MOSS_DRY = (0.42, 0.42, 0.22)
EARTH = (0.24, 0.19, 0.13)
END = B.END_GRAIN

FOLIAGE = ("Needles", "Leaves", "FernLeaf")
WOOD = ("Bark", "BirchBark", "DeadWood", "Wood")


def mul(c, k):
    return (c[0] * k, c[1] * k, c[2] * k)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def jit(c, amt, rng):
    """A colour a little lighter or darker, and a little warmer or greener."""
    k = 1.0 + rng.uniform(-amt, amt)
    h = rng.uniform(-amt, amt) * 0.5
    return (c[0] * k * (1 + h), c[1] * k, c[2] * k * (1 - h))


def nz(p, s=1.0, o=0.0):
    return noise.noise(Vector((p[0] * s + o, p[1] * s - o * 0.7, p[2] * s + o * 0.3)))


# --- a mesh being made: one bmesh, a material per stuff, a colour at every corner -----------------

class Mesh:
    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")
        self.mats = []

    def mat(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def face(self, verts, cols, mat, smooth=True):
        """A face on `verts` (BMVerts or points), `cols` one colour for all or one per corner."""
        vs = [v if isinstance(v, bmesh.types.BMVert) else self.bm.verts.new(v) for v in verts]
        try:
            f = self.bm.faces.new(vs)
        except ValueError:
            return None
        f.material_index = self.mat(mat)
        f.smooth = smooth
        for i, loop in enumerate(f.loops):
            c = cols[i] if isinstance(cols, list) else cols
            loop[self.col] = (min(c[0], 1.0), min(c[1], 1.0), min(c[2], 1.0), 1.0)
        return f

    def paint(self, faces, fn, mat, smooth=True):
        """Faces made by a bmesh op given a material and coloured by fn(point, face normal)."""
        mi = self.mat(mat)
        for f in faces:
            f.material_index = mi
            f.smooth = smooth
            f.normal_update()
            for loop in f.loops:
                c = fn(loop.vert.co, f.normal)
                loop[self.col] = (min(c[0], 1.0), min(c[1], 1.0), min(c[2], 1.0), 1.0)

    def tris(self):
        return sum(len(f.verts) - 2 for f in self.bm.faces)

    def to_object(self, name):
        me = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for n in self.mats:
            me.materials.append(B._material(n))
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.color_attributes.active_color = me.color_attributes["Col"]
        me.color_attributes.render_color_index = me.color_attributes.find("Col")
        return ob


def frames(pts):
    """Tangents and a twist-free side vector along a polyline."""
    tans = []
    for i in range(len(pts)):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, len(pts) - 1)]
        tans.append((b - a).normalized())
    u = tans[0].cross(Z)
    if u.length < 1e-3:
        u = tans[0].cross(Vector((1, 0, 0)))
    us = [u.normalized()]
    for i in range(1, len(pts)):
        q = tans[i - 1].rotation_difference(tans[i])
        u = q @ us[-1]
        u = (u - tans[i] * u.dot(tans[i])).normalized()
        us.append(u)
    return tans, us


def tube(m, pts, radii, mat, color, segs=8, cap=True, base_cap=False, rough=0.0, seed=0.0, flat=False, jag=None):
    """A tube along `pts` (Vectors), `radii` at each; color(point, t along, angle 0..1) per corner.
    rough: the girth wavers (bark plates, a root flare's lobes). jag(i) lifts or drops the last
    ring's i-th corner (a broken top). Returns the rings."""
    tans, us = frames(pts)
    rings = []
    n = len(pts)
    for i, (p, r) in enumerate(zip(pts, radii)):
        t = tans[i]
        u = us[i]
        v = t.cross(u)
        ring = []
        for s in range(segs):
            a = s / segs * TAU
            d = u * math.cos(a) + v * math.sin(a)
            rr = r * (1.0 + rough * nz(p + d * 0.6, 1.3, seed)) if rough else r
            q = p + d * rr
            if jag and i == n - 1:
                q = q + t * jag(s)
            ring.append(m.bm.verts.new(q))
        rings.append(ring)
    for i in range(n - 1):
        for s in range(segs):
            s1 = (s + 1) % segs
            q = [rings[i][s], rings[i][s1], rings[i + 1][s1], rings[i + 1][s]]
            ti = (i, i, i + 1, i + 1)
            si = (s, s1, s1, s)
            m.face(q, [color(q[k].co, ti[k] / (n - 1), si[k] / segs) for k in range(4)], mat, smooth=not flat)
    if cap:
        c = m.bm.verts.new(pts[-1] + tans[-1] * radii[-1] * 0.15)
        for s in range(segs):
            q = [c, rings[-1][s], rings[-1][(s + 1) % segs]]
            m.face(q, [color(v.co, 1.0, -1.0) for v in q], mat, smooth=not flat)
    if base_cap:
        c = m.bm.verts.new(pts[0])
        for s in range(segs):
            q = [c, rings[0][(s + 1) % segs], rings[0][s]]
            m.face(q, [color(v.co, 0.0, -1.0) for v in q], mat, smooth=not flat)
    return rings


def bend_line(a, b, n, sag=0.0, wobble=0.0, seed=0.0, up=0.0):
    """n points from a to b, bowing down by `sag` and up toward the end by `up` (fractions of the
    length), wandering by `wobble`."""
    a, b = Vector(a), Vector(b)
    L = (b - a).length
    pts = []
    for i in range(n):
        t = i / (n - 1)
        p = a.lerp(b, t)
        p = p - Z * (sag * L * math.sin(math.pi * t) * 0.5) + Z * (up * L * t * t)
        if wobble and 0 < i < n - 1:
            p = p + Vector((nz(p, 0.7, seed), nz(p, 0.7, seed + 3.1), nz(p, 0.7, seed + 7.7) * 0.5)) * wobble * L
        pts.append(p)
    return pts


def blob(m, c, size, mat, color, rng, subdiv=2, lump=0.25, under=0.6, yaw=None, smooth=True, tilt=None):
    """A lumpy, flattened ball: a clump of needles or leaves (or a stone, flat-shaded).
    under: how much of its lower half is pressed flat. color(point, normal from the middle)."""
    res = bmesh.ops.create_icosphere(m.bm, subdivisions=subdiv, radius=1.0)
    verts = res["verts"]
    o = rng.uniform(0, 100)
    yaw = rng.uniform(0, TAU) if yaw is None else yaw
    rot = Matrix.Rotation(yaw, 3, "Z")
    if tilt is not None:
        rot = tilt @ rot
    c = Vector(c)
    dirs = {}
    for v in verts:
        n = v.co.normalized()
        d = 1.0 + lump * nz(n, 1.6, o) + lump * 0.7 * nz(n, 3.9, o + 9.0)
        p = n * d
        if p.z < 0:
            p.z *= (1.0 - under)
        p = Vector((p.x * size[0], p.y * size[1], p.z * size[2]))
        v.co = c + rot @ p
        dirs[v] = rot @ n
    faces = list({f for v in verts for f in v.link_faces})
    mi = m.mat(mat)
    for f in faces:
        f.material_index = mi
        f.smooth = smooth
        f.normal_update()
        for loop in f.loops:
            col = color(loop.vert.co, dirs[loop.vert] if smooth else f.normal)
            loop[m.col] = (min(col[0], 1.0), min(col[1], 1.0), min(col[2], 1.0), 1.0)
    return verts


# --- bark -------------------------------------------------------------------------------------------

def bark_fn(base, rng, top=None, top_from=0.5, height=10.0, moss=0.0, furrow=0.8, seed=0.0, marks=None):
    """Bark: vertical furrows (every third strip darker), plates, knots; `top` the colour it goes to
    above top_from of `height` (a pine's orange); moss low on one side."""
    cache = {}

    def fn(p, t, a):
        key = (round(p.x, 3), round(p.y, 3), round(p.z, 3), round(a, 3))
        if key in cache:
            return cache[key]
        c = base
        if top is not None:
            c = mix(base, top, (p.z / height - top_from) / 0.2 + nz(p, 1.1, seed) * 0.6)
        stripe = 0.5 + 0.5 * math.sin(a * TAU * 7.0 + nz(p, 0.6, seed) * 4.0 + p.z * 0.15)
        c = mul(c, 1.0 - (1.0 - furrow) * stripe ** 3)
        c = mul(c, 0.92 + 0.16 * nz(p, 2.3, seed + 5.0))
        if marks:
            c = marks(p, a, c)
        if moss and p.z < 1.6:
            side = nz(p, 0.9, seed + 2.0) + (0.6 if 0.3 < (a % 1.0) < 0.7 else -0.2)
            if side > 0.25 + p.z * 0.4:
                c = mix(c, jit(MOSS, 0.1, rng), moss)
        cache[key] = c
        return c
    return fn


def trunk_points(H, lean, seed, bottom=-1.0, n=None, sweep=0.0):
    """The trunk's line from under the ground to its top: leaning and wandering a little; a pine's
    `sweep` bows its foot."""
    n = n or max(6, int(H / 1.6) + 4)
    pts = []
    for i in range(n):
        t = i / (n - 1)
        z = bottom + (H - bottom) * t
        h = max(z, 0.0) / H
        off = Vector((lean[0] * h * H, lean[1] * h * H, 0))
        off += Vector((nz((0, 0, z), 0.12, seed), nz((0, 0, z), 0.12, seed + 4.0), 0)) * 0.012 * H * h
        off += Vector((sweep, 0, 0)) * math.sin(min(h * 3.0, 1.0) * math.pi * 0.5) * (1 - h) * H * 0.02
        pts.append(Vector((0, 0, z)) + off)
    return pts


def trunk_radii(pts, H, r0, flare=1.6, top=0.02):
    out = []
    for p in pts:
        h = min(max(p.z, 0.0) / H, 1.0)
        r = r0 * (1.0 - h) ** 0.85 + top
        if p.z < 0.6:
            r *= 1.0 + (flare - 1.0) * (1.0 - max(p.z, 0.0) / 0.6) ** 2
        out.append(r)
    return out


def trunk_at(pts, z):
    """The trunk line's point at height z."""
    for a, b in zip(pts, pts[1:]):
        if a.z <= z <= b.z:
            return a.lerp(b, (z - a.z) / max(b.z - a.z, 1e-6))
    return pts[-1].copy()


def roots(m, r0, n, mat, color, rng, segs=5, reach=2.6):
    """Root buttresses: flared lobes from the trunk's foot down into the ground."""
    for i in range(n):
        a = (i + rng.uniform(-0.3, 0.3)) / n * TAU
        d = Vector((math.cos(a), math.sin(a), 0))
        L = r0 * reach * rng.uniform(0.8, 1.2)
        pts = [d * r0 * 0.3 + Z * r0 * 1.6, d * (r0 * 0.85) + Z * r0 * 0.45, d * (r0 * 0.9 + L * 0.45) - Z * (L * 0.12), d * (r0 + L) - Z * (0.3 + L * 0.3)]
        tube(m, pts, [r0 * 0.55, r0 * 0.45, r0 * 0.26, r0 * 0.08], mat, color, segs=segs, cap=True)


# --- spruce -----------------------------------------------------------------------------------------

def fan(m, root, d, L, width, droop, curl, base, rng, fringe=0.14, stations=4, mat="Needles", lod=0):
    """A spruce bough seen as one mass: a shallow roof of needles from the trunk out, drooping and
    turning up at the tip, its lower edges hung with a ragged fringe of branchlets."""
    side = d.cross(Z).normalized()
    up = side.cross(d).normalized()
    rows = []
    tip = None
    for k in range(stations + 1):
        t = k / stations
        p = root + d * (L * t) + Z * (-droop * L * t * t + curl * L * t ** 3)
        if k == stations:
            tip = p
            break
        w = width * L * (0.35 + 0.65 * math.sin(math.pi * min(0.15 + t * 0.85, 1.0))) * (1.0 - 0.5 * t ** 2)
        ridge = p + up * (w * 0.28)
        el = p - side * w - up * (w * 0.1)
        er = p + side * w - up * (w * 0.1)
        hang = L * fringe * min(t * 2.5, 1.0) + 0.05
        fl = el - Z * hang * rng.uniform(0.6, 1.3) + side * (w * 0.1)
        fr = er - Z * hang * rng.uniform(0.6, 1.3) - side * (w * 0.1)
        rows.append(([fl, el, ridge, er, fr], t))
    shade = rng.uniform(0.85, 1.12)
    tone = jit(base, 0.1, rng)

    def col(j, t):
        c = mul(tone, shade * (0.7 + 0.45 * t))
        if j == 2:
            c = mix(mul(c, 1.2), (c[0] * 1.35, c[1] * 1.25, c[2] * 0.9), t)  # (the sunlit ridge, new growth at the tip)
        elif j in (0, 4):
            c = mul(c, 0.68)
        return c
    vs = [[m.bm.verts.new(q) for q in r[0]] for r in rows]
    tv = m.bm.verts.new(tip)
    js = range(4) if lod == 0 else range(1, 3)
    for k in range(len(rows) - 1):
        t0, t1 = rows[k][1], rows[k + 1][1]
        for j in js:
            m.face([vs[k][j], vs[k][j + 1], vs[k + 1][j + 1], vs[k + 1][j]], [col(j, t0), col(j + 1, t0), col(j + 1, t1), col(j, t1)], mat)
    t0 = rows[-1][1]
    for j in js:
        m.face([vs[-1][j], vs[-1][j + 1], tv], [col(j, t0), col(j + 1, t0), col(2, 1.0)], mat)


def spruce(H, crown_base, R, droop, seed, lod, r0=None, narrow=1.0, double_top=False):
    rng = random.Random(seed)
    m = Mesh()
    r0 = r0 or H * 0.0145
    lean = (rng.uniform(-0.01, 0.01), rng.uniform(-0.01, 0.01))
    pts = trunk_points(H * 0.985, lean, seed * 0.37, n=None if lod == 0 else 5)
    radii = trunk_radii(pts, H, r0)
    bark = bark_fn(BARK_SPRUCE, rng, height=H, moss=0.5, seed=seed * 0.1)
    tube(m, pts, radii, "Bark", bark, segs=9 if lod == 0 else 5, rough=0.06 if lod == 0 else 0.0, seed=seed)
    if lod == 0:
        roots(m, r0 * 1.3, 5, "Bark", bark, rng)
    span = H - crown_base

    def reach(z):
        x = max(0.0, min(1.0, (H - z) / span))
        return R * (x ** 0.92) * (0.18 + 0.82 * min(1.0, x * 3.0 + 0.55)) * narrow

    if lod == 0:
        z = crown_base
        k = 0
        while z < H - 0.5:
            x = (H - z) / span
            n = 6 if x > 0.25 else 5
            off = k * 2.39996
            for i in range(n):
                a = off + i / n * TAU + rng.uniform(-0.25, 0.25)
                d = Vector((math.cos(a), math.sin(a), 0))
                L = reach(z) * rng.uniform(0.78, 1.12)
                if L < 0.25:
                    continue
                zz = z + rng.uniform(-0.1, 0.1)
                root = trunk_at(pts, zz) + d * 0.05
                d3 = (d + Z * (0.12 if x < 0.3 else -0.08)).normalized()
                fan(m, root, d3, L, 0.5, droop * (0.5 + 0.7 * x), 0.1 + 0.08 * (1 - x), SPRUCE_N, rng, fringe=0.24 * (0.45 + x))
            step = 0.5 + 0.22 * x
            z += step * rng.uniform(0.85, 1.15)
            k += 1
        # the spire: a last tuft of upturned shoots round the leader
        top = trunk_at(pts, H * 0.9)
        tube(m, [top, trunk_at(pts, H * 0.95), Vector((top.x, top.y, H + 0.3))], [0.32, 0.18, 0.02], "Needles",
             lambda p, t, a: mul(SPRUCE_N, 0.9 + 0.35 * t), segs=6, cap=False)
        if double_top:
            side = trunk_at(pts, H * 0.86)
            d = Vector((0.35, 0.2, 1)).normalized()
            fan(m, side, d, 2.2, 0.3, 0.05, 0.0, SPRUCE_N, rng, fringe=0.06)
        # dead twigs low on the trunk under the crown
        for i in range(int(crown_base * 2.5)):
            zz = rng.uniform(0.6, max(crown_base, 0.8))
            a = rng.uniform(0, TAU)
            d = Vector((math.cos(a), math.sin(a), -0.25)).normalized()
            p0 = trunk_at(pts, zz)
            tube(m, [p0, p0 + d * rng.uniform(0.3, 0.9)], [0.025, 0.006], "Bark", lambda p, t, a2: mul(DEAD, 0.75), segs=3, cap=False)
    else:
        # far off: the crown as a stack of ragged skirts
        tiers = 6 if span > 8 else 5
        for i in range(tiers):
            f0 = i / tiers
            f1 = (i + 1.6) / tiers
            z0 = crown_base + span * f0 - 0.3
            z1 = min(crown_base + span * f1, H)
            r = reach(z0 + 0.4) * 1.05
            ring_n = 10
            c = trunk_at(pts, z1)
            topv = m.bm.verts.new(c)
            mid, low = [], []
            for s in range(ring_n):
                a = s / ring_n * TAU + i * 0.7
                d = Vector((math.cos(a), math.sin(a), 0))
                rr = r * (1.0 if s % 2 == 0 else 0.82)
                base = trunk_at(pts, z0)
                mid.append(m.bm.verts.new(base + d * rr * 0.55 + Z * ((z1 - z0) * 0.45)))
                low.append(m.bm.verts.new(base + d * rr - Z * (0.35 if s % 2 == 0 else 0.1)))
            tone = jit(SPRUCE_N, 0.06, rng)
            for s in range(ring_n):
                s1 = (s + 1) % ring_n
                m.face([topv, mid[s], mid[s1]], [mul(tone, 1.15), tone, tone], "Needles")
                m.face([mid[s], low[s], low[s1], mid[s1]], [tone, mul(tone, 0.72), mul(tone, 0.72), tone], "Needles")
    info = {"kind": "tree", "species": "spruce", "height": round(H, 2), "trunk_radius": round(radii_at(pts, radii, 1.0), 3),
            "collision": "trunk", "crown_radius": round(R * narrow, 2), "crown_base": crown_base}
    return m, info


def radii_at(pts, radii, z):
    for (a, ra), (b, rb) in zip(zip(pts, radii), zip(pts[1:], radii[1:])):
        if a.z <= z <= b.z:
            t = (z - a.z) / max(b.z - a.z, 1e-6)
            return ra + (rb - ra) * t
    return radii[-1]


# --- Scots pine -------------------------------------------------------------------------------------

def pad_fn(base, rng, crown=None):
    """A clump's colour: lit as part of the whole crown (crown: its middle, half-width, half-height),
    lighter toward the top and the outside, darker in and under; only a little by the clump's own
    roundness, so the crown reads as one mass and not a heap of balls."""
    tone = jit(base, 0.07, rng)
    if crown is None:
        crown = (Vector((0, 0, 1)), 1.0, 1.0)
    mid, rw, rh = crown

    def fn(p, n):
        d = p - mid
        h = max(-1.0, min(1.0, d.z / rh))
        o = min(1.0, math.hypot(d.x, d.y) / rw)
        k = 0.78 + 0.16 * h + 0.14 * o + 0.07 * n.z
        c = mul(tone, k)
        if h > 0.3 and n.z > 0.4:
            c = mix(c, (c[0] * 1.12, c[1] * 1.08, c[2] * 0.92), (h - 0.3) * (n.z - 0.4) * 2.0)
        return c
    return fn


def pine(H, crown_base, R, seed, lod, sweep=0.0, limbs=6, young=False):
    rng = random.Random(seed)
    m = Mesh()
    r0 = H * 0.0155
    lean = (rng.uniform(-0.015, 0.015) + sweep * 0.01, rng.uniform(-0.015, 0.015))
    pts = trunk_points(H * 0.93, lean, seed * 0.41, sweep=sweep, n=None if lod == 0 else 5)
    radii = trunk_radii(pts, H, r0, top=0.04)
    bark = bark_fn(BARK_PINE, rng, top=BARK_PINE_TOP, top_from=0.38, height=H, moss=0.35, furrow=0.7, seed=seed * 0.1)
    tube(m, pts, radii, "Bark", bark, segs=9 if lod == 0 else 5, rough=0.08 if lod == 0 else 0.0, seed=seed)
    if lod == 0:
        roots(m, r0 * 1.3, 5, "Bark", bark, rng)
    span = H - crown_base
    pads = []
    # the limbs: up and out from the upper trunk, crooked, each ending in a few flat clumps
    for i in range(limbs):
        f = (i + rng.uniform(0.0, 0.8)) / limbs
        z = crown_base - 0.5 + span * f * 0.82
        a = i * 2.39996 + rng.uniform(-0.4, 0.4)
        d = Vector((math.cos(a), math.sin(a), 0))
        reach = R * (0.55 + 0.45 * (1.0 - abs(f - 0.35) * 1.3)) * rng.uniform(0.8, 1.1)
        p0 = trunk_at(pts, z)
        rise = rng.uniform(0.35, 0.8) * (1.4 if young else 1.0)
        end = p0 + d * reach * 0.85 + Z * (reach * rise)
        line = bend_line(p0, end, 4 if lod == 0 else 3, sag=-0.08, wobble=0.06, seed=seed + i)
        rl = radii_at(pts, radii, z) * 0.45
        if lod == 0:
            tube(m, line, [rl, rl * 0.7, rl * 0.45, rl * 0.25][:len(line)], "Bark", bark, segs=5, cap=True)
            # a side shoot
            mid = line[1].lerp(line[2], 0.5)
            a2 = a + rng.choice((-1, 1)) * rng.uniform(0.7, 1.2)
            sd = Vector((math.cos(a2), math.sin(a2), 0.4)).normalized()
            se = mid + sd * reach * 0.4
            tube(m, [mid, mid.lerp(se, 0.5) + Z * 0.15, se], [rl * 0.4, rl * 0.28, rl * 0.15], "Bark", bark, segs=4, cap=True)
            pads.append((se + Z * 0.15, reach * 0.32))
        pads.append((end + Z * 0.1, reach * 0.36))
        pads.append((line[-2].lerp(end, 0.4) + Z * 0.05, reach * 0.28))
        pads.append((line[1].lerp(line[2], 0.6) + Z * 0.05, reach * 0.22))
    # the top
    top = pts[-1]
    crown = (Vector((0, 0, (crown_base + H) * 0.5)), R, (H - crown_base) * 0.5)
    pads.append((top + Z * 0.3, R * 0.42))
    pads.append((top + Vector((rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8), -0.9)), R * 0.36))
    for c, s in pads:
        if lod == 0:
            # a clump is a few pads together: flat on top, hanging a little beneath
            for j in range(2):
                off = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.4, 0.3))) * s * 0.6
                ss = s * rng.uniform(0.65, 0.9)
                blob(m, c + off, (ss * 1.1, ss, ss * 0.66), "Needles", pad_fn(PINE_N, rng, crown), rng, subdiv=2, lump=0.38, under=0.35)
        else:
            blob(m, c, (s * 1.45, s * 1.3, s * 0.62), "Needles", pad_fn(PINE_N, rng, crown), rng, subdiv=1, lump=0.2, under=0.4)
    if lod == 0:
        # dead stubs of the lower branches the pine shed as it grew
        for i in range(int(crown_base * 0.9)):
            zz = rng.uniform(2.0, crown_base)
            a = rng.uniform(0, TAU)
            d = Vector((math.cos(a), math.sin(a), rng.uniform(-0.2, 0.1))).normalized()
            p0 = trunk_at(pts, zz)
            tube(m, [p0, p0 + d * (radii_at(pts, radii, zz) + rng.uniform(0.15, 0.5))], [0.04, 0.02], "Bark", lambda p, t, a2: mul(DEAD, 0.7), segs=3, cap=True)
    info = {"kind": "tree", "species": "pine", "height": round(H, 2), "trunk_radius": round(radii_at(pts, radii, 1.0), 3),
            "collision": "trunk", "crown_radius": round(R, 2), "crown_base": crown_base}
    return m, info


# --- silver birch -----------------------------------------------------------------------------------

def birch_marks(rng, seed):
    """The black on a birch: dashes across the bark, heavier where branches leave; black and
    fissured at the foot."""
    def marks(p, a, c):
        foot = max(0.0, min(1.0, 1.0 - (p.z - 0.2) / 1.3 + nz(p, 1.7, seed) * 0.35))
        c = mix(c, mul(BIRCH_FOOT, 0.85 + 0.3 * nz(p, 3.1, seed)), foot)
        dash = nz((p.x * 0.4, p.y * 0.4, p.z * 5.5), 1.0, seed + 11.0) + 0.45 * nz(p, 0.8, seed)
        if dash > 0.2:
            c = mix(c, BIRCH_MARK, 0.85)
        return c
    return marks


def birch(H, seed, lod, stems=1, weep=0.35, R=3.7):
    rng = random.Random(seed)
    m = Mesh()
    r0 = H * 0.0125 / math.sqrt(stems)
    clusters = []
    tot_r = 0.0
    for st in range(stems):
        lean = (rng.uniform(-0.02, 0.02) + (0.05 * (st - (stems - 1) * 0.5)), rng.uniform(-0.02, 0.02))
        h = H * (1.0 if st == 0 else rng.uniform(0.82, 0.92))
        pts = trunk_points(h, lean, seed * 0.5 + st * 9, n=None if lod == 0 else 5)
        if stems > 1:
            shift = Vector(((st - (stems - 1) * 0.5) * r0 * 1.8, 0, 0))
            pts = [p + shift for p in pts]
        radii = trunk_radii(pts, h, r0, flare=1.7, top=0.02)
        tot_r = max(tot_r, radii_at(pts, radii, 1.0) * (1.6 if stems > 1 else 1.0))
        bark = bark_fn(BIRCH_W, rng, height=h, furrow=0.95, seed=seed * 0.1 + st, marks=birch_marks(rng, seed + st))
        tube(m, pts, radii, "BirchBark", bark, segs=8 if lod == 0 else 5, rough=0.04 if lod == 0 else 0.0, seed=seed)
        if lod == 0 and st == 0:
            roots(m, r0 * 1.25, 4, "BirchBark", bark, rng, reach=2.0)
        nb = (10 if lod == 0 else 5) * 2 // (stems + 1)  # (a stem of a clump has fewer limbs)
        for i in range(nb):
            f = 0.32 + 0.6 * (i + rng.uniform(0, 0.7)) / nb
            z = h * f
            a = i * 2.39996 + rng.uniform(-0.3, 0.3) + st * 1.3
            d = Vector((math.cos(a), math.sin(a), 0))
            reach = R * (0.45 + 0.55 * math.sin(math.pi * min(1.0, (1.0 - f) * 1.25 + 0.15))) * rng.uniform(0.8, 1.1) / (1 + 0.3 * (stems - 1))
            p0 = trunk_at(pts, z)
            out = p0 + d * reach * 0.55 + Z * (reach * 0.75)
            end = out + d * reach * 0.5 - Z * (reach * weep)
            rl = radii_at(pts, radii, z) * 0.42
            line = [p0, p0.lerp(out, 0.5) + Z * 0.1, out, out.lerp(end, 0.5) + Z * reach * 0.06, end]
            twig = lambda p, t, a2, rl=rl: mix(mul(BIRCH_W, 0.85), TWIG, t * 1.3)
            if lod == 0:
                tube(m, line, [rl, rl * 0.75, rl * 0.5, rl * 0.3, rl * 0.12], "BirchBark", twig, segs=5, cap=False)
                for j in range(1):
                    q = line[2 + j]
                    a2 = a + rng.uniform(-1.2, 1.2)
                    sd = Vector((math.cos(a2), math.sin(a2), 0))
                    se = q + sd * reach * 0.35 - Z * reach * weep * 0.6
                    tube(m, [q, q.lerp(se, 0.5) + Z * 0.12, se], [rl * 0.3, rl * 0.18, rl * 0.06], "BirchBark", lambda p, t, a3: TWIG, segs=3, cap=False)
                    clusters.append((se, reach * 0.27))
                clusters.append((line[2].lerp(line[3], 0.5), reach * 0.3))
                clusters.append((end + Z * reach * 0.1, reach * 0.28))
            else:
                tube(m, line[::2], [rl, rl * 0.5, rl * 0.12], "BirchBark", twig, segs=3, cap=False)
                clusters.append((line[2].lerp(end, 0.4), reach * 0.55))
        clusters.append((pts[-1], R * 0.22 if lod == 0 else R * 0.35))
    crown = (Vector((0, 0, H * 0.66)), R, H * 0.34)
    for c, s in clusters:
        if lod == 0:
            # a spray of leaves: a few small lumps, hanging, with sky between
            blob(m, c, (s, s * 0.9, s * 0.85), "Leaves", pad_fn(BIRCH_L, rng, crown), rng, subdiv=2, lump=0.42, under=0.0)
            off = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), -0.9)) * s * 0.7
            blob(m, c + off, (s * 0.5, s * 0.45, s * 0.55), "Leaves", pad_fn(BIRCH_L, rng, crown), rng, subdiv=1, lump=0.3, under=0.0)
        else:
            blob(m, c - Z * s * 0.2, (s * 1.25, s * 1.15, s * 0.95), "Leaves", pad_fn(mul(BIRCH_L, 0.88), rng, crown), rng, subdiv=2, lump=0.25, under=0.2)
    info = {"kind": "tree", "species": "birch", "height": round(H, 2), "trunk_radius": round(tot_r, 3),
            "collision": "trunk", "crown_radius": round(R, 2), "crown_base": round(H * 0.32, 2)}
    return m, info


# --- dead wood --------------------------------------------------------------------------------------

def dead_fn(rng, seed, moss=0.3):
    """Bleached grey wood, cracked along the grain, a few patches of bark still on it."""
    def fn(p, t, a):
        c = mul(DEAD, 0.9 + 0.2 * nz(p, 1.9, seed))
        crack = 0.5 + 0.5 * math.sin(a * TAU * 9.0 + nz(p, 0.5, seed) * 6.0)
        c = mul(c, 1.0 - 0.3 * crack ** 6)
        if nz(p, 0.7, seed + 3.0) > 0.18:
            c = mul(DEAD_BARK, 0.9 + 0.2 * nz(p, 2.5, seed))
        if moss and p.z < 1.2 and nz(p, 1.2, seed + 8.0) > 0.1:
            c = mix(c, MOSS, moss)
        return c
    return fn


def dead_tree(H, seed, lod, lean=0.0, limbs=3):
    rng = random.Random(seed)
    m = Mesh()
    r0 = 0.28
    pts = trunk_points(H, (lean, rng.uniform(-0.01, 0.01)), seed * 0.3, n=None if lod == 0 else 5)
    radii = trunk_radii(pts, H * 1.6, r0, top=0.03)
    wood = dead_fn(rng, seed)
    jag = (lambda s: rng.uniform(-0.15, 0.7) * (1.0 if s % 2 else 0.3)) if lod == 0 else None
    tube(m, pts, radii, "DeadWood", wood, segs=9 if lod == 0 else 5, cap=lod > 0, rough=0.07 if lod == 0 else 0.0, seed=seed, jag=jag)
    if lod == 0:
        # the splintered top's inside: pale wood
        c = pts[-1]
        tube(m, [c - Z * 0.4, c + Z * 0.35], [radii[-1] * 0.85, 0.02], "DeadWood", lambda p, t, a: mul(END, 0.8), segs=6, cap=True)
        roots(m, r0 * 1.3, 5, "DeadWood", wood, rng)
        for i in range(14):
            zz = rng.uniform(1.5, H * 0.92)
            a = rng.uniform(0, TAU)
            d = Vector((math.cos(a), math.sin(a), rng.uniform(-0.3, 0.3))).normalized()
            p0 = trunk_at(pts, zz)
            L = rng.uniform(0.2, 0.7)
            tube(m, [p0, p0 + d * (radii_at(pts, radii, zz) + L)], [0.06, 0.03], "DeadWood", wood, segs=4, cap=True)
    for i in range(limbs):
        zz = H * rng.uniform(0.45, 0.85)
        a = i * 2.2 + rng.uniform(0, 1)
        d = Vector((math.cos(a), math.sin(a), 0))
        p0 = trunk_at(pts, zz)
        L = rng.uniform(1.2, 2.6)
        line = bend_line(p0, p0 + d * L + Z * L * rng.uniform(0.2, 0.7), 4 if lod == 0 else 2, wobble=0.1, seed=seed + i)
        r = 0.08
        tube(m, line, [r, r * 0.7, r * 0.45, r * 0.2][:len(line)], "DeadWood", wood, segs=5 if lod == 0 else 3, cap=True)
    info = {"kind": "tree", "species": "dead", "height": round(H, 2), "trunk_radius": round(radii_at(pts, radii, 1.0), 3),
            "collision": "trunk", "crown_radius": 2.5, "crown_base": 2.5}
    return m, info


def log_model(seed, lod, rotten=False, root_plate=True):
    """A fallen trunk along X, 6 m, lying on the ground and sunk into it a little."""
    rng = random.Random(seed)
    m = Mesh()
    r = 0.22
    L = 6.0
    x0, x1 = -3.0, (2.5 if root_plate else 3.0)
    n = 8 if lod == 0 else 3
    pts = []
    for i in range(n):
        t = i / (n - 1)
        x = x0 + (x1 - x0) * t
        pts.append(Vector((x, nz((x, 0, 0), 0.3, seed) * 0.12, r - 0.06 + 0.02 * math.sin(t * math.pi))))
    radii = [r * (0.82 + 0.3 * (i / (n - 1))) for i in range(n)]
    seedf = seed * 0.1

    def col(p, t, a):
        if rotten:
            c = dead_fn(rng, seed, moss=0.0)(p, t, a)
            c = mix(c, DEAD_BARK, 0.4)
        else:
            c = bark_fn(BARK_SPRUCE, rng, seed=seedf)(p, t, a)
        top = (p.z - r * 0.5) / r
        if top > 0.0 and nz(p, 1.1, seed + 4.0) > (-0.25 if rotten else 0.15):
            c = mix(c, jit(MOSS, 0.08, rng), min(1.0, top * 1.6) * (0.9 if rotten else 0.6))
        if p.z < 0.08:
            c = mix(c, EARTH, 0.5)
        return c
    jag = (lambda s: rng.uniform(-0.1, 0.35)) if (lod == 0 and rotten) else None
    tube(m, pts, radii, "Bark" if not rotten else "DeadWood", col, segs=10 if lod == 0 else 5, cap=False, base_cap=False, rough=0.06 if lod == 0 else 0.0, seed=seed, jag=jag)
    # the sawn or broken ends
    for p, rr, sgn in ((pts[0], radii[0], -1), (pts[-1], radii[-1], 1)):
        if root_plate and sgn > 0:
            continue
        cv = m.bm.verts.new(p)
        ring = []
        for s in range(10 if lod == 0 else 5):
            a = s / (10 if lod == 0 else 5) * TAU
            ring.append(m.bm.verts.new(p + Vector((0, math.cos(a), math.sin(a))) * rr * 1.0))
        for s in range(len(ring)):
            q = [cv, ring[s], ring[(s + 1) % len(ring)]] if sgn > 0 else [cv, ring[(s + 1) % len(ring)], ring[s]]
            m.face(q, [mul(END, 0.55 if rotten else 0.85), mul(BARK_SPRUCE, 0.8), mul(BARK_SPRUCE, 0.8)], "Wood")
    if root_plate:
        # the root plate torn up with the trunk: a disc of roots and earth standing on edge
        c = pts[-1] + Vector((0.25, 0, 0.35))
        blob(m, c, (0.35, 1.05, 0.95), "Earth", lambda p, nn: mix(mul(EARTH, 0.85 + 0.3 * nz(p, 2.0, seed)), mul(TWIG, 0.9), 0.3 if nn.x < 0 else 0.0),
             rng, subdiv=2 if lod == 0 else 1, lump=0.3, under=0.0, yaw=0.0, smooth=False)
        if lod == 0:
            for i in range(9):
                a = i / 9 * TAU + rng.uniform(-0.2, 0.2)
                d = Vector((0.15, math.cos(a), math.sin(a)))
                q = c + d * 0.9
                tube(m, [c + d * 0.3, q, q + d * 0.35 + Vector((rng.uniform(-0.2, 0.3), 0, 0))], [0.07, 0.04, 0.01], "Bark", lambda p, t, a2: mul(TWIG, 0.85), segs=4, cap=False)
    if lod == 0:
        for i in range(5):
            x = rng.uniform(x0 + 0.5, x1 - 0.5)
            p0 = trunk_line_x(pts, x)
            a = rng.uniform(0.2, math.pi - 0.2)
            d = Vector((rng.uniform(-0.3, 0.3), math.cos(a), math.sin(a))).normalized()
            tube(m, [p0, p0 + d * (r + rng.uniform(0.15, 0.5))], [0.05, 0.025], "DeadWood", dead_fn(rng, seed, 0.0), segs=4, cap=True)
    info = {"kind": "log", "species": "log", "height": round(2 * r, 2), "radius": r, "length": L, "axis": "x",
            "collision": "cylinder", "center": [0.0, r, 0.0]}
    return m, info


def trunk_line_x(pts, x):
    for a, b in zip(pts, pts[1:]):
        if a.x <= x <= b.x:
            return a.lerp(b, (x - a.x) / max(b.x - a.x, 1e-6))
    return pts[-1].copy()


def branches(seed, lod):
    """A heap of lopped branches, the needles on them gone brown, a few still green."""
    rng = random.Random(seed)
    m = Mesh()
    n = 16 if lod == 0 else 5
    for i in range(n):
        a = rng.uniform(-0.5, 0.5) + (math.pi * 0.5 if i % 3 == 0 else 0.0)
        d = Vector((math.cos(a), math.sin(a), 0))
        L = rng.uniform(1.4, 2.6)
        c = Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.4, 0.4), 0.08 + 0.12 * (i / n) * 3.0 * rng.uniform(0.3, 1.0)))
        a0 = c - d * L * 0.5
        a1 = c + d * L * 0.5 + Z * rng.uniform(-0.1, 0.25)
        r = rng.uniform(0.025, 0.05)
        tube(m, [a0, a0.lerp(a1, 0.5) + Z * 0.06, a1], [r, r * 0.7, r * 0.3], "Wood", lambda p, t, a2: mix(mul(BARK_SPRUCE, 0.9), mul(END, 0.75), 0.2 if t < 0.05 else 0.0), segs=4 if lod == 0 else 3, cap=True)
        if lod == 0 or i % 2 == 0:
            tone = DRY_NEEDLE if rng.random() < 0.75 else mix(DRY_NEEDLE, SPRUCE_N, 0.6)
            for k in range(2 if lod == 0 else 1):
                p = a0.lerp(a1, 0.45 + k * 0.3)
                fan(m, p - d * 0.4 * L * 0.5, (d + Z * 0.05).normalized(), L * 0.45, 0.5, 0.1, 0.0, tone, rng, fringe=0.1, stations=3, lod=lod)
    info = {"kind": "log", "species": "log", "height": 0.7, "radius": 0.35, "length": 2.2, "axis": "x",
            "collision": "cylinder", "center": [0.0, 0.35, 0.0]}
    return m, info


def stump(seed, lod, kind="sawn"):
    rng = random.Random(seed)
    m = Mesh()
    r = 0.3
    h = 0.55 if kind != "old" else 0.42
    rotten = kind == "old"
    n = 4 if lod == 0 else 2
    pts = [Vector((0, 0, -0.6 + (h + 0.6) * i / (n - 1))) for i in range(n)]
    radii = [r * (1.25 if p.z < 0.15 else 1.0) * (1.0 + 0.4 * max(0.0, 0.25 - p.z)) for p in pts]
    if rotten:
        bark = dead_fn(rng, seed, moss=0.7)
    else:
        bark = bark_fn(BARK_PINE, rng, height=10.0, moss=0.4, seed=seed * 0.1)
    jag = None
    if kind == "broken" and lod == 0:
        jag = lambda s: rng.uniform(0.0, 0.55) * (1.0 if s % 3 else 0.2)
    if rotten and lod == 0:
        jag = lambda s: rng.uniform(-0.1, 0.12)
    rings = tube(m, pts, radii, "Bark" if not rotten else "DeadWood", bark, segs=11 if lod == 0 else 6, cap=False, rough=0.08 if lod == 0 else 0.0, seed=seed, jag=jag)
    top = rings[-1]
    ctr = Vector((0, 0, sum(v.co.z for v in top) / len(top)))
    if kind == "broken" and lod == 0:
        ctr.z += 0.25
    seg = len(top)
    if lod == 0 and kind != "broken":
        # the sawn face: bark, sapwood, heartwood, the rings; the old one's mossed and rotten
        mid = [m.bm.verts.new(ctr.lerp(v.co, 0.88)) for v in top]
        inner = [m.bm.verts.new(ctr.lerp(v.co, 0.5) + Z * (rng.uniform(-0.04, 0.0) if rotten else 0.0)) for v in top]
        cv = m.bm.verts.new(ctr - Z * (0.06 if rotten else 0.0))
        sap = mul(END, 0.9) if not rotten else mix(END, DEAD_BARK, 0.6)
        heart = mul(END, 0.75) if not rotten else mix(MOSS, DEAD_BARK, 0.4)
        for s in range(seg):
            s1 = (s + 1) % seg
            m.face([top[s], top[s1], mid[s1], mid[s]], mul(BARK_PINE, 0.7), "Wood")
            m.face([mid[s], mid[s1], inner[s1], inner[s]], [sap, sap, mul(sap, 0.88), mul(sap, 0.88)], "Wood")
            m.face([inner[s], inner[s1], cv], [heart, heart, mul(heart, 0.8)], "Wood")
    else:
        cv = m.bm.verts.new(ctr)
        for s in range(seg):
            m.face([top[s], top[(s + 1) % seg], cv], [mul(END, 0.8), mul(END, 0.8), mul(END, 0.65)], "Wood")
    if lod == 0:
        roots(m, r * 1.1, 5, "Bark" if not rotten else "DeadWood", bark, rng, reach=2.2)
    info = {"kind": "stump", "species": "stump", "height": h, "radius": r, "trunk_radius": r,
            "collision": "cylinder", "center": [0.0, h * 0.5, 0.0]}
    return m, info


# --- scrub and ferns --------------------------------------------------------------------------------

def juniper(seed, lod, spread=False):
    rng = random.Random(seed)
    m = Mesh()
    n = (7 if not spread else 9) if lod == 0 else 3
    H = 1.7 if not spread else 0.75
    for i in range(n):
        a = i / n * TAU + rng.uniform(-0.3, 0.3)
        rr = rng.uniform(0.0, 0.45 if not spread else 0.9)
        c = Vector((math.cos(a) * rr, math.sin(a) * rr, 0))
        h = H * rng.uniform(0.55, 1.0) * (1.0 - rr * 0.3)
        s = 0.42 if not spread else 0.55
        blob(m, c + Z * h * 0.5, (s * rng.uniform(0.8, 1.1), s * rng.uniform(0.8, 1.1), h * 0.55), "Needles", pad_fn(JUNIPER, rng, (Vector((0, 0, H * 0.5)), 0.8, H * 0.5)), rng,
             subdiv=2 if lod == 0 else 1, lump=0.3, under=0.0)
    if lod == 0:
        for i in range(4):
            a = rng.uniform(0, TAU)
            tube(m, [Vector((0, 0, -0.2)), Vector((math.cos(a) * 0.2, math.sin(a) * 0.2, 0.4))], [0.05, 0.03], "Bark", lambda p, t, a2: TWIG, segs=4, cap=True)
    return m, {"kind": "bush", "species": "bush", "height": H, "radius": 0.75 if not spread else 1.2, "collision": "none"}


def willow(seed, lod):
    rng = random.Random(seed)
    m = Mesh()
    clusters = []
    for i in range(7 if lod == 0 else 3):
        a = i / 7 * TAU + rng.uniform(-0.4, 0.4)
        d = Vector((math.cos(a), math.sin(a), 0))
        top = d * rng.uniform(0.3, 0.7) + Z * rng.uniform(1.0, 1.5)
        if lod == 0:
            tube(m, [Vector((0, 0, -0.2)), d * 0.1 + Z * 0.4, top], [0.035, 0.025, 0.01], "Bark", lambda p, t, a2: mix(TWIG, (0.45, 0.3, 0.2), t), segs=4, cap=False)
        clusters.append(top)
        clusters.append(top * 0.6)
    for c in clusters:
        s = rng.uniform(0.3, 0.45) * (1.0 if lod == 0 else 1.5)
        blob(m, c, (s, s, s * 0.85), "Leaves", pad_fn(WILLOW, rng, (Vector((0, 0, 0.9)), 0.8, 0.7)), rng, subdiv=1, lump=0.35, under=0.2)
    return m, {"kind": "bush", "species": "bush", "height": 1.5, "radius": 0.8, "collision": "none"}


def fern(seed, lod, size=1.0):
    rng = random.Random(seed)
    m = Mesh()
    n = 9
    for i in range(n):
        a = i / n * TAU + rng.uniform(-0.25, 0.25)
        d = Vector((math.cos(a), math.sin(a), 0))
        side = d.cross(Z)
        L = size * rng.uniform(0.55, 0.85)
        rise = rng.uniform(0.6, 0.95)
        tone = jit(FERN_C, 0.12, rng)
        k_n = 8
        rows = []
        for k in range(k_n + 1):
            t = k / k_n
            p = d * L * t + Z * (L * rise * math.sin(t * math.pi * 0.62) - L * 0.25 * t * t)
            w = L * 0.2 * math.sin(math.pi * min(t * 1.05 + 0.08, 1.0)) * (1.0 if k % 2 else 0.45)  # (the pinnae, notched between)
            rows.append((p - side * w - Z * w * 0.25, p + Z * w * 0.15, p + side * w - Z * w * 0.25, t))
        vs = [[m.bm.verts.new(q) for q in r[:3]] for r in rows]
        for k in range(k_n):
            t0, t1 = rows[k][3], rows[k + 1][3]
            for j in range(2):
                c0 = mul(tone, 0.6 + 0.5 * t0)
                c1 = mul(tone, 0.6 + 0.5 * t1)
                m.face([vs[k][j], vs[k][j + 1], vs[k + 1][j + 1], vs[k + 1][j]], [c0, mul(c0, 1.15), mul(c1, 1.15), c1] if j == 0 else [mul(c0, 1.15), c0, c1, mul(c1, 1.15)], "FernLeaf")
    return m, {"kind": "fern", "species": "fern", "height": round(0.67 * size, 2), "radius": round(0.74 * size, 2), "collision": "none"}


def reeds(seed, lod):
    """A clump of reeds and bulrushes for the lake's shallows: tall blades bending out, greener low
    down and straw at the tips, a few brown cattail heads on their stalks."""
    rng = random.Random(seed)
    m = Mesh()
    for i in range(14 if lod == 0 else 7):
        a = rng.uniform(0, TAU)
        r = rng.uniform(0.0, 0.45)
        base = Vector((math.cos(a) * r, math.sin(a) * r, -0.3))
        out = Vector((math.cos(a), math.sin(a), 0)) * rng.uniform(0.1, 0.45)
        h = rng.uniform(1.1, 1.9)
        face = rng.uniform(0, TAU)
        side = Vector((math.cos(face), math.sin(face), 0))
        w = rng.uniform(0.025, 0.045)
        tone = jit((0.38, 0.42, 0.2), 0.1, rng)
        rows = []
        for k in range(4):
            t = k / 3
            p = base + out * t * t + Z * (h + 0.3) * t
            ww = w * (1.0 - t * 0.9)
            c = mix(mul(tone, 0.7), (0.62, 0.55, 0.34), max(0.0, t - 0.45) * 1.8)
            rows.append((p - side * ww, p + side * ww, c))
        for k in range(3):
            r0, r1 = rows[k], rows[k + 1]
            m.face([r0[0], r0[1], r1[1], r1[0]], [r0[2], r0[2], r1[2], r1[2]], "FernLeaf")
    for i in range(3 if lod == 0 else 1):
        a = rng.uniform(0, TAU)
        b = Vector((math.cos(a) * 0.2, math.sin(a) * 0.2, -0.3))
        top = b + Vector((math.cos(a) * 0.15, math.sin(a) * 0.15, rng.uniform(1.6, 2.0)))
        tube(m, [b, top], [0.012, 0.008], "FernLeaf", lambda p, t, a2: (0.4, 0.42, 0.22), segs=3, cap=False)
        tube(m, [top - Z * 0.32, top - Z * 0.06], [0.035, 0.03], "Wood", lambda p, t, a2: (0.3, 0.19, 0.11), segs=6, cap=True, base_cap=True)
    return m, {"kind": "decor", "species": "reeds", "height": 1.8, "collision": "none"}


# --- stone ------------------------------------------------------------------------------------------

def rock_colour(seed, rng, base=ROCK, moss=0.6, lichen=0.12, ground=0.0):
    """Granite: mottled grey at two scales, darker in the creases, lichen spots and moss on what
    faces the sky, earth splashed at the foot."""
    tone = jit(base, 0.06, rng)

    def fn(p, n):
        c = mul(tone, 0.86 + 0.22 * nz(p, 0.9, seed) + 0.08 * nz(p, 3.3, seed + 1.0))
        if n.z < -0.2:
            c = mul(c, 0.8)
        up = n.z + 0.35 * nz(p, 1.4, seed + 2.0)
        if moss and up > 0.62:
            c = mix(c, jit(MOSS if nz(p, 0.5, seed + 5.0) > -0.2 else MOSS_DRY, 0.1, rng), moss * min(1.0, (up - 0.62) * 3.5))
        elif lichen and nz(p, 2.6, seed + 7.0) > 0.42:
            c = mix(c, LICHEN, 0.55)
        if p.z < ground + 0.25:
            c = mix(c, EARTH, 0.45 * (1.0 - max(0.0, p.z - ground) / 0.25))
        return c
    return fn


def stone(m, c, size, rng, subdiv=3, cuts=7, blocky=0.0, moss=0.6, lichen=0.12, flat_bottom=0.35, tilt=0.0, base=ROCK, ground=0.0,
          elev=(-0.25, 0.75), reach=(0.68, 0.9), top=None):
    """A boulder: a noisy ball split by a few planes (glacier-ground and frost-split faces), its foot
    pressed flat, flat-shaded."""
    res = bmesh.ops.create_icosphere(m.bm, subdivisions=subdiv, radius=1.0)
    verts = res["verts"]
    o = rng.uniform(0, 100)
    planes = []
    for i in range(cuts):
        a = rng.uniform(0, TAU)
        e = rng.uniform(*elev)
        nrm = Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)))
        planes.append((nrm, rng.uniform(*reach)))
    if top is not None:  # (a bedding plane across the top: a ledge)
        planes.append((Vector((rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), 1)).normalized(), top))
    yaw = rng.uniform(0, TAU)
    rot = Matrix.Rotation(tilt, 3, "X") @ Matrix.Rotation(yaw, 3, "Z")
    for v in verts:
        n = v.co.normalized()
        if blocky:
            q = Vector((abs(n.x), abs(n.y), abs(n.z)))
            k = (q.x ** 4 + q.y ** 4 + q.z ** 4) ** 0.25
            n = n.lerp(n / k, blocky)
        p = n * (1.0 + 0.16 * nz(n, 1.2, o) + 0.06 * nz(n, 3.0, o + 4.0))
        for nrm, off in planes:
            d = p.dot(nrm) - off
            if d > 0:
                p = p - nrm * d
        if p.z < -flat_bottom:
            p.z = -flat_bottom - (-(p.z) - flat_bottom) * 0.25
        v.co = Vector(c) + rot @ Vector((p.x * size[0], p.y * size[1], p.z * size[2]))
    faces = list({f for v in verts for f in v.link_faces})
    m.paint(faces, rock_colour(o, rng, base=base, moss=moss, lichen=lichen, ground=ground), "Rock", smooth=False)
    return verts


def boulder(seed, lod, size, shape="round"):
    rng = random.Random(seed)
    m = Mesh()
    sd = 3 if lod == 0 else 2
    sx, sy, sz = size
    if shape == "slab":
        stone(m, (0, 0, sz * 0.2), (sx * 0.5, sy * 0.5, sz * 0.75), rng, subdiv=sd, cuts=6, blocky=0.6, moss=0.8, flat_bottom=0.2)
    elif shape == "group":
        stone(m, (0.15, 0.1, sz * 0.25), (sx * 0.32, sy * 0.3, sz * 0.75), rng, subdiv=sd, cuts=7, moss=0.6)
        stone(m, (-sx * 0.38, -sy * 0.15, sz * 0.05), (sx * 0.2, sy * 0.18, sz * 0.4), rng, subdiv=max(sd - 1, 1), cuts=5, moss=0.5)
        stone(m, (sx * 0.2, -sy * 0.42, 0.0), (sx * 0.14, sy * 0.13, sz * 0.25), rng, subdiv=max(sd - 1, 1), cuts=4, moss=0.4)
    else:
        stone(m, (0, 0, sz * 0.22), (sx * 0.5, sy * 0.5, sz * 0.72), rng, subdiv=sd, cuts=8 if shape == "split" else 6,
              blocky=0.35 if shape == "split" else 0.0, moss=0.65, flat_bottom=0.45)
    return m, {"kind": "rock", "species": "rock", "height": round(sz, 2), "collision": "box",
               "size": [round(sx * 0.85, 2), round(sz, 2), round(sy * 0.85, 2)], "center": [0.0, round(sz * 0.5, 2), 0.0]}


def cliff(seed, lod, w=7.4, d=5.7, h=4.75):
    """An outcrop in ledges: big bedded blocks stepping back and up, split by vertical joints, moss and
    earth on the ledges, blocks fallen from it at its foot."""
    rng = random.Random(seed)
    m = Mesh()
    sd = 3 if lod == 0 else 2
    tilt = rng.uniform(-0.08, 0.08)
    k = h / 4.75
    layers = [((0.0, 0.0, 0.2 * k), (w * 0.5, d * 0.5, 2.2 * k)),
              ((-w * 0.06, d * 0.08, 2.6 * k), (w * 0.4, d * 0.38, 1.4 * k)),
              ((-w * 0.12, d * 0.12, 3.9 * k), (w * 0.26, d * 0.26, 1.1 * k)),
              ((w * 0.22, -d * 0.1, 1.6 * k), (w * 0.22, d * 0.26, 2.6 * k))]
    for c, s in layers:
        stone(m, c, s, rng, subdiv=sd, cuts=15, blocky=0.85, moss=0.55, lichen=0.2, flat_bottom=0.9, tilt=tilt, base=ROCK,
              elev=(-0.15, 0.3), reach=(0.72, 0.92), top=0.76)
    if lod == 0:
        for i in range(5):
            a = rng.uniform(-1.2, 1.2) - math.pi * 0.5
            r = rng.uniform(0.9, 1.15)
            c = Vector((math.cos(a) * w * 0.5 * r, math.sin(a) * d * 0.5 * r, 0.05))
            s = rng.uniform(0.3, 0.7)
            stone(m, c, (s, s * rng.uniform(0.7, 1.0), s * 0.7), rng, subdiv=2, cuts=5, moss=0.5, blocky=0.4)
    return m, {"kind": "cliff", "species": "cliff", "height": h, "collision": "box",
               "size": [round(w * 0.85, 2), h, round(d * 0.85, 2)], "center": [0.0, round(h * 0.5, 2), 0.0]}


# --- finishing and export ---------------------------------------------------------------------------

def grime(ob, mats):
    """Mud and dark at the foot of trunks and stones, the higher the less."""
    import numpy as np
    me = ob.data
    col, cbuf = B._colors(me)
    n = len(me.loops)
    vi = np.empty(n, dtype=np.int32)
    me.loops.foreach_get("vertex_index", vi)
    co = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    z = co.reshape(-1, 3)[vi, 2]
    lm = np.zeros(n, dtype=bool)
    keep = [i for i, mt in enumerate(me.materials) if mt.name.split(".")[0] in mats]
    for poly in me.polygons:
        if poly.material_index in keep:
            lm[poly.loop_start:poly.loop_start + poly.loop_total] = True
    g = np.clip(1.0 - z / 0.8, 0.0, 1.0) ** 1.8 * 0.4
    g[~lm] = 0.0
    for i in range(3):
        cbuf[:, i] = cbuf[:, i] * (1.0 - g) + EARTH[i] * g
    col.data.foreach_set("color", cbuf.ravel())


def clear():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)


def build(name, fn, ao=1.6, strength=0.6, **kw):
    clear()
    obs = []
    info = None
    tris = []
    for lod in (0, 1):
        m, inf = fn(lod=lod, **kw)
        info = info or inf
        tris.append(m.tris())
        ob = m.to_object("LOD%d" % lod)
        obs.append(ob)
    if not RAW:
        B.AO_DISTANCE = ao
        B.AO_STRENGTH = strength
        for ob in obs:
            B._bake_ao([ob], rays=16)
            grime(ob, WOOD + ("Rock", "Earth"))
    os.makedirs(B.OUT, exist_ok=True)
    path = os.path.join(B.OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False, export_apply=True, export_yup=True)
    info["tris"] = tris
    print("wrote", path, tris)
    return info


MODELS = {
    "spruce_a": (lambda lod: spruce(19.5, 2.4, 3.5, 0.32, 101, lod), 2.0),
    "spruce_b": (lambda lod: spruce(23.5, 5.0, 3.7, 0.3, 102, lod, narrow=0.9), 2.0),
    "spruce_c": (lambda lod: spruce(14.5, 0.6, 3.2, 0.36, 103, lod), 2.0),
    "spruce_d": (lambda lod: spruce(17.5, 1.5, 3.3, 0.45, 104, lod), 2.0),
    "spruce_e": (lambda lod: spruce(21.0, 3.4, 3.4, 0.3, 105, lod, double_top=True, narrow=0.95), 2.0),
    "pine_a": (lambda lod: pine(17.5, 10.0, 4.0, 201, lod, limbs=7), 2.2),
    "pine_b": (lambda lod: pine(19.5, 12.5, 4.2, 202, lod, limbs=6), 2.2),
    "pine_c": (lambda lod: pine(15.0, 7.5, 4.4, 203, lod, limbs=8), 2.2),
    "pine_d": (lambda lod: pine(18.0, 11.0, 3.9, 204, lod, sweep=1.0, limbs=7), 2.2),
    "pine_e": (lambda lod: pine(12.5, 5.0, 3.0, 205, lod, limbs=8, young=True), 2.2),
    "birch_a": (lambda lod: birch(13.0, 301, lod), 1.8),
    "birch_b": (lambda lod: birch(11.7, 302, lod, weep=0.45), 1.8),
    "birch_c": (lambda lod: birch(14.0, 303, lod, R=3.2), 1.8),
    "birch_d": (lambda lod: birch(10.5, 304, lod, stems=2, R=3.6), 1.8),
    "birch_e": (lambda lod: birch(12.0, 305, lod, weep=0.6, R=4.0), 1.8),
    "dead_tree": (lambda lod: dead_tree(11.2, 401, lod), 1.2),
    "dead_tree_b": (lambda lod: dead_tree(8.5, 402, lod, lean=0.04, limbs=4), 1.2),
    "log": (lambda lod: log_model(501, lod), 0.8),
    "log_b": (lambda lod: log_model(502, lod, rotten=True, root_plate=False), 0.8),
    "branches": (lambda lod: branches(503, lod), 0.6),
    "stump": (lambda lod: stump(601, lod), 0.7),
    "stump_b": (lambda lod: stump(602, lod, kind="broken"), 0.7),
    "stump_c": (lambda lod: stump(603, lod, kind="old"), 0.7),
    "bush_a": (lambda lod: juniper(701, lod), 0.8),
    "bush_b": (lambda lod: willow(702, lod), 0.8),
    "bush_c": (lambda lod: juniper(703, lod, spread=True), 0.8),
    "fern": (lambda lod: fern(801, lod), 0.5),
    "fern_b": (lambda lod: fern(802, lod, size=0.7), 0.5),
    "reeds": (lambda lod: reeds(851, lod), 0.4),
    "rock_a": (lambda lod: boulder(901, lod, (1.8, 1.6, 1.5)), 1.0),
    "rock_b": (lambda lod: boulder(902, lod, (2.6, 2.2, 2.2), shape="split"), 1.2),
    "rock_c": (lambda lod: boulder(903, lod, (2.5, 2.1, 0.85), shape="slab"), 0.8),
    "rock_d": (lambda lod: boulder(904, lod, (2.8, 2.4, 1.4), shape="group"), 1.0),
    "rock_e": (lambda lod: boulder(905, lod, (1.2, 1.0, 0.85)), 0.7),
    "cliff_a": (lambda lod: cliff(1001, lod), 2.0),
    "cliff_b": (lambda lod: cliff(1002, lod, w=6.2, d=4.6, h=5.4), 2.0),
}


def main():
    global RAW
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    for a in argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
        if a == "--raw":
            RAW = True
    path = os.path.join(B.OUT, "nature.json")
    table = {}
    if only and os.path.exists(path):
        with open(path) as fh:
            table = json.load(fh)
    for name, (fn, ao) in MODELS.items():
        if only and name not in only:
            continue
        table[name] = build(name, fn, ao=ao)
    table = {k: table[k] for k in MODELS if k in table}
    with open(path, "w") as fh:
        json.dump(table, fh, indent=1)
    print("wrote", path)


if __name__ == "__main__":
    main()
