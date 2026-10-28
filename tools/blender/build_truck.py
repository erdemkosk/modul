"""Builds the detailed off-road pickup used as the visual model of the game truck.

Run headless from the repo root:
    blender --background --factory-startup --python tools/blender/build_truck.py
    blender --background --factory-startup --python tools/blender/build_truck.py -- --no-render
    blender --background --factory-startup --python tools/blender/build_truck.py -- --views side,top

Everything is generated procedurally (no image textures). Output:
    assets/truck/truck.glb          exported model (Y-up, front = -Z in Godot)
    assets/truck/previews/*.png     Eevee studio renders (ground/lights/cameras are not exported)

Blender axes: +X right, +Y forward, +Z up. The glTF exporter maps Blender +Y to -Z, so the
truck faces -Z in Godot, matching the physics body in scripts/vehicle.gd.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

# --------------------------------------------------------------------------------------------
# Dimensions (metres, Blender axes). Wheel numbers mirror scripts/vehicle.gd.
# --------------------------------------------------------------------------------------------
WHEEL_R = 0.55
TIRE_W = 0.42
TRACK_HALF = 1.05
AXLE_F_Y = 1.50  # Godot z = -1.50
AXLE_R_Y = -1.45  # Godot z = +1.45
WHEEL_Z = -0.44  # wheel centre height at rest, relative to the body origin
GROUND_Z = WHEEL_Z - WHEEL_R

BODY_HALF_W = 0.90  # body is 1.8 m wide (flares stick out further, over the tyres)
SILL_Z = -0.40  # underside of cab/fenders -> ~0.6 m ground clearance
NOSE_Y = 2.18  # fender / grille face
TAIL_Y = -2.24  # rear face of the bed
BELT_Z = 0.52  # bottom of the side windows
ROOF_Z = 1.168

HOOD_HINGE_Y = 0.985
HOOD_FRONT_Y = 2.175
HOOD_REAR_Z = 0.48
HOOD_FRONT_Z = 0.405
HOOD_HALF_W = 0.612
FENDER_IN_X = 0.62
FENDER_REAR_Y = 0.708
FENDER_BOTTOM_Z = -0.20
ARCH_R = 0.64

WS_BASE_Y = 0.80  # windscreen base (front of the greenhouse at z = 0.50)
WS_TOP_Y = 0.37
CAB_BACK_Y = -0.72
DOOR_FRONT_Y = 0.70
DOOR_REAR_Y = -0.30
DOOR_BOTTOM_Z = -0.36

BED_FRONT_Y = -0.77
BED_FLOOR_Z = -0.05
BED_TOP_Z = 0.50
BED_BOTTOM_Z = -0.30
BED_IN_X = 0.84

WINCH_DRUM = (0.0, 2.27, -0.045)  # drum axis centre (axis along X)
WINCH_ANCHOR = (0.0, 2.40, -0.07)  # rope exit at the fairlead; the hook hangs here at rest

# Cab interior (left-hand drive). Used for the first-person driving camera.
DRIVER_X = -0.42
SEAT_CUSHION_Y = 0.08
DRIVER_SEAT = (DRIVER_X, -0.04, 0.0)  # hip (H) point on the driver's seat
DRIVER_EYE = (DRIVER_X, -0.12, 0.74)  # first-person camera position
WHEEL_C = (DRIVER_X, 0.36, 0.52)  # steering wheel centre
WHEEL_AXIS = (0.0, -0.848, 0.53)  # column axis, pointing from the wheel towards the driver
WHEEL_RIM_R = 0.19  # rim centre-line radius (grip tube ~0.035 thick)
GAUGE_N = (0.0, -0.986, 0.166)  # instrument faces point back at the driver's eyes
NEEDLES = []  # (group, centre) filled by gauge()

# Light sources for the game (Blender coords): (name, lens centre, faces backwards).
LIGHT_MARKERS = (
    ("Headlight_L", (-0.76, 2.205, 0.19), False), ("Headlight_R", (0.76, 2.205, 0.19), False),
    ("AuxLight_L", (-0.22, 2.34, 0.39), False), ("AuxLight_R", (0.22, 2.34, 0.39), False),
    ("LightBar", (0.0, 0.372, 1.265), False),
    ("Tail_L", (-0.80, -2.27, 0.31), True), ("Tail_R", (0.80, -2.27, 0.31), True),
    ("Reverse_L", (-0.80, -2.27, 0.07), True), ("Reverse_R", (0.80, -2.27, 0.07), True),
)

# Get-in / get-out markers on the driver side (Blender coords, door closed). (name, point, parent)
DOOR_OPEN_DEG = 70.0  # Door_L opens with -70° about Z (Godot Y), Door_R with +70°
ENTRY_MARKERS = (
    ("DoorHandle_L_Out", (-0.915, -0.19, 0.36), "Door_L"),  # outside handle grip
    ("DoorPull_L_In", (-0.826, 0.12, 0.31), "Door_L"),  # inside pull handle above the armrest
    ("DoorRelease_L_In", (-0.852, 0.52, 0.38), "Door_L"),  # inside release lever
    ("Sill_L", (-0.88, 0.20, -0.36), None),  # top of the sill, outer edge, mid door opening
    ("Step_L", (-0.94, 0.20, -0.296), None),  # step plate on the rock slider
    ("GrabHandle_L", (-0.735, 0.545, 0.80), None),  # A-pillar grab handle, middle of the grip
    ("CabFloor_L", (-0.65, 0.30, -0.33), None),  # floor mat just inside the door, left foot
    ("DriverExit", (-1.47, -0.44, GROUND_Z), None),  # stand here: behind the open door, outside its swing
)

# Fuel, spare wheel and radiator (M5: fuel, repairs, damage).
FUEL_DOOR_C = (-0.903, -1.05, 0.30)  # centre of the fuel flap on the left bed side
FUEL_DOOR_HINGE = (-0.903, -1.118, 0.30)  # vertical hinge on the flap's rear edge
FUEL_DOOR_OPEN_DEG = 80.0  # +80° about Z (Godot Y) swings the flap out
SPARE_C = (0.0, -0.26, 1.455)  # spare wheel centre: lying flat on the cab roof rack, outer face up
M5_MARKERS = (
    ("FuelFiller", (-0.885, -1.05, 0.30), None),  # filler neck mouth (cap off); the jerrycan spout goes here, pointing +X
    ("FuelStand", (-1.55, -1.05, GROUND_Z), None),  # stand here on the ground to pour, facing +X
    ("SpareTyreMount", SPARE_C, None),  # where the spare sits in the bed (stays when SpareTyre is hidden)
    ("Radiator", (0.0, 1.99, 0.07), None),  # centre of the radiator core
    ("SteamVent", (0.32, 1.99, 0.35), None),  # radiator cap on the top tank: leak steam rises from here
    ("PassengerSeat", (-DRIVER_SEAT[0], DRIVER_SEAT[1], DRIVER_SEAT[2]), None),  # mirror of the driver's seat
    ("PassengerEye", (-DRIVER_EYE[0], DRIVER_EYE[1], DRIVER_EYE[2]), None),
    ("TowHitch", (0.0, -2.44, -0.40), None),  # mouth of the rear receiver: the trailer's Hitch goes here
)

PAINT_COLOR =(0.42, 0.33, 0.20)  # desert khaki

TREAD_PITCHES = 18
TIRE_SEGS = 48

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "truck")

PI = math.pi
MAT = {}


# --------------------------------------------------------------------------------------------
# Small math helpers
# --------------------------------------------------------------------------------------------
def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def side_x(z):
    """Outer x of the greenhouse side at height z (tumblehome)."""
    return 0.865 - (z - 0.50) * 0.15


def ws_y(z):
    """Outer y of the windscreen at height z."""
    return WS_BASE_Y - (z - 0.50) * (WS_BASE_Y - WS_TOP_Y) / 0.60


def back_y(z):
    return CAB_BACK_Y + (z - 0.50) * 0.05


def hood_z(y):
    """Hood / fender top line (no crown)."""
    return HOOD_REAR_Z + (y - HOOD_HINGE_Y) * (HOOD_FRONT_Z - HOOD_REAR_Z) / (HOOD_FRONT_Y - HOOD_HINGE_Y)


def poly_area(poly):
    return 0.5 * sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                     for i in range(len(poly)))


def offset_poly(poly, d):
    """Offset a convex polygon inward by d (negative = outward)."""
    pts = [Vector(p) for p in poly]
    n = len(pts)
    if poly_area(poly) < 0:
        d = -d
    lines = []
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        e = (b - a).normalized()
        lines.append((a + Vector((-e.y, e.x)) * d, e))
    out = []
    for i in range(n):
        p1, e1 = lines[i - 1]
        p2, e2 = lines[i]
        den = e1.x * e2.y - e1.y * e2.x
        if abs(den) < 1e-9:
            out.append((p2.x, p2.y))
            continue
        w = p2 - p1
        t = (w.x * e2.y - w.y * e2.x) / den
        q = p1 + e1 * t
        out.append((q.x, q.y))
    return out


def fillet(poly, radius, k=4):
    """Round each corner of a 2-D polygon. radius: float or per-corner list."""
    n = len(poly)
    out = []
    for i in range(n):
        p0, p1, p2 = Vector(poly[i - 1]), Vector(poly[i]), Vector(poly[(i + 1) % n])
        r = radius[i] if isinstance(radius, (list, tuple)) else radius
        a = p0 - p1
        b = p2 - p1
        if r <= 0 or a.length < 1e-6 or b.length < 1e-6:
            out.extend([(p1.x, p1.y)] * (k + 1))
            continue
        ang = a.angle(b)
        if ang > PI - 1e-3:
            out.extend([(p1.x, p1.y)] * (k + 1))
            continue
        t = r / math.tan(ang / 2)
        t = min(t, a.length * 0.49, b.length * 0.49)
        r_eff = t * math.tan(ang / 2)
        a.normalize()
        b.normalize()
        s = p1 + a * t
        e = p1 + b * t
        c = p1 + (a + b).normalized() * (r_eff / math.sin(ang / 2))
        a0 = math.atan2(s.y - c.y, s.x - c.x)
        a1 = math.atan2(e.y - c.y, e.x - c.x)
        da = a1 - a0
        while da > PI:
            da -= 2 * PI
        while da < -PI:
            da += 2 * PI
        for j in range(k + 1):
            aa = a0 + da * j / k
            out.append((c.x + r_eff * math.cos(aa), c.y + r_eff * math.sin(aa)))
    # Drop exact duplicates (zero-radius corners) but keep the count stable for ring frames.
    return out


def dedupe(poly, eps=1e-7):
    out = []
    for p in poly:
        if not out or (abs(p[0] - out[-1][0]) > eps or abs(p[1] - out[-1][1]) > eps):
            out.append(p)
    if len(out) > 1 and abs(out[0][0] - out[-1][0]) < eps and abs(out[0][1] - out[-1][1]) < eps:
        out.pop()
    return out


def densify(poly, step, closed=True):
    out = []
    n = len(poly)
    for i in range(n if closed else n - 1):
        a, b = Vector(poly[i]), Vector(poly[(i + 1) % n])
        m = max(1, int(math.ceil((b - a).length / step)))
        for j in range(m):
            p = a.lerp(b, j / m)
            out.append((p.x, p.y))
    if not closed:
        out.append(tuple(poly[-1]))
    return out


def arch_arc(cy, cz, r, z_cut, n):
    """Arc of a wheel arch from the rear bottom over the top to the front bottom (y, z)."""
    a = math.asin(max(-1.0, min(1.0, (z_cut - cz) / r)))
    return [(cy + r * math.cos(t), cz + r * math.sin(t))
            for t in (lerp(PI - a, a, i / (n - 1)) for i in range(n))]


def catmull(pts, sub):
    P = [Vector(p) for p in pts]
    if len(P) < 3 or sub <= 1:
        return P
    out = []
    for i in range(len(P) - 1):
        p0 = P[i - 1] if i > 0 else P[i] * 2 - P[i + 1]
        p1, p2 = P[i], P[i + 1]
        p3 = P[i + 2] if i + 2 < len(P) else P[i + 1] * 2 - P[i]
        for j in range(sub):
            t = j / sub
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-1])
    return out


# --------------------------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------------------------
def make_mat(name, color, metal=0.0, rough=0.5, emit=None, strength=0.0, alpha=1.0, coat=0.0):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")

    def put(key, val):
        if key in b.inputs:
            b.inputs[key].default_value = val

    put("Base Color", (*color, 1.0))
    put("Metallic", metal)
    put("Roughness", rough)
    if emit:
        put("Emission Color", (*emit, 1.0))
        put("Emission Strength", strength)
    if coat:
        put("Coat Weight", coat)
        put("Coat Roughness", 0.06)
    if alpha < 1.0:
        put("Alpha", alpha)
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(m, attr, val)
            except Exception:
                pass
        try:
            m.use_backface_culling = False
        except Exception:
            pass
    m.diffuse_color = (*color, alpha)
    MAT[name] = m
    return m


def build_materials():
    make_mat("Paint", PAINT_COLOR, metal=0.0, rough=0.4, coat=0.5)
    make_mat("TrimBlack", (0.03, 0.03, 0.03), rough=0.72)
    make_mat("SteelBlack", (0.035, 0.035, 0.038), metal=0.55, rough=0.45)
    make_mat("Chrome", (0.92, 0.92, 0.92), metal=1.0, rough=0.08)
    make_mat("RimGunmetal", (0.16, 0.16, 0.17), metal=1.0, rough=0.32)
    make_mat("Aluminium", (0.72, 0.72, 0.74), metal=1.0, rough=0.28)
    make_mat("Rubber", (0.028, 0.028, 0.028), rough=0.9)
    make_mat("Glass", (0.03, 0.04, 0.045), rough=0.03, alpha=0.28)
    make_mat("HeadlightLens", (0.85, 0.85, 0.8), rough=0.1, emit=(1.0, 0.94, 0.82), strength=3.0)
    make_mat("TailRed", (0.45, 0.02, 0.02), rough=0.15, emit=(1.0, 0.04, 0.02), strength=2.0)
    make_mat("Amber", (0.75, 0.35, 0.02), rough=0.15, emit=(1.0, 0.45, 0.05), strength=1.5)
    make_mat("ReverseWhite", (0.8, 0.8, 0.8), rough=0.12, emit=(1.0, 1.0, 1.0), strength=0.4)
    make_mat("LedLens", (0.8, 0.85, 0.9), rough=0.1, emit=(0.9, 0.95, 1.0), strength=3.0)
    make_mat("EnginePaint", (0.45, 0.05, 0.03), metal=0.2, rough=0.38)
    make_mat("EngineMetal", (0.33, 0.33, 0.34), metal=0.85, rough=0.5)
    make_mat("CastDark", (0.11, 0.11, 0.115), metal=0.7, rough=0.6)
    make_mat("Radiator", (0.07, 0.07, 0.075), metal=0.6, rough=0.55)
    make_mat("Hose", (0.035, 0.035, 0.035), rough=0.55)
    make_mat("CableRed", (0.6, 0.03, 0.02), rough=0.45)
    make_mat("PlasticWhite", (0.72, 0.7, 0.62), rough=0.4)
    make_mat("Interior", (0.07, 0.07, 0.075), rough=0.85)
    make_mat("BedLiner", (0.035, 0.035, 0.035), rough=0.95)
    make_mat("BrakeDisc", (0.42, 0.42, 0.43), metal=1.0, rough=0.35)
    make_mat("Exhaust", (0.26, 0.2, 0.16), metal=0.75, rough=0.65)
    make_mat("MirrorGlass", (0.9, 0.9, 0.9), metal=1.0, rough=0.02)
    make_mat("AccentRed", (0.7, 0.06, 0.03), metal=0.1, rough=0.35)
    make_mat("DamperGold", (0.85, 0.6, 0.18), metal=1.0, rough=0.3)
    make_mat("Plate", (0.85, 0.85, 0.8), rough=0.5)
    make_mat("Dash", (0.05, 0.05, 0.052), rough=0.62)
    make_mat("Seat", (0.075, 0.072, 0.068), rough=0.95)
    make_mat("Headliner", (0.42, 0.4, 0.37), rough=0.92)
    make_mat("Belt", (0.02, 0.02, 0.022), rough=0.8)
    make_mat("Slot", (0.008, 0.008, 0.008), rough=0.9)
    make_mat("GaugeFace", (0.012, 0.012, 0.014), rough=0.35)
    make_mat("GaugeMark", (0.9, 0.9, 0.85), rough=0.4, emit=(1.0, 0.97, 0.9), strength=0.4)
    make_mat("Needle", (1.0, 0.35, 0.05), rough=0.35, emit=(1.0, 0.35, 0.05), strength=0.6)
    make_mat("DomeLens", (0.85, 0.85, 0.8), rough=0.3, emit=(1.0, 0.95, 0.85), strength=0.3)


# --------------------------------------------------------------------------------------------
# Mesh building helpers. Every part is a separate object tagged with a group name; groups are
# baked (modifiers applied) and joined into the exported nodes at the end.
# --------------------------------------------------------------------------------------------
def link(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def obj_from_bm(name, bm, mats, grp, smooth, recalc=True):
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6)
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(MAT[m])
    ob = link(bpy.data.objects.new(name, me))
    ob["grp"] = grp
    ob["smooth"] = smooth
    return ob


def mk(name, verts, faces, mats=("Paint",), fmat=None, grp="Body", smooth=35, recalc=True):
    bm = bmesh.new()
    bv = [bm.verts.new(v) for v in verts]
    for i, f in enumerate(faces):
        vs = [bv[j] for j in f]
        try:
            face = bm.faces.new(vs)
        except ValueError:
            continue
        face.material_index = fmat[i] if fmat else 0
    return obj_from_bm(name, bm, mats, grp, smooth, recalc)


def bevel(ob, width, seg=2, angle=40):
    m = ob.modifiers.new("Bevel", "BEVEL")
    m.width = width
    m.segments = seg
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(angle)
    m.use_clamp_overlap = True
    return ob


def solidify(ob, thickness, offset=-1.0):
    m = ob.modifiers.new("Solidify", "SOLIDIFY")
    m.thickness = thickness
    m.offset = offset
    m.use_even_offset = True
    return ob


def cut(ob, cutter):
    m = ob.modifiers.new("Cut", "BOOLEAN")
    m.operation = "DIFFERENCE"
    m.object = cutter
    m.solver = "EXACT"
    return ob


def prism(name, outline, to3d, d0, d1, mats=("Paint",), side_mats=None, caps=(0, 0), **kw):
    outline = dedupe(outline)
    n = len(outline)
    verts = [to3d(u, v, d0) for u, v in outline] + [to3d(u, v, d1) for u, v in outline]
    faces = [list(range(n)), list(range(n, 2 * n))]
    fm = [caps[0], caps[1]]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, n + j, n + i])
        fm.append(side_mats[i] if side_mats else 0)
    return mk(name, verts, faces, mats, fm, **kw)


def ring_frame(name, outer, inner, to3d, d0, d1, mats=("Paint",), **kw):
    """Closed band between two loops with the same vertex count, extruded from d0 to d1."""
    n = len(outer)
    assert n == len(inner), (name, n, len(inner))
    verts = ([to3d(u, v, d0) for u, v in outer] + [to3d(u, v, d1) for u, v in outer]
             + [to3d(u, v, d0) for u, v in inner] + [to3d(u, v, d1) for u, v in inner])
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append([n + i, n + j, 3 * n + j, 3 * n + i])  # front band
        faces.append([i, 2 * n + i, 2 * n + j, j])  # back band
        faces.append([i, j, n + j, n + i])  # outer wall
        faces.append([2 * n + i, 3 * n + i, 3 * n + j, 2 * n + j])  # inner wall
    return mk(name, verts, faces, mats, **kw)


def box(name, size, center, mat="Paint", rot=(0, 0, 0), bev=0.0, seg=2, angle=40, grp="Body", smooth=35):
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    vs = [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
          (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]
    R = Euler(rot).to_matrix()
    c = Vector(center)
    vs = [R @ Vector(v) + c for v in vs]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    ob = mk(name, vs, faces, (mat,), grp=grp, smooth=smooth)
    if bev:
        bevel(ob, bev, seg, angle)
    return ob


def axis_matrix(axis):
    if isinstance(axis, str):
        axis = {"X": (1, 0, 0), "Y": (0, 1, 0), "Z": (0, 0, 1)}[axis]
    return Vector((0, 0, 1)).rotation_difference(Vector(axis).normalized()).to_matrix().to_4x4()


def cyl(name, r, length, center, axis="Z", segs=24, mat="SteelBlack", r2=None, bev=0.0, seg=2,
        grp="Body", smooth=40):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segs, radius1=r,
                          radius2=r if r2 is None else r2, depth=length)
    M = Matrix.Translation(Vector(center)) @ axis_matrix(axis)
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    ob = obj_from_bm(name, bm, (mat,), grp, smooth)
    if bev:
        bevel(ob, bev, seg)
    return ob


def cyl_between(name, p0, p1, r, **kw):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    return cyl(name, r, d.length, (p0 + p1) / 2, axis=tuple(d.normalized()), **kw)


def revolve(name, prof, segs, mats=("SteelBlack",), axis="X", center=(0, 0, 0), a0=0.0, a1=2 * PI,
            closed=True, prof_mats=None, grp="Body", smooth=40, recalc=True):
    """Revolve a (h, r) profile around the local X axis, then orient it along `axis`.

    The angle is measured from +Y towards +Z, so partial arcs work for wheel arches.
    """
    full = abs((a1 - a0) - 2 * PI) < 1e-6
    nr = segs if full else segs + 1
    npf = len(prof)
    verts = []
    for k in range(nr):
        th = a0 + (a1 - a0) * k / segs
        c, s = math.cos(th), math.sin(th)
        for h, r in prof:
            verts.append(Vector((h, r * c, r * s)))
    if axis != "X":
        R = Vector((1, 0, 0)).rotation_difference(
            Vector({"Y": (0, 1, 0), "Z": (0, 0, 1)}.get(axis, axis) if isinstance(axis, str) else axis).normalized()
        ).to_matrix()
        verts = [R @ v for v in verts]
    verts = [v + Vector(center) for v in verts]
    faces, fm = [], []
    nseg = npf if closed else npf - 1
    for k in range(segs):
        k2 = (k + 1) % nr
        for i in range(nseg):
            i2 = (i + 1) % npf
            faces.append((k * npf + i, k * npf + i2, k2 * npf + i2, k2 * npf + i))
            fm.append(prof_mats[i] if prof_mats else 0)
    if not full and closed:
        faces.append(list(range(npf)))
        fm.append(0)
        faces.append([(nr - 1) * npf + i for i in range(npf)])
        fm.append(0)
    return mk(name, verts, faces, mats, fm, grp=grp, smooth=smooth, recalc=recalc)


def loft(name, rings, mats=("Paint",), cap_start=False, cap_end=True, grp="Body", smooth=35):
    n = len(rings[0])
    verts = [v for ring in rings for v in ring]
    faces = []
    for k in range(len(rings) - 1):
        for i in range(n):
            j = (i + 1) % n
            faces.append((k * n + i, k * n + j, (k + 1) * n + j, (k + 1) * n + i))
    if cap_start:
        faces.append(list(range(n)))
    if cap_end:
        faces.append([(len(rings) - 1) * n + i for i in range(n)])
    return mk(name, verts, faces, mats, grp=grp, smooth=smooth)


def tube(name, pts, r, mat="SteelBlack", nring=10, sub=6, cap=True, closed=False, grp="Body", smooth=50):
    P = catmull(pts + ([pts[0]] if closed else []), sub) if sub > 1 else [Vector(p) for p in pts]
    if closed:
        P = P[:-1]
    n = len(P)
    T = []
    for i in range(n):
        if closed:
            t = P[(i + 1) % n] - P[i - 1]
        elif i == 0:
            t = P[1] - P[0]
        elif i == n - 1:
            t = P[-1] - P[-2]
        else:
            t = P[i + 1] - P[i - 1]
        T.append(t.normalized())
    up = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
    N = T[0].cross(up).normalized()
    verts = []
    for i in range(n):
        if i > 0:
            N = T[i - 1].rotation_difference(T[i]) @ N
            N = (N - T[i] * N.dot(T[i])).normalized()
        B = T[i].cross(N)
        rr = r(i / max(1, n - 1)) if callable(r) else r
        for k in range(nring):
            a = 2 * PI * k / nring
            verts.append(P[i] + (N * math.cos(a) + B * math.sin(a)) * rr)
    faces = []
    segs = n if closed else n - 1
    for i in range(segs):
        i2 = (i + 1) % n
        for k in range(nring):
            k2 = (k + 1) % nring
            faces.append((i * nring + k, i * nring + k2, i2 * nring + k2, i2 * nring + k))
    if cap and not closed:
        faces.append(list(range(nring))[::-1])
        faces.append([(n - 1) * nring + k for k in range(nring)])
    return mk(name, verts, faces, (mat,), grp=grp, smooth=smooth)


def helix_spring(name, center, z0, z1, coil_r, wire_r, turns, mat="AccentRed"):
    pts = []
    steps = int(turns * 14)
    for i in range(steps + 1):
        t = i / steps
        a = 2 * PI * turns * t
        # Closed (flat) end coils like a real spring.
        zz = lerp(z0, z1, smoothstep(0, 1, t) * 0.15 + t * 0.85)
        pts.append((center[0] + coil_r * math.cos(a), center[1] + coil_r * math.sin(a), zz))
    return tube(name, pts, wire_r, mat=mat, nring=7, sub=1)


def mirror_x(fn):
    """Call fn(s) for both sides, s = +1 (right, +X) and -1 (left)."""
    return [fn(1), fn(-1)]


# --------------------------------------------------------------------------------------------
# Wheel (tyre + rim + brake disc). Built once with the outer face towards +X.
# --------------------------------------------------------------------------------------------
def build_wheel_parts(grp, pitches=TREAD_PITCHES, lug=None, lug_root=0.478, tread=0.505):
    """Pickup wheel. pitches, lug (x, s outline), lug_root (lug root radius) and tread (carcass radius under the
    lugs) default to the stock MT tyre; a lower tread gives deeper lugs at the same 0.55 m outer radius."""
    R = WHEEL_R
    # Carcass: open profile from bead to bead over the tread base.
    half = [(0.0, 0.505), (0.08, 0.505), (0.14, 0.503), (0.172, 0.497), (0.192, 0.484), (0.204, 0.465),
            (0.21, 0.44), (0.212, 0.41), (0.209, 0.375), (0.203, 0.345), (0.199, 0.32), (0.206, 0.305),
            (0.204, 0.29), (0.188, 0.282), (0.172, 0.278), (0.165, 0.272)]
    half = [(x, r - (0.505 - tread) * min(1.0, max(0.0, (r - 0.42) / 0.085))) for x, r in half]
    prof = [(-x, r) for x, r in reversed(half[1:])] + half
    revolve("Carcass", prof, TIRE_SEGS, ("Rubber",), closed=False, grp=grp, smooth=40)

    # Tread lugs: alternating shoulder lugs that wrap over the shoulder onto the sidewall.
    pitch = 2 * PI * R / pitches
    lug = lug or [(-0.016, 0.014), (0.10, 0.0), (0.219, 0.006), (0.219, 0.094), (0.10, 0.100), (-0.016, 0.080)]

    def r_top(x):
        return R - max(0.0, abs(x) - 0.165) * 1.25

    def r_base(x):
        return lug_root - max(0.0, abs(x) - 0.17) * 1.1

    verts, faces = [], []
    for k in range(pitches):
        for side in (1, -1):
            off = k * pitch + (0 if side > 0 else pitch / 2)
            poly = [(side * x, s + off) for x, s in lug]
            poly = densify(poly, 0.07)
            n = len(poly)
            base = len(verts)
            for h in (0, 1):
                for x, s in poly:
                    th = s / R
                    rr = r_base(x) if h == 0 else r_top(x)
                    verts.append((x, rr * math.cos(th), rr * math.sin(th)))
            faces.append(list(range(base, base + n)))
            faces.append(list(range(base + n, base + 2 * n)))
            for i in range(n):
                j = (i + 1) % n
                faces.append([base + i, base + j, base + n + j, base + n + i])
            # Sidewall biter between two shoulder lugs.
            th0 = (off + 0.145) / R
            c, s_ = math.cos(th0), math.sin(th0)
            b = [(0.385, -0.022), (0.455, -0.032), (0.455, 0.032), (0.385, 0.022)]
            base = len(verts)
            for xx in (side * 0.196, side * 0.224):
                for u, v in b:
                    verts.append((xx, u * c - v * s_, u * s_ + v * c))
            faces.append([base, base + 1, base + 2, base + 3])
            faces.append([base + 4, base + 5, base + 6, base + 7])
            for i in range(4):
                j = (i + 1) % 4
                faces.append([base + i, base + j, base + 4 + j, base + 4 + i])
    lugs = mk("Lugs", verts, faces, ("Rubber",), grp=grp, smooth=30)
    # Round only the top edges of the lugs (bottom edges are buried in the carcass).
    me = lugs.data
    bw = me.attributes.new("bevel_weight_edge", "FLOAT", "EDGE")
    for e in me.edges:
        top = all(Vector(me.vertices[i].co).yz.length > 0.48 for i in e.vertices)
        bw.data[e.index].value = 1.0 if top else 0.0
    bevel(lugs, 0.007, 1, 30).modifiers["Bevel"].limit_method = "WEIGHT"

    # Rim barrel (closed profile so both the outer and the inner surface exist).
    barrel = [(0.19, 0.26), (0.19, 0.29), (0.178, 0.297), (0.168, 0.288), (0.152, 0.255), (0.13, 0.245),
              (-0.15, 0.245), (-0.168, 0.285), (-0.18, 0.292), (-0.188, 0.285), (-0.175, 0.262),
              (-0.16, 0.235), (0.12, 0.235), (0.145, 0.245), (0.16, 0.258)]
    revolve("Barrel", barrel, 40, ("RimGunmetal",), grp=grp, smooth=40)
    # Beadlock ring + bolts.
    ring = [(0.19, 0.238), (0.212, 0.238), (0.217, 0.244), (0.217, 0.288), (0.211, 0.296), (0.19, 0.296)]
    revolve("Beadlock", ring, 40, ("Aluminium",), grp=grp, smooth=40)
    for i in range(24):
        a = 2 * PI * (i + 0.5) / 24
        cyl(f"BLBolt{i}", 0.0085, 0.012, (0.222, 0.2665 * math.cos(a), 0.2665 * math.sin(a)), axis="X",
            segs=6, mat="Chrome", grp=grp, smooth=0)
    # Lip that the spokes hang from.
    revolve("FaceLip", [(0.118, 0.222), (0.152, 0.222), (0.16, 0.24), (0.118, 0.24)], 40, ("RimGunmetal",),
            grp=grp)
    # Spokes, leaning outwards towards the lip (deep dish look).
    spoke = [(0.09, -0.022), (0.232, -0.03), (0.232, 0.03), (0.09, 0.022)]
    for i in range(8):
        a = 2 * PI * i / 8

        def to3d(u, v, d, a=a):
            return (d + (u - 0.09) * 0.16, u * math.cos(a) - v * math.sin(a), u * math.sin(a) + v * math.cos(a))

        bevel(prism(f"Spoke{i}", spoke, to3d, 0.103, 0.13, ("RimGunmetal",), grp=grp, smooth=40), 0.006, 2)
    # Hub with centre cap.
    hub = [(0.085, 0.0), (0.085, 0.105), (0.14, 0.105), (0.152, 0.094), (0.155, 0.062), (0.163, 0.056),
           (0.176, 0.038), (0.181, 0.0)]
    revolve("Hub", hub, 32, ("RimGunmetal",), grp=grp, smooth=40)
    cyl("Cap", 0.03, 0.006, (0.182, 0, 0), axis="X", segs=24, mat="Chrome", grp=grp)
    for i in range(6):
        a = 2 * PI * i / 6
        cyl(f"Nut{i}", 0.012, 0.02, (0.163, 0.078 * math.cos(a), 0.078 * math.sin(a)), axis="X", segs=6,
            mat="Chrome", grp=grp, smooth=0)
    # Brake disc + hat.
    revolve("Disc", [(-0.075, 0.10), (-0.075, 0.215), (-0.045, 0.215), (-0.045, 0.10)], 40, ("BrakeDisc",),
            grp=grp, smooth=40)
    revolve("Hat", [(-0.05, 0.085), (-0.05, 0.11), (0.086, 0.106), (0.086, 0.085)], 32, ("CastDark",),
            grp=grp)


# --------------------------------------------------------------------------------------------
# Bake / join
# --------------------------------------------------------------------------------------------
def bake_group(grp, name, pivot=(0, 0, 0)):
    objs = [o for o in bpy.data.objects if o.get("grp") == grp]
    dg = bpy.context.evaluated_depsgraph_get()
    mats = []
    bm = bmesh.new()
    for o in objs:
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), depsgraph=dg)
        me.transform(o.matrix_world)
        n = len(me.polygons)
        ang = o.get("smooth", 35)
        if ang > 0:
            me.polygons.foreach_set("use_smooth", [True] * n)
            me.set_sharp_from_angle(angle=math.radians(ang))
        elif ang == 0:
            me.polygons.foreach_set("use_smooth", [False] * n)
        remap = []
        for m in me.materials:
            if m not in mats:
                mats.append(m)
            remap.append(mats.index(m))
        if remap and n:
            idx = [0] * n
            me.polygons.foreach_get("material_index", idx)
            me.polygons.foreach_set("material_index", [remap[min(i, len(remap) - 1)] for i in idx])
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    me.transform(Matrix.Translation(-Vector(pivot)))
    ob = link(bpy.data.objects.new(name, me))
    ob.location = pivot
    return ob


def orient_into(ob, forward):
    """Rotate a baked node about X so its local +Y (Godot -Z) points along `forward`; mesh stays put."""
    f = Vector(forward).normalized()
    ang = math.atan2(f.z, f.y)
    ob.data.transform(Matrix.Rotation(-ang, 4, "X"))
    ob.rotation_euler = (ang, 0, 0)


def mirrored_copy(me, name):
    """Copy of a mesh mirrored across X (left-side wheels) with fixed winding."""
    m2 = me.copy()
    m2.name = name
    bm = bmesh.new()
    bm.from_mesh(m2)
    bmesh.ops.scale(bm, vec=(-1, 1, 1), verts=bm.verts)
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:], flip_multires=False)
    bm.to_mesh(m2)
    bm.free()
    return m2


# --------------------------------------------------------------------------------------------
# Body parts
# --------------------------------------------------------------------------------------------
def along_x(s):
    return lambda u, v, d: (s * d, u, v)  # (u, v) = (y, z)


def along_y(u, v, d):
    return (u, d, v)  # (u, v) = (x, z)


def along_z(u, v, d):
    return (u, v, d)  # (u, v) = (x, y)


def build_chassis():
    for s in (1, -1):
        box(f"Rail{s}", (0.08, 4.30, 0.16), (s * 0.45, -0.03, -0.34), "SteelBlack", bev=0.01)
    for y in (2.05, 0.95, -0.20, -0.85, -2.10):
        box(f"Cross{y}", (0.82, 0.08, 0.10), (0, y, -0.36), "SteelBlack", bev=0.008)
    # Transmission / transfer case / drive shafts.
    cyl("Bellhousing", 0.2, 0.36, (0, 0.86, -0.12), axis="Y", r2=0.14, segs=20, mat="CastDark")
    box("TransferCase", (0.30, 0.30, 0.16), (0, 0.45, -0.45), "CastDark", bev=0.03, seg=2)
    tube("ShaftRear", [(0, 0.30, -0.46), (0, -1.30, -0.44)], 0.035, "SteelBlack", nring=12, sub=1)
    tube("ShaftFront", [(0.08, 0.60, -0.46), (0.18, 1.33, -0.44)], 0.032, "SteelBlack", nring=12, sub=1)
    for p, a in (((0, 0.28, -0.46), "Y"), ((0, -1.27, -0.44), "Y"), ((0.08, 0.62, -0.46), "Y")):
        cyl(f"UJoint{p[1]}", 0.045, 0.05, p, axis=a, segs=12, mat="EngineMetal")
    # Skid plate under the front of the engine bay.
    box("Skid", (0.86, 0.42, 0.012), (0, 1.92, -0.43), "SteelBlack", bev=0.004)
    # Links (static: the game moves the wheels, these are just visual).
    for s in (1, -1):
        tube(f"RadiusArm{s}", [(s * 0.42, 1.42, -0.52), (s * 0.45, 0.75, -0.44)], 0.03, nring=10, sub=1)
        tube(f"TrailArm{s}", [(s * 0.50, -1.38, -0.53), (s * 0.47, -0.75, -0.44)], 0.03, nring=10, sub=1)
        # Coil springs (front ones sit in buckets inside the engine bay).
        helix_spring(f"CoilF{s}", (s * 0.55, AXLE_F_Y), -0.385, -0.03, 0.075, 0.013, 7)
        helix_spring(f"CoilR{s}", (s * 0.52, AXLE_R_Y), -0.385, -0.075, 0.075, 0.013, 6)
        cyl(f"CoilCupF{s}", 0.1, 0.05, (s * 0.55, AXLE_F_Y, -0.005), segs=20, mat="SteelBlack")
        cyl(f"CoilCupR{s}", 0.1, 0.03, (s * 0.52, AXLE_R_Y, -0.06), segs=20, mat="SteelBlack")
        damper(f"DamperF{s}", (s * 0.70, 1.40, -0.50), (s * 0.66, 1.30, 0.05))
        damper(f"DamperR{s}", (s * 0.70, -1.55, -0.50), (s * 0.66, -1.64, -0.10))
    tube("TrackBar", [(-0.75, 1.64, -0.42), (0.45, 1.64, -0.36)], 0.022, nring=10, sub=1)


def damper(name, p_bot, p_top):
    p0, p1 = Vector(p_bot), Vector(p_top)
    d = p1 - p0
    cyl_between(name + "Body", p0 + d * 0.06, p0 + d * 0.58, 0.032, mat="DamperGold", segs=16)
    cyl_between(name + "Rod", p0 + d * 0.5, p0 + d * 0.95, 0.011, mat="Chrome", segs=10)
    cyl_between(name + "Boot", p0 + d * 0.72, p0 + d * 0.96, 0.024, mat="TrimBlack", segs=12)
    cyl_between(name + "Res", p0 + d * 0.2 + Vector((0.045, 0, 0)) * (1 if p0.x > 0 else -1),
                p0 + d * 0.5 + Vector((0.045, 0, 0)) * (1 if p0.x > 0 else -1), 0.024, mat="DamperGold", segs=12)
    for p in (p0, p1):
        cyl(name + f"Eye{p.z:.2f}", 0.022, 0.04, p, axis="Y", segs=12, mat="SteelBlack")


def build_axle(grp, y, front):
    sgn = 1 if front else -1
    diff_x = 0.18 if front else 0.0
    half = 0.84 if front else 0.92
    cyl("Tube", 0.055, 2 * half, (0, y, WHEEL_Z), axis="X", segs=20, mat="SteelBlack", grp=grp)
    # Pumpkin: cover towards the front on the front axle, towards the rear at the back.
    body = [(-0.08, 0.0), (-0.08, 0.085), (-0.04, 0.118), (0.03, 0.125), (0.06, 0.115), (0.06, 0.0)]
    cover = [(0.058, 0.0), (0.058, 0.122), (0.072, 0.122), (0.086, 0.108), (0.097, 0.06), (0.1, 0.0)]
    ax = (0, sgn, 0)
    revolve("Pumpkin", body, 24, ("SteelBlack",), axis=ax, center=(diff_x, y, WHEEL_Z), grp=grp)
    revolve("Cover", cover, 24, ("CastDark",), axis=ax, center=(diff_x, y, WHEEL_Z), grp=grp)
    for i in range(10):
        a = 2 * PI * i / 10
        cyl(f"CovBolt{i}", 0.007, 0.012, (diff_x + 0.11 * math.cos(a), y + sgn * 0.076, WHEEL_Z + 0.11 * math.sin(a)),
            axis="Y", segs=6, mat="Chrome", grp=grp, smooth=0)
    cyl("Pinion", 0.05, 0.11, (diff_x, y - sgn * 0.13, WHEEL_Z), axis="Y", r2=0.038, segs=16, mat="SteelBlack",
        grp=grp)
    for s in (1, -1):
        if front:
            cyl(f"Knuckle{s}", 0.075, 0.17, (s * 0.84, y, WHEEL_Z), segs=20, mat="CastDark", bev=0.025, grp=grp)
            cyl(f"Spindle{s}", 0.07, 0.14, (s * 0.92, y, WHEEL_Z), axis="X", segs=20, mat="CastDark", grp=grp)
            box(f"SteerArm{s}", (0.04, 0.16, 0.03), (s * 0.80, y - 0.09, WHEEL_Z - 0.08), "CastDark", grp=grp,
                bev=0.008)
        else:
            cyl(f"HubR{s}", 0.075, 0.08, (s * 0.94, y, WHEEL_Z), axis="X", segs=20, mat="CastDark", grp=grp)
            # Calipers only on the rear: the front ones would not follow steering.
            box(f"Caliper{s}", (0.07, 0.07, 0.12), (s * 0.99, y + 0.13, WHEEL_Z + 0.12), "AccentRed",
                rot=(math.radians(-45), 0, 0), bev=0.015, grp=grp)
        box(f"Perch{s}", (0.17, 0.17, 0.02), (s * (0.55 if front else 0.52), y, WHEEL_Z + 0.06), "SteelBlack",
            grp=grp, bev=0.004)
        box(f"ShockMount{s}", (0.05, 0.07, 0.07), (s * 0.70, y + (-0.10 if front else -0.10), WHEEL_Z - 0.06),
            "SteelBlack", grp=grp, bev=0.005)
    if front:
        tube("TieRod", [(-0.80, y - 0.17, WHEEL_Z - 0.08), (0.80, y - 0.17, WHEEL_Z - 0.08)], 0.02, "SteelBlack",
             nring=10, sub=1, grp=grp)
        cyl_between("SteerDamper", (-0.35, y - 0.23, WHEEL_Z - 0.07), (0.25, y - 0.23, WHEEL_Z - 0.07), 0.022,
                    mat="DamperGold", segs=12, grp=grp)


def build_front_clip():
    # Fenders (solid side-profile prisms with the wheel arch cut out of the outline).
    for s in (1, -1):
        arc = arch_arc(AXLE_F_Y, WHEEL_Z, ARCH_R, FENDER_BOTTOM_Z, 26)
        outline = ([(FENDER_REAR_Y, FENDER_BOTTOM_Z)] + arc
                   + [(NOSE_Y, FENDER_BOTTOM_Z), (NOSE_Y, HOOD_FRONT_Z - 0.005),
                      (FENDER_REAR_Y, hood_z(FENDER_REAR_Y) - 0.005)])
        side = [0] + [1] * (len(arc) - 1) + [0] * 4
        bevel(prism(f"Fender{s}", outline, along_x(s), FENDER_IN_X, BODY_HALF_W, ("Paint", "TrimBlack"),
                    side_mats=side), 0.025, 3, 40)
        flare(f"FlareF{s}", s, AXLE_F_Y, FENDER_BOTTOM_Z)
        # Headlight in the fender front.
        hx = s * 0.76
        revolve(f"Bezel{s}", [(0.0, 0.094), (0.022, 0.1), (0.028, 0.114), (0.02, 0.124), (0.0, 0.124)], 32,
                ("Chrome",), axis="Y", center=(hx, NOSE_Y - 0.004, 0.19))
        revolve(f"Lens{s}", [(0.0, 0.0), (0.0, 0.097), (0.012, 0.093), (0.02, 0.07), (0.024, 0.0)], 32,
                ("HeadlightLens",), axis="Y", center=(hx, NOSE_Y - 0.004, 0.19))
        box(f"Indicator{s}", (0.15, 0.014, 0.065), (s * 0.76, NOSE_Y + 0.004, 0.02), "Amber", bev=0.008)
        box(f"Marker{s}", (0.012, 0.07, 0.035), (s * (BODY_HALF_W + 0.003), 2.06, 0.22), "Amber", bev=0.004)
    # Fascia and grille between the fenders.
    fx = FENDER_IN_X - 0.005
    box("GrilleTop", (2 * fx, 0.08, 0.065), (0, 2.138, 0.335), "Paint", bev=0.012)
    box("GrilleBottom", (2 * fx, 0.08, 0.09), (0, 2.138, -0.115), "Paint", bev=0.012)
    for s in (1, -1):
        box(f"GrilleSide{s}", (0.065, 0.08, 0.46), (s * (fx - 0.0325), 2.138, 0.11), "Paint", bev=0.012)
    box("GrilleBack", (1.1, 0.02, 0.38), (0, 2.08, 0.11), "Radiator")
    for i in range(6):
        z = -0.045 + i * 0.062
        box(f"Slat{i}", (1.09, 0.05, 0.026), (0, 2.15, z), "TrimBlack", bev=0.006)
    for x in (-0.18, 0.18):
        box(f"Bar{x}", (0.03, 0.05, 0.36), (x, 2.152, 0.11), "TrimBlack", bev=0.006)
    box("Badge", (0.2, 0.012, 0.05), (0, 2.18, 0.23), "Chrome", bev=0.01, seg=3)
    box("Valance", (1.24, 0.08, 0.14), (0, 2.12, -0.23), "SteelBlack", bev=0.01)
    # Cowl, firewall, hood hinges.
    box("Cowl", (2 * fx, 0.185, 0.03), (0, 0.8825, 0.483), "Paint", bev=0.008)
    box("CowlVent", (1.0, 0.07, 0.008), (0, 0.9, 0.5), "TrimBlack", bev=0.002)
    box("Firewall", (2 * fx, 0.03, 0.78), (0, 0.935, 0.08), "Paint")
    for s in (1, -1):
        box(f"HoodHinge{s}", (0.03, 0.06, 0.04), (s * 0.55, 0.985, 0.465), "SteelBlack", bev=0.005)
        # Wipers resting on the windscreen base.
        z0, z1 = 0.575, 0.62
        x0, x1 = (0.08, 0.6) if s > 0 else (-0.62, -0.1)
        p0 = Vector((x0, ws_y(z0) + 0.02, z0))
        p1 = Vector((x1, ws_y(z1) + 0.02, z1))
        cyl_between(f"Wiper{s}", p0, p1, 0.007, mat="TrimBlack", segs=6)
        cyl_between(f"WiperArm{s}", (x0 + 0.08, 0.86, 0.505), (x0 + 0.06, ws_y(0.6) + 0.03, 0.6), 0.008,
                    mat="TrimBlack", segs=6)


def flare(name, s, cy, z_cut):
    """Black fender flare revolved around the wheel axis."""
    a = math.asin((z_cut - WHEEL_Z) / ARCH_R)
    prof = [(0.895, 0.632), (0.922, 0.632), (0.922, 0.70), (1.12, 0.69), (1.152, 0.665), (1.172, 0.668),
            (1.178, 0.70), (1.165, 0.735), (1.10, 0.752), (0.895, 0.762)]
    prof = [(s * x, r) for x, r in prof]
    if s < 0:
        prof = prof[::-1]
    revolve(name, prof, 30, ("TrimBlack",), center=(0, cy, WHEEL_Z), a0=a, a1=PI - a, smooth=35)
    for i in range(9):
        t = lerp(a + 0.08, PI - a - 0.08, i / 8)
        cyl(f"{name}Bolt{i}", 0.009, 0.012, (s * 1.0, cy + 0.73 * math.cos(t), WHEEL_Z + 0.73 * math.sin(t) + 0.025),
            axis="Z", segs=6, mat="Chrome", smooth=0)


def build_cab():
    # Lower shell: open-top box, rounded, hollow, door openings cut out.
    hx = BODY_HALF_W - 0.005
    y0, y1, z0, z1 = CAB_BACK_Y, WS_BASE_Y, SILL_Z, BELT_Z
    vs = [(-hx, y0, z0), (hx, y0, z0), (hx, y1, z0), (-hx, y1, z0),
          (-hx, y0, z1), (hx, y0, z1), (hx, y1, z1), (-hx, y1, z1)]
    lower = mk("CabLower", vs, [(0, 3, 2, 1), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)])
    bevel(lower, 0.045, 3, 40)
    solidify(lower, 0.03)

    # Greenhouse: lofted rounded rectangles with tumblehome and a raked windscreen.
    def rr(hx_, ya, yb, r, z):
        return [(x, y, z) for x, y in fillet([(-hx_, ya), (hx_, ya), (hx_, yb), (-hx_, yb)], r, 5)]

    rings = [rr(side_x(0.50), back_y(0.50), ws_y(0.50), 0.05, 0.50),
             rr(side_x(1.10), back_y(1.10), ws_y(1.10), 0.06, 1.10),
             rr(0.745, -0.665, 0.335, 0.07, 1.148),
             rr(0.705, -0.63, 0.295, 0.07, ROOF_Z)]
    gh = loft("Greenhouse", rings)
    solidify(gh, 0.03)

    def cutter(name, outline, to3d, d0, d1):
        ob = prism(name, outline, to3d, d0, d1, grp="Cutter")
        ob.hide_render = True
        ob.display_type = "WIRE"
        return ob

    ws_poly = [(-0.72, 0.565), (0.72, 0.565), (0.665, 1.055), (-0.665, 1.055)]
    ws_cut = fillet(ws_poly, [0.035, 0.035, 0.06, 0.06], 5)
    cut(gh, cutter("CutWS", ws_cut, along_y, 0.2, 1.1))
    rear_poly = [(-0.56, 0.64), (0.56, 0.64), (0.56, 1.02), (-0.56, 1.02)]
    rear_cut = fillet(rear_poly, 0.06, 5)
    cut(gh, cutter("CutRear", rear_cut, along_y, -1.0, -0.5))
    quarter_poly = [(-0.62, 0.60), (-0.40, 0.60), (-0.40, 1.04), (-0.62, 1.04)]
    quarter_cut = fillet(quarter_poly, 0.04, 4)
    for s in (1, -1):
        door_cut = fillet(DOOR_POLY, [0.04, 0.04, 0.0, 0.07, 0.05], 5)
        c = cutter(f"CutDoor{s}", door_cut, along_x(s), 0.55, 1.0)
        cut(gh, c)
        cut(lower, c)
        cut(gh, cutter(f"CutQuarter{s}", quarter_cut, along_x(s), 0.55, 1.0))

    # Glass + black seals.
    def glass_ring(name, poly, to_surface, k=5, radius=0.05):
        g = fillet(offset_poly(poly, -0.015), radius, k)
        prism(name + "Glass", g, to_surface(-0.016), 0.0, 0.005, ("Glass",), smooth=0)
        outer = fillet(offset_poly(poly, -0.012), radius, k)
        inner = fillet(offset_poly(poly, 0.008), radius, k)
        ring_frame(name + "Seal", outer, inner, to_surface(-0.004), 0.0, 0.006, ("TrimBlack",))

    glass_ring("WS", ws_poly, lambda o: (lambda u, v, d: (u, ws_y(v) + o + d, v)), radius=[0.035, 0.035, 0.06, 0.06])
    glass_ring("Rear", rear_poly, lambda o: (lambda u, v, d: (u, back_y(v) - o - d, v)), radius=0.06)
    for s in (1, -1):
        glass_ring(f"Quarter{s}", quarter_poly,
                   lambda o, s=s: (lambda u, v, d: (s * (side_x(v) + o + d), u, v)), k=4, radius=0.04)

    # Roof gutters, clearance lights, third brake light.
    for s in (1, -1):
        tube(f"Gutter{s}", [(s * 0.778, 0.36, 1.115), (s * 0.778, -0.69, 1.115)], 0.008, "Paint", nring=6, sub=1)
    for i, x in enumerate((-0.3, -0.15, 0.0, 0.15, 0.3)):
        box(f"Clearance{i}", (0.06, 0.03, 0.022), (x, 0.31, ROOF_Z + 0.005), "Amber", bev=0.008)
    box("ThirdBrake", (0.3, 0.03, 0.035), (0, -0.66, ROOF_Z + 0.01), "TailRed", bev=0.008)
    # Rock sliders under the doors.
    for s in (1, -1):
        tube(f"Slider{s}", [(s * 0.94, 0.70, -0.31), (s * 0.97, 0.66, -0.34), (s * 0.97, -0.62, -0.34),
                            (s * 0.94, -0.68, -0.31)], 0.035, "SteelBlack", nring=12, sub=4)
        for y in (0.45, -0.45):
            tube(f"SliderLeg{s}{y}", [(s * 0.96, y, -0.34), (s * 0.49, y, -0.36)], 0.025, "SteelBlack",
                 nring=10, sub=1)
        box(f"SliderStep{s}", (0.08, 1.2, 0.012), (s * 0.94, 0.0, -0.302), "SteelBlack", bev=0.004)
        # External door hinges on the A-pillar side of the door gap.
        for z in (-0.05, 0.36):
            box(f"DoorHinge{s}{z}", (0.022, 0.045, 0.1), (s * 0.912, DOOR_FRONT_Y + 0.012, z), "SteelBlack",
                bev=0.006)
            cyl(f"HingePin{s}{z}", 0.008, 0.12, (s * 0.925, DOOR_FRONT_Y + 0.004, z), segs=8, mat="Chrome")


DOOR_POLY = [(DOOR_REAR_Y, DOOR_BOTTOM_Z), (DOOR_FRONT_Y, DOOR_BOTTOM_Z), (DOOR_FRONT_Y, 0.53),
             (0.32, 1.075), (DOOR_REAR_Y, 1.075)]


def build_door(s):
    grp = "Door_R" if s > 0 else "Door_L"
    lower_poly = [(DOOR_REAR_Y, DOOR_BOTTOM_Z), (DOOR_FRONT_Y, DOOR_BOTTOM_Z), (DOOR_FRONT_Y, BELT_Z),
                  (DOOR_REAR_Y, BELT_Z)]
    lp = fillet(offset_poly(lower_poly, 0.004), [0.04, 0.04, 0.0, 0.0], 4)
    bevel(prism("DoorSkin", lp, along_x(s), 0.866, 0.902, ("Paint", "Interior"), caps=(1, 0), grp=grp), 0.01,
          2, 40)
    up = [(DOOR_REAR_Y, BELT_Z), (DOOR_FRONT_Y, BELT_Z), (0.32, 1.075), (DOOR_REAR_Y, 1.075)]
    radii = [0.0, 0.0, 0.066, 0.046]

    def on_side(o):
        return lambda u, v, d: (s * (side_x(v) + o + d), u, v)

    outer = fillet(offset_poly(up, 0.004), radii, 4)
    inner = fillet(offset_poly(up, 0.032), radii, 4)
    bevel(ring_frame("DoorFrame", outer, inner, on_side(-0.028), 0.0, 0.031, ("Paint",), grp=grp), 0.004, 1)
    glass = fillet(offset_poly(up, 0.018), radii, 4)
    prism("DoorGlass", glass, on_side(-0.016), 0.0, 0.005, ("Glass",), grp=grp, smooth=0)
    box("BeltMolding", (0.04, DOOR_FRONT_Y - DOOR_REAR_Y - 0.01, 0.018),
        (s * 0.886, (DOOR_FRONT_Y + DOOR_REAR_Y) / 2, BELT_Z + 0.007), "TrimBlack", grp=grp, bev=0.004)
    box("HandleRecess", (0.004, 0.16, 0.06), (s * 0.9035, -0.19, 0.36), "TrimBlack", grp=grp)
    box("Handle", (0.024, 0.13, 0.026), (s * 0.912, -0.19, 0.36), "TrimBlack", grp=grp, bev=0.008)
    box("Armrest", (0.05, 0.42, 0.05), (s * 0.84, 0.12, 0.27), "Interior", grp=grp, bev=0.015)
    # Door card details facing the cab.
    xi = s * 0.866
    box("CardTrim", (0.02, 0.97, 0.06), (xi - s * 0.008, 0.2, 0.485), "Dash", grp=grp, bev=0.006)
    box("PullHandle", (0.03, 0.16, 0.03), (xi - s * 0.04, 0.12, 0.31), "TrimBlack", grp=grp, bev=0.008)
    box("InnerHandleRecess", (0.006, 0.11, 0.04), (xi - s * 0.003, 0.52, 0.38), "Slot", grp=grp, bev=0.004)
    box("InnerHandle", (0.012, 0.09, 0.016), (xi - s * 0.01, 0.52, 0.38), "Chrome", grp=grp, bev=0.004)
    cyl("CrankHub", 0.018, 0.016, (xi - s * 0.008, 0.3, 0.41), axis="X", segs=12, mat="Chrome", grp=grp)
    box("CrankArm", (0.01, 0.1, 0.014), (xi - s * 0.016, 0.35, 0.41), "Chrome", grp=grp, bev=0.003)
    cyl("CrankKnob", 0.011, 0.035, (xi - s * 0.035, 0.395, 0.41), axis="X", segs=10, mat="TrimBlack", grp=grp)
    box("MapPocket", (0.035, 0.55, 0.14), (xi - s * 0.017, 0.2, -0.16), "Dash", grp=grp, bev=0.01)
    cyl("Speaker", 0.065, 0.006, (xi - s * 0.003, 0.52, -0.1), axis="X", segs=24, mat="TrimBlack", grp=grp)
    revolve("SpeakerRing", [(0.0, 0.062), (0.006, 0.064), (0.006, 0.07), (0.0, 0.07)], 24, ("Chrome",),
            axis=(-s, 0, 0), center=(xi, 0.52, -0.1), grp=grp)
    cyl("LockKnob", 0.006, 0.03, (xi - s * 0.02, -0.22, 0.53), segs=8, mat="Chrome", grp=grp)
    # Mirror.
    tube("MirrorArm", [(s * 0.90, 0.63, 0.60), (s * 1.0, 0.61, 0.63), (s * 1.06, 0.6, 0.66)], 0.013, nring=8,
         sub=3, grp=grp)
    tube("MirrorArm2", [(s * 0.90, 0.63, 0.47), (s * 1.0, 0.61, 0.55), (s * 1.08, 0.6, 0.58)], 0.011, nring=8,
         sub=3, grp=grp)
    box("MirrorHousing", (0.15, 0.07, 0.22), (s * 1.11, 0.59, 0.68), "TrimBlack", grp=grp, bev=0.022, seg=3)
    box("MirrorGlass", (0.13, 0.004, 0.195), (s * 1.11, 0.553, 0.68), "MirrorGlass", grp=grp, bev=0.001)
    return grp


def obox(name, center, U, V, N, size, mat, grp="Body", bev=0.0, seg=2, smooth=35):
    """Box with its edges along the (not necessarily world-aligned) axes U, V, N."""
    c, U, V, N = Vector(center), Vector(U).normalized(), Vector(V).normalized(), Vector(N).normalized()
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    vs = [c + U * x + V * y + N * z for x, y, z in
          ((-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
           (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz))]
    faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    ob = mk(name, vs, faces, (mat,), grp=grp, smooth=smooth)
    if bev:
        bevel(ob, bev, seg)
    return ob


def gauge_face_y(z):
    """The instrument face in the binnacle is a plane leaning back towards the driver's eyes."""
    return 0.43 + (z - 0.47) * 0.03 / 0.178


