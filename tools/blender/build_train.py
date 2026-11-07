"""The railway's rolling stock and the things that stand by the line, made as the buildings are
(tools/blender/build_buildings.py): each object "<stuff>-<tag>-<n>", its colours in its vertices,
the edges eased, the occlusion baked in, the grime at the foot.

    blender --background --factory-startup --python tools/blender/build_train.py [-- --only=lokomotif] [-- --render]

Blender: the rail top at z 0, the car running along y, its front at -y (Godot +z); +X its right.
Gauge five feet: the rails' middles at x +-0.76.

  lokomotif  a 1910s freight engine of the 0-8-0 kind: a long black boiler banded in steel, the
             smokebox with its door and dogs, a tall stack with a flared cap, the steam dome and the
             sand dome, safety valves and whistle, the cab with its arched roof and round front
             windows, a headlamp on the smokebox and two on the buffer beam, red frames and buffer
             beams, buffers and a screw coupling, an air pump, handrails, running boards, cylinders
             with their steam chests. Four pairs of drivers (tag "driver"), each with its crank pin and
             counterweight, the right side leading the left by a quarter turn; the side rod coupling
             them (tag "siderod"), the main rod from the third pair to the crosshead (tag "mainrod"),
             the crosshead and piston rod (tag "crosshead"): the game drives them round (train.gd)
  tender     the coal and water behind: a riveted tank, the coal heaped in its coped bunker, tool
             boxes, the water filler, a ladder; two bogies (wheels tag "wheel")
  vagon      the coach: green matchboard, a row of framed windows, a clerestory roof with its lights
             and lamp tops, open end platforms with railings and steps; two bogies
  yuk        a teplushka: a two-axle boxcar of oxide-red boards on a braced frame, a sliding door
             each side, barred hatches high up, an arched tarred roof and the stovepipe of the stove
             inside; its springs, axleguards and brake gear
  platforma  an open wagon with low sides and stakes, logs chained on it and a tarp over crates
  tampon     the buffer stop at a line's end: a crib of sleepers and raked struts, the red beam
  su_kulesi  the water tower: an octagon of fieldstone, the timber tank house over it, its roof and
             vent, the spout swung out toward -y (the track, 4.6 m off), its chain and counterweight
  travers    a sleeper with its two tie plates and spikes (the rails sit at x +-0.76)

Wheels are pieces of their own, each with its origin on its axle (they turn about their local X).

Output: assets/train/<kind>.glb
"""

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import build_buildings as B  # noqa: E402

B.OUT = os.path.join(B.ROOT, "assets", "train")

# --- the paint -------------------------------------------------------------------------------------
INK = (0.085, 0.085, 0.085)      # the engine's black, a little worn
INK_HI = (0.13, 0.13, 0.125)     # black gone grey where it's handled
STEEL = (0.36, 0.35, 0.33)       # tyres, rods, bands: bright steel dulled
ROD = (0.42, 0.41, 0.38)
IRON = (0.17, 0.17, 0.17)
RED = (0.44, 0.12, 0.08)         # frames, wheel centres, buffer beams
RED_DK = (0.32, 0.09, 0.06)
BRASS = (0.62, 0.49, 0.25)
GLASS = (0.16, 0.15, 0.13)
LAMP = (1.0, 0.86, 0.55)
COAL = (0.05, 0.05, 0.05)
SOOT = (0.05, 0.045, 0.04)
OXIDE = (0.47, 0.23, 0.15)       # the wagons' red-brown
OXIDE_DK = (0.35, 0.17, 0.11)
TAR = (0.2, 0.19, 0.18)          # a tarred roof
COACH = (0.3, 0.38, 0.25)        # third-class green
COACH_DK = (0.21, 0.27, 0.17)
CREAM = (0.8, 0.76, 0.64)
WOOD = (0.5, 0.42, 0.32)         # weathered timber
WOOD_GREY = (0.46, 0.43, 0.38)
TARP = (0.42, 0.4, 0.3)
STONE = B.STONE
WHITE = (0.84, 0.82, 0.76)

RAIL_X = 0.76
X = Vector((1, 0, 0))

# The engine's motion (train.gd's DRIVER_R, CRANK, MAIN_ROD, DRIVERS, MAIN_AXLE agree with these)
DRIVER_R = 0.65
CRANK = 0.3
MAIN_ROD = 3.3
DRIVERS = (-2.1, -0.75, 0.6, 1.95)  # the axles' y
MAIN_AXLE = 2                        # the third pair takes the main rod
ROD_X = 0.93                         # the side rod's middle, out from the track's middle
MAIN_X = 1.03                        # the main rod's, outside the side rod


def jit(c, amt=0.06, rng=random):
    return B.jit(c, amt, rng)


def cyl(p, a, b, r, color, segs=16, taper=0.0):
    B.cyl(p, a, b, r, color, segs=segs, taper=taper)


def add(k, p, pivot=None):
    """Into the kit; `pivot` the point its origin goes on (else the middle of its bounds)."""
    if len(p.bm.verts) == 0:
        p.bm.free()
        return
    k.add(p)
    if pivot is not None:
        k.pivots[k.objects[-1].name] = Vector(pivot)


def kit(kind):
    k = B.Kit(kind)
    k.pivots = {}
    return k


def finish(k):
    """As build_buildings' Kit.finish, but each piece's origin where it's asked for (a wheel's on its
    axle, a crosshead's on its pin)."""
    if B.FINISH["bevel"]:
        for ob in k.objects:
            if ob.name.split("-")[0] in B.BEVELLED:
                B._bevel(ob.data)
    if B.FINISH["ao"]:
        B._bake_ao(k.objects)
    if B.FINISH["grime"]:
        for ob in k.objects:
            B._grime(ob)
    for ob in k.objects:
        me = ob.data
        if ob.name in k.pivots:
            c = k.pivots[ob.name]
        else:
            lo = Vector((min(v.co.x for v in me.vertices), min(v.co.y for v in me.vertices), min(v.co.z for v in me.vertices)))
            hi = Vector((max(v.co.x for v in me.vertices), max(v.co.y for v in me.vertices), max(v.co.z for v in me.vertices)))
            c = (lo + hi) * 0.5
        me.transform(Matrix.Translation(-c))
        ob.location = c
    os.makedirs(B.OUT, exist_ok=True)
    path = os.path.join(B.OUT, k.kind + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False, export_apply=True, export_yup=True)
    print("wrote", path, len(k.objects), "pieces")


def bx(p, c, size, col):
    return p.box(c, size, col)


def rivets(p, a, b, n, col=INK_HI, s=0.035):
    a, b = Vector(a), Vector(b)
    for i in range(n):
        p.box(a.lerp(b, (i + 0.5) / n), (s, s, s), col)


def sector(p, x0, x1, c, r0, r1, a0, a1, col, n=8):
    """A flat ring sector across x (a counterweight): between radii r0 and r1, angles a0..a1 in the
    y-z plane about `c` (y, z)."""
    out = []
    for i in range(n + 1):
        a = a0 + (a1 - a0) * i / n
        out.append((c[0] + math.cos(a) * r1, c[1] + math.sin(a) * r1))
    for i in range(n, -1, -1):
        a = a0 + (a1 - a0) * i / n
        out.append((c[0] + math.cos(a) * r0, c[1] + math.sin(a) * r0))
    # (a ring's outline isn't convex: fanned in strips instead of one face)
    bm = p.bm
    m = n + 1
    top = [bm.verts.new((x1, u, v)) for u, v in out]
    bot = [bm.verts.new((x0, u, v)) for u, v in out]
    faces = []
    for i in range(n):
        o0, o1, i0, i1 = i, i + 1, 2 * m - 1 - i, 2 * m - 2 - i
        faces.append(bm.faces.new((top[o0], top[o1], top[i1], top[i0])))
        faces.append(bm.faces.new((bot[i0], bot[i1], bot[o1], bot[o0])))
    L = len(out)
    for i in range(L):
        j = (i + 1) % L
        faces.append(bm.faces.new((bot[i], bot[j], top[j], top[i])))
    for f in faces:
        f.normal_update()
    p._paint(faces, col)


def arch(p, y0, y1, half, z_eave, rise, thick, col, n=10, over=0.0):
    """A roof arched across x: `n` slats from eave to eave, along y from y0 to y1."""
    rad = (half * half + rise * rise) / (2 * rise)
    cz = z_eave + rise - rad
    span = math.asin(min(half / rad, 1.0))
    for i in range(n):
        a0 = -span + 2 * span * i / n
        a1 = -span + 2 * span * (i + 1) / n
        am = (a0 + a1) * 0.5
        w = 2 * rad * math.sin((a1 - a0) * 0.5) * 1.04
        c = Vector((math.sin(am) * (rad + thick * 0.5), (y0 + y1) * 0.5, cz + math.cos(am) * (rad + thick * 0.5)))
        tan = Vector((math.cos(am), 0, -math.sin(am)))
        nrm = Vector((math.sin(am), 0, math.cos(am)))
        B.rbox(p, c, tan, (0, 1, 0), (w, y1 - y0 + over * 2, thick), jit(col, 0.03))


# --- running gear ----------------------------------------------------------------------------------

