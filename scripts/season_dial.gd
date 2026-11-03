class_name SeasonDial
extends Control
## The year at a glance, top middle (the HUD's): a dial of the four seasons, inked in their colours
## (spring's green, summer's gold, autumn's rust, winter's ice), a hand on today, the day's
## temperature in its middle; beside it how many days the food and the firewood in store will last
## at the rate they're going, red when it's fewer than are left before the winter's out. The winter
## is what the town's running against: the nearer it is, the colder the dial's rim.

const SEASON_COLOURS := [Color(0.55, 0.72, 0.38), Color(0.88, 0.7, 0.32), Color(0.78, 0.4, 0.22), Color(0.72, 0.85, 0.95)]
const R := 30.0

var game: Node
var _food_days := 0.0
var _wood_days := 0.0
var _year := 0.0 ## 0..1 through the year (spring's first morning at 0)
var _temp := 0.0
var _winter_in := 0.0 ## days to the winter's first day (0 in it)
var _food: Label
var _wood: Label
var _season: Label


func _ready() -> void:
	custom_minimum_size = Vector2(R * 2.0 + 8.0, R * 2.0 + 8.0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	tooltip_text = "Yıl: ilkbahar, yaz, sonbahar, kış. İbre bugünü gösterir; ortada sıcaklık."


## The labels beside the dial, built by the HUD into its row.
func make_labels(row: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	_season = Ui.label(col, "", 15, Ui.ACCENT, "head")
	_food = Ui.label(col, "", 14, Ui.INK, "head")
	_wood = Ui.label(col, "", 14, Ui.INK, "head")
	col.tooltip_text = "Depodaki yiyecek ve yakacak, şimdiki tüketimle kaç gün yeter (kış yakacağı iki katına çıkarır)"
	col.mouse_filter = Control.MOUSE_FILTER_PASS


func refresh() -> void:
	var v: Village = game.village
	var w: Weather = game.weather
	var se: Seasons = game.seasons
	var per_season := float(Seasons.LENGTHS[3]) # (the winter's length, for "to the winter's end")
	var day_in := float(se.day_in(v.day)) + w.hour / 24.0
	_year = (float(Seasons.start_of(maxi(se.season, 0))) + day_in) / float(Seasons.YEAR)
	_temp = w.temperature
	_winter_in = 0.0 if se.season == 3 else (float(Seasons.start_of(3) - Seasons.start_of(maxi(se.season, 0))) - day_in)
	var day_secs := maxf(w.day_length_minutes * 60.0, 1.0)
	# food: each mouth by its traits, an ox as one
	var mouths := 0.0
	for x in v.villagers:
		mouths += x.trait_mul("eat")
	mouths += v.oxen()
	var food_rate := mouths / v.EAT_EVERY * day_secs
	_food_days = float(v.stock.get("yiyecek", 0)) / food_rate if food_rate > 0.0 else 99.0
	# firewood: the lived-in houses' hearths, by their plaster and stoves; most of the day in the
	# winter, the night (and the cold mornings) the rest of the year
	var burn := 0.0
	var held := 0
	for b in v.buildings:
		if b.def.role == "house" and b.state == "done" and not b.residents.is_empty():
			burn += b.fuel_mul()
			held += Village.house_fuel(b)
	var share := 0.95 if se.season == 3 else (0.6 if se.season == 2 else 0.4)
	var wood_rate := burn * share / v.LOG_EVERY * day_secs * (1.5 if se.season == 3 else 1.0)
	_wood_days = float(int(v.stock.get("odun", 0)) + int(v.stock.get("komur", 0)) * v.COAL_LASTS + held) / wood_rate if wood_rate > 0.0 else 99.0
	var short := _winter_in + per_season # (to the winter's end)
	if se.season == 3:
		short = per_season - day_in
	_season.text = "%s · %d°%s" % [Ui.upper(str(Seasons.NAMES[se.season])), roundi(_temp),
		"  ·  kışa %d gün" % ceili(_winter_in) if se.season != 3 and _winter_in < per_season * 2.0 else ""]
	_food.text = "YİYECEK  %s" % _days(_food_days)
	_food.add_theme_color_override("font_color", Ui.BAD if _food_days < minf(short, 3.0) else Ui.INK)
	_wood.text = "YAKACAK  %s" % _days(_wood_days)
	_wood.add_theme_color_override("font_color", Ui.BAD if _wood_days < minf(short, 3.0) and burn > 0.0 else Ui.INK)
	queue_redraw()


static func _days(d: float) -> String:
	if d >= 30.0:
		return "bol"
	if d < 1.0:
		return "%d saat" % maxi(roundi(d * 24.0), 0)
	return "%.1f gün" % d


func _draw() -> void:
	var c := size * 0.5
	# the leather disc, its rim cold as the winter nears
	draw_circle(c, R + 3.0, Color(0.12, 0.09, 0.07))
	var cold := clampf(1.0 - _winter_in / float(Seasons.DAYS * 2), 0.0, 1.0)
	draw_arc(c, R + 2.5, 0.0, TAU, 48, Color(0.55, 0.42, 0.28).lerp(SEASON_COLOURS[3], cold), 1.5, true)
	# the four seasons, each as long as it is, from the top going round
	for s in 4:
		var a0 := -PI * 0.5 + float(Seasons.start_of(s)) / Seasons.YEAR * TAU + 0.04
		var a1 := a0 + float(Seasons.LENGTHS[s]) / Seasons.YEAR * TAU - 0.08
		draw_arc(c, R - 4.0, a0, a1, 16, SEASON_COLOURS[s], 6.0, true)
	# ticks for the days
	for d in Seasons.YEAR:
		var a := -PI * 0.5 + d * TAU / Seasons.YEAR
		draw_line(c + Vector2(cos(a), sin(a)) * (R - 9.0), c + Vector2(cos(a), sin(a)) * (R - 11.5), Color(Ui.INK, 0.35), 1.0, true)
	# the hand on today
	var ah := -PI * 0.5 + _year * TAU
	var tip := c + Vector2(cos(ah), sin(ah)) * (R - 2.0)
	draw_line(c, tip, Ui.ACCENT, 2.0, true)
	draw_circle(tip, 2.5, Ui.ACCENT)
	draw_circle(c, 11.0, Color(0.12, 0.09, 0.07))
	var f := Ui.font("display")
	var t := "%d°" % roundi(_temp)
	var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	draw_string(f, c + Vector2(-ts.x * 0.5, ts.y * 0.32), t, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, SEASON_COLOURS[3] if _temp < 0.0 else Ui.INK)
