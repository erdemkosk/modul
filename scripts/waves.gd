class_name Waves
extends Node
## ARENA: round after round in a walled maze (WaveArena), a new one each round.
##
##   build     every round starts here: your machine whole again on full racks in the middle cell,
##             the builder open (B): build what this round needs (ammunition's limited: ammo boxes
##             carry more), Enter when it's ready
##   the round the other side comes in from the furthest cells, a few at a time (2 + the round's
##             number of them in all, up to 2 + round / 2 at once, each stronger as the rounds go);
##             they find their way to you through the maze. While it goes on, supply crates come down
##             by parachute here and there (CEPHANE, ONARIM, AKÜ): go and get them. When the last of
##             them is in pieces the round's won, and it's back to building on a new maze
##   lost      your machine gone: how far you got, your best; Enter for a new run
##
## The best round reached is kept in user://arena.cfg.

const SAVE := "user://arena.cfg"
const SPAWN_GAP := 5.0 ## s between arrivals
const DROP_EVERY := 28.0 ## s between supply crates (the first a little sooner)
const DROPS_AT_ONCE := 3
const DROP_KINDS := [["ammo", 0.55], ["repair", 0.3], ["power", 0.15]]

static var save_path := SAVE ## (tests point it elsewhere)

var game: Node
var arena: WaveArena
var state := "build" ## build, fight, cleared, lost
var round := 1
var run_seed := 0
var rivals: Array[Machine] = []
var to_come := 0
var best := 0
var time := 0.0
var _spawn_t := 0.0
var _drop_t := 0.0
var _clear_t := 0.0
var _ui: CanvasLayer
var _top: Label
var _sub: Label
var _big: Label
var _big_t := 0.0
var _panel: PanelContainer
var _box: VBoxContainer


func _ready() -> void:
	name = "Waves"
	var cf := ConfigFile.new()
	cf.load(save_path)
	best = int(cf.get_value("arena", "best", 0))
	_make_ui()
	var b := game.get("builder") as Builder
	b.closed.connect(func() -> void:
		if state == "build":
			_show_build())
	_build_phase()


## The round's maze and your machine whole on full racks in the middle; the builder open.
func _build_phase() -> void:
	state = "build"
	for e in rivals:
		if is_instance_valid(e):
			e.queue_free()
	rivals.clear()
	for d in get_tree().get_nodes_in_group("supply"):
		d.queue_free()
	if Combat.current:
		Combat.current.clear_debris()
	arena.lay_out(run_seed * 7919 + round * 104729)
	var mv: Variant = game.get("machine")
	if not is_instance_valid(mv) or not (mv as Machine).alive:
		game.call("_respawn_quiet") # (a new run: a new machine)
	var m: Machine = game.get("machine")
	var data := Builder.load_saved()
	m.from_data(data if not data.is_empty() else Designs.starter())
	_place(m)
	game.set("player_input", false)
	var b := game.get("builder") as Builder
	if not b.active:
		b.set_active(true)
	_show_build()


func _place(m: Machine) -> void:
	var at := arena.center(WaveArena.START) + Vector3.UP * 1.5
	m.linear_velocity = Vector3.ZERO
	m.angular_velocity = Vector3.ZERO
	m.global_transform = Transform3D(Basis.IDENTITY, at)
	m.set_down()


func can_build() -> bool:
	return state == "build"


func panel_up() -> bool:
	return _panel.visible


