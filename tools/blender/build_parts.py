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
  engine_l   2x2x3  a V8 turbo-diesel (200 kW): two banks, twin turbos and stacks, a big radiator and fan
  engine_s   1x1x2  a small petrol engine (40 kW): block, finned head, pull start, muffler
  spike      1x1x1  a ram head: a steel wedge with three hardened spikes forward
  flamer     2x1x2  a flamethrower: Turret > Gun (the projector, its nozzle), Muzzle at the nozzle; a fuel tank
  plate      1x1x1  a steel plate on the cell's outer face, on brackets
  cannon     2x2x2  a 76 mm gun in a sloped armoured turret: Turret > Gun (the mantlet and barrel, a muzzle
                    brake), Muzzle at its end
  crane      2x1x2  a slewing knuckle crane: its ring bolted down; on it (node Top, slewing about its middle)
                    the king post, a lattice boom out forward to the sheave at its tip (Godot 0, 1.85, -2.5),
                    the luffing ram, the hoist drum and a counterweight behind
  winch      1x1x2  a recovery winch: a drum of wire rope between side plates, its motor, the fairlead's
                    rollers at the back where the rope comes out (Godot 0, -0.05, 0.5), a hook stowed there

  saw        2x1x2  a feller's saw head: a flat circular blade (node Blade, spinning about up round Godot
                    0, -0.4, -0.95; r 0.55) low out in front on two arms, its hydraulic motor over the hub,
                    a guard over its back half, the mount bolted on behind
  wood_cab   2x2x2  the wood age's driver's place: a plank floor, boarded sides, a bench, posts, a plank
                    roof, a spoked wooden wheel
  wood_crane 2x1x2  a short timber crane: sills, an iron ring, and slewing (node Top) a post, a pole jib to
                    its sheave (Godot 0, 1.45, -1.8), a windlass, a box of stones behind
  wood_rail  1x2x1  a metre of rail fencing: two posts, three rails
  wood_frame 1x1x1  a lattice of hand-hewn timber, not quite square, pegged and nailed
  wood_plate 1x1x1  thick planks nailed across two battens on the cell's outer face
  wood_wedge 1x1x1  planks laid down a slope over two side boards

  steer      1x1x1  a steering knuckle: a base bolted down, the kingpin's housing, the steering ram to one
                    side and its arm; on top (node Top, turning about up) the flange what's carried bolts to

  wood_wheel 1x2x2  a cart wheel: an iron tyre on a rim of wooden felloes, twelve spokes, a turned hub (node
                    Wheel), on a timber axle block bolted on at its inner face

  ballista   2x1x2  a ballista on a timber ring: Turret > Gun (the stock, two bow limbs, the string, the
                    windlass), its bolt in the groove (node Rocket0), Muzzle at the stock's nose
  catapult   2x2x3  a torsion catapult: Turret (the timber bed, the uprights) > Gun (the axle and its rope
                    skein) > Barrels (the throwing arm, lying back, its sling bucket; swings over the top),
                    the stone in the bucket (node Rocket0)
  oilpot     2x1x2  a tipping cask of boiling oil: Turret > Gun (the cradle, the cask, its spout), a brazier
                    under it; Muzzle at the spout
  pitch      1x1x1  a cask of pitch: staves, iron hoops, the black pitch at the top, a ladle

Only some: -- --only=crane,winch
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
         "battery": (1, 1, 2), "engine_l": (2, 2, 3), "engine_s": (1, 1, 2), "spike": (1, 1, 1), "flamer": (2, 1, 2),
         "plate": (1, 1, 1), "flipper": (2, 1, 3), "hinge": (1, 1, 1), "rotor": (2, 1, 2), "piston": (1, 1, 1),
         "turret": (2, 1, 2), "ammo": (1, 1, 1), "barrel": (1, 1, 1), "crane": (2, 1, 2), "winch": (1, 1, 2),
         "saw": (2, 1, 2), "wood_cab": (2, 2, 2), "wood_crane": (2, 1, 2), "wood_rail": (1, 2, 1), "wood_frame": (1, 1, 1), "wood_plate": (1, 1, 1), "wood_wedge": (1, 1, 1),
         "steer": (1, 1, 1), "wood_wheel": (1, 2, 2), "wood_wheel_l": (2, 3, 3),
         "ballista": (2, 1, 2), "catapult": (2, 2, 3), "oilpot": (2, 1, 2), "pitch": (1, 1, 1)}


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
    m("Wood", (0.3, 0.2, 0.11), rough=0.88)
    m("WoodPale", (0.4, 0.28, 0.16), rough=0.85)
    m("WoodDark", (0.2, 0.13, 0.075), rough=0.9)
    m("Blade", (0.5, 0.5, 0.52), metal=0.95, rough=0.3)
    m("Stone", (0.3, 0.29, 0.27), rough=0.95)
    m("Rope", (0.45, 0.37, 0.24), rough=0.95)
    m("Iron", (0.1, 0.09, 0.085), metal=0.7, rough=0.65)


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



# --- Third batch: a big and a small engine, a ram, a flamethrower, a plate ---------------------------

def build_engine_l():
    """A V8 turbo-diesel (200 kW): the vee of two banks with their covers, twin turbos and stacks, a big
    radiator and fan, the bell housing, on a heavy bed."""
    sx, sy, sz = ext(PARTS["engine_l"])
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    base = -hz
    for s in (-1, 1):
        box(f"Rail{s}", (0.08, sy - 0.04, 0.09), (s * (hx - 0.06), 0, base + 0.045), "SteelDark", bev=0.008, grp="Part")
        for y in (-0.5, 0.0, 0.5):
            cyl(f"Mount{s}{y}", 0.05, 0.06, (s * 0.32, y, base + 0.12), segs=12, mat="Rubber", grp="Part")
    bz = base + 0.16
    box("Crank", (0.42, 0.95, 0.24), (0, -0.05, bz + 0.12), "Engine", bev=0.03, grp="Part")
    box("Sump", (0.36, 0.85, 0.1), (0, -0.05, bz + 0.0), "PaintDark", bev=0.02, grp="Part")
    for s in (-1, 1):  # the two banks, leaning out
        bank = box(f"Bank{s}", (0.26, 0.9, 0.3), (s * 0.2, -0.05, bz + 0.36), "Engine", rot=(0, s * 0.5, 0), bev=0.025, grp="Part")
        box(f"Cover{s}", (0.2, 0.86, 0.06), (s * 0.29, -0.05, bz + 0.52), "Paint", rot=(0, s * 0.5, 0), bev=0.02, grp="Part")
        for k in range(4):
            y = -0.4 + k * 0.24
            box(f"CoverFin{s}{k}", (0.18, 0.02, 0.03), (s * 0.31, y, bz + 0.56), "Paint", rot=(0, s * 0.5, 0), grp="Part")
            tube(f"Runner{s}{k}", [(s * 0.38, y, bz + 0.36), (s * 0.48, y, bz + 0.34), (s * 0.5, y * 0.7, bz + 0.3)], 0.024,
                 mat="Exhaust", nring=8, sub=4, grp="Part")
        cyl(f"Manifold{s}", 0.035, 0.85, (s * 0.5, -0.05, bz + 0.3), axis="Y", segs=12, mat="Exhaust", grp="Part")
        revolve(f"Turbo{s}", [(-0.06, 0.02), (-0.06, 0.09), (0.0, 0.1), (0.06, 0.08), (0.06, 0.02)], 18, ("Exhaust",), axis="Y",
                center=(s * 0.5, -0.55, bz + 0.4), grp="Part")
        tube(f"Stack{s}", [(s * 0.5, -0.6, bz + 0.45), (s * 0.52, -0.62, bz + 0.6), (s * 0.52, -0.62, hz + 0.2)], 0.045,
             mat="HeatWrap", nring=12, sub=4, grp="Part")
        box(f"Cap{s}", (0.11, 0.11, 0.01), (s * 0.52, -0.6, hz + 0.22), "SteelDark", rot=(0.5, 0, 0), grp="Part")
    box("Intake", (0.16, 0.8, 0.12), (0, -0.05, bz + 0.5), "Steel", bev=0.03, grp="Part")
    cyl("Bell", 0.26, 0.12, (0, -0.6, bz + 0.22), axis="Y", segs=28, mat="Engine", bev=0.015, grp="Part")
    box("Radiator", (sx - 0.16, 0.08, sz * 0.66), (0, hy - 0.08, bz + 0.34), "Radiator", bev=0.01, grp="Part")
    for k in range(12):
        box(f"Fin{k}", (sx - 0.2, 0.01, 0.012), (0, hy - 0.035, bz + 0.06 + k * 0.05), "Steel", grp="Part")
    box("Shroud", (0.7, 0.06, 0.6), (0, hy - 0.2, bz + 0.34), "PaintDark", bev=0.01, grp="Part")
    for k in range(7):
        a = k * 2 * PI / 7
        box(f"Blade{k}", (0.07, 0.012, 0.24), (math.cos(a) * 0.13, hy - 0.2, bz + 0.34 + math.sin(a) * 0.13), "SteelDark",
            rot=(0.35, PI / 2 - a, 0), grp="Part")
    cyl("Alternator", 0.08, 0.14, (-0.28, 0.42, bz + 0.3), axis="Y", segs=18, mat="Steel", bev=0.01, grp="Part")
    tube("Hose", [(0.0, 0.38, bz + 0.5), (0.06, 0.5, bz + 0.62), (0.1, hy - 0.1, bz + 0.62)], 0.03, mat="Rubber", nring=10,
         sub=4, grp="Part")
    box("Badge", (0.12, 0.005, 0.05), (0.15, -0.6 - 0.065, bz + 0.38), "Steel", grp="Part")


