"""Shared parts for the vehicle build scripts (6x6 truck, van, trailer).

Builds on the mesh helpers in build_truck.py and adds parametric wheels, gauges, a steering
wheel, seats, marker empties, export and studio renders.

Vehicle convention (Godot): +Y up, front = -Z, +X = right. Scene origin = centre of the
wheelbase (midway between the front and the rearmost axle) at wheel-centre height, so every wheel
node sits at y = 0. Blender: +Y forward, +Z up (the glTF exporter maps Blender +Y to Godot -Z).
"""

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import build_truck as bt  # noqa: E402

from build_truck import PI, bevel, box, cyl, cyl_between, densify, link, mk, obox, revolve, tube  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))

# Carcass half-profile of the pickup's 0.55 m tyre on a 0.27 m rim: (x, r). Other tyres are mapped from it.
_HALF = [(0.0, 0.505), (0.08, 0.505), (0.14, 0.503), (0.172, 0.497), (0.192, 0.484), (0.204, 0.465),
         (0.21, 0.44), (0.212, 0.41), (0.209, 0.375), (0.203, 0.345), (0.199, 0.32), (0.206, 0.305),
         (0.204, 0.29), (0.188, 0.282), (0.172, 0.278), (0.165, 0.272)]

# Tread lugs per pitch, in pickup-tyre x units and pitch fractions (t), right half only.
# "alt": the left half is mirrored and shifted half a pitch; otherwise mirrored in place (chevron).
PATTERNS = {
    "mt": dict(alt=True, lugs=[[(-0.016, 0.073), (0.10, 0.0), (0.219, 0.031), (0.219, 0.49), (0.10, 0.52),
                                (-0.016, 0.417)]]),
    "chevron": dict(alt=False, lugs=[[(0.0, 0.0), (0.06, 0.0), (0.219, 0.34), (0.219, 0.66), (0.14, 0.66),
                                      (0.0, 0.36)]]),
    "at": dict(alt=True, lugs=[[(0.012, 0.04), (0.095, 0.0), (0.105, 0.42), (0.02, 0.46)],
                               [(0.125, 0.0), (0.219, 0.02), (0.219, 0.44), (0.13, 0.42)]]),
}


def materials(paint, extra=()):
    """Pickup materials (with this vehicle's paint) plus extras: (name, colour, kwargs)."""
    bt.PAINT_COLOR = paint
    bt.build_materials()
    for name, color, kw in extra:
        bt.make_mat(name, color, **kw)


