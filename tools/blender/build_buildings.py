"""Builds the timber town's buildings, each one a GLB of separate pieces the game can burn and bring
down one by one (scripts/building.gd):

    blender --background --factory-startup --python tools/blender/build_buildings.py [-- --render] [-- --only=ev,ambar] [-- --raw]

(--raw: without the finish, the bevels, baked occlusion and grime at the foot: a quick look at shapes.)

Every piece is its own object, its origin at the middle of its bounds, named "<stuff>-<n>" or
"<stuff>-<tag>-<n>": the stuff (scripts/building_defs.gd STUFF: log, plank, dark, stone, shingle,
window, wood, thatch...) decides how it burns and breaks; a tag marks a piece the game looks for
("plinth", "chimneytop"). Colours are vertex colours (the game multiplies them into the stuff's own).

Blender: +X right, -Y the front (the door; Godot +Z), +Z up. The plinth's top is at 0.35 m and the
floor at 0.47; the ground is at 0 (the plinth goes 3.5 m down to take up a slope).

Output: assets/buildings/<kind>.glb, assets/buildings/previews/<kind>.png (--render).

  ev         a log cabin: saddle-notched log walls, log gables, purlins, a shingled roof, a fieldstone
             chimney, framed windows with shutters, a plank door, a porch, a woodpile
  ambar      the store: a red barn of boards and battens under a gambrel roof, wide double doors, a hay
             door and hoist in the gable, a loading platform, crates, barrels, sacks
  kule       the lookout: a timber tower on a stone base, braced, a ladder, a railed platform, a roof
  fener      a lamp post: a squared post, an iron arm, a glazed lantern
  kuyu       a well: a fieldstone ring, a windlass, a little shingled roof, a bucket
  oduncu     the felling camp's yard: a sawhorse with a log and a frame saw, a deck of raw logs,
             sawdust, a lean-to with a tool rack and a grindstone
  tasci      the stone yard: a dressing bench with mallet and chisel, a tripod derrick lifting a
             block, rough blocks heaped, dressed ones stacked, rubble
  toplayici  the gatherers' yard: a birch-bark cone hut, drying racks hung with berries, a sorting
             table, baskets
  silahlik   the armoury: a grey log blockhouse, its upper storey jutting out over the lower,
             loopholes, a hipped roof, a flagstaff
  okuma      the reading room: a white clapboard schoolhouse, tall shuttered windows, a slate-grey
             roof, a belfry with its bell
  sifaci     the feldsher's: a low hut of whitewashed logs under a turf roof, a herb garden
  istasyon   the station: an ochre clapboard depot, a hipped green iron roof on carved brackets, a
             clock and a bell, the platform and its canopy
  demirci    the smithy: rubble-stone walls open at the front, a sooty iron roof, the forge's stack
             up through it
  ev_oda     a house's back room (the game adds it to an "ev" when it's made bigger): log walls on
             three sides against the house's back wall, a shuttered window, a shingled lean-to
             roof running up under the house's eaves, boarded gable triangles
  ev_soba    a house's brick stove flue (added with the stove): whitewashed brick courses up
             through the roof, a corbelled head and a brick cap
  camur      the mud pit: a plank-framed pit of wet mud with a spade in it, a moulding table with
             brick moulds and fresh bricks, a thatched drying shelter over a straw-strewn floor,
             a heap of straw, a water barrel, puddles on the trodden mud
  arabaci    the cartwright's shed: a two-wheeled cart tipped on its shafts, a wheel being built on its
             stool, spares on the wall, a bench with drawknife, adze and mallet, a shaving horse, spokes
             and felloes stacked, a grindstone, the tyring plate with embers and a tyre, a plank rack
  hapishane  the lock-up: rubble-stone walls, dressed quoins, a hipped iron roof, barred windows, an
             iron-banded padlocked door with a judas hatch, a sign, a lantern, the guard's bench
"""

import math
import os
import random
import sys
import zlib

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "buildings")

FLOOR = 0.47
YARD_FLOOR = 0.37 # (a yard's ground is at 0.35: what stands on it, there)
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
TUFT = (0.33, 0.4, 0.17) # grass grown up at a wall's foot
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

    def stone(self, center, size, color=STONE, rng=random, subdiv=1):
        """A fieldstone: a lumpy, flattened ball (a sack, at subdiv 2)."""
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=0.5)
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
        if self.tag != "ground": # (every closed shape's faces turned outward, whichever way its axes ran)
            bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
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
        self.rng = random.Random(zlib.crc32(kind.encode()) & 0xFFFF) # (the same building every run)
        self.moss_seed = self.rng.uniform(0.0, 100.0)
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
        if FINISH["bevel"]:
            for ob in self.objects:
                if ob.name.split("-")[0] in BEVELLED:
                    _bevel(ob.data)
        if FINISH["ao"]:
            _bake_ao(self.objects)
        if FINISH["grime"]:
            for ob in self.objects:
                _grime(ob)
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



# --- the finish: edges eased, the shade of the corners, the dirt at the foot ------------------------
# Every piece is a vertex-coloured mesh with no texture, so what makes it read as built and lived in
# is put into its colours here, once it's all assembled: sawn edges bevelled a centimetre so they
# catch the light, the occlusion (under the eaves, in the corners, between the logs, at the foot of
# the walls on the ground) baked into the vertices by Cycles, and the splash of mud and grime that
# darkens every wall's foot. (--raw leaves them off: a quick look at shapes.)

FINISH = {"bevel": True, "ao": True, "grime": True}
BEVELLED = ("plank", "dark", "wood", "plaster", "cloth")
AO_DISTANCE = 1.1 # m: how far a thing shades what's near it
AO_STRENGTH = 0.72
GRIME = (0.2, 0.16, 0.11)
GRIME_TOP = 0.95 # m above the ground the splash reaches


def _bevel(me, width=0.012):
    """Hard edges (between faces at more than ~70 degrees) bevelled `width`, a face of their own."""
    bm = bmesh.new()
    bm.from_mesh(me)
    if len(bm.verts) < 40000:
        edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > 1.2]
        if edges:
            bmesh.ops.bevel(bm, geom=edges, offset=width, offset_type="OFFSET", segments=1, profile=0.5,
                            affect="EDGES", clamp_overlap=True)
    bm.to_mesh(me)
    bm.free()


def _colors(me):
    import numpy as np
    a = me.color_attributes["Col"]
    buf = np.empty(len(a.data) * 4, dtype=np.float32)
    a.data.foreach_get("color", buf)
    return a, buf.reshape(-1, 4)


def _bake_ao(objects, rays=20):
    """The ambient occlusion: from each corner of each face (drawn in toward the face's middle, so a
    corner tucked under the next shingle or log doesn't read its crevice for the whole face), rays
    over the hemisphere it faces, against everything in the building and a ground under it; what's
    hit within AO_DISTANCE shades it, the nearer the more. Multiplied into the piece's own colours."""
    import numpy as np
    from mathutils.bvhtree import BVHTree
    rng = random.Random(7)
    world = bmesh.new()
    for ob in objects:
        world.from_mesh(ob.data)
    g = [world.verts.new(v) for v in ((-40, -40, 0), (40, -40, 0), (40, 40, 0), (-40, 40, 0))]
    world.faces.new(g)
    tree = BVHTree.FromBMesh(world)
    world.free()
    # cosine-weighted directions over the hemisphere about +Z
    base = []
    for i in range(rays):
        u, v = (i + 0.5) / rays, (i * 0.618034) % 1.0
        r, a = math.sqrt(u), v * math.tau
        base.append(Vector((r * math.cos(a), r * math.sin(a), math.sqrt(max(0.0, 1.0 - u)))))
    seen = []
    for ob in objects:
        me = ob.data
        if not me.color_attributes.get("Col") or ob.name.startswith("window"):
            continue
        col, cbuf = _colors(me)
        verts = me.vertices
        occ = np.ones(len(me.loops), dtype=np.float32)
        for poly in me.polygons:
            n = poly.normal
            c = poly.center
            rot = n.to_track_quat("Z", "Y") @ Quaternion((0, 0, 1), rng.uniform(0, math.tau))
            dirs = [rot @ d for d in base]
            for li in poly.loop_indices:
                q = verts[me.loops[li].vertex_index].co
                if q.z < -0.05:
                    continue
                p = q.lerp(c, 0.45) + n * 0.012
                shade = 0.0
                for d in dirs:
                    hit = tree.ray_cast(p, d, AO_DISTANCE)
                    if hit[0] is not None:
                        shade += 1.0 - (hit[3] / AO_DISTANCE) * 0.6
                occ[li] = 1.0 - shade / rays
        seen.append(occ)
        k = 1.0 - AO_STRENGTH * (1.0 - occ)
        cbuf[:, :3] *= k[:, None]
        col.data.foreach_set("color", cbuf.ravel())
    if seen:
        allo = np.concatenate(seen)
        print("ao: %d corners, mean %.2f, %.0f%% under 0.6" % (len(allo), allo.mean(), (allo < 0.6).mean() * 100))


def _grime(ob):
    """Mud splashed up the foot of whatever stands on the ground: the vertices darkened toward a muddy
    brown the lower they are (not on faces turned up to the sky, which the rain washes)."""
    import numpy as np
    me = ob.data
    if not me.color_attributes.get("Col") or ob.name.startswith("window"):
        return
    col, cbuf = _colors(me)
    n = len(me.loops)
    vi = np.empty(n, dtype=np.int32)
    me.loops.foreach_get("vertex_index", vi)
    co = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    z = co.reshape(-1, 3)[vi, 2]
    nz = np.empty(n * 3, dtype=np.float32)
    me.corner_normals.foreach_get("vector", nz)
    up = nz.reshape(-1, 3)[:, 2]
    g = np.clip(1.0 - z / GRIME_TOP, 0.0, 1.0) ** 1.6 * 0.42 * np.clip(1.0 - up, 0.2, 1.0)
    g[z < -0.05] = 0.0 # (underground: nobody sees it)
    for i in range(3):
        cbuf[:, i] = cbuf[:, i] * (1.0 - g) + GRIME[i] * g
    col.data.foreach_set("color", cbuf.ravel())


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
        # grass and weeds grown up against the stones (none trodden away before the door)
        for i in range(int(along / 0.3)):
            t = k.rng.uniform(-0.5, 0.5)
            out = k.rng.uniform(0.25, 0.55)
            if side < 2:
                if side == 0 and abs(t * along) < 1.0:
                    continue
                c = (t * (w + 0.4), (-1 if side == 0 else 1) * (d * 0.5 + out), -0.04)
            else:
                c = ((-1 if side == 2 else 1) * (w * 0.5 + out), t * (d + 0.4), -0.04)
            g = jit(TUFT, 0.12, k.rng)
            if k.rng.random() < 0.3:
                g = (g[0] * 1.3, g[1] * 1.12, g[2] * 0.8) # (gone to seed, yellowing)
            p.stone(c, (k.rng.uniform(0.22, 0.4), k.rng.uniform(0.2, 0.34), k.rng.uniform(0.22, 0.36)), color=g, rng=k.rng)
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


def log_walls(k, w, d, courses, openings, dia=0.3, color=BARK, end=END_GRAIN, base=None):
    """Log walls, course on course, saddle-notched: the side walls' logs half a log higher, every
    log's ends past the corners. `openings`: (wall, centre along it, width, bottom, top) with wall
    "front" (-Y), "back", "left" (-X), "right"; bottom and top above the floor (`base`, the floor's
    height unless given: an upper storey's). A log through an opening is cut either side of it;
    `color` and `end` the bark's and the sawn ends' (whitewashed, weathered grey)."""
    base = FLOOR if base is None else base
    hx, hy = w * 0.5 - dia * 0.5, d * 0.5 - dia * 0.5
    top = base
    for c in range(courses):
        for wall in ("front", "back", "left", "right"):
            side = wall in ("left", "right")
            z = base + dia * 0.5 + c * dia + (dia * 0.5 if side else 0.0)
            length = (d if side else w) + 0.55
            holes = []
            for ow, oc, owid, ob, ot in openings:
                if ow == wall and base + ob - dia * 0.4 < z < base + ot + dia * 0.4:
                    holes.append((oc - owid * 0.5, oc + owid * 0.5))
            for s0, s1 in _cut((-length * 0.5, length * 0.5), holes):
                if side:
                    x = (-1 if wall == "left" else 1) * hx
                    a, b = (x, s0, z), (x, s1, z)
                else:
                    y = (-1 if wall == "front" else 1) * hy
                    a, b = (s0, y, z), (s1, y, z)
                p = k.piece("log")
                p.log(a, b, dia * 0.5, color=color, end=end, rng=k.rng, moss=(0.5 if c < 2 else 0.05) if color == BARK else 0.0)
                # (the chinking between it and the log below, a pale line of moss and clay)
                if c > 0:
                    ax = Vector(b) - Vector(a)
                    mid = (Vector(a) + Vector(b)) * 0.5 - Vector((0, 0, dia * 0.47))
                    p.obox(mid, ax.normalized(), Vector((0, 0, 1)).cross(ax.normalized()), (0, 0, 1), (ax.length - 0.3, dia * 0.55, 0.05), jit(CHINK, 0.05, k.rng))
                k.add(p)
            top = max(top, z + dia * 0.5)
    return top


def log_gables(k, w, d, wall_top, rise, dia=0.3, ridge_axis="x", color=BARK, end=END_GRAIN):
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
            p.log((x, -span, z), (x, span, z), dia * 0.5, color=color, end=end, rng=k.rng)
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


def shingle_colour(k, base, x, frac, side=0, moss=1.0):
    """A shingle's colour: a little off the roof's own, now and then an old one gone darker, and moss
    where a roof stays wettest: toward the eave (`frac` of the way down), in drifts along it rather
    than a scatter, more on the back slope (`side` > 0) than the front."""
    sc = jit(base, 0.055, k.rng)
    if k.rng.random() < 0.05:
        sc = (sc[0] * 0.84, sc[1] * 0.83, sc[2] * 0.82)
    if moss > 0.0:
        drift = 0.5 + 0.5 * math.sin(x * 1.3 + k.moss_seed) * math.sin(x * 0.47 + frac * 3.1 + k.moss_seed * 1.7)
        wet = max(0.0, (frac - 0.45) / 0.55)
        amt = wet * drift * (1.3 if side > 0 else 0.75) * moss
        if amt > 0.3 + k.rng.random() * 0.35:
            m = jit(MOSS, 0.08, k.rng)
            t = min(0.7, 0.35 + amt * 0.5)
            sc = (sc[0] * (1 - t) + m[0] * t, sc[1] * (1 - t) + m[1] * t, sc[2] * (1 - t) + m[2] * t)
    return sc


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
                    sc = shingle_colour(k, color, x, vv / length, side)
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
            p.obox(top + down * ((r + 0.5) * run / rows) + nrm * 0.05 + Vector((x + sw * 0.5, 0, 0)), (1, 0, 0), down, nrm, (sw - 0.015, 0.34, 0.025), shingle_colour(k, SHINGLE, x, (r + 0.5) / rows, 0, 0.6))
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

def cabin(kind, w, d, courses, rise, door_w=1.0, windows=(), porch_on=True, chimney_at=None, extra=None, double_door=False, paint=None):
    k = Kit(kind)
    k.paint = paint or k.rng.choice(PAINTS)
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


def _arms_extra(k, w, d):
    # the armoury: a stout iron-banded door's look, a rack of rifles under the eave, ammunition boxes,
    # a target board out at the side for practice
    p = k.piece("dark")
    p.box((-w * 0.5 + 1.1, -d * 0.5 - 0.25, 1.55), (1.3, 0.1, 0.08), DARK)
    for i in range(4):
        p.obox((-w * 0.5 + 0.65 + i * 0.3, -d * 0.5 - 0.3, 1.2), (0, 0, 1), (1, 0, 0), (0, 1, 0), (1.15, 0.04, 0.05), (0.18, 0.18, 0.19))
    for z in (0.9, 1.9):
        p.box((0, -d * 0.5 - 0.05, z), (1.05, 0.04, 0.07), (0.2, 0.2, 0.21))
    k.add(p)
    for i, (x, y, z) in enumerate([(w * 0.5 - 0.7, -d * 0.5 - 0.8, 0.0), (w * 0.5 - 1.25, -d * 0.5 - 0.75, 0.0), (w * 0.5 - 0.95, -d * 0.5 - 0.78, 0.46)]):
        crate(k, x, y, z, 0.46)
    p = k.piece("plank", "target")
    tx = w * 0.5 + 2.6
    for sx in (-0.45, 0.45):
        p.box((tx + sx, 0.0, 0.6), (0.08, 0.08, 1.4), DARK)
    p.box((tx, -0.05, 1.05), (1.1, 0.06, 1.0), jit(PLANK, 0.06, k.rng))
    for r, c in ((0.42, (0.85, 0.82, 0.74)), (0.3, (0.12, 0.11, 0.1)), (0.18, (0.85, 0.82, 0.74)), (0.07, (0.62, 0.15, 0.1))):
        p.obox((tx, -0.09 - (0.42 - r) * 0.02, 1.05), (1, 0, 0), (0, 0, 1), (0, -1, 0), (r * 2, r * 2, 0.01), c)
    k.add(p)


# The house these are made for: ev() below (6 x 5, 8 courses, a 1.9 m rise; its trim and shutters
# came out light blue and white).
EV_W, EV_D = 6.0, 5.0
EV_PAINT = PAINTS[4]
ODA_W, ODA_D = 3.3, 3.2 # (scripts/building_defs.gd ANNEX, give or take the logs' ends)
ODA_X = -EV_W * 0.5 + ODA_W * 0.5 # its middle: flush with the house's left wall
ODA_Y = EV_D * 0.5 + ODA_D * 0.5 # behind the house's back wall
WHITEWASH = (0.9, 0.88, 0.82)


def _shift(k, first, by):
    """The objects added to `k` since `first` moved by `by` (built round the origin, put in place)."""
    for ob in k.objects[first:]:
        ob.location = Vector(ob.location) + Vector(by)


def ev_oda():
    """A house's back room, built round its own middle and then set behind the house: log walls on
    the left, right and back (the house's back wall is its fourth), a shuttered window at the back,
    a shingled lean-to roof from under the house's eaves down past its back wall, the triangles
    between the side walls and the roof boarded."""
    k = Kit("ev_oda")
    k.paint = EV_PAINT
    w, d = ODA_W, ODA_D
    plinth(k, w, d)
    floor(k, w, d)
    # (the front's the house's wall: its logs cut away whole)
    top = log_walls(k, w, d, 6, [("front", 0.0, w + 2.0, -1.0, 10.0), ("back", 0.2, 0.95, 0.85, 1.85)])
    window(k, "back", 0.2, w, d)
    # the roof: boards, then shingles in staggered courses, from the house's wall down past the back
    y0, z0 = -d * 0.5, 2.98
    y1, z1 = d * 0.5 + 0.4, 2.62
    run = Vector((0, y1 - y0, z1 - z0))
    length = run.length
    down = run.normalized()
    across = Vector((1, 0, 0))
    normal = across.cross(down).normalized()
    if normal.z < 0:
        normal = -normal
    start = Vector((0, y0, z0))
    over = 0.35
    p = k.piece("shingle")
    p.obox(start + down * length * 0.5, across, down, normal, (w + over * 2, length, 0.05), jit(PLANK, 0.05, k.rng))
    course = 0.22
    rows = int(round(length / course))
    for r in range(rows):
        vv = (r + 0.5) * length / rows
        x = -w * 0.5 - over + (0.15 if r % 2 else 0.0)
        while x < w * 0.5 + over - 0.05:
            sw = min(k.rng.uniform(0.22, 0.34), w * 0.5 + over - x)
            sc = shingle_colour(k, SHINGLE, x, vv / length, 1)
            tilt = Matrix.Rotation(-0.08, 3, across)
            p.obox(start + down * vv + normal * 0.057 + across * (x + sw * 0.5), across, tilt @ down, tilt @ normal, (sw - 0.015, course * 1.6, 0.025), sc)
            x += sw
    k.add(p)
    p = k.piece("dark")
    p.obox(start + down * length - normal * 0.05, across, normal, down, (w + over * 2 + 0.05, 0.22, 0.05), jit(DARK, 0.05, k.rng))
    k.add(p)
    # the gable triangles: upright boards from the side walls' top up to the roof
    for sx in (-1, 1):
        x = sx * (w * 0.5 - 0.15)
        p = k.piece("plank", "gable")
        n = 9
        for i in range(n):
            y = -d * 0.5 + (i + 0.5) * d / n
            roof_z = z0 + (y - y0) / (y1 - y0) * (z1 - z0) - 0.03
            h = roof_z - top
            if h > 0.04:
                p.box((x, y, top + h * 0.5), (0.05, d / n - 0.015, h), jit(PLANK, 0.08, k.rng))
        k.add(p)
    _shift(k, 0, (ODA_X, ODA_Y, 0.0))
    k.finish()


def ev_soba():
    """The brick stove's flue: up through the house's roof left of the ridge, whitewashed brick in
    courses (the bricks showing under the wash), a corbelled head and a brick cap over the smoke."""
    k = Kit("ev_soba")
    x, y = -1.4, -0.35
    base, head = 4.0, 5.9
    size = 0.64
    z = base
    c = 0
    while z < head:
        p = k.piece("plaster", "flue")
        p.box((x, y, z + 0.06), (size - 0.02, size - 0.02, 0.12), jit(WHITEWASH, 0.03, k.rng))
        # (the bricks of this course, a little proud of the wash, laid on alternate sides)
        for side in range(4):
            along = Vector((1, 0, 0)) if side < 2 else Vector((0, 1, 0))
            out = Vector((0, 1 if side == 0 else -1, 0)) if side < 2 else Vector((1 if side == 2 else -1, 0, 0))
            off = 0.08 if (c + side) % 2 else -0.08
            for b in (-1, 0, 1):
                ctr = Vector((x, y, z + 0.06)) + out * (size * 0.5 - 0.005) + along * (b * 0.22 + off)
                if abs(b * 0.22 + off) > size * 0.5 - 0.1:
                    continue
                col = jit(WHITEWASH, 0.05, k.rng)
                if k.rng.random() < 0.18: # (where the wash has flaked: the brick under it)
                    col = jit(CLAY, 0.08, k.rng)
                p.obox(ctr, along, out, (0, 0, 1), (0.2, 0.012, 0.1), col)
        k.add(p)
        z += 0.12
        c += 1
    # the head: two courses stepped out, then the cap on four brick legs
    p = k.piece("plaster", "chimneytop")
    p.box((x, y, head + 0.06), (size + 0.12, size + 0.12, 0.12), jit(WHITEWASH, 0.03, k.rng))
    p.box((x, y, head + 0.18), (size + 0.2, size + 0.2, 0.12), jit(WHITEWASH, 0.03, k.rng))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((x + sx * 0.22, y + sy * 0.22, head + 0.36), (0.14, 0.14, 0.24), jit(CLAY, 0.06, k.rng))
    p.box((x, y, head + 0.52), (size + 0.1, size + 0.1, 0.08), jit((0.42, 0.4, 0.37), 0.05, k.rng))
    k.add(p)
    k.finish()


def ev():
    cabin("ev", 6.0, 5.0, 8, 1.9, 1.0, windows=[("front", -1.8), ("left", 0.0), ("back", 1.0)], chimney_at=(3.0 + 0.85, 0.8), extra=_house_extra, paint=EV_PAINT)


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
                p.obox(apex + down * v + nrm * 0.03 + across * (x + sw * 0.5), across, down, nrm, (sw - 0.012, L / rows * 1.5, 0.03), shingle_colour(k, SHINGLE, x, (r + 0.5) / rows, 0, 0.6))
                x += sw
        k.add(p)
    k.finish()


def shed(kind, w, d, props, roof=SHINGLE):
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
                p.obox(top + down * (v0 + (r + 0.5) * (v1 - v0) / rows) + nrm * 0.05 + Vector((x + sw * 0.5, 0, 0)), (1, 0, 0), down, nrm, (sw - 0.015, 0.34, 0.025), shingle_colour(k, roof, x, (r + 0.5) / rows, 0, 0.6))
                x += sw
        k.add(p)
    props(k, w, d)
    k.finish()


FELLOE = (0.55, 0.4, 0.25)
ASH = (0.7, 0.58, 0.4)
CHAR = (0.12, 0.1, 0.09)
EMBER = (1.0, 0.42, 0.1)


def _axes(axis):
    a = Vector(axis).normalized()
    u = a.cross(Vector((0, 0, 1)))
    if u.length < 0.1:
        u = a.cross(Vector((1, 0, 0)))
    u.normalize()
    return a, u, a.cross(u).normalized()


def _ring(p, c, axis, radius, thick, width, color, n=18, frac=1.0, start=0.0, rng=None):
    """A ring of `n` short blocks round `axis` (a felloe, a tyre, a hoop); only `frac` of it."""
    a, u, v = _axes(axis)
    c = Vector(c)
    for i in range(int(round(n * frac))):
        t = start + (i + 0.5) / n * math.tau
        rad = u * math.cos(t) + v * math.sin(t)
        tan = -u * math.sin(t) + v * math.cos(t)
        col = jit(color, 0.05, rng) if rng else color
        p.obox(c + rad * radius, tan, a, rad, (math.tau * radius / n * 1.06, width, thick), col)


