class_name GrassFires
extends Node3D
## Fire in the grass: a burning building now and then sets the dry grass round it alight, and the
## patches creep on before the wind, a few metres at a time, setting light to a building they come up
## against and burning anyone standing in them, till each burns itself out and leaves the ground
## black. Wet weather keeps them down; rain or snow puts them out fast. Not in snow, not on roads or
## the town's trodden yards, not over water.

const MAX := 28 ## patches burning at once, at most
const LIFE := Vector2(18.0, 40.0) ## s a patch burns, between
const STEP := 2.6 ## m a patch creeps to the next

var village: Village
var patches: Array[Dictionary] = [] ## {at, left, fx, spread}
var _t := 0.0


func _ready() -> void:
	name = "GrassFires"


## How ready the grass is to burn just now: dry and warm, more so in summer; nothing in rain or snow.
func dryness() -> float:
	var wet := maxf(Weather.rain_now, maxf(Weather.snow_now, Weather.snow_cover_now))
	if wet > 0.15 or village.weather.wetness > 0.6:
		return 0.0
	var summer := 1.4 if village.seasons and village.seasons.season == 1 else 1.0
	return clampf((1.0 - village.weather.wetness) * summer * (0.5 + clampf(village.weather.temperature / 25.0, 0.0, 0.7)), 0.0, 1.4)


func can_burn(p: Vector3) -> bool:
	var nav: Nav = village.nav
	if nav.shut_kind(p) != 0 or nav.on_road(p) or nav.worn(p) > 0.5:
		return false
	if p.y < village.terrain.lake_level + 0.3:
		return false
	for q: Dictionary in patches:
		if (q.at as Vector3).distance_to(p) < STEP * 0.7:
			return false
	return true


## A patch lit at `p` (if the grass there will take).
func light(p: Vector3) -> bool:
	if patches.size() >= MAX:
		return false
	p.y = village.nav.height(p.x, p.z)
	if not can_burn(p):
		return false
	var fx := FireFx.flames()
	fx.amount = 10
	(fx.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(1.1, 0.05, 1.1)
	fx.scale = Vector3.ONE * 0.55
	add_child(fx)
	fx.global_position = p + Vector3.UP * 0.1
	patches.append({"at": p, "left": randf_range(LIFE.x, LIFE.y), "fx": fx, "spread": 1.0})
	return true


func _process(dt: float) -> void:
	_t += dt
	if _t < 0.5:
		return
	var t := _t
	_t = 0.0
	var dry := dryness()
	var wet := maxf(Weather.rain_now, maxf(Weather.snow_now * 1.3, Weather.snow_cover_now))
	# a building on fire: sparks into the grass round it
	if dry > 0.0 and patches.size() < MAX:
		for b in village.buildings:
			if b.is_burning() and randf() < 0.05 * dry * t * mini(b.burning_count(), 6) / 3.0:
				var a := randf() * TAU
				var p := b.global_position + Vector3(cos(a), 0, sin(a)) * (b.radius + randf_range(1.0, 3.5))
				light(p)
	var wind := Weather.wind_now
	var fresh: Array[Vector3] = []
	for i in range(patches.size() - 1, -1, -1):
		var q: Dictionary = patches[i]
		q.left = float(q.left) - t * (1.0 + wet * 8.0) # (rain or snow: out in a moment)
		var at: Vector3 = q.at
		if float(q.left) <= 0.0:
			_out(i)
			continue
		# creeping on, more before the wind, less as it tires
		if dry > 0.0 and randf() < 0.12 * dry * float(q.spread) * t:
			var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			if wind.length() > 0.5:
				dir = (dir + Vector3(wind.x, 0, wind.z).normalized() * clampf(wind.length() / 5.0, 0.0, 1.5)).normalized()
			fresh.append(at + dir * STEP)
			q.spread = float(q.spread) * 0.75
		# up against a building: it may catch
		for b in village.buildings:
			if b.state in ["done", "site", "repair"] and not b.is_burning() and b.global_position.distance_to(at) < b.radius + 0.8:
				if randf() < 0.04 * t * (1.0 - wet):
					if b.ignite():
						village.message.emit("Otlardaki yangın %s binasını tutuşturdu!" % b.display_name(), "bad")
		# anyone standing in it
		for v in village.villagers:
			if not v.dead and not v.down and v.position.distance_to(at) < 1.4:
				v.hurt(4.0 * t)
	for p in fresh:
		light(p)


## Burnt out: the flames gone, the ground left black, the grass gone from it.
func _out(i: int) -> void:
	var q: Dictionary = patches[i]
	if is_instance_valid(q.fx):
		var fx: GPUParticles3D = q.fx
		fx.emitting = false
		var tw := fx.create_tween()
		tw.tween_interval(2.0)
		tw.tween_callback(fx.queue_free)
	village.nav.scorch(q.at, 1.8, 0.6)
	village.terrain.clear_grass(q.at, 1.6)
	patches.remove_at(i)


## All put out at once (the test panel).
func douse_all() -> void:
	for i in range(patches.size() - 1, -1, -1):
		_out(i)
