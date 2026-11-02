class_name EraDressing
extends Node3D
## What says the years of the war along the line, laid out from the railway and the station so it's
## the same on a loaded game: the telegraph poles beside the track every so often, two wires sagging
## between them, glass insulators on their crossarms; by the station the water tower the engines
## drink from (a stave tank on a timber trestle, its spout swung over the track) and the semaphore
## signal before it, its arm down for the line clear.

const POLE_EVERY := 150 ## rail points between poles (0.3 m each: 45 m)
const POLE_SIDE := 4.2 ## m off the track's middle
const POLE_H := 6.6

var village: Node
var _wood: StandardMaterial3D
var _dark: StandardMaterial3D


func build(v: Node, rail: PackedVector3Array, station: Node3D) -> void:
	village = v
	_wood = Building.material("wood")
	_dark = Building.material("dark")
	if rail.size() < POLE_EVERY * 2:
		return
	_telegraph(rail, station)
	if station:
		_water_tower(rail, station)
		_semaphore(rail, station)


## The side of the line away from the station (where the poles and the tower stand), at rail point k.
func _away(rail: PackedVector3Array, k: int, station: Node3D) -> Vector3:
	var dir := rail[mini(k + 3, rail.size() - 1)] - rail[maxi(k - 3, 0)]
	dir.y = 0.0
	var side := dir.normalized().cross(Vector3.UP)
	if station and side.dot(station.global_position - rail[k]) > 0.0:
		side = -side
	return side


func _ground(p: Vector3) -> Vector3:
	p.y = village.nav.height(p.x, p.z)
	return p


func _box(size: Vector3, mat: Material, xf: Transform3D) -> void:
	var m := BoxMesh.new()
	m.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	add_child(mi)
	mi.global_transform = xf


func _cyl(top: float, bottom: float, h: float, mat: Material, xf: Transform3D, sides := 10) -> void:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = sides
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	add_child(mi)
	mi.global_transform = xf


## The poles, every POLE_EVERY points, and the wires between them (a sag to each span).
func _telegraph(rail: PackedVector3Array, station: Node3D) -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.72, 0.62)
	glass.metallic = 0.2
	glass.roughness = 0.15
	var tops: Array = [] ## each pole's insulators (two), for the wires
	for k in range(POLE_EVERY / 2, rail.size() - 20, POLE_EVERY):
		var side := _away(rail, k, station)
		var foot := _ground(rail[k] + side * POLE_SIDE)
		if not village.nav.is_ground_open(foot):
			tops.append([])
			continue
		var dir := rail[mini(k + 3, rail.size() - 1)] - rail[maxi(k - 3, 0)]
		dir.y = 0.0
		var yaw := atan2(dir.x, dir.z)
		var lean := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, sin(k * 0.37) * 0.03) # (not quite plumb)
		_cyl(0.09, 0.12, POLE_H, _wood, Transform3D(lean, foot + lean * Vector3(0, POLE_H * 0.5 - 0.3, 0)), 7)
		var arm_c := foot + lean * Vector3(0, POLE_H - 0.75, 0)
		var across := lean * Vector3(1, 0, 0)
		_box(Vector3(1.5, 0.1, 0.1), _dark, Transform3D(lean, arm_c))
		var ends: Array = []
		for s in [-0.6, 0.6]:
			var at: Vector3 = arm_c + across * s + Vector3.UP * 0.12
			_cyl(0.035, 0.045, 0.14, glass, Transform3D(Basis.IDENTITY, at), 6)
			ends.append(at + Vector3.UP * 0.07)
		tops.append(ends)
	# the wires: a span between each pole and the next, sagging, drawn as thin lines
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in tops.size() - 1:
		var a: Array = tops[i]
		var b: Array = tops[i + 1]
		if a.is_empty() or b.is_empty():
			continue
		for w in 2:
			var p0: Vector3 = a[w]
			var p1: Vector3 = b[w]
			var sag := p0.distance_to(p1) * 0.025
			var prev := p0
			for j in range(1, 13):
				var t := j / 12.0
				var q := p0.lerp(p1, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)
				st.add_vertex(prev)
				st.add_vertex(q)
				prev = q
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.08, 0.08, 0.08)
	wire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = wire
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The water tower: past the station along the line, across the track from it.
func _water_tower(rail: PackedVector3Array, station: Node3D) -> void:
	var k := mini(_k_of(rail, station.global_position) + 80, rail.size() - 10)
	var side := _away(rail, k, station)
	var c := _ground(rail[k] + side * 5.2)
	_clear(c, 3.5)
	var dir := rail[mini(k + 3, rail.size() - 1)] - rail[maxi(k - 3, 0)]
	dir.y = 0.0
	var b := Basis(Vector3.UP, atan2(dir.x, dir.z))
	var legs_h := 5.2
	# the trestle: four legs, braced across
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var foot := c + b * Vector3(sx * 1.3, 0, sz * 1.3)
			_box(Vector3(0.24, legs_h, 0.24), _dark, Transform3D(b, foot + Vector3.UP * (legs_h * 0.5 - 0.2)))
	for h in [1.6, 3.6]:
		for sx in [-1.0, 1.0]:
			_box(Vector3(0.12, 0.12, 2.8), _wood, Transform3D(b, c + b * Vector3(sx * 1.3, h, 0)))
			_box(Vector3(2.8, 0.12, 0.12), _wood, Transform3D(b, c + b * Vector3(0, h + 0.3, sx * 1.3)))
	# the tank: staves, iron hoops, a conical roof with a vent
	var staves := Building.material("plank")
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.16, 0.15, 0.14)
	iron.metallic = 0.6
	iron.roughness = 0.5
	var tank_y := legs_h + 1.3
	_box(Vector3(3.2, 0.2, 3.2), _dark, Transform3D(b, c + Vector3.UP * (legs_h - 0.1)))
	_cyl(1.65, 1.75, 2.6, staves, Transform3D(Basis.IDENTITY, c + Vector3.UP * tank_y), 16)
	for h in [-0.9, 0.0, 0.9]:
		_cyl(1.74, 1.78, 0.08, iron, Transform3D(Basis.IDENTITY, c + Vector3.UP * (tank_y + h)), 16)
	_cyl(0.0, 1.95, 1.0, Building.material("shingle"), Transform3D(Basis.IDENTITY, c + Vector3.UP * (tank_y + 1.8)), 16)
	_cyl(0.12, 0.12, 0.4, iron, Transform3D(Basis.IDENTITY, c + Vector3.UP * (tank_y + 2.4)), 8)
	# the spout, swung out over the track, and its chain
	var spout_at := c + b * Vector3(0, 0, 0) + Vector3.UP * (tank_y - 0.6) - side * 1.6
	var spout_b := Basis.looking_at(-side, Vector3.UP) * Basis(Vector3.RIGHT, -0.35)
	_cyl(0.16, 0.16, 2.4, iron, Transform3D(spout_b * Basis(Vector3.RIGHT, PI * 0.5), spout_at - side * 1.0), 8)
	# a ladder up a leg
	var lad := c + b * Vector3(1.3, 0, 1.55)
	for s in [-0.22, 0.22]:
		_box(Vector3(0.05, legs_h + 1.6, 0.05), _wood, Transform3D(b, lad + b * Vector3(s, 0, 0) + Vector3.UP * ((legs_h + 1.6) * 0.5)))
	for r in 12:
		_box(Vector3(0.44, 0.04, 0.04), _wood, Transform3D(b, lad + Vector3.UP * (0.4 + r * 0.55)))


