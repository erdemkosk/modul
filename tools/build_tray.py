"""The build tray's pieces, as a cabinetmaker and an engraver would have made them for the station's
counter: a walnut plinth with a brass edge the group medallions sit on, a lighter walnut tray that
rises over it with the buildings' cards, the brass medallions themselves (at rest, under the hand,
chosen), the glyphs engraved in their faces, a red wax seal for what's not yet allowed, and a little
paper fibre to lay over the cards.

Everything is drawn at twice the size it's seen at (Hud draws it halved, so it's sharp on a Retina
screen and smooth on any other), with numpy and Pillow only.

    python3 tools/build_tray.py

Output: assets/ui/tray/*.png
"""
import os

import numpy as np
from PIL import Image, ImageDraw

K = 2  # texture pixels to a UI pixel
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui", "tray")
rng = np.random.default_rng(1918)


def hexc(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])


WALNUT = hexc("3b2918")
SHELF = hexc("5a3e26")
BRASS = hexc("b8925a")
BRASS_HI = hexc("f0d9a6")
BRASS_LO = hexc("4a3216")
EDGE_DARK = hexc("1c120a")


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def blur(a, sy, sx, wrap_x=False, wrap_y=False):
    """A gaussian blur by FFT; an axis not wrapped is padded so its ends don't meet."""
    py = 0 if wrap_y else int(sy * 3) + 1
    px = 0 if wrap_x else int(sx * 3) + 1
    b = np.pad(a, ((py, py), (px, px)), mode="reflect")
    h, w = b.shape
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * (np.pi ** 2) * ((fy * sy) ** 2 + (fx * sx) ** 2))
    r = np.real(np.fft.ifft2(np.fft.fft2(b) * g))
    return r[py:py + a.shape[0], px:px + a.shape[1]]


def norm(a):
    a = a - a.mean()
    return a / (a.std() + 1e-9)


def save(name, rgb, alpha):
    img = np.dstack([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)])
    Image.fromarray((img * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name))
    print("wrote", name, img.shape[1], "x", img.shape[0])


def grain(h, period, base, seed):
    """Walnut: long streaks along x, the latewood's darker lines wandering across them, fine pores.
    Periodic along x with `period` (the nine-patch's middle tiles)."""
    r = np.random.default_rng(seed)
    w = period
    long = norm(blur(r.standard_normal((h, w)), 1.2 * K, 46 * K, wrap_x=True))
    fine = norm(blur(r.standard_normal((h, w)), 0.5 * K, 7 * K, wrap_x=True))
    xx = np.arange(w)[None, :] / w * 2 * np.pi
    yy = np.arange(h)[:, None].astype(float)
    warp = 5.0 * K * np.sin(xx + 0.7) + 2.2 * K * np.sin(2 * xx + 2.1) + 1.0 * K * np.sin(3 * xx + 4.0)
    warp = warp + norm(blur(r.standard_normal((h, w)), 5 * K, 24 * K, wrap_x=True)) * 4.0 * K
    lines = np.sin((yy + warp) / (5.5 * K) * 2 * np.pi)
    late = smoothstep(0.55, 0.95, lines) # (the dark late wood)
    pores = smoothstep(2.2, 3.2, norm(r.standard_normal((h, w)))) * 0.5
    v = 1.0 + long * 0.1 + fine * 0.035 - late * 0.085 - pores * 0.06
    return base[None, None, :] * v[..., None]


def rounded_sdf(xx, yy, x0, y0, x1, y1, r):
    """Distance inside (positive) a box with corners rounded by r."""
    cx = (x0 + x1) * 0.5
    cy = (y0 + y1) * 0.5
    hx = (x1 - x0) * 0.5 - r
    hy = (y1 - y0) * 0.5 - r
    qx = np.abs(xx - cx) - hx
    qy = np.abs(yy - cy) - hy
    out = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r
    return -out


def normals(d):
    gy, gx = np.gradient(d)
    l = np.hypot(gx, gy) + 1e-9
    return -gx / l, -gy / l # (pointing out)


