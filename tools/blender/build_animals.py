"""The animals: the wolf, the town's laika dogs and hens, the roe deer and the mountain hare of the
woods. Made as the buildings and props are (tools/blender/build_buildings.py, build_props.py), each
object "<stuff>-<tag>-<n>", its colours in its vertices, the occlusion baked in.

    blender --background --factory-startup --python tools/blender/build_animals.py [-- --only=wolf,hen]

Blender: +Y the way it faces (Godot -Z), +X its right, +Z up; the ground at 0.

The parts the game swings each carry a tag, and each tag has an empty "pivot_<tag>" at the joint it
swings from (scripts/animal_body.gd hangs the part there):

  body                 the trunk (not swung; the whole of it pitched and bobbed)
  head                 the head (with the neck, where the neck moves with it)
  antler               a roe buck's antlers (on the head; left off a doe)
  tail                 the tail
  leg_fl leg_fr ...    each leg from the shoulder or hip to the knee or hock (fl fr hl hr; l r on a hen)
  shin_fl ...          below it, hung from that knee
  wing_l wing_r        a hen's wings

The coat ("hide") is painted in the alpha too: 1 where the beast's own coat colour (chosen in the game,
and changed with the season) tints it, 0 for what keeps its colour whatever the coat (a white belly,
a roe's rump, a hen's comb, the black tips of a hare's ears).

  wolf   a grey taiga wolf: deep chest, tucked waist, a ruff, the tail hung low
  dog    a laika: pricked ears, wedge head, the tail curled over the back
  deer   a Siberian roe deer: slender legs, big ears, white rump; a buck's short three-tined antlers
  hare   a mountain hare, crouched: long hind feet, black ear tips
  hen    a hen: comb and wattles, tail feathers up, wings that open

Output: assets/animals/<kind>.glb
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bmesh  # noqa: E402
import bpy  # noqa: E402
from mathutils import Vector, noise  # noqa: E402

import build_buildings as B  # noqa: E402

B.OUT = os.path.join(B.ROOT, "assets", "animals")
B.BEVELLED = ()  # (nothing here has a sawn edge)

DARK = (0.05, 0.04, 0.035)
NOSE = (0.07, 0.06, 0.055)
EYE_AMBER = (0.42, 0.3, 0.12)
HOOF = (0.11, 0.09, 0.08)
CLAW = (0.16, 0.14, 0.12)


def smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))


def fur(v, pos, amt=0.07, f=11.0, streak=(1.0, 0.35, 1.0)):
    """The coat's broken colour: blotches and streaks along the lie of the hair, as a brush leaves it."""
    q = Vector((pos.x * f * streak[0], pos.y * f * streak[1], pos.z * f * streak[2]))
    n = noise.noise(q) * 0.6 + noise.noise(q * 2.7 + Vector((3.1, 1.7, 5.3))) * 0.4
    return tuple(min(c * (1.0 + amt * n), 1.0) for c in v)


def tube(p, rings, paint, segs=14, caps=True):
    """A body lofted along a bent spine (as build_props.loft): `rings` (centre, half-width, half-height),
    each square to the way along. `paint(pos, along, belly, top)` gives (r, g, b, a) for each corner:
    `along` 0..1 down the rings, `belly`/`top` how far that corner faces down or up."""
    bm = p.bm
    pts = [Vector(r[0]) for r in rings]
    loops = []
    info = {}
    n = len(rings)
    for i, r in enumerate(rings):
        fwd = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        side = fwd.cross(Vector((0, 0, 1)))
        side = side.normalized() if side.length > 1e-3 else Vector((1, 0, 0))
        up = side.cross(fwd).normalized()
        vs = []
        for k in range(segs):
            t = k / segs * math.tau
            v = bm.verts.new(pts[i] + side * (math.cos(t) * r[1]) + up * (math.sin(t) * r[2]))
            info[v] = (i / max(n - 1, 1), max(-math.sin(t), 0.0), max(math.sin(t), 0.0))
            vs.append(v)
        loops.append(vs)
    faces = []
    for a, b in zip(loops, loops[1:]):
        for k in range(segs):
            f = bm.faces.new((a[k], a[(k + 1) % segs], b[(k + 1) % segs], b[k]))
            f.smooth = True
            faces.append(f)
    if caps:
        for vs, i, out in ((loops[0], 0, pts[0] - pts[1]), (list(reversed(loops[-1])), n - 1, pts[-1] - pts[-2])):
            # (domed, not flat: a rounded end where it sinks into the next part)
            c = bm.verts.new(sum((v.co for v in vs), Vector()) / len(vs) + out.normalized() * min(rings[i][1], rings[i][2]) * 0.7)
            info[c] = info[vs[0]][:1] + (0.5, 0.5)
            for k in range(segs):
                f = bm.faces.new((vs[k], vs[(k + 1) % segs], c))
                f.smooth = True
                faces.append(f)
    bmesh.ops.recalc_face_normals(bm, faces=faces)
    for f in faces:
        for loop in f.loops:
            a, bl, tp = info[loop.vert]
            c = paint(loop.vert.co, a, bl, tp)
            loop[p.col] = c if len(c) == 4 else (c[0], c[1], c[2], 0.0)
    return faces


