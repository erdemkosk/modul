class_name Hud
extends CanvasLayer
## What's on the screen, every piece sized to what's in it and anchored to its corner or edge so it
## holds at any window size:
##   top left     the store (all the stores' goods together), the people, the free hands
##   top right    the day, the hour, the weather; the next raid; the game's speed (click to set)
##   top middle   news, a few lines at a time, fading
##   bottom       the buildings to put up, in four groups (tabs), the keys on each; what's being
##                placed and why it can't go there above them
##   right        the chosen building's card (its work, its stuff, its workers, mend, pull down) or
##                the chosen settler's (its work, its home; free it, or right-click a workplace to
##                put it to work there)
##   F1           the keys

const WEATHER_NAMES := {"clear": "Açık", "cloudy": "Bulutlu", "overcast": "Kapalı", "rain": "Yağmurlu",
	"storm": "Fırtına", "fog": "Sisli", "snow": "Karlı", "frost": "Ayaz"}
const CATS := [["KASABA", ["ev", "ambar", "kuyu", "fener", "meydan", "cankulesi"]], ["ÜRETİM", ["tarla", "oduncu", "tasci", "toplayici", "ormanci", "insaatci"]],
	["TAŞIMA", ["yol", "arabaci", "ahir"]], ["SAVUNMA", ["sur", "kapi", "kule", "kisla", "silahlik", "yayci"]]]
const SPEEDS := [1.0, 2.0, 4.0]
## Every key, in one place (the help card, F1). Nothing needs a key: what the selected thing can do
## is a button on its card, and the build bar, the speed and the menu have their own.
const KEYS := [
	["Kamera", "WASD / ok tuşları / ekran kenarı: kaydır · Shift: hızlı · Q E / orta tuş: döndür · tekerlek: yakınlaş · H: depoya dön"],
	["Bina", "Tab: bina grubu · 1-6: bina seç · sol tık: koy · Shift+tık: üst üste koy · R / Shift+R: çevir · sağ tık / Esc: vazgeç · tahta yol: sürükle"],
	["Seçim", "Sol tık: bina ya da kasabalı seç · Shift+tık: birkaç kasabalı · kasabalı seçiliyken sağ tık bir işyerine: oraya ata"],
	["Kart", "Seçtiğin şeyin yapabileceği her şey kartında düğme: onar, yık, işçi ekle, milis yap, topla, fener, tüfekçi / okçu yetiştir..."],
	["Kısayol", "O: onar · Del: yık · M: milis yap · G: milisi topla / bırak · L: fener · toplanmışken sağ tık: mevzi (siper arar) · hayduda sağ tık: ona ateş"],
	["Zaman", "Boşluk: duraklat (durmuşken de emir verilir) · + / -: hızlandır, yavaşlat · F5: kaydet · F9: yükle · Esc: menü"],
	["Görüntü", "P: fotoğraf modu (ekran gizlenir, uzak bulanıklaşır; tekrar P ile çık)"],
	["Deneme", "F: seçili binayı tutuştur · B: haydut baskını"],
]

var game: Node
var category := 0

var _res: Dictionary = {}
var _pop: Label
var _free: Label
var _clock: Label
var _raid: Label
var _speed_buttons: Array[Button] = []
var _hint: Label
var _toasts: VBoxContainer
var _tabs: Array[Button] = []
var _build_row: HBoxContainer
var _card: PanelContainer
var _card_title: Label
var _card_lines: Label
var _card_workers: HBoxContainer
var _card_count: Label
var _card_acts: HBoxContainer
var _card_folk: HBoxContainer
var _btn := {} ## the card's buttons by name, shown and labelled for what's selected
var _placing_plate: PanelContainer
var _card_train: HBoxContainer
var _guns: Label
var _bows: Label
var _pause: PanelContainer
var _help: PanelContainer
var _t := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stores_plate()
	_clock_plate()
	_build_bar()
	_make_card()
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.offset_top = 18
	_toasts.add_theme_constant_override("separation", 2)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)
	var help := _small_button("? TUŞLAR", func() -> void: toggle_help())
	help.tooltip_text = "Bütün tuşlar (F1)"
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.offset_left = 12
	help.offset_top = -44
	help.offset_bottom = -10
	add_child(help)
	_make_placing()
	_test_plate()
	_make_help()
	_make_pause()
	show_category(0)