def board(name, size1, margins1, base, radius1, pad1, bottom_open, seed, edge1=3.0):
    """A walnut panel with a brass edge, its shadow baked round it. size1 / margins1 / pad1 in UI px
    (margins: left, top, right, bottom). bottom_open: it runs on off the screen's foot (no edge
    there, no corners)."""
    W, H = size1[0] * K, size1[1] * K
    ml, mt, mr, mb = [m * K for m in margins1]
    period = W - ml - mr
    yy, xx = np.mgrid[0:H, 0:W].astype(float) + 0.5
    p = pad1 * K
    r = radius1 * K
    y1 = H + r * 3 if bottom_open else H - p
    d = rounded_sdf(xx, yy, p, p, W - p, y1, r)
    # the shadow it throws: soft, a little below it
    ds = rounded_sdf(xx, yy, p - 1 * K, p + 3 * K, W - p + 1 * K, y1 + 3 * K, r + 2 * K)
    sh = smoothstep(-p * 0.95, p * 0.3, ds) ** 1.6 * 0.62
    # the wood, shifted so the middle columns are the period's
    g = grain(H, period, base, seed)
    cols = (np.arange(W) - ml) % period
    wood = g[:, cols]
    e = edge1 * K
    t = np.clip(d / e, 0, 1) # 0 at the edge .. 1 where the brass meets the wood
    nx, ny = normals(d)
    # the brass edge: a half-round bead, lit from above and a little left
    tilt = (0.5 - t) * np.pi
    sx = np.sin(tilt) * 0.9
    N = np.dstack([nx * sx, ny * sx, np.cos(tilt)])
    L = np.array([-0.3, -0.85, 0.45])
    L = L / np.linalg.norm(L)
    dif = np.clip((N * L).sum(axis=2), 0, 1)
    Rv = 2 * (N * L).sum(axis=2)[..., None] * N - L
    spec = np.clip(Rv[..., 2], 0, 1) ** 18
    brush = norm(blur(rng.standard_normal((H, W)), 0.4 * K, 14 * K)) * 0.04
    brass = BRASS_LO + (BRASS - BRASS_LO) * (dif[..., None] * 1.15) + (BRASS_HI - BRASS) * (spec[..., None] * 0.9)
    brass = brass * (1 + brush[..., None])
    # inside the brass: a dark groove, then the wood a shade darker toward it (it sits a touch low)
    inner = d - e
    col = wood.copy()
    col *= (1 - 0.45 * (1 - smoothstep(0, 1.6 * K, inner)))[..., None]
    col *= (1 - 0.22 * (1 - smoothstep(0, 9 * K, inner)) * (0.6 + 0.4 * np.clip(-ny, 0, 1)))[..., None]
    # a faint sheen along the top of the wood (French polish)
    sheen = smoothstep(14 * K, 3 * K, inner) * smoothstep(2 * K, 4 * K, inner) * np.clip(-ny, 0, 1) * 0.0
    col = col + sheen[..., None]
    is_brass = (d < e)
    col = np.where(is_brass[..., None], brass, col)
    # the outermost hair: dark, so it reads against bright snow
    col = np.where((d < 0.9 * K)[..., None], col * 0.55 + EDGE_DARK * 0.45, col)
    cover = np.clip(d / 1.0 + 0.5, 0, 1)
    a = cover + (1 - cover) * sh
    rgb = (col * cover[..., None] + np.zeros(3) * (1 - cover[..., None]) * sh[..., None]) / np.maximum(a, 1e-6)[..., None]
    save(name, rgb, a)


