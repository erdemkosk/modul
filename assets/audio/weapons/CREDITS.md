# Gun shot audio credits

The shots of every gun (`<gun>/close_*`, `body_*`, `body_suppressed_*`, `tail_*`, `distant_*`, `far_*`)
are built from real recordings by `tools/audio/import_real_gun_sounds.py`. The script holds every
choice it makes and can rebuild these files from the source.

## Source

| Key | Source | Authors | Licence |
|---|---|---|---|
| FFSL | [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library), "Prepared SFX Library" (96 kHz / 24-bit stereo) | Students of Michigan Technological University (Visual and Performing Arts, audio production) | CC0 1.0 |
| FS-508747 | [Bolt Action Rifle Reload](https://freesound.org/people/AugustSandberg/sounds/508747/) (Mauser K98), already in the repo as `rifle/reload_bolt_close.wav` | AugustSandberg (Freesound) | CC0 1.0 |

Both are CC0 (public domain), so no attribution is required. The authors are credited here anyway.
The derived files are released under CC0 as well.

Each file in the library is one gun from one perspective. "Near" files are recorded beside the
shooter (stereo, left/right). "Mid" files are recorded further out in front of the shooter
(forward/back).

- `close_*` is your own shot. It is built from a near-mic shot (the crack and blast) with a
  mid-mic take of the same gun under it (the weight), a synthesized sub thump (a short sine falling to
  40-80 Hz depending on the gun) and, for self-loaders, the bolt slam from FS-508747. The `OWN` table in
  the script holds these settings.
- `body_*` is the mid mic.
- `tail_*` is the mid mic with the direct blast removed: the range's real reflections and decay. A darker
  2.8 s rolling decay is convolved on, from 80 ms.
- `distant_*` and `far_*` are mid takes filtered and diffused, as if heard 200 m and 500 m+ away.
- `body_suppressed_*` is low-passed and shortened, with the near mic's first milliseconds high-passed
  on top as the action's click. The library has no suppressed recording.

| Game gun | Recording used | Why |
|---|---|---|
| `ak` (AK-47) | FFSL AK-47 (7.62x39): C_28P, C_29P, C_27P near; C_31P, C_34P, C_36P mid | the gun itself, single shots and the last shot of bursts |
| `mosin` (Mosin-Nagant) | FFSL Mosin Nagant (7.62x54R): M_21P near, M_26P mid | the gun itself |
| `sks` (SKS) | FFSL Norinco SKS (7.62x39): U_14P near, U_19P mid; Savage 10 (.300 Blackout): T_27P near, T_17P mid | the gun itself; the .300 Blackout (7.62x35) is the 7.62x39's twin, for more takes |
| `ppsh` (PPSh-41) | FFSL PPSh (7.62x25 Tokarev): P_30P, P_32P, P_34P near; P_16P, P_18P, P_22P mid | the gun itself |
| `makarov` (Makarov, 9x18) | FFSL Bersa (.380 ACP / 9x17): F_47P near, F_41P mid; Smith & Wesson 642 (.38 Special): V_27P near, V_22P mid | no Makarov in the library; the Bersa is the nearest: a blowback pistol like the Makarov, with nearly the same cartridge energy. It has only two shots per mic, so the S&W's short-barrel .38 (about the Makarov's energy) adds two more, and one take is re-pitched 2.5 % |
| `tabanca9` (9 mm pistol) | FFSL Walther PPQ (9 mm): X_39P near, X_31P mid; Colt 1911 (.45 ACP): A_42P near, A_34P mid | a modern 9 mm service pistol; the 1911 for more takes and a heavier report among them |
| `hafif` (light SMG, 9 mm) | FFSL Carl Gustav M45 / Swedish K (9 mm): G_31P, G_33P, G_35P near; G_20P, G_22P, G_24P mid | a 9 mm submachine gun |
| `piyade` (battle rifle) | FFSL Tikka T3, Springfield 1917, Arisaka (.30-06 per the library): W_29P, B_24P, E_25P near; W_24P, B_16P, E_18P mid | no 7.62x51 battle rifle in the library; these full-power rifle cartridges are the nearest report |
| `toz` (TOZ double 12 ga) | FFSL Winchester Model 12, Benelli Nova, Charles Daly, Mossberg 190 (12 ga): K_22P, O_21P, H_21P near; K_17P, O_17P, H_16P, N_26P mid | no break-action gun in the library; a 12-bore's report comes from the load, not the action |

