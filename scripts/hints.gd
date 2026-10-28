class_name Hints
extends CanvasLayer
## The first time you're at something (driving, building, the cage's start), a card saying how it's
## done: the keys that matter there, once each (kept in the settings: "hints_seen"). It goes after
## a while, or at once with H; Esc's pause menu has none of it.

const CARDS := {
	"drive": ["SÜRÜŞ", [["W  S", "ileri · geri"], ["A  D", "direksiyon · Space fren"], ["Fare · sol tık", "nişan al · ateş et"],
		["Sağ tık", "uzağa nişan (görüş daralır)"], ["1-9 · 0", "silahları aç / kapat · hepsi"], ["F", "çevirici (varsa): üstündekini ters çevirir"], ["E", "menteşe, döner tabla, piston (tuşu yoksa)"],
		["B", "inşa ekranı"], ["C", "kamera"]]],
	"build": ["İNŞA", [["Sol tık · sağ tık", "parça tak · sök"], ["1-0, Q E Z X C F H", "parça seç (üstteki sekmeler de)"],
		["R · T · M", "çevir · devir (yan, ters) · ayna"], ["K", "fare üstteki silaha / çeviriciye tuş ver"], ["V", "izometrik görünüm"], ["Ctrl Z / Y", "geri al / ileri al"], ["Sol panel", "hazır tasarımlar ve kayıtlar"],
		["B", "sür"]]],
	"mission": ["GÖREV", [["B", "önce aracını kur: görev başlayınca değişmez"], ["BAŞLA · Enter", "saat işlemeye başlar"],
		["Turuncu işaretler", "yıkılacak yapılar; hepsi yıkılınca biter"], ["Ahşap ve yakıt", "alevle, patlamayla tutuşur; ıslakta zor"],
		["Ayaklar, dipler", "taşıyanı kır: üstündeki devrilir"], ["R", "baştan başla"]]],
	"valley": ["VADİ", [["Elindekiyle kur", "inşa sadece envanterindeki parçalarla"], ["Işıklı parçalar", "parçalanan araçların sağlam parçaları: üstünden geç, alırsın"],
		["Avcılar", "vadide dolaşır; aracın büyüdükçe onlar da büyür"], ["Hazır tasarımlar", "parçaların yetiyorsa yüklenir"]]],
	"cage": ["KAFES", [["B", "önce aracını kur: turnuvada sadece atölyede değişir"], ["DÖVÜŞE BAŞLA · Enter", "ilk tura çık"],
		["Kazanmak", "rakibi parçala ya da 8 sn hareketsiz bırak"], ["Turlar arası", "atölyede hasarı kredinle onar"],
		["Ters dönmek", "8 sn'de sayılırsın; ancak çeviriciyle (F) doğrulursun"],
		["Dikkat", "çukur 0:45'te açılır; köşelerde ev robotları"]]],
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
	var cage := game.get("cage") as Cage
	var ms := game.get("missions") as Missions
	if b and b.active:
		_show("build")
	elif cage and cage.state == "prep" and cage.panel_up():
		_show("cage")
	elif ms and ms.state == "prep" and ms.panel_up():
		_show("mission")
	elif (cage == null or cage.state == "fight") and (ms == null or ms.state == "run") and game.get("player_input") \
			and is_instance_valid(game.get("machine")):
		_show("drive")
		if Mode.current == "valley" and _card == null:
			_show("valley")


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
	# driving: top middle, under the round's bar (the HUD's along the bottom); building and at the
	# cage's start: bottom middle (the parts' tray and the start panel are up top and in the middle)
	if key == "drive":
		_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_card.offset_top = 120.0 if game.get("missions") == null else 250.0 # (a mission's targets list is up there)
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