def medal(name, state):
    """A brass medallion seen from in front: a bevelled bead of a rim with a groove and a milled edge,
    the face inside dished: walnut at rest and under the hand (the rim lit), polished pale brass when
    chosen."""
    S = 76 * K
    c = S / 2.0
    yy, xx = np.mgrid[0:S, 0:S].astype(float) + 0.5
    dx, dy = xx - c, yy - c
    r = np.hypot(dx, dy)
    ux, uy = dx / (r + 1e-9), dy / (r + 1e-9)
    RO = 30.0 * K
    RI = 23.0 * K
    on = state == "on"
    hover = state == "hover"
    L = np.array([-0.4, -0.75, 0.55])
    L = L / np.linalg.norm(L)
    # the shadow on the plinth (deeper and wider when it's pressed in, the chosen one sits proud)
    so = (3.5 if not on else 4.5) * K
    rs = np.hypot(dx, dy - so)
    sh = smoothstep(RO + 7 * K, RO - 3 * K, rs) * 0.7
    # the rim: a rounded bead from RI to RO
    t = np.clip((r - RI) / (RO - RI), 0, 1)
    tilt = (t - 0.5) * np.pi * 0.92
    s = np.sin(tilt)
    N = np.dstack([ux * s, uy * s, np.cos(tilt)])
    nl = (N * L).sum(axis=2)
    dif = np.clip(nl, 0, 1)
    Rz = 2 * nl * N[..., 2] - L[2]
    spec = np.clip(Rz, 0, 1) ** 22
    hi = BRASS_HI if on else BRASS * 1.08
    base = BRASS * (1.12 if on else (1.06 if hover else 0.92))
    lo = BRASS_LO * (1.25 if on else 1.0)
    rim = lo + (base - lo) * (dif[..., None] * 1.2) + (hi * 1.1 - base) * (spec[..., None] * (1.0 if on or hover else 0.75))
    # the groove round the bead, and the milling on its outer edge
    groove = np.exp(-((r - (RI + 4.2 * K)) / (0.7 * K)) ** 2)
    rim = rim * (1 - 0.35 * groove[..., None])
    ang = np.arctan2(dy, dx)
    mill = (np.cos(ang * 72) * 0.5 + 0.5) * smoothstep(RO - 2.6 * K, RO - 0.8 * K, r)
    rim = rim * (1 - 0.18 * mill[..., None])
    # the face: dished, the rim's shadow on its top, its light on its foot
    rr = np.clip(r / RI, 0, 1)
    edge = smoothstep(0.55, 1.0, rr)
    top = np.clip(-uy, 0, 1)
    bot = np.clip(uy, 0, 1)
    if on:
        conc = norm(blur(rng.standard_normal((S, S)), 0.4 * K, 0.4 * K)) * 0.0
        # polished pale brass, turned on a lathe: fine rings
        rings = np.sin(r / (0.9 * K) * 2 * np.pi + norm(blur(rng.standard_normal((S, S)), 3 * K, 3 * K)) * 2.0) * 0.025
        face = BRASS * (1.08 + rings[..., None])
        face = face * (1 - (0.30 * edge * (0.4 + 0.6 * top)))[..., None] + (BRASS_HI - face) * (0.28 * edge * bot)[..., None]
        # a broad soft highlight across the upper left
        hl = np.exp(-(((dx + 7 * K) / (13 * K)) ** 2 + ((dy + 9 * K) / (8 * K)) ** 2))
        face = face + (BRASS_HI - face) * (0.55 * hl)[..., None]
    else:
        g = grain(S, S, WALNUT * (1.18 if hover else 1.0), 7 if hover else 5)
        face = g * (1 - (0.5 * edge * (0.35 + 0.65 * top)))[..., None] + hexc("7a5634") * (0.35 * edge * bot)[..., None]
        hl = np.exp(-(((dx + 6 * K) / (12 * K)) ** 2 + ((dy + 8 * K) / (7 * K)) ** 2))
        face = face + (hexc("8a6a46") - face) * (0.16 * hl)[..., None]
    col = np.where((r < RI)[..., None], face, rim)
    # the hair between face and rim, and round the outside
    col = col * (1 - 0.5 * np.exp(-((r - RI) / (0.6 * K)) ** 2))[..., None]
    col = col * (1 - 0.6 * np.exp(-((r - RO + 0.5 * K) / (0.6 * K)) ** 2))[..., None]
    cover = np.clip(RO - r + 0.5, 0, 1)
    glow = np.zeros_like(r)
    if hover or on:
        glow = smoothstep(RO + 9 * K, RO, r) * (0.28 if hover else 0.18) * (1 - cover)
    a_sh = sh * (1 - cover)
    a = cover + (1 - cover) * np.clip(a_sh + glow, 0, 1)
    warm = hexc("ffcf7a")
    out_rgb = warm * (glow / np.maximum(a_sh + glow, 1e-6))[..., None]
    rgb = (col * cover[..., None] + out_rgb * ((1 - cover) * np.clip(a_sh + glow, 0, 1))[..., None]) / np.maximum(a, 1e-6)[..., None]
    save(name, rgb, a)