def tyre_and_rim(grp, R, W, rim_r, pattern="mt", pitches=18, rim="steel", segs=48, rim_mat="RimSteel",
                 depth=1.0, nuts=6, biters=False):
    """One wheel with its outer face towards +X, centred on the origin. Returns nothing; parts go to grp."""
    sx = W / 0.42
    S = (R - rim_r) / 0.28

    def mr(r):
        return rim_r + (r - 0.27) * S

    half = [(x * sx, mr(r)) for x, r in _HALF]
    prof = [(-x, r) for x, r in reversed(half[1:])] + half
    revolve("Carcass", prof, segs, ("Rubber",), closed=False, grp=grp, smooth=40)

    def r_top(u):
        return mr(0.55 - (1 - depth) * 0.04 - max(0.0, abs(u) - 0.165) * 1.25)

    def r_base(u):
        return mr(0.478 - max(0.0, abs(u) - 0.17) * 1.1)

    pitch = 2 * PI * R / pitches
    pat = PATTERNS[pattern]
    verts, faces = [], []
    for k in range(pitches):
        for side in (1, -1):
            for lug in pat["lugs"]:
                t0 = k + (0.5 if (side < 0 and pat["alt"]) else 0.0)
                poly = [(side * u, (t0 + t) * pitch) for u, t in lug]
                if side < 0:
                    poly = poly[::-1]
                poly = densify(poly, 0.07 * sx)
                n = len(poly)
                base = len(verts)
                for h in (0, 1):
                    for u, s in poly:
                        th = s / R
                        rr = r_base(u) if h == 0 else r_top(u)
                        verts.append((u * sx, rr * math.cos(th), rr * math.sin(th)))
                faces.append(list(range(base, base + n)))
                faces.append(list(range(base + n, base + 2 * n)))
                for i in range(n):
                    j = (i + 1) % n
                    faces.append([base + i, base + j, base + n + j, base + n + i])
            if biters:
                th0 = ((k + 0.75) * pitch) / R
                c, s_ = math.cos(th0), math.sin(th0)
                b = [(mr(0.385), -0.022 * S), (mr(0.455), -0.032 * S), (mr(0.455), 0.032 * S), (mr(0.385), 0.022 * S)]
                base = len(verts)
                for xx in (side * 0.196 * sx, side * 0.224 * sx):
                    for u, v in b:
                        verts.append((xx, u * c - v * s_, u * s_ + v * c))
                faces += [[base, base + 1, base + 2, base + 3], [base + 4, base + 5, base + 6, base + 7]]
                faces += [[base + i, base + (i + 1) % 4, base + 4 + (i + 1) % 4, base + 4 + i] for i in range(4)]
    lugs = mk("Lugs", verts, faces, ("Rubber",), grp=grp, smooth=30)
    me = lugs.data
    bw = me.attributes.new("bevel_weight_edge", "FLOAT", "EDGE")
    cut_r = mr(0.48)
    for e in me.edges:
        bw.data[e.index].value = 1.0 if all(Vector(me.vertices[i].co).yz.length > cut_r for i in e.vertices) else 0.0
    bevel(lugs, 0.007 * S, 1, 30).modifiers["Bevel"].limit_method = "WEIGHT"

    # Rim: barrel with flanges at the tyre beads, then a pressed steel disc set back from the face.
    bx = 0.165 * sx
    barrel = [(bx + 0.02, rim_r - 0.01), (bx + 0.02, rim_r + 0.018), (bx + 0.008, rim_r + 0.024),
              (bx - 0.004, rim_r + 0.014), (bx - 0.02, rim_r - 0.02), (-bx + 0.02, rim_r - 0.02),
              (-bx + 0.004, rim_r + 0.014), (-bx - 0.008, rim_r + 0.024), (-bx - 0.02, rim_r + 0.018),
              (-bx - 0.02, rim_r - 0.01), (-bx + 0.01, rim_r - 0.03), (bx - 0.01, rim_r - 0.03)]
    revolve("Barrel", barrel, 40, (rim_mat,), grp=grp, smooth=40)
    hub_r = rim_r * 0.36
    dx = bx * 0.45  # disc offset towards the outside
    disc = [(dx - 0.012, hub_r), (dx + 0.004, hub_r), (dx + 0.004, hub_r + 0.02), (dx - 0.01, rim_r * 0.62),
            (dx - 0.01, rim_r * 0.74), (dx + 0.03, rim_r - 0.03), (dx + 0.018, rim_r - 0.03),
            (dx - 0.022, rim_r * 0.74), (dx - 0.022, rim_r * 0.62), (dx - 0.012, hub_r + 0.02)]
    revolve("Disc", disc, 40, (rim_mat,), grp=grp, smooth=40)
    holes = 8 if rim == "steel" else 6
    for i in range(holes):  # vent holes in the disc (dark ovals on both faces)
        a = 2 * PI * (i + 0.5) / holes
        rr = rim_r * 0.68
        obox(f"Vent{i}", (dx - 0.0045, rr * math.cos(a), rr * math.sin(a)), (0, -math.sin(a), math.cos(a)),
             (0, math.cos(a), math.sin(a)), (1, 0, 0), (rim_r * 0.16, rim_r * 0.09, 0.0205), "Slot", grp=grp,
             bev=rim_r * 0.03)
    revolve("Hub", [(dx, 0.0), (dx, hub_r * 0.95), (dx + 0.03, hub_r * 0.9), (dx + 0.05, hub_r * 0.55),
                    (dx + 0.06, 0.0)], 24, ("CastDark",), grp=grp, smooth=40)
    for i in range(nuts):
        a = 2 * PI * i / nuts
        rr = hub_r * 0.78 + 0.02
        cyl(f"Nut{i}", 0.011 * max(1.0, S), 0.02, (dx + 0.012, rr * math.cos(a), rr * math.sin(a)), axis="X",
            segs=6, mat="Chrome", grp=grp, smooth=0)
    if rim == "military":  # central tyre inflation: valve block on the hub and a hose to the rim
        box("CtisValve", (0.03, 0.05, 0.05), (dx + 0.075, 0.0, 0.0), "CastDark", grp=grp, bev=0.008)
        tube("CtisHose", [(dx + 0.075, 0.0, 0.03), (dx + 0.06, 0.0, rim_r * 0.5), (dx + 0.02, 0.0, rim_r - 0.03)],
             0.007, "Rubber", nring=6, sub=4, grp=grp)
    # Brake drum behind the disc.
    revolve("Drum", [(-bx * 0.9, rim_r * 0.5), (-bx * 0.9, rim_r - 0.05), (dx - 0.03, rim_r - 0.05),
                     (dx - 0.03, rim_r * 0.5)], 32, ("CastDark",), grp=grp, smooth=40)


