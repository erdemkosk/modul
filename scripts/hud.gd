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
const CATS := [["KASABA", ["ev", "ambar", "kuyu", "fener", "meydan", "okuma"]], ["ÜRETİM", ["tarla", "oduncu", "sifaci"]],
	["TAŞIMA", ["yol", "arabaci"]], ["SAVUNMA", ["sur", "kapi", "kule", "silahlik", "siper", "tel", "makineli", "demirci", "hapishane"]], ["EMİRLER", ["kes", "kesme", "tuzak", "mayin", "hendek"]]]
## What's ordered on the ground rather than built (Main.AREA_ORDERS): the build bar's EMİRLER.
const ORDERS := {"kes": {"name": "Kes", "gives": "herkes önce bunları keser", "desc": "Bir alan sürükle ya da bir ağaca tıkla: kırmızı kurdele bağlanır, oduncu becerisi 'hiç' olmayan herkes işini bırakıp önce bu ağaçları keser, tomrukları depoya taşınır. Bitince herkes işine döner. Bina gerekmez."},
	"kesme": {"name": "Kesme", "gives": "kesim işaretini kaldırır", "desc": "Bir alan sürükle: içindeki ağaçların kesim işareti kalkar."},
	"mayin": {"name": "Mayın", "gives": "düşmanı, kamyonu, tankı uçurur", "needs": "patlayici", "desc": "Bir alan sürükle ya da bir yere tıkla: toprağa gizli kara mayınları gömülür (mayın başı 1 demir, 1 kömür; 5 m arayla). Üstüne basan firari ya da asker, üstünden geçen kamyon ya da tank havaya uçar; tankın paleti kopar, yerinde kalır. Köylüler yerini bilir, basmaz."},
	"hendek": {"name": "Hendek", "gives": "milise siper", "desc": "Bir çizgi sürükle: boştaki köylüler kürekle bir siper hendeği kazar. Hendekteki milis siperdedir: onu vurmak iki kat zor. Bedava, emek ister."},
	"tuzak": {"name": "Tuzak", "gives": "firariyi yaralar, yavaşlatır", "desc": "Bir alan sürükle ya da bir yere tıkla: gizli kazık çukurları kazılır (çukur başı 2 odun). Üstünden geçen firari yaralanır, topallar; çukur bozulur. Aynı yere yeniden TUZAK verince bozulanlar kurulur. Köylüler yerini bilir, düşmez."}}
const SPEEDS := [1.0, 2.0, 4.0]
## Every key, in one place (the help card, F1), by what it's for: the keys of each line (a "+" or
## "/" between them printed as it is, not as a key) and what they do. Nothing needs a key: what the
## selected thing can do is a button on its card, and the build bar, the speed and the menu have
## their own.
const KEYS := [
	["Kamera", [[["W", "A", "S", "D"], "kaydır"], [["Shift"], "hızlı kaydır"], [["Q", "E"], "döndür (orta tuşla da)"],
		[["Tekerlek"], "yakınlaş"], [["H"], "depoya dön"], [["Home"], "seçileni izle"], [["Harita"], "tıklanan yere git"]]],
	["Bina", [[["Tab"], "bina grubu, sonra 1–6 bina seçer"], [["1", "–", "6"], "bina seç (Tab'dan, sekmeden sonra)"], [["Sol tık"], "koy"], [["Shift", "+", "tık"], "üst üste koy"],
		[["Q", "/", "E"], "çevir"], [["Shift", "+", "Tekerlek"], "çevir"], [["Alt"], "hizasız koy"], [["Sağ tık", "/", "Esc"], "vazgeç"]]],
	["Emirler", [[["Sürükle"], "kesim, tuzak, mayın alanı"], [["Çizgi"], "hendek: boştakiler kazar"], [["Sağ tık"], "işareti kaldır (kimse seçili değilken)"]]],
	["Seçim", [[["Sol tık"], "bina ya da kasabalı"], [["Shift", "+", "tık"], "birkaç kasabalı"], [["Sürükle"], "kutuyla seç"],
		[["Ctrl", "+", "1–9"], "seçilenleri gruba al"], [["1–9"], "grubu seç · iki kez: oraya git"],
		[["V"], "bütün milis"], [["Sağ tık"], "işyerine ata (emirde kimse yokken)"]]],
	["Emirde", [[["R"], "seçilenleri emre al, bırak"], [["Sağ tık"], "imleçte yazanı yapar: saldır, ara, esir al, saklan, silah al, siper al, git"], [["Sağ sürükle"], "sıraya diz, siper arar"],
		[["M"], "milis yap: alarmda kendisi silahlanır"], [["L"], "fener"]]],
	["Bina kartı", [[["O"], "onar"], [["Del"], "yık"]]],
	["Defterler", [[["K"], "kasabalılar"], [["T"], "araştırma"], [["J"], "günlük"], [["G"], "keşif haritası"], [["F1"], "bu kart"]]],
	["Zaman", [[["Boşluk"], "duraklat (emir verilir)"], [["+", "/", "−"], "hız"], [["F5"], "kaydet"], [["F9"], "yükle"], [["Esc"], "menü"]]],
	["Görüntü", [[["P"], "fotoğraf, sepya, çık"]]],
	["Deneme", [[["F"], "tutuştur"], [["B"], "baskın"], [["N"], "inşaatı bitir"]]],
]
## How hard one in cover is to hit (the help card's table).
const COVER := [["Kütük duvar", "0,22"], ["Kum torbası", "0,28"], ["Hendek", "0,35"], ["Kaya", "0,40"], ["Kazık sur", "0,40"],
	["Ağaç", "0,60"], ["Duvar dibi, köşe", "0,65"]]

var game: Node
var category := 0
var build_keys := false ## Tab pressed or a tab clicked: the numbers pick a building of the group, not the folk kept under them (Main)

var _res: Dictionary = {} ## good -> [row, amount Label, change Label]
const GOODS := ["odun", "tas", "yiyecek", "camur", "kerpic", "ot", "komur", "demir"]
const GOOD_TIPS := {"odun": "Kesim kampından: inşaat ve evlerin, fenerlerin yakacağı",
	"tas": "Taş ocağından: temeller, bacalar, kuyu, meydan", "yiyecek": "Tarladan ve toplayıcıdan: herkes yer, öküzler de",
	"camur": "Çamur ocağından: evleri sıvamak için", "kerpic": "Çamur ocağında kerpiç yaptırınca: soba için",
	"ot": "Felçerin ormandan topladığı ot ve trenle gelen sargı bezi: her yara sarışta bir tane gider",
	"komur": "Atölyede kara kayalardan (kömür damarı) kazılır: demircinin ocağı için", "demir": "Atölyede pas renkli kayalardan (demir damarı) sökülür: demirci tüfek ve fişek döver"}
var _seen := {} ## goods once had: shown from then on
var _goods_head: Button
var _folds: Array = [] ## [header, body, seconds since the mouse left both]
var _history: Array = [] ## [clock, stock] every few seconds, the last minute's
var _pop: Label
var _purse: Label
var _clock: Label
var _raid: Label
var _speed_buttons: Array[Button] = []
var _hint: Label
var _toasts: VBoxContainer
var _tabs: Array[Button] = []
var _build_row: HBoxContainer
var _card: PanelContainer
var _card_title: Label
var _card_kind: Label ## printed at the head of the card: what sort of record it is
var _card_lines: Label
var _card_workers: HBoxContainer
var _card_count: Label
var _card_acts: HFlowContainer
var _card_folk: HFlowContainer
var _btn := {} ## the card's buttons by name, shown and labelled for what's selected
var _placing_plate: PanelContainer
var _people_plate: PanelContainer ## the townsfolk table
var _people_grid: GridContainer
var _people_rows: Array = [] ## the villagers the table's rows are for
var _people_t := 0.0
var _store_line: Button ## under the goods: how full the stores are, and what's stopped (a click: show it)
var _tele_plate: PanelContainer ## the telegraph office
var _test_panel: Control ## (kept over the minimap when it folds out)
var _train_stat: Label ## the next train, in the top bar
var _log_plate: PanelContainer ## the day-book: every message so far, newest first (GÜNLÜK, J)
var _log_list: VBoxContainer
var _log: Array = [] ## [day, hour, text, kind]
var _ask_paused := false ## (a question put: the game held still till it's answered)
var _asks: VBoxContainer ## the questions put to the player (ask), top middle
var _tele: TelegraphPanel
var _tech_plate: PanelContainer ## the research tree
var _map_plate: PanelContainer ## the survey map (G)
var _map_note: Label
var _map_big: Minimap
var _tech_tree: TechTree
var _tech_note: Label
var _card_train: HFlowContainer
var _card_make: HFlowContainer ## a workshop's card: what it's set to make
var _make_btns := {} ## what -> its button
var _place_make: HBoxContainer ## while placing a workshop: what it's to make
var _place_btns := {} ## what -> its button
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
	var board := AlertBoard.new()
	board.game = game
	board.make(self)
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
	var map_plate := _plate(false) # (the leather the others are, the map on it)
	map_plate.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	map_plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	map_plate.offset_right = -12
	map_plate.offset_bottom = -50
	add_child(map_plate)
	var mini := Minimap.new()
	mini.game = game
	map_plate.add_child(mini)
	if _test_panel:
		_test_panel.move_to_front()
	var squad := SquadBar.new()
	squad.game = game
	squad.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	squad.grow_horizontal = Control.GROW_DIRECTION_BOTH
	squad.grow_vertical = Control.GROW_DIRECTION_BEGIN
	squad.offset_bottom = -178
	add_child(squad)
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.offset_top = 18
	_toasts.add_theme_constant_override("separation", 5)
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
	_make_tech()
	_make_telegraph()
	_make_log()
	_asks = VBoxContainer.new()
	_asks.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_asks.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_asks.offset_top = 150
	_asks.add_theme_constant_override("separation", 10)
	add_child(_asks)
	_test_plate()
	_make_help()
	_make_pause()
	show_category(0)


func _plate(lean := true, fill := Ui.GLASS) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.glass(lean, 8.0, fill))
	return p


## A read-out on a bar: its name small over it, the figure under. `ink`: on the enamel sign (dark
## writing on cream), else cream on the leather.
func _stat(row: HBoxContainer, title: String, tip := "", ink := false, kind := "text", size := 21) -> Label:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -2)
	box.tooltip_text = tip
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(box)
	Ui.label(box, title, 12, Ui.P_DIM if ink else Ui.DIM, "label")
	return Ui.label(box, "-", size, Ui.P_INK if ink else Ui.INK, kind)


## The goods down the left: each as it's first had, how much is in the stores, and how it's gone
## the last minute.
func _goods_plate() -> void:
	var p := _plate()
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.offset_left = 12
	p.offset_top = 116
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
	# a game day's worth of the stores looked back over: what's come in and gone out, per day
	var day_s := maxf(game.weather.day_length_minutes * 60.0, 60.0)
	if _history.is_empty() or v.clock - float(_history[-1][0]) >= day_s / 96.0:
		_history.append([v.clock, stock.duplicate()])
		while _history.size() > 1 and v.clock - float(_history[0][0]) > day_s:
			_history.pop_front()
	var then: Dictionary = _history[0][1]
	var span := maxf(v.clock - float(_history[0][0]), day_s / 24.0)
	for id: String in GOODS:
		var n := int(stock.get(id, 0))
		if n > 0:
			_seen[id] = true
		var parts: Array = _res[id]
		(parts[0] as Control).visible = _seen.has(id) or id in ["odun", "tas", "yiyecek"]
		(parts[1] as Label).text = str(n)
		(parts[1] as Label).add_theme_color_override("font_color", Ui.BAD if id == "yiyecek" and n <= 5 else Ui.INK)
		var d := roundi(float(n - int(then.get(id, 0))) / span * day_s)
		(parts[2] as Label).text = ("+%d/gün" % d) if d > 0 else (("%d/gün" % d) if d < 0 else "")
		(parts[2] as Label).add_theme_color_override("font_color", Ui.GOOD if d > 0 else Ui.BAD)
	_goods_head.add_theme_color_override("font_color", Ui.BAD if int(stock.get("yiyecek", 0)) <= 5 else Ui.INK) # (short of food: it says so, folded or not)
	# how full the stores are and where the town stands with the sides, on the brass plate under
	# the bar; a slip pinned under it when work's stopped for want of room or carters
	var fill := v.store_fill()
	var full := v.full_yards()
	_depo_fill.text = "%d / %d" % [fill.x, fill.y]
	_depo_bar.max_value = maxf(float(fill.y), 1.0)
	_depo_bar.value = fill.x
	(_depo_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.5, 0.1, 0.06) if fill.y > 0 and fill.x >= fill.y * 0.85 else Color(0.2, 0.13, 0.06)
	for side: String in _side_marks:
		var st := v.standing(side)
		var l: Label = _side_marks[side]
		l.text = "%+d" % st
		l.add_theme_color_override("font_color", Color(0.5, 0.08, 0.04) if st <= Village.HOSTILE else (Color(0.08, 0.3, 0.1) if st >= Village.FRIENDLY else Color(0.2, 0.13, 0.06)))
	var line := ""
	var bad := false
	if fill.y > 0 and fill.x >= fill.y:
		line = "DEPOLAR DOLU: yeni depo kur, üretim duruyor"
		bad = true
	elif not full.is_empty():
		line = "%d işyerinin yığını dolu: %s" % [full.size(), "arabacılar yetişemiyor" if v.carters_about() else "arabacı kur"]
		bad = true
	elif not v.unmanned().is_empty():
		line = "%d işyerinde çalışan yok: boşta kasabalı kalmadı" % v.unmanned().size()
		bad = true
	elif v.line_shut() and v.depot() != null:
		line = "HAT KARLA KAPALI: bir atölyede HAT KÜRE seçin"
		bad = true
	elif fill.y > 0 and fill.x >= fill.y * 0.85:
		line = "Depolar dolmak üzere"
	if game.raids.camp_known:
		line = "FİRARİ KAMPI (%d kişi): milisi seç, R ile emre al, kampa sağ tıkla" % game.raids.camp_men.size()
		bad = true
	_store_line.visible = line != "" and _brass.visible
	_state_head.text = ("Durum !" if bad else "Durum") + (" ▴" if _brass.visible else " ▾")
	_state_head.add_theme_color_override("font_color", Ui.P_RED if bad else Ui.INK)
	_state_head.tooltip_text = "Depoların doluluğu, tarafların gözünde kasaba" + ("\n" + line if line != "" else "")
	_store_line.text = line + ("   ▸ GÖSTER" if bad else "")
	var lc: Color = Ui.P_RED if bad else Ui.P_INK
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_store_line.add_theme_color_override(state, lc.darkened(0.3) if state == "font_hover_color" else lc)
	_store_line.tooltip_text = "Tıkla: oraya bak" + ("\n" + "\n".join(full.map(func(b: Building) -> String: return "%s: yığın dolu" % b.display_name())) if not full.is_empty() else "")


