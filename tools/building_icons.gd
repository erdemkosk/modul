extends SceneTree
## The build bar's pictures: every building put up whole in a little studio of its own and taken
## from the front right, a little above, on a clear background (its buried plinth left out).
##
##   godot --path . -s res://tools/building_icons.gd [-- --only=ev,ambar]
##
## Output: assets/ui/icons/<kind>.png (the HUD shows them if they're there).

const OUT := "res://assets/ui/icons/"
const SIZE := Vector2i(256, 176)

var _vp: SubViewport
var _cam: Camera3D
var _kinds: Array = []


func _initialize() -> void:
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	for k: String in BuildingDefs.DEFS.keys() + ["kes", "kesme", "tuzak", "mayin", "hendek"]:
		if only.is_empty() or k in only:
			_kinds.append(k)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b8b0a0")
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffe6c4")
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-42, 30, 0)
	sun.shadow_enabled = true
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 28.0
	_vp.add_child(_cam)
	_take_all.call_deferred()


func _take_all() -> void:
	for k: String in _kinds:
		await _take(k)
	quit()


## The orders' pictures (the build bar's EMİRLER): a spruce with the marker over it, orange to fell it,
## grey to let it stand.
func _take_order(kind: String) -> void:
	var tree := (load("res://assets/nature/spruce_a.glb") as PackedScene).instantiate() as Node3D
	_vp.add_child(tree)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.6
	cm.bottom_radius = 0.0
	cm.height = 2.8
	cm.radial_segments = 4
	cone.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.45, 0.08) if kind == "kes" else Color(0.55, 0.6, 0.66)
	m.emission_enabled = kind == "kes"
	m.emission = Color(1.0, 0.4, 0.05)
	m.emission_energy_multiplier = 0.4
	cone.material_override = m
	var box := AABB()
	var first := true
	for mi: Node in tree.find_children("*", "MeshInstance3D", true, false):
		var bb := (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	cone.position = Vector3(0, box.end.y + 2.2, 0)
	cone.rotation.y = 0.785
	_vp.add_child(cone)
	box = box.merge(AABB(cone.position - Vector3(1.6, 1.4, 1.6), Vector3(3.2, 2.8, 3.2)))
	var centre := box.get_center()
	var dir := Vector3(0.78, 0.25, 1.0).normalized()
	var dist := box.size.y * 0.5 / tan(deg_to_rad(_cam.fov * 0.5)) * 1.15
	_cam.look_at_from_position(centre + dir * dist, centre)
	await process_frame
	await process_frame
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	_vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + kind + ".png"))
	print("icons: wrote %s" % kind)
	tree.queue_free()
	cone.queue_free()
	await process_frame


