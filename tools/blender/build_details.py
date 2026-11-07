"""The town's small things, made as the buildings and props are (tools/blender/build_buildings.py):
each object "<stuff>-<tag>-<n>", its colours in its vertices, edges eased, the occlusion baked in.

    blender --background --factory-startup --python tools/blender/build_details.py [-- --only=stake_0,gate_frame]

Blender: +X right, -Y the front (Godot +Z), +Z up; the ground at 0. Whatever's driven into the
ground goes on down below 0 (so on a slope it sinks in rather than stands off it).

  the palisade (scripts/wall.gd):
    stake_0..2    sharpened barked logs, each its own lean, knots and axe facets (0.3 m of it buried)
    rail          a binding rail, 1 m along X (stretched to its span)
    lashing       withy and rope bound round a stake and its rail
    brace         a raking prop, 1 m along Y (stretched)
    berm          the earth banked against the stakes' feet, grassed, a stone or two in it
    walk_board    a plank of the walkway; walk_frame its trestle every few planks, legs into the ground
    ditch         the trench dug for stakes still to raise, the spoil thrown up beside it
    footing       fieldstones along a strengthened wall's foot
  the gate (scripts/gate.gd): gate_frame (posts, lintel, a little roof and its icon), gate_leaf_l /
    gate_leaf_r (pointed planks on battens, a brace, strap hinges: hinged at x 0), gate_bar
  the line (scripts/era_dressing.gd): telegraph_pole (crossarm, braces, glass insulators), semaphore,
    shrine (a roadside icon post)
  the graveyard (scripts/cemetery.gd): grave_mound, cross_a (three-barred), cross_b (roofed),
    headstone, fence_post, fence_rail (1 m along Y), cemetery_gate
  what lies about (scripts/town_litter.gd): woodpile, chopping_block, boards, haystack, breastwork,
    ammo, drum_0..2, tins, trough, washing, signboard

Output: assets/details/<kind>.glb
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from mathutils import Vector  # noqa: E402

import build_buildings as B  # noqa: E402

B.OUT = os.path.join(B.ROOT, "assets", "details")

GREY_BARK = (0.42, 0.36, 0.29) # a pine log's bark a year in the weather
CUT = (0.72, 0.62, 0.47) # an axe cut, gone pale
SPLIT = (0.78, 0.67, 0.5) # fresh split wood
SILVER = (0.49, 0.46, 0.41) # boards gone grey
TARRED = (0.27, 0.22, 0.17) # a creosoted pole
EARTH = (0.31, 0.25, 0.18)
SPOIL = (0.38, 0.31, 0.22)
TURF = (0.27, 0.31, 0.17)
STRAW = (0.68, 0.6, 0.38)
ROPE = (0.6, 0.5, 0.33)
WITHY = (0.42, 0.34, 0.22)
IRON = (0.19, 0.18, 0.17)
RUST = (0.35, 0.22, 0.14)
LINEN = (0.86, 0.84, 0.78)
UNBLEACHED = (0.76, 0.71, 0.6)
FADED_RED = (0.6, 0.22, 0.16)
OLIVE = (0.3, 0.32, 0.21)
OCHRE = (0.72, 0.55, 0.26)
WHITEWASH = (0.84, 0.82, 0.75)
INK = (0.1, 0.09, 0.08)
GLASS = (0.62, 0.72, 0.62) # bottle-green insulator glass
LAMP_GREEN = (0.45, 0.95, 0.5)
LICHEN = (0.62, 0.62, 0.42)


# --- shapes ----------------------------------------------------------------------------------------

def _frame(axis):
    axis = Vector(axis).normalized()
    u = axis.cross(Vector((0, 0, 1)))
    if u.length < 0.1:
        u = axis.cross(Vector((1, 0, 0)))
    u.normalize()
    return axis, u, axis.cross(u).normalized()


def stake(p, a, b, r, rng, point=0.42, segs=8, bark=GREY_BARK, cut=CUT, taper=0.12, stub=True):
    """A barked log from `a` (its foot, sawn) to `b`, hewn above `b` to a point with a few axe
    facets, a little knobbly, a knot or a branch stub on it, a strip of bark gone here and there."""
    a, b = Vector(a), Vector(b)
    axis, u, v = _frame(b - a)
    length = (b - a).length
    bm = p.bm
    n = max(3, int(length / 0.6) + 2)
    wob = [1.0 + rng.uniform(-0.08, 0.08) for _ in range(segs)]
    base = B.jit(bark, 0.1, rng)
    rings = []
    for k in range(n):
        t = k / (n - 1)
        c = a.lerp(b, t) + u * math.sin(t * math.pi) * rng.uniform(-0.015, 0.015)
        rr = r * (1.0 + taper * (0.5 - t))
        rings.append([bm.verts.new(c + (u * math.cos(s / segs * math.tau) + v * math.sin(s / segs * math.tau)) * rr * wob[s] * (1 + rng.uniform(-0.03, 0.03)))
                      for s in range(segs)])
    peeled = rng.randrange(segs)
    for k in range(n - 1):
        for s in range(segs):
            s1 = (s + 1) % segs
            f = bm.faces.new((rings[k][s], rings[k][s1], rings[k + 1][s1], rings[k + 1][s]))
            f.smooth = True
            c = base
            if s % 3 == 0:
                c = (c[0] * 0.8, c[1] * 0.79, c[2] * 0.78) # (a furrow)
            if s == peeled and 0 < k < n - 2:
                c = B.jit((cut[0] * 0.8, cut[1] * 0.78, cut[2] * 0.76), 0.06, rng) # (the bark come away)
            elif rng.random() < 0.04:
                c = (c[0] * 0.8, c[1] * 0.76, c[2] * 0.72) # (a knot)
            p._face_color(f, c)
    f = bm.faces.new(list(reversed(rings[0])))
    p._face_color(f, B.jit(B.END_GRAIN, 0.08, rng))
    if point > 0:
        # the axe's facets: the cut begins a hand below the top, a ragged ring, then the point
        mid_c = b + axis * point * 0.4
        mid = [bm.verts.new(mid_c + (vv.co - b) * rng.uniform(0.5, 0.62) + axis * rng.uniform(-0.04, 0.04)) for vv in rings[-1]]
        apex = bm.verts.new(b + axis * point + u * rng.uniform(-0.04, 0.04) + v * rng.uniform(-0.04, 0.04))
        for s in range(segs):
            s1 = (s + 1) % segs
            shade = 0.88 if s % 2 else 1.0
            c = B.jit((cut[0] * shade, cut[1] * shade, cut[2] * shade), 0.06, rng)
            f = bm.faces.new((rings[-1][s], rings[-1][s1], mid[s1], mid[s]))
            p._face_color(f, c)
            f = bm.faces.new((mid[s], mid[s1], apex))
            p._face_color(f, (c[0] * 0.92, c[1] * 0.9, c[2] * 0.88))
    else:
        f = bm.faces.new(rings[-1])
        p._face_color(f, B.jit(B.END_GRAIN, 0.08, rng))
    if stub and rng.random() < 0.6:
        t = rng.uniform(0.3, 0.8)
        ang = rng.uniform(0, math.tau)
        out = u * math.cos(ang) + v * math.sin(ang)
        q = a.lerp(b, t)
        B.cyl(p, q + out * r * 0.7, q + out * (r + 0.07) + axis * 0.03, r * 0.22, (base[0] * 0.75, base[1] * 0.72, base[2] * 0.7), segs=5, taper=0.3)


def tube(p, pts, r, color, segs=5, closed=False):
    """A round line through `pts` (a rope, a wire, a withy)."""
    pts = [Vector(q) for q in pts]
    bm = p.bm
    rings = []
    n = len(pts)
    prev_u = None
    for i, q in enumerate(pts):
        if closed:
            t = pts[(i + 1) % n] - pts[(i - 1) % n]
        else:
            t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        t.normalize()
        if prev_u is None:
            _, u, _ = _frame(t)
        else:
            u = (prev_u - t * prev_u.dot(t))
            if u.length < 1e-4:
                _, u, _ = _frame(t)
            u.normalize()
        prev_u = u
        v = t.cross(u).normalized()
        rings.append([bm.verts.new(q + (u * math.cos(s / segs * math.tau) + v * math.sin(s / segs * math.tau)) * r) for s in range(segs)])
    faces = []
    for i in range(n if closed else n - 1):
        ra, rb = rings[i], rings[(i + 1) % n]
        for s in range(segs):
            s1 = (s + 1) % segs
            f = bm.faces.new((ra[s], ra[s1], rb[s1], rb[s]))
            f.smooth = True
            faces.append(f)
    if not closed:
        faces.append(bm.faces.new(list(reversed(rings[0]))))
        faces.append(bm.faces.new(rings[-1]))
    p._paint(faces, color)
    return faces


def sag(a, b, drop, n=10):
    """Points along a line hung from `a` to `b`, `drop` down at its middle."""
    a, b = Vector(a), Vector(b)
    return [a.lerp(b, i / n) - Vector((0, 0, drop * 4 * (i / n) * (1 - i / n))) for i in range(n + 1)]


def revolve(p, profile, color, segs=14, rng=None, wobble=0.0, smooth=True, cap=True):
    """A body turned about Z: `profile` [(z, r)] from the bottom up; colour a fixed one or f(z)."""
    bm = p.bm
    rings = []
    for z, r in profile:
        rings.append([bm.verts.new(Vector((math.cos(s / segs * math.tau) * r * (1 + (rng.uniform(-wobble, wobble) if rng else 0)),
                                           math.sin(s / segs * math.tau) * r * (1 + (rng.uniform(-wobble, wobble) if rng else 0)), z))) for s in range(segs)])
    faces = []
    for ra, rb in zip(rings, rings[1:]):
        for s in range(segs):
            s1 = (s + 1) % segs
            f = bm.faces.new((ra[s], ra[s1], rb[s1], rb[s]))
            f.smooth = smooth
            faces.append(f)
    if cap:
        if profile[0][1] > 1e-3:
            faces.append(bm.faces.new(list(reversed(rings[0]))))
        if profile[-1][1] > 1e-3:
            faces.append(bm.faces.new(rings[-1]))
    for f in faces:
        f.normal_update()
        c = color(f.calc_center_median().z) if callable(color) else color
        p._face_color(f, c)
    return faces


def mound(p, c, size, color, rng, top=None, subdiv=2):
    """A heap of earth (a lumpy flattened ball sunk to its middle), smooth, its top going over in
    patches to `top` (grass come back on it)."""
    before = set(p.bm.faces)
    p.stone(c, size, color=color, rng=rng, subdiv=subdiv)
    new = [f for f in p.bm.faces if f not in before]
    for f in new:
        f.smooth = True
        f.normal_update()
    for f in new:
        for v in f.verts:
            v.normal_update()
    seed = rng.uniform(0, 100)
    for f in new:
        for loop in f.loops:
            v = loop.vert
            n = 0.5 + 0.5 * math.sin(v.co.x * 5.3 + seed) * math.sin(v.co.y * 4.1 + seed * 1.3)
            t = 0.0
            if top is not None:
                t = max(0.0, min(1.0, (v.normal.z - 0.35) * 2.5)) * (0.45 + 0.55 * n)
            k = 0.92 + 0.16 * n
            tc = top if top is not None else color
            col = tuple((color[i] * (1 - t) + tc[i] * t) * k for i in range(3))
            loop[p.col] = (col[0], col[1], col[2], 1.0)


def tufts(p, c, rx, ry, n, rng, z=0.0, color=B.TUFT):
    """Grass come up in tufts over an oval."""
    for _ in range(n):
        a = rng.uniform(0, math.tau)
        d = math.sqrt(rng.random())
        q = (c[0] + math.cos(a) * rx * d, c[1] + math.sin(a) * ry * d, z)
        g = B.jit(color, 0.12, rng)
        if rng.random() < 0.3:
            g = (g[0] * 1.3, g[1] * 1.12, g[2] * 0.8) # (gone to seed)
        p.stone(q, (rng.uniform(0.12, 0.26), rng.uniform(0.12, 0.24), rng.uniform(0.1, 0.22)), color=g, rng=rng)


def plank(p, c, size, color, rng, rot=0.0):
    p.box(c, size, B.jit(color, 0.08, rng), rot_z=rot)


def billet(p, c, length, r, rot, rng, axis="y"):
    """A split log: a quarter round, the bark on its curve, its split faces pale, its ends sawn."""
    bm = p.bm
    a0 = rot
    arc = [a0 + i / 4 * (math.pi * 0.5) for i in range(5)]
    outline = [(0.0, 0.0)] + [(math.cos(t) * r, math.sin(t) * r) for t in arc]
    c = Vector(c)

    def at(u, v, w):
        return c + (Vector((w, u, v)) if axis == "x" else Vector((u, w, v)))
    lo = [bm.verts.new(at(u - r * 0.3 * math.cos(a0 + 0.78), v - r * 0.3 * math.sin(a0 + 0.78), -length * 0.5)) for u, v in outline]
    hi = [bm.verts.new(at(u - r * 0.3 * math.cos(a0 + 0.78), v - r * 0.3 * math.sin(a0 + 0.78), length * 0.5 + rng.uniform(-0.03, 0.03))) for u, v in outline]
    bark = B.jit(B.BARK, 0.1, rng)
    split = B.jit(SPLIT, 0.07, rng)
    end = B.jit(B.END_GRAIN, 0.06, rng)
    f = bm.faces.new(list(reversed(lo)))
    p._face_color(f, end)
    f = bm.faces.new(hi)
    p._face_color(f, end)
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        f = bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
        p._face_color(f, bark if (i > 0 and j > 0) else split)


def stones(p, c, r, n, rng, size=0.3, color=B.STONE):
    for _ in range(n):
        a = rng.uniform(0, math.tau)
        d = r * math.sqrt(rng.random())
        s = size * rng.uniform(0.6, 1.2)
        p.stone((c[0] + math.cos(a) * d, c[1] + math.sin(a) * d, c[2] + s * 0.12), (s, s * 0.8, s * 0.6), color=color, rng=rng)


def orthodox_cross(p, c, h, rng, color=SILVER, bar=0.72, thick=0.09, sink=0.5):
    """The three-barred cross: the upright, the short bar above the long one, and the foot-bar
    slanting up to the viewer's left (+X, seen from +Y). Faces +Y."""
    x, y, z = c
    col = B.jit(color, 0.06, rng)
    p.box((x, y, z + (h - sink) * 0.5), (thick, thick, h + sink), col)
    p.box((x, y, z + h * 0.7), (bar, thick * 0.9, thick * 0.9), B.jit(color, 0.06, rng))
    p.box((x, y, z + h * 0.85), (bar * 0.5, thick * 0.8, thick * 0.8), B.jit(color, 0.06, rng))
    p.obox((x, y, z + h * 0.28), (math.cos(0.38), 0, math.sin(0.38)), (0, 1, 0), (-math.sin(0.38), 0, math.cos(0.38)), (bar * 0.6, thick * 0.8, thick * 0.8), B.jit(color, 0.06, rng))


