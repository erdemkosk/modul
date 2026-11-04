"""The things that aren't buildings: the ox, the two carts, tents, and the small goods that lie about.
Made as the buildings are (tools/blender/build_buildings.py), each object "<stuff>-<tag>-<n>", its
colours in its vertices.

    blender --background --factory-startup --python tools/blender/build_props.py [-- --only=ox]

Blender: +Y the way it faces (Godot -Z), +X its right, +Z up; the ground at 0.

  ox         a deep-chested ox: body (tag body), head and horns (tag head), four legs (tag leg), the game
             swings the head and legs from their tops
  hand_cart  the handcart: slatted bed, stake sides, long handles, a prop; two wheels (tag wheel)
  ox_cart    the ox cart: sills, floor, staked plank sides, tail and head boards, pole and yoke; two
             high wheels (tag wheel)
  tent       a wall tent: canvas over a ridge pole, walls, guy ropes and pegs, a laced door flap
  crate      a nailed crate with battens
  barrel     a barrel, staved and hooped
  sack       a sack, tied at the neck
  logs       a short stack of logs

Output: assets/props/<kind>.glb
"""

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bmesh  # noqa: E402
from mathutils import Vector  # noqa: E402

import build_buildings as B  # noqa: E402

B.OUT = os.path.join(B.ROOT, "assets", "props")

HIDE = (0.86, 0.84, 0.8)  # (multiplied by the beast's own colour in the game)
HIDE_DARK = (0.5, 0.47, 0.44)
MUZZLE = (0.2, 0.17, 0.16)
HORN = (0.84, 0.78, 0.66)
HOOF = (0.12, 0.1, 0.09)
CANVAS = (0.66, 0.61, 0.48)
CANVAS_DARK = (0.5, 0.45, 0.34)
BURLAP = (0.63, 0.52, 0.35)
ROPE = (0.6, 0.5, 0.33)


def loft(p, rings, color, under=None, segs=20):
    """A body of revolution about a bent spine: `rings` are (centre, half-width, half-height), each
    square to the way from the last; `under` the colour its belly goes toward."""
    bm = p.bm
    loops = []
    pts = [Vector(r[0]) for r in rings]
    belly = {}
    for i, r in enumerate(rings):
        fwd = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        side = fwd.cross(Vector((0, 0, 1)))
        side = side.normalized() if side.length > 1e-3 else Vector((1, 0, 0))
        up = side.cross(fwd).normalized()
        vs = []
        for k in range(segs):
            t = k / segs * math.tau
            v = bm.verts.new(pts[i] + side * (math.cos(t) * r[1]) + up * (math.sin(t) * r[2]))
            belly[v] = max(-math.sin(t), 0.0)
            vs.append(v)
        loops.append(vs)
    faces = []
    for a, b in zip(loops, loops[1:]):
        for k in range(segs):
            f = bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
            f.smooth = True
            faces.append(f)
    for vs in (loops[0], list(reversed(loops[-1]))):
        f = bm.faces.new(vs)
        f.smooth = True
        faces.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    for f in faces:
        for loop in f.loops:
            t = belly[loop.vert] if under is not None else 0.0
            c = tuple(color[q] + ((under or color)[q] - color[q]) * t for q in range(3))
            loop[p.col] = (c[0], c[1], c[2], 1.0)
    return faces


