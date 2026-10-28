"""Builds the vehicle parts you put together in İnşa: each one a separate GLB sized to the build grid.

    blender --background --factory-startup --python tools/blender/build_parts.py [-- --render]

The grid cell is CELL (0.5 m). A part fills a box of cells (its footprint, PARTS below and the game's
scripts/parts.gd agree on it) and its GLB's origin is that box's centre. Blender: +X right, +Y forward
(Godot -Z), +Z up. Every part's attaching faces carry bolt flanges; wheels attach by their inner face (-X).

Output: assets/parts/<id>.glb, assets/parts/previews/*.png (--render).

  cab        2x2x2  the driver's cab: a steel shell, windscreen and side windows, a seat and the wheel
  frame      1x1x1  a square-tube steel lattice cube with gussets and bolt plates
  armor      1x1x1  a solid block of bolted armour plate
  wedge      1x1x1  a sloped armour wedge (high at the back, down to the front edge)
  wheel_s    1x2x2  a road wheel (r 0.38) on a swing arm with a coil-over; node Wheel spins and steers
  wheel_l    2x3x3  a big off-road wheel (r 0.62, lugged) on a heavy arm and twin dampers
  engine     2x2x2  a diesel engine (90 kW): block, head, radiator in front, a stack with a rain cap
  light      1x1x1  a work light on a bracket; node Glow is its lit lens
  minigun    2x1x2  a six-barrel rotary gun on a ring mount: Turret (turns about +Z) > Gun (elevates about +X)
                    > Barrels (spin about the bore), Muzzle at the barrels' end; an ammo can and its feed chute
  track      2x2x6  a track unit: five twin road wheels on swing arms (nodes Road0..4), the drive sprocket
                    at the back, the idler at the front (Sprocket, Idler), return rollers, a fender; the belt
                    (node Belt) one band whose UVs run along it in links, for the game to scroll and draw
  rockets    2x2x2  a six-tube rocket launcher: Turret > Gun (the pod), its rockets Rocket0..5 in the tubes
  battery    1x1x2  two 12 V blocks in a tray, cables and an isolator switch
  cannon     2x2x2  a 76 mm gun in a sloped armoured turret: Turret > Gun (the mantlet and barrel, a muzzle
                    brake), Muzzle at its end
"""

import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import build_truck as bt  # noqa: E402
import vehicle_kit as vk  # noqa: E402

from build_truck import PI, box, cyl, cyl_between, revolve, tube  # noqa: E402

CELL = 0.5
OUT_DIR = os.path.join(vk.ROOT, "assets", "parts")
PARTS = {"cab": (2, 2, 2), "frame": (1, 1, 1), "armor": (1, 1, 1), "wedge": (1, 1, 1), "wheel_s": (1, 2, 2),
         "wheel_l": (2, 3, 3), "engine": (2, 2, 2), "light": (1, 1, 1),
         "minigun": (2, 1, 2), "cannon": (2, 2, 2), "track": (2, 2, 6), "rockets": (2, 2, 2),
         "battery": (1, 1, 2)}


def materials():
    m = bt.make_mat
    m("Paint", (0.55, 0.36, 0.08), metal=0.25, rough=0.5)  # worn industrial yellow-ochre
    m("PaintDark", (0.12, 0.13, 0.12), metal=0.3, rough=0.55)
    m("Steel", (0.42, 0.42, 0.42), metal=0.9, rough=0.4)
    m("SteelDark", (0.06, 0.06, 0.065), metal=0.6, rough=0.5)
    m("Bolt", (0.3, 0.3, 0.29), metal=0.9, rough=0.35)
    m("Rubber", (0.025, 0.025, 0.025), rough=0.85)
    m("RubberSide", (0.04, 0.04, 0.04), rough=0.75)
    m("Rim", (0.2, 0.21, 0.2), metal=0.6, rough=0.45)
    m("Glass", (0.05, 0.08, 0.09), rough=0.05, metal=0.2, alpha=0.35)
    m("Seat", (0.07, 0.065, 0.06), rough=0.8)
    m("Spring", (0.6, 0.08, 0.05), metal=0.5, rough=0.35)
    m("Radiator", (0.04, 0.04, 0.04), metal=0.5, rough=0.6)
    m("Exhaust", (0.12, 0.08, 0.06), metal=0.7, rough=0.7)
    m("Lens", (0.85, 0.85, 0.8), rough=0.05, alpha=0.6)
    m("LensLit", (1.0, 0.92, 0.75), emit=(1.0, 0.9, 0.7), strength=18.0)
    m("Reflector", (0.85, 0.85, 0.85), metal=1.0, rough=0.1)
    m("Hazard", (0.05, 0.05, 0.05), rough=0.6)
    m("Slot", (0.008, 0.008, 0.008), rough=0.9)
    m("Track", (0.09, 0.085, 0.08), metal=0.7, rough=0.6)  # (the game draws the links over it)
    m("Olive", (0.2, 0.22, 0.12), metal=0.2, rough=0.6)
    m("Battery", (0.03, 0.03, 0.035), rough=0.55)
    m("BatteryLid", (0.12, 0.12, 0.13), rough=0.5)
    m("Terminal", (0.55, 0.04, 0.03), rough=0.5)
    m("TerminalNeg", (0.02, 0.02, 0.02), rough=0.5)
    m("Engine", (0.07, 0.16, 0.1), metal=0.35, rough=0.5)  # engine-green cast iron
    m("HeatWrap", (0.42, 0.38, 0.3), rough=0.9)


def ext(cells):
    """A footprint (Godot order: x across, y up, z along) in Blender metres (x, y forward, z up)."""
    return Vector((cells[0], cells[2], cells[1])) * CELL


def bolts(name, center, normal, span_u, span_v, n=2, grp="Part"):
    """A square of bolt heads on a face (normal one of the axes), inset from its edges."""
    c, nrm = Vector(center), Vector(normal)
    axes = [Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))]
    u, v = [a for a in axes if abs(a.dot(nrm)) < 0.5]
    k = 0
    for i in range(n):
        for j in range(n):
            fu = (i / (n - 1) - 0.5) * span_u if n > 1 else 0.0
            fv = (j / (n - 1) - 0.5) * span_v if n > 1 else 0.0
            p = c + u * fu + v * fv + nrm * 0.006
            cyl(f"{name}{k}", 0.014, 0.014, tuple(p), axis=tuple(nrm), segs=6, mat="Bolt", grp=grp)
            k += 1


def flange_faces(name, size, skip=(), grp="Part"):
    """Bolt squares on each of a block's faces (the attaching faces), but those in skip."""
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    faces = {"+x": ((hx, 0, 0), (1, 0, 0), size[1], size[2]), "-x": ((-hx, 0, 0), (-1, 0, 0), size[1], size[2]),
             "+y": ((0, hy, 0), (0, 1, 0), size[0], size[2]), "-y": ((0, -hy, 0), (0, -1, 0), size[0], size[2]),
             "+z": ((0, 0, hz), (0, 0, 1), size[0], size[1]), "-z": ((0, 0, -hz), (0, 0, -1), size[0], size[1])}
    for f, (c, n, su, sv) in faces.items():
        if f in skip:
            continue
        for cu in range(max(1, round(su / CELL))):
            for cv in range(max(1, round(sv / CELL))):
                # one bolt square per cell of the face
                off_u = (cu + 0.5) * CELL - su / 2
                off_v = (cv + 0.5) * CELL - sv / 2
                nv = Vector(n)
                axes = [Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))]
                u, v = [a for a in axes if abs(a.dot(nv)) < 0.5]
                bolts(f"{name}{f}{cu}{cv}", tuple(Vector(c) + u * off_u + v * off_v), n, CELL * 0.6, CELL * 0.6, grp=grp)


# --- Parts ---------------------------------------------------------------------------------------