def gauge(name, x, z, r, ticks, major, red_from=None):
    N = Vector(GAUGE_N)
    U = Vector((1, 0, 0))
    V = N.cross(U).normalized()
    C = Vector((x, gauge_face_y(z), z)) + N * 0.002
    revolve(f"{name}Bezel", [(0.0, r), (0.006, r), (0.008, r + 0.004), (0.004, r + 0.008), (0.0, r + 0.008)], 32,
            ("Chrome",), axis=tuple(N), center=tuple(C))
    cyl(f"{name}Face", r, 0.003, tuple(C - N * 0.001), axis=tuple(N), segs=32, mat="GaugeFace")
    for i in range(ticks + 1):
        th = math.radians(-135 + 270 * i / ticks)
        d = V * math.cos(th) + U * math.sin(th)
        p = U * math.cos(th) - V * math.sin(th)
        big = i % major == 0
        ln = 0.011 if big else 0.006
        mat = "TailRed" if red_from is not None and i >= red_from else "GaugeMark"
        obox(f"{name}Tick{i}", C + d * (r * 0.9 - ln / 2) + N * 0.001, p, d, N,
             (0.0022 if big else 0.0013, ln, 0.0008), mat)
    # The needle is its own node; at rest it points at the first tick.
    th = math.radians(-135)
    d = V * math.cos(th) + U * math.sin(th)
    p = U * math.cos(th) - V * math.sin(th)
    grp = f"Needle_{name}"
    obox(f"{name}Needle", C + N * 0.004 + d * (r * 0.38), p, d, N, (0.0028, r * 0.95, 0.0012), "Needle", grp=grp)
    cyl(f"{name}NeedleCap", r * 0.12, 0.004, tuple(C + N * 0.005), axis=tuple(N), segs=16, mat="GaugeFace", grp=grp)
    NEEDLES.append((grp, tuple(C + N * 0.004)))