**Matched to the AK** (makarov, tabanca9, sks, mosin, hafif, piyade, toz; the `MATCH` settings in the
script). Built like the AK and PPSh at first, these sounded like a pop beside them: equally loud on a
meter (levelled by their loudest 50 ms), but most of that was sub-bass, the crack's first 80 ms were
2-5 dB weaker A-weighted, and the 300 Hz-1.2 kHz ring after it (the report's weight) was 7-10 dB under
the AK's. Now each take's spectrum is drawn 85 % of the way to the AK's own files', window by window
(the crack 0-10 ms, the blast 10-60 ms, the ring 60-200 ms, the decay 200-800 ms; the tail 40-400 ms and
on), by minimum-phase filters (nothing rings before the crack), with a tilt per kind on top (a pistol's
lighter low end; a full-power rifle's and a 12-bore's heavier 80-300 Hz). The match is done again after
limiting. Then `close`, `body` and `tail` are levelled by A-weighted loudness (the first 80 ms for the
shot) against the AK's, offsets as heard in the game (GunAudio's per-gun level made up for): pistols
0.5-0.7 dB under the AK, the SMG level with it, the SKS 0.5 dB over, the Mosin, battle rifle and TOZ
1.5 dB over. The declipper's re-drawn peaks are held to 1.6x full scale on these, and your own shot may
be limited by up to 10 dB.

Not taken from the library: the mechanism sounds (bolt, magazine, slide, dry fire, handling, break
and shells, casings). The library has none of them, so those files are unchanged. See
`rifle/CREDITS.md` and `tools/audio/build_weapon_sounds.py`.

Not used: "Gunshot Sounds" by Tabasco (opengameart.org/content/gunshot-sounds). It was downloaded
as a possible layer, but the library above covers every gun with cleaner recordings. Note that its
own `creativecommons.txt` says CC-BY 3.0 (Vincent Sevedge), not CC0 as its listing does.

## Files

The table lists which shot of which recording each take is (onset in seconds in the library file).
Re-pitched takes show their rate. A `close_*` row names the near-mic shot of each take; a mid-mic
shot of the same gun (from the mid files listed above) is layered under it.

### ak

| Files | Takes (source file, shot onset, pitch if re-pitched) |
|---|---|
| `close_01..05` | 1: AK-47/C_28P.wav 0.611 s; 2: AK-47/C_29P.wav 1.344 s; 3: AK-47/C_29P.wav 5.792 s; 4: AK-47/C_28P.wav 6.021 s; 5: AK-47/C_28P.wav 9.156 s |
| `body_01..05` | 1: AK-47/C_31P.wav 0.338 s; 2: AK-47/C_36P.wav 1.171 s; 3: AK-47/C_36P.wav 5.019 s; 4: AK-47/C_34P.wav 9.371 s; 5: AK-47/C_36P.wav 8.990 s |
| `tail_01..04` | 1: AK-47/C_31P.wav 0.338 s; 2: AK-47/C_36P.wav 1.171 s; 3: AK-47/C_36P.wav 5.019 s; 4: AK-47/C_34P.wav 9.371 s |
| `distant_01..04` | 1: AK-47/C_36P.wav 5.019 s; 2: AK-47/C_34P.wav 9.371 s; 3: AK-47/C_36P.wav 8.990 s; 4: AK-47/C_34P.wav 0.914 s |
| `far_01..03` | 1: AK-47/C_36P.wav 8.990 s; 2: AK-47/C_34P.wav 0.914 s; 3: AK-47/C_34P.wav 13.731 s |
| `body_suppressed_01..03` | 1: AK-47/C_31P.wav 0.338 s; 2: AK-47/C_36P.wav 1.171 s; 3: AK-47/C_36P.wav 5.019 s |