def driver(k, side, y, pin_up, main=False):
    """One driving wheel (tag "driver"): a steel tyre with its flange, a red spoked centre, the
    counterweight opposite the crank, the crank boss and pin. `pin_up`: the pin at the top (else at
    the front, -y). Its origin on the axle."""
    p = k.piece("dark", "driver")
    r = DRIVER_R
    x = side * RAIL_X
    c = Vector((x, y, r))
    B._ring(p, c, X, r - 0.045, 0.09, 0.14, STEEL, n=36)  # (the tyre)
    B._ring(p, c - X * side * 0.055, X, r + 0.01, 0.05, 0.035, STEEL, n=36)  # (the flange, inside)
    B._ring(p, c, X, r - 0.115, 0.06, 0.1, RED, n=30)  # (the rim of the centre)
    cyl(p, c - X * 0.08, c + X * 0.08, 0.17, RED, segs=16)  # (the boss)
    cyl(p, c - X * 0.1, c + X * 0.1, 0.07, IRON, segs=10)  # (the axle end)
    for i in range(14):
        a = i / 14 * math.tau
        rad = Vector((0, math.cos(a), math.sin(a)))
        tan = Vector((0, -math.sin(a), math.cos(a)))
        ln = r - 0.14 - 0.15
        p.obox(c + rad * (0.15 + ln * 0.5) + X * side * 0.01, X, rad, tan, (0.06, ln, 0.055), jit(RED, 0.04, k.rng))
    pa = math.pi * 0.5 if pin_up else math.pi  # (angle in y-z: pi is -y, the front)
    cw = pa + math.pi
    sector(p, x + side * 0.01 - 0.045, x + side * 0.01 + 0.045, (y, r), 0.2, r - 0.13, cw - 0.95, cw + 0.95, RED_DK, n=10)
    pin = c + Vector((0, math.cos(pa), math.sin(pa))) * CRANK
    cyl(p, pin + X * side * 0.03, pin + X * side * 0.1, 0.11, RED, segs=14)  # (the crank boss)
    reach = MAIN_X + 0.07 if main else ROD_X + 0.05
    cyl(p, pin + X * side * 0.08, Vector((side * reach, pin.y, pin.z)), 0.045, ROD, segs=10)  # (the pin)
    cyl(p, Vector((side * (reach - 0.012), pin.y, pin.z)), Vector((side * (reach + 0.015), pin.y, pin.z)), 0.06, STEEL, segs=10)  # (its collar)
    add(k, p, c)


def plain_wheel(k, side, y, r, spokes=10, axle=False, disc=False):
    """A carrying wheel (tag "wheel"): steel tyre and flange, a spoked or disc centre; `axle`: the
    axle across to the other wheel with it."""
    p = k.piece("dark", "wheel")
    x = side * RAIL_X
    c = Vector((x, 0.0, 0.0)) + Vector((0, y, r))
    B._ring(p, c, X, r - 0.035, 0.07, 0.13, STEEL, n=28)
    B._ring(p, c - X * side * 0.05, X, r + 0.008, 0.04, 0.03, STEEL, n=28)
    if disc:
        cyl(p, c - X * 0.03, c + X * 0.03, r - 0.06, IRON, segs=24)
        cyl(p, c - X * 0.05, c + X * 0.05, r * 0.45, INK_HI, segs=16)
    else:
        B._ring(p, c, X, r - 0.09, 0.04, 0.08, IRON, n=24)
        for i in range(spokes):
            a = i / spokes * math.tau
            rad = Vector((0, math.cos(a), math.sin(a)))
            tan = Vector((0, -math.sin(a), math.cos(a)))
            ln = r - 0.11 - 0.09
            p.obox(c + rad * (0.09 + ln * 0.5), X, rad, tan, (0.045, ln, 0.045), IRON)
    cyl(p, c - X * 0.09, c + X * 0.09, 0.1, INK_HI, segs=12)
    if axle:
        cyl(p, Vector((-RAIL_X + 0.05, y, r)), Vector((RAIL_X - 0.05, y, r)), 0.065, IRON, segs=10)
    add(k, p, c)


def wheelset(k, y, r, **kw):
    plain_wheel(k, 1, y, r, axle=True, **kw)
    plain_wheel(k, -1, y, r, **kw)


def buffer_pair(k, y, s, z=1.06, beam=RED, width=2.5, beam_h=0.36):
    """A headstock across the end at `y` (`s` -1 the front, 1 the back): the beam, two sprung buffers
    with round heads, the drawhook and its screw coupling hung on it."""
    p = k.piece("dark", "buffers")
    p.box((0, y, z), (width, 0.2, beam_h), jit(beam, 0.04, k.rng))
    for sx in (-1, 1):
        bx(p, (sx * 0.87, y + s * 0.11, z), (0.3, 0.04, 0.3), IRON)  # (the buffer's flange)
        cyl(p, (sx * 0.87, y + s * 0.1, z), (sx * 0.87, y + s * 0.3, z), 0.1, IRON, segs=12)  # (its case)
        cyl(p, (sx * 0.87, y + s * 0.28, z), (sx * 0.87, y + s * 0.4, z), 0.055, STEEL, segs=8)  # (the plunger)
        cyl(p, (sx * 0.87, y + s * 0.39, z), (sx * 0.87, y + s * 0.45, z), 0.19, STEEL, segs=16)  # (the head)
        for dx in (-0.1, 0.1):
            for dz in (-0.1, 0.1):
                bx(p, (sx * 0.87 + dx, y + s * 0.135, z + dz), (0.035, 0.02, 0.035), INK_HI)
    # the hook out through the beam, the coupling's links and screw hung from it
    bx(p, (0, y + s * 0.2, z - 0.02), (0.1, 0.24, 0.1), IRON)
    p.obox((0, y + s * 0.33, z + 0.02), (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.08, 0.05, 0.16), IRON)
    for sx in (-0.07, 0.07):
        p.obox((sx, y + s * 0.34, z - 0.18), (1, 0, 0), (0, 0.2, 0.98), (0, -0.98, 0.2), (0.025, 0.36, 0.035), IRON)
    cyl(p, (-0.05, y + s * 0.37, z - 0.36), (0.05, y + s * 0.37, z - 0.36), 0.03, IRON, segs=6)
    cyl(p, (0.0, y + s * 0.37, z - 0.36), (0.0, y + s * 0.37, z - 0.52), 0.025, IRON, segs=6)
    bx(p, (0.1, y + s * 0.37, z - 0.44), (0.18, 0.025, 0.025), IRON)  # (the screw's handle)
    # the brake pipe's hose hung beside it
    cyl(p, (0.42, y + s * 0.1, z - 0.12), (0.42, y + s * 0.3, z - 0.38), 0.035, (0.1, 0.09, 0.08), segs=6)
    add(k, p)


def axlebox(p, x, y, z, s, col=IRON):
    """An axlebox on its axle end, its lid outward."""
    bx(p, (x, y, z + 0.02), (0.16, 0.26, 0.3), col)
    bx(p, (x + s * 0.09, y, z + 0.02), (0.03, 0.2, 0.22), INK_HI)
    bx(p, (x + s * 0.11, y, z + 0.1), (0.02, 0.06, 0.04), STEEL)


def spring(p, x, y, z_top, length=1.1, n=6):
    B.leaf_spring(p, x, y - length * 0.5, y + length * 0.5, z_top, n=n)


def bogie(k, y, r=0.45, wb=1.8):
    """A diamond-frame bogie: the arch bars and tie bar each side, the axleboxes at their ends, the
    bolster on its springs in the middle; two wheelsets."""
    p = k.piece("dark", "bogie")
    h = wb * 0.5
    for sx in (-1, 1):
        x = sx * 1.02
        top_z, bot_z, tie_z = r + 0.42, r - 0.25, r - 0.12
        # the top arch bar, straight over; the lower bar bent down under the bolster
        bx(p, (x, y, top_z), (0.08, wb + 0.5, 0.06), IRON)
        for s in (-1, 1):
            a = Vector((x, y + s * (h + 0.1), r + 0.22))
            b = Vector((x, y + s * 0.45, bot_z))
            d = b - a
            B.rbox(p, (a + b) * 0.5, d, (1, 0, 0), (d.length + 0.06, 0.08, 0.05), IRON)
            B.rbox(p, (Vector((x, y + s * (h + 0.1), top_z)) + a) * 0.5, (0, 0, 1), (1, 0, 0), ((top_z - a.z) + 0.04, 0.08, 0.05), IRON)
            axlebox(p, x, y + s * h, r, sx)
            bx(p, (x, y + s * h, r + 0.3), (0.06, 0.06, 0.24), IRON)  # (the box bolts)
        bx(p, (x, y, bot_z), (0.08, 0.95, 0.05), IRON)
        bx(p, (x, y, tie_z - 0.22), (0.08, wb + 0.3, 0.04), INK_HI)  # (the tie bar)
        for dy in (-0.25, 0.0, 0.25):  # (the bolster springs, coiled)
            cyl(p, (x, y + dy, bot_z + 0.03), (x, y + dy, top_z - 0.12), 0.07, STEEL, segs=8)
        bx(p, (x, y, top_z - 0.08), (0.12, 0.85, 0.08), IRON)
        for s in (-1, 1):  # (the brake shoes against the treads)
            bx(p, (sx * RAIL_X, y + s * (h - r - 0.02), r), (0.1, 0.07, 0.3), IRON)
    bx(p, (0, y, r + 0.36), (2.1, 0.32, 0.18), IRON)  # (the bolster across)
    cyl(p, (0, y, r + 0.45), (0, y, r + 0.55), 0.22, IRON, segs=12)  # (the centre plate)
    for s in (-1, 1):
        cyl(p, (-1.02, y + s * 0.62, r + 0.0), (1.02, y + s * 0.62, r + 0.0), 0.025, IRON, segs=6)  # (brake beams)
    add(k, p)
    wheelset(k, y - h, r)
    wheelset(k, y + h, r)


def wagon_gear(k, y_axles, r, solebar_z, length):
    """A two-axle wagon's running gear: axleguards (W irons) under the solebars, the axleboxes in
    them, a leaf spring over each, the brake gear between, a truss rod under the length."""
    p = k.piece("dark", "gear")
    for sx in (-1, 1):
        x = sx * 1.02
        for y in y_axles:
            for s in (-1, 1):  # (the W iron's two legs, splayed)
                a = Vector((x, y + s * 0.55, solebar_z - 0.12))
                b = Vector((x, y + s * 0.15, r - 0.25))
                d = b - a
                B.rbox(p, (a + b) * 0.5, d, (1, 0, 0), (d.length, 0.07, 0.04), IRON)
            bx(p, (x, y, r - 0.27), (0.08, 0.5, 0.04), IRON)
            axlebox(p, x, y, r, sx)
            spring(p, x, y, solebar_z - 0.16, 1.15, 6)
            for s in (-1, 1):  # (spring hangers)
                bx(p, (x, y + s * 0.6, solebar_z - 0.15), (0.05, 0.05, 0.12), IRON)
            for s in (-1, 1):  # (brake shoes)
                bx(p, (sx * RAIL_X, y + s * (r + 0.04), r - 0.05), (0.1, 0.07, 0.3), IRON)
        # the brake lever along the side, and the truss under
    mid = sum(y_axles) / len(y_axles)
    cyl(p, (0.0, mid - 0.45, solebar_z - 0.35), (0.0, mid + 0.45, solebar_z - 0.35), 0.16, IRON, segs=12)  # (the brake cylinder)
    for sx in (-0.5, 0.5):
        cyl(p, (sx, y_axles[0] + 0.3, solebar_z - 0.12), (sx, mid, solebar_z - 0.5), 0.02, IRON, segs=5)
        cyl(p, (sx, mid, solebar_z - 0.5), (sx, y_axles[-1] - 0.3, solebar_z - 0.12), 0.02, IRON, segs=5)
    add(k, p)
    for y in y_axles:
        wheelset(k, y, r)