var _depo_fill: Label
var _depo_bar: ProgressBar
var _brass: PanelContainer ## the plate itself: folded away until DURUM is pressed (the screen kept clear)
var _state_head: Button ## DURUM ▾ on the bar: opens the plate; a red mark on it when something's wrong
var _side_marks := {} ## side -> its standing on the brass plate


func _stores_plate() -> void:
	var p := _plate()
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.offset_left = 12
	p.offset_top = 10
	add_child(p)
	_brass_plate()
	# what's gone wrong, on a slip of tape pinned under the plate (a click: show it)
	_store_line = Button.new()
	_store_line.focus_mode = Control.FOCUS_NONE
	_store_line.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_store_line.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_store_line.offset_left = 22
	_store_line.offset_top = 118
	_store_line.visible = false
	_store_line.add_theme_font_override("font", Ui.font("type_bold"))
	_store_line.add_theme_font_size_override("font_size", 13)
	var tape := Ui.sheet("tape")
	var tape_over := Ui.sheet("tape")
	tape_over.modulate_color = Color(0.96, 0.94, 0.88)
	_store_line.add_theme_stylebox_override("normal", tape)
	_store_line.add_theme_stylebox_override("hover", tape_over)
	_store_line.add_theme_stylebox_override("pressed", tape_over)
	_store_line.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_store_line.rotation = -0.012
	_store_line.pressed.connect(func() -> void: game.show_trouble())
	add_child(_store_line)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	p.add_child(row)
	var pair := HBoxContainer.new() # (the two that open something, side by side)
	pair.add_theme_constant_override("separation", 4)
	row.add_child(pair)
	_goods_head = _nav_button("Kaynaklar ▾", func() -> void: pass)
	_goods_head.tooltip_text = "Depolardaki odun, taş, yiyecek, silahlar...: üzerine gel"
	pair.add_child(_goods_head)
	var who := _nav_button("Halk", func() -> void: toggle_people())
	who.tooltip_text = "Herkesin becerileri ve hangi işe öncelikle verileceği (K)"
	pair.add_child(who)
	var tech := _nav_button("Araştırma", func() -> void: toggle_tech())
	tech.tooltip_text = "Araştırma ağacı: ne bulunabilir, ne açar, ne kadar kaldı (T)"
	pair.add_child(tech)
	_state_head = _nav_button("Durum ▾", func() -> void:
		_brass.visible = not _brass.visible
		_t = 1.0) # (redrawn on the next frame)
	pair.add_child(_state_head)
	var book := _nav_button("Günlük", func() -> void: toggle_log())
	book.tooltip_text = "Olanların hepsi, gün gün: kaçırdığın haberler, telgraflar, baskınlar (J)"
	pair.add_child(book)
	_pop = _stat(row, "Nüfus", "Kasabalılar / yataklar, ve bir işyerine verilmemiş olanlar (taşır, inşa eder)")
	_purse = _stat(row, "Kasa", "Mirka (Zarovya parası): trene mal satınca gelir, telgrafla tren çağırınca gider")
	_train_stat = _stat(row, "Tren", "Sonraki tren: kaç gün sonra, peronda mı, hat karla kapalı mı")


## Under the bar, a brass plate screwed to the leather: how full the stores are (a gauge, the
## figures), and the town's standing with the two sides, engraved.
func _brass_plate() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.sheet("brass"))
	p.set_anchors_preset(Control.PRESET_TOP_LEFT)
	p.offset_left = 22
	p.offset_top = 80
	p.tooltip_text = "Bütün depoların aldığı ve içindeki yük; Merkez ve Özgür Kordal'ın gözünde kasaba (−30 ve altı düşman, +30 ve üstü dost)"
	p.visible = false
	_brass = p
	add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	var engraved := Color(0.2, 0.13, 0.06)
	var cut := func(text: String, size: int, kind: String) -> Label:
		var l := Ui.label(row, text, size, engraved, kind)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return l
	cut.call("DEPO", 12, "head")
	_depo_bar = _bar(engraved, 64, 6)
	(_depo_bar.get_theme_stylebox("background") as StyleBoxFlat).bg_color = Color(0.3, 0.2, 0.08, 0.35)
	row.add_child(_depo_bar)
	_depo_fill = cut.call("0 / 0", 14, "digital")
	for side: String in Village.SIDES:
		var bar := ColorRect.new() # (an engraved stroke between them)
		bar.color = Color(engraved, 0.5)
		bar.custom_minimum_size = Vector2(1, 14)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		cut.call(Ui.upper(str(Village.SIDES[side])), 12, "head")
		_side_marks[side] = cut.call("+0", 14, "digital")


func _clock_plate() -> void:
	var p := PanelContainer.new() # (a cream enamel sign, as on the station's wall: the day, the hour, the sky)
	p.add_theme_stylebox_override("panel", Ui.sheet("enamel"))
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -12
	p.offset_top = 10
	add_child(p)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	p.add_child(row)
	_clock = _stat(row, "Gün", "", true)
	_clock_time = _stat(row, "Saat", "", true, "type", 21)
	_clock_sky = _stat(row, "Hava", "", true, "italic", 20)
	var bar := ColorRect.new() # (a line struck down the sign between the hour and the raid)
	bar.color = Color(Ui.P_INK, 0.35)
	bar.custom_minimum_size = Vector2(1, 0)
	row.add_child(bar)
	_raid = _stat(row, "Baskın", "Firarilerin gelmesi beklenen gece", true)
	var sp := VBoxContainer.new()
	sp.add_theme_constant_override("separation", 1)
	row.add_child(sp)
	Ui.label(sp, "Hız", 12, Ui.P_DIM, "label")
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
	Ui.inkify(p, Ui.P_INK)
	for b: Button in _speed_buttons:
		Ui.ink_button(b, Ui.P_INK, 15, "digital") # (the figures even, as a timetable's)


var _clock_time: Label
var _clock_sky: Label


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
	_test_panel = p
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
	raid.tooltip_text = "Hemen bir firari baskını (B)"
	row2.add_child(raid)
	var build := _small_button("İNŞAATI BİTİR", func() -> void: game.test_build()) # (a test, to come out later)
	build.tooltip_text = "Yapımdaki ve onarılan her şeyi hemen bitir (N)"
	row2.add_child(build)
	var fire := _small_button("TUTUŞTUR", func() -> void: game.ignite_selected())
	fire.tooltip_text = "Seçili binayı ateşe ver (F)"
	row2.add_child(fire)
	# the war's events, at once, to try them
	for line: Array in [
			[["TANKLI KONVOY", "convoy_tank", "Merkez ya da isyancı konvoyu, tankıyla, hemen yola çıkar"], ["KONVOY", "convoy", "Kamyonlu konvoy (tanksız)"], ["DÜŞMAN KONVOY", "convoy_hostile", "Kasabaya düşman bir tarafın tanklı konvoyu: sormadan saldırır"]],
			[["ZIRHLI TREN", "armoured", "Bir tarafın zırhlı treni istasyona gelir"], ["DÜŞMAN TREN", "armoured_hostile", "Düşman zırhlı tren: askerleri inip saldırır"], ["FİRARİ KAMPI", "camp", "Ormanda bulunmuş bir firari kampı"], ["KAPIDA FİRARİ", "beg", "Firariler yiyecek istemeye gelir"]],
			[["YARDIM GELSİN", "help", "Dost bir tarafın askerleri hemen yola çıkar (beklemeden)"], ["TELGRAF HABERİ", "news", "Rastgele bir telgraf haberi"], ["POSTA", "mail", "Trenle posta gelmiş gibi mektuplar"], ["HEPSİNİ SÖNDÜR", "douse", "Yanan her şey söner"], ["HER ŞEYİ AÇ", "techs", "Bütün araştırmalar bilinir"], ["+ KAYNAK", "stock", "Her maldan 100, kasaya 200 mirka"]]]:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 4)
		col.add_child(r)
		for e: Array in line:
			var what: String = e[1]
			var b := _small_button(str(e[0]), func() -> void: game.test_event(what))
			b.tooltip_text = str(e[2])
			r.add_child(b)


var _tray: PanelContainer
var _tab_row: HBoxContainer
var _build_info: PanelContainer ## the card over the bar naming what the mouse is on
var _info_pic: Control
var _info_name: Label
var _info_gives: Label
var _info_costs: GridContainer
var _info_work: Label
var _info_desc: Label
var _info_lock: Label
var _info_at := 0.0 ## where along the card its notch points
var _info_tex: Texture2D

# The bar's palette: the top bars' leather, their cream, brass; the enamel of the season dial.
const _AMBER := Ui.ACCENT ## brass
const _AMBER_HI := Color(1.0, 0.87, 0.6)
const _BRASS_LO := Color(0.36, 0.25, 0.11)
const _FROST := Ui.INK ## cream lettering
const _ENAMEL := Color(0.94, 0.9, 0.8)
const _ENAMEL_LO := Color(0.82, 0.76, 0.64)
const _LEATHER := Color(0.25, 0.18, 0.13) ## (Ui.PAPER: the tabs are cut from the same hide)
const _SHORT := Color(0.78, 0.2, 0.1) ## the red of what can't be paid for
const _MEDAL_R := 44.0


func _build_bar() -> void:
	# The station master's board along the foot of the view: the leather of the bars above, its
	# worn lower edge off the bottom of the screen; the groups as folder tabs standing up out of it,
	# the chosen one cut from the same hide so it runs on into the board unbroken; the buildings as
	# enamel medallions in brass bezels, as the season dial is, each with its engraved plate.
	var p := PanelContainer.new()
	var sb := Ui.paper(8.0)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 18
	sb.content_margin_bottom = 26
	p.add_theme_stylebox_override("panel", sb)
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_bottom = 12 # (its worn foot below the screen's edge: the board sits on it)
	add_child(p)
	_tray = p
	_build_row = HBoxContainer.new()
	_build_row.add_theme_constant_override("separation", 6)
	_build_row.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(_build_row)
	_tab_row = HBoxContainer.new()
	_tab_row.top_level = true # (placed by hand on the board's top edge, over it)
	_tab_row.add_theme_constant_override("separation", 3)
	p.add_child(_tab_row)
	for i in CATS.size():
		var t := Button.new()
		t.text = Ui.upper(str(CATS[i][0]))
		t.focus_mode = Control.FOCUS_NONE
		t.tooltip_text = "Tab: sonraki grup"
		t.custom_minimum_size = Vector2(0, 30)
		t.add_theme_font_override("font", Ui.face("head", 14))
		t.add_theme_font_size_override("font_size", 14)
		t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
		t.add_theme_constant_override("outline_size", 2)
		t.pressed.connect(func() -> void:
			show_category(i)
			build_keys = true)
		_tab_row.add_child(t)
		_tabs.append(t)
	p.resized.connect(_place_tabs)
	_tab_row.resized.connect(_place_tabs)
	_make_build_info()
	_hint = Ui.label(self, "", 17, Ui.INK, "strong")
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_top = -206
	_hint.offset_bottom = -174
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## The tabs set on the board's top edge, in the middle.
func _place_tabs() -> void:
	if _tab_row == null or _tray == null:
		return
	_tab_row.reset_size()
	var w := _tab_row.size.x
	var want := w + 90.0 # (the board never narrower than its tabs, whatever the group holds)
	if absf(_tray.custom_minimum_size.x - want) > 1.0:
		_tray.custom_minimum_size.x = want
		return # (resized: called again)
	_tab_row.global_position = Vector2(_tray.global_position.x + (_tray.size.x - w) * 0.5, _tray.global_position.y - _tab_row.size.y + 5.0)


## A group's tab: a flap of the board's leather with a stitched brass edge; the chosen one the same
## hide as the board, reaching down over its edge so the two are one piece; the rest a shade darker,
## standing behind.
static func _tab_style(on: bool, hover: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = _LEATHER.lightened(0.02) if on else (_LEATHER.darkened(0.2) if hover else _LEATHER.darkened(0.36))
	s.border_color = Color(_AMBER, 0.85) if on else Color(0.62, 0.5, 0.34, 0.45 if hover else 0.28)
	s.border_width_top = 1
	s.border_width_left = 1
	s.border_width_right = 1
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 4
	if on:
		s.expand_margin_bottom = 12 # (down over the board's worn edge: one hide)
		s.shadow_color = Color(0, 0, 0, 0.25)
		s.shadow_size = 3
		s.shadow_offset = Vector2(0, -1)
	return s


## The group's buildings along the board (Tab, or its tab), each medallion coming up in turn.
func show_category(i: int) -> void:
	category = posmod(i, CATS.size())
	for k in _tabs.size():
		var on := k == category
		_tabs[k].add_theme_stylebox_override("normal", _tab_style(on, false))
		_tabs[k].add_theme_stylebox_override("hover", _tab_style(on, true))
		_tabs[k].add_theme_stylebox_override("pressed", _tab_style(true, true))
		_tabs[k].add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_tabs[k].add_theme_color_override("font_color", _AMBER_HI if on else _FROST.darkened(0.3))
		_tabs[k].add_theme_color_override("font_hover_color", _AMBER_HI if on else _FROST)
		_tabs[k].add_theme_color_override("font_pressed_color", _AMBER_HI)
	for c in _build_row.get_children():
		c.queue_free()
	if _build_info:
		_build_info.visible = false
	var kinds: Array = CATS[category][1]
	for k in kinds.size():
		var b := _build_button(kinds[k], k)
		_build_row.add_child(b)
		b.modulate.a = 0.0
		var tw := b.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.03 * k)
		tw.tween_method(func(v: float) -> void:
			b.set_meta("enter", v)
			b.modulate.a = v
			b.queue_redraw(), 0.0, 1.0, 0.22)
	_place_tabs.call_deferred()