## The semaphore before the station: a tall post, the arm (red, a white band) down for the line clear,
## its lamp below.
func _semaphore(rail: PackedVector3Array, station: Node3D) -> void:
	var k := maxi(_k_of(rail, station.global_position) - 110, 10)
	var side := _away(rail, k, station)
	var foot := _ground(rail[k] + side * 3.0)
	var dir := rail[mini(k + 3, rail.size() - 1)] - rail[maxi(k - 3, 0)]
	dir.y = 0.0
	var b := Basis(Vector3.UP, atan2(dir.x, dir.z))
	_box(Vector3(0.2, 7.0, 0.2), _dark, Transform3D(b, foot + Vector3.UP * 3.3))
	_box(Vector3(0.4, 0.4, 0.4), _dark, Transform3D(b, foot + Vector3.UP * 7.0))
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.62, 0.12, 0.08)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.86, 0.84, 0.78)
	var arm := b * Basis(Vector3.BACK, -0.6) # (lowered: the line clear)
	var pivot := foot + Vector3.UP * 6.4 - side * 0.15
	_box(Vector3(1.6, 0.26, 0.05), red, Transform3D(arm, pivot + arm * Vector3(-0.8, 0, 0) - side * 0.05))
	_box(Vector3(0.18, 0.27, 0.06), white, Transform3D(arm, pivot + arm * Vector3(-1.2, 0, 0) - side * 0.06))
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(0.3, 0.8, 0.4)
	lamp.emission_enabled = true
	lamp.emission = Color(0.3, 0.9, 0.4)
	lamp.emission_energy_multiplier = 1.5
	_box(Vector3(0.3, 0.4, 0.3), _dark, Transform3D(b, foot + Vector3.UP * 5.6))
	_cyl(0.08, 0.08, 0.05, lamp, Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * b, foot + Vector3.UP * 5.65 - side * 0.17), 8)
	# a ladder up the post
	for r in 10:
		_box(Vector3(0.3, 0.03, 0.03), _wood, Transform3D(b, foot + Vector3.UP * (0.5 + r * 0.55) + side * 0.12))


func _k_of(rail: PackedVector3Array, p: Vector3) -> int:
	var best := 0
	var bd := INF
	for k in range(0, rail.size(), 4):
		var d := Vector2(rail[k].x - p.x, rail[k].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = k
	return best


## The trees where something's put up felled (their stumps left).
func _clear(at: Vector3, r: float) -> void:
	for i in village._props_in(at, r + 2.0):
		var info: Dictionary = village.props.prop_info(i)
		if str(info.kind) != "cliff" and Vector2(info.origin.x - at.x, info.origin.z - at.z).length() < r:
			village.props.cut_tree(i)
