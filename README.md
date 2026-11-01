# İnşa

A timber town in the taiga, 1880s-90s: log cabins in a forest valley, everything hauled through the
mud, lit at night by lamps and windows, and ready to burn (Godot 4.7, Jolt). The valley, its terrain, mud, snow, trees, river, lake
and sky come from the Mud Run project (`../car`), stripped of its roads and its place names: the only
ways are the ones the villagers walk in, and the river is crossed at its two fords. The village is
this project's own.

## Play

You start with a store (Depo), a log cabin and six settlers on the flat by the river. Put buildings
down where you like, turned how you like: a ghost follows the mouse (red where it can't go: too
steep, water, too close to another building) and the trees and rocks on its ground are cleared.
A site is staked out first, string run between the stakes, and a scaffold goes up round it with
plank decks every 1.8 m. What the free settlers carry from the store for it is stacked at its
corner, logs and stone, the stack going down as it's built in. It goes up in stages (the footing,
the walls course by course, the roof, then the windows, doors, porch and the rest), and nothing goes
up that nobody carried: a builder takes an armful off the stack (a few pieces going up side by side),
carries it round to where it goes, climbs onto the scaffold for the high ones, and sets each in its
place from its hands. The card says which stage it's at.

- **Kütük ev**: a log cabin, its walls log on log (each burns and falls on its own), a stone
  chimney; four beds. With a bed free and food in store, someone new comes now and then.
- **Tarla**: a fenced field (it claims its ground but is walked over). Its farmers sow it row by
  row, hoe it while it grows (faster in the rain, not at all under snow), and reap it ripe: sixty
  food a crop, carried home (or piled by the gate, with carters about). A ripe crop burns: a fire
  runs across it and leaves it black and fallow.
- **Kesim kampı**: a yard with a sawhorse. Its workers fell the nearest tree (it goes over away from
  the axe, a stump stays), lop its branches, buck the trunk into logs where it lies (the slash rots
  away), shoulder a log back to the yard and saw it up on the trestles. The sawn wood is piled in
  the yard; carters fetch the pile, or, with none about, the workers take it to the store once it's
  grown.
- **Ormancı**: plants a sapling on the stump of a felled tree: the same tree, small, growing slowly
  at first and then shooting up; a few minutes on it's the tree again.
- **Taş ocağı**: a stone yard with a dressing bench and a derrick: blocks broken off the rocks
  round it are carried in and dressed with mallet and chisel, then piled.
- **Toplayıcı**: picks the bushes for berries (none in winter), sorts them on the table, piles them;
  a picked bush bears again later.
- **Depo**: a store. Each holds its own goods (the top bar adds them up): loads go to the
  nearest one, a site's stuff is fetched from the nearest that has it. A store that burns loses
  what's in it; one raided is plundered; one left a ruin keeps its goods under the rubble till
  it's mended.
- **Arabacı**: its workers push handcarts, twelve to a load. With carters about, a workplace
  more than 20 m from a store piles what its workers bring by its own door, and the carters fetch
  the piles. A cart wears a path three times as fast, but in the rain or on soft ground it's slow
  and now and then sinks in and has to be heaved out.
- **Ahır**: each of its workers leads an ox and its two-wheeled cart: thirty to a load, slow,
  wearing the deepest ruts of all (a broad pair beside the drover), stuck in mud more often and
  longer. Every ox eats as much as a villager.
- **Kuyu**: in a fire the villagers run buckets from the nearest well. No well, no putting it out.
- **Fener**: a lamp post burning pine kindling (a log a few hours, brought at dusk): its light
  reaches 20 m. Windows light up where people live and the hearth burns, and anyone out at night
  carries a lantern. A lamp in the wind throws sparks now and then.
- **Gözcü kulesi**: a timber tower with a rifleman up it, who shoots what he can see within 70 m;
  with one standing, a band or a pack is heard coming.
- **Bekçi karakolu**: the settlers given to it (up to six) are watchmen with rifles.
- **Meydan**: the town square, paved round a fire pit with log benches. Of an evening (18:30 to
  23:00) its fire burns the wood brought for it, and the townsfolk gather round it to sit and talk.
- **Çan kulesi**: the bell rings for work at six and for the end of it at seven in the evening;
  when a raid comes it rings the alarm, and everyone in the town hides, not just those nearby.
- **Tahta yol** (TAŞIMA): drag from one point to another to lay a plank road, a log for every 2 m.
  On planks the townsfolk walk half as fast again, never in mud, and paths prefer them.

