"""Builds the townsfolk: 1880s settlers in the taiga, as nine rigid parts the game swings by hand
(scripts/villager.gd): Torso (body, head, hat; origin at the feet), ArmL and ArmR (the upper arms,
origins at the shoulders) with ArmL2 and ArmR2 (the forearms and hands, origins at the elbows), LegL
and LegR (the thighs, origins at the hips) with LegL2 and LegR2 (the shins and boots, origins at the
knees).

    blender --background --factory-startup --python tools/blender/build_villagers.py [-- --render]

Blender: +X right, -Y forward (Godot +Z is behind: the game turns them to face -Z), +Z up. Colours
are vertex colours. Hips at 0.78 m, shoulders at 1.47, the head's middle at 1.74.

Output: assets/villagers/<variant>.glb, assets/villagers/previews/sheet.png (--render).

  man_cap      a shirt, a waistcoat, braces, wool trousers, boots, a flat cap
  man_hat      a work shirt, a short coat, a felt hat with a brim, a beard
  man_fur      a quilted coat with a belt, a fur hat with flaps, a beard, felt boots
  woman_scarf  a blouse, a long skirt, an apron, a headscarf
  woman_shawl  a dress, a shawl over the shoulders, a long skirt, hair in a bun
  outlaw       a long dark coat, a bandana over the face, a slouch hat
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "villagers")

HIP = 0.78
SHOULDER = 1.47
HEAD = 1.74
SHOULDER_X = 0.27
HIP_X = 0.1

SKIN = [(0.86, 0.67, 0.53), (0.76, 0.57, 0.44), (0.66, 0.49, 0.37)]
HAIR = [(0.22, 0.15, 0.09), (0.42, 0.3, 0.17), (0.12, 0.1, 0.09), (0.55, 0.45, 0.3)]


class Part:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")

    def _paint(self, verts, c):
        for f in {f for v in verts for f in v.link_faces}:
            for loop in f.loops:
                loop[self.col] = (c[0], c[1], c[2], 1.0)

    def tube(self, rings, color, segs=10, cap_top=True, cap_bottom=True, smooth=True):
        """A body of revolution about Z: `rings` is [(z, rx, ry, (cx, cy))...] bottom to top."""
        made = []
        for z, rx, ry, c in rings:
            ring = []
            for s in range(segs):
                a = s / segs * math.tau
                ring.append(self.bm.verts.new((c[0] + math.cos(a) * rx, c[1] + math.sin(a) * ry, z)))
            made.append(ring)
        verts = [v for r in made for v in r]
        for k in range(len(made) - 1):
            for s in range(segs):
                f = self.bm.faces.new([made[k][s], made[k][(s + 1) % segs], made[k + 1][(s + 1) % segs], made[k + 1][s]])
                f.smooth = smooth
        if cap_bottom:
            self.bm.faces.new(list(reversed(made[0])))
        if cap_top:
            self.bm.faces.new(made[-1])
        self._paint(verts, color)
        return verts

    def ball(self, center, radii, color, segs=12, rings=8):
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=rings, radius=0.5)
        verts = res["verts"]
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(Vector(center)) @ Matrix.Diagonal((radii[0] * 2, radii[1] * 2, radii[2] * 2, 1.0)), verts=verts)
        for f in {f for v in verts for f in v.link_faces}:
            f.smooth = True
        self._paint(verts, color)
        return verts

    def box(self, center, size, color, rot=(0, 0, 0)):
        res = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = res["verts"]
        m = Matrix.Translation(Vector(center)) @ Matrix.Rotation(rot[2], 4, "Z") @ Matrix.Rotation(rot[1], 4, "Y") @ Matrix.Rotation(rot[0], 4, "X") @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        bmesh.ops.transform(self.bm, matrix=m, verts=verts)
        self._paint(verts, color)
        return verts

    def to_object(self, origin):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.translate(self.bm, vec=-Vector(origin), verts=self.bm.verts)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(self.name, me)
        ob.location = origin
        bpy.context.scene.collection.objects.link(ob)
        if me.color_attributes.get("Col"):
            me.color_attributes.active_color = me.color_attributes["Col"]
        me.materials.append(_material())
        return ob


def _material():
    mat = bpy.data.materials.get("cloth")
    if mat:
        return mat
    mat = bpy.data.materials.new("cloth")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    return mat


def _shade(c, k):
    return (c[0] * k, c[1] * k, c[2] * k)


# --- the parts -------------------------------------------------------------------------------------

def head(p, skin, hair, beard=None, kind="man"):
    p.ball((0, 0, HEAD), (0.105, 0.115, 0.13), skin)
    p.box((0, -0.11, HEAD - 0.01), (0.028, 0.035, 0.05), _shade(skin, 0.95), rot=(0.3, 0, 0)) # the nose
    for sx in (-1, 1):
        p.ball((sx * 0.105, 0.0, HEAD), (0.02, 0.03, 0.04), _shade(skin, 0.92), segs=6, rings=4)
        p.ball((sx * 0.04, -0.1, HEAD + 0.025), (0.014, 0.008, 0.012), (0.08, 0.06, 0.05), segs=6, rings=4) # eyes
        p.box((sx * 0.04, -0.105, HEAD + 0.05), (0.04, 0.01, 0.012), _shade(hair, 0.9)) # brows
    p.tube([(HEAD - 0.2, 0.05, 0.05, (0, 0)), (HEAD - 0.1, 0.052, 0.052, (0, 0))], skin, segs=8) # the neck
    # hair round the back and sides, under any hat
    p.ball((0, 0.035, HEAD + 0.035), (0.11, 0.105, 0.115), hair)
    if beard:
        p.ball((0, -0.065, HEAD - 0.085), (0.085, 0.06, 0.075), beard)
        p.box((0, -0.11, HEAD - 0.03), (0.09, 0.02, 0.022), beard) # moustache


def body(p, shirt, waist_c, chest_scale=1.0, coat=None, coat_len=0.0):
    rings = [
        (HIP - 0.02, 0.16, 0.11, (0, 0)),
        (HIP + 0.15, 0.15, 0.1, (0, 0)),
        (HIP + 0.38, 0.17 * chest_scale, 0.12, (0, 0.005)),
        (SHOULDER - 0.05, 0.2 * chest_scale, 0.12, (0, 0.01)),
        (SHOULDER + 0.04, 0.12, 0.08, (0, 0.01)),
    ]
    p.tube(rings, shirt)
    p.tube([(HIP + 0.02, 0.165, 0.115, (0, 0)), (HIP + 0.08, 0.165, 0.115, (0, 0))], waist_c) # belt
    p.box((0, -0.118, HIP + 0.05), (0.05, 0.01, 0.045), (0.55, 0.5, 0.35)) # buckle
    if coat:
        crings = [
            (HIP - coat_len, 0.21 + coat_len * 0.15, 0.15 + coat_len * 0.1, (0, 0.01)),
            (HIP + 0.1, 0.18, 0.125, (0, 0)),
            (HIP + 0.38, 0.185 * chest_scale, 0.13, (0, 0.005)),
            (SHOULDER - 0.05, 0.215 * chest_scale, 0.13, (0, 0.01)),
            (SHOULDER + 0.03, 0.13, 0.09, (0, 0.01)),
        ]
        p.tube(crings, coat, cap_bottom=False)
        # (the coat open down the front: the shirt shows in a strip)
        p.box((0, -0.128, HIP + 0.35), (0.06, 0.01, 0.55), shirt)
        for z in (HIP + 0.2, HIP + 0.38, HIP + 0.56):
            p.box((0.045, -0.132, z), (0.018, 0.01, 0.018), (0.2, 0.17, 0.13))


def waistcoat(p, color):
    p.tube([(HIP + 0.05, 0.172, 0.123, (0, 0)), (HIP + 0.4, 0.182, 0.128, (0, 0.003)), (SHOULDER - 0.08, 0.205, 0.128, (0, 0.01))], color, cap_top=False, cap_bottom=False)
    p.box((0, -0.13, HIP + 0.3), (0.05, 0.01, 0.45), (0.85, 0.82, 0.74))
    for z in (HIP + 0.15, HIP + 0.27, HIP + 0.39):
        p.box((0.032, -0.135, z), (0.016, 0.01, 0.016), (0.3, 0.27, 0.2))


def braces(p, color):
    for sx in (-1, 1):
        for side in (-1, 1):
            p.box((sx * 0.09, side * 0.125, HIP + 0.4), (0.03, 0.01, 0.62), color)


def skirt(p, color, apron=None):
    p.tube([(0.12, 0.3, 0.27, (0, 0.01)), (0.5, 0.24, 0.2, (0, 0)), (HIP + 0.1, 0.17, 0.12, (0, 0))], color, cap_top=False)
    if apron:
        p.box((0, -0.19, 0.55), (0.32, 0.015, 0.75), apron, rot=(-0.12, 0, 0))
        p.box((0, -0.125, HIP + 0.08), (0.34, 0.01, 0.04), apron)


def hat(p, kind, color, hair):
    top = HEAD + 0.11
    if kind == "cap":
        p.tube([(top - 0.02, 0.118, 0.125, (0, 0)), (top + 0.04, 0.125, 0.135, (0, -0.01)), (top + 0.065, 0.1, 0.11, (0, -0.02))], color, segs=12)
        p.box((0, -0.15, top - 0.005), (0.19, 0.08, 0.015), _shade(color, 0.8), rot=(-0.2, 0, 0))
    elif kind == "hat":
        p.tube([(top - 0.03, 0.125, 0.13, (0, 0)), (top + 0.12, 0.1, 0.105, (0, 0)), (top + 0.13, 0.075, 0.08, (0, 0))], color, segs=12)
        p.tube([(top - 0.035, 0.24, 0.24, (0, 0)), (top - 0.015, 0.24, 0.24, (0, 0))], _shade(color, 0.9), segs=16)
        p.tube([(top - 0.015, 0.128, 0.133, (0, 0)), (top + 0.01, 0.128, 0.133, (0, 0))], (0.15, 0.12, 0.1), segs=12)
    elif kind == "fur":
        fur = (0.4, 0.3, 0.2)
        p.tube([(top - 0.06, 0.135, 0.14, (0, 0)), (top + 0.1, 0.14, 0.145, (0, 0)), (top + 0.13, 0.11, 0.12, (0, 0))], fur, segs=12)
        for sx in (-1, 1):
            p.box((sx * 0.125, 0.0, HEAD - 0.01), (0.04, 0.12, 0.15), fur)
        p.box((0, -0.125, top + 0.03), (0.24, 0.04, 0.1), fur)
    elif kind == "slouch":
        p.tube([(top - 0.03, 0.125, 0.13, (0, 0)), (top + 0.09, 0.11, 0.11, (0, 0.01)), (top + 0.1, 0.08, 0.08, (0, 0.01))], color, segs=12)
        brim = p.tube([(top - 0.04, 0.27, 0.27, (0, 0)), (top - 0.02, 0.27, 0.27, (0, 0))], _shade(color, 0.9), segs=16)
        for v in brim:
            v.co.z -= 0.05 * max(0.0, -v.co.y / 0.27) # (the brim pulled down at the front)
    elif kind == "scarf":
        p.ball((0, 0.045, HEAD + 0.035), (0.122, 0.11, 0.13), color)
        p.tube([(HEAD - 0.12, 0.09, 0.09, (0, 0.02)), (HEAD - 0.06, 0.1, 0.1, (0, 0.01))], color, segs=10)
        p.box((0, 0.13, HEAD - 0.12), (0.07, 0.05, 0.12), color, rot=(0.3, 0, 0))
    elif kind == "bun":
        p.ball((0, 0.1, HEAD + 0.06), (0.06, 0.05, 0.055), hair)


ELBOW = SHOULDER - 0.31
KNEE = 0.43


def arm(name, side, sleeve, skin, cuff=None, length=0.62, coat=None):
    """An arm in two: the upper arm (origin at the shoulder) and the forearm with the hand (origin at
    the elbow, `name` + "2"), so the elbow bends."""
    sx = side * SHOULDER_X
    top = SHOULDER
    c = coat or sleeve
    p = Part(name)
    p.tube([(ELBOW - 0.03, 0.05, 0.055, (sx, 0)), (top - 0.15, 0.055, 0.06, (sx, 0)), (top - 0.02, 0.06, 0.066, (sx, 0))], c, segs=8)
    p.ball((sx, 0, top - 0.01), (0.07, 0.075, 0.07), c, segs=8, rings=6)
    p.ball((sx, 0, ELBOW), (0.052, 0.056, 0.05), c, segs=8, rings=5) # (the elbow, round so the bend's clean)
    p.to_object((sx, 0, top))
    q = Part(name + "2")
    wrist = top - length + 0.08
    q.tube([(wrist, 0.043, 0.048, (sx, 0)), (ELBOW - 0.12, 0.048, 0.053, (sx, 0)), (ELBOW + 0.02, 0.05, 0.054, (sx, 0))], c, segs=8)
    if cuff:
        q.tube([(wrist, 0.05, 0.055, (sx, 0)), (wrist + 0.05, 0.05, 0.055, (sx, 0))], cuff, segs=8)
    q.ball((sx, -0.01, top - length + 0.03), (0.04, 0.045, 0.06), skin, segs=8, rings=6) # the hand
    q.box((sx + side * -0.03, -0.035, top - length + 0.05), (0.025, 0.03, 0.05), skin) # the thumb
    return q.to_object((sx, 0, ELBOW))


def leg(name, side, trouser, boot, skirt_long=False):
    """A leg in two: the thigh (origin at the hip) and the shin with the boot (origin at the knee,
    `name` + "2"), so the knee bends."""
    sx = side * HIP_X
    p = Part(name)
    cloth = (0.25, 0.2, 0.17) if skirt_long else trouser
    p.tube([(KNEE - 0.03, 0.058, 0.062, (sx, 0)), (0.62, 0.068, 0.072, (sx, 0)), (HIP, 0.075, 0.08, (sx, 0))], cloth, segs=8)
    p.ball((sx, 0, KNEE), (0.06, 0.064, 0.055), cloth, segs=8, rings=5)
    p.to_object((sx, 0, HIP))
    q = Part(name + "2")
    q.tube([(0.2, 0.052, 0.057, (sx, 0)), (KNEE + 0.02, 0.058, 0.062, (sx, 0))], cloth, segs=8)
    # the boot: a shaft and a foot pointing forward
    q.tube([(0.02, 0.058, 0.065, (sx, -0.01)), (0.24, 0.058, 0.064, (sx, 0))], boot, segs=8)
    q.box((sx, -0.07, 0.04), (0.1, 0.2, 0.08), boot)
    q.box((sx, -0.07, 0.005), (0.105, 0.21, 0.015), _shade(boot, 0.6))
    return q.to_object((sx, 0, KNEE))


# --- the folk --------------------------------------------------------------------------------------

def clear():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)


def export(variant):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, variant + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False, export_apply=True, export_yup=True)
    print("wrote", path)


def build(variant, rng):
    clear()
    skin = rng.choice(SKIN)
    hair = rng.choice(HAIR)
    t = Part("Torso")
    if variant == "man_cap":
        shirt, vest, trous = (0.78, 0.74, 0.66), (0.28, 0.25, 0.22), (0.3, 0.28, 0.25)
        body(t, shirt, (0.22, 0.16, 0.1))
        waistcoat(t, vest)
        braces(t, (0.35, 0.22, 0.14))
        head(t, skin, hair)
        hat(t, "cap", (0.32, 0.3, 0.28), hair)
        arms = (shirt, None, (0.85, 0.82, 0.76))
        legs = (trous, (0.22, 0.15, 0.1), False)
    elif variant == "man_hat":
        shirt, coat, trous = (0.55, 0.22, 0.17), (0.38, 0.3, 0.22), (0.25, 0.25, 0.27)
        body(t, shirt, (0.18, 0.13, 0.09), coat=coat, coat_len=0.12)
        head(t, skin, hair, beard=_shade(hair, 1.1))
        hat(t, "hat", (0.24, 0.2, 0.16), hair)
        arms = (shirt, coat, None)
        legs = (trous, (0.2, 0.14, 0.09), False)
    elif variant == "man_fur":
        coat = (0.3, 0.33, 0.27)
        body(t, (0.5, 0.45, 0.38), (0.4, 0.15, 0.12), coat=coat, coat_len=0.28, chest_scale=1.08)
        t.tube([(HIP + 0.02, 0.2, 0.15, (0, 0)), (HIP + 0.09, 0.2, 0.15, (0, 0))], (0.45, 0.17, 0.13)) # a sash
        head(t, skin, hair, beard=_shade(hair, 1.2))
        hat(t, "fur", coat, hair)
        arms = (coat, coat, None)
        legs = ((0.28, 0.27, 0.25), (0.45, 0.42, 0.37), False)
    elif variant == "woman_scarf":
        blouse, sk = (0.82, 0.78, 0.7), (0.32, 0.2, 0.22)
        body(t, blouse, sk, chest_scale=0.95)
        skirt(t, sk, apron=(0.78, 0.74, 0.62))
        head(t, skin, hair, kind="woman")
        hat(t, "scarf", (0.6, 0.18, 0.14), hair)
        arms = (blouse, None, None)
        legs = (sk, (0.2, 0.14, 0.09), True)
    elif variant == "woman_shawl":
        dress = (0.25, 0.3, 0.38)
        body(t, dress, dress, chest_scale=0.95)
        skirt(t, dress)
        t.tube([(SHOULDER - 0.25, 0.2, 0.135, (0, 0.01)), (SHOULDER - 0.03, 0.215, 0.135, (0, 0.01)), (SHOULDER + 0.05, 0.12, 0.09, (0, 0.01))], (0.5, 0.35, 0.22), cap_bottom=False)
        head(t, skin, hair, kind="woman")
        hat(t, "bun", None, hair)
        arms = (dress, None, None)
        legs = (dress, (0.18, 0.12, 0.08), True)
    else: # outlaw
        coat = (0.13, 0.11, 0.1)
        body(t, (0.3, 0.27, 0.24), (0.1, 0.08, 0.07), coat=coat, coat_len=0.55)
        head(t, skin, hair, beard=_shade(hair, 0.9))
        t.tube([(HEAD - 0.115, 0.108, 0.118, (0, -0.005)), (HEAD - 0.025, 0.11, 0.12, (0, -0.005))], (0.45, 0.12, 0.1), segs=12) # the bandana over the face
        hat(t, "slouch", (0.12, 0.1, 0.09), hair)
        arms = (coat, coat, None)
        legs = ((0.18, 0.16, 0.15), (0.12, 0.09, 0.07), False)
    t.to_object((0, 0, 0))
    sleeve, coat_c, cuff = arms
    for name, side in (("ArmL", -1), ("ArmR", 1)):
        arm(name, side, sleeve, skin, cuff=cuff, coat=coat_c)
    trous, boot, long = legs
    for name, side in (("LegL", -1), ("LegR", 1)):
        leg(name, side, trous, boot, skirt_long=long)
    export(variant)


VARIANTS = ["man_cap", "man_hat", "man_fur", "woman_scarf", "woman_shawl", "outlaw"]


def render_sheet():
    scene = bpy.context.scene
    clear()
    xs = []
    for i, v in enumerate(VARIANTS):
        bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, v + ".glb"))
        for ob in bpy.context.selected_objects:
            ob.location.x += i * 0.8
        xs.append(i * 0.8)
    for mat in bpy.data.materials:
        mat.use_nodes = True
    cam_d = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_d)
    scene.collection.objects.link(cam)
    mid = (len(VARIANTS) - 1) * 0.4
    cam.location = (mid + 1.2, -7.0, 1.6)
    cam.rotation_euler = (Vector((mid, 0, 0.95)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam_d.lens = 38
    scene.camera = cam
    sun_d = bpy.data.lights.new("sun", "SUN")
    sun_d.energy = 4.0
    sun = bpy.data.objects.new("sun", sun_d)
    sun.rotation_euler = (math.radians(55), 0, math.radians(-30))
    scene.collection.objects.link(sun)
    world = scene.world or bpy.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.6, 0.65, 0.7, 1)
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 700
    os.makedirs(os.path.join(OUT, "previews"), exist_ok=True)
    scene.render.filepath = os.path.join(OUT, "previews", "sheet.png")
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for i, v in enumerate(VARIANTS):
        build(v, random.Random(i * 7 + 3))
    if "--render" in argv:
        render_sheet()


main()