def ox():
    k = B.Kit("ox")
    body = k.piece("hide", "body")
    # the barrel of it, rump to neck, with the hump over the shoulders
    loft(body, [((0, -1.17, 1.12), 0.1, 0.13), ((0, -1.1, 1.14), 0.27, 0.32), ((0, -0.92, 1.17), 0.39, 0.47), ((0, -0.62, 1.17), 0.44, 0.53),
                ((0, -0.2, 1.13), 0.47, 0.57), ((0, 0.2, 1.12), 0.48, 0.58), ((0, 0.52, 1.18), 0.44, 0.58), ((0, 0.78, 1.32), 0.37, 0.53),
                ((0, 1.0, 1.42), 0.27, 0.4), ((0, 1.18, 1.44), 0.2, 0.3), ((0, 1.3, 1.44), 0.16, 0.23)], HIDE, HIDE_DARK)
    # the dewlap hanging from the throat
    loft(body, [((0, 0.72, 0.78), 0.05, 0.08), ((0, 0.88, 0.86), 0.09, 0.18), ((0, 1.06, 1.06), 0.08, 0.17), ((0, 1.22, 1.22), 0.05, 0.08)], HIDE_DARK)
    # the ribs and hip bones just showing
    for s in (-1, 1):
        loft(body, [((s * 0.33, -0.95, 1.5), 0.04, 0.03), ((s * 0.39, -0.88, 1.53), 0.09, 0.07), ((s * 0.33, -0.76, 1.5), 0.04, 0.03)], HIDE)
    k.add(body)
    # the tail, with its switch
    tail = k.piece("hide", "body")
    loft(tail, [((0, -1.16, 1.5), 0.04, 0.04), ((0, -1.26, 1.3), 0.035, 0.035), ((0.02, -1.28, 0.9), 0.03, 0.03), ((0.03, -1.28, 0.62), 0.025, 0.025)], HIDE_DARK, segs=7)
    loft(tail, [((0.03, -1.28, 0.64), 0.03, 0.03), ((0.03, -1.28, 0.5), 0.08, 0.08), ((0.03, -1.28, 0.32), 0.03, 0.03)], MUZZLE, segs=7)
    k.add(tail)
    # the head, carried low
    head = k.piece("hide", "head")
    loft(head, [((0, 1.26, 1.42), 0.17, 0.2), ((0, 1.42, 1.44), 0.21, 0.24), ((0, 1.6, 1.38), 0.21, 0.24), ((0, 1.78, 1.26), 0.17, 0.19), ((0, 1.92, 1.15), 0.14, 0.14)], HIDE, HIDE_DARK)
    for s in (-1, 1):  # (the ears, cupped and sideways)
        loft(head, [((s * 0.19, 1.42, 1.54), 0.03, 0.04), ((s * 0.33, 1.4, 1.53), 0.05, 0.09), ((s * 0.46, 1.38, 1.5), 0.02, 0.03)], HIDE_DARK, segs=8)
    k.add(head)
    muzzle = k.piece("dark", "head")
    loft(muzzle, [((0, 1.9, 1.17), 0.14, 0.13), ((0, 2.0, 1.1), 0.15, 0.11), ((0, 2.07, 1.05), 0.11, 0.07)], MUZZLE, segs=10)
    for s in (-1, 1):
        loft(muzzle, [((s * 0.205, 1.64, 1.4), 0.02, 0.02), ((s * 0.215, 1.68, 1.4), 0.04, 0.038), ((s * 0.205, 1.72, 1.4), 0.02, 0.02)], (0.03, 0.02, 0.02), segs=10)  # (an eye)
        loft(muzzle, [((s * 0.06, 2.06, 1.09), 0.012, 0.012), ((s * 0.065, 2.09, 1.08), 0.03, 0.022), ((s * 0.07, 2.11, 1.07), 0.012, 0.012)], (0.03, 0.02, 0.02), segs=8)  # (a nostril)
    k.add(muzzle)
    brow = k.piece("hide", "head")
    for s in (-1, 1):  # (the ridge over the eye, the lid)
        loft(brow, [((s * 0.1, 1.6, 1.53), 0.03, 0.03), ((s * 0.17, 1.67, 1.5), 0.05, 0.035), ((s * 0.22, 1.74, 1.44), 0.025, 0.02)], HIDE, segs=8)
    loft(brow, [((0, 1.38, 1.62), 0.06, 0.05), ((0, 1.46, 1.63), 0.13, 0.07), ((0, 1.58, 1.58), 0.08, 0.05)], HIDE_DARK, segs=10)  # (the curly poll)
    k.add(brow)
    horns = k.piece("plaster", "head")
    for s in (-1, 1):  # (out from the poll, forward, and up to a dark tip)
        loft(horns, [((s * 0.15, 1.38, 1.6), 0.055, 0.055), ((s * 0.3, 1.42, 1.65), 0.05, 0.05), ((s * 0.44, 1.5, 1.74), 0.04, 0.04), ((s * 0.5, 1.56, 1.88), 0.028, 0.028)], HORN, segs=8)
        loft(horns, [((s * 0.5, 1.56, 1.87), 0.028, 0.028), ((s * 0.51, 1.58, 1.98), 0.008, 0.008)], MUZZLE, segs=8)
    k.add(horns)
    # the legs, thigh to hoof
    for y, front in ((0.5, True), (-0.78, False)):
        for s in (-1, 1):
            leg = k.piece("hide", "leg")
            t = 1.0 if front else 1.18
            loft(leg, [((s * 0.3, y, 1.02), 0.15 * t, 0.2 * t), ((s * 0.31, y, 0.78), 0.14 * t, 0.17 * t), ((s * 0.31, y - (0 if front else 0.05), 0.54), 0.085, 0.1),
                       ((s * 0.31, y, 0.3), 0.055, 0.065), ((s * 0.31, y + 0.01, 0.17), 0.06, 0.07), ((s * 0.31, y + 0.02, 0.1), 0.085, 0.09)], HIDE, HIDE_DARK, segs=9)
            k.add(leg)
            hoof = k.piece("dark", "leg")
            loft(hoof, [((s * 0.31, y + 0.02, 0.11), 0.085, 0.09), ((s * 0.31, y + 0.04, 0.0), 0.095, 0.11)], HOOF, segs=9)
            hoof.box((s * 0.31, y + 0.1, 0.05), (0.012, 0.1, 0.1), (0.04, 0.03, 0.03))  # (the cleft)
            k.add(hoof)
    k.finish()