# --- the palisade ----------------------------------------------------------------------------------

def _stake(i):
    k = B.Kit("stake_%d" % i)
    rng = k.rng
    p = k.piece("log")
    lean = Vector((rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), 0))
    stake(p, (0, 0, 0), Vector((0, 0, 2.45)) + lean, 0.145 + 0.01 * i, rng, point=0.38 + 0.05 * i, segs=8)
    k.add(p)
    k.finish()


def rail():
    k = B.Kit("rail")
    p = k.piece("log")
    p.log((-0.5, 0, 0), (0.5, 0, 0), 0.075, color=GREY_BARK, segs=7, rng=k.rng, taper=0.0, bow=0.0, jitter=0.06)
    k.add(p)
    k.finish()


def lashing():
    """Withies twisted round a stake and the rail across it, a rope's end hanging."""
    k = B.Kit("lashing")
    rng = k.rng
    p = k.piece("wood")
    for i in range(4):
        z = -0.06 + i * 0.04
        tilt = (i - 1.5) * 0.04
        pts = []
        for s in range(18):
            t = s / 18 * math.tau
            pts.append((math.cos(t) * 0.27, math.sin(t) * 0.2, z + math.sin(t) * tilt))
        tube(p, pts, 0.014, B.jit(WITHY if i % 2 else ROPE, 0.08, rng), segs=4, closed=True)
    tube(p, [(0.27, 0.0, 0.0), (0.3, -0.02, -0.12), (0.29, -0.03, -0.24)], 0.012, ROPE, segs=4)
    k.add(p)
    k.finish()