A house when finished gets its yard: a fence with a gate before the door, a garden of cabbages,
an outhouse, a hen house, a woodshed, and the odds and ends of a farm (a cart, hay, a trough, a
bench, a sledge). Where another yard or building is in the way the fence is left open. A new
building turns its door to the nearest square, store, well or bell tower and lines up with its
neighbours; R turns it by hand.

The night is dark, and what's in it comes out (`raids.gd`). From the third night, every other night
after midnight a band of outlaws comes out of the woods and makes for the town from its darkest
side: they go for the unlit buildings first, light a torch at the door, set it alight, plunder the
store, cut down anyone in their way, and go when they've burnt enough or the dawn's coming. Some
nights a pack of wolves comes down after anyone out in the dark; in the light they turn back. The
watchmen and the lookout only see what's lit (or close): light is the town's defence. Everyone else
runs for a house or the store and hides till it's over (out again if it catches fire). B starts a
raid at once.

The buildings are lived in: a settler going home to sleep, hiding from a raid, setting down a load
in the store or fetching from it, or bringing firewood to a hearth walks up to the door, which swings
in, steps inside, and the door shuts behind; coming out, it opens again.

The year turns (`seasons.gd`), three days a season: a wet spring (the trodden ground goes to dark
mud, slow underfoot and slower for carts), a dry summer (fire weather), a grey autumn, and a
winter of snow and frost (the snow lies on the ground, the roofs and the tops of the logs; nothing
grows, the bushes bear nothing, the hearths burn up to twice the wood). Get the food and wood in
before it comes. The test panel at the bottom right jumps to a season, to night or day, or starts a
raid.

The settlers live: they eat at noon and at supper (at home if it's near, through the door, or sat
on the ground with a bowl), and with nothing to do they talk with whoever else is standing about,
sit on the ground, stretch, look round, stroll. Click one to see who it is and what it's doing;
with it chosen, right-click a workplace, a field or the watch house to put it to work there.

The valley is alive (`atmosphere.gd`, `ambience.gd`, `critters.gd`): mist settles in it at dawn
and dusk with the low sun's shafts through it and the lamps haloed in it; the golden hours run warm
and winter pale; close in, the distance goes soft. Birds wheel over the woods by day, butterflies
over the summer grass, breath smokes in the cold, sawdust and chips fly from the work, embers blow
off a fire. Hens scratch about every lived-in house and scatter from anyone walking through them; a
dog follows one of every few households. Some newcomers are children, who play and grow up to work
after four days. You hear the woods and their birds by day, crickets on warm nights, the cold wind
in winter and the stream by the river, every blow of an axe or a pick, a tree cracking and crashing
down, a log thrown down. P hides the screen for a picture.

Settlers work with the tool for the work: an axe swung in flat at the trunk, a pick, a hammer on a
site, a sickle bent to the crop, a hoe, a spade for a sapling.

Choose a workplace to set how many work there (− / +); the rest are free to haul and build.
People eat; out of food, everyone works slowly. At night everyone with a house goes home, and
the windows light up.

The paths find themselves: every step wears the ground, and enough feet make a trodden path
(drawn on the terrain, the grass gone from it) that's quicker to walk and chosen more by the
pathfinder, so the village's ways come out of where its people go. A path nobody uses grows over.
In the rain the paths go to mud and lose most of what they give.

Nothing a fire or a raid does is wiped away. What falls stays where it fell, charred; the ground
round a fire is scorched black and greens again only slowly. A damaged building or a ruin can be
mended (O, or ONAR): it costs its share of what the building cost, a scaffold goes up, and the
missing pieces are put back one by one out of what's brought, the rubble cleared as they go.
What only charred stays charred.

In the cold (under 12°, and every night) each lived-in house burns firewood, which the villagers
carry to it from the store; smoke rises from its chimney while it burns. A house with none left
goes cold, and those who slept in it are hurt by morning. A lit hearth now and then throws a spark
onto its roof, more often when it's dry and windy. People mend slowly, quicker asleep.

The woods hold the hills. Where enough of a slope's trees have been felled (counted per 48 m
square), heavy rain can bring it down (`landslides.gd`): a tongue of mud and stones runs off down
the fall line, the ground it crossed left deep mud (carts sink in it), pieces knocked off any
building in its way, anyone standing there hurt. A slope goes once; grow its trees back and it
holds again. A building's card warns when the hillside round it is bare.