def build_engine_s():
    """A small petrol engine (40 kW): a single block with its head, a carburettor and air filter, a
    pull-start drum, a little radiator, a short exhaust with a muffler."""
    sx, sy, sz = ext(PARTS["engine_s"])
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    base = -hz
    box("Plate", (sx - 0.02, sy - 0.02, 0.03), (0, 0, base + 0.015), "SteelDark", bev=0.004, grp="Part")
    bolts("PlateBolt", (0, 0, base + 0.03), (0, 0, 1), sx * 0.7, sy * 0.8, grp="Part")
    box("Block", (0.26, 0.36, 0.2), (0, -0.04, base + 0.13), "Engine", bev=0.02, grp="Part")
    box("Head", (0.22, 0.32, 0.08), (0, -0.04, base + 0.27), "Steel", bev=0.015, grp="Part")
    for k in range(5):
        box(f"Fin{k}", (0.24, 0.015, 0.06), (0, -0.18 + k * 0.07, base + 0.33), "Steel", grp="Part")
    cyl("Starter", 0.07, 0.05, (0, -0.25, base + 0.14), axis="Y", segs=18, mat="Paint", grp="Part")
    cyl("Filter", 0.06, 0.08, (-0.17, 0.05, base + 0.28), axis="X", segs=16, mat="Paint", bev=0.01, grp="Part")
    tube("Exhaust", [(0.13, -0.05, base + 0.22), (0.2, -0.05, base + 0.2), (0.2, 0.15, base + 0.15)], 0.02, mat="Exhaust",
         nring=8, sub=4, grp="Part")
    cyl("Muffler", 0.045, 0.16, (0.2, 0.25, base + 0.15), axis="Y", segs=14, mat="Exhaust", grp="Part")
    box("Radiator", (0.3, 0.04, 0.22), (0, hy - 0.05, base + 0.16), "Radiator", bev=0.006, grp="Part")