def brace():
    k = B.Kit("brace")
    p = k.piece("log")
    p.log((0, -0.56, 0), (0, 0.5, 0), 0.08, color=GREY_BARK, segs=7, rng=k.rng, taper=0.1, bow=0.01)
    k.add(p)
    k.finish()


def berm():
    """The earth thrown up against the stakes' feet: long, low, the grass come back on it."""
    k = B.Kit("berm")
    rng = k.rng
    p = k.piece("earth")
    for i in range(3):
        y = -0.8 + i * 0.8
        mound(p, (rng.uniform(-0.08, 0.08), y, -0.06), (1.2, 1.3, 0.42), SPOIL, rng, top=TURF)
    stones(p, (0, 0, 0.02), 0.6, 3, rng, size=0.22)
    k.add(p)
    p = k.piece("earth", "grass")
    tufts(p, (0, 0), 0.55, 1.1, 9, rng, z=0.08)
    k.add(p)
    k.finish()


def walk_board():
    k = B.Kit("walk_board")
    p = k.piece("plank")
    p.box((0, 0, 0), (0.9, 0.27, 0.055), B.jit(SILVER, 0.05, k.rng))
    k.add(p)
    k.finish()


def walk_frame():
    """The walkway's trestle: two legs into the ground, a bearer under the planks, a brace."""
    k = B.Kit("walk_frame")
    rng = k.rng
    p = k.piece("log")
    for x in (-0.36, 0.36):
        p.log((x, 0, -2.4), (x, 0, -0.06), 0.065, color=GREY_BARK, segs=7, rng=rng, taper=0.05)
    p.log((-0.5, 0, -0.1), (0.5, 0, -0.1), 0.06, color=GREY_BARK, segs=7, rng=rng, taper=0.0)
    p.log((-0.36, 0.02, -1.25), (0.36, 0.02, -0.2), 0.04, color=GREY_BARK, segs=6, rng=rng, taper=0.0)
    k.add(p)
    k.finish()


def ditch():
    """A trench dug for stakes still to be raised, the spoil thrown up along one side."""
    k = B.Kit("ditch")
    rng = k.rng
    p = k.piece("earth")
    p.box((0, 0, 0.005), (0.42, 0.62, 0.02), (0.18, 0.13, 0.09))
    for y in (-0.2, 0.15):
        mound(p, (0.42 + rng.uniform(-0.04, 0.04), y, -0.05), (0.42, 0.55, 0.26), SPOIL, rng, subdiv=1)
    k.add(p)
    k.finish()


def footing():
    k = B.Kit("footing")
    rng = k.rng
    p = k.piece("stone")
    for i in range(3):
        p.stone((-0.28 + i * 0.28 + rng.uniform(-0.04, 0.04), rng.uniform(-0.06, 0.06), 0.06), (rng.uniform(0.3, 0.42), rng.uniform(0.3, 0.4), rng.uniform(0.22, 0.3)), rng=rng)
    k.add(p)
    k.finish()


# --- the gate --------------------------------------------------------------------------------------

