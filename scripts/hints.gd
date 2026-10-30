class_name Hints
extends CanvasLayer
## The first time you're at something (driving, building, the valley's work), a card saying how it's
## done: the keys that matter there, once each (kept in the settings: "hints_seen"). It goes after
## a while, or at once with H; Esc's pause menu has none of it.

const CARDS := {
	"drive": ["SÜRÜŞ", [["W  S", "ileri · geri"], ["A  D", "direksiyon · Space fren"], ["Fare · sol tık", "nişan al · ateş et"],
		["Sağ tık", "uzağa nişan (görüş daralır)"], ["1-9 · 0", "silahları aç / kapat · hepsi"], ["F", "çevirici (varsa): üstündekini ters çevirir"], ["E", "menteşe, döner tabla, piston (tuşu yoksa)"],
		["B", "inşa ekranı"], ["C", "kamera"]]],
	"build": ["İNŞA", [["Sol tık · sağ tık", "parça tak · sök"], ["1-0, Q E Z X C F H", "parça seç (üstteki sekmeler de)"],
		["R · T · M", "çevir · devir (yan, ters) · ayna"], ["K", "fare üstteki silaha / çeviriciye tuş ver"], ["V", "izometrik görünüm"], ["Ctrl Z / Y", "geri al / ileri al"], ["Sol panel", "hazır tasarımlar ve kayıtlar"],
		["B", "sür"]]],
	"valley_wood": ["ODUN", [["R · testere", "çalıştır, ağaca sür: gövdeyi keser, ağaç devrilir, kütüklere ayrılır"],
		["Toplama kasası", "yanından geçtiğin kütükleri içine alır (en çok 8)"], ["Atölye", "kasayı yanına getir: odun depoya iner"],
		["Ahşap parçalar", "inşada AHŞAP: odunla yapılır; ağır, çabuk kırılır, alev alır"],
		["Silahlar", "arbalet, mancınık, kaynar yağ: odundan; yanına katran fıçısı: yanan ok ve çömlek"],
		["Planlar", "metal parça planla yapılır: harabelerin zulasında, devlerde, uzun seferlerde ışıklı tüp"],
		["Direksiyon mafsalı", "üstündekini A/D ile çevirir; tuş verirsen (K) o tuşla"]]],
	"valley_lift": ["VADİ", [["J", "telsiz: sefer al (bir yükü bir yerden ötekine taşı)"], ["Y · vinç", "kancayı yükün üstüne getir, Y: kaldırır; kasana çevir, Y: bırakır"], ["N · çeki vinci", "arkadaki yükü ya da saplanmış aracı bağlar, sarıp çeker"],
		["Teslim", "yükü gideceği yerin halkasına indir, bırak"],
		["V", "atölye kamyonuna bin / in: inşa ve onarım sadece onun yanında"], ["Işıklı parçalar", "enkazdan çıkan parçalar yıpranmıştır: yüzdesi yazar"],
		["Hurda", "atölyede onarımın bedeli: seferlerden, enkazdan"], ["Yağmur", "çamur derinleşir, geçitler taşar; yollar heyelanla kapanır"],
		["Dev makineler", "vurarak değil, sökerek devrilir: silahını, paletini kopar"]]],
}
const SHOW_FOR := 14.0 ## s a card stays

var game: Node
var _card: PanelContainer
var _t := 0.0
var _seen := PackedStringArray()


func _ready() -> void:
	layer = 6
	_seen = str(Settings.get_value("hints_seen")).split(",", false)


func _process(dt: float) -> void:
	if get_tree().current_scene == null:
		return # (a test or a picture-taking run builds the game by hand: those aren't you seeing it)
	if _card:
		_t -= dt
		if _t < 0.6:
			_card.modulate.a = clampf(_t / 0.6, 0.0, 1.0)
		if _t <= 0.0:
			_close()
		return
	var b := game.get("builder") as Builder
	if b and b.active:
		_show("build")
	elif game.get("player_input") and is_instance_valid(game.get("machine")):
		_show("drive")
		if Mode.current == "valley" and _card == null:
			_show("valley_wood" if not "valley_wood" in _seen else "valley_lift")


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if _card and k and k.pressed and not k.echo and k.keycode == KEY_H:
		_t = minf(_t, 0.6)


## The card for `key`, unless it's been shown before.
func _show(key: String) -> void:
	if key in _seen:
		return
	_seen.append(key)
	Settings.set_value("hints_seen", ",".join(_seen))
	var c: Array = CARDS[key]
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", Ui.glass(true, 16.0))
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	_card.add_child(col)
	Ui.label(col, "İLK KEZ  ·  %s" % c[0], 15, Ui.ACCENT, "head")
	Ui.rule(col, 40.0)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 3)
	col.add_child(grid)
	for row: Array in c[1]:
		Ui.label(grid, str(row[0]), 15, Ui.INK, "head")
		Ui.label(grid, str(row[1]), 15, Ui.DIM)
	Ui.label(col, "H  kapat", 12, Ui.DIM, "label")
	# driving: top middle (the HUD's along the bottom); building: bottom middle (the parts' tray is up top)
	if key == "drive":
		_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_card.offset_top = 120.0
	else:
		_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_card.offset_bottom = -36.0
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.modulate.a = 0.0
	_card.create_tween().tween_property(_card, "modulate:a", 1.0, 0.3)
	_t = SHOW_FOR


func _close() -> void:
	if _card:
		_card.queue_free()
	_card = null


## Shows every card again (from the settings' "hints_seen" cleared).
static func reset() -> void:
	Settings.set_value("hints_seen", "")