def wheel_template(name, **kw):
    """Bake a wheel (outer face +X) and return its mesh."""
    tyre_and_rim(name, **kw)
    ob = bt.bake_group(name, name)
    me = ob.data
    bpy.data.objects.remove(ob, do_unlink=True)
    return me


def place_wheels(tpl_me, wheels):
    """wheels: [(name, x, y, z)]; left wheels (x < 0) get a mirrored copy. Returns the nodes."""
    out = []
    for name, x, y, z in wheels:
        me = bt.mirrored_copy(tpl_me, "Wheel_" + name) if x < 0 else tpl_me.copy()
        me.name = "Wheel_" + name
        ob = link(bpy.data.objects.new(name, me))
        ob.location = (x, y, z)
        out.append(ob)
    return out


def gauge(name, C, N, r, ticks, major=4, red_from=None):
    """Round gauge facing N, with its needle as group Needle_<name>. Returns (group, centre)."""
    N = Vector(N).normalized()
    U = Vector((1, 0, 0))
    V = N.cross(U).normalized()
    C = Vector(C)
    revolve(f"{name}Bezel", [(0.0, r), (0.006, r), (0.008, r + 0.004), (0.004, r + 0.008), (0.0, r + 0.008)], 32,
            ("Chrome",), axis=tuple(N), center=tuple(C))
    cyl(f"{name}Face", r, 0.003, tuple(C - N * 0.001), axis=tuple(N), segs=32, mat="GaugeFace")
    for i in range(ticks + 1):
        th = math.radians(-135 + 270 * i / ticks)
        d = V * math.cos(th) + U * math.sin(th)
        p = U * math.cos(th) - V * math.sin(th)
        big = i % major == 0
        ln = (0.011 if big else 0.006) * r / 0.05
        mat = "TailRed" if red_from is not None and i >= red_from else "GaugeMark"
        obox(f"{name}Tick{i}", C + d * (r * 0.9 - ln / 2) + N * 0.001, p, d, N, (0.0022 if big else 0.0013, ln, 0.0008),
             mat)
    th = math.radians(-135)
    d = V * math.cos(th) + U * math.sin(th)
    p = U * math.cos(th) - V * math.sin(th)
    grp = f"Needle_{name}"
    obox(f"{name}Needle", C + N * 0.004 + d * (r * 0.38), p, d, N, (0.0028, r * 0.95, 0.0012), "Needle", grp=grp)
    cyl(f"{name}NeedleCap", r * 0.12, 0.004, tuple(C + N * 0.005), axis=tuple(N), segs=16, mat="GaugeFace", grp=grp)
    return grp, tuple(C + N * 0.004), tuple(N)


