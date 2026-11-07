# Nature set (trees, scrub, rocks)

The taiga round the town, made in Blender the way the buildings and props are: no textures, colours
painted into the vertices, the shade of crowns' insides and of the ground baked into them.
Everything comes from `tools/blender/build_nature.py` (fixed seeds):

```
blender --background --factory-startup --python tools/blender/build_nature.py [-- --only=pine_a,rock_b] [-- --raw]
```

## Files

- `<id>.glb`: two meshes, `LOD0` (full) and `LOD1` (same silhouette, a few hundred triangles; it is
  drawn far off and casts every shadow). Origin at the trunk's foot (or the middle of a rock's/log's
  footprint), 1 unit = 1 m. Trunks, roots, stumps and rocks run on under y = 0 so they sit into slopes.
- `nature.json`: per id `kind`, `species` (the variants scripts/world_props.gd picks between), `height`,
  collision hints in Godot axes, and `tris` [LOD0, LOD1].

Materials (one per stuff; the game swaps them for shaders/nature.gdshader): `Bark`, `BirchBark`,
`DeadWood`, `Wood`, `Earth`, `Rock` (rigid), `Needles`, `Leaves`, `FernLeaf` (foliage; `Leaves` turn in
the autumn and fall in winter). All colour is in `COLOR_0`; material albedo is white.

## Models

| ids | what |
|---|---|
| `spruce_a..e` | Norway spruce, drooping tiers with hanging fringes (14.5-23.5 m) |
| `pine_a..e` | Scots pine, orange upper bark, high clumped crown (12.5-19.5 m) |
| `birch_a..e` | silver birch, `birch_d` a two-stemmed clump (10.5-14 m) |
| `dead_tree`, `dead_tree_b` | grey snags, broken tops |
| `log`, `log_b`, `branches` | fallen trunk with root plate, a rotten broken one, a heap of lopped branches (kind log) |
| `stump`, `stump_b`, `stump_c` | sawn, broken off, old and mossy |
| `bush_a..c`, `fern`, `fern_b` | juniper, willow, low juniper; bracken |
| `rock_a..e` | granite boulders, a slab, a group of three |
| `cliff_a`, `cliff_b` | ledged outcrops |
| `reeds` | reed clump for the lake shallows (scripts/world_decor.gd) |
