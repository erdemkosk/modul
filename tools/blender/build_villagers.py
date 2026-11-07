"""The townsfolk's clothes: what the taiga wore in 1918, made the way the buildings and props are
(tools/blender/build_buildings.py, build_props.py) and skinned onto the townsman's own skeleton
(assets/townsfolk/townsman.glb), so every clip and every pose the game turns onto his bones moves
them too (scripts/townsfolk.gd puts them on).

    blender --background --factory-startup --python tools/blender/build_villagers.py [-- --render]

Each piece is one object "<piece>" in assets/townsfolk/kit.glb, skinned to the townsman's armature,
in his rest pose (Blender: +Y the way he faces, +Z up, the ground at 0; arms down at 45 degrees).
Its colours: the material's name says what it is ("Cloth", "Fur", "Leather"...; the game dyes each
per person), its vertices carry the shading (occlusion baked in, seams and folds, mud on the boots).

  shirt       the peasant shirt (kosovorotka), worn over the trousers to mid-thigh, the collar
              buttoned at the side, embroidered at the collar, cuffs and hem, a cord belt
  smock       a child's shirt, the same, to the knee
  tunic       a soldier's summer tunic (gymnastyorka): the same cut, plain, a leather belt
  padded      the quilted jacket (telogreika): to the hips, sewn in channels, a stand collar
  shinel      the greatcoat: to the calf, a turned-down collar, two rows of buttons, a belt
  tulup       the sheepskin coat: long and wide, the fleece out at the collar, cuffs and hem, a sash
  blouse      a woman's blouse, full in the sleeves
  skirt       a woman's long skirt, pleated, to the ankle
  apron       an apron over it
  shawl       a shawl over a woman's shoulders
  trousers    wool trousers, bloused over the boots
  trousers_long  the same, down to the ankle (for bast shoes and leg wraps)
  boots       tall leather boots
  valenki     felt boots
  lapti       bast shoes over linen leg wraps, the cords crossed up the shin
  kartuz      the workman's peaked cloth cap
  furazhka    the Centre's peaked service cap: a coloured band, a cockade
  budenovka   Free Kordal's pointed cloth helmet, a red star on the front
  papakha     the tall fur hat
  ushanka     the fur cap with ear flaps
  kerchief    a woman's kerchief, tied under the chin
  shawl_head  the winter's wool shawl over the head and shoulders
  hair        a man's hair, cropped
  beard_full, beard_short, moustache
  belt_kit    a soldier's leather belt with pouches and a cross strap (over the greatcoat or the
              quilted jacket; _thin over a shirt or tunic, _wide over a sheepskin)
  armband     Free Kordal's red band on the left arm (_wide over a greatcoat's or sheepskin's sleeve)
  neck_rag    a rag knotted at the neck (Kordal's red, an outlaw's grey)

Output: assets/townsfolk/kit.glb, assets/townsfolk/kit_sheet.png (--render).
"""

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector, kdtree, noise  # noqa: E402

import build_buildings as B  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "assets", "townsfolk", "townsman.glb")
OUT = os.path.join(ROOT, "assets", "townsfolk", "kit.glb")

W = (0.92, 0.92, 0.92)  # (the vertex colour under the game's dye: near white, the shading darkens it)
SEAM = (0.7, 0.7, 0.7)
EMBROIDERY = (0.95, 0.95, 0.95)

# --- the townsman as he stands (measured off his own clothes, rest pose) ---------------------------
# the torso: (z, half-width, half-depth to the front, to the back), the middle at y = -0.005
TORSO = [
    (0.86, 0.205, 0.145, 0.152), (0.92, 0.196, 0.140, 0.148), (0.98, 0.183, 0.134, 0.139),
    (1.05, 0.180, 0.132, 0.135), (1.12, 0.184, 0.137, 0.132), (1.20, 0.192, 0.146, 0.128),
    (1.28, 0.198, 0.150, 0.126), (1.35, 0.200, 0.146, 0.124), (1.40, 0.200, 0.134, 0.121),
    (1.44, 0.192, 0.120, 0.116), (1.465, 0.172, 0.108, 0.108), (1.485, 0.118, 0.088, 0.098),
]
NECK = (1.50, 0.083, 0.070, 0.092)  # the collar round the neck (the neck: x 0.07, y -0.084..0.058)
NECK_Y = -0.013
# the arm (the right; the left mirrored): into the shoulder, the shoulder, elbow, wrist
SHOULDER_IN = Vector((0.125, -0.015, 1.385))
SHOULDER = Vector((0.178, -0.02, 1.405))
ELBOW = Vector((0.3676, -0.02, 1.179))
HAND = Vector((0.5311, 0.0341, 0.9842))
# a leg (the right): (z, x of its middle, half-width, half-depth front, back)
LEG = [
    (0.90, 0.098, 0.108, 0.115, 0.135), (0.80, 0.108, 0.110, 0.105, 0.112), (0.66, 0.105, 0.096, 0.095, 0.097),
    (0.53, 0.100, 0.080, 0.082, 0.082), (0.44, 0.102, 0.076, 0.072, 0.090), (0.32, 0.099, 0.071, 0.066, 0.086),
    (0.20, 0.097, 0.064, 0.063, 0.072), (0.10, 0.097, 0.058, 0.060, 0.060),
]
HEAD_Y = 0.004


def smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


# --- a piece -------------------------------------------------------------------------------------

class Piece:
    """One garment: a mesh of lofts with per-face materials and per-corner colours, and the rule
    its weights come by ("pool": nearest of the townsman's own clothes; "head": the head's own)."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")
        self.mats = []
        self.rules = {}  # vert -> (query point, pools, hips share)

    def mat(self, name):
        if name not in self.mats:
            self.mats.append(name)
        return self.mats.index(name)

    def _face(self, vs, mat, cols):
        try:
            f = self.bm.faces.new(vs)
        except ValueError:
            return None
        f.material_index = self.mat(mat)
        f.smooth = True
        for loop in f.loops:
            c = cols(loop.vert) if callable(cols) else cols
            loop[self.col] = (c[0], c[1], c[2], 1.0)
        return f

    def loft(self, rings, mat, col=W, cap0=False, cap1=False, closed=True, shade=None, rule=None):
        """Rings of points (each a list of Vectors, the same count) joined in a skin. `shade(i, k)`
        darkens ring i's point k (folds, seams); `rule` the weight rule of every vertex."""
        loops = [[self.bm.verts.new(p) for p in r] for r in rings]
        n = len(rings[0])
        tone = {}
        for i, r in enumerate(loops):
            for k, v in enumerate(r):
                tone[v] = shade(i, k) if shade else 1.0
                if rule:
                    self.rules[v] = rule
        def cols(v):
            t = tone.get(v, 1.0)
            return (col[0] * t, col[1] * t, col[2] * t)
        faces = []
        span = n if closed else n - 1
        for a, b in zip(loops, loops[1:]):
            for k in range(span):
                f = self._face((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]), mat, cols)
                if f:
                    faces.append(f)
        if cap0:
            f = self._face(list(reversed(loops[0])), mat, cols)
            if f:
                faces.append(f)
        if cap1:
            f = self._face(loops[-1], mat, cols)
            if f:
                faces.append(f)
        return loops, faces


# --- rings -----------------------------------------------------------------------------------------

def ell(z, rx, ryf, ryb, n=32, cx=0.0, cy=0.0, wob=None, tilt=0.0):
    """A ring about Z at height z: half-width rx, to the front (+y) ryf, to the back ryb; `wob(a)`
    scales the radius at angle a (pleats, channels, fur); `tilt` lifts the front (+) or back."""
    pts = []
    for k in range(n):
        a = k / n * math.tau
        s = math.sin(a)
        r = wob(a) if wob else 1.0
        y = s * (ryf if s > 0 else ryb) * r
        pts.append(Vector((cx + math.cos(a) * rx * r, cy + y, z + tilt * y)))
    return pts


def disc_frame(c, d, r, n=14, wob=None, ry=None):
    """A ring of radius r about centre c, square to direction d (the limb's way)."""
    d = d.normalized()
    u = d.cross(Vector((0, 1, 0)))
    if u.length < 1e-3:
        u = Vector((1, 0, 0))
    u.normalize()
    v = u.cross(d).normalized()
    pts = []
    for k in range(n):
        a = k / n * math.tau
        rr = r * (wob(a) if wob else 1.0)
        pts.append(c + u * (math.cos(a) * rr) + v * (math.sin(a) * (ry if ry else r) * (rr / r)))
    return pts