def underframe(k, half_len, z, beam=RED, width=2.7):
    """Solebars (channels) along each side, crossbearers, the headstocks with their buffers."""
    p = k.piece("dark", "frame")
    for sx in (-1, 1):
        bx(p, (sx * 1.1, 0, z), (0.08, half_len * 2, 0.3), INK_HI)
        bx(p, (sx * 1.05, 0, z + 0.13), (0.14, half_len * 2, 0.04), INK_HI)
        bx(p, (sx * 1.05, 0, z - 0.13), (0.14, half_len * 2, 0.04), INK_HI)
        rivets(p, (sx * 1.145, -half_len + 0.2, z + 0.08), (sx * 1.145, half_len - 0.2, z + 0.08), int(half_len * 3), IRON, 0.03)
    n = int(half_len * 2 / 1.2)
    for i in range(n + 1):
        bx(p, (0, -half_len + i * half_len * 2 / n, z), (2.1, 0.12, 0.2), IRON)
    for sx in (-0.45, 0.45):
        bx(p, (sx, 0, z), (0.12, half_len * 2, 0.22), IRON)
    add(k, p)
    buffer_pair(k, -half_len - 0.1, -1, z=z, beam=beam, width=width)
    buffer_pair(k, half_len + 0.1, 1, z=z, beam=beam, width=width)


def steps(p, x, y, z_top, n=2, col=IRON):
    for i in range(n):
        zz = z_top - 0.32 * (i + 1)
        bx(p, (x, y, zz), (0.22, 0.38, 0.035), col)
    bx(p, (x, y - 0.19, z_top - 0.16 * (n + 1)), (0.03, 0.03, 0.32 * n + 0.1), col)
    bx(p, (x, y + 0.19, z_top - 0.16 * (n + 1)), (0.03, 0.03, 0.32 * n + 0.1), col)


# --- the engine ------------------------------------------------------------------------------------

