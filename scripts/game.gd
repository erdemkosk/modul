extends Node3D
## İnşa: a machine you put together from parts and drive and fight with. Three places (Mode):
##   cage     KAFES: a tournament of rounds in a small walled arena before a crowd (Cage, CageArena)
##   valley   the open valley (WorldTerrain: its mud, snow, roads; WorldDecor's trees; Weather's sky)
##   arena    the proving ground (TestTerrain): asphalt, gravel, mud pits, a bog, snow, ice, ramps;
##            build on the spot and set the other side's machines on yourself
##
##   B / Tab    build / drive
##   W S        throttle / brake and back       A D   steer       Space  brake
##   mouse      look and aim                    left button       fire
##   L          lights                          T     back on its wheels
##   1-9  0     turn that gun on or off (the others stay as they are) · all of them on
##   C          the camera: chase, high, from the turret     right button held: aim at range
##   F1 F2 F3   a raider (minigun), a tank (cannon), a target       F4  a wave
##   F5         a tracked rocket carrier                             F6  clear them all away
##   G          (proving ground) yours takes no damage / does again
##   Esc        pause (go on, settings, the start menu)

const ARENA_ZONES := [
	["asphalt", Rect2(-30, -60, 60, 40)], ["gravel", Rect2(-60, -20, 25, 60)], ["mud", Rect2(-30, 0, 24, 22)],
	["bog", Rect2(0, 4, 18, 18)], ["snow", Rect2(30, -20, 26, 30)], ["ice", Rect2(30, 14, 22, 18)],
	["wet", Rect2(-30, 26, 60, 18)],
]

var terrain: Node
var weather: Weather
var machine: Machine
var cam: OrbitCamera
var builder: Builder
var combat: Combat
var arena := false
var arena_node: Arena
var cage: Cage
var place_name := "" ## (the HUD's top left)
var kills := 0
var player_input := true ## (tests, a demo) false: nothing here drives or aims your machine
var disarmed: Array[int] = [] ## your guns (by their order) turned off: the rest fire together
var _hud: Label
var _drive_hud: DriveHud
var pause: PauseMenu
var _recover_t := 0.0 ## (K held) seconds toward rebuilding a machine that can't move
var _death: DeathCard
var _life_t := 0.0 ## seconds this machine's lived
var _kills_at_spawn := 0
var _cross: Control
var _banner: Label
var _toast: PanelContainer
var _banner_t := 0.0