def cart_wheel(p, c, axis, r, spokes=12, felloes=1.0, tyre=True, rng=random):
    """A wooden cart wheel: a turned nave banded in iron, its spokes, the felloes round them (only
    `felloes` of the round, for one being built), an iron tyre shrunk on."""
    a, u, v = _axes(axis)
    c = Vector(c)
    cyl(p, c - a * 0.16, c + a * 0.16, 0.1, jit(FELLOE, 0.05, rng), segs=12, taper=0.0)
    for s in (-1, 1):
        cyl(p, c + a * (s * 0.15), c + a * (s * 0.12), 0.11, IRON, segs=12)
    cyl(p, c - a * 0.2, c + a * 0.2, 0.035, IRON, segs=8) # (the axle box)
    rin = r - 0.025 - 0.075 # (the felloes' inside)
    for i in range(spokes):
        t = i / spokes * math.tau
        rad = u * math.cos(t) + v * math.sin(t)
        tan = -u * math.sin(t) + v * math.cos(t)
        ln = rin + 0.02 - 0.08
        dish = a * (0.012 if i % 2 else -0.012)
        p.obox(c + rad * (0.08 + ln * 0.5) + dish, tan, a, rad, (0.04, 0.05, ln), jit(ASH, 0.06, rng))
    _ring(p, c, a, r - 0.025 - 0.0375, 0.075, 0.07, FELLOE, n=24, frac=felloes, rng=rng)
    if tyre:
        _ring(p, c, a, r - 0.0125, 0.025, 0.075, IRON, n=28)


def _place(m, at):
    return m @ Vector(at)


def _cart(k, x, y, rng):
    """A two-wheeled cart standing tipped forward, its shafts on a trestle: a plank bed on two side
    beams that run on forward into the shafts, sideboards held by stakes, a tailboard, the axle under
    it all, the wheels on its ends ("wheel" pieces)."""
    r = 0.6
    ax_z = FLOOR + r
    rest = FLOOR + 0.5 # (the trestle's top)
    L = 2.3 # (the shafts' reach ahead of the axle)
    tip_z = 0.18
    # tip forward till the shafts' undersides lie on the trestle at L - 0.2 ahead
    want = rest - ax_z
    reach = L - 0.25
    lo, hi = 0.0, 0.8
    for _ in range(40):
        phi = (lo + hi) * 0.5
        if -reach * math.sin(phi) + (tip_z - 0.045) * math.cos(phi) > want:
            lo = phi
        else:
            hi = phi
    m = Matrix.Translation((x, y, ax_z)) @ Matrix.Rotation(phi, 4, "X")
    rot = m.to_3x3()
    X, Y, Z = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0)), rot @ Vector((0, 0, 1))

    def bx(p, at, size, col):
        p.obox(m @ Vector(at), X, Y, Z, size, col)

    p = k.piece("plank", "cart")
    # the axle-tree and the bolster on it
    bx(p, (0, 0, 0.0), (1.44, 0.11, 0.11), jit(DARK, 0.05, rng))
    bx(p, (0, 0, 0.1), (1.12, 0.14, 0.1), jit(DARK, 0.05, rng))
    for sx in (-1, 1):
        # the side beams, running on forward into the shafts, which close in toward their tips
        bx(p, (sx * 0.5, 0.15, 0.2), (0.09, 1.9, 0.1), jit(DARK, 0.05, rng))
        a = m @ Vector((sx * 0.5, -0.75, 0.2))
        b = m @ Vector((sx * 0.36, -L, 0.18))
        p.log(a, b, 0.045, color=jit(PLANK, 0.06, rng), end=END_GRAIN, rng=rng, taper=0.15, jitter=0.02)
        bx(p, (sx * 0.36, -L + 0.12, 0.18), (0.06, 0.08, 0.1), IRON) # (the tug iron)
    # the bed
    for i in range(6):
        bx(p, (0, -0.75 + (i + 0.5) * 1.8 / 6, 0.28), (1.1, 1.8 / 6 - 0.012, 0.05), jit(PLANK, 0.08, rng))
    # sideboards, two planks a side, held by stakes in iron staples; the front and the tailboard
    stakes = (-0.7, -0.2, 0.3, 0.85)
    for sx in (-1, 1):
        for zz in (0.42, 0.62):
            bx(p, (sx * 0.58, 0.15, zz), (0.04, 1.84, 0.17), jit(PLANK, 0.08, rng))
        for sy in stakes:
            bx(p, (sx * 0.63, sy, 0.48), (0.05, 0.05, 0.62), jit(DARK, 0.06, rng))
            bx(p, (sx * 0.62, sy, 0.24), (0.07, 0.09, 0.05), IRON)
    for sy in (-0.77, 1.07):
        for zz in (0.42, 0.62):
            bx(p, (0, sy, zz), (1.12, 0.04, 0.17), jit(PLANK, 0.08, rng))
    bx(p, (0, 1.1, 0.52), (0.04, 0.03, 0.34), IRON) # (the tailboard's pin)
    # a crossbar between the shafts, part way, and a sack and some straw in the bed
    bx(p, (0, -1.1, 0.2), (0.84, 0.06, 0.06), jit(DARK, 0.05, rng))
    k.add(p)
    p = k.piece("cloth", "sack")
    p.stone(m @ Vector((0.2, 0.55, 0.42)), (0.5, 0.35, 0.26), color=SACK, rng=rng, subdiv=2)
    k.add(p)
    for sx in (-1, 1):
        p = k.piece("dark", "wheel")
        cart_wheel(p, (x + sx * 0.74, y, ax_z), (1, 0, 0), r, rng=rng)
        k.add(p)
    # the trestle under the shafts
    ty = (m @ Vector((0, -reach, 0))).y
    p = k.piece("wood", "trestle")
    p.box((x, ty, rest - 0.04), (1.0, 0.1, 0.08), jit(PLANK, 0.06, rng))
    for sx in (-0.4, 0.4):
        for sy in (-1, 1):
            p.log((x + sx, ty + sy * 0.22, FLOOR), (x + sx, ty, rest - 0.06), 0.035, color=DARK, rng=rng, taper=0.0, bow=0.0)
    k.add(p)


def _cart_props(k, w, d):
    """The cartwright's shop: a cart in for mending; a wheel being built on its stool, spares leant on
    the back wall; a bench with the drawknife, adze and mallet on it, tools hung over it; a shaving
    horse; felloes and spokes stacked; a grindstone; the tyring plate with a ring of embers and a
    tyre on it; a rack of planks; a water barrel."""
    rng = k.rng
    _cart(k, -1.3, -0.1, rng)
    back = d * 0.5 - 0.3 # (the back wall's inside face)
    side = w * 0.5 - 0.3
    # spare wheels leant on the back wall
    for i, (x, r, lean) in enumerate(((-2.15, 0.58, 0.2), (-1.55, 0.6, 0.24), (-0.95, 0.52, 0.18))):
        up = Vector((0, math.sin(lean), math.cos(lean)))
        ctr = Vector((x, back - 0.045 - up.y * r, FLOOR + up.z * r + 0.012))
        p = k.piece("dark", "spare")
        cart_wheel(p, ctr, Vector((0, math.cos(lean), -math.sin(lean))), r, rng=rng)
        k.add(p)
    # the wheel stool and a wheel half built on it, lying flat, its nave in the stool's hole
    sx0, sy0 = 1.15, -0.3
    p = k.piece("wood", "stool")
    p.box((sx0, sy0, FLOOR + 0.42), (1.2, 0.3, 0.1), jit(PLANK, 0.06, rng))
    for dx in (-0.5, 0.5):
        for dy in (-1, 1):
            p.log((sx0 + dx, sy0 + dy * 0.2, FLOOR), (sx0 + dx, sy0 + dy * 0.1, FLOOR + 0.38), 0.035, color=DARK, rng=rng, taper=0.0, bow=0.0)
    k.add(p)
    p = k.piece("plank", "new")
    cart_wheel(p, (sx0, sy0, FLOOR + 0.63), (0, 0, 1), 0.58, felloes=0.5, tyre=False, rng=rng)
    k.add(p)
    # the bench along the right wall, the tools on it
    bx0, by0, bl = side - 0.32, 0.75, 1.8
    top = FLOOR + 0.85
    p = k.piece("plank", "bench")
    p.box((bx0, by0, top - 0.04), (0.62, bl, 0.08), jit(PLANK, 0.05, rng))
    p.box((bx0 - 0.29, by0, top - 0.14), (0.06, bl, 0.14), jit(PLANK, 0.05, rng)) # (its apron)
    for dx in (-0.25, 0.25):
        for dy in (-bl * 0.5 + 0.1, bl * 0.5 - 0.1):
            p.box((bx0 + dx, by0 + dy, FLOOR + (top - 0.08 - FLOOR) * 0.5), (0.08, 0.08, top - 0.08 - FLOOR), jit(DARK, 0.05, rng))
    p.box((bx0, by0, FLOOR + 0.2), (0.45, bl - 0.2, 0.06), jit(DARK, 0.05, rng)) # (the shelf)
    for i in range(3): # (spokes roughed out on it)
        p.box((bx0 - 0.05 + i * 0.07, by0 - 0.3 + i * 0.05, FLOOR + 0.26), (0.05, 0.55, 0.05), jit(ASH, 0.08, rng))
    k.add(p)
    p = k.piece("dark", "tools")
    z = top + 0.005
    # the drawknife: a long blade, a handle turned down at each end
    p.box((bx0 - 0.05, by0 - 0.5, z + 0.01), (0.07, 0.4, 0.015), STEEL)
    for s in (-1, 1):
        p.box((bx0 - 0.05, by0 - 0.5 + s * 0.24, z + 0.025), (0.035, 0.12, 0.035), (0.42, 0.3, 0.18))
    # the adze: a long handle, the curved blade across its end
    p.box((bx0 + 0.1, by0 + 0.1, z + 0.02), (0.035, 0.6, 0.035), (0.48, 0.35, 0.2))
    for i in range(3):
        p.obox((bx0 + 0.1 + 0.04 * (i - 1), by0 + 0.42 + 0.02 * abs(i - 1), z + 0.02), (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.05, 0.06, 0.03), STEEL)
    # the mallet
    cyl(p, (bx0 - 0.1, by0 + 0.55, z + 0.08), (bx0 + 0.08, by0 + 0.55, z + 0.08), 0.075, jit(FELLOE, 0.06, rng), segs=10)
    p.box((bx0 - 0.01, by0 + 0.75, z + 0.03), (0.035, 0.36, 0.035), (0.48, 0.35, 0.2))
    # a spokeshave and a brace
    p.box((bx0 + 0.15, by0 - 0.2, z + 0.015), (0.28, 0.04, 0.03), (0.42, 0.3, 0.18))
    p.box((bx0 + 0.15, by0 - 0.2, z + 0.035), (0.07, 0.03, 0.015), STEEL)
    k.add(p)
    # the vice's screw and chop at the bench's front end
    p = k.piece("wood", "vice")
    p.box((bx0 - 0.33, by0 - bl * 0.5 + 0.2, top - 0.2), (0.06, 0.2, 0.38), jit(DARK, 0.05, rng))
    cyl(p, (bx0 - 0.42, by0 - bl * 0.5 + 0.2, top - 0.1), (bx0 - 0.25, by0 - bl * 0.5 + 0.2, top - 0.1), 0.025, DARK, segs=8)
    p.box((bx0 - 0.43, by0 - bl * 0.5 + 0.2, top - 0.1), (0.03, 0.26, 0.03), DARK)
    k.add(p)
    # tools on pegs on the right wall over the bench: a bow saw, an auger, a square
    wx = side - 0.005
    p = k.piece("dark", "hung")
    for py in (0.25, 0.95, 1.45):
        p.box((wx - 0.06, py, FLOOR + 1.2), (0.12, 0.03, 0.03), DARK)
    for dz in (-0.22, 0.22):
        p.box((wx - 0.1, 0.25, FLOOR + 1.2 + dz), (0.03, 0.03, 0.03), DARK)
    p.box((wx - 0.1, 0.25, FLOOR + 1.2), (0.025, 0.025, 0.46), (0.48, 0.35, 0.2)) # (the saw's middle bar)
    for s in (-1, 1):
        p.box((wx - 0.1, 0.25 + s * 0.3, FLOOR + 1.2), (0.03, 0.03, 0.56), (0.48, 0.35, 0.2)) # (its cheeks)
    p.box((wx - 0.1, 0.25, FLOOR + 0.93), (0.01, 0.62, 0.04), STEEL) # (the blade)
    p.box((wx - 0.1, 0.25, FLOOR + 1.47), (0.01, 0.6, 0.01), (0.7, 0.66, 0.55)) # (the cord)
    p.box((wx - 0.1, 0.95, FLOOR + 1.1), (0.025, 0.025, 0.55), STEEL) # (the auger)
    p.box((wx - 0.1, 0.95, FLOOR + 1.2), (0.03, 0.3, 0.035), (0.48, 0.35, 0.2))
    p.box((wx - 0.1, 1.45, FLOOR + 1.05), (0.02, 0.04, 0.35), STEEL) # (the square)
    p.box((wx - 0.1, 1.55, FLOOR + 0.885), (0.02, 0.24, 0.04), STEEL)
    k.add(p)
    # the shaving horse: a bench on splayed legs, a ramp up, the swinging head on its arm
    hx0, hy0 = 0.15, -1.75
    p = k.piece("wood", "horse")
    p.box((hx0, hy0, FLOOR + 0.5), (1.5, 0.22, 0.08), jit(PLANK, 0.05, rng))
    for dx, dys in ((-0.6, (-1, 1)), (0.6, (0,))):
        for dy in dys:
            p.log((hx0 + dx * 1.12, hy0 + dy * 0.22, FLOOR), (hx0 + dx, hy0 + dy * 0.05, FLOOR + 0.47), 0.035, color=DARK, rng=rng, taper=0.0, bow=0.0)
    rmp = math.radians(22)
    p.obox((hx0 + 0.35, hy0, FLOOR + 0.54 + 0.2 * math.sin(rmp)), (math.cos(rmp), 0, math.sin(rmp)), (0, 1, 0), (-math.sin(rmp), 0, math.cos(rmp)), (0.5, 0.2, 0.05), jit(PLANK, 0.06, rng))
    p.box((hx0 + 0.55, hy0, FLOOR + 0.55), (0.06, 0.12, 0.08), jit(DARK, 0.05, rng)) # (the ramp's prop)
    p.box((hx0 + 0.55, hy0, FLOOR + 0.6), (0.07, 0.05, 0.8), jit(DARK, 0.05, rng)) # (the arm through the bench)
    p.box((hx0 + 0.55, hy0, FLOOR + 0.98), (0.12, 0.36, 0.1), jit(FELLOE, 0.05, rng)) # (the head)
    p.box((hx0 + 0.55, hy0, FLOOR + 0.24), (0.06, 0.5, 0.05), jit(DARK, 0.05, rng)) # (the treadle)
    p.box((hx0 + 0.45, hy0, FLOOR + 0.71), (0.42, 0.05, 0.05), jit(ASH, 0.06, rng)) # (a spoke held under it)
    k.add(p)
    # spokes stacked crosswise, felloes in a pile
    p = k.piece("plank", "spokes")
    sx1, sy1 = 1.45, 1.25
    for layer in range(3):
        along_x = layer % 2 == 0
        for i in range(5):
            o = -0.2 + i * 0.1
            if along_x:
                p.box((sx1, sy1 + o, FLOOR + 0.03 + layer * 0.055), (0.5, 0.05, 0.05), jit(ASH, 0.08, rng))
            else:
                p.box((sx1 + o, sy1, FLOOR + 0.03 + layer * 0.055), (0.05, 0.5, 0.05), jit(ASH, 0.08, rng))
    k.add(p)
    p = k.piece("plank", "felloes")
    for i in range(5):
        _ring(p, (0.85, 1.05 + 0.03 * (i % 2), FLOOR + 0.04 + i * 0.075), (0, 0, 1), 0.5, 0.075, 0.07, FELLOE, n=24, frac=4 / 24, start=math.pi * 0.25 + i * 0.12, rng=rng)
    k.add(p)
    # the grindstone in its frame, a trough under it, a crank
    gx, gy = 2.05, -1.75
    p = k.piece("wood", "grindframe")
    for sx in (-1, 1):
        p.box((gx + sx * 0.18, gy, FLOOR + 0.35), (0.08, 0.7, 0.08), jit(DARK, 0.05, rng))
        for sy in (-1, 1):
            p.box((gx + sx * 0.18, gy + sy * 0.3, FLOOR + 0.2), (0.08, 0.08, 0.4), jit(DARK, 0.05, rng))
        p.box((gx + sx * 0.18, gy, FLOOR + 0.5), (0.08, 0.1, 0.22), jit(DARK, 0.05, rng))
    p.box((gx, gy, FLOOR + 0.43), (0.28, 0.5, 0.08), jit(PLANK, 0.05, rng)) # (the trough)
    cyl(p, (gx - 0.3, gy, FLOOR + 0.66), (gx + 0.3, gy, FLOOR + 0.66), 0.025, IRON, segs=6) # (the spindle)
    p.box((gx + 0.3, gy, FLOOR + 0.57), (0.03, 0.03, 0.2), IRON) # (the crank)
    p.box((gx + 0.35, gy, FLOOR + 0.48), (0.1, 0.035, 0.035), (0.48, 0.35, 0.2))
    k.add(p)
    p = k.piece("stone", "grindstone")
    cyl(p, (gx - 0.06, gy, FLOOR + 0.66), (gx + 0.06, gy, FLOOR + 0.66), 0.3, (0.68, 0.62, 0.5), segs=20)
    k.add(p)
    # the tyring plate: a round of flat stones, a ring of embers on it, a tyre heating in them
    tx, ty = -0.1, 1.1
    p = k.piece("stone", "plate")
    cyl(p, (tx, ty, FLOOR - 0.02), (tx, ty, FLOOR + 0.05), 0.55, jit((0.4, 0.39, 0.36), 0.05, rng), segs=18)
    k.add(p)
    p = k.piece("window", "embers")
    _ring(p, (tx, ty, FLOOR + 0.08), (0, 0, 1), 0.42, 0.05, 0.1, EMBER, n=16, rng=rng)
    k.add(p)
    p = k.piece("dark", "tyre")
    _ring(p, (tx, ty, FLOOR + 0.14), (0, 0, 1), 0.42, 0.06, 0.03, (0.3, 0.18, 0.12), n=28)
    for i in range(10):
        a = i / 10 * math.tau
        p.box((tx + math.cos(a) * 0.3, ty + math.sin(a) * 0.3, FLOOR + 0.08), (0.12, 0.08, 0.06), CHAR, rot_z=a)
    k.add(p)
    # the plank rack against the back wall: bearers, boards stacked with sticks between
    p = k.piece("plank", "rack")
    rx, ry, rl = 0.95, back - 0.28, 1.7
    for dx in (-0.7, 0.0, 0.7):
        p.box((rx + dx, ry, FLOOR + 0.05), (0.1, 0.5, 0.1), jit(DARK, 0.05, rng))
    for layer in range(4):
        z = FLOOR + 0.13 + layer * 0.085
        for i in range(3):
            p.box((rx, ry - 0.16 + i * 0.16, z), (rl, 0.15, 0.045), jit(PLANK, 0.1, rng))
        if layer < 3:
            for dx in (-0.7, 0.0, 0.7):
                p.box((rx + dx, ry, z + 0.042), (0.04, 0.48, 0.04), jit(DARK, 0.05, rng))
    k.add(p)
    # two felloe patterns and a hub hung on the back wall over the rack
    p = k.piece("plank", "patterns")
    for py, (dx, zz) in enumerate(((-0.25, 0.62), (0.35, 0.58))):
        p.box((rx + dx, back - 0.04, FLOOR + zz + 0.1), (0.03, 0.08, 0.03), DARK)
        _ring(p, (rx + dx, back - 0.035, FLOOR + zz + 0.55), (0, 1, 0), 0.5, 0.07, 0.04, (0.66, 0.54, 0.36), n=24, frac=3 / 24, start=math.pi * 0.5 - 1.5 * math.tau / 24)
    k.add(p)
    barrel(k, -2.35, -1.9, z=FLOOR, r=0.28, h=0.75)


# --- work yards ------------------------------------------------------------------------------------

EARTH = (0.36, 0.29, 0.2)
SAWDUST = (0.86, 0.74, 0.52)


MUD = (0.25, 0.19, 0.13)
TURF = (0.24, 0.26, 0.15)
CHIPS = (0.66, 0.64, 0.6)


def yard_pad(k, w, d, top=EARTH, floor="earth"):
    """A yard's ground: the block buried under it, and on it trodden earth that runs out past its
    edge and down into the grass in a soft, ragged, muddy skirt (no hard step). `floor`: "earth",
    "sawdust" (the felling camp: sawdust and chips trodden in) or "chips" (the stone yard: stone
    chips and grit)."""
    rng = k.rng
    # (no buried block: the game lays this ground on the land as it lies, every vertex on it)
    p = k.piece("stone", "ground")
    bm = p.bm
    hw, hd = w * 0.5 + 0.1, d * 0.5 + 0.1
    spokes = 64
    rings = [0.0, 0.08, 0.16, 0.25, 0.34, 0.43, 0.52, 0.61, 0.7, 0.78, 0.86, 0.93, 1.0, 1.1, 1.22, 1.36]
    rim = [1.0 + rng.uniform(-0.06, 0.08) for _ in range(spokes)]
    rim = [(rim[i - 1] + rim[i] * 2 + rim[(i + 1) % spokes]) / 4 for i in range(spokes)]

    def radius(a):
        n = 4.0
        return (abs(math.cos(a) / hw) ** n + abs(math.sin(a) / hd) ** n) ** (-1.0 / n)

    grid = []
    for ri, t in enumerate(rings):
        row = []
        for j in range(spokes):
            a = j / spokes * math.tau
            R = radius(a)
            if t <= 1.0:
                r = R * t
                z = PLINTH_TOP + 0.03 + rng.uniform(-0.012, 0.012)
            else:
                f = (t - 1.0) / (rings[-1] - 1.0)
                r = R + f * 1.5 * rim[j]
                z = PLINTH_TOP + 0.03 - (PLINTH_TOP + 0.65) * (f ** 1.4)
            row.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
            if ri == 0:
                break
        grid.append(row)
    speck = {"sawdust": SAWDUST, "chips": CHIPS}.get(floor)

    def colour(t):
        if t > 1.0:
            f = (t - 1.0) / (rings[-1] - 1.0)
            c = tuple(MUD[i] * (1 - f) + TURF[i] * f for i in range(3))
        else:
            # trodden lighter in the middle, darker and wetter toward the edge
            c = tuple(top[i] * (1.06 - 0.16 * t) for i in range(3))
            if speck and rng.random() < (0.22 if t < 0.95 else 0.08):
                m = rng.uniform(0.15, 0.4)
                c = tuple(c[i] * (1 - m) + speck[i] * m for i in range(3))
        return jit(c, 0.05, rng)

    for ri in range(1, len(rings)):
        t = (rings[ri - 1] + rings[ri]) * 0.5
        for j in range(spokes):
            j1 = (j + 1) % spokes
            if ri == 1:
                vs = [grid[0][0], grid[1][j], grid[1][j1]]
            else:
                vs = [grid[ri - 1][j], grid[ri][j], grid[ri][j1], grid[ri - 1][j1]]
            f = bm.faces.new(vs)
            f.normal_update()
            if f.normal.z < 0:
                f.normal_flip()
            p._face_color(f, colour(t))
    k.add(p)
    # a few stones half sunk at the edge, and the floor's litter
    p = k.piece("stone", "found")
    for i in range(10):
        a = rng.uniform(0, math.tau)
        R = radius(a) * rng.uniform(0.98, 1.12)
        p.stone((math.cos(a) * R, math.sin(a) * R, PLINTH_TOP - 0.05), (0.3, 0.25, 0.16), color=jit(STONE, 0.1, rng), rng=rng)
    if floor == "chips":
        for i in range(40):
            a = rng.uniform(0, math.tau)
            R = radius(a) * math.sqrt(rng.random()) * 0.95
            s = rng.uniform(0.05, 0.12)
            p.stone((math.cos(a) * R, math.sin(a) * R, PLINTH_TOP + 0.04), (s * 1.3, s, s * 0.5), color=jit(CHIPS, 0.08, rng), rng=rng)
    k.add(p)
    if floor == "sawdust":
        p = k.piece("wood")
        for i in range(30):
            a = rng.uniform(0, math.tau)
            R = radius(a) * math.sqrt(rng.random()) * 0.95
            p.box((math.cos(a) * R, math.sin(a) * R, PLINTH_TOP + 0.045), (rng.uniform(0.06, 0.16), rng.uniform(0.03, 0.06), 0.015),
                  jit(SAWDUST_C, 0.1, rng), rot_z=rng.uniform(0, math.tau))
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
            p.obox(top + down * ((r + 0.5) * run / rows) + nrm * 0.05 + Vector((x + sw * 0.5, 0, 0)), (1, 0, 0), down, nrm, (sw - 0.015, 0.34, 0.025), shingle_colour(k, SHINGLE, x, (r + 0.5) / rows, 0, 0.6))
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
    FLOOR = YARD_FLOOR # (a yard: its things on its own ground, not up on a floor)
    w, d = 7.0, 6.0
    k = Kit("oduncu")
    yard_pad(k, w, d, floor="sawdust")
    # rounds of log the sawyers sit on, an axe-chopping stump
    p = k.piece("log", "stools")
    for (x, y, h) in ((-w * 0.5 + 0.9, -d * 0.5 + 0.9, 0.45), (-w * 0.5 + 1.6, -d * 0.5 + 0.7, 0.42), (w * 0.5 - 0.9, -d * 0.5 + 0.9, 0.6)):
        p.log((x, y, PLINTH_TOP), (x, y, PLINTH_TOP + h), 0.2 if h < 0.5 else 0.28, rng=k.rng, taper=0.0)
    k.add(p)
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
    FLOOR = YARD_FLOOR # (a yard: its things on its own ground, not up on a floor)
    w, d = 7.0, 6.0
    k = Kit("tasci")
    yard_pad(k, w, d, top=(0.4, 0.36, 0.3), floor="chips")
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


