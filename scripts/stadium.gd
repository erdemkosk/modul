class_name Stadium
extends Node3D
## ARENA's stadium: Prototip Deneme Sahası 07, where machines are tried out to destruction before a
## paying crowd. A square bowl all the way round the yard's wall (its corners closed): a lower tier
## of LOWER rows from just over the wall, a concourse, an upper tier of UPPER steeper rows, and a
## roof over the upper tier on its back wall, an LED strip and floodlights along the roof's front
## edge. Seats in each side's colours, aisles every AISLE m; along the front of the lower tier a
## band of hazard stripes and LED panels.
##
## The crowd's a MultiMesh of plain figures a side and a tier (so what's off the screen isn't drawn)
## in crowd.gdshader: sat swaying, up on their feet with their arms going with `set_excite`.
##
## Two LED screens stand on the roof's front edge, north and south, facing in: what `board` is given
## (the trial's number, its time, the machines left, the crowd's mood) drawn into a SubViewport and
## shown through led_screen.gdshader as diodes.

const R0 := 71.05 ## m from the middle the front of the bowl is (just behind the yard's wall)
const FRONT_H := 5.6 ## m up the first row is
const DEPTH := 0.85 ## m a row
const LOWER := 22
const LOWER_RISE := 0.42
const CONCOURSE := 3.2
const UPPER := 16
const UPPER_RISE := 0.62
const ROOF_H := 33.0
const ROOF_FROM := 84.0 ## m out the roof's front edge is
const AISLE := 14.0
const SEAT_GAP := 0.6
const SHIRTS := [Color(0.7, 0.15, 0.12), Color(0.15, 0.3, 0.65), Color(0.85, 0.75, 0.2), Color(0.2, 0.45, 0.25),
	Color(0.9, 0.9, 0.88), Color(0.15, 0.15, 0.17), Color(0.85, 0.45, 0.15), Color(0.45, 0.25, 0.5)]
const SEATS := [Color(0.62, 0.25, 0.08), Color(0.1, 0.32, 0.4), Color(0.62, 0.25, 0.08), Color(0.1, 0.32, 0.4)]
const LAYER := 2 ## (its render layer: the yard's floodlights leave it out)
const SIDE_SHIRT := [Color(0.95, 0.45, 0.1), Color(0.1, 0.7, 0.8), Color(0.95, 0.45, 0.1), Color(0.1, 0.7, 0.8)]

var terrain: Node
var crowd_mat: ShaderMaterial
var people := 0
var _view: SubViewport
var _lines: Array[Label] = []
var _bar: ColorRect
var _bar_back: ColorRect
var _led_mat: StandardMaterial3D
var _strip_mat: StandardMaterial3D
var _bowl_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("stadium")
	_bowl()
	_crowd()
	_screens()


static func lower_h(row: int) -> float:
	return FRONT_H + row * LOWER_RISE


static func upper_r0() -> float:
	return R0 + LOWER * DEPTH + CONCOURSE


static func upper_h(row: int) -> float:
	return lower_h(LOWER - 1) + 2.6 + row * UPPER_RISE


# --- The concrete ------------------------------------------------------------------------------------

## A side's frame: side 0 on +z, its rows running along x, out from the middle along +z.
static func _side(s: int) -> Basis:
	return Basis(Vector3.UP, s * PI * 0.5)


## Square-ring pieces into `st` (all four sides, mitred at the corners): a flat ring between r0 and
## r1 at height h ...
func _top(st: SurfaceTool, r0: float, r1: float, h: float, c: Color, up := true) -> void:
	for s in 4:
		var b := _side(s)
		_quad(st, [b * Vector3(-r0, h, r0), b * Vector3(r0, h, r0), b * Vector3(r1, h, r1), b * Vector3(-r1, h, r1)],
			Vector3.UP if up else Vector3.DOWN, c)