def seat(s):
    x, yc = s * 0.42, SEAT_CUSHION_Y
    for k in (1, -1):
        box(f"SeatRail{s}{k}", (0.03, 0.46, 0.02), (x + k * 0.15, yc, -0.33), "SteelBlack")
    box(f"SeatFrame{s}", (0.42, 0.42, 0.13), (x, yc - 0.01, -0.255), "TrimBlack", bev=0.01)
    box(f"Cushion{s}", (0.5, 0.5, 0.11), (x, yc, -0.135), "Seat", bev=0.04, seg=3)
    for k in (1, -1):
        box(f"CushionBolster{s}{k}", (0.07, 0.46, 0.07), (x + k * 0.215, yc, -0.07), "Seat", bev=0.03, seg=3)
    a = math.radians(12)
    R = Matrix.Rotation(a, 3, "X")
    H = Vector((x, yc - 0.24, -0.11))

    def at(lx, ly, lz):
        return tuple(H + R @ Vector((lx, ly, lz)))

    box(f"Backrest{s}", (0.5, 0.11, 0.62), at(0, -0.05, 0.34), "Seat", rot=(a, 0, 0), bev=0.04, seg=3)
    for k in (1, -1):
        box(f"BackBolster{s}{k}", (0.07, 0.1, 0.5), at(k * 0.215, 0.0, 0.31), "Seat", rot=(a, 0, 0), bev=0.03, seg=3)
        cyl(f"HeadPost{s}{k}", 0.006, 0.1, at(k * 0.07, -0.05, 0.69), axis=tuple(R @ Vector((0, 0, 1))), segs=8,
            mat="Chrome")
    box(f"Headrest{s}", (0.26, 0.09, 0.17), at(0, -0.05, 0.8), "Seat", rot=(a, 0, 0), bev=0.035, seg=3)
    cyl(f"Buckle{s}", 0.012, 0.12, (x - s * 0.27, yc - 0.18, -0.06), axis=(0, 0.3, 1), segs=8, mat="TrimBlack")
    box(f"BeltStrap{s}", (0.006, 0.045, 1.15), (s * 0.81, -0.31, 0.35), "Belt", rot=(0.05, 0, 0))
    box(f"BeltAnchor{s}", (0.02, 0.06, 0.08), (s * 0.81, -0.31, 0.93), "TrimBlack", bev=0.008)