def lokomotif():
    k = kit("lokomotif")
    rng = k.rng
    BZ = 2.4   # the boiler's middle
    BR = 0.8
    deck = 1.48  # the running boards' top
    front = -5.1
    # -- frames, the buffer beams, the cylinders' saddle
    p = k.piece("dark", "frame")
    for sx in (-1, 1):
        x = sx * 0.58
        bx(p, (x, -0.45, 0.95), (0.08, 9.0, 0.8), RED)
        rivets(p, (x + sx * 0.045, -4.6, 1.28), (x + sx * 0.045, 3.6, 1.28), 26, RED_DK, 0.03)
        for y in DRIVERS:  # (the hornblocks and axleboxes in the frame)
            axlebox(p, sx * 0.6, y, DRIVER_R, sx, RED_DK)
            spring(p, sx * 0.6, y, 0.4 + DRIVER_R * 0.2, 0.9, 6)
    bx(p, (0, -4.0, 1.25), (1.4, 1.0, 0.7), INK)  # (the saddle under the smokebox)
    bx(p, (0, 4.15, 1.0), (0.9, 0.4, 0.3), RED)  # (the drag box at the back)
    add(k, p)
    buffer_pair(k, front + 0.1, -1, z=1.06, beam=RED, width=2.7, beam_h=0.42)
    # -- the boiler, banded, the firebox under its back end, the smokebox in front
    p = k.piece("dark", "boiler")
    cyl(p, (0, -3.45, BZ), (0, 2.75, BZ), BR, INK, segs=28)
    for y in (-2.6, -1.4, -0.2, 1.0, 2.2):
        cyl(p, (0, y, BZ), (0, y + 0.06, BZ), BR + 0.012, STEEL, segs=28)
    bx(p, (0, 1.9, 1.62), (1.0, 1.7, 0.6), INK)  # (the firebox down between the frames)
    for y in (1.25, 2.55):
        cyl(p, (0, y, BZ), (0, y + 0.05, BZ), BR + 0.014, STEEL, segs=28)
    add(k, p)
    p = k.piece("dark", "smokebox")
    cyl(p, (0, -4.62, BZ), (0, -3.38, BZ), BR + 0.07, SOOT, segs=28)
    cyl(p, (0, -4.7, BZ), (0, -4.6, BZ), BR + 0.09, INK, segs=28)  # (the front ring)
    cyl(p, (0, -4.78, BZ), (0, -4.68, BZ), 0.68, SOOT, segs=28, taper=0.06)  # (the door, dished)
    cyl(p, (0, -4.83, BZ), (0, -4.76, BZ), 0.16, INK_HI, segs=14)  # (its centre)
    for a in range(8):  # (the dogs round its edge)
        aa = a / 8 * math.tau + 0.2
        bx(p, (math.cos(aa) * 0.7, -4.74, BZ + math.sin(aa) * 0.7), (0.07, 0.06, 0.07), IRON)
    for dz in (-0.35, 0.35):  # (the hinge straps)
        bx(p, (-0.32, -4.8, BZ + dz), (0.72, 0.03, 0.07), IRON)
    bx(p, (0, -4.84, BZ), (0.08, 0.06, 0.34), STEEL)  # (the handle)
    cyl(p, (0, -4.86, BZ + 0.48), (0, -4.82, BZ + 0.48), 0.14, BRASS, segs=12)  # (the number plate)
    add(k, p)
    # -- the stack: tall and straight, a flared cap, soot round its foot
    p = k.piece("dark", "stack")
    cyl(p, (0, -4.0, BZ + 0.7), (0, -4.0, BZ + 0.92), 0.4, INK, segs=18)  # (the base flare)
    cyl(p, (0, -4.0, BZ + 0.85), (0, -4.0, 4.55), 0.26, INK, segs=18, taper=-0.06)
    cyl(p, (0, -4.0, 4.5), (0, -4.0, 4.72), 0.36, INK, segs=18, taper=-0.3)  # (the cap)
    cyl(p, (0, -4.0, 4.7), (0, -4.0, 4.76), 0.37, IRON, segs=18)
    cyl(p, (0, -4.0, 4.6), (0, -4.0, 4.765), 0.25, SOOT, segs=18)  # (the black mouth)
    add(k, p)
    # -- the domes: steam dome, sand dome, the safety valves, the whistle
    p = k.piece("dark", "domes")
    for y, r, h, col in ((-1.1, 0.42, 0.62, INK), (0.55, 0.38, 0.34, INK)):
        cyl(p, (0, y, BZ + 0.5), (0, y, BZ + BR + h - 0.12), r, col, segs=20)
        cyl(p, (0, y, BZ + BR + h - 0.14), (0, y, BZ + BR + h), r * 0.86, col, segs=20, taper=0.3)
        cyl(p, (0, y, BZ + 0.62), (0, y, BZ + 0.78), r + 0.06, col, segs=20, taper=0.2)  # (its skirt)
        cyl(p, (0, y, BZ + BR + h - 0.13), (0, y, BZ + BR + h - 0.09), r + 0.01, STEEL, segs=20)
    for sx in (-0.11, 0.11):
        cyl(p, (sx, 2.1, BZ + 0.7), (sx, 2.1, BZ + 1.12), 0.06, BRASS, segs=8)  # (the safety valves)
    cyl(p, (0.3, 2.35, BZ + 0.7), (0.3, 2.35, BZ + 1.05), 0.035, BRASS, segs=8)
    cyl(p, (0.3, 2.35, BZ + 1.05), (0.3, 2.35, BZ + 1.3), 0.07, BRASS, segs=10)  # (the whistle's bell)
    add(k, p)
    # -- the headlamp on the smokebox's top, and two on the buffer beam
    p = k.piece("dark", "lampbox")
    for c, s in (((0, -4.55, BZ + 1.05), 1.0), ((-0.95, front - 0.02, 1.52), 0.7), ((0.95, front - 0.02, 1.52), 0.7)):
        c = Vector(c)
        bx(p, c, (0.42 * s, 0.38 * s, 0.5 * s), INK)
        bx(p, c + Vector((0, 0, 0.28 * s)), (0.5 * s, 0.46 * s, 0.06 * s), INK)
        cyl(p, c + Vector((0, 0, 0.3 * s)), c + Vector((0, 0, 0.42 * s)), 0.06 * s, INK, segs=8)
        cyl(p, c + Vector((0, -0.19 * s, 0)), c + Vector((0, -0.23 * s, 0)), 0.17 * s, BRASS, segs=14)
        bx(p, c + Vector((0, 0.02, -0.33 * s)), (0.1 * s, 0.1 * s, 0.18 * s), IRON)
    add(k, p)
    p = k.piece("window", "lamp")
    for c, s in (((0, -4.55, BZ + 1.05), 1.0), ((-0.95, front - 0.02, 1.52), 0.7), ((0.95, front - 0.02, 1.52), 0.7)):
        cyl(p, Vector(c) + Vector((0, -0.2 * s, 0)), Vector(c) + Vector((0, -0.24 * s, 0)), 0.13 * s, LAMP, segs=14)
    add(k, p)
    # -- cylinders, steam chests, the guides the crosshead slides in
    p = k.piece("dark", "cylinders")
    cy0, cy1 = -4.45, -3.45
    for sx in (-1, 1):
        x = sx * MAIN_X
        cyl(p, (x, cy0, DRIVER_R), (x, cy1, DRIVER_R), 0.3, INK, segs=20)
        for y in (cy0 - 0.04, cy1 - 0.02):
            cyl(p, (x, y, DRIVER_R), (x, y + 0.06, DRIVER_R), 0.33, INK_HI, segs=20)
        cyl(p, (x, cy0 - 0.08, DRIVER_R), (x, cy0 - 0.03, DRIVER_R), 0.22, STEEL, segs=16)  # (the front cover)
        bx(p, (x - sx * 0.05, (cy0 + cy1) * 0.5, DRIVER_R + 0.42), (0.36, 1.0, 0.36), INK)  # (the steam chest)
        bx(p, (x - sx * 0.05, (cy0 + cy1) * 0.5, DRIVER_R + 0.62), (0.4, 1.04, 0.05), INK_HI)
        p.obox((sx * 0.72, -3.9, 1.55), (0, 0, 1), (1, 0, 0), (0, 1, 0), (1.0, 0.12, 0.14), INK)  # (the steam pipe up into the smokebox)
        cyl(p, (x, cy1 + 0.05, DRIVER_R), (x, cy1 + 0.15, DRIVER_R), 0.12, STEEL, segs=10)  # (the gland)
        gy0, gy1 = cy1 + 0.1, -2.15
        for dz in (0.13, -0.13):  # (the guide bars)
            bx(p, (x, (gy0 + gy1) * 0.5, DRIVER_R + dz), (0.08, gy1 - gy0, 0.05), STEEL)
        bx(p, (sx * 0.85, gy1 + 0.05, DRIVER_R + 0.35), (0.3, 0.08, 0.6), INK)  # (the motion bracket)
        cyl(p, (sx * 0.85, cy0 + 0.2, DRIVER_R - 0.2), (sx * 0.85, cy0 + 0.2, DRIVER_R - 0.45), 0.035, IRON, segs=6)  # (drain cock)
    add(k, p)
    # -- running boards, valances, handrails, the air pump, sand pipes, the reversing rod
    p = k.piece("dark", "boards")
    for sx in (-1, 1):
        bx(p, (sx * 0.97, -1.0, deck), (0.62, 7.2, 0.05), INK)
        bx(p, (sx * 1.27, -1.0, deck - 0.1), (0.04, 7.2, 0.2), INK)  # (the valance)
        bx(p, (sx * 1.29, -1.0, deck - 0.1), (0.015, 7.1, 0.035), RED)  # (a lined edge)
        for y in (-4.0, -2.8, -1.6, -0.4, 0.8, 2.0):
            cyl(p, (sx * 0.78, y, BZ + 0.3), (sx * 0.86, y, BZ + 0.35), 0.022, STEEL, segs=6)
        cyl(p, (sx * 0.87, -4.3, BZ + 0.35), (sx * 0.87, 2.55, BZ + 0.35), 0.022, STEEL, segs=6)  # (the handrail)
        for y in (-0.9, 1.1):  # (sand pipes down to the treads)
            p.obox((sx * 0.68, y - 0.22, 1.2), (0, 0.25, -0.97), (1, 0, 0), (0, 0.97, 0.25), (0.9, 0.035, 0.035), IRON)
        bx(p, (sx * 1.0, -4.85, deck + 0.02), (0.55, 0.3, 0.04), INK)  # (a step at the front)
        cyl(p, (sx * 1.18, -4.82, deck), (sx * 1.18, -4.82, 0.9), 0.02, IRON, segs=5)  # (a step hung off the board)
        bx(p, (sx * 1.18, -4.82, 0.92), (0.26, 0.22, 0.035), IRON)
    p.obox((0.98, -0.5, deck + 0.35), (0, 1, 0), (1, 0, 0), (0, 0, 1), (5.4, 0.05, 0.05), IRON)  # (the reversing rod)
    # the air pump on the right by the smokebox, its pipes
    cyl(p, (1.0, -2.9, deck), (1.0, -2.9, deck + 0.95), 0.18, INK, segs=14)
    cyl(p, (1.0, -2.9, deck + 0.4), (1.0, -2.9, deck + 0.48), 0.2, STEEL, segs=14)
    cyl(p, (1.0, -2.9, deck + 0.95), (1.0, -2.9, deck + 1.02), 0.2, STEEL, segs=14)
    cyl(p, (1.0, -2.75, deck + 0.8), (0.8, -2.3, BZ + 0.2), 0.03, STEEL, segs=6)
    # the air reservoir slung on the left, injectors under the cab
    cyl(p, (-0.95, -2.4, deck + 0.27), (-0.95, -0.6, deck + 0.27), 0.22, INK, segs=14)
    for sx in (-1, 1):
        cyl(p, (sx * 0.72, 2.5, 1.4), (sx * 0.72, 2.5, 1.0), 0.06, BRASS, segs=8)
        cyl(p, (sx * 0.72, 2.5, 1.2), (sx * 0.72, 0.9, BZ - 0.55), 0.025, BRASS, segs=6)
    add(k, p)
    # -- the cab: sheet sides with a window and the cut-out to climb in, round front windows either
    # side of the boiler, an arched roof with a ventilator, the floor over the drag box
    cab0, cab1 = 2.75, 4.55
    ctop = 3.95
    p = k.piece("dark", "cab")
    for sx in (-1, 1):
        x = sx * 1.32
        bx(p, (x, (cab0 + 3.95) * 0.5, 1.95), (0.05, 3.95 - cab0, 0.95), INK)  # (below the window)
        bx(p, (x, cab0 + 0.17, 3.1), (0.05, 0.34, 1.3), INK)  # (front of the window)
        bx(p, (x, 3.85, 3.1), (0.05, 0.2, 1.3), INK)  # (behind it)
        bx(p, (x, (cab0 + 3.95) * 0.5, ctop - 0.07), (0.05, 3.95 - cab0, 0.14), INK)  # (over it)
        bx(p, (x, 4.42, 3.25), (0.05, 0.26, 1.42), INK)  # (the back pillar)
        bx(p, (x, 4.25, 1.55), (0.05, 0.6, 0.15), INK)  # (the sill of the cut-out)
        bx(p, (x + sx * 0.02, (cab0 + 3.95) * 0.5, 2.45), (0.02, 3.95 - cab0, 0.04), RED)  # (lining)
        bx(p, (x + sx * 0.03, 3.4, 2.47), (0.015, 0.95, 0.05), STEEL)  # (the window's ledge)
        cyl(p, (x + sx * 0.06, 4.1, 1.7), (x + sx * 0.06, 4.1, 3.0), 0.022, STEEL, segs=6)  # (grab rails)
        cyl(p, (x + sx * 0.06, 4.52, 1.7), (x + sx * 0.06, 4.52, 3.4), 0.022, STEEL, segs=6)
        steps(p, sx * 1.33, 4.3, 1.4, 2)
        bx(p, (x + sx * 0.03, 3.3, 2.05), (0.02, 0.62, 0.26), BRASS)  # (the number plate)
        bx(p, (x + sx * 0.04, 3.3, 2.05), (0.015, 0.5, 0.14), RED_DK)
        for z in (2.62, 3.58):  # (the window's wooden frame)
            bx(p, (x + sx * 0.03, 3.4, z), (0.03, 1.0, 0.07), (0.3, 0.2, 0.12))
        for y in (2.92, 3.88):
            bx(p, (x + sx * 0.03, y, 3.1), (0.03, 0.07, 1.0), (0.3, 0.2, 0.12))
    # the front sheet, round the boiler, its two round windows
    bx(p, (0, cab0, 3.55), (2.66, 0.05, 0.8), INK)
    for sx in (-1, 1):
        bx(p, (sx * 1.07, cab0, 2.3), (0.52, 0.05, 1.7), INK)
    for sx in (-1, 1):
        cyl(p, (sx * 0.72, cab0 - 0.04, 3.4), (sx * 0.72, cab0 + 0.04, 3.4), 0.24, STEEL, segs=16)
    arch(p, cab0 - 0.15, cab1 + 0.25, 1.42, ctop, 0.4, 0.05, INK_HI, n=12)
    bx(p, (0, 3.6, ctop + 0.42), (0.7, 0.9, 0.12), INK_HI)  # (the roof vent)
    for sx in (-1, 1):
        bx(p, (sx * 1.4, 3.65, ctop + 0.02), (0.06, cab1 - cab0 + 0.4, 0.06), STEEL)  # (the rain strip)
    bx(p, (0, (cab0 + cab1) * 0.5, 1.48), (2.6, cab1 - cab0, 0.06), (0.25, 0.2, 0.15))  # (the floor)
    add(k, p)
    p = k.piece("window", "cab")
    for sx in (-1, 1):
        bx(p, (sx * 1.31, 3.4, 3.1), (0.02, 0.92, 1.0), GLASS)
        cyl(p, (sx * 0.72, cab0 - 0.05, 3.4), (sx * 0.72, cab0 + 0.05, 3.4), 0.19, GLASS, segs=16)
    add(k, p)
    p = k.piece("plank", "cab")  # (the backhead's glow seen inside: firedoor, gauges, the seat boards)
    bx(p, (0, 2.85, 2.4), (1.2, 0.08, 1.2), (0.2, 0.17, 0.15))
    bx(p, (0, 2.82, 2.05), (0.4, 0.04, 0.3), (0.55, 0.22, 0.08))
    for sx in (-0.9, 0.9):
        bx(p, (sx, 4.0, 2.3), (0.45, 0.5, 0.05), WOOD)
    add(k, p)
    # -- the motion: the drivers, the rods
    for sx in (-1, 1):
        for i, y in enumerate(DRIVERS):
            driver(k, sx, y, pin_up=(sx < 0), main=(i == MAIN_AXLE))
    for sx in (-1, 1):
        up = sx < 0
        # the side rod, coupling all four pins, a boss round each
        p = k.piece("dark", "siderod")
        x = sx * ROD_X
        dz = CRANK if up else 0.0
        dy = 0.0 if up else -CRANK
        a = Vector((x, DRIVERS[0] + dy, DRIVER_R + dz))
        b = Vector((x, DRIVERS[-1] + dy, DRIVER_R + dz))
        bx(p, (a + b) * 0.5, (0.05, (b - a).length, 0.11), ROD)
        bx(p, (a + b) * 0.5 + Vector((0, 0, 0.06)), (0.05, (b - a).length - 0.3, 0.025), STEEL)
        for y in DRIVERS:
            cyl(p, (x - 0.03, y + dy, DRIVER_R + dz), (x + 0.03, y + dy, DRIVER_R + dz), 0.1, ROD, segs=14)
        add(k, p)
        # the main rod: along y, its big end at the pin end (+y), its little end at the crosshead;
        # its origin at its middle (train.gd sets it from pin and crosshead each frame)
        p = k.piece("dark", "mainrod")
        x = sx * MAIN_X
        pin = Vector((x, DRIVERS[MAIN_AXLE] + dy, DRIVER_R + dz))
        cross = Vector((x, pin.y - MAIN_ROD, DRIVER_R))
        mid_z = (pin.z + cross.z) * 0.5
        c = Vector((x, (pin.y + cross.y) * 0.5, mid_z))
        p.obox(c, (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.06, MAIN_ROD - 0.2, 0.1), ROD)
        cyl(p, (x - 0.035, c.y + MAIN_ROD * 0.5, mid_z), (x + 0.035, c.y + MAIN_ROD * 0.5, mid_z), 0.13, ROD, segs=14)
        bx(p, (x, c.y + MAIN_ROD * 0.5 - 0.05, mid_z), (0.07, 0.28, 0.24), ROD)
        cyl(p, (x - 0.035, c.y - MAIN_ROD * 0.5, mid_z), (x + 0.035, c.y - MAIN_ROD * 0.5, mid_z), 0.075, ROD, segs=12)
        add(k, p, c)
        # the crosshead between the guides, the piston rod forward into the cylinder; its origin on
        # its gudgeon pin
        p = k.piece("dark", "crosshead")
        cpos = Vector((x, cross.y, DRIVER_R))
        bx(p, cpos, (0.1, 0.32, 0.2), STEEL)
        bx(p, cpos + Vector((0, 0, 0.13)), (0.12, 0.36, 0.04), ROD)
        bx(p, cpos - Vector((0, 0, 0.13)), (0.12, 0.36, 0.04), ROD)
        cyl(p, cpos - Vector((0, 0.15, 0)), Vector((x, cy1 - 0.75, DRIVER_R)), 0.045, STEEL, segs=8)  # (long enough to stay in the gland at full stroke)
        add(k, p, cpos)
    finish(k)


