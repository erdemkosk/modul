extends SceneTree
## The HUD's drawings, in ink on clear paper (shaders/ink.gdshader with its outline behind): the goods
## (a stack of logs, stones, a sack and a loaf, a pail of mud, a stack of bricks), and as a trial
## a few buildings and a settler's head, all from the game's own shapes and models.
##
##   godot --path . -s res://tools/ink_icons.gd [-- --only=odun,tas]
##
## Output: assets/ui/ink/<id>.png

const OUT := "res://assets/ui/ink/"
const INK := preload("res://shaders/ink.gdshader")
const OUTLINE := preload("res://shaders/ink_outline.gdshader")
const GOODS := ["odun", "tas", "yiyecek", "camur", "kerpic", "ot", "komur", "demir"]
const TRIAL := [] ## (buildings and heads drawn the same way: "ev", "oduncu", "camur_ocagi", "portre")

var _vp: SubViewport
var _cam: Camera3D
var _ids: Array = []


func _initialize() -> void:
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",")
	for id: String in GOODS + TRIAL:
		if only.is_empty() or id in only:
			_ids.append(id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = Vector2i(256, 256)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_8X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 26.0
	_vp.add_child(_cam)
	_draw_all.call_deferred()


func _draw_all() -> void:
	for id: String in _ids:
		var thing := _make(id)
		_vp.add_child(thing)
		await process_frame
		_inked(thing)
		var size := Vector2i(256, 256) if id in GOODS or id == "portre" else Vector2i(320, 220)
		_vp.size = size
		_frame(thing, id)
		await process_frame
		await process_frame
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		_vp.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + id + ".png"))
		print("ink: wrote %s" % id)
		thing.queue_free()
		await process_frame
	quit()


## Every mesh under `n` drawn in ink: its own colour as the wash (a model's vertex colours averaged,
## a plain material's albedo), the outline as the next pass.
func _inked(n: Node) -> void:
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var wash := _colour_of(m)
		var mat := ShaderMaterial.new()
		mat.shader = INK
		mat.set_shader_parameter("wash", wash)
		var line := ShaderMaterial.new()
		line.shader = OUTLINE
		line.set_shader_parameter("width", 0.035 * maxf(m.get_aabb().size.length(), 0.4) / 1.5)
		mat.next_pass = line
		m.material_override = mat


