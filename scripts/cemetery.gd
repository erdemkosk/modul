class_name Cemetery
extends Node3D
## Where the town's dead are laid: a plot fenced off a way out from the town, the first time someone
## dies, and a grave dug in it for each one after (a mound of earth, a three-barred wooden cross, the
## name on a board). Those who knew them come out to stand at it a while, and go back easier for it.

const ROWS := 5 ## graves to a row
const GAP := Vector2(1.8, 2.6) ## m between graves, along a row and between rows

var village: Node
var graves: Array = [] ## [name, day]
var _plot := Vector3.INF
var _yaw := 0.0
var _fence: Node3D


func _ready() -> void:
	name = "Cemetery"


## The plot's corner and its way: out from the store, away from the line, on open ground.
func _site() -> bool:
	if _plot != Vector3.INF:
		return true
	var stores: Array = village.stores()
	if stores.is_empty():
		return false
	var home: Vector3 = (stores[0] as Node3D).global_position
	var away := Vector3.RIGHT
	if village.rail.size() > 1:
		away = home - village.rail[village.rail.size() - 1]
		away.y = 0.0
		away = away.normalized() if away.length() > 1.0 else Vector3.RIGHT
	for k in 60:
		var a := atan2(away.z, away.x) + randf_range(-1.2, 1.2)
		var p := home + Vector3(cos(a), 0, sin(a)) * randf_range(38.0, 55.0)
		var ok := true
		for q in [Vector3.ZERO, Vector3(8, 0, 0), Vector3(0, 0, 10), Vector3(8, 0, 10), Vector3(4, 0, 5)]:
			if not village.nav.is_ground_open(p + Basis(Vector3.UP, a) * q):
				ok = false
				break
		if ok:
			_plot = p
			_yaw = a
			_clear()
			return true
	return false


func _clear() -> void:
	var c := _plot + Basis(Vector3.UP, _yaw) * Vector3(4.5, 0, 6.0)
	for i in village._props_in(c, 12.0):
		var info: Dictionary = village.props.prop_info(i)
		if str(info.kind) != "cliff" and Vector2(info.origin.x - c.x, info.origin.z - c.z).length() < 9.0:
			village.props.cut_tree(i)


func _slot(i: int) -> Vector3:
	var p := _plot + Basis(Vector3.UP, _yaw) * Vector3(1.2 + (i % ROWS) * GAP.x, 0, 1.4 + (i / ROWS) * GAP.y)
	p.y = village.ground_at(p)
	return p


## A grave for `who` (laid out, not walked to: on a loaded game too).
func lay(who: String, day: int) -> Vector3:
	if not _site():
		return Vector3.INF
	graves.append([who, day])
	var at := _slot(graves.size() - 1)
	_grave(at, who)
	_fence_round()
	return at


## Someone of the town dead: their grave, and the mourners out to it (not while there's fighting).
func bury(v: Villager) -> void:
	var at := lay(v.display_name, int(village.day))
	if at == Vector3.INF:
		return
	village.message.emit("%s mezarlığa gömüldü." % v.display_name, "info")
	Ambience.funeral(at)
	if village.raids and village.raids.active:
		return
	var n := 0
	for o: Villager in village.villagers:
		if o.dead or o.down or o.is_child or o.drafted or o.sleeping or o.leaving:
			continue
		if o.family != v.family and (n >= 3 or not (o.plan.is_empty() or o.idle)):
			continue
		var spot := at + Basis(Vector3.UP, _yaw) * Vector3(randf_range(-1.6, 1.6), 0, -1.6 - randf_range(0.0, 1.0))
		spot.y = village.ground_at(spot)
		o.abort()
		var close := o.family == v.family
		o.give([{"t": "go", "to": spot}, {"t": "work", "time": randf_range(14.0, 22.0), "anim": "idle", "face": at},
			{"t": "do", "f": func() -> bool:
				o.think("funeral", "%s cenazesine katıldı" % v.display_name.split(" ")[0], 6.0 if close else 3.0, maxf(village.weather.day_length_minutes * 60.0, 60.0))
				return true}], "Cenazede")
		if not close:
			n += 1