## ... and an upright ring at r from h0 to h1 (facing in, or out).
func _riser(st: SurfaceTool, r: float, h0: float, h1: float, c: Color, inward := true) -> void:
	for s in 4:
		var b := _side(s)
		_quad(st, [b * Vector3(-r, h0, r), b * Vector3(r, h0, r), b * Vector3(r, h1, r), b * Vector3(-r, h1, r)],
			b * (Vector3.FORWARD if inward else Vector3.BACK), c)


func _quad(st: SurfaceTool, v: Array, n: Vector3, c: Color) -> void:
	st.set_normal(n)
	st.set_color(c)
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(v[i])


## A box into `st` (in `xf`), its colour `c`.
func _box(st: SurfaceTool, xf: Transform3D, size: Vector3, c: Color) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, [Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)]],
		[Vector3.LEFT, [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)]],
		[Vector3.UP, [Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3.DOWN, [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)]],
		[Vector3.BACK, [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]],
		[Vector3.FORWARD, [Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)]],
	]
	for f: Array in faces:
		var vs: Array = []
		for p: Vector3 in f[1]:
			vs.append(xf * p)
		_quad(st, vs, xf.basis * (f[0] as Vector3), c)


func _mesh(st: SurfaceTool, mat: Material, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = LAYER
	add_child(mi)
	return mi


static func _vmat(rough := 0.92) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _bowl() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var conc := Color(0.46, 0.46, 0.45)
	var dark := Color(0.2, 0.2, 0.21)
	var steel := Color(0.3, 0.31, 0.33)
	# the front: a wall up from the ground to the first row
	_riser(st, R0, 0.0, FRONT_H + 0.9, conc)
	_top(st, R0, R0 + 0.3, FRONT_H + 0.9, conc)
	_riser(st, R0 + 0.3, FRONT_H, FRONT_H + 0.9, conc)
	# the lower tier's rows
	for row in LOWER:
		var r := R0 + row * DEPTH
		var h := lower_h(row)
		if row > 0:
			_riser(st, r, lower_h(row - 1), h, conc)
		_top(st, r, r + DEPTH, h, conc.darkened(0.05 * (row % 2)))
	# the concourse, the wall up to the upper tier (its ways in dark)
	var rc := R0 + LOWER * DEPTH
	_top(st, rc, rc + CONCOURSE, lower_h(LOWER - 1), Color(0.4, 0.4, 0.39))
	var ru := upper_r0()
	_riser(st, ru, lower_h(LOWER - 1), upper_h(0), conc)
	for row in UPPER:
		var r := ru + row * DEPTH
		var h := upper_h(row)
		if row > 0:
			_riser(st, r, upper_h(row - 1), h, conc)
		_top(st, r, r + DEPTH, h, conc.darkened(0.05 * (row % 2)))
	# the back wall up to the roof, the outside of it
	var rb := ru + UPPER * DEPTH
	_riser(st, rb, upper_h(UPPER - 1), ROOF_H, conc.darkened(0.15))
	_riser(st, rb + 1.0, 0.0, ROOF_H + 1.4, conc.darkened(0.1), false)
	# the roof: its underside, its top, its front beam
	_top(st, ROOF_FROM, rb + 1.0, ROOF_H, steel.darkened(0.3), false)
	_top(st, ROOF_FROM, rb + 1.0, ROOF_H + 1.4, steel)
	_riser(st, ROOF_FROM, ROOF_H - 0.9, ROOF_H + 1.4, steel.darkened(0.2))
	for s in 4:
		var b := _side(s)
		# the ways in from the concourse, and the roof's trusses over the upper tier
		var t := -rc + AISLE * 0.5
		while t < rc:
			_box(st, Transform3D(b, b * Vector3(t, lower_h(LOWER - 1) + 1.2, ru - 0.02)), Vector3(3.0, 2.4, 0.05), dark)
			t += AISLE * 2.0
		t = -rb + 8.0
		while t < rb - 4.0:
			var a := Vector3(t, ROOF_H - 0.4, ROOF_FROM + 0.4)
			var z := Vector3(t, upper_h(UPPER - 1) + 1.0, rb - 0.4)
			var mid := (a + z) * 0.5
			var along := (a - z).normalized()
			var xf := Transform3D(Basis(Vector3.RIGHT, atan2(-along.y, along.z)), mid)
			_box(st, Transform3D(b, Vector3.ZERO) * xf, Vector3(0.45, 0.6, a.distance_to(z)), steel)
			_box(st, Transform3D(b, b * Vector3(t, ROOF_H - 0.5, (ROOF_FROM + rb) * 0.5)), Vector3(0.4, 0.5, rb - ROOF_FROM), steel)
			t += 12.0
		# aisles: the steps' edges painted, a handrail down them
		t = -R0 + AISLE * 0.5
		while t < R0:
			for row in LOWER:
				var r := R0 + row * DEPTH
				_box(st, Transform3D(b, b * Vector3(t, lower_h(row) + 0.01, r + 0.06)), Vector3(1.2, 0.03, 0.1), Color(0.85, 0.7, 0.15))
			t += AISLE
	_bowl_mat = _vmat()
	_mesh(st, _bowl_mat)
	# the seats: a row of backs and pans each row, a side's colour (the upper tier a shade darker)
	var ss := SurfaceTool.new()
	ss.begin(Mesh.PRIMITIVE_TRIANGLES)
	for tier in 2:
		for row in (LOWER if tier == 0 else UPPER):
			var r := (R0 if tier == 0 else upper_r0()) + row * DEPTH
			var h := lower_h(row) if tier == 0 else upper_h(row)
			for s in 4:
				var b := _side(s)
				var c: Color = SEATS[s].darkened(0.25 * tier)
				_quad(ss, [b * Vector3(-r - 0.7, h + 0.42, r + 0.7), b * Vector3(r + 0.7, h + 0.42, r + 0.7),
					b * Vector3(r + 0.7, h + 0.86, r + 0.74), b * Vector3(-r - 0.7, h + 0.86, r + 0.74)], b * Vector3.FORWARD, c)
				_quad(ss, [b * Vector3(-r - 0.3, h + 0.4, r + 0.3), b * Vector3(r + 0.3, h + 0.4, r + 0.3),
					b * Vector3(r + 0.7, h + 0.42, r + 0.7), b * Vector3(-r - 0.7, h + 0.42, r + 0.7)], Vector3.UP, c)
	_mesh(ss, _vmat(0.5), false)
	# the front band: hazard stripes, LED panels between; the roof's LED strip and its lamps
	var hz := SurfaceTool.new()
	hz.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in 4:
		var b := _side(s)
		var t := -R0
		var k := 0
		while t < R0 - 0.5:
			var c := Color(0.85, 0.6, 0.05) if k % 2 == 0 else Color(0.06, 0.06, 0.06)
			_box(hz, Transform3D(b, b * Vector3(t + 0.5, 4.75, R0 - 0.03)), Vector3(1.0, 0.5, 0.04), c)
			t += 1.0
			k += 1
	_mesh(hz, _vmat(0.6), false)
	_strip_mat = StandardMaterial3D.new()
	_strip_mat.albedo_color = Color(0.05, 0.07, 0.08)
	_strip_mat.emission_enabled = true
	_strip_mat.emission = Color(0.35, 0.9, 1.0)
	_strip_mat.emission_energy_multiplier = 1.2
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(0.9, 0.92, 0.95)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(1.0, 0.97, 0.9)
	_led_mat.emission_energy_multiplier = 0.4
	var strip := SurfaceTool.new()
	strip.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lamps := SurfaceTool.new()
	lamps.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in 4:
		var b := _side(s)
		# a cyan line along the roof's beam and along the lower tier's front
		_box(strip, Transform3D(b, b * Vector3(0.0, ROOF_H - 0.95, ROOF_FROM - 0.05)), Vector3(ROOF_FROM * 2.0, 0.12, 0.06), Color.WHITE)
		_box(strip, Transform3D(b, b * Vector3(0.0, FRONT_H + 0.88, R0 - 0.03)), Vector3(R0 * 2.0, 0.08, 0.05), Color.WHITE)
		# LED panels on the front between the stripes and the parapet
		var t := -R0 + 6.0
		while t < R0 - 6.0:
			_box(strip, Transform3D(b, b * Vector3(t, 5.55, R0 - 0.03)), Vector3(9.0, 0.5, 0.05), Color.WHITE)
			t += 14.0
		# the floodlights: banks under the beam
		t = -ROOF_FROM + 5.0
		while t < ROOF_FROM - 4.0:
			var xf := Transform3D(b * Basis(Vector3.RIGHT, -0.5), b * Vector3(t, ROOF_H - 1.35, ROOF_FROM + 0.6))
			_box(lamps, xf, Vector3(2.2, 0.7, 0.3), Color.WHITE)
			t += 7.0
	_mesh(strip, _strip_mat, false)
	_mesh(lamps, _led_mat, false)


## Night: the floodlights and the LED strips up.
func set_night(on: bool) -> void:
	_led_mat.emission_energy_multiplier = 9.0 if on else 0.4
	_strip_mat.emission_energy_multiplier = 4.0 if on else 1.2
	crowd_mat.set_shader_parameter("lit", 0.22 if on else 0.0) # (the spill of the lights on them)
	_bowl_mat.emission_enabled = on
	_bowl_mat.emission = Color(0.06, 0.065, 0.07)


# --- The people --------------------------------------------------------------------------------------

func _crowd() -> void:
	crowd_mat = ShaderMaterial.new()
	crowd_mat.shader = preload("res://shaders/crowd.gdshader")
	var fig := _figure()
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for tier in 2:
		for s in 4:
			var b := _side(s)
			var xfs: Array[Transform3D] = []
			var cols: Array[Color] = []
			for row in (LOWER if tier == 0 else UPPER):
				var r := (R0 if tier == 0 else upper_r0()) + row * DEPTH
				var h := lower_h(row) if tier == 0 else upper_h(row)
				var fill := 0.86 if tier == 0 else 0.74
				var t := -r + 0.5
				while t < r - 0.5:
					var into := fposmod(t, AISLE)
					var empty_patch := sin(t * 0.11 + s * 2.1 + row * 0.07 + tier) * 0.5 + 0.5 # (clumps of empty seats)
					if absf(into - AISLE * 0.5) > 0.75 and rng.randf() < fill * (0.7 + 0.3 * empty_patch):
						var at := b * Vector3(t + rng.randf_range(-0.06, 0.06), h + 0.42, r + 0.42)
						xfs.append(Transform3D(b * Basis(Vector3.UP, rng.randf_range(-0.2, 0.2)), at))
						var c: Color = SIDE_SHIRT[s] if rng.randf() < 0.3 else SHIRTS[rng.randi() % SHIRTS.size()]
						cols.append(c.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.15))
					t += SEAT_GAP
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = fig
			mm.instance_count = xfs.size()
			for i in xfs.size():
				mm.set_instance_transform(i, xfs[i])
				mm.set_instance_color(i, cols[i])
				mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), 0, 0))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = crowd_mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.layers = LAYER
			add_child(mmi)
			people += xfs.size()