def steering_wheel(W, n, rim_r):
    """Steering wheel as group SteeringWheel; n points from the wheel to the driver."""
    grp = "SteeringWheel"
    W, n = Vector(W), Vector(n).normalized()
    U = Vector((1, 0, 0))
    V = n.cross(U).normalized()
    prof = [(0.015 * math.cos(a), rim_r + 0.019 * math.sin(a)) for a in (2 * PI * i / 10 for i in range(10))]
    revolve("Rim", prof, 44, ("Interior",), axis=tuple(n), center=tuple(W), grp=grp, smooth=60)
    for d in (U, -U, -V):
        obox(f"Spoke{tuple(d)}", W + d * (rim_r * 0.6) - n * 0.012, d.cross(n), d, n, (0.032, rim_r * 0.8, 0.01),
             "SteelBlack", grp=grp, bev=0.003)
    cyl("WheelHub", 0.06, 0.05, tuple(W - n * 0.025), axis=tuple(n), segs=20, mat="Interior", grp=grp)
    revolve("HornPad", [(0.0, 0.0), (0.0, 0.055), (0.012, 0.05), (0.02, 0.033), (0.024, 0.0)], 20, ("Interior",),
            axis=tuple(n), center=tuple(W), grp=grp, smooth=60)
    return grp


def seat(name, x, yc, zf, width=0.5, recline=12):
    """Bucket seat on a floor at height zf, cushion centred at y = yc. Returns the hip (H) point."""
    box(f"{name}Frame", (width - 0.08, 0.42, 0.13), (x, yc - 0.01, zf + 0.085), "TrimBlack", bev=0.01)
    box(f"{name}Cushion", (width, 0.5, 0.11), (x, yc, zf + 0.205), "Seat", bev=0.04, seg=3)
    for k in (1, -1):
        box(f"{name}Bolster{k}", (0.07, 0.46, 0.07), (x + k * (width / 2 - 0.035), yc, zf + 0.27), "Seat", bev=0.03,
            seg=3)
    a = math.radians(recline)
    R = Matrix.Rotation(a, 3, "X")
    H = Vector((x, yc - 0.24, zf + 0.23))

    def at(lx, ly, lz):
        return tuple(H + R @ Vector((lx, ly, lz)))

    box(f"{name}Back", (width, 0.11, 0.62), at(0, -0.05, 0.34), "Seat", rot=(a, 0, 0), bev=0.04, seg=3)
    box(f"{name}Head", (0.26, 0.09, 0.17), at(0, -0.05, 0.8), "Seat", rot=(a, 0, 0), bev=0.035, seg=3)
    for k in (1, -1):
        cyl(f"{name}Post{k}", 0.006, 0.1, at(k * 0.07, -0.05, 0.69), axis=tuple(R @ Vector((0, 0, 1))), segs=8,
            mat="Chrome")
    return Vector((x, yc - 0.12, zf + 0.34))


def empty(name, p, parent=None, scale=None, rot=None):
    e = link(bpy.data.objects.new(name, None))
    e.empty_display_size = 0.08
    if parent:
        e.parent = bpy.data.objects[parent]
        e.location = Vector(p) - e.parent.location
    else:
        e.location = p
    if scale:
        e.empty_display_type = "CUBE"
        e.scale = scale
    if rot:
        e.rotation_euler = rot
    return e


def export(nodes, path, keep_originals=False):
    """keep_originals: image textures stay the PNG files next to the GLB (not packed into it)."""
    tris = 0
    for o in nodes:
        if o.type == "MESH":
            o.data.calc_loop_triangles()
            t = len(o.data.loop_triangles)
            tris += t
            print(f"node {o.name:14s} tris {t:7d} at {tuple(round(c, 3) for c in o.location)}")
        else:
            print(f"node {o.name:14s} (empty) at {tuple(round(c, 3) for c in o.location)}")
    print("TOTAL TRIS", tris)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in nodes:
        o.select_set(True)
        for c in o.children:
            c.select_set(True)
    bpy.context.view_layer.objects.active = nodes[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_keep_originals=keep_originals)
    print("exported", path)
    return tris


def studio(out_dir, ground_z):
    bt.OUT_DIR = out_dir
    os.makedirs(os.path.join(out_dir, "previews"), exist_ok=True)
    bt.setup_studio()
    bpy.data.objects["Ground"].location.z = ground_z - bt.GROUND_Z


def render(name, **view):
    bt.render_view(name, **view)