func _grave(at: Vector3, who: String) -> void:
	var b := Basis(Vector3.UP, _yaw)
	var earth := StandardMaterial3D.new()
	earth.albedo_color = Color(0.25, 0.19, 0.13)
	earth.roughness = 1.0
	var wood := Building.material("dark")
	var mound := MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.5
	mm.height = 0.35
	mm.radial_segments = 10
	mm.rings = 4
	mound.mesh = mm
	mound.material_override = earth
	add_child(mound)
	mound.global_transform = Transform3D(b * Basis.from_scale(Vector3(1.0, 1.0, 2.0)), at + Vector3.UP * 0.05)
	# the cross at its head: the upright, the long bar, the short one above, the slanted foot-bar
	var head := at + b * Vector3(0, 0, 1.2)
	for part: Array in [[Vector3(0.09, 1.5, 0.09), Vector3(0, 0.75, 0), 0.0], [Vector3(0.7, 0.08, 0.08), Vector3(0, 1.1, 0), 0.0],
			[Vector3(0.36, 0.07, 0.07), Vector3(0, 1.32, 0), 0.0], [Vector3(0.42, 0.07, 0.07), Vector3(0, 0.45, 0), 0.35]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[0]
		mi.mesh = bm
		mi.material_override = wood
		add_child(mi)
		mi.global_transform = Transform3D(b * Basis(Vector3.BACK, float(part[2])), head + b * (part[1] as Vector3))
	var tag := Label3D.new()
	tag.text = "%s\n1918" % who
	tag.font_size = 20
	tag.pixel_size = 0.004
	tag.modulate = Color(0.85, 0.8, 0.7)
	tag.outline_size = 4
	tag.visibility_range_end = 25.0
	add_child(tag)
	tag.global_transform = Transform3D(b, head + b * Vector3(0, 0.85, -0.06))


## A low rail fence round the plot, as big as the rows it holds (drawn again as it grows).
func _fence_round() -> void:
	if _fence:
		_fence.queue_free()
	_fence = Node3D.new()
	add_child(_fence)
	var rows := maxi(2, ceili((graves.size() + 1) / float(ROWS)) + 1)
	var w := ROWS * GAP.x + 0.6
	var d := rows * GAP.y + 0.6
	var b := Basis(Vector3.UP, _yaw)
	var wood := Building.material("wood")
	var corners := [Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, d), Vector3(0, 0, d)]
	for e in 4:
		var a: Vector3 = corners[e]
		var c: Vector3 = corners[(e + 1) % 4]
		var n := maxi(1, int(a.distance_to(c) / 2.0))
		for k in n + 1:
			if e == 0 and k == n / 2:
				continue # (the gap to walk in by)
			var p := _plot + b * a.lerp(c, float(k) / n)
			p.y = village.ground_at(p)
			var post := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(0.1, 1.0, 0.1)
			post.mesh = pm
			post.material_override = wood
			_fence.add_child(post)
			post.global_position = p + Vector3.UP * 0.5
			if k < n and not (e == 0 and (k == n / 2 or k + 1 == n / 2)):
				var q := _plot + b * a.lerp(c, float(k + 1) / n)
				q.y = village.ground_at(q)
				for h in [0.45, 0.85]:
					var rail := MeshInstance3D.new()
					var rm := BoxMesh.new()
					rm.size = Vector3(0.05, 0.07, p.distance_to(q))
					rail.mesh = rm
					rail.material_override = wood
					_fence.add_child(rail)
					rail.global_position = (p + q) * 0.5 + Vector3.UP * h
					rail.look_at(q + Vector3.UP * h, Vector3.UP)
