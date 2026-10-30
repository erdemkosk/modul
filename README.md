# İnşa

Build a machine from parts on a 0.5 m grid and drive and fight with it (Godot 4.7, Jolt). The valley, its
terrain, mud, snow, ruts, trees and sky come from the Mud Run project (`../car`); the machine and fighting
are this project's own.

## Play

- **Test Alanı**: the proving ground, built as an arena: a ring of jersey barriers under a catch fence,
  grandstands, floodlight masts (lit at night), a gate the other side drives in through, the surface
  zones and ramps, and cover that breaks (concrete blocks, containers, sandbags, crates, drums).
- **Vadi**: the 2 km valley, the Terra Tech way: machines roam it to be hunted (Forge's, sized to
  yours), and what comes off them whole lies lit where it falls; drive up to it and it's yours. You
  build only with what you hold (a ready design or a slot loads if your parts cover it), and the
  valley's machine and parts are kept apart from the other modes'. Its work is carrying: jobs on the
  radio (J) to haul a load (medicine, the wounded, a generator, fuel, a pump, steel beams) between the
  map's places: a real crate of its weight, lifted onto your bed with a crane (Y: it slews to your
  aim, its trolley runs out to where you look, a load moment limiter keeps it from tipping you over)
  or dragged with a winch (N: it also pulls a stuck machine out of the mud), set down on the pad it's
  for, paid in good parts and scrap. There's no
  base: you build and mend only beside the workshop truck (V to drive it: slow, heavy, it hauls the
  big loads). Parts have a past (salvage is worn, a worn part may give on the road). The valley soaks
  and dries (the mud's depth), its fords flood, its roads are shut some mornings (a slide, trees down),
  and two giants roam it, taken apart rather than shot down.
  You start with little, on easy ground (the start's slopes eased, little mud): a small wooden cart
  (KÜTÜKÇÜ: a driver's seat of planks, a 40 kW engine, the saw out in front, a short wooden crane on
  the seat's roof, a load bed fenced with rails, four wooden wheels), two spare rails and a little
  wood. Wood is the first stuff: R starts the saw, drive it into a tree and it cuts through the trunk
  (chips thrown out of the cut, the cart shuddering, needles shaken down, a crack before it goes); the
  tree goes over away from you (whatever it lands on is hit) and lies as billets, solid on the ground,
  a log on the forest floor is cut up too. The crane lifts them: Y with the hook over a billet takes
  hold and winds it up, look over your bed, Y sets it down there and lets go; the rails keep the load
  on. Stopped beside the workshop truck (or set down within 12 m of it), what's on the bed goes into
  the store, and parts off wrecks are brought home the same way. Wooden parts (AHŞAP: a timber frame,
  planking, rails, a wedge, a wooden wheel, the wooden crane) are made out of the store as you place
  them: heavy, quick to break, and a flame takes them three times as hard and sets them burning on,
  spreading to the wood beside them; they're mended with wood. The builder shows only what can be had
  now: more parts open as wood comes home (Parts.OPENS), metal ones once their plan's found; its ready
  designs are haulers (KÜTÜKÇÜ, YÜK ARABASI, ÇİFT VİNÇLİ) and the rest once their parts can be had.
  A steering joint turns what's bolted on it with A/D (a wheel on a block on it steers), or with a key
  of its own while it's held. The screen keeps quiet: the wood in the store, the saw's cut, the way
  to the workshop when it's far; the machine's plate only once it's hurt; short cards, one step at a
  time (drive, fell, load, bring home).
  The valley goes through ages. In the wood age the weapons are the wood age's, made of wood and
  worked by hand: a ballista (its bolt goes through into the part behind and sticks there), a
  catapult (a stone lobbed high to come down where you look, ~230 m), a cask of boiling oil (tipped
  out ahead: the ground burns), and a cask of pitch beside the ballista or the catapult makes fire
  arrows and burning pots; they're stocked again at the workshop for wood. The crews out there are
  wooden carts (WoodForge: archers, catapults, oil casks, rams). Metal parts are made of scrap only
  once their plan's found: five plans (steel work, wheels and tracks, engines, machinery, guns), lit
  tubes in a cleared works site's cache, a giant's heart, now and then a long haul's pay; the first
  opens the metal age (jobs pay parts again, steel crews come out too). A part held can always go on.

| Key | |
|---|---|
| B · Tab | build / drive |
| W S · A D · Space | throttle and back · steer · brake |
| Mouse · left button · right button held | look and aim · fire · aim at range (the view narrows) |
| 1-9 · 0 | turn that gun on or off (the others stay as they are: any of them fire together) · all on |
| C | the camera: chase (behind, up, looking where you aim) · high (over the fight) · from the turret |
| Esc · K held | pause (go on, settings, the start menu) · rebuild a machine that can't move |
| L · T | lights · back on its wheels |
| F | fire the flipper |
| E | the hinges, rotors and pistons with no key of their own (each press: up/down, spin/stop, out/in) |
| F1 F2 F3 F5 F4 | raider (minigun) · tank (cannon) · target · tracked rocket carrier · a wave (proving ground) |
| F7 | a new rival from Forge, any style and strength (proving ground) |
| F6 | clear the other side's machines and the wreckage away (proving ground) |
| G | your machine takes no damage / does again (proving ground) |
| Building: left / right click | bolt on / take off (right drag turns the view) |
| Building: 1-9, 0, Q, E, Z, X, C, F, H · R | pick a part · turn it |
| Building: V · M · Ctrl Z / Ctrl Y | isometric view · mirror · undo / redo |
| Building: T | tip the part over (forward, upside down, back, on either side; wheels, tracks, the cab stay upright) |
| Building: K | over a gun or a flipper, then any key: it answers to that key (Esc: back to the mouse / F) |

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
  screen's ready designs (HAZIR TASARIMLAR: Gezgin, Akıncı, Topçu, Roketatar, Koçbaşı, Ateşbaz, Gürz),
  each with a picture (`assets/ui/presets`, rendered by `godot --path . -s res://tools/preset_icons.gd`).
- The other side is painted its own colours (`machine.gd` TEAM_PAINT): the rivals oxide red; their
  pieces keep it when they come off.
- `scripts/hints.gd`: the first time you drive, build or take up the valley's work, a card with the
  keys that matter there (once each; AYARLAR can show them again).
- `scripts/forge.gd`: builds the other side's machines from sensible parts, a different one from each
  seed: a style (skirmisher, gunner, artillery, rocketeer, flamethrower brawler, rammer) picks the guns
  and the nose; then the cab at the front, a battery if the guns draw more than an engine charges,
  engines until its kW per tonne reaches the tier's mark, and wheels or tracks rated for its weight;
  everything checked to bolt to the cab.
- The flipper (`machine_flipper.gd`): a hinged plate on a pneumatic ram (F). It throws what's
  standing on it up and over onto its back, and rights its own machine on its back; it fills with
  air from the battery in 3 s. Forge has a flipper style (a flipper out in front, a minigun), whose
  crew drives under you and fires it.
- Joints (`machine_joint.gd`, the HAREKET tab): a hinge swings what's bolted on its top up 90°, a
  rotor spins it (16 rad/s), a piston pushes it out half a metre, each on its key (E if none). What
  a joint carries is everything on its top that doesn't reach the cab another way (if it does, the
  joint's locked); joints on joints move together. The carried parts' models and boxes move with
  it, hits find them where they are, and where a moving part strikes something the blow is by that
  point's speed and the weight moving (a ram on it bites harder): a bar of plates on a rotor is a
  spinner. Forge has a spinner style; crews spin their rotors up as they close, work hinges and
  pistons up close.
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
- Fire control (`machine_gun.gd`): the cannon and the pod lay themselves over for their round's drop at
  the aim's range; the crosshair's rings show where each would land.
- Salvage: `inventory.gd` (what you hold, user://valley_inventory.cfg), `salvage.gd` (the lit parts
  and taking them), `wanderers.gd` (the valley's hunters); the builder's guard, removed and
  swap_guard hooks keep the building to what's held; each part held has its wear (`Inventory.cond`).
- Cranes and winches: `machine_hoist.gd` (the rope as a spring that only pulls, the crane's slew and
  trolley, its load moment limiter, drawing the rope); models in tools/blender/build_parts.py.
- Wood: `machine_tool.gd` (the saw on a machine, what biting feels like), `timber.gd` (felling, the
  stump, billets, taking them in), `workshop.gd` (`_take_in`: what's brought home), `world_props.gd`
  (prop_near, prop_info, felled_mesh; felled trees kept in RutStore.cut), `Inventory.wood`/`delivered`/
  `shown()`; wooden parts burn in `machine.gd` (`_burn`); the start's ground in
  `world_terrain.gd` (`_flatten_start`, `start_ease`).
- Sound: `engine_sound.gd` (each engine's four loops crossfaded by revs), the saw's idle and cutting
  loops in `machine_tool.gd`, wood knocks and the tree's crack and fall in `timber.gd`; sources and
  how they're built in assets/audio/CREDITS.md and tools/audio/build_insa_sounds.py.
- Ages: `Parts.PLANS` (what each plan makes), `Inventory.plans`/`age()`/`make_metal()`, plans dropped
  by `Salvage.drop_plan` (works sites, giants) and paid by expeditions; the wood age's weapons in
  `machine_gun.gd` (ballista, catapult, oil) and `combat.gd` (bolts, stones, burning oil);
  `wood_forge.gd` (the wood age's crews); the steering joint in `machine_joint.gd` ("steer").
- The valley's work: `expeditions.gd` (places, jobs, the load and its knocks, delivery),
  `workshop.gd` (the truck, building and mending beside it), `valley_life.gd` (soaking mud, fords in
  flood, shut roads, worn parts giving), `colossus.gd` (the giants), `valley_hud.gd` (the lines and
  the radio); saved in user://valley_jobs.cfg, valley_workshop.cfg, valley_life.cfg, valley_giants.cfg.
- Structures (the valley's works sites): `structure.gd` and `structure_piece.gd` (what stands on
  what, falling, hit points by stuff, fire), `structures.gd` (the industrial structures).
- `scripts/game.gd`: both modes (Vadi, Test Alanı). `scripts/menu.gd`: the start.

## Tests

```
godot --headless --path . -s res://tests/drive_test.gd
godot --headless --path . -s res://tests/combat_test.gd
godot --headless --path . -s res://tests/tracks_test.gd
godot --headless --path . -s res://tests/build_test.gd
godot --headless --path . -s res://tests/arena_test.gd
godot --headless --path . -s res://tests/hazard_test.gd
godot --headless --path . -s res://tests/ai_test.gd
godot --headless --path . -s res://tests/designs_test.gd
godot --headless --path . -s res://tests/flipper_test.gd
godot --headless --path . -s res://tests/structures_test.gd
godot --headless --path . -s res://tests/salvage_test.gd
godot --headless --path . -s res://tests/keys_test.gd
godot --headless --path . -s res://tests/joints_test.gd
godot --headless --path . -s res://tests/valley_test.gd
godot --headless --path . -s res://tests/wood_test.gd
godot --headless --path . -s res://tests/sound_check.gd
godot --path . --resolution 1600x900 -s res://tests/shots.gd -- --out=<folder> [--valley | --tracks | --arena | --polish | --forge | --flip | --sites | --spin | --robots | --worksite | --expedition | --wood]
```