### mosin

| Files | Takes (source file, shot onset, pitch if re-pitched) |
|---|---|
| `close_01..05` | 1: Mosin Nagant/M_21P.wav 1.034 s; 2: Mosin Nagant/M_21P.wav 5.020 s; 3: Mosin Nagant/M_21P.wav 9.156 s; 4: Mosin Nagant/M_21P.wav 14.137 s; 5: Mosin Nagant/M_21P.wav 1.034 s (x1.020) |
| `body_01..05` | 1: Mosin Nagant/M_26P.wav 1.138 s; 2: Mosin Nagant/M_26P.wav 6.105 s; 3: Mosin Nagant/M_26P.wav 10.743 s; 4: Mosin Nagant/M_26P.wav 1.138 s (x0.980); 5: Mosin Nagant/M_26P.wav 10.743 s (x0.980) |
| `tail_01..04` | 1: Mosin Nagant/M_26P.wav 1.138 s; 2: Mosin Nagant/M_26P.wav 6.105 s; 3: Mosin Nagant/M_26P.wav 10.743 s; 4: Mosin Nagant/M_26P.wav 1.138 s (x0.980) |
| `distant_01..04` | 1: Mosin Nagant/M_26P.wav 1.138 s; 2: Mosin Nagant/M_26P.wav 6.105 s; 3: Mosin Nagant/M_26P.wav 10.743 s; 4: Mosin Nagant/M_26P.wav 10.743 s (x0.980) |
| `far_01..03` | 1: Mosin Nagant/M_26P.wav 10.743 s (x0.980); 2: Mosin Nagant/M_26P.wav 6.105 s (x0.980); 3: Mosin Nagant/M_26P.wav 10.743 s (x1.020) |
| `body_suppressed_01..03` | 1: Mosin Nagant/M_26P.wav 1.138 s; 2: Mosin Nagant/M_26P.wav 6.105 s; 3: Mosin Nagant/M_26P.wav 10.743 s |

### sks

| Files | Takes (source file, shot onset, pitch if re-pitched) |
|---|---|
| `close_01..05` | 1: SKS/U_14P.wav 3.577 s; 2: Savage 10 .300 Blackout/T_27P.wav 0.951 s; 3: SKS/U_14P.wav 6.755 s; 4: SKS/U_14P.wav 10.211 s; 5: SKS/U_14P.wav 13.291 s |
| `body_01..05` | 1: SKS/U_19P.wav 2.614 s; 2: Savage 10 .300 Blackout/T_17P.wav 0.862 s; 3: SKS/U_19P.wav 8.016 s; 4: Savage 10 .300 Blackout/T_17P.wav 4.255 s; 5: SKS/U_19P.wav 12.786 s |
| `tail_01..04` | 1: SKS/U_19P.wav 2.614 s; 2: Savage 10 .300 Blackout/T_17P.wav 0.862 s; 3: SKS/U_19P.wav 8.016 s; 4: Savage 10 .300 Blackout/T_17P.wav 4.255 s |
| `distant_01..04` | 1: SKS/U_19P.wav 2.614 s; 2: SKS/U_19P.wav 8.016 s; 3: SKS/U_19P.wav 12.786 s; 4: SKS/U_19P.wav 2.614 s (x0.980) |
| `far_01..03` | 1: SKS/U_19P.wav 12.786 s; 2: SKS/U_19P.wav 2.614 s (x0.980); 3: SKS/U_19P.wav 8.016 s (x0.980) |
| `body_suppressed_01..03` | 1: SKS/U_19P.wav 2.614 s; 2: Savage 10 .300 Blackout/T_17P.wav 0.862 s; 3: SKS/U_19P.wav 8.016 s |

### ppsh