def build_interior():
    box("FloorMat", (1.7, 1.45, 0.02), (0, 0.04, -0.34), "Rubber")
    box("Tunnel", (0.36, 0.95, 0.17), (0, 0.32, -0.27), "Rubber", bev=0.06, seg=3)
    # Dashboard (side-profile prism) and the instrument binnacle in front of the driver.
    dash = [(0.775, 0.2), (0.775, 0.555), (0.70, 0.566), (0.53, 0.592), (0.495, 0.585), (0.475, 0.52),
            (0.47, 0.4), (0.5, 0.28), (0.56, 0.2)]
    bevel(prism("Dash", dash, along_x(1), -0.845, 0.845, ("Dash",)), 0.012, 2, 40)
    binn = [(0.43, 0.47), (0.62, 0.47), (0.62, 0.6), (0.5, 0.682), (0.415, 0.678), (0.405, 0.664), (0.46, 0.65)]
    bevel(prism("Binnacle", binn, along_x(1), -0.66, -0.18, ("Dash",)), 0.006, 2, 40)
    gauge("Speed", -0.52, 0.585, 0.05, 36, 4)
    gauge("RPM", -0.32, 0.585, 0.05, 32, 4, red_from=26)
    gauge("Fuel", -0.45, 0.505, 0.022, 4, 2, red_from=None)
    gauge("Temp", -0.39, 0.505, 0.022, 4, 2, red_from=4)
    for i, m in enumerate(("Amber", "TailRed", "LedLens", "Amber")):
        x = -0.6 + i * 0.024 if i < 2 else -0.24 - (i - 2) * 0.024
        cyl(f"Telltale{i}", 0.005, 0.003, (x, gauge_face_y(0.5), 0.5), axis=tuple(-Vector(GAUGE_N)), segs=10, mat=m)
    # Centre stack: vents, radio, heater knobs, switches; glovebox and grab handle on the passenger side.
    for x in (-0.76, -0.1, 0.1, 0.76):
        revolve(f"Vent{x}", [(0.0, 0.026), (0.012, 0.028), (0.012, 0.034), (0.0, 0.034)], 20, ("TrimBlack",),
                axis=(0, -1, 0), center=(x, 0.47, 0.5))
        cyl(f"VentBack{x}", 0.027, 0.004, (x, 0.478, 0.5), axis="Y", segs=20, mat="Slot")
        for k in (-1, 0, 1):
            box(f"VentSlat{x}{k}", (0.05, 0.012, 0.004), (x, 0.468, 0.5 + k * 0.014), "TrimBlack")
    box("Radio", (0.19, 0.03, 0.055), (0, 0.475, 0.43), "TrimBlack", bev=0.004)
    box("RadioDisplay", (0.08, 0.004, 0.016), (0, 0.4595, 0.438), "Amber")
    for x in (-0.072, 0.072):
        cyl(f"RadioKnob{x}", 0.009, 0.014, (x, 0.456, 0.43), axis="Y", segs=12, mat="Chrome")
    for i, x in enumerate((-0.07, 0.0, 0.07)):
        cyl(f"HeaterKnob{i}", 0.016, 0.018, (x, 0.464, 0.365), axis="Y", segs=16, mat="TrimBlack", bev=0.003)
        box(f"HeaterMark{i}", (0.002, 0.003, 0.012), (x, 0.454, 0.372), "GaugeMark")
    for i in range(5):
        x = 0.17 + i * 0.035
        box(f"SwitchBase{i}", (0.022, 0.01, 0.03), (x, 0.47, 0.46), "TrimBlack")
        cyl_between(f"Toggle{i}", (x, 0.466, 0.46), (x, 0.448, 0.468), 0.003, mat="Chrome", segs=6)
    box("Glovebox", (0.34, 0.012, 0.12), (0.5, 0.466, 0.44), "Dash", bev=0.006)
    box("GloveHandle", (0.07, 0.012, 0.014), (0.5, 0.458, 0.48), "Chrome", bev=0.003)
    tube("GrabHandle", [(0.32, 0.53, 0.59), (0.34, 0.505, 0.632), (0.6, 0.505, 0.632), (0.62, 0.53, 0.59)], 0.012,
         "TrimBlack", nring=8, sub=4)
    for x in (-0.3, 0.3):
        box(f"Defrost{x}", (0.4, 0.03, 0.004), (x, 0.66, 0.578), "Slot")
    # Steering column (the wheel itself is a separate node).
    W, n = Vector(WHEEL_C), Vector(WHEEL_AXIS).normalized()
    U = Vector((1, 0, 0))
    V = n.cross(U).normalized()
    obox("ColumnShroud", W - n * 0.15, U, V, n, (0.085, 0.08, 0.2), "Dash", bev=0.02)
    cyl_between("Column", W - n * 0.04, W - n * 0.08, 0.025, mat="TrimBlack", segs=12)
    for k in (1, -1):
        cyl_between(f"Stalk{k}", W - n * 0.08 + U * k * 0.04, W - n * 0.07 + U * k * 0.15 - V * 0.03, 0.006,
                    mat="TrimBlack", segs=8)
    cyl("Ignition", 0.012, 0.012, tuple(W - n * 0.13 + U * 0.045), axis="X", segs=12, mat="Chrome")
    build_steering_wheel()
    # Pedals: clutch, brake, accelerator.
    for name, x, w, h in (("Clutch", -0.56, 0.07, 0.075), ("Brake", -0.44, 0.09, 0.075)):
        cyl_between(f"{name}Arm", (x, 0.68, 0.22), (x, 0.6, -0.15), 0.008, mat="SteelBlack", segs=8)
        obox(f"{name}Pad", (x, 0.59, -0.17), (1, 0, 0), (0, -0.3, 0.95), (0, 0.95, 0.3), (w, h, 0.012), "Rubber",
             bev=0.003)
    obox("Throttle", (-0.29, 0.58, -0.24), (1, 0, 0), (0, -0.45, 0.89), (0, 0.89, 0.45), (0.055, 0.17, 0.012),
         "Rubber", bev=0.003)
    # Gear lever, transfer-case lever, handbrake.
    cyl("ShiftBoot", 0.055, 0.08, (0, 0.27, -0.15), segs=16, r2=0.016, mat="TrimBlack")
    tube("GearLever", [(0, 0.27, -0.15), (0, 0.255, 0.02), (0, 0.22, 0.16)], 0.008, "Chrome", nring=8, sub=4)
    revolve("GearKnob", [(-0.022, 0.0), (-0.02, 0.012), (-0.008, 0.022), (0.008, 0.022), (0.02, 0.012),
                         (0.022, 0.0)], 16, ("TrimBlack",), axis="Z", center=(0, 0.215, 0.175), smooth=60)
    tube("TransferLever", [(0.09, 0.22, -0.18), (0.095, 0.2, -0.05), (0.1, 0.17, 0.06)], 0.007, "Chrome", nring=8,
         sub=4)
    cyl("TransferKnob", 0.016, 0.03, (0.1, 0.168, 0.07), segs=12, mat="AccentRed", bev=0.005)
    tube("Handbrake", [(0, 0.04, -0.18), (0, -0.08, -0.15), (0, -0.2, -0.1)], 0.013, "TrimBlack", nring=8, sub=3)
    for s in (1, -1):
        seat(s)
    # Headliner, dome light, grab handles, visors, rear-view mirror.
    hl = fillet([(-0.665, -0.6), (0.665, -0.6), (0.665, 0.28), (-0.665, 0.28)], 0.06, 4)
    prism("Headliner", hl, along_z, 1.118, 1.132, ("Headliner",))
    box("DomeLight", (0.15, 0.08, 0.014), (0, -0.15, 1.112), "TrimBlack", bev=0.004)
    box("DomeLens", (0.12, 0.05, 0.004), (0, -0.15, 1.104), "DomeLens")
    for s in (1, -1):
        tube(f"RoofGrab{s}", [(s * 0.66, -0.05, 1.118), (s * 0.645, 0.0, 1.075), (s * 0.645, 0.2, 1.075),
                              (s * 0.66, 0.25, 1.118)], 0.011, "TrimBlack", nring=8, sub=3)
        box(f"Visor{s}", (0.38, 0.16, 0.016), (s * 0.4, 0.22, 1.1), "Headliner", rot=(math.radians(12), 0, 0),
            bev=0.006)
    for s in (1, -1):  # A-pillar grab handles for climbing in
        tube(f"PillarGrab{s}", [(s * 0.8, 0.635, 0.66), (s * 0.755, 0.625, 0.68), (s * 0.735, 0.545, 0.8),
                                (s * 0.755, 0.47, 0.9), (s * 0.785, 0.465, 0.92)], 0.014, "TrimBlack", nring=10, sub=4)
    cyl_between("MirrorStem", (0, 0.31, 1.118), (0, 0.3, 1.05), 0.006, mat="TrimBlack", segs=8)
    box("InnerMirror", (0.25, 0.03, 0.07), (0, 0.3, 1.025), "TrimBlack", bev=0.012, seg=2)
    box("InnerMirrorGlass", (0.23, 0.003, 0.055), (0, 0.284, 1.025), "MirrorGlass")
    box("RearWallPad", (1.5, 0.02, 0.5), (0, -0.675, 0.1), "Interior", bev=0.01)