func _colour_of(m: MeshInstance3D) -> Color:
	var src: Material = m.material_override if m.material_override else (m.mesh.surface_get_material(0) if m.mesh.get_surface_count() > 0 else null)
	if m.has_meta("wash"):
		return m.get_meta("wash")
	if src is BaseMaterial3D:
		return (src as BaseMaterial3D).albedo_color
	if src is ShaderMaterial and str(m.name).begins_with("Head"):
		return Color(0.86, 0.66, 0.52) # (a face)
	var arr := m.mesh.surface_get_arrays(0) if m.mesh is ArrayMesh else []
	if arr.size() > Mesh.ARRAY_COLOR and arr[Mesh.ARRAY_COLOR] is PackedColorArray and (arr[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0:
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var sum := Color(0, 0, 0)
		var step := maxi(1, cols.size() / 64)
		var n := 0
		for i in range(0, cols.size(), step):
			sum += cols[i]
			n += 1
		return Color(sum.r / n, sum.g / n, sum.b / n)
	return Color(0.6, 0.5, 0.4)


func _frame(thing: Node3D, id: String) -> void:
	var box := AABB()
	var first := true
	for mi: Node in thing.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.visible or m.mesh == null:
			continue
		var bb := m.global_transform * m.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var centre := box.get_center()
	if id == "portre": # (head and shoulders: the head bone, a little down)
		var body := thing.get_child(0) as Townsfolk
		var sk := body.skeleton
		var b := sk.find_bone("Head")
		var head := (sk.global_transform * sk.get_bone_global_pose(b)).origin + Vector3.UP * 0.05
		_cam.look_at_from_position(head + Vector3(0.18, 0.02, 1.15), head + Vector3(0, -0.12, 0))
		return
	var dir := Vector3(0.7, 0.55, 1.0).normalized()
	var radius := box.size.length() * 0.5
	var dist := radius / tan(deg_to_rad(_cam.fov * 0.5)) * (0.75 if id == "portre" else 0.95)
	_cam.look_at_from_position(centre + dir * dist, centre)


func _mesh(mesh: Mesh, wash: Color, xf := Transform3D.IDENTITY) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.transform = xf
	m.set_meta("wash", wash)
	return m


func _cyl(r: float, h: float, top := -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = r
	c.top_radius = r if top < 0.0 else top
	c.height = h
	c.radial_segments = 16
	return c


## What's drawn for `id`.
func _make(id: String) -> Node3D:
	var n := Node3D.new()
	match id:
		"odun": # (a stack of logs, three, two, one)
			var k := 0
			for row in 3:
				for i in 3 - row:
					var x := (i - (2 - row) * 0.5) * 0.42
					n.add_child(_mesh(_cyl(0.2, 1.4), Color(0.55, 0.38, 0.22), Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, 0.05 * k), Vector3(x, 0.2 + row * 0.36, 0))))
					k += 1
		"tas": # (a few broken stones)
			for k in 4:
				var m := _mesh(Building.rock(k), Color(0.6, 0.6, 0.57))
				m.position = Vector3([-0.35, 0.3, 0.0, -0.05][k], [0.0, 0.0, 0.0, 0.32][k], [0.1, 0.05, -0.3, -0.05][k])
				m.scale = Vector3.ONE * [0.7, 0.62, 0.66, 0.55][k]
				n.add_child(m)
		"yiyecek": # (a sack tied at the neck, a round loaf leaning on it)
			var sack := SphereMesh.new()
			sack.radius = 0.42
			sack.height = 0.95
			n.add_child(_mesh(sack, Color(0.8, 0.7, 0.5), Transform3D(Basis.IDENTITY, Vector3(-0.15, 0.45, 0))))
			n.add_child(_mesh(_cyl(0.06, 0.2, 0.14), Color(0.8, 0.7, 0.5), Transform3D(Basis.IDENTITY, Vector3(-0.15, 0.98, 0))))
			var loaf := SphereMesh.new()
			loaf.radius = 0.28
			loaf.height = 0.32
			n.add_child(_mesh(loaf, Color(0.78, 0.52, 0.26), Transform3D(Basis(Vector3.FORWARD, -0.4), Vector3(0.38, 0.22, 0.25))))
		"camur": # (a wooden pail brimming with mud)
			n.add_child(_mesh(_cyl(0.32, 0.6, 0.4), Color(0.55, 0.42, 0.28), Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 0))))
			var mud := SphereMesh.new()
			mud.radius = 0.38
			mud.height = 0.3
			n.add_child(_mesh(mud, Color(0.3, 0.22, 0.15), Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0))))
			var handle := TorusMesh.new()
			handle.inner_radius = 0.38
			handle.outer_radius = 0.41
			n.add_child(_mesh(handle, Color(0.3, 0.3, 0.3), Transform3D(Basis(Vector3.RIGHT, PI * 0.5).rotated(Vector3.UP, 0.5), Vector3(0, 0.6, 0))))
		"kerpic": # (bricks stacked in courses, crosswise)
			var brick := BoxMesh.new()
			brick.size = Vector3(0.5, 0.2, 0.26)
			for c in 3:
				for i in 2:
					var along := c % 2 == 0
					var p := Vector3(0, 0.1 + c * 0.2, (i - 0.5) * 0.28) if along else Vector3((i - 0.5) * 0.28, 0.1 + c * 0.2, 0)
					n.add_child(_mesh(brick, Color(0.72, 0.58, 0.4), Transform3D(Basis(Vector3.UP, 0.0 if along else PI * 0.5), p)))
		"ot": # (a bundle of herbs tied at the stems, the leaves fanned out)
			for k in 7:
				var a := (k - 3) * 0.16
				var stem := _mesh(_cyl(0.025, 0.9), Color(0.4, 0.5, 0.25), Transform3D(Basis(Vector3.FORWARD, a), Vector3(sin(a) * 0.45, 0.45, 0)))
				n.add_child(stem)
				var leaf := SphereMesh.new()
				leaf.radius = 0.16
				leaf.height = 0.42
				n.add_child(_mesh(leaf, Color(0.38, 0.58, 0.28).lerp(Color(0.5, 0.62, 0.3), k / 7.0), Transform3D(Basis(Vector3.FORWARD, a), Vector3(sin(a) * 0.9, 0.95 - absf(a) * 0.3, 0))))
			n.add_child(_mesh(_cyl(0.09, 0.12), Color(0.6, 0.45, 0.3), Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 0))))
		"komur": # (a heap of charcoal lumps)
			for k in 7:
				var m := _mesh(Building.rock(k % 4), Color(0.16, 0.15, 0.15))
				m.position = Vector3([-0.35, 0.3, 0.0, -0.05, 0.2, -0.25, 0.05][k], [0.0, 0.0, 0.0, 0.3, 0.28, 0.25, 0.5][k], [0.1, 0.05, -0.3, -0.05, -0.1, 0.0, -0.05][k])
				m.scale = Vector3.ONE * 0.45
				n.add_child(m)
		"demir": # (iron bars stacked crosswise)
			var bar := BoxMesh.new()
			bar.size = Vector3(1.0, 0.16, 0.22)
			for c in 3:
				for i in 2:
					var along := c % 2 == 0
					var p := Vector3(0, 0.08 + c * 0.16, (i - 0.5) * 0.4) if along else Vector3((i - 0.5) * 0.4, 0.08 + c * 0.16, 0)
					n.add_child(_mesh(bar, Color(0.42, 0.42, 0.45), Transform3D(Basis(Vector3.UP, 0.0 if along else PI * 0.5), p)))
		"ev", "oduncu", "camur_ocagi":
			var b := Building.new()
			b.setup("camur" if id == "camur_ocagi" else id)
			n.add_child(b)
			b.complete_now()
			b.set_ghost(false)
			for p in b.pieces:
				if p.tag in ["plinth", "ground"] and is_instance_valid(p.mesh):
					p.mesh.visible = false
		"portre": # (a settler's head and shoulders)
			var body := Townsfolk.new()
			n.add_child(body)
			var rng := RandomNumberGenerator.new()
			rng.seed = 12345
			body.build("man", rng)
			body.player.seek(0.0, true)
			n.set_meta("portrait", true)
	return n