| Files | Takes (source file, shot onset, pitch if re-pitched) |
|---|---|
| `close_01..05` | 1: PPSh/P_30P.wav 0.969 s; 2: PPSh/P_32P.wav 4.600 s; 3: PPSh/P_30P.wav 8.243 s; 4: PPSh/P_30P.wav 11.421 s; 5: PPSh/P_30P.wav 15.090 s |
| `body_01..05` | 1: PPSh/P_18P.wav 1.370 s; 2: PPSh/P_22P.wav 1.544 s; 3: PPSh/P_18P.wav 3.783 s; 4: PPSh/P_18P.wav 7.743 s; 5: PPSh/P_18P.wav 11.889 s |
| `tail_01..04` | 1: PPSh/P_18P.wav 1.370 s; 2: PPSh/P_22P.wav 1.544 s; 3: PPSh/P_18P.wav 3.783 s; 4: PPSh/P_18P.wav 7.743 s |
| `distant_01..04` | 1: PPSh/P_18P.wav 1.370 s; 2: PPSh/P_22P.wav 1.544 s; 3: PPSh/P_18P.wav 11.889 s; 4: PPSh/P_16P.wav 0.292 s |
| `far_01..03` | 1: PPSh/P_18P.wav 11.889 s; 2: PPSh/P_16P.wav 0.292 s; 3: PPSh/P_16P.wav 9.047 s |

### makarov

| Files | Takes (source file, shot onset, pitch if re-pitched) |
|---|---|
| `close_01..05` | 1: Bersa/F_47P.wav 0.334 s; 2: Smith & Wesson 642/V_27P.wav 0.805 s; 3: Bersa/F_47P.wav 4.410 s; 4: Smith & Wesson 642/V_27P.wav 6.219 s; 5: Bersa/F_47P.wav 4.410 s (x0.975) |
| `body_01..05` | 1: Bersa/F_41P.wav 0.438 s; 2: Smith & Wesson 642/V_22P.wav 0.673 s; 3: Bersa/F_41P.wav 4.808 s; 4: Smith & Wesson 642/V_22P.wav 5.506 s; 5: Smith & Wesson 642/V_22P.wav 5.506 s (x0.975) |
| `tail_01..04` | 1: Bersa/F_41P.wav 0.438 s; 2: Smith & Wesson 642/V_22P.wav 0.673 s; 3: Bersa/F_41P.wav 4.808 s; 4: Smith & Wesson 642/V_22P.wav 5.506 s |
| `distant_01..04` | 1: Smith & Wesson 642/V_22P.wav 0.673 s; 2: Bersa/F_41P.wav 4.808 s; 3: Smith & Wesson 642/V_22P.wav 5.506 s; 4: Smith & Wesson 642/V_22P.wav 5.506 s (x0.975) |
| `far_01..03` | 1: Smith & Wesson 642/V_22P.wav 5.506 s (x0.975); 2: Bersa/F_41P.wav 0.438 s (x0.975); 3: Bersa/F_41P.wav 4.808 s (x0.975) |
| `body_suppressed_01..03` | 1: Bersa/F_41P.wav 0.438 s; 2: Smith & Wesson 642/V_22P.wav 0.673 s; 3: Bersa/F_41P.wav 4.808 s |

### tabanca9

| Files | Takes (source file, shot onset, pitch if re-pitched) |
|---|---|
| `close_01..05` | 1: 1911/A_42P.wav 0.941 s; 2: Walther PPQ/X_39P.wav 6.444 s; 3: 1911/A_42P.wav 5.002 s; 4: Walther PPQ/X_39P.wav 10.660 s; 5: Walther PPQ/X_39P.wav 1.407 s (x0.980) |
| `body_01..05` | 1: Walther PPQ/X_31P.wav 1.085 s; 2: 1911/A_34P.wav 2.527 s; 3: Walther PPQ/X_31P.wav 5.243 s; 4: 1911/A_34P.wav 7.640 s; 5: 1911/A_34P.wav 2.527 s (x0.980) |
| `tail_01..04` | 1: Walther PPQ/X_31P.wav 1.085 s; 2: 1911/A_34P.wav 2.527 s; 3: Walther PPQ/X_31P.wav 5.243 s; 4: 1911/A_34P.wav 7.640 s |
| `distant_01..04` | 1: Walther PPQ/X_31P.wav 1.085 s; 2: 1911/A_34P.wav 2.527 s; 3: Walther PPQ/X_31P.wav 5.243 s; 4: 1911/A_34P.wav 7.640 s |
| `far_01..03` | 1: Walther PPQ/X_31P.wav 1.085 s (x0.980); 2: Walther PPQ/X_31P.wav 5.243 s (x0.980); 3: Walther PPQ/X_31P.wav 1.085 s (x1.020) |
| `body_suppressed_01..03` | 1: Walther PPQ/X_31P.wav 1.085 s; 2: 1911/A_34P.wav 2.527 s; 3: Walther PPQ/X_31P.wav 5.243 s |