def build_steering_wheel():
    grp = "SteeringWheel"
    W, n = Vector(WHEEL_C), Vector(WHEEL_AXIS).normalized()
    U = Vector((1, 0, 0))
    V = n.cross(U).normalized()
    prof = [(0.015 * math.cos(a), WHEEL_RIM_R + 0.019 * math.sin(a)) for a in (2 * PI * i / 10 for i in range(10))]
    revolve("Rim", prof, 40, ("Interior",), axis=tuple(n), center=tuple(W), grp=grp, smooth=60)
    for d in (U, -U, -V):
        obox(f"Spoke{tuple(d)}", W + d * 0.115 - n * 0.012, d.cross(n), d, n, (0.032, 0.15, 0.01), "SteelBlack",
             grp=grp, bev=0.003)
    cyl("WheelHub", 0.055, 0.045, tuple(W - n * 0.025), axis=tuple(n), segs=20, mat="Interior", grp=grp)
    revolve("HornPad", [(0.0, 0.0), (0.0, 0.05), (0.012, 0.046), (0.02, 0.03), (0.024, 0.0)], 20, ("Interior",),
            axis=tuple(n), center=tuple(W), grp=grp, smooth=60)
    cyl("HornBadge", 0.014, 0.003, tuple(W + n * 0.024), axis=tuple(n), segs=16, mat="Chrome", grp=grp)


