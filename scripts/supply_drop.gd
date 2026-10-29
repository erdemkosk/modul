class_name SupplyDrop
extends Node3D
## A supply crate dropped in under a parachute (the cage crowd's present): it comes down
## slowly, swaying, from DROP_H m; on the ground the chute falls over it and a red flare burns
## beside it so it can be found. Drive up to it (REACH) and it's yours:
##
##   ammo    CEPHANE: every gun's ammunition taken up by AMMO_FRAC of a full load
##   repair  ONARIM: every part given back REPAIR_FRAC of its hit points (a part that's gone stays gone)
##   power   AKÜ: the batteries charged full
##
## It lies LIFE s, then it's gone. Shot, it's only knocked about: it's what it carries that matters.

signal taken(drop: SupplyDrop, by: Machine)

const DROP_H := 55.0 ## m it comes in from
const FALL := 5.5 ## m/s under the chute
const REACH := 3.6 ## m
const LIFE := 75.0 ## s on the ground
const AMMO_FRAC := 0.6
const REPAIR_FRAC := 0.35
const NAMES := {"ammo": "CEPHANE", "repair": "ONARIM", "power": "AKÜ"}
const COLORS := {"ammo": Color(0.36, 0.38, 0.2), "repair": Color(0.62, 0.62, 0.6), "power": Color(0.12, 0.2, 0.36)}

var kind := "ammo"
var terrain: Node
var landed := false
var _ground := 0.0
var _t := 0.0
var _life := LIFE
var _chute: Node3D
var _flare: OmniLight3D
var _smoke: GPUParticles3D


static func make(kind_: String, at: Vector3, terrain_: Node) -> SupplyDrop:
	var d := SupplyDrop.new()
	d.kind = kind_
	d.terrain = terrain_
	d._ground = float(terrain_.call("height_at", at.x, at.z)) if terrain_ else at.y
	d.position = Vector3(at.x, d._ground + DROP_H, at.z)
	return d


func _ready() -> void:
	add_to_group("supply")
	_build()


func title() -> String:
	return "İKMAL · %s" % NAMES[kind]