def gate_frame():
    """Two stout posts and a lintel log over them, a little plank roof on it with an icon under it
    on the outside (Godot -Z: Blender +Y), iron pins for the hinges."""
    k = B.Kit("gate_frame")
    rng = k.rng
    for sx in (-1, 1):
        p = k.piece("log")
        stake(p, (sx * 1.72, 0, -0.9), (sx * 1.72, 0, 3.95), 0.22, rng, point=0.4, segs=9, stub=False)
        k.add(p)
    p = k.piece("log")
    p.log((-2.25, 0, 3.5), (2.25, 0, 3.5), 0.17, color=GREY_BARK, rng=rng, taper=0.03)
    k.add(p)
    # the little roof: two slopes of boards on short rafters
    p = k.piece("plank")
    for s in (-1, 1):
        ang = math.atan2(0.5, 0.6)
        across = Vector((1, 0, 0))
        down = Vector((0, s * math.cos(ang), -math.sin(ang)))
        nrm = Vector((0, s * math.sin(ang), math.cos(ang)))
        apex = Vector((0, 0, 4.22))
        x = -2.45
        while x < 2.45:
            w = min(rng.uniform(0.2, 0.3), 2.45 - x)
            p.obox(apex + down * 0.4 + across * (x + w * 0.5) + nrm * 0.02, across, down, nrm, (w - 0.01, 0.82, 0.035), B.shingle_colour(k, SILVER, x, 0.5, 0, 0.5))
            x += w
    p.box((0, 0, 4.24), (5.0, 0.08, 0.08), B.jit(B.DARK, 0.05, rng))
    for x in (-1.6, 0.0, 1.6):
        for s in (-1, 1):
            p.obox((x, s * 0.25, 3.92), (1, 0, 0), (0, s * 0.77, -0.64), (0, s * 0.64, 0.77), (0.06, 0.62, 0.06), B.jit(B.DARK, 0.05, rng))
    k.add(p)
    # the icon in its case over the gateway, a towel hung from it
    p = k.piece("dark", "icon")
    p.box((0, 0.24, 3.5), (0.42, 0.06, 0.5), (0.3, 0.22, 0.14))
    p.box((0, 0.275, 3.5), (0.36, 0.02, 0.44), OCHRE)
    p.box((0, 0.29, 3.48), (0.26, 0.02, 0.34), (0.22, 0.12, 0.08))
    p.box((0, 0.3, 3.56), (0.1, 0.02, 0.1), (0.78, 0.62, 0.32))
    p.box((0, 0.3, 3.42), (0.16, 0.02, 0.16), (0.48, 0.14, 0.1))
    k.add(p)
    p = k.piece("cloth", "towel")
    for sx in (-1, 1):
        p.obox((sx * 0.24, 0.29, 3.12), (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.08, 0.01, 0.6), LINEN)
        p.box((sx * 0.24, 0.296, 2.86), (0.081, 0.01, 0.06), FADED_RED)
    k.add(p)
    p = k.piece("dark", "iron")
    for sx in (-1, 1):
        for z in (0.55, 2.2):
            p.box((sx * 1.52, 0, z), (0.12, 0.05, 0.05), IRON)
    k.add(p)
    k.finish()


def _gate_leaf(name, d):
    """A leaf hung at x 0, reaching `d` (+1/-1) along X: pointed planks, two battens and a brace on
    the town's side (Blender -Y), long iron straps on the other."""
    k = B.Kit(name)
    rng = k.rng
    p = k.piece("plank")
    for i in range(5):
        x0 = d * (0.01 + i * 0.29)
        x1 = d * (0.01 + i * 0.29 + 0.28)
        top = 2.48 + (i % 2) * 0.1 + rng.uniform(-0.03, 0.03)
        lo, hi = min(x0, x1), max(x0, x1)
        B.prism(p, [(lo, 0.0), (hi, 0.0), (hi, top), ((lo + hi) * 0.5, top + 0.16), (lo, top)], -0.035, 0.035, B.jit(SILVER, 0.08, rng), axis="y")
    k.add(p)
    p = k.piece("dark")
    for z in (0.45, 2.1):
        p.box((d * 0.73, -0.065, z), (1.42, 0.06, 0.15), B.jit(B.DARK, 0.06, rng))
    ang = math.atan2(1.5, 1.2)
    a = Vector((d * math.cos(ang), 0, math.sin(ang)))
    p.obox((d * 0.73, -0.065, 1.27), a, (0, 1, 0), a.cross(Vector((0, 1, 0))), (1.85, 0.055, 0.12), B.jit(B.DARK, 0.06, rng))
    k.add(p)
    p = k.piece("dark", "iron")
    for z in (0.45, 2.1):
        p.box((d * 0.5, 0.045, z), (1.0, 0.012, 0.06), IRON)
        p.box((d * 0.95, 0.045, z), (0.08, 0.014, 0.1), IRON)
        B.cyl(p, (0, 0, z - 0.06), (0, 0, z + 0.06), 0.03, IRON, segs=6)
    p.box((d * 1.38, -0.11, 1.4), (0.05, 0.05, 0.22), IRON) # (the ring to pull it by)
    k.add(p)
    k.finish()


def gate_bar():
    k = B.Kit("gate_bar")
    rng = k.rng
    p = k.piece("log")
    p.box((0, 0, 0), (3.5, 0.17, 0.19), B.jit(B.DARK, 0.06, rng))
    k.add(p)
    p = k.piece("dark", "iron")
    for sx in (-0.75, 0.75):
        p.box((sx, 0.0, -0.13), (0.09, 0.26, 0.03), IRON)
        for s in (-1, 1):
            p.box((sx, s * 0.12, -0.0), (0.09, 0.03, 0.29), IRON)
    k.add(p)
    k.finish()


# --- along the line --------------------------------------------------------------------------------

def telegraph_pole():
    """A tarred pole, its crossarm across the line, braced, two glass insulators on their pins,
    a cap against the rain; 0.7 m of it in the ground."""
    k = B.Kit("telegraph_pole")
    rng = k.rng
    p = k.piece("wood")
    p.log((0, 0, -0.7), (0, 0, 6.28), 0.11, color=TARRED, end=(0.42, 0.34, 0.24), segs=9, rng=rng, taper=0.25, jitter=0.03, bow=0.004)
    p.box((0, 0, 6.32), (0.2, 0.2, 0.05), B.jit(B.DARK, 0.05, rng))
    p.box((0, 0, 5.85), (1.5, 0.1, 0.1), B.jit(B.DARK, 0.05, rng))
    for x in (-0.6, 0.6):
        B.cyl(p, (x, 0, 5.9), (x, 0, 5.97), 0.018, B.DARK, segs=6)
    k.add(p)
    p = k.piece("dark", "iron")
    for s in (-1, 1):
        p.obox((s * 0.18, 0.06, 5.62), (s * 0.6, 0, 0.8), (0, 1, 0), (s * -0.8, 0, 0.6), (0.6, 0.01, 0.035), IRON)
    p.box((0, -0.11, 2.4), (0.12, 0.02, 0.08), (0.75, 0.72, 0.64)) # (its number plate)
    k.add(p)
    p = k.piece("glass")
    for x in (-0.6, 0.6):
        revolve(p, [(5.95, 0.026), (5.96, 0.042), (6.0, 0.036), (6.02, 0.03), (6.05, 0.024), (6.06, 0.0)], GLASS, segs=8)
    k.add(p)
    k.finish()