## A plain sat figure for a crowd seen from far (as CageArena's, in boxes, without its shins): the
## parts told in UV for crowd.gdshader.
static func _figure() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var parts := [
		[Vector3(0.34, 0.5, 0.22), Vector3(0, 0.3, 0.02), 0.0, 0.0],
		[Vector3(0.3, 0.13, 0.42), Vector3(0, 0.08, -0.17), 0.25, 0.0],
		[Vector3(0.19, 0.22, 0.2), Vector3(0, 0.67, 0.0), 0.5, 0.0],
		[Vector3(0.1, 0.44, 0.1), Vector3(-0.21, 0.26, 0.0), 1.0, 0.0],
		[Vector3(0.1, 0.44, 0.1), Vector3(0.21, 0.26, 0.0), 1.0, 1.0],
	]
	for e: Array in parts:
		var bm := BoxMesh.new()
		bm.size = e[0]
		var arr: Array = bm.surface_get_arrays(0)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for j in idx:
			st.set_normal(ns[j])
			st.set_uv(Vector2(float(e[2]), float(e[3])))
			st.set_color(Color.WHITE)
			st.add_vertex(vs[j] + (e[1] as Vector3))
	st.index()
	return st.commit()


## The audience: 0 sat .. 1 on their feet.
func set_excite(v: float) -> void:
	crowd_mat.set_shader_parameter("excite", clampf(v, 0.0, 1.0))