# --- the glyphs, cut at 16 times and brought down --------------------------------------------------
G = 32 # UI px the glyph's box is
U = 32 # canvas px to a UI px while drawing


def canvas():
    im = Image.new("L", (G * U, G * U), 0)
    return im, ImageDraw.Draw(im)


def P(*pts):
    return [(x * U, y * U) for x, y in pts]


def rot(pts, ang, cx, cy):
    ca, sa = np.cos(ang), np.sin(ang)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]


def glyph_save(name, im):
    small = im.resize((G * K, G * K), Image.LANCZOS)
    a = np.asarray(small).astype(float) / 255.0
    save(name, np.ones(a.shape + (3,)), a)


def g_house():
    im, d = canvas()
    d.polygon(P((2.5, 15.2), (16, 4.0), (29.5, 15.2), (27.2, 15.2), (16, 6.6), (4.8, 15.2)), fill=255) # the roof's line
    d.polygon(P((5.6, 15.0), (16, 7.6), (26.4, 15.0)), fill=255) # (the gable)
    d.rectangle(P((20.6, 5.2), (23.6, 11.6)), fill=255) # the chimney
    d.rectangle(P((7.4, 16.2), (24.6, 28.0)), fill=255) # the walls
    d.rectangle(P((14.0, 19.6), (18.0, 28.0)), fill=0) # the door
    d.rectangle(P((9.4, 18.6), (12.4, 21.6)), fill=0) # windows
    d.rectangle(P((19.6, 18.6), (22.6, 21.6)), fill=0)
    d.rectangle(P((14.6, 10.6), (17.4, 13.4)), fill=0) # (the loft light in the gable)
    d.rectangle(P((4.0, 28.0), (28.0, 29.4)), fill=255) # the sill log
    return im


def g_hammer():
    im, d = canvas()
    cx, cy = 16, 16
    a = -np.pi / 4
    handle = rot([(14.6, 9.0), (17.4, 9.0), (17.8, 29.5), (14.2, 29.5)], a, cx, cy)
    head = rot([(7.0, 4.0), (21.5, 4.0), (21.5, 6.0), (24.5, 6.0), (24.5, 10.6), (21.5, 10.6), (21.5, 12.0), (7.0, 12.0), (6.0, 10.6), (6.0, 5.4)], a, cx, cy)
    # (the claw: a notched peen on the far side)
    claw = rot([(7.0, 4.0), (3.0, 2.4), (5.4, 7.6), (3.0, 12.8), (7.0, 12.0)], a, cx, cy)
    for poly in (handle, head, claw):
        d.polygon([(x * U, y * U) for x, y in poly], fill=255)
    wedge = rot([(15.2, 5.0), (16.8, 5.0), (16.8, 11.0), (15.2, 11.0)], a, cx, cy) # (the wedge in the eye)
    d.polygon([(x * U, y * U) for x, y in wedge], fill=0)
    return im