func _plate(lean := true, fill := Ui.GLASS) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.glass(lean, 8.0, fill))
	return p


func _stat(row: HBoxContainer, title: String, tip := "") -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -4)
	box.tooltip_text = tip
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(box)
	Ui.label(box, title, 12, Ui.DIM, "head")
	return Ui.label(box, "-", 22, Ui.INK, "display")


func _stores_plate() -> void:
	var p := _plate()
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.offset_left = 12
	p.offset_top = 10
	add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	p.add_child(row)
	for id: String in ["odun", "tas", "yiyecek"]:
		_res[id] = _stat(row, Ui.upper(BuildingDefs.RES_NAMES[id]), "Bütün depolardakinin toplamı")
	_pop = _stat(row, "NÜFUS", "Kasabalılar / yataklar")
	_free = _stat(row, "BOŞTA", "Bir işyerine verilmemiş, taşıyıp inşa eden kasabalılar")
	_guns = _stat(row, "TÜFEK", "Silahlıklardaki ve eldeki Mosin tüfekleri · fişek")
	_bows = _stat(row, "YAY", "Silahlıklardaki ve eldeki yaylar · ok")


func _clock_plate() -> void:
	var p := _plate()
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -12
	p.offset_top = 10
	add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	p.add_child(row)
	_clock = _stat(row, "MEVSİM · SAAT · HAVA")
	_raid = _stat(row, "BASKIN", "Haydutların gelmesi beklenen gece")
	var sp := VBoxContainer.new()
	sp.add_theme_constant_override("separation", 2)
	row.add_child(sp)
	Ui.label(sp, "HIZ", 12, Ui.DIM, "head")
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 4)
	sp.add_child(btns)
	var pause := _small_button("II", func() -> void: game.set_speed(0.0))
	pause.tooltip_text = "Duraklat (Boşluk)"
	btns.add_child(pause)
	_speed_buttons.append(pause)
	for s in SPEEDS:
		var b := _small_button("%dx" % int(s), func() -> void: game.set_speed(s))
		b.tooltip_text = "Oyun hızı (+ / -)"
		btns.add_child(b)
		_speed_buttons.append(b)
	var menu := _small_button("MENÜ", func() -> void: game.set_menu(true))
	menu.tooltip_text = "Kaydet, yükle, yeni oyun (Esc)"
	btns.add_child(menu)


## Bottom right: to try things out at once.
func _test_plate() -> void:
	var p := _plate(false, Color(0.05, 0.055, 0.06, 0.65))
	p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -12
	p.offset_bottom = -10
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	p.add_child(col)
	Ui.label(col, "DENEME", 12, Ui.DIM, "head")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	for s in 4:
		var b := _small_button(Ui.upper(Seasons.NAMES[s]), func() -> void: game.seasons.force(s))
		b.tooltip_text = "Hemen bu mevsime geç (havası ve zemini ile)"
		row.add_child(b)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	col.add_child(row2)
	var night := _small_button("GECE", func() -> void: game.weather.hour = 22.0)
	night.tooltip_text = "Saati gece 22:00'ye al"
	row2.add_child(night)
	var day := _small_button("GÜNDÜZ", func() -> void: game.weather.hour = 10.0)
	row2.add_child(day)
	var raid := _small_button("BASKIN", func() -> void: game.test_raid())
	raid.tooltip_text = "Hemen bir haydut baskını (B)"
	row2.add_child(raid)
	var fire := _small_button("TUTUŞTUR", func() -> void: game.ignite_selected())
	fire.tooltip_text = "Seçili binayı ateşe ver (F)"
	row2.add_child(fire)


