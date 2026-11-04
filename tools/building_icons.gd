extends SceneTree
## The build bar's pictures: every building put up whole in a little studio of its own and taken
## from the front right, a little above, on a clear background (its buried plinth left out).
##
##   godot --path . -s res://tools/building_icons.gd [-- --only=ev,ambar] [--passes=<dir>]
##
## Output: assets/ui/icons/<kind>.png (the HUD shows them if they're there).
## With --passes: instead, for the build bar's engraved plates (tools/ink_plates.py), each one drawn
## square and flat on (an orthographic, axonometric view, as a draughtsman's plate), lit hard from
## the upper left: <dir>/<kind>_c.png its colours, <dir>/<kind>_n.png its surfaces (RG which way
## each faces, B how far off), the creases and edges the ink lines are found from.

const OUT := "res://assets/ui/icons/"
const SIZE := Vector2i(256, 176)

var _vp: SubViewport
var _cam: Camera3D
var _kinds: Array = []
var _passes := "" ## (--passes: the folder the plates' passes go to)
var _sun: DirectionalLight3D
var _env: Environment
var _surf: ShaderMaterial


func _initialize() -> void:
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
		if a.begins_with("--passes="):
			_passes = a.trim_prefix("--passes=")
	for k: String in BuildingDefs.DEFS.keys() + ["kes", "kesme", "tuzak", "mayin", "hendek"]:
		if only.is_empty() or k in only:
			_kinds.append(k)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = SIZE if _passes == "" else Vector2i(1024, 1024)
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
	_env = env
	if _passes != "":
		# the plates: a hard key light, little fill, so the shaded sides read dark enough to hatch
		env.ambient_light_energy = 0.42
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		DirAccess.make_dir_recursive_absolute(_passes)
		var sh := Shader.new()
		sh.code = "shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec3 n = normalize(NORMAL) * (FRONT_FACING ? 1.0 : -1.0);
	ALBEDO = vec3(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, clamp(-VERTEX.z / 400.0, 0.0, 1.0));
}"
		_surf = ShaderMaterial.new()
		_surf.shader = sh
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("#ffe6c4")
	sun.light_energy = 1.5
	sun.rotation_degrees = Vector3(-42, 30, 0)
	sun.shadow_enabled = true
	_vp.add_child(sun)
	_sun = sun
	if _passes != "":
		sun.light_energy = 2.1
		sun.rotation_degrees = Vector3(-48, -28, 0) # (from the upper left, over the viewer's shoulder)
		sun.directional_shadow_max_distance = 300.0
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
	# close on a trunk: the lower boughs over it, a red ribbon tied round it, and for KES an axe bitten
	# into its side; for KESME the same tree with the ribbon struck through by a big red cross
	var n := Node3D.new()
	_vp.add_child(n)
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.36, 0.26, 0.18)
	bark.roughness = 1.0
	var needles := StandardMaterial3D.new()
	needles.albedo_color = Color(0.16, 0.32, 0.18)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.15, 0.08)
	red.emission_enabled = true
	red.emission = Color(0.6, 0.08, 0.03)
	red.emission_energy_multiplier = 0.3
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.3, 0.26, 0.17)
	var g := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 1.6
	gm.bottom_radius = 1.6
	gm.height = 0.1
	g.mesh = gm
	g.material_override = ground
	n.add_child(g)
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.32
	tm.bottom_radius = 0.42
	tm.height = 3.4
	tm.radial_segments = 12
	trunk.mesh = tm
	trunk.material_override = bark
	trunk.position.y = 1.7
	n.add_child(trunk)
	for k in 3: # (the lowest boughs)
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.1
		cm.bottom_radius = 1.5 - k * 0.35
		cm.height = 1.1
		cm.radial_segments = 8
		c.mesh = cm
		c.material_override = needles
		c.position.y = 3.0 + k * 0.7
		n.add_child(c)
	var rib := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.41
	rm.bottom_radius = 0.41
	rm.height = 0.22
	rm.radial_segments = 16
	rib.mesh = rm
	rib.material_override = red
	rib.position.y = 1.55
	n.add_child(rib)
	for s in [-1.0, 1.0]: # (its ends hanging)
		var tail := MeshInstance3D.new()
		var tl := BoxMesh.new()
		tl.size = Vector3(0.1, 0.55, 0.03)
		tail.mesh = tl
		tail.material_override = red
		tail.position = Vector3(0.2 * s + 0.15, 1.25, 0.42)
		tail.rotation.z = s * 0.25
		n.add_child(tail)
	if kind == "kes":
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color(0.55, 0.56, 0.58)
		iron.metallic = 0.7
		iron.roughness = 0.35
		var haft := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.045
		hm.bottom_radius = 0.05
		hm.height = 1.3
		haft.mesh = hm
		haft.material_override = bark
		haft.position = Vector3(0.6, 0.75, 0.62)
		haft.rotation = Vector3(0, -0.6, 1.15)
		n.add_child(haft)
		var head := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.36, 0.26, 0.06)
		head.mesh = am
		head.material_override = iron
		head.position = Vector3(0.25, 0.95, 0.45)
		head.rotation = Vector3(0, -0.6, 1.15)
		n.add_child(head)
		var chips := StandardMaterial3D.new()
		chips.albedo_color = Color(0.85, 0.7, 0.48)
		for k in 6:
			var ch := MeshInstance3D.new()
			var chm := BoxMesh.new()
			chm.size = Vector3(0.12, 0.03, 0.08)
			ch.mesh = chm
			ch.material_override = chips
			ch.position = Vector3(0.5 + k * 0.12, 0.07, 0.3 + (k % 3) * 0.15)
			ch.rotation.y = k * 1.1
			n.add_child(ch)
	else:
		var white := StandardMaterial3D.new()
		white.albedo_color = Color(0.92, 0.9, 0.85)
		white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for s in [-1.0, 1.0]:
			var bar := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.22, 2.4, 0.06)
			bar.mesh = bm
			bar.material_override = white
			bar.position = Vector3(0, 1.6, 0.75)
			bar.rotation.z = s * 0.75
			n.add_child(bar)
	var box := AABB(Vector3(-1.6, 0, -1.6), Vector3(3.2, 3.6, 3.2))
	var centre := box.get_center()
	var dir := Vector3(0.78, 0.35, 1.0).normalized()
	var dist := box.size.y * 0.5 / tan(deg_to_rad(_cam.fov * 0.5)) * 1.05
	_cam.look_at_from_position(centre + dir * dist, centre)
	await _snap(kind, n)
	n.queue_free()
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
		"tuzak", "mayin", "hendek": # (a block of ground cut away, so the depth shows)
			var turf := StandardMaterial3D.new()
			turf.albedo_color = Color(0.3, 0.42, 0.18)
			var earth := StandardMaterial3D.new()
			earth.albedo_color = Color(0.36, 0.26, 0.17)
			var deep := StandardMaterial3D.new()
			deep.albedo_color = Color(0.12, 0.09, 0.06)
			var iron := StandardMaterial3D.new()
			iron.albedo_color = Color(0.3, 0.31, 0.27)
			iron.metallic = 0.6
			iron.roughness = 0.45
			var red := StandardMaterial3D.new()
			red.albedo_color = Color(0.82, 0.14, 0.08)
			var slabs: Array = [[Vector3(3.2, 0.7, 3.2), Vector3(0, -0.35, 0)]]
			if kind == "hendek":
				slabs = [[Vector3(3.2, 0.7, 1.1), Vector3(0, -0.35, -1.05)], [Vector3(3.2, 0.7, 1.1), Vector3(0, -0.35, 1.05)]]
			for sl: Array in slabs:
				var b := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = sl[0]
				b.mesh = bm
				b.material_override = earth
				b.position = sl[1]
				n.add_child(b)
				var t := MeshInstance3D.new()
				var tbm := BoxMesh.new()
				tbm.size = Vector3((sl[0] as Vector3).x, 0.08, (sl[0] as Vector3).z)
				t.mesh = tbm
				t.material_override = turf
				t.position = (sl[1] as Vector3) + Vector3(0, 0.37, 0)
				n.add_child(t)
			match kind:
				"tuzak":
					var hole := MeshInstance3D.new()
					var hm := CylinderMesh.new()
					hm.top_radius = 0.95
					hm.bottom_radius = 0.95
					hm.height = 0.1
					hole.mesh = hm
					hole.material_override = deep
					hole.position.y = 0.03
					n.add_child(hole)
					for k in 10:
						var a := k * TAU / 10.0
						var rim := MeshInstance3D.new()
						var rmm := SphereMesh.new()
						rmm.radius = 0.28
						rmm.height = 0.25
						rim.mesh = rmm
						rim.material_override = earth
						rim.position = Vector3(cos(a) * 1.1, 0.1, sin(a) * 1.1)
						n.add_child(rim)
					for k in 9:
						var a := k * TAU / 9.0 + 0.2
						var r := 0.15 + (k % 3) * 0.25
						var st := MeshInstance3D.new()
						var sm := CylinderMesh.new()
						sm.top_radius = 0.0
						sm.bottom_radius = 0.07
						sm.height = 0.9
						st.mesh = sm
						st.material_override = wood
						st.position = Vector3(cos(a) * r, 0.4, sin(a) * r)
						st.rotation = Vector3(0.12, a, 0)
						n.add_child(st)
				"mayin":
					var mound := MeshInstance3D.new()
					var mm := SphereMesh.new()
					mm.radius = 1.0
					mm.height = 0.4
					mound.mesh = mm
					mound.material_override = earth
					mound.position.y = 0.05
					n.add_child(mound)
					var case := MeshInstance3D.new()
					var cm := CylinderMesh.new()
					cm.top_radius = 0.5
					cm.bottom_radius = 0.58
					cm.height = 0.32
					case.mesh = cm
					case.material_override = iron
					case.position.y = 0.3
					n.add_child(case)
					for k in 3: # (the horns of its fuses)
						var a := k * TAU / 3.0
						var horn := MeshInstance3D.new()
						var hm2 := CylinderMesh.new()
						hm2.top_radius = 0.05
						hm2.bottom_radius = 0.07
						hm2.height = 0.25
						horn.mesh = hm2
						horn.material_override = iron
						horn.position = Vector3(cos(a) * 0.25, 0.55, sin(a) * 0.25)
						n.add_child(horn)
					var stick := MeshInstance3D.new()
					var stm := CylinderMesh.new()
					stm.top_radius = 0.035
					stm.bottom_radius = 0.035
					stm.height = 1.6
					stick.mesh = stm
					stick.material_override = wood
					stick.position = Vector3(1.05, 0.8, 0.3)
					n.add_child(stick)
					var rag := MeshInstance3D.new()
					var rgm := BoxMesh.new()
					rgm.size = Vector3(0.03, 0.35, 0.55)
					rag.mesh = rgm
					rag.material_override = red
					rag.position = Vector3(1.05, 1.42, 0.58)
					n.add_child(rag)
				"hendek":
					var floor := MeshInstance3D.new()
					var fm := BoxMesh.new()
					fm.size = Vector3(3.2, 0.06, 1.0)
					floor.mesh = fm
					floor.material_override = deep
					floor.position.y = -0.62
					n.add_child(floor)
					for s in [-1.0, 1.0]: # (planks shoring the walls)
						for k in 4:
							var pl := MeshInstance3D.new()
							var pm := BoxMesh.new()
							pm.size = Vector3(3.2, 0.14, 0.04)
							pl.mesh = pm
							pl.material_override = wood
							pl.position = Vector3(0, -0.5 + k * 0.17, s * 0.49)
							n.add_child(pl)
					var heap := MeshInstance3D.new()
					var hpm := SphereMesh.new()
					hpm.radius = 1.0
					hpm.height = 0.7
					heap.mesh = hpm
					heap.material_override = earth
					heap.position = Vector3(0, 0.15, -1.25)
					heap.scale = Vector3(1.6, 1.0, 0.55)
					n.add_child(heap)
					var haft := MeshInstance3D.new()
					var hfm := CylinderMesh.new()
					hfm.top_radius = 0.035
					hfm.bottom_radius = 0.035
					hfm.height = 1.3
					haft.mesh = hfm
					haft.material_override = wood
					haft.position = Vector3(0.9, 0.25, 0.75)
					haft.rotation.z = 0.45
					n.add_child(haft)
					var blade := MeshInstance3D.new()
					var blm := BoxMesh.new()
					blm.size = Vector3(0.26, 0.34, 0.03)
					blade.mesh = blm
					blade.material_override = iron
					blade.position = Vector3(1.18, -0.3, 0.75)
					blade.rotation.z = 0.45
					n.add_child(blade)
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
	await _snap(kind, n)
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
	if kind == "tarla":
		_furrows(b)
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
	await _snap(kind, b)
	b.queue_free()
	await process_frame