def semaphore():
    """The home signal: a tall squared post with a finial, the arm (red, a white band) lowered
    toward -X on the front (Blender -Y), its spectacle of red and green glass, the lamp under it,
    a ladder up the back and the lever at its foot."""
    k = B.Kit("semaphore")
    rng = k.rng
    p = k.piece("wood")
    p.obox((0, 0, 3.1), (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.22, 0.22, 7.8), B.jit((0.4, 0.38, 0.34), 0.04, rng))
    revolve(p, [(7.0, 0.14), (7.08, 0.14), (7.14, 0.07), (7.3, 0.08), (7.45, 0.0)], (0.22, 0.2, 0.19), segs=8, smooth=False)
    for r in range(11):
        p.box((0, 0.2, 0.5 + r * 0.5), (0.34, 0.03, 0.03), B.PLANK)
    for s in (-0.17, 0.17):
        p.box((s, 0.2, 2.9), (0.03, 0.03, 5.6), B.PLANK)
    p.box((0, 0.0, 5.3), (0.7, 0.6, 0.05), B.jit(SILVER, 0.05, rng)) # (the lamp man's step)
    k.add(p)
    arm = k.piece("wood", "arm")
    ang = -0.6
    ax = Vector((-math.cos(ang), 0, math.sin(ang)))
    piv = Vector((0, -0.16, 6.4))
    arm.obox(piv + ax * 0.85, ax, (0, 1, 0), ax.cross(Vector((0, 1, 0))), (1.5, 0.04, 0.26), (0.6, 0.12, 0.08))
    arm.obox(piv + ax * 1.25 + Vector((0, -0.005, 0)), ax, (0, 1, 0), ax.cross(Vector((0, 1, 0))), (0.18, 0.04, 0.27), (0.86, 0.84, 0.78))
    k.add(arm)
    sp = k.piece("dark", "iron")
    sp.obox(piv - ax * 0.25, ax, (0, 1, 0), ax.cross(Vector((0, 1, 0))), (0.6, 0.03, 0.06), IRON)
    B.cyl(sp, piv + Vector((0, -0.02, 0)), piv + Vector((0, 0.12, 0)), 0.05, IRON, segs=8)
    sp.box((0, -0.16, 5.62), (0.32, 0.32, 0.42), (0.16, 0.15, 0.14))
    revolve(sp, [(5.83, 0.12), (5.86, 0.12), (5.98, 0.0)], (0.16, 0.15, 0.14), segs=8)
    B.cyl(sp, (0.0, 0.1, 0.3), (0.0, -0.3, 1.1), 0.025, IRON, segs=6)
    sp.box((0, -0.35, 0.15), (0.3, 0.2, 0.3), (0.2, 0.2, 0.19))
    k.add(sp)
    for glass, at in (((0.7, 0.12, 0.08), 0.15), ((0.3, 0.62, 0.32), -0.15)):
        g = k.piece("glass")
        B.cyl(g, piv - ax * 0.45 + Vector((0, -0.01, at)), piv - ax * 0.45 + Vector((0, -0.04, at)), 0.07, glass, segs=8)
        k.add(g)
    lamp = k.piece("lamp")
    B.cyl(lamp, (0, -0.32, 5.64), (0, -0.335, 5.64), 0.08, LAMP_GREEN, segs=10)
    k.add(lamp)
    k.finish()


def shrine():
    """A roadside icon post: a stout post, a little roofed case with the icon behind its glass, a
    towel hung from it, a small three-barred cross on the ridge, stones at its foot. Faces -Y."""
    k = B.Kit("shrine")
    rng = k.rng
    p = k.piece("wood")
    p.obox((0, 0, 0.65), (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.18, 0.18, 2.5), B.jit(SILVER, 0.04, rng))
    p.box((0, 0, 1.5), (0.6, 0.4, 0.05), B.jit(B.DARK, 0.04, rng))
    for sx in (-1, 1):
        p.box((sx * 0.26, 0, 1.8), (0.05, 0.34, 0.6), B.jit(SILVER, 0.05, rng))
    p.box((0, 0.17, 1.8), (0.5, 0.04, 0.6), B.jit(SILVER, 0.05, rng))
    p.obox((0, 0.14, 1.28), (1, 0, 0), (0, 0.6, 0.8), (0, -0.8, 0.6), (0.06, 0.5, 0.06), B.jit(B.DARK, 0.05, rng))
    k.add(p)
    roof = k.piece("plank")
    for s in (-1, 1):
        ang = 0.75
        d = Vector((s * math.cos(ang), 0, -math.sin(ang)))
        n = Vector((s * math.sin(ang), 0, math.cos(ang)))
        roof.obox(Vector((0, 0, 2.37)) + d * 0.22 + n * 0.02, (0, 1, 0), d, n, (0.56, 0.48, 0.035), B.jit(SILVER, 0.06, rng))
    k.add(roof)
    cr = k.piece("wood")
    orthodox_cross(cr, (0, 0, 2.4), 0.5, rng, color=SILVER, bar=0.24, thick=0.035, sink=0.05)
    k.add(cr)
    icon = k.piece("dark", "icon")
    icon.box((0, -0.12, 1.8), (0.42, 0.02, 0.52), OCHRE)
    icon.box((0, -0.135, 1.78), (0.32, 0.02, 0.42), (0.24, 0.13, 0.08))
    icon.box((0, -0.15, 1.88), (0.12, 0.02, 0.12), (0.8, 0.64, 0.34))
    icon.box((0, -0.15, 1.72), (0.2, 0.02, 0.22), (0.5, 0.15, 0.1))
    k.add(icon)
    cl = k.piece("cloth", "towel")
    for sx in (-1, 1):
        cl.box((sx * 0.22, -0.2, 1.22), (0.1, 0.012, 0.5), LINEN)
        cl.box((sx * 0.22, -0.207, 1.0), (0.101, 0.012, 0.05), FADED_RED)
        cl.box((sx * 0.22, -0.207, 1.08), (0.101, 0.012, 0.025), FADED_RED)
    k.add(cl)
    st = k.piece("stone")
    stones(st, (0, 0, 0), 0.45, 7, rng, size=0.26)
    k.add(st)
    k.finish()


# --- the graveyard ---------------------------------------------------------------------------------

def grave_mound():
    k = B.Kit("grave_mound")
    rng = k.rng
    p = k.piece("earth")
    mound(p, (0, 0, -0.08), (0.95, 2.0, 0.5), EARTH, rng, top=(0.3, 0.24, 0.17))
    k.add(p)
    p = k.piece("earth", "grass")
    for s in (-1, 1):
        for i in range(5):
            p.stone((s * 0.48 + rng.uniform(-0.05, 0.05), -0.8 + i * 0.4, -0.02), (0.18, 0.3, 0.12), color=B.jit(TURF, 0.1, rng), rng=rng)
    k.add(p)
    k.finish()


