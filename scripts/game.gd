extends Node3D
## İnşa: a machine you put together from parts and drive and fight with. Two places (Mode):
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
var hit_feel: HitFeel
var salvage: Salvage
var wanderers: Wanderers
var sites: Node ## (the valley's works sites: works_sites.gd)
var workshop: Workshop ## (the valley's: the truck you build and mend beside)
var expeditions: Expeditions
var life: ValleyLife
var giants: Colossus
var valley_hud: ValleyHud
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
	place_name = "TEST ALANI" if arena else "VADİ"
	Builder.keep_wear = Mode.current == "valley" # (the valley's parts are worn and stay so)
	if Mode.current == "valley" and Builder.save_path == "user://design.json":
		Builder.save_path = "user://valley_design.json" # (the valley's machine is its own: built from what you hold)
	weather = Weather.new()
	weather.hour = 11.0
	weather.day_length_minutes = 0.0 if arena else 40.0
	weather.preset = "clear"
	add_child(weather)
	if arena:
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
	hit_feel = HitFeel.new()
	hit_feel.game = self
	hit_feel.process_mode = Node.PROCESS_MODE_ALWAYS # (it lets go of a hit-stop even paused)
	add_child(hit_feel)
	machine = _spawn(Builder.load_saved(), _start_xform(), 0)
	if machine.design.is_empty():
		machine.from_data(_first_design())
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
		if workshop:
			workshop.save()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	add_child(pause)
	_death = DeathCard.new()
	_death.respawn.connect(_respawn)
	add_child(_death)
	if Mode.current == "valley":
		_valley_salvage()
	Settings.apply(get_tree())
	machine.label = "SEN"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if arena:
		say("Test alanı · B: inşa · F1 akıncı · F2 tank · F3 hedef · F5 paletli · F4 dalga · F6 temizle · G hasar")


## The valley's way: you build with what you hold (Inventory), what comes off the other side's
## machines whole is yours to take (Salvage), and machines come to be hunted (Wanderers); old works
## out in the valley are still guarded by their robots, a cache left in each (works_sites.gd).
## Its work is carrying (Expeditions: J); you build and mend only beside the workshop truck
## (Workshop: V to drive it); the valley soaks, floods and shuts its roads (ValleyLife); giants roam
## it to be taken apart (Colossus).
func _valley_salvage() -> void:
	Inventory.load_all() # (what's held, its wear and the scrap: read now, for the HUD)
	workshop = Workshop.new()
	workshop.game = self
	workshop.terrain = terrain
	add_child(workshop)
	life = ValleyLife.new()
	life.game = self
	life.terrain = terrain
	life.weather = weather
	add_child(life)
	expeditions = Expeditions.new()
	expeditions.game = self
	expeditions.terrain = terrain
	add_child(expeditions)
	giants = Colossus.new()
	giants.game = self
	giants.terrain = terrain
	add_child(giants)
	valley_hud = ValleyHud.new()
	valley_hud.game = self
	valley_hud.exp_ = expeditions
	valley_hud.shop = workshop
	valley_hud.life = life
	valley_hud.giants = giants
	add_child(valley_hud)
	salvage = Salvage.new()
	salvage.game = self
	add_child(salvage)
	wanderers = Wanderers.new()
	wanderers.game = self
	wanderers.terrain = terrain
	add_child(wanderers)
	sites = (load("res://scripts/works_sites.gd") as GDScript).new()
	sites.set("game", self)
	sites.set("terrain", terrain)
	add_child(sites)
	builder.guard = func(id: String, _at: Vector3i, _rot: int) -> bool:
		if Inventory.take(id):
			return true
		if Inventory.make_wood(id) and Inventory.take(id): # (wooden: made here and now, out of the store)
			say("%s yapıldı: %d odun  ·  depoda %d" % [Parts.def(id).name, Parts.wood_cost(id), Inventory.wood])
			return true
		if Inventory.make_metal(id) and Inventory.take(id): # (metal: its plan's known, made of scrap)
			say("%s yapıldı: %d hurda  ·  kalan %d" % [Parts.def(id).name, Parts.metal_cost(id), Inventory.scrap])
			return true
		var plan := Parts.plan_of(id)
		if Parts.wood_cost(id) > 0:
			say("%s için %d odun gerek, depoda %d: testereyle ağaç kes, kasayla topla" % [Parts.def(id).name, Parts.wood_cost(id), Inventory.wood])
		elif plan != "" and not Inventory.knows(plan):
			say("%s için plan yok (%s): harabelerde, devlerde, uzun seferlerde ara" % [Parts.def(id).name, Parts.PLANS[plan].name])
		elif Parts.metal_cost(id) > 0:
			say("%s için %d hurda gerek, elde %d" % [Parts.def(id).name, Parts.metal_cost(id), Inventory.scrap])
		else:
			say("Elinde %s yok: parçalanan araçlardan topla" % Parts.def(id).name)
		return false
	# (the part bolted on is the one taken: as worn as it was)
	builder.placed.connect(func(i: int) -> void:
		var m := builder.machine
		if i < m.design.size() and Inventory.taken < 0.995:
			var p: Dictionary = m.design[i]
			p.hp = Parts.hp_of(p.id) * Inventory.taken
			m.rebuild())
	builder.removed.connect(func(id: String, _at: Vector3i, _rot: int) -> void: Inventory.add(id, 1, builder.removed_cond))
	builder.price_note = func(id: String) -> String:
		var b := Inventory.best(id)
		if Inventory.count(id) <= 0 and Parts.wood_cost(id) > 0:
			return "%d odun (depoda %d)" % [Parts.wood_cost(id), Inventory.wood]
		if Inventory.count(id) <= 0 and Parts.plan_of(id) != "" and not Inventory.knows(Parts.plan_of(id)):
			return "plan yok"
		if Inventory.count(id) <= 0 and Parts.metal_cost(id) > 0:
			return "%d hurda (elde %d)" % [Parts.metal_cost(id), Inventory.scrap]
		return "elde %d" % Inventory.count(id) + (" · en iyisi %%%d" % roundi(b * 100.0) if b >= 0.0 and b < 0.995 else "")
	builder.swap_guard = func(old: Array, new: Array) -> bool:
		var r := Inventory.swap(old, new)
		if bool(r.ok):
			builder.swap_rows = r.rows
		if not bool(r.ok):
			var need := []
			for id: String in r.short:
				need.append("%s ×%d" % [Parts.def(id).name, r.short[id]])
			say("Eksik parça: " + ", ".join(need))
		return bool(r.ok)