def build_hood():
    grp = "Hood"
    xs = [-HOOD_HALF_W, -0.59, -0.52, -0.42, -0.36, -0.335, -0.31, -0.28, -0.2, -0.1, 0.0]
    xs = xs + [-x for x in reversed(xs[:-1])]
    ys = [HOOD_HINGE_Y, 1.02, 1.08, 1.14, 1.17, 1.2, 1.3, 1.45, 1.6, 1.75, 1.88, 1.95, 1.98, 2.01, 2.08, 2.14,
          HOOD_FRONT_Y]

    def z_at(x, y):
        crown = 0.018 * (1 - (x / HOOD_HALF_W) ** 2)
        bulge = 0.032 * smoothstep(0.36, 0.30, abs(x)) * smoothstep(1.10, 1.20, y) * smoothstep(2.02, 1.92, y)
        return hood_z(y) + crown + bulge

    verts = [(x, y, z_at(x, y)) for y in ys for x in xs]
    # Front lip folding down.
    for dz, dy in ((0.02, 0.006), (0.042, 0.004)):
        verts += [(x, HOOD_FRONT_Y + dy, z_at(x, HOOD_FRONT_Y) - dz) for x in xs]
    nx = len(xs)
    rows = len(ys) + 2
    faces = []
    for j in range(rows - 1):
        for i in range(nx - 1):
            a = j * nx + i
            faces.append((a, a + 1, a + nx + 1, a + nx))
    hood = mk("HoodPanel", verts, faces, ("Paint",), grp=grp, smooth=50, recalc=False)
    solidify(hood, 0.02)
    bevel(hood, 0.005, 2, 50)
    # Insulation pad underneath and two vents on the bulge shoulders.
    pad = [(-0.5, 1.08), (0.5, 1.08), (0.5, 2.02), (-0.5, 2.02)]
    prism("HoodPad", pad, lambda u, v, d: (u, v, hood_z(v) - 0.03 - d), 0.0, 0.012, ("TrimBlack",), grp=grp)
    for s in (1, -1):
        for i in range(4):
            y = 1.36 + i * 0.05
            box(f"Vent{s}{i}", (0.16, 0.022, 0.012), (s * 0.47, y, z_at(0.47, y) + 0.004), "TrimBlack", grp=grp,
                rot=(-math.atan(0.063), 0, 0), bev=0.004)
    return grp


def build_engine_bay():
    ez = 0.06  # raise from the nominal layout
    # Block, head, valve cover.
    box("Block", (0.34, 0.73, 0.36), (0, 1.415, -0.12 + ez), "EngineMetal", bev=0.02)
    for s in (1, -1):
        for i in range(5):
            box(f"BlockRib{s}{i}", (0.015, 0.025, 0.3), (s * 0.175, 1.12 + i * 0.15, -0.12 + ez), "EngineMetal")
    box("OilPanDeep", (0.28, 0.25, 0.12), (0, 1.175, -0.36), "CastDark", bev=0.015)
    box("OilPanShallow", (0.28, 0.45, 0.05), (0, 1.52, -0.265), "CastDark", bev=0.01)
    box("Head", (0.32, 0.71, 0.09), (0, 1.415, 0.105 + ez), "EngineMetal", bev=0.01)
    box("ValveCover", (0.26, 0.67, 0.09), (0, 1.415, 0.195 + ez), "EnginePaint", bev=0.03, seg=3)
    for i in range(5):
        box(f"CoverFin{i}", (0.01, 0.52, 0.014), (-0.08 + i * 0.04, 1.415, 0.243 + ez), "Aluminium", bev=0.003)
    cyl("OilCap", 0.03, 0.025, (0.07, 1.69, 0.245 + ez), segs=16, mat="TrimBlack")
    # Injection pump + lines.
    box("InjPump", (0.09, 0.2, 0.12), (-0.25, 1.68, 0.0 + ez), "Aluminium", bev=0.015)
    for i in range(6):
        y = 1.15 + i * 0.105
        cyl(f"Injector{i}", 0.012, 0.05, (-0.11, y, 0.25 + ez), segs=8, mat="EngineMetal")
        tube(f"InjLine{i}", [(-0.25, 1.62 + i * 0.012, 0.06 + ez), (-0.2, (1.62 + y) / 2, 0.2 + ez),
                             (-0.11, y, 0.27 + ez)], 0.005, "Chrome", nring=5, sub=4)
    # Intake (left) and exhaust (right) manifolds, turbo.
    box("Plenum", (0.1, 0.62, 0.1), (-0.27, 1.40, 0.12 + ez), "Aluminium", bev=0.025)
    for i in range(6):
        y = 1.15 + i * 0.105
        cyl_between(f"Runner{i}", (-0.24, y, 0.12 + ez), (-0.16, y, 0.1 + ez), 0.022, mat="Aluminium", segs=10)
        tube(f"ExhRunner{i}", [(0.16, y, 0.08 + ez), (0.21, y, 0.07 + ez), (0.24, lerp(y, 1.46, 0.3), 0.02 + ez)],
             0.02, "Exhaust", nring=8, sub=3)
    cyl("ExhCollector", 0.032, 0.6, (0.245, 1.4, 0.02 + ez), axis="Y", segs=12, mat="Exhaust")
    cyl("Turbine", 0.07, 0.07, (0.3, 1.5, 0.1 + ez), axis="X", segs=20, mat="Exhaust", bev=0.015)
    cyl("Compressor", 0.075, 0.07, (0.38, 1.5, 0.1 + ez), axis="X", segs=20, mat="Aluminium", bev=0.015)
    # Air filter box (fed by the snorkel through the fender) and intake hoses.
    cyl("AirBox", 0.11, 0.32, (0.46, 1.14, 0.17 + ez), axis="Y", segs=24, mat="TrimBlack", bev=0.02)
    for y in (1.0, 1.28):
        cyl(f"AirClamp{y}", 0.113, 0.015, (0.46, y, 0.17 + ez), axis="Y", segs=24, mat="Chrome")
    tube("IntakeHose", [(0.46, 1.30, 0.17 + ez), (0.45, 1.42, 0.14 + ez), (0.4, 1.5, 0.1 + ez)], 0.045, "Hose",
         nring=12, sub=4)
    tube("ChargePipe", [(0.38, 1.56, 0.14 + ez), (0.3, 1.82, 0.25 + ez), (0.0, 1.85, 0.28 + ez),
                        (-0.24, 1.82, 0.22 + ez), (-0.27, 1.72, 0.13 + ez)], 0.03, "Hose", nring=10, sub=5)
    # Front of the engine: timing cover, pulleys, belt, alternator, fan.
    box("TimingCover", (0.3, 0.04, 0.36), (0, 1.8, -0.06 + ez), "CastDark", bev=0.02)
    for name, p, r in (("Crank", (0, 1.835, -0.18 + ez), 0.085), ("WaterPump", (0, 1.835, 0.04 + ez), 0.06),
                       ("AltPulley", (-0.22, 1.835, 0.03 + ez), 0.03)):
        cyl(name, r, 0.03, p, axis="Y", segs=24, mat="EngineMetal")
    cyl("Alternator", 0.068, 0.13, (-0.22, 1.76, 0.03 + ez), axis="Y", segs=20, mat="Aluminium", bev=0.01)
    belt = [(0.085, -0.18), (0.06, 0.04), (0.0, 0.1), (-0.22, 0.06), (-0.252, 0.03), (-0.22, 0.0), (-0.07, -0.25),
            (0.0, -0.265), (0.07, -0.24)]
    tube("Belt", [(x, 1.835, z + ez) for x, z in belt], 0.007, "Hose", nring=6, sub=3, closed=True)
    cyl("FanClutch", 0.06, 0.05, (0, 1.875, 0.04 + ez), axis="Y", segs=20, mat="Aluminium")
    for i in range(7):
        a = 2 * PI * i / 7
        c = Vector((0.13 * math.cos(a), 1.895, 0.04 + ez + 0.13 * math.sin(a)))
        box(f"FanBlade{i}", (0.15, 0.006, 0.07), tuple(c), "TrimBlack", rot=(0, -a, 0.0), bev=0.0)
    # Radiator, shroud, hoses.
    box("RadCore", (1.0, 0.05, 0.44), (0, 1.99, 0.07), "Radiator")
    box("RadTankTop", (1.04, 0.07, 0.04), (0, 1.99, 0.31), "TrimBlack", bev=0.008)
    box("RadTankBot", (1.04, 0.07, 0.04), (0, 1.99, -0.17), "TrimBlack", bev=0.008)
    cyl("RadCap", 0.026, 0.02, (0.32, 1.99, 0.338), segs=16, mat="Chrome")
    revolve("Shroud", [(0.0, 0.225), (0.08, 0.225), (0.08, 0.238), (0.0, 0.238)], 32, ("TrimBlack",), axis="Y",
            center=(0, 1.87, 0.04 + ez))
    for z, h in ((0.295, 0.03), (-0.155, 0.03)):
        box(f"ShroudBar{z}", (0.62, 0.02, h), (0, 1.955, z), "TrimBlack")
    for s in (1, -1):
        box(f"ShroudSide{s}", (0.07, 0.02, 0.48), (s * 0.275, 1.955, 0.07), "TrimBlack")
    tube("UpperHose", [(0.3, 1.97, 0.27), (0.25, 1.9, 0.29), (0.12, 1.83, 0.24), (0.06, 1.78, 0.2 + ez)], 0.024,
         "Hose", nring=10, sub=5)
    tube("LowerHose", [(-0.35, 1.97, -0.12), (-0.3, 1.9, -0.15), (-0.12, 1.85, -0.1), (-0.04, 1.82, -0.04)], 0.024,
         "Hose", nring=10, sub=5)
    for i, x in enumerate((0.08, 0.13)):
        tube(f"HeaterHose{i}", [(x, 1.07, 0.15 + ez), (x + 0.02, 1.0, 0.2 + ez), (x + 0.05, 0.95, 0.16 + ez)], 0.012,
             "Hose", nring=8, sub=4)
    # Battery, brake booster, master cylinder, reservoirs, fuse box, wiring.
    box("BattTray", (0.27, 0.3, 0.02), (-0.45, 1.65, 0.04), "SteelBlack")
    box("Battery", (0.22, 0.26, 0.2), (-0.45, 1.65, 0.15), "TrimBlack", bev=0.008)
    box("BattLid", (0.222, 0.262, 0.02), (-0.45, 1.65, 0.255), "PlasticWhite", bev=0.004)
    cyl("TermPos", 0.012, 0.025, (-0.39, 1.56, 0.275), segs=10, mat="AccentRed")
    cyl("TermNeg", 0.012, 0.025, (-0.39, 1.74, 0.275), segs=10, mat="TrimBlack")
    box("HoldDown", (0.24, 0.02, 0.015), (-0.45, 1.65, 0.27), "SteelBlack")
    tube("CablePos", [(-0.39, 1.56, 0.29), (-0.34, 1.5, 0.3), (-0.27, 1.45, 0.15), (-0.22, 1.3, -0.15)], 0.009,
         "CableRed", nring=8, sub=5)
    tube("CableNeg", [(-0.39, 1.74, 0.29), (-0.33, 1.78, 0.28), (-0.3, 1.8, 0.1), (-0.17, 1.75, -0.05)], 0.009,
         "Hose", nring=8, sub=5)
    cyl("Booster", 0.12, 0.1, (-0.40, 1.0, 0.2), axis="Y", segs=28, mat="SteelBlack", bev=0.02)
    cyl("MasterCyl", 0.035, 0.15, (-0.40, 1.12, 0.2), axis="Y", segs=14, mat="Aluminium")
    box("BrakeRes", (0.08, 0.07, 0.06), (-0.40, 1.12, 0.26), "PlasticWhite", bev=0.01)
    cyl("BrakeResCap", 0.02, 0.015, (-0.40, 1.12, 0.297), segs=12, mat="DamperGold")
    box("FuseBox", (0.12, 0.2, 0.09), (-0.50, 1.33, 0.13), "TrimBlack", bev=0.015)
    box("Coolant", (0.1, 0.14, 0.15), (0.48, 1.70, 0.17), "PlasticWhite", bev=0.02)
    cyl("CoolantCap", 0.022, 0.02, (0.48, 1.70, 0.255), segs=12, mat="DamperGold")
    tube("Loom", [(-0.2, 1.1, 0.2 + ez), (-0.2, 1.4, 0.21 + ez), (-0.2, 1.72, 0.2 + ez), (-0.32, 1.8, 0.16)], 0.009,
         "TrimBlack", nring=6, sub=5)
    cyl("Dipstick", 0.006, 0.3, (0.19, 1.25, 0.1 + ez), axis=(0.2, 0, 1), segs=6, mat="DamperGold")


