"""The new town's sheets: a square of old paper, foxed and creased, its edges torn and darkened, a
soft shadow under it. Cut as a nine-patch by scripts/title_menu.gd.

    python tools/parchment.py

Output: assets/ui/parchment.png
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

S = 768
EDGE = 34  # where the paper's torn edge lies, on average, in from the image's
rng = np.random.default_rng(1918)


def noise(blur, scale=1.0):
    # (wrapped: a nine-patch's middle tiles)
    n = ndimage.gaussian_filter(rng.standard_normal((S, S)), blur, mode="wrap")
    return n / n.std() * scale


def edge_wobble():
    # the torn line, one value along each side: big bites and fine fray (the same round each side's ends)
    a = ndimage.gaussian_filter1d(rng.standard_normal(S), 26, mode="wrap")
    b = ndimage.gaussian_filter1d(rng.standard_normal(S), 5, mode="wrap")
    c = ndimage.gaussian_filter1d(rng.standard_normal(S), 1.4, mode="wrap")
    return a / a.std() * 7.0 + b / b.std() * 3.0 + c / c.std() * 1.2


yy, xx = np.mgrid[0:S, 0:S].astype(float)
d_left = xx - (EDGE + edge_wobble()[:, None])
d_right = (S - 1 - xx) - (EDGE + edge_wobble()[:, None])
d_top = yy - (EDGE + edge_wobble()[None, :])
d_bot = (S - 1 - yy) - (EDGE + edge_wobble()[None, :])
inside = np.minimum.reduce([d_left, d_right, d_top, d_bot])

base = np.array([0.885, 0.805, 0.65])
c = np.ones((S, S, 3)) * base
c *= (1.0 + noise(90, 0.035) + noise(24, 0.025) + noise(5, 0.016) + noise(1.2, 0.012))[..., None]
# fibres, long and faint
fib = ndimage.gaussian_filter(rng.standard_normal((S, S)), (0.7, 9), mode="wrap")
c *= (1.0 + fib / fib.std() * 0.012)[..., None]
# foxing: brown spots
spots = (noise(7) > 2.3).astype(float)
spots = ndimage.gaussian_filter(spots, 3, mode="wrap")
c = c * (1.0 - spots[..., None] * 0.6) + np.array([0.52, 0.34, 0.17]) * spots[..., None] * 0.6
# stains and creases
stain = np.clip(noise(55) - 1.2, 0, 1) * 0.22
c = c * (1.0 - stain[..., None]) + np.array([0.6, 0.45, 0.28]) * stain[..., None]
# burnt brown toward the edge
burn = np.clip(1.0 - inside / 52.0 + noise(18, 0.12), 0, 1) ** 2.4
c = c * (1.0 - burn[..., None] * 0.6) + np.array([0.46, 0.31, 0.17]) * burn[..., None] * 0.6
# the pale raw fibre right at the tear
rim = np.clip(1.0 - np.abs(inside - 2.5) / 3.0, 0, 1)
c = c * (1.0 - rim[..., None] * 0.55) + np.array([0.9, 0.84, 0.72]) * rim[..., None] * 0.55

alpha = np.clip(inside + 0.5, 0, 1)
shadow = ndimage.gaussian_filter(np.roll(np.roll(alpha, 7, axis=0), 4, axis=1), 9) * 0.6
a = alpha + (1.0 - alpha) * shadow
rgb = c * alpha[..., None]  # (the shadow black under the paper)
rgb = rgb / np.maximum(a[..., None], 1e-3)
out = np.dstack([np.clip(rgb, 0, 1), a])
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(os.path.join(root, "assets", "ui", "parchment.png"))
print("parchment written")