def torso_rings(ease, bottom, flare, n=40, wob=None, top_ease=None):
    """The torso's rings, eased out by `ease`, from the shoulders down to `bottom` (below the seat a
    skirt, flaring by `flare` (dx, dyf, dyb) at its hem)."""
    te = ease if top_ease is None else top_ease
    rows = []
    for z, rx, f, b in TORSO:
        e = lerp(ease, te, smooth(1.2, 1.46, z))
        rows.append((z, rx + e, f + e, b + e))
    rows.sort()
    skirt = []
    if bottom < 0.86:
        z0, rx0, f0, b0 = rows[0]
        steps = max(2, int((0.86 - bottom) / 0.09))
        for s in range(1, steps + 1):
            t = s / steps
            z = lerp(0.86, bottom, t)
            k = t ** 1.15
            skirt.append((z, rx0 + 0.025 * smooth(0, 0.3, t) + flare[0] * k, f0 + flare[1] * k, b0 + flare[2] * k))
        skirt.reverse()
    else:
        rows = [r for r in rows if r[0] >= bottom - 0.001]
        if rows[0][0] > bottom + 0.001:
            z, rx, f, b = rows[0]
            rows.insert(0, (bottom, rx, f, b))
    rows = skirt + rows
    return [ell(z, rx, f, b, n, cy=-0.005, wob=wob) for z, rx, f, b in rows], [r[0] for r in rows]


def arm_points(side):
    m = Vector((side, 1, 1))
    pts = [SHOULDER_IN, SHOULDER, SHOULDER.lerp(ELBOW, 0.5), ELBOW, ELBOW.lerp(HAND, 0.5), ELBOW.lerp(HAND, 0.9)]
    return [Vector((p.x * m.x, p.y, p.z)) for p in pts]


ARM_R = [0.07, 0.072, 0.066, 0.06, 0.056, 0.05]


def sleeve(p, side, ease, mat="Cloth", col=W, end=0.9, n=16, cuff=None, full=0.0, ribs=0.0):
    """A sleeve from inside the shoulder to the wrist (`end` of the way from elbow to hand)."""
    pts = arm_points(side)
    pts[-1] = Vector((ELBOW.x * side, ELBOW.y, ELBOW.z)).lerp(Vector((HAND.x * side, HAND.y, HAND.z)), end)
    rad = [r + ease for r in ARM_R]
    rad[2] += full
    rad[4] += full * 1.4
    # sampled finer along the arm, so it bends round the elbow
    rings, ts = [], []
    seg = [(0, 1, 2), (1, 2, 4), (2, 3, 4), (3, 4, 4), (4, 5, 5)]
    for a, b, steps in seg:
        for s in range(steps):
            t = s / steps
            c = pts[a].lerp(pts[b], t)
            r = lerp(rad[a], rad[b], t)
            d = pts[min(b, 5)] - pts[a]
            rings.append((c, d, r))
    rings.append((pts[5], pts[5] - pts[4], rad[5]))
    if full > 0:
        # gathered into the cuff: the last rings drawn in
        c, d, r = rings[-1]
        rings[-1] = (c, d, ARM_R[5] + ease * 0.6)
    out = []
    for i, (c, d, r) in enumerate(rings):
        if ribs and 2 < i < len(rings) - 1:
            r *= 1.0 + ribs * (1 if i % 2 else -1)
        out.append(disc_frame(c, d, r, n))
    shade = lambda i, k: 0.82 if i == 0 else (0.9 if 7 <= i <= 9 and (k % 4 == 0) else 1.0)
    arm_pool = ("pool", ("arm%d" % side,), 0.0, None)
    loops, _ = p.loft(out, mat, col, shade=shade, rule=arm_pool)
    for ring in loops[:2]: # (into the shoulder: as the jacket's shoulder moves, body and arm)
        for v in ring:
            p.rules[v] = ("pool", ("jacket",), 0.0, None)
    if cuff:
        cm, cc, w, extra = cuff
        c5, d5 = pts[5], (pts[5] - pts[4]).normalized()
        r5 = rad[5] + (0.0 if full == 0 else -ease * 0.4)
        ring = [disc_frame(c5 - d5 * w, d5, r5 + extra * 0.7, n), disc_frame(c5 - d5 * (w * 0.5), d5, r5 + extra, n),
                disc_frame(c5 + d5 * 0.004, d5, r5 + extra * 0.8, n), disc_frame(c5 + d5 * 0.006, d5, r5 * 0.6, n)]
        p.loft(ring, cm, cc, rule=arm_pool)


def leg_rings(side, ease, bottom, n=18, blouse=0.0):
    rows = []
    for z, cx, rx, f, b in LEG:
        if z < bottom - 0.001:
            continue
        bl = blouse * smooth(bottom + 0.2, bottom + 0.06, z)
        rows.append((z, cx, rx + ease + bl, f + ease + bl, b + ease + bl))
    if rows[-1][0] > bottom + 0.001:
        # (interpolated down to the bottom)
        for (z1, *r1), (z0, *r0) in zip(LEG, LEG[1:]):
            if z0 <= bottom <= z1:
                t = (z1 - bottom) / (z1 - z0)
                cx, rx, f, b = [lerp(a, c, t) for a, c in zip(r1, r0)]
                rows.append((bottom, cx, rx + ease + blouse * 0.6, f + ease + blouse * 0.6, b + ease + blouse * 0.6))
                break
    rows.reverse()
    return [ell(z, rx, f, b, n, cx=cx * side, cy=-0.008) for z, cx, rx, f, b in rows], [r[0] for r in rows]


# --- the garments ----------------------------------------------------------------------------------

def collar_band(p, mat, col, h=0.03, ease=0.0, z0=None):
    z0 = NECK[0] - 0.012 if z0 is None else z0
    rx, f, b = NECK[1] + ease, NECK[2] + ease, NECK[3] + ease
    rings = [ell(z0 - 0.025, rx + 0.03, f + 0.03, b + 0.02, 32, cy=NECK_Y), ell(z0, rx + 0.004, f + 0.004, b + 0.004, 32, cy=NECK_Y),
             ell(z0 + h, rx, f, b, 32, cy=NECK_Y), ell(z0 + h + 0.004, rx - 0.008, f - 0.008, b - 0.008, 32, cy=NECK_Y)]
    p.loft(rings, mat, col, rule=("head_pool", None, 0.0, None))


def belt_ring(p, z, ease, mat="Leather", col=W, h=0.045, buckle=True, n=40, extra=0.0):
    rows = [r for r in TORSO]
    def at(z):
        for (z0, *a), (z1, *b) in zip(rows, rows[1:]):
            if z0 <= z <= z1:
                t = (z - z0) / (z1 - z0)
                return [lerp(x, y, t) for x, y in zip(a, b)]
        return list(rows[0][1:])
    rx, f, b = [v + ease + extra for v in at(z)]
    rings = [ell(z - h / 2, rx, f, b, n, cy=-0.005), ell(z - h / 2 + 0.004, rx + 0.006, f + 0.006, b + 0.006, n, cy=-0.005),
             ell(z + h / 2 - 0.004, rx + 0.006, f + 0.006, b + 0.006, n, cy=-0.005), ell(z + h / 2, rx, f, b, n, cy=-0.005)]
    p.loft(rings, mat, col, rule=("pool", ("jacket", "trousers"), 0.0, None))
    if buckle:
        box(p, (0, -0.005 + f + 0.008, z), (0.05, 0.012, h + 0.008), "Metal", W)
    return rx, f, b