func _ready() -> void:
	_bind_keys()
	arena = Mode.current == "arena"
	var caged := Mode.current == "cage"
	place_name = "KAFES" if caged else ("TEST ALANI" if arena else "VADİ")
	weather = Weather.new()
	weather.hour = 21.6 if caged else 11.0 # (the cage fights at night, under its lights)
	weather.day_length_minutes = 0.0 if arena or caged else 40.0
	weather.preset = "clear"
	add_child(weather)
	if caged:
		var ct := TestTerrain.new()
		ct.default_surface = Surface.preset("asphalt")
		ct.noise_from = 52.0
		ct.grid_strength = 0.0
		terrain = ct
		add_child(ct)
		var ca := CageArena.new()
		ca.terrain = ct
		add_child(ca)
		cage = Cage.new()
		cage.arena = ca
		cage.game = self
	elif arena:
		var t := TestTerrain.new()
		t.default_surface = Surface.preset("grass") # (a meadow round the zones)
		t.noise_from = Arena.R + 12.0 # (the arena's floor flat out to its stands)
		t.grid_strength = 0.0
		for z: Array in ARENA_ZONES:
			t.add_zone(z[1], Surface.preset(z[0]))
		terrain = t
		add_child(t)
		arena_node = Arena.new()
		arena_node.terrain = t
		add_child(arena_node)
	else:
		var w := WorldTerrain.new()
		terrain = w
		add_child(w)
		var decor := WorldDecor.new()
		decor.terrain = w
		add_child(decor)
	combat = Combat.new()
	combat.terrain = terrain
	add_child(combat)
	combat.shook.connect(_on_shook)
	combat.hit_confirmed.connect(_on_hit_confirmed)
	machine = _spawn(Builder.load_saved(), _start_xform(), 0)
	if machine.design.is_empty():
		machine.from_data(Designs.starter())
	machine.died.connect(_on_player_died)
	cam = OrbitCamera.new()
	cam.target = machine
	cam.terrain = terrain
	add_child(cam)
	cam.global_position = machine.global_position + Vector3(0, 3, 9)
	cam.make_current()
	builder = Builder.new()
	builder.machine = machine
	builder.cam = cam
	add_child(builder)
	_make_hud()
	pause = PauseMenu.new()
	pause.to_menu.connect(func() -> void:
		builder.save()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	add_child(pause)
	_death = DeathCard.new()
	_death.respawn.connect(_respawn)
	add_child(_death)
	if cage:
		add_child(cage)
	Settings.apply(get_tree())
	machine.label = "SEN"
	if cage == null: # (the cage opens on its start panel: the pointer stays free to press it)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if arena:
		say("Test alanı · B: inşa · F1 akıncı · F2 tank · F3 hedef · F5 paletli · F4 dalga · F6 temizle · G hasar")


func _start_xform() -> Transform3D:
	if Mode.current == "cage":
		var at := Vector3(-CageArena.HALF + 4.5, float(terrain.call("height_at", -CageArena.HALF + 4.5, -CageArena.HALF + 4.5)) + 1.5, -CageArena.HALF + 4.5)
		return Transform3D(Basis.looking_at(-at * Vector3(1, 0, 1), Vector3.UP), at)
	if arena:
		return Transform3D(Basis.IDENTITY, Vector3(0.0, terrain.call("height_at", 0.0, -40.0) + 2.0, -40.0))
	var at: Transform3D = terrain.get("spawn")
	return Transform3D(at.basis, at.origin + Vector3.UP * 2.0)


## A machine of `data` at `xf` on `team` (an AI drives it if it's theirs and asked to).
func _spawn(data: Array, xf: Transform3D, team: int, ai := false) -> Machine:
	var m := Machine.new()
	m.terrain = terrain
	m.team = team
	m.transform = xf
	add_child(m)
	m.from_data(data)
	if ai:
		var d := AiDriver.new()
		m.add_child(d)
	m.label = "SEN" if team == 0 else "DÜŞMAN"
	if team == 0: # (what gives on yours: said at once, in red)
		m.system_hit.connect(func(text: String, _at: Vector3) -> void: say("▲ " + text))
	if team != 0:
		m.died.connect(func() -> void:
			kills += 1
			say("%s PARÇALANDI  ·  %d" % [m.label, kills]))
	return m


func spawn_enemy(kind: String) -> Machine:
	var data: Array = {"raider": Designs.raider(), "tank": Designs.tank(), "dummy": Designs.dummy(),
		"tracked": Designs.tracked()}[kind]
	if arena_node and kind != "dummy":
		# in through the gate, one beside the other
		var k := 0
		for m: Node in get_tree().get_nodes_in_group("machines"):
			if m != machine and (m as Machine).team != 0:
				k += 1
		var e := _spawn(data, arena_node.gate_point(k % 9), 1, true)
		e.label = LABELS.get(kind, "DÜŞMAN")
		return e
	var a := randf() * TAU
	var r := 70.0 if kind != "dummy" else 30.0
	var p := machine.global_position + Vector3(cos(a), 0, sin(a)) * r
	if arena_node and p.length() > Arena.R - 8.0:
		p = p.normalized() * (Arena.R - 8.0)
	p.y = float(terrain.call("height_at", p.x, p.z)) + 2.5
	var face := Basis(Vector3.UP, atan2(p.x - machine.global_position.x, p.z - machine.global_position.z))
	var e2 := _spawn(data, Transform3D(face, p), 1, kind != "dummy")
	e2.label = LABELS.get(kind, "DÜŞMAN")
	return e2


const LABELS := {"raider": "AKINCI", "tank": "TANK", "dummy": "HEDEF", "tracked": "PALETLİ"}


func _bind_keys() -> void:
	var keys := {"throttle": [KEY_W, KEY_UP], "reverse": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT],
		"right": [KEY_D, KEY_RIGHT], "brake": [KEY_SPACE], "build": [KEY_TAB, KEY_B], "lights": [KEY_L], "right_up": [KEY_T]}
	for a: String in keys:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a)
		for k: int in keys[a]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(a, e)