def _wheel(k, x, y, z, r, spokes):
    p = k.piece("wood", "wheel")
    B.cart_wheel(p, (x, y, z), (1, 0, 0), r, spokes=spokes, rng=k.rng)
    k.add(p)


def _rope(p, a, b, r=0.012):
    B.cyl(p, a, b, r, ROPE, segs=6)


def hand_cart():
    k = B.Kit("hand_cart")
    rng = k.rng
    frame = k.piece("wood")
    bed = k.piece("plank")
    iron = k.piece("dark")
    for i in range(7):  # (the bed's boards, across, a finger between each)
        bed.box((0, -0.5 + i * 0.167, 0.6), (0.96, 0.15, 0.03), B.jit(B.PLANK, 0.1, rng))
    for s in (-1, 1):
        frame.box((s * 0.34, 0, 0.54), (0.06, 1.3, 0.08), B.jit(B.DARK, 0.1, rng))
        # the handle runs back from the bearer, rising
        B.cyl(frame, (s * 0.34, -0.6, 0.56), (s * 0.3, -1.34, 0.94), 0.024, B.jit(B.PLANK, 0.1, rng), segs=7)
        B.cyl(iron, (s * 0.3, -1.33, 0.94), (s * 0.3, -1.48, 0.975), 0.032, B.IRON, segs=7)
        for y in (-0.48, 0.0, 0.48):  # (stakes, and two rails on them)
            frame.box((s * 0.49, y, 0.78), (0.05, 0.05, 0.42), B.jit(B.DARK, 0.1, rng))
            iron.box((s * 0.51, y, 0.73), (0.015, 0.07, 0.03), B.IRON)
        for z in (0.72, 0.92):
            bed.box((s * 0.49, 0, z), (0.035, 1.14, 0.08), B.jit(B.PLANK, 0.1, rng))
        B.cyl(frame, (s * 0.34, -0.58, 0.5), (s * 0.34, -0.72, 0.04), 0.018, B.DARK, segs=6)  # (the prop)
        iron.box((s * 0.34, 0.08, 0.5), (0.07, 0.1, 0.03), B.IRON)  # (the axle's strap)
    for z in (0.72, 0.92):
        bed.box((0, 0.56, z), (0.96, 0.035, 0.08), B.jit(B.PLANK, 0.1, rng))
    B.cyl(iron, (-0.62, 0.08, 0.42), (0.62, 0.08, 0.42), 0.018, B.IRON, segs=8)
    B.cyl(frame, (-0.3, -1.3, 0.94), (0.3, -1.3, 0.94), 0.02, B.DARK, segs=6)
    k.add(frame)
    k.add(bed)
    k.add(iron)
    for s in (-1, 1):
        _wheel(k, s * 0.62, 0.08, 0.42, 0.42, 10)
    k.finish()