def g_wheel():
    im, d = canvas()
    c = 16 * U
    def circ(r, f):
        d.ellipse((c - r * U, c - r * U, c + r * U, c + r * U), fill=f)
    circ(13.6, 255)
    circ(10.9, 0)
    for k in range(10):
        a = k * np.pi * 2 / 10 + 0.1
        w = 0.95
        x1, y1 = 16 + np.cos(a) * 3.0, 16 + np.sin(a) * 3.0
        x2, y2 = 16 + np.cos(a) * 11.4, 16 + np.sin(a) * 11.4
        px, py = -np.sin(a) * w, np.cos(a) * w
        d.polygon(P((x1 + px * 1.2, y1 + py * 1.2), (x2 + px * 0.8, y2 + py * 0.8), (x2 - px * 0.8, y2 - py * 0.8), (x1 - px * 1.2, y1 - py * 1.2)), fill=255)
    circ(4.4, 255)
    circ(1.7, 0)
    # (the felloes' joints: little cuts in the rim)
    for k in range(5):
        a = k * np.pi * 2 / 5 + 0.42
        x1, y1 = 16 + np.cos(a) * 10.6, 16 + np.sin(a) * 10.6
        x2, y2 = 16 + np.cos(a) * 14.0, 16 + np.sin(a) * 14.0
        d.line(P((x1, y1), (x2, y2)), fill=0, width=int(0.7 * U))
    return im


def rifle(d, ang):
    """One rifle, muzzle up, turned `ang` about the middle."""
    pts = [(15.0, 1.4), (16.8, 1.4), (16.9, 12.6), (17.8, 12.6), (18.2, 19.5), (19.4, 27.0), (18.8, 30.6), (13.4, 30.6), (14.0, 21.0), (14.3, 12.6), (14.9, 12.6)]
    poly = rot(pts, ang, 16, 16)
    d.polygon([(x * U, y * U) for x, y in poly], fill=255)
    bolt = rot([(17.2, 14.6), (19.4, 15.2), (19.4, 16.4), (17.2, 16.2)], ang, 16, 16)
    d.polygon([(x * U, y * U) for x, y in bolt], fill=255)
    band = rot([(14.6, 9.6), (17.0, 9.6), (17.0, 10.6), (14.6, 10.6)], ang, 16, 16)
    d.polygon([(x * U, y * U) for x, y in band], fill=255)


def g_rifles():
    im, d = canvas()
    rifle(d, 0.6)
    # (the second laid over the first: a hair of clear round it where it crosses)
    over = Image.new("L", im.size, 0)
    od = ImageDraw.Draw(over)
    rifle(od, -0.6)
    from PIL import ImageFilter
    halo = over.filter(ImageFilter.MaxFilter(int(1.4 * U) | 1))
    im = Image.fromarray(np.minimum(np.asarray(im), 255 - np.asarray(halo)).astype(np.uint8))
    im = Image.fromarray(np.maximum(np.asarray(im), np.asarray(over)).astype(np.uint8))
    return im


def g_flag():
    im, d = canvas()
    d.rectangle(P((7.2, 5.0), (9.2, 30.0)), fill=255) # the staff
    d.ellipse(P((6.2, 2.0), (10.2, 6.0)), fill=255) # its knob
    top = [(9.2 + i * 0.8, 6.0 + np.sin(i * 0.8 / 18.0 * np.pi * 2) * 1.4) for i in range(24)]
    bot = [(9.2 + i * 0.8, 18.0 + np.sin(i * 0.8 / 18.0 * np.pi * 2 + 0.5) * 1.4) for i in range(24)]
    end = top[-1][0]
    # (the fly's end swallow-tailed, as a railway's flags were)
    poly = top + [(end, top[-1][1]), (end - 3.6, (top[-1][1] + bot[-1][1]) * 0.5), (end, bot[-1][1])] + bot[::-1]
    d.polygon(P(*poly), fill=255)
    # its fold: a cut line down it
    fold = [(16.8 + np.sin(t * 0.3) * 0.4, 7.4 + t) for t in np.linspace(0, 11.4, 20)]
    d.line(P(*fold), fill=0, width=int(0.8 * U))
    return im