def blob(p, c, r, paint, segs=12, n=7):
    """An egg of half-sizes `r` (x, y, z) about `c`, its long way along y."""
    rings = []
    for i in range(n):
        t = -1 + 2 * i / (n - 1)
        k = math.sqrt(max(1 - t * t, 0.0))
        rings.append(((c[0], c[1] + t * r[1], c[2]), max(r[0] * k, 0.004), max(r[2] * k, 0.004)))
    return tube(p, rings, paint, segs)


def solid(col):
    return lambda pos, a, bl, tp: (col[0], col[1], col[2], 0.0)


def pivot(name, at):
    ob = bpy.data.objects.new("pivot_" + name, None)
    ob.location = at
    bpy.context.scene.collection.objects.link(ob)


def finish(k, ao, grime_top=None):
    B.AO_DISTANCE = ao
    B.FINISH["grime"] = grime_top is not None
    if grime_top:
        B.GRIME_TOP = grime_top
    k.finish()


def mirror(s, pt):
    return (s * pt[0], pt[1], pt[2])


def scale(rings, S, s=1):
    return [((s * c[0] * S, c[1] * S, c[2] * S), w * S, h * S) for c, w, h in rings]


# --- the dogs: a wolf and a laika -----------------------------------------------------------------

def canid(kind, S, coat_dark, mark, muzzle_len, tail, ear, ruff, eye, bib=0.0):
    """The wolf and the laika, one frame at two sizes: `S` the scale, `coat_dark` how dark the saddle,
    `mark` the colour of what's pale on it (belly, cheeks, legs inside), `tail` "hang" or "curl"."""
    k = B.Kit(kind)

    def coat(pos, a, bl, tp, legs=False):
        # the coat: darkest along the spine (the saddle), lighter down the flanks, pale beneath
        v = 0.86 - coat_dark * tp ** 1.4
        c = fur((v, v * 0.97, v * 0.92), pos / S)
        m = smooth(0.25, 0.75, bl)
        if bib > 0.0:
            # (a laika's white: the chest and throat, the belly, the feet)
            q = pos / S
            m = max(m, bib * smooth(0.2, 0.34, q.y) * smooth(0.82, 0.68, q.z),
                    bib * smooth(0.3, 0.18, q.z))
        if legs:
            c = mix(c, (0.95, 0.88, 0.75), 0.6)  # (the tawny of the legs)
        return (c[0], c[1], c[2], 1.0 - m) if m < 0.01 else (*mix(c, mark, m), 1.0 - m)

    body = k.piece("hide", "body")
    tube(body, scale([((0, -0.57, 0.71), 0.04, 0.04), ((0, -0.52, 0.72), 0.12, 0.13), ((0, -0.4, 0.71), 0.15, 0.16),
                      ((0, -0.22, 0.72), 0.13, 0.135), ((0, -0.02, 0.7), 0.15, 0.18), ((0, 0.15, 0.68), 0.17, 0.21),
                      ((0, 0.29, 0.7), 0.175, 0.215), ((0, 0.41, 0.75), 0.15, 0.18), ((0, 0.5, 0.81), 0.115, 0.14),
                      ((0, 0.56, 0.85), 0.085, 0.1)], S), coat, segs=18)
    # the ruff over the shoulders and round the neck, standing off the coat
    tube(body, scale([((0, 0.2, 0.71), 0.15, 0.18), ((0, 0.32, 0.735), 0.165 + 0.04 * ruff, 0.2 + 0.035 * ruff),
                      ((0, 0.44, 0.8), 0.14 + 0.035 * ruff, 0.17 + 0.03 * ruff), ((0, 0.53, 0.855), 0.095, 0.115)], S), coat, segs=16)
    k.add(body)

    # the head, from the back of the skull: the wedge of it, the muzzle, the jaw, the ears
    hz = 0.86
    head = k.piece("hide", "head")
    L = muzzle_len

    def face(pos, a, bl, tp):
        c = coat(pos, a, bl, tp)
        # (the pale of the cheeks and under the muzzle, the dark of the brow)
        ch = smooth(0.15, 0.6, bl)
        rgb = mix(c[:3], mark, ch)
        return (*rgb, min(c[3], 1.0 - ch))
    tube(head, scale([((0, 0.5, hz + 0.0), 0.06, 0.07), ((0, 0.55, hz + 0.025), 0.1, 0.1), ((0, 0.61, hz + 0.04), 0.118, 0.105),
                      ((0, 0.67, hz + 0.03), 0.105, 0.09), ((0, 0.72, hz + 0.005), 0.08, 0.072), ((0, 0.72 + 0.07 * L, hz - 0.018), 0.06, 0.056),
                      ((0, 0.72 + 0.14 * L, hz - 0.032), 0.048, 0.045), ((0, 0.72 + 0.2 * L, hz - 0.04), 0.035, 0.035),
                      ((0, 0.72 + 0.225 * L, hz - 0.042), 0.02, 0.022)], S), face, segs=16)
    # (the stop: the brow over the eyes, the forehead dropping to the muzzle)
    tube(head, scale([((0, 0.6, hz + 0.09), 0.03, 0.02), ((0, 0.66, hz + 0.075), 0.075, 0.03), ((0, 0.71, hz + 0.045), 0.03, 0.02)], S), face, segs=10)
    tube(head, scale([((0, 0.7, hz - 0.06), 0.06, 0.035), ((0, 0.72 + 0.12 * L, hz - 0.085), 0.04, 0.022),
                      ((0, 0.72 + 0.19 * L, hz - 0.08), 0.022, 0.014)], S), lambda q, a, b, t: (*mix(mark, (0.7, 0.66, 0.6), 0.3), 0.0), segs=10)
    for s in (-1, 1):
        # cheek tufts, the fur flaring back from the jaw
        tube(head, scale([((0.06, 0.66, hz - 0.03), 0.03, 0.03), ((0.115, 0.6, hz - 0.05), 0.05, 0.05), ((0.15, 0.55, hz - 0.08), 0.015, 0.02)], S, s), face, segs=8)
        # the ear: a thick triangle, tawny behind and pale in the cup
        e0 = (0.055, 0.6, hz + 0.1)
        tube(head, scale([(e0, 0.05 * ear, 0.022 * ear), ((0.07, 0.595, hz + 0.1 + 0.07 * ear), 0.032 * ear, 0.016 * ear),
                          ((0.08, 0.59, hz + 0.1 + 0.135 * ear), 0.004, 0.004)], S, s),
             lambda q, a, b, t: (*fur(mix((0.86, 0.8, 0.7), (0.5, 0.46, 0.42), a * coat_dark), q / S), 1.0), segs=8)
        tube(head, scale([((0.056, 0.607, hz + 0.105), 0.032 * ear, 0.008), ((0.07, 0.604, hz + 0.1 + 0.08 * ear), 0.016 * ear, 0.005)], S, s),
             solid(mix(mark, (0.3, 0.26, 0.22), 0.3)), segs=6)
    k.add(head)
    feat = k.piece("dark", "head")
    blob(feat, (0, (0.72 + 0.215 * L) * S, (hz - 0.035) * S), (0.026 * S, 0.02 * S, 0.02 * S), solid(NOSE), segs=10, n=5)
    for s in (-1, 1):
        blob(feat, (s * 0.075 * S, 0.715 * S, (hz + 0.045) * S), (0.012 * S, 0.016 * S, 0.01 * S), solid(eye), segs=8, n=5)
        tube(feat, scale([((0.06, 0.71, hz + 0.058), 0.012, 0.004), ((0.08, 0.73, hz + 0.052), 0.012, 0.004)], S, s), solid(DARK), segs=6)  # (the dark of the lid)
        tube(feat, scale([((0.02, 0.72 + 0.2 * L, hz - 0.08), 0.01, 0.005), ((0.045, 0.72 + 0.04 * L, hz - 0.07), 0.008, 0.004)], S, s), solid(DARK), segs=5)  # (the lip line)
    k.add(feat)
    pivot("head", (0, 0.5 * S, (hz - 0.04) * S))

    # the tail
    tl = k.piece("hide", "tail")

    def tailc(pos, a, bl, tp):
        v = 0.8 - coat_dark * 0.6 * tp
        c = fur((v, v * 0.97, v * 0.92), pos / S, 0.1)
        tip = smooth(0.7, 0.95, a)
        if tail == "hang":
            return (*mix(c, (0.1, 0.09, 0.08), tip), 1.0 - tip)
        m = smooth(0.3, 0.8, bl)
        return (*mix(c, mark, m), 1.0 - m)
    if tail == "hang":
        tube(tl, scale([((0, -0.55, 0.72), 0.04, 0.04), ((0, -0.62, 0.66), 0.06, 0.065), ((0, -0.69, 0.55), 0.075, 0.08),
                        ((0, -0.73, 0.43), 0.07, 0.075), ((0, -0.745, 0.33), 0.045, 0.05), ((0, -0.75, 0.27), 0.012, 0.012)], S), tailc, segs=12)
    else:
        tube(tl, scale([((0, -0.55, 0.73), 0.045, 0.045), ((0, -0.61, 0.82), 0.065, 0.065), ((0, -0.6, 0.95), 0.075, 0.075),
                        ((0, -0.5, 1.02), 0.075, 0.07), ((0, -0.4, 0.99), 0.065, 0.06), ((0.03, -0.36, 0.92), 0.04, 0.04),
                        ((0.05, -0.39, 0.88), 0.01, 0.01)], S), tailc, segs=12)
    k.add(tl)
    pivot("tail", (0, -0.55 * S, 0.72 * S))

    # the legs: the shoulder and forearm to the wrist, the hind thigh and gaskin to the hock; below that the paw
    def legc(pos, a, bl, tp):
        return coat(pos, a, bl, tp, legs=True)
    for s in (-1, 1):
        fx, fy = 0.1, 0.24
        up = k.piece("hide", "leg_f" + ("l" if s < 0 else "r"))
        tube(up, scale([((fx, fy + 0.02, 0.68), 0.055, 0.08), ((fx + 0.005, fy - 0.01, 0.52), 0.055, 0.065), ((fx, fy - 0.01, 0.4), 0.04, 0.045),
                        ((fx, fy, 0.24), 0.03, 0.035), ((fx, fy + 0.005, 0.19), 0.028, 0.032)], S, s), legc, segs=10)
        k.add(up)
        lo = k.piece("hide", "shin_f" + ("l" if s < 0 else "r"))
        tube(lo, scale([((fx, fy + 0.005, 0.2), 0.028, 0.032), ((fx, fy + 0.01, 0.13), 0.025, 0.027), ((fx, fy + 0.02, 0.05), 0.027, 0.03),
                        ((fx, fy + 0.035, 0.03), 0.046, 0.03), ((fx, fy + 0.075, 0.022), 0.04, 0.02)], S, s), legc, segs=10)
        k.add(lo)
        cl = k.piece("dark", "shin_f" + ("l" if s < 0 else "r"))
        for t in (-1, -0.33, 0.33, 1):
            blob(cl, ((s * fx + t * 0.022) * S, (fy + 0.088) * S, 0.012 * S), (0.006 * S, 0.01 * S, 0.006 * S), solid(CLAW), segs=5, n=4)
        k.add(cl)
        pivot("leg_f" + ("l" if s < 0 else "r"), (s * fx * S, fy * S, 0.68 * S))
        pivot("shin_f" + ("l" if s < 0 else "r"), (s * fx * S, (fy + 0.005) * S, 0.2 * S))

        hx, hy = 0.11, -0.38
        up = k.piece("hide", "leg_h" + ("l" if s < 0 else "r"))
        tube(up, scale([((hx, hy + 0.02, 0.7), 0.065, 0.1), ((hx + 0.008, hy + 0.06, 0.53), 0.065, 0.085), ((hx, hy + 0.01, 0.38), 0.045, 0.06),
                        ((hx, hy - 0.06, 0.25), 0.03, 0.04), ((hx, hy - 0.075, 0.22), 0.028, 0.034)], S, s), legc, segs=10)
        k.add(up)
        lo = k.piece("hide", "shin_h" + ("l" if s < 0 else "r"))
        tube(lo, scale([((hx, hy - 0.075, 0.23), 0.028, 0.034), ((hx, hy - 0.06, 0.12), 0.024, 0.026), ((hx, hy - 0.045, 0.05), 0.026, 0.028),
                        ((hx, hy - 0.03, 0.03), 0.044, 0.028), ((hx, hy + 0.01, 0.022), 0.038, 0.019)], S, s), legc, segs=10)
        k.add(lo)
        cl = k.piece("dark", "shin_h" + ("l" if s < 0 else "r"))
        for t in (-1, -0.33, 0.33, 1):
            blob(cl, ((s * hx + t * 0.02) * S, (hy + 0.023) * S, 0.012 * S), (0.006 * S, 0.01 * S, 0.006 * S), solid(CLAW), segs=5, n=4)
        k.add(cl)
        pivot("leg_h" + ("l" if s < 0 else "r"), (s * hx * S, hy * S, 0.7 * S))
        pivot("shin_h" + ("l" if s < 0 else "r"), (s * hx * S, (hy - 0.075) * S, 0.23 * S))
    finish(k, 0.35 * S, 0.16 * S)