## Off: the round begins (the builder shut, what you built kept).
func start() -> void:
	if state != "build":
		return
	var b := game.get("builder") as Builder
	if b.active:
		b.set_active(false)
	b.save()
	var m: Machine = game.get("machine")
	_place(m)
	m.resupply(1.0)
	state = "fight"
	time = 0.0
	to_come = 2 + round
	_spawn_t = 1.0
	_drop_t = DROP_EVERY * 0.7
	game.set("player_input", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_panel.visible = false
	_flash("BÖLÜM %d" % round)


func _physics_process(dt: float) -> void:
	_big_t -= dt
	_big.modulate.a = clampf(_big_t, 0.0, 1.0)
	match state:
		"fight":
			time += dt
			_fight(dt)
		"cleared":
			_clear_t -= dt
			if _clear_t <= 0.0:
				round += 1
				_build_phase()
	_show_top()


func _fight(dt: float) -> void:
	for k in range(rivals.size() - 1, -1, -1):
		if not is_instance_valid(rivals[k]) or not rivals[k].alive:
			rivals.remove_at(k)
	# arrivals: a few at a time, from the cells furthest from you
	_spawn_t -= dt
	var at_once := 2 + round / 2
	if to_come > 0 and rivals.size() < at_once and _spawn_t <= 0.0:
		_spawn_t = SPAWN_GAP
		_send_one()
	# supply crates now and then (only so many on the ground)
	_drop_t -= dt
	if _drop_t <= 0.0:
		_drop_t = DROP_EVERY
		if get_tree().get_nodes_in_group("supply").size() < DROPS_AT_ONCE:
			drop()
	if to_come == 0 and rivals.is_empty():
		state = "cleared"
		_clear_t = 3.5
		if round > best:
			best = round
			var cf := ConfigFile.new()
			cf.set_value("arena", "best", best)
			cf.save(save_path)
		_flash("BÖLÜM %d TAMAM" % round)
		game.set("player_input", false)


## One of the other side in, at a far cell, built for the round, finding its way to you.
func _send_one() -> Machine:
	var m: Machine = game.get("machine")
	var cells := arena.far_cells(m.global_position, 6)
	var c: Vector2i = cells[randi() % cells.size()]
	var at := arena.center(c) + Vector3(randf_range(-1.5, 1.5), 1.6, randf_range(-1.5, 1.5)) # (cover is never on a cell's middle)
	var tier := clampi((round - 1) / 2, 0, 5)
	var made := Forge.make(run_seed * 31 + round * 1009 + to_come * 7, tier)
	var face := Basis(Vector3.UP, atan2(at.x - m.global_position.x, at.z - m.global_position.z))
	var e: Machine = game.call("_spawn", made.data, Transform3D(face, at), 1, true)
	e.label = str(made.name)
	for d in e.get_children():
		if d is AiDriver:
			(d as AiDriver).route = arena.route
			(d as AiDriver).clumsy = clampf(2.0 - round * 0.2, 1.0, 2.0)
			(d as AiDriver).target = m
	rivals.append(e)
	to_come -= 1
	return e


## A supply crate down somewhere open 25-60 m from you (not in your cell's middle, not on a wall).
func drop(kind := "") -> SupplyDrop:
	var m: Machine = game.get("machine")
	if kind == "":
		var r := randf()
		kind = "ammo"
		for e: Array in DROP_KINDS:
			r -= float(e[1])
			if r <= 0.0:
				kind = str(e[0])
				break
	var at := Vector3.ZERO
	for tries in 30:
		var c := Vector2i(randi() % WaveArena.N, randi() % WaveArena.N)
		at = arena.center(c)
		var d := at.distance_to(m.global_position)
		if d > 25.0 and d < 60.0:
			break
	var s := SupplyDrop.make(kind, at, arena.terrain)
	game.add_child(s)
	if game.has_method("say"):
		game.call("say", "İKMAL GELİYOR: %s  ·  %d m" % [SupplyDrop.NAMES[kind], int(at.distance_to(m.global_position))])
	return s


func on_player_died() -> void:
	if state != "fight":
		return
	state = "lost"
	game.set("player_input", false)
	_show_lost()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if not k or not k.pressed or k.echo:
		return
	if k.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		if state == "build":
			start()
			get_viewport().set_input_as_handled()
		elif state == "lost":
			# a new run: a new lot of mazes from round 1
			run_seed = randi()
			round = 1
			_panel.visible = false
			_build_phase()
			get_viewport().set_input_as_handled()


# --- The screens ------------------------------------------------------------------------------------

func _make_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 7
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_top = 14
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_top = Ui.label(top, "", 30, Ui.INK, "display")
	_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = Ui.label(top, "", 14, Ui.DIM, "label")
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big = Ui.label(root, "", 88, Ui.INK, "display")
	_big.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_big.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_big.offset_top = -190
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.modulate.a = 0.0
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Ui.glass(false, 24.0, Color(0.05, 0.055, 0.06, 0.93)))
	_panel.custom_minimum_size.x = 560
	center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_panel.add_child(_box)
	_panel.visible = false


func _flash(text: String) -> void:
	_big.text = text
	_big_t = 2.2


func _show_top() -> void:
	match state:
		"build":
			_top.text = "ARENA  ·  BÖLÜM %d" % round
			_sub.text = "İNŞA  ·  hazır olunca ENTER" + ("  ·  en iyi: bölüm %d" % best if best > 0 else "")
		"fight", "cleared":
			_top.text = "BÖLÜM %d  ·  %d:%02d" % [round, int(time) / 60, int(time) % 60]
			_sub.text = "DÜŞMAN  %d sahada  ·  %d gelecek" % [rivals.size(), to_come]
		"lost":
			_top.text = "ARENA"
			_sub.text = ""


func _clear_box() -> void:
	for c in _box.get_children():
		c.queue_free()


## Building: the round's lines (only while the builder's shut: it has its own screen).
func _show_build() -> void:
	_clear_box()
	var b := game.get("builder") as Builder
	_panel.visible = not b.active
	if b.active:
		return
	Ui.label(_box, "ARENA", 15, Ui.ACCENT, "head")
	Ui.label(_box, "BÖLÜM %d" % round, 52, Ui.INK, "display")
	Ui.rule(_box, 60.0)
	var lines := Ui.label(_box, "%d rakip gelecek, labirentin uzak köşelerinden. Cephane sınırlı: sandık tak ya da sahaya düşen ikmalleri topla. Duvarların arkasına saklan, etraflarından dolaş." % (2 + round), 17, Ui.DIM)
	lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.custom_minimum_size.x = 500
	Ui.label(_box, "B  inşa     ENTER  başla", 15, Ui.INK, "label")


func _show_lost() -> void:
	_clear_box()
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Ui.label(_box, "ARENA", 15, Ui.BAD, "head")
	Ui.label(_box, "PARÇALANDIN", 52, Ui.INK, "display")
	Ui.rule(_box, 60.0, Ui.BAD)
	Ui.label(_box, "Bölüm %d'e kadar geldin  ·  en iyi: bölüm %d" % [round, best], 18, Ui.DIM)
	Ui.label(_box, "ENTER  yeni koşu (yeni labirentler)", 15, Ui.INK, "label")
