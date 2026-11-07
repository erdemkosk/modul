class_name EraDressing
extends Node3D
## What says the years of the war along the line, laid out from the railway and the station so it's
## the same on a loaded game: the telegraph poles beside the track every so often, two wires sagging
## between them, glass insulators on their crossarms; by the station the water tower the engines
## drink from (RailWorks), the semaphore signal before it, its arm down for the line clear, and a
## roadside icon post. (The poles, the semaphore and the shrine: Details, made in Blender.)

const POLE_EVERY := 150 ## rail points between poles (0.3 m each: 45 m)
const POLE_SIDE := 4.2 ## m off the track's middle
const POLE_H := 6.6

var village: Node


func build(v: Node, rail: PackedVector3Array, station: Node3D) -> void:
	village = v
	if rail.size() < POLE_EVERY * 2:
		return
	_telegraph(rail, station)
	if station:
		station_dress(rail, station)


## A station's water tower and semaphore, and an icon post by the line before it.
func station_dress(rail: PackedVector3Array, station: Node3D) -> void:
	_water_tower(rail, station)
	_semaphore(rail, station)
	_shrine(rail, station)


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


## A model put down at `xf` (in the world).
func _put(kind: String, xf: Transform3D, into: Node3D = null) -> void:
	var to := into if into else self
	Details.place(to, kind, to.global_transform.affine_inverse() * xf)


## The poles, every POLE_EVERY points, and the wires between them (a sag to each span): the poles
## baked into a few meshes.
func _telegraph(rail: PackedVector3Array, station: Node3D) -> void:
	var poles := Node3D.new()
	poles.name = "Poles"
	add_child(poles)
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
		_put("telegraph_pole", Transform3D(lean, foot), poles)
		var ends: Array = []
		for s in [-0.6, 0.6]:
			ends.append(foot + lean * Vector3(s, 6.05, 0))
		tops.append(ends)
	MeshBake.bake(poles)
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
	wire.albedo_color = Color(0.13, 0.12, 0.11)
	wire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = wire
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## The water tower (RailWorks': the train's own model): past the station along the line, across the
## track from it, its spout swung out over the track.
func _water_tower(rail: PackedVector3Array, station: Node3D) -> void:
	var k := mini(_k_of(rail, station.global_position) + 80, rail.size() - 10)
	var side := _away(rail, k, station)
	var c := _ground(rail[k] + side * 5.2)
	_clear(c, 3.5)
	RailWorks.water_tower(self, c, rail[k])


## The semaphore before the station: a tall post, the arm (red, a white band) lowered over the track
## for the line clear, its lamp under it, facing the trains coming in.
func _semaphore(rail: PackedVector3Array, station: Node3D) -> void:
	var k := maxi(_k_of(rail, station.global_position) - 110, 10)
	var side := _away(rail, k, station)
	var foot := _ground(rail[k] + side * 3.0)
	# (its -X, where the arm reaches, toward the track; its front along the line)
	var b := Basis(side, Vector3.UP, side.cross(Vector3.UP))
	_put("semaphore", Transform3D(b, foot))


## A roadside icon post by the line, a way before the station on its own side, facing the track.
func _shrine(rail: PackedVector3Array, station: Node3D) -> void:
	for back in [190, 230, 150, 270]:
		var k := maxi(_k_of(rail, station.global_position) - int(back), 10)
		var side := -_away(rail, k, station)
		var foot := _ground(rail[k] + side * 6.5)
		if not village.nav.is_ground_open(foot) or village.nav.on_road(foot):
			continue
		_clear(foot, 1.5)
		_put("shrine", Transform3D(Basis.looking_at(side, Vector3.UP), foot)) # (its face, +Z, to the track)
		return


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