def wolf():
    canid("wolf", 1.0, 0.62, (0.86, 0.8, 0.68), 1.15, "hang", 1.0, 1.12, EYE_AMBER)


def dog():
    canid("dog", 0.72, 0.28, (0.94, 0.92, 0.86), 0.95, "curl", 1.15, 1.05, (0.2, 0.13, 0.07), bib=1.0)


# --- the roe deer ---------------------------------------------------------------------------------

def deer():
    k = B.Kit("deer")
    WHITE = (0.93, 0.9, 0.84)

    def coat(pos, a, bl, tp):
        v = 0.86 - 0.18 * tp ** 1.5
        c = fur((v, v * 0.97, v * 0.93), pos, 0.06, 9.0)
        m = smooth(0.4, 0.85, bl) * 0.75
        rump = smooth(-0.36, -0.46, pos.y) * smooth(0.6, 0.72, pos.z)  # (the white rump patch)
        m = max(m, rump)
        return (*mix(c, WHITE if rump > m * 0.9 else (0.82, 0.74, 0.62), m), 1.0 - m)

    body = k.piece("hide", "body")
    tube(body, [((0, -0.53, 0.8), 0.04, 0.05), ((0, -0.48, 0.81), 0.12, 0.15), ((0, -0.37, 0.82), 0.15, 0.18), ((0, -0.18, 0.8), 0.15, 0.185),
                ((0, 0.0, 0.79), 0.165, 0.21), ((0, 0.17, 0.79), 0.165, 0.215), ((0, 0.29, 0.83), 0.14, 0.19), ((0, 0.36, 0.88), 0.1, 0.13)],
         coat, segs=18)
    k.add(body)

    # neck and head together, from the withers (it grazes with the neck down)
    head = k.piece("hide", "head")

    def neckc(pos, a, bl, tp):
        c = coat(pos, a, bl, tp)
        # the pale gorget patches on the throat (winter), the white chin
        g = smooth(0.4, 0.9, bl) * (smooth(0.97, 1.02, pos.z) * smooth(1.13, 1.08, pos.z)) * 0.9
        return (*mix(c[:3], WHITE, g), min(c[3], 1.0 - g))
    tube(head, [((0, 0.3, 0.88), 0.11, 0.15), ((0, 0.38, 0.97), 0.085, 0.11), ((0, 0.44, 1.07), 0.068, 0.085), ((0, 0.49, 1.16), 0.06, 0.07),
                ((0, 0.52, 1.23), 0.058, 0.062)], neckc, segs=14)

    def facec(pos, a, bl, tp):
        c = coat(pos, a, bl, tp)
        chin = smooth(0.5, 0.9, bl) * smooth(0.66, 0.74, pos.y)
        muz = smooth(0.72, 0.77, pos.y) * (1 - chin)  # (the dark of the muzzle round the nose)
        rgb = mix(mix(c[:3], WHITE, chin), (0.2, 0.16, 0.13), muz * 0.8)
        return (*rgb, min(c[3], 1.0 - max(chin, muz)))
    tube(head, [((0, 0.5, 1.25), 0.06, 0.065), ((0, 0.56, 1.28), 0.07, 0.072), ((0, 0.63, 1.27), 0.058, 0.06), ((0, 0.7, 1.23), 0.042, 0.046),
                ((0, 0.75, 1.2), 0.033, 0.036), ((0, 0.785, 1.185), 0.022, 0.026)], facec, segs=14)
    for s in (-1, 1):
        # the big ears, spread, the inside pale and furred
        tube(head, [((s * 0.045, 0.55, 1.32), 0.04, 0.018), ((s * 0.09, 0.535, 1.39), 0.045, 0.014), ((s * 0.125, 0.52, 1.44), 0.026, 0.01),
                    ((s * 0.14, 0.515, 1.46), 0.005, 0.005)],
             lambda q, a, b, t: (*fur(mix((0.78, 0.72, 0.62), (0.4, 0.34, 0.28), smooth(0.75, 1.0, a)), q), 1.0 - smooth(0.75, 1.0, a)), segs=8)
        tube(head, [((s * 0.05, 0.56, 1.33), 0.026, 0.006), ((s * 0.09, 0.545, 1.385), 0.03, 0.006), ((s * 0.115, 0.535, 1.425), 0.012, 0.004)],
             solid((0.85, 0.8, 0.72)), segs=6)
    k.add(head)
    feat = k.piece("dark", "head")
    blob(feat, (0, 0.79, 1.19), (0.024, 0.014, 0.02), solid(NOSE), segs=10, n=5)
    for s in (-1, 1):
        blob(feat, (s * 0.058, 0.62, 1.295), (0.013, 0.02, 0.013), solid((0.03, 0.025, 0.02)), segs=8, n=5)
        tube(feat, [((s * 0.04, 0.6, 1.315), 0.014, 0.004), ((s * 0.06, 0.635, 1.31), 0.012, 0.004)], solid((0.1, 0.08, 0.07)), segs=6)
    k.add(feat)
    pivot("head", (0, 0.3, 0.92))

    # a buck's antlers: rough at the base (the pearling), a forward tine, the main beam forking at the top
    ant = k.piece("plaster", "antler")
    BASE = (0.36, 0.29, 0.2)
    TIP = (0.84, 0.78, 0.66)
    for s in (-1, 1):
        def beam(pts, w0, w1):
            n = len(pts)
            tube(ant, [((s * x, y, z), w0 + (w1 - w0) * i / (n - 1), w0 + (w1 - w0) * i / (n - 1)) for i, (x, y, z) in enumerate(pts)],
                 lambda q, a, b, t: (*fur(mix(BASE, TIP, smooth(0.5, 1.0, a)), q, 0.18, 40.0), 0.0), segs=7)
        beam([(0.035, 0.555, 1.32), (0.04, 0.555, 1.35)], 0.022, 0.026)  # (the coronet)
        beam([(0.04, 0.555, 1.34), (0.05, 0.55, 1.42), (0.055, 0.545, 1.5), (0.05, 0.54, 1.56), (0.045, 0.53, 1.6)], 0.016, 0.006)
        beam([(0.05, 0.55, 1.44), (0.055, 0.58, 1.48), (0.055, 0.6, 1.52)], 0.01, 0.004)  # (the front tine)
        beam([(0.053, 0.545, 1.53), (0.06, 0.515, 1.56), (0.065, 0.5, 1.58)], 0.009, 0.004)  # (the back tine)
    k.add(ant)

    tl = k.piece("hide", "tail")  # (a roe's tail is a nub hidden in the white)
    blob(tl, (0, -0.53, 0.82), (0.025, 0.03, 0.035), solid(WHITE), segs=8, n=5)
    k.add(tl)
    pivot("tail", (0, -0.52, 0.84))

    for s in (-1, 1):
        sd = "l" if s < 0 else "r"
        fx, fy = 0.08, 0.22
        up = k.piece("hide", "leg_f" + sd)
        tube(up, [((s * fx, fy + 0.03, 0.77), 0.05, 0.075), ((s * fx, fy - 0.005, 0.6), 0.045, 0.06), ((s * fx, fy - 0.01, 0.45), 0.03, 0.035),
                  ((s * fx, fy, 0.33), 0.022, 0.028), ((s * fx, fy + 0.002, 0.29), 0.024, 0.028)], coat, segs=9)
        k.add(up)
        lo = k.piece("hide", "shin_f" + sd)
        tube(lo, [((s * fx, fy + 0.002, 0.3), 0.023, 0.027), ((s * fx, fy + 0.004, 0.18), 0.015, 0.019), ((s * fx, fy + 0.008, 0.07), 0.016, 0.019),
                  ((s * fx, fy + 0.012, 0.045), 0.02, 0.022)], coat, segs=9)
        k.add(lo)
        hf = k.piece("dark", "shin_f" + sd)
        for c in (-1, 1):
            tube(hf, [((s * fx + c * 0.009, fy + 0.012, 0.05), 0.009, 0.015), ((s * fx + c * 0.01, fy + 0.03, 0.0), 0.011, 0.024)], solid(HOOF), segs=7)
        k.add(hf)
        pivot("leg_f" + sd, (s * fx, fy, 0.78))
        pivot("shin_f" + sd, (s * fx, fy + 0.002, 0.3))

        hx, hy = 0.09, -0.36
        up = k.piece("hide", "leg_h" + sd)
        tube(up, [((s * hx, hy + 0.02, 0.8), 0.065, 0.11), ((s * (hx + 0.006), hy + 0.06, 0.62), 0.06, 0.085), ((s * hx, hy + 0.005, 0.47), 0.035, 0.05),
                  ((s * hx, hy - 0.07, 0.36), 0.024, 0.032), ((s * hx, hy - 0.085, 0.33), 0.022, 0.028)], coat, segs=9)
        k.add(up)
        lo = k.piece("hide", "shin_h" + sd)
        tube(lo, [((s * hx, hy - 0.085, 0.34), 0.022, 0.03), ((s * hx, hy - 0.075, 0.2), 0.015, 0.019), ((s * hx, hy - 0.065, 0.07), 0.016, 0.019),
                  ((s * hx, hy - 0.06, 0.045), 0.02, 0.022)], coat, segs=9)
        k.add(lo)
        hf = k.piece("dark", "shin_h" + sd)
        for c in (-1, 1):
            tube(hf, [((s * hx + c * 0.009, hy - 0.06, 0.05), 0.009, 0.015), ((s * hx + c * 0.01, hy - 0.042, 0.0), 0.011, 0.024)], solid(HOOF), segs=7)
        k.add(hf)
        pivot("leg_h" + sd, (s * hx, hy, 0.8))
        pivot("shin_h" + sd, (s * hx, hy - 0.085, 0.34))
    finish(k, 0.32, 0.18)