def bark_hut(k, x, y, r, h, door_at=-math.pi * 0.5, base=YARD_FLOOR):
    """A conical hut of the forest's folk: a ring of poles leant together and lashed at the top, their
    ends crossed out past it, sheathed in sheets of birch bark sewn in courses, a door gap with a hide
    hung back over it, a smoke hole at the peak."""
    rng = k.rng
    apex = Vector((x, y, base + h))
    n = 14
    p = k.piece("wood", "poles")
    for i in range(n):
        a = i / n * math.tau
        foot = Vector((x + math.cos(a) * r, y + math.sin(a) * r, base - 0.1))
        tip = apex + (apex - foot).normalized() * 0.55
        p.log(foot, tip, 0.04, rng=rng, taper=0.3)
    k.add(p)
    # the bark: courses of sheets round the cone, the door gap left open
    courses = 6
    for c in range(courses):
        p = k.piece("thatch", "bark")
        t0, t1 = c / courses * 0.86, (c + 1) / courses * 0.86 + 0.03
        segs = 16
        for j in range(segs):
            a0, a1 = j / segs * math.tau, (j + 1) / segs * math.tau
            mid = (a0 + a1) * 0.5
            if c < 3 and abs((mid - door_at + math.pi) % math.tau - math.pi) < 0.4:
                continue
            def at(a, t, out=0.04):
                return Vector((x + math.cos(a) * (r * (1 - t) + out), y + math.sin(a) * (r * (1 - t) + out), base + t * h))
            col = jit(BIRCH, 0.06, rng)
            if rng.random() < 0.3:
                col = (col[0] * 0.8, col[1] * 0.75, col[2] * 0.65) # (an older sheet, gone tan)
            slab(p, [at(a0, t0), at(a1, t0), at(a1, t1), at(a0, t1)], 0.02, col)
            for q in range(2): # (the bark's dark marks)
                aa = rng.uniform(a0, a1)
                tt = rng.uniform(t0, t1)
                p.box(at(aa, tt, 0.065), (0.08, 0.08, 0.02), (0.15, 0.14, 0.12), rot_z=aa)
        # the course's seam: a withy round the cone
        k.add(p)
    p = k.piece("cloth", "hide")
    for s in (-1, 1):
        a = door_at + s * 0.42
        foot = Vector((x + math.cos(a) * (r + 0.1), y + math.sin(a) * (r + 0.1), base))
        rbox(p, foot + Vector((0, 0, 0.8)), (math.cos(a + math.pi * 0.5), math.sin(a + math.pi * 0.5), 0), (0, 0, 1), (0.45, 1.6, 0.03), jit((0.48, 0.34, 0.22), 0.05, rng))
    k.add(p)


def toplayici():
    """The gatherers' hut: a birch-bark cone hut, drying racks hung with berries, a sorting table
    out front, baskets about."""
    FLOOR = YARD_FLOOR # (a yard: its things on its own ground, not up on a floor)
    w, d = 6.0, 5.0
    k = Kit("toplayici")
    yard_pad(k, w, d)
    bark_hut(k, 1.4, 0.9, 1.25, 3.2)
    p = k.piece("wood", "rack")
    for sx in (-2.3, 0.0): # (its own posts, so it stands)
        p.log((sx, 1.6, FLOOR - 0.05), (sx, 1.6, FLOOR + 2.15), 0.05, rng=k.rng, taper=0.0)
    for z in (1.0, 1.5, 2.0):
        p.log((-2.3, 1.6, FLOOR + z), (0.0, 1.6, FLOOR + z), 0.03, rng=k.rng)
        for i in range(9):
            x = -2.1 + i * 0.25
            c = (0.45, 0.08, 0.12) if i % 3 else (0.18, 0.15, 0.35)
            p.stone((x, 1.6, FLOOR + z - 0.12), (0.12, 0.08, 0.18), color=c, rng=k.rng)
    k.add(p)
    p = k.piece("plank", "work")
    p.box((-1.0, -0.8, FLOOR + 0.75), (1.6, 0.7, 0.06), jit(PLANK, 0.05, k.rng))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((-1.0 + sx * 0.7, -0.8 + sy * 0.28, FLOOR + 0.37), (0.06, 0.06, 0.74), DARK)
    k.add(p)
    p = k.piece("thatch", "baskets")
    for i, (x, y) in enumerate([(-2.2, -1.6), (-1.6, -1.8), (0.4, -1.7), (-0.6, -0.75)]):
        z = FLOOR if i < 3 else FLOOR + 0.78
        p.log((x, y, z), (x, y, z + 0.32), 0.24, color=(0.62, 0.5, 0.3), end=(0.42, 0.1, 0.18), taper=-0.25)
    k.add(p)
    k.finish()




CLAY = (0.66, 0.54, 0.38) # a dry mud brick
WET_MUD = (0.22, 0.16, 0.1)
STRAW = (0.78, 0.66, 0.38)


def brick(p, x, y, z, rng, rot=0.0, wet=False):
    """A mud brick, its corners a little worn: dry and pale, or fresh and dark."""
    c = jit(WET_MUD if wet else CLAY, 0.1, rng)
    p.box((x, y, z + 0.06), (0.3, 0.16, 0.12), c, rot_z=rot + rng.uniform(-0.05, 0.05))


def camur_ocagi():
    """The mud pit: mud dug from the wet ground is trodden with straw in a framed pit, pressed into
    moulds on the table out front and laid out to dry under a thatched shelter at the back left; the
    straw heaped by it, a barrel of water, puddles about."""
    FLOOR = YARD_FLOOR # (a yard: its things on its own ground)
    w, d = 6.0, 5.0
    k = Kit("camur")
    rng = k.rng
    yard_pad(k, w, d, top=(0.3, 0.23, 0.16))
    # wet patches on the trodden mud, where it's slopped over
    p = k.piece("dark", "slop")
    for (x, y, rx, ry) in ((1.6, -1.0, 0.55, 0.32), (-0.4, -1.5, 0.38, 0.24), (2.6, 0.3, 0.3, 0.45), (0.9, 0.5, 0.35, 0.3)):
        p.stone((x, y, PLINTH_TOP + 0.06), (rx * 2, ry * 2, 0.025), color=jit(WET_MUD, 0.08, rng), rng=rng)
    k.add(p)
    # the mixing pit at the back right: a plank frame round mud trodden with straw, a spade in it
    px, py, pw, pd = 1.75, 1.35, 1.9, 1.6
    p = k.piece("plank", "pit")
    for sy in (-1, 1):
        p.box((px, py + sy * pd * 0.5, FLOOR - 0.02), (pw + 0.12, 0.08, 0.3), jit(DARK, 0.08, rng))
    for sx in (-1, 1):
        p.box((px + sx * pw * 0.5, py, FLOOR - 0.02), (0.08, pd, 0.3), jit(DARK, 0.08, rng))
    k.add(p)
    p = k.piece("dark", "mud")
    p.box((px, py, FLOOR - 0.06), (pw - 0.04, pd - 0.04, 0.12), WET_MUD)
    for i in range(14): # (lumps, and the straw trodden in)
        p.stone((px + rng.uniform(-0.8, 0.8), py + rng.uniform(-0.65, 0.65), FLOOR + 0.0), (0.22, 0.18, 0.08), color=jit(WET_MUD, 0.15, rng), rng=rng)
    for i in range(22):
        p.box((px + rng.uniform(-0.85, 0.85), py + rng.uniform(-0.7, 0.7), FLOOR + 0.015), (rng.uniform(0.12, 0.25), 0.012, 0.008), jit(STRAW, 0.1, rng), rot_z=rng.uniform(0, math.tau))
    k.add(p)
    p = k.piece("wood", "spade")
    blade_at = Vector((px - 0.4, py - 0.3, FLOOR + 0.05))
    shaft = Vector((0.15, 0.1, 1.0)).normalized()
    p.log(blade_at + shaft * 0.15, blade_at + shaft * 1.2, 0.022, color=PLANK, end=PLANK, taper=0.0, segs=6, rng=rng)
    p.obox(blade_at + shaft * 1.24, (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.2, 0.04, 0.04), PLANK)
    p.obox(blade_at, shaft.cross(Vector((1, 0, 0))).normalized(), (1, 0, 0), shaft, (0.04, 0.22, 0.28), IRON)
    k.add(p)
    # the moulding table out front: planks on trestle legs, a four-brick mould, fresh bricks beside it
    p = k.piece("plank", "work")
    p.box((0.0, -0.6, FLOOR + 0.72), (1.7, 0.7, 0.06), jit(PLANK, 0.05, rng))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((sx * 0.72, -0.6 + sy * 0.26, FLOOR + 0.35), (0.07, 0.07, 0.72), jit(DARK, 0.05, rng))
    k.add(p)
    p = k.piece("wood", "mould")
    mx, my, mz = -0.3, -0.6, FLOOR + 0.78
    p.box((mx, my - 0.105, mz), (1.32, 0.03, 0.12), jit(PLANK, 0.06, rng))
    p.box((mx, my + 0.105, mz), (1.32, 0.03, 0.12), jit(PLANK, 0.06, rng))
    for i in range(5):
        p.box((mx - 0.64 + i * 0.32, my, mz), (0.03, 0.24, 0.12), jit(PLANK, 0.06, rng))
    p.box((mx + 0.62, my, mz + 0.05), (0.2, 0.03, 0.03), PLANK) # (a handle)
    k.add(p)
    p = k.piece("dark", "fresh")
    for i in range(4): # (in the mould, filled and struck off level)
        p.box((mx - 0.48 + i * 0.32, my, mz - 0.01), (0.28, 0.17, 0.1), jit(WET_MUD, 0.08, rng))
    for i in range(3):
        brick(p, 0.62, -0.6 - 0.2 + i * 0.2, FLOOR + 0.75, rng, rot=math.pi * 0.5, wet=True)
    k.add(p)
    # the drying shelter at the back left: a thatched roof on posts, straw strewn under it (the
    # game lays its drying bricks there), a few left from the last lot stacked at its side
    lean_to(k, -2.7, 0.3, 0.6, 2.3, 2.2, 1.8)
    p = k.piece("thatch", "floor")
    p.box((-1.2, 1.45, PLINTH_TOP + 0.1), (2.8, 1.5, 0.06), jit(STRAW, 0.05, rng))
    for i in range(30):
        p.box((-1.2 + rng.uniform(-1.5, 1.5), 1.45 + rng.uniform(-0.8, 0.8), PLINTH_TOP + 0.135), (rng.uniform(0.15, 0.3), 0.015, 0.01), jit(STRAW, 0.12, rng), rot_z=rng.uniform(0, math.tau))
    k.add(p)
    p = k.piece("plaster", "stack")
    for c in range(4):
        for i in range(3):
            if c % 2 == 0:
                brick(p, -2.45, 0.95 + i * 0.17, FLOOR - 0.03 + c * 0.12, rng, rot=0.0)
            else:
                brick(p, -2.6 + i * 0.17, 1.12, FLOOR - 0.03 + c * 0.12, rng, rot=math.pi * 0.5)
    k.add(p)
    # the straw heaped at the front left, a barrel of water, a bucket
    p = k.piece("thatch", "straw")
    p.stone((-2.2, -1.5, FLOOR + 0.12), (1.3, 1.05, 0.95), color=STRAW, rng=rng, subdiv=2)
    for i in range(16):
        a = rng.uniform(0, math.tau)
        p.box((-2.2 + math.cos(a) * rng.uniform(0.55, 0.85), -1.5 + math.sin(a) * rng.uniform(0.45, 0.7), PLINTH_TOP + 0.04), (rng.uniform(0.2, 0.4), 0.02, 0.02), jit(STRAW, 0.12, rng), rot_z=rng.uniform(0, math.tau))
    k.add(p)
    barrel(k, -0.9, -1.9, z=PLINTH_TOP)
    p = k.piece("wood", "bucket")
    p.log((-0.35, -1.95, PLINTH_TOP), (-0.35, -1.95, PLINTH_TOP + 0.3), 0.15, color=PLANK, end=(0.12, 0.1, 0.08), taper=0.25, segs=10, rng=rng)
    k.add(p)
    k.finish()


def meydan():
    """The town square: paved, a fire pit in the middle ringed with stones and logs laid ready, log
    benches round it, a notice board, a lamp on a post, the town bell on its frame."""
    w = d = 10.0
    k = Kit("meydan")
    k.paint = k.rng.choice(PAINTS)
    yard_pad(k, w, d, top=(0.4, 0.34, 0.26))
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
    # the town bell, on a frame of two posts in the far corner, under a little roof
    gx, gy = -3.6, 3.6
    p = k.piece("log", "frame")
    for s in (-1, 1):
        p.log((gx + s * 0.75, gy, PLINTH_TOP - 0.1), (gx + s * 0.75, gy, PLINTH_TOP + 3.3), 0.13, rng=k.rng)
    p.log((gx - 1.0, gy, PLINTH_TOP + 3.1), (gx + 1.0, gy, PLINTH_TOP + 3.1), 0.11, rng=k.rng)
    k.add(p)
    p = k.piece("shingle", "frame")
    for s in (-1, 1):
        p.obox((gx, gy + s * 0.32, PLINTH_TOP + 3.55), (1, 0, 0), (0, s * math.cos(0.7), -math.sin(0.7)), (0, s * math.sin(0.7), math.cos(0.7)), (2.3, 0.9, 0.05), jit(SHINGLE, 0.05, k.rng))
    k.add(p)
    p = k.piece("stone", "bell")
    bronze = (0.5, 0.38, 0.18)
    top = PLINTH_TOP + 3.0
    p.log((0 + gx, gy, top - 0.75), (gx, gy, top - 0.05), 0.3, color=bronze, end=bronze, taper=0.9, segs=16, jitter=0.0, bow=0.0)
    p.log((gx, gy, top - 0.82), (gx, gy, top - 0.7), 0.34, color=bronze, end=bronze, taper=0.0, segs=16, jitter=0.0, bow=0.0)
    p.box((gx, gy, top - 0.9), (0.05, 0.05, 0.22), IRON)
    k.add(p)
    k.finish()




# --- the train and its station ----------------------------------------------------------------------
# Rolling stock: each car its own GLB (assets/buildings/tren_*.glb), the rail top at z 0, the car
# running along y (its front at -y, Godot +z). Its wheels are pieces of their own tagged "wheel", each
# with its origin on its axle, so the game turns them as it rolls. Gauge: five feet (rails at +-0.76).

INK = (0.06, 0.06, 0.065)
IRON = (0.16, 0.16, 0.17)
BRASS = (0.72, 0.56, 0.26)
BEAM_RED = (0.5, 0.11, 0.08)
COACH = (0.12, 0.24, 0.17)
BOXCAR = (0.42, 0.18, 0.11)
RAIL_X = 0.76


def cyl(p, a, b, r, color, segs=16, taper=0.0):
    p.log(a, b, r, color=color, end=color, segs=segs, jitter=0.0, taper=taper, bow=0.0)


def wheelset(k, y, r, color=INK, rim=IRON):
    """An axle's two wheels, each a piece of its own (the game turns them)."""
    for sx in (-1, 1):
        p = k.piece("dark", "wheel")
        x = sx * RAIL_X
        cyl(p, (x - 0.07, y, r), (x + 0.07, y, r), r, color, segs=18)
        cyl(p, (x - 0.08, y, r), (x - 0.02, y, r), r * 1.06, rim, segs=18) # (the flange)
        cyl(p, (x - 0.12, y, r), (x + 0.12, y, r), r * 0.18, IRON, segs=8) # (the hub)
        n = 12 if r > 0.6 else 8
        for i in range(n): # (the spokes, standing proud of the web)
            a = i / n * math.tau
            p.obox((x + sx * 0.075, y + math.cos(a) * r * 0.48, r + math.sin(a) * r * 0.48), (1, 0, 0), (0, math.cos(a), math.sin(a)), (0, -math.sin(a), math.cos(a)),
                   (0.03, r * 0.8, 0.05), rim)
        if r > 0.6: # (the crank boss and its counterweight)
            p.box((x + sx * 0.09, y + r * 0.45, r), (0.05, 0.22, 0.22), rim)
            p.obox((x + sx * 0.09, y - r * 0.4, r + 0.15), (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.04, r * 0.7, r * 0.35), color)
        k.add(p)


def buffers(k, y, s):
    """Buffers and a coupling hook at a car's end (`s` -1 front, 1 back)."""
    p = k.piece("dark", "buffers")
    p.box((0, y, 1.0), (2.3, 0.18, 0.32), BEAM_RED)
    for sx in (-1, 1):
        cyl(p, (sx * 0.6, y, 1.0), (sx * 0.6, y + s * 0.38, 1.0), 0.07, IRON, segs=8)
        cyl(p, (sx * 0.6, y + s * 0.36, 1.0), (sx * 0.6, y + s * 0.42, 1.0), 0.18, IRON, segs=12)
    p.box((0, y + s * 0.25, 0.95), (0.12, 0.4, 0.1), IRON)
    p.box((0, y + s * 0.45, 0.92), (0.08, 0.08, 0.16), IRON)
    k.add(p)


def bogie(k, y):
    p = k.piece("dark")
    p.box((0, y, 0.55), (1.9, 2.3, 0.22), IRON)
    for sx in (-1, 1):
        p.box((sx * 0.95, y, 0.45), (0.12, 2.2, 0.35), INK)
        for sy in (-0.85, 0.85): # (axle boxes)
            p.box((sx * 1.02, y + sy, 0.45), (0.12, 0.28, 0.3), IRON)
        for i in range(4): # (the leaf spring between them)
            p.box((sx * 1.02, y, 0.68 - i * 0.04), (0.1, 1.2 - i * 0.22, 0.035), IRON)
    k.add(p)
    wheelset(k, y - 0.85, 0.45)
    wheelset(k, y + 0.85, 0.45)


def lokomotif():
    """The engine: black, a diamond stack, a big boiler banded in brass, three pairs of tall driving
    wheels, a cowcatcher and a lamp in front, the cab behind."""
    k = Kit("tren_lokomotif")
    p = k.piece("dark", "frame")
    p.box((0, 0, 1.05), (1.5, 10.2, 0.35), INK)
    p.box((0, -5.05, 1.0), (2.3, 0.22, 0.4), BEAM_RED) # (the buffer beam)
    for sx in (-1, 1):
        p.box((sx * 0.55, -5.25, 1.05), (0.18, 0.25, 0.18), IRON) # (the buffers)
    k.add(p)
    p = k.piece("dark", "boiler")
    cyl(p, (0, -4.3, 2.35), (0, 2.0, 2.35), 0.78, INK, segs=20)
    cyl(p, (0, -5.0, 2.35), (0, -4.25, 2.35), 0.84, INK, segs=20) # (the smokebox)
    cyl(p, (0, -5.05, 2.35), (0, -4.98, 2.35), 0.7, IRON, segs=20) # (its door)
    for y in (-3.4, -2.0, -0.6, 0.8):
        cyl(p, (0, y, 2.35), (0, y + 0.08, 2.35), 0.8, BRASS, segs=20)
    k.add(p)
    p = k.piece("dark", "stack")
    cyl(p, (0, -4.6, 3.0), (0, -4.6, 3.75), 0.24, INK, segs=14)
    cyl(p, (0, -4.6, 4.55), (0, -4.6, 3.7), 0.55, INK, segs=14, taper=0.6) # (the diamond's wide top, narrowing down)
    cyl(p, (0, -4.6, 4.5), (0, -4.6, 4.62), 0.56, IRON, segs=14)
    k.add(p)
    p = k.piece("stone", "domes")
    cyl(p, (0, -1.4, 2.95), (0, -1.4, 3.45), 0.36, BRASS, segs=14)
    cyl(p, (0, 0.5, 2.95), (0, 0.5, 3.35), 0.32, INK, segs=14)
    cyl(p, (0, 1.4, 3.05), (0, 1.4, 3.45), 0.12, BRASS, segs=10) # (the bell)
    cyl(p, (0.3, 1.0, 3.05), (0.3, 1.0, 3.6), 0.05, BRASS, segs=8) # (the whistle)
    k.add(p)
    p = k.piece("window", "lamp")
    p.box((0, -5.05, 3.35), (0.32, 0.06, 0.32), (1.0, 0.85, 0.5))
    k.add(p)
    p = k.piece("dark", "lampbox")
    p.box((0, -4.85, 3.35), (0.55, 0.42, 0.6), INK)
    p.box((0, -4.85, 3.72), (0.65, 0.5, 0.1), INK)
    k.add(p)
    p = k.piece("dark", "cylinders")
    for sx in (-1, 1):
        cyl(p, (sx * 1.0, -4.2, 1.35), (sx * 1.0, -3.0, 1.35), 0.32, INK, segs=14)
        p.box((sx * 0.92, 0.6, 0.85), (0.08, 4.0, 0.14), IRON) # (the coupling rods)
        p.box((sx * 0.92, -1.8, 1.1), (0.08, 2.6, 0.12), IRON) # (the main rod)
    k.add(p)
    p = k.piece("dark", "pilot")
    for i in range(9):
        x = -0.95 + i * 0.24
        p.obox(((x, -5.55, 0.62)), (1, 0, 0), (0, 0.75, 0.65), (0, -0.65, 0.75), (0.06, 1.0, 0.05), BEAM_RED)
    k.add(p)
    p = k.piece("dark", "cab")
    p.box((0, 3.3, 2.55), (2.5, 2.4, 2.6), INK)
    p.box((0, 3.3, 3.95), (2.8, 2.9, 0.12), IRON)
    k.add(p)
    p = k.piece("window", "cab")
    for sx in (-1, 1):
        p.box((sx * 0.62, 2.08, 3.0), (0.55, 0.05, 0.55), GLASS)
        p.box((sx * 1.26, 3.6, 3.0), (0.05, 0.9, 0.6), GLASS)
    k.add(p)
    # running boards along the boiler, handrails on stanchions, steam pipes down to the cylinders,
    # sand pipes to the wheels, the smokebox door's brass plate and dogs, a coupling hook and lamp irons
    p = k.piece("dark", "boards")
    for sx in (-1, 1):
        p.box((sx * 1.05, -1.2, 1.32), (0.38, 6.4, 0.05), INK)
        p.box((sx * 1.24, -1.2, 1.4), (0.03, 6.4, 0.12), BRASS)
        for y in (-3.9, -2.6, -1.3, 0.0, 1.3):
            cyl(p, (sx * 0.8, y, 2.35), (sx * 0.92, y, 2.35), 0.025, IRON, segs=6)
        cyl(p, (sx * 0.92, -4.1, 2.35), (sx * 0.92, 1.6, 2.35), 0.022, BRASS, segs=6)
        p.obox((sx * 0.62, -3.35, 2.25), (0, 0.55, -0.83), (1, 0, 0), (0, 0.83, 0.55), (1.3, 0.12, 0.12), INK) # (the steam pipe)
        for y in (-1.3, 0.6):
            p.obox((sx * 0.55, y - 0.3, 2.0), (0, 0.2, -0.98), (1, 0, 0), (0, 0.98, 0.2), (1.25, 0.04, 0.04), IRON) # (sand pipes)
        cyl(p, (sx * 0.6, 2.05, 3.7), (sx * 0.6, 2.05, 4.0), 0.04, BRASS, segs=6) # (cab grab rails)
        for i in range(3): # (cab steps)
            p.box((sx * 1.15, 2.3, 0.55 + i * 0.32), (0.3, 0.35, 0.04), IRON)
    k.add(p)
    p = k.piece("stone", "front")
    cyl(p, (0, -5.1, 2.6), (0, -5.06, 2.6), 0.16, BRASS, segs=12) # (the number plate)
    p.box((0, -5.09, 2.35), (0.08, 0.04, 0.4), BRASS) # (the door's handle)
    for a in range(6):
        aa = a / 6 * math.tau
        p.box((math.cos(aa) * 0.62, -5.07, 2.35 + math.sin(aa) * 0.62), (0.08, 0.04, 0.08), IRON) # (the dogs)
    p.box((0, -5.3, 0.95), (0.12, 0.35, 0.1), IRON) # (the coupling hook)
    for sx in (-0.7, 0.7):
        p.box((sx, -5.12, 1.4), (0.12, 0.12, 0.12), IRON) # (lamp irons)
    k.add(p)
    for y in (-1.3, 0.6, 2.5):
        wheelset(k, y, 0.82, color=INK)
    wheelset(k, -3.9, 0.45)
    k.finish()