### hafif

| Files | Takes (source file, shot onset, pitch if re-pitched) |
|---|---|
| `close_01..05` | 1: Carl Gustav M45/G_35P.wav 1.064 s; 2: Carl Gustav M45/G_31P.wav 3.501 s; 3: Carl Gustav M45/G_33P.wav 4.459 s; 4: Carl Gustav M45/G_35P.wav 6.249 s; 5: Carl Gustav M45/G_31P.wav 6.728 s |
| `body_01..05` | 1: Carl Gustav M45/G_20P.wav 0.348 s; 2: Carl Gustav M45/G_24P.wav 1.270 s; 3: Carl Gustav M45/G_20P.wav 2.259 s; 4: Carl Gustav M45/G_22P.wav 4.281 s; 5: Carl Gustav M45/G_20P.wav 5.267 s |
| `tail_01..04` | 1: Carl Gustav M45/G_20P.wav 0.348 s; 2: Carl Gustav M45/G_24P.wav 1.270 s; 3: Carl Gustav M45/G_20P.wav 2.259 s; 4: Carl Gustav M45/G_22P.wav 4.281 s |
| `distant_01..04` | 1: Carl Gustav M45/G_24P.wav 1.270 s; 2: Carl Gustav M45/G_22P.wav 4.281 s; 3: Carl Gustav M45/G_20P.wav 5.267 s; 4: Carl Gustav M45/G_22P.wav 0.446 s |
| `far_01..03` | 1: Carl Gustav M45/G_20P.wav 5.267 s; 2: Carl Gustav M45/G_22P.wav 0.446 s; 3: Carl Gustav M45/G_24P.wav 1.270 s (x0.980) |
| `body_suppressed_01..03` | 1: Carl Gustav M45/G_20P.wav 0.348 s; 2: Carl Gustav M45/G_24P.wav 1.270 s; 3: Carl Gustav M45/G_20P.wav 2.259 s |

### piyade

| Files | Takes (source file, shot onset, pitch if re-pitched) |
|---|---|
| `close_01..05` | 1: Tikka/W_29P.wav 0.577 s; 2: 1917/B_24P.wav 1.308 s; 3: Arisaka/E_25P.wav 0.524 s; 4: Tikka/W_29P.wav 5.665 s; 5: Arisaka/E_25P.wav 4.030 s |
| `body_01..05` | 1: Tikka/W_24P.wav 0.755 s; 2: 1917/B_16P.wav 0.607 s; 3: Arisaka/E_18P.wav 0.360 s; 4: Tikka/W_24P.wav 5.377 s; 5: 1917/B_16P.wav 5.972 s |
| `tail_01..04` | 1: Tikka/W_24P.wav 0.755 s; 2: 1917/B_16P.wav 0.607 s; 3: Arisaka/E_18P.wav 0.360 s; 4: Tikka/W_24P.wav 5.377 s |
| `distant_01..04` | 1: Tikka/W_24P.wav 0.755 s; 2: Arisaka/E_18P.wav 0.360 s; 3: Tikka/W_24P.wav 5.377 s; 4: 1917/B_16P.wav 5.972 s |
| `far_01..03` | 1: 1917/B_16P.wav 5.972 s; 2: Arisaka/E_18P.wav 4.487 s; 3: Tikka/W_24P.wav 0.755 s (x0.980) |
| `body_suppressed_01..03` | 1: Tikka/W_24P.wav 0.755 s; 2: 1917/B_16P.wav 0.607 s; 3: Arisaka/E_18P.wav 0.360 s |

