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
const CATS := [["KASABA", ["ev", "ambar", "kuyu", "fener", "meydan", "cankulesi", "okuma"]], ["ÜRETİM", ["tarla", "oduncu", "tasci", "camur", "toplayici", "sifaci"]],
	["TAŞIMA", ["yol", "arabaci"]], ["SAVUNMA", ["sur", "kapi", "kule", "silahlik", "demirci", "hapishane"]], ["EMİRLER", ["kes", "kesme", "tuzak"]]]
## What's ordered on the ground rather than built (Main.AREA_ORDERS): the build bar's EMİRLER.
const ORDERS := {"kes": {"name": "Kes", "gives": "herkes önce bunları keser", "desc": "Bir alan sürükle ya da bir ağaca tıkla: kırmızı kurdele bağlanır, oduncu becerisi 'hiç' olmayan herkes işini bırakıp önce bu ağaçları keser, tomrukları depoya taşınır. Bitince herkes işine döner. Bina gerekmez."},
	"kesme": {"name": "Kesme", "gives": "kesim işaretini kaldırır", "desc": "Bir alan sürükle: içindeki ağaçların kesim işareti kalkar."},
	"tuzak": {"name": "Tuzak", "gives": "haydutu yaralar, yavaşlatır", "desc": "Bir alan sürükle ya da bir yere tıkla: gizli kazık çukurları kazılır (çukur başı 2 odun). Üstünden geçen haydut yaralanır, topallar; çukur bozulur. Aynı yere yeniden TUZAK verince bozulanlar kurulur. Köylüler yerini bilir, düşmez."}}
const SPEEDS := [1.0, 2.0, 4.0]
## Every key, in one place (the help card, F1). Nothing needs a key: what the selected thing can do
## is a button on its card, and the build bar, the speed and the menu have their own.
const KEYS := [
	["Kamera", "WASD / ok tuşları / ekran kenarı: kaydır · Shift: hızlı · Q E / orta tuş: döndür · tekerlek: yakınlaş · H: depoya dön"],
	["Bina", "Tab: bina grubu · 1-6: bina seç · sol tık: koy · Shift+tık: üst üste koy · R / Shift+R: çevir · sağ tık / Esc: vazgeç · tahta yol: sürükle"],
	["Seçim", "Sol tık: bina ya da kasabalı seç · Shift+tık: birkaç kasabalı · kasabalı seçiliyken sağ tık bir işyerine: oraya ata"],
	["Kart", "Seçtiğin şeyin yapabileceği her şey kartında düğme: onar, yık, işçi ekle, milis yap, topla, fener, tüfekçi / okçu yetiştir..."],
	["Kasabalılar", "K ya da üstteki KASABALILAR: herkesin becerileri; bir beceriye tıkla: o işe önce verilsin (▲), normal, hiç verilmesin (–)"],
	["Kısayol", "O: onar · Del: yık · M: milis yap · G: milisi topla / bırak · L: fener · toplanmışken sağ tık: mevzi (siper arar) · hayduda sağ tık: ona ateş"],
	["Zaman", "Boşluk: duraklat (durmuşken de emir verilir) · + / -: hızlandır, yavaşlat · F5: kaydet · F9: yükle · Esc: menü"],
	["Görüntü", "P: fotoğraf modu (ekran gizlenir, uzak bulanıklaşır; tekrar P ile çık)"],
	["Deneme", "F: seçili binayı tutuştur · B: haydut baskını · N: inşaatları bitir"],
]

var game: Node
var category := 0

var _res: Dictionary = {} ## good -> [row, amount Label, change Label]
const GOODS := ["odun", "tas", "yiyecek", "camur", "kerpic", "ot", "komur", "demir"]
const GOOD_TIPS := {"odun": "Kesim kampından: inşaat ve evlerin, fenerlerin yakacağı",
	"tas": "Taş ocağından: temeller, bacalar, kuyu, meydan", "yiyecek": "Tarladan ve toplayıcıdan: herkes yer, öküzler de",
	"camur": "Çamur ocağından: evleri sıvamak için", "kerpic": "Çamur ocağında kerpiç yaptırınca: soba için",
	"ot": "Şifacının ormandan topladığı: her yara sarışta bir tane gider",
	"komur": "Kömür ocağında odundan yakılır: demircinin ocağı için", "demir": "Demir madeninden: demirci tüfek ve fişek döver"}
var _seen := {} ## goods once had: shown from then on
var _goods_head: Button
var _folds: Array = [] ## [header, body, seconds since the mouse left both]
var _history: Array = [] ## [clock, stock] every few seconds, the last minute's
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
var _people_plate: PanelContainer ## the townsfolk table
var _people_grid: GridContainer
var _people_rows: Array = [] ## the villagers the table's rows are for
var _people_t := 0.0
var _card_train: HBoxContainer
var _card_pick: VBoxContainer ## a workplace's card: who's best at its work, to put on or take off it
var _pick_title: Label
var _pick_rows: Array = [] ## [HBoxContainer, name Label, knack Label, where Label, Button, face TextureRect]
var _pick_for: Array = [] ## the villager each row is showing
var _pick_open: Building ## the workplace whose list is open (ATA); another picked, it shuts
var _pick_btn: Button
var _guns: Label
var _bows: Label
var _pause: PanelContainer
var _help: PanelContainer
var _t := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stores_plate()
	_goods_plate()
	_clock_plate()
	_build_bar()
	add_child(Portraits.new())
	_make_card()
	_make_dial()
	_strip = FolkStrip.new()
	_strip.game = game
	_strip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_strip.offset_left = 12
	_strip.offset_bottom = -52
	add_child(_strip)
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
	_make_people()
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


