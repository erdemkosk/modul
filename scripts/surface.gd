class_name Surface
extends Resource
## A ground material: how much grip it gives and, when soft, how wheels sink
## into it. Soft surfaces get a deformable SoftPatch on the terrain.

@export var label := "dirt"
@export var color := Color(0.40, 0.34, 0.26)
@export var grip := 0.75
@export var rolling_resistance := 0.03

@export_group("Soft ground")
@export var max_depth := 0.0 ## Deepest a rut can get, m. 0 = rigid ground.
@export var static_sink := 0.0 ## Sinkage the moment a wheel at reference load touches down, m.
@export var sink_rate := 0.0 ## Slow settling per second while loaded, m/s at reference load.
@export var dig_rate := 0.0 ## Sinkage per second for each m/s of wheelspin, at reference load.
@export var sink_drag := 0.0 ## Extra rolling resistance per wheel radius of sinkage.
@export var hold_cap := 0.85 ## Most the ground in front of a sunk tyre holds back, as a fraction of its grip (> 1: it can trap you).
@export var deep_color := Color(0.25, 0.2, 0.15) ## Colour at the bottom of ruts.
@export var wetness := 0.0 ## How shiny the bottom of ruts gets.

static var _presets := {}


func is_soft() -> bool:
	return max_depth > 0.0


## Shared tuning for the surfaces: asphalt, dirt, ice, snow, mud, bog, and the open world's
## rigid ground: gravel (roads), grass, rock, snowpack (shallow snow over hard ground), wet.
static func preset(id: String) -> Surface:
	if _presets.has(id):
		return _presets[id]
	var s := Surface.new()
	s.label = id
	match id:
		"asphalt":
			s.color = Color(0.2, 0.2, 0.21)
			s.grip = 1.0
			s.rolling_resistance = 0.015
		"concrete": # (a works yard: poured slabs, worn and dusty)
			s.color = Color(0.46, 0.45, 0.43)
			s.grip = 0.95
			s.rolling_resistance = 0.016
		"dirt":
			pass
		"ice":
			s.color = Color(0.72, 0.84, 0.92)
			s.grip = 0.12
			s.rolling_resistance = 0.01
		"snow":
			s.color = Color(0.9, 0.92, 0.95)
			s.deep_color = Color(0.66, 0.71, 0.79)
			s.grip = 0.4
			s.rolling_resistance = 0.05
			s.max_depth = 0.3
			s.static_sink = 0.1
			s.sink_rate = 0.005
			s.dig_rate = 0.04
			s.sink_drag = 0.25
			s.wetness = 0.2
		"mud":
			s.color = Color(0.25, 0.19, 0.13)
			s.deep_color = Color(0.13, 0.09, 0.06)
			s.grip = 0.4
			s.rolling_resistance = 0.1
			s.max_depth = 0.4
			s.static_sink = 0.12
			s.sink_rate = 0.008
			s.dig_rate = 0.06
			s.sink_drag = 0.6
			s.wetness = 0.8
		"gravel":
			s.color = Color(0.45, 0.39, 0.3)
			s.grip = 0.85
			s.rolling_resistance = 0.022
		"grass":
			s.color = Color(0.3, 0.35, 0.16)
			s.grip = 0.68
			s.rolling_resistance = 0.035
		"rock":
			s.color = Color(0.42, 0.41, 0.39)
			s.grip = 0.9
			s.rolling_resistance = 0.015
		"snowpack":
			s.color = Color(0.86, 0.89, 0.94)
			s.grip = 0.45
			s.rolling_resistance = 0.04
		"wet":
			s.color = Color(0.2, 0.17, 0.11)
			s.grip = 0.52
			s.rolling_resistance = 0.05
		"black_ice":
			# Frozen water on a road (Weather.ice): looks like a wet road, grips like a rink.
			s.color = Color(0.3, 0.33, 0.36)
			s.grip = 0.13
			s.rolling_resistance = 0.01
		"bog":
			s.color = Color(0.2, 0.17, 0.12)
			s.deep_color = Color(0.09, 0.07, 0.05)
			s.grip = 0.35
			s.rolling_resistance = 0.1
			s.max_depth = 0.75
			s.static_sink = 0.18
			s.sink_rate = 0.02
			s.dig_rate = 0.1
			s.sink_drag = 0.7
			s.hold_cap = 1.25 # a real bog: road tyres and a wrong line will leave you there
			s.wetness = 1.0
		_:
			push_warning("Unknown surface preset '%s', using dirt" % id)
	_presets[id] = s
	return s
