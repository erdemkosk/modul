class_name Settings
extends RefCounted
## What the player sets (the pause menu's and the start menu's AYARLAR), kept in user://settings.cfg
## and put into effect at once: the mouse's sensitivity, the field of view, how hard the view
## shakes, the sound's loudness, full screen, shadows and ambient occlusion, the frame rate shown.

const PATH := "user://settings.cfg"
const DEFAULTS := {"sensitivity": 1.0, "fov": 70.0, "shake": 1.0, "volume": 0.8, "fullscreen": false,
	"shadows": true, "ssao": true, "show_fps": true}

static var values := {}
static var _loaded := false


static func get_value(key: String) -> Variant:
	if not _loaded:
		load_all()
	return values.get(key, DEFAULTS[key])


static func set_value(key: String, v: Variant) -> void:
	if not _loaded:
		load_all()
	values[key] = v
	save_all()
	apply(Engine.get_main_loop() as SceneTree)


static func load_all() -> void:
	_loaded = true
	values = DEFAULTS.duplicate()
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k: String in DEFAULTS:
			values[k] = cf.get_value("settings", k, DEFAULTS[k])


static func save_all() -> void:
	var cf := ConfigFile.new()
	for k: String in values:
		cf.set_value("settings", k, values[k])
	cf.save(PATH)


## Into effect: the sound, the window, and (in a game) its sun's shadows and the ambient occlusion.
static func apply(tree: SceneTree) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(get_value("volume")), 0.0001)))
	if DisplayServer.get_name() != "headless":
		var full: bool = get_value("fullscreen")
		var mode := DisplayServer.window_get_mode()
		if full and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not full and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if tree == null or tree.root == null:
		return
	for n in tree.root.find_children("*", "DirectionalLight3D", true, false):
		(n as DirectionalLight3D).shadow_enabled = bool(get_value("shadows"))
	for n in tree.root.find_children("*", "WorldEnvironment", true, false):
		var env := (n as WorldEnvironment).environment
		if env:
			env.ssao_enabled = bool(get_value("ssao"))