# --- the mountain hare ----------------------------------------------------------------------------

def hare():
    k = B.Kit("hare")
    WHITE = (0.94, 0.93, 0.9)

    def coat(pos, a, bl, tp):
        v = 0.88 - 0.14 * tp
        c = fur((v, v * 0.97, v * 0.93), pos, 0.1, 30.0)
        m = smooth(0.35, 0.8, bl)
        return (*mix(c, WHITE, m), 1.0 - m)

    body = k.piece("hide", "body")
    tube(body, [((0, -0.2, 0.13), 0.04, 0.04), ((0, -0.175, 0.15), 0.09, 0.1), ((0, -0.1, 0.17), 0.11, 0.12), ((0, -0.01, 0.18), 0.095, 0.11),
                ((0, 0.07, 0.2), 0.08, 0.095), ((0, 0.13, 0.23), 0.06, 0.07), ((0, 0.16, 0.25), 0.04, 0.045)], coat, segs=16)
    k.add(body)
    head = k.piece("hide", "head")

    def facec(pos, a, bl, tp):
        c = coat(pos, a, bl, tp)
        return c
    tube(head, [((0, 0.12, 0.26), 0.045, 0.05), ((0, 0.16, 0.285), 0.058, 0.06), ((0, 0.21, 0.285), 0.055, 0.055), ((0, 0.25, 0.27), 0.04, 0.042),
                ((0, 0.275, 0.26), 0.022, 0.026)], facec, segs=14)
    for s in (-1, 1):
        # the long ears laid back a little, black at the tips whatever the season
        tube(head, [((s * 0.022, 0.165, 0.325), 0.02, 0.011), ((s * 0.034, 0.135, 0.375), 0.025, 0.01), ((s * 0.042, 0.105, 0.415), 0.02, 0.008),
                    ((s * 0.046, 0.09, 0.435), 0.004, 0.004)],
             lambda q, a, b, t: (*mix(fur((0.84, 0.8, 0.74), q, 0.08, 30.0), (0.06, 0.05, 0.045), smooth(0.68, 0.8, a)), 1.0 - smooth(0.68, 0.8, a)), segs=8)
    k.add(head)
    feat = k.piece("dark", "head")
    blob(feat, (0, 0.283, 0.262), (0.008, 0.005, 0.006), solid((0.35, 0.25, 0.22)), segs=6, n=4)
    for s in (-1, 1):
        blob(feat, (s * 0.044, 0.215, 0.3), (0.009, 0.014, 0.011), solid((0.12, 0.07, 0.03)), segs=8, n=5)
    k.add(feat)
    pivot("head", (0, 0.12, 0.25))
    tl = k.piece("hide", "tail")
    blob(tl, (0, -0.215, 0.17), (0.028, 0.025, 0.03), solid(WHITE), segs=8, n=5)
    k.add(tl)
    pivot("tail", (0, -0.2, 0.16))
    for s in (-1, 1):
        sd = "l" if s < 0 else "r"
        lg = k.piece("hide", "leg_f" + sd)
        tube(lg, [((s * 0.045, 0.1, 0.17), 0.025, 0.03), ((s * 0.045, 0.11, 0.08), 0.014, 0.016), ((s * 0.045, 0.12, 0.02), 0.016, 0.014),
                  ((s * 0.045, 0.14, 0.012), 0.014, 0.01)], coat, segs=8)
        k.add(lg)
        pivot("leg_f" + sd, (s * 0.045, 0.1, 0.16))
        # the hind leg: the big haunch, and the long foot flat on the ground from the heel
        th = k.piece("hide", "leg_h" + sd)
        blob(th, (s * 0.075, -0.1, 0.12), (0.04, 0.085, 0.07), coat, segs=12)
        k.add(th)
        ft = k.piece("hide", "shin_h" + sd)
        tube(ft, [((s * 0.08, -0.175, 0.045), 0.02, 0.026), ((s * 0.08, -0.12, 0.02), 0.018, 0.016), ((s * 0.08, -0.04, 0.012), 0.017, 0.011),
                  ((s * 0.08, -0.015, 0.01), 0.012, 0.008)], coat, segs=8)
        k.add(ft)
        pivot("leg_h" + sd, (s * 0.075, -0.1, 0.14))
        pivot("shin_h" + sd, (s * 0.08, -0.17, 0.05))
    B.FINISH["grime"] = False
    finish(k, 0.1)