def build_bed():
    for s in (1, -1):
        a = math.asin((BED_BOTTOM_Z - WHEEL_Z) / ARCH_R)
        arc = arch_arc(AXLE_R_Y, WHEEL_Z, ARCH_R, BED_BOTTOM_Z, 26)
        outline = ([(TAIL_Y, BED_BOTTOM_Z)] + arc
                   + [(BED_FRONT_Y, BED_BOTTOM_Z), (BED_FRONT_Y, BED_TOP_Z), (TAIL_Y, BED_TOP_Z)])
        side = [0] + [1] * (len(arc) - 1) + [0] * 4
        bed_side = bevel(prism(f"BedSide{s}", outline, along_x(s), BED_IN_X, BODY_HALF_W, ("Paint", "TrimBlack"),
                               side_mats=side), 0.02, 3, 40)
        if s < 0:
            # Recessed fuel-filler pocket behind the FuelDoor flap.
            fy, fz = FUEL_DOOR_C[1], FUEL_DOOR_C[2]
            c = prism("CutFuel", fillet([(fy - 0.062, fz - 0.062), (fy + 0.062, fz - 0.062), (fy + 0.062, fz + 0.062),
                                         (fy - 0.062, fz + 0.062)], 0.015, 3), along_x(-1), 0.865, 0.95, grp="Cutter")
            c.hide_render = True
            cut(bed_side, c)
            box("FuelPocket", (0.004, 0.124, 0.124), (-0.866, fy, fz), "Slot")
            cyl("FillerNeck", 0.032, 0.02, (-0.875, fy, fz), axis="X", segs=20, mat="SteelBlack")
            cyl("FillerCap", 0.03, 0.008, (-0.889, fy, fz), axis="X", segs=20, mat="TrimBlack", bev=0.003)
            box("FillerCapGrip", (0.006, 0.045, 0.01), (-0.895, fy, fz), "TrimBlack", bev=0.002)
        flare(f"FlareR{s}", s, AXLE_R_Y, BED_BOTTOM_Z)
        box(f"RailCap{s}", (0.105, BED_FRONT_Y - TAIL_Y, 0.035), (s * 0.8525, (BED_FRONT_Y + TAIL_Y) / 2, 0.512),
            "TrimBlack", bev=0.008)
        box(f"Tub{s}", (0.25, 1.28, 0.36), (s * 0.72, AXLE_R_Y, 0.08), "BedLiner", bev=0.12, seg=4)
        box(f"Post{s}", (0.15, 0.07, 0.8), (s * 0.775, TAIL_Y + 0.035, 0.1), "Paint", bev=0.01)
        # Tail light cluster.
        box(f"TailHousing{s}", (0.18, 0.025, 0.42), (s * 0.80, TAIL_Y - 0.012, 0.215), "TrimBlack", bev=0.008)
        box(f"TailRed{s}", (0.15, 0.012, 0.18), (s * 0.80, TAIL_Y - 0.028, 0.31), "TailRed", bev=0.006)
        box(f"TailAmber{s}", (0.15, 0.012, 0.085), (s * 0.80, TAIL_Y - 0.028, 0.17), "Amber", bev=0.006)
        box(f"TailRev{s}", (0.15, 0.012, 0.075), (s * 0.80, TAIL_Y - 0.028, 0.07), "ReverseWhite", bev=0.006)
        # Mud flaps.
        box(f"FlapR{s}", (0.38, 0.012, 0.5), (s * 1.05, -2.12, -0.57), "Rubber", bev=0.004)
        box(f"FlapRBar{s}", (0.42, 0.03, 0.03), (s * 1.03, -2.115, -0.315), "SteelBlack", bev=0.004)
        box(f"FlapF{s}", (0.36, 0.012, 0.42), (s * 1.06, 0.82, -0.5), "Rubber", bev=0.004)
    box("BedFront", (2 * BED_IN_X, 0.04, BED_TOP_Z - BED_BOTTOM_Z), (0, BED_FRONT_Y - 0.02, 0.1), "Paint")
    box("FrontCap", (2 * 0.905, 0.07, 0.035), (0, BED_FRONT_Y - 0.035, 0.512), "TrimBlack", bev=0.008)
    box("BedFloor", (2 * BED_IN_X, (BED_FRONT_Y - 0.04) - (TAIL_Y + 0.07), 0.03),
        (0, (BED_FRONT_Y - 0.04 + TAIL_Y + 0.07) / 2, BED_FLOOR_Z - 0.015), "BedLiner")
    for i in range(9):
        x = -0.6 + i * 0.15
        box(f"Rib{i}", (0.035, 1.34, 0.015), (x, -1.5, BED_FLOOR_Z + 0.007), "BedLiner", bev=0.005)
    box("RearSill", (1.4, 0.04, 0.2), (0, TAIL_Y + 0.02, -0.2), "Paint", bev=0.008)
    # Fuel flap: its own node, hinged on its rear edge (vertical), so +80° about Z swings it out.
    fy, fz = FUEL_DOOR_C[1], FUEL_DOOR_C[2]
    box("FuelFlap", (0.008, 0.136, 0.136), (-0.903, fy, fz), "Paint", bev=0.012, seg=3, grp="FuelDoor")
    cyl("FuelFlapHinge", 0.004, 0.1, (-0.905, fy - 0.068, fz), segs=8, mat="Chrome", grp="FuelDoor")
    # Rear bumper, hitch, plate.
    box("RearBumper", (1.86, 0.14, 0.18), (0, -2.31, -0.29), "SteelBlack", bev=0.015)
    box("Receiver", (0.07, 0.12, 0.07), (0, -2.36, -0.4), "SteelBlack", bev=0.006)
    cyl("HitchPin", 0.008, 0.11, (0, -2.39, -0.4), axis="X", segs=8, mat="Chrome")
    box("Plate", (0.3, 0.008, 0.15), (0, -2.384, -0.29), "Plate", bev=0.006)
    for s in (1, -1):
        box(f"StepPad{s}", (0.3, 0.12, 0.012), (s * 0.55, -2.31, -0.195), "TrimBlack", bev=0.003)
    # Exhaust from the turbo down along the right frame rail to behind the rear wheel.
    tube("Exhaust", [(0.3, 1.5, 0.12), (0.3, 1.45, -0.05), (0.32, 1.25, -0.3), (0.3, 1.0, -0.46),
                     (0.28, 0.6, -0.48), (0.28, -0.7, -0.47), (0.32, -1.0, -0.33), (0.32, -1.9, -0.31),
                     (0.4, -2.12, -0.4), (0.45, -2.27, -0.44)], 0.032, "Exhaust", nring=12, sub=5)
    cyl("Muffler", 0.085, 0.5, (0.28, -0.2, -0.475), axis="Y", segs=20, mat="Exhaust", bev=0.02)


def build_tailgate():
    grp = "Tailgate"
    hw = 0.695
    box("Gate", (2 * hw, 0.05, 0.6), (0, TAIL_Y + 0.025, 0.2), "Paint", grp=grp, bev=0.012)
    box("GateInner", (2 * hw - 0.06, 0.006, 0.54), (0, TAIL_Y + 0.052, 0.2), "BedLiner", grp=grp)
    box("GateHandle", (0.2, 0.012, 0.05), (0, TAIL_Y - 0.004, 0.42), "TrimBlack", grp=grp, bev=0.006)
    for z in (0.12, 0.3):
        box(f"GateRib{z}", (2 * hw - 0.1, 0.008, 0.025), (0, TAIL_Y - 0.002, z), "Paint", grp=grp, bev=0.003)
    for s in (1, -1):
        box(f"GateHinge{s}", (0.05, 0.03, 0.03), (s * 0.6, TAIL_Y + 0.01, -0.095), "SteelBlack", grp=grp)
    return grp


def build_front_bumper():
    outline = [(-0.97, 2.16), (0.97, 2.16), (0.97, 2.22), (0.56, 2.38), (-0.56, 2.38), (-0.97, 2.22)]
    bevel(prism("Bumper", outline, along_z, -0.40, -0.13, ("SteelBlack",)), 0.014, 2, 40)
    for x in (-0.5, 0.5):
        box(f"BumperGusset{x}", (0.012, 0.18, 0.1), (x, 2.29, -0.08), "SteelBlack")
    # Winch. The drum and the hook are their own nodes so the game can spin / move them; the rope
    # itself is left to the game (from the WinchAnchor marker at the fairlead to the hook).
    box("WinchPlate", (0.72, 0.18, 0.02), (0, 2.27, -0.12), "SteelBlack")
    cyl("Drum", 0.058, 0.26, WINCH_DRUM, axis="X", segs=24, mat="CastDark", grp="WinchDrum")
    for i in range(7):
        x = -0.11 + i * 0.037
        revolve(f"Wrap{i}", [(x - 0.017, 0.058), (x, 0.066), (x + 0.017, 0.058)], 20, ("CastDark",), closed=False,
                center=WINCH_DRUM, grp="WinchDrum")
    for x in (-0.137, 0.137):
        cyl(f"DrumFlange{x}", 0.08, 0.012, (x, WINCH_DRUM[1], WINCH_DRUM[2]), axis="X", segs=24, mat="SteelBlack",
            grp="WinchDrum")
        for k in range(3):  # bolts on the flanges make the drum's rotation visible
            a = 2 * PI * k / 3
            cyl(f"FlangeBolt{x}{k}", 0.008, 0.02, (x * 1.06, WINCH_DRUM[1] + 0.055 * math.cos(a),
                                                    WINCH_DRUM[2] + 0.055 * math.sin(a)),
                axis="X", segs=6, mat="Chrome", grp="WinchDrum", smooth=0)
    cyl("WinchMotor", 0.062, 0.22, (0.255, 2.27, -0.045), axis="X", segs=24, mat="SteelBlack", bev=0.012)
    cyl("MotorCap", 0.064, 0.02, (0.37, 2.27, -0.045), axis="X", segs=24, mat="Chrome", bev=0.006)
    box("Gearbox", (0.13, 0.15, 0.15), (-0.21, 2.27, -0.045), "SteelBlack", bev=0.02, seg=2)
    box("Solenoid", (0.16, 0.08, 0.06), (0.25, 2.27, 0.045), "TrimBlack", bev=0.01)
    for y in (2.2, 2.34):
        cyl(f"TieBar{y}", 0.011, 0.6, (0.06, y, 0.012), axis="X", segs=8, mat="Chrome")
    box("Fairlead", (0.3, 0.02, 0.13), (0, 2.385, -0.07), "Aluminium", bev=0.01, seg=2)
    box("FairleadSlot", (0.18, 0.022, 0.035), (0, 2.386, -0.07), "TrimBlack", bev=0.01, seg=2)
    tube("Cable", [(0, 2.29, -0.1), (0, 2.36, -0.075), (WINCH_ANCHOR[0], WINCH_ANCHOR[1] - 0.005, WINCH_ANCHOR[2])],
         0.006, "CastDark", nring=6, sub=3)
    hx, hy, hz = WINCH_ANCHOR
    revolve("HookEye", [(0.004 * math.cos(a), 0.016 + 0.004 * math.sin(a)) for a in (2 * PI * i / 6 for i in range(6))],
            16, ("Chrome",), axis="Y", center=(hx, hy + 0.006, hz), grp="WinchHook")
    tube("Hook", [(hx, hy + 0.02, hz - 0.012), (hx, hy + 0.03, hz - 0.05), (hx, hy + 0.05, hz - 0.08),
                  (hx, hy + 0.07, hz - 0.06), (hx, hy + 0.065, hz - 0.04)], 0.009, "AccentRed", nring=8, sub=4,
         grp="WinchHook")
    box("HookLatch", (0.006, 0.04, 0.006), (hx, hy + 0.05, hz - 0.035), "Chrome", rot=(0.5, 0, 0), grp="WinchHook")
    # Shackles (D-rings).
    for x in (-0.42, 0.42):
        box(f"ShackleTab{x}", (0.02, 0.06, 0.08), (x, 2.40, -0.30), "SteelBlack", bev=0.004)
        d = Vector((0, 0.6, -0.8)).normalized()
        base = Vector((x, 2.41, -0.29))
        pts = [base + Vector((u, 0, 0)) + d * v for u, v in
               ((-0.04, 0.0), (-0.042, 0.05), (-0.03, 0.085), (0.0, 0.1), (0.03, 0.085), (0.042, 0.05), (0.04, 0.0))]
        tube(f"Shackle{x}", pts, 0.012, "AccentRed", nring=8, sub=4)
        cyl(f"ShacklePin{x}", 0.014, 0.11, tuple(base), axis="X", segs=10, mat="AccentRed")
    # Grille hoop with a pair of LED pods.
    tube("Hoop", [(-0.48, 2.3, -0.13), (-0.47, 2.31, 0.18), (-0.4, 2.3, 0.3), (0.4, 2.3, 0.3), (0.47, 2.31, 0.18),
                  (0.48, 2.3, -0.13)], 0.028, "SteelBlack", nring=12, sub=6)
    for x in (-0.22, 0.22):
        cyl(f"PodBody{x}", 0.065, 0.07, (x, 2.3, 0.39), axis="Y", segs=20, mat="SteelBlack", bev=0.01)
        cyl(f"PodLens{x}", 0.055, 0.006, (x, 2.337, 0.39), axis="Y", segs=20, mat="LedLens")
        box(f"PodMount{x}", (0.03, 0.03, 0.06), (x, 2.3, 0.33), "SteelBlack")