def tender():
    k = kit("tender")
    rng = k.rng
    L = 3.15
    z0 = 1.3  # the tank's foot
    top = 2.85
    underframe(k, L, 1.06, beam=RED)
    p = k.piece("dark", "tank")
    bx(p, (0, 0.15, (z0 + top) * 0.5), (2.7, 2 * L - 0.5, top - z0), INK)
    bx(p, (0, 0.15, top + 0.02), (2.78, 2 * L - 0.42, 0.06), INK_HI)  # (the beading round its top)
    bx(p, (0, 0.15, z0 + 0.03), (2.78, 2 * L - 0.42, 0.08), INK_HI)
    for sx in (-1, 1):
        bx(p, (sx * 1.36, 0.15, (z0 + top) * 0.5), (0.015, 2 * L - 0.7, top - z0 - 0.35), (0.11, 0.11, 0.105))  # (the panel)
        bx(p, (sx * 1.365, 0.15, top - 0.2), (0.012, 2 * L - 0.7, 0.03), RED)  # (lining)
        bx(p, (sx * 1.365, 0.15, z0 + 0.2), (0.012, 2 * L - 0.7, 0.03), RED)
        for z in (z0 + 0.06, top - 0.02):
            rivets(p, (sx * 1.39, -L + 0.4, z), (sx * 1.39, L - 0.1, z), 22, INK_HI, 0.028)
        # the coal coping, flared out over the front half
        B.rbox(p, (sx * 1.47, -1.3, top + 0.22), (0, 1, 0), (sx * 0.45, 0, 0.9), (3.6, 0.48, 0.04), INK)
    bx(p, (0, -L + 0.3, top + 0.25), (2.7, 0.05, 0.5), INK)  # (the coal plate at the front)
    bx(p, (0, 0.5, top + 0.25), (2.7, 0.05, 0.5), INK)  # (the bunker's back)
    # the water filler and its lid, the tool boxes, a ladder up the back
    cyl(p, (0.5, 2.2, top), (0.5, 2.2, top + 0.22), 0.3, INK, segs=16)
    cyl(p, (0.5, 2.2, top + 0.22), (0.5, 2.2, top + 0.27), 0.33, INK_HI, segs=16)
    bx(p, (0.5, 1.9, top + 0.26), (0.08, 0.12, 0.05), STEEL)
    for sx in (-0.85, 0.85):
        bx(p, (sx, 1.1, top + 0.18), (0.8, 0.5, 0.32), INK)
        bx(p, (sx, 1.1, top + 0.36), (0.86, 0.56, 0.04), INK_HI)
    for sx in (-0.28, 0.28):
        bx(p, (sx, L - 0.05, 2.0), (0.04, 0.05, 1.9), STEEL)
    for i in range(6):
        bx(p, (0, L - 0.05, 1.2 + i * 0.3), (0.6, 0.04, 0.035), STEEL)
    for sx in (-1, 1):  # (grab rails and steps at the front corners)
        cyl(p, (sx * 1.4, -L + 0.35, 1.5), (sx * 1.4, -L + 0.35, 2.7), 0.022, STEEL, segs=6)
        cyl(p, (sx * 1.4, L - 0.3, 1.5), (sx * 1.4, L - 0.3, 2.7), 0.022, STEEL, segs=6)
        steps(p, sx * 1.33, -L + 0.4, 1.3, 2)
    bx(p, (0, -L - 0.05, 1.32), (2.2, 0.4, 0.05), (0.25, 0.2, 0.15))  # (the fall plate to the cab)
    add(k, p)
    # the coal heaped in the bunker, higher at the back
    p = k.piece("stone", "coal")
    for i in range(70):
        y = rng.uniform(-L + 0.4, 0.4)
        x = rng.uniform(-1.15, 1.15)
        z = top + 0.05 + (0.45 - abs(x) * 0.15) * (0.6 + 0.4 * (y + L) / (L + 0.4)) + rng.uniform(-0.05, 0.08)
        p.stone((x, y, z), (rng.uniform(0.2, 0.42), rng.uniform(0.2, 0.4), rng.uniform(0.15, 0.25)), color=jit(COAL, 0.4, rng), rng=rng)
    bx(p, (0, -L * 0.5 + 0.2, top + 0.15), (2.6, L - 0.1, 0.3), COAL)
    add(k, p)
    bogie(k, -1.75)
    bogie(k, 1.85)
    finish(k)


def vagon():
    """The coach the settlers ride in."""
    k = kit("vagon")
    rng = k.rng
    L = 4.45   # half the body's length
    pl = 0.7   # the platforms' depth
    z0, z1 = 1.25, 3.45  # the body's foot and eaves
    underframe(k, L + pl, 1.06, beam=RED_DK)
    p = k.piece("plank", "body")
    bx(p, (0, 0, (z0 + z1) * 0.5), (2.8, 2 * L, z1 - z0), COACH)
    for sx in (-1, 1):
        x = sx * 1.41
        # matchboard below the waist, panels above, a cream waist and eaves line
        for i in range(int(2 * L / 0.11)):
            y = -L + 0.06 + i * 0.11
            bx(p, (x, y, z0 + 0.55), (0.012, 0.025, 1.0), jit(COACH_DK, 0.05, rng))
        bx(p, (x + sx * 0.01, 0, z0 + 1.1), (0.03, 2 * L, 0.09), jit(COACH_DK, 0.03, rng))  # (the waist rail)
        bx(p, (x + sx * 0.01, 0, z1 - 0.08), (0.03, 2 * L, 0.12), jit(COACH_DK, 0.03, rng))
        bx(p, (x + sx * 0.008, 0, z0 + 0.02), (0.03, 2 * L, 0.1), COACH_DK)
        for i in range(8):  # (the window frames, cream, a mullion between)
            y = -L + 0.85 + i * (2 * L - 1.7) / 7
            bx(p, (x + sx * 0.015, y, z0 + 1.62), (0.03, 0.82, 0.07), CREAM)
            bx(p, (x + sx * 0.015, y, z0 + 2.07), (0.03, 0.82, 0.07), CREAM)
            for dy in (-0.39, 0.39):
                bx(p, (x + sx * 0.015, y + dy, z0 + 1.85), (0.03, 0.06, 0.52), CREAM)
            bx(p, (x + sx * 0.01, y, z0 + 2.27), (0.025, 0.7, 0.04), COACH_DK)  # (a drip over it)
        for sy in (-1, 1):
            bx(p, (x + sx * 0.01, sy * (L - 0.05), (z0 + z1) * 0.5), (0.03, 0.1, z1 - z0), COACH_DK)  # (the corner posts)
    for sy in (-1, 1):  # (the end walls, a door to the platform in each)
        y = sy * L
        bx(p, (0, y + sy * 0.01, z0 + 1.0), (0.85, 0.03, 1.95), jit(COACH_DK, 0.04, rng))
        bx(p, (0, y + sy * 0.03, z0 + 1.6), (0.5, 0.02, 0.5), GLASS)
        bx(p, (0.32, y + sy * 0.035, z0 + 1.0), (0.05, 0.03, 0.04), BRASS)
    add(k, p)
    p = k.piece("window", "side")
    for sx in (-1, 1):
        for i in range(8):
            y = -L + 0.85 + i * (2 * L - 1.7) / 7
            bx(p, (sx * 1.415, y, z0 + 1.85), (0.02, 0.72, 0.4), GLASS)
    for i in range(14):  # (the clerestory lights)
        y = -L + 0.6 + i * (2 * L - 1.2) / 13
        for sx in (-1, 1):
            bx(p, (sx * 0.66, y, z1 + 0.5), (0.02, 0.3, 0.14), GLASS)
    add(k, p)
    # the roof: lower arched decks either side, the clerestory along the middle, its own roof,
    # lamp tops and torpedo vents
    p = k.piece("dark", "roof")
    for sx in (-1, 1):
        B.rbox(p, (sx * 1.07, 0, z1 + 0.14), (0, 1, 0), (sx * 0.92, 0, -0.38), (2 * L + 2 * pl + 0.1, 0.92, 0.05), jit(TAR, 0.04, rng))
        bx(p, (sx * 0.66, 0, z1 + 0.5), (0.04, 2 * L + 0.4, 0.4), COACH_DK)
    arch(p, -L - pl - 0.05, L + pl + 0.05, 0.8, z1 + 0.7, 0.18, 0.04, TAR, n=8)
    for i in range(4):
        y = -L + 1.1 + i * (2 * L - 2.2) / 3
        cyl(p, (0, y, z1 + 0.85), (0, y, z1 + 1.0), 0.13, IRON, segs=10)
        cyl(p, (0, y, z1 + 1.0), (0, y, z1 + 1.05), 0.17, IRON, segs=10)
    for sy in (-1, 1):
        bx(p, (0, sy * (L + pl * 0.5), z1 + 0.32), (2.0, pl + 0.1, 0.04), jit(TAR, 0.04, rng))  # (the hood over the platform)
    add(k, p)
    # the open platforms: floor, railings, gates, steps down each side, a hand brake wheel
    p = k.piece("dark", "platforms")
    for sy in (-1, 1):
        y0 = sy * (L + pl * 0.5)
        bx(p, (0, y0, 1.27), (2.6, pl, 0.06), WOOD)
        bx(p, (0, sy * (L + pl), 2.25), (2.2, 0.04, 0.05), IRON)
        for x in (-1.05, -0.35, 0.35, 1.05):
            bx(p, (x, sy * (L + pl), 1.8), (0.035, 0.035, 0.95), IRON)
        bx(p, (0, sy * (L + pl), 1.6), (2.2, 0.03, 0.03), IRON)
        for sx in (-1, 1):
            cyl(p, (sx * 1.3, sy * (L + 0.05), 1.3), (sx * 1.3, sy * (L + 0.05), 3.3), 0.025, IRON, segs=6)
            cyl(p, (sx * 1.3, sy * (L + pl - 0.05), 1.3), (sx * 1.3, sy * (L + pl - 0.05), 3.3), 0.025, IRON, segs=6)
            steps(p, sx * 1.32, y0, 1.25, 3)
        cyl(p, (0.7, sy * (L + 0.2), 1.3), (0.7, sy * (L + 0.2), 2.2), 0.025, IRON, segs=6)
        B._ring(p, (0.7, sy * (L + 0.2), 2.2), (0, 0, 1), 0.17, 0.02, 0.025, IRON, n=12)
    add(k, p)
    bogie(k, -3.25)
    bogie(k, 3.25)
    finish(k)