# --- the hen --------------------------------------------------------------------------------------

def hen():
    k = B.Kit("hen")
    COMB = (0.62, 0.1, 0.07)
    HORN = (0.78, 0.6, 0.22)

    def feathers(pos, a, bl, tp):
        v = 0.9 - 0.12 * tp
        c = fur((v, v * 0.96, v * 0.9), pos, 0.12, 60.0, (1.0, 0.5, 1.0))
        speck = smooth(0.35, 0.55, noise.noise(pos * 90.0)) * 0.3  # (the lacing of the feathers)
        c = tuple(x * (1 - speck) for x in c)
        m = smooth(0.6, 0.95, bl) * 0.3
        return (*mix(c, (0.86, 0.82, 0.74), m), 1.0)

    body = k.piece("hide", "body")
    tube(body, [((0, -0.14, 0.25), 0.03, 0.04), ((0, -0.12, 0.23), 0.07, 0.08), ((0, -0.06, 0.21), 0.095, 0.1), ((0, 0.02, 0.21), 0.095, 0.105),
                ((0, 0.08, 0.23), 0.075, 0.09), ((0, 0.11, 0.26), 0.05, 0.06)], feathers, segs=14)
    # the tail feathers fanned up behind, blade by blade
    for i, sx in enumerate((-0.03, -0.012, 0.012, 0.03)):
        tube(body, [((sx * 0.5, -0.1, 0.27), 0.012, 0.02), ((sx, -0.145, 0.32), 0.008, 0.035), ((sx * 1.2, -0.17, 0.37 - abs(sx)), 0.006, 0.03),
                    ((sx * 1.3, -0.18, 0.4 - abs(sx) * 1.5), 0.002, 0.008)],
             lambda q, a, b, t, i=i: (*fur(mix((0.66, 0.62, 0.56), (0.5, 0.47, 0.42), a), q, 0.15, 60.0), 1.0), segs=8)
    # the fluff of the thighs
    for s in (-1, 1):
        blob(body, (s * 0.045, -0.01, 0.15), (0.035, 0.05, 0.04), feathers, segs=8, n=5)
    k.add(body)
    head = k.piece("hide", "head")
    tube(head, [((0, 0.07, 0.26), 0.05, 0.055), ((0, 0.1, 0.31), 0.038, 0.04), ((0, 0.12, 0.35), 0.032, 0.034), ((0, 0.135, 0.375), 0.03, 0.03),
                ((0, 0.155, 0.385), 0.022, 0.022)], feathers, segs=10)
    # the comb, single and serrated, and the wattles
    for i, (y, h) in enumerate(((0.115, 0.022), (0.13, 0.03), (0.145, 0.028), (0.16, 0.018))):
        tube(head, [((0, y, 0.395), 0.005, 0.008), ((0, y, 0.395 + h), 0.004, 0.006), ((0, y, 0.4 + h), 0.001, 0.001)], solid(COMB), segs=6)
    tube(head, [((0, 0.11, 0.4), 0.006, 0.006), ((0, 0.165, 0.4), 0.006, 0.006)], solid(COMB), segs=6)
    for s in (-1, 1):
        blob(head, (s * 0.008, 0.16, 0.355), (0.006, 0.01, 0.014), solid(COMB), segs=6, n=4)
    k.add(head)
    bk = k.piece("plaster", "head")
    tube(bk, [((0, 0.165, 0.385), 0.01, 0.009), ((0, 0.185, 0.378), 0.006, 0.005), ((0, 0.195, 0.372), 0.001, 0.001)], solid(HORN), segs=6)
    for s in (-1, 1):
        blob(bk, (s * 0.024, 0.145, 0.388), (0.005, 0.006, 0.006), solid(DARK), segs=6, n=4)
    k.add(bk)
    pivot("head", (0, 0.08, 0.26))
    for s in (-1, 1):
        sd = "l" if s < 0 else "r"
        w = k.piece("hide", "wing_" + sd)
        tube(w, [((s * 0.085, 0.06, 0.25), 0.012, 0.03), ((s * 0.093, 0.0, 0.235), 0.016, 0.05), ((s * 0.09, -0.07, 0.245), 0.014, 0.042),
                 ((s * 0.085, -0.12, 0.27), 0.006, 0.02)],
             lambda q, a, b, t: (*fur(mix((0.86, 0.82, 0.76), (0.66, 0.62, 0.56), smooth(0.3, 1.0, a)), q, 0.15, 60.0, (1.0, 0.3, 1.0)), 1.0), segs=8)
        k.add(w)
        pivot("wing_" + sd, (s * 0.085, 0.05, 0.26))
        lg = k.piece("plaster", "leg_" + sd)
        tube(lg, [((s * 0.04, 0.0, 0.13), 0.009, 0.009), ((s * 0.04, 0.005, 0.02), 0.007, 0.007)], solid(HORN), segs=6)
        for ang in (-0.45, 0.0, 0.45, math.pi):
            ln = 0.045 if ang != math.pi else 0.025
            tube(lg, [((s * 0.04, 0.005, 0.012), 0.005, 0.004), ((s * 0.04 + math.sin(ang) * ln, 0.005 + math.cos(ang) * ln, 0.004), 0.003, 0.003)],
                 solid(HORN), segs=5)
        k.add(lg)
        pivot("leg_" + sd, (s * 0.04, 0.0, 0.15))
    B.FINISH["grime"] = False
    finish(k, 0.08)


BUILDERS = {"wolf": wolf, "dog": dog, "deer": deer, "hare": hare, "hen": hen}


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


main()