## The picture taken of `n` as the camera now stands: the icon, or (--passes) the plate's two passes,
## the camera turned orthographic along the same line and closed on the thing's box.
func _snap(kind: String, n: Node3D) -> void:
	if _passes == "":
		await _render()
		_vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + kind + ".png"))
		print("icons: wrote %s" % kind)
		return
	for k in 6: # (a building merges its pieces into one mesh after a frame or two: let it)
		await process_frame
	for ps: Node in n.find_children("*", "GPUParticles3D", true, false):
		(ps as GPUParticles3D).visible = false # (no smoke on a plate)
	var box := AABB()
	var first := true
	var meshes: Array[MeshInstance3D] = []
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		meshes.append(m)
		var bb := m.global_transform * m.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var fwd := -_cam.global_basis.z
	if box.size.y < 0.2 * maxf(box.size.x, box.size.z): # (a flat thing, a field: looked at from higher up)
		fwd = (fwd + Vector3.DOWN * 0.9).normalized()
	var centre := box.get_center()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = box.size.length() * 1.02
	_cam.near = 0.5
	_cam.far = 600.0
	_cam.look_at_from_position(centre - fwd * 150.0, centre)
	_sun.directional_shadow_max_distance = 300.0
	await _render()
	_vp.get_texture().get_image().save_png(_passes.path_join(kind + "_c.png"))
	var kept: Array = []
	for m in meshes:
		kept.append(m.material_override)
		m.material_override = _surf
	await _render()
	_vp.get_texture().get_image().save_png(_passes.path_join(kind + "_n.png"))
	for i in meshes.size():
		if is_instance_valid(meshes[i]):
			meshes[i].material_override = kept[i]
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	print("plates: wrote %s" % kind)


