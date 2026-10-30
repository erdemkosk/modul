"""Small DSP helpers for building İnşa's sounds from recordings (numpy/scipy, ffmpeg on PATH)."""
import os, subprocess, tempfile
import numpy as np
from scipy.signal import butter, sosfiltfilt, sosfilt, find_peaks, resample_poly, fftconvolve
from scipy.io import wavfile

SR = 48000


def load(path, t0=0.0, t1=None, sr=SR):
    """Mono float64 at `sr`, from t0 to t1 seconds."""
    cmd = ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-acodec", "pcm_f32le", "-ar", str(sr), "-ac", "1", "-"]
    x = np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, dtype=np.float32).astype(np.float64)
    a = int(t0 * sr)
    b = len(x) if t1 is None else int(t1 * sr)
    return x[a:b].copy()


def rms(x):
    return float(np.sqrt(np.mean(x * x))) if len(x) else 0.0


def db(v):
    return 20.0 * np.log10(max(v, 1e-12))


def hp(x, f, order=2):
    return sosfiltfilt(butter(order, f, "high", fs=SR, output="sos"), x)


def lp(x, f, order=2):
    return sosfiltfilt(butter(order, f, "low", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=2):
    return sosfiltfilt(butter(order, [lo, hi], "band", fs=SR, output="sos"), x)


def shelf_hi(x, f, gain_db):
    """A gentle high shelf: the part above f scaled (approximate, zero phase)."""
    g = 10 ** (gain_db / 20.0) - 1.0
    return x + g * hp(x, f, 1)


def shelf_lo(x, f, gain_db):
    g = 10 ** (gain_db / 20.0) - 1.0
    return x + g * lp(x, f, 1)


def resample(x, ratio):
    """Plays `ratio` times faster (pitch up by ratio, shorter)."""
    from fractions import Fraction
    fr = Fraction(ratio).limit_denominator(200)
    return resample_poly(x, fr.denominator, fr.numerator)


def even_level(x, win=0.4, amount=1.0):
    """Takes out slow swells in level (a pass-by, a gust): the envelope over `win` s levelled to its median."""
    n = int(win * SR)
    e = np.sqrt(np.maximum(fftconvolve(x * x, np.ones(n) / n, mode="same"), 0) + 1e-12)
    g = (np.median(e) / e) ** amount
    g = np.clip(g, 0.25, 4.0)
    return x * g


def fade(x, fin=0.0, fout=0.0):
    y = x.copy()
    a = int(fin * SR)
    b = int(fout * SR)
    if a > 0:
        y[:a] *= np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    if b > 0:
        y[-b:] *= np.cos(np.linspace(0, np.pi / 2, b)) ** 2
    return y


def loop(seg, length, xfade):
    """A seamless loop `length` s long from `seg` (needs length + xfade s): its end crossfaded into its start
    (equal power), so the wrap is the recording carrying on."""
    L = int(length * SR)
    X = int(xfade * SR)
    assert len(seg) >= L + X, (len(seg) / SR, length, xfade)
    out = seg[:L].copy()
    t = np.linspace(0, np.pi / 2, X)
    out[:X] = seg[:X] * np.sin(t) + seg[L:L + X] * np.cos(t)
    return out


def level(x, rms_db=-18.0, peak_db=-1.0):
    """RMS to `rms_db`, then any peak over `peak_db` softly limited."""
    y = x * (10 ** (rms_db / 20.0) / max(rms(x), 1e-9))
    lim = 10 ** (peak_db / 20.0)
    over = np.abs(y) > lim * 0.7
    if np.any(over):
        k = lim * 0.7
        s = np.sign(y)
        a = np.abs(y)
        a = np.where(a > k, k + (lim - k) * np.tanh((a - k) / (lim - k)), a)
        y = s * a
    return y


def level_peak(x, peak_db=-1.0):
    return x * (10 ** (peak_db / 20.0) / max(np.max(np.abs(x)), 1e-9))


def write_wav(x, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    y = np.clip(x, -1.0, 1.0)
    wavfile.write(path, SR, (y * 32767.0).astype(np.int16))


def write_ogg(x, path, q=6):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    write_wav(x, tmp)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(q), path], check=True)
    os.remove(tmp)