def tender():
    """The coal and the water behind the engine."""
    k = Kit("tren_tender")
    p = k.piece("dark", "frame")
    p.box((0, 0, 1.0), (2.4, 6.0, 0.3), INK)
    p.box((0, 0.4, 1.95), (2.6, 5.0, 1.6), INK)
    for sx in (-1, 1):
        p.box((sx * 1.3, 0.4, 2.78), (0.08, 5.1, 0.08), BRASS) # (a brass rim round the top)
        p.box((0, 0.4 + sx * 2.52, 2.78), (2.6, 0.08, 0.08), BRASS)
    p.box((0, 0.4, 2.62), (2.5, 4.9, 0.1), INK)
    k.add(p)
    p = k.piece("stone", "coal")
    rng = k.rng
    for i in range(26):
        p.stone((rng.uniform(-0.9, 0.9), rng.uniform(-1.9, 0.5), 2.85 + rng.uniform(0, 0.25)), (0.5, 0.45, 0.3), color=(0.05, 0.05, 0.05), rng=rng)
    k.add(p)
    # a tool box on the top, the water filler, a ladder up the back, grab rails
    p = k.piece("dark", "fittings")
    p.box((0, 2.55, 2.95), (1.8, 0.5, 0.35), INK)
    cyl(p, (0.7, 1.9, 2.67), (0.7, 1.9, 2.9), 0.25, IRON, segs=12)
    for sx in (-0.3, 0.3):
        p.box((sx, 2.92, 1.8), (0.04, 0.04, 1.6), IRON)
    for i in range(5):
        p.box((0, 2.92, 1.15 + i * 0.32), (0.64, 0.04, 0.04), IRON)
    for sx in (-1, 1):
        cyl(p, (sx * 1.32, -2.0, 1.4), (sx * 1.32, -2.0, 2.5), 0.025, BRASS, segs=6)
        cyl(p, (sx * 1.32, 2.8, 1.4), (sx * 1.32, 2.8, 2.5), 0.025, BRASS, segs=6)
    k.add(p)
    buffers(k, 3.0, 1)
    bogie(k, -1.7)
    bogie(k, 1.9)
    k.finish()


def vagon():
    """A coach: green planked sides, a row of windows, a clerestory roof, open platforms at the ends."""
    k = Kit("tren_vagon")
    p = k.piece("dark", "frame")
    p.box((0, 0, 1.0), (2.4, 10.0, 0.25), INK)
    k.add(p)
    p = k.piece("plank", "body")
    p.box((0, 0, 2.2), (2.75, 8.8, 2.3), COACH)
    for y in [x * 0.55 - 4.1 for x in range(16)]:
        for sx in (-1, 1):
            p.box((sx * 1.385, y, 1.55), (0.02, 0.04, 0.9), jit(COACH, 0.03, k.rng)) # (the matchboard lines)
    p.box((0, 0, 3.42), (2.95, 9.3, 0.14), IRON)
    p.box((0, 0, 3.66), (1.3, 8.4, 0.34), IRON)
    k.add(p)
    p = k.piece("window", "side")
    for i in range(7):
        y = -3.3 + i * 1.1
        for sx in (-1, 1):
            p.box((sx * 1.39, y, 2.55), (0.04, 0.65, 0.75), GLASS)
    k.add(p)
    p = k.piece("dark", "ends")
    for sy in (-1, 1):
        p.box((0, sy * 4.75, 1.18), (2.4, 0.7, 0.08), PLANK)
        for sx in (-1, 1):
            p.box((sx * 1.1, sy * 5.05, 1.7), (0.05, 0.05, 1.0), IRON)
            p.box((sx * 0.75, sy * 5.05, 2.15), (0.7, 0.04, 0.05), IRON)
        p.box((0, sy * 4.42, 2.0), (0.75, 0.05, 1.8), (0.2, 0.14, 0.09)) # (the door)
    k.add(p)
    # window frames, a brass band along the side, footboards and steps, lamps and vents on the roof
    p = k.piece("dark", "trim")
    for i in range(7):
        y = -3.3 + i * 1.1
        for sx in (-1, 1):
            p.box((sx * 1.4, y, 2.95), (0.03, 0.75, 0.05), (0.85, 0.82, 0.7))
            p.box((sx * 1.4, y, 2.15), (0.03, 0.75, 0.05), (0.85, 0.82, 0.7))
    for sx in (-1, 1):
        p.box((sx * 1.4, 0, 3.15), (0.03, 8.6, 0.08), BRASS)
        p.box((sx * 1.5, 0, 0.98), (0.25, 8.4, 0.05), IRON) # (the footboard)
        for sy in (-1, 1):
            for i in range(2):
                p.box((sx * 1.3, sy * 4.75, 0.55 + i * 0.25), (0.35, 0.4, 0.04), IRON) # (the steps up to the platforms)
    for y in (-3.0, -1.0, 1.0, 3.0):
        cyl(p, (0, y, 3.82), (0, y, 4.02), 0.14, IRON, segs=10) # (roof lamps)
        p.box((0, y + 0.5, 3.88), (0.3, 0.2, 0.12), IRON) # (vents)
    k.add(p)
    buffers(k, -5.0, -1)
    buffers(k, 5.0, 1)
    bogie(k, -3.4)
    bogie(k, 3.4)
    k.finish()


def yuk():
    """A boxcar: red-brown boards, a sliding door each side, a low roof."""
    k = Kit("tren_yuk")
    p = k.piece("dark", "frame")
    p.box((0, 0, 1.0), (2.4, 8.2, 0.25), INK)
    k.add(p)
    p = k.piece("plank", "body")
    p.box((0, 0, 2.15), (2.75, 7.6, 2.2), BOXCAR)
    for y in [x * 0.45 - 3.6 for x in range(17)]:
        for sx in (-1, 1):
            p.box((sx * 1.385, y, 2.15), (0.02, 0.04, 2.1), jit(BOXCAR, 0.04, k.rng))
    p.box((0, 0, 3.3), (2.95, 7.9, 0.12), IRON)
    for sx in (-1, 1):
        p.box((sx * 1.41, 0.0, 2.05), (0.05, 1.6, 1.95), jit(BOXCAR, 0.06, k.rng)) # (the door)
        p.box((sx * 1.43, 0.0, 3.05), (0.04, 3.4, 0.06), IRON) # (its rail)
        for dz in (-0.7, 0.0, 0.7):
            p.box((sx * 1.44, 0.0, 2.05 + dz), (0.03, 1.55, 0.06), IRON)
    k.add(p)
    # diagonal iron braces across the boards, ladders at the corners, a roof walk, the seal on the door
    p = k.piece("dark", "braces")
    for sx in (-1, 1):
        for y0, s in ((-3.2, 1), (-1.2, -1), (1.2, 1), (3.2, -1)):
            if abs(y0) < 1.0:
                continue
            p.obox((sx * 1.42, y0 + s * 0.0 - (0.55 if y0 < 0 else -0.55) * 0.0, 2.15), (0, 0.6, 0.8), (1, 0, 0), (0, -0.8, 0.6), (2.5, 0.03, 0.08), IRON)
        for sy in (-1, 1):
            for i in range(6):
                p.box((sx * 1.2, sy * 3.84, 1.3 + i * 0.35), (0.4, 0.03, 0.04), IRON) # (corner ladders)
        p.box((sx * 1.45, 0.82, 2.05), (0.04, 0.08, 0.14), (0.75, 0.15, 0.1)) # (the seal)
    p.box((0, 0, 3.4), (0.5, 7.6, 0.05), jit(PLANK, 0.05, k.rng)) # (the roof walk)
    k.add(p)
    buffers(k, -4.1, -1)
    buffers(k, 4.1, 1)
    bogie(k, -2.7)
    bogie(k, 2.7)
    k.finish()


def _station_extra(k, w, d):
    # the platform along the front, a canopy over it on posts, a bench, the name board, a water butt
    p = k.piece("plank", "platform")
    for i in range(13):
        y = -d * 0.5 - 0.25 - i * 0.26
        p.box((0, y, 0.92), (w + 6.0, 0.25, 0.08), jit(PLANK, 0.07, k.rng))
    p.box((0, -d * 0.5 - 1.8, 0.45), (w + 6.0, 3.3, 0.8), jit(STONE, 0.04, k.rng))
    k.add(p)
    # the canopy slopes down to the wall; its posts reach right up under it, a beam along their tops
    # carrying it, braces from post to beam, a plate on the wall for its other edge
    cy, cz = -d * 0.5 - 1.6, 3.85
    py = -d * 0.5 - 2.6
    under = cz + (cy - py) * 0.25 / 0.97 - 0.05 # (the canopy's underside above the posts)
    for x in (-w * 0.5 - 2.0, -w * 0.25, w * 0.25, w * 0.5 + 2.0):
        p = k.piece("log")
        p.log((x, py, 0.95), (x, py, under - 0.14), 0.09, rng=k.rng)
        k.add(p)
        p = k.piece("dark", "brace")
        for sx in (-1, 1):
            if abs(x + sx * 0.6) < w * 0.5 + 2.4:
                p.obox((x + sx * 0.3, py, under - 0.55), (0.7, 0, 0.7), (0, 1, 0), (-0.7, 0, 0.7) if sx > 0 else (0.7, 0, 0.7), (0.9, 0.08, 0.08), DARK)
        k.add(p)
    p = k.piece("log", "beam")
    p.log((-w * 0.5 - 2.4, py, under - 0.07), (w * 0.5 + 2.4, py, under - 0.07), 0.08, rng=k.rng, taper=0.0)
    k.add(p)
    p = k.piece("dark", "plate")
    p.box((0, -d * 0.5 - 0.06, cz - 1.65 * 0.25 / 0.97 - 0.1), (w + 0.2, 0.12, 0.14), DARK)
    k.add(p)
    p = k.piece("shingle", "canopy")
    p.obox((0, cy, cz), (1, 0, 0), (0, 0.97, -0.25), (0, 0.25, 0.97), (w + 5.0, 3.4, 0.08), jit(PLANK, 0.05, k.rng))
    k.add(p)
    p = k.piece("dark", "sign")
    p.box((0, -d * 0.5 - 2.6, 3.25), (2.6, 0.08, 0.45), (0.92, 0.9, 0.82))
    for i in range(7):
        p.box((-0.9 + i * 0.3, -d * 0.5 - 2.65, 3.25), (0.18, 0.02, 0.22), INK)
    k.add(p)
    p = k.piece("plank", "bench")
    p.box((-w * 0.25, -d * 0.5 - 0.6, 1.4), (1.8, 0.4, 0.06), jit(PLANK, 0.06, k.rng))
    p.box((-w * 0.25, -d * 0.5 - 0.42, 1.75), (1.8, 0.05, 0.4), jit(PLANK, 0.06, k.rng))
    for sx in (-0.8, 0.8):
        p.box((-w * 0.25 + sx, -d * 0.5 - 0.6, 1.15), (0.08, 0.36, 0.45), DARK)
    k.add(p)
    barrel(k, w * 0.5 + 0.5, -d * 0.5 + 0.4)
    woodpile(k, -w * 0.5 - 0.7, 0.4, length=2.2)


# --- the convoy: a lorry and an early tank (scripts/convoy.gd) ------------------------------------
# Built nose toward +Y (Godot -Z, the way they drive); wheels are pieces of their own, tagged "wheel".

OLIVE = (0.29, 0.31, 0.21)
OLIVE_DK = (0.2, 0.22, 0.15)
CANVAS = (0.52, 0.49, 0.37)
RUBBER = (0.08, 0.08, 0.075)
RIVET = (0.17, 0.17, 0.15)
STEEL = (0.26, 0.27, 0.24)


def prism(p, outline, x0, x1, color, axis="x"):
    """A slab with the given 2-D outline (a list of (u, v) in order), extruded from x0 to x1 along
    `axis` (outline in y-z for "x", in x-z for "y")."""
    bm = p.bm
    def v3(u, v, w):
        return Vector((w, u, v)) if axis == "x" else Vector((u, w, v))
    a = [bm.verts.new(v3(u, v, x0)) for u, v in outline]
    b = [bm.verts.new(v3(u, v, x1)) for u, v in outline]
    faces = [bm.faces.new(list(reversed(a))), bm.faces.new(b)]
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new([a[i], a[j], b[j], b[i]]))
    for f in faces:
        f.normal_update()
    p._paint(faces, color)
    return faces


def spoked_wheel(k, x, y, r, width=0.16, out=None):
    """A lorry's wheel, a "wheel" piece of its own: a solid rubber tyre on a steel rim, a wooden
    felloe, twelve artillery spokes, a steel hub with its flange, bolts and cap on the outer side
    (`out`: the side it faces, by default away from the middle)."""
    out = out if out is not None else (1 if x >= 0 else -1)
    p = k.piece("dark", "wheel")
    hw = width * 0.5
    c = (x, y, r)
    _ring(p, c, (1, 0, 0), r - 0.035, 0.07, width, RUBBER, n=28) # (the solid tyre)
    for s in (-1, 1): # (its moulded edge)
        _ring(p, (x + s * hw, y, r), (1, 0, 0), r - 0.05, 0.03, 0.008, (0.11, 0.11, 0.1), n=28)
    _ring(p, c, (1, 0, 0), r - 0.085, 0.035, width * 0.85, STEEL, n=28) # (the rim)
    _ring(p, c, (1, 0, 0), r - 0.13, 0.06, width * 0.6, OLIVE_DK, n=24) # (the felloe)
    r0, r1 = r * 0.16, r - 0.15
    for i in range(12):
        a = i / 12 * math.tau
        rad = Vector((0, math.cos(a), math.sin(a)))
        tan = Vector((0, -math.sin(a), math.cos(a)))
        p.obox(Vector(c) + rad * ((r0 + r1) * 0.5), (1, 0, 0), rad, tan, (width * 0.4, r1 - r0, 0.045), OLIVE_DK)
    cyl(p, (x - hw * 0.8, y, r), (x + hw * 0.8, y, r), r * 0.2, STEEL, segs=12) # (the hub)
    fx = x + out * hw * 0.8
    cyl(p, (fx - out * 0.01, y, r), (fx + out * 0.02, y, r), r * 0.3, STEEL, segs=14) # (its flange)
    for i in range(8):
        a = i / 8 * math.tau
        p.box((fx + out * 0.03, y + math.cos(a) * r * 0.24, r + math.sin(a) * r * 0.24), (0.025, 0.03, 0.03), RIVET)
    cyl(p, (fx, y, r), (fx + out * 0.07, y, r), r * 0.12, IRON, segs=10) # (the cap)
    # (the same inward, so the piece's middle stays on the axle and it turns true)
    fi = x - out * hw * 0.8
    cyl(p, (fi + out * 0.01, y, r), (fi - out * 0.02, y, r), r * 0.3, STEEL, segs=14)
    cyl(p, (fi, y, r), (fi - out * 0.07, y, r), r * 0.12, IRON, segs=10)
    k.add(p)


def leaf_spring(p, x, y0, y1, z_top, n=5):
    """A leaf spring along Y from y0 to y1, its top leaf at z_top, the shorter leaves under it."""
    ln = y1 - y0
    for i in range(n):
        p.box((x, (y0 + y1) * 0.5, z_top - i * 0.025), (0.07, ln * (1.0 - i * 0.16), 0.022), IRON)
    p.box((x, (y0 + y1) * 0.5, z_top - n * 0.0125), (0.09, 0.08, n * 0.03 + 0.02), STEEL) # (the clip)