## A build medallion: the engraved plate (assets/ui/plates, tools/ink_plates.py) on cream enamel in
## a brass bezel, its key on a small plaque at the top. Lifts and warms under the mouse; the card
## over the board names it. Shows how many stand (a brass coin), whether the stores can't pay for it
## (the bezel's foot red), a new one (a red dot), the one in hand (lit), a locked one (greyed, a lock).
func _build_button(kind: String, k: int) -> Button:
	var def: Dictionary = ORDERS[kind] if ORDERS.has(kind) else BuildingDefs.DEFS[kind]
	var b := Button.new()
	b.custom_minimum_size = Vector2(_MEDAL_R * 2.0 + 14.0, _MEDAL_R * 2.0 + 18.0)
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.set_meta("kind", kind)
	b.set_meta("key", k)
	b.set_meta("lift", 0.0)
	b.set_meta("enter", 0.0)
	var pic := "atolye" if kind == "oduncu" else kind # (the workshop: its four trades)
	for path in ["res://assets/ui/plates/%s.png" % kind, "res://assets/ui/icons/%s.png" % pic]:
		if ResourceLoader.exists(path):
			b.set_meta("tex", load(path))
			break
	b.pressed.connect(func() -> void: game.start_placing(kind))
	b.draw.connect(func() -> void: _draw_medal(b))
	var lift_to := func(to: float) -> void:
		var tw := b.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(v: float) -> void:
			b.set_meta("lift", v)
			b.queue_redraw(), float(b.get_meta("lift")), to, 0.13)
	b.mouse_entered.connect(func() -> void:
		lift_to.call(1.0)
		if b.get_meta("new", false):
			b.set_meta("new", false)
			_seen_new[kind] = true
		_show_build_info(b, kind, def))
	b.mouse_exited.connect(func() -> void:
		lift_to.call(0.0)
		_build_info.visible = false)
	b.button_down.connect(func() -> void: lift_to.call(0.25))
	b.button_up.connect(func() -> void: lift_to.call(1.0 if b.is_hovered() else 0.0))
	# (kept for the frame's update: the cost's figures, coloured as the stores stand)
	var costs := HBoxContainer.new()
	costs.visible = false
	b.add_child(costs)
	var nums: Array = []
	if not ORDERS.has(kind):
		var cost: Dictionary = BuildingDefs.DEFS[kind].cost
		for r: String in cost:
			var n := Ui.label(costs, str(int(cost[r])), 13, _FROST, "type_bold")
			nums.append([r, n])
	var lock := Ui.label(b, "", 10, _SHORT, "type_bold")
	lock.visible = false
	var needs := str(def.get("needs", ""))
	if needs != "":
		b.set_meta("needs", needs)
	b.set_meta("costs", nums)
	b.set_meta("cost_row", costs)
	b.set_meta("lock_label", lock)
	return b


var _seen_new := {} ## kinds whose "new" dot has been seen (moused over) since they were unlocked


## The ink drawings of the goods as pale marks on the leather (they're drawn dark for paper).
static var _pale: ShaderMaterial


static func _pale_mat() -> ShaderMaterial:
	if _pale == null:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nvoid fragment() { vec4 t = texture(TEXTURE, UV); COLOR = vec4(vec3(0.9, 0.84, 0.72), t.a * COLOR.a); }"
		_pale = ShaderMaterial.new()
		_pale.shader = sh
	return _pale


## A medallion drawn at `ctr`, radius `r`: shadow, bezel, enamel face, plate. (The card's picture
## uses it too.)
func _medal(c: CanvasItem, ctr: Vector2, r: float, tex: Texture2D, warm: float, grey: bool, short: bool, held: float) -> void:
	# the shadow it throws on the leather
	c.draw_circle(ctr + Vector2(0, r * 0.1 + 2.0), r + 3.0, Color(0, 0, 0, 0.16))
	c.draw_circle(ctr + Vector2(0, r * 0.06 + 1.0), r + 1.0, Color(0, 0, 0, 0.32))
	# warm light round it under the mouse, or in hand
	var glow := maxf(warm, held)
	if glow > 0.01:
		for k in 5:
			c.draw_circle(ctr, r + 3.0 + float(5 - k) * 2.4, Color(1.0, 0.72, 0.35, 0.05 * glow))
	# the bezel: dark brass at its rim, bright through its middle, lit at the upper left
	var lit := 0.25 * warm + 0.35 * held
	c.draw_circle(ctr, r, _BRASS_LO)
	c.draw_circle(ctr, r - 1.4, _AMBER.darkened(0.1).lerp(_AMBER_HI, lit))
	c.draw_arc(ctr, r - 3.2, PI * 1.0, PI * 1.8, 28, Color(_AMBER_HI, 0.85), 2.2, true)
	c.draw_arc(ctr, r - 3.2, PI * 0.05, PI * 0.8, 28, Color(_BRASS_LO, 0.55), 2.0, true)
	if short: # (the foot of the bezel in the red, as a gauge past its mark)
		c.draw_arc(ctr, r - 2.4, PI * 0.36, PI * 0.64, 16, Color(_SHORT, 0.9), 2.0, true)
	c.draw_circle(ctr, r - 6.0, _BRASS_LO.darkened(0.3))
	# the enamel face: lit from the upper left, deeper toward its rim
	var face := _ENAMEL if not grey else Color(0.66, 0.65, 0.62)
	var face_lo := _ENAMEL_LO if not grey else Color(0.52, 0.51, 0.49)
	c.draw_circle(ctr, r - 7.0, face_lo)
	c.draw_circle(ctr + Vector2(-1.2, -1.6), r - 9.0, face_lo.lerp(face, 0.6))
	c.draw_circle(ctr + Vector2(-2.6, -3.4), r - 13.0, face)
	c.draw_circle(ctr + Vector2(-r * 0.25, -r * 0.3), r * 0.42, Color(1, 1, 1, 0.12))
	if held > 0.01:
		c.draw_arc(ctr, r - 8.5, 0.0, TAU, 48, Color(_AMBER, 0.8 * held), 2.0, true)
	if tex:
		var s := (r - 8.0) * 1.9
		c.draw_texture_rect(tex, Rect2(ctr - Vector2(s, s) * 0.5 + Vector2(0, 1.0), Vector2(s, s)), false, Color(1, 1, 1, 0.32) if grey else (Color(1, 1, 1, 0.78) if short else Color(1, 1, 1)))
	# the glaze: a thin bright crescent along the top of the face
	c.draw_arc(ctr, r - 8.5, PI * 1.15, PI * 1.6, 20, Color(1, 1, 1, 0.35), 1.2, true)