def yuk():
    """The teplushka: a covered goods wagon, a stove inside for the folk it carries in winter."""
    k = kit("yuk")
    rng = k.rng
    L = 3.3
    z0, z1 = 1.24, 3.3
    underframe(k, L, 1.06, beam=OXIDE_DK)
    p = k.piece("plank", "body")
    bx(p, (0, 0, (z0 + z1) * 0.5), (2.74, 2 * L, z1 - z0), OXIDE)
    for sx in (-1, 1):
        x = sx * 1.38
        for i in range(int(2 * L / 0.16)):  # (vertical boards, each its own shade)
            y = -L + 0.08 + i * 0.16
            if abs(y) < 0.78:
                continue
            bx(p, (x, y, (z0 + z1) * 0.5), (0.02, 0.145, z1 - z0 - 0.04), jit(OXIDE, 0.07, rng))
        # the frame outside the boards: posts, a rail, braces (the wagon's skeleton)
        for y in (-L + 0.06, -1.95, -0.85, 0.85, 1.95, L - 0.06):
            bx(p, (x + sx * 0.03, y, (z0 + z1) * 0.5), (0.04, 0.1, z1 - z0), OXIDE_DK)
        bx(p, (x + sx * 0.03, 0, z1 - 0.05), (0.05, 2 * L, 0.1), OXIDE_DK)
        bx(p, (x + sx * 0.03, 0, z0 + 0.05), (0.05, 2 * L, 0.1), OXIDE_DK)
        for y0, y1 in ((-L + 0.06, -1.95), (-1.95, -0.85), (0.85, 1.95), (1.95, L - 0.06)):
            a = Vector((x + sx * 0.03, y0 if y0 < 0 else y1, z0 + 0.1))
            b = Vector((x + sx * 0.03, y1 if y0 < 0 else y0, z1 - 0.1))
            d = b - a
            B.rbox(p, (a + b) * 0.5, d, (1, 0, 0), (d.length, 0.04, 0.08), OXIDE_DK)
        # the sliding door: boards on a frame, its runner top and bottom, the handle, the seal
        bx(p, (x + sx * 0.07, 0.15, (z0 + z1) * 0.5 - 0.05), (0.04, 1.6, z1 - z0 - 0.15), jit(OXIDE, 0.05, rng))
        for i in range(10):
            bx(p, (x + sx * 0.09, -0.6 + i * 0.165, (z0 + z1) * 0.5 - 0.05), (0.012, 0.012, z1 - z0 - 0.2), OXIDE_DK)
        for z in (z0 + 0.1, (z0 + z1) * 0.5, z1 - 0.2):
            bx(p, (x + sx * 0.1, 0.15, z), (0.03, 1.6, 0.08), OXIDE_DK)
        p.obox((x + sx * 0.1, 0.15, (z0 + z1) * 0.5 - 0.05), (0, 0.8, 0.6), (1, 0, 0), (0, -0.6, 0.8), (1.9, 0.03, 0.07), OXIDE_DK)
        bx(p, (x + sx * 0.12, 0.0, z1 + 0.02), (0.04, 3.4, 0.07), IRON)
        bx(p, (x + sx * 0.12, 0.0, z0 - 0.02), (0.04, 3.4, 0.06), IRON)
        bx(p, (x + sx * 0.13, 0.9, (z0 + z1) * 0.5), (0.04, 0.05, 0.3), IRON)
        bx(p, (x + sx * 0.14, 0.95, (z0 + z1) * 0.5 + 0.05), (0.02, 0.06, 0.08), (0.7, 0.15, 0.1))
        # a stencilled patch (the wagon's number and what it's rated for), chalk scrawl
        bx(p, (x + sx * 0.06, -2.5, z0 + 1.05), (0.012, 0.75, 0.35), jit(OXIDE_DK, 0.03, rng))
        for i in range(3):
            bx(p, (x + sx * 0.068, -2.5, z0 + 1.15 - i * 0.1), (0.008, 0.55 - i * 0.12, 0.035), WHITE)
        bx(p, (x + sx * 0.05, 2.45, z0 + 0.95), (0.01, 0.6, 0.04), (0.78, 0.76, 0.7))
    for sy in (-1, 1):  # (the ends, boards across, a frame)
        y = sy * L
        for i in range(int((z1 - z0) / 0.16)):
            bx(p, (0, y + sy * 0.01, z0 + 0.08 + i * 0.16), (2.66, 0.02, 0.145), jit(OXIDE, 0.07, rng))
        for x in (-1.3, 0, 1.3):
            bx(p, (x, y + sy * 0.04, (z0 + z1) * 0.5), (0.1, 0.05, z1 - z0), OXIDE_DK)
        for i in range(6):  # (a ladder up the end)
            bx(p, (0.95, y + sy * 0.09, z0 + 0.2 + i * 0.33), (0.4, 0.03, 0.035), IRON)
        for sx in (0.76, 1.14):
            bx(p, (sx, y + sy * 0.09, (z0 + z1) * 0.5), (0.03, 0.03, z1 - z0), IRON)
    add(k, p)
    # the barred hatches high on the sides, shutters open
    p = k.piece("window", "hatch")
    for sx in (-1, 1):
        for y in (-2.45, 2.45):
            bx(p, (sx * 1.39, y, z1 - 0.42), (0.02, 0.5, 0.32), GLASS)
    add(k, p)
    p = k.piece("dark", "hatch")
    for sx in (-1, 1):
        for y in (-2.45, 2.45):
            for dy in (-0.15, 0.0, 0.15):
                bx(p, (sx * 1.41, y + dy, z1 - 0.42), (0.02, 0.025, 0.32), IRON)
            bx(p, (sx * 1.41, y + 0.43, z1 - 0.42), (0.04, 0.38, 0.34), OXIDE_DK)  # (the shutter, swung back)
    add(k, p)
    # the roof, arched, tarred over the boards; its stovepipe with a cap, soot down from it
    p = k.piece("dark", "roof")
    arch(p, -L - 0.12, L + 0.12, 1.47, z1, 0.32, 0.05, TAR, n=12)
    for sy in (-1, 1):
        bx(p, (0, sy * (L + 0.1), z1 + 0.18), (2.75, 0.04, 0.16), OXIDE_DK)
    cyl(p, (0.55, -1.9, z1 + 0.15), (0.55, -1.9, z1 + 1.15), 0.09, IRON, segs=10)
    cyl(p, (0.55, -1.9, z1 + 1.15), (0.55, -1.9, z1 + 1.23), 0.2, IRON, segs=10, taper=-0.4)  # (the cap)
    for t in (0.1, 0.25):  # (stays)
        cyl(p, (0.55, -1.9, z1 + 0.85), (0.55 + 0.45, -1.9 + (t - 0.17) * 3, z1 + 0.28), 0.01, IRON, segs=4)
    p2 = k.piece("dark", "soot")
    p2.obox((0.62, -1.9, z1 + 0.33), (0, 1, 0), (0.9, 0, -0.3), (0.3, 0, 0.9), (0.5, 0.9, 0.012), SOOT)
    add(k, p)
    add(k, p2)
    wagon_gear(k, (-1.95, 1.95), 0.45, 1.06, L)
    finish(k)