def kamyon():
    """A lorry of the war years: a long louvred bonnet hinged along its top, a flat radiator with its
    filler cap, maker's badge and starting handle; an open cab with half doors, a buttoned bench,
    the steering wheel on a raked column, a framed two-pane screen and a canvas roof on stays; a
    plank bed with benches down both sides, a tailgate hung on chains, under an arched canvas tilt
    on hoops roped down to the sides, the back flap rolled up; deep front mudguards sweeping into
    running boards, a fuel can and a tool box on them; the chassis' rails, cross members and leaf
    springs, a beam front axle, two driven back axles with their differentials and the shaft to
    them, solid-tyred spoked wheels (doubled at the back), a spare on the side, a lamp each side of
    the radiator, the exhaust run back under the frame, a tow hook behind."""
    k = Kit("kamyon")
    rng = k.rng
    R_FRONT, R_BACK = 0.45, 0.48
    # --- the chassis: rails, cross members, dumb irons, bumper, springs, axles, the shaft
    p = k.piece("dark", "frame")
    for sx in (-1, 1):
        p.box((sx * 0.42, -0.05, 0.78), (0.12, 6.4, 0.22), RUBBER)
        for i in range(14):
            p.box((sx * (0.42 + 0.062), -3.0 + i * 0.45, 0.85), (0.01, 0.03, 0.03), RIVET)
    for y in (-3.2, -2.6, -1.45, -0.3, 1.0, 2.0, 2.95):
        p.box((0, y, 0.78), (0.74, 0.1, 0.12), RUBBER)
    p.box((0, 3.2, 0.72), (1.8, 0.12, 0.16), STEEL) # (the bumper)
    for sx in (-1, 1):
        p.box((sx * 0.42, 3.17, 0.75), (0.1, 0.1, 0.2), RUBBER) # (the dumb iron's end)
    k.add(p)
    p = k.piece("dark", "springs")
    for sx in (-1, 1):
        leaf_spring(p, sx * 0.42, 2.45 - 0.55, 2.45 + 0.55, 0.655)
        for yy in (2.45 - 0.55, 2.45 + 0.55):
            p.box((sx * 0.42, yy, 0.64), (0.06, 0.05, 0.08), STEEL) # (the shackles)
        for yb in (-2.0, -0.9):
            leaf_spring(p, sx * 0.42, yb - 0.42, yb + 0.42, 0.655)
        p.box((sx * 0.42, -1.45, 0.62), (0.08, 0.2, 0.12), STEEL) # (the rocker between the back springs)
    k.add(p)
    p = k.piece("dark", "axles")
    p.box((0, 2.45, 0.47), (1.48, 0.09, 0.1), RUBBER) # (the front axle's beam)
    for sx in (-1, 1):
        cyl(p, (sx * 0.74, 2.45, 0.38), (sx * 0.74, 2.45, 0.56), 0.05, STEEL, segs=8) # (its king pins)
        cyl(p, (sx * 0.72, 2.45, 0.45), (sx * 0.8, 2.45, 0.45), 0.04, STEEL, segs=8)
    p.box((0, 2.2, 0.5), (1.3, 0.04, 0.04), STEEL) # (the track rod)
    for sx in (-1, 1):
        p.box((sx * 0.68, 2.33, 0.5), (0.04, 0.3, 0.04), STEEL) # (the steering arms)
    for yb in (-2.0, -0.9):
        cyl(p, (-0.6, yb, R_BACK), (0.6, yb, R_BACK), 0.06, RUBBER, segs=10)
        cyl(p, (0, yb - 0.14, R_BACK), (0, yb + 0.14, R_BACK), 0.17, RUBBER, segs=14) # (the differential)
        cyl(p, (0, yb - 0.2, R_BACK), (0, yb - 0.14, R_BACK), 0.11, STEEL, segs=12)
    p.box((0, 1.05, 0.68), (0.4, 0.5, 0.26), RUBBER) # (the gearbox under the floor)
    cyl(p, (0, 0.8, 0.62), (0, -0.76, R_BACK), 0.04, STEEL, segs=8) # (the shafts back to the axles)
    cyl(p, (0, -1.04, R_BACK), (0, -1.86, R_BACK), 0.04, STEEL, segs=8)
    k.add(p)
    # --- the bonnet: its sides and rounded top, hinged along the middle, louvred, two catches a side
    p = k.piece("dark", "bonnet")
    p.box((0, 2.25, 1.28), (0.95, 1.5, 0.7), OLIVE)
    prism(p, [(-0.48, 1.62), (0.48, 1.62), (0.4, 1.74), (-0.4, 1.74)], 1.5, 3.0, OLIVE, axis="y")
    cyl(p, (0, 1.5, 1.745), (0, 3.0, 1.745), 0.018, OLIVE_DK, segs=6) # (the hinge)
    for sx in (-1, 1):
        p.box((sx * 0.476, 2.25, 1.61), (0.012, 1.48, 0.015), OLIVE_DK) # (where the top lifts)
        for i in range(7):
            p.box((sx * 0.48, 1.75 + i * 0.17, 1.38), (0.02, 0.05, 0.3), OLIVE_DK) # (the louvres)
        for yy in (1.7, 2.8):
            p.box((sx * 0.485, yy, 1.08), (0.02, 0.05, 0.1), STEEL) # (the catches)
        p.box((sx * 0.485, 2.25, 0.95), (0.02, 1.5, 0.04), OLIVE_DK) # (the valance's edge)
    k.add(p)
    # --- the radiator: a shell, the core's grid in it, the cap, the badge, the starting handle
    p = k.piece("dark", "radiator")
    p.box((0, 3.06, 1.36), (1.0, 0.12, 1.0), STEEL)
    p.box((0, 3.12, 1.34), (0.82, 0.02, 0.8), INK)
    for i in range(10):
        p.box((-0.36 + i * 0.08, 3.13, 1.34), (0.02, 0.02, 0.78), RIVET)
    for i in range(9):
        p.box((0, 3.13, 0.98 + i * 0.09), (0.8, 0.015, 0.012), RIVET)
    cyl(p, (0, 3.03, 1.86), (0, 3.03, 1.95), 0.065, BRASS, segs=10) # (the filler cap)
    p.box((0, 3.03, 1.97), (0.12, 0.03, 0.03), BRASS)
    cyl(p, (0, 3.12, 1.78), (0, 3.14, 1.78), 0.06, BRASS, segs=10) # (the badge)
    p.box((0, 3.145, 1.78), (0.08, 0.005, 0.02), BEAM_RED)
    cyl(p, (0, 3.1, 0.86), (0, 3.35, 0.86), 0.025, STEEL, segs=6) # (the starting handle)
    p.box((0, 3.36, 0.76), (0.03, 0.03, 0.22), STEEL)
    cyl(p, (0, 3.36, 0.66), (0, 3.46, 0.66), 0.025, (0.4, 0.3, 0.2), segs=6)
    for sx in (-1, 1):
        p.box((sx * 0.57, 3.05, 1.45), (0.16, 0.05, 0.05), STEEL) # (the lamp brackets)
        cyl(p, (sx * 0.68, 2.98, 1.45), (sx * 0.68, 3.18, 1.45), 0.11, RUBBER, segs=12) # (the lamps)
        cyl(p, (sx * 0.68, 3.17, 1.45), (sx * 0.68, 3.2, 1.45), 0.125, BRASS, segs=12) # (their rims)
        p.box((sx * 0.68, 3.06, 1.58), (0.04, 0.04, 0.04), RUBBER) # (the chimney)
    k.add(p)
    p = k.piece("window", "lamps")
    for sx in (-1, 1):
        cyl(p, (sx * 0.68, 3.19, 1.45), (sx * 0.68, 3.21, 1.45), 0.1, (1.0, 0.9, 0.7), segs=12)
    k.add(p)
    # --- the mudguards sweeping down into the running boards, their brackets to the rails
    p = k.piece("dark", "guards")
    for sx in (-1, 1):
        n = 10
        for i in range(n):
            a = math.pi * (0.05 + 0.72 * i / (n - 1))
            p.obox((sx * 0.87, 2.45 + math.cos(a) * 0.6, 0.47 + math.sin(a) * 0.6), (1, 0, 0), (0, -math.sin(a), math.cos(a)), (0, math.cos(a), math.sin(a)),
                   (0.34, 0.22, 0.03), OLIVE)
        # (the arc's back end swept down into the board)
        a = math.pi * 0.77
        e = Vector((2.45 + math.cos(a) * 0.6, 0.47 + math.sin(a) * 0.6))
        f = Vector((1.75, 0.68))
        dv = (f - e)
        p.obox((sx * 0.87, (e.x + f.x) * 0.5, (e.y + f.y) * 0.5), (1, 0, 0), (0, dv.normalized().x, dv.normalized().y), (0, -dv.normalized().y, dv.normalized().x),
               (0.34, dv.length + 0.06, 0.03), OLIVE)
        p.box((sx * 0.87, 0.7, 0.67), (0.34, 2.15, 0.035), OLIVE_DK) # (the running board)
        for i in range(6):
            p.box((sx * 0.87, -0.2 + i * 0.36, 0.69), (0.3, 0.02, 0.01), RUBBER) # (its treads)
        for yy in (-0.15, 0.7, 1.55):
            p.box((sx * 0.6, yy, 0.67), (0.28, 0.06, 0.04), RUBBER) # (the outriggers to the rail)
            p.box((sx * 0.48, yy, 0.72), (0.04, 0.06, 0.12), RUBBER)
    k.add(p)
    # a fuel can on the left board, a tool box on the right
    p = k.piece("dark", "can")
    p.box((-0.87, -0.05, 0.92), (0.16, 0.34, 0.46), (0.3, 0.33, 0.22))
    for dz in (-0.12, 0.0, 0.12):
        p.box((-0.87, -0.05, 0.92 + dz), (0.17, 0.3, 0.02), (0.24, 0.27, 0.18)) # (its ribs)
    cyl(p, (-0.87, 0.06, 1.15), (-0.87, 0.06, 1.2), 0.03, STEEL, segs=6)
    p.box((-0.87, -0.1, 1.17), (0.03, 0.14, 0.03), STEEL) # (the handle)
    p.box((-0.75, -0.05, 0.92), (0.03, 0.36, 0.03), STEEL) # (the strap round it to the board's edge)
    p.box((0.87, 0.0, 0.8), (0.3, 0.55, 0.22), OLIVE_DK) # (the tool box)
    p.box((0.87, 0.0, 0.92), (0.32, 0.57, 0.03), OLIVE)
    p.box((1.03, 0.0, 0.84), (0.02, 0.08, 0.06), STEEL)
    k.add(p)
    # --- the cab: floor, a bench with its cushion and back, the dash, the half doors, the column
    p = k.piece("dark", "cab")
    p.box((0, 0.95, 0.92), (1.7, 1.15, 0.06), OLIVE_DK) # the floor on the rails
    p.box((0, 0.72, 1.1), (1.5, 0.55, 0.3), OLIVE) # the seat box
    p.box((0, 0.42, 1.55), (1.6, 0.06, 1.2), OLIVE) # the back panel
    p.box((0, 1.5, 1.6), (1.6, 0.08, 0.9), OLIVE) # the dash and scuttle
    p.box((0, 1.46, 1.75), (1.1, 0.02, 0.18), (0.28, 0.2, 0.13)) # (its wooden board)
    for gx in (-0.2, 0.0, 0.15):
        cyl(p, (gx, 1.45, 1.76), (gx, 1.44, 1.76), 0.035, BRASS, segs=8) # (gauges)
    for sx in (-1, 1):
        # the half door, a cutaway top, hinges forward, a handle
        p.box((sx * 0.83, 0.98, 1.24), (0.04, 0.88, 0.6), OLIVE)
        p.box((sx * 0.83, 0.98, 1.55), (0.05, 0.88, 0.04), OLIVE_DK)
        for zz in (1.05, 1.4):
            p.box((sx * 0.855, 1.38, zz), (0.015, 0.14, 0.04), STEEL)
        p.box((sx * 0.86, 0.62, 1.38), (0.03, 0.1, 0.03), STEEL)
        p.box((sx * 0.83, 0.47, 1.25), (0.05, 0.1, 0.62), OLIVE) # (the post behind it)
        # the roof stays and the screen's posts
        p.box((sx * 0.8, 0.45, 2.2), (0.05, 0.05, 0.36), OLIVE_DK)
        p.box((sx * 0.78, 1.52, 2.2), (0.05, 0.05, 0.36), OLIVE_DK)
        # the step under the door
        p.box((sx * 0.87, 1.0, 0.705), (0.3, 0.35, 0.03), STEEL)
    p.box((0, 1.52, 2.36), (1.61, 0.06, 0.05), OLIVE_DK) # (the screen's top rail)
    p.box((0, 1.52, 2.06), (1.61, 0.06, 0.05), OLIVE_DK) # (its bottom rail)
    p.box((0, 1.52, 2.21), (0.04, 0.05, 0.3), OLIVE_DK) # (the bar between the panes)
    for sx in (-1, 1):
        p.box((sx * 0.55, 1.535, 2.36), (0.05, 0.04, 0.04), STEEL) # (the panes' hinges)
    k.add(p)
    p = k.piece("cloth", "seat")
    p.box((0, 0.74, 1.3), (1.45, 0.5, 0.1), (0.3, 0.2, 0.13))
    p.box((0, 0.5, 1.6), (1.45, 0.1, 0.42), (0.3, 0.2, 0.13))
    for i in range(5):
        for zz in (1.5, 1.7):
            p.box((-0.56 + i * 0.28, 0.44, zz), (0.03, 0.02, 0.03), (0.2, 0.13, 0.08)) # (buttons)
    k.add(p)
    p = k.piece("dark", "steering")
    col0, col1 = Vector((0.38, 1.45, 1.4)), Vector((0.38, 1.12, 1.78))
    cyl(p, col0, col1, 0.025, RUBBER, segs=8)
    ax = (col1 - col0).normalized()
    _ring(p, col1, ax, 0.19, 0.03, 0.03, RUBBER, n=18)
    a, u, v = _axes(ax)
    for t in (0.0, math.tau / 3, 2 * math.tau / 3):
        rad = u * math.cos(t) + v * math.sin(t)
        p.obox(col1 + rad * 0.095, rad.cross(a), a, rad, (0.02, 0.02, 0.19), STEEL)
    p.box((0.05, 1.3, 1.0), (0.04, 0.04, 0.12), STEEL) # (the levers)
    p.obox((0.15, 1.25, 1.05), (1, 0, 0), (0, 0.5, 0.86), (0, -0.86, 0.5), (0.03, 0.03, 0.35), STEEL)
    k.add(p)
    p = k.piece("cloth", "cabroof")
    p.box((0, 0.98, 2.41), (1.75, 1.35, 0.06), CANVAS)
    for sx in (-1, 1):
        p.box((sx * 0.87, 0.98, 2.36), (0.02, 1.35, 0.1), (0.46, 0.43, 0.32)) # (its valance)
    k.add(p)
    p = k.piece("window", "screen")
    for sx in (-1, 1):
        p.box((sx * 0.39, 1.52, 2.21), (0.74, 0.02, 0.26), GLASS)
    k.add(p)
    # the side's paint on the doors
    p = k.piece("dark", "mark")
    for sx in (-1, 1):
        p.box((sx * 0.855, 0.98, 1.26), (0.01, 0.42, 0.26), (0.82, 0.8, 0.72))
    k.add(p)
    # --- the bed (floor, sides, front: the game seats the men on it), the bearers under it
    p = k.piece("plank", "bed")
    for i in range(9):
        x = -1.025 + (i + 0.5) * 2.05 / 9
        p.box((x, -1.45, 1.0), (2.05 / 9 - 0.01, 3.4, 0.1), jit(PLANK, 0.05, rng))
    for sx in (-1, 1):
        for i in range(3):
            p.box((sx * 1.0, -1.45, 1.13 + i * 0.15), (0.05, 3.4, 0.14), jit(PLANK, 0.06, rng))
    for i in range(3):
        p.box((0, 0.225, 1.13 + i * 0.15), (2.05, 0.05, 0.14), jit(PLANK, 0.06, rng))
    k.add(p)
    p = k.piece("dark", "bearers")
    for y in (-3.0, -2.2, -1.4, -0.6, 0.15):
        p.box((0, y, 0.92), (2.05, 0.1, 0.06), OLIVE_DK)
    for sx in (-1, 1):
        for y in (-2.9, -1.95, -1.0, -0.05):
            p.box((sx * 1.035, y, 1.27), (0.035, 0.08, 0.5), OLIVE_DK) # (the side stakes outside)
            p.box((sx * 1.06, y, 1.1), (0.03, 0.06, 0.04), STEEL) # (the rope hooks)
    k.add(p)
    # the benches inside, down both sides
    p = k.piece("plank", "benches")
    for sx in (-1, 1):
        p.box((sx * 0.8, -1.45, 1.42), (0.32, 3.2, 0.05), jit(PLANK, 0.05, rng))
        for y in (-2.9, -1.9, -0.9, 0.0):
            p.box((sx * 0.8, y, 1.235), (0.05, 0.05, 0.32), DARK)
            p.box((sx * 0.885, y, 1.38), (0.16, 0.05, 0.04), DARK) # (bracket to the side)
    k.add(p)
    # the tailgate let down on its two chains, hinged at the floor
    p = k.piece("plank", "tailgate")
    tg = math.radians(80) # (from upright)
    hinge = Vector((0, -3.15, 1.05))
    dn = Vector((0, -math.sin(tg), math.cos(tg)))
    nrm = Vector((0, math.cos(tg), math.sin(tg)))
    for i in range(3):
        p.obox(hinge + dn * (0.08 + i * 0.15), (1, 0, 0), dn, nrm, (2.05, 0.14, 0.05), jit(PLANK, 0.06, rng))
    for sx in (-0.9, 0.0, 0.9):
        p.obox(hinge + dn * 0.235, (1, 0, 0), dn, nrm, (0.05, 0.45, 0.06), OLIVE_DK)
    for sx in (-1, 1):
        p.box((sx * 0.75, -3.15, 1.03), (0.12, 0.08, 0.06), STEEL) # (the hinges)
    k.add(p)
    p = k.piece("dark", "chains")
    tip = hinge + dn * 0.45
    for sx in (-1, 1):
        a = Vector((sx * 1.0, -3.15, 1.55))
        b = Vector((sx * 1.0, tip.y, tip.z + 0.04))
        m = 7
        for i in range(m):
            c = a.lerp(b, (i + 0.5) / m) - Vector((0, 0, 0.06 * math.sin(math.pi * (i + 0.5) / m)))
            d = (b - a).normalized()
            p.obox(c, d, (1, 0, 0), d.cross(Vector((1, 0, 0))), (((b - a).length / m) * 1.15, 0.015, 0.035 if i % 2 else 0.015), IRON)
    k.add(p)
    # --- the tilt: hoops off the sides, the canvas over them, ropes down to the hooks, the flap rolled up
    p = k.piece("dark", "hoops")
    for y in (-3.0, -2.0, -1.0, 0.05):
        for i in range(9):
            a = math.pi * i / 8
            p.obox((math.cos(a) * 0.98, y, 1.55 + math.sin(a) * 0.95), (0, 1, 0), (-math.sin(a), 0, math.cos(a)), (math.cos(a), 0, math.sin(a)),
                   (0.04, 0.36, 0.04), OLIVE_DK)
    k.add(p)
    p = k.piece("cloth", "tilt")
    arch = [(math.cos(math.pi * i / 12) * 1.02, 1.55 + math.sin(math.pi * i / 12) * 0.98) for i in range(13)]
    arch += [(-1.02, 1.3), (1.02, 1.3)]
    arch = [arch[-1]] + arch[:13] + [arch[-2]]
    prism(p, arch, -3.15, 0.15, jit(CANVAS, 0.04, rng), axis="y")
    for y in (-3.0, -2.0, -1.0, 0.05):
        for i in range(13): # (a darker band where the canvas lies on each hoop)
            a = math.pi * i / 12
            p.obox((math.cos(a) * 1.03, y, 1.55 + math.sin(a) * 0.99), (0, 1, 0), (-math.sin(a), 0, math.cos(a)), (math.cos(a), 0, math.sin(a)),
                   (0.06, 0.27, 0.01), (0.44, 0.41, 0.3))
    # (the rear flap, rolled up and tied under the top)
    cyl(p, (-0.85, -3.2, 2.32), (0.85, -3.2, 2.32), 0.09, jit(CANVAS, 0.05, rng), segs=10)
    k.add(p)
    p = k.piece("cloth", "ropes")
    rope = (0.5, 0.45, 0.32)
    for sx in (-1, 1):
        p.box((sx * 1.03, -1.5, 1.31), (0.02, 3.3, 0.02), rope) # (along the tilt's hem)
        for y in (-2.9, -1.95, -1.0, -0.05):
            p.box((sx * 1.055, y + 0.04, 1.2), (0.015, 0.015, 0.24), rope) # (down to the hooks)
    for xx in (-0.55, 0.55):
        for i in range(5): # (the ties round the rolled flap)
            a = i / 5 * math.tau
            p.obox((xx, -3.2 + math.cos(a) * 0.1, 2.32 + math.sin(a) * 0.1), (1, 0, 0), (0, -math.sin(a), math.cos(a)), (0, math.cos(a), math.sin(a)), (0.02, 0.13, 0.012), rope)
    for y in (-2.5, -1.5, -0.5): # (the lacing over the top)
        p.box((0, y, 2.535), (0.3, 0.04, 0.02), (0.4, 0.37, 0.27))
    k.add(p)
    # --- the spare on the right side, on a bracket to the bed's side
    p = k.piece("dark", "spare")
    cyl(p, (1.06, -0.1, 0.95), (1.18, -0.1, 0.95), 0.45, RUBBER, segs=20)
    cyl(p, (1.06, -0.1, 0.95), (1.18, -0.1, 0.95), 0.36, STEEL, segs=20)
    cyl(p, (1.07, -0.1, 0.95), (1.17, -0.1, 0.95), 0.32, INK, segs=16)
    p.box((1.04, -0.1, 0.95), (0.04, 0.12, 0.5), STEEL) # (its bracket)
    cyl(p, (1.04, -0.1, 0.95), (1.24, -0.1, 0.95), 0.03, STEEL, segs=6) # (the clamp bolt)
    k.add(p)
    # --- the exhaust: down from the engine, back under the frame on hangers, a silencer, the tail
    p = k.piece("dark", "exhaust")
    cyl(p, (0.3, 1.7, 0.9), (0.3, 1.55, 0.6), 0.045, RUBBER, segs=8)
    cyl(p, (0.3, 1.55, 0.6), (0.3, -3.35, 0.6), 0.045, RUBBER, segs=8)
    cyl(p, (0.3, 0.1, 0.6), (0.3, -0.55, 0.6), 0.1, RUBBER, segs=10) # (the silencer)
    for y in (1.0, -1.45, -2.6):
        p.box((0.36, y, 0.645), (0.12, 0.04, 0.09), STEEL) # (hangers up to the rail)
    k.add(p)
    # --- the tow hook on the back cross member
    p = k.piece("dark", "hook")
    p.box((0, -3.3, 0.76), (0.22, 0.1, 0.16), STEEL)
    cyl(p, (0, -3.33, 0.74), (0, -3.5, 0.74), 0.035, IRON, segs=8)
    for i in range(6):
        a = math.pi * (-0.5 + i / 5 * 1.2)
        p.obox((0, -3.56 + math.cos(a) * 0.06, 0.8 + math.sin(a) * 0.06), (1, 0, 0), (0, -math.sin(a), math.cos(a)), (0, math.cos(a), math.sin(a)), (0.04, 0.05, 0.03), IRON)
    k.add(p)
    # --- the wheels
    spoked_wheel(k, -0.88, 2.45, R_FRONT)
    spoked_wheel(k, 0.88, 2.45, R_FRONT)
    for y in (-2.0, -0.9):
        for sx in (-1, 1):
            spoked_wheel(k, sx * 0.84, y, R_BACK, width=0.14)
            spoked_wheel(k, sx * 0.66, y, R_BACK, width=0.14, out=-sx) # (doubled, its hub facing in)
    k.finish()


TRACK_PITCH = 0.28


def _loop_at(pts, s):
    """The point at arc length `s` round the closed outline `pts` (2-D), and the direction there."""
    total = sum((Vector(pts[(i + 1) % len(pts)]) - Vector(pts[i])).length for i in range(len(pts)))
    s = s % total
    for i in range(len(pts)):
        a, b = Vector(pts[i]), Vector(pts[(i + 1) % len(pts)])
        seg = (b - a).length
        if s <= seg or i == len(pts) - 1:
            d = (b - a).normalized()
            return a + d * min(s, seg), d
        s -= seg


def _corner_circle(pts, i, r):
    """The centre of a circle of radius `r` set into the corner `i` of the outline, touching both sides."""
    v = Vector(pts[i])
    e1 = (Vector(pts[i - 1]) - v).normalized()
    e2 = (Vector(pts[(i + 1) % len(pts)]) - v).normalized()
    half = math.acos(max(-1.0, min(1.0, e1.dot(e2)))) * 0.5
    return v + (e1 + e2).normalized() * (r / math.sin(half))


def tank():
    """An early tank: the tracks run right round its rhomboid sides (the nose climbing high to take a
    trench), the hull riveted plate between them, a gun in a sponson on each flank, a small cupola
    on the roof with vision slits, the exhaust and the steering tail behind. Each track is three
    pieces, "track0", "track1", "track2", the same links each a third of a link further round the
    loop: the game shows one at a time, in turn, and the track runs. The drive sprocket at the back
    corner and the idler at the nose are "wheel" pieces (turned on X)."""
    k = Kit("tank")
    rng = k.rng
    side = [(-3.4, 0.28), (2.2, 0.28), (3.8, 1.55), (3.4, 2.55), (-3.0, 2.55), (-3.9, 1.25)]
    FX0, FX1 = 1.02, 1.52 # (the track frame, inner and outer face)
    # the track frames, plate inside the loop
    for sx in (-1, 1):
        p = k.piece("dark", "frame")
        prism(p, side, sx * FX0, sx * FX1, STEEL)
        k.add(p)
    # the hull between them
    p = k.piece("dark", "hull")
    prism(p, [(-3.0, 0.7), (2.4, 0.7), (3.3, 1.5), (3.0, 2.35), (-2.7, 2.35), (-3.3, 1.3)], -1.02, 1.02, OLIVE)
    k.add(p)
    # the tracks: three phases of the same links round each whole loop, each lying flat on the frame's
    # edge; every link a cast shoe, a raised grip bar across it and its hinge knuckles at the back
    perim = sum((Vector(side[(i + 1) % len(side)]) - Vector(side[i])).length for i in range(len(side)))
    n = max(8, int(round(perim / TRACK_PITCH)))
    step = perim / n
    for sx in (-1, 1):
        xc = sx * (FX0 + FX1) * 0.5
        for ph in range(3):
            p = k.piece("dark", "track%d" % ph)
            for j in range(n):
                c, d = _loop_at(side, (j + ph / 3.0) * step)
                out = Vector((d.y, -d.x)) # (out of the loop)
                ax = (0, d.x, d.y)
                az = (0, out.x, out.y)
                base = c + out * 0.03
                p.obox((xc, base.x, base.y), (1, 0, 0), ax, az, (0.62, step - 0.04, 0.06), RUBBER)
                g = c + out * 0.075
                p.obox((xc, g.x, g.y), (1, 0, 0), ax, az, (0.6, 0.05, 0.035), RIVET) # (the grip bar)
                h = c + out * 0.03 - d * (step * 0.5 - 0.02)
                for kx in (-0.22, 0.0, 0.22): # (the hinge knuckles)
                    p.obox((xc + kx, h.x, h.y), (1, 0, 0), ax, az, (0.1, 0.05, 0.07), (0.13, 0.12, 0.11))
            k.add(p)
    # the drive sprocket in the back corner and the idler in the nose, each on a stub axle out of the
    # frame; and the road wheels' hubs and bolts showing on the frame's face down the bottom run
    for sx in (-1, 1):
        for corner, r, teeth in ((5, 0.46, 12), (2, 0.4, 0)):
            ctr = _corner_circle(side, corner, r)
            p = k.piece("dark", "wheel")
            x0 = sx * FX1
            cyl(p, (x0 - sx * 0.02, ctr.x, ctr.y), (x0 + sx * 0.07, ctr.x, ctr.y), r - 0.04, STEEL, segs=20)
            if teeth:
                for t in range(teeth):
                    a = t / teeth * math.tau
                    rad = Vector((0, math.cos(a), math.sin(a)))
                    tan = Vector((0, -math.sin(a), math.cos(a)))
                    p.obox(Vector((x0 + sx * 0.025, ctr.x, ctr.y)) + rad * (r - 0.02), (1, 0, 0), tan, rad, (0.07, 0.1, 0.12), RIVET)
            else:
                for t in range(6): # (the idler's lightening holes)
                    a = t / 6 * math.tau
                    cyl(p, (x0 + sx * 0.068, ctr.x + math.cos(a) * r * 0.55, ctr.y + math.sin(a) * r * 0.55),
                        (x0 + sx * 0.075, ctr.x + math.cos(a) * r * 0.55, ctr.y + math.sin(a) * r * 0.55), 0.07, INK, segs=8)
            cyl(p, (x0 - sx * 0.02, ctr.x, ctr.y), (x0 + sx * 0.16, ctr.x, ctr.y), 0.12, IRON, segs=10) # (the hub on its stub)
            for t in range(6):
                a = t / 6 * math.tau + 0.3
                p.box((x0 + sx * 0.17, ctr.x + math.cos(a) * 0.08, ctr.y + math.sin(a) * 0.08), (0.03, 0.035, 0.035), RIVET)
            k.add(p)
        p = k.piece("dark", "hubs")
        for i in range(8):
            y = -2.75 + i * 0.66
            cyl(p, (sx * (FX1 - 0.01), y, 0.62), (sx * (FX1 + 0.035), y, 0.62), 0.14, IRON, segs=12)
            for t in range(5):
                a = t / 5 * math.tau
                p.box((sx * (FX1 + 0.045), y + math.cos(a) * 0.09, 0.62 + math.sin(a) * 0.09), (0.025, 0.03, 0.03), RIVET)
        k.add(p)
    # rivet rows and plate seams on the frames
    p = k.piece("dark", "rivets")
    for sx in (-1, 1):
        for row in (1.05, 1.6, 2.3):
            for i in range(16):
                y = -3.0 + i * 0.38
                p.box((sx * 1.535, y, row), (0.03, 0.05, 0.05), RIVET)
        for y in (-1.6, 0.2, 1.8):
            p.box((sx * 1.535, y, 1.62), (0.03, 0.04, 1.5), RIVET)
    k.add(p)
    # a sponson on each flank, a mantlet bolted to its face and the short gun through it
    for sx in (-1, 1):
        p = k.piece("dark", "sponson")
        prism(p, [(-0.9, 0.9), (0.9, 0.9), (0.7, 2.0), (-0.7, 2.0)], sx * 1.52, sx * 2.05, OLIVE)
        k.add(p)
        p = k.piece("dark", "gun")
        cyl(p, (sx * 2.04, 0.4, 1.45), (sx * 2.2, 0.4, 1.45), 0.22, STEEL, segs=14) # (its mantlet)
        cyl(p, (sx * 2.15, 0.4, 1.45), (sx * 2.55, 1.35, 1.45), 0.075, RUBBER, segs=10)
        cyl(p, (sx * 2.5, 1.23, 1.45), (sx * 2.56, 1.37, 1.45), 0.095, RUBBER, segs=10) # (the muzzle)
        k.add(p)
    # the cupola, slits, hatch
    p = k.piece("dark", "cupola")
    p.box((0, 1.2, 2.65), (1.1, 1.0, 0.6), OLIVE)
    p.box((0, 1.2, 2.98), (1.2, 1.1, 0.06), OLIVE_DK) # (its lid)
    p.box((0, 1.71, 2.72), (0.7, 0.02, 0.06), (0.02, 0.02, 0.02))
    for sx in (-1, 1):
        p.box((sx * 0.56, 1.2, 2.72), (0.02, 0.5, 0.06), (0.02, 0.02, 0.02))
    p.box((0, -1.5, 2.4), (0.9, 0.9, 0.1), OLIVE_DK) # (the hatch)
    p.box((0, -1.5, 2.47), (0.4, 0.05, 0.05), STEEL) # (its handle)
    k.add(p)
    # the exhaust stacks clamped to the roof, and the steering tail: two booms hinged to the hull's
    # back, the wheels on an axle between them, a spring off the roof holding them down
    p = k.piece("dark", "tail")
    for sx in (-0.4, 0.4):
        cyl(p, (sx, -2.2, 2.3), (sx, -2.2, 3.0), 0.09, RUBBER, segs=8)
        p.box((sx, -2.2, 2.4), (0.24, 0.24, 0.1), STEEL) # (its foot clamp)
        p.box((sx, -2.2, 2.8), (0.22, 0.22, 0.05), STEEL)
    p.box((0, -2.2, 2.8), (0.8, 0.05, 0.05), STEEL) # (a stay between them)
    p.box((0, -3.12, 1.0), (1.5, 0.2, 0.3), STEEL) # (the hinge plate on the hull's back)
    for sx in (-1, 1):
        a, b = Vector((sx * 0.68, -3.1, 1.0)), Vector((sx * 0.68, -4.95, 0.55))
        dv = (b - a)
        p.obox((a + b) * 0.5, (1, 0, 0), dv.normalized(), Vector((1, 0, 0)).cross(dv.normalized()), (0.1, dv.length + 0.1, 0.14), STEEL)
        cyl(p, (sx * 0.62, -4.95, 0.55), (sx * 0.74, -4.95, 0.55), 0.1, IRON, segs=10) # (the axle boss)
        cyl(p, (sx * 0.5, -2.75, 2.3), (sx * 0.68, -4.1, 0.85), 0.04, IRON, segs=6) # (the spring rod)
    cyl(p, (-0.62, -4.95, 0.55), (0.62, -4.95, 0.55), 0.05, IRON, segs=8) # (the axle)
    k.add(p)
    for sx in (-1, 1):
        spoked = k.piece("dark", "wheel")
        cyl(spoked, (sx * 0.5 - 0.06, -4.95, 0.55), (sx * 0.5 + 0.06, -4.95, 0.55), 0.55, STEEL, segs=16)
        cyl(spoked, (sx * 0.5 - 0.1, -4.95, 0.55), (sx * 0.5 + 0.1, -4.95, 0.55), 0.12, IRON, segs=10)
        k.add(spoked)
    # the side's mark: a band of paint on each frame (light: the Centre; the game recolours the rebels')
    p = k.piece("dark", "mark")
    for sx in (-1, 1):
        p.box((sx * 1.54, -1.9, 1.9), (0.02, 1.0, 0.3), (0.82, 0.8, 0.72))
    k.add(p)
    k.finish()


# --- the town's other buildings: the reading room, the smithy, the feldsher's hut, the jail ---------

def _sign(k, w, d, text_len=1.4, z=2.65):
    """A board over the door (the lettering's dark strokes painted on it)."""
    p = k.piece("plank", "sign")
    p.box((0, -d * 0.5 - 0.2, z), (text_len, 0.05, 0.36), jit(PLANK, 0.04, k.rng))
    for i in range(6):
        p.box((-text_len * 0.4 + i * text_len * 0.16, -d * 0.5 - 0.23, z), (0.06, 0.01, 0.2), INK)
    k.add(p)


