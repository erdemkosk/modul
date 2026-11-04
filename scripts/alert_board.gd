class_name AlertBoard
extends VBoxContainer
## What's going wrong, down the right of the view: a strip a trouble, worst first, in the town's own
## words; a click goes to it. And for a new town, FIRST STEPS at the left: what to do next, ticked
## off as it's done, put away for good once it's finished or closed.

var game: Node
var _guide_col: VBoxContainer
var _guide_rows: Array = [] ## a step: [its box, its line, the box's frame]
var _train_lines: Label
var _train_card: PanelContainer
var _stack: PanelContainer
var _stack_name: Label
var _stack_line: Label
var _stop: PanelContainer
var _follow: Button
var _rows: Array[Button] = []
var _t := 0.0
var _at: Array = [] ## where each strip's click goes (INF: nowhere)

const STEPS := [
	["Treni durdur", "Yer beğenince TRENİ DURDUR: herkes orada iner,
     yük rayın yanına yığılır"],
	["Depo kur", "G: haritaya bak, yerini seç.
     KASABA > KAMP DEPOSU: yük oraya taşınır"],
	["Ev kur", "KASABA > KÜTÜK EV: kış gelmeden herkese yatak"],
	["Odun kes", "ÜRETİM > ATÖLYE: odun için kur, işçi ata"],
	["Yiyecek bul", "ÜRETİM > TARLA ya da toplayıcı atölyesi"],
	["Telgrafı araştır", "KASABA > OKUMA ODASI kur, işçi ata, T: Telgraf.
     Telgraf yoksa tren gelmez"],
	["İstasyon kur", "TAŞIMA > İSTASYON: rayın yanına. Tren orada durur"],
	["Köyü bildir", "İstasyon > TELGRAFHANE > KÖYÜ BİLDİR: göçmenler gelsin"],
	["Sözleşme al", "TELGRAFHANE: bir sözleşmeyi kabul et,
     mallarını trene yükle"],
	["Korun", "SAVUNMA > GÖZCÜ KULESİ ya da SİLAHLIK: baskın gelmeden"],
]
var _guide: PanelContainer
var _guide_head: Label
var _closed := false


func make(parent: Node) -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_top = 74
	offset_right = -12
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(self)
	_guide = PanelContainer.new()
	var slate := StyleBoxFlat.new() # (dark and plain: small writing has to read over anything)
	slate.bg_color = Color(0.085, 0.06, 0.045, 0.96)
	slate.border_color = Color(0.72, 0.55, 0.3, 0.8)
	slate.set_border_width_all(2)
	slate.set_corner_radius_all(3)
	slate.set_content_margin_all(12.0)
	_guide.add_theme_stylebox_override("panel", slate)
	_guide.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_guide.offset_left = 12
	_guide.offset_top = 118
	parent.add_child(_guide)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	_guide.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	_guide_head = Ui.label(top, "İLK ADIMLAR", 15, Color(1.0, 0.87, 0.6), "head")
	_guide_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var x := Button.new()
	x.text = "×"
	x.flat = true
	x.focus_mode = Control.FOCUS_NONE
	x.tooltip_text = "Rehberi kapat"
	x.add_theme_color_override("font_color", Ui.INK)
	x.pressed.connect(func() -> void:
		_closed = true
		_guide.visible = false
		Settings.guide_off = true
		Settings.save_settings())
	top.add_child(x)
	_guide_col = VBoxContainer.new()
	_guide_col.add_theme_constant_override("separation", 5)
	col.add_child(_guide_col)
	for s: Array in STEPS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		_guide_col.add_child(row)
		var box := Label.new()
		box.custom_minimum_size = Vector2(16, 16)
		box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		box.add_theme_font_size_override("font_size", 13)
		box.add_theme_color_override("font_color", Color(1.0, 0.87, 0.6))
		var line := StyleBoxFlat.new()
		line.bg_color = Color(0, 0, 0, 0.2)
		line.border_color = Color(0.8, 0.7, 0.5, 0.75)
		line.set_border_width_all(1)
		box.add_theme_stylebox_override("normal", line)
		row.add_child(box)
		var l := Ui.label(row, str(s[0]), 16, Color(0.98, 0.95, 0.88), "strong")
		l.add_theme_constant_override("outline_size", 0)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 0)
		_guide_rows.append([box, l, line])
	var strip := TextureRect.new()
	strip.texture = load("res://assets/ui/guide_strip.jpg")
	strip.custom_minimum_size = Vector2(0, 56)
	strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	strip.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	col.add_child(strip)
	_closed = Settings.guide_off
	_guide.visible = not _closed
	_make_stop(parent)
	_make_train(parent)
	_make_stack(parent)


## The brake, while the first train's rolling: where it's stopped is where the town begins.
func _make_stop(parent: Node) -> void:
	_stop = PanelContainer.new()
	_stop.add_theme_stylebox_override("panel", Ui.paper(4.0))
	_stop.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stop.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stop.offset_bottom = -256
	parent.add_child(_stop)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_stop.add_child(col)
	var note := Ui.label(col, "Yük ve insanlar trende. Yer beğenince durdur.", 15, Ui.INK, "text")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var brake := Ui.ink_button(Button.new(), Color(1.0, 0.62, 0.42), 19, "strong")
	brake.text = "  TRENİ DURDUR  "
	brake.pressed.connect(func() -> void:
		var why: String = game.village.stop_train()
		if why != "" and why != "x":
			game.hud.toast(why, "bad"))
	row.add_child(brake)
	_follow = Ui.ink_button(Button.new(), Ui.INK, 15, "strong")
	_follow.text = "TRENE DÖN"
	_follow.pressed.connect(func() -> void:
		game._cam_free = false)
	row.add_child(_follow)
	_stop.visible = false


## The train's card, bottom left: where it is, when the next is due, what's waiting on it.
func _make_train(parent: Node) -> void:
	var p := PanelContainer.new()
	_train_card = p
	p.visible = false
	p.add_theme_stylebox_override("panel", Ui.paper(6.0))
	p.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_left = 12
	p.offset_bottom = -92
	p.custom_minimum_size = Vector2(286, 0)
	parent.add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	p.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	Ui.label(top, "TREN", 17, Color(1.0, 0.87, 0.6), "head").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fold := Button.new()
	fold.text = "–"
	fold.flat = true
	fold.focus_mode = Control.FOCUS_NONE
	fold.tooltip_text = "Kartı katla"
	fold.add_theme_color_override("font_color", Ui.INK)
	top.add_child(fold)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	col.add_child(body)
	fold.pressed.connect(func() -> void: body.visible = not body.visible)
	var pic := TextureRect.new()
	pic.texture = load("res://assets/ui/train_card.jpg")
	pic.custom_minimum_size = Vector2(104, 84)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	body.add_child(pic)
	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 2)
	body.add_child(lines)
	_train_lines = Ui.label(lines, "", 14, Color(0.95, 0.9, 0.8), "text")
	var wire := Ui.ink_button(Button.new(), Ui.INK, 13, "strong")
	wire.text = "TELGRAF"
	wire.tooltip_text = "Tren çağır, mal sat, sözleşme al"
	wire.pressed.connect(func() -> void: game.hud.toggle_telegraph())
	lines.add_child(wire)


func _refresh_train() -> void:
	var v: Village = game.village
	_train_card.visible = v.knows("telgraf") # (nothing to say of the train till there's a wire)
	if not _train_card.visible:
		return
	var state := "Hat boş"
	if v.arriving:
		state = "Yolda" if v.can_stop_train() else "Yük iniyor"
	elif v.line_shut():
		state = "Hat karla kapalı"
	elif is_instance_valid(v.armoured):
		state = "Zırhlı tren hatta"
	elif is_instance_valid(v.train):
		state = "Peronda" if v.train.is_standing() else "Hatta"
	var next := "—"
	if v.knows("telgraf") and v.depot() != null:
		next = "Bugün" if v.next_train <= v.day else "%d gün" % (v.next_train - v.day)
	elif not v.arriving:
		next = "istasyon yok"
	_train_lines.text = "Durum: %s\nSonraki: %s\nSözleşme: %d" % [state, next, v.trade.active.size()]


## A stack in the open, clicked on: what it is and how much, and what the weather's doing to it.
func _make_stack(parent: Node) -> void:
	_stack = PanelContainer.new()
	_stack.add_theme_stylebox_override("panel", Ui.paper(6.0))
	_stack.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_stack.offset_bottom = -216
	_stack.visible = false
	parent.add_child(_stack)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.custom_minimum_size = Vector2(230, 0)
	_stack.add_child(col)
	_stack_name = Ui.label(col, "", 19, Color(1.0, 0.87, 0.6), "head")
	_stack_line = Ui.label(col, "", 15, Ui.INK, "strong")


func _refresh_stack() -> void:
	var b: Building = game.picked_heap
	if b == null or not is_instance_valid(b) or b.picked < 0 or b.picked >= b.stacks.size():
		_stack.visible = false
		return
	var e: Dictionary = b.stacks[b.picked]
	_stack.visible = true
	_stack_name.text = str(BuildingDefs.RES_NAMES[e.res])
	_stack_line.text = "%d / %d%s" % [int(e.n), int(e.of), "  ·  açıkta bozuluyor" if e.res in ["yiyecek", "odun"] else ""]


func _process(dt: float) -> void:
	_refresh_stack()
	_stop.visible = game.village.can_stop_train()
	_follow.visible = game._cam_free
	_t -= dt
	if _t > 0.0 or game == null or game.village == null or game.get("_loading"):
		return
	_t = 1.0
	_refresh()
	_refresh_guide()
	_refresh_train()


func _steps_done() -> Array[bool]:
	var v: Village = game.village
	var has := func(kinds: Array) -> bool:
		for b in v.buildings:
			if b.kind in kinds and b.state == "done":
				return true
		return false
	var work := false
	for b in v.buildings:
		if b.kind in BuildingDefs.WORKSHOP_KINDS and b.state == "done" and not b.workers.is_empty():
			work = true
	return [not v.arriving, has.call(["kamp", "ambar"]), has.call(["ev"]), work, has.call(["tarla", "toplayici"]), v.knows("telgraf"), v.depot() != null, v.announced,
		not v.trade.active.is_empty() or v.rubles > 80, has.call(["kule", "silahlik"])]


func _refresh_guide() -> void:
	if _closed:
		return
	var done := _steps_done()
	var n := 0
	var next := true
	for i in STEPS.size():
		var r: Array = _guide_rows[i]
		var box: Label = r[0]
		var l: Label = r[1]
		var mine := not done[i] and next
		if done[i]:
			n += 1
		elif next:
			next = false
		box.text = "✓" if done[i] else ""
		(r[2] as StyleBoxFlat).border_color = Color(1.0, 0.72, 0.3) if mine else Color(0.8, 0.7, 0.5, 0.75)
		l.text = "%s\n%s" % [STEPS[i][0], str(STEPS[i][1]).replace("\n     ", "\n")] if mine else str(STEPS[i][0])
		l.add_theme_color_override("font_color", Color(1.0, 0.84, 0.52) if mine else (Color(0.74, 0.7, 0.62) if done[i] else Color(0.98, 0.95, 0.88)))
	_guide_head.text = "İLK ADIMLAR  %d / %d" % [n, STEPS.size()]
	if n >= STEPS.size():
		_closed = true
		_guide.visible = false
		Settings.guide_off = true
		Settings.save_settings()


## The troubles as they stand: [text, tip, at, bad]
func _troubles() -> Array:
	var v: Village = game.village
	var out: Array = []
	var dial: SeasonDial = game.hud._dial
	var cold: bool = v.needs_fire() or game.seasons.season >= 2
	if int(v.stock.get("yiyecek", 0)) <= 0 and not v.villagers.is_empty() and not v.arriving:
		out.append(["YİYECEK BİTTİ", "Depoda hiç yiyecek yok: tarla, toplayıcı ya da trenden sipariş", Vector3.INF, true])
	elif dial._food_days < 3.0 and not v.arriving:
		out.append(["Yiyecek %d gün yeter" % ceili(dial._food_days), "Kasabanın yiyeceği azalıyor", Vector3.INF, true])
	if cold and dial._wood_days < 3.0 and not v.arriving:
		out.append(["Yakacak %d gün yeter" % ceili(dial._wood_days), "Evlerde soba sönerse kasabalılar donar: odun kes", Vector3.INF, true])
	var burning: Building = null
	var nb := 0
	for b in v.buildings:
		if b.state != "gone" and b.is_burning():
			nb += 1
			burning = b
	if burning:
		out.append(["%d bina yanıyor" % nb, "Su taşıyacak kişi gerek; kuyu yakında olsun", burning.global_position, true])
	var rd: Raids = game.raids
	if rd and rd.active:
		out.append(["BASKIN", "Kasaba saldırı altında", rd.origin(), true])
	var bleed: Villager = null
	var homeless := 0
	var hurt := 0
	for x: Villager in v.villagers:
		if x.dead:
			continue
		if x.bleeding or x.down:
			hurt += 1
			bleed = x
		if not x.is_child and not is_instance_valid(x.home):
			homeless += 1
	if bleed:
		out.append(["%d yaralı" % hurt, "Feldşer ya da sargı gerek", bleed.global_position, true])
	for s in v.stores():
		if s.def.get("open", false) and s.goods_total() > 0 and not v.arriving:
			out.append(["Yük açıkta bozuluyor", "KAMP DEPOSU kur: köylüler yığını oraya taşır", s.global_position, true])
	if homeless > 0 and not v.arriving:
		out.append(["%d kişi evsiz" % homeless, "Ev kur: dışarıda yatanlar üşür, morali düşer", Vector3.INF, false])
	var crowded: Building = null
	var idle: Building = null
	var nidle := 0
	var waiting := 0
	for b in v.buildings:
		if b.state == "done" and b.def.role == "house" and b.residents.size() >= b.beds() and b.level < 2 and b.beds() > 0:
			crowded = b
		if b.state == "done" and int(b.def.get("slots", 0)) > 0 and b.workers.is_empty() and b.def.role in ["work", "smith", "healer", "research", "farm"]:
			nidle += 1
			idle = b
		if b.state != "done" and b.state != "gone" and b.state != "ghost":
			waiting += 1
	if idle:
		out.append(["%d işyeri boş" % nidle, "Kartından işçi ata", idle.global_position, false])
	if crowded:
		out.append(["Ev dolu: oda ekle", "Karttaki ODA EKLE ile büyüt (malzeme varsa kendileri de ekler)", crowded.global_position, false])
	if v.knows("telgraf") and not v.trade.offers.is_empty():
		out.append(["%d yeni sözleşme" % v.trade.offers.size(), "İstasyonun telgrafından kabul et", v.station_at(), false])
	for c: Dictionary in v.trade.active:
		if int(c.due) - v.day <= 3:
			out.append(["Sözleşme %d gün kaldı" % maxi(int(c.due) - v.day, 0), "Kalan: " + Trade.goods_text(c.left), v.station_at(), true])
	var tr: Train = v.train
	if is_instance_valid(tr) and tr._bar_s < INF and absf(tr._v) < 0.05:
		out.append(["Tren surda duruyor", "Raya kapı koy ya da kilidi aç", tr.engine_at(), true])
	return out.slice(0, 8)


func _refresh() -> void:
	var list := _troubles()
	while _rows.size() < list.size():
		var i := _rows.size()
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.add_theme_font_override("font", Ui.face("strong", 14))
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func() -> void:
			if i < _at.size() and _at[i] != Vector3.INF:
				game.cam.jump_to(_at[i]))
		add_child(b)
		_rows.append(b)
	_at.clear()
	for i in _rows.size():
		var b := _rows[i]
		b.visible = i < list.size()
		if i >= list.size():
			continue
		var e: Array = list[i]
		_at.append(e[2])
		b.text = str(e[0])
		b.tooltip_text = str(e[1])
		var bad: bool = e[3]
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.4, 0.09, 0.05, 0.92) if bad else Color(0.2, 0.145, 0.105, 0.92)
		s.border_color = Color(0.95, 0.5, 0.35, 0.8) if bad else Color(Ui.ACCENT, 0.6)
		s.border_width_right = 3
		s.content_margin_left = 12
		s.content_margin_right = 10
		s.content_margin_top = 3
		s.content_margin_bottom = 3
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, s)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", Color(1.0, 0.92, 0.84) if bad else Ui.INK)
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