def ox_cart():
    k = B.Kit("ox_cart")
    rng = k.rng
    frame = k.piece("wood")
    boards = k.piece("plank")
    iron = k.piece("dark")
    for s in (-0.5, 0.5):
        frame.box((s, 0, 0.98), (0.1, 2.5, 0.12), B.jit(B.DARK, 0.1, rng))
    for i in range(10):
        boards.box((0, -1.04 + i * 0.232, 1.05), (1.48, 0.22, 0.04), B.jit(B.PLANK, 0.1, rng))
    for s in (-1, 1):
        for y in (-1.05, -0.35, 0.35, 1.05):  # (stakes in their iron pockets)
            frame.box((s * 0.76, y, 1.42), (0.07, 0.07, 0.86), B.jit(B.DARK, 0.1, rng))
            iron.box((s * 0.77, y, 1.05), (0.1, 0.1, 0.1), B.IRON)
        for z in (1.26, 1.5, 1.74):
            boards.box((s * 0.76, 0, z), (0.04, 2.3, 0.13), B.jit(B.PLANK, 0.1, rng))
        for y in (-0.7, 0.7):  # (a rope lashing the load)
            _rope(frame, (s * 0.76, y, 1.84), (0, y, 1.72 + (y * 0.01)))
    for y in (1.14, -1.14):
        for z in (1.26, 1.5, 1.74):
            boards.box((0, y, z), (1.5, 0.04, 0.13), B.jit(B.PLANK, 0.1, rng))
    # the pole out to the yoke, and the hounds that brace it
    B.cyl(frame, (0, -0.2, 1.0), (0, 3.86, 1.74), 0.05, B.jit(B.PLANK, 0.1, rng), segs=8)
    B.cyl(frame, (-0.5, 0.9, 1.0), (0, 1.75, 1.13), 0.03, B.DARK, segs=7)
    B.cyl(frame, (0.5, 0.9, 1.0), (0, 1.75, 1.13), 0.03, B.DARK, segs=7)
    B.cyl(iron, (-0.95, -0.1, 0.68), (0.95, -0.1, 0.68), 0.04, B.IRON, segs=8)
    # the yoke, a carved beam with its bows, lashed to the pole
    B.cyl(frame, (-0.7, 3.78, 1.78), (0.7, 3.78, 1.78), 0.065, B.jit(B.PLANK, 0.05, rng), segs=8, taper=0.1)
    for s in (-0.26, 0.26):
        B.cyl(frame, (s, 3.78, 1.8), (s, 3.78, 1.2), 0.016, B.DARK, segs=6)
    _rope(frame, (-0.26, 3.78, 1.2), (0.26, 3.78, 1.2), 0.018)
    for i in range(5):
        _rope(frame, (-0.08, 3.74 + i * 0.02, 1.84), (0.08, 3.74 + i * 0.02, 1.84), 0.012)
    # a lantern hung at the corner, and a pail
    iron.box((-0.76, 1.05, 1.96), (0.11, 0.11, 0.17), B.IRON)
    B.cyl(boards, (0.5, 1.2, 0.72), (0.5, 1.2, 0.98), 0.12, B.PLANK, segs=9)
    k.add(frame)
    k.add(boards)
    k.add(iron)
    for s in (-1, 1):
        _wheel(k, s * 0.95, -0.1, 0.68, 0.68, 12)
    k.finish()