def _smith_props(k, w, d, stack_top=None):
    # the forge: a fieldstone hearth with glowing coals, a stone stack up through the roof, leather
    # bellows on a frame; an anvil on a stump, a quench tub, tongs and hammers, iron bars, shoes on the wall
    p = k.piece("stone", "forge")
    for i in range(14):
        a = i / 14 * math.tau
        p.stone((-1.3 + math.cos(a) * 0.55, 0.9 + math.sin(a) * 0.45, FLOOR + 0.35), (0.4, 0.34, 0.5), rng=k.rng)
    p.box((-1.3, 0.9, FLOOR + 0.35), (1.1, 0.9, 0.7), jit(STONE, 0.05, k.rng))
    if stack_top is None:
        for i in range(10):
            p.stone((-1.3 + k.rng.uniform(-0.25, 0.25), 1.2, FLOOR + 1.0 + i * 0.32), (0.55, 0.5, 0.34), rng=k.rng)
    else: # (a solid stack up through the roof, fieldstones on its faces, blackened at the top)
        z0 = FLOOR + 0.7
        p.box((-1.3, 1.2, (z0 + stack_top) * 0.5), (0.7, 0.6, stack_top - z0), jit((0.42, 0.41, 0.38), 0.04, k.rng))
        z = z0
        while z < stack_top - 0.2:
            for j in range(8):
                a = j / 8 * math.tau + z
                c = (0.1, 0.1, 0.1) if z > stack_top - 0.8 else STONE
                p.stone((-1.3 + math.cos(a) * 0.33, 1.2 + math.sin(a) * 0.28, z + 0.15), (0.3, 0.26, 0.22), color=c, rng=k.rng)
            z += 0.3
    k.add(p)
    p = k.piece("window", "coals") # (stuff "window": it glows at night)
    for i in range(8):
        p.box((-1.3 + k.rng.uniform(-0.3, 0.3), 0.85 + k.rng.uniform(-0.2, 0.2), FLOOR + 0.74), (0.14, 0.12, 0.06), (1.0, 0.45, 0.12))
    k.add(p)
    p = k.piece("cloth", "bellows")
    p.obox((-2.05, 0.9, FLOOR + 0.8), (0, 1, 0), (0.8, 0, 0.6), (-0.6, 0, 0.8), (0.6, 0.7, 0.3), (0.35, 0.22, 0.12))
    k.add(p)
    p = k.piece("log", "stump")
    p.log((0.6, -0.3, FLOOR), (0.6, -0.3, FLOOR + 0.6), 0.32, rng=k.rng, taper=0.0)
    k.add(p)
    p = k.piece("dark", "anvil")
    p.box((0.6, -0.3, FLOOR + 0.68), (0.32, 0.22, 0.16), IRON)
    p.box((0.6, -0.3, FLOOR + 0.84), (0.56, 0.24, 0.12), IRON)
    p.obox((0.98, -0.3, FLOOR + 0.84), (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.22, 0.12, 0.08), IRON) # (the horn)
    p.box((0.65, -0.55, FLOOR + 0.95), (0.4, 0.04, 0.04), DARK) # (a hammer laid by it)
    p.box((0.48, -0.55, FLOOR + 0.95), (0.1, 0.08, 0.08), IRON)
    k.add(p)
    barrel(k, 1.6, 0.3, r=0.35, h=0.6) # (the quench tub)
    p = k.piece("dark", "bars")
    for i in range(6):
        p.box((1.7, -1.2 + i * 0.07, FLOOR + 0.05 + (i % 2) * 0.05), (1.4, 0.04, 0.04), IRON)
    for i in range(5):
        p.obox((-0.8 + i * 0.35, d * 0.5 - 0.25, 1.8), (1, 0, 0), (0, 0, 1), (0, -1, 0), (0.18, 0.18, 0.02), IRON) # (shoes on the back wall)
    k.add(p)


def _felcer_extra(k, w, d):
    # a pole with a white flag and a green cross on it, a line of bandages drying, a stretcher leant on
    # the wall, herb bundles under the eave, a bench
    p = k.piece("wood", "pole")
    p.log((w * 0.5 + 0.7, -d * 0.5 - 0.6, 0.0), (w * 0.5 + 0.7, -d * 0.5 - 0.6, 4.4), 0.05, rng=k.rng, taper=0.1)
    k.add(p)
    p = k.piece("cloth", "flag")
    fx = w * 0.5 + 0.7 + 0.55
    p.box((fx, -d * 0.5 - 0.6, 3.9), (1.0, 0.02, 0.7), (0.92, 0.9, 0.86))
    p.box((fx, -d * 0.5 - 0.62, 3.9), (0.6, 0.02, 0.16), (0.15, 0.45, 0.2)) # (a green cross: the healer's sign)
    p.box((fx, -d * 0.5 - 0.62, 3.9), (0.16, 0.02, 0.5), (0.15, 0.45, 0.2))
    k.add(p)
    p = k.piece("cloth", "bandages")
    p.box((-w * 0.5 - 1.2, 0.0, 1.75), (0.02, 2.6, 0.02), DARK)
    for i in range(6):
        p.box((-w * 0.5 - 1.2, -1.1 + i * 0.44, 1.5), (0.02, 0.14, 0.5), (0.92, 0.9, 0.85))
    k.add(p)
    p = k.piece("wood")
    for yy in (-1.3, 1.3):
        p.box((-w * 0.5 - 1.2, yy, 0.9), (0.06, 0.06, 1.8), DARK)
    k.add(p)
    p = k.piece("cloth", "stretcher")
    p.obox((w * 0.5 + 0.25, 0.6, 1.0), (0, 1, 0), (0.95, 0, 0.3), (-0.3, 0, 0.95), (0.6, 0.06, 1.9), (0.5, 0.47, 0.36))
    for sy in (-0.3, 0.3):
        p.obox((w * 0.5 + 0.25, 0.6 + sy, 1.0), (0, 1, 0), (0.95, 0, 0.3), (-0.3, 0, 0.95), (0.05, 0.05, 2.2), DARK)
    k.add(p)
    p = k.piece("thatch", "herbs")
    for i in range(6):
        p.obox((-w * 0.5 + 0.6 + i * 0.7, -d * 0.5 - 0.35, 2.15), (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.16, 0.16, 0.45), (0.45, 0.5, 0.25) if i % 2 else (0.55, 0.45, 0.3))
    k.add(p)


MORTAR = (0.6, 0.58, 0.53)
DRESSED = (0.66, 0.64, 0.58)
ROOF_IRON = (0.42, 0.21, 0.15)


def stone_walls(k, w, d, top, openings, thick=0.45, course=0.3, band=3):
    """Rubble-stone walls laid in courses on the plinth, up to `top`: rough blocks of a few sizes in
    mortar, a little proud and a little skewed, dressed quoins at the corners, a dressed lintel over
    and a sill under each opening. `openings` as log_walls takes them (bottom and top above the
    floor). Returns the walls' top."""
    rng = k.rng
    z0 = PLINTH_TOP
    n_courses = int(math.ceil((top - z0) / course - 1e-6))
    # which courses each opening cuts, and the dressed stones that fill in round it
    cuts = []
    for ow, oc, owid, ob, ot in openings:
        lo, hi = FLOOR + ob, FLOOR + ot
        cs = [c for c in range(n_courses) if z0 + (c + 1) * course > lo + 1e-6 and z0 + c * course < hi - 1e-6]
        if z0 + (cs[-1] + 1) * course - hi < 0.15 and cs[-1] + 1 < n_courses:
            cs.append(cs[-1] + 1)
        cuts.append((ow, oc, owid, lo, hi, set(cs), z0 + cs[0] * course, z0 + (cs[-1] + 1) * course))
    walls = {
        "front": (Vector((1, 0, 0)), Vector((0, -1, 0)), -d * 0.5, (-w * 0.5, w * 0.5)),
        "back": (Vector((1, 0, 0)), Vector((0, 1, 0)), d * 0.5, (-w * 0.5, w * 0.5)),
        "left": (Vector((0, 1, 0)), Vector((-1, 0, 0)), -w * 0.5, (-d * 0.5 + thick, d * 0.5 - thick)),
        "right": (Vector((0, 1, 0)), Vector((1, 0, 0)), w * 0.5, (-d * 0.5 + thick, d * 0.5 - thick)),
    }
    up = Vector((0, 0, 1))
    for wall, (along, out, plane, span) in walls.items():
        face0 = out * abs(plane) # (a point on the wall's outer face)
        for b0 in range(0, n_courses, band):
            p = k.piece("stone", "wall")
            for c in range(b0, min(b0 + band, n_courses)):
                zc = z0 + (c + 0.5) * course
                holes = [(oc - owid * 0.5, oc + owid * 0.5) for ow, oc, owid, lo, hi, cs, a, b in cuts if ow == wall and c in cs]
                for s0, s1 in _cut(span, holes):
                    # the mortar bed and the wall's core behind the face stones
                    mid = (s0 + s1) * 0.5
                    p.obox(face0 + along * mid - out * (thick * 0.5 + 0.02) + up * zc, along, out, up, (s1 - s0, thick - 0.04, course), jit(MORTAR, 0.03, rng))
                    # the face stones, running bond
                    s = s0
                    first = True
                    while s < s1 - 0.05:
                        ln = rng.uniform(0.3, 0.62)
                        if first:
                            ln = 0.22 + 0.18 * ((c + (1 if wall in ("left", "right") else 0)) % 2)
                            first = False
                        if s1 - (s + ln) < 0.2:
                            ln = s1 - s
                        hgt = course - rng.uniform(0.025, 0.05)
                        col = jit(STONE, 0.14, rng)
                        if rng.random() < 0.25:
                            col = (col[0] * 1.06, col[1] * 1.0, col[2] * 0.9) # (a warmer, rustier stone)
                        tilt = rng.uniform(-0.03, 0.03)
                        a2 = Matrix.Rotation(tilt, 3, out) @ along
                        u2 = Matrix.Rotation(tilt, 3, out) @ up
                        ctr = face0 + along * (s + ln * 0.5) - out * (0.1 - rng.uniform(0.0, 0.025)) + up * (zc + rng.uniform(-0.01, 0.01))
                        p.obox(ctr, a2, out, u2, (ln - 0.03, 0.2, hgt), col)
                        s += ln
            k.add(p)
    # quoins: dressed blocks at the corners, long on the front and back walls and on the ends in turn
    p = k.piece("stone", "quoin")
    for c in range(n_courses):
        zc = z0 + (c + 0.5) * course
        long_x = c % 2 == 0
        for sx in (-1, 1):
            for sy in (-1, 1):
                lx, ly = (0.6, thick + 0.02) if long_x else (thick + 0.02, 0.6)
                p.box((sx * (w * 0.5 - lx * 0.5 + 0.015), sy * (d * 0.5 - ly * 0.5 + 0.015), zc), (lx, ly, course - 0.025), jit(DRESSED, 0.05, rng))
    k.add(p)
    # lintels and sills
    p = k.piece("stone", "lintel")
    for ow, oc, owid, lo, hi, cs, bot, topc in cuts:
        along, out, plane, span = walls[ow]
        face0 = out * abs(plane)
        p.obox(face0 + along * oc - out * (thick * 0.5 - 0.02) + up * (hi + topc) * 0.5, along, out, up, (owid + 0.36, thick + 0.04, topc - hi), jit(DRESSED, 0.04, rng))
        if lo - bot > 0.01:
            p.obox(face0 + along * oc - out * (thick * 0.5 - 0.04) + up * (lo + bot) * 0.5, along, out, up, (owid + 0.12, thick + 0.08, lo - bot), jit(DRESSED, 0.04, rng))
    k.add(p)
    return z0 + n_courses * course


def hip_roof(k, w, d, wall_top, over=0.35, pitch=0.46, color=ROOF_IRON, seam=0.42):
    """A low hipped roof of painted sheet iron: four slopes on rafters off the walls' outer edge, the
    sheets' standing seams running down them, rolled caps along the hips and the ridge, a fascia
    board along the eaves. Returns the ridge's height."""
    rng = k.rng
    tp = math.tan(pitch)
    hw, hd = w * 0.5 + over, d * 0.5 + over
    eave = wall_top - over * tp
    rl = hw - hd
    rz = eave + hd * tp
    th = 0.06

    def slab(p, pts, col):
        pts = [Vector(q) for q in pts]
        nrm = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
        if nrm.z < 0:
            pts.reverse()
            nrm = -nrm
        bm = p.bm
        a = [bm.verts.new(q) for q in pts]
        b = [bm.verts.new(q - nrm * th) for q in pts]
        faces = [bm.faces.new(a), bm.faces.new(list(reversed(b)))]
        for i in range(len(pts)):
            j = (i + 1) % len(pts)
            faces.append(bm.faces.new([b[i], b[j], a[j], a[i]]))
        for f in faces:
            f.normal_update()
        p._paint(faces, col)
        return nrm

    base = jit(color, 0.04, rng)
    seam_c = (base[0] * 0.78, base[1] * 0.78, base[2] * 0.78)
    for sy in (-1, 1):
        p = k.piece("shingle", "roof")
        nrm = slab(p, [(-hw, sy * hd, eave), (hw, sy * hd, eave), (rl, 0, rz), (-rl, 0, rz)], base)
        dn = Vector((0, sy * math.cos(pitch), -math.sin(pitch)))
        x = -hw + seam
        while x < hw - 0.1:
            ln = (hd if abs(x) <= rl else hd - (abs(x) - rl)) / math.cos(pitch)
            top = Vector((x, sy * (hd - ln * math.cos(pitch)), eave + ln * math.sin(pitch)))
            if ln > 0.15:
                p.obox(top + dn * (ln * 0.5) + nrm * 0.02, (1, 0, 0), dn, nrm, (0.03, ln - 0.06, 0.04), seam_c)
            x += seam
        k.add(p)
    for sx in (-1, 1):
        p = k.piece("shingle", "roof")
        nrm = slab(p, [(sx * hw, -hd, eave), (sx * hw, hd, eave), (sx * rl, 0, rz)], base)
        dn = Vector((sx * math.cos(pitch), 0, -math.sin(pitch)))
        y = -hd + seam
        while y < hd - 0.1:
            ln = (hd - abs(y)) / math.cos(pitch)
            top = Vector((sx * (hw - ln * math.cos(pitch)), y, eave + ln * math.sin(pitch)))
            if ln > 0.15:
                p.obox(top + dn * (ln * 0.5) + nrm * 0.02, (0, 1, 0), dn, nrm, (0.03, ln - 0.06, 0.04), seam_c)
            y += seam
        k.add(p)
    # the ridge and hip caps, the fascia, the rafter ends under the eaves
    p = k.piece("shingle", "ridge")
    cap = (base[0] * 0.7, base[1] * 0.7, base[2] * 0.7)
    cyl(p, (-rl - 0.04, 0, rz + 0.0), (rl + 0.04, 0, rz + 0.0), 0.055, cap, segs=8)
    for sx in (-1, 1):
        for sy in (-1, 1):
            cyl(p, (sx * rl, 0, rz), (sx * hw, sy * hd, eave), 0.05, cap, segs=8)
    k.add(p)
    p = k.piece("plank", "fascia")
    for sy in (-1, 1):
        p.box((0, sy * (hd - 0.02), eave - th - 0.06), (2 * hw, 0.04, 0.14), jit(DARK, 0.05, rng))
    for sx in (-1, 1):
        p.box((sx * (hw - 0.02), 0, eave - th - 0.06), (0.04, 2 * hd - 0.04, 0.14), jit(DARK, 0.05, rng))
    for sy in (-1, 1):
        for i in range(9):
            x = -w * 0.5 + 0.2 + i * (w - 0.4) / 8
            run = over + 0.05
            ctr = Vector((x, sy * (d * 0.5 + over * 0.5 - 0.03), wall_top - th - 0.05 - (over * 0.5) * tp))
            dn = Vector((0, sy * math.cos(pitch), -math.sin(pitch)))
            p.obox(ctr, (1, 0, 0), dn, Vector((1, 0, 0)).cross(dn) * -sy, (0.07, run / math.cos(pitch), 0.1), jit(DARK, 0.05, rng))
    k.add(p)
    return rz


def barred_window(k, wall, at, w, d, bottom, height, width, thick=0.45):
    """A small high window: a dark pane deep in the wall, a grille of iron bars at the face, its
    bars run up into the lintel and down into the sill."""
    hx, hy = w * 0.5, d * 0.5
    if wall in ("front", "back"):
        s = -1 if wall == "front" else 1
        along, out = Vector((1, 0, 0)), Vector((0, s, 0))
        o = Vector((at, s * hy, 0))
    else:
        s = -1 if wall == "left" else 1
        along, out = Vector((0, 1, 0)), Vector((s, 0, 0))
        o = Vector((s * hx, at, 0))
    up = Vector((0, 0, 1))
    zc = FLOOR + bottom + height * 0.5
    g = k.piece("window")
    g.obox(o - out * (thick * 0.6) + up * zc, along, out, up, (width + 0.04, 0.04, height + 0.04), (0.16, 0.18, 0.18))
    k.add(g)
    p = k.piece("dark", "bars")
    nb = 4
    for i in range(nb):
        t = -width * 0.5 + (i + 0.5) * width / nb
        p.obox(o - out * 0.08 + along * t + up * zc, along, out, up, (0.03, 0.03, height + 0.16), IRON)
    for z in (zc - height * 0.18, zc + height * 0.18):
        p.obox(o - out * 0.06 + up * z, along, out, up, (width + 0.1, 0.012, 0.035), IRON)
    k.add(p)


def hapishane():
    """The lock-up: squat walls of rubble stone in mortar with dressed quoins, a low hipped roof of
    red-painted sheet iron, small high barred windows, a heavy plank door banded in iron with a
    padlocked hasp and a barred judas hatch, a board over it, a lantern on a bracket, a whitewashed
    flue, a guard's bench and stool by the door."""
    w, d = 5.0, 4.0
    k = Kit("hapishane")
    rng = k.rng
    plinth(k, w, d)
    floor(k, w, d)
    thick = 0.45
    door_w, door_h = 1.0, 2.0
    win = [("left", 0.0), ("right", 0.0), ("back", -1.2), ("back", 1.2), ("front", 1.3)]
    openings = [("front", 0.0, door_w, -0.12, door_h)] + [(wl, at, 0.55, 1.55, 1.95) for wl, at in win]
    top = stone_walls(k, w, d, 3.35, openings, thick=thick)
    for wl, at in win:
        barred_window(k, wl, at, w, d, 1.55, 0.4, 0.55, thick)
    ridge = hip_roof(k, w, d, top)
    # the threshold stone and a step before it
    p = k.piece("stone", "step")
    p.box((0, -d * 0.5 + thick * 0.5, (PLINTH_TOP + FLOOR) * 0.5), (door_w, thick, FLOOR - PLINTH_TOP), jit(DRESSED, 0.04, rng))
    p.box((0, -d * 0.5 - 0.35, 0.12), (door_w + 0.4, 0.5, 0.24), jit(DRESSED, 0.05, rng))
    k.add(p)
    # the door frame of squared timber in the opening, the heavy door in it
    dy = -d * 0.5 + 0.14
    p = k.piece("dark", "doorframe")
    for sx in (-1, 1):
        p.box((sx * (door_w * 0.5 - 0.05), dy + 0.06, FLOOR + door_h * 0.5), (0.1, 0.2, door_h), jit(DARK, 0.05, rng))
    p.box((0, dy + 0.06, FLOOR + door_h - 0.05), (door_w, 0.2, 0.1), jit(DARK, 0.05, rng))
    k.add(p)
    leaf_w, leaf_h = door_w - 0.2, door_h - 0.1
    p = k.piece("plank", "door")
    n = 5
    for i in range(n):
        bx = -leaf_w * 0.5 + (i + 0.5) * leaf_w / n
        p.box((bx, dy, FLOOR + leaf_h * 0.5), (leaf_w / n - 0.01, 0.07, leaf_h), jit((0.4, 0.3, 0.2), 0.08, rng))
    fy = dy - 0.045
    for zz in (0.25, leaf_h * 0.5, leaf_h - 0.25): # (iron straps, strap hinges running off the left side)
        p.box((-0.03, fy, FLOOR + zz), (leaf_w + 0.04, 0.02, 0.09), IRON)
        for i in range(6):
            p.box((-leaf_w * 0.5 + 0.08 + i * (leaf_w - 0.16) / 5, fy - 0.015, FLOOR + zz), (0.03, 0.015, 0.03), RIVET)
        p.box((-leaf_w * 0.5 - 0.04, fy + 0.01, FLOOR + zz), (0.06, 0.05, 0.12), IRON) # (the hinge pin's knuckle)
    diag = math.atan2(leaf_h * 0.5 - 0.25, leaf_w - 0.15)
    for z0 in (0.25, leaf_h * 0.5):
        p.obox((0, fy + 0.002, FLOOR + z0 + (leaf_h * 0.5 - 0.25) * 0.5), (math.cos(diag), 0, math.sin(diag)), (0, 1, 0), (-math.sin(diag), 0, math.cos(diag)),
               (math.hypot(leaf_w - 0.15, leaf_h * 0.5 - 0.25), 0.015, 0.06), IRON)
    # the judas hatch: a small iron-framed opening, barred, a little shutter hung open beside it
    hz = FLOOR + 1.5
    p.box((0, fy - 0.005, hz), (0.26, 0.02, 0.2), IRON)
    p.box((0, fy - 0.004, hz), (0.2, 0.022, 0.14), (0.05, 0.05, 0.05))
    for t in (-0.06, 0.0, 0.06):
        p.box((t, fy - 0.02, hz), (0.015, 0.015, 0.16), IRON)
    p.box((0.22, fy - 0.02, hz), (0.18, 0.02, 0.16), (0.36, 0.27, 0.18))
    # the hasp and staple, a heavy padlock hanging from it, a drawbolt
    p.box((leaf_w * 0.5 - 0.08, fy - 0.01, FLOOR + 1.05), (0.24, 0.025, 0.06), IRON)
    p.box((leaf_w * 0.5 - 0.06, fy - 0.035, FLOOR + 0.95), (0.13, 0.05, 0.11), (0.2, 0.19, 0.17))
    cyl(p, (leaf_w * 0.5 - 0.1, fy - 0.035, FLOOR + 1.0), (leaf_w * 0.5 - 0.1, fy - 0.035, FLOOR + 1.06), 0.012, IRON, segs=6)
    cyl(p, (leaf_w * 0.5 - 0.02, fy - 0.035, FLOOR + 1.0), (leaf_w * 0.5 - 0.02, fy - 0.035, FLOOR + 1.06), 0.012, IRON, segs=6)
    p.box((0.05, fy - 0.01, FLOOR + 0.62), (0.4, 0.03, 0.05), IRON)
    p.box((-0.1, fy - 0.035, FLOOR + 0.62), (0.03, 0.03, 0.1), IRON) # (its knob)
    k.add(p)
    # the staple on the frame the hasp goes over
    p = k.piece("dark", "staple")
    p.box((door_w * 0.5 - 0.05, dy - 0.05, FLOOR + 1.05), (0.06, 0.04, 0.08), IRON)
    k.add(p)
    # a board over the door, lettered
    p = k.piece("plank", "sign")
    p.box((0, -d * 0.5 - 0.075, 2.64), (1.3, 0.04, 0.18), jit((0.82, 0.8, 0.72), 0.03, rng))
    p.box((0, -d * 0.5 - 0.065, 2.64), (1.36, 0.04, 0.23), jit(DARK, 0.04, rng))
    for i in range(7):
        p.box((-0.54 + i * 0.18, -d * 0.5 - 0.098, 2.64), (0.07, 0.01, 0.1), INK)
    k.add(p)
    # the lantern on a scrolled bracket left of the door
    lx = -1.0
    p = k.piece("dark", "bracket")
    p.box((lx, -d * 0.5 - 0.02, 2.5), (0.12, 0.04, 0.22), IRON) # (the wall plate)
    p.box((lx, -d * 0.5 - 0.2, 2.58), (0.035, 0.36, 0.035), IRON) # (the arm)
    p.obox((lx, -d * 0.5 - 0.12, 2.47), (0, 0.7, 0.7), (1, 0, 0), (0, -0.7, 0.7), (0.025, 0.025, 0.26), IRON) # (its stay)
    p.box((lx, -d * 0.5 - 0.34, 2.52), (0.02, 0.02, 0.12), IRON) # (the hook)
    cx, cy, cz = lx, -d * 0.5 - 0.34, 2.24
    p.box((cx, cy, cz + 0.2), (0.2, 0.2, 0.04), IRON) # (the lantern's cap)
    p.box((cx, cy, cz + 0.25), (0.12, 0.12, 0.06), IRON)
    p.box((cx, cy, cz - 0.16), (0.18, 0.18, 0.04), IRON) # (its base)
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((cx + sx * 0.08, cy + sy * 0.08, cz + 0.02), (0.02, 0.02, 0.36), IRON)
    k.add(p)
    p = k.piece("window", "lamp")
    p.box((cx, cy, cz + 0.02), (0.14, 0.14, 0.32), (1.0, 0.85, 0.55))
    k.add(p)
    # the flue: whitewashed brick up out of the back wall through the roof, a cap on it
    fx, fy2 = 0.3, d * 0.5 - thick * 0.5
    ftop = ridge + 0.35
    z = top - 0.3
    p = k.piece("stone", "chimney")
    c = 0
    while z < ftop - 0.13:
        p.box((fx, fy2, z + 0.06), (0.5 + (0.01 if c % 2 else 0), 0.5 + (0 if c % 2 else 0.01), 0.12), jit(WHITEWASH, 0.04, rng))
        z += 0.12
        c += 1
    k.add(p)
    p = k.piece("stone", "chimneytop")
    p.box((fx, fy2, z + 0.06), (0.62, 0.62, 0.12), jit(WHITEWASH, 0.03, rng))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((fx + sx * 0.18, fy2 + sy * 0.18, z + 0.22), (0.12, 0.12, 0.2), jit((0.55, 0.3, 0.22), 0.06, rng))
    p.box((fx, fy2, z + 0.36), (0.6, 0.6, 0.06), jit(IRON, 0.05, rng))
    k.add(p)
    # the guard's bench under the front window, his stool, a water bucket, a rifle leant up by the door
    p = k.piece("plank", "bench")
    by = -d * 0.5 - 0.58
    p.box((1.35, by, 0.46), (1.3, 0.34, 0.06), jit(PLANK, 0.05, rng))
    for sx in (-0.5, 0.5):
        p.box((1.35 + sx, by, 0.215), (0.07, 0.28, 0.43), jit(DARK, 0.05, rng))
    p.box((1.35, by, 0.12), (1.0, 0.05, 0.05), jit(DARK, 0.05, rng))
    k.add(p)
    p = k.piece("wood", "stool")
    sx0, sy0 = -1.55, -d * 0.5 - 0.55
    cyl(p, (sx0, sy0, 0.42), (sx0, sy0, 0.47), 0.18, jit(PLANK, 0.05, rng), segs=12)
    for i in range(3):
        a = i / 3 * math.tau
        p.log((sx0 + math.cos(a) * 0.17, sy0 + math.sin(a) * 0.17, 0.0), (sx0 + math.cos(a) * 0.1, sy0 + math.sin(a) * 0.1, 0.43), 0.022, color=DARK, rng=rng, taper=0.0, bow=0.0)
    k.add(p)
    p = k.piece("wood", "bucket")
    cyl(p, (-2.05, -d * 0.5 - 0.5, 0.0), (-2.05, -d * 0.5 - 0.5, 0.3), 0.14, jit(PLANK, 0.06, rng), segs=12, taper=-0.15)
    cyl(p, (-2.05, -d * 0.5 - 0.5, 0.06), (-2.05, -d * 0.5 - 0.5, 0.09), 0.15, IRON, segs=12)
    cyl(p, (-2.05, -d * 0.5 - 0.5, 0.22), (-2.05, -d * 0.5 - 0.5, 0.25), 0.16, IRON, segs=12)
    k.add(p)
    p = k.piece("dark", "rifle")
    rx, ry = 0.78, -d * 0.5 - 0.12
    a, b = Vector((rx, -d * 0.5 - 0.42, 0.0)), Vector((rx, -d * 0.5 - 0.03, 1.2))
    dv = (b - a).normalized()
    p.obox(a + dv * 0.3, (1, 0, 0), dv, Vector((1, 0, 0)).cross(dv), (0.05, 0.6, 0.1), (0.38, 0.26, 0.15)) # (the stock)
    p.obox(a + dv * 0.85, (1, 0, 0), dv, Vector((1, 0, 0)).cross(dv), (0.03, 0.55, 0.03), IRON) # (the barrel)
    k.add(p)
    k.finish()