# --- engines: pitch-synchronous re-timing --------------------------------------------------------

def firing_marks(x, f0, lo=60.0, hi=3000.0):
    """The firing pulses of a running engine near `f0` Hz: peaks of its band-passed envelope, one a period."""
    e = np.abs(bp(x, lo, hi))
    e = lp(e, min(f0 * 3.0, 400.0))
    T = SR / f0
    pk, _ = find_peaks(e, distance=int(T * 0.7))
    # keep it one a period: where two fall closer than 0.75 T keep the louder
    out = [pk[0]]
    for p in pk[1:]:
        if p - out[-1] < 0.75 * T:
            if e[p] > e[out[-1]]:
                out[-1] = p
        else:
            out.append(p)
    return np.array(out)


def psola_loop(x, marks, factor, length, jitter=0.0, seed=1, block=8):
    """The engine `factor` times faster with its pulses' own sound kept (TD-PSOLA): each firing cut from
    the source and laid at the new period, wrapped round so the result loops seamlessly. The firings are
    taken in their order while the source lasts, then in runs of `block` (an engine cycle: every cylinder
    once) from random places in it, so a short recording still makes a long loop that doesn't repeat
    itself. `length` is about the loop's length in s (it ends on a whole firing)."""
    rng = np.random.default_rng(seed)
    per = np.diff(marks)
    avail = np.arange(1, len(marks) - 1)  # marks with a period either side
    want = int(length * SR)
    js = []
    acc = 0.0
    i = 0
    while acc < want:
        if i < len(avail):
            j = avail[i]
            i += 1
        else:
            if (len(js) % block) == 0 or js[-1] + 1 > avail[-1]:
                start = int(rng.integers(0, max(len(avail) - block, 1)))
                j = avail[start]
            else:
                j = js[-1] + 1
        js.append(j)
        acc += per[j] / factor
    P = np.array([per[j] / factor for j in js]) * (1.0 + jitter * rng.standard_normal(len(js)))
    P = np.maximum(P, 8).astype(int)
    L = int(np.sum(P))
    out = np.zeros(L)
    t = 0
    for k, j in enumerate(js):
        left = P[k - 1]  # the previous output period (wraps for k = 0)
        right = P[k]
        m = marks[j]
        a = max(m - left, 0)
        b = min(m + right, len(x))
        g = x[a:b].copy()
        # asymmetric Hann: rises over the period before, falls over the one after
        wl = np.sin(np.linspace(0, np.pi / 2, m - a, endpoint=False)) ** 2
        wr = np.cos(np.linspace(0, np.pi / 2, b - m, endpoint=False)) ** 2
        g *= np.concatenate([wl, wr])
        idx = (np.arange(a, b) - m + t) % L
        np.add.at(out, idx, g)
        t += right
    return out


def firing_marks_tracked(x, period, lo=60.0, hi=3000.0, smooth=None, search=0.22):
    """Firing marks followed one period at a time (for engines whose envelope has more than one peak a
    firing): the next mark is the envelope's peak within `search` of a period after the last, the
    period itself allowed to drift slowly."""
    T = period * SR
    e = np.abs(bp(x, lo, hi))
    e = lp(e, smooth if smooth else min(3.0 * SR / T, 400.0))
    m = [int(np.argmax(e[: int(T)]))]
    Tl = T
    while True:
        c = m[-1] + Tl
        a = int(c - search * T)
        b = int(c + search * T)
        if b >= len(e):
            break
        k = np.arange(a, b)
        w = np.exp(-0.5 * ((k - c) / (0.12 * T)) ** 2)
        n = a + int(np.argmax(e[a:b] * w))
        Tl = float(np.clip(0.85 * Tl + 0.15 * (n - m[-1]), 0.85 * T, 1.15 * T))
        m.append(n)
    return np.array(m)