func _start_xform() -> Transform3D:
	if arena:
		return Transform3D(Basis.IDENTITY, Vector3(0.0, terrain.call("height_at", 0.0, -40.0) + 2.0, -40.0))
	if Mode.current == "valley":
		if workshop and is_instance_valid(workshop.truck): # (a new one's built beside the workshop)
			var t := workshop.truck.global_transform
			var p := t.origin - t.basis.x * 8.0
			p.y = float(terrain.call("height_at", p.x, p.z)) + 1.5
			return Transform3D(Basis(Vector3.UP, t.basis.get_euler().y), p)
		return Workshop.beside(terrain)
	var at: Transform3D = terrain.get("spawn")
	return Transform3D(at.basis, at.origin + Vector3.UP * 2.0)


## A machine of `data` at `xf` on `team` (an AI drives it if it's theirs and asked to).
func _spawn(data: Array, xf: Transform3D, team: int, ai := false) -> Machine:
	var m := Machine.new()
	m.terrain = terrain
	m.team = team
	m.transform = xf
	# ammunition runs out everywhere but the proving ground (a crew carries twice yours)
	m.ammo_limited = Mode.current != "arena"
	m.ammo_k = 1.0 if team == 0 else 2.0
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
			if Mode.current == "valley":
				Inventory.add_scrap(3) # (what's left of it)
			kills += 1
			say("%s PARÇALANDI  ·  %d" % [m.label, kills]))
	return m


func spawn_enemy(kind: String) -> Machine:
	var made := Forge.make(randi(), randi_range(0, 5)) if kind == "forge" else {}
	var data: Array = made.data if kind == "forge" else {"raider": Designs.raider(), "tank": Designs.tank(),
		"dummy": Designs.dummy(), "tracked": Designs.tracked()}[kind]
	if arena_node and kind != "dummy":
		# in through the gate, one beside the other
		var k := 0
		for m: Node in get_tree().get_nodes_in_group("machines"):
			if m != machine and (m as Machine).team != 0:
				k += 1
		var e := _spawn(data, arena_node.gate_point(k % 9), 1, true)
		e.label = str(made.name) if kind == "forge" else LABELS.get(kind, "DÜŞMAN")
		return e
	var a := randf() * TAU
	var r := 70.0 if kind != "dummy" else 30.0
	var p := machine.global_position + Vector3(cos(a), 0, sin(a)) * r
	if arena_node and p.length() > Arena.R - 8.0:
		p = p.normalized() * (Arena.R - 8.0)
	p.y = float(terrain.call("height_at", p.x, p.z)) + 2.5
	var face := Basis(Vector3.UP, atan2(p.x - machine.global_position.x, p.z - machine.global_position.z))
	var e2 := _spawn(data, Transform3D(face, p), 1, kind != "dummy")
	e2.label = str(made.name) if kind == "forge" else LABELS.get(kind, "DÜŞMAN")
	return e2


const LABELS := {"raider": "AKINCI", "tank": "TANK", "dummy": "HEDEF", "tracked": "PALETLİ"}