func _build_bar() -> void:
	var p := _plate()
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_bottom = -10
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(tabs)
	for i in CATS.size():
		var t := _small_button(str(CATS[i][0]), func() -> void: show_category(i))
		t.tooltip_text = "Tab: sonraki grup"
		t.custom_minimum_size = Vector2(110, 26)
		tabs.add_child(t)
		_tabs.append(t)
	_build_row = HBoxContainer.new()
	_build_row.add_theme_constant_override("separation", 6)
	_build_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_build_row)
	_hint = Ui.label(self, "", 17, Ui.INK, "strong")
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_top = -168
	_hint.offset_bottom = -136
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## The group's buildings along the bottom (Tab, or its tab).
func show_category(i: int) -> void:
	category = posmod(i, CATS.size())
	for k in _tabs.size():
		_tabs[k].add_theme_stylebox_override("normal", Ui.glass(false, 5.0, Color(1.0, 0.56, 0.14, 0.35) if k == category else Color(1, 1, 1, 0.06), Ui.ACCENT if k == category else Ui.EDGE))
	for c in _build_row.get_children():
		c.queue_free()
	var kinds: Array = CATS[category][1]
	for k in kinds.size():
		var kind: String = kinds[k]
		var b := Button.new()
		b.text = "%d  %s\n%s" % [k + 1, Ui.upper(str(BuildingDefs.DEFS[kind].name)), BuildingDefs.cost_text(kind)]
		b.tooltip_text = str(BuildingDefs.DEFS[kind].desc)
		b.custom_minimum_size = Vector2(150, 54)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", Ui.font("head"))
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_stylebox_override("normal", Ui.glass(false, 6.0, Color(1, 1, 1, 0.05)))
		var hover := Ui.glass(false, 6.0, Color(1.0, 0.56, 0.14, 0.25), Ui.ACCENT)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", hover)
		b.set_meta("kind", kind)
		b.pressed.connect(func() -> void: game.start_placing(kind))
		_build_row.add_child(b)


## The kind under key `n` (0-based) in the shown group, or "".
func kind_at(n: int) -> String:
	var kinds: Array = CATS[category][1]
	return kinds[n] if n >= 0 and n < kinds.size() else ""


func _make_card() -> void:
	_card = _plate(false)
	_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.offset_right = -12
	_card.offset_top = 84
	_card.visible = false
	add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_card.add_child(col)
	_card_title = Ui.label(col, "", 26, Ui.INK, "display")
	Ui.rule(col)
	_card_lines = Ui.label(col, "", 15, Ui.INK)
	_card_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_lines.custom_minimum_size = Vector2(300, 0)
	_card_workers = HBoxContainer.new()
	_card_workers.add_theme_constant_override("separation", 8)
	col.add_child(_card_workers)
	Ui.label(_card_workers, "İŞÇİ", 14, Ui.DIM, "head")
	_card_workers.add_child(_small_button("−", func() -> void: game.change_workers(-1)))
	_card_count = Ui.label(_card_workers, "0/3", 20, Ui.INK, "display")
	_card_workers.add_child(_small_button("+", func() -> void: game.change_workers(1)))
	_card_acts = HBoxContainer.new()
	_card_acts.add_theme_constant_override("separation", 8)
	col.add_child(_card_acts)
	_btn.repair = _add(_card_acts, "ONAR", func() -> void: game.repair_selected(), "Yıkılan parçaları yeniden yap (O)")
	_btn.demolish = _add(_card_acts, "YIK", func() -> void: game.demolish_selected(), "Binayı kaldır (Del)")
	_btn.look = _add(_card_acts, "ODAKLAN", func() -> void: game.focus_building(), "Kamerayı binaya götür")
	_card_train = HBoxContainer.new()
	_card_train.add_theme_constant_override("separation", 8)
	col.add_child(_card_train)
	_card_train.add_child(_small_button("+ TÜFEKÇİ", func() -> void: game.train("rifle")))
	_card_train.add_child(_small_button("+ OKÇU", func() -> void: game.train("bow")))
	_card_train.add_child(_small_button("SIRAYI SİL", func() -> void: game.train("")))
	_card_folk = HBoxContainer.new()
	_card_folk.add_theme_constant_override("separation", 8)
	col.add_child(_card_folk)
	_btn.release = _add(_card_folk, "İŞTEN AL", func() -> void: game.release_selected(), "İşyerinden çıkar: taşır, inşa eder")
	_btn.militia = _add(_card_folk, "MİLİS YAP", func() -> void: game.toggle_militia(), "Tehlike çanında silahlıktan silah alıp mevziye geçer (M)")
	_btn.draft = _add(_card_folk, "TOPLA", func() -> void: game.toggle_draft(), "Emrine al: sağ tık mevzi, hayduda sağ tık hedef (G)")
	_btn.lantern = _add(_card_folk, "FENERİ SÖNDÜR", func() -> void: game.toggle_lantern(), "Karanlıkta görünmez olur ama az görür (L)")
	_btn.folk_look = _add(_card_folk, "ODAKLAN", func() -> void: game.focus_selected(), "Kamerayı ona götür")