def build_frame():
    s = CELL
    h = s / 2
    t = 0.045  # square tube
    for a in (-1, 1):
        for b in (-1, 1):
            box(f"EdgeZ{a}{b}", (t, t, s), (a * (h - t / 2), b * (h - t / 2), 0), "Paint", bev=0.004, grp="Part")
            box(f"EdgeY{a}{b}", (t, s - 2 * t, t), (a * (h - t / 2), 0, b * (h - t / 2)), "Paint", bev=0.004, grp="Part")
            box(f"EdgeX{a}{b}", (s - 2 * t, t, t), (0, a * (h - t / 2), b * (h - t / 2)), "Paint", bev=0.004, grp="Part")
    # diagonal braces on the sides, gussets in the corners
    for a in (-1, 1):
        cyl_between(f"BraceX{a}", (a * (h - t / 2), -h + t, -h + t), (a * (h - t / 2), h - t, h - t), 0.012, mat="Paint",
                    segs=6, grp="Part")
        cyl_between(f"BraceY{a}", (-h + t, a * (h - t / 2), -h + t), (h - t, a * (h - t / 2), h - t), 0.012, mat="Paint",
                    segs=6, grp="Part")
    # bolt plates centred on each face
    for n in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
        nv = Vector(n)
        sz = [0.2, 0.2, 0.2]
        sz[[abs(x) for x in n].index(1)] = 0.012
        box(f"Plate{n}", tuple(sz), tuple(nv * (h - 0.006)), "SteelDark", bev=0.002, grp="Part")
        bolts(f"PlateBolt{n}", tuple(nv * (h - 0.006)), n, 0.13, 0.13, grp="Part")


def build_armor():
    s = CELL
    box("Block", (s - 0.01, s - 0.01, s - 0.01), (0, 0, 0), "Paint", bev=0.03, seg=2, grp="Part")
    # an applied plate on each side, slightly proud, with its bolts
    for n in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
        nv = Vector(n)
        sz = [s - 0.08] * 3
        sz[[abs(x) for x in n].index(1)] = 0.02
        box(f"Applique{n}", tuple(sz), tuple(nv * (s / 2 - 0.002)), "Paint", bev=0.006, grp="Part")
        bolts(f"AppBolt{n}", tuple(nv * (s / 2 + 0.008)), n, s - 0.16, s - 0.16, grp="Part")
    # hazard stripe on the front edge
    box("Stripe", (s - 0.1, 0.022, 0.06), (0, s / 2 + 0.011, s / 2 - 0.08), "Hazard", grp="Part")