func _render() -> void:
	await process_frame
	await process_frame
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw


## A field's ploughed ground for its picture: dark earth inside the fence, ridged in rows, a green
## sprout every so often along them (a field put up fresh is bare, which reads as nothing).
func _furrows(b: Node3D) -> void:
	var sz: Vector2 = BuildingDefs.DEFS["tarla"].size
	var earth := StandardMaterial3D.new()
	earth.albedo_color = Color(0.5, 0.38, 0.25)
	var ridge := StandardMaterial3D.new()
	ridge.albedo_color = Color(0.64, 0.5, 0.33)
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.42, 0.62, 0.2)
	var soil := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(sz.x - 0.4, 0.08, sz.y - 0.4)
	soil.mesh = sm
	soil.material_override = earth
	soil.position.y = 0.04
	b.add_child(soil)
	var rows := int((sz.x - 1.0) / 1.25)
	for i in rows:
		var x := -sz.x * 0.5 + 1.0 + i * 1.25
		var r := MeshInstance3D.new()
		var rm := PrismMesh.new()
		rm.size = Vector3(0.75, 0.32, sz.y - 0.8)
		r.mesh = rm
		r.material_override = ridge
		r.position = Vector3(x, 0.24, 0)
		b.add_child(r)
		var z := -sz.y * 0.5 + 0.8
		var k := 0
		while z < sz.y * 0.5 - 0.6:
			var sp := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.38
			cm.bottom_radius = 0.04
			cm.height = 0.7
			cm.radial_segments = 5
			sp.mesh = cm
			sp.material_override = green
			sp.position = Vector3(x, 0.72, z + fmod(i * 0.37, 0.5))
			b.add_child(sp)
			z += 2.4
			k += 1
