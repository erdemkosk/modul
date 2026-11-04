class_name AlertBoard
extends VBoxContainer
## What's going wrong, down the right of the view: a strip a trouble, worst first, in the town's own
## words; a click goes to it. And for a new town, FIRST STEPS at the left: what to do next, ticked
## off as it's done, put away for good once it's finished or closed.

var game: Node
var _rows: Array[Button] = []
var _t := 0.0
var _at: Array = [] ## where each strip's click goes (INF: nowhere)

const STEPS := [
	["Yükü indir", "Trenle gelenler yükü istasyona taşısın"],
	["Ev kur", "KASABA > KÜTÜK EV: kış gelmeden herkese yatak"],
	["Odun kes", "ÜRETİM > ATÖLYE: odun için kur, işçi ata"],
	["Yiyecek bul", "ÜRETİM > TARLA ya da toplayıcı atölyesi"],
	["Köyü bildir", "İstasyona tıkla > TELGRAF > KÖYÜ BİLDİR: göçmenler gelsin"],
	["Sözleşme al", "TELGRAF: bir tarafın sözleşmesini kabul et, mallarını trene yükle"],
	["Korun", "SAVUNMA > GÖZCÜ KULESİ ya da SİLAHLIK: baskın gelmeden"],
]
var _guide: PanelContainer
var _guide_lines: Label
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
	_guide.add_theme_stylebox_override("panel", Ui.paper(4.0))
	_guide.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_guide.offset_left = 12
	_guide.offset_top = 126
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
	_guide_lines = Ui.label(col, "", 14, Color(0.95, 0.9, 0.8), "text")
	_guide_lines.add_theme_constant_override("outline_size", 0)
	_closed = Settings.guide_off
	_guide.visible = not _closed


func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0 or game == null or game.village == null or game.get("_loading"):
		return
	_t = 1.0
	_refresh()
	_refresh_guide()


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
	return [not v.arriving, has.call(["ev"]), work, has.call(["tarla", "toplayici"]), v.announced,
		not v.trade.active.is_empty() or v.rubles > 80, has.call(["kule", "silahlik"])]


func _refresh_guide() -> void:
	if _closed:
		return
	var done := _steps_done()
	var n := 0
	var text: Array[String] = []
	var next := true
	for i in STEPS.size():
		if done[i]:
			n += 1
			text.append("✓  " + str(STEPS[i][0]))
		elif next:
			next = false
			text.append("▸  %s\n     %s" % [STEPS[i][0], STEPS[i][1]])
		else:
			text.append("·  " + str(STEPS[i][0]))
	_guide_head.text = "İLK ADIMLAR  %d / %d" % [n, STEPS.size()]
	_guide_lines.text = "\n".join(text)
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
	if not v.trade.offers.is_empty():
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
