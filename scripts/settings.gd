class_name Settings
## What isn't drawing (that's Graphics): the sound's loudness, the window or the full screen and the
## window's size, how big the menus and panels are drawn, and whether the view pans when the mouse
## is at the screen's edge. Kept in user://settings.cfg and put on at every start.
##
## Sizes are the screen's own pixels: on a Mac's Retina screen there are two to a point, so by
## default the window's made most of the screen and the menus drawn twice the size.

const PATH := "user://settings.cfg"

const UI_SCALES := [0.0, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0] ## (0: as the screen and the window ask)
const WINDOWS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3200, 1800), Vector2i(3840, 2160)]

static var volume := 0.8 ## 0..1, all the sound
static var fullscreen := true ## (full screen by default; AYARLAR can make it a window)
static var window := Vector2i.ZERO ## the window's size (zero: most of the screen)
static var ui_scale := 0.0
static var edge_pan := true
static var _loaded := false
static var _window_done := false ## (the window's sized once a run, and when it's chosen: not again on every new town)


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	volume = clampf(float(cf.get_value("s", "volume", volume)), 0.0, 1.0)
	fullscreen = bool(cf.get_value("s", "fullscreen", fullscreen))
	window = cf.get_value("s", "window", window)
	ui_scale = float(cf.get_value("s", "ui_scale", ui_scale))
	edge_pan = bool(cf.get_value("s", "edge_pan", edge_pan))


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("s", "volume", volume)
	cf.set_value("s", "fullscreen", fullscreen)
	cf.set_value("s", "window", window)
	cf.set_value("s", "ui_scale", ui_scale)
	cf.set_value("s", "edge_pan", edge_pan)
	cf.save(PATH)


## The window sizes the screen has room for.
static func windows() -> Array[Vector2i]:
	var room := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	var out: Array[Vector2i] = []
	for w: Vector2i in WINDOWS:
		if w.x <= room.x and w.y <= room.y - 60:
			out.append(w)
	return out


## The window's size by default: 85% of the room on the screen, 16:9.
static func auto_window() -> Vector2i:
	var room := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	var h := mini(roundi(room.y * 0.85), roundi(room.x * 0.85 * 9.0 / 16.0))
	return Vector2i(roundi(h * 16.0 / 9.0), h)


## How big the menus are drawn: as chosen, or by the screen's scale (a Retina screen: twice) and the
## window's height (as a 1080-row screen's, no smaller than a 720-row one's).
static func ui_factor(window_height := 0) -> float:
	if ui_scale > 0.0:
		return ui_scale
	var h := float(window_height if window_height > 0 else DisplayServer.window_get_size().y)
	var screen := DisplayServer.screen_get_scale(DisplayServer.window_get_current_screen())
	var f := maxf(1.0, maxf(minf(screen, h / 720.0), h / 1080.0))
	return clampf(snappedf(f, 0.25), 1.0, 3.0)


## Put on: the sound's loudness, the window (full screen, or its size, centred), how big the menus
## are, and (in a town) the view's edge panning.
static func apply(cam: RtsCamera = null) -> void:
	load_settings()
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)
	if not _window_done:
		_window_done = true
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want:
			DisplayServer.window_set_mode(want)
		if not fullscreen:
			var size := window if window != Vector2i.ZERO else auto_window()
			var scr := DisplayServer.window_get_current_screen()
			var room := DisplayServer.screen_get_usable_rect(scr)
			size = Vector2i(mini(size.x, room.size.x), mini(size.y, room.size.y - 40))
			if DisplayServer.window_get_size() != size:
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position(room.position + (room.size - size) / 2)
	apply_ui()
	if cam and is_instance_valid(cam):
		cam.edge_pan = edge_pan


## The menus' size put on (again, when the window's resized).
static func apply_ui(tree: SceneTree = null) -> void:
	var root: Window = (tree if tree else Engine.get_main_loop() as SceneTree).root
	root.content_scale_factor = ui_factor(root.size.y)


## The window's mode or size changed in AYARLAR: put on at once.
static func window_changed() -> void:
	_window_done = false