# --- each one its own: board walls, a gambrel, a blockhouse, a schoolhouse, a sod roof ---------------
# From the camera every log cabin with a brown shingled roof is the same brown box, so the buildings
# that aren't homes aren't log cabins: the store a red board barn under a gambrel, the armoury a
# blockhouse with its upper storey jutting out, the reading room a white clapboard schoolhouse with a
# belfry, the feldsher a low whitewashed hut under green sod, the station a yellow clapboard depot
# under a green iron roof, the smithy a stone forge under sooty iron.

BARN_RED = (0.47, 0.14, 0.09)
OCHRE = (0.8, 0.62, 0.3)
CLAP_WHITE = (0.88, 0.87, 0.82)
SLATE = (0.34, 0.36, 0.4)
SOD = (0.3, 0.4, 0.15)
BIRCH = (0.88, 0.86, 0.8)
GREY_LOG = (0.36, 0.33, 0.3)
GREY_END = (0.58, 0.53, 0.46)
LIMEWASH = (0.86, 0.85, 0.8)
TRIM_BROWN = (0.32, 0.2, 0.12)
RAIL_GREEN = (0.2, 0.34, 0.26)
SOOT = (0.16, 0.16, 0.17)
BRASS = (0.62, 0.48, 0.2)


def rbox(p, c, a, b, size, col):
    """A box on two axes and their cross (always right-handed, so its faces wind outward): `size`
    along a, b and a x b."""
    a = Vector(a).normalized()
    b = Vector(b).normalized()
    return p.obox(c, a, b, a.cross(b), size, col)


def slab(p, pts, thick, col):
    """A flat polygon (its points in order round it) made `thick`, centred on its plane."""
    pts = [Vector(q) for q in pts]
    nrm = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized()
    a = [p.bm.verts.new(q + nrm * thick * 0.5) for q in pts]
    b = [p.bm.verts.new(q - nrm * thick * 0.5) for q in pts]
    faces = [p.bm.faces.new(a), p.bm.faces.new(list(reversed(b)))]
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        faces.append(p.bm.faces.new([b[i], b[j], a[j], a[i]]))
    for f in faces:
        f.normal_update()
    p._paint(faces, col)


def _wall_frame(w, d, wall):
    """A wall of a w x d building: (along it, out of it, the middle of its outer face, its span along)."""
    if wall == "front":
        return Vector((1, 0, 0)), Vector((0, -1, 0)), Vector((0, -d * 0.5, 0)), (-w * 0.5, w * 0.5)
    if wall == "back":
        return Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, d * 0.5, 0)), (-w * 0.5, w * 0.5)
    if wall == "left":
        return Vector((0, 1, 0)), Vector((-1, 0, 0)), Vector((-w * 0.5, 0, 0)), (-d * 0.5, d * 0.5)
    return Vector((0, 1, 0)), Vector((1, 0, 0)), Vector((w * 0.5, 0, 0)), (-d * 0.5, d * 0.5)


def board_walls(k, w, d, top, openings, color, vertical=False, trim=None, core=None):
    """Walls of sawn boards on a frame, from the plinth up to `top`: clapboards lapped in rows, their
    feet kicked out (or, `vertical`, upright boards with battens over the joints), a sheathing behind,
    both cut round the openings (as log_walls takes them); corner boards and a plate in `trim`.
    Stuff plank, tag "wall": they go up with the walls."""
    rng = k.rng
    up = Vector((0, 0, 1))
    z0 = PLINTH_TOP
    trim = trim or DARK
    core = core or (color[0] * 0.55, color[1] * 0.55, color[2] * 0.55)
    for wall in ("front", "back", "left", "right"):
        along, out, o, span = _wall_frame(w, d, wall)
        span = (span[0] + 0.08, span[1] - 0.08)
        mine = [(oc, ow, FLOOR + ob, FLOOR + ot) for wl, oc, ow, ob, ot in openings if wl == wall]
        if not vertical:
            row = 0.2
            n = int(math.ceil((top - z0) / row - 1e-6))
            for r0 in range(0, n, 5):
                p = k.piece("plank", "wall")
                for r in range(r0, min(n, r0 + 5)):
                    za, zb = z0 + r * row, min(z0 + (r + 1) * row, top)
                    zc = (za + zb) * 0.5
                    holes = [(oc - ow * 0.5, oc + ow * 0.5) for oc, ow, lo, hi in mine if lo < zb - 0.01 and hi > za + 0.01]
                    kick = (up - out * 0.12).normalized()
                    for s0, s1 in _cut(span, holes):
                        mid = (s0 + s1) * 0.5
                        rbox(p, o + along * mid - out * 0.1 + up * zc, along, up, (s1 - s0, zb - za, 0.16), core)
                        c = jit(color, 0.035, rng)
                        rbox(p, o + along * mid - out * 0.005 + up * zc, along, kick, (s1 - s0, row + 0.035, 0.028), c)
                k.add(p)
        else:
            bw = 0.3
            m = max(1, int((span[1] - span[0]) / bw))
            step = (span[1] - span[0]) / m
            for g0 in range(0, m, 5):
                p = k.piece("plank", "wall")
                for i in range(g0, min(m, g0 + 5)):
                    s0 = span[0] + i * step
                    s1 = s0 + step
                    holes = [(lo, hi) for oc, ow, lo, hi in mine if oc - ow * 0.5 < s1 - 0.03 and oc + ow * 0.5 > s0 + 0.03]
                    for za, zb in _cut((z0, top), holes):
                        zc = (za + zb) * 0.5
                        mid = (s0 + s1) * 0.5
                        rbox(p, o + along * mid - out * 0.1 + up * zc, along, up, (step, zb - za, 0.16), core)
                        rbox(p, o + along * mid + up * zc, along, up, (step - 0.012, zb - za, 0.03), jit(color, 0.05, rng))
                        if i < m - 1: # (the batten over the joint)
                            rbox(p, o + along * s1 + out * 0.025 + up * zc, along, up, (0.07, zb - za, 0.03), jit(color, 0.03, rng))
                k.add(p)
    # the corner boards and the plate along the walls' top, in the trim's colour
    p = k.piece("plank", "wall")
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = sx * (w * 0.5 + 0.0), sy * (d * 0.5 + 0.0)
            p.box((x, y, (z0 + top) * 0.5), (0.2, 0.2, top - z0), jit(trim, 0.03, rng))
    for sy in (-1, 1):
        p.box((0, sy * (d * 0.5 + 0.02), top - 0.08), (w + 0.12, 0.08, 0.16), jit(trim, 0.03, rng))
    for sx in (-1, 1):
        p.box((sx * (w * 0.5 + 0.02), 0, top - 0.08), (0.08, d + 0.12, 0.16), jit(trim, 0.03, rng))
    k.add(p)
    return top


def board_gables(k, w, d, top, profile, color, trim=None):
    """The ends (left and right: the ridge runs along x) filled in with upright boards and battens up
    to the roof's underside, `profile(y)` its height."""
    rng = k.rng
    n = int(d / 0.3)
    step = d / n
    for sx in (-1, 1):
        x = sx * w * 0.5
        p = k.piece("plank", "gable")
        for i in range(n):
            y0, y1 = -d * 0.5 + i * step, -d * 0.5 + (i + 1) * step
            h0, h1 = profile(y0) - 0.05, profile(y1) - 0.05
            if max(h0, h1) - top < 0.05:
                continue
            pts = [(x, y0, top), (x, y1, top), (x, y1, max(h1, top + 0.01)), (x, y0, max(h0, top + 0.01))]
            if sx < 0:
                pts.reverse()
            slab(p, pts, 0.05, jit(color, 0.05, rng))
            if i < n - 1:
                hm = min(h1, profile(y1)) - 0.05
                if hm - top > 0.1:
                    p.box((x + sx * 0.03, y1, (top + hm) * 0.5), (0.03, 0.07, hm - top), jit(color, 0.03, rng))
        k.add(p)


def roof_plane(k, top, across, down, width, length, color, course=0.22, moss=0.0, stuff="shingle", tag="", piece=None, shingle_w=(0.22, 0.34)):
    """One slope: its boarding, and shingles in staggered courses from `top` down it (`across` along
    its width, `down` down its fall)."""
    across, down = Vector(across).normalized(), Vector(down).normalized()
    nrm = across.cross(down)
    if nrm.z < 0:
        nrm = -nrm
    top = Vector(top)
    p = piece or k.piece(stuff, tag)
    rbox(p, top + down * (length * 0.5), across, down, (width, length, 0.05), jit(PLANK, 0.05, k.rng))
    rows = max(1, int(round(length / course)))
    for r in range(rows):
        vv = (r + 0.5) * length / rows
        x = -width * 0.5 + (0.13 if r % 2 else 0.0)
        while x < width * 0.5 - 0.05:
            sw = min(k.rng.uniform(*shingle_w), width * 0.5 - x)
            sc = shingle_colour(k, color, x, vv / length, down.y, moss * 3.0)
            tilt = Matrix.Rotation(0.07, 3, across)
            rbox(p, top + down * vv + nrm * 0.055 + across * (x + sw * 0.5), across, tilt @ down, (sw - 0.015, course * 1.5, 0.025), sc)
            x += sw
    if piece is None:
        k.add(p)
    return nrm


def plain_window(k, wall, at, w, d, width, bottom, height, trim, panes=(2, 3), sill=True, shutter=None):
    """A sash window in a board or stone wall: the glass (lit at night), glazing bars, a plain frame
    with a head and a sill in `trim`, and, `shutter` a colour, louvred shutters folded back."""
    along, out, o, span = _wall_frame(w, d, wall)
    up = Vector((0, 0, 1))
    c = o + along * at + up * (FLOOR + bottom + height * 0.5)
    g = k.piece("window")
    rbox(g, c - out * 0.04, along, up, (width, height, 0.03), GLASS)
    k.add(g)
    p = k.piece("plank", "trim")
    for sgn in (-1, 1):
        rbox(p, c + along * sgn * (width * 0.5 + 0.05), along, up, (0.1, height + 0.2, 0.08), jit(trim, 0.02, k.rng))
    rbox(p, c + up * (height * 0.5 + 0.1), along, up, (width + 0.34, 0.14, 0.1), jit(trim, 0.02, k.rng))
    rbox(p, c + up * (height * 0.5 + 0.2) + out * 0.02, along, up, (width + 0.44, 0.05, 0.14), jit(trim, 0.02, k.rng))
    if sill:
        rbox(p, c - up * (height * 0.5 + 0.06) + out * 0.04, along, up, (width + 0.3, 0.06, 0.16), jit(trim, 0.02, k.rng))
    nx, nz = panes
    for i in range(1, nx):
        rbox(p, c - out * 0.02 + along * (-width * 0.5 + i * width / nx), along, up, (0.025, height, 0.03), trim)
    for j in range(1, nz):
        rbox(p, c - out * 0.02 + up * (-height * 0.5 + j * height / nz), along, up, (width, 0.025, 0.03), trim)
    k.add(p)
    if shutter:
        p = k.piece("plank", "shutter")
        for sgn in (-1, 1):
            sc = c + along * sgn * (width * 0.75 + 0.12) + out * 0.04
            rbox(p, sc, along, up, (width * 0.5, height + 0.1, 0.03), jit(shutter, 0.04, k.rng))
            for j in range(int(height / 0.09)):
                rbox(p, sc + out * 0.02 + up * (-height * 0.5 + 0.05 + j * 0.09), along, up, (width * 0.44, 0.025, 0.015), jit(shutter, 0.08, k.rng))
        k.add(p)


def eave_brackets(k, w, d, top, n, color, depth=0.5):
    """Carved brackets under the eaves along the front and back, from the wall up to the roof."""
    p = k.piece("plank", "brackets")
    for sy in (-1, 1):
        for i in range(n):
            x = -w * 0.5 + (i + 0.5) * w / n
            y = sy * (d * 0.5 + depth * 0.5)
            p.box((x, y, top - 0.1), (0.08, depth, 0.1), jit(color, 0.03, k.rng))
            p.obox((x, sy * (d * 0.5 + depth * 0.3), top - 0.32), (1, 0, 0), (0, 0.7 * sy, 0.7), (0, -0.7 * sy, 0.7), (0.07, 0.55, 0.07), jit(color, 0.03, k.rng))
    k.add(p)


def bell(p, c, r, color=BRASS):
    """A cast bell hung mouth down at `c` (its crown), its lip `r` across."""
    c = Vector(c)
    p.log(c - Vector((0, 0, r * 1.25)), c, r, color=color, end=color, taper=0.55, segs=12, jitter=0.0, bow=0.0)
    cyl(p, c - Vector((0, 0, r * 1.3)), c - Vector((0, 0, r * 1.18)), r * 1.06, color, segs=12)
    p.box(c + Vector((0, 0, 0.04)), (0.06, r * 0.5, 0.08), IRON)


# -- the store: a red barn

def gambrel(k, w, d, top, over=0.45, a1=1.05, a2=0.42, knee=0.18, color=SHINGLE, wall_color=BARN_RED, trim=None):
    """A barn's roof along x: a steep lower pitch from the eaves (`a1`), a shallow upper one to the
    ridge (`a2`), the knee `knee` of the depth in; shingled, a ridge board, the gable ends boarded up
    in `wall_color` and edged with trim boards. Returns (knee z, knee y, ridge z)."""
    trim = trim or CLAP_WHITE
    yk = d * 0.5 - d * knee
    zk = top + d * knee * math.tan(a1)
    zr = zk + yk * math.tan(a2)
    width = w + over * 2
    for s in (-1, 1):
        d1 = Vector((0, s * math.cos(a1), -math.sin(a1)))
        l1 = (d * knee) / math.cos(a1) + over
        roof_plane(k, (0, s * yk, zk + 0.05), (1, 0, 0), d1, width, l1, color, moss=0.15)
        d2 = Vector((0, s * math.cos(a2), -math.sin(a2)))
        l2 = yk / math.cos(a2) + 0.12
        roof_plane(k, (0, 0, zr + 0.06), (1, 0, 0), d2, width, l2, color, moss=0.1)
    p = k.piece("shingle", "ridge")
    p.box((0, 0, zr + 0.16), (width + 0.06, 0.26, 0.08), jit(DARK, 0.05, k.rng))
    k.add(p)

    def profile(y):
        y = abs(y)
        if y >= yk:
            return top + (d * 0.5 - y) * math.tan(a1)
        return zk + (yk - y) * math.tan(a2)
    board_gables(k, w, d, top, profile, wall_color)
    # the trim boards up the gables' edges, and the fascia along the eaves
    for sx in (-1, 1):
        p = k.piece("plank", "barge")
        x = sx * (w * 0.5 + over + 0.02)
        pts = [(d * 0.5 + over * math.cos(a1), top - over * math.sin(a1)), (yk, zk), (0.0, zr)]
        for s in (-1, 1):
            for (y0, z0), (y1, z1) in zip(pts, pts[1:]):
                a, b = Vector((x, s * y0, z0 + 0.12)), Vector((x, s * y1, z1 + 0.12))
                rbox(p, (a + b) * 0.5, b - a, (0, 0, 1), ((b - a).length + 0.1, 0.2, 0.05), jit(trim, 0.02, k.rng))
        k.add(p)
    return zk, yk, zr


def _barn_extra(k, w, d, zk, zr):
    trim = CLAP_WHITE
    # the loading platform along the front on squared posts, its edge boarded, and what waits on it
    p = k.piece("plank")
    for i in range(7):
        p.box((0, -d * 0.5 - 0.15 - i * 0.22, 0.42), (w - 1.0, 0.21, 0.08), jit(PLANK, 0.08, k.rng))
    p.box((0, -d * 0.5 - 1.63, 0.33), (w - 1.0, 0.06, 0.26), jit(DARK, 0.05, k.rng))
    k.add(p)
    for x, y in [(-w * 0.5 + 0.9, -d * 0.5 - 0.9), (-w * 0.5 + 1.75, -d * 0.5 - 0.85), (w * 0.5 - 1.0, -d * 0.5 - 0.9)]:
        crate(k, x, y, 0.46)
    crate(k, -w * 0.5 + 1.3, -d * 0.5 - 0.88, 1.16, 0.55)
    barrel(k, w * 0.5 - 1.9, -d * 0.5 - 0.95, 0.46)
    p = k.piece("wood", "sacks")
    for i in range(5):
        x = -0.4 + i * 0.4 + (0.2 if i > 2 else 0) + 2.2
        y = -d * 0.5 - 1.0 - (0.3 if i > 2 else 0)
        z = 0.7 + (0.36 if i == 4 else 0)
        burlap = jit((0.62, 0.53, 0.38), 0.06, k.rng)
        p.stone((x, y, z), (0.4, 0.34, 0.46), color=burlap, rng=k.rng, subdiv=2)
        p.log((x, y, z + 0.2), (x, y, z + 0.3), 0.055, color=burlap, end=burlap, segs=6, rng=k.rng, taper=0.3)
    k.add(p)
    # the store's board over the doors, white with dark letters
    p = k.piece("dark", "sign")
    p.box((0, -d * 0.5 - 0.06, FLOOR + 2.62), (2.6, 0.05, 0.42), jit(trim, 0.03, k.rng))
    for i in range(5):
        p.box((-0.8 + i * 0.4, -d * 0.5 - 0.09, FLOOR + 2.62), (0.24, 0.02, 0.24), INK)
    k.add(p)
    # the hay door high in the right gable, and the hoist beam over it under the ridge, a rope and pulley
    x = w * 0.5 + 0.03
    p = k.piece("plank", "loft")
    for i in range(5):
        p.box((x, -0.48 + i * 0.24, zk - 0.35), (0.04, 0.22, 1.3), jit(BARN_RED, 0.08, k.rng))
    for sy in (-1, 1):
        p.box((x + 0.02, sy * 0.66, zk - 0.35), (0.04, 0.12, 1.5), jit(trim, 0.02, k.rng))
    p.box((x + 0.02, 0, zk + 0.4), (0.04, 1.44, 0.12), jit(trim, 0.02, k.rng))
    k.add(p)
    p = k.piece("log", "hoist")
    p.log((w * 0.5 + 1.3, 0.0, zr - 0.55), (w * 0.5 - 0.8, 0.0, zr - 0.55), 0.12, rng=k.rng)
    p.log((w * 0.5 + 1.2, 0.0, zr - 0.62), (w * 0.5 + 1.2, 0.0, zk - 1.2), 0.012, color=(0.6, 0.5, 0.35), end=(0.6, 0.5, 0.35), segs=5)
    p.log((w * 0.5 + 1.15, 0.0, zr - 0.72), (w * 0.5 + 1.25, 0.0, zr - 0.72), 0.09, color=DARK, end=DARK, taper=0.0)
    k.add(p)
    # a weathervane on the ridge
    p = k.piece("dark", "finial")
    p.box((-w * 0.25, 0, zr + 0.5), (0.03, 0.03, 0.8), IRON)
    p.box((-w * 0.25, 0, zr + 0.75), (0.5, 0.02, 0.1), IRON)
    p.obox((-w * 0.25 + 0.27, 0, zr + 0.75), (0.7, 0, 0.7), (0, 1, 0), (-0.7, 0, 0.7), (0.12, 0.02, 0.12), IRON)
    k.add(p)
    woodpile(k, w * 0.5 + 0.7, d * 0.5 - 1.6, length=2.0, height=1.2)


def ambar():
    """The store: a big barn of upright boards and battens painted red, white corner boards and
    trim, under a gambrel roof; wide double doors, small square windows, a hay door in the gable
    with a hoist beam over it, a loading platform with crates and sacks."""
    w, d = 9.0, 7.0
    k = Kit("ambar")
    k.paint = (CLAP_WHITE, BARN_RED)
    plinth(k, w, d)
    floor(k, w, d)
    top = FLOOR + 3.0
    door_w, door_h = 2.4, 2.15
    wins = [("left", -1.5), ("left", 1.5), ("right", -1.5), ("back", -2.5), ("back", 2.5), ("front", -3.0), ("front", 3.0)]
    openings = [("front", 0.0, door_w + 0.2, -0.2, door_h + 0.1)] + [(wl, at, 0.7, 1.15, 1.85) for wl, at in wins]
    board_walls(k, w, d, top, openings, BARN_RED, vertical=True, trim=CLAP_WHITE)
    zk, yk, zr = gambrel(k, w, d, top, color=(0.36, 0.33, 0.3))
    door(k, -door_w * 0.25, -d * 0.5 + 0.1, door_w * 0.5, door_h)
    door(k, door_w * 0.25, -d * 0.5 + 0.1, door_w * 0.5, door_h)
    for wl, at in wins:
        plain_window(k, wl, at, w, d, 0.62, 1.2, 0.62, CLAP_WHITE, panes=(2, 2))
    _barn_extra(k, w, d, zk, zr)
    k.finish()


# -- the armoury: a blockhouse

def silahlik():
    """The armoury: a blockhouse of weathered grey logs, its upper storey jutting out half a metre
    all round over the lower on joists (to fire down the walls), loopholes in both storeys, a low
    hipped roof, a flagstaff on its peak; the rifle rack, ammunition boxes and a target outside."""
    w, d = 5.0, 4.0
    k = Kit("silahlik")
    k.paint = ((0.8, 0.78, 0.7), (0.3, 0.3, 0.32))
    plinth(k, w, d)
    floor(k, w, d)
    low = log_walls(k, w, d, 8, [("front", 0.0, 1.25, 0.0, 2.05)], color=GREY_LOG, end=GREY_END)
    door(k, 0.0, -d * 0.5 + 0.15, 1.0, 2.0)
    # the joists out through the walls, the upper floor on them
    p = k.piece("dark")
    for i in range(6):
        x = -w * 0.5 - 0.3 + i * (w + 0.6) / 5
        p.box((x, 0, low + 0.1), (0.22, d + 1.3, 0.2), jit(DARK, 0.05, k.rng))
    p.box((0, 0, low + 0.25), (w + 1.1, d + 1.1, 0.1), jit(DARK, 0.04, k.rng))
    k.add(p)
    W, D = w + 1.0, d + 1.0
    up_top = log_walls(k, W, D, 5, [], dia=0.28, color=GREY_LOG, end=GREY_END, base=low + 0.3)
    # loopholes: slits in the upper walls (the stuff of a window: lit from inside at night), in the lower
    p = k.piece("window", "loophole")
    for wall, ats in (("front", (-1.8, 0.0, 1.8)), ("back", (-1.8, 0.0, 1.8)), ("left", (-1.2, 1.2)), ("right", (-1.2, 1.2))):
        along, out, o, span = _wall_frame(W, D, wall)
        for at in ats:
            rbox(p, o + along * at + out * 0.02 + Vector((0, 0, low + 1.05)), along, (0, 0, 1), (0.12, 0.5, 0.03), (0.05, 0.05, 0.05))
    for wall, ats in (("front", (-1.6, 1.6)), ("left", (0.0,)), ("right", (0.0,)), ("back", (-1.0, 1.0))):
        along, out, o, span = _wall_frame(w, d, wall)
        for at in ats:
            rbox(p, o + along * at + out * 0.02 + Vector((0, 0, FLOOR + 1.4)), along, (0, 0, 1), (0.1, 0.42, 0.03), (0.05, 0.05, 0.05))
    k.add(p)
    rz = hip_roof(k, W, D, up_top, over=0.45, pitch=0.6, color=(0.33, 0.28, 0.22), seam=0.26)
    p = k.piece("dark", "flagstaff")
    p.log((0, 0, rz - 0.2), (0, 0, rz + 2.6), 0.045, color=DARK, end=DARK, rng=k.rng, taper=0.25)
    p.stone((0, 0, rz + 2.65), (0.1, 0.1, 0.1), color=BRASS, rng=k.rng)
    k.add(p)
    _arms_extra(k, w, d)
    k.finish()


# -- the reading room: a schoolhouse