def _cross(name, roofed):
    k = B.Kit(name)
    rng = k.rng
    p = k.piece("wood")
    orthodox_cross(p, (0, 0, 0), 1.6, rng, color=SILVER)
    p.box((0, 0.06, 0.82), (0.3, 0.025, 0.2), B.jit((0.66, 0.62, 0.55), 0.05, rng)) # (the board the name's on)
    if roofed:
        for s in (-1, 1):
            ang = 0.7
            d = Vector((0, s * math.cos(ang), -math.sin(ang)))
            n = Vector((0, s * math.sin(ang), math.cos(ang)))
            p.obox(Vector((0, 0, 1.68)) + d * 0.13 + n * 0.015, (1, 0, 0), d, n, (0.48, 0.26, 0.025), B.jit(SILVER, 0.06, rng))
    k.add(p)
    k.finish()


def headstone():
    k = B.Kit("headstone")
    rng = k.rng
    p = k.piece("stone")
    p.obox((0, 0, 0.22), (1, 0, 0), (0, math.cos(0.08), -math.sin(0.08)), (0, math.sin(0.08), math.cos(0.08)), (0.5, 0.16, 0.9), B.jit((0.5, 0.49, 0.46), 0.05, rng))
    p.stone((0, 0, 0.62), (0.52, 0.17, 0.2), color=(0.5, 0.49, 0.46), rng=rng)
    for z, w in ((0.48, 0.05), (0.5, 0.24)):
        p.box((0, 0.1, z), (w, 0.01, 0.05 if w > 0.1 else 0.3), (0.3, 0.29, 0.27))
    for _ in range(5):
        p.box((rng.uniform(-0.2, 0.2), 0.09, rng.uniform(0.1, 0.6)), (0.07, 0.01, 0.05), LICHEN)
    k.add(p)
    k.finish()


def fence_post():
    k = B.Kit("fence_post")
    p = k.piece("wood")
    p.box((0, 0, 0.27), (0.11, 0.11, 1.55), B.jit(SILVER, 0.05, k.rng))
    B.prism(p, [(-0.055, 1.045), (0.055, 1.045), (0.0, 1.13)], -0.055, 0.055, B.jit(SILVER, 0.05, k.rng), axis="y")
    k.add(p)
    k.finish()


def fence_rail():
    k = B.Kit("fence_rail")
    p = k.piece("wood")
    B.prism(p, [(-0.045, -0.025), (0.045, -0.025), (0.04, 0.0), (0.02, 0.02), (-0.02, 0.025), (-0.04, 0.005)], -0.53, 0.53, B.jit(SILVER, 0.05, k.rng), axis="y")
    k.add(p)
    k.finish()


def cemetery_gate():
    """The way in: two posts, a lintel, a little gable roof over it and a cross on that (3.6 m)."""
    k = B.Kit("cemetery_gate")
    rng = k.rng
    p = k.piece("wood")
    for sx in (-1, 1):
        p.box((sx * 1.8, 0, 0.8), (0.15, 0.15, 2.6), B.jit(SILVER, 0.05, rng))
    p.box((0, 0, 2.15), (3.9, 0.14, 0.16), B.jit(SILVER, 0.05, rng))
    for sx in (-1, 1):
        p.obox((sx * 1.55, 0, 1.85), Vector((sx * 0.7, 0, 0.7)).normalized(), (0, 1, 0), Vector((sx * -0.7, 0, 0.7)).normalized(), (0.6, 0.08, 0.08), B.jit(SILVER, 0.05, rng))
    k.add(p)
    roof = k.piece("plank")
    for s in (-1, 1):
        ang = 0.6
        d = Vector((0, s * math.cos(ang), -math.sin(ang)))
        n = Vector((0, s * math.sin(ang), math.cos(ang)))
        x = -2.15
        while x < 2.15:
            w = min(rng.uniform(0.18, 0.28), 2.15 - x)
            roof.obox(Vector((x + w * 0.5, 0, 2.55)) + d * 0.28 + n * 0.02, (1, 0, 0), d, n, (w - 0.01, 0.58, 0.03), B.shingle_colour(k, SILVER, x, 0.5, 0, 0.5))
            x += w
    k.add(roof)
    cr = k.piece("wood")
    orthodox_cross(cr, (0, 0, 2.55), 0.8, rng, color=SILVER, bar=0.4, thick=0.05, sink=0.05)
    k.add(cr)
    k.finish()


# --- what lies about -------------------------------------------------------------------------------

def woodpile():
    k = B.Kit("woodpile")
    rng = k.rng
    p = k.piece("wood")
    for row in range(5):
        n = 7 if row % 2 == 0 else 6
        for i in range(n):
            x = (i - (n - 1) * 0.5) * 0.165
            billet(p, (x + rng.uniform(-0.02, 0.02), rng.uniform(-0.03, 0.03), 0.08 + row * 0.145), 0.5, 0.11, rng.uniform(0, math.tau), rng)
    k.add(p)
    s = k.piece("log")
    for sx in (-1, 1):
        stake(s, (sx * 0.64, 0, -0.3), (sx * 0.62, 0.02, 0.85), 0.04, rng, point=0.1, segs=6, stub=False)
    for x in (-0.4, 0.4):
        s.log((x, -0.35, 0.03), (x, 0.35, 0.03), 0.045, rng=rng, segs=6)
    k.add(s)
    k.finish()


def chopping_block():
    k = B.Kit("chopping_block")
    rng = k.rng
    p = k.piece("log")
    p.log((0, 0, -0.05), (0, 0, 0.5), 0.27, color=GREY_BARK, rng=rng, taper=0.0, jitter=0.06)
    k.add(p)
    ax = k.piece("wood", "axe")
    d = Vector((0.25, 0, 0.97)).normalized()
    ax.obox(Vector((0.04, 0, 0.5)) + d * 0.36, d, (0, 1, 0), d.cross(Vector((0, 1, 0))), (0.04, 0.03, 0.72), B.jit(SPLIT, 0.05, rng))
    ax.obox((0.03, 0, 0.53), (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.2, 0.025, 0.1), IRON)
    k.add(ax)
    ch = k.piece("wood", "chips")
    for _ in range(14):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0.35, 0.85)
        ch.box((math.cos(a) * r, math.sin(a) * r, 0.01), (rng.uniform(0.06, 0.13), rng.uniform(0.03, 0.06), 0.02), B.jit(SPLIT, 0.1, rng), rot_z=rng.uniform(0, math.pi))
    k.add(ch)
    k.finish()


def boards():
    k = B.Kit("boards")
    rng = k.rng
    p = k.piece("log")
    for s in (-0.8, 0.8):
        p.log((s, -0.5, 0.06), (s, 0.5, 0.06), 0.07, rng=rng, segs=7)
    k.add(p)
    b = k.piece("plank")
    for row in range(5):
        for i in range(3):
            rot = rng.uniform(-0.03, 0.03)
            col = SILVER if row == 4 else B.PLANK
            b.box((rng.uniform(-0.05, 0.05), -0.3 + i * 0.3 + rng.uniform(-0.02, 0.02), 0.155 + row * 0.052), (2.2, 0.28, 0.045), B.jit(col, 0.08, rng), rot_z=rot)
    k.add(b)
    k.finish()