## The things drawn along a line rather than put up whole: a stretch of palisade, its gate, a few
## planks of road.
func _take_line(kind: String) -> void:
	var n := Node3D.new()
	_vp.add_child(n)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.33, 0.22)
	var plank := StandardMaterial3D.new()
	plank.albedo_color = Color(0.62, 0.48, 0.32)
	match kind:
		"sur", "kapi":
			for k in 11:
				var x := (k - 5) * 0.3
				if kind == "kapi" and absf(x) < 0.9:
					continue
				var st := MeshInstance3D.new()
				st.mesh = Wall.stake_mesh() # (its own bark and cut point)
				var h := fposmod(sin(k * 78.233) * 43758.5453, 1.0)
				st.position = Vector3(x, 0, 0)
				st.rotation.y = h * TAU
				st.scale = Vector3(1, 0.9 + h * 0.2, 1)
				n.add_child(st)
			if kind == "sur": # (the rails binding them on the inside)
				for hgt in [0.75, 1.95]:
					var r := MeshInstance3D.new()
					r.mesh = Wall.rail_mesh()
					r.material_override = Wall.bark_material(1)
					r.position = Vector3(0, hgt, -0.19)
					r.scale = Vector3(3.3, 1, 1)
					n.add_child(r)
			if kind == "kapi":
				for s in [-1.0, 1.0]:
					var leaf := MeshInstance3D.new()
					var bm := BoxMesh.new()
					bm.size = Vector3(0.85, 2.0, 0.08)
					leaf.mesh = bm
					leaf.material_override = plank
					leaf.position = Vector3(s * 0.45, 1.0, 0.25)
					leaf.rotation.y = s * 0.5
					n.add_child(leaf)
		"tuzak": # (a pit of turned earth, sharpened stakes in it)
			var earth := StandardMaterial3D.new()
			earth.albedo_color = Color(0.3, 0.22, 0.15)
			var pit := MeshInstance3D.new()
			var pm := CylinderMesh.new()
			pm.top_radius = 1.0
			pm.bottom_radius = 1.0
			pm.height = 0.05
			pit.mesh = pm
			pit.material_override = earth
			n.add_child(pit)
			for k in 9:
				var a := k * TAU / 9.0
				var st := MeshInstance3D.new()
				var sm := CylinderMesh.new()
				sm.top_radius = 0.0
				sm.bottom_radius = 0.06
				sm.height = 0.7
				st.mesh = sm
				st.material_override = wood
				st.position = Vector3(cos(a) * (0.2 + (k % 3) * 0.25), 0.3, sin(a) * (0.2 + (k % 3) * 0.25))
				st.rotation = Vector3(0.15, a, 0)
				n.add_child(st)
		"mayin": # (a round iron mine half dug in, its pressure plate up, a red-ragged stick by it)
			var earth := StandardMaterial3D.new()
			earth.albedo_color = Color(0.3, 0.22, 0.15)
			var iron := StandardMaterial3D.new()
			iron.albedo_color = Color(0.25, 0.26, 0.22)
			iron.metallic = 0.6
			var mound := MeshInstance3D.new()
			var mm := SphereMesh.new()
			mm.radius = 1.0
			mm.height = 0.3
			mound.mesh = mm
			mound.material_override = earth
			n.add_child(mound)
			var case := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.55
			cm.bottom_radius = 0.6
			cm.height = 0.3
			case.mesh = cm
			case.material_override = iron
			case.position.y = 0.15
			n.add_child(case)
			var plate := MeshInstance3D.new()
			var pm2 := CylinderMesh.new()
			pm2.top_radius = 0.18
			pm2.bottom_radius = 0.18
			pm2.height = 0.12
			plate.mesh = pm2
			plate.material_override = iron
			plate.position.y = 0.36
			n.add_child(plate)
			var stick := MeshInstance3D.new()
			var sm2 := CylinderMesh.new()
			sm2.top_radius = 0.03
			sm2.bottom_radius = 0.03
			sm2.height = 1.4
			stick.mesh = sm2
			stick.material_override = wood
			stick.position = Vector3(1.0, 0.7, 0)
			n.add_child(stick)
			var rag := MeshInstance3D.new()
			var rm := BoxMesh.new()
			rm.size = Vector3(0.02, 0.25, 0.4)
			rag.mesh = rm
			var red := StandardMaterial3D.new()
			red.albedo_color = Color(0.75, 0.12, 0.08)
			rag.material_override = red
			rag.position = Vector3(1.0, 1.3, 0.2)
			n.add_child(rag)
		"hendek": # (a trench cut in the earth, its spoil heaped along one lip, a spade in it)
			var earth := StandardMaterial3D.new()
			earth.albedo_color = Color(0.3, 0.22, 0.15)
			var dark := StandardMaterial3D.new()
			dark.albedo_color = Color(0.12, 0.09, 0.06)
			for s in [-1.0, 1.0]:
				var lip := MeshInstance3D.new()
				var lm := BoxMesh.new()
				lm.size = Vector3(3.2, 0.35 if s > 0 else 0.15, 0.7)
				lip.mesh = lm
				lip.material_override = earth
				lip.position = Vector3(0, 0.15, s * 0.75)
				n.add_child(lip)
			var floor := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(3.2, 0.05, 0.8)
			floor.mesh = fm
			floor.material_override = dark
			n.add_child(floor)
			var haft := MeshInstance3D.new()
			var hm := CylinderMesh.new()
			hm.top_radius = 0.03
			hm.bottom_radius = 0.03
			hm.height = 1.2
			haft.mesh = hm
			haft.material_override = wood
			haft.position = Vector3(0.8, 0.55, 0.1)
			haft.rotation.z = 0.5
			n.add_child(haft)
		"yol":
			for k in 7:
				var pl := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(2.2, 0.08, 0.3)
				pl.mesh = bm
				pl.material_override = plank
				pl.position = Vector3(sin(k * 0.3) * 0.3, 0.04, (k - 3) * 0.36)
				pl.rotation.y = k * 0.06
				n.add_child(pl)
	var box := AABB()
	var first := true
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
		var bb := (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var centre := box.get_center()
	var dir := Vector3(0.78, 0.62, 1.0).normalized()
	_cam.look_at_from_position(centre + dir * box.size.length() * 0.5 / tan(deg_to_rad(_cam.fov * 0.5)) * 0.95, centre)
	await process_frame
	await process_frame
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	_vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + kind + ".png"))
	print("icons: wrote %s" % kind)
	n.queue_free()
	await process_frame


func _take(kind: String) -> void:
	if kind in ["kes", "kesme"]:
		await _take_order(kind)
		return
	if kind in ["sur", "kapi", "yol", "tuzak", "mayin", "hendek"]:
		await _take_line(kind)
		return
	var b := Building.new()
	b.setup(kind)
	_vp.add_child(b)
	b.complete_now()
	b.set_ghost(false)
	var box := AABB()
	var first := true
	for p in b.pieces:
		if p.tag == "plinth" or p.aabb.position.y < -1.0: # (a drawn-up building's plinth: sunk deep)
			if is_instance_valid(p.mesh):
				p.mesh.visible = false
			continue
		box = p.aabb if first else box.merge(p.aabb)
		first = false
	if first:
		print("icons: %s has nothing to show" % kind)
		b.queue_free()
		return
	var centre := box.get_center()
	var dir := Vector3(0.78, 0.62, 1.0).normalized()
	var radius := box.size.length() * 0.5
	var dist := radius / tan(deg_to_rad(_cam.fov * 0.5)) * 0.92
	_cam.look_at_from_position(centre + dir * dist, centre)
	await process_frame
	await process_frame
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + kind + ".png"))
	print("icons: wrote %s" % kind)
	b.queue_free()
	await process_frame