def okuma():
    """The reading room: a schoolhouse of white clapboard with dark green corner boards, tall sash
    windows with green shutters, a steep slate-grey roof, an open belfry on the ridge with its bell,
    a pedimented hood over the door, a sign, a bench and a table out front, a brick flue."""
    w, d = 6.0, 5.0
    k = Kit("okuma")
    trim = RAIL_GREEN
    k.paint = (CLAP_WHITE, trim)
    plinth(k, w, d)
    floor(k, w, d)
    top = FLOOR + 3.1
    wins = [("front", -1.9), ("front", 1.9), ("left", -1.1), ("left", 1.1), ("right", -1.1), ("right", 1.1), ("back", -1.5), ("back", 1.5)]
    openings = [("front", 0.0, 1.25, -0.2, 2.25)] + [(wl, at, 0.85, 0.75, 2.35) for wl, at in wins]
    board_walls(k, w, d, top, openings, CLAP_WHITE, trim=trim)
    rise = 2.3
    half = d * 0.5
    slope = math.atan2(rise, half)
    ridge = top + rise
    for s in (-1, 1):
        down = Vector((0, s * math.cos(slope), -math.sin(slope)))
        roof_plane(k, (0, 0, ridge + 0.06), (1, 0, 0), down, w + 0.7, (half + 0.45) / math.cos(slope), SLATE, course=0.18, shingle_w=(0.18, 0.26))
    p = k.piece("shingle", "ridge")
    p.box((0, 0, ridge + 0.16), (w + 0.76, 0.24, 0.08), jit(DARK, 0.05, k.rng))
    k.add(p)
    board_gables(k, w, d, top, lambda y: top + (half - abs(y)) * math.tan(slope), CLAP_WHITE)
    for sx in (-1, 1): # (the rake boards up the gables, green)
        p = k.piece("plank", "barge")
        x = sx * (w * 0.5 + 0.37)
        for s in (-1, 1):
            a, b = Vector((x, s * (half + 0.45), top - 0.45 * math.tan(slope) + 0.12)), Vector((x, 0, ridge + 0.12))
            rbox(p, (a + b) * 0.5, b - a, (0, 0, 1), ((b - a).length, 0.22, 0.05), jit(trim, 0.02, k.rng))
        k.add(p)
    door(k, 0.0, -d * 0.5 + 0.1, 1.05, 2.15)
    for wl, at in wins:
        plain_window(k, wl, at, w, d, 0.75, 0.8, 1.5, CLAP_WHITE, panes=(2, 4), shutter=trim)
    # the hood over the door: a little pediment on two brackets
    p = k.piece("plank", "hood")
    hz = FLOOR + 2.55
    for sx in (-1, 1):
        a, b = Vector((sx * 0.85, -d * 0.5 - 0.35, hz)), Vector((0, -d * 0.5 - 0.35, hz + 0.45))
        rbox(p, (a + b) * 0.5, b - a, (0, 1, 0), ((b - a).length + 0.1, 0.75, 0.06), jit(SLATE, 0.04, k.rng))
        p.obox((sx * 0.62, -d * 0.5 - 0.2, hz - 0.25), (1, 0, 0), (0, -0.7, 0.7), (0, 0.7, 0.7), (0.07, 0.5, 0.07), jit(trim, 0.03, k.rng))
    slab(p, [(-0.8, -d * 0.5 - 0.66, hz + 0.02), (0.8, -d * 0.5 - 0.66, hz + 0.02), (0, -d * 0.5 - 0.66, hz + 0.42)], 0.04, CLAP_WHITE)
    k.add(p)
    # the belfry on the ridge: a boarded base, four posts, a pyramid cap, the bell inside
    bx = 0.0
    p = k.piece("plank", "belfry")
    p.box((bx, 0, ridge + 0.3), (0.95, 0.95, 0.7), jit(CLAP_WHITE, 0.02, k.rng))
    for sx in (-1, 1):
        for sy in (-1, 1):
            p.box((bx + sx * 0.4, sy * 0.4, ridge + 1.0), (0.1, 0.1, 0.75), jit(CLAP_WHITE, 0.02, k.rng))
    p.box((bx, 0, ridge + 0.68), (1.05, 1.05, 0.06), jit(trim, 0.02, k.rng))
    p.box((bx, 0, ridge + 1.4), (1.15, 1.15, 0.08), jit(trim, 0.02, k.rng))
    for (ax, ay), (cx, cy) in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
        slab(p, [(bx + ax * 0.62, ay * 0.62, ridge + 1.44), (bx + cx * 0.62, cy * 0.62, ridge + 1.44), (bx, 0, ridge + 2.15)], 0.04, jit(SLATE, 0.04, k.rng))
    p.box((bx, 0, ridge + 2.35), (0.03, 0.03, 0.45), IRON)
    k.add(p)
    p = k.piece("stone", "schoolbell")
    bell(p, (bx, 0, ridge + 1.3), 0.17)
    k.add(p)
    # the brick flue at the back
    p = k.piece("stone", "chimneytop")
    fx, fy = 1.6, d * 0.5 - 0.6
    p.box((fx, fy, ridge - 0.2), (0.45, 0.45, 1.2), jit((0.56, 0.3, 0.22), 0.05, k.rng))
    p.box((fx, fy, ridge + 0.45), (0.55, 0.55, 0.1), jit((0.4, 0.38, 0.35), 0.05, k.rng))
    k.add(p)
    # a table and benches out on the grass, books on it, a stack of papers by the door
    p = k.piece("plank", "table")
    tx, ty = 2.0, -d * 0.5 - 1.6
    p.box((tx, ty, 0.78), (1.4, 0.65, 0.05), jit(PLANK, 0.05, k.rng))
    for sx in (-0.6, 0.6):
        for sy in (-0.25, 0.25):
            p.box((tx + sx, ty + sy, 0.38), (0.06, 0.06, 0.76), DARK)
    for sy in (-0.65, 0.65):
        p.box((tx, ty + sy, 0.45), (1.4, 0.28, 0.05), jit(PLANK, 0.05, k.rng))
        for sx in (-0.6, 0.6):
            p.box((tx + sx, ty + sy, 0.22), (0.06, 0.24, 0.44), DARK)
    k.add(p)
    p = k.piece("cloth", "books")
    for i, c in enumerate([(0.55, 0.15, 0.1), (0.2, 0.3, 0.5), (0.3, 0.4, 0.2)]):
        p.box((tx - 0.4 + i * 0.3, ty, 0.83 + (i % 2) * 0.03), (0.2, 0.28, 0.05 + (i % 2) * 0.04), c, rot_z=i * 0.3)
    p.box((tx + 0.45, ty - 0.05, 0.82), (0.36, 0.26, 0.02), (0.9, 0.86, 0.75))
    k.add(p)
    p = k.piece("cloth", "papers")
    for i in range(4):
        p.box((-1.2, -d * 0.5 - 0.35, 0.05 + i * 0.07), (0.5, 0.36, 0.06), (0.85, 0.82, 0.72), rot_z=i * 0.15)
    k.add(p)
    # steps up to the door
    p = k.piece("plank", "steps")
    for i, (dy, z) in enumerate(((0.2, 0.3), (0.48, 0.15))):
        p.box((0, -d * 0.5 - dy, z), (1.5, 0.3, 0.06), jit(PLANK, 0.06, k.rng))
        for sx in (-1, 1):
            p.box((sx * 0.72, -d * 0.5 - dy, z * 0.5), (0.06, 0.3, z), DARK)
    k.add(p)
    k.finish()


# -- the feldsher: a whitewashed hut under sod

def sod_roof(k, w, ridge, half, slope, over=0.5, eave_over=0.55):
    """A turf roof: boards, birch bark under them showing white along the eaves, then the sod, lumpy,
    thick with grass and a few flowers, a log along the eave holding it on."""
    run = half + eave_over
    length = run / math.cos(slope)
    width = w + over * 2
    top = Vector((0, 0, ridge + 0.42))
    for side in (-1, 1):
        down = Vector((0, side * math.cos(slope), -math.sin(slope)))
        nrm = Vector((0, side * math.sin(slope), math.cos(slope)))
        across = Vector((1, 0, 0))
        p = k.piece("shingle", "sod")
        rbox(p, top + down * (length * 0.5), across, down, (width, length, 0.05), jit(PLANK, 0.05, k.rng))
        rbox(p, top + down * (length * 0.5 + 0.06) + nrm * 0.04, across, down, (width + 0.04, length + 0.08, 0.03), BIRCH)
        rbox(p, top + down * (length * 0.5 - 0.05) + nrm * 0.12, across, down, (width - 0.1, length - 0.1, 0.16), jit(SOD, 0.05, k.rng))
        for i in range(int(width * length * 5.0)):
            u = k.rng.uniform(-width * 0.47, width * 0.47)
            v = k.rng.uniform(0.1, length - 0.2)
            c = top + across * u + down * v + nrm * 0.19
            dry = 0.5 + 0.5 * math.sin(u * 0.9 + v * 1.7 + k.moss_seed) # (drier in drifts)
            col = jit(SOD, 0.1, k.rng)
            col = (col[0] * (1 + 0.35 * dry), col[1] * (1 + 0.15 * dry), col[2] * (1 - 0.15 * dry))
            p.stone(c, (k.rng.uniform(0.18, 0.32), k.rng.uniform(0.16, 0.28), 0.09), color=col, rng=k.rng)
        for i in range(int(width * length * 0.8)):
            u = k.rng.uniform(-width * 0.45, width * 0.45)
            v = k.rng.uniform(0.2, length - 0.3)
            col = k.rng.choice([(0.95, 0.85, 0.3), (0.92, 0.92, 0.88), (0.65, 0.4, 0.75)])
            p.box(top + across * u + down * v + nrm * 0.25, (0.04, 0.04, 0.04), col)
        k.add(p)
        # the turf log along the eave on hooks
        p = k.piece("log", "turflog")
        e = top + down * (length - 0.1) + nrm * 0.25
        p.log(e - across * width * 0.5, e + across * width * 0.5, 0.09, rng=k.rng)
        k.add(p)


def _herb_garden(k, x0, y0, w, d):
    """A little plot in a wattle fence: raised beds of herbs in rows."""
    p = k.piece("wood", "fence")
    for (ax, ay), (bx, by) in (((0, 0), (w, 0)), ((w, 0), (w, d)), ((w, d), (0, d)), ((0, d), (0, 0))):
        n = max(2, int(math.hypot(bx - ax, by - ay) / 0.5))
        for i in range(n + 1):
            t = i / n
            x, y = x0 + ax + (bx - ax) * t, y0 + ay + (by - ay) * t
            p.log((x, y, -0.1), (x, y, 0.65), 0.025, rng=k.rng, taper=0.1)
        for z in (0.25, 0.4, 0.55):
            p.log((x0 + ax, y0 + ay, z), (x0 + bx, y0 + by, z), 0.02, color=(0.45, 0.36, 0.24), rng=k.rng, bow=0.03)
    k.add(p)
    p = k.piece("thatch", "herbs")
    for r in range(3):
        y = y0 + 0.35 + r * (d - 0.7) / 2
        p.box((x0 + w * 0.5, y, 0.06), (w - 0.4, 0.4, 0.12), jit((0.3, 0.22, 0.15), 0.05, k.rng))
        for i in range(int((w - 0.5) / 0.28)):
            col = [(0.3, 0.45, 0.2), (0.4, 0.5, 0.25), (0.35, 0.4, 0.45), (0.55, 0.45, 0.6)][r % 4]
            p.stone((x0 + 0.35 + i * 0.28, y, 0.2), (0.22, 0.22, 0.24), color=jit(col, 0.1, k.rng), rng=k.rng)
    k.add(p)


def sifaci():
    """The feldsher's: a low hut of whitewashed logs (clean, as a sick room should be) under a turf
    roof green with grass, green shutters, a stone chimney, a white flag with a green cross, bandages
    drying, a stretcher by the wall, herbs under the eave and a fenced herb garden."""
    w, d = 5.0, 4.0
    k = Kit("sifaci")
    k.paint = ((0.92, 0.9, 0.85), (0.2, 0.45, 0.25))
    plinth(k, w, d)
    floor(k, w, d)
    wins = [("front", 1.4), ("left", 0.0), ("right", 0.0)]
    openings = [("front", -0.6, 1.25, 0.0, 2.1)] + [(wl, at, 0.95, 0.85, 1.85) for wl, at in wins]
    top = log_walls(k, w, d, 7, openings, color=LIMEWASH, end=LIMEWASH)
    ridge, half, slope = log_gables(k, w, d, top, 1.15, color=LIMEWASH, end=LIMEWASH)
    sod_roof(k, w, ridge, half, slope)
    door(k, -0.6, -d * 0.5 + 0.15, 1.0, 2.0)
    for wl, at in wins:
        window(k, wl, at, w, d)
    chimney(k, w * 0.5 + 0.45, 0.8, 0.0, ridge + 0.9, size=0.6)
    _felcer_extra(k, w, d)
    _herb_garden(k, -w * 0.5 - 0.2, -d * 0.5 - 3.2, 2.6, 2.2)
    k.finish()


# -- the station: a yellow clapboard depot

def istasyon():
    """The station: a depot of ochre clapboard with brown trim, tall windows, carved brackets under
    a wide-eaved hipped roof of green-painted iron, a bell by the door, a clock over it; the platform,
    its canopy, a bench, the name board."""
    w, d = 7.0, 5.0
    k = Kit("istasyon")
    k.paint = (TRIM_BROWN, TRIM_BROWN)
    plinth(k, w, d)
    floor(k, w, d)
    top = FLOOR + 3.5
    wins = [("front", -2.2), ("front", 2.2), ("left", 0.0), ("right", -1.0), ("right", 1.0), ("back", -2.0), ("back", 0.0), ("back", 2.0)]
    openings = [("front", 0.0, 1.35, -0.2, 2.45)] + [(wl, at, 0.85, 0.8, 2.45) for wl, at in wins]
    board_walls(k, w, d, top, openings, OCHRE, trim=TRIM_BROWN)
    eave_brackets(k, w, d, top, 6, TRIM_BROWN)
    rz = hip_roof(k, w, d, top, over=0.65, pitch=0.5, color=RAIL_GREEN, seam=0.4)
    door(k, 0.0, -d * 0.5 + 0.1, 1.1, 2.35)
    for wl, at in wins:
        plain_window(k, wl, at, w, d, 0.75, 0.85, 1.55, CLAP_WHITE, panes=(2, 3))
    # the clock over the door, the bell beside it on a bracket
    p = k.piece("plank", "clock")
    cyl(p, (0, -d * 0.5 - 0.02, FLOOR + 2.95), (0, -d * 0.5 - 0.1, FLOOR + 2.95), 0.3, TRIM_BROWN, segs=16)
    cyl(p, (0, -d * 0.5 - 0.1, FLOOR + 2.95), (0, -d * 0.5 - 0.12, FLOOR + 2.95), 0.25, CLAP_WHITE, segs=16)
    p.box((0, -d * 0.5 - 0.13, FLOOR + 3.02), (0.02, 0.01, 0.16), INK)
    p.box((0.05, -d * 0.5 - 0.13, FLOOR + 2.95), (0.12, 0.01, 0.02), INK)
    k.add(p)
    p = k.piece("dark", "bracket")
    p.box((1.05, -d * 0.5 - 0.2, FLOOR + 2.55), (0.04, 0.4, 0.04), IRON)
    p.box((1.05, -d * 0.5 - 0.02, FLOOR + 2.45), (0.12, 0.04, 0.3), IRON)
    k.add(p)
    p = k.piece("stone", "stationbell")
    bell(p, (1.05, -d * 0.5 - 0.36, FLOOR + 2.52), 0.12)
    k.add(p)
    # the flue through the roof
    p = k.piece("stone", "chimneytop")
    p.box((-1.6, 0.8, rz - 0.3), (0.45, 0.45, 1.6), jit((0.56, 0.3, 0.22), 0.05, k.rng))
    p.box((-1.6, 0.8, rz + 0.52), (0.55, 0.55, 0.1), jit((0.4, 0.38, 0.35), 0.05, k.rng))
    k.add(p)
    _station_extra(k, w, d)
    k.finish()


# -- the smithy: stone, under sooty iron

def demirci():
    """The smithy: walls of rubble stone (the fire's kept in by stone), the front open under a great
    timber lintel to let the heat and the smoke out, a hipped roof of sooty sheet iron, the forge and
    its stack up through it; a horseshoe over the opening, coal heaped by the side, a wheel waiting."""
    w, d = 5.0, 4.0
    k = Kit("demirci")
    plinth(k, w, d)
    floor(k, w, d)
    thick = 0.45
    top = stone_walls(k, w, d, 2.9, [("front", 0.0, 3.2, -0.12, 2.0), ("left", 0.6, 0.55, 1.3, 1.85), ("right", -0.5, 0.55, 1.3, 1.85)], thick=thick)
    for wl, at in (("left", 0.6), ("right", -0.5)):
        barred_window(k, wl, at, w, d, 1.3, 0.55, 0.55, thick)
    rz = hip_roof(k, w, d, top, over=0.45, pitch=0.5, color=SOOT, seam=0.38)
    _smith_props(k, w, d, stack_top=rz + 0.9)
    # a horseshoe hung over the opening, points up, for luck
    p = k.piece("dark", "shoe")
    for i in range(9):
        a = math.pi * (0.1 + 0.8 * i / 8)
        rbox(p, (math.cos(a) * 0.2, -d * 0.5 - 0.08, 2.84 - math.sin(a) * 0.2), (math.sin(a), 0, math.cos(a)), (0, 1, 0), (0.1, 0.03, 0.05), IRON)
    k.add(p)
    # coal heaped against the right wall, a cart wheel waiting for its tyre, a grindstone
    p = k.piece("stone", "coal")
    for i in range(16):
        p.stone((w * 0.5 + 0.6 + k.rng.uniform(-0.4, 0.4), -0.6 + k.rng.uniform(-0.7, 0.7), k.rng.uniform(0.05, 0.35)), (0.3, 0.25, 0.2), color=(0.1, 0.1, 0.1), rng=k.rng)
    k.add(p)
    p = k.piece("wood", "wheel")
    cart_wheel(p, Vector((-w * 0.5 - 0.25, -0.6, 0.62)), (1, 0, 0), 0.6, rng=k.rng)
    k.add(p)
    k.finish()


# --- the defences: a sandbag post, a Maxim nest, barbed wire ----------------------------------------

SACK = (0.5, 0.44, 0.31)


def sandbag(p, x, y, z, rot, rng, length=0.62):
    """A sack of earth: a fat block, its ends pinched in, a tie at one end."""
    c = jit(SACK, 0.08, rng)
    a = Vector((math.cos(rot), math.sin(rot), 0))
    b = Vector((-math.sin(rot), math.cos(rot), 0))
    p.obox((x, y, z), a, b, (0, 0, 1), (length * 0.8, 0.34, 0.2), c)
    for s in (-1, 1):
        q = Vector((x, y, z)) + a * s * length * 0.42
        p.obox(tuple(q), a, b, (0, 0, 1), (length * 0.12, 0.26, 0.15), c)
    q = Vector((x, y, z)) + a * length * 0.52
    p.obox(tuple(q), a, b, (0, 0, 1), (0.05, 0.1, 0.06), (0.35, 0.3, 0.2))


def siper():
    k = Kit("siper")
    rng = k.rng
    p = k.piece("sand", "bags")
    for c in range(3):
        z = 0.11 + c * 0.2
        for i in range(5):
            x = -1.2 + i * 0.6 + (0.3 if c % 2 else 0.0)
            if x > 1.25:
                continue
            sandbag(p, x, -0.65, z, rng.uniform(-0.06, 0.06), rng)
        for sx in (-1, 1):
            for j in range(2):
                sandbag(p, sx * 1.32, -0.1 + j * 0.6 - (0.25 if c % 2 else 0.0), z, math.pi * 0.5 + rng.uniform(-0.06, 0.06), rng)
    k.add(p)
    p = k.piece("sand", "ground")
    p.box((0, 0, 0.01), (3.0, 2.0, 0.02), (0.3, 0.24, 0.16))
    k.add(p)
    crate(k, 0.7, 0.55, 0.0, 0.4)
    k.finish()


def makineli():
    k = Kit("makineli")
    rng = k.rng
    p = k.piece("sand", "bags")
    for c in range(4):
        z = 0.11 + c * 0.2
        for i in range(9):
            if c == 3 and i == 4:
                continue # (the embrasure)
            a = math.radians(-120 + i * 30 + (15 if c % 2 else 0))
            sandbag(p, math.sin(a) * 1.25, -math.cos(a) * 1.25, z, a, rng)
    k.add(p)
    p = k.piece("sand", "platform")
    p.box((0, 0.15, 0.18), (1.0, 1.1, 0.36), (0.36, 0.28, 0.19))
    k.add(p)
    # the Maxim on its wheeled mount: a fluted water jacket, the barrel, the receiver and its spade
    # grips, the shield, a belt of rounds feeding from a box
    p = k.piece("dark", "gun")
    cyl(p, (0, -0.05, 0.95), (0, -0.82, 0.95), 0.09, (0.26, 0.28, 0.22), segs=14)
    for i in range(6):
        cyl(p, (0, -0.12 - i * 0.12, 0.95), (0, -0.15 - i * 0.12, 0.95), 0.1, (0.18, 0.19, 0.16), segs=14)
    cyl(p, (0, -0.82, 0.95), (0, -1.15, 0.95), 0.025, (0.12, 0.12, 0.12), segs=8)
    p.box((0, 0.12, 0.95), (0.2, 0.36, 0.2), (0.2, 0.21, 0.18))
    for sx in (-0.08, 0.08):
        p.box((sx, 0.34, 0.92), (0.03, 0.12, 0.1), (0.35, 0.25, 0.15))
    p.box((0, 0.0, 0.78), (0.08, 0.08, 0.2), (0.18, 0.18, 0.16))
    k.add(p)
    p = k.piece("dark", "shield")
    p.obox((0, -0.3, 1.0), (1, 0, 0), (0, 0.97, 0.25), (0, -0.25, 0.97), (0.62, 0.03, 0.55), (0.25, 0.27, 0.21))
    k.add(p)
    p = k.piece("dark", "belt")
    for i in range(10):
        p.box((0.16 + i * 0.03, 0.1 + i * 0.04, 0.9 - i * 0.04), (0.03, 0.05, 0.08), (0.72, 0.56, 0.26))
    k.add(p)
    crate(k, 0.5, 0.55, 0.36, 0.3)
    p = k.piece("dark", "frame")
    p.box((0, 0.05, 0.72), (0.5, 0.9, 0.06), (0.2, 0.21, 0.18))
    p.box((0, 0.6, 0.6), (0.06, 0.6, 0.06), (0.2, 0.21, 0.18)) # (the trail)
    k.add(p)
    for sx in (-1, 1):
        p = k.piece("dark", "wheel")
        cyl(p, (sx * 0.32 - 0.03, -0.05, 0.6), (sx * 0.32 + 0.03, -0.05, 0.6), 0.22, (0.15, 0.15, 0.13), segs=14)
        k.add(p)
    k.finish()


def tel():
    k = Kit("tel")
    rng = k.rng
    # knife-rests: crossed stakes at either end and in the middle, the wire strung between, barbed,
    # and a coil of it sagging along the foot
    for x in (-1.8, 0.0, 1.8):
        p = k.piece("wood")
        for s in (-1, 1):
            p.log((x, s * 0.45, 0.0), (x, -s * 0.45, 1.25), 0.05, rng=rng, taper=0.1)
        k.add(p)
    p = k.piece("dark", "wire")
    for z, yy in ((0.35, 0.2), (0.65, 0.0), (0.95, -0.15)):
        p.box((0, yy, z), (3.8, 0.012, 0.012), (0.25, 0.24, 0.22))
        for i in range(30):
            x = -1.85 + i * 0.128
            p.obox((x, yy, z), (0, 0.7, 0.7), (0, -0.7, 0.7), (1, 0, 0), (0.06, 0.008, 0.008), (0.25, 0.24, 0.22))
    for i in range(40): # (the coil)
        a = i / 40 * math.tau * 9
        x = -1.85 + i / 40 * 3.7
        p.obox((x, math.cos(a) * 0.32, 0.34 + math.sin(a) * 0.3), (1, 0, 0), (0, -math.sin(a), math.cos(a)), (0, math.cos(a), math.sin(a)), (0.11, 0.01, 0.01), (0.3, 0.29, 0.27))
    k.add(p)
    k.finish()


BUILDERS = {
    "ev": ev, "ambar": ambar, "fener": fener, "kuyu": kuyu, "kule": kule,
    "silahlik": silahlik, "istasyon": istasyon, # (the square: BuildingDefs._square)
    "tren_lokomotif": lokomotif, "tren_tender": tender, "tren_vagon": vagon, "tren_yuk": yuk,
    "oduncu": kesim, "tasci": tas_ocagi, "toplayici": toplayici, "camur": camur_ocagi,
    "ev_oda": ev_oda, "ev_soba": ev_soba,
    "kamyon": kamyon, "tank": tank,
    "okuma": okuma, "demirci": demirci, "sifaci": sifaci, "hapishane": hapishane,
    "siper": siper, "makineli": makineli, "tel": tel,
    "arabaci": lambda: shed("arabaci", 6.0, 5.0, _cart_props, roof=(0.5, 0.47, 0.42)), # (split boards gone silver)
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
    if "--raw" in argv:
        for key in FINISH:
            FINISH[key] = False
    for a in argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
    for kind, fn in BUILDERS.items():
        if only and kind not in only:
            continue
        fn()
        if "--render" in argv:
            render(kind)


if __name__ == "__main__":
    main()
