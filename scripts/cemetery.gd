class_name Cemetery
extends Node3D
## Where the town's dead are laid: a plot fenced off a way out from the town, the first time someone
## dies, and a grave dug in it for each one after (a mound of earth, a three-barred wooden cross, the
## name on a board; the models: Details grave_mound, cross_a/_b, headstone, fence_post...).
## Those who knew them come out to stand at it a while, and go back easier for it.

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
	var who := v.display_name # (the dead are freed soon: what's needed of them, kept now)
	var first := who.split(" ")[0]
	var fam := v.family
	village.message.emit("%s mezarlığa gömüldü." % who, "info")
	Ambience.funeral(at)
	if village.raids and village.raids.active:
		return
	var n := 0
	for o: Villager in village.villagers:
		if o.dead or o.down or o.is_child or o.drafted or o.sleeping or o.leaving:
			continue
		if o.family != fam and (n >= 3 or not (o.plan.is_empty() or o.idle)):
			continue
		var spot := at + Basis(Vector3.UP, _yaw) * Vector3(randf_range(-1.6, 1.6), 0, -1.6 - randf_range(0.0, 1.0))
		spot.y = village.ground_at(spot)
		o.abort()
		var close := o.family == fam
		o.give([{"t": "go", "to": spot}, {"t": "work", "time": randf_range(14.0, 22.0), "anim": "idle", "face": at},
			{"t": "do", "f": func() -> bool:
				o.think("funeral", "%s cenazesine katıldı" % first, 6.0 if close else 3.0, maxf(village.weather.day_length_minutes * 60.0, 60.0))
				return true}], "Cenazede")
		if not close:
			n += 1


func _grave(at: Vector3, who: String) -> void:
	var b := Basis(Vector3.UP, _yaw)
	var i := graves.size() - 1
	var h := fposmod(sin(i * 12.9898 + _yaw * 7.0) * 43758.5453, 1.0)
	_put("grave_mound", Transform3D(b * Basis(Vector3.UP, (h - 0.5) * 0.08), at))
	# at its head: a three-barred cross, now and then one with a little roof, or a rough stone
	var head := at + b * Vector3(0, 0, 1.2)
	head.y = village.ground_at(head)
	var mark := "cross_a" if h < 0.6 else ("cross_b" if h < 0.85 else "headstone")
	var lean := Basis(Vector3.BACK, (h - 0.5) * 0.06)
	_put(mark, Transform3D(b * lean, head)) # (its face, the model's -z, to the grave)
	var tag := Label3D.new()
	tag.text = "%s\n1918" % who
	tag.font_size = 20
	tag.pixel_size = 0.004
	tag.modulate = Color(0.85, 0.8, 0.7)
	tag.outline_size = 4
	tag.visibility_range_end = 25.0
	add_child(tag)
	tag.global_transform = Transform3D(b * Basis(Vector3.UP, PI), head + b * Vector3(0, 0.82 if mark != "headstone" else 0.5, -0.1))


## A model put down at `xf` (in the world) under `into` (or the plot itself).
func _put(kind: String, xf: Transform3D, into: Node3D = null) -> void:
	var to := into if into else self
	Details.place(to, kind, to.global_transform.affine_inverse() * xf)


## A low rail fence round the plot, as big as the rows it holds (drawn again as it grows): squared
## posts down into the ground, split rails between them, a roofed gateway with a cross on it.
func _fence_round() -> void:
	if _fence:
		_fence.queue_free()
	_fence = Node3D.new()
	add_child(_fence)
	var rows := maxi(2, ceili((graves.size() + 1) / float(ROWS)) + 1)
	var w := ROWS * GAP.x + 0.6
	var d := rows * GAP.y + 0.6
	var b := Basis(Vector3.UP, _yaw)
	var corners := [Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, 0, d), Vector3(0, 0, d)]
	for e in 4:
		var a: Vector3 = corners[e]
		var c: Vector3 = corners[(e + 1) % 4]
		var n := maxi(1, int(a.distance_to(c) / 2.0))
		if e == 0:
			# the gateway, over the gap left in the first side
			var g0 := _plot + b * a.lerp(c, float(n / 2 - 1) / n)
			var g1 := _plot + b * a.lerp(c, float(n / 2 + 1) / n)
			var mid := (g0 + g1) * 0.5
			mid.y = minf(village.ground_at(g0), village.ground_at(g1))
			var gw := Vector2(g1.x - g0.x, g1.z - g0.z).length()
			_put("cemetery_gate", Transform3D(b.scaled(Vector3(gw / 3.6, 1, 1)), mid), _fence)
		for k in n + 1:
			var p := _plot + b * a.lerp(c, float(k) / n)
			p.y = village.ground_at(p)
			var h := fposmod(sin((e * 31 + k) * 7.13) * 917.3, 1.0)
			if not (e == 0 and absi(k - n / 2) <= 1): # (the gateway's posts stand there, and the gap between)
				_put("fence_post", Transform3D(b * Basis(Vector3.UP, (h - 0.5) * 0.3), p), _fence)
			if k < n and not (e == 0 and (k == n / 2 - 1 or k == n / 2)):
				var q := _plot + b * a.lerp(c, float(k + 1) / n)
				q.y = village.ground_at(q)
				for hgt in [0.45, 0.85]:
					var from: Vector3 = p + Vector3.UP * (float(hgt) + (h - 0.5) * 0.04)
					var to: Vector3 = q + Vector3.UP * float(hgt)
					var rb := Basis.looking_at(to - from, Vector3.UP).scaled(Vector3(1, 1, from.distance_to(to)))
					_put("fence_rail", Transform3D(rb, (from + to) * 0.5), _fence)
	MeshBake.bake(_fence)
