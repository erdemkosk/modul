class_name HitFeel
extends Node
## How a blow feels: every machine listened to (Machine.struck, torn, died), and each one made felt.
##
##   a knock     into another machine, a wall, cover: sparks off the metal where it struck, the
##               clang of it (louder and heavier the harder), the view shaken (fully if it's yours,
##               less further off); into the ground only dust, past a hard landing
##   a part off  a spray of sparks and embers, the bolts shearing, a ricochet
##   a kill      the wreck's burst shakes the view hard
##   hit-stop    when you're in a big one (a hard ram either way, a part torn off yours or theirs by
##               you, one of them put down by you) the game all but stops for a few hundredths of a
##               second, then goes on: the blow lands. Not headless (the tests run at their own pace).

const SPARK_FROM := 4.5 ## m/s a knock changes speed by before it throws sparks
const HARD := 12.0 ## m/s: a knock this hard is as hard as they come (for the sound, the sparks, the shake)
const STOP_SCALE := 0.05 ## the game's speed while it stops
const COOL := 0.12 ## s before the same pair (or one machine and the ground) throws sparks again

var game: Node
var stops := 0 ## (hit-stops so far: for the tests)
var _cool := {} ## key -> s left
var _scan := 0.0
var _stop_until := 0 ## ms (real time)
var _headless := DisplayServer.get_name() == "headless"


func _process(dt: float) -> void:
	_scan -= dt
	if _scan <= 0.0:
		_scan = 0.5
		for n in get_tree().get_nodes_in_group("machines"):
			var m := n as Machine
			if m.has_meta("hit_feel"):
				continue
			m.set_meta("hit_feel", true)
			m.struck.connect(func(at: Vector3, dv: float, other: Object) -> void:
				_on_struck.call_deferred(m, at, dv, other)) # (out of the physics step)
			m.torn.connect(_on_torn.bind(m))
			m.died.connect(_on_died.bind(m))
	for k: Variant in _cool.keys():
		_cool[k] = float(_cool[k]) - dt
		if float(_cool[k]) <= 0.0:
			_cool.erase(k)
	if _stop_until > 0 and Time.get_ticks_msec() >= _stop_until:
		_stop_until = 0
		Engine.time_scale = 1.0


func _you() -> Machine:
	var m: Variant = game.get("machine") if game else null
	return m as Machine if is_instance_valid(m) else null


func _on_struck(m: Machine, at: Vector3, dv: float, other: Object) -> void:
	if not is_instance_valid(m) or dv < SPARK_FROM or Combat.current == null:
		return
	var o_id := other.get_instance_id() if is_instance_valid(other) else 0
	var key := [mini(m.get_instance_id(), o_id), maxi(m.get_instance_id(), o_id)]
	if _cool.has(key):
		return
	_cool[key] = COOL
	var c := Combat.current
	var k := clampf((dv - SPARK_FROM) / (HARD - SPARK_FROM), 0.0, 1.0)
	var ground := other == null or other == m.terrain or not is_instance_valid(other)
	var you := _you()
	var mine := you != null and (m == you or other == you)
	if ground:
		if k < 0.3:
			return
		c._burst(at, "dirt", 0.5 + k * 0.6)
		c.sound("res://assets/audio/impact/dirt_0%d.wav" % randi_range(1, 3), at, -10.0 + k * 8.0, randf_range(0.8, 1.0))
		c.shake(at, k * 0.35, you if m == you else null)
		return
	c._burst(at, "metal", 0.7 + k * 1.1, (m.com_global() - at).normalized())
	c.sound("res://assets/audio/impact/metal_0%d.wav" % randi_range(1, 3), at, -6.0 + k * 9.0, randf_range(0.8, 1.05) - k * 0.15)
	if k > 0.35:
		c.sound("res://assets/audio/build/heavy_01.wav" if k > 0.7 else "res://assets/audio/build/clank_0%d.wav" % randi_range(1, 3),
			at, -4.0 + k * 6.0, randf_range(0.7, 0.85))
	if mine:
		c.shake(at, 0.12 + k * 0.6, you, k * 5.0)
		if k > 0.5 and other is Machine:
			hit_stop(0.04 + k * 0.05)
	else:
		c.shake(at, k * 0.45, null)


func _on_torn(at: Vector3, _id: String, m: Machine) -> void:
	var c := Combat.current
	if c == null:
		return
	c._burst(at, "metal", 1.6)
	c._burst(at, "embers", 0.6)
	c.sound("res://assets/audio/build/bolt_off_0%d.wav" % randi_range(1, 2), at, 2.0, randf_range(0.7, 0.85))
	c.sound("res://assets/audio/impact/ricochet_0%d.wav" % randi_range(1, 2), at, -2.0, randf_range(0.85, 1.0))
	var you := _you()
	if you == null:
		return
	if m == you or m.last_hit_by == you:
		c.shake(at, 0.35, you, 3.0)
		hit_stop(0.06)


func _on_died(m: Machine) -> void:
	var you := _you()
	if you != null and is_instance_valid(m) and m != you and m.last_hit_by == you:
		Combat.current.shake(m.global_position, 0.8, you, 6.0)
		hit_stop(0.11)


## The game all but stopped for `secs` (real time), then on.
func hit_stop(secs: float) -> void:
	stops += 1
	if _headless:
		return
	Engine.time_scale = STOP_SCALE
	_stop_until = maxi(_stop_until, Time.get_ticks_msec() + int(secs * 1000.0))


func _exit_tree() -> void:
	Engine.time_scale = 1.0
