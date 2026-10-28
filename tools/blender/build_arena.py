"""Builds the proving ground's arena pieces: each a separate GLB, origin at its foot's centre.

    blender --background --factory-startup --python tools/blender/build_arena.py [-- --render]

Blender: +X right, +Y forward (Godot -Z), +Z up. Output: assets/arena/<id>.glb (and previews/*.png).

  barrier     a 3 m concrete jersey barrier with lifting slots and a worn hazard band
  tyres       a stack of four old truck tyres, chained
  crate       a 1.2 m wooden crate, planked and battened, stencilled
  drum        a 200 l oil drum, dented, its bung and rolling hoops
  container   a 6 m (20 ft) shipping container, corrugated, its doors and their bars
  block       a 2 x 1.2 x 2 m cast concrete block, chipped, with lifting eyes
  sandbags    a 3 m wall of sandbags three courses high
  tower       a 20 m floodlight mast: lattice, a ladder with hoops, a bank of six lamps (node Lamps)
  stand       a 24 m section of grandstand: concrete terraces, steel railings, bench seats, a roof
  gate        a gate pillar 8 m high with its swung-open steel leaf
"""

import math
import os
import random
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import build_truck as bt  # noqa: E402
import vehicle_kit as vk  # noqa: E402

from build_truck import PI, box, cyl, cyl_between, revolve, tube  # noqa: E402

OUT_DIR = os.path.join(vk.ROOT, "assets", "arena")


def materials():
    m = bt.make_mat
    m("Concrete", (0.52, 0.5, 0.46), rough=0.92)
    m("ConcreteDark", (0.36, 0.35, 0.32), rough=0.95)
    m("HazardY", (0.75, 0.55, 0.06), rough=0.6)
    m("HazardK", (0.04, 0.04, 0.04), rough=0.6)
    m("Rubber", (0.03, 0.03, 0.03), rough=0.85)
    m("RubberSide", (0.05, 0.05, 0.05), rough=0.8)
    m("Wood", (0.42, 0.3, 0.17), rough=0.85)
    m("WoodDark", (0.3, 0.21, 0.12), rough=0.9)
    m("Stencil", (0.08, 0.07, 0.06), rough=0.9)
    m("DrumRed", (0.45, 0.08, 0.05), metal=0.4, rough=0.55)
    m("DrumBlue", (0.08, 0.17, 0.32), metal=0.4, rough=0.55)
    m("Steel", (0.42, 0.42, 0.42), metal=0.85, rough=0.45)
    m("SteelDark", (0.08, 0.08, 0.085), metal=0.6, rough=0.55)
    m("Galv", (0.55, 0.56, 0.56), metal=0.7, rough=0.5)
    m("Container", (0.12, 0.25, 0.38), metal=0.3, rough=0.6)
    m("ContainerRust", (0.42, 0.16, 0.07), metal=0.3, rough=0.7)
    m("Sand", (0.5, 0.43, 0.29), rough=0.95)
    m("SandDark", (0.42, 0.36, 0.24), rough=0.95)
    m("Paint", (0.55, 0.36, 0.08), metal=0.25, rough=0.5)
    m("Seat", (0.55, 0.12, 0.08), rough=0.6)
    m("LampLit", (1.0, 0.95, 0.85), emit=(1.0, 0.94, 0.82), strength=12.0)
    m("Glass", (0.6, 0.65, 0.7), rough=0.05, alpha=0.5)
    m("Chain", (0.3, 0.3, 0.28), metal=0.9, rough=0.4)