def platforma():
    """An open wagon: low board sides on stakes, logs chained down, a tarp over crates at one end."""
    k = kit("platforma")
    rng = k.rng
    L = 3.2
    z0 = 1.24
    underframe(k, L, 1.06, beam=OXIDE_DK)
    p = k.piece("plank", "deck")
    for i in range(int(2 * L / 0.2)):
        bx(p, (0, -L + 0.1 + i * 0.2, z0), (2.72, 0.19, 0.06), jit(WOOD_GREY, 0.08, rng))
    for sx in (-1, 1):
        for z in (z0 + 0.15, z0 + 0.38):
            bx(p, (sx * 1.36, 0, z), (0.05, 2 * L, 0.21), jit(WOOD, 0.06, rng))
    for sy in (-1, 1):
        for z in (z0 + 0.15, z0 + 0.38):
            bx(p, (0, sy * L, z), (2.72, 0.05, 0.21), jit(WOOD, 0.06, rng))
    add(k, p)
    p = k.piece("dark", "stakes")
    for sx in (-1, 1):
        for y in (-2.9, -1.45, 0.0, 1.45, 2.9):
            bx(p, (sx * 1.43, y, z0 + 0.6), (0.08, 0.08, 1.3), jit(WOOD, 0.08, rng))
            bx(p, (sx * 1.44, y, z0 + 0.0), (0.12, 0.12, 0.12), IRON)
            bx(p, (sx * 1.44, y, z0 + 0.4), (0.1, 0.11, 0.06), IRON)
    add(k, p)
    # the logs, along it, two tiers; the chains over them
    p = k.piece("log", "load")
    for i, (x, z) in enumerate([(-0.9, 0.2), (-0.3, 0.2), (0.3, 0.2), (0.9, 0.2), (-0.6, 0.7), (0.0, 0.7), (0.6, 0.7), (-0.3, 1.17), (0.3, 1.17)]):
        y0 = rng.uniform(-0.1, 0.1)
        p.log((x, -L + 1.25 + y0, z0 + 0.06 + z), (x, L - 0.15 + y0, z0 + 0.06 + z), 0.26 - (0.02 if z > 1 else 0), rng=rng, jitter=0.04)
    add(k, p)
    p = k.piece("dark", "chain")
    for y in (-0.8, 1.9):
        pts = [(-1.43, z0 + 1.2), (-1.1, z0 + 1.15), (-0.55, z0 + 1.62), (0.0, z0 + 1.72), (0.55, z0 + 1.62), (1.1, z0 + 1.15), (1.43, z0 + 1.2)]
        for (x0, za), (x1, zb) in zip(pts, pts[1:]):
            cyl(p, (x0, y, za), (x1, y, zb), 0.02, IRON, segs=5)
    add(k, p)
    # the front end: crates and sacks under a lashed tarp
    p = k.piece("plank", "crates")
    for x, y, s in ((-0.7, -2.6, 0.75), (0.5, -2.55, 0.85), (-0.1, -2.6, 0.6)):
        bx(p, (x, y, z0 + 0.03 + s * 0.5), (s, s * 0.9, s), jit(WOOD, 0.1, rng))
    add(k, p)
    p = k.piece("cloth", "tarp")
    bm = p.bm
    rows = []
    for i in range(6):
        y = -L + 0.1 + i * 0.22
        row = []
        for j in range(9):
            x = -1.42 + j * 2.84 / 8
            h = z0 + 0.95 + 0.12 * math.cos(x * 1.3) + 0.05 * math.sin(j * 1.7 + i)
            if abs(x) > 1.2:
                h = z0 + 0.95 - (abs(x) - 1.2) * 2.6
            row.append(bm.verts.new((x, y, h)))
        rows.append(row)
    faces = []
    for a, b in zip(rows, rows[1:]):
        for j in range(8):
            f = bm.faces.new((a[j], a[j + 1], b[j + 1], b[j]))
            f.smooth = True
            faces.append(f)
    for f in faces:
        f.normal_update()
        p._paint([f], jit(TARP, 0.06, rng))
    edge = rows[-1]
    hang = [bm.verts.new(v.co + Vector((0, 0.18, -0.55))) for v in edge]
    for j in range(8):
        f = bm.faces.new((edge[j], edge[j + 1], hang[j + 1], hang[j]))
        f.normal_update()
        p._paint([f], jit(TARP, 0.06, rng))
    add(k, p)
    p = k.piece("dark", "rope")
    for y in (-2.9, -2.3):
        cyl(p, (-1.43, y, z0 + 0.5), (0, y, z0 + 1.1), 0.014, (0.55, 0.46, 0.3), segs=5)
        cyl(p, (0, y, z0 + 1.1), (1.43, y, z0 + 0.5), 0.014, (0.55, 0.46, 0.3), segs=5)
    add(k, p)
    wagon_gear(k, (-1.9, 1.9), 0.45, 1.06, L)
    finish(k)


# --- by the line -----------------------------------------------------------------------------------

def tampon():
    """The buffer stop: two rails bent up and back into raked struts, a crib of sleepers between,
    the heavy beam across them painted red with a white band, a lamp disc on it."""
    k = kit("tampon")
    rng = k.rng
    p = k.piece("wood", "crib")
    for i in range(4):  # (a crib of old sleepers, laid crosswise, earth inside)
        z = 0.1 + i * 0.17
        y = 0.4 + i * 0.05
        for yy in (y, y + 1.1):
            p.box((0, yy, z), (2.4 - i * 0.12, 0.24, 0.16), jit((0.3, 0.24, 0.18), 0.1, rng))
        for sx in (-1, 1):
            p.box((sx * (1.08 - i * 0.06), y + 0.55, z + 0.085), (0.24, 1.3, 0.16), jit((0.3, 0.24, 0.18), 0.1, rng))
    add(k, p)
    p = k.piece("stone", "earth")
    for i in range(10):
        p.stone((rng.uniform(-0.8, 0.8), rng.uniform(0.6, 1.4), 0.6 + rng.uniform(-0.05, 0.05)), (0.5, 0.45, 0.25), color=jit((0.34, 0.31, 0.26), 0.1, rng), rng=rng)
    add(k, p)
    p = k.piece("dark", "struts")
    for sx in (-1, 1):
        x = sx * RAIL_X
        bx(p, (x, 0.3, 0.12), (0.08, 1.6, 0.14), IRON)  # (the rail run in)
        a, b = Vector((x, -0.25, 1.0)), Vector((x, 1.5, 0.15))
        d = b - a
        B.rbox(p, (a + b) * 0.5, d, (1, 0, 0), (d.length, 0.1, 0.14), IRON)  # (the raked strut)
        bx(p, (x, -0.22, 0.55), (0.12, 0.14, 0.95), IRON)  # (the upright)
        for z in (0.35, 0.7):
            bx(p, (x + sx * 0.07, -0.15 + (1.0 - z) * 0.3, z), (0.04, 0.12, 0.06), INK_HI)
    add(k, p)
    p = k.piece("wood", "beam")
    bx(p, (0, -0.42, 1.0), (2.6, 0.36, 0.42), RED)
    for x in (-0.2, 0.2):
        bx(p, (x, -0.61, 1.0), (0.4 if x < 0 else 0.4, 0.02, 0.42), WHITE)
    for sx in (-1, 1):
        bx(p, (sx * 0.87, -0.65, 1.0), (0.4, 0.08, 0.4), jit((0.3, 0.24, 0.18), 0.05, rng))  # (timber pads where the buffers strike)
        for dz in (-0.12, 0.12):
            bx(p, (sx * 0.87, -0.7, 1.0 + dz), (0.05, 0.02, 0.05), IRON)
    add(k, p)
    p = k.piece("dark", "lamp")
    cyl(p, (0, -0.3, 1.2), (0, -0.3, 1.75), 0.04, IRON, segs=6)
    cyl(p, (0, -0.33, 1.95), (0, -0.4, 1.95), 0.25, RED, segs=16)
    cyl(p, (0, -0.41, 1.95), (0, -0.43, 1.95), 0.2, WHITE, segs=16)
    add(k, p)
    finish(k)