func _add(row: HBoxContainer, text: String, f: Callable, tip := "") -> Button:
	var b := _small_button(text, f)
	b.tooltip_text = tip
	row.add_child(b)
	return b


func _small_button(text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(34, 30)
	b.add_theme_font_override("font", Ui.font("head"))
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", Ui.glass(false, 5.0, Color(1, 1, 1, 0.06)))
	b.add_theme_stylebox_override("hover", Ui.glass(false, 5.0, Color(1.0, 0.56, 0.14, 0.3), Ui.ACCENT))
	b.add_theme_stylebox_override("pressed", Ui.glass(false, 5.0, Color(1.0, 0.56, 0.14, 0.45), Ui.ACCENT))
	b.pressed.connect(f)
	return b


func _make_help() -> void:
	_help = _plate(false)
	_help.set_anchors_preset(Control.PRESET_CENTER)
	_help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_help.grow_vertical = Control.GROW_DIRECTION_BOTH
	_help.visible = false
	add_child(_help)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_help.add_child(col)
	Ui.label(col, "TUŞLAR", 26, Ui.INK, "display")
	Ui.rule(col)
	for pair in KEYS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		col.add_child(row)
		var h := Ui.label(row, Ui.upper(pair[0]), 15, Ui.ACCENT, "head")
		h.custom_minimum_size = Vector2(80, 0)
		var l := Ui.label(row, pair[1], 15, Ui.INK)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(620, 0)
	Ui.label(col, "F1 ya da Esc: kapat", 13, Ui.DIM, "head")


## While a building's being placed: turn it, or give up, with the mouse.
func _make_placing() -> void:
	_placing_plate = _plate(false)
	_placing_plate.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_placing_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_placing_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_placing_plate.offset_bottom = -126
	_placing_plate.visible = false
	add_child(_placing_plate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_placing_plate.add_child(row)
	_add(row, "↺ ÇEVİR", func() -> void: game.rotate_ghost(-15.0), "Sola çevir (Shift+R)")
	_add(row, "ÇEVİR ↻", func() -> void: game.rotate_ghost(15.0), "Sağa çevir (R)")
	_add(row, "VAZGEÇ", func() -> void: game.stop_placing(), "Koymaktan vazgeç (sağ tık / Esc)")


func toggle_help() -> bool:
	_help.visible = not _help.visible
	return _help.visible


func help_open() -> bool:
	return _help.visible


func _make_pause() -> void:
	_pause = _plate(false)
	_pause.set_anchors_preset(Control.PRESET_CENTER)
	_pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause.visible = false
	add_child(_pause)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(280, 0)
	_pause.add_child(col)
	Ui.label(col, "DURAKLATILDI", 28, Ui.INK, "display")
	Ui.rule(col)
	for pair in [["DEVAM", func() -> void: game.set_menu(false)], ["KAYDET", func() -> void: game.save_game()], ["YÜKLE", func() -> void: game.load_game()],
			["TUŞLAR", func() -> void: toggle_help()], ["YENİ OYUN", func() -> void: game.new_game()], ["KAYDET VE ÇIK", func() -> void:
				game.save_game()
				game.get_tree().quit()]]:
		var b := _small_button(pair[0], pair[1])
		b.custom_minimum_size = Vector2(0, 40)
		col.add_child(b)


func show_menu(on: bool) -> void:
	_pause.visible = on


func set_hint(text: String, bad := false) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", Ui.BAD if bad else Ui.INK)


func toast(text: String, kind := "info") -> void:
	var l := Ui.label(_toasts, text, 17, {"good": Ui.GOOD, "bad": Ui.BAD}.get(kind, Ui.INK), "strong")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.offset_top = 84
	while _toasts.get_child_count() > 4:
		_toasts.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


func _process(dt: float) -> void:
	_t += dt
	if _t < 0.15:
		return
	_t = 0.0
	var v: Village = game.village
	var stock := v.stock
	for id: String in _res:
		(_res[id] as Label).text = str(int(stock.get(id, 0)))
	(_res["yiyecek"] as Label).add_theme_color_override("font_color", Ui.BAD if int(stock.yiyecek) <= 5 else Ui.INK)
	_pop.text = "%d / %d" % [v.villagers.size(), v.beds()]
	_free.text = str(v.free_count())
	var guns := 0
	var shots := 0
	var bows := 0
	var arrows := 0
	for a in v.armories():
		guns += a.arms
		shots += a.ammo
		bows += a.bows
		arrows += a.arrows
	for x in v.villagers:
		if x.armed and not x.dead:
			if x.held == "bow":
				bows += 1
				arrows += x.ammo
			else:
				guns += 1
				shots += x.ammo
	_guns.text = "%d·%d" % [guns, shots]
	_bows.text = "%d·%d" % [bows, arrows]
	var w: Weather = game.weather
	var h := int(w.hour)
	var m := int((w.hour - h) * 60.0)
	_clock.text = "%s · %02d:%02d · %s %d°" % [game.seasons.label(), h, m, WEATHER_NAMES.get(w._state, w._state), roundi(w.temperature)]
	var rd: Raids = game.raids
	if rd.active:
		var alive := 0
		for x in rd.raiders:
			if is_instance_valid(x) and not x.dead:
				alive += 1
		_raid.text = "%d HAYDUT" % alive
		_raid.add_theme_color_override("font_color", Ui.BAD)
	else:
		_raid.text = ("GÜN %d" % rd.next_day) if rd.next_day > v.day else "BU GECE"
		_raid.add_theme_color_override("font_color", Ui.INK)
	var now := 0.0 if game.get_tree().paused else Engine.time_scale
	for k in _speed_buttons.size():
		var on := is_equal_approx(now, 0.0 if k == 0 else SPEEDS[k - 1])
		_speed_buttons[k].add_theme_stylebox_override("normal", Ui.glass(false, 5.0, Color(1.0, 0.56, 0.14, 0.4) if on else Color(1, 1, 1, 0.06), Ui.ACCENT if on else Ui.EDGE))
	for b: Node in _build_row.get_children():
		if b.has_meta("kind"):
			var can := true
			var cost: Dictionary = BuildingDefs.DEFS[b.get_meta("kind")].cost
			for r: String in cost:
				if int(stock.get(r, 0)) < int(cost[r]):
					can = false
			(b as Button).add_theme_color_override("font_color", Ui.INK if can else Ui.DIM)
	_update_card()


func _update_card() -> void:
	_placing_plate.visible = game._placing != "" and not game._placing in ["yol", "sur", "kapi"]
	var folk: Villager = game.selected_villager
	if folk and is_instance_valid(folk) and not folk.dead:
		_folk_card(folk)
		return
	var w: Wall = game.selected_wall
	if w and is_instance_valid(w):
		_wall_card(w)
		return
	var b: Building = game.selected
	if b == null or not is_instance_valid(b) or b.state == "gone":
		_card.visible = false
		return
	_card.visible = true
	_card_folk.visible = false
	_card_acts.visible = true
	_card_train.visible = b.state == "done" and b.def.role == "armory"
	(_btn.repair as Button).visible = b.state == "ruin" or (b.state == "done" and b.can_repair())
	_card_title.text = Ui.upper(b.display_name())
	var lines: Array[String] = []
	match b.state:
		"site", "repair":
			lines.append(("Onarılıyor: %%%d" if b.state == "repair" else "İnşa ediliyor: %%%d · " + b.stage_name()) % int(b.progress() * 100.0))
			var need: Array[String] = []
			for r: String in b.cost:
				need.append("%s %d/%d" % [BuildingDefs.RES_NAMES[r], int(b.delivered[r]), int(b.cost[r])])
			lines.append("Malzeme: " + " · ".join(need))
			var short: Array[String] = []
			for r: String in b.cost:
				if b.missing(r) > 0 and int(game.village.stock.get(r, 0)) <= 0:
					short.append(BuildingDefs.RES_NAMES[r].to_lower())
			if not short.is_empty():
				lines.append("Depoda yok: " + ", ".join(short))
		"ruin":
			lines.append("Harabe. ONAR ile parça parça yeniden yapılır, YIK ile kaldırılır.")
		"done":
			lines.append(str(b.def.desc))
	if b.is_burning():
		lines.append("YANIYOR! (%d parça)" % b.burning_count())
	if b.state == "done" and b.def.role == "house":
		var names: Array[String] = []
		for x in b.residents:
			if is_instance_valid(x):
				names.append(x.display_name)
		lines.append("Oturanlar (%d/%d): %s" % [b.residents.size(), int(b.def.beds), ", ".join(names) if not names.is_empty() else "kimse"])
		if not b.warm:
			lines.append("SOĞUK: yakacak bitti!")
		else:
			lines.append("Yakacak: %d odun" % int(b.goods.get("odun", 0)))
	if b.state == "done" and b.def.role in ["work", "farm", "forest", "bowyer", "builders"] and b.idle_note != "":
		lines.append(b.idle_note)
	var standing := b.standing_share()
	if standing < 0.999 and b.state != "ghost":
		lines.append("Ayakta kalan: %%%d" % int(standing * 100.0))
		if b.can_repair():
			var need: Array[String] = []
			var rc := b.repair_cost()
			for r: String in rc:
				need.append("%d %s" % [rc[r], BuildingDefs.RES_NAMES[r].to_lower()])
			lines.append("Onarım: %d parça · %s" % [b.fallen_count(), " · ".join(need)])
	if b.state == "done" and b.def.role == "armory":
		var rifles := 0
		var archers := 0
		var any := 0
		for x in game.village.villagers:
			if x.militia and not x.dead:
				match x.weapon:
					"rifle":
						rifles += 1
					"bow":
						archers += 1
					_:
						any += 1
		lines.append("Rafta: %d Mosin · %d fişek · %d yay · %d ok" % [b.arms, b.ammo, b.bows, b.arrows])
		lines.append("Milis: %d tüfekçi · %d okçu%s" % [rifles, archers, (" · %d elle işaretli" % any) if any > 0 else ""])
		if not b.training.is_empty():
			var q: Array[String] = []
			for t in b.training:
				q.append("tüfekçi" if t == "rifle" else "okçu")
			lines.append("Yetişecek: " + ", ".join(q))
			var tr: Variant = b.get_meta("trainee") if b.has_meta("trainee") else null
			if tr != null and is_instance_valid(tr) and str((tr as Villager).job).begins_with("Talim"):
				lines.append("Talimde: " + (tr as Villager).display_name)
			elif game.village._weapon_at(b, b.training[0]) == "":
				lines.append("Bekliyor: rafta %s yok" % ("tüfek" if b.training[0] == "rifle" else "yay ya da ok"))
	if b.goods_total() > 0 and b.def.role != "house":
		var g: Array[String] = []
		for r: String in b.goods:
			if int(b.goods[r]) > 0:
				g.append("%d %s" % [int(b.goods[r]), BuildingDefs.RES_NAMES[r].to_lower()])
		lines.append(("İçinde: " if b.def.role == "store" else "Yığın: ") + ", ".join(g))
	_card_workers.visible = b.def.role in ["work", "barracks", "tower", "carts", "oxen", "farm", "forest", "bowyer", "builders"] and b.state == "done"
	if _card_workers.visible:
		_card_count.text = "%d / %d" % [b.wanted, int(b.def.slots)]
		var names: Array[String] = []
		for x in b.workers:
			if is_instance_valid(x):
				names.append(x.display_name)
		lines.append("Çalışanlar: " + (", ".join(names) if not names.is_empty() else "kimse"))
		if b.workers.size() < b.wanted:
			lines.append("Boşta kasabalı yok: %d işçi eksik" % (b.wanted - b.workers.size()))
	_card_lines.text = "\n".join(lines)


func _wall_card(w: Wall) -> void:
	_card.visible = true
	_card_workers.visible = false
	_card_train.visible = false
	_card_folk.visible = false
	_card_acts.visible = true
	(_btn.repair as Button).visible = false
	_card_title.text = "KAZIK SUR"
	var up := 0
	var todo := 0
	for k in w.line.size():
		if w.built[k] == 1:
			up += 1
		elif w.built[k] == 0 and not w.in_gap(k):
			todo += 1
	var lines: Array[String] = []
	lines.append("Dikili: %d kazık · dikilecek: %d (%d odun)" % [up, todo, ceili(todo / float(Wall.WOOD_PER))])
	var gs: Array[String] = []
	for g in w.gates:
		if is_instance_valid(g):
			gs.append("kırık" if g.broken else ("açık" if g.is_open else "kapalı"))
	lines.append("Kapılar: " + (", ".join(gs) if not gs.is_empty() else "yok"))
	if not w.burning.is_empty():
		lines.append("YANIYOR: %d kazık (yavaş yanar; yağmur söndürür)" % w.burning.size())
	lines.append("")
	lines.append("Milis surun iç tarafındaki basamaktan ateş eder. YIK: sökülür, kazıkların yarısının odunu geri gelir.")
	_card_lines.text = "\n".join(lines)


func _folk_card(v: Villager) -> void:
	_card.visible = true
	_card_workers.visible = false
	_card_acts.visible = false
	_card_train.visible = false
	_card_folk.visible = true
	var many: Array = game._chosen()
	var guard: bool = v.workplace != null and v.workplace.def.role in ["barracks", "tower"]
	(_btn.release as Button).visible = v.workplace != null and many.size() <= 1
	(_btn.militia as Button).visible = not v.is_child and not guard
	(_btn.militia as Button).text = "MİLİSTEN ÇIKAR" if v.militia else "MİLİS YAP"
	(_btn.draft as Button).visible = v.militia and not v.down
	(_btn.draft as Button).text = "BIRAK" if v.drafted else "TOPLA"
	(_btn.lantern as Button).visible = v.militia
	(_btn.lantern as Button).text = "FENERİ YAK" if v.lantern_mode == "off" else "FENERİ SÖNDÜR"
	_card_title.text = Ui.upper(v.display_name) if many.size() <= 1 else "%d KİŞİ SEÇİLİ" % many.size()
	var lines: Array[String] = []
	lines.append("Ne yapıyor: " + v.job)
	lines.append("İşyeri: " + (v.workplace.display_name() if is_instance_valid(v.workplace) else "yok (taşır, inşa eder)"))
	lines.append("Evi: " + (v.home.display_name() if is_instance_valid(v.home) else "yok"))
	lines.append("Can: %d / %d" % [int(v.hp), int(v.max_hp)])
	if v.down:
		lines.append("YARALI, YERDE: %d sn içinde eve taşınmazsa ölecek" % int(v.bleed))
	if v.militia:
		lines.append("Milis (%s)%s · %s: %d · Fener: %s" % [{"rifle": "tüfekçi", "bow": "okçu"}.get(v.weapon, "silahı raftan"), " TOPLANDI" if v.drafted else "",
			"Ok" if v.held == "bow" else "Fişek", v.ammo, {"": "oto", "off": "sönük", "on": "yanık"}[v.lantern_mode]])
		if v.in_cover:
			lines.append("Siperde")
	if v.carry_n > 0:
		lines.append("Taşıdığı: %d %s" % [v.carry_n, str(BuildingDefs.RES_NAMES.get(v.carry_res, v.carry_res)).to_lower()])
	if many.size() > 1:
		var names: Array[String] = []
		for x in many:
			names.append((x as Villager).display_name)
		lines.append("Seçili: " + ", ".join(names))
	lines.append("")
	if v.drafted:
		lines.append("Toplandı: yere sağ tık mevzi (siper arar), hayduda sağ tık hedef.")
	else:
		lines.append("Bir işyerine, tarlaya ya da karakola sağ tıkla: oraya ata. Shift+tık: birkaç kişi seç.")
	_card_lines.text = "\n".join(lines)
