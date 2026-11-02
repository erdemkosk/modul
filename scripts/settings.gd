class_name Settings
## What isn't drawing (that's Graphics): the sound's loudness, the window or the full screen, and
## whether the view pans when the mouse is at the screen's edge. Kept in user://settings.cfg and
## put on at every start.

const PATH := "user://settings.cfg"

static var volume := 0.8 ## 0..1, all the sound
static var fullscreen := false
static var edge_pan := true
static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	volume = clampf(float(cf.get_value("s", "volume", volume)), 0.0, 1.0)
	fullscreen = bool(cf.get_value("s", "fullscreen", fullscreen))
	edge_pan = bool(cf.get_value("s", "edge_pan", edge_pan))


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("s", "volume", volume)
	cf.set_value("s", "fullscreen", fullscreen)
	cf.set_value("s", "edge_pan", edge_pan)
	cf.save(PATH)


## Put on: the sound's loudness, the window's mode, and (in a town) the view's edge panning.
static func apply(cam: RtsCamera = null) -> void:
	load_settings()
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want and not (want == DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MAXIMIZED):
		DisplayServer.window_set_mode(want)
	if cam and is_instance_valid(cam):
		cam.edge_pan = edge_pan