def su_kulesi():
    """The water tower: a stone octagon with a door and a slit window, the boarded tank house over
    it jutting out on brackets, its eight-sided roof and the vent on top; the spout on its arm swung
    out over the track (toward -y), a chain to pull it down, a ladder."""
    k = kit("su_kulesi")
    rng = k.rng
    n = 8
    R0, H0 = 2.3, 3.6
    p = k.piece("stone", "base")
    course = 0.3
    for c in range(int(H0 / course)):
        z = c * course + course * 0.5
        for i in range(n):
            a0 = i / n * math.tau + math.pi / n
            a1 = (i + 1) / n * math.tau + math.pi / n
            pa = Vector((math.cos(a0), math.sin(a0), 0)) * R0
            pb = Vector((math.cos(a1), math.sin(a1), 0)) * R0
            side = pb - pa
            m = 3 if c % 2 == 0 else 4
            for j in range(m):
                t0 = (j + (0.5 if c % 2 else 0.0)) / m
                t1 = min((j + 1 + (0.5 if c % 2 else 0.0)) / m, 1.0)
                if t0 >= 1.0:
                    continue
                mid = pa + side * ((t0 + t1) * 0.5)
                out = Vector((mid.x, mid.y, 0)).normalized()
                p.obox((mid.x, mid.y, z), side.normalized(), out, (0, 0, 1), (side.length * (t1 - t0) - 0.03, 0.4, course - 0.03),
                       jit(rng.choice((STONE, (0.5, 0.47, 0.42), (0.6, 0.58, 0.53), (0.44, 0.43, 0.41))), 0.08, rng))
    bx(p, (0, 0, H0 * 0.5), (R0 * 1.75, R0 * 1.75, H0 - 0.1), (0.46, 0.44, 0.4))  # (the core, the mortar between)
    for i in range(n):  # (a dressed course at the top)
        a = (i + 0.5) / n * math.tau + math.pi / n
        out = Vector((math.cos(a), math.sin(a), 0))
        p.obox(out * (R0 + 0.05) + Vector((0, 0, H0 + 0.1)), Vector((-out.y, out.x, 0)), out, (0, 0, 1), (2 * R0 * math.tan(math.pi / n) + 0.1, 0.5, 0.2), jit((0.62, 0.6, 0.55), 0.04, rng))
    add(k, p)
    p = k.piece("plank", "door")
    bx(p, (0, R0 * math.cos(math.pi / n) + 0.04, 1.0), (0.95, 0.08, 2.0), jit(WOOD, 0.05, rng))
    for z in (0.4, 1.6):
        bx(p, (0, R0 * math.cos(math.pi / n) + 0.09, z), (0.9, 0.02, 0.07), IRON)
    bx(p, (0, R0 * math.cos(math.pi / n) + 0.05, 2.08), (1.15, 0.12, 0.16), jit((0.62, 0.6, 0.55), 0.04, rng))
    add(k, p)
    p = k.piece("window", "slit")
    for a in (math.pi * 0.25, math.pi * 1.25, math.pi * 0.75):
        out = Vector((math.cos(a), math.sin(a), 0))
        p.obox(out * (R0 * math.cos(math.pi / n) + 0.02) + Vector((0, 0, 2.3)), Vector((-out.y, out.x, 0)), out, (0, 0, 1), (0.2, 0.06, 0.6), GLASS)
    add(k, p)
    # the tank house: boards up the eight faces, jutting out on brackets, a sill band
    R1, H1 = 2.65, 3.0
    zb = H0 + 0.2
    p = k.piece("plank", "tankhouse")
    for i in range(n):
        a0 = i / n * math.tau + math.pi / n
        a1 = (i + 1) / n * math.tau + math.pi / n
        pa = Vector((math.cos(a0), math.sin(a0), 0)) * R1
        pb = Vector((math.cos(a1), math.sin(a1), 0)) * R1
        side = pb - pa
        out = Vector(((pa + pb).x, (pa + pb).y, 0)).normalized()
        nb = 9
        for j in range(nb):
            mid = pa + side * ((j + 0.5) / nb)
            p.obox((mid.x, mid.y, zb + H1 * 0.5), side.normalized(), out, (0, 0, 1), (side.length / nb - 0.012, 0.05, H1), jit(WOOD_GREY, 0.09, rng))
        mid = (pa + pb) * 0.5
        for z in (zb + 0.12, zb + H1 - 0.1):
            p.obox((mid.x + out.x * 0.04, mid.y + out.y * 0.04, z), side.normalized(), out, (0, 0, 1), (side.length + 0.06, 0.06, 0.12), jit(WOOD, 0.05, rng))
        # a corner post
        p.obox((pa.x * 1.01, pa.y * 1.01, zb + H1 * 0.5), side.normalized(), out, (0, 0, 1), (0.12, 0.1, H1), jit(WOOD, 0.05, rng))
        # a bracket under it, from the stone
        cb = Vector((math.cos(a0), math.sin(a0), 0))
        a, b = cb * (R0 + 0.05) + Vector((0, 0, H0 - 0.6)), cb * (R1 - 0.05) + Vector((0, 0, zb))
        d = b - a
        B.rbox(p, (a + b) * 0.5, d, Vector((-cb.y, cb.x, 0)), (d.length, 0.12, 0.12), jit(WOOD, 0.05, rng))
    bx(p, (0, 0, zb), (R1 * 1.9, R1 * 1.9, 0.12), jit(WOOD, 0.05, rng))  # (the floor under it)
    add(k, p)
    p = k.piece("window", "tank")
    out = Vector((0, -1, 0))
    p.obox((0, -R1 * math.cos(math.pi / n) - 0.03, zb + 1.9), (1, 0, 0), out, (0, 0, 1), (0.55, 0.04, 0.5), GLASS)
    add(k, p)
    # the roof: eight shingled faces up to a vent with its own little roof
    zr = zb + H1
    p = k.piece("shingle", "roof")
    R2, peak = R1 + 0.45, 2.0
    for i in range(n):
        a0 = i / n * math.tau + math.pi / n
        a1 = (i + 1) / n * math.tau + math.pi / n
        pa = Vector((math.cos(a0) * R2, math.sin(a0) * R2, zr - 0.15))
        pb = Vector((math.cos(a1) * R2, math.sin(a1) * R2, zr - 0.15))
        top = Vector((0, 0, zr + peak))
        rows = 6
        for r in range(rows):
            t0, t1 = r / rows, (r + 1) / rows
            qa0, qb0 = pa.lerp(top, t0), pb.lerp(top, t0)
            qa1, qb1 = pa.lerp(top, t1 + 0.03), pb.lerp(top, t1 + 0.03)
            B.slab(p, [qa0, qb0, qb1, qa1], 0.05, jit(B.SHINGLE, 0.1, rng))
    add(k, p)
    p = k.piece("wood", "vent")
    bx(p, (0, 0, zr + peak - 0.1), (0.5, 0.5, 0.7), jit(WOOD_GREY, 0.05, rng))
    p.obox((0, 0, zr + peak + 0.35), (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.8, 0.8, 0.08), jit(B.SHINGLE, 0.05, rng))
    cyl(p, (0, 0, zr + peak + 0.38), (0, 0, zr + peak + 0.8), 0.025, IRON, segs=6)
    add(k, p)
    # the spout: an iron pipe out of the tank house wall, hinged, its arm out over the track with a
    # leather sock hanging; the counterweight and chain
    p = k.piece("dark", "spout")
    sz = zb + 0.7
    y0 = -R1 * math.cos(math.pi / n) - 0.05
    cyl(p, (0, y0 + 0.2, sz), (0, y0 - 0.25, sz), 0.2, IRON, segs=12)  # (the outlet)
    cyl(p, (-0.18, y0 - 0.3, sz), (0.18, y0 - 0.3, sz), 0.08, INK_HI, segs=8)  # (the hinge)
    tip = Vector((0, -4.6, sz - 0.6))
    cyl(p, (0, y0 - 0.3, sz), tip, 0.16, IRON, segs=12, taper=0.1)
    cyl(p, tip, tip + Vector((0, -0.05, -0.85)), 0.15, (0.22, 0.16, 0.1), segs=10, taper=0.2)  # (the sock)
    cyl(p, (0, y0 - 0.3, sz + 0.1), (0, (y0 + tip.y) * 0.5, sz + 1.2), 0.025, IRON, segs=5)  # (the stay)
    cyl(p, (0, (y0 + tip.y) * 0.5, sz + 1.2), tip + Vector((0, 0, 0.15)), 0.025, IRON, segs=5)
    cyl(p, tip + Vector((0, 0, -0.02)), tip + Vector((0.0, 0.1, -3.2)), 0.012, IRON, segs=4)  # (the chain down)
    cyl(p, (0.25, y0 - 0.3, sz), (0.25, y0 + 0.3, sz + 0.5), 0.02, IRON, segs=4)
    bx(p, (0.25, y0 + 0.35, sz - 0.2), (0.22, 0.22, 0.35), INK_HI)  # (the counterweight)
    add(k, p)
    # a ladder up the stone to the tank house's hatch
    p = k.piece("wood", "ladder")
    lx = R0 * math.cos(math.pi / n) + 0.25
    for s in (-0.25, 0.25):
        bx(p, (lx, s, (zb + 0.4) * 0.5), (0.07, 0.07, zb + 0.4), jit(WOOD, 0.05, rng))
    for i in range(int(zb / 0.35)):
        bx(p, (lx, 0, 0.3 + i * 0.35), (0.05, 0.5, 0.04), jit(WOOD, 0.05, rng))
    add(k, p)
    finish(k)


def travers():
    """One sleeper: an adzed timber, two tie plates, spikes."""
    k = kit("travers")
    rng = k.rng
    p = k.piece("wood", "sleeper")
    p.box((0, 0, -0.075), (2.6, 0.24, 0.15), jit((0.33, 0.27, 0.2), 0.05, rng))
    for x in (-1.0, 1.0):
        p.box((x, 0.06, -0.003), (0.5, 0.06, 0.006), (0.27, 0.22, 0.16))  # (a check in its top)
    add(k, p)
    p = k.piece("dark", "plates")
    for sx in (-1, 1):
        bx(p, (sx * RAIL_X, 0, 0.01), (0.34, 0.18, 0.02), IRON)
        for dx in (-0.11, 0.11):
            for dy in (-0.05, 0.05):
                bx(p, (sx * RAIL_X + dx, dy, 0.035), (0.03, 0.03, 0.03), (0.13, 0.12, 0.11))
    add(k, p)
    finish(k)


BUILDERS = {"lokomotif": lokomotif, "tender": tender, "vagon": vagon, "yuk": yuk, "platforma": platforma,
            "tampon": tampon, "su_kulesi": su_kulesi, "travers": travers}


def render(kind):
    import bpy as b
    scene = b.context.scene
    for ob in list(scene.objects):
        if ob.type in ("CAMERA", "LIGHT"):
            b.data.objects.remove(ob, do_unlink=True)
    cam = b.data.objects.new("cam", b.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    size = {"lokomotif": 9.0, "su_kulesi": 11.0, "travers": 2.5, "tampon": 3.5}.get(kind, 7.5)
    look = Vector((0, 0, 1.6 if kind != "su_kulesi" else 4.5))
    cam.location = look + Vector((size * 1.1, -size * 1.0, size * 0.45))
    cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 40
    scene.camera = cam
    sun = b.data.objects.new("sun", b.data.lights.new("sun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    scene.collection.objects.link(sun)
    world = scene.world or b.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.7, 0.7, 0.68, 1)
        bg.inputs[1].default_value = 0.9
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 600
    out = os.environ.get("TRAIN_PREVIEWS", os.path.join(B.OUT, "previews"))
    os.makedirs(out, exist_ok=True)
    scene.render.filepath = os.path.join(out, kind + ".png")
    b.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--raw" in argv:
        for key in B.FINISH:
            B.FINISH[key] = False
    for a in argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
    for kind, fn in BUILDERS.items():
        if only and kind not in only:
            continue
        fn()
        if "--render" in argv:
            render(kind)


main()
