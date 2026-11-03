class_name Seasons
extends Node
## The year: spring, summer, autumn and winter, LENGTHS days each (the winter longest). Each season has its own weather
## (it picks the next every few minutes, by the season's odds, and the weather glides to it):
## spring is wet (the ground goes to mud), summer warm and dry (fire weather), autumn grey and
## foggy, winter snowy and bitter (snow lies on the ground, the roofs and the trees). Each season
## shifts the temperature: in winter the hearths burn more, nothing grows and the bushes bear
## nothing, so the food must be in before it comes.

signal message(text: String, kind: String)

const NAMES := ["İlkbahar", "Yaz", "Sonbahar", "Kış"]
const DAYS := 3 ## (the shorter seasons; the dial's ticks)
const LENGTHS := [3, 3, 3, 5]
const YEAR := 14
const TEMP := [-3.0, 5.0, -4.0, -13.0] ## deg C on top of the weather's own
const ODDS := [
	{"clear": 2.0, "cloudy": 3.0, "overcast": 2.0, "rain": 4.0, "storm": 1.0, "fog": 1.5},
	{"clear": 6.0, "cloudy": 3.0, "overcast": 1.0, "rain": 1.0, "storm": 1.2, "fog": 0.3},
	{"clear": 1.5, "cloudy": 3.0, "overcast": 3.0, "rain": 3.0, "storm": 1.0, "fog": 3.0},
	{"frost": 3.0, "cloudy": 2.0, "overcast": 2.0, "snow": 5.0, "fog": 1.0},
]
const ARRIVE := ["İlkbahar geldi: kar eriyor, yollar çamur olacak.", "Yaz geldi: kuru ve sıcak; yangına dikkat.",
	"Sonbahar geldi: kış gelmeden yiyecek ve yakacak biriktir.", "Kış geldi: kar yağıyor, toplayıcılar boş döner, ocaklar daha çok yakar."]

var weather: Weather
var village: Village
var season := -1
var offset := 0 ## days skipped ahead by hand (the test panel, a new town begun later in the year), kept as the year goes on
var _hold := 0.0


## The first day of season `s` in the year (0-based).
static func start_of(s: int) -> int:
	var d := 0
	for k in s:
		d += int(LENGTHS[k])
	return d


## The season on day `day` of the year as kept (`off` days ahead).
static func of_day(day: int, off := 0) -> int:
	var d := posmod(day - 1 + off, YEAR)
	for s in 4:
		if d < int(LENGTHS[s]):
			return s
		d -= int(LENGTHS[s])
	return 3


## How many days into its season `day` is (0-based, whole days).
func day_in(day: int) -> int:
	var d := posmod(day - 1 + offset, YEAR)
	return d - start_of(of_day(day, offset))


func winter() -> bool:
	return season == 3


## Straight to season `s` (the test panel): its weather at once, the ground as that season leaves it.
func force(s: int) -> void:
	offset = posmod(start_of(s) - (village.day - 1), YEAR)
	season = s
	_next(true)
	match s:
		0:
			weather.snow_cover = 0.0
			weather.wetness = 0.95
		1:
			weather.snow_cover = 0.0
			weather.wetness = 0.05
		2:
			weather.snow_cover = 0.0
			weather.wetness = 0.55
		3:
			weather.snow_cover = 0.9
			weather.wetness = 0.0
	message.emit(ARRIVE[s], "info")


var _autumn := -1.0


func _process(dt: float) -> void:
	# The broadleaf trees turning: green in spring and summer, gold and red through the autumn,
	# coming on over its first days (nature.gdshader's season_autumn).
	var into := float(day_in(village.day)) / float(LENGTHS[2]) if season == 2 else 0.0
	var want := clampf(into * 2.5 + 0.25, 0.0, 1.0) if season == 2 else (1.0 if season == 3 else 0.0)
	if absf(want - _autumn) > 0.01:
		_autumn = want
		RenderingServer.global_shader_parameter_set(&"season_autumn", want)
	var s := of_day(village.day, offset)
	if s != season:
		var first := season < 0
		season = s
		_hold = 0.0
		if not first:
			message.emit(ARRIVE[s], "info")
		_next(first)
		return
	_hold -= dt
	if _hold <= 0.0:
		_next(false)


func _next(instant: bool) -> void:
	var odds: Dictionary = ODDS[season]
	var total := 0.0
	for k: String in odds:
		total += float(odds[k])
	var roll := randf() * total
	var pick := "cloudy"
	for k: String in odds:
		roll -= float(odds[k])
		if roll <= 0.0:
			pick = k
			break
	weather.set_preset(pick, instant)
	weather._t_temp += TEMP[season]
	if instant:
		weather.temperature = weather._t_temp
	_hold = randf_range(140.0, 320.0)


## For the clock: the season's name and the day within it.
func label() -> String:
	return "%s %d" % [NAMES[maxi(season, 0)], day_in(village.day) + 1]