def seal():
    """A blob of red wax pressed with a ring seal: uneven round its edge, lit from the top left."""
    S = 24 * K
    c = S / 2
    yy, xx = np.mgrid[0:S, 0:S].astype(float) + 0.5
    dx, dy = xx - c, yy - c
    r = np.hypot(dx, dy)
    ang = np.arctan2(dy, dx)
    wob = 1 + 0.06 * np.sin(ang * 5 + 0.4) + 0.04 * np.sin(ang * 9 + 1.3) + 0.03 * np.sin(ang * 14)
    R = 9.0 * K * wob
    d = R - r
    sh = smoothstep(-4 * K, 2 * K, (9.0 * K * wob) - np.hypot(dx, dy - 1.5 * K)) * 0.5
    t = np.clip(d / (2.4 * K), 0, 1)
    ux, uy = dx / (r + 1e-9), dy / (r + 1e-9)
    tilt = (1 - t) * np.pi * 0.42
    N = np.dstack([ux * np.sin(tilt), uy * np.sin(tilt), np.cos(tilt)])
    L = np.array([-0.45, -0.7, 0.55])
    L = L / np.linalg.norm(L)
    nl = (N * L).sum(axis=2)
    wax = hexc("7c1a12")
    col = wax * (0.62 + 0.55 * np.clip(nl, 0, 1))[..., None]
    spec = np.clip(2 * nl * N[..., 2] - L[2], 0, 1) ** 30
    col = col + (hexc("f4a88a") - col) * (spec * 0.6)[..., None]
    # the pressed ring and a star in it: sunk, so dark on their top side, lit on the foot
    ring = np.exp(-((r - 5.6 * K) / (0.55 * K)) ** 2)
    col = col * (1 - 0.35 * ring * (0.5 + 0.5 * np.clip(-uy, 0, 1)))[..., None] + hexc("c0473a") * (0.25 * ring * np.clip(uy, 0, 1))[..., None]
    star = np.zeros_like(r)
    for k in range(5):
        a = k * 2 * np.pi / 5 - np.pi / 2
        px, py = np.cos(a), np.sin(a)
        along = dx * px + dy * py
        across = np.abs(-dx * py + dy * px)
        star = np.maximum(star, ((along > 0) & (along < 3.8 * K) & (across < (1.1 * K) * (1 - along / (3.8 * K)) + 0.25 * K)).astype(float))
    col = col * (1 - 0.32 * star)[..., None]
    cover = np.clip(d + 0.5, 0, 1)
    a = cover + (1 - cover) * sh
    rgb = col * (cover / np.maximum(a, 1e-6))[..., None]
    save("seal.png", rgb, a)


def fibre():
    """Paper's fibre and a little foxing, as a tile: a dark mark where it's laid over the card."""
    S = 128 * K
    f1 = norm(blur(rng.standard_normal((S, S)), 0.5 * K, 3.5 * K, True, True))
    f2 = norm(blur(rng.standard_normal((S, S)), 3.5 * K, 0.5 * K, True, True))
    fox = norm(blur(rng.standard_normal((S, S)), 14 * K, 14 * K, True, True))
    a = np.clip(0.5 + 0.18 * f1 + 0.14 * f2, 0, 1) * 0.5 + smoothstep(1.4, 2.6, fox) * 0.18
    a = np.clip(a - 0.18, 0, 1)
    save("fibre.png", np.ones((S, S, 3)) * hexc("6b4520"), a)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    # plinth: 12 shadow + 92 high, runs off the foot; tray: 12 shadow round it, 104 + its tuck
    board("plinth.png", (192, 104), (28, 28, 28, 8), WALNUT, 12, 12, True, 3)
    board("shelf.png", (192, 140), (28, 28, 28, 28), SHELF, 9, 12, False, 4)
    for st in ("idle", "hover", "on"):
        medal("medal_%s.png" % st, st)
    glyph_save("glyph_kasaba.png", g_house())
    glyph_save("glyph_uretim.png", g_hammer())
    glyph_save("glyph_tasima.png", g_wheel())
    glyph_save("glyph_savunma.png", g_rifles())
    glyph_save("glyph_emirler.png", g_flag())
    seal()
    fibre()