def haystack():
    """A stack of hay round its pole (a stog), raked into a rounded cone, its top weathered grey."""
    k = B.Kit("haystack")
    rng = k.rng
    p = k.piece("thatch")

    def col(z):
        t = min(max(z / 2.0, 0.0), 1.0)
        c = B.jit(STRAW, 0.08, rng)
        return (c[0] * (1 - 0.3 * t), c[1] * (1 - 0.26 * t), c[2] * (1 - 0.15 * t))
    revolve(p, [(-0.05, 0.7), (0.3, 0.92), (0.7, 0.98), (1.1, 0.88), (1.5, 0.62), (1.85, 0.32), (2.05, 0.1), (2.1, 0.0)], col, segs=16, rng=rng, wobble=0.06)
    for _ in range(6):
        a = rng.uniform(0, math.tau)
        p.stone((math.cos(a) * 0.95, math.sin(a) * 0.95, 0.05), (0.4, 0.3, 0.2), color=B.jit(STRAW, 0.1, rng), rng=rng)
    k.add(p)
    w = k.piece("wood")
    B.cyl(w, (0, 0, 1.6), (0.02, 0.01, 2.65), 0.04, GREY_BARK, segs=6)
    for s in (-1, 1): # (the withies over its top, weighted)
        tube(w, sag((s * 0.5, -0.5, 1.6), (s * -0.5, 0.5, 1.6), -0.45, 6), 0.02, WITHY, segs=4)
    k.add(w)
    k.finish()


def breastwork():
    k = B.Kit("breastwork")
    rng = k.rng
    p = k.piece("sand", "bags")
    for row in range(3):
        n = 6 - row
        for i in range(n):
            a = (i - (n - 1) * 0.5) * 0.27
            B.sandbag(p, math.sin(a) * 2.2, -(math.cos(a) * 2.2 - 2.2) + row * 0.03, 0.1 + row * 0.18, a, rng, tilt=rng.uniform(-0.06, 0.06))
    k.add(p)
    s = k.piece("sand")
    mound(s, (0, -0.35, -0.08), (2.0, 0.6, 0.3), SPOIL, rng, subdiv=1)
    k.add(s)
    k.finish()


