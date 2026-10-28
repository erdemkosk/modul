# İnşa

Build a machine from parts on a 0.5 m grid and drive and fight with it (Godot 4.7, Jolt). The valley, its
terrain, mud, snow, ruts, trees and sky come from the Mud Run project (`../car`); the machine and fighting
are this project's own.

## Play

- **Kafes**: a six-round tournament in a small walled cage before a crowd. Each round lays its own
  floor (a mud pit, an ice rink, fire vents, spikes, a bog, fenced islands) and sends its own rivals,
  built fresh for each run (`forge.gd`) and stronger each round; win by tearing them apart or leaving them unable to move for 8 s, or on the
  judges' decision at the bell. The damage stays between rounds: each win pays credits, and the
  workshop buys back what you lost, the cab first, and sells you new parts (B; half back for one
  taken off). From the third round house robots keep two hatched corners and drive into whatever comes
  in; some rounds have a pit that opens at 0:45 (what goes over it falls and is out); spinners and
  floor saws tear at what touches them. Your cab gone, you're out.
- **Test Alanı**: the proving ground, built as an arena: a ring of jersey barriers under a catch fence,
  grandstands, floodlight masts (lit at night), a gate the other side drives in through, the surface
  zones and ramps, and cover that breaks (concrete blocks, containers, sandbags, crates, drums).
- **Vadi**: the 2 km valley, to explore.

| Key | |
|---|---|
| B · Tab | build / drive |
| W S · A D · Space | throttle and back · steer · brake |
| Mouse · left button · right button held | look and aim · fire · aim at range (the view narrows) |
| 1-9 · 0 | turn that gun on or off (the others stay as they are: any of them fire together) · all on |
| C | the camera: chase (behind, up, looking where you aim) · high (over the fight) · from the turret |
| Esc · K held | pause (go on, settings, the start menu) · rebuild a machine that can't move |
| L · T | lights · back on its wheels |
| F1 F2 F3 F5 F4 | raider (minigun) · tank (cannon) · target · tracked rocket carrier · a wave (proving ground) |
| F7 | a new rival from Forge, any style and strength (proving ground) |
| F6 | clear the other side's machines and the wreckage away (proving ground) |
| G | your machine takes no damage / does again (proving ground) |
| Building: left / right click | bolt on / take off (right drag turns the view) |
| Building: 1-9, 0, Q, E, Z, X, C, F, H · R | pick a part · turn it |
| Building: V · M · Ctrl Z / Ctrl Y | isometric view · mirror · undo / redo |

## How it works

- `scripts/ui.gd`: the one look every screen shares: Barlow and Barlow Condensed (`assets/fonts`,
  SIL OFL 1.1), smoked glass plates leaning like armour, one orange accent; Turkish upper case.

- `scripts/parts.gd`: every part's footprint, mass, hit points and job. Models: `tools/blender/build_parts.py`
  (`blender --background --factory-startup --python tools/blender/build_parts.py [-- --render] [-- --icons]`).
- `scripts/machine.gd`: one rigid body from the parts (mass, centre of mass, boxes), building rules, damage
  and parts breaking off. `machine_wheel.gd`: ray suspension, tyre grip from the ground, sinking and ruts in
  soft ground. `machine_track.gd`: a track (five road wheels through one belt, turned by its sides; its
  sprocket, idler and belt, the links scrolled by `shaders/track_belt.gdshader`, caked with mud).
  `wheel_spray.gd`: clods and dust. `machine_gun.gd`: turrets, minigun, cannon, rocket pod, and what each
  draws from the battery.
- Electricity (`machine.gd`, `_power`): the cab's 0.3 kWh and any battery parts; each engine's alternator
  charges 2.8 kW (more as it revs); the minigun's motor, turrets turning, loaders and lights draw. Flat,
  nothing turns, spins up or loads until it's charged a little.
- `scripts/combat.gd`: rounds, shells, rockets (thrust, wobble, smoke trail), bursts, craters, debris,
  effects and sound, pooled.