## The goods down the left: each as it's first had, how much is in the stores, and how it's gone
## the last minute.
func _goods_plate() -> void:
	var p := _plate()
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.offset_left = 12
	p.offset_top = 84
	add_child(p)
	_fold(_goods_head, p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.custom_minimum_size = Vector2(170, 0)
	p.add_child(col)
	Ui.label(col, "KAYNAKLAR", 13, Ui.ACCENT, "head")
	for id: String in GOODS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.tooltip_text = str(GOOD_TIPS[id]) + "\n(bütün depolardakinin toplamı; yanında son bir dakikadaki değişim)"
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.visible = false
		col.add_child(row)
		var icon := TextureRect.new() # (drawn in ink: tools/ink_icons.gd)
		icon.custom_minimum_size = Vector2(30, 30)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ResourceLoader.exists("res://assets/ui/ink/%s.png" % id):
			icon.texture = load("res://assets/ui/ink/%s.png" % id)
		row.add_child(icon)
		var name := Ui.label(row, Ui.upper(BuildingDefs.RES_NAMES[id]), 13, Ui.DIM, "head")
		name.custom_minimum_size = Vector2(62, 0)
		var amount := Ui.label(row, "0", 22, Ui.INK, "display")
		amount.custom_minimum_size = Vector2(52, 0)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var change := Ui.label(row, "", 13, Ui.DIM, "head")
		change.custom_minimum_size = Vector2(40, 0)
		_res[id] = [row, amount, change]
	# the arms: rifles and their cartridges, bows and their arrows (in the armouries and in hand)
	for arm: Array in [["TÜFEK", "Silahlıklardaki ve eldeki Mosin tüfekleri · fişek"], ["YAY", "Silahlıklardaki ve eldeki yaylar · ok"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.tooltip_text = str(arm[1])
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.visible = false
		col.add_child(row)
		Ui.label(row, str(arm[0]), 13, Ui.DIM, "head").custom_minimum_size = Vector2(70, 0)
		var amount := Ui.label(row, "", 20, Ui.INK, "display")
		amount.custom_minimum_size = Vector2(52, 0)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if arm[0] == "TÜFEK":
			_guns = amount
		else:
			_bows = amount


## The goods column's numbers, and the minute's change (sampled every few seconds of game time).
func _refresh_goods(v: Village, stock: Dictionary) -> void:
	if _history.is_empty() or v.clock - float(_history[-1][0]) >= 5.0:
		_history.append([v.clock, stock.duplicate()])
		while _history.size() > 1 and v.clock - float(_history[0][0]) > 62.0:
			_history.pop_front()
	var then: Dictionary = _history[0][1]
	for id: String in GOODS:
		var n := int(stock.get(id, 0))
		if n > 0:
			_seen[id] = true
		var parts: Array = _res[id]
		(parts[0] as Control).visible = _seen.has(id) or id in ["odun", "tas", "yiyecek"]
		(parts[1] as Label).text = str(n)
		(parts[1] as Label).add_theme_color_override("font_color", Ui.BAD if id == "yiyecek" and n <= 5 else Ui.INK)
		var d := n - int(then.get(id, 0))
		(parts[2] as Label).text = ("+%d" % d) if d > 0 else (str(d) if d < 0 else "")
		(parts[2] as Label).add_theme_color_override("font_color", Ui.GOOD if d > 0 else Ui.BAD)
	_goods_head.add_theme_color_override("font_color", Ui.BAD if int(stock.get("yiyecek", 0)) <= 5 else Ui.INK) # (short of food: it says so, folded or not)


func _stores_plate() -> void:
	var p := _plate()
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.offset_left = 12
	p.offset_top = 10
	add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	p.add_child(row)
	var pair := HBoxContainer.new() # (the two that open something, side by side)
	pair.add_theme_constant_override("separation", 6)
	row.add_child(pair)
	_goods_head = _small_button("KAYNAKLAR ▾", func() -> void: pass)
	_goods_head.tooltip_text = "Depolardaki odun, taş, yiyecek, silahlar...: üzerine gel"
	pair.add_child(_goods_head)
	var who := _small_button("KASABALILAR", func() -> void: toggle_people())
	who.tooltip_text = "Herkesin becerileri ve hangi işe öncelikle verileceği (K)"
	pair.add_child(who)
	_pop = _stat(row, "NÜFUS", "Kasabalılar / yataklar")
	_free = _stat(row, "BOŞTA", "Bir işyerine verilmemiş, taşıyıp inşa eden kasabalılar")


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
	_clock = _stat(row, "GÜN · SAAT · HAVA")
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


## Bottom right, folded under its name: to try things out at once.
func _test_plate() -> void:
	var head := _small_button("DENEME ▴", func() -> void: pass)
	head.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	head.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	head.grow_vertical = Control.GROW_DIRECTION_BEGIN
	head.offset_right = -12
	head.offset_bottom = -10
	add_child(head)
	var p := _plate(false, Color(0.05, 0.055, 0.06, 0.8))
	p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -12
	p.offset_bottom = -46
	add_child(p)
	_fold(head, p)
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
	var build := _small_button("İNŞAATI BİTİR", func() -> void: game.test_build()) # (a test, to come out later)
	build.tooltip_text = "Yapımdaki ve onarılan her şeyi hemen bitir (N)"
	row2.add_child(build)
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
		_build_row.add_child(_build_button(kinds[k], k))


## A build bar button: the building's picture (assets/ui/icons, made by tools/building_icons.gd),
## its key and name, what it brings (and how many work there), what it costs (red while the stores
## can't cover it).
func _build_button(kind: String, k: int) -> Button:
	var def: Dictionary = ORDERS[kind] if ORDERS.has(kind) else BuildingDefs.DEFS[kind]
	var b := Button.new()
	b.tooltip_text = str(def.desc)
	b.custom_minimum_size = Vector2(134, 124)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", Ui.glass(false, 6.0, Color(1, 1, 1, 0.05)))
	var hover := Ui.glass(false, 6.0, Color(1.0, 0.56, 0.14, 0.25), Ui.ACCENT)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.set_meta("kind", kind)
	b.pressed.connect(func() -> void: game.start_placing(kind))
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 4
	col.offset_right = -4
	col.offset_top = 3
	col.offset_bottom = -3
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(0, 62)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := "res://assets/ui/icons/%s.png" % kind
	if ResourceLoader.exists(path):
		icon.texture = load(path)
	col.add_child(icon)
	var name := Ui.label(col, "%d  %s" % [k + 1, Ui.upper(str(def.name))], 13, Ui.INK, "head")
	var gives := str(def.gives) if ORDERS.has(kind) else str(BuildingDefs.GIVES.get(kind, ""))
	if int(def.get("slots", 0)) > 0:
		gives += " · %d kişi" % int(def.slots)
	var give := Ui.label(col, gives, 11, Ui.GOOD, "head")
	var cost := Ui.label(col, "bedava" if ORDERS.has(kind) else BuildingDefs.cost_text(kind), 11, Ui.DIM, "head")
	var needs := "" if ORDERS.has(kind) else str(def.get("needs", ""))
	if needs != "":
		b.set_meta("needs", needs)
		b.tooltip_text = "KİLİTLİ: okuma odasında %s araştırılınca açılır.\n\n%s" % [BuildingDefs.TECHS[needs].name, def.desc]
	for l: Label in [name, give, cost]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.set_meta("cost_label", cost)
	return b


## The kind under key `n` (0-based) in the shown group, or "".
func kind_at(n: int) -> String:
	var kinds: Array = CATS[category][1]
	return kinds[n] if n >= 0 and n < kinds.size() else ""


var _dial: SeasonDial
var _card_jail: VBoxContainer ## a jail's card: a row each held, with what to do with them
var _jail_rows: Array = [] ## the prisoner each row was built for
var _card_extra: VBoxContainer ## a station's orders, a reading room's studies
var _extra_sig := "" ## what it was last built for (rebuilt only when that changes)
var _extra_status: Label
var _strip: FolkStrip


## The year's dial, top middle: the seasons, today, how long the food and firewood will last.
func _make_dial() -> void:
	var p := _plate()
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.offset_top = 8
	add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	p.add_child(row)
	_dial = SeasonDial.new()
	_dial.game = game
	row.add_child(_dial)
	_dial.make_labels(row)


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
	_make_folk_box(col)
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
	_pick_btn = _add(_card_workers, "ATA ▾", func() -> void: _pick_open = null if _pick_open == game.selected else game.selected,
		"Kimin bu işe en yatkın olduğunu gör ve ata")
	_card_pick = VBoxContainer.new()
	_card_pick.add_theme_constant_override("separation", 3)
	col.add_child(_card_pick)
	_pick_title = Ui.label(_card_pick, "", 13, Ui.ACCENT, "head")
	for i in 10:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_card_pick.add_child(row)
		var face := TextureRect.new()
		face.custom_minimum_size = Vector2(40, 40)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		row.add_child(face)
		var nm := Ui.label(row, "", 14, Ui.INK)
		nm.custom_minimum_size = Vector2(140, 0)
		nm.clip_text = true
		var kn := Ui.label(row, "", 16, Ui.INK, "display")
		kn.custom_minimum_size = Vector2(44, 0)
		kn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var wh := Ui.label(row, "", 12, Ui.DIM)
		wh.custom_minimum_size = Vector2(110, 0)
		wh.clip_text = true
		var idx := i
		var bt := _small_button("ATA", func() -> void: _pick(idx))
		bt.custom_minimum_size = Vector2(96, 26)
		row.add_child(bt)
		_pick_rows.append([row, nm, kn, wh, bt, face])
	_card_extra = VBoxContainer.new()
	_card_extra.add_theme_constant_override("separation", 4)
	col.add_child(_card_extra)
	_card_jail = VBoxContainer.new()
	_card_jail.add_theme_constant_override("separation", 6)
	col.add_child(_card_jail)
	_card_acts = HBoxContainer.new()
	_card_acts.add_theme_constant_override("separation", 8)
	col.add_child(_card_acts)
	_btn.repair = _add(_card_acts, "ONAR", func() -> void: game.repair_selected(), "Yıkılan parçaları yeniden yap (O)")
	for what: String in BuildingDefs.UPGRADES:
		var up: Dictionary = BuildingDefs.UPGRADES[what]
		_btn["up_" + what] = _add(_card_acts, str(up.name), func() -> void: game.upgrade_selected(what),
			"%s (%s)" % [up.tip, BuildingDefs.cost_text_of(up.cost)])
	_btn.mode = _add(_card_acts, "KERPİÇ YAP", func() -> void: game.toggle_mode_selected(), "Çamuru kalıba döküp kerpiç kurutsunlar / yalnızca çamur kazsınlar")
	_btn.demolish = _add(_card_acts, "YIK", func() -> void: game.demolish_selected(), "Binayı kaldır (Del)")
	_btn.look = _add(_card_acts, "ODAKLAN", func() -> void: game.focus_building(), "Kamerayı binaya götür")
	_btn.plant = _add(_card_acts, "FİDAN DİK", func() -> void: game.toggle_planting(), "Kesimciler boş kaldıkça kesilen ağaçların kütüklerine fidan diksin")
	_btn.ox = _add(_card_acts, "ÖKÜZ AL", func() -> void: game.buy_oxen(), "Arabalar öküz arabası olsun: 30 yük, yavaş; her öküz bir kişi kadar yer (%s)" % BuildingDefs.cost_text_of(BuildingDefs.OX_COST))
	_btn.strong = _add(_card_acts, "GÜÇLENDİR", func() -> void: game.strengthen_wall(), "Kalın kütük ve taş temel: kazıklar üç kat dayanıklı olur, zor kesilir, zor yanar")
	_btn.area = _add(_card_acts, "ALAN ÇİZ", func() -> void: game.start_placing("alan"), "İşçiler yalnızca sürükleyeceğin alanda çalışsın")
	_btn.no_area = _add(_card_acts, "ALANI KALDIR", func() -> void: game.clear_work_area(), "İşçiler yine her yerde çalışsın")
	_card_train = HBoxContainer.new()
	_card_train.add_theme_constant_override("separation", 8)
	col.add_child(_card_train)
	_card_train.add_child(_small_button("+ TÜFEKÇİ", func() -> void: game.train("rifle")))
	_card_train.add_child(_small_button("+ OKÇU", func() -> void: game.train("bow")))
	_card_train.add_child(_small_button("SIRAYI SİL", func() -> void: game.train("")))
	_btn.cast = _small_button("FİŞEK DÖK", func() -> void:
		var a: Building = game.selected
		if a and is_instance_valid(a):
			a.casting = not a.casting)
	_btn.cast.tooltip_text = "Her sabah 2 taş ve 1 odundan 6 fişek dökülür"
	_card_train.add_child(_btn.cast)
	_btn.bows = _small_button("YAY YAP", func() -> void:
		var a: Building = game.selected
		if a and is_instance_valid(a):
			a.bowing = not a.bowing)
	_btn.bows.tooltip_text = "Her sabah depodan odun alınıp bir yay (2 odun) ya da 12 ok (1 odun) yapılır"
	_card_train.add_child(_btn.bows)

	_card_folk = HBoxContainer.new()
	_card_folk.add_theme_constant_override("separation", 8)
	col.add_child(_card_folk)
	_btn.release = _add(_card_folk, "İŞTEN AL", func() -> void: game.release_selected(), "İşyerinden çıkar: taşır, inşa eder")
	_btn.militia = _add(_card_folk, "MİLİS YAP", func() -> void: game.toggle_militia(), "Tehlike çanında silahlıktan silah alıp mevziye geçer (M)")
	_btn.draft = _add(_card_folk, "TOPLA", func() -> void: game.toggle_draft(), "Emrine al: sağ tık mevzi, hayduda sağ tık hedef (G)")
	_btn.lantern = _add(_card_folk, "FENERİ SÖNDÜR", func() -> void: game.toggle_lantern(), "Karanlıkta görünmez olur ama az görür (L)")
	_btn.folk_look = _add(_card_folk, "ODAKLAN", func() -> void: game.focus_selected(), "Kamerayı ona götür")


## The workplace card's list: everyone grown, best at the work first; those working here marked.
func _fill_pick(b: Building) -> void:
	var sk := Villager.skill_of(b)
	var folk: Array = game.village.villagers.filter(func(v: Villager) -> bool: return not v.dead and not v.is_child)
	folk.sort_custom(func(a: Villager, c: Villager) -> bool: return a.skill(sk) > c.skill(sk))
	_pick_title.text = "EN UYGUN: %s · %d / %d kişi" % [Ui.upper(str(Villager.SKILLS.get(sk, "iş"))), b.workers.size(), int(b.def.slots)]
	_pick_for = folk.slice(0, _pick_rows.size())
	var full := b.workers.size() >= int(b.def.slots)
	for i in _pick_rows.size():
		var row: Array = _pick_rows[i]
		(row[0] as Control).visible = i < _pick_for.size()
		if i >= _pick_for.size():
			continue
		var v: Villager = _pick_for[i]
		var here := v.workplace == b
		(row[5] as TextureRect).texture = Portraits.of(v)
		(row[1] as Label).text = v.display_name
		(row[1] as Label).add_theme_color_override("font_color", Ui.ACCENT if here else Ui.INK)
		(row[2] as Label).text = str(int(v.skill(sk))) + (" ♥" if sk in v.keen else "")
		(row[2] as Label).tooltip_text = "Bu işe hevesli: iki kat hızlı öğrenir" if sk in v.keen else ""
		(row[2] as Label).mouse_filter = Control.MOUSE_FILTER_PASS
		(row[2] as Label).add_theme_color_override("font_color", Ui.GOOD if v.skill(sk) >= 6.0 else (Ui.DIM if v.skill(sk) < 2.0 else Ui.INK))
		var pr := int(v.prio.get(sk, 1))
		(row[3] as Label).text = ("burada" if here else (v.workplace.display_name() if is_instance_valid(v.workplace) else "boşta")) + (" · ▲" if pr == 2 else (" · –" if pr == 0 else ""))
		(row[4] as Button).text = "ÇIKAR" if here else ("DEĞİŞTİR" if full else "ATA")
		(row[4] as Button).tooltip_text = "İşten al" if here else ("Buradaki en beceriksizin yerine koy" if full else "Bu işe ver")


func _pick(i: int) -> void:
	var b: Building = game.selected
	if b == null or not is_instance_valid(b) or i >= _pick_for.size():
		return
	var v: Villager = _pick_for[i]
	if not is_instance_valid(v) or v.dead:
		return
	if v.workplace == b:
		game.village.free_from_work(v)
		toast("%s işten alındı" % v.display_name, "info")
		return
	if b.workers.size() >= int(b.def.slots):
		# (full: the one here who's worst at it makes room)
		var sk := Villager.skill_of(b)
		var worst: Villager = null
		for w in b.workers:
			if is_instance_valid(w) and (worst == null or (w as Villager).skill(sk) < worst.skill(sk)):
				worst = w
		if worst:
			game.village.free_from_work(worst)
	var why: String = game.village.assign(v, b)
	toast(why if why != "" else "%s artık %s'de çalışıyor" % [v.display_name, b.display_name()], "info" if why != "" else "good")


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
	b.add_theme_color_override("font_color", Ui.INK)
	b.add_theme_color_override("font_hover_color", Ui.ACCENT)
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


## The townsfolk table: a row each, their knack at each kind of work (0-10, growing as they do it),
## and, clicked, whether they're put to it first (▲), as needed, or never (–).
func _make_people() -> void:
	_people_plate = _plate(false)
	_people_plate.set_anchors_preset(Control.PRESET_CENTER)
	_people_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_people_plate.grow_vertical = Control.GROW_DIRECTION_BOTH
	_people_plate.visible = false
	add_child(_people_plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_people_plate.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	Ui.label(head, "KASABALILAR", 26, Ui.INK, "display")
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(_small_button("KAPAT", func() -> void: toggle_people()))
	Ui.rule(col)
	Ui.label(col, "Sayı: beceri (iş yaptıkça artar). ♥ hevesli: iki kat hızlı öğrenir. Tıkla: ▲ önce bu işe verilir · normal · – bu işe hiç verilmez.", 14, Ui.DIM)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(980, 420)
	col.add_child(scroll)
	_people_grid = GridContainer.new()
	_people_grid.columns = 2 + Villager.SKILLS.size()
	_people_grid.add_theme_constant_override("h_separation", 6)
	_people_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_people_grid)


func toggle_people() -> void:
	_people_plate.visible = not _people_plate.visible
	_people_rows = []
	_refresh_people()


func _refresh_people() -> void:
	if not _people_plate.visible:
		return
	var folk: Array = game.village.villagers.filter(func(v: Villager) -> bool: return not v.dead)
	folk.sort_custom(func(a: Villager, b: Villager) -> bool: return a.family + a.display_name < b.family + b.display_name)
	if folk != _people_rows:
		_people_rows = folk
		for c in _people_grid.get_children():
			c.queue_free()
		Ui.label(_people_grid, "KİŞİ", 13, Ui.ACCENT, "head").custom_minimum_size = Vector2(170, 0)
		Ui.label(_people_grid, "NE YAPIYOR", 13, Ui.ACCENT, "head").custom_minimum_size = Vector2(170, 0)
		for k: String in Villager.SKILLS:
			var h := Ui.label(_people_grid, Ui.upper(str(Villager.SKILLS[k])).substr(0, 6), 12, Ui.ACCENT, "head")
			h.custom_minimum_size = Vector2(64, 0)
			h.tooltip_text = str(Villager.SKILLS[k])
			h.mouse_filter = Control.MOUSE_FILTER_PASS
		for v: Villager in folk:
			var n := Ui.label(_people_grid, v.display_name + (" (çocuk)" if v.is_child else ""), 14, Ui.INK)
			n.custom_minimum_size = Vector2(170, 0)
			var j := Ui.label(_people_grid, "", 13, Ui.DIM)
			j.custom_minimum_size = Vector2(170, 0)
			j.clip_text = true
			for k: String in Villager.SKILLS:
				var who := v
				var key := k
				var b := _small_button("", func() -> void:
					who.prio[key] = [2, 0, 1][int(who.prio.get(key, 1))] # (normal -> first -> never -> normal)
					_refresh_people())
				b.custom_minimum_size = Vector2(64, 28)
				b.tooltip_text = "%s · %s" % [v.display_name, Villager.SKILLS[k]]
				b.disabled = v.is_child
				_people_grid.add_child(b)
	var cols := 2 + Villager.SKILLS.size()
	for i in folk.size():
		var v: Villager = folk[i]
		var base := cols * (i + 1)
		(_people_grid.get_child(base + 1) as Label).text = v.job
		var c := 0
		for k: String in Villager.SKILLS:
			var b := _people_grid.get_child(base + 2 + c) as Button
			var pr := int(v.prio.get(k, 1))
			b.text = ("%d%s%s" % [int(v.skill(k)), "♥" if k in v.keen else "", " ▲" if pr == 2 else ""]) if pr != 0 else "–"
			b.add_theme_color_override("font_color", Ui.ACCENT if pr == 2 else (Ui.DIM if pr == 0 else (Ui.GOOD if v.skill(k) >= 6.0 else Ui.INK)))
			c += 1


func people_open() -> bool:
	return _people_plate.visible


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
			["TUŞLAR", func() -> void: toggle_help()], ["AYARLAR", func() -> void: _show_settings(true)], ["YENİ OYUN", func() -> void: game.new_game()], ["KAYDET VE ÇIK", func() -> void:
				game.save_game()
				game.get_tree().quit()]]:
		var b := _small_button(pair[0], pair[1])
		b.custom_minimum_size = Vector2(0, 40)
		col.add_child(b)


func show_menu(on: bool) -> void:
	_pause.visible = on
	if not on and _settings:
		_settings.visible = false


var _settings: SettingsPanel


## The settings plate over the pause menu.
func _show_settings(on: bool) -> void:
	if _settings == null:
		_settings = SettingsPanel.new()
		_settings.weather = game.weather
		_settings.cam = game.cam
		_settings.set_anchors_preset(Control.PRESET_CENTER)
		_settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_settings.grow_vertical = Control.GROW_DIRECTION_BOTH
		_settings.closed.connect(func() -> void: _pause.visible = true)
		add_child(_settings)
	_settings.visible = on
	_pause.visible = not on


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


## `body` folded away under `header`: it slides out as the mouse comes onto the header and folds
## again a moment after the mouse has left both.
func _fold(header: Control, body: Control) -> void:
	body.visible = false
	_folds.append([header, body, 1.0, null])


func _unfold(dt: float) -> void:
	for f: Array in _folds:
		var header: Control = f[0]
		var body: Control = f[1]
		var at := header.get_global_mouse_position()
		var over := header.is_visible_in_tree() and (header.get_global_rect().has_point(at) or (body.visible and body.get_global_rect().grow(6.0).has_point(at)))
		f[2] = 0.0 if over else float(f[2]) + dt
		if over and not body.visible:
			body.visible = true
			body.modulate.a = 0.0
			var down := body.grow_vertical != Control.GROW_DIRECTION_BEGIN
			if f[3] == null:
				f[3] = body.position # (where it stands open, kept: a slide cut short won't move it)
			var to: Vector2 = f[3]
			body.position = to + Vector2(0, -10 if down else 10)
			var tw := create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_property(body, "modulate:a", 1.0, 0.16)
			tw.tween_property(body, "position", to, 0.16)
		elif body.visible and float(f[2]) > 0.35:
			body.visible = false


func _process(dt: float) -> void:
	_unfold(dt)
	_t += dt
	if _t < 0.15:
		return
	_t = 0.0
	var v: Village = game.village
	var stock := v.stock
	_refresh_goods(v, stock)
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
	_guns.get_parent().visible = guns + shots > 0 # (in the goods column once there are any)
	_bows.get_parent().visible = bows + arrows > 0
	var w: Weather = game.weather
	var h := int(w.hour)
	var m := int((w.hour - h) * 60.0)
	_clock.text = "Gün %d · %02d:%02d · %s" % [game.village.day, h, m, WEATHER_NAMES.get(w._state, w._state)]
	_dial.refresh()
	_strip.refresh()
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
		if b.has_meta("kind") and BuildingDefs.DEFS.has(b.get_meta("kind")):
			var can := true
			var cost: Dictionary = BuildingDefs.DEFS[b.get_meta("kind")].cost
			for r: String in cost:
				if int(stock.get(r, 0)) < int(cost[r]):
					can = false
			var lbl := b.get_meta("cost_label") as Label
			if b.has_meta("needs") and not game.village.knows(str(b.get_meta("needs"))):
				lbl.text = "KİLİTLİ · %s" % Ui.upper(str(BuildingDefs.TECHS[b.get_meta("needs")].name))
				lbl.add_theme_color_override("font_color", Ui.BAD)
				(b as Control).modulate.a = 0.45
				continue
			lbl.text = BuildingDefs.cost_text(b.get_meta("kind"))
			lbl.add_theme_color_override("font_color", Ui.DIM if can else Ui.BAD)
			(b as Control).modulate.a = 1.0 if can else 0.75
	_update_card()


func _update_card() -> void:
	_people_t += 0.016
	if _people_t > 0.5:
		_people_t = 0.0
		_refresh_people()
	if _people_plate.visible:
		_card.visible = false # (the table's over where the card stands)
		return
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
	_folk_box.visible = false
	_card_jail.visible = false
	_card_extra.visible = false
	_card_acts.visible = true
	_card_train.visible = b.state == "done" and b.kind == "silahlik"
	if _card_train.visible:
		(_btn.cast as Button).text = "FİŞEK DÖKÜMÜNÜ DURDUR" if b.casting else "FİŞEK DÖK"
		(_btn.bows as Button).text = "YAY YAPMAYI DURDUR" if b.bowing else "YAY YAP"
	_card_pick.visible = _pick_open == b and b.state == "done" and b.def.role in ["work", "farm", "carts", "barracks", "tower", "research", "smith", "healer"]
	_pick_btn.text = "ATA ▴" if _card_pick.visible else "ATA ▾"
	if _card_pick.visible:
		_fill_pick(b)
	(_btn.repair as Button).visible = b.state == "ruin" or (b.state == "done" and b.can_repair())
	_fill_jail(b)
	_fill_extra(b)
	for what: String in BuildingDefs.UPGRADES:
		(_btn["up_" + what] as Button).visible = b.can_upgrade(what)
	(_btn.mode as Button).visible = b.state == "done" and (b.kind == "camur" or (b.kind == "tasci" and game.village.knows("madencilik")))
	(_btn.plant as Button).visible = b.kind == "oduncu" and b.state == "done"
	(_btn.plant as Button).text = "FİDAN DİKMEYİ BIRAK" if b.planting else "FİDAN DİK"
	(_btn.ox as Button).visible = b.kind == "arabaci" and b.state == "done" and not b.ox
	(_btn.strong as Button).visible = false
	(_btn.area as Button).visible = b.def.role in ["work", "forest"] and b.kind != "camur" and b.state == "done"
	(_btn.no_area as Button).visible = (_btn.area as Button).visible and b.work_area.has_area()
	if b.kind == "tasci":
		(_btn.mode as Button).text = "TAŞ KIR" if b.mode == "demir" else "DEMİR ÇIKAR"
	else:
		(_btn.mode as Button).text = "ÇAMUR KAZ" if b.mode == "kerpic" else "KERPİÇ YAP"
	_card_title.text = Ui.upper(b.display_name())
	var lines: Array[String] = []
	match b.state:
		"site", "repair":
			lines.append(({"oda": "Büyütülüyor: %%%d", "siva": "Sıvanıyor: %%%d", "soba": "Soba yapılıyor: %%%d"}.get(b.upgrading, "Onarılıyor: %%%d") if b.state == "repair" else "İnşa ediliyor: %%%d · " + b.stage_name()) % int(b.progress() * 100.0))
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
		var fams := {}
		for x in b.residents:
			if is_instance_valid(x):
				var fx := x as Villager
				if not fams.has(fx.family):
					fams[fx.family] = []
				(fams[fx.family] as Array).append(fx.display_name.split(" ")[0] + (" (çocuk)" if fx.is_child else ""))
		var parts: Array[String] = []
		for f: String in fams:
			parts.append("%s ailesi: %s" % [f, ", ".join(fams[f])])
		lines.append("Oturanlar (%d/%d): %s" % [b.residents.size(), b.beds(), " · ".join(parts) if not parts.is_empty() else "kimse"])
		if not b.warm:
			lines.append("SOĞUK: yakacak bitti!")
		else:
			lines.append("Yakacak: %d odun" % int(b.goods.get("odun", 0)))
		var has: Array[String] = []
		if b.level >= 2:
			has.append("ek oda")
		if b.plastered:
			has.append("sıvalı")
		if b.stove:
			has.append("kerpiç soba")
		if not has.is_empty():
			lines.append("Ev: %s · yakacak %%%d" % [", ".join(has), roundi(b.fuel_mul() * 100.0)])
	if b.kind == "camur" and b.state == "done":
		lines.append("Yapılan: " + ("kerpiç" if b.mode == "kerpic" else "çamur"))
		if b.drying_count() > 0:
			var why := ""
			if Weather.snow_cover_now > 0.3 or game.weather.temperature < 0.0:
				why = " (ayazda kurumaz)"
			elif Weather.rain_now > 0.15:
				why = " (yağmurda yavaş)"
			lines.append("Rafta kuruyan: %d kerpiç%s" % [b.drying_count(), why])
	if b.state == "done" and b.def.role in ["work", "farm", "research", "smith", "healer"] and b.idle_note != "":
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
	if b.state == "done" and b.kind == "silahlik":
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
		lines.append("Fişek dökümü: %s" % ("açık · her sabah 6 fişek (2 taş, 1 odun)" if b.casting else "kapalı"))
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
	_card_workers.visible = b.def.role in ["work", "barracks", "tower", "carts", "farm", "research", "smith", "healer"] and b.state == "done"
	if _card_workers.visible:
		_card_count.text = "%d / %d" % [b.wanted, int(b.def.slots)]
		var names: Array[String] = []
		var sk := Villager.skill_of(b)
		for x in b.workers:
			if is_instance_valid(x):
				names.append(x.display_name + ((" (%d)" % int(x.skill(sk))) if sk != "" else ""))
		if names.is_empty():
			lines.append("Çalışan yok: aşağıdan birini ata")
		if b.workers.size() < b.wanted:
			lines.append("Boşta kasabalı yok: %d işçi eksik" % (b.wanted - b.workers.size()))
	_card_lines.text = "\n".join(lines)


func _wall_card(w: Wall) -> void:
	_card.visible = true
	_card_workers.visible = false
	_card_train.visible = false
	_card_pick.visible = false
	_card_folk.visible = false
	_folk_box.visible = false
	_card_jail.visible = false
	_card_extra.visible = false
	_card_acts.visible = true
	(_btn.repair as Button).visible = false
	for what: String in BuildingDefs.UPGRADES:
		(_btn["up_" + what] as Button).visible = false
	(_btn.mode as Button).visible = false
	(_btn.area as Button).visible = false
	(_btn.no_area as Button).visible = false
	(_btn.strong as Button).visible = w.level < 2
	if w.level < 2:
		(_btn.strong as Button).tooltip_text = "Kalın kütük ve taş temel: kazıklar üç kat dayanıklı olur, zor kesilir, zor yanar (%s)" % BuildingDefs.cost_text_of(w.strengthen_cost())
	_card_title.text = "KÜTÜK SUR" if w.level >= 2 else "KAZIK SUR"
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


# --- A villager's card: its face, what it's doing, how it is, what it's good at ------------------

var _folk_box: VBoxContainer
var _folk_face: TextureRect
var _folk_job: Label
var _folk_state: Label
var _folk_traits: VBoxContainer ## a line a trait: its name, its good, its bad
var _folk_mood: ProgressBar
var _folk_mood_word: Label
var _folk_thoughts: Label ## what it's been thinking, each with its say (+5, -14)
var _folk_traits_of: Villager
var _folk_hp: ProgressBar
var _folk_rows: Array = [] ## [name Label, ProgressBar, number Label, marks Label] a skill each, best first


func _bar(fill: Color, width: float, height: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, height)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.3)
	bg.set_corner_radius_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(2)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _make_folk_box(col: VBoxContainer) -> void:
	_folk_box = VBoxContainer.new()
	_folk_box.add_theme_constant_override("separation", 6)
	_folk_box.visible = false
	col.add_child(_folk_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_folk_box.add_child(head)
	_folk_face = TextureRect.new()
	_folk_face.custom_minimum_size = Vector2(84, 84)
	_folk_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_folk_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	head.add_child(_folk_face)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(side)
	_folk_job = Ui.label(side, "", 16, Ui.INK, "strong")
	_folk_job.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_folk_job.custom_minimum_size = Vector2(230, 0)
	_folk_state = Ui.label(side, "", 13, Ui.DIM, "head")
	_folk_traits = VBoxContainer.new()
	_folk_traits.add_theme_constant_override("separation", 0)
	side.add_child(_folk_traits)
	_folk_hp = _bar(Color(0.55, 0.78, 0.4), 230, 8)
	side.add_child(_folk_hp)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	_folk_box.add_child(mrow)
	Ui.label(mrow, "MORAL", 12, Ui.ACCENT, "head")
	_folk_mood = _bar(Ui.GOOD, 150, 8)
	_folk_mood.max_value = 100.0
	mrow.add_child(_folk_mood)
	_folk_mood_word = Ui.label(mrow, "", 13, Ui.INK, "head")
	_folk_thoughts = Ui.label(_folk_box, "", 13, Ui.INK)
	_folk_thoughts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_folk_thoughts.custom_minimum_size = Vector2(330, 0)
	Ui.label(_folk_box, "BECERİLER  ·  ♥ hevesli  ·  ▲ önce  ·  – hiç", 12, Ui.ACCENT, "head")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 1)
	_folk_box.add_child(grid)
	for i in Villager.SKILLS.size():
		var n := Ui.label(grid, "", 13, Ui.INK, "head")
		n.custom_minimum_size = Vector2(96, 0)
		var bar := _bar(Ui.ACCENT, 130, 7)
		bar.max_value = 10.0
		grid.add_child(bar)
		var num := Ui.label(grid, "", 15, Ui.INK, "display")
		num.custom_minimum_size = Vector2(22, 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var marks := Ui.label(grid, "", 13, Ui.ACCENT, "head")
		marks.custom_minimum_size = Vector2(26, 0)
		_folk_rows.append([n, bar, num, marks])
	Ui.rule(_folk_box)


func _fill_folk_box(v: Villager) -> void:
	_folk_box.visible = true
	_folk_face.texture = Portraits.of(v)
	_folk_job.text = v.job
	var state := "iyi"
	if v.down:
		state = "YARALI, YERDE"
	elif v.bleeding:
		state = "KANIYOR: şifacı gerek"
	elif v.recovering:
		state = "yatakta, iyileşiyor"
	elif v.sleeping:
		state = "uyuyor"
	elif v.hp < v.max_hp * 0.999:
		state = "yaralı"
	var age := "çocuk, %d günlük" % (game.village.day - v.born_day) if v.is_child else ("kadın" if v.female else "erkek")
	_folk_state.text = "%s · %s · can %d/%d" % [age, state, int(v.hp), int(v.max_hp)]
	if _folk_traits_of != v or _folk_traits.get_child_count() != v.traits.size() + v.scars.size():
		_folk_traits_of = v
		for ch in _folk_traits.get_children():
			ch.queue_free()
		for t: String in v.traits:
			var tr: Dictionary = Villager.TRAITS[t]
			var line := Ui.label(_folk_traits, "%s: + %s · − %s" % [tr.name, tr.plus, tr.minus], 12, Ui.ACCENT, "head")
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.custom_minimum_size = Vector2(230, 0)
		for t: String in v.scars:
			var sc: Dictionary = Villager.SCARS[t]
			var line := Ui.label(_folk_traits, "%s: %s" % [sc.name, sc.minus], 12, Ui.BAD, "head")
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.custom_minimum_size = Vector2(230, 0)
	var m := v.mood
	_folk_mood.value = m
	(_folk_mood.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Ui.GOOD if m >= 55.0 else (Ui.ACCENT if m >= 35.0 else Ui.BAD)
	_folk_mood_word.text = "%s (%d)" % [v.mood_word(), roundi(m)]
	var th: Array = v.thoughts.duplicate()
	th.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(float(a.value)) > absf(float(b.value)))
	var lines: Array[String] = []
	for t: Dictionary in th.slice(0, 6):
		lines.append("%+d  %s" % [roundi(float(t.value)), t.text])
	_folk_thoughts.text = "\n".join(lines) if not lines.is_empty() else "Aklında bir şey yok"
	_folk_hp.max_value = v.max_hp
	_folk_hp.value = v.hp
	(_folk_hp.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Ui.BAD if v.hp < v.max_hp * 0.4 else (Color(0.9, 0.7, 0.3) if v.hp < v.max_hp * 0.8 else Color(0.55, 0.78, 0.4))
	var ks: Array = Villager.SKILLS.keys()
	ks.sort_custom(func(a: String, b: String) -> bool: return v.skill(a) > v.skill(b))
	var work := Villager.skill_of(v.workplace) if is_instance_valid(v.workplace) else ""
	for i in ks.size():
		var k: String = ks[i]
		var row: Array = _folk_rows[i]
		var sk := v.skill(k)
		var pr := int(v.prio.get(k, 1))
		(row[0] as Label).text = str(Villager.SKILLS[k])
		(row[0] as Label).add_theme_color_override("font_color", Ui.ACCENT if k == work else (Ui.DIM if pr == 0 else Ui.INK))
		(row[1] as ProgressBar).value = sk
		(row[1] as ProgressBar).modulate = Color(1, 1, 1, 0.35 if pr == 0 else 1.0)
		(row[2] as Label).text = str(int(sk))
		(row[2] as Label).add_theme_color_override("font_color", Ui.GOOD if sk >= 6.0 else (Ui.DIM if sk < 2.0 else Ui.INK))
		(row[3] as Label).text = ("♥" if k in v.keen else "") + (" ▲" if pr == 2 else (" –" if pr == 0 else ""))


## A jail's prisoners, each with its face, who it is, how it's being kept, and the three choices.
## A station's card: what can be sent for on the train and what it's paid with, what's sent for,
## when the train's due. A reading room's: what can be studied, what's being, how far.
func _fill_extra(b: Building) -> void:
	var v: Village = game.village
	var kind := b.kind if b.state == "done" and b.kind in ["istasyon", "okuma"] else ""
	_card_extra.visible = kind != ""
	if kind == "":
		_extra_sig = ""
		return
	var sig := "%s|%s|%s|%s" % [b.get_instance_id(), v.known, v.studying, v.orders]
	if sig != _extra_sig:
		_extra_sig = sig
		for ch in _card_extra.get_children():
			ch.queue_free()
		if kind == "istasyon":
			Ui.label(_card_extra, "TRENLE SİPARİŞ", 12, Ui.ACCENT, "head")
			if not v.knows("telgraf"):
				var l := Ui.label(_card_extra, "Telgraf yok: tren gelmiyor, sipariş verilemiyor. Okuma odasında Telgraf araştır.", 13, Ui.DIM)
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.custom_minimum_size = Vector2(300, 0)
			else:
				for what: String in Village.OFFERS:
					var o: Dictionary = Village.OFFERS[what]
					var row := HBoxContainer.new()
					row.add_theme_constant_override("separation", 8)
					_card_extra.add_child(row)
					var l := Ui.label(row, "%s  ←  %s" % [o.name, BuildingDefs.cost_text_of(o.pay)], 13, Ui.INK)
					l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					var bt := _small_button("ISMARLA", func() -> void:
						var why := v.order(what)
						toast(why if why != "" else "%s ısmarlandı: bir sonraki trenle gelecek" % o.name, "bad" if why != "" else "good"))
					bt.disabled = v.orders.size() >= Village.ORDERS_MAX
					row.add_child(bt)
		else:
			Ui.label(_card_extra, "ARAŞTIRMA", 12, Ui.ACCENT, "head")
			for t: String in BuildingDefs.TECHS:
				var td: Dictionary = BuildingDefs.TECHS[t]
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 8)
				_card_extra.add_child(row)
				var known := v.knows(t)
				var l := Ui.label(row, "%s%s" % [td.name, "  ✓" if known else ""], 14, Ui.GOOD if known else (Ui.ACCENT if t == v.studying else Ui.INK), "head")
				l.tooltip_text = str(td.desc)
				l.mouse_filter = Control.MOUSE_FILTER_PASS
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				if not known:
					var after := str(td.get("after", ""))
					if not v.knows(after):
						Ui.label(row, "önce %s" % BuildingDefs.TECHS[after].name, 12, Ui.DIM)
					elif t != v.studying:
						var bt := _small_button("ARAŞTIR", func() -> void: v.study(t))
						bt.tooltip_text = str(td.desc)
						row.add_child(bt)
		_extra_status = Ui.label(_card_extra, "", 12, Ui.DIM, "head")
		_extra_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_extra_status.custom_minimum_size = Vector2(300, 0)
	if kind == "istasyon":
		if not v.knows("telgraf"):
			_extra_status.text = ""
		else:
			var due := v.next_train - v.day
			_extra_status.text = "%s%s" % ["Tren istasyonda" if is_instance_valid(v.train) else ("Tren bugün bekleniyor" if due <= 0 else "Tren ~%d gün sonra bekleniyor (gecikebilir)" % due),
				"  ·  Ismarlanan: " + ", ".join(v.orders.map(func(o: String) -> String: return str(Village.OFFERS[o].name))) if not v.orders.is_empty() else ""]
	else:
		if v.studying == "":
			_extra_status.text = "Bir konu seç: okuyanlar onu araştırır." if v.known.size() < BuildingDefs.TECHS.size() else "Her şey araştırıldı."
		else:
			var td: Dictionary = BuildingDefs.TECHS[v.studying]
			_extra_status.text = "%s araştırılıyor: %%%d" % [td.name, roundi(v.study_pts / float(td.pts) * 100.0)]


func _fill_jail(b: Building) -> void:
	var held: Array = b.prisoners if b.def.role == "jail" and b.state == "done" else []
	_card_jail.visible = not held.is_empty()
	if held != _jail_rows: # (rebuilt only when who's held changes)
		_jail_rows = held.duplicate()
		for ch in _card_jail.get_children():
			ch.queue_free()
		Ui.label(_card_jail, "ESİRLER", 12, Ui.ACCENT, "head")
		for o: Villager in held:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			_card_jail.add_child(row)
			var face := TextureRect.new()
			face.custom_minimum_size = Vector2(46, 46)
			face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			face.set_meta("who", o)
			row.add_child(face)
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 1)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(col)
			Ui.label(col, o.display_name, 15, Ui.INK, "head")
			var ks: Array = Villager.SKILLS.keys()
			ks.sort_custom(func(a: String, c: String) -> bool: return o.skill(a) > o.skill(c))
			var tr: Array = o.traits.map(func(t: String) -> String: return str(Villager.TRAITS[t].name))
			var info := Ui.label(col, "%s %d · %s %d%s" % [Villager.SKILLS[ks[0]], int(o.skill(ks[0])), Villager.SKILLS[ks[1]], int(o.skill(ks[1])),
				(" · " + ", ".join(tr)) if not tr.is_empty() else ""], 12, Ui.DIM)
			info.custom_minimum_size = Vector2(200, 0)
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var state := Ui.label(col, "", 12, Ui.ACCENT, "head")
			state.set_meta("who", o)
			var btns := HBoxContainer.new()
			btns.add_theme_constant_override("separation", 4)
			col.add_child(btns)
			for pair in [["KAZAN", "kazan", "İyi bakılırsa üç sabah sonra kasabaya katılır"], ["ÇALIŞTIR", "calistir", "Her sabah taş ya da odun getirir; kasabalıların morali biraz düşer"]]:
				var mode: String = pair[1]
				var bt := _small_button(str(pair[0]), func() -> void:
					o.held_mode = "" if o.held_mode == mode else mode
					o.won = 0)
				bt.tooltip_text = str(pair[2])
				bt.set_meta("who", o)
				bt.set_meta("mode", mode)
				btns.add_child(bt)
			var free := _small_button("BIRAK", func() -> void: game.village.let_go(o))
			free.tooltip_text = "Serbest bırak: gider, haydutlar bir gün daha geç gelir"
			btns.add_child(free)
			var kill := _small_button("İDAM", func() -> void: game.village.execute(o))
			kill.tooltip_text = "İdam et: haydutlar üç gün daha geç gelir, ama bütün kasabanın morali ağır düşer"
			kill.add_theme_color_override("font_color", Ui.BAD)
			btns.add_child(kill)
	for n in _card_jail.find_children("*", "", true, false):
		if not n.has_meta("who") or not is_instance_valid(n.get_meta("who")):
			continue
		var o: Villager = n.get_meta("who")
		if n is TextureRect:
			(n as TextureRect).texture = Portraits.of_look(o.look_seed, "outlaw")
		elif n is Label:
			(n as Label).text = {"": "Hapiste tutuluyor", "kazan": "Kazanılıyor: %d / 3 sabah" % o.won, "calistir": "Zorla çalıştırılıyor"}[o.held_mode]
		elif n is Button and n.has_meta("mode"):
			(n as Button).add_theme_color_override("font_color", Ui.ACCENT if o.held_mode == n.get_meta("mode") else Ui.INK)


func _folk_card(v: Villager) -> void:
	_card.visible = true
	_card_workers.visible = false
	_card_acts.visible = false
	_card_train.visible = false
	_card_pick.visible = false
	_card_folk.visible = true
	_card_jail.visible = false
	_card_extra.visible = false
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
	if many.size() <= 1:
		_fill_folk_box(v)
	else:
		_folk_box.visible = false
		lines.append("Ne yapıyor: " + v.job)
	var kin: Array[String] = []
	for o in game.village.family_of(v.family):
		if o != v:
			kin.append(o.display_name.split(" ")[0] + (" (çocuk)" if o.is_child else ""))
	lines.append("%s ailesi%s" % [v.family, (": " + ", ".join(kin)) if not kin.is_empty() else " (tek)"])
	lines.append("İşyeri: " + (v.workplace.display_name() if is_instance_valid(v.workplace) else "yok (taşır, inşa eder)"))
	lines.append("Evi: " + (v.home.display_name() if is_instance_valid(v.home) else "yok, ateş başında yatıyor"))
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
		lines.append("Bir işyerine, tarlaya ya da silahlığa sağ tıkla: oraya ata. Shift+tık: birkaç kişi seç.")
	_card_lines.text = "\n".join(lines)
