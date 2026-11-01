# Realistic heads: sources and licences

The heads of the survivor, the raiders and the dead are made with **MakeHuman** through the
**MPFB 2** add-on for Blender (2.0.18, GPL-3.0; the add-on is a tool only, nothing of its code
ships with the game). Everything used from MakeHuman is **CC0** (public domain):

| What | Pack | Author | Licence |
|---|---|---|---|
| Base mesh and face targets (shape of every head, the 18 face blend shapes) | bundled with MPFB 2.0.18 | MakeHuman team | CC0 |
| Skins: young/middle-aged/old caucasian male, middle-aged asian male, middle-aged african male, young caucasian female (dead woman) | `makehuman_system_assets_cc0.zip` | makehuman_system | CC0 |
| Eyes (`high-poly`, brown iris texture), eyebrows `eyebrow001` (full) and `eyebrow009` (heavy, `brows_heavy.png`), eyelashes `eyelashes01`, teeth `teeth_base`, hair `long01` and `short02` (the dead) | `makehuman_system_assets_cc0.zip` | makehuman_system | CC0 |
| Skins: middle-aged and old Slavic male with beard | `skins02_cc0.zip` | Jartur69 | CC0 |
| Skin: middle-aged African male | `skins02_cc0.zip` | Mindfront | CC0 |
| Skin relief and sheen for every head: the normal and specular maps of "Aksel" (`skin_normal.png`, `skin_rough.png`) | `skins02_cc0.zip` | Mindfront | CC0 |
| Skin: old Eurasian male | `skins02_cc0.zip` | onlytheghosts | CC0 |
| Skin: light-skinned male, bronze | `skins02_cc0.zip` | Toigo | CC0 |
| Beard (`BeardViking`, trimmed short) and moustache (`MoustacheViking`) | `bodyparts05_cc0.zip` | Rehman Polanski | CC0 |
| (`eyebrows01_cc0.zip` was loaded into MPFB; its brows are strand geometry, ~26k vertices each, so none is used) | `eyebrows01_cc0.zip` | Mindfront | CC0 |

Downloaded from `files.makehumancommunity.org` / `files2.makehumancommunity.org`
(`asset_packs/<pack>/<pack>_cc0.zip`) on 2026-10-24. The `bodyparts05` pack also holds two
beards whose own `.mhclo` files say AGPL3 (`wdg_scruffy_beard`, `grinsegold_beard_sigmund_wip`);
they are not used.

Everything here was reworked by `tools/blender/build_heads.py`: the head's islands cut out of
MakeHuman's body atlas and packed into 1024 x 2048, the hair textures made grey (tinted in the
game), the brown iris made browner, and the dead's skins, eyes and teeth painted from the living
ones (`skin_dead_*.png`, `eyes_dead.png`, `teeth_dead.png`), Aksel's normal map cut to the same
packing (`skin_normal.png`) and its specular map turned into roughness (`skin_rough.png`). The mask
(`head_mask.png`) is drawn by that script. (`build_heads.py -- --maps-only` redoes only the two
detail maps.)

Rebuild: see `tools/blender/build_heads.py` (needs MPFB and the packs), then
`build_character.py` and `build_zombie.py` (need only `tools/blender/heads/heads.npz` and these
textures).