func _bind_keys() -> void:
	var keys := {"throttle": [KEY_W, KEY_UP], "reverse": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT],
		"right": [KEY_D, KEY_RIGHT], "brake": [KEY_SPACE], "build": [KEY_TAB, KEY_B], "lights": [KEY_L], "right_up": [KEY_T], "flip": [KEY_F]}
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
	if valley_hud and valley_hud.board_open and event is InputEventKey and (event as InputEventKey).pressed 			and (event as InputEventKey).physical_keycode in [KEY_J, KEY_ESCAPE]:
		valley_hud.toggle_board()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build"):
		if workshop and not builder.active and workshop.driving():
			say("Atölyeyi sürerken inşa olmaz: V ile aracına geç")
		elif workshop and not builder.active and not workshop.near(machine):
			say("İnşa ve onarım yalnız atölyenin yanında: %s" % workshop.status())
		else:
			builder.set_active(not builder.active)
	elif event.is_action_pressed("lights"):
		machine.set_lights(not machine.lights_on)
	elif event.is_action_pressed("right_up") and not builder.active:
		right_up()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and not builder.active \
			and player_input:
		var code := (event as InputEventKey).physical_keycode
		_fire_flippers(code)
		machine.joint_key(code)
		var hoisted := machine.hoist_key(code)
		if hoisted != "":
			say(hoisted)
		var tooled := machine.tool_key(code)
		if tooled != "":
			say(tooled)
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and not builder.active:
		if key.keycode >= KEY_0 and key.keycode <= KEY_9:
			toggle_gun(key.keycode - KEY_1 if key.keycode != KEY_0 else -1)
			return
		if key.keycode == KEY_C:
			say("Kamera: " + cam.cycle_mode())
			return
		if workshop and key.physical_keycode == KEY_V:
			workshop.swap()
			return
		if valley_hud and key.physical_keycode == KEY_J:
			valley_hud.toggle_board()
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
			KEY_F7:
				var f := spawn_enemy("forge")
				say("Yeni rakip: %s" % f.label)
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
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not builder.active:
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
## The flippers on `code` (F for those with no key of their own): fired. True if any answers to it.
func _fire_flippers(code: int) -> bool:
	var any := false
	var fired := false
	for f in machine.flippers:
		if (f.key if f.key != 0 else KEY_F) == code:
			any = true
			fired = f.fire() or fired
	if any and not fired:
		say("Çevirici dolmadı" if machine.powered else "Akü bitti: çevirici çalışmaz")
	elif not any and code == KEY_F and machine.flippers.is_empty() and Mode.current != "valley":
		say("Çevirici yok: inşada SİLAH sekmesinden takılır")
	return any


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
	if Input.is_physical_key_pressed(KEY_K) and not (workshop and workshop.driving()):
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
	machine.keyed = true
	for g in machine.guns:
		g.key_down = g.key != 0 and Input.is_physical_key_pressed(g.key)


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
	if workshop and workshop.driving(): # (the machine you left's gone: a new one beside the workshop)
		say("Bıraktığın araç parçalandı: atölyenin yanında yenisi kuruldu")
		var data := Builder.load_saved()
		var m := _spawn(data if not data.is_empty() else _first_design(), _start_xform(), 0)
		m.died.connect(_on_player_died)
		m.brake = 1.0
		workshop.own = m
		builder.machine = m
		builder.rebind()
		return
	var by := machine.last_hit_by
	var who := by.label if is_instance_valid(by) and by != machine else ""
	_death.show_card(who, machine.last_hit_kind, _life_t, kills - _kills_at_spawn)
	Engine.time_scale = 0.25
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.5)
	tw.tween_property(Engine, "time_scale", 1.0, 1.0)


## You at the wheel of `m` (the valley's workshop truck, or your own machine again): the one left braked.
func drive(m: Machine) -> void:
	if is_instance_valid(machine):
		machine.throttle = 0.0
		machine.steer = 0.0
		machine.firing = false
		machine.brake = 1.0
	machine = m
	m.brake = 0.0
	cam.target = m


## What a machine's built as with nothing saved.
func _first_design() -> Array:
	return Designs.valley_start() if Mode.current == "valley" else Designs.starter()


## A new machine from the saved design where you start.
func _respawn() -> void:
	Engine.time_scale = 1.0
	_life_t = 0.0
	_kills_at_spawn = kills
	var data := Builder.load_saved()
	machine = _spawn(data if not data.is_empty() else _first_design(), _start_xform(), 0)
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
	top.offset_top = 70
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
	var hints := Hints.new() # (the first time at each thing: how it's done)
	hints.game = self
	add_child(hints)
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
	return {"asphalt": "asfalt", "concrete": "beton", "gravel": "çakıl", "dirt": "toprak", "grass": "çimen", "rock": "kaya",
		"mud": "çamur", "bog": "bataklık", "snow": "kar", "snowpack": "sert kar", "wet": "ıslak zemin",
		"ice": "buz"}.get(label, label)