def build_roof_rack():
    rail = fillet([(-0.7, -0.64), (0.7, -0.64), (0.7, 0.26), (-0.7, 0.26)], 0.08, 4)
    tube("RackRail", [(x, y, 1.29) for x, y in rail], 0.017, "SteelBlack", nring=8, sub=1, closed=True)
    base = fillet([(-0.68, -0.62), (0.68, -0.62), (0.68, 0.24), (-0.68, 0.24)], 0.06, 4)
    tube("RackBase", [(x, y, 1.225) for x, y in base], 0.017, "SteelBlack", nring=8, sub=1, closed=True)
    for y in (0.12, -0.12, -0.36, -0.56):
        tube(f"RackBar{y}", [(-0.68, y, 1.225), (0.68, y, 1.225)], 0.015, "SteelBlack", nring=8, sub=1)
    for x in (-0.69, 0.69):
        for y in (0.2, -0.05, -0.3, -0.58):
            tube(f"RackPost{x}{y}", [(x, y, 1.225), (x * 1.014, y, 1.29)], 0.012, "SteelBlack", nring=6, sub=1)
        for y in (0.2, -0.2, -0.56):
            box(f"RackFoot{x}{y}", (0.05, 0.08, 0.07), (x * 0.97, y, ROOF_Z + 0.03), "SteelBlack", bev=0.008)
    box("LightBar", (1.1, 0.075, 0.085), (0, 0.33, 1.265), "SteelBlack", bev=0.012)
    box("LightBarLens", (1.06, 0.006, 0.058), (0, 0.369, 1.265), "LedLens", bev=0.002)
    for i in range(11):
        box(f"LBDiv{i}", (0.006, 0.008, 0.058), (-0.5 + i * 0.1, 0.372, 1.265), "SteelBlack")


def build_snorkel():
    pts = [(0.86, 1.02, 0.27), (0.95, 0.97, 0.31), (0.956, 0.84, 0.44), (0.93, 0.7, 0.6), (0.885, 0.53, 0.84),
           (0.855, 0.45, 1.0), (0.848, 0.43, 1.14), (0.848, 0.43, 1.24)]
    tube("Snorkel", pts, 0.045, "TrimBlack", nring=14, sub=6)
    box("RamHead", (0.12, 0.2, 0.12), (0.848, 0.46, 1.275), "TrimBlack", bev=0.045, seg=3)
    box("RamGrille", (0.09, 0.01, 0.08), (0.848, 0.562, 1.275), "SteelBlack", bev=0.01)
    for z in (0.72, 1.02):
        x = side_x(z) + 0.02
        box(f"SnorkelBracket{z}", (0.1, 0.025, 0.04), ((x + 0.88) / 2, ws_y(z) - 0.06, z), "SteelBlack")
    cyl("Antenna", 0.004, 0.8, (-0.86, 0.76, 0.9), segs=6, mat="TrimBlack")


def build_spare(template_me):
    """Spare wheel lying flat on the cab roof rack, outer face up: its own node (SpareTyre) so the game can take
    it. At 1.1 m across it does not fit under the bed (rear axle, frame rails) and would fill the bed."""
    me = template_me.copy()
    me.name = "SpareTire"
    me.transform(Matrix.Translation(SPARE_C) @ Matrix.Rotation(-PI / 2, 4, "Y"))
    ob = link(bpy.data.objects.new("Spare", me))
    ob["grp"] = "SpareTyre"
    ob["smooth"] = -1  # already shaded
    sy, sz = SPARE_C[1], SPARE_C[2]
    top = sz + TIRE_W / 2 + 0.012
    for dy in (-0.12, 0.12):  # two ratchet straps from rail to rail, over the tyre
        tube(f"Strap{dy}", [(-0.69, sy + dy, 1.29), (-0.5, sy + dy, top), (0.0, sy + dy, top + 0.004),
                            (0.5, sy + dy, top), (0.69, sy + dy, 1.29)], 0.01, "DamperGold", nring=6, sub=4,
             grp="SpareTyre")
        box(f"Ratchet{dy}", (0.06, 0.04, 0.02), (0.42, sy + dy, top + 0.01), "Chrome", bev=0.004, grp="SpareTyre")


# --------------------------------------------------------------------------------------------
# Studio + renders
# --------------------------------------------------------------------------------------------
def setup_studio():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    try:
        scene.eevee.taa_render_samples = 48
        scene.eevee.use_raytracing = True
    except Exception:
        pass
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1000
    scene.render.film_transparent = False
    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    world = bpy.data.worlds.new("Studio")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.62, 0.64, 0.68, 1)
    bg.inputs[1].default_value = 0.55
    studio = []
    me = bpy.data.meshes.new("Ground")
    me.from_pydata([(-40, -40, GROUND_Z), (40, -40, GROUND_Z), (40, 40, GROUND_Z), (-40, 40, GROUND_Z)], [],
                   [(0, 1, 2, 3)])
    gm = bpy.data.materials.new("GroundMat")
    gb = next(n for n in gm.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    gb.inputs["Base Color"].default_value = (0.5, 0.5, 0.5, 1)
    gb.inputs["Roughness"].default_value = 0.75
    me.materials.append(gm)
    studio.append(link(bpy.data.objects.new("Ground", me)))
    for name, loc, energy, size in (("Key", (6, 5, 7), 2600, 5), ("Fill", (-7, 3, 4), 1000, 7),
                                    ("Rim", (-2, -8, 5), 1800, 5), ("Top", (0, 0, 9), 900, 8)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy = energy
        ld.size = size
        lo = link(bpy.data.objects.new(name, ld))
        lo.location = loc
        lo.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        studio.append(lo)
    return studio


def render_view(name, loc, target, lens=50, ortho=None, res=(1600, 1000)):
    scene = bpy.context.scene
    cd = bpy.data.cameras.new(name)
    cam = link(bpy.data.objects.new(name, cd))
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    cd.lens = lens
    cd.clip_end = 200
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = res
    path = os.path.join(OUT_DIR, "previews", name + ".png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)


VIEWS = {
    "front_34": dict(loc=(4.6, 6.6, 1.5), target=(0, 0.25, 0.05), lens=45),
    "rear_34": dict(loc=(-4.8, -6.4, 1.9), target=(0, -0.3, 0.05), lens=45),
    "side": dict(loc=(12, 0, 0.1), target=(0, 0, 0.1), ortho=5.4),
    "top": dict(loc=(0, 0, 12), target=(0, 0.0001, 0), ortho=5.6, res=(1000, 1200)),
    "front": dict(loc=(0, 12, 0.2), target=(0, 0, 0.2), ortho=3.3, res=(1300, 1000)),
    "wheel_closeup": dict(loc=(2.65, 2.55, -0.1), target=(1.1, 1.5, -0.42), lens=50, res=(1200, 1000)),
    "winch_closeup": dict(loc=(0.75, 3.35, 0.3), target=(0.02, 2.3, -0.07), lens=50, res=(1200, 900)),
    "cab_fps": dict(loc=DRIVER_EYE, target=(DRIVER_X + 0.05, 1.6, 0.36), lens=20, res=(1600, 1000)),
    "dash_closeup": dict(loc=(-0.28, 0.06, 0.7), target=(-0.38, 0.45, 0.55), lens=32, res=(1600, 1000)),
    "fuel_door": dict(loc=(-1.45, -0.62, 0.52), target=(-0.9, -1.06, 0.28), lens=40, res=(1400, 1000)),
    "entry_left": dict(loc=(-2.6, -0.9, 0.55), target=(-0.75, 0.25, 0.0), lens=32, res=(1600, 1000)),
    "cab_door_open": dict(loc=(1.75, -0.35, 0.75), target=(0.0, 0.25, 0.25), lens=35, res=(1600, 1000)),
    "hood_open": dict(loc=(1.9, 4.3, 2.4), target=(0, 1.35, 0.05), lens=40),
}


# --------------------------------------------------------------------------------------------
def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    do_render = "--no-render" not in argv
    views = list(VIEWS)
    if "--views" in argv:
        views = argv[argv.index("--views") + 1].split(",")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_materials()

    # Wheel template (outer face +X), mirrored for the left side.
    build_wheel_parts("WheelTpl")
    tpl = bake_group("WheelTpl", "WheelTpl")
    tpl_me = tpl.data
    bpy.data.objects.remove(tpl, do_unlink=True)

    build_chassis()
    build_front_clip()
    build_cab()
    build_interior()
    build_engine_bay()
    build_bed()
    build_front_bumper()
    build_roof_rack()
    build_snorkel()
    build_spare(tpl_me)
    door_grps = [build_door(1), build_door(-1)]
    build_hood()
    build_tailgate()
    build_axle("Axle_F", AXLE_F_Y, True)
    build_axle("Axle_R", AXLE_R_Y, False)

    nodes = [bake_group("Body", "Body")]
    nodes.append(bake_group("Hood", "Hood", (0, HOOD_HINGE_Y, HOOD_REAR_Z)))
    for g in door_grps:
        s = 1 if g.endswith("R") else -1
        nodes.append(bake_group(g, g, (s * BODY_HALF_W, DOOR_FRONT_Y, 0.0)))
    nodes.append(bake_group("Tailgate", "Tailgate", (0, TAIL_Y + 0.025, -0.1)))
    nodes.append(bake_group("Axle_F", "Axle_F", (0, AXLE_F_Y, WHEEL_Z)))
    nodes.append(bake_group("Axle_R", "Axle_R", (0, AXLE_R_Y, WHEEL_Z)))
    nodes.append(bake_group("WinchDrum", "WinchDrum", WINCH_DRUM))
    nodes.append(bake_group("WinchHook", "WinchHook", WINCH_ANCHOR))
    nodes.append(bake_group("FuelDoor", "FuelDoor", FUEL_DOOR_HINGE))
    nodes.append(bake_group("SpareTyre", "SpareTyre", SPARE_C))
    # Steering wheel and gauge needles: the node's local -Z (Godot) runs into the dash, so turning the
    # wheel / moving a needle is a rotation about local Z.
    sw = bake_group("SteeringWheel", "SteeringWheel", WHEEL_C)
    orient_into(sw, -Vector(WHEEL_AXIS))
    nodes.append(sw)
    for grp, centre in NEEDLES:
        nd = bake_group(grp, grp, centre)
        orient_into(nd, -Vector(GAUGE_N))
        nodes.append(nd)
    for o in [o for o in bpy.data.objects if o.get("grp") == "Cutter"]:
        bpy.data.objects.remove(o, do_unlink=True)

    for name, x, y in (("FL", -TRACK_HALF, AXLE_F_Y), ("FR", TRACK_HALF, AXLE_F_Y),
                       ("RL", -TRACK_HALF, AXLE_R_Y), ("RR", TRACK_HALF, AXLE_R_Y)):
        me = mirrored_copy(tpl_me, "Wheel_" + name) if x < 0 else tpl_me.copy()
        me.name = "Wheel_" + name
        ob = link(bpy.data.objects.new(name, me))
        ob.location = (x, y, WHEEL_Z)
        nodes.append(ob)

    tris = 0
    for o in nodes:
        o.data.calc_loop_triangles()
        t = len(o.data.loop_triangles)
        tris += t
        print(f"node {o.name:10s} tris {t:7d} at {tuple(round(c, 3) for c in o.location)}")
    print("TOTAL TRIS", tris)

    # Marker (empty) nodes: winch rope exit, driver hip point, first-person eye, and the points the
    # get-in / get-out animations use on the driver (left) side. Door markers are children of Door_L.
    door_l = bpy.data.objects["Door_L"]
    for name, p, parent in (("WinchAnchor", WINCH_ANCHOR, None), ("DriverSeat", DRIVER_SEAT, None),
                            ("DriverEye", DRIVER_EYE, None)) + ENTRY_MARKERS + M5_MARKERS:
        e = link(bpy.data.objects.new(name, None))
        e.empty_display_size = 0.05
        if parent:
            e.parent = bpy.data.objects[parent]
            e.location = Vector(p) - e.parent.location
        else:
            e.location = p
        nodes.append(e)
    assert door_l.rotation_euler.z == 0
    # Light markers: each empty's -Z (Godot) points where its light shines (front lights forward, tails back).
    for name, p, back in LIGHT_MARKERS:
        e = link(bpy.data.objects.new(name, None))
        e.empty_display_size = 0.05
        e.location = p
        if back:
            e.rotation_euler = (0, 0, PI)
        nodes.append(e)
    # Cargo volume of the bed: origin at the centre of the bed floor, node scale = box size
    # (Godot: x width wall to wall, y height to the rail tops, z length front wall to tailgate).
    cargo = link(bpy.data.objects.new("CargoArea", None))
    cargo.empty_display_type = "CUBE"
    cargo.location = (0.0, (BED_FRONT_Y - 0.04 + TAIL_Y + 0.07) / 2, BED_FLOOR_Z)
    cargo.scale = (2 * BED_IN_X, (BED_FRONT_Y - 0.04) - (TAIL_Y + 0.07), BED_TOP_Z - BED_FLOOR_Z)
    nodes.append(cargo)

    os.makedirs(os.path.join(OUT_DIR, "previews"), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in nodes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = nodes[0]
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "truck.glb"), export_format="GLB",
                              use_selection=True, export_apply=True, export_yup=True)
    print("exported", os.path.join(OUT_DIR, "truck.glb"))

    if not do_render:
        return
    setup_studio()
    hood = bpy.data.objects["Hood"]
    door_r = bpy.data.objects["Door_R"]
    for v in views:
        if v == "hood_open":
            hood.rotation_euler = (math.radians(72), 0, 0)
        if v == "fuel_door":
            bpy.data.objects["FuelDoor"].rotation_euler = (0, 0, math.radians(FUEL_DOOR_OPEN_DEG))
        if v == "cab_door_open":
            door_r.rotation_euler = (0, 0, math.radians(DOOR_OPEN_DEG))
        if v == "entry_left":
            # Preview only: open the driver door and show the entry markers as small red balls.
            bpy.data.objects["Door_L"].rotation_euler = (0, 0, math.radians(-DOOR_OPEN_DEG))
            bpy.context.view_layer.update()
            for name, _, _ in ENTRY_MARKERS:
                ball = cyl(f"Probe{name}", 0.025, 0.05, bpy.data.objects[name].matrix_world.translation, segs=12,
                           mat="AccentRed", grp="Probe")
                ball.hide_render = False
        render_view(v, **VIEWS[v])
        hood.rotation_euler = (0, 0, 0)
        door_r.rotation_euler = (0, 0, 0)
        bpy.data.objects["Door_L"].rotation_euler = (0, 0, 0)
        bpy.data.objects["FuelDoor"].rotation_euler = (0, 0, 0)
        for o in [o for o in bpy.data.objects if o.get("grp") == "Probe"]:
            bpy.data.objects.remove(o, do_unlink=True)


if __name__ == "__main__":
    main()
