"""Builds İnşa's engine, saw and wood sounds from CC0 / public-domain recordings.

    python -I tools/audio/build_insa_sounds.py <downloads dir> [<project dir>]

<downloads dir> holds each source as downloaded (see assets/audio/CREDITS.md for what and where):
bsb_<n>/<n>.wav are BigSoundBank's WAVs (https://bigsoundbank.com/UPLOAD/bwf-en/<n>.wav),
wc_detroit/detroit.ogg is Wikimedia Commons' File:Detroit62.ogg.
Every choice (which seconds, how far each layer is re-timed, the levels) is here.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sndlib import *

DL = sys.argv[1]
OUT = os.path.join(sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(__file__), "..", ".."), "assets", "audio")


def bsb(n, t0=0.0, t1=None):
    return load(os.path.join(DL, "bsb_%s" % n, "%s.wav" % n), t0, t1)


def report(name, x):
    print("%-34s %6.2fs rms %6.1f peak %6.1f" % (name, len(x) / SR, db(rms(x)), db(np.max(np.abs(x)))))


def put_ogg(rel, x):
    write_ogg(x, os.path.join(OUT, rel))
    report(rel, x)


def put_wav(rel, x):
    write_wav(x, os.path.join(OUT, rel))
    report(rel, x)


# --- Engines ---------------------------------------------------------------------------------------
# Each engine is a few loops at rising revs, crossfaded by the game (EngineSound) and each pitched only
# a little either side. The idle is the recording itself; the higher ones are the same engine's firings
# re-timed closer together (pitch-synchronous: every pulse keeps its own sound, only the gaps shorten),
# so it gets faster without the whole sound being sped up. Brighter and harder the higher it goes.

def engine_set(name, src, period, factors, length, hp_f, bright, low_shelf=None, lo=60.0, hi=3000.0, jitter=0.004, excite=0.0, block=1):
    x = hp(src, hp_f)
    if low_shelf:
        x = shelf_lo(x, *low_shelf)
    m = firing_marks_tracked(x, period, lo, hi)
    per = np.diff(m) / SR
    print("%s: %d firings, %.2f Hz (sd %.1f %%)" % (name, len(m), 1.0 / np.median(per), 100 * np.std(per) / np.median(per)))
    for i, k in enumerate(factors):
        y = psola_loop(x, m, k, length, jitter=jitter, seed=i + 1, block=block)
        if bright[i]:
            y = shelf_hi(y, 1200.0, bright[i])
        if excite:
            # (the recording stops at 5.5 kHz: a little of its own clatter, driven, put back above that)
            pk = np.max(np.abs(y))
            y = y + excite * (1.0 + 0.5 * i) * hp(np.tanh(3.0 * hp(y, 1800.0) / pk) * pk, 5000.0, 4)
        y = level(y, -17.0 + 1.0 * i, -1.0)
        put_ogg("engine/%s_%d.ogg" % (name, i), y)
    return 1.0 / np.median(per)


# engine_s, "Küçük motor": a 1903 De Dion-Bouton single (BSB 2546), putting 7.5 times a second at idle,
# re-timed up to 3x (22 a second).
f_small = engine_set("small", bsb("2546", 0.5, 19.5), 0.13285, [1.0, 1.45, 2.1, 3.0], 6.0, 40.0, [0, 1.5, 3.0, 4.5])
# engine_l, "V8 dizel": a Detroit 6.2 l V8 diesel at idle (Wikimedia Commons, Detroit62.ogg, CC0): its two
# idling stretches (0-1 s, 6.4-9.9 s) joined, 40 firings a second (600 rpm), re-timed up to 3.3x (2000 rpm).
def detroit():
    d = load(os.path.join(DL, "wc_detroit", "detroit.ogg"))
    a = d[int(0.05 * SR):int(1.0 * SR)]
    b = d[int(6.4 * SR):int(9.9 * SR)]
    X = int(0.08 * SR)
    t = np.linspace(0, np.pi / 2, X)
    return np.concatenate([a[:-X], a[-X:] * np.cos(t) + b[:X] * np.sin(t), b[X:]])

f_v8 = engine_set("big", detroit(), 0.02473, [1.0, 1.5, 2.25, 3.3], 5.0, 28.0, [0, 1.0, 2.0, 3.0],
                  low_shelf=(150.0, 2.0), lo=50.0, hi=2000.0, jitter=0.004, excite=0.12, block=8)

# engine, "Dizel motor": an Iveco Daily 3.0 four-cylinder diesel at idle (BSB 1145), 28.7 firings a second
# (860 rpm), re-timed up to 3.1x (2700 rpm), a whole engine cycle (four firings) at a time.
f_diesel = engine_set("diesel", bsb("1145", 2.0, 33.0), 0.03483, [1.0, 1.5, 2.2, 3.1], 7.0, 30.0, [0, 1.0, 2.0, 3.0],
                      lo=50.0, hi=2500.0, block=4)

# --- The saw: a circular blade turning free, and biting into wood ------------------------------
def saw():
    idle = bsb("1135", 2.5, 13.6)
    idle = level(loop(hp(idle, 60.0), 9.0, 1.0), -18.0)
    put_ogg("tools/saw_idle.ogg", idle)
    # the cuts in BSB 1136 (a table saw through boards), the blade labouring, joined end to end
    parts = [bsb("1136", a, b) for a, b in [(8.1, 12.9), (24.0, 26.6), (37.0, 41.2), (49.0, 51.2), (57.5, 59.8)]]
    X = int(0.25 * SR)
    t = np.linspace(0, np.pi / 2, X)
    cut = parts[0]
    for p in parts[1:]:
        cut = np.concatenate([cut[:-X], cut[-X:] * np.cos(t) + p[:X] * np.sin(t), p[X:]])
    cut = hp(cut, 60.0)
    cut = shelf_lo(cut, 400.0, 3.0) # (heavier: a log, not a plank)
    cut = level(loop(cut, len(cut) / SR - 0.4, 0.4), -15.0)
    put_ogg("tools/saw_cut.ogg", cut)

saw()

# --- Wood ---------------------------------------------------------------------------------------
def wood():
    # a tree going over and down (BSB 2750, after the chainsaw stops): the swish, the crash, the settling
    fall = bsb("2750", 18.55, 22.8)
    fall = fade(hp(fall, 40.0), 0.01, 1.6)
    fall = shelf_lo(fall, 200.0, 4.0)
    fall = level_peak(fall, -1.0)
    # the cut giving: twigs snapping (BSB 1299) taken down an octave and a half into a trunk's crack, the
    # tree's creak (BSB 1051, a branch grinding in the wind) under it
    tw = bsb("1299")
    snaps = []
    for a in [1.08, 3.66, 0.18, 1.86, 2.66]:
        s = tw[int(a * SR):int((a + 0.35) * SR)]
        snaps.append(resample(s, 0.4))
    crack = np.zeros(int(1.9 * SR))
    for i, (s, at, g) in enumerate(zip(snaps, [0.62, 0.70, 0.95, 1.08, 1.25], [1.0, 0.6, 0.8, 0.5, 0.7])):
        a = int(at * SR)
        n = min(len(s), len(crack) - a)
        crack[a:a + n] += s[:n] * g / max(np.max(np.abs(s)), 1e-9)
    creak = bsb("1051", 0, 40.0)
    # the loudest creak in the first 40 s
    e = fftconvolve(bp(creak, 200, 2000) ** 2, np.ones(SR // 4), "same")
    c0 = max(int(np.argmax(e)) - int(0.9 * SR), 0)
    cr = resample(creak[c0:c0 + int(1.6 * SR)], 0.8)[:len(crack)]
    cr = fade(bp(cr, 120, 4000), 0.25, 0.4)
    crack[:len(cr)] += cr * (0.5 / max(np.max(np.abs(cr)), 1e-9))
    crack = fade(hp(crack, 50.0), 0.05, 0.25)
    put_wav("wood/tree_crack.wav", level_peak(crack, -1.0))
    # knocks: an axe's blows on a log (BSB 705), each its own hit
    ax = bsb("0705")
    e = np.abs(ax)
    pk, _ = find_peaks(e, height=0.1, distance=SR)
    for i, p in enumerate(pk[[1, 4, 7, 10]]):
        s = ax[max(p - int(0.004 * SR), 0):p + int(0.30 * SR)]
        s = fade(hp(s, 60.0), 0.002, 0.12)
        put_wav("wood/knock_%02d.wav" % (i + 1), level_peak(s, -1.0))
    # a log dropped: logs off a truck's bed (BSB 1441), the single thumps near the end
    lg = bsb("1441")
    for i, a in enumerate([121.30, 119.35, 122.85]):
        s = lg[int(a * SR):int((a + 0.9) * SR)]
        p = int(np.argmax(np.abs(s[: int(0.5 * SR)])))
        s = s[max(p - int(0.01 * SR), 0):]
        s = fade(hp(s, 45.0), 0.004, 0.45)
        put_wav("wood/log_drop_%02d.wav" % (i + 1), level_peak(s, -1.0))
        if i == 1:
            thump = s
    # the trunk's weight under the crash (the recording is mostly its branches): that log's thump an
    # octave down, where the crash is loudest
    th = lp(resample(thump, 0.55), 900.0)
    th = fade(th, 0.0, 0.3)
    at = int(np.argmax(np.abs(fall[: int(0.8 * SR)]))) - int(0.015 * SR)
    n = min(len(th), len(fall) - at)
    fall[at:at + n] += th[:n] * (0.9 / np.max(np.abs(th)))
    put_wav("wood/tree_fall.wav", level_peak(fall, -1.0))

wood()
print("idle firings: small %.2f Hz, diesel %.2f Hz, big %.2f Hz" % (f_small, f_diesel, f_v8))