def box(p, c, size, mat, col, rule=None, rot=0.0):
    """A small block (buttons, buckles, pouches), skinned like what's nearest."""
    c = Vector(c)
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    cr, sr = math.cos(rot), math.sin(rot)
    corners = []
    for z in (-hz, hz):
        for x, y in ((-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)):
            corners.append(c + Vector((x * cr - y * sr, x * sr + y * cr, z)))
    vs = [p.bm.verts.new(q) for q in corners]
    for v in vs:
        p.rules[v] = rule or ("pool", ("jacket", "trousers"), 0.0, c)
    for idx in ((3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        f = p._face([vs[i] for i in idx], mat, col)
        if f:
            f.smooth = False


def blob(p, c, r, mat, col, rule=None, n=8, rings=5):
    c = Vector(c)
    rr = r if hasattr(r, "__len__") else (r, r, r)
    pts = []
    for i in range(1, rings):
        th = i / rings * math.pi
        pts.append([c + Vector((math.sin(th) * math.cos(a) * rr[0], math.sin(th) * math.sin(a) * rr[1], math.cos(th) * rr[2]))
                    for a in (k / n * math.tau for k in range(n))])
    loops, faces = p.loft(pts, mat, col, rule=rule or ("pool", ("jacket",), 0.0, c))
    top = p.bm.verts.new(c + Vector((0, 0, rr[2])))
    bot = p.bm.verts.new(c - Vector((0, 0, rr[2])))
    for v in (top, bot):
        p.rules[v] = rule or ("pool", ("jacket",), 0.0, c)
    for k in range(n):
        p._face([loops[0][k], loops[0][(k + 1) % n], top][::-1], mat, col)
        p._face([loops[-1][k], loops[-1][(k + 1) % n], bot], mat, col)


def tube_path(p, path, r, mat, col, n=8, rule=None, wob=None, flat=1.0):
    rings = []
    for i, c in enumerate(path):
        d = path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]
        rr = r(i) if callable(r) else r
        rings.append(disc_frame(c, d, rr, n, wob=wob, ry=rr * flat))
    p.loft(rings, mat, col, cap0=True, cap1=True, rule=rule)


def torso_garment(p, ease, bottom, flare, mat="Cloth", col=W, wob=None, hem=None, n=40, open_front=False):
    rings, zs = torso_rings(ease, bottom, flare, n=n, wob=wob)
    def shade(i, k):
        z = zs[i]
        a = k / n * math.tau
        t = 1.0
        if z < 0.86:  # folds in the skirt
            t *= 1.0 - 0.1 * max(0.0, math.sin(a * 7 + 0.6)) * smooth(0.86, 0.5, z)
        if open_front and abs(a - math.pi / 2) < 0.08:
            t *= 0.55  # (the front's edge, where the coat closes)
        if i == 0:
            t *= 0.8
        return t
    loops, _ = p.loft(rings, mat, col, shade=shade, rule=("skirt", ("jacket", "trousers"), 0.0, None))
    # the hem turned up inside: a ring a little in and up (no hole to see into)
    r0 = rings[0]
    inner = [Vector((q.x * 0.96, (q.y + 0.005) * 0.96 - 0.005, q.z + 0.03)) for q in r0]
    p.loft([inner, r0], mat, (col[0] * 0.55, col[1] * 0.55, col[2] * 0.55), rule=("skirt", ("jacket", "trousers"), 0.0, None))
    if hem:
        # a band above the hem (embroidery, the fleece): the skirt's own surface stood off a little
        hm, hc, hh, hx = hem
        z0, z1 = zs[0], zs[1]
        rows = []
        for dz, dx in ((-0.002, 0.0), (0.006, hx), (hh - 0.006, hx), (hh, 0.0)):
            t = min(max(dz, 0.0) / (z1 - z0), 1.0)
            ring = [a.lerp(b, t) for a, b in zip(rings[0], rings[1])]
            rows.append([Vector((q.x * (1 + 0.012 + dx * 4), (q.y + 0.005) * (1 + 0.012 + dx * 4) - 0.005, q.z)) for q in ring])
        p.loft(rows, hm, hc, rule=("skirt", ("jacket", "trousers"), 0.0, None))
    return zs


def neck_top(p, ease, mat, col, n=40):
    """The shoulders' top ring drawn in to the collar."""
    z, rx, f, b = TORSO[-1]
    p.loft([ell(z, rx + ease, f + ease, b + ease, n, cy=-0.005), ell(NECK[0] - 0.005, NECK[1] + ease + 0.008, NECK[2] + ease + 0.008, NECK[3] + ease + 0.006, n, cy=NECK_Y)],
           mat, col, rule=("head_pool", None, 0.0, None))


def shirt(name="shirt", bottom=0.70, ease=0.014, embroider=True, belt="cord", flare=(0.04, 0.035, 0.04)):
    p = Piece(name)
    zs = torso_garment(p, ease, bottom, flare, hem=("Trim", EMBROIDERY, 0.035, 0.002) if embroider else None)
    neck_top(p, ease, "Cloth", W)
    collar_band(p, "Trim" if embroider else "Cloth", EMBROIDERY if embroider else W, h=0.026, ease=0.004)
    for side in (-1, 1):
        sleeve(p, side, ease, full=0.012 if embroider else 0.004, cuff=("Trim" if embroider else "Cloth", EMBROIDERY if embroider else W, 0.03, 0.006))
    # the side placket, buttoned at the left of the collar
    front = TORSO[-4][2] + ease
    for i, z in enumerate((1.47, 1.43, 1.39)):
        blob(p, (-0.045, -0.005 + front * (0.86 + i * 0.04) + 0.004, z), 0.007, "Metal", W, n=6, rings=4)
    box(p, (-0.03, -0.005 + front * 0.96, 1.41), (0.022, 0.012, 0.15), "Trim" if embroider else "Cloth", EMBROIDERY if embroider else SEAM)
    if belt == "cord":
        rx, f, b = belt_ring(p, 0.975, ease, mat="Belt", h=0.016, buckle=False)
        # the cord's two ends hanging at the left hip, tasselled
        for dx in (0.0, 0.022):
            top = Vector((-rx * 0.72 + dx, f * 0.62, 0.97))
            tube_path(p, [top, top + Vector((0.004, 0.006, -0.08)), top + Vector((0.008, 0.008, -0.15))], lambda i: 0.006 if i < 2 else 0.011, "Belt", W, n=6,
                      rule=("pool", ("trousers",), 0.4, top))
    elif belt == "leather":
        belt_ring(p, 0.975, ease, mat="Leather", h=0.045)
        # a soldier's tunic: breast pockets, buttoned
        for sx in (-1, 1):
            c = (sx * 0.085, -0.005 + TORSO[6][2] + ease + 0.006, 1.29)
            box(p, c, (0.075, 0.012, 0.085), "Cloth", (0.86, 0.86, 0.86))
            blob(p, (c[0], c[1] + 0.008, 1.32), 0.007, "Metal", W, n=6, rings=4)
    return p


def padded():
    p = Piece("padded")
    n = 44
    ch = lambda a: 1.0 + 0.022 * (1 if (int(a / math.tau * n) % 2) else -1)
    ease = 0.034
    torso_garment(p, ease, 0.79, (0.03, 0.02, 0.025), wob=ch, n=n, open_front=True)
    neck_top(p, ease, "Cloth", W, n=n)
    collar_band(p, "Cloth", W, h=0.045, ease=0.02)
    for side in (-1, 1):
        sleeve(p, side, ease - 0.004, ribs=0.035, cuff=("ClothDark", W, 0.035, 0.004))
    front = TORSO[4][2] + ease
    for z in (0.88, 1.0, 1.12, 1.24, 1.36):
        blob(p, (0.0, -0.005 + front + 0.01 + (0.012 if z > 1.2 else 0.0), z), 0.011, "Button", W, n=6, rings=4)
    return p


def shinel(name="shinel", ease=0.04, bottom=0.30):
    p = Piece(name)
    torso_garment(p, ease, bottom, (0.07, 0.07, 0.1), open_front=True)
    neck_top(p, ease, "Cloth", W)
    # the turned-down collar lying wide on the shoulders
    rows = [(NECK[0] + 0.022, 0.0), (NECK[0] - 0.005, 0.012), (1.46, 0.05), (1.425, 0.085)]
    rings = [ell(z, NECK[1] + ease + d, NECK[2] + ease + d * 1.3, NECK[3] + ease + d * 0.8, 40, cy=NECK_Y) for z, d in rows]
    p.loft(rings, "ClothDark", W, rule=("head_pool", None, 0.0, None))
    for side in (-1, 1):
        sleeve(p, side, ease - 0.006, cuff=("ClothDark", W, 0.07, 0.01))
    for sx in (-1, 1):
        for i, z in enumerate((1.06, 1.15, 1.24, 1.33)):
            w = 0.075 - (i * 0.004)
            y = -0.005 + TORSO[4 + i][2] + ease + 0.008
            blob(p, (sx * w, y, z), 0.011, "Metal", W, n=6, rings=4)
    belt_ring(p, 0.985, ease, mat="Leather", h=0.05, extra=0.004)
    return p


def tulup(name="tulup", ease=0.05, bottom=0.30):
    p = Piece(name)
    torso_garment(p, ease, bottom, (0.1, 0.09, 0.12), mat="Hide", open_front=True, hem=("Fur", W, 0.06, 0.012))
    neck_top(p, ease, "Hide", W)
    for side in (-1, 1):
        sleeve(p, side, ease - 0.008, mat="Hide", cuff=("Fur", W, 0.07, 0.02))
    # the fleece turned out in a great collar: standing up round the neck, and down the front in
    # two broad lapels crossing at the belt
    path = []
    for i in range(15):
        t = i / 14
        a = lerp(0.35, math.pi - 0.35, t)  # (from the front right, round the back, to the front left)
        x = math.cos(a) * (NECK[1] + 0.045)
        y = NECK_Y - math.sin(a) * (NECK[3] + 0.04)
        path.append(Vector((x, y, NECK[0] - 0.01)))
    def chest_y(z, x):
        rows = sorted(TORSO)
        for (z0, rx0, f0, b0), (z1, rx1, f1, b1) in zip(rows, rows[1:]):
            if z0 <= z <= z1:
                t = (z - z0) / (z1 - z0)
                rx, f = lerp(rx0, rx1, t) + ease, lerp(f0, f1, t) + ease
                return -0.005 + f * math.sqrt(max(0.0, 1 - (x / rx) ** 2)) + 0.016
        return 0.15
    right = []
    for t in (0.0, 0.2, 0.45, 0.7, 1.0):
        z = lerp(1.47, 0.99, t)
        x = lerp(0.1, 0.02, t)
        right.append(Vector((x, chest_y(z, x) if t > 0 else NECK_Y + NECK[2] + 0.05, z)))
    left = [Vector((-q.x + 0.012, q.y + 0.006, q.z)) for q in right]
    full = list(reversed(right)) + path + left
    tube_path(p, full, lambda i: 0.05 + 0.006 * math.sin(i * 1.7), "Fur", W, n=12, rule=("pool", ("jacket",), 0.0, None),
              wob=lambda a: 1.0 + 0.1 * noise.noise(Vector((a * 2.0, 0.5, 0.2))), flat=0.45)
    # the fleece edge down the front from the belt to the hem
    edge = [Vector((-0.02, -0.005 + TORSO[2][2] + ease + 0.012 + 0.07 * smooth(0.86, bottom, z), z)) for z in (0.97, 0.86, 0.7, 0.55, bottom + 0.06)]
    tube_path(p, edge, 0.02, "Fur", W, n=8, rule=("skirt", ("jacket", "trousers"), 0.0, None))
    rx, f, b = belt_ring(p, 0.975, ease, mat="Belt", h=0.06, buckle=False, extra=0.006)
    top = Vector((-rx * 0.7, f * 0.7, 0.97))
    for dx in (0.0, 0.03):
        tube_path(p, [top + Vector((dx, 0, 0)), top + Vector((dx + 0.01, 0.01, -0.12)), top + Vector((dx + 0.02, 0.02, -0.24))], 0.016, "Belt", W, n=6,
                  rule=("pool", ("trousers",), 0.4, top))
    return p


def blouse():
    p = Piece("blouse")
    torso_garment(p, 0.012, 0.95, (0, 0, 0))
    neck_top(p, 0.012, "Cloth", W)
    collar_band(p, "Trim", EMBROIDERY, h=0.018, ease=0.004)
    for side in (-1, 1):
        sleeve(p, side, 0.012, full=0.018, cuff=("Trim", EMBROIDERY, 0.025, 0.004))
    return p


SKIRT = [(1.02, 0.175, 0.136, 0.14), (0.94, 0.205, 0.15, 0.165), (0.78, 0.24, 0.19, 0.21), (0.55, 0.265, 0.225, 0.245),
         (0.32, 0.288, 0.252, 0.272), (0.12, 0.305, 0.27, 0.29), (0.07, 0.308, 0.272, 0.292)]


def skirt():
    p = Piece("skirt")
    n = 48
    rings = []
    for z, rx, f, b in SKIRT:
        k = smooth(1.0, 0.3, z)
        rings.append(ell(z, rx, f, b, n, cy=-0.005, wob=lambda a, k=k: 1.0 + 0.03 * k * math.sin(a * 14)))
    rings.reverse()
    p.loft(rings, "Cloth", W, shade=lambda i, k: 0.72 if i == 0 else 0.86 + 0.14 * (0.5 + 0.5 * math.sin(k / n * math.tau * 14 + 1.2)),
           rule=("skirt", ("trousers",), 0.45, None))
    inner = [Vector((q.x * 0.97, q.y * 0.97, q.z + 0.03)) for q in rings[0]]
    p.loft([inner, rings[0]], "Cloth", (0.5, 0.5, 0.5), rule=("skirt", ("trousers",), 0.45, None))
    # a darker band above the hem
    band = [ell(z, rx + 0.004, f + 0.004, b + 0.004, n, cy=-0.005, wob=lambda a: 1.0 + 0.03 * math.sin(a * 14)) for z, rx, f, b in
            ((0.1, 0.306, 0.271, 0.291), (0.14, 0.302, 0.267, 0.287))]
    p.loft(band, "Trim", (0.75, 0.75, 0.75), rule=("skirt", ("trousers",), 0.45, None))
    # the waistband
    p.loft([ell(0.995, 0.178, 0.139, 0.143, n, cy=-0.005), ell(1.035, 0.176, 0.137, 0.141, n, cy=-0.005)], "ClothDark", W,
           rule=("pool", ("jacket", "trousers"), 0.0, None))
    return p


def apron():
    p = Piece("apron")
    rows = []
    for z, rx, f, b in [(1.0, 0.178, 0.139, 0.143), (0.94, 0.208, 0.153, 0.168), (0.78, 0.243, 0.193, 0.213), (0.55, 0.268, 0.228, 0.248), (0.3, 0.29, 0.254, 0.274)]:
        ring = []
        for k in range(13):
            a = lerp(0.42, math.pi - 0.42, k / 12)
            r = 1.0 + 0.03 * smooth(1.0, 0.3, z) * math.sin(a * 14) + 0.05
            ring.append(Vector((math.cos(a) * rx * r, -0.005 + math.sin(a) * f * r + 0.004, z)))
        rows.append(ring)
    rows.reverse()
    p.loft(rows, "Apron", W, closed=False, shade=lambda i, k: 0.75 if i == 0 else 1.0, rule=("skirt", ("trousers",), 0.45, None))
    # its band round the waist, the ties at the back
    p.loft([ell(1.0, 0.184, 0.145, 0.149, 40, cy=-0.005), ell(1.03, 0.183, 0.144, 0.148, 40, cy=-0.005)], "Apron", W,
           rule=("pool", ("jacket", "trousers"), 0.0, None))
    knot = Vector((0.0, -0.16, 1.01))
    blob(p, knot, (0.03, 0.015, 0.02), "Apron", W)
    for sx in (-1, 1):
        tube_path(p, [knot, knot + Vector((sx * 0.03, -0.01, -0.07)), knot + Vector((sx * 0.04, -0.012, -0.16))], 0.012, "Apron", W, n=6,
                  rule=("pool", ("trousers",), 0.5, knot))
    return p


def shawl():
    """A shawl over a woman's shoulders, its point down the back, the ends crossed at the breast."""
    p = Piece("shawl")
    n = 40
    rows = []
    for z, d, back in ((NECK[0] - 0.01, 0.012, 0.0), (1.47, 0.06, 0.0), (1.43, 0.08, 0.03), (1.36, 0.075, 0.08), (1.3, 0.06, 0.14)):
        ring = ell(z, NECK[1] + d + (0.11 if z < 1.47 else 0.06 * (1.5 - z) / 0.03), NECK[2] + d + 0.02, NECK[3] + d + 0.02, n, cy=NECK_Y)
        out = []
        for k, q in enumerate(ring):
            a = k / n * math.tau
            down = back * max(0.0, -math.sin(a)) ** 2  # (the point hangs down the back)
            out.append(Vector((q.x, q.y, q.z - down * 1.4)))
        rows.append(out)
    rows.reverse()
    p.loft(rows, "Cloth", W, shade=lambda i, k: 0.75 if i == 0 else (0.88 if k % 5 == 0 else 1.0), rule=("shawl", ("jacket",), 0.0, None))
    # a fringe of darker border along the edge
    edge = rows[0]
    inner = [Vector((q.x * 0.985, (q.y - NECK_Y) * 0.985 + NECK_Y, q.z + 0.02)) for q in edge]
    p.loft([edge, inner], "Trim", W, rule=("shawl", ("jacket",), 0.0, None))
    return p


def trousers(name="trousers", bottom=0.36, blouse=0.018):
    p = Piece(name)
    # the seat and the waist
    rows = [(1.03, 0.178, 0.132, 0.137), (0.97, 0.188, 0.135, 0.145), (0.9, 0.2, 0.135, 0.155), (0.84, 0.205, 0.12, 0.14)]
    p.loft([ell(z, rx + 0.01, f + 0.01, b + 0.01, 36, cy=-0.005) for z, rx, f, b in reversed(rows)], "Cloth", W,
           shade=lambda i, k: 0.7 if i == 0 else 1.0, rule=("pool", ("trousers",), 0.0, None))
    for side in (-1, 1):
        rings, zs = leg_rings(side, 0.014, bottom, blouse=blouse)
        p.loft(rings, "Cloth", W, shade=lambda i, k: (0.78 if i == 0 else 1.0) * (0.86 if k == 4 or k == 13 else 1.0),
               rule=("pool", ("trousers",), 0.0, None))
    return p


def foot_rings(side, ln=1.0, puff=0.0, n=14, top=0.075):
    """The foot from heel to toe: (y, z of the middle, half-width, half-height)."""
    rows = [(-0.088, 0.055, 0.05, 0.055), (-0.05, 0.06, 0.056, 0.06), (0.02, 0.052, 0.056, 0.052), (0.09, 0.042, 0.054, 0.042),
            (0.16, 0.035, 0.05, 0.034), (0.21, 0.03, 0.043, 0.028), (0.238 * ln, 0.03, 0.03, 0.02)]
    rings = []
    for y, z, w, h in rows:
        w += puff
        h += puff * 0.8
        z = max(z, h + 0.006)
        pts = []
        for k in range(n):
            a = k / n * math.tau
            pts.append(Vector((0.097 * side + math.cos(a) * w, y, z + math.sin(a) * h)))
        rings.append(pts)
    return rings


def footwear(name, kind):
    p = Piece(name)
    for side in (-1, 1):
        if kind == "boots":
            shaft = [(0.07, 0.061, 0.064, 0.072), (0.16, 0.059, 0.066, 0.072), (0.3, 0.068, 0.072, 0.086), (0.44, 0.08, 0.084, 0.094), (0.465, 0.083, 0.087, 0.097)]
            mat, puff, cc = "Leather", 0.0, W
        elif kind == "valenki":
            shaft = [(0.07, 0.068, 0.07, 0.078), (0.2, 0.072, 0.075, 0.085), (0.36, 0.08, 0.083, 0.092), (0.47, 0.087, 0.09, 0.098), (0.5, 0.088, 0.091, 0.099)]
            mat, puff, cc = "Felt", 0.012, W
        else:  # the leg wraps of the bast shoes
            shaft = [(0.06, 0.062, 0.065, 0.07), (0.18, 0.066, 0.068, 0.078), (0.3, 0.072, 0.072, 0.088), (0.42, 0.078, 0.078, 0.094), (0.45, 0.077, 0.077, 0.092)]
            mat, puff, cc = "Linen", 0.004, W
        rings = [ell(z, rx, f, b, 16, cx=0.097 * side, cy=-0.012, wob=(lambda a: 1.0 + 0.03 * math.sin(a * 5)) if kind == "valenki" else None) for z, rx, f, b in shaft]
        # the shaft's top folded in (its thickness)
        z, rx, f, b = shaft[-1]
        rings.append(ell(z - 0.02, rx - 0.012, f - 0.012, b - 0.012, 16, cx=0.097 * side, cy=-0.012))
        shade = (lambda i, k: (0.9 if i < 2 else 1.0) * (0.8 + 0.2 * ((i + k // 2) % 2))) if kind == "lapti" else (lambda i, k: 0.6 if i == len(shaft) else 1.0)
        p.loft(rings, mat, cc, shade=shade, rule=("pool", ("boots", "trousers"), 0.0, None))
        if kind == "lapti":
            # the bast shoe: woven, low, over the foot, cords crossed up the wrap
            fr = foot_rings(side, puff=0.008)
            fr = [[Vector((q.x, q.y, min(q.z, 0.085))) for q in r] for r in fr]
            p.loft(fr, "Bast", W, cap0=True, cap1=True, shade=lambda i, k: 0.7 + 0.3 * ((i + k) % 2), rule=("pool", ("boots",), 0.0, None))
            for ph in (0.0, math.pi):
                path = []
                for s in range(17):
                    t = s / 16
                    z = lerp(0.09, 0.43, t)
                    a = ph + t * math.tau * 2.2
                    r = lerp(0.07, 0.083, t)
                    path.append(Vector((0.097 * side + math.cos(a) * r, -0.012 + math.sin(a) * r * 1.08, z)))
                tube_path(p, path, 0.0045, "Bast", (0.7, 0.7, 0.7), n=5, rule=("pool", ("boots", "trousers"), 0.0, None))
            continue
        fr = foot_rings(side, puff=puff)
        p.loft(fr, mat, cc, cap0=True, cap1=True, shade=lambda i, k: 0.85 if k in (0, 1, 13) else 1.0, rule=("pool", ("boots",), 0.0, None))
        if kind == "boots":
            # sole and heel
            box(p, (0.097 * side, 0.08, 0.008), (0.1, 0.25, 0.016), "Sole", W, rule=("pool", ("boots",), 0.0, None))
            box(p, (0.097 * side, -0.065, 0.016), (0.085, 0.06, 0.032), "Sole", W, rule=("pool", ("boots",), 0.0, None))
    return p


# --- on the head (rigid to it) -----------------------------------------------------------------------

def band_z(y, z0, lift=0.022):
    return z0 + lift * (y / 0.115)


def head_ring(z0, rx, ry, n=28, lift=0.022, dz=0.0, wob=None):
    out = []
    for k in range(n):
        a = k / n * math.tau
        r = wob(a) if wob else 1.0
        x, y = math.cos(a) * rx * r, HEAD_Y + math.sin(a) * ry * r
        out.append(Vector((x, y, band_z(y - HEAD_Y, z0, lift) + dz)))
    return out


HEADR = ("head", None, 0.0, None)
HAT_Z = 1.668  # the band's bottom round the middle of the head (the front higher, the back lower)


def kartuz():
    p = Piece("kartuz")
    z = HAT_Z
    rings = [head_ring(z, 0.099, 0.116), head_ring(z, 0.1, 0.117, dz=0.04), head_ring(z, 0.112, 0.13, dz=0.065, lift=0.03),
             head_ring(z, 0.108, 0.124, dz=0.088, lift=0.035), head_ring(z, 0.06, 0.07, dz=0.098, lift=0.035)]
    p.loft(rings, "Cloth", W, cap1=True, shade=lambda i, k: 0.85 if i == 1 else 1.0, rule=HEADR)
    p.loft([head_ring(z, 0.1, 0.117, dz=-0.002), head_ring(z, 0.101, 0.118, dz=0.03)], "ClothDark", W, rule=HEADR)
    peak(p, z + 0.012, 0.075, "Leather")
    return p


def peak(p, z, depth, mat, w=0.095, droop=0.02):
    rows = []
    for j in range(4):
        t = j / 3
        row = []
        for k in range(9):
            s = lerp(-1, 1, k / 8)
            x = s * w * (1 - 0.35 * t * t)
            y = HEAD_Y + 0.11 * math.sqrt(max(0.0, 1 - (x / 0.105) ** 2)) * (1 - t) + (0.112 + depth * t) * t
            row.append(Vector((x, y, band_z(0.115, z) - droop * t * t + 0.003)))
        rows.append(row)
    top = rows
    bot = [[q + Vector((0, 0, -0.008)) for q in r] for r in rows]
    p.loft(top, mat, W, closed=False, rule=HEADR)
    p.loft(list(reversed(bot)), mat, (0.6, 0.6, 0.6), closed=False, rule=HEADR)
    p.loft([top[-1], bot[-1]], mat, W, closed=False, rule=HEADR)


def furazhka():
    p = Piece("furazhka")
    z = HAT_Z + 0.004
    p.loft([head_ring(z, 0.1, 0.117), head_ring(z, 0.101, 0.118, dz=0.042)], "Band", W, rule=HEADR)
    crown = [head_ring(z, 0.101, 0.118, dz=0.042), head_ring(z, 0.125, 0.142, dz=0.072, lift=0.04), head_ring(z, 0.127, 0.145, dz=0.082, lift=0.045),
             head_ring(z, 0.11, 0.128, dz=0.088, lift=0.045), head_ring(z, 0.05, 0.06, dz=0.092, lift=0.045)]
    p.loft(crown, "Cloth", W, cap1=True, shade=lambda i, k: 0.8 if i == 0 else 1.0, rule=HEADR)
    peak(p, z, 0.06, "Sole", w=0.09, droop=0.03)
    blob(p, (0.0, HEAD_Y + 0.121, band_z(0.115, z) + 0.024), (0.012, 0.006, 0.016), "Metal", W, rule=HEADR)
    return p


def papakha(name="papakha", h=0.15):
    p = Piece(name)
    z = HAT_Z - 0.006
    fur = lambda zz: (lambda a: 1.0 + 0.045 * noise.noise(Vector((math.cos(a) * 3, math.sin(a) * 3, zz * 20))))
    rows = [head_ring(z, 0.103, 0.12, dz=-0.004, lift=0.015)]
    for j in range(1, 6):
        t = j / 5
        rows.append(head_ring(z, 0.11 + 0.008 * t, 0.127 + 0.008 * t, dz=h * t, lift=0.015, wob=fur(t)))
    rows.append(head_ring(z, 0.104, 0.12, dz=h + 0.01, lift=0.015, wob=fur(1.2)))
    p.loft(rows, "Fur", W, shade=lambda i, k: 0.75 + 0.25 * (0.5 + 0.5 * noise.noise(Vector((i * 0.9, k * 0.7, 1.0)))), rule=HEADR)
    p.loft([head_ring(z, 0.104, 0.12, dz=h + 0.01, lift=0.015), head_ring(z, 0.095, 0.11, dz=h - 0.004, lift=0.015)], "Top", W, cap1=True, rule=HEADR)
    # (the cloth top crossed with braid)
    for rot in (0.0, math.pi / 2):
        box(p, (0, HEAD_Y, band_z(0, z) + h - 0.002), (0.19, 0.01, 0.004), "Trim", W, rule=HEADR, rot=rot)
    return p


def ushanka():
    p = Piece("ushanka")
    z = HAT_Z - 0.004
    fur = lambda a: 1.0 + 0.05 * noise.noise(Vector((math.cos(a) * 4, math.sin(a) * 4, 0.7)))
    p.loft([head_ring(z, 0.099, 0.117, dz=0.02), head_ring(z, 0.103, 0.12, dz=0.07), head_ring(z, 0.088, 0.104, dz=0.105), head_ring(z, 0.04, 0.05, dz=0.122)],
           "Cloth", W, cap1=True, rule=HEADR)
    # the fur turned up all round, deeper at the front
    rows = [head_ring(z, 0.104, 0.122, dz=-0.008, wob=fur), head_ring(z, 0.122, 0.142, dz=0.0, wob=fur), head_ring(z, 0.126, 0.148, dz=0.045, wob=fur),
            head_ring(z, 0.112, 0.13, dz=0.06, wob=fur), head_ring(z, 0.1, 0.118, dz=0.045)]
    p.loft(rows, "Fur", W, shade=lambda i, k: 0.8 + 0.2 * ((k * 7 + i * 3) % 5) / 4, rule=HEADR)
    # the ear flaps down
    for sx in (-1, 1):
        rings = []
        for j, zz in enumerate((1.665, 1.63, 1.59, 1.565)):
            w = (0.035, 0.05, 0.048, 0.03)[j]
            c = Vector((sx * (0.104 - j * 0.006), HEAD_Y - 0.012, zz))
            rings.append([c + Vector((sx * math.cos(a) * 0.018, math.sin(a) * w, 0)) for a in (k / 10 * math.tau for k in range(10))])
        p.loft(rings, "Fur", W, cap1=True, shade=lambda i, k: 0.85 + 0.15 * (k % 2), rule=HEADR)
    # a flap's tie
    return p


def budenovka():
    p = Piece("budenovka")
    z = HAT_Z - 0.004
    rows = [head_ring(z, 0.101, 0.118, dz=0.0), head_ring(z, 0.106, 0.122, dz=0.05), head_ring(z, 0.098, 0.112, dz=0.1),
            head_ring(z, 0.07, 0.08, dz=0.15), head_ring(z, 0.035, 0.04, dz=0.2), head_ring(z, 0.012, 0.014, dz=0.24)]
    # (sewn of panels: the seams darker)
    p.loft(rows, "Cloth", W, cap1=True, shade=lambda i, k: 0.82 if k % 7 == 0 else 1.0, rule=HEADR)
    blob(p, (0, HEAD_Y, band_z(0, z) + 0.247), 0.016, "Cloth", W, rule=HEADR)
    # the flaps folded up round it, buttoned at the front
    fl = [head_ring(z, 0.105, 0.122, dz=-0.012), head_ring(z, 0.113, 0.13, dz=-0.006), head_ring(z, 0.113, 0.13, dz=0.045), head_ring(z, 0.105, 0.122, dz=0.05)]
    p.loft(fl, "ClothDark", W, rule=HEADR)
    for sx in (-1, 1):
        blob(p, (sx * 0.04, HEAD_Y + 0.126, band_z(0.115, z) + 0.035), 0.008, "Metal", W, rule=HEADR)
    peak(p, z - 0.006, 0.055, "ClothDark", w=0.09, droop=0.02)
    star(p, Vector((0.0, HEAD_Y + 0.112, band_z(0.1, z) + 0.105)), 0.04, -0.35)
    return p


def star(p, c, r, tilt):
    """A five-pointed star on the front, a little raised."""
    pts = []
    for k in range(10):
        a = math.pi / 2 + k / 10 * math.tau
        rr = r if k % 2 == 0 else r * 0.42
        x, z = math.cos(a) * rr, math.sin(a) * rr
        pts.append(c + Vector((x, -z * math.sin(tilt), z * math.cos(tilt))))
    mid = p.bm.verts.new(c + Vector((0, 0.006, 0)))
    vs = [p.bm.verts.new(q) for q in pts]
    p.rules[mid] = HEADR
    for v in vs:
        p.rules[v] = HEADR
    for k in range(10):
        p._face([vs[k], vs[(k + 1) % 10], mid], "Star", W)


# --- from the head's own skin: the kerchief, hair, beards --------------------------------------------

class HeadSrc:
    """The townsman's head (Survivor_Body's skin): its points, normals, faces and weights, so what
    lies on the face (a beard, a kerchief) can be cut from it and stood off it."""

    def __init__(self, ob):
        me = ob.data
        self.co = [v.co.copy() for v in me.vertices]
        self.no = [v.normal.copy() for v in me.vertices]
        skin = me.materials.find("HeadSkin")
        self.faces = [list(f.vertices) for f in me.polygons if f.material_index == skin]
        self.weights = []
        names = {g.index: g.name for g in ob.vertex_groups}
        for v in me.vertices:
            self.weights.append({names[g.group]: g.weight for g in v.groups if g.weight > 0.001})


def shell(p, src, keep, off, mat, col, solid=0.0, shade=None, move=None):
    """The head's faces whose corners all pass `keep(co)`, stood off along their normals by
    `off(co)`, each point then moved by `move(co, new)`; `solid` closes it back toward the skin."""
    used = {}
    faces = [f for f in src.faces if all(keep(src.co[i]) for i in f)]
    for f in faces:
        for i in f:
            if i not in used:
                c = src.co[i]
                q = c + src.no[i] * off(c)
                if move:
                    q = move(c, q)
                v = p.bm.verts.new(q)
                used[i] = v
                p.rules[v] = ("copy", src.weights[i], 0.0, None)
    def cols(v):
        t = shade(v.co) if shade else 1.0
        return (col[0] * t, col[1] * t, col[2] * t)
    made = []
    for f in faces:
        g = p._face([used[i] for i in f], mat, cols)
        if g:
            made.append(g)
    if solid > 0 and made:
        # the open edge folded back in toward the skin (a thickness to it)
        edges = [e for e in {e for g in made for e in g.edges} if len(e.link_faces) == 1]
        inner = {}
        for e in edges:
            for v in e.verts:
                if v not in inner:
                    n = v.normal if v.normal.length > 0.1 else Vector((0, 0, 1))
                    w = p.bm.verts.new(v.co - n * solid)
                    p.rules[w] = p.rules[v]
                    inner[v] = w
        for e in edges:
            a, b = e.verts
            p._face([a, b, inner[b], inner[a]], mat, (col[0] * 0.6, col[1] * 0.6, col[2] * 0.6))
    return made


HOOD_C = Vector((0.0, 0.005, 1.64))


def hood_pt(th, ph, e):
    """A point of the cloth over the head: azimuth th (0 at +x, 90 degrees to the front), elevation
    ph, on an egg a little bigger than the head (`e` out from it)."""
    c, s = math.cos(ph), math.sin(ph)
    ry = (0.126 if math.sin(th) > 0 else 0.118) + e
    rz = (0.134 if s > 0 else 0.152) + e
    return HOOD_C + Vector((math.cos(th) * c * (0.101 + e), math.sin(th) * c * ry, s * rz))


def in_face(th, ph, grow=0.0):
    return ((math.degrees(th) - 90) / (60 + grow)) ** 2 + ((math.degrees(ph) + 9) / (39 + grow)) ** 2 < 1.0


def kerchief(src, name="kerchief", big=False):
    """Tied over the head, the face showing in its opening, the cloth drawn under the chin and
    knotted there; `big` the winter's wool shawl, thicker, down over the shoulders as well."""
    p = Piece(name)
    e = 0.024 if big else 0.016
    nt, nphi = 40, 22
    phis = [math.radians(lerp(-62, 90, j / nphi)) for j in range(nphi + 1)]
    ths = [k / nt * math.tau for k in range(nt)]
    grid = {}
    for j, ph in enumerate(phis[:-1]):
        for k, th in enumerate(ths):
            # (a few folds in the cloth, deeper toward the back)
            fold = 1.0 + 0.012 * math.sin(th * 7 + ph * 3) * max(0.0, -math.sin(th))
            q = hood_pt(th, ph, e) - HOOD_C
            grid[(j, k)] = HOOD_C + q * fold
    top = p.bm.verts.new(HOOD_C + Vector((0, 0, 0.134 + e)))
    p.rules[top] = HEADR
    verts = {}
    def vert(j, k):
        if (j, k) not in verts:
            v = p.bm.verts.new(grid[(j, k % nt)])
            p.rules[v] = HEADR
            verts[(j, k)] = v
        return verts[(j, k)]
    shade = lambda v: tuple(c * (0.82 + 0.18 * smooth(1.5, 1.66, v.co.z)) for c in W)
    for j in range(nphi - 1):
        for k in range(nt):
            cth = (ths[k] + math.pi / nt)
            cph = (phis[j] + phis[j + 1]) / 2
            if in_face(cth, cph):
                continue
            p._face([vert(j, k), vert(j, k + 1 if k + 1 < nt else 0), vert(j + 1, k + 1 if k + 1 < nt else 0), vert(j + 1, k)], "Cloth", shade)
    for k in range(nt):
        p._face([vert(nphi - 1, k), vert(nphi - 1, (k + 1) % nt), top], "Cloth", W)
    # down from under the jaw round the neck, closing on it
    low = [grid[(0, k)] for k in range(nt)]
    neck = ell(NECK[0] - 0.005, NECK[1] + e * 0.8, NECK[2] + e * 0.8, NECK[3] + e, nt, cy=NECK_Y)
    neck = [neck[(k) % nt] for k in range(nt)]
    loops, _ = p.loft([neck, low], "Cloth", (0.8, 0.8, 0.8), rule=("head_pool", None, 0.0, None))
    for k, v in enumerate(loops[1]):
        p.rules[v] = HEADR
    # the cloth's edge rolled round the face
    edge = []
    for k in range(33):
        a = k / 32 * math.tau
        th = math.radians(90 + 60 * math.cos(a))
        ph = math.radians(-9 + 39 * math.sin(a))
        edge.append(hood_pt(th, ph, e + 0.004))
    tube_path(p, edge, 0.015 if big else 0.011, "Cloth", (0.88, 0.88, 0.88), n=8, rule=HEADR)
    # the knot under the chin and its ends
    knot = Vector((0.0, 0.085, 1.495))
    blob(p, knot, (0.03, 0.022, 0.02), "Cloth", W, rule=HEADR)
    for sx in (-1, 1):
        tube_path(p, [knot, knot + Vector((sx * 0.02, 0.012, -0.04)), knot + Vector((sx * 0.03, 0.016, -0.075))], 0.012, "Cloth", (0.85, 0.85, 0.85), n=6,
                  rule=("head_pool", None, 0.0, knot))
    # the point hanging down the back of the head
    tip = [hood_pt(math.radians(240), math.radians(10), e + 0.002), hood_pt(math.radians(300), math.radians(10), e + 0.002),
           Vector((0.0, -0.13 - e, 1.5 if not big else 1.4))]
    vs = [p.bm.verts.new(q) for q in tip]
    for v in vs:
        p.rules[v] = HEADR if v.co.z > 1.55 else ("head_pool", None, 0.0, None)
    p._face(vs, "Cloth", W)
    p._face(list(reversed(vs)), "Cloth", (0.7, 0.7, 0.7))
    if big:
        # the shawl's wings over the shoulders, crossed at the breast
        n = 40
        rows = []
        # (worn over a winter coat: it lies on the coat's shoulders, not in them)
        for z, d in ((1.53, 0.035), (1.5, 0.09), (1.45, 0.13), (1.38, 0.14), (1.31, 0.13)):
            rows.append(ell(z, NECK[1] + d + (0.105 if z < 1.49 else 0.03), NECK[2] + d + 0.02, NECK[3] + d + 0.03, n, cy=NECK_Y))
        rows.reverse()
        p.loft(rows, "Cloth", W, shade=lambda i, k: 0.72 if i == 0 else (0.88 if k % 5 == 0 else 1.0), rule=("shawl", ("jacket",), 0.0, None))
    return p


def hair(src):
    p = Piece("hair")
    def keep(c):
        if c.y > 0.04:
            return c.z > 1.725 - 0.04 * min(1.0, abs(c.x) / 0.08)
        if c.y > -0.02:
            return c.z > 1.672
        return c.z > 1.6 - 0.02 * (abs(c.x) / 0.08)
    off = lambda c: 0.006 + 0.012 * smooth(1.66, 1.76, c.z)
    lump = lambda c, q: q + Vector((0, 0, 0.004 * noise.noise(c * 60.0)))
    shell(p, src, keep, off, "Hair", W, solid=0.008, move=lump, shade=lambda q: 0.85 + 0.15 * (0.5 + 0.5 * noise.noise(q * 90.0)))
    return p


def beard(src, kind):
    p = Piece(kind)
    if kind == "moustache":
        # under the nose, its ends drooping past the mouth's corners
        path = []
        for k in range(11):
            t = lerp(-1, 1, k / 10)
            x = t * 0.046
            y = 0.124 - 0.05 * t * t
            z = 1.594 - 0.016 * t ** 4
            path.append(Vector((x, y, z)))
        tube_path(p, path, lambda i: 0.004 + 0.005 * math.sin(i / 10 * math.pi) ** 0.6, "Hair", W, n=8, rule=HEADR, flat=0.7)
        return p
    full = kind == "beard_full"
    def keep(c):
        if c.y < -0.015 or c.z > 1.63:
            return False
        if c.z < 1.475:
            return False
        if abs(c.x) > 0.072 and c.z > 1.6:
            return False
        if c.z > 1.568 and abs(c.x) < 0.038 and c.y > 0.08:
            return False  # (the mouth bare)
        if c.z > 1.605 and abs(c.x) < 0.06 and c.y > 0.07:
            return False  # (the cheeks above it)
        if c.z < 1.53 and c.y < 0.03:
            return c.z > 1.505 and full  # (down the throat a little, only a full beard)
        return True
    def off(c):
        chin = smooth(1.6, 1.53, c.z) * smooth(-0.01, 0.08, c.y)
        return (0.008 + (0.03 if full else 0.012) * chin)
    def move(c, q):
        # a full beard hangs: the chin's growth drawn down and forward
        chin = smooth(1.58, 1.52, c.z) * smooth(0.0, 0.09, c.y)
        drop = (0.055 if full else 0.012) * chin
        q = q + Vector((0, 0.012 * chin if full else 0.0, -drop))
        return q + Vector((0, 0, 0.004 * noise.noise(c * 70.0)))
    shell(p, src, keep, off, "Hair", W, solid=0.012, move=move, shade=lambda q: 0.82 + 0.18 * (0.5 + 0.5 * noise.noise(q * 80.0)))
    # (the moustache with it)
    mp = p
    path = []
    for k in range(11):
        t = lerp(-1, 1, k / 10)
        path.append(Vector((t * 0.046, 0.124 - 0.05 * t * t, 1.594 - 0.02 * t ** 4)))
    tube_path(mp, path, lambda i: 0.005 + 0.006 * math.sin(i / 10 * math.pi) ** 0.6, "Hair", W, n=8, rule=HEADR, flat=0.7)
    return p


# --- soldiers' kit -----------------------------------------------------------------------------------

def belt_kit(name="belt_kit", ease=0.044):
    p = Piece(name)
    rx, f, b = belt_ring(p, 0.985, ease, mat="Leather", h=0.05, extra=0.01)
    for sx in (-1, 1):
        for dx in (0.06, 0.13):
            a = math.acos(min(1.0, dx / rx))
            c = (sx * dx, -0.005 + math.sin(a) * f + 0.022, 0.975)
            box(p, c, (0.06, 0.035, 0.07), "Leather", (0.8, 0.8, 0.8), rot=-sx * (math.pi / 2 - a) * 0.8)
            box(p, (c[0], c[1] + 0.002, 1.008), (0.062, 0.038, 0.012), "Leather", (0.65, 0.65, 0.65), rot=-sx * (math.pi / 2 - a) * 0.8)
    # the cross strap over the right shoulder, front and back
    def strap(front):
        ys = 1 if front else -1
        pts = []
        for t in (0.0, 0.25, 0.5, 0.75, 1.0):
            x = lerp(-0.12, 0.13, t)
            z = lerp(1.0, 1.46, t)
            rr = [r for r in TORSO if r[0] <= z][-1]
            d = (rr[2] if front else rr[3]) + ease + 0.008
            y = -0.005 + ys * d * math.sqrt(max(0.05, 1 - (x / (rr[1] + ease + 0.01)) ** 2))
            pts.append(Vector((x, y, z)))
        return pts
    for front in (True, False):
        path = strap(front)
        rings = []
        for i, c in enumerate(path):
            d = path[min(i + 1, 4)] - path[max(i - 1, 0)]
            side = d.cross(Vector((0, 1 if front else -1, 0))).normalized() * 0.022
            out = Vector((0, 0.004 if front else -0.004, 0))
            rings.append([c - side, c + side, c + side + out, c - side + out])
        p.loft(rings, "Leather", W, rule=("pool", ("jacket",), 0.0, None))
    return p


def armband(name="armband", ease=0.034):
    p = Piece(name)
    pts = arm_points(-1)
    c0, c1 = pts[1].lerp(pts[3], 0.42), pts[1].lerp(pts[3], 0.58)
    d = pts[3] - pts[1]
    r = 0.068 + ease + 0.008
    p.loft([disc_frame(c0, d, r - 0.004, 16), disc_frame(c0, d, r, 16), disc_frame(c1, d, r, 16), disc_frame(c1, d, r - 0.004, 16)], "Star", W,
           rule=("pool", ("arm-1",), 0.0, None))
    return p


def neck_rag():
    p = Piece("neck_rag")
    n = 32
    rows = [ell(z, NECK[1] + d, NECK[2] + d, NECK[3] + d, n, cy=NECK_Y, wob=lambda a: 1.0 + 0.06 * math.sin(a * 5)) for z, d in
            ((1.47, 0.05), (1.5, 0.04), (1.535, 0.022))]
    p.loft(rows, "Cloth", W, shade=lambda i, k: 0.8 + 0.2 * (k % 3) / 2, rule=("head_pool", None, 0.0, None))
    knot = Vector((0.03, NECK_Y + NECK[2] + 0.06, 1.475))
    blob(p, knot, (0.03, 0.02, 0.024), "Cloth", W, rule=("head_pool", None, 0.0, knot))
    for dx in (-0.015, 0.02):
        tube_path(p, [knot, knot + Vector((dx, 0.025, -0.06)), knot + Vector((dx * 1.5, 0.03, -0.12))], lambda i: 0.012 + 0.006 * i, "Cloth", (0.85, 0.85, 0.85),
                  n=6, rule=("pool", ("jacket",), 0.0, knot))
    return p


# --- weights -----------------------------------------------------------------------------------------

class Pools:
    """The townsman's own clothes' points and weights, for each piece to take its weights from the
    nearest of them (a coat's from his jacket, trousers from his, boots from his boots)."""

    def __init__(self, objs):
        self.trees = {}
        for key, ob in objs.items():
            me = ob.data
            names = {g.index: g.name for g in ob.vertex_groups}
            pts, ws = [], []
            for v in me.vertices:
                w = {names[g.group]: g.weight for g in v.groups if g.weight > 0.001}
                if w:
                    pts.append(v.co.copy())
                    ws.append(w)
            t = kdtree.KDTree(len(pts))
            for i, c in enumerate(pts):
                t.insert(c, i)
            t.balance()
            self.trees[key] = (t, ws)
            if key == "jacket":
                # each arm alone (its sleeve's points: what's mostly the arm's or the hand's bones)
                for side, pre in ((-1, "Left"), (1, "Right")):
                    keep = [i for i, w in enumerate(ws) if max(w, key=w.get).startswith(pre) and
                            any(b in max(w, key=w.get) for b in ("UpperArm", "LowerArm", "Hand"))]
                    ta = kdtree.KDTree(len(keep))
                    for j, i in enumerate(keep):
                        ta.insert(pts[i], j)
                    ta.balance()
                    self.trees["arm%d" % side] = (ta, [ws[i] for i in keep])

    def near(self, q, keys, k=5):
        found = []
        for key in keys:
            t, ws = self.trees[key]
            for co, i, d in t.find_n(q, k):
                found.append((d, ws[i]))
        found.sort(key=lambda e: e[0])
        acc = {}
        for d, w in found[:k]:
            s = 1.0 / (d + 0.004) ** 2
            for g, x in w.items():
                acc[g] = acc.get(g, 0.0) + x * s
        return acc


def _norm(acc, keep=4):
    top = sorted(acc.items(), key=lambda e: -e[1])[:keep]
    tot = sum(x for _, x in top) or 1.0
    return {g: x / tot for g, x in top if x / tot > 0.01}


def weigh(p, pools):
    out = {}
    for v in p.bm.verts:
        rule = p.rules.get(v, ("pool", ("jacket", "trousers"), 0.0, None))
        kind, keys, hips, at = rule
        q = Vector(at) if at is not None else v.co.copy()
        if kind == "copy":
            acc = dict(keys)
        elif kind == "head":
            acc = {"Head": 1.0}
        elif kind == "head_pool":
            acc = pools.near(q, ("head", "jacket"), k=6)
        elif kind == "skirt":
            # below the seat: as the thighs move, not the shins (a coat's skirt, a skirt), drawn
            # toward the hips the further it hangs
            if q.z < 0.88:
                hang = smooth(0.88, 0.3, q.z)
                qq = Vector((q.x * 0.6, q.y * 0.6, max(q.z, 0.66)))
                acc = pools.near(qq, ("trousers",), k=6)
                hips = max(hips, 0.25 + 0.3 * hang)
            else:
                acc = pools.near(q, keys, k=6)
        elif kind == "shawl":
            qq = Vector((max(-0.13, min(0.13, q.x)), q.y, q.z))
            acc = pools.near(qq, ("jacket", "head"), k=6)
        else:
            acc = pools.near(q, keys, k=5)
        acc = _norm(acc, 6)
        if hips > 0:
            acc = {g: x * (1 - hips) for g, x in acc.items()}
            acc["Hips"] = acc.get("Hips", 0.0) + hips
        out[v] = _norm(acc, 4)
    return out


# --- making them -------------------------------------------------------------------------------------

def _material(name):
    mat = bpy.data.materials.get("kit_" + name)
    if mat:
        return mat
    mat = bpy.data.materials.new("kit_" + name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = {"Leather": 0.55, "Sole": 0.5, "Metal": 0.4, "Button": 0.6}.get(name, 0.92)
    return mat


class Morphs:
    """The head's shape keys (a broader head, an old one, a heavy brow, a long face...), each a
    shift of every point of it: what sits on the head takes the shift of the head's point nearest
    it, so a hat or a beard keeps to the face whatever face it is."""

    def __init__(self, ob):
        me = ob.data
        kb = me.shape_keys.key_blocks
        base = kb[0]
        self.names = [k.name for k in kb[1:]]
        self.delta = {k.name: [k.data[i].co - base.data[i].co for i in range(len(base.data))] for k in kb[1:]}
        self.tree = kdtree.KDTree(len(base.data))
        for i, d in enumerate(base.data):
            self.tree.insert(d.co, i)
        self.tree.balance()

    def apply(self, ob, verts):
        if not verts:
            return
        ob.shape_key_add(name="Basis")
        near = {i: self.tree.find(ob.data.vertices[i].co)[1] for i in verts}
        for name in self.names:
            sk = ob.shape_key_add(name=name, from_mix=False)
            d = self.delta[name]
            if max(d[j].length for j in set(near.values())) < 1e-5:
                ob.shape_key_remove(sk)
                continue
            for i, j in near.items():
                sk.data[i].co = ob.data.vertices[i].co + d[j]


def finish(p, arm, pools, morphs):
    ws = weigh(p, pools)
    on_head = [v for v in p.bm.verts if p.rules.get(v, ("",))[0] in ("head", "copy")]
    me = bpy.data.meshes.new(p.name)
    p.bm.to_mesh(me)
    idx = {v: i for i, v in enumerate(p.bm.verts)}
    head_idx = [idx[v] for v in on_head]
    p.bm.free()
    ob = bpy.data.objects.new(p.name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in p.mats:
        me.materials.append(_material(m))
    groups = {}
    for v, w in ws.items():
        for g, x in w.items():
            if g not in groups:
                groups[g] = ob.vertex_groups.new(name=g)
            groups[g].add([idx[v]], x, "REPLACE")
    ob.parent = arm
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    if me.color_attributes.get("Col"):
        me.color_attributes.active_color = me.color_attributes["Col"]
    morphs.apply(ob, head_idx)
    return ob


NO_AO = ("hair", "beard_full", "beard_short", "moustache", "kerchief", "armband", "armband_wide", "neck_rag")


def bake(objects):
    """The occlusion, each piece against itself (a collar under the chin, a belt over the coat, the
    armpits), and the mud on what's near the ground."""
    old = (B.AO_DISTANCE, B.AO_STRENGTH, B.GRIME_TOP, B.GRIME)
    B.AO_DISTANCE, B.AO_STRENGTH = 0.07, 0.4
    for ob in objects:
        if len(ob.data.polygons) > 0 and ob.name not in NO_AO:
            B._bake_ao([ob], rays=14)
    B.GRIME_TOP, B.GRIME = 0.35, (0.3, 0.25, 0.19)
    for ob in objects:
        B._grime(ob)
    B.AO_DISTANCE, B.AO_STRENGTH, B.GRIME_TOP, B.GRIME = old


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    arm = bpy.data.objects["Survivor"]
    arm.animation_data_clear()
    arm.data.pose_position = "REST"
    obj = lambda n: bpy.data.objects["Survivor_" + n]
    pools = Pools({"jacket": obj("Jacket"), "trousers": obj("Trousers"), "boots": obj("Boots"), "head": obj("Body")})
    src = HeadSrc(obj("Body"))
    pieces = [
        shirt(), shirt("smock", bottom=0.52, flare=(0.05, 0.05, 0.05)), shirt("tunic", bottom=0.72, embroider=False, belt="leather", flare=(0.03, 0.03, 0.035)),
        padded(), shinel(), tulup(), blouse(), skirt(), apron(), shawl(),
        trousers(), trousers("trousers_long", bottom=0.1, blouse=0.0),
        footwear("boots", "boots"), footwear("valenki", "valenki"), footwear("lapti", "lapti"),
        kartuz(), furazhka(), budenovka(), papakha(), ushanka(), kerchief(src), kerchief(src, "shawl_head", big=True),
        hair(src), beard(src, "beard_full"), beard(src, "beard_short"), beard(src, "moustache"),
        belt_kit("belt_kit_thin", 0.02), belt_kit(), belt_kit("belt_kit_wide", 0.058), armband(), armband("armband_wide", 0.044), neck_rag(),
    ]
    morphs = Morphs(obj("Body"))
    made = [finish(p, arm, pools, morphs) for p in pieces]
    bake(made)
    # only the armature and the kit go out
    for ob in list(bpy.data.objects):
        if ob.type == "MESH" and ob not in made:
            bpy.data.objects.remove(ob, do_unlink=True)
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False, export_apply=False, export_yup=True,
                              export_animations=False, export_skins=True, export_morph=True, export_morph_normal=False)
    print("wrote", OUT, len(made), "pieces:", ", ".join(o.name for o in made))
    return made


def render_sheet(made):
    """A sheet of outfits on the townsman (for a look in Blender)."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    cam_d = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_d)
    scene.collection.objects.link(cam)
    cam.location = (0.6, 4.2, 1.2)
    cam.rotation_euler = (Vector((0, 0, 1.0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.rotation_euler = (math.radians(50), 0, math.radians(150))
    scene.collection.objects.link(sun)
    scene.render.resolution_x, scene.render.resolution_y = 800, 900
    scene.render.filepath = OUT.replace("kit.glb", "kit_sheet.png")
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    made = build()
    if "--render" in argv:
        render_sheet(made)


main()
