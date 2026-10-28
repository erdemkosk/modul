class_name GameSettings
## What the next game is, picked on the menu's "Yeni Oyun" page before single player starts:
## the map, zombies or a free drive without them, the start time, the weather and how fast the
## day goes by. main.gd reads it when it builds the world. Saved so the menu remembers the last
## choice. Defaults to the small test map, which the headless tests in tests/ rely on.

const SAVE_FILE := "user://game_settings.cfg"

const MAPS := {"world": "Havza (2 km açık dünya)", "test": "Test pisti"}
const MODES := {"survival": "Hayatta Kalma", "free": "Serbest Sürüş", "arena": "Test arenası"}
const WEATHERS := {
	"dynamic": "Değişken", "clear": "Açık", "cloudy": "Parçalı bulutlu", "overcast": "Kapalı",
	"rain": "Yağmurlu", "storm": "Fırtına", "fog": "Sisli", "snow": "Karlı", "frost": "Ayaz (buzlu yollar)",
}
const TIMES := {"dawn": 6.2, "morning": 9.0, "noon": 13.0, "evening": 18.6, "night": 22.5}
const TIME_NAMES := {"dawn": "Şafak", "morning": "Sabah", "noon": "Öğle", "evening": "Gün batımı", "night": "Gece"}
const STARTS := {"vehicle": "Araçla, üs kapısında", "heli": "Helikopterle, Kaletepe pistinde"} ## Free drive and survival: where you start.
## Free drive and survival: the gun you start with in hand (the Makarov in the holster besides;
## "makarov": the pistol alone).
const GUNS := {"mosin": "Mosin-Nagant", "ak": "AK-47", "sks": "SKS", "ppsh": "PPSh-41", "toz": "TOZ çifte",
	"piyade": "Piyade tüfeği", "hafif": "Hafif makineli", "makarov": "Yalnız Makarov", "tabanca9": "Yalnız 9 mm tabanca"}

static var map := "test"
static var mode := "free"
static var weather := "clear"
static var time := "morning"
static var day_length := 40.0 ## Real minutes per game day; 0 stops the clock.
static var start := "vehicle" ## STARTS: in the vehicle at the gate, or at the controls of the base's helicopter on its pad.
static var gun := "mosin" ## GUNS: free drive and survival's starting gun.
## The menu's Helikopter game: the base's helicopter is where you live (HeliHome, HeliSupply). You
## start in its cabin on the Kaletepe pad, the engines cold, the door shut; its world is kept in a
## save of its own (HELI_SAVE), apart from Oyna's.
static var heli_home := false
const HELI_SAVE := "user://heli_world.save"
const WORLD_SAVE := "user://world.save"
## The 3D is drawn at this share of the screen's size and FSR 2 brings it up to full (its own
## anti-aliasing: no MSAA then). 1.0: native, MSAA. 0.77 (FSR 2 "quality") about doubled the
## frame rate at 1440p for very little lost.
static var render_scale := 0.77
## The gunfight's screen effects (the pause menu's GÖRÜNTÜ rows; ScreenFx, HitStop): motion blur (the view
## smeared a little as it swings, more sprinting, a blast), the sprint's darkened edges, the one you hit
## held a moment, the view's small punch with each hit.
static var motion_blur := true
static var sprint_vignette := true
static var hit_stop := true
static var fov_punch := true
const FX_FIELDS := {"motion_blur": "Hareket bulanıklığı", "sprint_vignette": "Koşu vinyeti", "hit_stop": "Vuruş duraksaması", "fov_punch": "Vuruşta görüş darbesi"}


static func zombies() -> bool:
	return mode == "survival"


static func hour() -> float:
	return float(TIMES.get(time, 9.0))


static func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_FILE) != OK:
		map = "world"
		return
	map = str(cfg.get_value("game", "map", "world"))
	mode = str(cfg.get_value("game", "mode", "survival"))
	weather = str(cfg.get_value("game", "weather", "dynamic"))
	time = str(cfg.get_value("game", "time", "morning"))
	day_length = float(cfg.get_value("game", "day_length", 40.0))
	start = str(cfg.get_value("game", "start", "vehicle"))
	gun = str(cfg.get_value("game", "gun", "mosin"))
	for k: String in FX_FIELDS:
		set_field(k, bool(cfg.get_value("fx", k, true)))
	if not GUNS.has(gun):
		gun = "mosin"
	if not MAPS.has(map):
		map = "world"
	if not MODES.has(mode):
		mode = "survival"
	if not WEATHERS.has(weather):
		weather = "dynamic"
	if not STARTS.has(start):
		start = "vehicle"
	if not TIMES.has(time):
		time = "morning"


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "map", map)
	cfg.set_value("game", "mode", mode)
	cfg.set_value("game", "weather", weather)
	cfg.set_value("game", "time", time)
	cfg.set_value("game", "day_length", day_length)
	cfg.set_value("game", "start", start)
	cfg.set_value("game", "gun", gun)
	for k: String in FX_FIELDS:
		cfg.set_value("fx", k, bool(get_field(k)))
	cfg.save(SAVE_FILE)


## Only the screen effects' choices (the pause menu): the rest of what's saved left as it was.
static func save_fx() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_FILE)
	for k: String in FX_FIELDS:
		cfg.set_value("fx", k, bool(get_field(k)))
	cfg.save(SAVE_FILE)


## The menu's choice rows set and read fields by name.
static func set_field(field: String, value: Variant) -> void:
	match field:
		"map": map = str(value)
		"mode": mode = str(value)
		"weather": weather = str(value)
		"time": time = str(value)
		"day_length": day_length = float(value)
		"start": start = str(value)
		"gun": gun = str(value)
		"motion_blur": motion_blur = bool(value)
		"sprint_vignette": sprint_vignette = bool(value)
		"hit_stop": hit_stop = bool(value)
		"fov_punch": fov_punch = bool(value)


static func get_field(field: String) -> Variant:
	match field:
		"map": return map
		"mode": return mode
		"weather": return weather
		"time": return time
		"day_length": return day_length
		"start": return start
		"gun": return gun
		"motion_blur": return motion_blur
		"sprint_vignette": return sprint_vignette
		"hit_stop": return hit_stop
		"fov_punch": return fov_punch
	return null


## F11: fullscreen on and off (the game starts fullscreen: project.godot).
static func toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