def tent():
    k = B.Kit("tent")
    rng = k.rng
    canvas = k.piece("cloth")
    w, d = 1.45, 1.9  # (half its width, half its length)
    eave, ridge = 0.95, 2.35
    bm = canvas.bm

    def sheet(rows, color):
        """A grid of points, the cloth's slight sag and creases in them."""
        vs = [[bm.verts.new(q) for q in row] for row in rows]
        fs = []
        for a, b in zip(vs, vs[1:]):
            for i in range(len(a) - 1):
                f = bm.faces.new((a[i], a[i + 1], b[i + 1], b[i]))
                f.smooth = True
                fs.append(f)
        for f in fs:
            f.normal_update()
            canvas._paint([f], B.jit(color, 0.05, rng))

    for s in (-1, 1):  # (the two slopes, and the walls under them)
        rows = []
        for i in range(9):
            t = i / 8
            y = -d + t * 2 * d
            row = []
            for j in range(6):
                u = j / 5
                sag = math.sin(u * math.pi) * (0.09 + 0.05 * math.sin(t * math.pi * 4))
                row.append((s * (w * (1 - u)), y, eave + (ridge - eave) * u - sag))
            rows.append(row)
        sheet(rows, CANVAS)
        rows = []
        for i in range(9):
            t = i / 8
            y = -d + t * 2 * d
            bulge = 0.05 * math.sin(t * math.pi * 4)
            rows.append([(s * (w + 0.08 + bulge), y, 0.0), (s * (w + bulge * 0.5), y, eave)])
        sheet(rows, CANVAS_DARK)
    for s in (-1, 1):  # (the end walls, the front a door laced and part open)
        y = s * d
        for x0, x1 in ((-w, -0.22), (0.22, w)) if s > 0 else ((-w, 0.0), (0.0, w)):
            rows = []
            for j in range(5):
                u = j / 4
                z = u * ridge
                lim = w * (1 - max(z - eave, 0) / (ridge - eave))
                a = max(x0, -lim)
                b = min(x1, lim)
                rows.append([(a + (b - a) * i / 3, y, z) for i in range(4)])
            sheet(rows, CANVAS_DARK)
    k.add(canvas)
    wood = k.piece("wood")
    B.cyl(wood, (0, -d - 0.25, ridge), (0, d + 0.25, ridge), 0.04, B.DARK, segs=8)  # (the ridge pole)
    for y in (-d, d):
        B.cyl(wood, (0, y, 0), (0, y, ridge + 0.1), 0.04, B.DARK, segs=8)
    for y in (-d * 0.95, 0, d * 0.95):  # (guy ropes, out from the eaves to their pegs)
        for s in (-1, 1):
            peg = (s * (w + 0.85), y, 0.0)
            _rope(wood, (s * (w + 0.03), y, eave), (peg[0], y, 0.12), 0.01)
            B.cyl(wood, peg, (peg[0] * 0.98, y, 0.28), 0.025, B.PLANK, segs=6)
    B.cyl(wood, (0, d + 0.25, ridge), (0, d + 0.9, 0.08), 0.01, ROPE, segs=6)
    B.cyl(wood, (0, -d - 0.25, ridge), (0, -d - 0.9, 0.08), 0.01, ROPE, segs=6)
    k.add(wood)
    k.finish()


def crate():
    k = B.Kit("crate")
    p = k.piece("plank")
    rng = k.rng
    s = 0.66
    p.box((0, 0, s * 0.5), (s - 0.05, s - 0.05, s - 0.05), B.jit(B.PLANK, 0.05, rng))
    for sy in (-1, 1):
        for i in range(4):  # (boards on two faces, a dark line between)
            z = 0.1 + i * 0.155
            p.box((0, sy * s * 0.485, z), (s - 0.1, 0.03, 0.145), B.jit(B.PLANK, 0.1, rng))
            p.box((sy * s * 0.485, 0, z), (0.03, s - 0.1, 0.145), B.jit(B.PLANK, 0.1, rng))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * s * 0.47, sy * s * 0.47, s * 0.5), (0.07, 0.07, s + 0.01), B.jit(B.DARK, 0.1, rng))
    for sx in (-1, 1):
        p.box((sx * s * 0.47, 0, s), (0.07, s, 0.04), B.jit(B.DARK, 0.1, rng))
        p.box((0, sx * s * 0.47, s), (s, 0.07, 0.04), B.jit(B.DARK, 0.1, rng))
        p.box((sx * s * 0.47, 0, 0.0 + 0.02), (0.07, s, 0.04), B.jit(B.DARK, 0.1, rng))
    k.add(p)
    k.finish()