- `scripts/ai_driver.gd`: the other side's crews. `scripts/designs.gd`: ready machines, and the build
  screen's ready designs (HAZIR TASARIMLAR: Gezgin, Akıncı, Topçu, Roketatar, Koçbaşı, Ateşbaz, Gürz).
- `scripts/forge.gd`: builds the other side's machines from sensible parts, a different one from each
  seed: a style (skirmisher, gunner, artillery, rocketeer, flamethrower brawler, rammer) picks the guns
  and the nose; then the cab at the front, a battery if the guns draw more than an engine charges,
  engines until its kW per tonne reaches the round's mark, and wheels or tracks rated for its weight;
  everything checked to bolt to the cab.
- Parts added: the V8 (200 kW) and the small petrol engine (40 kW), steel plate (light armour), the ram
  head (spikes: knocks it deals bite 1.7× harder) and the flamethrower (a 14 m cone that burns parts).
- `scripts/builder.gd`: the build screen (its layout after Besiege's builder: part groups as tabs over
  tiles, tools down the left, slots, a drive button; a grid of the machine's cells, its centre of mass,
  ghosts with outlines, parts dropping in and lifting away to impact-gun and ratchet sounds from
  `assets/audio/build/`). `scripts/drive_hud.gd`: the panel along the bottom while driving (speed and
  hull, the battery and every consumer, shed or not, the guns).
- `scripts/arena.gd`: the arena (models: `tools/blender/build_arena.py`); `scripts/breakable.gd`: its
  cover, chipped by rounds, broken into chunks by bursts; `scripts/test_terrain.gd` digs craters.
- What a hurt part does (`machine.gd` `_systems`): an engine gives less power (sputtering when badly
  hurt), a tyre under 55% bursts (lower, half the grip, drag, a thump each turn), a track under 40% is
  thrown, a battery hit loses charge and holds less, a hurt gun turns slower and jams. Your own say so
  at once; on what you hit, the HUD shows the damage and the part's name where it struck and the
  target's parts from above (`combat_overlay.gd`).
- Hurt and death (`machine.gd`): rounds, bursts and knocks (ramming, walls, hard landings: the change
  in speed past 3 m/s) take hit points off the parts where they land; a part at none comes off and
  the machine is worked out anew (mass, centre of mass, wheels, power); the cab gone, it's dead; no
  engine or nothing to run on, it can't move. Hurt parts soot over and smoke (`shaders/part_wear`).
  `combat_overlay.gd` shows being hurt and where from, and marks the enemy; `death_card.gd` says what
  did it. `pause_menu.gd`, `settings.gd` (user://settings.cfg), `settings_panel.gd`.
- KAFES: `cage.gd` (the rounds, the judges, the credits, the workshop), `cage_arena.gd` (the cage, its
  stands and crowd (`shaders/crowd.gdshader`), its hazards), `cage_ui.gd`; crowd sounds in
  `assets/audio/crowd` (CC0, see its CREDITS).
- Fire control (`machine_gun.gd`): the cannon and the pod lay themselves over for their round's drop at
  the aim's range; the crosshair's rings show where each would land.
- `scripts/game.gd`: both modes. `scripts/menu.gd`: the start.

## Tests

```
godot --headless --path . -s res://tests/drive_test.gd
godot --headless --path . -s res://tests/combat_test.gd
godot --headless --path . -s res://tests/tracks_test.gd
godot --headless --path . -s res://tests/build_test.gd
godot --headless --path . -s res://tests/arena_test.gd
godot --headless --path . -s res://tests/cage_test.gd
godot --headless --path . -s res://tests/hazard_test.gd
godot --headless --path . -s res://tests/ai_test.gd
godot --headless --path . -s res://tests/designs_test.gd
godot --path . --resolution 1600x900 -s res://tests/shots.gd -- --out=<folder> [--valley | --tracks | --arena | --polish | --cage | --forge]
```