func _unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(machine):
		return
	if event.is_action_pressed("build"):
		if cage and not cage.can_build() and not builder.active:
			say("Dövüş sırasında araç değiştirilemez: turlar arası atölyede")
		else:
			if cage and not builder.active:
				cage.on_build_open()
			builder.set_active(not builder.active)
	elif event.is_action_pressed("lights"):
		machine.set_lights(not machine.lights_on)
	elif event.is_action_pressed("right_up") and not builder.active:
		right_up()
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and not builder.active:
		if key.keycode >= KEY_0 and key.keycode <= KEY_9:
			toggle_gun(key.keycode - KEY_1 if key.keycode != KEY_0 else -1)
			return
		if key.keycode == KEY_C:
			say("Kamera: " + cam.cycle_mode())
			return
	if key and key.pressed and not key.echo:
		match key.keycode:
			KEY_ESCAPE:
				pause.open()
				get_viewport().set_input_as_handled()
				return
			KEY_F1:
				spawn_enemy("raider")
			KEY_F2:
				spawn_enemy("tank")
			KEY_F3:
				spawn_enemy("dummy")
			KEY_F5:
				spawn_enemy("tracked")
			KEY_F6:
				var n := clear_enemies()
				say("Alan temizlendi: %d araç kaldırıldı" % n if n > 0 else "Alanda düşman yok")
			KEY_G:
				if arena:
					machine.invulnerable = not machine.invulnerable
					say("Hasar kapalı: aracın vurulmaz" if machine.invulnerable else "Hasar açık")
			KEY_F4:
				for i in 2:
					spawn_enemy("raider")
				spawn_enemy("tank")
				spawn_enemy("tracked")
				say("Dalga: iki akıncı, bir tank, bir paletli roketatar")
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not builder.active \
			and not (cage and cage.panel_up()):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Turns gun `i` on or off (the others stay as they are); -1 turns them all on.
func toggle_gun(i: int) -> void:
	var n := machine.guns.size()
	if n == 0:
		say("Silah yok")
		return
	if i < 0:
		disarmed.clear()
		say("Bütün silahlar açık")
	elif i < n:
		if i in disarmed:
			disarmed.erase(i)
		else:
			disarmed.append(i)
		var names := {"minigun": "Minigun", "cannon": "Top", "rockets": "Roketatar"}
		say("%d · %s %s" % [i + 1, names.get(machine.guns[i].kind, "Silah"), "kapalı" if i in disarmed else "açık"])
	_apply_armed()


func _apply_armed() -> void:
	for i in machine.guns.size():
		machine.guns[i].armed = not i in disarmed


## Every machine of the other side gone (and the wreckage lying about), as at the start.
func clear_enemies() -> int:
	var n := 0
	for m: Node in get_tree().get_nodes_in_group("machines"):
		if m != machine and (m as Machine).team != 0:
			m.queue_free()
			n += 1
	combat.clear_debris()
	return n


## Back on its wheels where it is (rolled over, or stuck nose-down).
func right_up() -> void:
	var p := machine.global_position
	var yaw := machine.global_basis.get_euler().y
	machine.linear_velocity = Vector3.ZERO
	machine.angular_velocity = Vector3.ZERO
	machine.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, float(terrain.call("height_at", p.x, p.z)) + 2.0, p.z))
	machine.set_down()


func _physics_process(dt: float) -> void:
	if not is_instance_valid(machine) or not player_input:
		return
	if builder.active:
		machine.throttle = 0.0
		machine.steer = 0.0
		machine.firing = false
		return
	var fwd := Input.get_action_strength("throttle")
	var back := Input.get_action_strength("reverse")
	machine.steer = Input.get_action_strength("right") - Input.get_action_strength("left")
	machine.brake = Input.get_action_strength("brake")
	# S: brakes while it still rolls forward, then backs up; W the same the other way.
	if back > 0.0 and machine.speed > 1.0:
		machine.throttle = 0.0
		machine.brake = maxf(machine.brake, back)
	elif fwd > 0.0 and machine.speed < -1.0:
		machine.throttle = 0.0
		machine.brake = maxf(machine.brake, fwd)
	else:
		machine.throttle = fwd - back * 0.6
	machine.aim_point = aim_point()
	_apply_armed() # (a rebuild makes the guns anew)
	# K held: a machine that can't move any more (no engine, nothing to run on) or that won't come right
	# is rebuilt where it started
	if Input.is_physical_key_pressed(KEY_K) and cage == null:
		_recover_t += dt
		if _recover_t >= 1.5:
			_recover_t = 0.0
			say("Araç yeniden kuruldu")
			machine.died.disconnect(_on_player_died)
			var old := machine
			old.queue_free()
			_respawn()
	else:
		_recover_t = 0.0
	machine.firing = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Where the middle of the screen looks: the first thing along the camera's line (not your own machine).