### toz

| Files | Takes (source file, shot onset, pitch if re-pitched) |
|---|---|
| `close_01..05` | 1: Model 12/K_22P.wav 0.842 s; 2: CD/H_21P.wav 0.464 s; 3: Model 12/K_22P.wav 7.445 s; 4: Nova/O_21P.wav 3.465 s; 5: CD/H_21P.wav 3.075 s |
| `body_01..05` | 1: Nova/O_17P.wav 0.694 s; 2: CD/H_16P.wav 0.607 s; 3: Mossberg/N_26P.wav 0.786 s; 4: Nova/O_17P.wav 3.708 s; 5: Mossberg/N_26P.wav 7.948 s |
| `tail_01..04` | 1: Nova/O_17P.wav 0.694 s; 2: CD/H_16P.wav 0.607 s; 3: Mossberg/N_26P.wav 0.786 s; 4: Nova/O_17P.wav 3.708 s |
| `distant_01..04` | 1: Nova/O_17P.wav 0.694 s; 2: Mossberg/N_26P.wav 0.786 s; 3: Nova/O_17P.wav 3.708 s; 4: Mossberg/N_26P.wav 7.948 s |
| `far_01..03` | 1: Mossberg/N_26P.wav 7.948 s; 2: CD/H_16P.wav 4.117 s; 3: Mossberg/N_26P.wav 4.574 s |

## Mechanism and handling made by tools/audio/build_foley_sounds.py

The guns that had no mechanism of their own now have one, made from the mechanism takes already
here (the AK's and the Makarov's, which come from the CC0 rifle recordings in `rifle/` and
`war/shotgun_pump`, `war/mine_click`), re-pitched, filtered and layered with small synthesized
parts: `ppsh/` (stick and drum magazine, bolt, selector), `hafif/`, `piyade/` (magazine, charging
handle, bolt release, selector), `tabanca9/` (magazine, slide), `sks/` (its own charging handle,
stripper clip with ten rounds thumbed down, bolt release: these override `rifle/`'s Mauser takes),
dry fire and handling for each, and a safety for the Mosin, Makarov, TOZ and SKS.
`common/<event>_<long|pistol>_*` (raise, lower, ads_in, ads_out, sling, unsling, holster, draw,
safety) are made from `foley/foley_rustle_*`, `foley/foley_gear_rattle_*` and synthesized knocks.
`casings/<brass|shell>_<surface>_*` (hard, gravel, dirt, grass, mud, snow, wood, metal, water) are
modal synthesis (as the first casings) with each surface's damping and knock, plus a mud squelch,
a water plip and splash, gravel grains. GunFoley plays them all by name.

**Real takes over the made ones:** many files here are now cut from real recordings (Sonniss GDC bundles, royalty-free, private repo; one OpenGameArt CC0 reload) by `tools/audio/import_foley_takes.py`; `../CREDITS_FOLEY_REAL.md` (or `../../CREDITS_FOLEY_REAL.md` from weapons subfolders) lists which file came from which recording, and `tools/audio/real_foley_takes.txt` lists them all.

## İnşa's own additions

- `minigun_motor_loop.wav`: synthesized (a Python one-off): the electric drive's whine (220 Hz and its
  harmonics, a gear whine at 1.3 kHz), a periodic noise bed, amplitude-modulated at 40 Hz for the six
  barrels passing; one second, every partial a whole number of cycles so it loops without a seam. CC0.
- `casings/brass_metal_0*.wav`, `casings/brass_dirt_0*.wav`: from the Mud Run project (`../car`), its
  modal-synthesis casings (CC0).
- `flame_loop.wav`: synthesized (a Python one-off): low-passed noise for the roar of burning fuel, a
  little unfiltered hiss and sparse crackles; its ends crossfaded over 0.3 s so it loops. CC0.
