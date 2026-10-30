# Audio credits

## Engines, the saw, wood (`engine/`, `tools/`, `wood/`)

Built by `tools/audio/build_insa_sounds.py` (every cut, re-timing and level is in it) from the recordings
below, downloaded as they are offered (BigSoundBank's WAVs at `https://bigsoundbank.com/UPLOAD/bwf-en/<n>.wav`).
All of them are **CC0 1.0 / public domain**: no attribution is required; the authors are credited anyway.
The derived files are released under CC0 as well.

| Files | Source | Author | Licence |
|---|---|---|---|
| `engine/small_0..3.ogg` (engine_s, "Küçük motor") | [Engine of 1903 De Dion-Bouton Type Q](https://bigsoundbank.com/engine-of-1903-dion-bouton-type-q-s2546.html) (BSB 2546) | Joseph Sardin, BigSoundBank | CC0 |
| `engine/diesel_0..3.ogg` (engine, "Dizel motor") | [Truck engine](https://bigsoundbank.com/truck-engine-s1145.html) (BSB 1145, an Iveco Daily 3.0 diesel idling) | Joseph Sardin, BigSoundBank | CC0 |
| `engine/big_0..3.ogg` (engine_l, "V8 dizel") | [File:Detroit62.ogg](https://commons.wikimedia.org/wiki/File:Detroit62.ogg) (a Detroit 6.2 l V8 diesel) | Sixthstar, Wikimedia Commons | CC0 |
| `tools/saw_idle.ogg` | [Table saw (empty)](https://bigsoundbank.com/table-saw-empty-s1135.html) (BSB 1135, the blade turning free) | Joseph Sardin, BigSoundBank | CC0 |
| `tools/saw_cut.ogg` | [Table saw (cut)](https://bigsoundbank.com/table-saw-cut-s1136.html) (BSB 1136, cutting wood) | Joseph Sardin, BigSoundBank | CC0 |
| `wood/tree_fall.wav` | [Chainsaw and falling tree](https://bigsoundbank.com/chainsaw-and-falling-tree-s2750.html) (BSB 2750, 18.55-22.8 s: after the saw stops), with the thump of `log_drop_02` an octave down under its crash | Joseph Sardin, BigSoundBank | CC0 |
| `wood/tree_crack.wav` | [Broken twigs 1](https://bigsoundbank.com/broken-twigs-1-s1299.html) (BSB 1299, five snaps taken down 1.3 octaves) over [Wind and tree squeaks](https://bigsoundbank.com/wind-and-tree-squeaks-s1051.html) (BSB 1051, a branch grinding) | Joseph Sardin, BigSoundBank | CC0 |
| `wood/knock_01..04.wav` | [Ax on log](https://bigsoundbank.com/ax-on-log-s0705.html) (BSB 705, single blows) | Joseph Sardin, BigSoundBank | CC0 |
| `wood/log_drop_01..03.wav` | [Unloading logs](https://bigsoundbank.com/unloading-logs-s1441.html) (BSB 1441, single logs landing, 119-124 s) | Joseph Sardin, BigSoundBank | CC0 |

How the engines are made: each is four loops of the one engine at rising revs. Loop 0 is the recording at
idle (the De Dion single 7.4 firings a second, the Iveco four 28.4, the Detroit V8 40.1). Loops 1-3 are the
same engine's own firings re-timed closer together (pitch-synchronous overlap-add: each firing cut out
and laid at the shorter period, so the pulses keep their own sound and the engine just runs faster;
1.45-3.3x), a whole engine cycle at a time, a little brighter the higher they go, each wrapped round on
itself so it loops without a seam. In the game `EngineSound` (scripts/engine_sound.gd) crossfades the two
loops either side of the revs and pitches each only a little (about ±20 % at most), louder on the
throttle; a badly hurt engine misses.

The saw: the free-running loop is 2.5-12.5 s of BSB 1135 (crossfaded at the seam); the cutting loop is
the five cuts of BSB 1136 joined end to end (8.1-12.9, 24.0-26.6, 37.0-41.2, 49.0-51.2, 57.5-59.8 s), a
little heavier in the lows (a log, not a plank). MachineTool fades from one to the other as the blade bites.

Not used (downloaded and checked, left out): BigSoundBank's AC Cobra 427 (534, its
firings too uneven to re-time), small tractor (499), tractors (132, 133), mower (1071), generator (115),
cement mixer (885), excavator (2147, idling, not at working revs as hoped), truck engine 2 (1443), Kia
diesel (967), sawmills (1536, 1538), band saw (139), chair falling (516), creaking barn door (539), and
Wikimedia Commons' Rover V8 (public domain). The engine loops these replace (`engine_idle/low/high_loop.ogg`,
BSB 1145-1147 cut into 2.4 s pieces with the revs wandering inside them, and only one of them used, sped up
and slowed down) are gone.

## Rolling

| File | Source | Author |
|---|---|---|
| `dirt_roll_loop.ogg` | [Toyota Landcruiser 4x4, dirt road, mud](https://freesound.org/people/felix.blume/sounds/668552/) (FS-668552) | felix.blume (Freesound), CC0 |

Copied from the Mud Run project (`car/assets/audio/vehicle`), cut and looped there by
`tools/audio/build_vehicle_audio.sh`.

## Weapons, impacts, explosions

Copied from the Mud Run project as they were:

- `weapons/close_0*.wav`, `weapons/tail_01.wav`: the light machine gun ("hafif") shots, built from the Free Firearm
  Sound Library (CC0); see `weapons/CREDITS.md`.
- `impact/*.wav` and `explosion/*.wav`: Sonniss GDC bundles (royalty free); see `CREDITS_SONNISS.md`.

Touched up here (10-30): `weapons/flip_air.wav` was clipping and ended mid-sound; it is 2.5 dB down with a
0.1 s fade at its end.

## İnşa's own

- `impact/tyre_pop.wav`: synthesized (a Python one-off): a few milliseconds of broad noise for the
  bang, a 70 Hz thump, and the air hissing out (high-passed noise dying over a third of a second). CC0.
  (10-30: 2.5 dB down, it was clipping, and faded over its last 0.15 s, where it stopped dead.)