func aim_point() -> Vector3:
	var vp := get_viewport().get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(vp)
	var dir := cam.project_ray_normal(vp)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 600.0, 1 | 2 | 4)
	q.exclude = [machine.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position if not hit.is_empty() else from + dir * 600.0


## Your cab's gone: the moment slowed right down, the wreck flying, and a card says what did it and
## how you did; Space (or a few seconds) and a new one's built where you start.
func _on_player_died() -> void:
	if cage:
		cage.on_player_died()
		return
	var by := machine.last_hit_by
	var who := by.label if is_instance_valid(by) and by != machine else ""
	_death.show_card(who, machine.last_hit_kind, _life_t, kills - _kills_at_spawn)
	Engine.time_scale = 0.25
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.5)
	tw.tween_property(Engine, "time_scale", 1.0, 1.0)


## A new machine from the saved design where you start, without a word (the cage's new run).
func _respawn_quiet() -> void:
	if is_instance_valid(machine):
		if machine.died.is_connected(_on_player_died):
			machine.died.disconnect(_on_player_died)
		machine.queue_free()
	_respawn()


## A new machine from the saved design where you start.
func _respawn() -> void:
	Engine.time_scale = 1.0
	_life_t = 0.0
	_kills_at_spawn = kills
	var data := Builder.load_saved()
	machine = _spawn(data if not data.is_empty() else Designs.starter(), _start_xform(), 0)
	machine.died.connect(_on_player_died)
	cam.target = machine
	builder.machine = machine
	builder.rebind()


## Shots and bursts shake the view: yours fully, others' less the further off.
func _on_shook(at: Vector3, amount: float, owner: Machine, punch: float) -> void:
	if cam == null or not is_instance_valid(machine):
		return
	if owner == machine:
		cam.add_trauma(amount, punch)
		return
	var d := cam.global_position.distance_to(at)
	var k := clampf(1.0 - d / (12.0 + 60.0 * amount), 0.0, 1.0)
	if k > 0.0:
		cam.add_trauma(amount * k * k, 0.0)


func _on_hit_confirmed(owner: Machine, killed: bool) -> void:
	if owner == machine and _cross:
		(_cross as Crosshair).confirm(killed)


## A line across the top for a moment: a smoked plate that springs in and fades away.
func say(text: String) -> void:
	_banner.text = text
	_banner_t = 4.0
	_toast.modulate.a = 0.0
	_toast.pivot_offset = _toast.size * 0.5
	_toast.scale = Vector2(0.92, 0.92)
	var tw := _toast.create_tween().set_parallel(true)
	tw.tween_property(_toast, "modulate:a", 1.0, 0.18)
	tw.tween_property(_toast, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_hud = Label.new()
	layer.add_child(_hud)
	# a row across the top, the plate in its middle as wide as its words
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 70 if Mode.current != "cage" else 150 # (under the cage's own bar)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top)
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", Ui.glass(true, 10.0))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	top.add_child(_toast)
	_banner = Ui.label(_toast, "", 20, Ui.INK, "head")
	_drive_hud = DriveHud.new()
	_drive_hud.game = self
	add_child(_drive_hud)
	_cross = Crosshair.new()
	_cross.game = self
	_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_cross)


func _process(dt: float) -> void:
	_banner_t -= dt
	if _banner_t < 0.6:
		_toast.modulate.a = clampf(_banner_t / 0.6, 0.0, 1.0)
	if not is_instance_valid(machine):
		_hud.text = ""
		return
	machine.wet = weather.wetness
	_life_t += dt
	_cross.visible = not builder.active
	_hud.text = ""


static func _ground_name(label: String) -> String:
	return {"asphalt": "asfalt", "gravel": "çakıl", "dirt": "toprak", "grass": "çimen", "rock": "kaya",
		"mud": "çamur", "bog": "bataklık", "snow": "kar", "snowpack": "sert kar", "wet": "ıslak zemin",
		"ice": "buz"}.get(label, label)