def build_barrier():
    L = 3.0
    # the jersey profile (y across, z up), extruded along x
    prof = [(-0.3, 0.0), (0.3, 0.0), (0.3, 0.08), (0.2, 0.25), (0.08, 0.8), (-0.08, 0.8), (-0.2, 0.25), (-0.3, 0.08)]
    verts = [(x, y, z) for x in (-L / 2, L / 2) for (y, z) in prof]
    n = len(prof)
    faces = [tuple(range(n))[::-1], tuple(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    ob = bt.mk("Barrier", verts, faces, ("Concrete",), grp="Part", smooth=0)
    bt.bevel(ob, 0.015, 2)
    for x in (-0.9, 0.9):
        box(f"Slot{x}", (0.4, 0.62, 0.1), (x, 0, 0.05), "ConcreteDark", grp="Part")
    # the hazard band, worn: alternating blocks on both faces
    for s in (-1, 1):
        for k in range(10):
            x = -L / 2 + 0.15 + k * 0.3
            box(f"Band{s}{k}", (0.28, 0.01, 0.12), (x, s * 0.143, 0.55), "HazardY" if k % 2 == 0 else "HazardK",
                rot=(s * 0.25, 0, 0), grp="Part")
    for x in (-L / 2 + 0.05, L / 2 - 0.05):
        cyl(f"Pin{x}", 0.025, 0.12, (x, 0, 0.72), segs=8, mat="Steel", grp="Part")


def tyre(name, center, r=0.55, w=0.32, grp="Part"):
    revolve(name, [(-w / 2, r * 0.6), (-w / 2, r - 0.05), (-w * 0.4, r), (w * 0.4, r), (w / 2, r - 0.05), (w / 2, r * 0.6)],
            28, ("RubberSide",), axis="Z", center=center, grp=grp)
    for k in range(18):
        a = k * 2 * PI / 18
        c = Vector(center) + Vector((math.cos(a) * r, math.sin(a) * r, 0))
        box(f"{name}Lug{k}", (0.05, 0.1, w * 0.85), tuple(c), "Rubber", rot=(0, 0, a), grp=grp)


def build_tyres():
    for k in range(4):
        tyre(f"Tyre{k}", (random.uniform(-0.03, 0.03), random.uniform(-0.03, 0.03), 0.16 + k * 0.32))
    cyl_between("ChainA", (0.0, -0.4, 0.0), (0.0, -0.4, 1.3), 0.012, mat="Chain", segs=6, grp="Part")


def build_crate():
    s = 1.2
    h = s / 2
    box("Core", (s - 0.06, s - 0.06, s - 0.06), (0, 0, h), "WoodDark", grp="Part")
    rnd = random.Random(3)
    for face in range(4):
        a = face * PI / 2
        R = lambda v: Vector((v[0] * math.cos(a) - v[1] * math.sin(a), v[0] * math.sin(a) + v[1] * math.cos(a), v[2]))  # noqa: E731
        for k in range(5):  # planks
            z = 0.12 + k * 0.24
            box(f"Plank{face}{k}", (s - 0.02, 0.025, 0.22), tuple(R((0, h - 0.012, z))), "Wood", rot=(0, 0, a),
                bev=0.004, grp="Part")
        for x in (-h + 0.06, h - 0.06):  # battens
            box(f"Batten{face}{x}", (0.1, 0.04, s), tuple(R((x, h + 0.008, h))), "WoodDark", rot=(0, 0, a), bev=0.006, grp="Part")
        cb = R((0, h + 0.01, h))
        box(f"Brace{face}", (0.08, 0.035, s * 1.25), tuple(cb), "WoodDark", rot=(0, rnd.choice((-1, 1)) * 0.79, a), grp="Part")
    for k in range(5):
        box(f"Lid{k}", (s - 0.02, 0.22, 0.025), (0, -0.48 + k * 0.24, s - 0.01), "Wood", bev=0.004, grp="Part")
    box("Stencil", (0.5, 0.005, 0.12), (0, h + 0.03, h + 0.25), "Stencil", grp="Part")


def build_drum():
    r, H = 0.29, 0.88
    revolve("Shell", [(0.0, 0.0), (0.0, r), (H, r)], 32, ("DrumRed",), axis="Z", grp="Part")
    for z in (H / 3, 2 * H / 3):
        revolve(f"Hoop{z}", [(z - 0.02, r), (z, r + 0.012), (z + 0.02, r)], 32, ("DrumRed",), axis="Z", grp="Part")
    for z in (0.01, H - 0.01):
        revolve(f"Chime{z}", [(z - 0.012, r - 0.005), (z, r + 0.012), (z + 0.012, r - 0.005)], 32, ("SteelDark",), axis="Z",
                grp="Part")
    cyl("Lid", r, 0.01, (0, 0, H - 0.01), segs=32, mat="DrumRed", grp="Part")
    cyl("Bung", 0.03, 0.02, (0.15, 0.05, H), segs=10, mat="SteelDark", grp="Part")
    cyl("Bung2", 0.02, 0.02, (-0.17, 0.0, H), segs=10, mat="SteelDark", grp="Part")
    box("Label", (0.18, 0.005, 0.2), (0, r + 0.004, 0.5), "HazardY", grp="Part")


def build_container():
    L, W, H = 6.06, 2.44, 2.59
    # frame: corner posts, rails, corner castings
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(f"Post{sx}{sy}", (0.16, 0.16, H), (sx * (L / 2 - 0.08), sy * (W / 2 - 0.08), H / 2), "Container", grp="Part")
            for z in (0.06, H - 0.06):
                box(f"Cast{sx}{sy}{z}", (0.18, 0.17, 0.12), (sx * (L / 2 - 0.09), sy * (W / 2 - 0.085), z), "SteelDark", grp="Part")
        for z in (0.08, H - 0.08):
            box(f"RailL{sx}{z}", (L, 0.14, 0.16), (0, sx * (W / 2 - 0.07), z), "Container", grp="Part")
            box(f"RailW{sx}{z}", (0.14, W, 0.16), (sx * (L / 2 - 0.07), 0, z), "Container", grp="Part")
    # corrugated sides: trapezoid ribs
    for sy in (-1, 1):
        n = 36
        for k in range(n):
            x = -L / 2 + 0.2 + k * (L - 0.4) / (n - 1)
            off = 0.035 if k % 2 == 0 else 0.0
            box(f"Rib{sy}{k}", ((L - 0.4) / n + 0.01, 0.02, H - 0.3), (x, sy * (W / 2 - 0.04 + off), H / 2),
                "Container" if (k * 7 + sy) % 11 else "ContainerRust", grp="Part")
    box("Front", (0.03, W - 0.3, H - 0.3), (L / 2 - 0.05, 0, H / 2), "Container", grp="Part")
    box("Roof", (L - 0.2, W - 0.2, 0.03), (0, 0, H - 0.04), "Container", grp="Part")
    box("Floor", (L - 0.2, W - 0.2, 0.05), (0, 0, 0.05), "SteelDark", grp="Part")
    # the doors at the back with their locking bars
    for sy in (-1, 1):
        box(f"Door{sy}", (0.04, W / 2 - 0.15, H - 0.3), (-L / 2 + 0.06, sy * (W / 4 - 0.02), H / 2), "Container", grp="Part")
        for k in (0.25, 0.75):
            yb = sy * (W / 2 - 0.15) * k
            cyl(f"Bar{sy}{k}", 0.022, H - 0.3, (-L / 2 + 0.01, yb, H / 2), segs=8, mat="Steel", grp="Part")
            box(f"Handle{sy}{k}", (0.03, 0.04, 0.3), (-L / 2 - 0.02, yb + 0.05, 1.1), "Steel", grp="Part")
    for k in range(3):
        box(f"Patch{k}", (random.uniform(0.3, 0.8), 0.006, random.uniform(0.2, 0.5)),
            (random.uniform(-2.5, 2.5), W / 2 + 0.002, random.uniform(0.4, 2.0)), "ContainerRust", grp="Part")


def build_block():
    sx, sy, sz = 2.0, 2.0, 1.2
    box("Block", (sx, sy, sz), (0, 0, sz / 2), "Concrete", bev=0.04, seg=2, grp="Part")
    rnd = random.Random(7)
    for k in range(9):  # chips off its edges
        x = rnd.choice((-1, 1)) * sx / 2
        y = rnd.uniform(-0.8, 0.8)
        z = rnd.choice((0.05, sz - 0.05))
        box(f"Chip{k}", (0.12, rnd.uniform(0.1, 0.3), 0.1), (x, y, z), "ConcreteDark", rot=(rnd.random(), rnd.random(), 0),
            grp="Part")
    for x in (-0.5, 0.5):
        tube(f"Eye{x}", [(x - 0.08, 0, sz), (x - 0.08, 0, sz + 0.1), (x + 0.08, 0, sz + 0.1), (x + 0.08, 0, sz)], 0.018,
             mat="Steel", nring=8, sub=3, grp="Part")
    box("Paint", (0.6, 0.006, 0.18), (0, -sy / 2 - 0.003, 0.8), "HazardY", grp="Part")


def build_sandbags():
    rnd = random.Random(11)
    L = 3.0
    for course in range(3):
        n = 5
        off = 0.3 if course % 2 else 0.0
        for k in range(n):
            x = -L / 2 + 0.3 + off + k * 0.6
            if x > L / 2 - 0.25:
                continue
            for row, y in enumerate((-0.2, 0.2)):
                c = (x, y + rnd.uniform(-0.02, 0.02), 0.11 + course * 0.2)
                ob = box(f"Bag{course}{k}{row}", (0.56, 0.36, 0.2), c, "Sand" if (k + row + course) % 3 else "SandDark",
                         rot=(0, 0, rnd.uniform(-0.06, 0.06)), bev=0.07, seg=3, angle=80, grp="Part")
                ob.scale = (1.0, 1.0, 1.0)


def build_tower():
    H = 20.0
    w = 0.8
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl_between(f"Leg{sx}{sy}", (sx * w, sy * w, 0), (sx * 0.35, sy * 0.35, H), 0.07, mat="Galv", segs=8, grp="Part")
    # lattice braces
    for k in range(10):
        z0, z1 = k * H / 10, (k + 1) * H / 10
        f0, f1 = w + (0.35 - w) * z0 / H, w + (0.35 - w) * z1 / H
        for s in (-1, 1):
            cyl_between(f"BrX{k}{s}", (-f0, s * f0, z0), (f1, s * f1, z1), 0.03, mat="Galv", segs=6, grp="Part")
            cyl_between(f"BrY{k}{s}", (s * f0, -f0, z0), (s * f1, f1, z1), 0.03, mat="Galv", segs=6, grp="Part")
            cyl_between(f"Ring{k}{s}", (-f1, s * f1, z1), (f1, s * f1, z1), 0.025, mat="Galv", segs=6, grp="Part")
            cyl_between(f"RingB{k}{s}", (s * f1, -f1, z1), (s * f1, f1, z1), 0.025, mat="Galv", segs=6, grp="Part")
    for sx in (-1, 1):  # the ladder up one side with its hoops
        cyl_between(f"Rail{sx}", (sx * 0.2, -w - 0.1, 0.3), (sx * 0.2, -0.45, H), 0.02, mat="Steel", segs=6, grp="Part")
    for k in range(int(H / 0.3)):
        z = 0.3 + k * 0.3
        f = w + (0.35 - w) * z / H
        cyl_between(f"Rung{k}", (-0.2, -f - 0.1, z), (0.2, -f - 0.1, z), 0.012, mat="Steel", segs=5, grp="Part")
    for k in range(12):
        z = 3.0 + k * 1.4
        f = w + (0.35 - w) * z / H
        revolve(f"Hoop{k}", [(-0.015, 0.33), (0.015, 0.33), (0.015, 0.35), (-0.015, 0.35)], 16, ("Steel",), axis="Z",
                center=(0, -f - 0.35, z), a0=PI, a1=2 * PI, grp="Part")
    # the platform and the lamp bank (node Lamps), aimed down at the middle (+Y)
    box("Platform", (2.4, 1.6, 0.08), (0, 0.2, H), "SteelDark", grp="Part")
    for s in (-1, 1):
        cyl_between(f"Guard{s}", (s * 1.2, -0.6, H + 1.0), (s * 1.2, 1.0, H + 1.0), 0.025, mat="Galv", segs=6, grp="Part")
    box("Frame", (2.6, 0.12, 1.6), (0, 1.0, H + 1.3), "SteelDark", grp="Part")
    for i in range(3):
        for j in range(2):
            c = Vector((-0.85 + i * 0.85, 1.05, H + 0.9 + j * 0.8))
            box(f"Housing{i}{j}", (0.7, 0.35, 0.6), tuple(c), "SteelDark", rot=(-0.45, 0, 0), bev=0.03, grp="Part")
            box(f"Lens{i}{j}", (0.6, 0.02, 0.5), tuple(c + Vector((0, 0.17, -0.08))), "LampLit", rot=(-0.45, 0, 0), grp="Lamps")
    box("Cabinet", (0.5, 0.3, 0.8), (0, -w - 0.2, 1.2), "Galv", bev=0.02, grp="Part")
    box("Footing", (2.2, 2.2, 0.4), (0, 0, -0.1), "Concrete", grp="Part")


def build_stand():
    L = 24.0
    rows = 8
    for k in range(rows):
        z = k * 0.45
        y = -k * 0.8
        box(f"Terrace{k}", (L, 0.8, z + 0.45), (0, y, (z + 0.45) / 2), "Concrete", grp="Part")
        n = 16
        for i in range(n):  # bench seats, a gap at each aisle
            if i in (5, 10):
                continue
            x = -L / 2 + 0.75 + i * (L - 1.5) / (n - 1)
            box(f"Seat{k}{i}", (1.3, 0.35, 0.06), (x, y + 0.1, z + 0.62), "Seat" if (i + k) % 7 else "Steel", grp="Part")
            for s in (-0.55, 0.55):
                box(f"SeatLeg{k}{i}{s}", (0.04, 0.2, 0.17), (x + s, y + 0.1, z + 0.53), "SteelDark", grp="Part")
    for x in (-L / 2 + 0.1, L / 2 - 0.1):
        box(f"End{x}", (0.2, rows * 0.8 + 0.4, rows * 0.45 + 1.0), (x, -rows * 0.4 + 0.4, (rows * 0.45 + 1.0) / 2), "ConcreteDark",
            grp="Part")
    # the front railing
    for i in range(13):
        x = -L / 2 + 0.5 + i * (L - 1.0) / 12
        cyl(f"RailPost{i}", 0.03, 1.1, (x, 0.35, 0.45 + 0.55), segs=6, mat="Galv", grp="Part")
    for z in (0.95, 1.5):
        cyl_between(f"Rail{z}", (-L / 2 + 0.5, 0.35, z), (L / 2 - 0.5, 0.35, z), 0.025, mat="Galv", segs=6, grp="Part")
    # the roof on its columns, sloping back
    top = rows * 0.45
    for i in range(5):
        x = -L / 2 + 1.0 + i * (L - 2.0) / 4
        cyl_between(f"Col{i}", (x, -rows * 0.8 + 0.2, 0), (x, -rows * 0.8 + 0.2, top + 4.0), 0.12, mat="SteelDark", segs=10,
                    grp="Part")
        cyl_between(f"Beam{i}", (x, -rows * 0.8 + 0.2, top + 4.0), (x, 1.0, top + 3.2), 0.09, mat="SteelDark", segs=8, grp="Part")
    box("Roof", (L + 1.0, rows * 0.8 + 1.6, 0.06), (0, -rows * 0.4 + 0.2, top + 3.65), "Galv", rot=(-0.11, 0, 0), grp="Part")
    box("Fascia", (L + 1.0, 0.05, 0.4), (0, 1.05, top + 3.0), "Paint", grp="Part")
    box("BackWall", (L, 0.2, top + 3.4), (0, -rows * 0.8 + 0.1, (top + 3.4) / 2), "ConcreteDark", grp="Part")


def build_gate():
    H = 8.0
    box("Pillar", (1.4, 1.4, H), (0, 0, H / 2), "Concrete", bev=0.05, grp="Part")
    box("Cap", (1.7, 1.7, 0.3), (0, 0, H + 0.15), "ConcreteDark", bev=0.03, grp="Part")
    for k in range(5):
        box(f"Band{k}", (1.42, 1.42, 0.25), (0, 0, 1.0 + k * 1.4), "HazardY" if k % 2 == 0 else "HazardK", grp="Part")
    # the leaf, swung open along +Y from its hinge at the pillar's +X face
    lx = 0.75
    box("LeafFrame", (0.12, 5.0, 6.0), (lx + 0.06, 2.6, 3.2), "SteelDark", grp="Part")
    for k in range(12):
        box(f"LeafSlat{k}", (0.05, 4.8, 0.4), (lx + 0.13, 2.6, 0.6 + k * 0.48), "Container" if k % 3 else "ContainerRust",
            grp="Part")
    for z in (1.0, 5.5):
        cyl(f"Hinge{z}", 0.08, 0.4, (lx, 0.1, z), segs=12, mat="Steel", grp="Part")
    cyl("Lamp", 0.12, 0.25, (0, 0.75, H - 0.6), axis="Y", segs=12, mat="LampLit", grp="Part")


BUILDERS = {"barrier": build_barrier, "tyres": build_tyres, "crate": build_crate, "drum": build_drum,
            "container": build_container, "block": build_block, "sandbags": build_sandbags, "tower": build_tower,
            "stand": build_stand, "gate": build_gate}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    os.makedirs(OUT_DIR, exist_ok=True)
    random.seed(5)
    for pid, fn in BUILDERS.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bt.MAT.clear()
        materials()
        fn()
        nodes = [bt.bake_group("Part", "Part")]
        if any(o.get("grp") == "Lamps" for o in bpy.data.objects):
            nodes.append(bt.bake_group("Lamps", "Lamps"))
        vk.export(nodes, os.path.join(OUT_DIR, pid + ".glb"))
        if "--render" in argv:
            vk.studio(OUT_DIR, 0.0)
            d = {"tower": 34.0, "stand": 34.0, "container": 11.0, "gate": 16.0}.get(pid, 5.0)
            vk.render(pid, loc=(d * 0.8, d * 0.9, d * 0.6), target=(0, 0, d * 0.12), lens=50, res=(600, 500))


if __name__ == "__main__":
    main()
