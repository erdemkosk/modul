class_name Wolf
extends Villager
## A wolf: a villager's walk and bite (Raids gives it its plans) in a grey wolf's body (assets/animals/
## wolf.glb, scripts/animal_body.gd): low and long, on four legs, its tail out behind. Quick, and
## quicker still running someone down; at a walk, a trot, or a gallop as fast as it goes, its feet
## set down where they go and kept there; struck, a flash of red; killed, down on its side.

const COATS := [Color(0.5, 0.48, 0.45), Color(0.4, 0.38, 0.35), Color(0.58, 0.53, 0.46), Color(0.46, 0.43, 0.39)]

var _beast: AnimalBody
var _last := Vector3.INF
var _gait_speed := 0.0


func _build_look() -> void:
	speed_mul = 1.5
	# (a plain material as the tunic, so a blow's red flash shows: step() passes it to the coat)
	_tunic = StandardMaterial3D.new()
	_tunic.albedo_color = Color.WHITE
	_beast = AnimalBody.make("wolf", COATS[randi() % COATS.size()], Color(-1, 0, 0), false, 220.0)
	add_child(_beast)
	_torso = _beast.body
	_legs.assign(_beast.legs.values())


func arm_with(_kind: String) -> void:
	pass


func _animate(dt: float, walking: bool) -> void:
	# how fast it's really going over the ground (whatever plan moved it)
	var flat := Vector3(position.x, 0, position.z)
	var v := 0.0
	if _last != Vector3.INF and dt > 0.0:
		v = minf(flat.distance_to(_last) / dt, 12.0) # (not a leap when it's set down somewhere)
	_last = flat
	_gait_speed = lerpf(_gait_speed, v if walking else 0.0, 1.0 - exp(-10.0 * dt))
	_beast.lunge = maxf(sin(Time.get_ticks_msec() * 0.012), 0.0) if _anim == "strike" else move_toward(_beast.lunge, 0.0, dt * 4.0)
	_beast.graze = 0.6 if _anim == "strike" else 0.0 # (the head low, going for the legs)
	_beast.fit_ground(func(p: Vector3) -> float: return village.ground_at(p), dt)
	_beast.step(dt, _gait_speed)


func _process(dt: float) -> void:
	super(dt)
	if not dead and _beast:
		_beast.set_flash(1.0 if _tunic.albedo_color.g < 0.6 else 0.0)


## Down on its side where it fell, a while, then gone into the ground.
func die() -> void:
	if dead:
		return
	abort()
	dead = true
	hp = 0.0
	died.emit(self)
	_beast.set_flash(0.0)
	var tw := create_tween()
	tw.tween_property(_beast, "rotation:z", PI * 0.5 * (1.0 if randf() < 0.5 else -1.0), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_beast, "position:y", 0.14, 0.5)
	tw.tween_interval(maxf(village.weather.day_length_minutes * 60.0 * 0.5, 90.0))
	tw.tween_property(self, "position:y", position.y - 1.0, 4.0)
	tw.tween_callback(queue_free)