def build_wedge():
    s = CELL
    h = s / 2
    # profile in the Y-Z plane (high at the back, -Y), extruded along X
    prof = [(-h, -h), (h, -h), (-h, h)]
    verts = [(x, y, z) for x in (-h, h) for (y, z) in prof]
    faces = [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
    ob = bt.mk("Wedge", verts, faces, ("Paint",), grp="Part", smooth=0)
    bt.bevel(ob, 0.015, 2)
    # bolts on the slope, the back and the bottom
    n = Vector((0, 1, 1)).normalized()
    for i in (-1, 1):
        for j in (-1, 1):
            p = Vector((i * 0.15, j * 0.12, -j * 0.12)) + n * 0.006  # (on the slope: z = -y)
            cyl(f"SlopeBolt{i}{j}", 0.014, 0.014, tuple(p), axis=tuple(n), segs=6, mat="Bolt", grp="Part")
    bolts("BackBolt", (0, -h, 0), (0, -1, 0), 0.3, 0.3, grp="Part")
    bolts("BottomBolt", (0, 0, -h), (0, 0, -1), 0.3, 0.3, grp="Part")
    box("Stripe", (s - 0.1, 0.02, 0.05), (0, h - 0.06, -h + 0.07), "Hazard", rot=(PI / 4, 0, 0), grp="Part")


def tyre(name, r, w, lugs, grp, lug_depth):
    """A tyre round local X at the origin: carcass, tread blocks, sidewall; a steel rim with a hub."""
    rin = r * 0.62
    prof = [(-w / 2, rin), (-w / 2, r - 0.05), (-w * 0.42, r - lug_depth), (w * 0.42, r - lug_depth), (w / 2, r - 0.05),
            (w / 2, rin)]
    revolve(f"{name}Carcass", prof, 40, ("RubberSide",), axis="X", grp=grp, smooth=40)
    for k in range(lugs):
        a = k * 2 * PI / lugs
        for side in (-1, 1):
            # chevron lugs: two blocks per pitch, staggered
            off = side * w * 0.22
            ang = a + (PI / lugs if side > 0 else 0.0)
            c = Vector((off, math.cos(ang) * (r - lug_depth / 2), math.sin(ang) * (r - lug_depth / 2)))
            box(f"{name}Lug{k}{side}", (w * 0.38, lug_depth, r * 0.16), tuple(c), "Rubber", rot=(ang - PI / 2, 0, side * 0.25),
                bev=0.006, grp=grp)
    rim = [(-w * 0.45, rin + 0.005), (-w * 0.3, rin * 0.92), (-w * 0.1, rin * 0.5), (w * 0.05, rin * 0.45), (w * 0.05, 0.0)]
    revolve(f"{name}Rim", rim, 32, ("Rim",), axis="X", grp=grp, smooth=40)
    cyl(f"{name}Hub", rin * 0.28, w * 0.3, (-w * 0.12, 0, 0), axis="X", segs=16, mat="Steel", grp=grp)
    for k in range(6):
        a = k * PI / 3
        cyl(f"{name}Nut{k}", 0.016, 0.03, (-w * 0.28, math.cos(a) * rin * 0.19, math.sin(a) * rin * 0.19), axis="X", segs=6,
            mat="Bolt", grp=grp)


def build_wheel(kind):
    fx, fy, fz = ext(PARTS[kind])
    big = kind == "wheel_l"
    r, w = (0.62, 0.42) if big else (0.38, 0.26)
    # hub at the footprint's centre, a little outboard; the mount flange on the inner face (-X)
    hub = Vector((fx / 2 - w / 2 - 0.02, 0, 0))
    tyre("Tyre", r, w, 18 if big else 14, "Wheel", 0.07 if big else 0.035)
    # the mount: a plate bolted to the hull, a trailing arm to the hub, a coil-over to the top
    mx = -fx / 2 + 0.015
    box("MountPlate", (0.03, CELL * 0.9, CELL * 0.9), (mx, 0, 0), "SteelDark", bev=0.005, grp="Part")
    bolts("MountBolt", (mx - 0.016, 0, 0), (-1, 0, 0), CELL * 0.6, CELL * 0.6, grp="Part")
    arm_w = 0.07 if big else 0.05
    box("Bracket", (0.12, 0.16, 0.2), (mx + 0.07, 0, 0.02), "Paint", bev=0.01, grp="Part")
    tube("Arm", [(mx + 0.1, 0.0, 0.0), (hub.x - w / 2 - 0.05, -0.05, -0.02)], arm_w * 0.5, mat="Paint", nring=10, sub=1,
         grp="Part")
    top = (mx + 0.1, 0.0, min(fz / 2 - 0.06, r * 0.75))
    low = (hub.x - w / 2 - 0.06, 0.0, 0.02)
    for dy in ((-0.07, 0.07) if big else (0.0,)):
        a, b = Vector(top) + Vector((0, dy, 0)), Vector(low) + Vector((0, dy, 0))
        cyl_between(f"Damper{dy}", tuple(a), tuple(a.lerp(b, 0.55)), 0.028 if big else 0.022, mat="SteelDark", segs=12,
                    grp="Part")
        cyl_between(f"Rod{dy}", tuple(a.lerp(b, 0.5)), tuple(b), 0.012, mat="Steel", segs=8, grp="Part")
        turns = 7
        pts = []
        d = (b - a)
        ax = d.normalized()
        side = ax.cross(Vector((0, 1, 0))).normalized()
        up = ax.cross(side)
        rad = 0.045 if big else 0.035
        for i in range(turns * 10 + 1):
            t = i / (turns * 10)
            ang = t * turns * 2 * PI
            pts.append(tuple(a + d * (0.12 + t * 0.7) + side * math.cos(ang) * rad + up * math.sin(ang) * rad))
        tube(f"Coil{dy}", pts, 0.006 if big else 0.005, mat="Spring", nring=5, sub=1, grp="Part")
    # the wheel node: placed at the hub
    for o in [o for o in bpy.data.objects if o.get("grp") == "Wheel"]:
        o.location = Vector(o.location) + hub
    return hub


def build_cab():
    sx, sy, sz = ext(PARTS["cab"])
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    t = 0.04
    # floor, back, sides (lower), roof; posts round the glass
    box("Floor", (sx, sy, t), (0, 0, -hz + t / 2), "PaintDark", bev=0.005, grp="Part")
    box("Back", (sx, t, sz), (0, -hy + t / 2, 0), "Paint", bev=0.01, grp="Part")
    box("Roof", (sx, sy, t), (0, 0, hz - t / 2), "Paint", bev=0.012, grp="Part")
    for s in (-1, 1):
        box(f"SideLow{s}", (t, sy, sz * 0.45), (s * (hx - t / 2), 0, -hz + sz * 0.225), "Paint", bev=0.01, grp="Part")
        box(f"PostF{s}", (0.06, 0.06, sz * 0.55), (s * (hx - 0.03), hy - 0.03, hz - sz * 0.275), "Paint", bev=0.008, grp="Part")
        box(f"PostB{s}", (0.06, 0.06, sz * 0.55), (s * (hx - 0.03), -hy + 0.03, hz - sz * 0.275), "Paint", bev=0.008, grp="Part")
        box(f"SideGlass{s}", (0.008, sy - 0.12, sz * 0.5), (s * (hx - 0.02), 0, hz - sz * 0.29), "Glass", grp="Part")
        # grab rail and a mirror
        cyl_between(f"Grab{s}", (s * (hx + 0.03), -0.25, hz - 0.15), (s * (hx + 0.03), 0.2, hz - 0.15), 0.012, mat="Steel",
                    segs=8, grp="Part")
        box(f"Mirror{s}", (0.03, 0.12, 0.16), (s * (hx + 0.12), hy - 0.1, hz - 0.3), "PaintDark", bev=0.01, grp="Part")
        cyl_between(f"MirrorArm{s}", (s * hx, hy - 0.1, hz - 0.25), (s * (hx + 0.11), hy - 0.1, hz - 0.28), 0.008,
                    mat="Steel", segs=6, grp="Part")
    box("Dash", (sx - 0.1, 0.2, sz * 0.45), (0, hy - 0.1, -hz + sz * 0.225), "Paint", bev=0.01, grp="Part")
    box("Windscreen", (sx - 0.1, 0.008, sz * 0.5), (0, hy - 0.02, hz - sz * 0.29), "Glass", rot=(0.08, 0, 0), grp="Part")
    box("WinBar", (0.04, 0.03, sz * 0.5), (0, hy - 0.025, hz - sz * 0.29), "Paint", grp="Part")
    # inside: the seat, the wheel, two gauges
    box("SeatBase", (0.4, 0.4, 0.08), (0, -0.12, -hz + 0.3), "Seat", bev=0.03, grp="Part")
    box("SeatBack", (0.4, 0.08, 0.45), (0, -0.33, -hz + 0.55), "Seat", rot=(-0.15, 0, 0), bev=0.03, grp="Part")
    revolve("SteerWheel", [(-0.012, 0.13), (0.012, 0.13), (0.012, 0.15), (-0.012, 0.15)], 24, ("Seat",),
            axis=(0.0, -0.6, 0.8), center=(0, hy - 0.25, -hz + 0.62), grp="Part")
    cyl_between("Column", (0, hy - 0.12, -hz + 0.45), (0, hy - 0.25, -hz + 0.62), 0.02, mat="SteelDark", segs=8, grp="Part")
    for i in (-1, 1):
        cyl(f"Gauge{i}", 0.04, 0.02, (i * 0.18, hy - 0.2, -hz + 0.46), axis=(0, -0.5, 0.86), segs=16, mat="Steel", grp="Part")
    # roof: a hatch, a beacon, a cage over the windscreen
    box("Hatch", (0.4, 0.4, 0.03), (0, -0.1, hz + 0.01), "PaintDark", bev=0.01, grp="Part")
    cyl("Beacon", 0.06, 0.1, (0.35, -0.35, hz + 0.05), segs=16, mat="Spring", grp="Part")
    for k in range(4):
        x = -hx + 0.1 + k * (sx - 0.2) / 3
        cyl_between(f"Cage{k}", (x, hy + 0.04, -hz + sz * 0.46), (x, hy + 0.04, hz - 0.03), 0.012, mat="SteelDark", segs=6,
                    grp="Part")
    flange_faces("Flange", (sx, sy, sz), skip=("+z", "+y"), grp="Part")


def build_light():
    s = CELL
    h = s / 2
    box("Base", (s * 0.6, s * 0.6, 0.03), (0, 0, -h + 0.015), "SteelDark", bev=0.004, grp="Part")
    bolts("BaseBolt", (0, 0, -h + 0.03), (0, 0, 1), s * 0.45, s * 0.45, grp="Part")
    for x in (-1, 1):
        box(f"Yoke{x}", (0.02, 0.05, 0.22), (x * 0.13, 0, -h + 0.13), "SteelDark", grp="Part")
    revolve("Housing", [(-0.1, 0.0), (-0.1, 0.09), (-0.05, 0.11), (0.06, 0.11), (0.08, 0.1)], 24, ("Paint",), axis="Y",
            center=(0, 0, -h + 0.22), grp="Part")
    revolve("ReflectorIn", [(0.075, 0.098), (0.0, 0.07), (-0.05, 0.02)], 24, ("Reflector",), axis="Y", center=(0, 0, -h + 0.22),
            grp="Part")
    cyl("Lens", 0.1, 0.01, (0, 0.08, -h + 0.22), axis="Y", segs=24, mat="Lens", grp="Part")
    cyl("LensLit", 0.096, 0.006, (0, 0.078, -h + 0.22), axis="Y", segs=24, mat="LensLit", grp="Glow")
    for k in range(3):
        box(f"Guard{k}", (0.2, 0.008, 0.008), (0, 0.095, -h + 0.16 + k * 0.06), "SteelDark", grp="Part")


# Turrets: node pivots (Blender space), filled in by each builder for main().
PIVOTS = {}


def build_minigun():
    sx, sy, sz = ext(PARTS["minigun"])
    hz = sz / 2
    box("BasePlate", (sx * 0.9, sy * 0.9, 0.03), (0, 0, -hz + 0.015), "SteelDark", bev=0.005, grp="Part")
    bolts("BaseBolt", (0, 0, -hz + 0.03), (0, 0, 1), sx * 0.7, sy * 0.7, grp="Part")
    cyl("Ring", 0.3, 0.08, (0, 0, -hz + 0.07), segs=28, mat="Paint", bev=0.01, grp="Part")
    yaw_z = -hz + 0.11
    # the turret: a turntable, two yoke arms, a shield
    cyl("Table", 0.27, 0.04, (0, 0, yaw_z + 0.02), segs=28, mat="SteelDark", grp="Turret")
    trun = Vector((0, 0, yaw_z + 0.26))
    for s in (-1, 1):
        box(f"Yoke{s}", (0.04, 0.16, 0.26), (s * 0.17, 0, yaw_z + 0.15), "Paint", bev=0.01, grp="Turret")
    box("Shield", (0.5, 0.02, 0.28), (0, 0.24, yaw_z + 0.2), "Paint", rot=(0.25, 0, 0), bev=0.008, grp="Turret")
    # the gun: receiver, motor, ammo can and chute; trunnion pins
    box("Receiver", (0.2, 0.36, 0.16), (0, -0.02, trun.z), "SteelDark", bev=0.015, grp="Gun")
    cyl("Motor", 0.05, 0.12, (0.0, -0.24, trun.z + 0.02), axis="Y", segs=14, mat="Steel", grp="Gun")
    box("AmmoCan", (0.14, 0.24, 0.18), (-0.2, -0.08, trun.z - 0.04), "Paint", bev=0.01, grp="Gun")
    tube("Chute", [(-0.14, -0.02, trun.z + 0.04), (-0.08, 0.02, trun.z + 0.07), (-0.03, 0.05, trun.z + 0.06)], 0.025,
         mat="SteelDark", nring=8, sub=4, grp="Gun")
    cyl("Trunnion", 0.03, 0.38, tuple(trun), axis="X", segs=10, mat="Steel", grp="Gun")
    # the barrels: six round the bore, three clamps, a spindle
    bore = Vector((0, 0.16, trun.z))
    for k in range(6):
        a = k * PI / 3
        o = Vector((math.cos(a) * 0.04, 0, math.sin(a) * 0.04))
        cyl(f"Barrel{k}", 0.012, 0.78, tuple(bore + o + Vector((0, 0.39, 0))), axis="Y", segs=8, mat="SteelDark",
            grp="Barrels")
    for y in (0.08, 0.5, 0.76):
        cyl(f"Clamp{y}", 0.06, 0.03, tuple(bore + Vector((0, y, 0))), axis="Y", segs=16, mat="Steel", grp="Barrels")
    cyl("Spindle", 0.022, 0.8, tuple(bore + Vector((0, 0.4, 0))), axis="Y", segs=10, mat="Steel", grp="Barrels")
    PIVOTS.update({"Turret": (0, 0, yaw_z), "Gun": tuple(trun), "Barrels": tuple(bore),
                   "Muzzle": tuple(bore + Vector((0, 0.8, 0)))})


def build_cannon():
    sx, sy, sz = ext(PARTS["cannon"])
    hz = sz / 2
    box("BasePlate", (sx * 0.95, sy * 0.95, 0.04), (0, 0, -hz + 0.02), "SteelDark", bev=0.006, grp="Part")
    bolts("BaseBolt", (0, 0, -hz + 0.04), (0, 0, 1), sx * 0.75, sy * 0.75, grp="Part")
    cyl("Ring", 0.44, 0.1, (0, 0, -hz + 0.09), segs=32, mat="SteelDark", bev=0.01, grp="Part")
    yaw_z = -hz + 0.14
    # the turret: a sloped armoured box (a frustum), a hatch, a periscope, stowage
    lo, hi = 0.0, 0.42
    bw, bl, tw, tl = 0.46, 0.5, 0.36, 0.38
    vs = [(-bw, -bl, lo), (bw, -bl, lo), (bw, bl * 0.8, lo), (-bw, bl * 0.8, lo),
          (-tw, -tl, hi), (tw, -tl, hi), (tw, tl * 0.6, hi), (-tw, tl * 0.6, hi)]
    vs = [(x, y, z + yaw_z) for (x, y, z) in vs]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    tur = bt.mk("TurretBody", vs, faces, ("Paint",), grp="Turret", smooth=0)
    bt.bevel(tur, 0.02, 2)
    cyl("Hatch", 0.13, 0.04, (-0.12, -0.12, yaw_z + hi + 0.02), segs=20, mat="PaintDark", grp="Turret")
    box("Periscope", (0.08, 0.06, 0.1), (0.15, 0.1, yaw_z + hi + 0.05), "SteelDark", grp="Turret")
    box("Stowage", (0.6, 0.18, 0.16), (0, -bl - 0.06, yaw_z + 0.18), "PaintDark", bev=0.02, grp="Turret")
    for k in range(3):
        cyl_between(f"Rail{k}", (-0.3 + k * 0.3, -bl - 0.15, yaw_z + 0.1), (-0.3 + k * 0.3, -bl - 0.15, yaw_z + 0.3),
                    0.01, mat="Steel", segs=6, grp="Turret")
    for x in (-0.38, 0.38):
        for y in (-0.3, 0.2):
            cyl(f"TBolt{x}{y}", 0.016, 0.014, (x * 0.9, y, yaw_z + hi + 0.005), segs=6, mat="Bolt", grp="Turret")
    trun = Vector((0, bl * 0.7, yaw_z + 0.22))
    # the gun: the mantlet, the barrel, a fume extractor, the muzzle brake
    box("Mantlet", (0.34, 0.14, 0.26), tuple(trun + Vector((0, 0.06, 0))), "Paint", bev=0.03, grp="Gun")
    cyl("Barrel", 0.045, 1.5, tuple(trun + Vector((0, 0.85, 0))), axis="Y", segs=16, mat="SteelDark", grp="Gun")
    cyl("Extractor", 0.07, 0.24, tuple(trun + Vector((0, 0.8, 0))), axis="Y", segs=18, mat="SteelDark", bev=0.01,
        grp="Gun")
    cyl("Brake", 0.075, 0.16, tuple(trun + Vector((0, 1.55, 0))), axis="Y", segs=18, mat="Steel", bev=0.01, grp="Gun")
    for s in (-1, 1):
        box(f"BrakePort{s}", (0.02, 0.06, 0.08), tuple(trun + Vector((s * 0.07, 1.55, 0))), "Slot", grp="Gun")
    PIVOTS.update({"Turret": (0, 0, yaw_z), "Gun": tuple(trun), "Muzzle": tuple(trun + Vector((0, 1.64, 0)))})


def turret_nodes():
    """Turret > Gun > Barrels (if any) > Muzzle, each about its pivot, parented in turn."""
    out = []
    parent = None
    for grp in ("Turret", "Gun", "Barrels"):
        if not any(o.get("grp") == grp for o in bpy.data.objects):
            continue
        ob = bt.bake_group(grp, grp, PIVOTS[grp])
        if parent:
            ob.parent = parent
            ob.location = Vector(PIVOTS[grp]) - Vector(PIVOTS[parent.name])
        out.append(ob)
        parent = ob
    for k in range(12):
        g = f"Rocket{k}"
        if any(o.get("grp") == g for o in bpy.data.objects):
            ob = bt.bake_group(g, g, PIVOTS[g])
            ob.parent = parent
            ob.location = Vector(PIVOTS[g]) - Vector(PIVOTS[parent.name])
    mz = vk.empty("Muzzle", PIVOTS["Muzzle"])
    mz.parent = parent
    mz.location = Vector(PIVOTS["Muzzle"]) - Vector(PIVOTS[parent.name])
    out.append(mz)
    return out



# --- Tracks, rockets, the battery, the engine (second batch) ------------------------------------

TRACK_ROADS = [0.9, 0.45, 0.0, -0.45, -0.9]  # road wheels along the track (Blender y: forward)
TRACK = {"x0": 0.08, "x1": 0.48, "t": 0.045, "hub_z": -0.26, "road_r": 0.17,
         "sprocket": (-1.2, -0.02, 0.22), "idler": (1.22, -0.07, 0.19), "rollers": [(0.45, 0.17, 0.06), (-0.45, 0.17, 0.06)]}


def _hull(pts):
    """Convex hull (y, z) of points, clockwise, starting anywhere (monotone chain)."""
    pts = sorted(set(pts))
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    ccw = lower[:-1] + upper[:-1]
    return list(reversed(ccw))  # clockwise


def belt_path(step=0.03):
    """The belt's inner face round the sprocket, the idler, under the road wheels and over the
    return rollers: their circles' hull (tangents and arcs), resampled evenly, clockwise seen from +x
    (so along the bottom it runs front to back: the way the ground goes past when it drives forward)."""
    circles = [TRACK["sprocket"], TRACK["idler"]] + [(y, TRACK["hub_z"], TRACK["road_r"]) for y in TRACK_ROADS]
    circles += TRACK["rollers"]
    pts = []
    for (cy, cz, r) in circles:
        for k in range(96):
            a = k * 2 * PI / 96
            pts.append((round(cy + math.cos(a) * r, 5), round(cz + math.sin(a) * r, 5)))
    hull = [Vector((0.0, p[0], p[1])) for p in _hull(pts)]
    n = len(hull)
    lens = [(hull[(i + 1) % n] - hull[i]).length for i in range(n)]
    total = sum(lens)
    m = max(8, round(total / step))
    out, i, acc = [], 0, 0.0
    for k in range(m):
        s = total * k / m
        while acc + lens[i] < s:
            acc += lens[i]
            i += 1
        f = (s - acc) / max(lens[i], 1e-9)
        out.append(hull[i].lerp(hull[(i + 1) % n], f))
    return out, total


def build_belt(name="Belt", grp="Belt"):
    """The belt as one closed band: outer (tread, UV u 0..0.45), inner (0.55..1), its edges (0.5).
    v runs along it in links (PITCH m each, a whole number of them round), so a shader can scroll
    it and draw the plates, grousers and guide horns."""
    import bmesh
    path, total = belt_path()
    links = round(total / 0.15)
    t = TRACK["t"]
    x0, x1 = TRACK["x0"], TRACK["x1"]
    n = len(path)
    # outward normals (the path is clockwise in y-z seen from +x: outward = tangent turned)
    normals = []
    for i in range(n):
        tg = (path[(i + 1) % n] - path[i - 1]).normalized()
        normals.append(Vector((0.0, -tg.z, tg.y)))
    # (check: at the bottom the tangent runs -y, the normal must point -z)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    rows = []  # per ring: inner x0, inner x1, outer x1, outer x0
    for i in range(n):
        p, nr = path[i], normals[i]
        rows.append([bm.verts.new((x0, p.y, p.z)), bm.verts.new((x1, p.y, p.z)),
                     bm.verts.new((x1, p.y + nr.y * t, p.z + nr.z * t)), bm.verts.new((x0, p.y + nr.y * t, p.z + nr.z * t))])
    us = {"in": (0.55, 1.0), "out": (0.0, 0.45)}
    for i in range(n):
        j = (i + 1) % n
        v0 = links * i / n
        v1 = links * (i + 1) / n
        a, b = rows[i], rows[j]
        quads = [((a[1], a[0], b[0], b[1]), "in"), ((a[3], a[2], b[2], b[3]), "out"),
                 ((a[0], a[3], b[3], b[0]), "edge"), ((a[2], a[1], b[1], b[2]), "edge")]
        for vs, kind in quads:
            try:
                f = bm.faces.new(vs)
            except ValueError:
                continue
            for li, loop in enumerate(f.loops):
                vv = v0 if loop.vert in (a[0], a[1], a[2], a[3]) else v1
                if kind == "edge":
                    u = 0.5
                else:
                    lo, hi = us[kind]
                    u = lo + (hi - lo) * (loop.vert.co.x - x0) / (x1 - x0)
                loop[uv].uv = (u, vv)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(bt.MAT["Track"])
    ob = bt.link(bpy.data.objects.new(name, me))
    ob["grp"] = grp
    ob["smooth"] = 30
    return links


def road_wheel(name, r, w, grp, center):
    """A twin road wheel: two rubber-tyred steel discs either side of the guide horns, a hub cap."""
    c = Vector(center)
    gap = 0.07
    for s in (-1, 1):
        x = s * (gap / 2 + w / 4)
        prof = [(-w / 4, r * 0.55), (-w / 4, r - 0.02), (-w / 4 + 0.012, r), (w / 4 - 0.012, r), (w / 4, r - 0.02),
                (w / 4, r * 0.55)]
        revolve(f"{name}Tyre{s}", prof, 32, ("RubberSide",), axis="X", center=tuple(c + Vector((x, 0, 0))), grp=grp, smooth=40)
        disc = [(-w / 4 + 0.01, r * 0.56), (-w / 8, r * 0.4), (-w / 8, r * 0.15), (w / 8, 0.0)]
        revolve(f"{name}Disc{s}", disc, 28, ("Rim",), axis="X", center=tuple(c + Vector((x, 0, 0))), grp=grp, smooth=40)
        for k in range(6):  # lightening holes
            a = k * PI / 3
            cyl(f"{name}Hole{s}{k}", r * 0.1, 0.012, tuple(c + Vector((x + s * 0.004, math.cos(a) * r * 0.32, math.sin(a) * r * 0.32))),
                axis="X", segs=10, mat="Slot", grp=grp)
    cyl(f"{name}Axle", r * 0.2, gap + w * 0.5, tuple(c), axis="X", segs=14, mat="Steel", grp=grp)
    cyl(f"{name}Cap", r * 0.24, 0.03, tuple(c + Vector((gap / 2 + w / 2 + 0.01, 0, 0))), axis="X", segs=14, mat="SteelDark",
        grp=grp)
    for k in range(6):
        a = k * PI / 3 + 0.3
        cyl(f"{name}Nut{k}", 0.011, 0.02, tuple(c + Vector((gap / 2 + w / 2 + 0.02, math.cos(a) * r * 0.16, math.sin(a) * r * 0.16))),
            axis="X", segs=6, mat="Bolt", grp=grp)


def sprocket(name, r, w, grp, center, teeth=11):
    c = Vector(center)
    for s in (-1, 1):
        x = s * w * 0.3
        cyl(f"{name}Disc{s}", r * 0.82, 0.03, tuple(c + Vector((x, 0, 0))), axis="X", segs=36, mat="SteelDark", grp=grp)
        for k in range(teeth):
            a = k * 2 * PI / teeth
            box(f"{name}Tooth{s}{k}", (0.03, 0.07, 0.07), tuple(c + Vector((x, math.cos(a) * r * 0.86, math.sin(a) * r * 0.86))),
                "SteelDark", rot=(a, 0, 0), bev=0.008, grp=grp)
        for k in range(5):
            a = k * 2 * PI / 5
            cyl(f"{name}Hole{s}{k}", r * 0.14, 0.035, tuple(c + Vector((x, math.cos(a) * r * 0.48, math.sin(a) * r * 0.48))),
                axis="X", segs=12, mat="Slot", grp=grp)
    cyl(f"{name}Hub", r * 0.32, w * 0.8, tuple(c), axis="X", segs=20, mat="Steel", bev=0.01, grp=grp)
    cyl(f"{name}Cap", r * 0.2, 0.05, tuple(c + Vector((w * 0.42, 0, 0))), axis="X", segs=16, mat="Paint", grp=grp)
    for k in range(8):
        a = k * PI / 4
        cyl(f"{name}Bolt{k}", 0.012, 0.03, tuple(c + Vector((w * 0.46, math.cos(a) * r * 0.27, math.sin(a) * r * 0.27))),
            axis="X", segs=6, mat="Bolt", grp=grp)


def build_track():
    fx, fy, fz = ext(PARTS["track"])
    xm = (TRACK["x0"] + TRACK["x1"]) / 2
    bw = TRACK["x1"] - TRACK["x0"]
    hub_z = TRACK["hub_z"]
    mx = -fx / 2 + 0.02
    # the hull side it bolts to: a long plate, the final drive at the back, the bogie mounts
    box("SidePlate", (0.04, fy * 0.96, 0.42), (mx, 0, 0.02), "PaintDark", bev=0.008, grp="Part")
    for i in range(3):
        bolts(f"PlateBolt{i}", (mx - 0.021, -0.9 + i * 0.9, 0.02), (-1, 0, 0), 0.3, 0.26, grp="Part")
    sy, sz, sr = TRACK["sprocket"]
    cyl("FinalDrive", 0.16, 0.42, (mx + 0.21, sy, sz), axis="X", segs=24, mat="PaintDark", bev=0.015, grp="Part")
    for k in range(8):
        a = k * PI / 4
        cyl(f"FDBolt{k}", 0.012, 0.02, (mx + 0.03, sy + math.cos(a) * 0.12, sz + math.sin(a) * 0.12), axis="X", segs=6,
            mat="Bolt", grp="Part")
    iy, iz, ir = TRACK["idler"]
    # the idler's tensioner: an arm and its screw
    box("TensionArm", (0.05, 0.34, 0.08), (mx + 0.12, iy - 0.14, iz + 0.02), "SteelDark", rot=(0.15, 0, 0), bev=0.01, grp="Part")
    cyl_between("TensionScrew", (mx + 0.1, iy - 0.45, iz + 0.12), (mx + 0.1, iy - 0.16, iz + 0.08), 0.018, mat="Steel", segs=10,
                grp="Part")
    cyl("IdlerAxle", 0.05, xm - mx, ((mx + xm) / 2, iy, iz), axis="X", segs=14, mat="Steel", grp="Part")
    # the swing arms and their bump stops (one per road wheel), the return rollers on stub axles
    for k, y in enumerate(TRACK_ROADS):
        box(f"ArmMount{k}", (0.1, 0.16, 0.14), (mx + 0.06, y - 0.12, 0.0), "Paint", bev=0.012, grp="Part")
        tube(f"Arm{k}", [(mx + 0.07, y - 0.12, -0.02), (mx + 0.08, y - 0.06, hub_z + 0.1), (mx + 0.08, y, hub_z)], 0.032,
             mat="SteelDark", nring=10, sub=4, grp="Part")
        box(f"BumpStop{k}", (0.07, 0.06, 0.05), (mx + 0.06, y + 0.1, hub_z + 0.24), "Rubber", bev=0.012, grp="Part")
    for k, (y, z, r) in enumerate(TRACK["rollers"]):
        revolve(f"Roller{k}", [(-bw / 2 + 0.02, r * 0.4), (-bw / 2 + 0.02, r), (bw / 2 - 0.02, r), (bw / 2 - 0.02, r * 0.4)], 20,
                ("RubberSide",), axis="X", center=(xm, y, z), grp="Part")
        cyl(f"RollerAxle{k}", 0.025, xm - mx, ((mx + xm) / 2, y, z), axis="X", segs=10, mat="Steel", grp="Part")
    # a fender over the top run from the hull side out past the belt, its lip, its front, a mud flap
    fx0, fx1 = mx + 0.02, TRACK["x1"] + 0.05
    fc, fw = (fx0 + fx1) / 2, fx1 - fx0
    box("Fender", (fw, fy * 0.98, 0.012), (fc, 0, 0.33), "Paint", bev=0.004, grp="Part")
    box("FenderLip", (0.012, fy * 0.98, 0.08), (fx1, 0, 0.3), "Paint", bev=0.003, grp="Part")
    box("FenderFront", (fw, 0.012, 0.18), (fc, fy / 2 - 0.02, 0.26), "Paint", rot=(-0.6, 0, 0), bev=0.003, grp="Part")
    box("MudFlap", (fw - 0.06, 0.01, 0.2), (fc + 0.03, -fy / 2 + 0.04, 0.2), "Rubber", grp="Part")
    box("Toolbox", (0.2, 0.5, 0.12), (fc - 0.1, -0.4, 0.4), "PaintDark", bev=0.012, grp="Part")
    for k in range(5):
        y = -1.2 + k * 0.6
        cyl(f"FenderBolt{k}", 0.012, 0.012, (fx0 + 0.03, y, 0.342), segs=6, mat="Bolt", grp="Part")
        box(f"FenderStay{k}", (0.04, 0.03, 0.1), (mx + 0.02, y, 0.28), "SteelDark", grp="Part")
    # the moving parts: road wheels, the sprocket, the idler (each spins about its hub), the belt
    for k, y in enumerate(TRACK_ROADS):
        road_wheel(f"Road{k}", TRACK["road_r"], bw - 0.04, f"Road{k}", (xm, y, hub_z))
        PIVOTS[f"Road{k}"] = (xm, y, hub_z)
    sprocket("Sprocket", sr, bw, "Sprocket", (xm, sy, sz))
    PIVOTS["Sprocket"] = (xm, sy, sz)
    road_wheel("Idler", ir, bw - 0.04, "Idler", (xm, iy, iz))
    PIVOTS["Idler"] = (xm, iy, iz)
    PIVOTS["Belt"] = (0, 0, 0)
    build_belt()


def build_rockets():
    sx, sy, sz = ext(PARTS["rockets"])
    hz = sz / 2
    box("BasePlate", (sx * 0.9, sy * 0.9, 0.03), (0, 0, -hz + 0.015), "SteelDark", bev=0.005, grp="Part")
    bolts("BaseBolt", (0, 0, -hz + 0.03), (0, 0, 1), sx * 0.7, sy * 0.7, grp="Part")
    cyl("Ring", 0.32, 0.08, (0, 0, -hz + 0.07), segs=28, mat="Paint", bev=0.01, grp="Part")
    yaw_z = -hz + 0.11
    # the turret: a turntable, a pedestal with its traverse motor, two side arms
    cyl("Table", 0.3, 0.04, (0, 0, yaw_z + 0.02), segs=28, mat="SteelDark", grp="Turret")
    box("Pedestal", (0.22, 0.26, 0.2), (0, -0.06, yaw_z + 0.14), "Paint", bev=0.02, grp="Turret")
    cyl("TraverseMotor", 0.06, 0.12, (0.17, -0.12, yaw_z + 0.1), segs=14, mat="SteelDark", grp="Turret")
    trun = Vector((0, 0.0, yaw_z + 0.36))
    for s in (-1, 1):
        box(f"Arm{s}", (0.04, 0.2, 0.28), (s * 0.4, -0.04, yaw_z + 0.22), "Paint", bev=0.01, grp="Turret")
        cyl(f"Pin{s}", 0.035, 0.05, (s * 0.38, 0, trun.z), axis="X", segs=12, mat="Steel", grp="Turret")
    # the launcher (elevates): a box of 2 x 3 tubes, the frame round them, the rockets' noses in them
    L = 0.86
    box("PodTop", (0.7, L, 0.02), (0, 0.04, trun.z + 0.2), "Paint", bev=0.005, grp="Gun")
    box("PodBottom", (0.7, L, 0.02), (0, 0.04, trun.z - 0.2), "Paint", bev=0.005, grp="Gun")
    for s in (-1, 1):
        box(f"PodSide{s}", (0.02, L, 0.42), (s * 0.35, 0.04, trun.z), "Paint", bev=0.005, grp="Gun")
    for y in (0.04 - L / 2 + 0.03, 0.04 + L / 2 - 0.03):
        for s in (-1, 1):
            box(f"Frame{y}{s}", (0.04, 0.05, 0.44), (s * 0.35, y, trun.z), "SteelDark", bev=0.006, grp="Gun")
        box(f"FrameT{y}", (0.74, 0.05, 0.04), (0, y, trun.z + 0.21), "SteelDark", bev=0.006, grp="Gun")
        box(f"FrameB{y}", (0.74, 0.05, 0.04), (0, y, trun.z - 0.21), "SteelDark", bev=0.006, grp="Gun")
    tubes = []
    for i, x in enumerate((-0.22, 0.0, 0.22)):
        for j, z in enumerate((0.09, -0.09)):
            c = Vector((x, 0.04, trun.z + z))
            revolve(f"Tube{i}{j}", [(-L / 2 + 0.01, 0.07), (-L / 2 + 0.01, 0.078), (L / 2 - 0.01, 0.078), (L / 2 - 0.01, 0.07)], 20,
                    ("SteelDark",), axis="Y", center=tuple(c), grp="Gun")
            cyl(f"TubeEnd{i}{j}", 0.07, 0.01, tuple(c + Vector((0, -L / 2 + 0.02, 0))), axis="Y", segs=16, mat="Slot", grp="Gun")
            tubes.append(c)
    box("Sight", (0.06, 0.12, 0.08), (0.28, 0.2, trun.z + 0.26), "SteelDark", bev=0.01, grp="Gun")
    box("Stencil", (0.3, 0.01, 0.04), (0, 0.04 - L / 2 + 0.005, trun.z + 0.17), "Hazard", grp="Gun")
    # the rockets: each a node (hidden once it's gone) whose nose sits just inside its tube's mouth
    for k, c in enumerate(tubes):
        g = f"Rocket{k}"
        tip = c + Vector((0, L / 2 - 0.05, 0))
        cyl(f"{g}Body", 0.06, 0.3, tuple(tip - Vector((0, 0.22, 0))), axis="Y", segs=16, mat="Olive", grp=g)
        cyl(f"{g}Nose", 0.06, 0.12, tuple(tip - Vector((0, 0.01, 0))), axis="Y", segs=16, r2=0.012, mat="Olive", grp=g)
        cyl(f"{g}Band", 0.061, 0.02, tuple(tip - Vector((0, 0.1, 0))), axis="Y", segs=16, mat="Spring", grp=g)
        PIVOTS[g] = tuple(tip)
    PIVOTS.update({"Turret": (0, 0, yaw_z), "Gun": tuple(trun), "Muzzle": tuple(trun + Vector((0, 0.04 + L / 2, 0)))})


def build_battery():
    sx, sy, sz = ext(PARTS["battery"])
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    # a steel tray, two 12 V blocks in series, the clamp bar, the cables and the isolator switch
    box("Tray", (sx - 0.02, sy - 0.02, 0.04), (0, 0, -hz + 0.02), "SteelDark", bev=0.006, grp="Part")
    for s in (-1, 1):
        box(f"TrayLip{s}", (sx - 0.02, 0.02, 0.1), (0, s * (hy - 0.02), -hz + 0.07), "SteelDark", bev=0.004, grp="Part")
    for i, y in enumerate((-0.22, 0.22)):
        box(f"Case{i}", (0.4, 0.4, 0.3), (0, y, -hz + 0.04 + 0.15), "Battery", bev=0.012, grp="Part")
        box(f"Lid{i}", (0.41, 0.41, 0.04), (0, y, -hz + 0.34 + 0.02), "BatteryLid", bev=0.01, grp="Part")
        for k in range(6):
            cyl(f"Cap{i}{k}", 0.018, 0.012, (-0.1 + (k % 3) * 0.1, y + (-0.06 if k < 3 else 0.06), -hz + 0.385), segs=10,
                mat="BatteryLid", grp="Part")
        for s, m in ((-1, "Terminal"), (1, "TerminalNeg")):
            cyl(f"Post{i}{s}", 0.018, 0.04, (s * 0.15, y + 0.15, -hz + 0.4), segs=12, mat="Steel", grp="Part")
            cyl(f"Boot{i}{s}", 0.03, 0.035, (s * 0.15, y + 0.15, -hz + 0.42), segs=12, mat=m, grp="Part")
    box("Clamp", (0.06, sy - 0.08, 0.025), (0, 0, -hz + 0.395), "Steel", bev=0.005, grp="Part")
    tube("Link", [(0.15, -0.07, -hz + 0.44), (0.05, 0.05, -hz + 0.47), (-0.15, 0.37, -hz + 0.44)], 0.014, mat="Rubber", nring=8,
         sub=4, grp="Part")
    tube("CablePos", [(-0.15, -0.07, -hz + 0.44), (-0.2, -0.2, -hz + 0.46), (-0.23, -0.4, -hz + 0.3), (-0.23, -hy, -hz + 0.12)],
         0.015, mat="TerminalNeg", nring=8, sub=4, grp="Part")
    tube("CableNeg", [(0.15, 0.37, -hz + 0.44), (0.21, 0.3, -hz + 0.46), (0.23, 0.1, -hz + 0.3), (0.23, -hy, -hz + 0.12)], 0.015,
         mat="Terminal", nring=8, sub=4, grp="Part")
    box("Isolator", (0.08, 0.04, 0.1), (-0.2, -hy + 0.04, -hz + 0.12), "Spring", bev=0.008, grp="Part")
    cyl("IsolatorKey", 0.02, 0.05, (-0.2, -hy + 0.0, -hz + 0.14), axis="Y", segs=10, mat="PaintDark", grp="Part")
    bolts("TrayBolt", (0, 0, -hz + 0.04), (0, 0, 1), sx * 0.7, sy * 0.8, grp="Part")


def build_engine():
    """A turbo-diesel straight six on its bed: the block (cast ribs, a sump, the oil filter), the
    head, a finned rocker cover with its filler cap, the injector lines, the exhaust manifold into
    the turbo and up the stack (heat-wrapped), the intercooler pipe, the alternator and the belt, a
    shrouded fan and the radiator with its grille guard, the air cleaner."""
    sx, sy, sz = ext(PARTS["engine"])
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    base = -hz
    for s in (-1, 1):
        box(f"Rail{s}", (0.06, sy - 0.02, 0.07), (s * (hx - 0.05), 0, base + 0.035), "SteelDark", bev=0.006, grp="Part")
        for y in (-0.22, 0.18):
            cyl(f"MountRubber{s}{y}", 0.04, 0.05, (s * 0.3, y, base + 0.095), segs=12, mat="Rubber", grp="Part")
            box(f"MountFoot{s}{y}", (0.12, 0.08, 0.03), (s * 0.26, y, base + 0.13), "PaintDark", bev=0.006, grp="Part")
        for y in (-0.4, 0.0, 0.4):
            cyl(f"RailBolt{s}{y}", 0.014, 0.016, (s * (hx - 0.05), y, base + 0.078), segs=6, mat="Bolt", grp="Part")
    bz = base + 0.14
    # the sump, the block (tapered toward the bottom) with cast ribs, the bell housing at the back
    box("Sump", (0.34, 0.6, 0.1), (0, -0.04, bz + 0.05), "PaintDark", bev=0.02, grp="Part")
    blk = [(-0.2, -0.36, bz + 0.1), (0.2, -0.36, bz + 0.1), (0.2, 0.28, bz + 0.1), (-0.2, 0.28, bz + 0.1),
           (-0.25, -0.36, bz + 0.42), (0.25, -0.36, bz + 0.42), (0.25, 0.28, bz + 0.42), (-0.25, 0.28, bz + 0.42)]
    ob = bt.mk("Block", blk, [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], ("Engine",),
               grp="Part", smooth=0)
    bt.bevel(ob, 0.02, 2)
    for k in range(6):
        y = -0.3 + k * 0.108
        for s in (-1, 1):
            box(f"Rib{k}{s}", (0.025, 0.03, 0.26), (s * 0.225, y, bz + 0.27), "Engine", rot=(0, s * 0.15, 0), bev=0.006, grp="Part")
    cyl("Bell", 0.22, 0.1, (0, -0.4, bz + 0.25), axis="Y", segs=28, mat="Engine", bev=0.015, grp="Part")
    cyl("OilFilter", 0.05, 0.13, (-0.27, 0.05, bz + 0.2), axis="X", segs=16, mat="Spring", bev=0.008, grp="Part")
    cyl("Dipstick", 0.006, 0.3, (-0.24, -0.15, bz + 0.5), segs=6, mat="Spring", grp="Part")
    # the head and the finned rocker cover, the filler cap and the lifting eyes
    box("Head", (0.42, 0.62, 0.1), (0, -0.04, bz + 0.47), "Steel", bev=0.015, grp="Part")
    box("Cover", (0.34, 0.6, 0.07), (0, -0.04, bz + 0.555), "Paint", bev=0.025, grp="Part")
    for k in range(9):
        box(f"CoverFin{k}", (0.3, 0.012, 0.025), (0, -0.3 + k * 0.065, bz + 0.6), "Paint", bev=0.004, grp="Part")
    cyl("Filler", 0.035, 0.035, (-0.08, 0.18, bz + 0.62), segs=16, mat="PaintDark", grp="Part")
    for y in (-0.33, 0.25):
        tube(f"Eye{y}", [(0.1, y, bz + 0.58), (0.1, y, bz + 0.65), (0.14, y, bz + 0.65), (0.14, y, bz + 0.58)], 0.012,
             mat="Steel", nring=8, sub=3, grp="Part")
    # injector pump on the left and its six lines over to the head
    box("InjPump", (0.08, 0.3, 0.12), (-0.3, -0.05, bz + 0.33), "Steel", bev=0.015, grp="Part")
    for k in range(6):
        y = -0.3 + k * 0.108
        tube(f"InjLine{k}", [(-0.3, -0.15 + k * 0.05, bz + 0.4), (-0.27, y, bz + 0.5), (-0.14, y, bz + 0.54)], 0.006, mat="Steel",
             nring=6, sub=4, grp="Part")
    # exhaust manifold (six runners) to the turbo, the stack heat-wrapped with its rain cap
    for k in range(6):
        y = -0.3 + k * 0.108
        tube(f"Runner{k}", [(0.2, y, bz + 0.44), (0.26, y, bz + 0.42), (0.28, y * 0.6 - 0.03, bz + 0.39)], 0.022, mat="Exhaust",
             nring=8, sub=4, grp="Part")
    cyl("Manifold", 0.035, 0.6, (0.28, -0.06, bz + 0.39), axis="Y", segs=14, mat="Exhaust", grp="Part")
    revolve("TurboHot", [(-0.06, 0.02), (-0.06, 0.09), (0.0, 0.1), (0.06, 0.08), (0.06, 0.02)], 20, ("Exhaust",), axis="Y",
            center=(0.36, -0.22, bz + 0.46), grp="Part")
    revolve("TurboCold", [(-0.05, 0.02), (-0.05, 0.08), (0.05, 0.08), (0.05, 0.02)], 20, ("Steel",), axis="Y",
            center=(0.36, -0.1, bz + 0.46), grp="Part")
    tube("Stack", [(0.36, -0.28, bz + 0.5), (0.4, -0.32, bz + 0.6), (0.4, -0.32, hz + 0.05), (0.4, -0.32, hz + 0.25)], 0.042,
         mat="HeatWrap", nring=14, sub=5, grp="Part")
    for k in range(3):
        cyl(f"WrapClamp{k}", 0.046, 0.015, (0.4, -0.32, bz + 0.65 + k * 0.17), segs=14, mat="Steel", grp="Part")
    box("RainCap", (0.1, 0.1, 0.008), (0.4, -0.29, hz + 0.27), "SteelDark", rot=(0.5, 0, 0), grp="Part")
    tube("Charge", [(0.36, -0.04, bz + 0.48), (0.3, 0.15, bz + 0.6), (0.1, 0.3, bz + 0.63), (-0.05, 0.3, bz + 0.57)], 0.03,
         mat="Steel", nring=12, sub=5, grp="Part")
    # the front: crank pulley, alternator, water pump, the belt round them; the fan in its shroud
    fy = 0.3
    cyl("CrankPulley", 0.08, 0.03, (0, fy, bz + 0.17), axis="Y", segs=24, mat="Steel", grp="Part")
    cyl("PumpPulley", 0.06, 0.03, (0, fy, bz + 0.4), axis="Y", segs=20, mat="Steel", grp="Part")
    cyl("Alternator", 0.07, 0.12, (-0.2, fy - 0.04, bz + 0.38), axis="Y", segs=18, mat="Steel", bev=0.01, grp="Part")
    for k in range(6):
        box(f"AltFin{k}", (0.01, 0.1, 0.14), (-0.2 + (k - 2.5) * 0.022, fy - 0.04, bz + 0.38), "SteelDark", grp="Part")
    cyl("AltPulley", 0.035, 0.03, (-0.2, fy + 0.03, bz + 0.38), axis="Y", segs=16, mat="Steel", grp="Part")
    belt_pts = [(0.0, fy + 0.005, bz + 0.09), (0.08, fy + 0.005, bz + 0.17), (0.06, fy + 0.005, bz + 0.42),
                (-0.2, fy + 0.03, bz + 0.415), (-0.235, fy + 0.03, bz + 0.38), (-0.08, fy + 0.005, bz + 0.17)]
    tube("Belt", belt_pts, 0.008, mat="Rubber", nring=6, sub=4, closed=True, grp="Part")
    box("Shroud", (0.56, 0.06, 0.56), (0, hy - 0.16, bz + 0.33), "PaintDark", bev=0.01, grp="Part")
    cyl("FanHub", 0.04, 0.05, (0, hy - 0.16, bz + 0.33), axis="Y", segs=14, mat="Steel", grp="Part")
    for k in range(7):
        a = k * 2 * PI / 7
        box(f"Blade{k}", (0.06, 0.012, 0.2), (math.cos(a) * 0.11, hy - 0.16, bz + 0.33 + math.sin(a) * 0.11), "SteelDark",
            rot=(0.35, PI / 2 - a, 0), grp="Part")
    box("Radiator", (sx - 0.14, 0.07, sz * 0.62), (0, hy - 0.09, bz + 0.33), "Radiator", bev=0.008, grp="Part")
    box("RadTop", (sx - 0.12, 0.09, 0.05), (0, hy - 0.09, bz + 0.33 + sz * 0.31 + 0.02), "Paint", bev=0.008, grp="Part")
    cyl("RadCap", 0.03, 0.03, (0.15, hy - 0.09, bz + 0.33 + sz * 0.31 + 0.06), segs=14, mat="Steel", grp="Part")
    tube("TopHose", [(0.0, 0.25, bz + 0.48), (0.05, 0.33, bz + 0.6), (0.08, hy - 0.1, bz + 0.62)], 0.025, mat="Rubber", nring=10,
         sub=4, grp="Part")
    tube("LowHose", [(0.0, 0.28, bz + 0.25), (-0.12, 0.34, bz + 0.15), (-0.2, hy - 0.1, bz + 0.12)], 0.025, mat="Rubber",
         nring=10, sub=4, grp="Part")
    for k in range(7):  # the grille guard
        x = -hx + 0.08 + k * (sx - 0.16) / 6
        cyl_between(f"Guard{k}", (x, hy - 0.025, bz + 0.05), (x, hy - 0.025, hz - 0.08), 0.008, mat="SteelDark", segs=6, grp="Part")
    for z in (bz + 0.05, hz - 0.08):
        box(f"GuardBar{z}", (sx - 0.1, 0.02, 0.03), (0, hy - 0.025, z), "Paint", bev=0.004, grp="Part")
    # the air cleaner drum on the left, its hose to the turbo
    cyl("AirCleaner", 0.1, 0.32, (-0.36, -0.12, bz + 0.6), axis="Y", segs=24, mat="Paint", bev=0.015, grp="Part")
    cyl("CleanerCap", 0.104, 0.02, (-0.36, 0.05, bz + 0.6), axis="Y", segs=24, mat="PaintDark", grp="Part")
    tube("Intake", [(-0.36, -0.28, bz + 0.6), (-0.2, -0.36, bz + 0.62), (0.2, -0.3, bz + 0.6), (0.36, -0.1, bz + 0.52)], 0.032,
         mat="Rubber", nring=10, sub=5, grp="Part")
    box("Plate", (0.1, 0.005, 0.05), (0.12, -0.36, bz + 0.3), "Steel", grp="Part")


BUILDERS = {"cab": build_cab, "frame": build_frame, "armor": build_armor, "wedge": build_wedge,
            "wheel_s": lambda: build_wheel("wheel_s"), "wheel_l": lambda: build_wheel("wheel_l"),
            "engine": build_engine, "light": build_light, "minigun": build_minigun, "cannon": build_cannon,
            "track": build_track, "rockets": build_rockets, "battery": build_battery}


def icon(pid):
    """The build bar's picture of a part: 256 px, transparent, three-quarter view from above-front."""
    scene = bpy.context.scene
    if "Ground" not in bpy.data.objects:
        vk.studio(OUT_DIR, -ext(PARTS[pid]).z / 2)
    bpy.data.objects["Ground"].hide_render = True
    scene.render.film_transparent = True
    e = ext(PARTS[pid])
    span = max(e.x, e.y, e.z)
    if pid in ("minigun", "cannon"):
        span *= 1.6
    if pid == "track":
        span *= 0.8  # (the barrels reach past the footprint)
    d = span * 1.45 + 0.2
    os.makedirs(os.path.join(OUT_DIR, "icons"), exist_ok=True)
    bt.OUT_DIR = OUT_DIR
    cd = bpy.data.cameras.new("Icon")
    cam = bt.link(bpy.data.objects.new("Icon", cd))
    target = Vector((0, 0.15 * span if pid in ("minigun", "cannon") else 0.0, 0))
    cam.location = target + Vector((d * 0.75, d * 0.95, d * 0.62))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    cd.lens = 50
    scene.camera = cam
    scene.render.resolution_x = scene.render.resolution_y = 256
    scene.render.filepath = os.path.join(OUT_DIR, "icons", pid + ".png")
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    os.makedirs(OUT_DIR, exist_ok=True)
    for pid, fn in BUILDERS.items():
        PIVOTS.clear()
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bt.MAT.clear()
        materials()
        hub = fn()
        nodes = [bt.bake_group("Part", "Part")]
        if any(o.get("grp") == "Wheel" for o in bpy.data.objects):
            nodes.append(bt.bake_group("Wheel", "Wheel", tuple(hub)))
        if any(o.get("grp") == "Glow" for o in bpy.data.objects):
            nodes.append(bt.bake_group("Glow", "Glow"))
        for g in ["Road%d" % k for k in range(5)] + ["Sprocket", "Idler", "Belt"]:
            if any(o.get("grp") == g for o in bpy.data.objects):
                nodes.append(bt.bake_group(g, g, PIVOTS[g]))
        if any(o.get("grp") == "Turret" for o in bpy.data.objects):
            nodes += turret_nodes()
        vk.export(nodes, os.path.join(OUT_DIR, pid + ".glb"))
        if "--icons" in argv:
            icon(pid)
        if "--render" in argv:
            vk.studio(OUT_DIR, -ext(PARTS[pid]).z / 2)
            e = ext(PARTS[pid])
            d = max(e) * 2.6 + 0.6
            vk.render(pid, loc=(d * 0.8, d * 0.9, d * 0.6), target=(0, 0, 0), lens=50, res=(700, 600))


if __name__ == "__main__":
    main()
