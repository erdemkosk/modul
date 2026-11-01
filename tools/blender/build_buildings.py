"""Builds the timber town's buildings, each one a GLB of separate pieces the game can burn and bring
down one by one (scripts/building.gd):

    blender --background --factory-startup --python tools/blender/build_buildings.py [-- --render] [-- --only=ev,ambar]

Every piece is its own object, its origin at the middle of its bounds, named "<stuff>-<n>" or
"<stuff>-<tag>-<n>": the stuff (scripts/building_defs.gd STUFF: log, plank, dark, stone, shingle,
window, wood, thatch...) decides how it burns and breaks; a tag marks a piece the game looks for
("plinth", "chimneytop"). Colours are vertex colours (the game multiplies them into the stuff's own).

Blender: +X right, -Y the front (the door; Godot +Z), +Z up. The plinth's top is at 0.35 m and the
floor at 0.47; the ground is at 0 (the plinth goes 3.5 m down to take up a slope).

Output: assets/buildings/<kind>.glb, assets/buildings/previews/<kind>.png (--render).

  ev         a log cabin: saddle-notched log walls, log gables, purlins, a shingled roof, a fieldstone
             chimney, framed windows with shutters, a plank door, a porch, a woodpile
  ambar      the store: a big log building, wide double doors, a loading platform, crates, barrels, sacks
  kisla      the watch house: a log house with a rifle rack, a bell on a post, a bench
  kule       the lookout: a timber tower on a stone base, braced, a ladder, a railed platform, a roof
  fener      a lamp post: a squared post, an iron arm, a glazed lantern
  kuyu       a well: a fieldstone ring, a windlass, a little shingled roof, a bucket
  oduncu     the felling camp's yard: a sawhorse with a log and a frame saw, a deck of raw logs,
             sawdust, a lean-to with a tool rack and a grindstone
  tasci      the stone yard: a dressing bench with mallet and chisel, a tripod derrick lifting a
             block, rough blocks heaped, dressed ones stacked, rubble
  toplayici  the gatherers' hut: drying racks hung with berries, a sorting table, baskets
  ormanci    the forester's nursery: raised beds of seedlings, a water barrel, a lean-to
  arabaci    the cart shed (a work shed with a handcart and spare wheels); ahir, the barn
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
OUT = os.path.join(ROOT, "assets", "buildings")

FLOOR = 0.47
PLINTH_TOP = 0.35

# --- colours --------------------------------------------------------------------------------------

def jit(c, amt=0.06, rng=random):
    k = 1.0 + rng.uniform(-amt, amt)
    return (min(c[0] * k, 1), min(c[1] * k, 1), min(c[2] * k, 1))

BARK = (0.42, 0.31, 0.21)
END_GRAIN = (0.78, 0.63, 0.43)
PLANK = (0.62, 0.48, 0.32)
DARK = (0.33, 0.24, 0.16)
STONE = (0.55, 0.54, 0.5)
SHINGLE = (0.47, 0.38, 0.29)
IRON = (0.22, 0.22, 0.23)
GLASS = (0.35, 0.42, 0.45)
SAWDUST_C = (0.86, 0.74, 0.52)
CHINK = (0.72, 0.68, 0.58)
MOSS = (0.3, 0.38, 0.16)
BONE = (0.82, 0.78, 0.68)
# painted trim and shutters, one pair to a building
PAINTS = [((0.88, 0.86, 0.8), (0.22, 0.38, 0.55)), ((0.85, 0.82, 0.72), (0.25, 0.42, 0.3)), ((0.3, 0.45, 0.6), (0.8, 0.65, 0.3)),
          ((0.9, 0.88, 0.82), (0.55, 0.2, 0.15)), ((0.55, 0.7, 0.75), (0.86, 0.84, 0.78))]


# --- one piece at a time -------------------------------------------------------------------------

class Piece:
    """A bmesh being filled, then made into an object called `name`."""

    count = {}

    def __init__(self, stuff, tag=""):
        self.stuff = stuff
        self.tag = tag
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")

    def _paint(self, faces, color, end_color=None, axis=None):
        for f in faces:
            c = color
            if end_color is not None and axis is not None and abs(f.normal.dot(axis)) > 0.8:
                c = end_color
            for loop in f.loops:
                loop[self.col] = (c[0], c[1], c[2], 1.0)

    def obox(self, center, ax, ay, az, size, color, smooth=False):
        """A box along three axes (unit vectors), `size` its full extents along them."""
        c = Vector(center)
        ax, ay, az = Vector(ax).normalized(), Vector(ay).normalized(), Vector(az).normalized()
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        vs = []
        for sx, sy, sz in [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]:
            vs.append(self.bm.verts.new(c + ax * hx * sx + ay * hy * sy + az * hz * sz))
        idx = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        faces = [self.bm.faces.new([vs[i] for i in q]) for q in idx]
        for f in faces:
            f.normal_update()
            f.smooth = smooth
        self._paint(faces, color)
        return faces

    def box(self, center, size, color, rot_z=0.0):
        a = Vector((math.cos(rot_z), math.sin(rot_z), 0))
        b = Vector((-math.sin(rot_z), math.cos(rot_z), 0))
        return self.obox(center, a, b, (0, 0, 1), size, color)

    def _face_color(self, f, c):
        for loop in f.loops:
            loop[self.col] = (min(c[0], 1.0), min(c[1], 1.0), min(c[2], 1.0), 1.0)

    def log(self, a, b, r, color=BARK, end=END_GRAIN, segs=12, jitter=0.05, rng=random, taper=0.06, moss=0.0, bow=0.012):
        """A round log from `a` to `b`: its bark furrowed and knotted, a little bowed, grimed low down
        and mossed on top near the ground (`moss`), its sawn ends showing sapwood and heartwood."""
        a, b = Vector(a), Vector(b)
        length = (b - a).length
        axis = (b - a).normalized()
        u = axis.cross(Vector((0, 0, 1)))
        if u.length < 0.1:
            u = axis.cross(Vector((1, 0, 0)))
        u.normalize()
        v = axis.cross(u).normalized()
        rings = []
        n_rings = max(3, min(8, int(length / 0.7) + 2))
        bend = u * rng.uniform(-1, 1) * bow * length
        for k in range(n_rings):
            t = k / (n_rings - 1)
            p = a.lerp(b, t) + bend * math.sin(math.pi * t)
            rr = r * (1.0 + taper * (0.5 - t))
            ring = []
            for s in range(segs):
                ang = s / segs * math.tau
                j = 1.0 + rng.uniform(-jitter, jitter)
                ring.append(self.bm.verts.new(p + (u * math.cos(ang) + v * math.sin(ang)) * rr * j))
            rings.append(ring)
        base = jit(color, 0.1, rng)
        faces = []
        for k in range(n_rings - 1):
            for s in range(segs):
                q = [rings[k][s], rings[k][(s + 1) % segs], rings[k + 1][(s + 1) % segs], rings[k + 1][s]]
                f = self.bm.faces.new(q)
                f.smooth = True
                f.normal_update()
                faces.append(f)
                c = base
                if s % 3 == 0:
                    c = (c[0] * 0.8, c[1] * 0.79, c[2] * 0.78) # (a furrow in the bark)
                if rng.random() < 0.025:
                    c = (c[0] * 0.5, c[1] * 0.45, c[2] * 0.42) # (a knot)
                z = f.calc_center_median().z
                grime = 0.72 + 0.28 * max(0.0, min(z / 1.6, 1.0))
                c = (c[0] * grime, c[1] * grime, c[2] * grime)
                if moss > 0.0 and f.normal.z > 0.35 and rng.random() < moss * (1.2 - min(z / 2.0, 1.0)):
                    m = jit(MOSS, 0.15, rng)
                    c = (c[0] * 0.35 + m[0] * 0.65, c[1] * 0.35 + m[1] * 0.65, c[2] * 0.35 + m[2] * 0.65)
                self._face_color(f, c)
        sap = jit(end, 0.05, rng)
        heart = (sap[0] * 0.82, sap[1] * 0.68, sap[2] * 0.58)
        for ring, flip in ((rings[0], True), (rings[-1], False)):
            ctr = Vector((0, 0, 0))
            for vv in ring:
                ctr += vv.co
            ctr /= len(ring)
            mid = [self.bm.verts.new(ctr + (vv.co - ctr) * 0.88) for vv in ring]
            inner = [self.bm.verts.new(ctr + (vv.co - ctr) * 0.5) for vv in ring]
            cv = self.bm.verts.new(ctr)
            for s in range(segs):
                s1 = (s + 1) % segs
                for quad, c in (([ring[s], ring[s1], mid[s1], mid[s]], (base[0] * 0.7, base[1] * 0.68, base[2] * 0.66)),
                                ([mid[s], mid[s1], inner[s1], inner[s]], sap)):
                    f = self.bm.faces.new(list(reversed(quad)) if not flip else quad)
                    f.normal_update()
                    self._face_color(f, c)
                tri = [inner[s], inner[s1], cv]
                f = self.bm.faces.new(list(reversed(tri)) if not flip else tri)
                f.normal_update()
                self._face_color(f, heart)
        return faces

    def stone(self, center, size, color=STONE, rng=random):
        """A fieldstone: a lumpy, flattened ball."""
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=1, radius=0.5)
        verts = res["verts"]
        m = Matrix.Translation(Vector(center)) @ Matrix.Rotation(rng.uniform(0, math.tau), 4, "Z") @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        for vv in verts:
            vv.co = vv.co * (1.0 + rng.uniform(-0.12, 0.12))
        bmesh.ops.transform(self.bm, matrix=m, verts=verts)
        faces = list({f for vv in verts for f in vv.link_faces})
        for f in faces:
            f.normal_update()
        self._paint(faces, jit(color, 0.12, rng))

    def to_object(self, coll):
        Piece.count[self.stuff] = Piece.count.get(self.stuff, 0) + 1
        name = "%s-%s-%03d" % (self.stuff, self.tag, Piece.count[self.stuff]) if self.tag else "%s-%03d" % (self.stuff, Piece.count[self.stuff])
        me = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(name, me)
        coll.objects.link(ob)
        if me.color_attributes.get("Col"):
            me.color_attributes.active_color = me.color_attributes["Col"]
            me.color_attributes.render_color_index = me.color_attributes.find("Col")
        me.materials.append(_material(self.stuff))
        return ob


def _material(stuff):
    """One per stuff, its base colour the vertices' (so the exporter writes them out)."""
    mat = bpy.data.materials.get(stuff)
    if mat:
        return mat
    mat = bpy.data.materials.new(stuff)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.1 if stuff == "window" else 0.85
    return mat


