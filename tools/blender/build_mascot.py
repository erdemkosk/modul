"""Budak Usta, who drives: a stocky bearded woodsman, seated, his hands on the wheel.

    blender --background --factory-startup --python tools/blender/build_mascot.py

Output: assets/mascot/budak.glb. Blender: +X his left... no: +X right as seen from behind him, +Y
forward of the machine; he faces -Y here (Godot +Z), and the machine turns him round to its front.
His origin is where he sits (the bench's top), Z up. About 0.95 m standing, 0.6 m seated, four heads
tall: a dwarf's build, which is what a 1 m cab on a cart of half-metre cells fits.

The nodes the game moves (scripts/mascot.gd, pose()):
  Head            the head, turning about the neck (its origin)
    EyeL/EyeR     an eye: White, Iris (looks about), Lid (comes down over it)
    BrowL/BrowR   bushy brows (up, down, tilted)
    CheekL/R      ruddy cheeks (puffed, raised by a smile)
    StacheL/R     the moustache's two halves (ends up in a smile, down in a frown)
    Mouth         the dark of the mouth in the beard (opens, rounds)
    Jaw           the beard below the mouth and the lower teeth, dropping as the mouth opens
"""

import math
import os

import bpy
import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "mascot", "budak.glb")

NECK = Vector((0.0, -0.005, 0.40))
HEAD_C = Vector((0.0, -0.01, 0.475))
SHOULDER = 0.155
HAND = Vector((0.13, -0.235, 0.285)) # (on the wheel's rim, its upper sides: the wood cab's wheel)

MATS = {
    "Skin": ((0.82, 0.56, 0.44), 0.6, 0.0),
    "Ruddy": ((0.84, 0.47, 0.4), 0.55, 0.0),
    "Hair": ((0.3, 0.15, 0.07), 0.9, 0.0),
    "HairGrey": ((0.42, 0.36, 0.3), 0.9, 0.0),
    "Hood": ((0.2, 0.28, 0.14), 0.95, 0.0),
    "Tunic": ((0.45, 0.2, 0.12), 0.95, 0.0),
    "Shirt": ((0.78, 0.72, 0.6), 0.95, 0.0),
    "Breeches": ((0.3, 0.26, 0.21), 0.95, 0.0),
    "Leather": ((0.36, 0.22, 0.12), 0.7, 0.0),
    "LeatherDark": ((0.2, 0.13, 0.08), 0.75, 0.0),
    "Iron": ((0.32, 0.32, 0.33), 0.45, 0.8),
    "Wood": ((0.66, 0.5, 0.32), 0.9, 0.0),
    "EyeWhite": ((0.93, 0.9, 0.85), 0.35, 0.0),
    "Iris": ((0.2, 0.12, 0.06), 0.25, 0.0),
    "MouthDark": ((0.2, 0.06, 0.05), 0.8, 0.0),
    "Teeth": ((0.9, 0.86, 0.76), 0.4, 0.0),
}


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for name, (c, rough, metal) in MATS.items():
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*c, 1.0)
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal


def link(o, parent=None):
    bpy.context.scene.collection.objects.link(o)
    if parent is not None:
        o.parent = parent
    return o


def empty(name, at, parent=None):
    e = link(bpy.data.objects.new(name, None), parent)
    e.location = Vector(at) - (parent.matrix_world.translation if parent else Vector())
    bpy.context.view_layer.update() # (its place in the world, for what's put under it next)
    return e


def smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True


def _place(o, name, at, parent, mat):
    o.name = name
    o.data.name = name
    if parent is not None:
        o.parent = parent
        o.location = Vector(at) - parent.matrix_world.translation
    else:
        o.location = at
    o.data.materials.append(bpy.data.materials[mat])
    smooth(o)
    return o