func _draw_medal(b: Button) -> void:
	var t: float = b.get_meta("lift", 0.0)
	var enter: float = b.get_meta("enter", 1.0)
	var locked: bool = b.get_meta("locked", false)
	var short: bool = b.get_meta("short", false)
	var held: float = 1.0 if b.get_meta("held", false) else 0.0
	var r := _MEDAL_R * (1.0 + 0.04 * t)
	var ctr := Vector2(b.size.x * 0.5, _MEDAL_R + 9.0 - 4.0 * t - 2.0 * held + (1.0 - enter) * 14.0)
	_medal(b, ctr, r, b.get_meta("tex", null), t * (0.4 if locked else 1.0), locked, short and not locked, held)
	# its key on a small enamel plaque riding the bezel's top
	var f := Ui.face("type_bold", 12)
	var key := str(int(b.get_meta("key", 0)) + 1)
	var kw := f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var tag := Rect2(ctr + Vector2(-9.0, -r - 5.0), Vector2(18.0, 15.0))
	b.draw_rect(Rect2(tag.position + Vector2(0, 1.5), tag.size), Color(0, 0, 0, 0.35), true)
	b.draw_rect(tag, _ENAMEL, true)
	b.draw_rect(tag, _BRASS_LO, false, 1.0)
	b.draw_string(f, Vector2(tag.position.x + (tag.size.x - kw) * 0.5, tag.end.y - 3.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.P_INK)
	# how many stand: a brass coin at the lower right
	var count: int = b.get_meta("count", 0)
	if count > 0:
		var cc := ctr + Vector2(r * 0.74, r * 0.7)
		b.draw_circle(cc + Vector2(0, 1.5), 10.5, Color(0, 0, 0, 0.4))
		b.draw_circle(cc, 10.0, _BRASS_LO)
		b.draw_circle(cc, 8.8, _AMBER)
		b.draw_arc(cc, 7.6, PI * 1.0, PI * 1.8, 12, Color(_AMBER_HI, 0.9), 1.2, true)
		var cs := str(count)
		var cf := Ui.face("type_bold", 12)
		var cw := cf.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		b.draw_string(cf, cc + Vector2(-cw * 0.5, 4.5), cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.P_INK)
	# new: a red dot at the upper right
	if b.get_meta("new", false):
		var nc := ctr + Vector2(r * 0.72, -r * 0.7)
		b.draw_circle(nc + Vector2(0, 1), 6.0, Color(0, 0, 0, 0.4))
		b.draw_circle(nc, 5.5, _SHORT.lightened(0.1))
		b.draw_circle(nc + Vector2(-1.5, -1.5), 1.8, Color(1, 1, 1, 0.6))
	# locked: an engraved padlock at the foot of the face
	if locked:
		var lc := ctr + Vector2(0, r * 0.52)
		var ink := Color(Ui.P_INK, 0.85)
		b.draw_arc(lc + Vector2(0, -5.5), 5.0, PI, TAU, 14, ink, 2.0, true)
		b.draw_rect(Rect2(lc + Vector2(-7.5, -5.5), Vector2(15, 11)), Color(0.6, 0.59, 0.56), true)
		b.draw_rect(Rect2(lc + Vector2(-7.5, -5.5), Vector2(15, 11)), ink, false, 1.4)
		b.draw_circle(lc + Vector2(0, -0.5), 1.6, ink)


## The card over the board: the building's medallion small and its name, what it brings; under a
## brass rule what it takes (each good: what's in the stores against what's needed, red if short),
## who works it; what it's for; how to unlock it if it's locked.
func _make_build_info() -> void:
	_build_info = PanelContainer.new()
	var ib := Ui.paper(6.0)
	ib.content_margin_left = 20
	ib.content_margin_right = 22
	ib.content_margin_top = 14
	ib.content_margin_bottom = 16
	_build_info.add_theme_stylebox_override("panel", ib)
	_build_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_info.visible = false
	_build_info.top_level = true
	add_child(_build_info)
	_build_info.draw.connect(func() -> void:
		var bx := clampf(_info_at, 18.0, _build_info.size.x - 18.0)
		var y := _build_info.size.y
		_build_info.draw_colored_polygon(PackedVector2Array([Vector2(bx - 9, y - 7), Vector2(bx + 9, y - 7), Vector2(bx, y + 6)]), _LEATHER.darkened(0.25)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_info.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	_info_pic = Control.new()
	_info_pic.custom_minimum_size = Vector2(52, 52)
	_info_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_pic.draw.connect(func() -> void: _medal(_info_pic, Vector2(26, 26), 25.0, _info_tex, 0.0, false, false, 0.0))
	head.add_child(_info_pic)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(names)
	_info_name = Ui.label(names, "", 20, _AMBER_HI, "head")
	_info_gives = Ui.label(names, "", 15, _FROST.darkened(0.05), "italic")
	var rule := ColorRect.new()
	rule.color = Color(_AMBER, 0.35)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rule)
	_info_costs = GridContainer.new()
	_info_costs.columns = 3
	_info_costs.add_theme_constant_override("h_separation", 8)
	_info_costs.add_theme_constant_override("v_separation", 2)
	_info_costs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_info_costs)
	_info_work = Ui.label(col, "", 14, _FROST.darkened(0.05), "italic")
	_info_desc = Ui.label(col, "", 15, Color(0.95, 0.9, 0.8), "text")
	_info_desc.add_theme_constant_override("line_spacing", 3)
	_info_lock = Ui.label(col, "", 14, Color(1.0, 0.56, 0.42), "type_bold")
	for l: Label in [_info_name, _info_gives, _info_work, _info_desc, _info_lock]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_constant_override("outline_size", 0) # (no halo on the leather: it muddies the letters)


## `s` broken into lines of at most `n` letters, at the spaces.
static func _wrap(s: String, n: int) -> String:
	var out := ""
	var line := ""
	for w in s.split(" ", false):
		if line.length() + w.length() + 1 > n and line != "":
			out += line + "\n"
			line = w
		else:
			line = w if line == "" else line + " " + w
	return out + line


func _show_build_info(b: Button, kind: String, def: Dictionary) -> void:
	_info_tex = b.get_meta("tex", null)
	_info_pic.queue_redraw()
	_info_name.text = Ui.upper(str(def.name))
	var gives := str(def.gives) if ORDERS.has(kind) else str(BuildingDefs.GIVES.get(kind, ""))
	_info_gives.text = gives
	_info_gives.visible = gives != ""
	for c in _info_costs.get_children():
		c.queue_free()
	var stock: Dictionary = game.village.stock if game.village else {}
	if ORDERS.has(kind):
		Ui.label(_info_costs, "", 12, _FROST)
		Ui.label(_info_costs, "bedava", 14, _FROST, "italic")
		Ui.label(_info_costs, "", 12, _FROST)
	else:
		var cost: Dictionary = BuildingDefs.DEFS[kind].cost
		for good: String in cost:
			var icn := TextureRect.new()
			if ResourceLoader.exists("res://assets/ui/ink/%s.png" % good):
				icn.texture = load("res://assets/ui/ink/%s.png" % good)
			icn.custom_minimum_size = Vector2(22, 22)
			icn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icn.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icn.material = _pale_mat()
			_info_costs.add_child(icn)
			var have := int(stock.get(good, 0))
			var need := int(cost[good])
			var fig := Ui.label(_info_costs, "%d / %d" % [have, need], 16, _FROST if have >= need else Color(1.0, 0.56, 0.42), "type_bold")
			fig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			fig.add_theme_constant_override("outline_size", 0)
			var gn := Ui.label(_info_costs, str(BuildingDefs.RES_NAMES.get(good, good)).to_lower(), 15, _FROST.darkened(0.05), "italic")
			gn.add_theme_constant_override("outline_size", 0)
	var slots := int(def.get("slots", 0))
	_info_work.text = "%d kişi çalışır" % slots if slots > 0 else ""
	_info_work.visible = slots > 0
	_info_desc.text = _wrap(str(def.desc), 44)
	var locked: bool = b.get_meta("locked", false)
	_info_lock.visible = locked
	if locked:
		_info_lock.text = _wrap("Kilitli: okuma odasında %s araştırılınca açılır" % BuildingDefs.TECHS[b.get_meta("needs")].name, 44)
	_build_info.visible = true
	_build_info.reset_size()
	await get_tree().process_frame
	if not is_instance_valid(b) or not _build_info.visible:
		return
	_build_info.reset_size()
	var w := _build_info.size.x
	var mid := b.global_position.x + b.size.x * 0.5
	var x := clampf(mid - w * 0.5, 8.0, get_viewport().get_visible_rect().size.x - w - 8.0)
	_build_info.global_position = Vector2(x, _tab_row.global_position.y - _build_info.size.y - 12.0)
	_info_at = mid - x
	_build_info.queue_redraw()


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


## The chosen thing's card: a buff file card from the clerk's drawer, its kind printed small at
## the head, the name over a red line, the rest written in.
func _make_card() -> void:
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", Ui.sheet("file"))
	_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.offset_right = -12
	_card.offset_top = 84
	_card.visible = false
	add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size = Vector2(340, 0)
	_card.add_child(col)
	_card_kind = Ui.label(col, "", 11, Ui.P_DIM, "head")
	_card_title = Ui.label(col, "", 25, Ui.P_INK, "display")
	_card_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_title.custom_minimum_size = Vector2(330, 0)
	var red := ColorRect.new() # (the card's printed red line under the name)
	red.color = Color(Ui.P_RED, 0.8)
	red.custom_minimum_size = Vector2(0, 2)
	col.add_child(red)
	_make_folk_box(col)
	_card_lines = Ui.label(col, "", 15, Ui.P_INK)
	_card_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card_lines.custom_minimum_size = Vector2(300, 0)
	_card_workers = HBoxContainer.new()
	_card_workers.add_theme_constant_override("separation", 8)
	col.add_child(_card_workers)
	Ui.label(_card_workers, "İŞÇİ", 14, Ui.P_DIM, "head")
	_card_workers.add_child(_small_button("−", func() -> void: game.change_workers(-1)))
	_card_count = Ui.label(_card_workers, "0/3", 20, Ui.P_INK, "display")
	_card_workers.add_child(_small_button("+", func() -> void: game.change_workers(1)))
	_pick_btn = _add(_card_workers, "ATA ▾", func() -> void: _pick_open = null if _pick_open == game.selected else game.selected,
		"Kimin bu işe en yatkın olduğunu gör ve ata")
	_card_pick = VBoxContainer.new()
	_card_pick.add_theme_constant_override("separation", 3)
	col.add_child(_card_pick)
	_pick_title = Ui.label(_card_pick, "", 13, Ui.P_BLUE, "head")
	for i in 10:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_card_pick.add_child(row)
		var face := TextureRect.new()
		face.custom_minimum_size = Vector2(40, 40)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		row.add_child(face)
		var nm := Ui.label(row, "", 14, Ui.P_INK)
		nm.custom_minimum_size = Vector2(140, 0)
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var kn := Ui.label(row, "", 16, Ui.P_INK, "display")
		kn.custom_minimum_size = Vector2(44, 0)
		kn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var wh := Ui.label(row, "", 12, Ui.P_DIM)
		wh.custom_minimum_size = Vector2(110, 0)
		wh.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	_card_acts = HFlowContainer.new()
	_card_acts.add_theme_constant_override("v_separation", 4)
	_card_acts.add_theme_constant_override("h_separation", 8)
	col.add_child(_card_acts)
	_btn.repair = _add(_card_acts, "ONAR", func() -> void: game.repair_selected(), "Yıkılan parçaları yeniden yap (O)")
	for what: String in BuildingDefs.UPGRADES:
		var up: Dictionary = BuildingDefs.UPGRADES[what]
		_btn["up_" + what] = _add(_card_acts, str(up.name), func() -> void: game.upgrade_selected(what),
			"%s (%s)" % [up.tip, BuildingDefs.cost_text_of(up.cost)])
	_btn.mode = _add(_card_acts, "KERPİÇ YAP", func() -> void: game.toggle_mode_selected(), "Çamuru kalıba döküp kerpiç kurutsunlar / yalnızca çamur kazsınlar")
	_btn.demolish = _add(_card_acts, "YIK", func() -> void: game.demolish_selected(), "Binayı kaldır (Del)")
	_btn.look = _add(_card_acts, "ODAKLAN", func() -> void: game.focus_building(), "Kamerayı binaya götür")
	_btn.spur = _add(_card_acts, "YAN HAT DÖŞE", func() -> void: game.lay_spur_selected(), "Ana hattan buraya dar hatlı ray: tren yükü buradan doğrudan alır")
	_btn.ox = _add(_card_acts, "ÖKÜZ AL", func() -> void: game.buy_oxen(), "Arabalar öküz arabası olsun: 30 yük, yavaş; her öküz bir kişi kadar yer (%s)" % BuildingDefs.cost_text_of(BuildingDefs.OX_COST))
	_btn.strong = _add(_card_acts, "GÜÇLENDİR", func() -> void: game.strengthen_wall(), "Kalın kütük ve taş temel: kazıklar üç kat dayanıklı olur, zor kesilir, zor yanar")
	_btn.gate_lock = _add(_card_acts, "KİLİTLE", func() -> void: game.toggle_gate_lock(), "Kilitli kapıdan kimse geçemez; kasabalılar başka kapıya gider, yoksa bekler")
	_btn.gates_on = _add(_card_acts, "TÜMÜNÜ KİLİTLE", func() -> void: game.lock_all_gates(true), "Kasabanın bütün kapıları kilitlenir")
	_btn.gates_off = _add(_card_acts, "TÜMÜNÜ AÇ", func() -> void: game.lock_all_gates(false), "Bütün kapıların kilidi açılır: yine kapalı durur, bizimkiler geçerken açılır")
	_btn.area = _add(_card_acts, "ALAN ÇİZ", func() -> void: game.start_placing("alan"), "İşçiler yalnızca sürükleyeceğin alanda çalışsın")
	_btn.no_area = _add(_card_acts, "ALANI KALDIR", func() -> void: game.clear_work_area(), "İşçiler yine her yerde çalışsın")
	_card_make = HFlowContainer.new()
	_card_make.add_theme_constant_override("v_separation", 4)
	_card_make.add_theme_constant_override("h_separation", 4)
	col.add_child(_card_make)
	Ui.label(_card_make, "ÜRET:", 12, Ui.P_BLUE, "head")
	for what: String in BuildingDefs.WORKSHOP:
		var mb := _small_button(str(BuildingDefs.WORKSHOP[what].name), func() -> void: game.refit_selected(what))
		mb.tooltip_text = "Atölye %s için kurulsun: içi ona göre değişir, işçiler kalır" % BuildingDefs.WORKSHOP[what].word
		_card_make.add_child(mb)
		_make_btns[what] = mb
	_card_train = HFlowContainer.new()
	_card_train.add_theme_constant_override("v_separation", 4)
	_card_train.add_theme_constant_override("h_separation", 8)
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

	_card_folk = HFlowContainer.new()
	_card_folk.add_theme_constant_override("v_separation", 4)
	_card_folk.add_theme_constant_override("h_separation", 8)
	col.add_child(_card_folk)
	_btn.release = _add(_card_folk, "İŞTEN AL", func() -> void: game.release_selected(), "İşyerinden çıkar: taşır, inşa eder")
	_btn.militia = _add(_card_folk, "MİLİS YAP", func() -> void: game.toggle_militia(), "Tehlike çanında silahlıktan silah alıp mevziye geçer (M)")
	_btn.lantern = _add(_card_folk, "FENERİ SÖNDÜR", func() -> void: game.toggle_lantern(), "Karanlıkta görünmez olur ama az görür (L)")
	_btn.folk_look = _add(_card_folk, "ODAKLAN", func() -> void: game.focus_selected(), "Kamerayı ona götür")
	_btn.ctl = _add(_card_folk, "EMRE AL (R)", func() -> void: game.toggle_control(), "Emre al: işini bırakır; silahlı mevzi tutar ve ateş eder, silahsız yakında silah ya da balta kapar. Sağ tık ne yapacağını imleçte yazar (R)")
	_btn.ctl_gun = _add(_card_folk, "SİLAH AL", func() -> void: game.control_order("weapon"), "En yakın silahlıktan ya da yerdeki tüfekten silah alır")
	_btn.ctl_cover = _add(_card_folk, "SİPER", func() -> void: game.control_order("cover"), "En yakın sipere geçer")
	_btn.ctl_cover.visible = false # (a right-click on the cover itself does it: the pointer turns a shield)
	_btn.ctl_hide = _add(_card_folk, "SAKLAN", func() -> void: game.control_order("hide"), "En yakın eve ya da depoya saklanır")
	_btn.ctl_carry = _add(_card_folk, "YARALI TAŞI", func() -> void: game.control_order("carry"), "En yakın yerde yatan yaralıyı bir eve taşır")
	Ui.inkify(_card)


## The workplace card's list: everyone grown, best at the work first; those working here marked.
func _fill_pick(b: Building) -> void:
	var sk := Villager.skill_of(b)
	var folk: Array = game.village.villagers.filter(func(v: Villager) -> bool: return not v.dead and not v.is_child)
	folk.sort_custom(func(a: Villager, c: Villager) -> bool: return a.skill(sk) > c.skill(sk))
	_pick_title.text = "EN UYGUN: %s (%d/%d)" % [Ui.upper(str(Villager.SKILLS.get(sk, "iş"))), b.workers.size(), int(b.def.slots)]
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
		(row[1] as Label).add_theme_color_override("font_color", Ui.P_BLUE if here else Ui.P_INK)
		(row[2] as Label).text = str(int(v.skill(sk))) + (" ♥" if sk in v.keen else "")
		(row[2] as Label).tooltip_text = "Bu işe hevesli: iki kat hızlı öğrenir" if sk in v.keen else ""
		(row[2] as Label).mouse_filter = Control.MOUSE_FILTER_PASS
		(row[2] as Label).add_theme_color_override("font_color", Ui.P_GREEN if v.skill(sk) >= 6.0 else (Ui.P_DIM if v.skill(sk) < 2.0 else Ui.P_INK))
		var pr := int(v.prio.get(sk, 1))
		(row[3] as Label).text = ("burada" if here else (v.workplace.display_name() if is_instance_valid(v.workplace) else "boşta")) + (" ▲" if pr == 2 else (" –" if pr == 0 else ""))
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


func _add(row: Container, text: String, f: Callable, tip := "") -> Button:
	var b := _small_button(text, f)
	b.tooltip_text = tip
	row.add_child(b)
	return b


## The bar's four that open a book: tooled tags as the rest, but the word set in the book face, as
## on a spine.
func _nav_button(text: String, f: Callable) -> Button:
	var b := _small_button(text, f)
	b.add_theme_font_override("font", Ui.font("strong"))
	b.add_theme_font_size_override("font_size", 15)
	return b


func _small_button(text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(34, 30)
	b.add_theme_font_override("font", Ui.face("head", 14))
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Ui.INK)
	b.add_theme_color_override("font_hover_color", Ui.ACCENT)
	b.add_theme_stylebox_override("normal", Ui.glass(false, 5.0, Color(1, 1, 1, 0.06)))
	b.add_theme_stylebox_override("hover", Ui.glass(false, 5.0, Color(1.0, 0.56, 0.14, 0.3), Ui.ACCENT))
	b.add_theme_stylebox_override("pressed", Ui.glass(false, 5.0, Color(1.0, 0.56, 0.14, 0.45), Ui.ACCENT))
	b.pressed.connect(f)
	return b


## The keys, as the card printed for the settlers would have them: a heading for each kind of
## thing, a line a key, the keys drawn as keys; the cover table and the sides' rule in the corner.
func _make_help() -> void:
	_help = PanelContainer.new()
	_help.add_theme_stylebox_override("panel", Ui.sheet("card"))
	_help.set_anchors_preset(Control.PRESET_CENTER)
	_help.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_help.grow_vertical = Control.GROW_DIRECTION_BOTH
	_help.visible = false
	add_child(_help)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_help.add_child(col)
	var title := Ui.label(col, "TUŞLAR", 30, Ui.P_INK, "display")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := Ui.label(col, "Kordal hattı kasabaları için kullanım kartı", 14, Ui.P_DIM, "italic")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Ui.double_rule(col)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	col.add_child(cols)
	var groups: Array = [KEYS.slice(0, 3), KEYS.slice(3, 6), KEYS.slice(6)]
	for gi in groups.size():
		var c := VBoxContainer.new()
		c.add_theme_constant_override("separation", 3)
		c.custom_minimum_size = Vector2(300, 0)
		cols.add_child(c)
		for sec: Array in groups[gi]:
			_help_heading(c, str(sec[0]))
			for line: Array in sec[1]:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 8)
				c.add_child(row)
				var keys := HBoxContainer.new()
				keys.add_theme_constant_override("separation", 3)
				keys.custom_minimum_size = Vector2(124, 0)
				row.add_child(keys)
				for k: String in line[0]:
					if k in ["+", "/", "–"]:
						Ui.label(keys, k, 13, Ui.P_DIM).size_flags_vertical = Control.SIZE_SHRINK_CENTER
					else:
						Ui.keycap(keys, k)
				var what := Ui.label(row, str(line[1]), 15, Ui.P_INK)
				what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if gi == 2:
			_help_heading(c, "Siperdekine isabet")
			for pair: Array in COVER:
				var row := HBoxContainer.new()
				c.add_child(row)
				var nm := Ui.label(row, str(pair[0]), 14, Ui.P_INK)
				nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				Ui.label(row, "× " + str(pair[1]), 14, Ui.P_INK, "type_bold")
			var note := Ui.label(c, "Yukarıdan atış daha isabetli.", 13, Ui.P_DIM, "italic")
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Ui.double_rule(col)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	col.add_child(foot)
	var sides := Ui.label(foot, "Merkez ve Özgür Kordal: −30 ve altı düşman, +30 ve üstü dost.", 13, Ui.P_DIM, "italic")
	sides.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Ui.keycap(foot, "F1")
	Ui.label(foot, "kapat", 13, Ui.P_DIM, "italic").size_flags_vertical = Control.SIZE_SHRINK_CENTER


## A heading on the key card: the word in spaced capitals between two short rules.
func _help_heading(parent: Control, text: String) -> void:
	if parent.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		parent.add_child(gap)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Ui.label(row, Ui.upper(text), 13, Ui.P_RED, "head")
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var line := ColorRect.new()
	line.color = Color(Ui.P_RED, 0.5)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)


