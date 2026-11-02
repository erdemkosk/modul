class_name MeshBake
## Many still meshes drawn as few: the MeshInstance3Ds right under a node, put together into one
## mesh per material (each at its place), so what was a draw call apiece is one per material. The
## look is the same; what's baked can't move on its own any more.


## `parent`'s own MeshInstance3D children (but those in `keep`) baked into one MeshInstance3D per
## material, added to `parent`; the originals freed. Returns the new ones.
static func bake(parent: Node3D, keep: Array = []) -> Array[MeshInstance3D]:
	var groups := {} ## material -> [MeshInstance3D]
	var shadow := {} ## material -> cast_shadow
	for c in parent.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi in keep or mi.mesh == null or not mi.visible:
			continue
		var mat: Material = mi.material_override
		if mat == null or mi.mesh.get_surface_count() != 1:
			continue
		if not groups.has(mat):
			groups[mat] = []
			shadow[mat] = mi.cast_shadow
		groups[mat].append(mi)
	var out: Array[MeshInstance3D] = []
	var inv := parent.global_transform.affine_inverse()
	for mat: Material in groups:
		var list: Array = groups[mat]
		if list.size() < 2:
			continue
		var st := SurfaceTool.new()
		for mi: MeshInstance3D in list:
			st.append_from(mi.mesh, 0, inv * mi.global_transform)
		var baked := MeshInstance3D.new()
		baked.mesh = st.commit()
		baked.material_override = mat
		baked.cast_shadow = shadow[mat]
		parent.add_child(baked)
		out.append(baked)
		for mi: MeshInstance3D in list:
			mi.queue_free()
	return out