def build_spike():
    """A ram: a steel wedge-shaped head bolted on, three hardened spikes forward from it."""
    s = CELL
    h = s / 2
    box("Back", (s - 0.02, 0.06, s - 0.02), (0, -h + 0.03, 0), "SteelDark", bev=0.006, grp="Part")
    bolts("BackBolt", (0, -h, 0), (0, -1, 0), 0.3, 0.3, grp="Part")
    prof = [(-h + 0.06, -h + 0.02), (0.05, -0.12), (0.05, 0.12), (-h + 0.06, h - 0.02)]
    verts = [(x, y, z) for x in (-h + 0.02, h - 0.02) for (y, z) in prof]
    faces = [(0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
    ob = bt.mk("Head", verts, faces, ("Paint",), grp="Part", smooth=0)
    bt.bevel(ob, 0.01, 2)
    for k, x in enumerate((-0.14, 0.0, 0.14)):
        cyl(f"Spike{k}", 0.045, 0.3, (x, 0.2, 0.0), axis="Y", r2=0.0, segs=10, mat="Steel", grp="Part")
        cyl(f"Collar{k}", 0.055, 0.03, (x, 0.06, 0.0), axis="Y", segs=10, mat="SteelDark", grp="Part")
    box("Stripe", (s - 0.08, 0.01, 0.05), (0, -0.02, 0.15), "Hazard", rot=(0.7, 0, 0), grp="Part")


def build_flamer():
    """A flamethrower on a ring mount: Turret (turns) > Gun (elevates): the projector tube with its
    shroud and nozzle, the pilot light (node Pilot), a fuel tank and its hose; Muzzle at the nozzle."""
    sx, sy, sz = ext(PARTS["flamer"])
    hz = sz / 2
    box("BasePlate", (sx * 0.9, sy * 0.9, 0.03), (0, 0, -hz + 0.015), "SteelDark", bev=0.005, grp="Part")
    bolts("BaseBolt", (0, 0, -hz + 0.03), (0, 0, 1), sx * 0.7, sy * 0.7, grp="Part")
    cyl("Ring", 0.28, 0.07, (0, 0, -hz + 0.065), segs=28, mat="Paint", bev=0.01, grp="Part")
    yaw_z = -hz + 0.1
    cyl("Table", 0.25, 0.04, (0, 0, yaw_z + 0.02), segs=28, mat="SteelDark", grp="Turret")
    cyl("Tank", 0.13, 0.42, (0.0, -0.22, yaw_z + 0.17), axis="X", segs=20, mat="Spring", bev=0.02, grp="Turret")
    for s in (-1, 1):
        box(f"Strap{s}", (0.02, 0.28, 0.3), (s * 0.12, -0.22, yaw_z + 0.17), "SteelDark", grp="Turret")
        box(f"Yoke{s}", (0.04, 0.12, 0.2), (s * 0.15, 0.05, yaw_z + 0.12), "Paint", bev=0.008, grp="Turret")
    trun = Vector((0, 0.05, yaw_z + 0.22))
    cyl("Body", 0.07, 0.42, tuple(trun + Vector((0, 0.12, 0))), axis="Y", segs=16, mat="SteelDark", bev=0.01, grp="Gun")
    cyl("Shroud", 0.055, 0.4, tuple(trun + Vector((0, 0.5, 0))), axis="Y", segs=14, mat="Steel", grp="Gun")
    for k in range(5):
        cyl(f"Vent{k}", 0.06, 0.02, tuple(trun + Vector((0, 0.36 + k * 0.07, 0))), axis="Y", segs=14, mat="SteelDark", grp="Gun")
    cyl("Nozzle", 0.04, 0.08, tuple(trun + Vector((0, 0.74, 0))), axis="Y", r2=0.03, segs=12, mat="Exhaust", grp="Gun")
    tube("Hose", [(0.0, -0.1, yaw_z + 0.17), (0.08, 0.0, trun.z - 0.04), (0.04, 0.1, trun.z - 0.05)], 0.02, mat="Rubber",
         nring=8, sub=4, grp="Gun")
    cyl("Igniter", 0.012, 0.06, tuple(trun + Vector((0, 0.74, -0.06))), axis="Y", segs=8, mat="Steel", grp="Gun")
    PIVOTS.update({"Turret": (0, 0, yaw_z), "Gun": tuple(trun), "Muzzle": tuple(trun + Vector((0, 0.8, 0)))})


def build_plate():
    """A steel plate: a slab two-fifths of a cell thick on the cell's outer face, bolted, its edges
    bevelled, on two brackets."""
    s = CELL
    h = s / 2
    box("Slab", (s - 0.01, 0.12, s - 0.01), (0, h - 0.06, 0), "Paint", bev=0.02, seg=2, grp="Part")
    for x in (-1, 1):
        for z in (-1, 1):
            cyl(f"Bolt{x}{z}", 0.02, 0.015, (x * 0.17, h + 0.005, z * 0.17), axis="Y", segs=6, mat="Bolt", grp="Part")
    for x in (-0.15, 0.15):
        box(f"Bracket{x}", (0.04, s - 0.14, 0.18), (x, -0.07, 0), "SteelDark", bev=0.006, grp="Part")
    box("Back", (s - 0.04, 0.03, s - 0.04), (0, -h + 0.015, 0), "SteelDark", bev=0.004, grp="Part")
    bolts("BackBolt", (0, -h, 0), (0, -1, 0), 0.3, 0.3, grp="Part")


def build_flipper():
    """A flipper: a steel tray (bolted on at its back) holding a pneumatic ram and its air bottle;
    over it the flap (node Flap, hinged at the back, its pivot at the hinge pin): a thick plate with
    a sharpened, hardened front lip, ribbed underneath, the ram's rod eye under it."""
    sx, sy, sz = ext(PARTS["flipper"])
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    base = -hz
    # the tray: floor, sides, the back where it bolts on
    box("Floor", (sx - 0.04, sy - 0.04, 0.03), (0, 0, base + 0.015), "SteelDark", bev=0.005, grp="Part")
    for s in (-1, 1):
        box(f"Side{s}", (0.03, sy - 0.1, sz - 0.12), (s * (hx - 0.03), -0.03, base + (sz - 0.12) / 2), "Paint", bev=0.006, grp="Part")
        for k in range(4):
            box(f"Lightening{s}{k}", (0.034, 0.16, 0.12), (s * (hx - 0.03), -0.45 + k * 0.3, base + 0.2), "SteelDark", grp="Part")
    box("Back", (sx - 0.04, 0.05, sz - 0.1), (0, -hy + 0.03, base + (sz - 0.1) / 2), "Paint", bev=0.008, grp="Part")
    bolts("BackBolt", (0, -hy, base + 0.12), (0, -1, 0), 0.6, 0.1, grp="Part")
    # the ram: its cylinder lying in the tray, trunnioned at the back, an air bottle and its line
    cyl("Ram", 0.06, 0.62, (0, -0.2, base + 0.1), axis="Y", segs=18, mat="Spring", bev=0.008, grp="Part")
    cyl("RamCap", 0.07, 0.04, (0, -0.52, base + 0.1), axis="Y", segs=18, mat="SteelDark", grp="Part")
    cyl("Bottle", 0.07, 0.5, (-0.28, -0.1, base + 0.1), axis="Y", segs=16, mat="Steel", bev=0.02, grp="Part")
    cyl("Valve", 0.03, 0.06, (-0.28, -0.38, base + 0.1), axis="Y", segs=10, mat="Exhaust", grp="Part")
    tube("AirLine", [(-0.28, -0.42, base + 0.1), (-0.15, -0.5, base + 0.14), (0, -0.5, base + 0.12)], 0.012,
         mat="Rubber", nring=8, sub=4, grp="Part")
    # hinge knuckles at the back of the tray
    hinge = Vector((0, -hy + 0.08, hz - 0.05))
    for x in (-0.38, 0.0, 0.38):
        cyl(f"Knuckle{x}", 0.04, 0.12, (x, hinge.y, hinge.z), axis="X", segs=14, mat="SteelDark", grp="Part")
    cyl("Pin", 0.018, sx - 0.06, tuple(hinge), axis="X", segs=10, mat="Steel", grp="Part")
    # the flap: a plate down to a sharp lip at the front, ribs underneath, the rod's eye
    L = sy - 0.12
    t = 0.05
    prof = [(hinge.y - 0.04, hinge.z + t / 2), (hinge.y + L - 0.12, hinge.z + t / 2), (hinge.y + L, hinge.z - t),
            (hinge.y + L - 0.12, hinge.z - t / 2), (hinge.y - 0.04, hinge.z - t / 2)]
    verts = [(x, y, z) for x in (-hx + 0.01, hx - 0.01) for (y, z) in prof]
    n = len(prof)
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    for k in range(n):
        faces.append((k, (k + 1) % n, n + (k + 1) % n, n + k))
    ob = bt.mk("Plate", verts, faces, ("Paint",), grp="Flap", smooth=0)
    bt.bevel(ob, 0.008, 2)
    box("Lip", (sx - 0.04, 0.1, 0.02), (0, hinge.y + L - 0.06, hinge.z - 0.035), "Steel", rot=(-0.3, 0, 0), grp="Flap")
    for x in (-0.3, 0.0, 0.3):
        box(f"Rib{x}", (0.03, L - 0.2, 0.05), (x, hinge.y + L * 0.45, hinge.z - 0.05), "SteelDark", grp="Flap")
    cyl("Eye", 0.035, 0.08, (0, hinge.y + 0.5, hinge.z - 0.07), axis="X", segs=12, mat="Steel", grp="Flap")
    cyl("Rod", 0.025, 0.3, (0, hinge.y + 0.3, hinge.z - 0.08), axis="Y", segs=10, mat="Steel", grp="Flap")
    box("Stripe", (sx - 0.2, 0.08, 0.004), (0, hinge.y + L - 0.25, hinge.z + t / 2 + 0.002), "Hazard", grp="Flap")
    for k in range(3):
        box(f"Tread{k}", (sx - 0.16, 0.03, 0.006), (0, hinge.y + 0.2 + k * 0.22, hinge.z + t / 2 + 0.003), "SteelDark", grp="Flap")
    PIVOTS["Flap"] = tuple(hinge)


def build_hinge():
    """A heavy hinge: the lower leaf bolted to what it's on, the upper leaf to what it carries, the
    knuckles and pin along the back top edge (node Top: the upper leaf, its pivot on the pin; it
    swings forward and up), a small actuator ram behind."""
    s = CELL
    h = s / 2
    pin = Vector((0, -(h - 0.06), h - 0.06))  # (Godot: the back top edge)
    box("Lower", (s - 0.04, s - 0.04, 0.12), (0, 0, -h + 0.06), "Paint", bev=0.01, grp="Part")
    bolts("LowBolt", (0, 0, -h), (0, 0, -1), 0.3, 0.3, grp="Part")
    box("Web", (0.08, s - 0.14, s - 0.22), (0, 0.02, -0.04), "SteelDark", bev=0.006, grp="Part")
    for x in (-0.17, 0.17):
        box(f"Cheek{x}", (0.06, 0.16, s - 0.16), (x, pin.y + 0.02, -0.02), "Paint", bev=0.006, grp="Part")
        cyl(f"KnuckleL{x}", 0.055, 0.1, (x, pin.y, pin.z), axis="X", segs=16, mat="SteelDark", grp="Part")
    cyl("Pin", 0.022, s - 0.02, tuple(pin), axis="X", segs=10, mat="Steel", grp="Part")
    cyl("Ram", 0.03, 0.22, (0.0, -0.12, -0.05), axis="Y", segs=12, mat="Spring", grp="Part")
    box("Upper", (s - 0.04, s - 0.04, 0.1), (0, 0, h - 0.05), "Paint", bev=0.01, grp="Top")
    cyl("KnuckleU", 0.055, 0.2, tuple(pin), axis="X", segs=16, mat="SteelDark", grp="Top")
    bolts("UpBolt", (0, 0, h), (0, 0, 1), 0.3, 0.3, grp="Top")
    box("Stripe", (s - 0.12, 0.05, 0.004), (0, h - 0.1, h + 0.002), "Hazard", grp="Top")
    PIVOTS["Top"] = tuple(pin)


def build_rotor():
    """A turntable: a drum bolted down holding the bearing and its motor; on it the table (node Top,
    turning about its middle), bolt holes round its rim for whatever's put on it."""
    sx, sy, sz = ext(PARTS["rotor"])
    hz = sz / 2
    box("Base", (sx - 0.04, sy - 0.04, 0.06), (0, 0, -hz + 0.03), "SteelDark", bev=0.006, grp="Part")
    bolts("BaseBolt", (0, 0, -hz), (0, 0, -1), sx * 0.8, sy * 0.8, grp="Part")
    cyl("Drum", 0.4, 0.14, (0, 0, -hz + 0.13), segs=32, mat="Paint", bev=0.01, grp="Part")
    cyl("Bearing", 0.36, 0.03, (0, 0, -hz + 0.215), segs=32, mat="Steel", grp="Part")
    cyl("Motor", 0.08, 0.16, (0.34, 0.34, -hz + 0.12), segs=16, mat="SteelDark", grp="Part")
    cyl("Table", 0.47, 0.06, (0, 0, hz - 0.03), segs=40, mat="Paint", bev=0.008, grp="Top")
    cyl("Hub", 0.1, 0.03, (0, 0, hz + 0.0), segs=20, mat="Steel", grp="Top")
    for k in range(8):
        a = k * 2 * PI / 8
        cyl(f"Hole{k}", 0.025, 0.012, (math.cos(a) * 0.38, math.sin(a) * 0.38, hz + 0.001), segs=8, mat="SteelDark", grp="Top")
    box("Mark", (0.06, 0.3, 0.005), (0, 0.24, hz + 0.003), "Hazard", grp="Top")
    PIVOTS["Top"] = (0, 0, 0)


def build_piston():
    """A hydraulic ram standing up: its barrel on a foot, the rod and the plate on top (node Top:
    pushed out a cell along it), its hose."""
    s = CELL
    h = s / 2
    box("Foot", (s - 0.04, s - 0.04, 0.08), (0, 0, -h + 0.04), "Paint", bev=0.008, grp="Part")
    bolts("FootBolt", (0, 0, -h), (0, 0, -1), 0.3, 0.3, grp="Part")
    cyl("Barrel", 0.14, s - 0.18, (0, 0, -h + 0.08 + (s - 0.18) / 2), segs=24, mat="Spring", bev=0.01, grp="Part")
    cyl("Gland", 0.16, 0.04, (0, 0, h - 0.12), segs=24, mat="SteelDark", grp="Part")
    tube("Hose", [(0.14, 0.0, -h + 0.12), (0.22, 0.05, -h + 0.2), (0.16, 0.0, h - 0.16)], 0.016, mat="Rubber", nring=8, sub=4, grp="Part")
    cyl("Rod", 0.05, s * 1.1, (0, 0, h - 0.06 - s * 0.55), segs=16, mat="Steel", grp="Top")
    box("Head", (s - 0.04, s - 0.04, 0.08), (0, 0, h - 0.04), "Paint", bev=0.008, grp="Top")
    bolts("HeadBolt", (0, 0, h), (0, 0, 1), 0.3, 0.3, grp="Top")
    PIVOTS["Top"] = (0, 0, 0)


def build_turret():
    """A slewing ring: a square steel base bolted down, the toothed ring and the drive motor's pinion
    in it; on it the deck (node Top, turning about its middle) with a bolt grid for what's put on it,
    a low skirt round it and a chevron to show where its front is."""
    sx, sy, sz = ext(PARTS["turret"])
    hz = sz / 2
    box("Base", (sx - 0.04, sy - 0.04, 0.08), (0, 0, -hz + 0.04), "SteelDark", bev=0.008, grp="Part")
    bolts("BaseBolt", (0, 0, -hz), (0, 0, -1), sx * 0.8, sy * 0.8, grp="Part")
    for x in (-1, 1):
        for y in (-1, 1):
            box(f"Gusset{x}{y}", (0.12, 0.12, 0.1), (x * (sx / 2 - 0.1), y * (sy / 2 - 0.1), -hz + 0.13), "Paint", bev=0.006, grp="Part")
    cyl("Ring", 0.44, 0.1, (0, 0, -hz + 0.13), segs=48, mat="Steel", grp="Part")
    for k in range(36):
        a = k * 2 * PI / 36
        box(f"Tooth{k}", (0.03, 0.02, 0.08), (math.cos(a) * 0.455, math.sin(a) * 0.455, -hz + 0.13), "SteelDark",
            rot=(0, 0, a), grp="Part")
    box("MotorBox", (0.14, 0.2, 0.14), (0.36, -0.36, -hz + 0.15), "Paint", bev=0.01, grp="Part")
    cyl("Pinion", 0.04, 0.06, (0.33, -0.3, -hz + 0.13), segs=10, mat="SteelDark", grp="Part")
    tube("Cable", [(0.43, -0.36, -hz + 0.12), (0.47, -0.3, -hz + 0.1), (0.47, -0.1, -hz + 0.09)], 0.012,
         mat="Rubber", nring=8, sub=3, grp="Part")
    # the deck
    box("Deck", (sx - 0.08, sy - 0.08, 0.07), (0, 0, hz - 0.035), "Paint", bev=0.012, grp="Top")
    box("Skirt", (sx - 0.12, sy - 0.12, 0.08), (0, 0, hz - 0.11), "PaintDark", bev=0.008, grp="Top")
    for i in range(3):
        for j in range(3):
            cyl(f"Hole{i}{j}", 0.022, 0.012, ((i - 1) * 0.3, (j - 1) * 0.3, hz + 0.001), segs=8, mat="SteelDark", grp="Top")
    for k, sgn in enumerate((-1, 1)):
        box(f"Chevron{k}", (0.2, 0.05, 0.005), (sgn * 0.07, sy / 2 - 0.16, hz + 0.003), "Hazard",
            rot=(0, 0, sgn * 0.6), grp="Top")
    PIVOTS["Top"] = (0, 0, 0)


def build_ammo():
    """An ammunition box: pressed steel in olive, ribbed, its lid clamped shut by two latches, a
    carrying handle, a stencilled band; bolted down through its feet."""
    s = CELL
    h = s / 2
    box("Body", (s - 0.08, s - 0.14, s - 0.1), (0, 0, -0.04), "Olive", bev=0.012, grp="Part")
    for y in (-0.11, 0.0, 0.11):
        box(f"Rib{y}", (s - 0.06, 0.025, s - 0.2), (0, y, -0.05), "Olive", bev=0.006, grp="Part")
    box("Lid", (s - 0.06, s - 0.12, 0.05), (0, 0, h - 0.07), "Olive", bev=0.01, grp="Part")
    box("Seal", (s - 0.09, s - 0.15, 0.012), (0, 0, h - 0.1), "Rubber", grp="Part")
    for x in (-0.13, 0.13):
        box(f"Latch{x}", (0.06, 0.03, 0.12), (x, -(s - 0.14) / 2 - 0.012, h - 0.12), "Steel", bev=0.004, grp="Part")
    cyl_between("Handle", (-0.09, 0, h - 0.02), (0.09, 0, h - 0.02), 0.012, mat="SteelDark", grp="Part")
    for x in (-0.09, 0.09):
        cyl_between(f"HandlePost{x}", (x, 0, h - 0.05), (x, 0, h - 0.02), 0.012, mat="SteelDark", grp="Part")
    box("Band", (s - 0.079, 0.004, 0.06), (0, -(s - 0.14) / 2 - 0.001, 0.02), "Spring", grp="Part")
    box("Stencil", (0.22, 0.003, 0.03), (0, -(s - 0.14) / 2 - 0.004, -0.06), "Hazard", grp="Part")
    for x in (-1, 1):
        box(f"Foot{x}", (0.06, s - 0.06, 0.04), (x * 0.17, 0, -h + 0.02), "SteelDark", bev=0.004, grp="Part")
    bolts("FootBolt", (0, 0, -h), (0, 0, -1), 0.34, 0.34, grp="Part")


def build_barrel():
    """A barrel kit: two spare barrels with their cooling jackets laid in a cradle on a bolted base,
    held by straps, a clamp and a coupling ready to go on."""
    s = CELL
    h = s / 2
    box("Base", (s - 0.04, s - 0.04, 0.05), (0, 0, -h + 0.025), "SteelDark", bev=0.006, grp="Part")
    bolts("BaseBolt", (0, 0, -h), (0, 0, -1), 0.3, 0.3, grp="Part")
    for y in (-0.16, 0.16):
        box(f"Cradle{y}", (s - 0.08, 0.05, 0.16), (0, y, -h + 0.13), "Paint", bev=0.008, grp="Part")
    for x in (-0.1, 0.1):
        z = -h + 0.25
        cyl(f"Tube{x}", 0.045, s - 0.04, (x, 0, z), axis="Y", segs=18, mat="SteelDark", grp="Part")
        for k in range(5):
            cyl(f"Jacket{x}{k}", 0.058, 0.025, (x, -0.18 + k * 0.09, z), axis="Y", segs=18, mat="Steel", grp="Part")
        cyl(f"Bore{x}", 0.02, 0.01, (x, (s - 0.04) / 2 + 0.001, z), axis="Y", segs=10, mat="Slot", grp="Part")
    for y in (-0.16, 0.16):
        box(f"Strap{y}", (s - 0.1, 0.035, 0.012), (0, y, -h + 0.31), "Rubber", grp="Part")
    cyl("Coupling", 0.07, 0.09, (0, 0, h - 0.07), segs=18, mat="Steel", grp="Part")
    box("Tag", (0.12, 0.003, 0.05), (0.13, -(s - 0.08) / 2, -h + 0.13), "Hazard", grp="Part")


def build_crane():
    """A slewing crane: a ring bolted down (as the turret's) and on it, slewing, the deck, the king
    post, a lattice boom angled up and out forward to its tip sheave, the luffing ram under it, the
    hoist drum and the counterweight behind the post. The game hangs the rope from the tip."""
    sx, sy, sz = ext(PARTS["crane"])
    hz = sz / 2
    box("Base", (sx - 0.04, sy - 0.04, 0.08), (0, 0, -hz + 0.04), "SteelDark", bev=0.008, grp="Part")
    bolts("BaseBolt", (0, 0, -hz), (0, 0, -1), sx * 0.8, sy * 0.8, grp="Part")
    cyl("Ring", 0.42, 0.1, (0, 0, -hz + 0.13), segs=48, mat="Steel", grp="Part")
    # what slews
    cyl("Deck", 0.46, 0.08, (0, 0, hz - 0.04), segs=40, mat="Paint", bev=0.01, grp="Top")
    box("Post", (0.24, 0.24, 1.45), (0, -0.05, hz + 0.72), "Paint", bev=0.02, grp="Top")
    box("PostCap", (0.3, 0.3, 0.06), (0, -0.05, hz + 1.46), "SteelDark", bev=0.01, grp="Top")
    tip = Vector((0, 2.5, 1.85))
    for x in (-0.09, 0.09):  # (the top chords)
        cyl_between(f"Chord{x}", (x, 0.02, 1.5), (x * 0.5, tip.y - 0.05, tip.z), 0.032, mat="Paint", grp="Top")
    cyl_between("ChordLow", (0, 0.08, 1.24), (0, tip.y - 0.12, tip.z - 0.12), 0.032, mat="Paint", grp="Top")
    for k in range(7):  # (the lacing)
        f0 = k / 7.0
        f1 = (k + 1) / 7.0
        a = Vector((0.0, 0.02, 1.5)).lerp(Vector((0, tip.y - 0.05, tip.z)), f0)
        b = Vector((0.0, 0.08, 1.24)).lerp(Vector((0, tip.y - 0.12, tip.z - 0.12)), f1)
        for x in (-1, 1):
            cyl_between(f"Lace{k}{x}", (x * 0.08 * (1 - f0 * 0.5), a.y, a.z), (0, b.y, b.z), 0.013, mat="SteelDark", grp="Top")
    cyl("Sheave", 0.09, 0.06, tuple(tip), axis="X", segs=20, mat="Steel", grp="Top")
    for x in (-0.05, 0.05):
        box(f"Cheek{x}", (0.015, 0.22, 0.22), (x, tip.y, tip.z), "Paint", bev=0.004, grp="Top")
    cyl_between("Ram", (0, 0.12, hz + 0.25), (0, 0.75, 1.32), 0.055, mat="Paint", grp="Top")
    cyl_between("RamRod", (0, 0.75, 1.32), (0, 1.15, 1.42), 0.028, mat="Steel", grp="Top")
    cyl("Drum", 0.12, 0.3, (0, -0.32, hz + 0.32), axis="X", segs=20, mat="SteelDark", grp="Top")
    cyl("Wound", 0.135, 0.24, (0, -0.32, hz + 0.32), axis="X", segs=20, mat="Steel", grp="Top")
    box("Counterweight", (0.6, 0.26, 0.34), (0, -0.4, hz + 0.08), "PaintDark", bev=0.015, grp="Top")
    for k in range(3):
        box(f"Stripe{k}", (0.06, 0.004, 0.3), (-0.2 + k * 0.2, -0.531, hz + 0.08), "Hazard", rot=(0, 0.6, 0), grp="Top")
    tube("Rope", [(0, -0.32, hz + 0.46), (0, -0.05, 1.62), (0, tip.y - 0.1, tip.z + 0.08)], 0.008, mat="SteelDark",
         nring=6, sub=2, grp="Top")
    PIVOTS["Top"] = (0, 0, 0)


def build_winch():
    """A recovery winch: side plates on a base bolted down, the drum of wire rope between them, the
    motor on one side and the gearbox on the other, the fairlead's four rollers at the back where the
    rope comes out, its hook stowed against them."""
    sx, sy, sz = ext(PARTS["winch"])
    hz = sz / 2
    box("Base", (sx - 0.04, sy - 0.04, 0.06), (0, 0, -hz + 0.03), "SteelDark", bev=0.006, grp="Part")
    bolts("BaseBolt", (0, 0.2, -hz), (0, 0, -1), 0.3, 0.3, grp="Part")
    for x in (-0.2, 0.2):
        box(f"Side{x}", (0.04, 0.5, 0.4), (x, 0.12, -0.02), "Paint", bev=0.008, grp="Part")
    cyl("Drum", 0.1, 0.36, (0, 0.12, -0.02), axis="X", segs=20, mat="SteelDark", grp="Part")
    cyl("Wound", 0.15, 0.32, (0, 0.12, -0.02), axis="X", segs=24, mat="Steel", grp="Part")
    cyl("Motor", 0.08, 0.14, (0.17, 0.32, -0.08), axis="X", segs=16, mat="SteelDark", grp="Part")
    box("Gearbox", (0.06, 0.18, 0.2), (-0.23, 0.12, -0.02), "PaintDark", bev=0.008, grp="Part")
    box("Fairlead", (sx - 0.06, 0.08, 0.3), (0, -0.44, -0.05), "Paint", bev=0.01, grp="Part")
    for x in (-0.07, 0.07):
        cyl(f"RollerV{x}", 0.03, 0.22, (x, -0.47, -0.05), segs=12, mat="Steel", grp="Part")
    for z in (-0.12, 0.02):
        cyl(f"RollerH{z}", 0.03, 0.2, (0, -0.47, z), axis="X", segs=12, mat="Steel", grp="Part")
    tube("Rope", [(0, 0.12, 0.12), (0, -0.2, 0.0), (0, -0.48, -0.05)], 0.009, mat="SteelDark", nring=6, sub=2, grp="Part")
    box("Hook", (0.05, 0.05, 0.12), (0, -0.53, -0.09), "Spring", bev=0.01, grp="Part")
    box("Stripe", (0.3, 0.004, 0.05), (0, -0.485, 0.07), "Hazard", grp="Part")


def _rough_beam(name, size, center, rng, mat=None, grp="Part", base=(0, 0, 0)):
    """A hand-hewn beam: a little off true (turned and swollen a touch), one of the woods."""
    mat = mat or rng.choice(["Wood", "WoodPale", "WoodDark", "Wood"])
    k = [1.0 + rng.uniform(-0.12, 0.12) if v < 0.2 else 1.0 for v in size]
    rot = tuple(b + rng.uniform(-0.035, 0.035) for b in base)
    return box(name, (size[0] * k[0], size[1] * k[1], size[2] * k[2]), center, mat, rot=rot, bev=0.008, grp=grp)


def _nail(name, center, normal, grp="Part"):
    cyl(name, 0.008, 0.006, center, axis=normal, segs=6, mat="SteelDark", grp=grp)


def build_wood_cab():
    """The wood age's driver's place: a plank floor on two sills, low boarded sides, a bench with a back,
    four corner posts holding a plank roof, a dash board in front and a spoked wooden wheel on its shaft."""
    import random
    rng = random.Random(31)
    s = ext(PARTS["wood_cab"])
    hx, hy, hz = s.x / 2, s.y / 2, s.z / 2
    for x in (-hx + 0.08, hx - 0.08):
        _rough_beam(f"Sill{x}", (0.1, s.y - 0.02, 0.09), (x, 0, -hz + 0.045), rng, mat="WoodDark")
    for k in range(5):
        y = -hy + s.y / 10 + k * s.y / 5
        _rough_beam(f"Floor{k}", (s.x - 0.02, s.y / 5 - 0.012, 0.05), (0, y, -hz + 0.115), rng)
    for x in (-1, 1):
        for k in range(3):
            _rough_beam(f"Side{x}{k}", (0.045, s.y - 0.1, 0.11), (x * (hx - 0.03), 0, -hz + 0.2 + k * 0.115), rng)
    for k in range(3):
        _rough_beam(f"Back{k}", (s.x - 0.1, 0.045, 0.11), (0, -hy + 0.03, -hz + 0.2 + k * 0.115), rng)
    _rough_beam("Dash", (s.x - 0.1, 0.045, 0.3), (0, hy - 0.03, -hz + 0.3), rng, mat="WoodDark")
    for a in (-1, 1):
        for b in (-1, 1):
            _rough_beam(f"Post{a}{b}", (0.08, 0.08, s.z - 0.12), (a * (hx - 0.05), b * (hy - 0.05), 0.0), rng, mat="WoodDark")
            box(f"Strap{a}{b}", (0.1, 0.1, 0.04), (a * (hx - 0.05), b * (hy - 0.05), -hz + 0.22), "Iron", bev=0.004, grp="Part")
    for k in range(6):
        x = -hx + s.x / 12 + k * s.x / 6
        _rough_beam(f"Roof{k}", (s.x / 6 - 0.01, s.y + 0.08, 0.045), (x, 0.0, hz - 0.03 + (0.02 if k % 2 else 0.0)), rng)
    for y in (-hy + 0.05, hy - 0.05):
        _rough_beam(f"Purlin{y}", (s.x - 0.02, 0.07, 0.07), (0, y, hz - 0.09), rng, mat="WoodDark")
    # the bench, its back and legs
    _rough_beam("Bench", (s.x - 0.24, 0.3, 0.05), (0, -0.12, -0.12), rng, mat="WoodPale")
    _rough_beam("BenchBack", (s.x - 0.24, 0.05, 0.28), (0, -0.3, 0.06), rng, mat="WoodPale", base=(0.2, 0, 0))
    for x in (-0.3, 0.3):
        for y in (-0.22, -0.02):
            _rough_beam(f"Leg{x}{y}", (0.05, 0.05, 0.25), (x, y, -0.26), rng, mat="WoodDark")
    box("Cushion", (s.x - 0.32, 0.26, 0.035), (0, -0.12, -0.08), "Seat", bev=0.012, grp="Part")
    # the wheel: a shaft out of the dash, four spokes, a rim of bent wood
    cyl_between("Shaft", (0, hy - 0.06, -0.05), (0, 0.18, 0.12), 0.022, mat="Iron", segs=8, grp="Part")
    w = Vector((0, 0.17, 0.13))
    for k in range(16):
        a0 = k * 2 * PI / 16
        a1 = a0 + 2 * PI / 16
        p0 = w + Vector((math.cos(a0) * 0.15, math.sin(a0) * 0.15 * 0.5, -math.sin(a0) * 0.15 * 0.85))
        p1 = w + Vector((math.cos(a1) * 0.15, math.sin(a1) * 0.15 * 0.5, -math.sin(a1) * 0.15 * 0.85))
        cyl_between(f"Rim{k}", tuple(p0), tuple(p1), 0.016, mat="Wood", segs=6, grp="Part")
    for k in range(4):
        a = k * PI / 2 + PI / 4
        p1 = w + Vector((math.cos(a) * 0.14, math.sin(a) * 0.14 * 0.5, -math.sin(a) * 0.14 * 0.85))
        cyl_between(f"Spoke{k}", tuple(w), tuple(p1), 0.01, mat="WoodPale", segs=6, grp="Part")
    for x in (-1, 1):
        _nail(f"NailBack{x}", (x * 0.4, -hy + 0.002, -hz + 0.3), "Y")


def build_wood_crane():
    """A small slewing crane of timber: a square sill and an iron ring bolted down, and on it, slewing
    (Top), a plank table, the king post, a short pole jib out forward to its sheave, a brace under it, a
    windlass drum with its crank on the post and a box of stones behind for the weight. The game hangs the
    rope from the tip (Godot 0, 1.45, -1.8)."""
    import random
    rng = random.Random(17)
    sx, sy, sz = ext(PARTS["wood_crane"])
    hz = sz / 2
    for y in (-sy / 2 + 0.06, sy / 2 - 0.06):
        _rough_beam(f"SillY{y}", (sx - 0.04, 0.1, 0.08), (0, y, -hz + 0.04), rng, mat="WoodDark")
    for x in (-sx / 2 + 0.06, sx / 2 - 0.06):
        _rough_beam(f"SillX{x}", (0.1, sy - 0.2, 0.08), (x, 0, -hz + 0.04), rng, mat="WoodDark")
    bolts("BaseBolt", (0, 0, -hz), (0, 0, -1), sx * 0.7, sy * 0.7, grp="Part")
    cyl("Ring", 0.32, 0.06, (0, 0, -hz + 0.11), segs=32, mat="Iron", grp="Part")
    # what slews
    for k in range(4):
        _rough_beam(f"Table{k}", (0.7, 0.17, 0.05), (0, -0.27 + k * 0.18, hz - 0.08), rng, grp="Top")
    _rough_beam("Post", (0.16, 0.16, 1.2), (0, -0.05, hz + 0.52), rng, mat="WoodDark", grp="Top")
    box("PostCap", (0.2, 0.2, 0.05), (0, -0.05, hz + 1.13), "Iron", bev=0.006, grp="Top")
    tip = Vector((0, 1.8, 1.45))
    root = Vector((0, -0.05, 1.28))
    cyl_between("JibPole", tuple(root), tuple(tip + Vector((0, 0.05, 0.02))), 0.06, mat="Wood", segs=10, grp="Jib")
    cyl_between("Brace", tuple(root.lerp(tip, 0.12) + Vector((0, 0, -0.03))), tuple(root.lerp(tip, 0.5) + Vector((0, 0, -0.04))),
                0.035, mat="WoodDark", segs=8, grp="Jib")
    cyl_between("Stay", (0, -0.05, hz + 1.14), (0, -0.42, hz + 0.32), 0.022, mat="Rope", segs=6, grp="Top")
    for f in (0.2, 0.55, 0.9):
        q = root.lerp(tip, f)
        cyl(f"Band{f}", 0.068, 0.04, tuple(q), axis=tuple((tip - root).normalized()), segs=10, mat="Iron", grp="Jib")
    cyl("Sheave", 0.06, 0.04, tuple(tip), axis="X", segs=16, mat="Iron", grp="Jib")
    for x in (-0.04, 0.04):
        box(f"Cheek{x}", (0.012, 0.16, 0.14), (x, tip.y, tip.z), "WoodDark", bev=0.003, grp="Jib")
    # the windlass: a drum across the post, a crank each side
    cyl("Drum", 0.07, 0.34, (0, 0.1, hz + 0.42), axis="X", segs=14, mat="WoodPale", grp="Top")
    cyl("Wound", 0.08, 0.24, (0, 0.1, hz + 0.42), axis="X", segs=14, mat="Rope", grp="Top")
    for x in (-1, 1):
        box(f"Cheek2{x}", (0.03, 0.18, 0.2), (x * 0.19, 0.06, hz + 0.42), "WoodDark", bev=0.004, grp="Top")
        cyl_between(f"Crank{x}", (x * 0.2, 0.1, hz + 0.42), (x * 0.24, 0.1, hz + 0.42), 0.015, mat="Iron", segs=6, grp="Top")
        cyl_between(f"Arm{x}", (x * 0.24, 0.1, hz + 0.42), (x * 0.24, 0.1, hz + 0.55), 0.014, mat="Iron", segs=6, grp="Top")
        cyl_between(f"Grip{x}", (x * 0.24, 0.1, hz + 0.55), (x * 0.3, 0.1, hz + 0.55), 0.02, mat="WoodPale", segs=6, grp="Top")
    tube("Rope", [tuple(root + Vector((0, 0.05, 0.07))), tuple(root.lerp(tip, 0.5) + Vector((0, 0, 0.07))),
                  (0, tip.y - 0.1, tip.z + 0.04)], 0.009, mat="Rope", nring=6, sub=2, grp="Jib")
    cyl_between("RopeDown", (0, 0.17, hz + 0.45), tuple(root + Vector((0, 0.05, 0.07))), 0.009, mat="Rope", segs=6, grp="Top")
    # the weight: a plank box of stones behind the post
    for y in (-0.5, -0.24):
        _rough_beam(f"BoxEnd{y}", (0.5, 0.04, 0.22), (0, y, hz + 0.08), rng, mat="WoodDark", grp="Top")
    for x in (-0.24, 0.24):
        _rough_beam(f"BoxSide{x}", (0.04, 0.3, 0.22), (x, -0.37, hz + 0.08), rng, mat="WoodDark", grp="Top")
    for k in range(9):
        r = rng.uniform(0.06, 0.09)
        cyl(f"Stone{k}", r, r * 1.4, (rng.uniform(-0.16, 0.16), rng.uniform(-0.45, -0.29), hz + 0.12 + rng.uniform(0, 0.08)),
            axis=(rng.uniform(-1, 1), rng.uniform(-1, 1), 1), segs=7, mat="Stone", grp="Top")
    PIVOTS["Top"] = (0, 0, 0)
    PIVOTS["Jib"] = tuple(root)  # (Godot 0, 1.28, 0.05: it luffs about X there)


def build_wood_rail():
    """A metre of rail fencing: two posts, three rails across nailed to them, iron straps at the feet."""
    import random
    rng = random.Random(23)
    s = ext(PARTS["wood_rail"])
    hx, hz = s.x / 2, s.z / 2
    for x in (-hx + 0.05, hx - 0.05):
        _rough_beam(f"Post{x}", (0.07, 0.07, s.z - 0.02), (x, 0, 0), rng, mat="WoodDark")
        box(f"Foot{x}", (0.09, 0.09, 0.05), (x, 0, -hz + 0.03), "Iron", bev=0.003, grp="Part")
    for k, z in enumerate((-0.28, 0.08, 0.4)):
        _rough_beam(f"Rail{k}", (s.x - 0.01, 0.045, 0.1), (0, 0.055, z), rng)
        for x in (-hx + 0.05, hx - 0.05):
            _nail(f"Nail{k}{x}", (x, 0.079, z), "Y")


def build_wood_frame():
    """A lattice of rough-sawn timber, a touch off square, braced across two sides, pegged and nailed."""
    import random
    rng = random.Random(7)
    s = CELL
    h = s / 2
    t = 0.085
    for a in (-1, 1):
        for b in (-1, 1):
            _rough_beam(f"EdgeZ{a}{b}", (t, t, s), (a * (h - t / 2), b * (h - t / 2), 0), rng)
            _rough_beam(f"EdgeY{a}{b}", (t, s - 2 * t, t), (a * (h - t / 2), 0, b * (h - t / 2)), rng)
            _rough_beam(f"EdgeX{a}{b}", (s - 2 * t, t, t), (0, a * (h - t / 2), b * (h - t / 2)), rng)
    for a in (-1, 1):
        cyl_between(f"Brace{a}", (a * (h - t / 2), -h + t, -h + t), (a * (h - t / 2), h - t, h - t), 0.03, mat="WoodDark",
                    segs=6, grp="Part")
    for a in (-1, 1):
        for b in (-1, 1):
            for c in (-1, 1):
                _nail(f"Nail{a}{b}{c}", (a * (h + 0.001), b * (h - t / 2), c * (h - t / 2)), "X")
                cyl(f"Peg{a}{b}{c}", 0.014, 0.012, (a * (h - t / 2), b * (h - t / 2), c * (h + 0.002)), axis="Z", segs=8,
                    mat="WoodPale", grp="Part")


def build_wood_plate():
    """Four thick planks across the cell's outer face, nailed to two battens on two legs."""
    import random
    rng = random.Random(11)
    s = CELL
    h = s / 2
    th = 0.07
    for k in range(4):
        w = s / 4 - 0.006
        x = -h + s / 8 + k * s / 4
        _rough_beam(f"Plank{k}", (w, th, s - 0.01), (x, h - th / 2, rng.uniform(-0.006, 0.006)), rng)
        for z in (-0.17, 0.17):
            _nail(f"Nail{k}{z}", (x, h + 0.001, z), "Y")
    for z in (-0.17, 0.17):
        _rough_beam(f"Batten{z}", (s - 0.03, 0.07, 0.08), (0, h - th - 0.035, z), rng, mat="WoodDark")
    for x in (-0.17, 0.17):
        _rough_beam(f"Leg{x}", (0.07, s - th - 0.1, 0.07), (x, -0.06, 0), rng, mat="WoodDark")
    _rough_beam("Back", (s - 0.05, 0.04, 0.12), (0, -h + 0.02, 0), rng, mat="WoodDark")


def build_wood_wedge():
    """Two side boards high at the back, planks nailed down the slope between them, a sill at the foot."""
    import random
    rng = random.Random(5)
    s = CELL
    h = s / 2
    for x in (-h + 0.02, h - 0.02):
        prof = [(-h, -h), (h, -h), (-h, h)]
        verts = [(x + dx, y, z) for dx in (-0.02, 0.02) for (y, z) in prof]
        faces = [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
        bt.mk(f"Side{x}", verts, faces, ("WoodDark",), grp="Part", smooth=0)
    n = Vector((0, 1, 1)).normalized()
    length = s * math.sqrt(2)
    for k in range(5):
        f = (k + 0.5) / 5
        p = Vector((0, -h + f * s, h - f * s)) + n * 0.03
        _rough_beam(f"Plank{k}", (s - 0.01, length / 5 - 0.008, 0.055), tuple(p), rng, base=(-PI / 4, 0, 0))
        for x in (-0.2, 0.2):
            _nail(f"Nail{k}{x}", tuple(p + n * 0.029 + Vector((x, 0, 0))), tuple(n))
    _rough_beam("Sill", (s - 0.03, 0.08, 0.08), (0, -h + 0.04, -h + 0.04), rng, mat="WoodDark")


def build_saw():
    """A feller's saw head: the mount bolted on behind, two arms forward to the hub, the hydraulic motor
    over it, the blade under (node Blade: spins about up) with its teeth, a guard over its back half."""
    sx, sy, sz = ext(PARTS["saw"])
    hy = sy / 2
    c = Vector((0, 0.95, -0.4))  # (the blade's middle, low: Godot 0, -0.4, -0.95)
    import random
    rng = random.Random(4)
    for x in (-0.3, 0.0, 0.3):
        _rough_beam(f"Mount{x}", (0.24, 0.3, sz - 0.08), (x, -hy + 0.15, 0), rng, mat="WoodDark")
    bolts("MountBolt", (0, -hy, 0), (0, -1, 0), sx * 0.7, sz * 0.6, grp="Part")
    for x in (-0.16, 0.16):
        cyl_between(f"Arm{x}", (x, -hy + 0.25, 0.05), (x * 0.4, c.y - 0.05, c.z + 0.11), 0.05, mat="WoodDark", grp="Arm")
    box("Yoke", (0.24, 0.2, 0.06), (0, c.y - 0.05, c.z + 0.11), "Iron", bev=0.01, grp="Arm")
    cyl("Motor", 0.08, 0.16, (0, c.y, c.z + 0.2), segs=20, mat="SteelDark", bev=0.01, grp="Arm")
    cyl("MotorCap", 0.05, 0.03, (0, c.y, c.z + 0.29), segs=16, mat="Steel", grp="Arm")
    for x in (-0.05, 0.05):
        tube(f"Hose{x}", [(x, -hy + 0.3, 0.12), (x * 2, 0.3, 0.2), (x, c.y - 0.08, c.z + 0.25)], 0.014, mat="Rubber",
             nring=6, sub=2, grp="Arm")
    # the guard: a flat hood over the blade's back half, its rim turned down
    for k in range(12):
        a0 = PI + k * PI / 12
        a1 = a0 + PI / 12
        am = (a0 + a1) / 2
        r = 0.6
        p = c + Vector((math.cos(am) * r * 0.5, math.sin(am) * r * 0.5, 0.06))
        box(f"Hood{k}", (r, r * math.sin(PI / 12) * 1.05, 0.012), tuple(p), "Iron", rot=(0, 0, am), grp="Arm")
        q = c + Vector((math.cos(am) * r, math.sin(am) * r, 0.02))
        box(f"Rim{k}", (0.012, 2 * r * math.sin(PI / 24) * 1.05, 0.08), tuple(q), "Iron", rot=(0, 0, am), grp="Arm")
    # the blade
    cyl("Disc", 0.53, 0.012, tuple(c), segs=48, mat="Blade", grp="Blade")
    cyl("Hub", 0.09, 0.04, tuple(c + Vector((0, 0, 0.015))), segs=20, mat="SteelDark", grp="Blade")
    for k in range(6):
        a = k * PI / 3
        cyl(f"Bolt{k}", 0.012, 0.02, tuple(c + Vector((math.cos(a) * 0.06, math.sin(a) * 0.06, 0.035))), segs=6,
            mat="Bolt", grp="Blade")
    for k in range(30):
        a = k * 2 * PI / 30
        p = c + Vector((math.cos(a), math.sin(a), 0)) * 0.545
        box(f"Tooth{k}", (0.05, 0.03, 0.026), tuple(p), "SteelDark", rot=(0, 0, a + 0.5), grp="Blade")
    PIVOTS["Blade"] = tuple(c)
    PIVOTS["Arm"] = (0, -hy + 0.25, 0.05)  # (Godot 0, 0.05, 0.25: it swings up about X there, the blade kept level)


def build_steer():
    """A steering knuckle: the base plate bolted down, the kingpin housing standing on it with its grease
    nipple, the hydraulic steering ram lying along one side to the arm on the turning part; on top (node
    Top) the flange plate, its bolts, the steering arm and a chevron for its front."""
    s = CELL
    h = s / 2
    box("Base", (s - 0.03, s - 0.03, 0.06), (0, 0, -h + 0.03), "SteelDark", bev=0.006, grp="Part")
    bolts("BaseBolt", (0, 0, -h), (0, 0, -1), 0.32, 0.32, grp="Part")
    cyl("Housing", 0.11, 0.3, (0, 0, -h + 0.2), segs=24, mat="Paint", bev=0.01, grp="Part")
    for z in (-h + 0.09, -h + 0.31):
        cyl(f"Collar{z}", 0.125, 0.03, (0, 0, z), segs=24, mat="SteelDark", grp="Part")
    cyl("Nipple", 0.012, 0.03, (0.12, 0, -h + 0.22), axis="X", segs=8, mat="Steel", grp="Part")
    box("RamFoot", (0.06, 0.08, 0.08), (-0.17, -0.17, -h + 0.1), "Paint", bev=0.006, grp="Part")
    cyl_between("Ram", (-0.17, -0.17, -h + 0.14), (-0.17, 0.08, h - 0.14), 0.03, mat="Paint", segs=12, grp="Part")
    cyl_between("RamRod", (-0.17, 0.08, h - 0.14), (-0.15, 0.17, h - 0.1), 0.014, mat="Steel", segs=10, grp="Part")
    tube("Hose", [(-0.17, -0.2, -h + 0.12), (-0.22, -0.1, -h + 0.08), (-0.2, 0.1, -h + 0.06)], 0.009, mat="Rubber",
         nring=6, sub=2, grp="Part")
    # what turns
    cyl("Spindle", 0.06, 0.1, (0, 0, h - 0.13), segs=16, mat="Steel", grp="Top")
    box("Flange", (s - 0.05, s - 0.05, 0.05), (0, 0, h - 0.025), "Paint", bev=0.008, grp="Top")
    bolts("FlangeBolt", (0, 0, h), (0, 0, 1), 0.3, 0.3, grp="Top")
    box("Arm", (0.06, 0.16, 0.04), (-0.15, 0.15, h - 0.08), "PaintDark", bev=0.006, grp="Top")
    for k, sgn in enumerate((-1, 1)):
        box(f"Chevron{k}", (0.12, 0.03, 0.004), (sgn * 0.04, h - 0.09, h + 0.002), "Hazard", rot=(0, 0, sgn * 0.6), grp="Top")
    PIVOTS["Top"] = (0, 0, 0)


def build_wood_wheel(pid="wood_wheel"):
    """A cart wheel on a timber block: the iron tyre round a rim of felloes, twelve spokes into a turned
    hub with its iron bands; the block it turns on bolted on at the inner face, an iron strap round it.
    wood_wheel_l is the wagon's: bigger, broader, sixteen spokes."""
    import random
    rng = random.Random(3)
    fx, fy, fz = ext(PARTS[pid])
    big = pid == "wood_wheel_l"
    r, w = (0.62, 0.2) if big else (0.42, 0.12)
    hub = Vector((fx / 2 - w / 2 - 0.02, 0, 0))
    revolve("Tyre", [(-w / 2, r - 0.025), (-w / 2, r), (w / 2, r), (w / 2, r - 0.025)], 40, ("SteelDark",), axis="X",
            grp="Wheel", smooth=40)
    revolve("Felloe", [(-w * 0.42, r - 0.09), (-w * 0.42, r - 0.025), (w * 0.42, r - 0.025), (w * 0.42, r - 0.09)], 36,
            ("Wood",), axis="X", grp="Wheel", smooth=40)
    n_sp = 16 if big else 12
    hr = 0.12 if big else 0.08
    for k in range(n_sp):
        a = k * 2 * PI / n_sp + rng.uniform(-0.02, 0.02)
        p0 = Vector((0, math.cos(a) * (hr - 0.01), math.sin(a) * (hr - 0.01)))
        p1 = Vector((0, math.cos(a) * (r - 0.08), math.sin(a) * (r - 0.08)))
        cyl_between(f"Spoke{k}", tuple(p0), tuple(p1), 0.026 if big else 0.018, mat=rng.choice(["Wood", "WoodPale"]), segs=6,
                    grp="Wheel")
    cyl("Hub", hr, w * 1.5, (0, 0, 0), axis="X", segs=16, mat="WoodDark", grp="Wheel")
    for x in (-w * 0.6, w * 0.6):
        cyl(f"Band{x}", hr + 0.005, 0.02, (x, 0, 0), axis="X", segs=16, mat="SteelDark", grp="Wheel")
    cyl("Cap", 0.04, 0.03, (w * 0.8, 0, 0), axis="X", segs=10, mat="SteelDark", grp="Wheel")
    # the block it turns on
    mx = -fx / 2 + 0.02
    _rough_beam("Block", (0.16, CELL * (1.6 if big else 0.8), CELL * (1.2 if big else 0.6)), (mx + 0.08, 0, 0), rng, mat="WoodDark")
    box("Strap", (0.17, 0.03, CELL * 0.62), (mx + 0.08, 0.12, 0), "SteelDark", bev=0.003, grp="Part")
    bolts("MountBolt", (mx - 0.005, 0, 0), (-1, 0, 0), CELL * 0.5, CELL * 0.4, grp="Part")
    cyl_between("Axle", (mx + 0.16, 0, 0), (hub.x - w * 0.5, 0, 0), 0.03, mat="SteelDark", segs=10, grp="Part")
    for o in [o for o in bpy.data.objects if o.get("grp") == "Wheel"]:
        o.location = Vector(o.location) + hub
    return hub


def _timber_ring(sx, sy, hz, rng):
    """A turning mount of timber: a square sill bolted down, an iron ring, the table (Turret) on it."""
    for y in (-sy / 2 + 0.06, sy / 2 - 0.06):
        _rough_beam(f"SillY{y}", (sx - 0.04, 0.1, 0.08), (0, y, -hz + 0.04), rng, mat="WoodDark")
    for x in (-sx / 2 + 0.06, sx / 2 - 0.06):
        _rough_beam(f"SillX{x}", (0.1, sy - 0.2, 0.08), (x, 0, -hz + 0.04), rng, mat="WoodDark")
    bolts("BaseBolt", (0, 0, -hz), (0, 0, -1), sx * 0.7, sy * 0.7, grp="Part")
    cyl("Ring", 0.3, 0.05, (0, 0, -hz + 0.1), segs=28, mat="SteelDark", grp="Part")
    cyl("Table", 0.32, 0.05, (0, 0, -hz + 0.15), segs=28, mat="Wood", grp="Turret")
    return -hz + 0.15


def build_ballista():
    """A ballista: the stock along its groove on a yoke, two bow limbs out of the head, the string drawn
    back to the nut, the windlass at the back with its spokes, a bolt in the groove (node Rocket0)."""
    import random
    rng = random.Random(21)
    sx, sy, sz = ext(PARTS["ballista"])
    hz = sz / 2
    yaw_z = _timber_ring(sx, sy, hz, rng)
    for x in (-0.12, 0.12):
        _rough_beam(f"Yoke{x}", (0.06, 0.12, 0.22), (x, 0.0, yaw_z + 0.12), rng, mat="WoodDark", grp="Turret")
    trun = Vector((0, 0.0, yaw_z + 0.22))
    _rough_beam("Stock", (0.12, 1.15, 0.1), tuple(trun + Vector((0, 0.1, 0.02))), rng, grp="Gun")
    box("Groove", (0.03, 1.1, 0.01), tuple(trun + Vector((0, 0.1, 0.075))), "WoodDark", grp="Gun")
    head = trun + Vector((0, 0.55, 0.05))
    box("Head", (0.22, 0.12, 0.14), tuple(head), "WoodDark", bev=0.01, grp="Gun")
    for k in range(2):
        box(f"HeadBand{k}", (0.23, 0.015, 0.15), tuple(head + Vector((0, -0.04 + k * 0.08, 0))), "SteelDark", grp="Gun")
    tips = []
    for sgn in (-1, 1):
        pts = [tuple(head + Vector((sgn * 0.1, 0, 0))), tuple(head + Vector((sgn * 0.35, -0.05, 0))),
               tuple(head + Vector((sgn * 0.55, -0.16, 0)))]
        tube(f"Limb{sgn}", pts, 0.03, mat="Wood", nring=8, sub=3, grp="Gun")
        tips.append(head + Vector((sgn * 0.55, -0.16, 0)))
    nut = trun + Vector((0, -0.25, 0.08))
    for k, t in enumerate(tips):
        tube(f"String{k}", [tuple(t), tuple(nut)], 0.006, mat="Seat", nring=5, sub=1, grp="Gun")
    cyl("Windlass", 0.05, 0.26, tuple(trun + Vector((0, -0.4, 0.0))), axis="X", segs=12, mat="WoodDark", grp="Gun")
    for sgn in (-1, 1):
        for k in range(4):
            a = k * PI / 2
            cyl_between(f"Spoke{sgn}{k}", tuple(trun + Vector((sgn * 0.14, -0.4, 0))),
                        tuple(trun + Vector((sgn * 0.14, -0.4 + math.cos(a) * 0.12, math.sin(a) * 0.12))), 0.01,
                        mat="Wood", segs=6, grp="Gun")
    # the bolt
    b0 = trun + Vector((0, -0.22, 0.1))
    cyl_between("Shaft", tuple(b0), tuple(b0 + Vector((0, 0.95, 0))), 0.012, mat="WoodPale", segs=8, grp="Rocket0")
    cyl("BoltHead", 0.022, 0.09, tuple(b0 + Vector((0, 0.99, 0))), axis="Y", r2=0.002, segs=8, mat="SteelDark", grp="Rocket0")
    for k in range(3):
        a = k * 2 * PI / 3
        box(f"Fletch{k}", (0.002, 0.1, 0.03), tuple(b0 + Vector((math.sin(a) * 0.02, 0.06, math.cos(a) * 0.02))), "Seat",
            rot=(0, a, 0), grp="Rocket0")
    PIVOTS.update({"Turret": (0, 0, yaw_z), "Gun": tuple(trun), "Rocket0": tuple(trun), "Muzzle": tuple(trun + Vector((0, 0.8, 0.1)))})


def build_catapult():
    """A torsion catapult: the timber bed on the ring with its uprights (Turret); the axle through its
    twisted rope skein (Gun); the arm lying back from it with the sling bucket at its end (Barrels: it
    swings up and over to throw), the stone in the bucket (Rocket0); a padded stop bar on the uprights."""
    import random
    rng = random.Random(33)
    sx, sy, sz = ext(PARTS["catapult"])
    hz = sz / 2
    yaw_z = _timber_ring(sx, sy, hz, rng)
    for x in (-0.38, 0.38):
        _rough_beam(f"Rail{x}", (0.1, sy - 0.1, 0.1), (x, 0, yaw_z + 0.08), rng, mat="WoodDark", grp="Turret")
    for y in (-0.6, 0.0, 0.6):
        _rough_beam(f"Cross{y}", (0.86, 0.09, 0.08), (0, y, yaw_z + 0.16), rng, grp="Turret")
    top = yaw_z + 0.7
    for x in (-0.33, 0.33):
        _rough_beam(f"Upright{x}", (0.1, 0.1, 0.62), (x, 0.1, yaw_z + 0.42), rng, grp="Turret")
        cyl_between(f"Brace{x}", (x, -0.3, yaw_z + 0.16), (x, 0.08, top - 0.12), 0.03, mat="WoodDark", segs=6, grp="Turret")
    _rough_beam("StopBar", (0.76, 0.1, 0.1), (0, 0.22, top + 0.05), rng, grp="Turret")
    cyl("Pad", 0.06, 0.3, (0, 0.17, top + 0.05), axis="X", segs=10, mat="Seat", grp="Turret")
    axle = Vector((0, 0.1, top - 0.2))
    cyl("Axle", 0.04, 0.72, tuple(axle), axis="X", segs=12, mat="SteelDark", grp="Gun")
    for x in (-0.2, 0.2):
        cyl(f"Skein{x}", 0.09, 0.2, tuple(axle + Vector((x, 0, 0))), axis="X", segs=14, mat="Seat", grp="Gun")
    # the arm, lying back (Blender -y is the back) and a little up
    back = Vector((0, -0.95, 0.18))
    end = axle + back
    cyl_between("Arm", tuple(axle), tuple(end), 0.05, mat="Wood", segs=10, grp="Barrels")
    for k in range(3):
        f = 0.25 + k * 0.25
        cyl(f"Lash{k}", 0.058, 0.03, tuple(axle.lerp(end, f)), axis=tuple(back.normalized()), segs=10, mat="SteelDark", grp="Barrels")
    cyl("Bucket", 0.14, 0.1, tuple(end + Vector((0, 0, 0.04))), segs=14, mat="WoodDark", grp="Barrels")
    cyl("BucketIn", 0.11, 0.02, tuple(end + Vector((0, 0, 0.09))), segs=14, mat="Seat", grp="Barrels")
    revolve("Stone", [(-0.09, 0.0), (-0.07, 0.06), (0.0, 0.09), (0.07, 0.07), (0.09, 0.0)], 10, ("PaintDark",), axis="Z",
            center=tuple(end + Vector((0, 0, 0.18))), grp="Rocket0")
    PIVOTS.update({"Turret": (0, 0, yaw_z), "Gun": tuple(axle), "Barrels": tuple(axle), "Rocket0": tuple(axle),
                   "Muzzle": tuple(end + Vector((0, 0, 0.18)))})


def build_oilpot():
    """A cask of boiling oil on a tipping cradle (Gun) over a little brazier: the cask's staves and hoops,
    a spout at its front, a lever arm at its back; Muzzle at the spout."""
    import random
    rng = random.Random(44)
    sx, sy, sz = ext(PARTS["oilpot"])
    hz = sz / 2
    yaw_z = _timber_ring(sx, sy, hz, rng)
    box("Brazier", (0.24, 0.24, 0.07), (0, 0.05, yaw_z + 0.06), "SteelDark", bev=0.01, grp="Turret")
    m = bt.make_mat("Coals", (0.5, 0.1, 0.02), emit=(1.0, 0.35, 0.05), strength=4.0)
    box("Coals", (0.2, 0.2, 0.02), (0, 0.05, yaw_z + 0.1), "Coals", grp="Turret")
    for x in (-0.22, 0.22):
        _rough_beam(f"Post{x}", (0.06, 0.08, 0.3), (x, 0.05, yaw_z + 0.16), rng, mat="WoodDark", grp="Turret")
    trun = Vector((0, 0.05, yaw_z + 0.3))
    cyl("Cask", 0.16, 0.36, tuple(trun + Vector((0, 0.02, 0.06))), axis="Y", segs=18, mat="Wood", grp="Gun")
    for k in range(3):
        cyl(f"Hoop{k}", 0.168, 0.025, tuple(trun + Vector((0, -0.12 + k * 0.14, 0.06))), axis="Y", segs=18, mat="SteelDark", grp="Gun")
    cyl("Spout", 0.04, 0.16, tuple(trun + Vector((0, 0.27, 0.12))), axis="Y", r2=0.03, segs=10, mat="SteelDark", grp="Gun")
    _rough_beam("Lever", (0.05, 0.4, 0.05), tuple(trun + Vector((0.18, -0.3, 0.02))), rng, mat="WoodDark", grp="Gun")
    cyl("Pivot", 0.025, 0.5, tuple(trun), axis="X", segs=8, mat="SteelDark", grp="Gun")
    PIVOTS.update({"Turret": (0, 0, yaw_z), "Gun": tuple(trun), "Muzzle": tuple(trun + Vector((0, 0.36, 0.12)))})


def build_pitch():
    """A cask of pitch standing: bellied staves, three iron hoops, the black pitch at its open top, a ladle."""
    s = CELL
    h = s / 2
    revolve("Staves", [(-h + 0.02, 0.17), (-0.1, 0.2), (0.0, 0.21), (0.1, 0.2), (h - 0.04, 0.17)], 20, ("Wood",), axis="Z",
            grp="Part")
    for z in (-h + 0.06, 0.0, h - 0.08):
        cyl(f"Hoop{z}", 0.205 if abs(z) < 0.01 else 0.18, 0.025, (0, 0, z), segs=20, mat="SteelDark", grp="Part")
    cyl("Pitch", 0.165, 0.02, (0, 0, h - 0.05), segs=20, mat="Hazard", grp="Part")
    cyl_between("Ladle", (0.05, 0.0, h - 0.06), (0.16, 0.08, h + 0.12), 0.012, mat="WoodPale", segs=6, grp="Part")
    bolts("BaseBolt", (0, 0, -h), (0, 0, -1), 0.24, 0.24, grp="Part")


BUILDERS = {"cab": build_cab, "frame": build_frame, "armor": build_armor, "wedge": build_wedge,
            "wheel_s": lambda: build_wheel("wheel_s"), "wheel_l": lambda: build_wheel("wheel_l"),
            "engine": build_engine, "light": build_light, "minigun": build_minigun, "cannon": build_cannon,
            "track": build_track, "rockets": build_rockets, "battery": build_battery, "engine_l": build_engine_l,
            "engine_s": build_engine_s, "spike": build_spike, "flamer": build_flamer, "plate": build_plate,
            "flipper": build_flipper, "hinge": build_hinge, "rotor": build_rotor, "piston": build_piston,
            "turret": build_turret, "ammo": build_ammo, "barrel": build_barrel, "crane": build_crane, "winch": build_winch,
            "saw": build_saw, "wood_cab": build_wood_cab, "wood_crane": build_wood_crane, "wood_rail": build_wood_rail, "wood_frame": build_wood_frame, "wood_plate": build_wood_plate,
            "wood_wedge": build_wood_wedge, "steer": build_steer,
            "wood_wheel": build_wood_wheel, "wood_wheel_l": lambda: build_wood_wheel("wood_wheel_l"), "ballista": build_ballista,
            "catapult": build_catapult, "oilpot": build_oilpot, "pitch": build_pitch}


def icon(pid):
    """The build bar's picture of a part: 256 px, transparent, three-quarter view from above-front."""
    scene = bpy.context.scene
    if "Ground" not in bpy.data.objects:
        vk.studio(OUT_DIR, -ext(PARTS[pid]).z / 2)
    bpy.data.objects["Ground"].hide_render = True
    scene.render.film_transparent = True
    e = ext(PARTS[pid])
    span = max(e.x, e.y, e.z)
    if pid in ("minigun", "cannon", "flamer", "ballista", "oilpot"):
        span *= 1.6
    if pid == "track":
        span *= 0.8  # (the barrels reach past the footprint)
    if pid in ("crane", "wood_crane"):
        span = 2.4 if pid == "crane" else 2.0  # (its boom reaches well past the footprint, up and out)
    d = span * 1.45 + 0.2
    os.makedirs(os.path.join(OUT_DIR, "icons"), exist_ok=True)
    bt.OUT_DIR = OUT_DIR
    cd = bpy.data.cameras.new("Icon")
    cam = bt.link(bpy.data.objects.new("Icon", cd))
    target = Vector((0, 0.15 * span if pid in ("minigun", "cannon") else 0.0, 0))
    if pid == "crane":
        target = Vector((0, 1.1, 0.85))
    if pid == "wood_crane":
        target = Vector((0, 0.8, 0.7))
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
    only = next((a[7:].split(",") for a in argv if a.startswith("--only=")), None)
    for pid, fn in BUILDERS.items():
        if only and pid not in only:
            continue
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
        for g in ["Road%d" % k for k in range(5)] + ["Sprocket", "Idler", "Belt", "Blade", "Jib", "Arm"]:
            if any(o.get("grp") == g for o in bpy.data.objects):
                nodes.append(bt.bake_group(g, g, PIVOTS[g]))
        if any(o.get("grp") == "Turret" for o in bpy.data.objects):
            nodes += turret_nodes()
        if any(o.get("grp") == "Flap" for o in bpy.data.objects):
            nodes.append(bt.bake_group("Flap", "Flap", PIVOTS["Flap"]))
        if any(o.get("grp") == "Top" for o in bpy.data.objects):
            nodes.append(bt.bake_group("Top", "Top", PIVOTS["Top"]))
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