func _mat(c: Color, rough := 0.7, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


func _box(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = m
	mi.mesh = b
	mi.position = at
	parent.add_child(mi)
	return mi


## The crate (its colour by what it carries, steel-banded, a white cross or band on its side), the
## chute over it on its lines.
func _build() -> void:
	var c: Color = COLORS[kind]
	_box(self, Vector3(1.3, 0.9, 1.3), Vector3(0, 0.45, 0), _mat(c))
	var band := _mat(Color(0.15, 0.15, 0.15), 0.5)
	for y: float in [0.15, 0.75]:
		_box(self, Vector3(1.34, 0.07, 1.34), Vector3(0, y, 0), band)
	var mark := _mat(Color(0.9, 0.9, 0.86))
	match kind:
		"repair":
			_box(self, Vector3(0.5, 0.14, 0.01), Vector3(0, 0.45, 0.656), _mat(Color(0.75, 0.08, 0.06)))
			_box(self, Vector3(0.14, 0.5, 0.01), Vector3(0, 0.45, 0.656), _mat(Color(0.75, 0.08, 0.06)))
		"power":
			_box(self, Vector3(0.12, 0.45, 0.01), Vector3(0, 0.45, 0.656), _mat(Color(0.95, 0.75, 0.1)))
		_:
			_box(self, Vector3(1.0, 0.1, 0.01), Vector3(0, 0.5, 0.656), mark)
	_chute = Node3D.new()
	_chute.position = Vector3(0, 6.0, 0)
	add_child(_chute)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 3.2
	sm.height = 3.2
	sm.is_hemisphere = true
	sm.radial_segments = 16
	sm.rings = 6
	var cm := _mat(Color(0.85, 0.42, 0.12), 0.9)
	cm.cull_mode = BaseMaterial3D.CULL_DISABLED
	sm.material = cm
	dome.mesh = sm
	_chute.add_child(dome)
	var line := _mat(Color(0.8, 0.8, 0.75))
	for k in 8:
		var a := k * TAU / 8.0
		var top := Vector3(cos(a) * 3.0, 0.0, sin(a) * 3.0)
		var low := Vector3(cos(a) * 0.5, -5.2, sin(a) * 0.5)
		var l := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.015
		cy.bottom_radius = 0.015
		cy.height = top.distance_to(low)
		cy.radial_segments = 4
		cy.rings = 1
		cy.material = line
		l.mesh = cy
		var along := (top - low).normalized()
		l.transform = Transform3D(Basis(Vector3.UP.cross(along).normalized(), Vector3.UP.angle_to(along)), (top + low) * 0.5)
		_chute.add_child(l)


func _physics_process(dt: float) -> void:
	_t += dt
	if not landed:
		# down under the chute, swaying
		position.y -= FALL * dt
		rotation.z = sin(_t * 1.3) * 0.08
		rotation.x = cos(_t * 1.1) * 0.06
		if position.y <= _ground:
			_land()
	else:
		_life -= dt
		if _flare:
			_flare.light_energy = 2.2 + sin(_t * 23.0) * 0.6 + randf() * 0.4
		if _life <= 0.0:
			queue_free()
			return
		_try_take()


func _land() -> void:
	landed = true
	position.y = _ground
	rotation = Vector3(0, rotation.y, 0)
	# the chute slumps over to one side
	var tw := create_tween()
	tw.tween_property(_chute, "position", Vector3(3.4, 0.08, 0.8), 1.2).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_chute, "rotation", Vector3(0.05, 0.4, -0.06), 1.2)
	tw.parallel().tween_property(_chute, "scale", Vector3(0.9, 0.06, 1.1), 1.2) # (flat on the ground, rumpled)
	# the flare beside it: a red light and its smoke
	var p := Node3D.new()
	p.position = Vector3(-1.1, 0.1, 0.4)
	add_child(p)
	_box(p, Vector3(0.06, 0.25, 0.06), Vector3(0, 0.12, 0), _mat(Color(1.0, 0.15, 0.08), 0.3, 6.0))
	_flare = OmniLight3D.new()
	_flare.light_color = Color(1.0, 0.25, 0.12)
	_flare.omni_range = 9.0
	_flare.position = Vector3(0, 0.5, 0)
	p.add_child(_flare)
	if DisplayServer.get_name() != "headless":
		_smoke = GPUParticles3D.new()
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 12.0
		pm.initial_velocity_min = 1.5
		pm.initial_velocity_max = 2.5
		pm.gravity = Vector3(0.4, 0.6, 0.0)
		pm.scale_min = 0.6
		pm.scale_max = 1.2
		var grow := CurveTexture.new()
		var cv := Curve.new()
		cv.add_point(Vector2(0.0, 0.4))
		cv.add_point(Vector2(1.0, 3.0))
		grow.curve = cv
		pm.scale_curve = grow
		var fade := GradientTexture1D.new()
		var g := Gradient.new()
		g.set_color(0, Color(0.85, 0.2, 0.15, 0.7))
		g.set_color(1, Color(0.6, 0.45, 0.42, 0.0))
		fade.gradient = g
		pm.color_ramp = fade
		_smoke.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2(1.0, 1.0)
		var qm := StandardMaterial3D.new()
		qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		qm.vertex_color_use_as_albedo = true
		qm.albedo_texture = WheelSpray._puff()
		q.material = qm
		_smoke.draw_pass_1 = q
		_smoke.amount = 60
		_smoke.lifetime = 4.0
		_smoke.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 26, 16))
		p.add_child(_smoke)
	if Combat.current:
		Combat.current.sound("res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3), global_position, 2.0, 0.6)


## Your machine (team 0) near enough: it's taken.
func _try_take() -> void:
	for n in get_tree().get_nodes_in_group("machines"):
		var m := n as Machine
		if m == null or not is_instance_valid(m) or not m.alive or m.team != 0 or m.building:
			continue
		if m.global_position.distance_to(global_position) > REACH + sqrt(m.frontal) * 0.5:
			continue
		apply_to(m)
		taken.emit(self, m)
		if Combat.current:
			Combat.current.sound("res://assets/audio/build/bolt_on_0%d.wav" % randi_range(1, 3), global_position, 3.0, 0.9)
		queue_free()
		return


## What it carries, given to `m`.
func apply_to(m: Machine) -> void:
	match kind:
		"ammo":
			m.resupply(AMMO_FRAC)
		"repair":
			m.repair(REPAIR_FRAC)
		"power":
			m.energy_kj = m.capacity_kj
