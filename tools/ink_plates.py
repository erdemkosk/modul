"""The build bar's plates: each building as an engraver would cut it for a 1910s catalogue.

From the two passes tools/building_icons.gd draws with --passes (<kind>_c.png its colours,
<kind>_n.png its surfaces), each building is:
  - fitted to the same frame (cropped to itself and scaled so its larger side fills the same share
    of the plate: a tower and a field weigh the same),
  - drawn in sepia ink: a firm outline, the creases where its faces turn, the seams of its logs and
    boards; its shaded sides hatched (one way, then crossed, then crossed again in the darkest),
  - washed with a light hand tint of its own colours under the ink, as the coloured plates were,
  - set on a few strokes of ground.

    python tools/ink_plates.py <passes dir> [--sheet <png>]

Output: assets/ui/plates/<kind>.png, 256 x 256, clear around the drawing.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

W = 512 # the working canvas (drawn at twice the size, then brought down: the lines come out smooth)
OUT = 256
FILL = 0.84 # of the plate its larger side takes
INK = np.array([0.17, 0.105, 0.065])
SEPIA = np.array([1.0, 0.92, 0.8])


def fit(c, n):
    """Both passes cropped to the drawing and scaled into the W x W canvas, centred."""
    a = c[..., 3]
    ys, xs = np.nonzero(a > 0.04)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    h, w = y1 - y0, x1 - x0
    k = FILL * W / max(h, w)
    nh, nw = max(1, int(round(h * k))), max(1, int(round(w * k)))
    out = []
    for img in (c, n):
        crop = Image.fromarray((img[y0:y1, x0:x1] * 255).astype(np.uint8))
        crop = crop.resize((nw, nh), Image.LANCZOS)
        canvas = np.zeros((W, W, img.shape[2]))
        oy = (W - nh) // 2 + int(W * 0.02) # (a touch low: room over it, the ground under it)
        ox = (W - nw) // 2
        canvas[oy:oy + nh, ox:ox + nw] = np.asarray(crop) / 255.0
        out.append(canvas)
    return out


def sobel(x):
    return np.hypot(ndimage.sobel(x, 0), ndimage.sobel(x, 1))


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def ink_plate(c, n):
    c, n = fit(c, n)
    a = c[..., 3]
    solid = a > 0.5
    inside = ndimage.binary_erosion(solid, iterations=2)
    col = c[..., :3]
    lum = col @ np.array([0.3, 0.59, 0.11])
    # --- the lines
    # (drawn for the size it's seen at, some 90 px across: a line there is 5-6 px here)
    sil = smoothstep(0.15, 0.6, sobel(a)) # the outline, on the edge of the drawing
    sil = ndimage.grey_dilation(sil, size=(5, 5))
    nx, ny, dep = n[..., 0], n[..., 1], n[..., 2]
    crease = np.maximum(sobel(nx), sobel(ny)) + sobel(dep) * 6.0
    crease = ndimage.grey_dilation(smoothstep(0.8, 1.6, crease), size=(3, 3)) * inside
    detail = smoothstep(0.4, 0.75, sobel(lum)) * inside * 0.55
    lines = np.clip(np.maximum.reduce([sil, crease, detail]), 0, 1)
    lines = ndimage.gaussian_filter(lines, 0.55)
    lines = smoothstep(0.12, 0.6, lines)
    # --- the hatching, from how dark it is (against this drawing's own lights and darks)
    vals = lum[inside]
    lo, hi = (np.percentile(vals, 4), np.percentile(vals, 96)) if vals.size else (0.0, 1.0)
    t = np.clip((lum - lo) / max(hi - lo, 1e-3), 0, 1)
    yy, xx = np.mgrid[0:W, 0:W].astype(float)
    def stripes(u, period, width):
        d = np.abs(((u / period) % 1.0) - 0.5) * period # distance to the nearest stroke
        return 1.0 - smoothstep(width * 0.5, width * 0.5 + 0.9, d)
    h1 = stripes(xx + yy, 15.0 * 1.414, 3.2) * (1 - smoothstep(0.3, 0.46, t))
    h2 = stripes(xx - yy, 15.0 * 1.414, 3.0) * (1 - smoothstep(0.1, 0.22, t))
    hatch = np.clip(h1 + h2, 0, 1) * inside * 0.7
    # --- the tint under the ink: its own colours, faded toward the paper, a little sepia
    grey = lum[..., None].repeat(3, axis=2)
    tint = (grey + (col - grey) * 0.75) * SEPIA
    tint = 0.22 + 0.85 * tint
    tint_a = a * 0.85
    # --- ground: a few strokes under it, shortest lowest
    ground = np.zeros((W, W))
    rows = np.nonzero(solid.any(axis=1))[0]
    if rows.size:
        foot = rows.max()
        bottom = np.nonzero(solid[max(foot - 6, 0):foot + 1].any(axis=0))[0]
        if bottom.size:
            cx, half = (bottom.min() + bottom.max()) / 2.0, (bottom.max() - bottom.min()) / 2.0 + 18
            for i, (dy, k) in enumerate([(6, 1.0), (12, 0.7), (18, 0.42)]):
                y = foot + dy
                if y >= W:
                    break
                x0, x1 = int(cx - half * k + 10 * i), int(cx + half * k + 14 * i)
                ground[y - 1:y + 1, max(x0, 0):min(x1, W)] = 0.8 - 0.18 * i
            ground = ndimage.gaussian_filter(ground, 0.6) * (1 - a)
    ink_a = np.clip(np.maximum.reduce([lines, hatch]), 0, 1)
    # --- the plate: ink over the tint
    out_a = ink_a + tint_a * (1 - ink_a)
    rgb = (INK * ink_a[..., None] + tint * (tint_a * (1 - ink_a))[..., None]) / np.maximum(out_a, 1e-4)[..., None]
    img = np.dstack([np.clip(rgb, 0, 1), np.clip(out_a, 0, 1)])
    pil = Image.fromarray((img * 255).astype(np.uint8), "RGBA")
    return pil.resize((OUT, OUT), Image.LANCZOS)


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")) / 255.0


def main():
    src = sys.argv[1]
    sheet = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else None
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "ui", "plates")
    os.makedirs(out_dir, exist_ok=True)
    kinds = sorted(f[:-6] for f in os.listdir(src) if f.endswith("_c.png") and os.path.exists(os.path.join(src, f[:-6] + "_n.png")))
    plates = []
    for k in kinds:
        p = ink_plate(load(os.path.join(src, k + "_c.png")), load(os.path.join(src, k + "_n.png")))
        p.save(os.path.join(out_dir, k + ".png"))
        plates.append(p)
        print("plate:", k)
    if sheet and plates:
        # a proof: each on a cream enamel disc, as the bar will show them
        cols = 6
        cell = 300
        rows = (len(plates) + cols - 1) // cols
        proof = Image.new("RGBA", (cols * cell, rows * cell), (58, 40, 28, 255))
        disc = Image.new("RGBA", (cell, cell), (0, 0, 0, 0))
        yy, xx = np.mgrid[0:cell, 0:cell]
        r = np.hypot(xx - cell / 2, yy - cell / 2)
        d = np.zeros((cell, cell, 4))
        d[..., :3] = np.array([0.93, 0.88, 0.77]) - (r / (cell / 2))[..., None] * 0.08
        d[..., 3] = (r < cell * 0.46).astype(float)
        ring = (np.abs(r - cell * 0.46) < 5).astype(float)
        d[..., :3] = d[..., :3] * (1 - ring[..., None]) + np.array([0.78, 0.6, 0.3]) * ring[..., None]
        d[..., 3] = np.maximum(d[..., 3], ring)
        disc = Image.fromarray((d * 255).astype(np.uint8), "RGBA")
        for i, p in enumerate(plates):
            x, y = (i % cols) * cell, (i // cols) * cell
            proof.alpha_composite(disc, (x, y))
            proof.alpha_composite(p.resize((int(cell * 0.78),) * 2, Image.LANCZOS), (x + int(cell * 0.11), y + int(cell * 0.11)))
        small = Image.new("RGBA", (cols * 110, rows * 110), (58, 40, 28, 255))
        sd = disc.resize((104, 104), Image.LANCZOS)
        for i, p in enumerate(plates):
            x, y = (i % cols) * 110, (i // cols) * 110
            small.alpha_composite(sd, (x + 3, y + 3))
            small.alpha_composite(p.resize((84, 84), Image.LANCZOS), (x + 13, y + 13))
        both = Image.new("RGBA", (proof.width, proof.height + small.height + 10), (58, 40, 28, 255))
        both.alpha_composite(proof, (0, 0))
        both.alpha_composite(small, (0, proof.height + 10))
        both.save(sheet)


if __name__ == "__main__":
    main()