## While a building's being placed: turn it, or give up, with the mouse.
func _make_placing() -> void:
	_placing_plate = _plate(false)
	_placing_plate.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_placing_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_placing_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_placing_plate.offset_bottom = -188 # (above the build bar and its tabs)
	_placing_plate.visible = false
	add_child(_placing_plate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_placing_plate.add_child(row)
	row.add_child(_iron_button("↺  ÇEVİR", func() -> void: game.rotate_ghost(-15.0), "Sola çevir (Q, Shift + tekerlek)"))
	row.add_child(_iron_button("ÇEVİR  ↻", func() -> void: game.rotate_ghost(15.0), "Sağa çevir (E, Shift + tekerlek)"))
	row.add_child(_iron_button("VAZGEÇ", func() -> void: game.stop_placing(), "Koymaktan vazgeç (sağ tık / Esc)"))
	_place_make = HBoxContainer.new()
	_place_make.add_theme_constant_override("separation", 4)
	row.add_child(_place_make)
	Ui.label(_place_make, "   ÜRET", 12, Color(_FROST, 0.5), "head")
	for what: String in BuildingDefs.WORKSHOP:
		var mb := _iron_button(Ui.upper(str(BuildingDefs.WORKSHOP[what].name)), func() -> void: game.place_workshop_as(what), "")
		mb.tooltip_text = "Atölye %s için kurulsun" % BuildingDefs.WORKSHOP[what].word
		_place_make.add_child(mb)
		_place_btns[what] = mb


## A button of the bar's kind: pale letters on the iron, amber with a line under it when the mouse
## is on it.
func _iron_button(text: String, f: Callable, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_override("font", Ui.face("head", 13))
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", _FROST.darkened(0.15))
	b.add_theme_color_override("font_hover_color", _AMBER_HI)
	b.add_theme_color_override("font_pressed_color", _AMBER)
	b.add_theme_stylebox_override("normal", _tab_style(false, false))
	b.add_theme_stylebox_override("hover", _tab_style(false, true))
	b.add_theme_stylebox_override("pressed", _tab_style(true, true))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(f)
	return b


## The townsfolk register: a green account book, a row each, ruled in red between the columns:
## their knack at each kind of work (0-10, growing as they do it), and, clicked, whether they're put
## to it first (▲), as needed, or never (–).
func _make_people() -> void:
	_people_plate = PanelContainer.new()
	_people_plate.add_theme_stylebox_override("panel", Ui.sheet("register"))
	_people_plate.set_anchors_preset(Control.PRESET_CENTER)
	_people_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_people_plate.grow_vertical = Control.GROW_DIRECTION_BOTH
	_people_plate.visible = false
	add_child(_people_plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_people_plate.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	Ui.label(title, "KASABALILAR DEFTERİ", 26, Ui.P_INK, "display")
	Ui.label(title, "Nüfus ve iş kaydı", 14, Ui.P_DIM, "italic")
	var close := Ui.ink_button(Button.new(), Ui.P_RED, 15, "strong")
	close.text = "×"
	close.tooltip_text = "Kapat (K)"
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(func() -> void: toggle_people())
	head.add_child(close)
	Ui.double_rule(col, Ui.P_GREEN)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1010, 400)
	col.add_child(scroll)
	_people_grid = GridContainer.new()
	_people_grid.columns = 2 + Villager.SKILLS.size()
	_people_grid.add_theme_constant_override("h_separation", 0)
	_people_grid.add_theme_constant_override("v_separation", 0)
	_people_grid.draw.connect(_rule_register)
	scroll.add_child(_people_grid)
	var key := HBoxContainer.new()
	key.add_theme_constant_override("separation", 18)
	key.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(key)
	for pair: Array in [["♥", "hevesli: iki kat hızlı öğrenir"], ["▲", "önce bu işe"], ["–", "bu işe hiç"]]:
		var k := HBoxContainer.new()
		k.add_theme_constant_override("separation", 4)
		key.add_child(k)
		Ui.label(k, str(pair[0]), 14, Ui.P_RED, "strong")
		Ui.label(k, str(pair[1]), 13, Ui.P_DIM, "italic")


## The register's ruling: green under each row, red down between the columns, a double red line
## after the names.
func _rule_register() -> void:
	var g := _people_grid
	var cols := g.columns
	if g.get_child_count() < cols:
		return
	var h := g.size.y
	for c in range(1, cols):
		var x := (g.get_child(c) as Control).position.x - 1.0
		g.draw_line(Vector2(x, 0), Vector2(x, h), Color(Ui.P_RED, 0.55), 1.0)
		if c == 2:
			g.draw_line(Vector2(x - 3.0, 0), Vector2(x - 3.0, h), Color(Ui.P_RED, 0.55), 1.0)
	for i in range(0, g.get_child_count(), cols):
		var r := g.get_child(i) as Control
		var y := r.position.y + r.size.y
		g.draw_line(Vector2(0, y), Vector2(g.size.x, y), Color(Ui.P_GREEN, 0.9 if i == 0 else 0.35), 2.0 if i == 0 else 1.0)


## The research tree, over the middle of the screen: a drawing's sepia print pinned to the board, the
## studies drawn on it in cream, what's being read pencilled in yellow, a title block in the corner.
func _make_tech() -> void:
	_tech_plate = PanelContainer.new()
	_tech_plate.add_theme_stylebox_override("panel", Ui.sheet("blueprint"))
	_tech_plate.set_anchors_preset(Control.PRESET_CENTER)
	_tech_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tech_plate.grow_vertical = Control.GROW_DIRECTION_BOTH
	_tech_plate.visible = false
	add_child(_tech_plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_tech_plate.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	Ui.label(title, "ARAŞTIRMA PLANI", 26, Ui.CHALK, "display").remove_theme_constant_override("outline_size")
	_tech_note = Ui.label(title, "", 14, Color(Ui.CHALK, 0.75), "italic")
	_tech_note.remove_theme_constant_override("outline_size")
	var close := Ui.ink_button(Button.new(), Ui.CHALK, 14)
	close.text = "KAPAT"
	close.tooltip_text = "Kapat (T)"
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(func() -> void: toggle_tech())
	head.add_child(close)
	var line := ColorRect.new()
	line.color = Color(Ui.CHALK, 0.7)
	line.custom_minimum_size = Vector2(0, 1)
	col.add_child(line)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 6)
	col.add_child(pad)
	_tech_tree = TechTree.new()
	_tech_tree.game = game
	pad.add_child(_tech_tree)


## The day-book, over the middle of the screen: a ruled ledger page, the hours down the left of its
## red margin, what happened written in beside them, a day to a heading, newest first.
func _make_log() -> void:
	_log_plate = PanelContainer.new()
	_log_plate.add_theme_stylebox_override("panel", Ui.sheet("ledger"))
	_log_plate.set_anchors_preset(Control.PRESET_CENTER)
	_log_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_log_plate.grow_vertical = Control.GROW_DIRECTION_BOTH
	_log_plate.visible = false
	add_child(_log_plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_log_plate.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(72, 0)
	head.add_child(gap)
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -2)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	Ui.label(title, "GÜNLÜK", 28, Ui.P_INK, "display")
	Ui.label(title, "Kordal kasabası, olanlar defteri", 14, Ui.P_DIM, "italic")
	var close := Ui.ink_button(Button.new(), Ui.P_RED, 15, "strong")
	close.text = "×"
	close.tooltip_text = "Kapat (J)"
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(func() -> void: toggle_log())
	head.add_child(close)
	var top := VBoxContainer.new()
	top.add_theme_constant_override("separation", 2)
	col.add_child(top)
	for k in 2: # (the ledger's double red line across the head of the page)
		var r := ColorRect.new()
		r.color = Color(Ui.P_RED, 0.75)
		r.custom_minimum_size = Vector2(0, 1)
		top.add_child(r)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_log_list = VBoxContainer.new()
	_log_list.add_theme_constant_override("separation", 0)
	_log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_log_list)


func toggle_log() -> void:
	_log_plate.visible = not _log_plate.visible
	if _log_plate.visible:
		_people_plate.visible = false
		_tech_plate.visible = false
		_tele_plate.visible = false
		_fill_log()


func log_open() -> bool:
	return _log_plate.visible


func _fill_log() -> void:
	for ch in _log_list.get_children():
		ch.queue_free()
	if _log.is_empty():
		_ledger_line(_log_list, "", "Henüz bir şey yazılmadı.", Ui.P_DIM, "italic")
		return
	var day := -1
	for e: Array in _log.slice(0, 150):
		if int(e[0]) != day:
			day = int(e[0])
			var h := _ledger_line(_log_list, "", "Gün %d" % day, Ui.P_INK, "display")
			h.custom_minimum_size = Vector2(0, 34)
		_ledger_line(_log_list, "%02d.%02d" % [int(e[1]), int(fmod(float(e[1]), 1.0) * 60.0)], str(e[2]),
			{"good": Ui.P_GREEN, "bad": Ui.P_RED}.get(str(e[3]), Ui.P_INK), "text")


## A line of the ledger: the hour in the margin, the words beside it, the page's blue rule under them.
func _ledger_line(parent: Control, hour: String, text: String, ink: Color, kind: String) -> PanelContainer:
	var line := PanelContainer.new()
	var rule := StyleBoxFlat.new()
	rule.bg_color = Color(0, 0, 0, 0)
	rule.border_color = Color(Ui.P_BLUE, 0.28)
	rule.border_width_bottom = 1
	rule.content_margin_top = 3
	rule.content_margin_bottom = 2
	line.add_theme_stylebox_override("panel", rule)
	parent.add_child(line)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	line.add_child(row)
	var t := Ui.label(row, hour, 13, Ui.P_DIM, "type")
	t.custom_minimum_size = Vector2(50, 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	t.size_flags_vertical = Control.SIZE_SHRINK_END
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(22, 0)
	row.add_child(gap)
	var w := Ui.label(row, text, 20 if kind == "display" else 15, ink, kind)
	w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line


## The box being dragged to pick folk (empty: none).
var _sel_box: Panel


func show_select_box(r: Rect2, tint := Ui.ACCENT) -> void:
	if _sel_box == null:
		_sel_box = Panel.new()
		_sel_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.set_border_width_all(1)
		_sel_box.add_theme_stylebox_override("panel", sb)
		add_child(_sel_box)
	var style := _sel_box.get_theme_stylebox("panel") as StyleBoxFlat
	style.bg_color = Color(tint, 0.12)
	style.border_color = Color(tint, 0.9)
	_sel_box.visible = r.size.length() > 1.0
	# (mouse and unproject_position are already in the interface's own units: no scaling here)
	_sel_box.position = r.position
	_sel_box.size = r.size


## A question put to the player, a telegram form at the top middle: the office's printed head, the
## day and the hour filled in, what's happened typed out, the office's stamp struck over the corner,
## and a typed answer for each choice ({label, f, ok (false: shown but not to be pressed), tip}). Any
## answer takes it away; so does closing it from outside (the returned card, queue_free).
var _ask_no := 214 ## (the forms' running number)


func ask(title: String, body: String, options: Array) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Ui.sheet("slip"))
	p.custom_minimum_size = Vector2(540, 0)
	_asks.add_child(p)
	_log.push_front([game.village.day, game.weather.hour, title + ": " + body.get_slice("\n", 0), "info"]) # (in the day-book; the card says it on the screen)
	# the game held still while it's thought over, and let go when the last question's answered
	if not game.get_tree().paused:
		_ask_paused = true
		game.set_speed(0.0)
	p.tree_exited.connect(func() -> void:
		if _ask_paused and is_inside_tree() and _asks.get_children().all(func(c: Node) -> bool: return c.is_queued_for_deletion() or c == p):
			_ask_paused = false
			game.set_speed(Engine.time_scale))
	_ask_no += 1
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", -2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(left)
	Ui.label(left, "ZAROVYA POSTA VE TELGRAF İDARESİ", 11, Ui.P_DIM, "head")
	Ui.label(left, "TELGRAF", 30, Ui.P_INK, "display")
	var h := int(game.weather.hour)
	var form := HBoxContainer.new()
	form.add_theme_constant_override("separation", 16)
	left.add_child(form)
	for pair: Array in [["No.", str(_ask_no)], ["Gün", str(game.village.day)], ["Saat", "%02d.%02d" % [h, int((float(game.weather.hour) - h) * 60.0)]]]:
		var f := HBoxContainer.new()
		f.add_theme_constant_override("separation", 4)
		form.add_child(f)
		Ui.label(f, str(pair[0]), 12, Ui.P_DIM, "italic").size_flags_vertical = Control.SIZE_SHRINK_END
		Ui.label(f, str(pair[1]), 14, Ui.P_BLUE, "type_bold")
	head.add_child(Ui.Stamp.new("KORDAL TELGRAFHANESİ", "GÜN\n%d" % game.village.day, randf_range(-0.35, 0.2)))
	Ui.double_rule(col)
	var t := Ui.label(col, Ui.upper(title), 17, Ui.P_INK, "type_bold")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(500, 0)
	var msg := Ui.label(col, body, 15, Ui.P_INK, "type")
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(500, 0)
	var dash := Ui.label(col, "- ".repeat(60), 10, Color(Ui.P_INK, 0.35), "type")
	dash.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	dash.custom_minimum_size = Vector2(500, 0)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	row.alignment = FlowContainer.ALIGNMENT_END
	col.add_child(row)
	Ui.label(row, "Cevap:", 13, Ui.P_DIM, "italic").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for o: Dictionary in options:
		var f: Callable = o.f
		var b := Ui.ink_button(Button.new(), Ui.P_INK, 15, "type_bold")
		b.text = str(o.label)
		b.pressed.connect(func() -> void:
			if is_instance_valid(p):
				p.queue_free()
			f.call())
		b.disabled = not bool(o.get("ok", true))
		b.tooltip_text = str(o.get("tip", ""))
		row.add_child(b)
	return p


## The telegraph office, over the middle of the screen: the key and its tape on the operator's
## wooden desk, the forms to send beside them.
func _make_telegraph() -> void:
	_tele_plate = PanelContainer.new()
	_tele_plate.add_theme_stylebox_override("panel", Ui.sheet("wood"))
	_tele_plate.set_anchors_preset(Control.PRESET_CENTER)
	_tele_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tele_plate.grow_vertical = Control.GROW_DIRECTION_BOTH
	_tele_plate.visible = false
	add_child(_tele_plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_tele_plate.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var plate := PanelContainer.new() # (the office's brass plate on the desk)
	plate.add_theme_stylebox_override("panel", Ui.sheet("brass"))
	head.add_child(plate)
	Ui.label(plate, "TELGRAFHANE", 18, Color(0.2, 0.13, 0.06), "head")
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var close := _small_button("KAPAT", func() -> void: toggle_telegraph())
	close.tooltip_text = "Telgrafhaneyi kapat"
	head.add_child(close)
	_tele = TelegraphPanel.new()
	_tele.game = game
	col.add_child(_tele)


func toggle_telegraph() -> void:
	_tele_plate.visible = not _tele_plate.visible
	if _tele_plate.visible:
		_people_plate.visible = false
		_tech_plate.visible = false
		_tele.refresh()
		if _tele._tape._lines.is_empty():
			_tele.send("HAT ACIK STOP", "BURASI MERKEZ STOP DINLIYORUZ STOP")


func telegraph_open() -> bool:
	return _tele_plate.visible


## The whole valley on one sheet, made the first time it's opened: the seams found so far on it.
func toggle_map() -> void:
	if _map_plate == null:
		_map_plate = PanelContainer.new()
		_map_plate.add_theme_stylebox_override("panel", Ui.paper(6.0))
		_map_plate.set_anchors_preset(Control.PRESET_CENTER)
		_map_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_map_plate.grow_vertical = Control.GROW_DIRECTION_BOTH
		add_child(_map_plate)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		_map_plate.add_child(col)
		var head := HBoxContainer.new()
		col.add_child(head)
		var title := Ui.label(head, "KORDAL VADİSİ · KEŞİF HARİTASI", 20, Color(1.0, 0.87, 0.6), "head")
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var close := _small_button("KAPAT", func() -> void: toggle_map())
		close.tooltip_text = "Kapat (G)"
		head.add_child(close)
		_map_big = Minimap.new()
		_map_big.game = game
		_map_big.whole = true
		_map_big.side = 780.0
		_map_big.reach = 1000.0
		_map_big.on_click = func() -> void: toggle_map()
		col.add_child(_map_big)
		_map_note = Ui.label(col, "", 14, Color(0.95, 0.9, 0.8), "text")
		_map_note.add_theme_constant_override("outline_size", 0)
		_map_plate.visible = false
	_map_plate.visible = not _map_plate.visible
	if _map_plate.visible:
		_map_plate.move_to_front()
		var n: int = game.village.survey.found.size()
		_map_note.text = "▲ taş   ◆ demir   ■ kömür · %d damar bulundu · Kasabalılar yakınından geçince ya da gözcü kulesi görünce işlenir: emre alıp yolla" % n


func map_open() -> bool:
	return _map_plate != null and _map_plate.visible


func toggle_tech() -> void:
	_tech_plate.visible = not _tech_plate.visible
	if _tech_plate.visible:
		_people_plate.visible = false
		_refresh_tech()


func tech_open() -> bool:
	return _tech_plate.visible


func _refresh_tech() -> void:
	if not _tech_plate.visible:
		return
	var v: Village = game.village
	var rooms := 0
	var readers := 0
	for b in v.buildings:
		if b.kind == "okuma" and b.state == "done":
			rooms += 1
			readers += b.workers.size()
	if rooms == 0:
		_tech_note.text = "Okuma odası yok: konu şimdiden seçilebilir"
	elif readers == 0:
		_tech_note.text = "Okuma odasında okuyan yok"
	else:
		_tech_note.text = "%d kişi okuyor" % readers
	_tech_note.tooltip_text = "Araştırma okuma odasında yapılır (KASABA). Okuryazarlığı yüksek olan çabuk ilerler; bir konu bitince sıradakini seç."
	_tech_note.mouse_filter = Control.MOUSE_FILTER_PASS
	_tech_note.add_theme_color_override("font_color", Color(1.0, 0.84, 0.45) if readers == 0 else Color(Ui.CHALK, 0.75))
	_tech_tree.refresh()


func toggle_people() -> void:
	_people_plate.visible = not _people_plate.visible
	if _people_plate.visible:
		_tech_plate.visible = false
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
			_people_grid.remove_child(c) # (out at once: the rows below are counted from the new ones)
			c.queue_free()
		var cell := func(text: String, w: float, ink: Color, kind: String, size: int) -> Label:
			var l := Ui.label(_people_grid, text, size, ink, kind)
			l.custom_minimum_size = Vector2(w, 30)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			return l
		var c0: Label = cell.call("  Adı", 175, Ui.P_DIM, "italic", 13)
		c0.custom_minimum_size.y = 26
		cell.call("  Ne yapıyor", 150, Ui.P_DIM, "italic", 13)
		for k: String in Villager.SKILLS:
			var hd: Label = cell.call(str(Villager.SKILLS[k]).substr(0, 7) + ".", 62, Ui.P_DIM, "italic", 12)
			hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hd.tooltip_text = str(Villager.SKILLS[k])
			hd.mouse_filter = Control.MOUSE_FILTER_PASS
		for v: Villager in folk:
			cell.call("  " + v.display_name + (" (çocuk)" if v.is_child else ""), 175, Ui.P_INK, "text", 15)
			var j: Label = cell.call("", 150, Ui.P_DIM, "italic", 13)
			j.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			for k: String in Villager.SKILLS:
				var who := v
				var key := k
				var b := Button.new()
				b.focus_mode = Control.FOCUS_NONE
				b.custom_minimum_size = Vector2(62, 30)
				b.add_theme_font_override("font", Ui.font("type_bold"))
				b.add_theme_font_size_override("font_size", 15)
				b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
				b.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
				b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
				var over := StyleBoxFlat.new() # (the pencil's ring round the figure)
				over.bg_color = Color(Ui.P_BLUE, 0.08)
				over.border_color = Color(Ui.P_BLUE, 0.7)
				over.set_border_width_all(1)
				over.set_corner_radius_all(12)
				over.set_expand_margin_all(-3)
				b.add_theme_stylebox_override("hover", over)
				b.add_theme_stylebox_override("pressed", over)
				b.pressed.connect(func() -> void:
					who.prio[key] = [2, 0, 1][int(who.prio.get(key, 1))] # (normal -> first -> never -> normal)
					_refresh_people())
				b.tooltip_text = "%s, %s\nTıkla: önce bu işe, olağan, hiç" % [v.display_name, Villager.SKILLS[k]]
				b.disabled = v.is_child
				_people_grid.add_child(b)
	var cols := 2 + Villager.SKILLS.size()
	for i in folk.size():
		var v: Villager = folk[i]
		var base := cols * (i + 1)
		(_people_grid.get_child(base + 1) as Label).text = "  " + v.job
		var c := 0
		for k: String in Villager.SKILLS:
			var b := _people_grid.get_child(base + 2 + c) as Button
			var pr := int(v.prio.get(k, 1))
			b.text = ("%d%s%s" % [int(v.skill(k)), "♥" if k in v.keen else "", " ▲" if pr == 2 else ""]) if pr != 0 else "–"
			var ink: Color = Ui.P_BLUE if pr == 2 else (Color(Ui.P_INK, 0.35) if pr == 0 else (Ui.P_GREEN if v.skill(k) >= 6.0 else Ui.P_INK))
			for st: String in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
				b.add_theme_color_override(st, ink)
			c += 1
	_people_grid.queue_redraw()


func people_open() -> bool:
	return _people_plate.visible


func toggle_help() -> bool:
	_help.visible = not _help.visible
	return _help.visible


func help_open() -> bool:
	return _help.visible


## The pause: a railway timetable pasted on its board. The line's name over it, then the stops,
## each an entry (its number, its name, dots to the key it's under), the day and the hour it was
## stopped at the foot.
func _make_pause() -> void:
	_pause = PanelContainer.new()
	_pause.add_theme_stylebox_override("panel", Ui.sheet("wood"))
	_pause.set_anchors_preset(Control.PRESET_CENTER)
	_pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pause.visible = false
	add_child(_pause)
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", Ui.sheet("timetable"))
	_pause.add_child(sheet)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.custom_minimum_size = Vector2(400, 0)
	sheet.add_child(col)
	var line := Ui.label(col, "ZAROVYA DEMİRYOLLARI", 12, Ui.P_DIM, "head")
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := Ui.label(col, "DURAKLATILDI", 32, Ui.P_INK, "display")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := Ui.label(col, "Kordal hattı, son durak", 14, Ui.P_DIM, "italic")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Ui.double_rule(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	Ui.label(head, "No.", 11, Ui.P_DIM, "italic").custom_minimum_size = Vector2(34, 0)
	var h2 := Ui.label(head, "İstikamet", 11, Ui.P_DIM, "italic")
	h2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Ui.label(head, "Tuş", 11, Ui.P_DIM, "italic")
	var thin := ColorRect.new()
	thin.color = Color(Ui.P_INK, 0.6)
	thin.custom_minimum_size = Vector2(0, 1)
	col.add_child(thin)
	var stops: Array = [["Devam", "Esc", func() -> void: game.set_menu(false)], ["Kaydet", "F5", func() -> void: game.save_game()],
		["Yükle", "F9", func() -> void: game.load_game()], ["Tuşlar", "F1", func() -> void: toggle_help()],
		["Ayarlar", "", func() -> void: _show_settings(true)], ["Yeni oyun", "", func() -> void: game.new_game()],
		["Kaydet ve çık", "", func() -> void:
			game.save_game()
			game.get_tree().quit()]]
	for i in stops.size():
		col.add_child(_timetable_row(i + 1, str(stops[i][0]), str(stops[i][1]), stops[i][2]))
	Ui.double_rule(col)
	_pause_foot = Ui.label(col, "", 12, Ui.P_DIM, "italic")
	_pause_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


var _pause_foot: Label


## A line of the timetable, a button: its number, its name, the dots running to its key; the line
## underscored in pencil while the mouse is on it.
func _timetable_row(no: int, text: String, key: String, f: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	var none := StyleBoxEmpty.new()
	var over := StyleBoxFlat.new()
	over.bg_color = Color(Ui.P_BLUE, 0.08)
	over.border_color = Color(Ui.P_BLUE, 0.8)
	over.border_width_bottom = 2
	for st: String in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, none)
	for st: String in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, over)
	b.pressed.connect(f)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var n := Ui.label(row, "%d" % no, 15, Ui.P_DIM, "type_bold")
	n.custom_minimum_size = Vector2(28, 0)
	var name := Ui.label(row, text, 19, Ui.P_INK, "strong")
	var dots := Ui.label(row, " . ".repeat(40), 13, Color(Ui.P_INK, 0.55), "type")
	dots.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var k := Ui.label(row, key if key != "" else "—", 15, Ui.P_INK, "type_bold")
	k.custom_minimum_size = Vector2(36, 0)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for l: Label in [n, name, dots, k]:
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func show_menu(on: bool) -> void:
	_pause.visible = on
	if on and game and game.village and game.weather:
		var h := int(game.weather.hour)
		_pause_foot.text = "Gün %d, saat %02d.%02d itibariyle" % [game.village.day, h, int((game.weather.hour - h) * 60.0)]
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
	var v: Village = game.village if game else null
	_log.push_front([v.day if v else 0, game.weather.hour if game and game.weather else 0.0, text, kind])
	if _log.size() > 300:
		_log.resize(300)
	if _log_plate and _log_plate.visible:
		_fill_log()
	# the news as it comes off the line: a strip of telegraph tape, typed, pasted up
	var l := PanelContainer.new()
	l.add_theme_stylebox_override("panel", Ui.sheet("tape"))
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(l)
	var words := Ui.label(l, text, 15, {"good": Ui.P_GREEN, "bad": Ui.P_RED}.get(kind, Ui.P_INK), "type_bold")
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.offset_top = 112
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


## Off the screen, what wants seeing: an arrow at the edge toward it, a word what it is; a click and
## the view goes there (the camp once found, an armoured train, a fire, a band on the town).
var _marks := {} ## key -> Button


func _edge_marks() -> void:
	var cam3 := get_viewport().get_camera_3d()
	if cam3 == null or not visible:
		return
	var want := {}
	var v: Village = game.village
	var rd: Raids = game.raids
	if rd.camp_known and rd.camp_at != Vector3.INF:
		want["camp"] = ["KAMP", rd.camp_at]
	if is_instance_valid(v.armoured):
		want["armour"] = ["ZIRHLI TREN", v.armoured.engine_at()]
	if is_instance_valid(v.convoy) and not v.convoy._cars.is_empty():
		want["convoy"] = ["KONVOY", (v.convoy._cars[0].node as Node3D).global_position]
	if is_instance_valid(v.relief) and not v.relief._cars.is_empty():
		want["relief"] = ["YARDIM", (v.relief._cars[0].node as Node3D).global_position]
	for b in v.buildings:
		if b.is_burning():
			want["fire"] = ["YANGIN", b.global_position]
			break
	if rd.active:
		for r in rd.raiders:
			if is_instance_valid(r) and not r.dead:
				want["raid"] = ["BASKIN", r.position]
				break
	for key: String in _marks.keys():
		if not want.has(key):
			(_marks[key] as Button).queue_free()
			_marks.erase(key)
	var size := get_viewport().get_visible_rect().size
	var mid := size * 0.5
	for key: String in want:
		var at: Vector3 = want[key][1]
		var behind := cam3.is_position_behind(at)
		var sp := cam3.unproject_position(at)
		if behind:
			sp = mid - (sp - mid) * 10.0
		var on := not behind and sp.x > 40 and sp.x < size.x - 40 and sp.y > 120 and sp.y < size.y - 150
		if not _marks.has(key):
			# a leather tag with a brass edge, the word in red ink for trouble, blue for our own
			var bt := Button.new()
			bt.focus_mode = Control.FOCUS_NONE
			bt.add_theme_font_override("font", Ui.face("head", 14))
			bt.add_theme_font_size_override("font_size", 14)
			var ours: bool = key == "relief"
			var ink := Color(0.55, 0.75, 1.0) if ours else Color(1.0, 0.45, 0.35)
			bt.add_theme_color_override("font_color", ink)
			bt.add_theme_color_override("font_hover_color", Ui.INK)
			bt.add_theme_stylebox_override("normal", Ui.glass(false, 6.0, Color(0.2, 0.14, 0.1, 0.94), Ui.ACCENT))
			bt.add_theme_stylebox_override("hover", Ui.glass(false, 6.0, Color(0.32, 0.22, 0.14, 0.96), Ui.ACCENT))
			bt.add_theme_stylebox_override("pressed", Ui.glass(false, 6.0, Color(0.32, 0.22, 0.14, 0.96), Ui.ACCENT))
			bt.tooltip_text = "Tıkla: kamera oraya gitsin"
			add_child(bt)
			_marks[key] = bt
		var b: Button = _marks[key]
		b.visible = not on
		if on:
			continue
		var d := (sp - mid)
		var k := minf((mid.x - 70.0) / maxf(absf(d.x), 0.001), (mid.y - 140.0) / maxf(absf(d.y), 0.001))
		var edge := mid + d * k
		var arrow := ("→" if d.x > 0 else "←") if absf(d.x) * size.y > absf(d.y) * size.x else ("↓" if d.y > 0 else "↑")
		var far := Vector2(at.x - game.cam.focus.x, at.z - game.cam.focus.z).length()
		b.text = "%s  %s · %d m" % [arrow, want[key][0], roundi(far / 10.0) * 10]
		var target: Vector3 = want[key][1]
		if b.pressed.get_connections().size() > 0:
			for c in b.pressed.get_connections():
				b.pressed.disconnect(c.callable)
		b.pressed.connect(func() -> void: game.cam.jump_to(target))
		b.position = edge - b.size * 0.5


func _process(dt: float) -> void:
	_unfold(dt)
	_t += dt
	if _t < 0.15:
		return
	_t = 0.0
	_edge_marks()
	var v: Village = game.village
	var stock := v.stock
	_refresh_goods(v, stock)
	_pop.text = "%d/%d (%d)" % [v.villagers.size(), v.beds(), v.free_count()]
	_purse.text = "%d m" % v.rubles
	var due := v.next_train - v.day
	if not v.knows("telgraf"):
		_train_stat.text = "—"
	elif v.line_shut():
		_train_stat.text = "Kapalı"
	elif is_instance_valid(v.armoured):
		_train_stat.text = "Zırhlı"
	elif is_instance_valid(v.train):
		_train_stat.text = "Peronda"
	else:
		_train_stat.text = "Bugün" if due <= 0 else "%d gün" % due
	_train_stat.add_theme_color_override("font_color", Ui.BAD if v.line_shut() or is_instance_valid(v.armoured) else Ui.INK)

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
	_clock.text = str(game.village.day)
	_clock_time.text = "%02d.%02d" % [h, m]
	_clock_sky.text = str(WEATHER_NAMES.get(w._state, w._state))
	_dial.refresh()
	_strip.refresh()
	var rd: Raids = game.raids
	if rd.active:
		var alive := 0
		for x in rd.raiders:
			if is_instance_valid(x) and not x.dead:
				alive += 1
		_raid.text = "%d haydut" % alive
		_raid.add_theme_color_override("font_color", Ui.P_RED)
	else:
		_raid.text = ("Gün %d" % rd.next_day) if rd.next_day > v.day else "Bu gece"
		_raid.add_theme_color_override("font_color", Ui.P_INK)
	var now := 0.0 if game.get_tree().paused else Engine.time_scale
	for k in _speed_buttons.size():
		var on := is_equal_approx(now, 0.0 if k == 0 else SPEEDS[k - 1])
		_speed_buttons[k].add_theme_stylebox_override("normal", Ui.ink_box(Ui.P_INK, 0.0, 0.5, on))
	for b: Node in _build_row.get_children():
		if b.has_meta("kind") and BuildingDefs.DEFS.has(b.get_meta("kind")):
			var can := true
			var cost: Dictionary = BuildingDefs.DEFS[b.get_meta("kind")].cost
			for r: String in cost:
				if int(stock.get(r, 0)) < int(cost[r]):
					can = false
			var row := b.get_meta("cost_row") as Control
			var lock := b.get_meta("lock_label") as Label
			var locked: bool = b.has_meta("needs") and not game.village.knows(str(b.get_meta("needs")))
			row.visible = false
			lock.visible = false
			var kind: String = b.get_meta("kind")
			var was_locked: bool = b.get_meta("locked", false)
			if was_locked and not locked and not _seen_new.has(kind):
				b.set_meta("new", true) # (just unlocked: a red dot till it's looked at)
			var count := 0
			for o in v.buildings:
				if o.kind == kind and o.state != "gone":
					count += 1
			var held: bool = game._placing == kind
			if was_locked != locked or bool(b.get_meta("short", false)) != (not can) or int(b.get_meta("count", 0)) != count or bool(b.get_meta("held", false)) != held:
				b.set_meta("locked", locked)
				b.set_meta("short", not can)
				b.set_meta("count", count)
				b.set_meta("held", held)
				(b as Control).queue_redraw()
	_update_card()


func _update_card() -> void:
	_people_t += 0.016
	if _people_t > 0.5:
		_people_t = 0.0
		_refresh_people()
		_refresh_tech()
		if _tele_plate.visible:
			_tele.refresh()
	if _people_plate.visible or _tech_plate.visible or _tele_plate.visible:
		_card.visible = false # (the table's over where the card stands)
		return
	_placing_plate.visible = game._placing != "" and not game._placing in ["yol", "sur", "kapi"]
	_place_make.visible = game._placing in BuildingDefs.WORKSHOP_KINDS
	if _place_make.visible:
		for what: String in _place_btns:
			var w: Dictionary = BuildingDefs.WORKSHOP[what]
			var pb: Button = _place_btns[what]
			pb.visible = game.village.knows(str(w.get("needs", "")))
			var on: bool = w.kind == game._placing and str(w.get("mode", "")) == game._placing_mode
			pb.add_theme_stylebox_override("normal", Ui.glass(false, 5.0, Color(1.0, 0.56, 0.14, 0.4) if on else Color(1, 1, 1, 0.06), Ui.ACCENT if on else Ui.EDGE))
	var folk: Villager = game.selected_villager
	if folk and is_instance_valid(folk) and not folk.dead:
		_folk_card(folk)
		return
	var gt: Gate = game.selected_gate
	if gt and is_instance_valid(gt):
		_gate_card(gt)
		return
	var w: Wall = game.selected_wall
	if w and is_instance_valid(w):
		_wall_card(w)
		return
	(_btn.gate_lock as Button).visible = false
	(_btn.gates_on as Button).visible = false
	(_btn.gates_off as Button).visible = false
	var b: Building = game.selected
	if b == null or not is_instance_valid(b) or b.state == "gone":
		_card.visible = false
		return
	_card.visible = true
	_card_folk.visible = false
	_folk_box.visible = false
	_card_jail.visible = false
	_card_extra.visible = false
	_card_make.visible = false
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
	(_btn.mode as Button).visible = b.state == "done" and b.kind == "camur"
	(_btn.spur as Button).visible = b.state == "done" and not b.spur and b != game.village.depot() and b.def.role in ["store", "work"] and game.village.knows("dekovil")
	if (_btn.spur as Button).visible:
		(_btn.spur as Button).tooltip_text = "Ana hattan buraya dar hatlı ray: tren yükü buradan doğrudan alır (%s)" % BuildingDefs.cost_text_of(game.village.spur_cost(b))
	(_btn.ox as Button).visible = b.kind == "arabaci" and b.state == "done" and not b.ox
	(_btn.strong as Button).visible = false
	(_btn.area as Button).visible = b.def.role in ["work", "forest"] and b.kind != "camur" and b.state == "done"
	(_btn.no_area as Button).visible = (_btn.area as Button).visible and b.work_area.has_area()
	(_btn.mode as Button).text = "ÇAMUR KAZ" if b.mode == "kerpic" else "KERPİÇ YAP"
	var making := BuildingDefs.workshop_of(b) if b.state in ["done", "site"] else ""
	_card_make.visible = making != ""
	for what: String in _make_btns:
		var mb: Button = _make_btns[what]
		mb.visible = game.village.knows(str(BuildingDefs.WORKSHOP[what].get("needs", "")))
		var on := what == making
		mb.add_theme_stylebox_override("normal", Ui.ink_box(Ui.P_INK, 0.0, 0.55, on))
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
			lines.append("Harabe.")
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
		lines.append("Oturanlar (%d/%d): %s" % [b.residents.size(), b.beds(), "; ".join(parts) if not parts.is_empty() else "kimse"])
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
		lines.append(("İçinde (%d / %d): " if b.def.role == "store" else "Yığın (%d / %d): ") % [b.goods_total(), b.holds()] + ", ".join(g))
	_card_workers.visible = b.def.role in ["work", "barracks", "tower", "carts", "farm", "research", "smith", "healer"] and b.state == "done"
	if _card_workers.visible:
		# (working there now, of how many it's asked for: red while it's short)
		_card_count.text = "%d / %d" % [b.workers.size(), b.wanted]
		_card_count.add_theme_color_override("font_color", Ui.P_RED if b.workers.size() < b.wanted or b.wanted == 0 else Ui.P_INK)
		_card_count.tooltip_text = "Çalışan / istenen (en çok %d)" % int(b.def.slots)
		_card_count.mouse_filter = Control.MOUSE_FILTER_PASS
		var names: Array[String] = []
		var sk := Villager.skill_of(b)
		for x in b.workers:
			if is_instance_valid(x):
				names.append(x.display_name + ((" (%d)" % int(x.skill(sk))) if sk != "" else ""))
		if names.is_empty():
			lines.append("Çalışan yok." if b.wanted == 0 else "Çalışan yok: boşta kasabalı kalmadı.")
		if b.workers.size() < b.wanted:
			lines.append("Boşta kasabalı yok: %d işçi eksik" % (b.wanted - b.workers.size()))
	_card_lines.text = "\n".join(lines).replace(" · ", ", ")
	_card_kind.text = "YAPI KAYDI"
	_card.tooltip_text = "Harabeyi ONAR parça parça yeniden yapar, YIK kaldırır." if b.state == "ruin" else ""
	if b.state == "done" and b.def.role in ["work", "barracks", "tower", "carts", "farm", "research", "smith", "healer"]:
		_card_count.tooltip_text += "\n+ ile işçi iste ya da ATA'dan birini seç"


## A gate's card: how it stands, and the bar.
func _gate_card(g: Gate) -> void:
	_wall_card(g.wall)
	(_btn.strong as Button).visible = false
	(_btn.gate_lock as Button).visible = true
	(_btn.gate_lock as Button).text = "KİLİDİ AÇ" if g.locked else "KİLİTLE"
	_card_title.text = "SUR KAPISI"
	_card_kind.text = "KAPI KAYDI"
	var state := "Kırık: açık duruyor, onarılacak" if g.broken else ("KİLİTLİ: kimse geçemez" if g.locked else "Kapalı: bizimkiler geçerken açılır")
	_card_lines.text = "%s\nDayanıklılık: %d / %d" % [state, roundi(g.hp), roundi(Gate.HP)]
	_card.tooltip_text = "Firariler kilitli kapıyı da kırmaya çalışır. YIK: kapı sökülür, yerine kazık dikilir."


func _wall_card(w: Wall) -> void:
	_card.visible = true
	(_btn.gate_lock as Button).visible = false
	(_btn.gates_on as Button).visible = true
	(_btn.gates_off as Button).visible = true
	_card_workers.visible = false
	_card_train.visible = false
	_card_pick.visible = false
	_card_folk.visible = false
	_folk_box.visible = false
	_card_jail.visible = false
	_card_extra.visible = false
	_card_make.visible = false
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
			gs.append("kırık" if g.broken else ("kilitli" if g.locked else ("açık" if g.is_open else "kapalı")))
	lines.append("Kapılar: " + (", ".join(gs) if not gs.is_empty() else "yok (kasabalılar geçemez; SUR KAPISI koy)"))
	if not w.burning.is_empty():
		lines.append("YANIYOR: %d kazık (yavaş yanar; yağmur söndürür)" % w.burning.size())
	_card_lines.text = "\n".join(lines)
	_card_kind.text = "SUR KAYDI"
	_card.tooltip_text = "Milis surun iç tarafındaki basamaktan ateş eder. YIK: sökülür, kazıkların yarısının odunu geri gelir."


# --- A villager's card: its face, what it's doing, how it is, what it's good at ------------------

var _folk_box: VBoxContainer
var _folk_face: TextureRect
var _folk_job: Label
var _folk_state: Label
var _folk_wounds: Label ## where it's hurt, whether it's bleeding
var _folk_traits: HFlowContainer ## a word a trait (its good and its bad on the mouse)
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
	var photo := PanelContainer.new() # (the photograph, its white border, a little crooked on the card)
	var print := StyleBoxFlat.new()
	print.bg_color = Color(0.97, 0.95, 0.9)
	print.set_content_margin_all(4)
	print.content_margin_bottom = 9
	print.shadow_color = Color(0, 0, 0, 0.28)
	print.shadow_size = 3
	print.shadow_offset = Vector2(1, 2)
	photo.add_theme_stylebox_override("panel", print)
	photo.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	photo.rotation = -0.03
	head.add_child(photo)
	_folk_face = TextureRect.new()
	_folk_face.custom_minimum_size = Vector2(80, 84)
	_folk_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_folk_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	photo.add_child(_folk_face)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(side)
	_folk_job = Ui.label(side, "", 16, Ui.P_INK, "strong")
	_folk_job.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_folk_job.custom_minimum_size = Vector2(230, 0)
	_folk_state = Ui.label(side, "", 14, Ui.P_DIM, "italic")
	_folk_wounds = Ui.label(side, "", 13, Ui.P_RED, "strong")
	_folk_wounds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_folk_wounds.custom_minimum_size = Vector2(230, 0)
	_folk_traits = HFlowContainer.new()
	_folk_traits.add_theme_constant_override("h_separation", 10)
	side.add_child(_folk_traits)
	_folk_hp = _bar(Color(0.36, 0.55, 0.26), 230, 6)
	_folk_hp.mouse_filter = Control.MOUSE_FILTER_PASS
	side.add_child(_folk_hp)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	_folk_box.add_child(mrow)
	Ui.label(mrow, "MORAL", 12, Ui.P_BLUE, "head")
	_folk_mood = _bar(Ui.P_GREEN, 150, 8)
	_folk_mood.max_value = 100.0
	mrow.add_child(_folk_mood)
	_folk_mood_word = Ui.label(mrow, "", 13, Ui.P_INK, "head")
	_folk_thoughts = Ui.label(_folk_box, "", 13, Ui.P_INK)
	_folk_thoughts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_folk_thoughts.custom_minimum_size = Vector2(330, 0)
	var sk := Ui.label(_folk_box, "BECERİLER", 12, Ui.P_RED, "head")
	sk.tooltip_text = "♥ hevesli: iki kat hızlı öğrenir\n▲ önce bu işe verilir\n– bu işe hiç verilmez"
	sk.mouse_filter = Control.MOUSE_FILTER_PASS
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 1)
	_folk_box.add_child(grid)
	for i in Villager.SKILLS.size():
		var n := Ui.label(grid, "", 13, Ui.P_INK, "head")
		n.custom_minimum_size = Vector2(96, 0)
		var bar := _bar(Color(Ui.P_INK, 0.7), 130, 5)
		bar.max_value = 10.0
		grid.add_child(bar)
		var num := Ui.label(grid, "", 15, Ui.P_INK, "display")
		num.custom_minimum_size = Vector2(22, 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var marks := Ui.label(grid, "", 13, Ui.P_BLUE, "head")
		marks.custom_minimum_size = Vector2(26, 0)
		_folk_rows.append([n, bar, num, marks])
	var end := ColorRect.new()
	end.color = Color(Ui.P_BLUE, 0.35)
	end.custom_minimum_size = Vector2(0, 1)
	_folk_box.add_child(end)


func _fill_folk_box(v: Villager) -> void:
	_folk_box.visible = true
	_folk_face.texture = Portraits.of(v)
	_folk_job.text = v.job
	var state := "iyi"
	if v.down:
		state = "YARALI, YERDE"
	elif v.bleeding:
		state = "KANIYOR: felçer gerek"
	elif v.recovering:
		state = "yatakta, iyileşiyor"
	elif v.sleeping:
		state = "uyuyor"
	elif v.hp < v.max_hp * 0.999:
		state = "yaralı"
	var age := "çocuk, %d günlük" % (game.village.day - v.born_day) if v.is_child else ("kadın" if v.female else "erkek")
	_folk_state.text = "%s%s%s" % [age, (", " + str(Villager.ORIGINS[v.origin].name).to_lower()) if v.origin != "" else "", (", " + state) if state != "iyi" else ""]
	_folk_hp.tooltip_text = "Can %d / %d" % [int(v.hp), int(v.max_hp)]
	_folk_wounds.visible = not v.wounds.is_empty() or v.bleeding
	if _folk_wounds.visible:
		_folk_wounds.text = "YARALAR: %s%s%s" % [v.wounds_text() if not v.wounds.is_empty() else "yarası var", ", KANIYOR" if v.bleeding else "", ", sarıldı" if v.treated else ""]
	if _folk_traits_of != v or _folk_traits.get_child_count() != v.traits.size() + v.scars.size():
		_folk_traits_of = v
		for ch in _folk_traits.get_children():
			ch.queue_free()
		for t: String in v.traits:
			var tr: Dictionary = Villager.TRAITS[t]
			var line := Ui.label(_folk_traits, str(tr.name), 13, Ui.P_BLUE, "strong")
			line.tooltip_text = "+ %s\n− %s" % [tr.plus, tr.minus]
			line.mouse_filter = Control.MOUSE_FILTER_PASS
		for t: String in v.scars:
			var sc: Dictionary = Villager.SCARS[t]
			var line := Ui.label(_folk_traits, str(sc.name), 13, Ui.P_RED, "strong")
			line.tooltip_text = str(sc.minus)
			line.mouse_filter = Control.MOUSE_FILTER_PASS
	var m := v.mood
	_folk_mood.value = m
	(_folk_mood.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Ui.P_GREEN if m >= 55.0 else (Color(0.7, 0.5, 0.15) if m >= 35.0 else Ui.P_RED)
	_folk_mood_word.text = "%s (%d)" % [v.mood_word(), roundi(m)]
	var th: Array = v.thoughts.duplicate()
	th.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(float(a.value)) > absf(float(b.value)))
	var lines: Array[String] = []
	for t: Dictionary in th.slice(0, 6):
		lines.append("%+d  %s" % [roundi(float(t.value)), t.text])
	_folk_thoughts.text = "\n".join(lines) if not lines.is_empty() else "Aklında bir şey yok"
	_folk_hp.max_value = v.max_hp
	_folk_hp.value = v.hp
	(_folk_hp.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Ui.P_RED if v.hp < v.max_hp * 0.4 else (Color(0.7, 0.5, 0.15) if v.hp < v.max_hp * 0.8 else Color(0.36, 0.55, 0.26))
	var ks: Array = Villager.SKILLS.keys()
	ks.sort_custom(func(a: String, b: String) -> bool: return v.skill(a) > v.skill(b))
	var work := Villager.skill_of(v.workplace) if is_instance_valid(v.workplace) else ""
	for i in ks.size():
		var k: String = ks[i]
		var row: Array = _folk_rows[i]
		var sk := v.skill(k)
		var pr := int(v.prio.get(k, 1))
		(row[0] as Label).text = str(Villager.SKILLS[k])
		(row[0] as Label).add_theme_color_override("font_color", Ui.P_BLUE if k == work else (Ui.P_DIM if pr == 0 else Ui.P_INK))
		(row[1] as ProgressBar).value = sk
		(row[1] as ProgressBar).modulate = Color(1, 1, 1, 0.35 if pr == 0 else 1.0)
		(row[2] as Label).text = str(int(sk))
		(row[2] as Label).add_theme_color_override("font_color", Ui.P_GREEN if sk >= 6.0 else (Ui.P_DIM if sk < 2.0 else Ui.P_INK))
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
	var sig := "%s|%s|%s|%s|%s|%d|%d" % [b.get_instance_id(), v.known, v.studying, v.announced, v.selling, v.rubles, roundi(v.drift * 50.0)]
	if sig != _extra_sig:
		_extra_sig = sig
		for ch in _card_extra.get_children():
			ch.queue_free()
		if kind == "istasyon":
			Ui.label(_card_extra, "TREN VE TELGRAF", 12, Ui.P_RED, "head")
			if not v.knows("telgraf"):
				var l := Ui.label(_card_extra, "Telgraf yok: tren gelmiyor.", 14, Ui.P_DIM, "italic")
				l.tooltip_text = "Telgraf olmadan köy Merkez'e bildirilemez. Telgraf okuma odasında araştırılır."
				l.mouse_filter = Control.MOUSE_FILTER_PASS
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.custom_minimum_size = Vector2(300, 0)
				var rb := _small_button("ARAŞTIRILIYOR: TELGRAF" if v.studying == "telgraf" else "TELGRAFI ARAŞTIR", func() -> void:
					game.village.study("telgraf")
					_extra_sig = ""
					if not game.village.buildings.any(func(o: Building) -> bool: return o.kind == "okuma" and o.state == "done"):
						toast("Telgraf seçildi: araştırma için bir okuma odası kur (KASABA > Okuma odası)", "info"))
				rb.disabled = v.studying == "telgraf"
				rb.tooltip_text = "Okuma odasının konusu Telgraf olsun"
				_card_extra.add_child(rb)
			else:
				var tb := _small_button("TELGRAFHANE ▸", func() -> void: toggle_telegraph())
				tb.tooltip_text = "Telgrafhaneyi aç: köyü bildir, mal sat, tren çağır, yardım iste"
				_card_extra.add_child(tb)
		else:
			Ui.label(_card_extra, "ARAŞTIRMA", 12, Ui.P_RED, "head")
			for t: String in BuildingDefs.TECHS:
				var td: Dictionary = BuildingDefs.TECHS[t]
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 8)
				_card_extra.add_child(row)
				var known := v.knows(t)
				var l := Ui.label(row, "%s%s" % [td.name, "  ✓" if known else ""], 14, Ui.P_GREEN if known else (Ui.P_BLUE if t == v.studying else Ui.P_INK), "head")
				l.tooltip_text = str(td.desc)
				l.mouse_filter = Control.MOUSE_FILTER_PASS
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				if not known:
					var after := str(td.get("after", ""))
					if not v.knows(after):
						Ui.label(row, "önce %s" % BuildingDefs.TECHS[after].name, 12, Ui.P_DIM)
					elif t != v.studying:
						var bt := _small_button("ARAŞTIR", func() -> void: v.study(t))
						bt.tooltip_text = str(td.desc)
						row.add_child(bt)
		_extra_status = Ui.label(_card_extra, "", 13, Ui.P_DIM, "italic")
		_extra_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_extra_status.custom_minimum_size = Vector2(300, 0)
		Ui.inkify(_card_extra)
	if kind == "istasyon":
		if not v.knows("telgraf"):
			_extra_status.text = ""
		else:
			var due := v.next_train - v.day
			var standing := "Tren istasyonda"
			if v.loading_until >= 0.0:
				var left := (v.loading_until - v.clock) / maxf(game.weather.day_length_minutes * 60.0, 60.0) * 24.0
				var on: Array[String] = []
				for r in v.selling:
					var n := 0
					for pb in v.platform():
						n += int(pb.goods.get(r, 0))
					on.append("%d %s" % [n, BuildingDefs.RES_NAMES[r].to_lower()])
				standing = "Tren perona yanaştı: %d sa %02d dk sonra kalkar%s" % [int(left), int(fmod(left, 1.0) * 60.0), ("; peronda: " + ", ".join(on)) if not on.is_empty() else ""]
			_extra_status.text = "%s.%s\nKasada %d mirka. Her trenle %d göçmen." % [standing if is_instance_valid(v.train) else ("Tren bugün bekleniyor" if due <= 0 else "Tren ~%d gün sonra bekleniyor" % due),
				"" if v.announced else "\nKöy henüz ana karaya bildirilmedi.", v.rubles, v.settlers_due()]
			if v.line_state() != "":
				_extra_status.text = v.line_state() + "\n" + _extra_status.text
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
		Ui.label(_card_jail, "ESİRLER", 12, Ui.P_BLUE, "head")
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
			Ui.label(col, o.display_name, 15, Ui.P_INK, "head")
			var ks: Array = Villager.SKILLS.keys()
			ks.sort_custom(func(a: String, c: String) -> bool: return o.skill(a) > o.skill(c))
			var tr: Array = o.traits.map(func(t: String) -> String: return str(Villager.TRAITS[t].name))
			var info := Ui.label(col, "%s %d, %s %d%s" % [Villager.SKILLS[ks[0]], int(o.skill(ks[0])), Villager.SKILLS[ks[1]], int(o.skill(ks[1])),
				("; " + ", ".join(tr)) if not tr.is_empty() else ""], 12, Ui.P_DIM, "italic")
			info.custom_minimum_size = Vector2(200, 0)
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var state := Ui.label(col, "", 12, Ui.P_BLUE, "head")
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
			free.tooltip_text = "Serbest bırak: gider, firariler bir gün daha geç gelir"
			btns.add_child(free)
			var talk := _small_button("SORGULA", func() -> void: game.village.interrogate(o))
			talk.tooltip_text = "Sorgula: kampın yerini, baskının ne zaman geleceğini söyleyebilir (bir kez)"
			btns.add_child(talk)
			var hand := _small_button("MERKEZE VER", func() -> void: game.village.hand_over(o))
			hand.tooltip_text = "Merkez'e teslim et: fidye olarak 20 mirka, Merkez memnun, Özgür Kordal kızgın"
			btns.add_child(hand)
			var kill := _small_button("İDAM", func() -> void: game.village.execute(o))
			kill.tooltip_text = "İdam et: firariler üç gün daha geç gelir, ama bütün kasabanın morali ağır düşer"
			kill.add_theme_color_override("font_color", Ui.P_RED)
			btns.add_child(kill)
		Ui.inkify(_card_jail)
	for n in _card_jail.find_children("*", "", true, false):
		if not n.has_meta("who") or not is_instance_valid(n.get_meta("who")):
			continue
		var o: Villager = n.get_meta("who")
		if n is TextureRect:
			(n as TextureRect).texture = Portraits.of_look(o.look_seed, "outlaw")
		elif n is Label:
			(n as Label).text = {"": "Hapiste; kazanma şansı %%%d" % roundi(game.village.win_chance(o) * 100.0), "kazan": "Kazanılıyor %d/3, bu sabah şansı %%%d" % [o.won, roundi(game.village.win_chance(o) * 100.0)], "calistir": "Zorla çalıştırılıyor"}[o.held_mode]
		elif n is Button and n.has_meta("mode"):
			(n as Button).add_theme_color_override("font_color", Ui.P_BLUE if o.held_mode == n.get_meta("mode") else Ui.P_INK)


func _folk_card(v: Villager) -> void:
	_card.visible = true
	_card_workers.visible = false
	_card_acts.visible = false
	_card_train.visible = false
	_card_pick.visible = false
	_card_folk.visible = true
	_card_jail.visible = false
	_card_extra.visible = false
	_card_make.visible = false
	var many: Array = game._chosen()
	var guard: bool = v.workplace != null and v.workplace.def.role in ["barracks", "tower"]
	(_btn.release as Button).visible = v.workplace != null and many.size() <= 1
	(_btn.militia as Button).visible = not v.is_child and not guard
	(_btn.militia as Button).text = "MİLİSTEN ÇIKAR" if v.militia else "MİLİS YAP"
	# one button for all chosen: EMRE AL while any of them isn't in hand, BIRAK once they all are
	var held: bool = game.village.controlled(v)
	var all_held := many.all(func(o: Villager) -> bool: return o.is_child or o.down or game.village.controlled(o))
	(_btn.ctl as Button).visible = not v.down and many.any(func(o: Villager) -> bool: return not o.is_child and not o.down)
	(_btn.ctl as Button).text = "BIRAK (R)" if all_held and held else "EMRE AL (R)"
	(_btn.ctl as Button).tooltip_text = "Bırak: yine kendi işine döner (R)" if all_held and held else "Emre al: işini bırakır; silahlı mevzi tutar ve ateş eder, silahsız yakında silah ya da balta kapar. Sağ tık ne yapacağını imleçte yazar (R)"
	(_btn.ctl as Button).add_theme_color_override("font_color", Ui.P_BLUE if held else Ui.P_INK)
	for key in ["ctl_gun", "ctl_hide", "ctl_carry"]: # (cover: a right-click on it)
		(_btn[key] as Button).visible = held and many.size() <= 1
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
		lines.append("Milis (%s)%s · %s: %d · Fener: %s" % [{"rifle": "tüfekçi", "bow": "okçu"}.get(v.weapon, "silahı raftan"), " · EMİRDE" if held else "",
			"Ok" if v.held == "bow" else "Fişek", v.ammo, {"": "oto", "off": "sönük", "on": "yanık"}[v.lantern_mode]])
		# its cover against the nearest foe: what shields it, and how hard it is to hit
		var foe: Villager = game.raids.nearest_raider(v.position, 160.0)
		if foe:
			var cv: Array = game.raids.cover(foe.position + Vector3.UP * 1.4, v)
			var back: Array = game.raids.cover(v.position + Vector3.UP * 1.4, foe)
			lines.append("Siper: %s · düşman isabeti %%%d  ·  bizim isabetimiz %%%d" % [str(cv[1]) if str(cv[1]) != "" else "açıkta", roundi(float(cv[0]) * 100.0), roundi(float(back[0]) * 100.0)])
		elif v.in_cover:
			lines.append("Siperde")
	if held and not v.militia:
		lines.append("EMİRDE · " + ("silahlı" if v.armed else ("baltalı" if v.has_meta("axe") else "silahsız")))
	if v.carry_n > 0:
		lines.append("Taşıdığı: %d %s" % [v.carry_n, str(BuildingDefs.RES_NAMES.get(v.carry_res, v.carry_res)).to_lower()])
	if many.size() > 1:
		var names: Array[String] = []
		for x in many:
			names.append((x as Villager).display_name)
		lines.append("Seçili: " + ", ".join(names))
	_card_lines.text = "\n".join(lines).replace(" · ", ", ")
	_card_kind.text = "NÜFUS KÂĞIDI" if many.size() <= 1 else "BİRLİK"
	_card.tooltip_text = "Emirde: sağ tık imleçte yazanı yapar (saldır, ara, saklan, siper al, git). R: bırak." if held else "Bir işyerine, tarlaya ya da silahlığa sağ tıkla: oraya ata. R: emre al. Ctrl+1–9: gruba al."