class Kit:
    """Collects pieces for one building."""

    def __init__(self, kind):
        self.kind = kind
        self.rng = random.Random(hash(kind) & 0xFFFF)
        Piece.count = {}
        for ob in list(bpy.data.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        for me in list(bpy.data.meshes):
            bpy.data.meshes.remove(me)
        self.coll = bpy.context.scene.collection
        self.objects = []
        self.paint = PAINTS[0]

    def piece(self, stuff, tag=""):
        return Piece(stuff, tag)

    def add(self, p):
        if len(p.bm.verts) == 0:
            p.bm.free()
            return
        self.objects.append(p.to_object(self.coll))

    def finish(self):
        bpy.ops.object.select_all(action="DESELECT")
        for ob in self.objects:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = self.objects[0]
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
        os.makedirs(OUT, exist_ok=True)
        path = os.path.join(OUT, self.kind + ".glb")
        kw = dict(filepath=path, export_format="GLB", use_selection=False, export_apply=True, export_yup=True)
        bpy.ops.export_scene.gltf(**kw)
        print("wrote", path, len(self.objects), "pieces")


# --- parts of buildings ---------------------------------------------------------------------------

def plinth(k, w, d):
    """The buried block (it takes up any slope) and a course of fieldstones showing round its top."""
    p = k.piece("stone", "plinth")
    p.box((0, 0, PLINTH_TOP - 1.75), (w + 0.3, d + 0.3, 3.5), jit(STONE, 0.05, k.rng))
    k.add(p)
    for side in range(4):
        p = k.piece("stone", "found")
        along = w if side < 2 else d
        n = max(2, int(along / 0.55))
        for i in range(n):
            t = (i + 0.5) / n - 0.5
            if side < 2:
                c = (t * (w + 0.2), (-1 if side == 0 else 1) * (d * 0.5 + 0.12), 0.18)
            else:
                c = ((-1 if side == 2 else 1) * (w * 0.5 + 0.12), t * (d + 0.2), 0.18)
            p.stone(c, (0.5, 0.4, 0.32), rng=k.rng)
        k.add(p)


def floor(k, w, d):
    p = k.piece("plank")
    n = int(w / 0.22)
    for i in range(n):
        x = -w * 0.5 + (i + 0.5) * w / n
        p.box((x, 0, 0.41), (w / n - 0.01, d - 0.1, 0.1), jit(PLANK, 0.08, k.rng))
    k.add(p)


def _cut(span, holes):
    """Pieces of [span0, span1] left once each hole (a0, a1) is taken out."""
    out = [list(span)]
    for a0, a1 in holes:
        nxt = []
        for s0, s1 in out:
            if a1 <= s0 or a0 >= s1:
                nxt.append([s0, s1])
                continue
            if a0 - s0 > 0.25:
                nxt.append([s0, a0])
            if s1 - a1 > 0.25:
                nxt.append([a1, s1])
        out = nxt
    return out


def log_walls(k, w, d, courses, openings, dia=0.3):
    """Log walls, course on course, saddle-notched: the side walls' logs half a log higher, every
    log's ends past the corners. `openings`: (wall, centre along it, width, bottom, top) with wall
    "front" (-Y), "back", "left" (-X), "right"; bottom and top above the floor. A log through an
    opening is cut either side of it."""
    hx, hy = w * 0.5 - dia * 0.5, d * 0.5 - dia * 0.5
    top = FLOOR
    for c in range(courses):
        for wall in ("front", "back", "left", "right"):
            side = wall in ("left", "right")
            z = FLOOR + dia * 0.5 + c * dia + (dia * 0.5 if side else 0.0)
            length = (d if side else w) + 0.55
            holes = []
            for ow, oc, owid, ob, ot in openings:
                if ow == wall and FLOOR + ob - dia * 0.4 < z < FLOOR + ot + dia * 0.4:
                    holes.append((oc - owid * 0.5, oc + owid * 0.5))
            for s0, s1 in _cut((-length * 0.5, length * 0.5), holes):
                if side:
                    x = (-1 if wall == "left" else 1) * hx
                    a, b = (x, s0, z), (x, s1, z)
                else:
                    y = (-1 if wall == "front" else 1) * hy
                    a, b = (s0, y, z), (s1, y, z)
                p = k.piece("log")
                p.log(a, b, dia * 0.5, rng=k.rng, moss=0.5 if c < 2 else 0.05)
                # (the chinking between it and the log below, a pale line of moss and clay)
                if c > 0:
                    ax = Vector(b) - Vector(a)
                    mid = (Vector(a) + Vector(b)) * 0.5 - Vector((0, 0, dia * 0.47))
                    p.obox(mid, ax.normalized(), Vector((0, 0, 1)).cross(ax.normalized()), (0, 0, 1), (ax.length - 0.3, dia * 0.55, 0.05), jit(CHINK, 0.05, k.rng))
                k.add(p)
            top = max(top, z + dia * 0.5)
    return top


def log_gables(k, w, d, wall_top, rise, dia=0.3, ridge_axis="x"):
    """The gable ends in logs, each course shorter, up to the ridge; the purlins and the ridge pole
    run through them and out past them, carrying the roof. Returns (ridge z, half span, slope)."""
    half = d * 0.5 + 0.0
    n = max(2, int(rise / dia))
    for c in range(n):
        z = wall_top + dia * 0.5 + c * dia
        span = half * (1.0 - (c + 0.5) / n) + 0.1
        for sx in (-1, 1):
            x = sx * (w * 0.5 - dia * 0.5)
            p = k.piece("log")
            p.log((x, -span, z), (x, span, z), dia * 0.5, rng=k.rng)
            k.add(p)
    ridge = wall_top + rise
    # purlins: the ridge pole and one each side half way down
    for t in (-0.5, 0.0, 0.5):
        y = t * half
        z = ridge - abs(t) * rise + dia * 0.3
        p = k.piece("log")
        p.log((-w * 0.5 - 0.65, y, z), (w * 0.5 + 0.65, y, z), dia * 0.42, rng=k.rng)
        k.add(p)
    return ridge, half, math.atan2(rise, half)


def shingle_roof(k, w, ridge, half, slope, over=0.55, eave_over=0.6, strips=3, color=SHINGLE, stuff="shingle"):
    """Both slopes boarded and shingled, each in `strips` strips from the ridge down past the walls,
    shingles in staggered courses; fascia boards along the eaves, a ridge cap."""
    run = half + eave_over
    length = run / math.cos(slope)
    for side in (-1, 1):
        down = Vector((0, side * math.cos(slope), -math.sin(slope)))
        normal = Vector((0, side * math.sin(slope), math.cos(slope)))
        across = Vector((1, 0, 0))
        top = Vector((0, 0, ridge + 0.42))
        for s in range(strips):
            p = k.piece(stuff)
            v0 = length * s / strips
            v1 = length * (s + 1) / strips
            mid = top + down * ((v0 + v1) * 0.5)
            p.obox(mid, across, down, normal, (w + over * 2, v1 - v0, 0.05), jit(PLANK, 0.05, k.rng))
            course = 0.22
            rows = int(round((v1 - v0) / course))
            for r in range(rows):
                vv = v0 + (r + 0.5) * (v1 - v0) / rows
                off = (0.15 if (int(vv / course)) % 2 else 0.0)
                x = -w * 0.5 - over + off
                while x < w * 0.5 + over - 0.05:
                    sw = k.rng.uniform(0.22, 0.34)
                    sw = min(sw, w * 0.5 + over - x)
                    c = top + down * vv + normal * (0.045 + 0.012) + across * (x + sw * 0.5)
                    sh = Vector(c) + normal * 0.0
                    tilt = Matrix.Rotation(-0.08 * side, 3, across)
                    sc = jit(color, 0.12, k.rng)
                    if k.rng.random() < 0.12:
                        sc = (sc[0] * 0.7, sc[1] * 0.68, sc[2] * 0.66) # (an old one, weathered dark)
                    if vv > length * 0.6 and k.rng.random() < 0.18 + 0.3 * (vv / length - 0.6):
                        m = jit(MOSS, 0.15, k.rng)
                        sc = (sc[0] * 0.4 + m[0] * 0.6, sc[1] * 0.4 + m[1] * 0.6, sc[2] * 0.4 + m[2] * 0.6)
                    p.obox(sh, across, (tilt @ down), (tilt @ normal), (sw - 0.015, course * 1.6, 0.025), sc)
                    x += sw
            k.add(p)
        # the fascia along the eave
        p = k.piece("dark")
        eave = top + down * length
        p.obox(eave - normal * 0.05, across, normal, down, (w + over * 2 + 0.05, 0.22, 0.05), jit(DARK, 0.05, k.rng))
        k.add(p)
    p = k.piece("dark")
    for side in (-1, 1):
        n = Vector((0, side * math.sin(slope), math.cos(slope)))
        dn = Vector((0, side * math.cos(slope), -math.sin(slope)))
        p.obox(Vector((0, 0, ridge + 0.5)) + dn * 0.1 + n * 0.03, (1, 0, 0), dn, n, (w + over * 2 + 0.1, 0.24, 0.04), jit(DARK, 0.05, k.rng))
    k.add(p)


def gable_trim(k, w, ridge, half, slope, over=0.55, eave_over=0.6):
    """The gable ends dressed: a carved bargeboard down each edge of the roof with a fringe of teeth
    under it, a carved board hanging from the apex, a turned finial on the ridge."""
    trim = k.paint[0]
    run = half + eave_over
    length = run / math.cos(slope)
    top = Vector((0, 0, ridge + 0.47))
    for sx in (-1, 1):
        p = k.piece("plank", "barge")
        x = sx * (w * 0.5 + over + 0.03)
        for side in (-1, 1):
            down = Vector((0, side * math.cos(slope), -math.sin(slope)))
            nrm = Vector((0, side * math.sin(slope), math.cos(slope)))
            p.obox(Vector((x, 0, 0)) + top + down * (length * 0.5) - nrm * 0.04, (1, 0, 0), down, nrm.cross(Vector((1, 0, 0))).cross(down).normalized() * -1 if False else down.cross(Vector((1, 0, 0))), (0.05, length, 0.24), jit(trim, 0.03, k.rng))
            n = int(length / 0.14)
            for i in range(1, n):
                c = Vector((x, 0, 0)) + top + down * (i * length / n) - nrm * 0.2
                p.obox(c, (1, 0, 0), (Matrix.Rotation(0.785, 3, Vector((1, 0, 0))) @ down), (Matrix.Rotation(0.785, 3, Vector((1, 0, 0))) @ nrm), (0.04, 0.07, 0.07), jit(trim, 0.03, k.rng))
        # the hanging board at the apex, notched, and the finial above
        hb = Vector((x, 0, ridge + 0.05))
        p.box(hb, (0.05, 0.22, 0.75), jit(trim, 0.03, k.rng))
        for i in range(3):
            p.box(hb + Vector((sx * 0.03, 0, -0.25 + i * 0.22)), (0.02, 0.1, 0.1), (trim[0] * 0.7, trim[1] * 0.7, trim[2] * 0.7))
        k.add(p)
        p = k.piece("wood", "finial")
        p.log((x - sx * 0.2, 0, ridge + 0.5), (x - sx * 0.2, 0, ridge + 1.0), 0.05, color=trim, end=trim, taper=0.3)
        p.stone((x - sx * 0.2, 0, ridge + 1.05), (0.13, 0.13, 0.13), color=trim, rng=k.rng)
        k.add(p)


def door(k, x, y, width, height, facing=-1):
    """A framed plank door (boards, a Z brace, an iron handle) in the front wall at (x, y)."""
    p = k.piece("dark")
    for sx in (-1, 1):
        p.box((x + sx * (width * 0.5 + 0.05), y, FLOOR + height * 0.5), (0.12, 0.34, height), jit(DARK, 0.05, k.rng))
    p.box((x, y, FLOOR + height + 0.07), (width + 0.3, 0.34, 0.14), jit(DARK, 0.05, k.rng))
    k.add(p)
    p = k.piece("plank", "door")
    n = 5
    fy = y + facing * 0.02
    for i in range(n):
        bx = x - width * 0.5 + (i + 0.5) * width / n
        p.box((bx, fy, FLOOR + height * 0.5 - 0.02), (width / n - 0.012, 0.05, height - 0.06), jit(PLANK, 0.1, k.rng))
    for zz in (0.3, height - 0.3):
        p.box((x, fy + facing * 0.035, FLOOR + zz), (width - 0.08, 0.03, 0.12), jit(DARK, 0.05, k.rng))
    diag = math.atan2(height - 0.6, width - 0.1)
    p.obox((x, fy + facing * 0.035, FLOOR + height * 0.5), (math.cos(diag), 0, math.sin(diag)), (0, 1, 0), (-math.sin(diag), 0, math.cos(diag)),
           (math.hypot(width - 0.1, height - 0.6), 0.03, 0.1), jit(DARK, 0.05, k.rng))
    p.box((x + width * 0.32, fy + facing * 0.06, FLOOR + 1.0), (0.04, 0.04, 0.14), IRON)
    k.add(p)


def window(k, wall, at, w, d, width=0.75, bottom=0.95, height=0.75, shutters=True):
    """A window in a wall: a frame, a cross of glazing bars, the panes (stuff "window": lit at night
    from inside), two plank shutters standing open."""
    hx, hy = w * 0.5, d * 0.5
    if wall in ("front", "back"):
        s = -1 if wall == "front" else 1
        o = Vector((at, s * (hy - 0.12), 0))
        along, out = Vector((1, 0, 0)), Vector((0, s, 0))
    else:
        s = -1 if wall == "left" else 1
        o = Vector((s * (hx - 0.12), at, 0))
        along, out = Vector((0, 1, 0)), Vector((s, 0, 0))
    up = Vector((0, 0, 1))
    zc = FLOOR + bottom + height * 0.5
    c = o + up * zc
    trim, paint = k.paint
    f = c + out * 0.19 # (the face of the trim, out past the logs)
    p = k.piece("plank", "trim")
    # the frame and the cross of glazing bars, in the trim's paint
    for sgn in (-1, 1):
        p.obox(c + along * sgn * (width * 0.5 + 0.04), along, out, up, (0.08, 0.3, height + 0.14), jit(trim, 0.03, k.rng))
        p.obox(c + up * sgn * (height * 0.5 + 0.04), along, out, up, (width + 0.16, 0.3, 0.08), jit(trim, 0.03, k.rng))
    p.obox(c + out * 0.03, along, out, up, (0.03, 0.04, height), trim)
    p.obox(c + out * 0.03 + up * height * 0.12, along, out, up, (width, 0.04, 0.03), trim)
    # the carved surround: broad side boards with notches cut in them, a crown with a pediment and
    # a fringe of teeth under it, a sill on brackets with a carved apron
    for sgn in (-1, 1):
        sb = f + along * sgn * (width * 0.5 + 0.17)
        p.obox(sb, along, out, up, (0.17, 0.04, height + 0.32), jit(trim, 0.03, k.rng))
        for n in range(4):
            p.obox(sb + up * (-height * 0.36 + n * height * 0.24) + out * 0.025, along, out, up, (0.07, 0.02, 0.07), (trim[0] * 0.75, trim[1] * 0.75, trim[2] * 0.75))
    crown = f + up * (height * 0.5 + 0.2)
    for n, (wd, hh) in enumerate([(width + 0.62, 0.07), (width + 0.5, 0.06), (width + 0.4, 0.05)]):
        p.obox(crown + up * (n * 0.065), along, out, up, (wd, 0.06, hh), jit(trim, 0.03, k.rng))
    peak = crown + up * 0.2
    for sgn in (-1, 1):
        a = 0.42 * sgn
        p.obox(peak + along * sgn * (width * 0.27), (Matrix.Rotation(a, 3, out) @ along), out, (Matrix.Rotation(a, 3, out) @ up), (width * 0.62, 0.05, 0.06), jit(trim, 0.03, k.rng))
    n_teeth = int((width + 0.4) / 0.09)
    for n in range(n_teeth):
        x = -(width + 0.4) * 0.5 + (n + 0.5) * (width + 0.4) / n_teeth
        p.obox(crown + along * x - up * 0.07, (Matrix.Rotation(0.785, 3, out) @ along), out, (Matrix.Rotation(0.785, 3, out) @ up), (0.05, 0.03, 0.05), jit(trim, 0.03, k.rng))
    sill = f - up * (height * 0.5 + 0.12) + out * 0.05
    p.obox(sill, along, out, up, (width + 0.55, 0.14, 0.05), jit(trim, 0.03, k.rng))
    p.obox(sill - up * 0.12 - out * 0.04, along, out, up, (width + 0.3, 0.03, 0.16), jit(trim, 0.03, k.rng))
    for n in range(n_teeth - 2):
        x = -(width + 0.2) * 0.5 + (n + 0.5) * (width + 0.2) / (n_teeth - 2)
        p.obox(sill - up * 0.22 - out * 0.04 + along * x, (Matrix.Rotation(0.785, 3, out) @ along), out, (Matrix.Rotation(0.785, 3, out) @ up), (0.045, 0.025, 0.045), jit(trim, 0.03, k.rng))
    k.add(p)
    g = k.piece("window")
    g.obox(c, along, out, up, (width, 0.03, height), GLASS)
    k.add(g)
    if shutters:
        for sgn in (-1, 1):
            p = k.piece("plank", "shutter")
            hinge = c + along * sgn * (width * 0.5 + 0.28) + out * 0.24
            ang = sgn * 1.2
            dirv = (Matrix.Rotation(ang, 3, up) @ along) * sgn
            ctr = hinge + dirv * (width * 0.25)
            nrm = dirv.cross(up).normalized() * sgn
            for i in range(3):
                p.obox(ctr + up * ((i - 1) * height / 3.0), dirv, nrm, up, (width * 0.5, 0.03, height / 3.0 - 0.008), jit(paint, 0.05, k.rng))
            # a border and a diamond in the trim's colour
            for z in (-height * 0.46, height * 0.46):
                p.obox(ctr + up * z + nrm * 0.02, dirv, nrm, up, (width * 0.5, 0.012, 0.035), trim)
            p.obox(ctr + nrm * 0.02, (Matrix.Rotation(0.785, 3, nrm) @ dirv), nrm, (Matrix.Rotation(0.785, 3, nrm) @ up), (0.12, 0.012, 0.12), trim)
            k.add(p)


def chimney(k, x, y, ground, top, size=0.75):
    """A fieldstone chimney stack up the outside of a wall, in courses, a cap stone on top."""
    z = ground
    course = 0.55
    i = 0
    while z < top:
        z1 = min(z + course, top)
        last = z1 >= top - 0.01
        p = k.piece("stone", "chimneytop" if last else "chimney")
        sz = size if z < ground + 1.6 else size * 0.82
        p.box((x, y, (z + z1) * 0.5), (sz * 0.86, sz * 0.86, z1 - z), jit((0.42, 0.41, 0.38), 0.04, k.rng))
        for j in range(8):
            ang = j / 8 * math.tau + i
            px = x + math.cos(ang) * sz * 0.42
            py = y + math.sin(ang) * sz * 0.42
            p.stone((px, py, (z + z1) * 0.5 + k.rng.uniform(-0.1, 0.1)), (0.32, 0.26, 0.22), rng=k.rng)
        if last:
            p.box((x, y, z1 + 0.05), (sz + 0.1, sz + 0.1, 0.1), jit(STONE, 0.04, k.rng))
        k.add(p)
        z = z1
        i += 1


def porch(k, w, front_y, depth=1.4, height=2.3, width=None, roof_top=None):
    """A porch along the front: plank deck on stump footings, two posts, a lean-to shingled roof
    tucked in under the main roof's eave (`roof_top`: the height it starts from at the wall)."""
    width = width or (w * 0.6)
    slope = 0.3
    run = depth + 0.3
    if roof_top is not None:
        height = roof_top - math.tan(slope) * (depth - 0.15) - FLOOR - 0.2
    p = k.piece("plank")
    for i in range(int(depth / 0.2)):
        y = front_y - 0.1 - i * 0.2
        p.box((0, y, 0.38), (width, 0.19, 0.06), jit(PLANK, 0.08, k.rng))
    k.add(p)
    p = k.piece("log")
    for sx in (-1, 1):
        for yy in (front_y - 0.2, front_y - depth + 0.15):
            p.log((sx * width * 0.45, yy, -0.4), (sx * width * 0.45, yy, 0.34), 0.13, rng=k.rng)
    k.add(p)
    for sx in (-1, 1):
        p = k.piece("log")
        p.log((sx * width * 0.45, front_y - depth + 0.15, 0.4), (sx * width * 0.45, front_y - depth + 0.15, FLOOR + height), 0.09, rng=k.rng)
        k.add(p)
    p = k.piece("log")
    p.log((-width * 0.55, front_y - depth + 0.15, FLOOR + height + 0.05), (width * 0.55, front_y - depth + 0.15, FLOOR + height + 0.05), 0.1, rng=k.rng)
    k.add(p)
    trim = k.paint[0]
    edge = front_y - depth + 0.1
    # two steps down the front, between the posts
    p = k.piece("plank", "steps")
    for i, (dy, z) in enumerate(((0.2, 0.24), (0.45, 0.1))):
        p.box((0, edge - dy, z), (1.3, 0.26, 0.05), jit(PLANK, 0.08, k.rng))
        for sx in (-1, 1):
            p.box((sx * 0.62, edge - dy, z * 0.5), (0.05, 0.26, z), DARK)
    k.add(p)
    # railings: a rail on balusters along the sides and either side of the steps
    for sx in (-1, 1):
        p = k.piece("plank", "rail")
        x = sx * width * 0.45
        for t in range(int((depth - 0.2) / 0.18)):
            p.box((x, front_y - 0.15 - t * 0.18, 0.67), (0.035, 0.035, 0.52), jit(trim, 0.04, k.rng))
        p.box((x, front_y - depth * 0.5, 0.95), (0.07, depth - 0.1, 0.06), jit(trim, 0.03, k.rng))
        run_x = width * 0.45 - 0.75
        for t in range(int(run_x / 0.18) + 1):
            p.box((sx * (0.75 + t * 0.18), edge, 0.67), (0.035, 0.035, 0.52), jit(trim, 0.04, k.rng))
        p.box((sx * (0.75 + run_x * 0.5), edge, 0.95), (run_x + 0.05, 0.07, 0.06), jit(trim, 0.03, k.rng))
        k.add(p)
    # a bench against the wall, a lantern on an iron arm by the door, antlers over the door
    p = k.piece("plank", "bench")
    bx = width * 0.3
    p.box((bx, front_y - 0.3, 0.86), (1.1, 0.32, 0.05), jit(PLANK, 0.06, k.rng))
    for sx in (-1, 1):
        p.box((bx + sx * 0.45, front_y - 0.3, 0.63), (0.06, 0.28, 0.42), DARK)
    k.add(p)
    p = k.piece("dark", "lamparm")
    p.box((-0.85, front_y - 0.2, FLOOR + 1.9), (0.04, 0.3, 0.04), IRON)
    p.box((-0.85, front_y - 0.33, FLOOR + 1.8), (0.16, 0.16, 0.04), IRON)
    p.box((-0.85, front_y - 0.33, FLOOR + 1.6), (0.18, 0.18, 0.03), IRON)
    k.add(p)
    g = k.piece("window", "lamp")
    g.box((-0.85, front_y - 0.33, FLOOR + 1.7), (0.12, 0.12, 0.17), (1.0, 0.85, 0.6))
    k.add(g)
    p = k.piece("wood", "antlers")
    base = Vector((0, front_y - 0.12, FLOOR + 2.55))
    p.box(base, (0.2, 0.04, 0.16), jit(PLANK, 0.05, k.rng))
    for sx in (-1, 1):
        a0 = base + Vector((sx * 0.06, -0.04, 0.04))
        a1 = a0 + Vector((sx * 0.35, -0.05, 0.25))
        p.log(a0, a1, 0.025, color=BONE, end=BONE, segs=6, taper=0.4)
        for t in (0.4, 0.75):
            q = a0.lerp(a1, t)
            p.log(q, q + Vector((sx * 0.02, -0.04, 0.18)), 0.015, color=BONE, end=BONE, segs=5, taper=0.5)
    k.add(p)
    p = k.piece("shingle")
    down = Vector((0, -math.cos(slope), -math.sin(slope)))
    nrm = Vector((0, -math.sin(slope), math.cos(slope)))
    top = Vector((0, front_y + 0.05, FLOOR + height + 0.2 + math.tan(slope) * (depth - 0.15)))
    p.obox(top + down * run * 0.5, (1, 0, 0), down, nrm, (width + 0.4, run, 0.05), jit(PLANK, 0.05, k.rng))
    rows = int(run / 0.22)
    for r in range(rows):
        x = -width * 0.5 - 0.2 + (0.14 if r % 2 else 0)
        while x < width * 0.5 + 0.15:
            sw = k.rng.uniform(0.22, 0.32)
            p.obox(top + down * ((r + 0.5) * run / rows) + nrm * 0.05 + Vector((x + sw * 0.5, 0, 0)), (1, 0, 0), down, nrm, (sw - 0.015, 0.34, 0.025), jit(SHINGLE, 0.12, k.rng))
            x += sw
    k.add(p)


def woodpile(k, x, y, length=1.8, height=1.0, along_x=False):
    p = k.piece("wood", "pile")
    rows = int(height / 0.16)
    for r in range(rows):
        n = int(length / 0.17)
        for i in range(n):
            t = -length * 0.5 + (i + 0.5) * length / n + (0.08 if r % 2 else 0)
            if abs(t) > length * 0.5:
                continue
            z = 0.1 + r * 0.15
            if along_x:
                p.log((x + t, y - 0.28, z), (x + t, y + 0.28, z), 0.075, segs=6, rng=k.rng, end=(0.82, 0.68, 0.48))
            else:
                p.log((x - 0.28, y + t, z), (x + 0.28, y + t, z), 0.075, segs=6, rng=k.rng, end=(0.82, 0.68, 0.48))
    k.add(p)


def barrel(k, x, y, z=0.0, r=0.3, h=0.8):
    p = k.piece("wood")
    for s in range(14):
        ang = s / 14 * math.tau
        bulge = 1.0
        c = Vector((x + math.cos(ang) * r, y + math.sin(ang) * r, z + h * 0.5))
        p.obox(c, (-math.sin(ang), math.cos(ang), 0), (math.cos(ang), math.sin(ang), 0), (0, 0, 1), (r * 0.46 * bulge, 0.04, h), jit(PLANK, 0.1, k.rng))
    p.box((x, y, z + h - 0.04), (r * 1.8, r * 1.8, 0.04), jit(PLANK, 0.05, k.rng))
    for hz in (0.15, h - 0.15):
        for s in range(14):
            ang = s / 14 * math.tau
            c = Vector((x + math.cos(ang) * (r + 0.025), y + math.sin(ang) * (r + 0.025), z + hz))
            p.obox(c, (-math.sin(ang), math.cos(ang), 0), (math.cos(ang), math.sin(ang), 0), (0, 0, 1), (r * 0.47, 0.015, 0.05), IRON)
    k.add(p)


def crate(k, x, y, z=0.0, s=0.7):
    p = k.piece("plank")
    p.box((x, y, z + s * 0.5), (s, s, s), jit(PLANK, 0.1, k.rng))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((x + sx * s * 0.48, y + sy * s * 0.48, z + s * 0.5), (0.06, 0.06, s + 0.01), jit(DARK, 0.05, k.rng))
    k.add(p)


def chopping_block(k, x, y):
    p = k.piece("log")
    p.log((x, y, 0.0), (x, y, 0.55), 0.25, rng=k.rng, taper=0.0)
    p.obox((x + 0.05, y, 0.75), (0.95, 0.31, 0), (0, 0, 1), (-0.31, 0.95, 0), (0.035, 0.6, 0.035), PLANK)
    p.box((x + 0.05, y, 0.58), (0.05, 0.22, 0.12), IRON)
    k.add(p)


# --- the buildings ---------------------------------------------------------------------------------

def cabin(kind, w, d, courses, rise, door_w=1.0, windows=(), porch_on=True, chimney_at=None, extra=None, double_door=False):
    k = Kit(kind)
    k.paint = k.rng.choice(PAINTS)
    plinth(k, w, d)
    floor(k, w, d)
    door_h = 2.0
    openings = [("front", 0.0, door_w + 0.25, 0.0, door_h + 0.1)]
    for wall, at in windows:
        openings.append((wall, at, 0.95, 0.85, 1.85))
    wall_top = log_walls(k, w, d, courses, openings)
    ridge, half, slope = log_gables(k, w, d, wall_top, rise)
    shingle_roof(k, w, ridge, half, slope)
    gable_trim(k, w, ridge, half, slope)
    if double_door:
        door(k, -door_w * 0.25, -d * 0.5 + 0.15, door_w * 0.5, door_h)
        door(k, door_w * 0.25, -d * 0.5 + 0.15, door_w * 0.5, door_h)
    else:
        door(k, 0.0, -d * 0.5 + 0.15, door_w, door_h)
    for wall, at in windows:
        window(k, wall, at, w, d)
    if chimney_at:
        chimney(k, chimney_at[0], chimney_at[1], 0.0, ridge + 0.8)
    if porch_on:
        eave_z = ridge + 0.42 - (half + 0.6) * math.tan(slope)
        porch(k, w, -d * 0.5, width=max(door_w + 1.6, w * 0.55), roof_top=eave_z - 0.25)
    if extra:
        extra(k, w, d)
    k.finish()


def _house_extra(k, w, d):
    woodpile(k, -w * 0.5 - 0.6, 0.6, length=2.4, height=1.1)
    # a lean-to roof over the woodpile, against the wall
    p = k.piece("plank")
    p.obox((-w * 0.5 - 0.6, 0.6, 1.55), (0.95, 0, -0.3), (0, 1, 0), (0.3, 0, 0.95), (0.9, 2.7, 0.04), jit(PLANK, 0.06, k.rng))
    for yy in (-0.6, 1.8):
        p.box((-w * 0.5 - 1.0, yy, 0.7), (0.06, 0.06, 1.4), DARK)
    k.add(p)
    chopping_block(k, -w * 0.5 - 1.2, -d * 0.5 - 0.7)
    p = k.piece("wood", "chips")
    for i in range(14):
        p.box((-w * 0.5 - 1.2 + k.rng.uniform(-0.6, 0.6), -d * 0.5 - 0.7 + k.rng.uniform(-0.6, 0.6), 0.01), (0.08, 0.05, 0.015), SAWDUST_C, rot_z=k.rng.uniform(0, 3))
    k.add(p)
    barrel(k, w * 0.5 - 0.6, -d * 0.5 - 0.45)
    # a path of flat stones out from the steps
    p = k.piece("stone", "path")
    for i in range(5):
        p.stone((k.rng.uniform(-0.15, 0.15), -d * 0.5 - 2.2 - i * 0.55, 0.02), (0.5, 0.42, 0.08), rng=k.rng)
    k.add(p)
    # a washing line between two poles at the side, things hung on it
    p = k.piece("wood", "line")
    x0, x1 = w * 0.5 + 0.9, w * 0.5 + 0.9
    p.log((x0, -1.6, -0.3), (x0, -1.6, 2.0), 0.04, rng=k.rng)
    p.log((x1, 1.8, -0.3), (x1, 1.8, 2.0), 0.04, rng=k.rng)
    p.box((x0, 0.1, 1.9), (0.01, 3.4, 0.01), (0.7, 0.65, 0.55))
    for i, col in enumerate([(0.8, 0.78, 0.72), (0.55, 0.2, 0.15), (0.3, 0.4, 0.55)]):
        p.box((x0, -0.9 + i * 0.95, 1.6), (0.01, 0.6, 0.55), col)
    k.add(p)


def _store_extra(k, w, d):
    # the loading platform along the front, and what waits on it
    p = k.piece("plank")
    for i in range(7):
        p.box((0, -d * 0.5 - 0.15 - i * 0.22, 0.42), (w - 1.0, 0.21, 0.08), jit(PLANK, 0.08, k.rng))
    k.add(p)
    for i, (x, y) in enumerate([(-w * 0.5 + 0.9, -d * 0.5 - 0.9), (-w * 0.5 + 1.75, -d * 0.5 - 0.85), (w * 0.5 - 1.0, -d * 0.5 - 0.9)]):
        crate(k, x, y, 0.46)
    crate(k, -w * 0.5 + 1.3, -d * 0.5 - 0.88, 1.16, 0.55)
    barrel(k, w * 0.5 - 1.9, -d * 0.5 - 0.95, 0.46)
    barrel(k, w * 0.5 + 0.6, 0.0)
    p = k.piece("wood", "sacks")
    for i in range(5):
        p.stone((-0.4 + i * 0.4 + (0.2 if i > 2 else 0), -d * 0.5 - 1.0 - (0.3 if i > 2 else 0), 0.66 + (0.3 if i == 4 else 0)), (0.42, 0.32, 0.36), color=(0.68, 0.6, 0.45), rng=k.rng)
    k.add(p)
    p = k.piece("dark", "sign")
    p.box((0, -d * 0.5 - 0.02, 3.0), (2.0, 0.06, 0.45), jit(DARK, 0.04, k.rng))
    for i in range(5):
        p.box((-0.7 + i * 0.35, -d * 0.5 - 0.06, 3.0), (0.2, 0.02, 0.22), k.paint[0])
    k.add(p)
    p = k.piece("log", "hoist")
    p.log((w * 0.5 + 1.4, 0.0, 4.2), (w * 0.5 - 0.6, 0.0, 4.2), 0.12, rng=k.rng)
    p.log((w * 0.5 + 1.3, 0.0, 4.15), (w * 0.5 + 1.3, 0.0, 3.0), 0.012, color=(0.6, 0.5, 0.35), end=(0.6, 0.5, 0.35), segs=5)
    p.log((w * 0.5 + 1.25, 0.0, 4.05), (w * 0.5 + 1.35, 0.0, 4.05), 0.09, color=DARK, end=DARK, taper=0.0)
    k.add(p)
    woodpile(k, w * 0.5 + 0.7, d * 0.5 - 1.2, length=2.0, height=1.2)


def _watch_extra(k, w, d):
    # a bell on a post by the door, a rifle rack, a bench
    p = k.piece("log")
    p.log((w * 0.5 + 0.8, -d * 0.5 - 0.8, -0.3), (w * 0.5 + 0.8, -d * 0.5 - 0.8, 3.2), 0.11, rng=k.rng)
    p.log((w * 0.5 + 0.8, -d * 0.5 - 0.8, 3.1), (w * 0.5 + 0.25, -d * 0.5 - 0.8, 3.1), 0.06, rng=k.rng)
    k.add(p)
    p = k.piece("stone", "bell")
    p.log((w * 0.5 + 0.3, -d * 0.5 - 0.8, 2.75), (w * 0.5 + 0.3, -d * 0.5 - 0.8, 3.05), 0.15, color=(0.45, 0.36, 0.2), end=(0.45, 0.36, 0.2), taper=0.6)
    k.add(p)
    p = k.piece("dark")
    p.box((-w * 0.5 + 1.0, -d * 0.5 - 0.25, 1.5), (1.2, 0.1, 0.08), DARK)
    for i in range(4):
        p.obox((-w * 0.5 + 0.6 + i * 0.27, -d * 0.5 - 0.3, 1.2), (0, 0, 1), (1, 0, 0), (0, 1, 0), (1.1, 0.04, 0.05), (0.18, 0.18, 0.19))
    k.add(p)
    p = k.piece("plank")
    p.box((0.9, -d * 0.5 - 0.5, 0.45), (1.5, 0.35, 0.06), jit(PLANK, 0.08, k.rng))
    for sx in (-1, 1):
        p.box((0.9 + sx * 0.6, -d * 0.5 - 0.5, 0.22), (0.08, 0.3, 0.44), DARK)
    k.add(p)
    woodpile(k, -w * 0.5 - 0.6, 0.3, length=2.0)


def ev():
    cabin("ev", 6.0, 5.0, 8, 1.9, 1.0, windows=[("front", -1.8), ("left", 0.0), ("back", 1.0)], chimney_at=(3.0 + 0.85, 0.8), extra=_house_extra)


def ambar():
    cabin("ambar", 9.0, 7.0, 10, 2.6, 2.4, windows=[("left", 0.0), ("right", -1.5)], porch_on=False, extra=_store_extra, double_door=True)


def kisla():
    cabin("kisla", 8.0, 6.0, 9, 2.2, 1.2, windows=[("front", -2.3), ("front", 2.3), ("left", 0.0), ("right", 0.0), ("back", 0.0)],
          chimney_at=(-4.0 - 0.85, 1.2), extra=_watch_extra, porch_on=False)


def fener():
    k = Kit("fener")
    p = k.piece("stone", "plinth")
    p.box((0, 0, PLINTH_TOP - 1.0), (0.55, 0.55, 2.0), jit(STONE, 0.05, k.rng))
    k.add(p)
    p = k.piece("stone")
    for j in range(6):
        ang = j / 6 * math.tau
        p.stone((math.cos(ang) * 0.32, math.sin(ang) * 0.32, 0.15), (0.3, 0.26, 0.22), rng=k.rng)
    k.add(p)
    p = k.piece("dark")
    p.box((0, 0, 0.35 + 1.6), (0.17, 0.17, 3.2), jit(DARK, 0.05, k.rng))
    p.obox((0.32, 0, 3.15), (0.85, 0, 0.53), (0, 1, 0), (-0.53, 0, 0.85), (0.75, 0.05, 0.05), IRON)
    p.box((0.35, 0, 3.42), (0.75, 0.05, 0.05), IRON)
    k.add(p)
    # the lantern: a hood, a cage of iron bars round its glass, a base
    p = k.piece("dark", "lamp")
    lx, lz = 0.7, 3.05
    p.box((lx, 0, lz - 0.24), (0.3, 0.3, 0.05), IRON)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((lx + sx * 0.13, sy * 0.13, lz), (0.025, 0.025, 0.44), IRON)
    res = Piece  # (just to keep the hood together)
    p.obox((lx, 0, lz + 0.3), (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.36, 0.36, 0.06), IRON)
    p.obox((lx, 0, lz + 0.38), (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.2, 0.2, 0.1), IRON)
    p.box((lx, 0, lz + 0.46), (0.05, 0.05, 0.1), IRON)
    k.add(p)
    g = k.piece("window")
    g.box((lx, 0, lz), (0.23, 0.23, 0.4), (1.0, 0.85, 0.6))
    k.add(g)
    k.finish()


def kuyu():
    k = Kit("kuyu")
    p = k.piece("stone", "plinth")
    p.box((0, 0, PLINTH_TOP - 1.75), (3.0, 3.0, 3.5), jit(STONE, 0.05, k.rng))
    k.add(p)
    for c in range(3):
        p = k.piece("stone")
        n = 14
        for j in range(n):
            ang = (j + 0.5 * (c % 2)) / n * math.tau
            p.stone((math.cos(ang) * 0.95, math.sin(ang) * 0.95, 0.35 + 0.15 + c * 0.28), (0.42, 0.32, 0.3), rng=k.rng)
        k.add(p)
    p = k.piece("water")
    p.box((0, 0, 1.05), (1.4, 1.4, 0.04), (0.05, 0.08, 0.09))
    k.add(p)
    for sx in (-1, 1):
        p = k.piece("log")
        p.log((sx * 1.05, 0, 0.3), (sx * 1.05, 0, 2.7), 0.09, rng=k.rng)
        k.add(p)
    p = k.piece("log")
    p.log((-1.2, 0, 2.0), (1.2, 0, 2.0), 0.1, rng=k.rng)
    p.box((1.3, 0, 1.85), (0.05, 0.05, 0.35), IRON)
    p.box((1.3, -0.12, 1.7), (0.05, 0.28, 0.05), IRON)
    k.add(p)
    p = k.piece("wood", "bucket")
    p.log((0.2, 0, 1.25), (0.2, 0, 1.55), 0.15, color=PLANK, end=PLANK, taper=-0.25)
    p.box((0.2, 0, 1.8), (0.01, 0.01, 0.45), (0.5, 0.45, 0.35))
    k.add(p)
    ridge, half, slope = 3.25, 0.95, math.atan2(0.75, 0.95)
    p = k.piece("log")
    p.log((-1.35, 0, ridge), (1.35, 0, ridge), 0.08, rng=k.rng)
    k.add(p)
    shingle_roof(k, 2.2, ridge - 0.4, half, slope, over=0.25, eave_over=0.25, strips=1)
    k.finish()


def kule():
    k = Kit("kule")
    plinth(k, 4.0, 4.0)
    p = k.piece("stone")
    for c in range(4):
        for side in range(4):
            for i in range(5):
                t = (i + 0.5) / 5 - 0.5 + (0.1 if c % 2 else 0)
                if side < 2:
                    ctr = (t * 3.6, (-1 if side == 0 else 1) * 1.8, 0.5 + c * 0.42)
                else:
                    ctr = ((-1 if side == 2 else 1) * 1.8, t * 3.6, 0.5 + c * 0.42)
                p.stone(ctr, (0.62, 0.45, 0.4), rng=k.rng)
    p.box((0, 0, 1.1), (3.4, 3.4, 1.5), jit((0.4, 0.39, 0.36), 0.03, k.rng))
    k.add(p)
    base = 2.2
    top = 9.4
    for sx in (-1, 1):
        for sy in (-1, 1):
            p = k.piece("log")
            p.log((sx * 1.55, sy * 1.55, base), (sx * 1.35, sy * 1.35, top + 2.2), 0.16, rng=k.rng)
            k.add(p)
    for lvl in (base + 2.3, base + 4.8):
        for side in range(4):
            p = k.piece("log")
            a = [(-1.5, -1.5), (1.5, -1.5), (1.5, 1.5), (-1.5, 1.5)][side]
            b = [(1.5, -1.5), (1.5, 1.5), (-1.5, 1.5), (-1.5, -1.5)][side]
            p.log((a[0], a[1], lvl), (b[0], b[1], lvl), 0.09, rng=k.rng)
            p.log((a[0], a[1], lvl - 2.2), (b[0], b[1], lvl), 0.07, rng=k.rng)
            k.add(p)
    # the platform, its rail, the ladder up the front
    p = k.piece("plank")
    for i in range(16):
        p.box((-2.1 + (i + 0.5) * 4.2 / 16, 0, top), (4.2 / 16 - 0.01, 4.4, 0.08), jit(PLANK, 0.08, k.rng))
    k.add(p)
    for side in range(4):
        p = k.piece("plank")
        for z in (top + 0.5, top + 0.95):
            if side < 2:
                p.box((0, (-1 if side == 0 else 1) * 2.15, z), (4.3, 0.06, 0.1), jit(PLANK, 0.06, k.rng))
            else:
                p.box(((-1 if side == 2 else 1) * 2.15, 0, z), (0.06, 4.3, 0.1), jit(PLANK, 0.06, k.rng))
        k.add(p)
    p = k.piece("wood")
    for sx in (-0.25, 0.25):
        p.log((sx, -2.4, 0.3), (sx, -2.0, top + 0.6), 0.04, rng=k.rng)
    n = int((top - 0.3) / 0.35)
    for i in range(n):
        t = (i + 0.5) / n
        y = -2.4 + 0.4 * t
        z = 0.3 + (top + 0.3) * t
        p.log((-0.27, y, z), (0.27, y, z), 0.03, segs=6, rng=k.rng)
    k.add(p)
    # a pyramid roof of shingles on four posts
    roof_base = top + 2.2
    for side in range(4):
        p = k.piece("shingle")
        ang = side * math.pi * 0.5
        out = Vector((math.sin(ang), -math.cos(ang), 0))
        across = Vector((math.cos(ang), math.sin(ang), 0))
        slope = math.atan2(1.6, 2.4)
        down = (out * math.cos(slope) + Vector((0, 0, -math.sin(slope)))).normalized()
        nrm = (out * math.sin(slope) + Vector((0, 0, math.cos(slope)))).normalized()
        apex = Vector((0, 0, roof_base + 1.6))
        L = 2.4 / math.cos(slope) + 0.3
        rows = 9
        for r in range(rows):
            v = (r + 0.5) * L / rows
            width = 2 * (v * math.cos(slope)) + 0.3
            x = -width * 0.5
            while x < width * 0.5:
                sw = min(k.rng.uniform(0.22, 0.32), width * 0.5 - x + 0.01)
                p.obox(apex + down * v + nrm * 0.03 + across * (x + sw * 0.5), across, down, nrm, (sw - 0.012, L / rows * 1.5, 0.03), jit(SHINGLE, 0.12, k.rng))
                x += sw
        k.add(p)
    k.finish()


def shed(kind, w, d, props):
    """An open-fronted work shed: a log back wall and log ends half way up, corner posts, a lean-to
    shingled roof sloping to the back; `props` adds what its work leaves about."""
    k = Kit(kind)
    plinth(k, w, d)
    floor(k, w, d)
    log_walls(k, w, d, 4, [("front", 0.0, w + 1.0, -1.0, 9.0)])
    back_h, front_h = 2.4, 3.0
    for sx in (-1, 1):
        for sy, h in ((-1, front_h), (1, back_h)):
            p = k.piece("log")
            p.log((sx * (w * 0.5 - 0.15), sy * (d * 0.5 - 0.15), FLOOR), (sx * (w * 0.5 - 0.15), sy * (d * 0.5 - 0.15), FLOOR + h), 0.12, rng=k.rng)
            k.add(p)
    for sy, h in ((-1, front_h), (1, back_h)):
        p = k.piece("log")
        p.log((-w * 0.5 - 0.3, sy * (d * 0.5 - 0.15), FLOOR + h + 0.1), (w * 0.5 + 0.3, sy * (d * 0.5 - 0.15), FLOOR + h + 0.1), 0.12, rng=k.rng)
        k.add(p)
    slope = math.atan2(front_h - back_h, d)
    run = d + 0.9
    down = Vector((0, math.cos(slope), -math.sin(slope)))
    nrm = Vector((0, math.sin(slope), math.cos(slope)))
    top = Vector((0, -d * 0.5 - 0.45, FLOOR + front_h + 0.28 + math.tan(slope) * 0.3))
    for s in range(2):
        p = k.piece("shingle")
        v0, v1 = run * s / 2, run * (s + 1) / 2
        p.obox(top + down * ((v0 + v1) * 0.5), (1, 0, 0), down, nrm, (w + 0.9, v1 - v0, 0.05), jit(PLANK, 0.05, k.rng))
        rows = int((v1 - v0) / 0.22)
        for r in range(rows):
            x = -w * 0.5 - 0.45 + (0.14 if r % 2 else 0)
            while x < w * 0.5 + 0.4:
                sw = k.rng.uniform(0.22, 0.32)
                p.obox(top + down * (v0 + (r + 0.5) * (v1 - v0) / rows) + nrm * 0.05 + Vector((x + sw * 0.5, 0, 0)), (1, 0, 0), down, nrm, (sw - 0.015, 0.34, 0.025), jit(SHINGLE, 0.12, k.rng))
                x += sw
        k.add(p)
    props(k, w, d)
    k.finish()


def _cart_props(k, w, d):
    p = k.piece("plank")
    p.box((-0.6, 0.0, 1.05), (1.2, 1.6, 0.1), jit(PLANK, 0.06, k.rng))
    for sx in (-1, 1):
        p.box((-0.6 + sx * 0.58, 0.0, 1.3), (0.05, 1.6, 0.4), jit(PLANK, 0.06, k.rng))
    p.box((-0.6, -1.25, 1.05), (0.06, 1.0, 0.06), DARK)
    k.add(p)
    for sx in (-1, 1):
        p = k.piece("dark", "wheel")
        p.log((-0.6 + sx * 0.7, 0.2, 0.82), (-0.6 + sx * 0.78, 0.2, 0.82), 0.36, color=DARK, end=PLANK, segs=14, taper=0.0)
        k.add(p)
    for i in range(3):
        p = k.piece("dark")
        p.log((1.6, 1.4 - i * 0.12, 0.47), (1.68, 1.4 - i * 0.12, 0.47), 0.36, color=DARK, end=PLANK, segs=14, taper=0.0)
        k.add(p)


def ahir():
    def extra(k, w, d):
        p = k.piece("thatch", "hay")
        for i in range(4):
            p.box((w * 0.5 + 0.7, -1.6 + i * 1.0, 0.45 + (i % 2) * 0.0), (0.9, 0.9, 0.6), (0.7, 0.6, 0.33))
        p.box((w * 0.5 + 0.7, -1.1, 1.05), (0.9, 0.9, 0.6), (0.7, 0.6, 0.33))
        k.add(p)
    cabin("ahir", 9.0, 6.0, 9, 2.5, 2.6, windows=[("left", 0.0), ("back", -2.0), ("back", 2.0)], porch_on=False, extra=extra, double_door=True)


# --- work yards ------------------------------------------------------------------------------------

EARTH = (0.36, 0.29, 0.2)
SAWDUST = (0.86, 0.74, 0.52)


def yard_pad(k, w, d, top=EARTH):
    """A yard's ground: the buried block, its top packed earth, a few stones at its edge."""
    p = k.piece("stone", "plinth")
    p.box((0, 0, PLINTH_TOP - 1.75), (w + 0.2, d + 0.2, 3.5), jit(STONE, 0.04, k.rng))
    p.box((0, 0, PLINTH_TOP + 0.02), (w + 0.1, d + 0.1, 0.04), jit(top, 0.04, k.rng))
    k.add(p)
    p = k.piece("stone", "found")
    for i in range(14):
        a = i / 14 * math.tau
        p.stone((math.cos(a) * w * 0.52, math.sin(a) * d * 0.52, 0.18), (0.35, 0.3, 0.25), rng=k.rng)
    k.add(p)


def lean_to(k, x0, x1, y0, y1, h_front, h_back):
    """A little shelter: four posts, a shingled roof sloping to the back."""
    for x in (x0, x1):
        for y, h in ((y0, h_front), (y1, h_back)):
            p = k.piece("log")
            p.log((x, y, FLOOR - 0.1), (x, y, FLOOR + h), 0.09, rng=k.rng)
            k.add(p)
    slope = math.atan2(h_front - h_back, y1 - y0)
    run = (y1 - y0) / math.cos(slope) + 0.6
    down = Vector((0, math.cos(slope), -math.sin(slope)))
    nrm = Vector((0, math.sin(slope), math.cos(slope)))
    top = Vector(((x0 + x1) * 0.5, y0 - 0.3 * math.cos(slope), FLOOR + h_front + 0.12 + 0.3 * math.sin(slope)))
    p = k.piece("shingle")
    w = x1 - x0 + 0.6
    p.obox(top + down * run * 0.5, (1, 0, 0), down, nrm, (w, run, 0.05), jit(PLANK, 0.05, k.rng))
    rows = int(run / 0.22)
    for r in range(rows):
        x = -w * 0.5 + (0.14 if r % 2 else 0)
        while x < w * 0.5 - 0.05:
            sw = min(k.rng.uniform(0.22, 0.32), w * 0.5 - x)
            p.obox(top + down * ((r + 0.5) * run / rows) + nrm * 0.05 + Vector((x + sw * 0.5, 0, 0)), (1, 0, 0), down, nrm, (sw - 0.015, 0.34, 0.025), jit(SHINGLE, 0.12, k.rng))
            x += sw
    k.add(p)


def trestle(k, x, y, h=0.85):
    """A sawhorse end: two legs crossed in an X."""
    p = k.piece("wood")
    for s in (-1, 1):
        p.log((x, y - 0.45 * s, FLOOR - 0.02), (x, y + 0.35 * s, FLOOR + h + 0.15), 0.06, rng=k.rng)
    k.add(p)


def heap(k, x, y, rx, ry, h, color):
    p = k.piece("wood", "heap")
    p.stone((x, y, FLOOR - h * 0.3), (rx * 2, ry * 2, h * 2), color=color, rng=k.rng)
    k.add(p)


def kesim():
    """The felling camp's yard: logs come in on shoulders, go up on the sawhorse and are sawn
    there; the raw logs in a deck at the back, sawdust underfoot, the tools under a lean-to."""
    w, d = 7.0, 6.0
    k = Kit("oduncu")
    yard_pad(k, w, d)
    # the sawhorse in the middle, a log on it and the frame saw across it
    for x in (-0.9, 0.9):
        trestle(k, x, 0.3)
    p = k.piece("log", "work")
    p.log((-1.6, 0.3, FLOOR + 1.0), (1.6, 0.3, FLOOR + 1.0), 0.2, rng=k.rng)
    k.add(p)
    p = k.piece("wood")
    p.box((0.4, 0.15, FLOOR + 1.35), (0.05, 0.05, 0.75), DARK)
    p.box((0.4, 0.62, FLOOR + 1.35), (0.05, 0.05, 0.75), DARK)
    p.box((0.4, 0.38, FLOOR + 1.7), (0.05, 0.5, 0.04), DARK)
    p.box((0.4, 0.38, FLOOR + 1.0), (0.01, 0.52, 0.08), (0.6, 0.6, 0.62))
    k.add(p)
    heap(k, 0.0, 0.0, 0.8, 0.6, 0.12, SAWDUST)
    heap(k, -0.6, 0.6, 0.5, 0.4, 0.08, SAWDUST)
    # the deck of raw logs at the back left
    p = k.piece("log", "deck")
    for r in range(3):
        for i in range(4 - r):
            x = -3.0 + i * 0.5 + r * 0.25
            p.log((x, 0.9, FLOOR + 0.22 + r * 0.42), (x, 2.7, FLOOR + 0.22 + r * 0.42), 0.22, rng=k.rng)
    k.add(p)
    # the lean-to at the back right: a tool rack and a grindstone under it
    lean_to(k, 0.9, 3.2, 1.5, 2.8, 2.4, 1.9)
    p = k.piece("wood")
    p.box((2.05, 2.75, FLOOR + 1.1), (2.0, 0.06, 0.06), DARK)
    for i, tool in enumerate(("axe", "axe", "saw", "pole")):
        x = 1.3 + i * 0.45
        p.box((x, 2.7, FLOOR + 0.6), (0.04, 0.04, 1.1), PLANK)
        if tool == "axe":
            p.box((x, 2.66, FLOOR + 0.12), (0.03, 0.18, 0.15), IRON)
    k.add(p)
    p = k.piece("wood", "grind")
    p.log((2.6, 1.85, FLOOR + 0.55), (2.75, 1.85, FLOOR + 0.55), 0.32, color=(0.55, 0.52, 0.47), end=(0.55, 0.52, 0.47), taper=0.0, segs=14)
    for s in (-1, 1):
        p.box((2.68 + s * 0.2, 1.85, FLOOR + 0.28), (0.06, 0.08, 0.6), DARK)
    k.add(p)
    chopping_block(k, -2.4, -1.7)
    k.finish()


def tas_ocagi():
    """The stone yard: rough blocks come in and are dressed on the bench with mallet and chisel; a
    tripod derrick to lift them, the rough ones heaped at the back, the dressed ones stacked."""
    w, d = 7.0, 6.0
    k = Kit("tasci")
    yard_pad(k, w, d, top=(0.42, 0.4, 0.36))
    # the bench: a stone slab on two blocks, a block on it being dressed, the tools
    p = k.piece("stone", "work")
    for x in (-0.55, 0.55):
        p.box((x, 0.3, FLOOR + 0.3), (0.3, 0.5, 0.6), jit(STONE, 0.08, k.rng))
    p.box((0, 0.3, FLOOR + 0.65), (1.5, 0.7, 0.12), jit(STONE, 0.05, k.rng))
    p.box((0.1, 0.32, FLOOR + 0.92), (0.55, 0.42, 0.42), jit((0.6, 0.59, 0.55), 0.04, k.rng))
    k.add(p)
    p = k.piece("wood")
    p.box((-0.45, 0.15, FLOOR + 0.75), (0.25, 0.08, 0.08), PLANK)
    p.box((-0.6, 0.15, FLOOR + 0.75), (0.1, 0.12, 0.12), PLANK)
    p.box((0.55, 0.12, FLOOR + 0.73), (0.22, 0.03, 0.03), IRON)
    k.add(p)
    heap(k, 0.2, -0.1, 0.9, 0.6, 0.06, (0.7, 0.69, 0.65))
    # the derrick: three poles to a head, a pulley, a rope, a block hanging
    top = Vector((-2.2, 0.9, FLOOR + 3.6))
    for a in (0.0, 2.1, 4.2):
        foot = Vector((-2.2 + math.cos(a) * 1.3, 0.9 + math.sin(a) * 1.3, FLOOR))
        p = k.piece("log")
        p.log(foot, top + Vector((0, 0, 0.2)), 0.08, rng=k.rng)
        k.add(p)
    p = k.piece("wood")
    p.log(top + Vector((-0.1, 0, -0.1)), top + Vector((0.1, 0, -0.1)), 0.12, color=DARK, end=DARK, taper=0.0)
    p.box(top + Vector((0, 0, -1.05)), (0.025, 0.025, 1.9), (0.6, 0.5, 0.35))
    k.add(p)
    p = k.piece("stone")
    p.box(top + Vector((0, 0, -2.25)), (0.6, 0.45, 0.45), jit(STONE, 0.05, k.rng))
    k.add(p)
    # rough blocks heaped at the back left, dressed ones stacked at the back right
    p = k.piece("stone", "rough")
    for i in range(9):
        p.stone((-1.0 + k.rng.uniform(-0.7, 0.7) - 1.6 * (i % 2), 2.2 + k.rng.uniform(-0.4, 0.4), FLOOR + 0.2 + (i // 4) * 0.3), (0.7, 0.55, 0.5), rng=k.rng)
    k.add(p)
    p = k.piece("stone", "dressed")
    for i in range(10):
        x = 1.2 + (i % 4) * 0.62
        z = FLOOR + 0.2 + (i // 4) * 0.42
        p.box((x, 2.3, z), (0.58, 0.45, 0.4), jit((0.62, 0.61, 0.57), 0.05, k.rng))
    k.add(p)
    lean_to(k, 1.0, 3.2, 1.2, 1.9, 2.3, 2.0)
    p = k.piece("stone")
    for i in range(12):
        p.stone((k.rng.uniform(-3.0, 3.0), k.rng.uniform(-2.6, -1.2), FLOOR - 0.05), (0.18, 0.15, 0.12), rng=k.rng)
    k.add(p)
    k.finish()


def toplayici():
    """The gatherers' hut: an open shelter of drying racks hung with berries, a sorting table out
    front, baskets about."""
    w, d = 6.0, 5.0
    k = Kit("toplayici")
    yard_pad(k, w, d)
    lean_to(k, -2.4, 2.4, 0.4, 2.2, 2.5, 2.0)
    p = k.piece("wood", "rack")
    for z in (1.0, 1.5, 2.0):
        p.log((-2.3, 1.3, FLOOR + z), (2.3, 1.3, FLOOR + z), 0.03, rng=k.rng)
        for i in range(18):
            x = -2.1 + i * 0.25
            c = (0.45, 0.08, 0.12) if i % 3 else (0.18, 0.15, 0.35)
            p.stone((x, 1.3, FLOOR + z - 0.12), (0.12, 0.08, 0.18), color=c, rng=k.rng)
    k.add(p)
    p = k.piece("plank", "work")
    p.box((0, -0.8, FLOOR + 0.75), (1.6, 0.7, 0.06), jit(PLANK, 0.05, k.rng))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * 0.7, -0.8 + sy * 0.28, FLOOR + 0.37), (0.06, 0.06, 0.74), DARK)
    k.add(p)
    p = k.piece("thatch", "baskets")
    for i, (x, y) in enumerate([(-1.6, -1.6), (-1.0, -1.8), (1.4, -1.7), (0.4, -0.75)]):
        z = FLOOR if i < 3 else FLOOR + 0.78
        p.log((x, y, z), (x, y, z + 0.32), 0.24, color=(0.62, 0.5, 0.3), end=(0.42, 0.1, 0.18), taper=-0.25)
    k.add(p)
    k.finish()


def ormanci():
    """The forester's nursery: raised beds of seedlings in rows, a water barrel, a tool shed."""
    w, d = 6.0, 5.0
    k = Kit("ormanci")
    yard_pad(k, w, d)
    for b in range(3):
        y = -1.5 + b * 1.3
        p = k.piece("plank", "bed")
        p.box((-0.6, y, FLOOR + 0.12), (3.6, 0.9, 0.24), jit(PLANK, 0.05, k.rng))
        p.box((-0.6, y, FLOOR + 0.25), (3.4, 0.75, 0.02), EARTH)
        k.add(p)
        p = k.piece("wood", "seedlings")
        for i in range(9):
            x = -2.2 + i * 0.4
            for j in (-0.2, 0.2):
                hgt = 0.2 + b * 0.12
                p.log((x, y + j, FLOOR + 0.26), (x, y + j, FLOOR + 0.26 + hgt), 0.07 + b * 0.015, color=(0.16, 0.34, 0.14), end=(0.14, 0.3, 0.12), taper=0.9, segs=6)
        k.add(p)
    barrel(k, 2.3, -1.6)
    lean_to(k, 1.6, 2.8, 0.6, 2.0, 2.2, 1.9)
    p = k.piece("wood")
    p.box((2.2, 1.95, FLOOR + 0.6), (0.04, 0.04, 1.1), PLANK)
    p.box((2.2, 1.9, FLOOR + 0.12), (0.18, 0.03, 0.22), IRON)
    k.add(p)
    k.finish()



def meydan():
    """The town square: paved, a fire pit in the middle ringed with stones and logs laid ready, log
    benches round it, a notice board, a lamp on a post."""
    w = d = 10.0
    k = Kit("meydan")
    k.paint = k.rng.choice(PAINTS)
    yard_pad(k, w, d, top=(0.42, 0.4, 0.37))
    for ring in range(4):
        p = k.piece("stone", "found")
        r = 1.8 + ring * 0.95
        n = int(r * 6.5)
        for i in range(n):
            a = i / n * math.tau + ring * 0.2
            p.box((math.cos(a) * r, math.sin(a) * r, PLINTH_TOP + 0.04), (0.62, 0.48, 0.06), jit((0.5, 0.49, 0.46), 0.08, k.rng), rot_z=a)
        k.add(p)
    p = k.piece("stone", "pit")
    for i in range(12):
        a = i / 12 * math.tau
        p.stone((math.cos(a) * 0.75, math.sin(a) * 0.75, PLINTH_TOP + 0.12), (0.32, 0.28, 0.24), rng=k.rng)
    k.add(p)
    p = k.piece("wood", "fire")
    for i in range(6):
        a = i / 6 * math.tau
        p.log((math.cos(a) * 0.45, math.sin(a) * 0.45, PLINTH_TOP + 0.05), (0, 0, PLINTH_TOP + 0.75), 0.06, rng=k.rng)
    k.add(p)
    for i in range(4):
        a = i / 4 * math.tau + math.pi / 4
        c = Vector((math.cos(a) * 2.9, math.sin(a) * 2.9, 0))
        along = Vector((-math.sin(a), math.cos(a), 0))
        p = k.piece("log", "bench")
        for t in (-0.7, 0.7):
            q = c + along * t
            p.log((q.x, q.y, PLINTH_TOP - 0.05), (q.x, q.y, PLINTH_TOP + 0.35), 0.15, rng=k.rng, taper=0.0)
        p.log(c - along * 1.0 + Vector((0, 0, PLINTH_TOP + 0.45)), c + along * 1.0 + Vector((0, 0, PLINTH_TOP + 0.45)), 0.14, rng=k.rng)
        k.add(p)
    p = k.piece("plank", "board")
    bx, by = 3.6, 3.6
    for s in (-1, 1):
        p.box((bx + s * 0.6, by, 1.2), (0.12, 0.12, 2.4), DARK)
    p.box((bx, by, 1.7), (1.4, 0.08, 0.9), jit(PLANK, 0.05, k.rng))
    p.obox((bx, by - 0.25, 2.3), (1, 0, 0), (0, math.cos(0.5), -math.sin(0.5)), (0, math.sin(0.5), math.cos(0.5)), (1.7, 0.6, 0.05), jit(SHINGLE, 0.05, k.rng))
    for i in range(5):
        p.box((bx - 0.45 + (i % 3) * 0.42, by - 0.05, 1.5 + (i // 3) * 0.35), (0.3, 0.01, 0.24), (0.88, 0.85, 0.76))
    k.add(p)
    k.finish()


def cankulesi():
    """The bell tower: a stone footing, four leaning posts braced across, a railed bell deck, the
    bell hanging from its beam, a steep shingled roof with a ball on top, a ladder up."""
    k = Kit("cankulesi")
    k.paint = k.rng.choice(PAINTS)
    plinth(k, 4.0, 4.0)
    p = k.piece("stone")
    for c in range(3):
        for side in range(4):
            for i in range(5):
                t = (i + 0.5) / 5 - 0.5 + (0.1 if c % 2 else 0)
                ctr = (t * 3.6, (-1 if side == 0 else 1) * 1.8, 0.5 + c * 0.4) if side < 2 else ((-1 if side == 2 else 1) * 1.8, t * 3.6, 0.5 + c * 0.4)
                p.stone(ctr, (0.62, 0.45, 0.4), rng=k.rng)
    p.box((0, 0, 0.95), (3.4, 3.4, 1.2), jit((0.4, 0.39, 0.36), 0.03, k.rng))
    k.add(p)
    base, deck = 1.55, 7.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            p = k.piece("log")
            p.log((sx * 1.5, sy * 1.5, base), (sx * 1.05, sy * 1.05, deck + 2.6), 0.15, rng=k.rng)
            k.add(p)
    for lvl in (base + 2.6, base + 5.0):
        for side in range(4):
            p = k.piece("log")
            a = [(-1.4, -1.4), (1.4, -1.4), (1.4, 1.4), (-1.4, 1.4)][side]
            b = [(1.4, -1.4), (1.4, 1.4), (-1.4, 1.4), (-1.4, -1.4)][side]
            f = 1.0 - (lvl - base) / (deck + 2.6 - base) * 0.3
            p.log((a[0] * f, a[1] * f, lvl), (b[0] * f, b[1] * f, lvl), 0.08, rng=k.rng)
            p.log((a[0] * f, a[1] * f, lvl - 2.3), (b[0] * f, b[1] * f, lvl), 0.06, rng=k.rng)
            k.add(p)
    p = k.piece("plank")
    for i in range(12):
        p.box((-1.5 + (i + 0.5) * 3.0 / 12, 0, deck), (3.0 / 12 - 0.01, 3.2, 0.08), jit(PLANK, 0.08, k.rng))
    k.add(p)
    trim = k.paint[0]
    for side in range(4):
        p = k.piece("plank", "rail")
        for i in range(9):
            t = -1.4 + i * 0.35
            q = (t, (-1 if side == 0 else 1) * 1.55, deck + 0.45) if side < 2 else ((-1 if side == 2 else 1) * 1.55, t, deck + 0.45)
            p.box(q, (0.04, 0.04, 0.8), jit(trim, 0.04, k.rng))
        q = (0, (-1 if side == 0 else 1) * 1.55, deck + 0.85) if side < 2 else ((-1 if side == 2 else 1) * 1.55, 0, deck + 0.85)
        p.box(q, (3.1, 0.07, 0.06) if side < 2 else (0.07, 3.1, 0.06), jit(trim, 0.03, k.rng))
        k.add(p)
    p = k.piece("log")
    p.log((-1.2, 0, deck + 2.2), (1.2, 0, deck + 2.2), 0.1, rng=k.rng)
    k.add(p)
    p = k.piece("stone", "bell")
    bronze = (0.5, 0.38, 0.18)
    p.log((0, 0, deck + 1.25), (0, 0, deck + 2.05), 0.36, color=bronze, end=bronze, taper=0.9, segs=16, jitter=0.0, bow=0.0)
    p.log((0, 0, deck + 1.18), (0, 0, deck + 1.3), 0.4, color=bronze, end=bronze, taper=0.0, segs=16, jitter=0.0, bow=0.0)
    p.box((0, 0, deck + 1.1), (0.06, 0.06, 0.25), IRON)
    k.add(p)
    roof_base = deck + 2.6
    for side in range(4):
        p = k.piece("shingle")
        ang = side * math.pi * 0.5
        out = Vector((math.sin(ang), -math.cos(ang), 0))
        across = Vector((math.cos(ang), math.sin(ang), 0))
        slope = math.atan2(2.4, 1.8)
        down = (out * math.cos(slope) + Vector((0, 0, -math.sin(slope)))).normalized()
        nrm = (out * math.sin(slope) + Vector((0, 0, math.cos(slope)))).normalized()
        apex = Vector((0, 0, roof_base + 2.4))
        L = 1.8 / math.cos(slope) + 0.4
        rows = 10
        for r in range(rows):
            v = (r + 0.5) * L / rows
            width = 2 * (v * math.cos(slope)) + 0.3
            x = -width * 0.5
            while x < width * 0.5:
                sw = min(k.rng.uniform(0.2, 0.3), width * 0.5 - x + 0.01)
                p.obox(apex + down * v + nrm * 0.03 + across * (x + sw * 0.5), across, down, nrm, (sw - 0.012, L / rows * 1.5, 0.03), jit(SHINGLE, 0.12, k.rng))
                x += sw
        k.add(p)
    p = k.piece("wood", "finial")
    p.log((0, 0, roof_base + 2.3), (0, 0, roof_base + 2.8), 0.05, color=trim, end=trim, taper=0.3)
    p.stone((0, 0, roof_base + 2.9), (0.2, 0.2, 0.2), color=trim, rng=k.rng)
    k.add(p)
    p = k.piece("wood")
    for sx in (-0.25, 0.25):
        p.log((sx, -2.3, 0.3), (sx, -1.6, deck + 0.4), 0.04, rng=k.rng)
    n = int(deck / 0.35)
    for i in range(n):
        t = (i + 0.5) / n
        p.log((-0.27, -2.3 + 0.7 * t, 0.3 + deck * t), (0.27, -2.3 + 0.7 * t, 0.3 + deck * t), 0.03, segs=6, rng=k.rng)
    k.add(p)
    k.finish()


BUILDERS = {
    "ev": ev, "ambar": ambar, "kisla": kisla, "fener": fener, "kuyu": kuyu, "kule": kule, "ahir": ahir,
    "meydan": meydan, "cankulesi": cankulesi,
    "oduncu": kesim, "tasci": tas_ocagi, "toplayici": toplayici, "ormanci": ormanci,
    "arabaci": lambda: shed("arabaci", 6.0, 5.0, _cart_props),
}


# --- previews -------------------------------------------------------------------------------------

def render(kind):
    import bpy as b
    scene = b.context.scene
    for ob in list(scene.objects):
        if ob.type in ("CAMERA", "LIGHT"):
            b.data.objects.remove(ob, do_unlink=True)
    cam_data = b.data.cameras.new("cam")
    cam = b.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    size = 12.0 if kind not in ("kule",) else 18.0
    cam.location = (size * 0.9, -size * 1.1, size * 0.62)
    direction = Vector((0, 0, 2.2 if kind != "kule" else 6.0)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 40
    scene.camera = cam
    sun_d = b.data.lights.new("sun", "SUN")
    sun_d.energy = 4.0
    sun = b.data.objects.new("sun", sun_d)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    scene.collection.objects.link(sun)
    world = scene.world or b.data.worlds.new("w")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.55, 0.62, 0.7, 1)
        bg.inputs[1].default_value = 0.9
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 700
    os.makedirs(os.path.join(OUT, "previews"), exist_ok=True)
    scene.render.filepath = os.path.join(OUT, "previews", kind + ".png")
    b.ops.render.render(write_still=True)


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
        if "--render" in argv:
            render(kind)


main()