# --- The screens -------------------------------------------------------------------------------------

const BOARD := Vector2(26.0, 10.0) ## m

func _screens() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1024, 394)
	_view.transparent_bg = false
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_view)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.size = Vector2(_view.size)
	_view.add_child(bg)
	var font := Ui.font("digital")
	var specs := [[Vector2(30, 8), 54, Color(0.35, 0.9, 1.0)], [Vector2(30, 62), 160, Color(1.0, 0.62, 0.15)],
		[Vector2(30, 232), 58, Color(0.9, 0.92, 0.95)], [Vector2(30, 292), 50, Color(0.35, 0.9, 1.0)]]
	for sp: Array in specs:
		var l := Label.new()
		l.position = sp[0]
		l.size = Vector2(964, 10)
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", sp[1])
		l.add_theme_color_override("font_color", sp[2])
		_view.add_child(l)
		_lines.append(l)
	_bar_back = ColorRect.new()
	_bar_back.color = Color(0.12, 0.14, 0.16)
	_bar_back.position = Vector2(30, 356)
	_bar_back.size = Vector2(964, 24)
	_view.add_child(_bar_back)
	_bar = ColorRect.new()
	_bar.position = _bar_back.position
	_bar.size = Vector2(0, 24)
	_view.add_child(_bar)
	var led := ShaderMaterial.new()
	led.shader = preload("res://shaders/led_screen.gdshader")
	led.set_shader_parameter("screen", _view.get_texture())
	led.set_shader_parameter("cells", Vector2(390.0, 150.0))
	var frame := _vmat(0.6)
	for s: int in [0, 2]:
		var b := _side(s)
		var at := b * Vector3(0.0, ROOF_H + 1.4 + BOARD.y * 0.5 + 0.8, ROOF_FROM + 2.0)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_box(st, Transform3D(b, at + b * Vector3(0, 0, 0.6)), Vector3(BOARD.x + 1.2, BOARD.y + 1.2, 1.0), Color(0.08, 0.08, 0.09))
		for k: float in [-1.0, 1.0]:
			_box(st, Transform3D(b, b * Vector3(k * BOARD.x * 0.3, ROOF_H + 1.4 + 0.4, ROOF_FROM + 2.6)), Vector3(0.6, 1.6, 0.6), Color(0.2, 0.2, 0.22))
		_mesh(st, frame)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = BOARD
		q.mesh = qm
		q.material_override = led
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		q.layers = LAYER
		q.transform = Transform3D(b * Basis(Vector3.UP, PI), at) # (its face in, toward the middle)
		add_child(q)
	board(["PROTOTİP DENEME SAHASI 07", "HAZIRLIK", "", ""], 0.0, Color(0.35, 0.9, 1.0))


## The screens' lines: [what's on, the big line, a line under it, a line at the foot], the bar.
func board(lines: Array, bar: float, bar_color: Color) -> void:
	var changed := false
	for i in mini(lines.size(), _lines.size()):
		if _lines[i].text != str(lines[i]):
			_lines[i].text = str(lines[i])
			changed = true
	var w := _bar_back.size.x * clampf(bar, 0.0, 1.0)
	if absf(_bar.size.x - w) > 4.0 or _bar.color != bar_color:
		_bar.size.x = w
		_bar.color = bar_color
		changed = true
	if changed:
		_view.render_target_update_mode = SubViewport.UPDATE_ONCE


func line(i: int) -> String:
	return _lines[i].text