def ball(name, r, at, mat, scale=(1, 1, 1), parent=None, segs=24, rot=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=max(8, segs // 2), radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new(name, me))
    o.rotation_euler = rot
    return _place(o, name, at, parent, mat)


def tube_between(name, a, b, r0, r1, mat, parent=None, segs=12):
    a, b = Vector(a), Vector(b)
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r0, radius2=r1, depth=(b - a).length)
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new(name, me))
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference((b - a).normalized())
    return _place(o, name, (a + b) * 0.5, parent, mat)


def box(name, size, at, mat, parent=None, rot=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new(name, me))
    o.rotation_euler = rot
    o = _place(o, name, at, parent, mat)
    for p in o.data.polygons:
        p.use_smooth = False
    bev = o.modifiers.new("Bevel", "BEVEL")
    bev.width = min(size) * 0.2
    bev.segments = 2
    return o


def skin(name, pts, edges, radii, mat, parent=None, level=2, root=0):
    """A limb or a body grown round a chain of points (a skin modifier), smoothed."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([Vector(p) for p in pts], edges, [])
    o = link(bpy.data.objects.new(name, me))
    o.modifiers.new("Skin", "SKIN")
    sv = me.skin_vertices[0].data
    for i, r in enumerate(radii):
        sv[i].radius = r if isinstance(r, tuple) else (r, r)
    sv[root].use_root = True
    sub = o.modifiers.new("Sub", "SUBSURF")
    sub.levels = level
    sub.render_levels = level
    o.data.materials.append(bpy.data.materials[mat])
    if parent is not None:
        o.parent = parent
        o.location = -parent.matrix_world.translation
    smooth(o)
    return o


def shaggy(o, strength=0.008, size=0.03, seed=1):
    """Hair: clumps pushed in and out over it."""
    tex = bpy.data.textures.new(o.name + "Clumps", "CLOUDS")
    tex.noise_scale = size
    tex.noise_depth = 2
    d = o.modifiers.new("Shag", "DISPLACE")
    d.texture = tex
    d.strength = strength
    d.mid_level = 0.5
    d.texture_coords = "GLOBAL"
    bpy.context.view_layer.update()
    return o


def build():
    root = link(bpy.data.objects.new("Budak", None))

    # --- the body: a barrel of a man in a wool tunic, a belt, breeches, boots --------------------------
    skin("Tunic", [(0, 0.0, 0.03), (0, -0.005, 0.15), (0, 0.0, 0.27), (0, 0.01, 0.35)],
         [(0, 1), (1, 2), (2, 3)], [(0.15, 0.13), (0.175, 0.15), (0.17, 0.125), (0.13, 0.1)], "Tunic", root)
    # the tunic's skirt over the thighs
    skin("Skirt", [(0, -0.02, 0.06), (0, -0.09, 0.02)], [(0, 1)], [(0.16, 0.12), (0.15, 0.1)], "Tunic", root)
    bpy.ops.mesh.primitive_torus_add(major_radius=0.17, minor_radius=0.018, location=(0, -0.005, 0.12))
    belt = bpy.context.active_object
    belt.scale = (1.0, 0.87, 1.0)
    _place(belt, "Belt", (0, -0.005, 0.12), root, "Leather")
    box("Buckle", (0.05, 0.015, 0.04), (0, -0.155, 0.12), "Iron", root)
    box("Pouch", (0.06, 0.035, 0.07), (0.13, -0.08, 0.09), "LeatherDark", root, rot=(0, 0, 0.6))
    for s in (-1, 1):
        x = s * 0.085
        skin("Leg" + ("L" if s < 0 else "R"), [(x, 0.0, 0.05), (s * 0.1, -0.24, 0.06), (s * 0.105, -0.27, -0.13)],
             [(0, 1), (1, 2)], [0.075, 0.06, 0.05], "Breeches", root)
        skin("Boot" + ("L" if s < 0 else "R"),
             [(s * 0.105, -0.27, -0.09), (s * 0.105, -0.275, -0.2), (s * 0.108, -0.32, -0.225), (s * 0.11, -0.37, -0.225)],
             [(0, 1), (1, 2), (2, 3)], [0.058, 0.056, (0.055, 0.04), (0.045, 0.035)], "LeatherDark", root)
        # the arms: a linen shirt's sleeves pushed up, leather bracers, gloved hands on the wheel
        sh = Vector((s * SHOULDER, 0.0, 0.335))
        el = Vector((s * 0.2, -0.11, 0.215))
        wr = Vector((s * HAND.x, HAND.y + 0.05, HAND.z - 0.02))
        skin("Arm" + ("L" if s < 0 else "R"), [sh, el, wr], [(0, 1), (1, 2)], [0.06, 0.047, 0.04], "Shirt", root)
        skin("Shoulder" + ("L" if s < 0 else "R"), [sh + Vector((0, 0, 0.0)), sh + Vector((s * 0.03, 0, -0.04))],
             [(0, 1)], [0.068, 0.06], "Tunic", root)
        tube_between("Bracer" + ("L" if s < 0 else "R"), el.lerp(wr, 0.35), el.lerp(wr, 0.92), 0.05, 0.044, "Leather", root)
        ball("Hand" + ("L" if s < 0 else "R"), 0.038, Vector((s * HAND.x, HAND.y, HAND.z)), "Leather", (1.0, 1.15, 0.85), root)
        ball("Thumb" + ("L" if s < 0 else "R"), 0.016, Vector((s * (HAND.x - 0.03), HAND.y - 0.02, HAND.z + 0.025)), "Leather",
             (1.0, 1.6, 1.0), root)
    # the felling axe across his back
    tube_between("AxeHaft", (0.14, 0.12, 0.05), (-0.1, 0.135, 0.5), 0.014, 0.012, "Wood", root, segs=8)
    box("AxeHead", (0.03, 0.02, 0.12), (-0.11, 0.14, 0.49), "Iron", root, rot=(0.0, -0.47, 0.0))
    box("AxeStrap", (0.36, 0.02, 0.03), (0.0, 0.115, 0.27), "Leather", root, rot=(0.0, 0.5, 0.0))

    # --- the head: under a hood, a big nose, deep eyes under bushy brows, a great beard -----------------
    head = empty("Head", NECK, root)
    ball("Skull", 0.093, HEAD_C, "Skin", (1.0, 0.98, 1.1), head)
    ball("Nose", 0.03, HEAD_C + Vector((0, -0.098, -0.012)), "Ruddy", (0.85, 1.0, 1.1), head)
    tube_between("NoseBridge", HEAD_C + Vector((0, -0.085, 0.022)), HEAD_C + Vector((0, -0.1, -0.004)), 0.014, 0.022, "Skin", head)
    ball("BrowRidge", 0.07, HEAD_C + Vector((0, -0.05, 0.03)), "Skin", (1.15, 0.6, 0.3), head)
    for s, n in ((-1, "L"), (1, "R")):
        eye = empty("Eye" + n, HEAD_C + Vector((s * 0.036, -0.077, 0.01)), head)
        ball("White" + n, 0.017, eye.matrix_world.translation, "EyeWhite", (1.0, 0.8, 0.9), eye)
        ball("Iris" + n, 0.0095, eye.matrix_world.translation + Vector((0, -0.012, 0)), "Iris", (1.0, 0.6, 1.0), eye)
        ball("Lid" + n, 0.0195, eye.matrix_world.translation + Vector((0, 0.001, 0)), "Skin", (1.05, 0.85, 1.0), eye)
        brow = ball("Brow" + n, 0.024, HEAD_C + Vector((s * 0.039, -0.086, 0.035)), "HairGrey", (1.35, 0.55, 0.5), head)
        shaggy(brow, 0.006, 0.012, 3)
        ball("Cheek" + n, 0.03, HEAD_C + Vector((s * 0.052, -0.072, -0.022)), "Ruddy", (1.0, 0.8, 0.85), head)
        ball("Ear" + n, 0.022, HEAD_C + Vector((s * 0.092, -0.0, 0.0)), "Skin", (0.5, 0.9, 1.25), head)
        st = ball("Stache" + n, 0.02, HEAD_C + Vector((s * 0.028, -0.104, -0.046)), "Hair", (1.6, 0.7, 0.6), head,
                  rot=(0, s * 0.35, 0))
        shaggy(st, 0.004, 0.01, 4)
    # the beard: over the cheeks and jaw, the upper part fixed, the lower on the jaw
    upper = ball("BeardUpper", 0.1, HEAD_C + Vector((0, -0.045, -0.05)), "Hair", (1.02, 0.72, 0.62), head, segs=32)
    shaggy(upper, 0.012, 0.025, 5)
    ball("Mouth", 0.017, HEAD_C + Vector((0, -0.106, -0.062)), "MouthDark", (1.5, 0.5, 0.7), head)
    ball("TeethTop", 0.012, HEAD_C + Vector((0, -0.107, -0.056)), "Teeth", (1.6, 0.5, 0.45), head)
    jaw = empty("Jaw", HEAD_C + Vector((0, -0.02, -0.04)), head)
    lower = ball("Beard", 0.1, HEAD_C + Vector((0, -0.06, -0.135)), "Hair", (1.0, 0.68, 1.15), jaw, segs=32)
    shaggy(lower, 0.014, 0.03, 6)
    tip = ball("BeardTip", 0.05, HEAD_C + Vector((0, -0.095, -0.235)), "Hair", (1.0, 0.7, 1.0), jaw)
    shaggy(tip, 0.01, 0.02, 7)
    ball("LowerLip", 0.014, HEAD_C + Vector((0, -0.105, -0.074)), "Ruddy", (1.6, 0.55, 0.55), jaw)
    # the hood: a green wool chaperon, open round the face, its capelet on the shoulders, a tail behind
    hood = ball("Hood", 0.116, HEAD_C + Vector((0, 0.008, 0.012)), "Hood", (1.04, 1.04, 1.1), head, segs=36)
    cut = ball("HoodCut", 0.08, HEAD_C + Vector((0, -0.12, -0.03)), "Hood", (0.95, 1.0, 1.15), None)
    cut.hide_render = True
    bm = hood.modifiers.new("Face", "BOOLEAN")
    bm.object = cut
    bm.operation = "DIFFERENCE"
    bm.solver = "EXACT"
    so = hood.modifiers.new("Thick", "SOLIDIFY")
    so.thickness = 0.012
    so.offset = -1.0
    tube_between("HoodRim", HEAD_C + Vector((0, -0.07, 0.083)), HEAD_C + Vector((0, -0.083, 0.07)), 0.01, 0.01, "Hood", head)
    bpy.ops.mesh.primitive_cone_add(vertices=32, radius1=0.2, radius2=0.11, depth=0.09, location=(0, 0, 0))
    cape = bpy.context.active_object
    cape.scale = (1.0, 0.88, 1.0)
    _place(cape, "Capelet", (0, 0.01, 0.375), root, "Hood")
    sc = cape.modifiers.new("Sub", "SUBSURF")
    sc.levels = 1
    skin("HoodTail", [HEAD_C + Vector((0, 0.1, 0.06)), HEAD_C + Vector((0, 0.15, -0.05)), HEAD_C + Vector((0.02, 0.17, -0.17))],
         [(0, 1), (1, 2)], [0.035, 0.024, 0.014], "Hood", head)
    return root, cut


def export(root, cut):
    nodes = []

    def walk(o):
        nodes.append(o)
        for c in o.children:
            walk(c)
    walk(root)
    bpy.ops.object.select_all(action="DESELECT")
    for o in nodes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = root
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    tris = 0
    for o in nodes:
        if o.type == "MESH":
            ev = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
            m = ev.to_mesh()
            m.calc_loop_triangles()
            tris += len(m.loop_triangles)
            ev.to_mesh_clear()
    print("exported", OUT, "nodes", len(nodes), "tris", tris)


if __name__ == "__main__":
    clear()
    r, c = build()
    export(r, c)