def ammo():
    k = B.Kit("ammo")
    rng = k.rng
    p = k.piece("wood")
    for i in range(4):
        x = (i % 2) * 0.62 - 0.31
        z = 0.16 + (i // 2) * 0.32
        rot = rng.uniform(-0.1, 0.1)
        ca, sa = math.cos(rot), math.sin(rot)

        def at(dx, dy, dz):
            return (x + dx * ca - dy * sa, dx * sa + dy * ca, z + dz)
        col = B.jit(OLIVE, 0.06, rng)
        p.box(at(0, 0, 0), (0.6, 0.36, 0.3), col, rot_z=rot)
        p.box(at(0, 0, 0.13), (0.62, 0.38, 0.04), (col[0] * 0.75, col[1] * 0.75, col[2] * 0.75), rot_z=rot)
        for s in (-1, 1):
            p.box(at(s * 0.305, 0, 0.02), (0.02, 0.12, 0.04), ROPE, rot_z=rot)
        for j in range(4): # (the stencil)
            p.box(at(-0.18 + j * 0.08, -0.182, -0.02), (0.05, 0.005, 0.07), (0.78, 0.74, 0.62), rot_z=rot)
    k.add(p)
    k.finish()


def _drum(i, paint):
    k = B.Kit("drum_%d" % i)
    rng = k.rng
    p = k.piece("dark")
    r, h = 0.29, 0.88

    def col(z):
        c = B.jit(paint, 0.05, rng)
        if rng.random() < 0.18:
            c = B.jit(RUST, 0.1, rng)
        return c
    revolve(p, [(0.0, r - 0.01), (0.02, r), (h - 0.02, r), (h, r - 0.01)], col, segs=18, smooth=True)
    for z in (0.01, h * 0.33, h * 0.67, h - 0.01):
        B._ring(p, Vector((0, 0, z)), Vector((0, 0, 1)), r + 0.006, 0.012, 0.025, (paint[0] * 0.8, paint[1] * 0.8, paint[2] * 0.8), n=18)
    B.cyl(p, (0.15, 0.05, h), (0.15, 0.05, h + 0.02), 0.03, IRON, segs=6)
    k.add(p)
    k.finish()


def tins():
    k = B.Kit("tins")
    rng = k.rng
    p = k.piece("dark")
    for i in range(3):
        c = B.jit((0.55, 0.5, 0.36), 0.06, rng)
        if i < 2:
            x = i * 0.3 - 0.3
            p.box((x, 0, 0.18), (0.24, 0.24, 0.36), c, rot_z=i * 0.3)
            B.cyl(p, (x + 0.06, 0.06, 0.36), (x + 0.06, 0.06, 0.4), 0.025, IRON, segs=6)
            p.box((x, 0, 0.42), (0.14, 0.015, 0.015), IRON, rot_z=i * 0.3)
        else:
            p.obox((0.32, 0.05, 0.12), (0.3, 0.95, 0), (0, 0, 1), Vector((0.3, 0.95, 0)).cross(Vector((0, 0, 1))), (0.24, 0.36, 0.24), c)
    k.add(p)
    k.finish()


def trough():
    k = B.Kit("trough")
    rng = k.rng
    p = k.piece("plank")
    for s in (-1, 1):
        p.box((0, s * 0.23, 0.24), (1.5, 0.06, 0.34), B.jit(SILVER, 0.06, rng))
        p.box((s * 0.72, 0, 0.24), (0.06, 0.4, 0.34), B.jit(SILVER, 0.06, rng))
        p.box((s * 0.55, 0, 0.04), (0.14, 0.62, 0.08), B.jit(B.DARK, 0.06, rng))
    p.box((0, 0, 0.1), (1.44, 0.42, 0.05), B.jit(SILVER, 0.06, rng))
    k.add(p)
    w = k.piece("water")
    w.box((0, 0, 0.34), (1.38, 0.38, 0.02), (0.05, 0.08, 0.08))
    k.add(w)
    k.finish()


def washing():
    """A line between two forked posts, propped in the middle, the wash hung on it: a shirt, a sheet,
    a towel with its red ends, drawers, held by pegs."""
    k = B.Kit("washing")
    rng = k.rng
    w = k.piece("log")
    for sx in (-1, 1):
        stake(w, (sx * 1.7, 0, -0.5), (sx * 1.7, 0, 1.9), 0.05, rng, point=0.0, segs=6, stub=False)
        B.cyl(w, (sx * 1.7, 0, 1.85), (sx * 1.7 - sx * 0.08, 0, 2.08), 0.025, GREY_BARK, segs=5)
        B.cyl(w, (sx * 1.7, 0, 1.85), (sx * 1.7 + sx * 0.06, 0, 2.05), 0.025, GREY_BARK, segs=5)
    B.cyl(w, (0.2, 0.25, 0.0), (0.15, 0.0, 1.8), 0.03, GREY_BARK, segs=5)
    k.add(w)
    line = sag((-1.7, 0, 1.95), (1.7, 0, 1.95), 0.12, 14)
    r = k.piece("wood", "rope")
    tube(r, line, 0.008, ROPE, segs=4)
    k.add(r)

    def y_at(x):
        return 1.95 - 0.12 * 4 * ((x + 1.7) / 3.4) * (1 - (x + 1.7) / 3.4)
    c = k.piece("cloth")
    # shirt: body and sleeves, hung by its hem
    x0 = -1.25
    top = y_at(x0)
    B.prism(c, [(x0 - 0.28, top), (x0 + 0.28, top), (x0 + 0.28, top - 0.42), (x0 + 0.5, top - 0.5), (x0 + 0.5, top - 0.62), (x0 + 0.22, top - 0.56),
                (x0 + 0.2, top - 0.8), (x0 - 0.2, top - 0.8), (x0 - 0.22, top - 0.56), (x0 - 0.5, top - 0.62), (x0 - 0.5, top - 0.5), (x0 - 0.28, top - 0.42)],
            -0.008, 0.008, B.jit(UNBLEACHED, 0.04, rng), axis="y")
    # a sheet, folded over the line
    x0 = -0.2
    for i in range(6):
        xa = x0 - 0.5 + i * 0.18
        B.prism(c, [(xa, y_at(xa)), (xa + 0.18, y_at(xa + 0.18)), (xa + 0.18, y_at(xa + 0.18) - 1.05), (xa, y_at(xa) - 1.05 + rng.uniform(-0.02, 0.02))],
                -0.01 + (i % 2) * 0.015, 0.006 + (i % 2) * 0.015, B.jit(LINEN, 0.02, rng), axis="y")
    # a towel, its red ends
    x0 = 0.75
    B.prism(c, [(x0 - 0.17, y_at(x0 - 0.17)), (x0 + 0.17, y_at(x0 + 0.17)), (x0 + 0.17, y_at(x0) - 0.7), (x0 - 0.17, y_at(x0) - 0.7)], -0.008, 0.008, LINEN, axis="y")
    for z in (0.6, 0.66):
        c.box((x0, 0.0, y_at(x0) - z), (0.345, 0.02, 0.03), FADED_RED)
    # drawers
    x0 = 1.25
    top = y_at(x0)
    B.prism(c, [(x0 - 0.2, top), (x0 + 0.2, top), (x0 + 0.18, top - 0.75), (x0 + 0.04, top - 0.75), (x0, top - 0.3), (x0 - 0.04, top - 0.75), (x0 - 0.18, top - 0.75)],
            -0.008, 0.008, B.jit(UNBLEACHED, 0.04, rng), axis="y")
    k.add(c)
    pegs = k.piece("wood", "pegs")
    for x in (-1.5, -1.0, -0.7, 0.3, 0.6, 0.9, 1.07, 1.43):
        pegs.box((x, 0, y_at(x) - 0.02), (0.02, 0.03, 0.08), B.PLANK)
    k.add(pegs)
    k.finish()


def signboard():
    """A hand-lettered board on two posts, a drip-batten over it: whitewashed, the letters dark."""
    k = B.Kit("signboard")
    rng = k.rng
    p = k.piece("wood")
    for sx in (-0.7, 0.7):
        stake(p, (sx, 0.06, -0.5), (sx, 0.06, 2.05), 0.05, rng, point=0.0, segs=6, stub=False)
    k.add(p)
    b = k.piece("plank", "sign")
    b.box((0, 0, 1.75), (1.7, 0.04, 0.5), B.jit(WHITEWASH, 0.03, rng))
    b.box((0, 0, 2.03), (1.8, 0.1, 0.05), B.jit(B.DARK, 0.04, rng))
    b.box((0, -0.02, 1.75), (1.72, 0.03, 0.52), B.jit(B.DARK, 0.04, rng)) # (its frame)
    k.add(b)
    ink = k.piece("plank", "letters")
    x = -0.66
    while x < 0.62:
        strokes = rng.choice([[(0, 0, 0.04, 0.24)], [(0, 0, 0.04, 0.24), (0.07, 0, 0.04, 0.24), (0.035, 0.08, 0.1, 0.035)],
                              [(0, 0, 0.04, 0.24), (0.04, 0.1, 0.08, 0.035), (0.04, -0.1, 0.08, 0.035)], [(0.03, 0, 0.1, 0.035), (0.03, 0.1, 0.1, 0.035), (0.0, 0, 0.04, 0.24)],
                              [(0, 0, 0.04, 0.24), (0.08, 0, 0.04, 0.24)]])
        for dx, dz, w, h in strokes:
            ink.box((x + dx, -0.026, 1.76 + dz), (w, 0.005, h), B.jit(INK if rng.random() < 0.85 else FADED_RED, 0.1, rng))
        x += rng.uniform(0.14, 0.18)
    k.add(ink)
    k.finish()


BUILDERS = {
    "stake_0": lambda: _stake(0), "stake_1": lambda: _stake(1), "stake_2": lambda: _stake(2),
    "rail": rail, "lashing": lashing, "brace": brace, "berm": berm, "walk_board": walk_board, "walk_frame": walk_frame,
    "ditch": ditch, "footing": footing,
    "gate_frame": gate_frame, "gate_leaf_l": lambda: _gate_leaf("gate_leaf_l", 1), "gate_leaf_r": lambda: _gate_leaf("gate_leaf_r", -1), "gate_bar": gate_bar,
    "telegraph_pole": telegraph_pole, "semaphore": semaphore, "shrine": shrine,
    "grave_mound": grave_mound, "cross_a": lambda: _cross("cross_a", False), "cross_b": lambda: _cross("cross_b", True), "headstone": headstone,
    "fence_post": fence_post, "fence_rail": fence_rail, "cemetery_gate": cemetery_gate,
    "woodpile": woodpile, "chopping_block": chopping_block, "boards": boards, "haystack": haystack, "breastwork": breastwork, "ammo": ammo,
    "drum_0": lambda: _drum(0, OLIVE), "drum_1": lambda: _drum(1, (0.36, 0.18, 0.12)), "drum_2": lambda: _drum(2, (0.21, 0.18, 0.15)),
    "tins": tins, "trough": trough, "washing": washing, "signboard": signboard,
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    for a in argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
    for kind, fn in BUILDERS.items():
        if only and kind not in only:
            continue
        fn()


main()