def barrel():
    k = B.Kit("barrel")
    p = k.piece("wood")
    r, h = 0.3, 0.84
    n = 16
    rng = k.rng
    for i in range(n):  # (staves, swelling at the middle)
        a = i / n * math.tau
        rad = Vector((math.cos(a), math.sin(a), 0))
        tan = Vector((-math.sin(a), math.cos(a), 0))
        c = B.jit(B.PLANK, 0.12, rng)
        for lo, hi, r0, r1 in ((0.0, 0.42, r * 0.84, r), (0.42, h, r, r * 0.84)):
            mid = rad * ((r0 + r1) * 0.5) + Vector((0, 0, (lo + hi) * 0.5))
            up = (rad * (r1 - r0) + Vector((0, 0, hi - lo))).normalized()
            p.obox(mid, tan, up.cross(tan), up, (r * math.tau / n * 0.98, 0.03, (hi - lo) * 1.02), c)
    p.box((0, 0, h - 0.03), (r * 1.5, r * 1.5, 0.03), B.jit(B.PLANK, 0.05, rng))
    iron = k.piece("dark")
    for z, rr in ((0.1, r * 0.885), (0.28, r * 0.97), (0.56, r * 0.97), (0.74, r * 0.885)):
        B._ring(iron, Vector((0, 0, z)), Vector((0, 0, 1)), rr + 0.012, 0.012, 0.045, B.IRON, n=18)
    k.add(p)
    k.add(iron)
    k.finish()


def sack():
    k = B.Kit("sack")
    p = k.piece("cloth")
    # lying as it was dropped: a full bag, flat under its weight, its neck tied and flopped over
    loft(p, [((0, -0.44, 0.15), 0.08, 0.04), ((0, -0.4, 0.16), 0.24, 0.13), ((0, -0.26, 0.18), 0.3, 0.18), ((0, 0.0, 0.19), 0.32, 0.19), ((0, 0.2, 0.18), 0.3, 0.18),
             ((0, 0.34, 0.16), 0.24, 0.14), ((0, 0.42, 0.14), 0.1, 0.07), ((0, 0.46, 0.13), 0.045, 0.04), ((0, 0.49, 0.125), 0.045, 0.04), ((0, 0.54, 0.12), 0.1, 0.05), ((0, 0.58, 0.1), 0.06, 0.02)],
         BURLAP, (0.46, 0.37, 0.24), segs=14)
    for x in (-0.16, 0.0, 0.16):  # (the creases across it)
        loft(p, [((x, -0.38, 0.345), 0.01, 0.006), ((x + 0.01, 0.0, 0.378), 0.02, 0.008), ((x, 0.3, 0.345), 0.01, 0.006)], (0.5, 0.41, 0.27), segs=6)
    B._ring(p, Vector((0, 0.475, 0.127)), Vector((0, 1, 0)), 0.05, 0.014, 0.03, ROPE, n=10)
    k.add(p)
    k.finish()


def logs():
    k = B.Kit("logs")
    p = k.piece("log")
    rng = k.rng
    ring = [(-0.42 + i * 0.28, 0.14) for i in range(4)] + [(-0.28 + i * 0.28, 0.38) for i in range(3)] + [(-0.14 + i * 0.28, 0.62) for i in range(2)]
    for x, z in ring:
        y0 = rng.uniform(-0.08, 0.08)
        p.log((x, -0.55 + y0, z), (x, 0.55 + y0, z), 0.13, jitter=0.03, rng=rng)
    k.add(p)
    k.finish()


BUILDERS = {"ox": ox, "hand_cart": hand_cart, "ox_cart": ox_cart, "tent": tent, "crate": crate, "barrel": barrel, "sack": sack, "logs": logs}


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