Buildings are made of pieces that rest on one another. Fire burns piece by piece (thatch quickest,
plaster slowest, stone never), chars them and spreads to what touches them, and from building to
building, downwind most. A piece burnt through falls, and what rested on it falls after it. Too
little left standing and it's a ruin. Rain puts fires out now and then, and a lightning strike in
a storm can start one.

| Key | |
|---|---|
| WASD · arrows · the window's edges | pan (Shift faster) |
| Q E · middle button held | turn the view |
| wheel | in and out |
| Tab · 1-5 · build bar | the next group of buildings · put one down (left click; Shift keeps placing) · R / Shift R turn it · right click cancel |
| left click · right click | choose a building or a settler · with a settler chosen, put it to work there |
| O | mend the chosen building |
| Del · X | pull the chosen building down (half its stuff back; all of it for a site) |
| F | set the chosen building alight (to try fire out) |
| H | back to the store |
| Space · + / - · Esc · F1 | pause · game speed 1x/2x/4x (or the buttons) · menu · the keys |
| P | picture mode (the screen hidden, the distance soft) |
| F5 · F9 | save · load (it also saves itself every morning, and starts from the save) |

## How it works

- The world, kept from the Mud Run project: `world_terrain.gd` (the heightmap, its chunks and LODs,
  collision, mud and snow, water), `world_decor.gd` (grass, lake, river, the horizon),
  `world_props.gd` (72 539 trees, bushes, rocks: LOD MultiMeshes, `prop_info`, `cut_tree`,
  `felled_mesh`), `weather.gd` (day and night, the dynamic weather), `soft_patch.gd`, `surface.gd`,
  `rut_store.gd`, `splash.gd`, `war_map.gd`; data in `assets/world`, models in `assets/nature`.
  `WorldTerrain.village_mask` (1024², 2 m a texel) carries the village's marks on the ground: red the
  paths, green the ground under buildings, blue scorched; `world_terrain.gdshader` and `grass.gdshader` read it.
- `scripts/nav.gd`: the 2 m walking grid (AStarGrid2D): water, cliffs, the river but at its fords, and
  buildings shut; forest and slope dearer; the wear of every step, its
  paths, their fading.
- Models: `tools/blender/build_buildings.py` builds every building as a GLB of separate pieces
  (`assets/buildings/<kind>.glb`; each log, roof strip, window, door, chimney course its own object,
  named for its stuff and tag, coloured in its vertices; previews in `assets/buildings/previews`):
  `blender --background --factory-startup --python tools/blender/build_buildings.py [-- --render] [-- --only=ev]`.
  `tools/blender/build_villagers.py` builds the townsfolk (`assets/villagers/<variant>.glb`: five
  outfits and the outlaw, each a body and four limbs the game swings).
- `scripts/building_defs.gd`: what can be built (cost, time, job) and each one's pieces.
  `scripts/building.gd`: a building: ghost, site, done, ruin; pieces going up, what rests on what,
  fire per piece, falling pieces as rigid bodies. `scripts/fire_fx.gd`: flames and smoke.
- `scripts/villager.gd`: a villager: its plan (go, work, do), walking and wearing the ground, carrying,
  its look and its moves. `scripts/village.gd`: the store, the buildings, who does what (fires,
  workplaces, hauling, building, sleeping), eating, newcomers, fire leaping between buildings,
  lightning, felling.
- `scripts/yard.gd`: a house's yard: fence, garden, outbuildings, clutter; its fence shut on the grid.
- `scripts/crop.gd`: a field's crop: sowing, growing, ripe, reaped, burning; its tufts.
  `scripts/village_save.gd`: the save (user://village_save.dat): buildings with their fallen and
  charred pieces and goods, people and their work and homes, felled trees and stumps, worn paths,
  scorched ground, the day, the camera. Loads in hand go back to their store; fires and raids
  under way are not kept.
- `scripts/seasons.gd`: the year and its weather. `shaders/building.gdshader`: the Blender pieces'
  look, wet and snowed on.
- `scripts/raids.gd`: outlaws, wolves (`scripts/wolf.gd`), who can see what, rifle shots.
- `scripts/rts_camera.gd`: the camera from above, and where the mouse meets the ground.
  `scripts/hud.gd`: the screen. `scripts/main.gd`: the game: placing, choosing, keys, saving.
  `scripts/ui.gd`: the look shared by the screens (Barlow, SIL OFL 1.1).
- Sounds of building: `assets/audio/build` (see its CREDITS.md).
