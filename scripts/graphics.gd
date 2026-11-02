class_name Graphics
## How the game is drawn, kept in user://graphics.cfg and put on at every start: a quality (picked
## for the machine at first: what kind of graphics card it has), the share of the screen's pixels
## the 3D is drawn at before it's scaled up to the screen (the menus stay sharp at full size; by
## default the 3D is drawn about as tall as the quality asks, so a big screen doesn't cost more),
## the edge smoothing, a frame cap and vsync.
##
## A quality sets: volumetric fog (and its grain), ambient occlusion, screen-space reflections, the
## sun's shadow reach, size and softness, and how far off the trees are drawn in full (WorldProps;
## that one takes from the next town made or loaded).

const PATH := "user://graphics.cfg"
const QUALITIES := ["auto", "dusuk", "orta", "yuksek"]
const QUALITY_NAMES := {"auto": "OTOMATİK", "dusuk": "DÜŞÜK", "orta": "ORTA", "yuksek": "YÜKSEK"}
const SCALES := [0.0, 0.5, 0.6, 0.67, 0.77, 0.85, 1.0] ## (0: as the quality and the screen ask)
const AAS := ["auto", "fxaa", "msaa", "fsr2", "off"]
const AA_NAMES := {"auto": "OTOMATİK", "fxaa": "FXAA", "msaa": "MSAA 2x", "fsr2": "FSR 2", "off": "KAPALI"}
const FPS := [0, 30, 60, 120]

## What each quality draws: the 3D drawn this tall (px) at most, then scaled up.
const LEVELS := {
	"dusuk": {"height": 720, "vfog": false, "fog_grid": 0, "ssao": false, "ssr": false, "shadow_dist": 110.0, "shadow_atlas": 2048, "soft": 0, "trees": 0.6},
	"orta": {"height": 900, "vfog": true, "fog_grid": 48, "ssao": true, "ssr": false, "shadow_dist": 160.0, "shadow_atlas": 4096, "soft": 1, "trees": 0.8},
	"yuksek": {"height": 1080, "vfog": true, "fog_grid": 64, "ssao": true, "ssr": true, "shadow_dist": 200.0, "shadow_atlas": 4096, "soft": 2, "trees": 1.0},
}

static var quality := "auto"
static var scale := 0.0
static var aa := "auto"
static var fps := 0
static var vsync := true
static var _loaded := false


## A setting by its name (the GRAFİK plate's rows).
static func value(key: String) -> Variant:
	match key:
		"quality": return quality
		"scale": return scale
		"aa": return aa
		"fps": return fps
		"vsync": return vsync
	return null


static func set_value(key: String, v: Variant) -> void:
	match key:
		"quality": quality = str(v)
		"scale": scale = float(v)
		"aa": aa = str(v)
		"fps": fps = int(v)
		"vsync": vsync = bool(v)


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	quality = str(cf.get_value("g", "quality", quality))
	scale = float(cf.get_value("g", "scale", scale))
	aa = str(cf.get_value("g", "aa", aa))
	fps = int(cf.get_value("g", "fps", fps))
	vsync = bool(cf.get_value("g", "vsync", vsync))
	if not quality in QUALITIES:
		quality = "auto"
	if not aa in AAS:
		aa = "auto"


static func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("g", "quality", quality)
	cf.set_value("g", "scale", scale)
	cf.set_value("g", "aa", aa)
	cf.set_value("g", "fps", fps)
	cf.set_value("g", "vsync", vsync)
	cf.save(PATH)


## The graphics card, as the driver names it.
static func card() -> String:
	return RenderingServer.get_video_adapter_name()


## The quality this machine is good for: low on graphics built into the processor, medium on the
## Apple chips and the older or smaller cards, high on a recent gaming card.
static func detect() -> String:
	var name := card().to_lower()
	var kind := RenderingServer.get_video_adapter_type()
	if kind in [RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_CPU, RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU]:
		return "orta" if name.contains("apple") else "dusuk"
	for weak in ["intel", "uhd", "iris", "vega", "radeon(tm) graphics", "radeon graphics", "mx1", "mx2", "mx3", "mx4", "mx5", "gt 1030", "gtx 9", "gtx 7", "rx 5"]:
		if name.contains(weak):
			return "dusuk"
	for strong in ["rtx 30", "rtx 40", "rtx 50", "rtx 20", "rx 6", "rx 7", "rx 9", "arc a7", "arc b"]:
		if name.contains(strong):
			return "yuksek"
	return "orta"


## The quality in force (OTOMATİK worked out).
static func level() -> String:
	return detect() if quality == "auto" else quality


## The share of the screen's pixels the 3D is drawn at.
static func render_scale(window_height := 0) -> float:
	if scale > 0.0:
		return scale
	var h := window_height if window_height > 0 else DisplayServer.window_get_size().y
	var want := float(LEVELS[level()].height)
	return clampf(want / maxf(float(h), 1.0), 0.5, 1.0)


## The edge smoothing in force (OTOMATİK: MSAA when the 3D is drawn at full size, FXAA when it's
## scaled up).
static func smoothing() -> String:
	if aa != "auto":
		return aa
	return "msaa" if render_scale() >= 0.999 and level() == "yuksek" else "fxaa"


## Everything put on: the window's viewport, and (in a town) the weather's sky and sun.
static func apply(tree: SceneTree, weather: Weather = null) -> void:
	load_settings()
	var lv: Dictionary = LEVELS[level()]
	var vp := tree.root
	var s := render_scale(vp.size.y)
	var sm := smoothing()
	vp.scaling_3d_scale = s
	if sm == "fsr2":
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 # (its own smoothing, over frames)
	elif s < 0.999:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		vp.fsr_sharpness = 0.25
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.msaa_3d = Viewport.MSAA_2X if sm == "msaa" else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if sm == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	Engine.max_fps = fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	RenderingServer.directional_shadow_atlas_set_size(int(lv.shadow_atlas), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(lv.soft))
	if int(lv.fog_grid) > 0:
		RenderingServer.environment_set_volumetric_fog_volume_size(int(lv.fog_grid), int(lv.fog_grid))
	WorldProps.detail = float(lv.trees)
	if weather and is_instance_valid(weather):
		var env := weather.environment
		if env:
			env.volumetric_fog_enabled = bool(lv.vfog)
			env.ssao_enabled = bool(lv.ssao)
			env.ssr_enabled = bool(lv.ssr)
		if weather.sun:
			weather.sun.directional_shadow_max_distance = float(lv.shadow_dist)
		if weather.moon:
			weather.moon.directional_shadow_max_distance = minf(float(lv.shadow_dist), 120.0)
