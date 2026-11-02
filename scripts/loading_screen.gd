class_name LoadingScreen
extends CanvasLayer
## Over everything while a valley's being made (Main._ready builds it a step at a time, `step` after
## each): the title picture darkened, the name, what's being made just now, a bar of how far it's
## got, and a tip about the game, a new one every step and every few seconds. When it's done it
## fades away.

const TIPS := [
	"Kışa hazırlık: kış saati yiyecek ve yakacağın kaç gün yeteceğini gösterir. Kırmızıysa acele et.",
	"Bir evi çamurla sıvamak yakacağı %30, kerpiç soba %40 azaltır.",
	"Çamur ocağı yalnızca ıslak zemine, kıyıya kurulur. Kartından KERPİÇ YAP ile kerpiç döktürebilirsin.",
	"EMİRLER > KES ile ormandan bir alan sürükle: işaretli ağaçları oduncular ya da boştakiler keser.",
	"Bir işyerine ALAN ÇİZ ile işçilerinin çalışacağı yeri sen belirlersin.",
	"Hevesli (♥) olduğu işte bir köylü iki kat hızlı öğrenir.",
	"Bir işyerinin kartında ATA'ya bas: en yatkın köylüler yüzleriyle sıralanır.",
	"Sibiryalı köylüler soğuk evde üşümez; korkaklar milis olmaz.",
	"Yaralı biri yerde kalırsa kan kaybeder: onu bir eve taşıyan olmazsa ölür.",
	"Evin bahçesi, içinde oturanların işine göre her sabah biraz daha dolar.",
	"Boş yatak ve depoda yiyecek varsa kasabaya zamanla yeni insanlar gelir.",
	"Fenerler geceyi aydınlatır; haydutlar en karanlık yerden yaklaşır.",
	"Çan kulesi baskında herkesi saklanmaya çağırır.",
	"Tahta yollar çamura batmaz ve taşımayı hızlandırır.",
	"Kartından ODA EKLE ile bir eve iki yatak daha eklenir.",
	"K: kasabalıların becerileri ve hangi işe öncelikle verileceği.",
	"Sol alttaki portrelere tıkla: o köylü seçilir, iki kez tıklayınca kamera ona gider.",
]
const BG := "res://assets/ui/title_bg.jpg"

var _root: Control
var _what: Label
var _tip: Label
var _bar: ProgressBar
var _tip_t := 0.0
var _tip_i := 0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tip_i = randi() % TIPS.size()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP # (nothing under it takes a click while it's up)
	add_child(_root)
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Color(0.05, 0.045, 0.04)
	_root.add_child(back)
	if ResourceLoader.exists(BG):
		var pic := TextureRect.new()
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.texture = load(BG)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.modulate = Color(0.45, 0.42, 0.4)
		_root.add_child(pic)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	col.offset_bottom = -70
	col.custom_minimum_size = Vector2(760, 0)
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(col)
	var name := Ui.label(col, "İNŞA", 72, Ui.LIGHT, "display")
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_what = Ui.label(col, "", 18, Color(Ui.LIGHT, 0.8), "head")
	_what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(760, 10)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.09, 0.07, 0.9)
	bg.border_color = Color(0.55, 0.42, 0.28)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Ui.ACCENT
	fg.set_corner_radius_all(3)
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fg)
	col.add_child(_bar)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	col.add_child(gap)
	var tip_head := Ui.label(col, "İPUCU", 13, Ui.ACCENT, "head")
	tip_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip = Ui.label(col, "", 18, Ui.LIGHT)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(760, 52)
	_next_tip()


func _process(dt: float) -> void:
	_tip_t += dt
	if _tip_t > 5.0:
		_next_tip()


func _next_tip() -> void:
	_tip_t = 0.0
	_tip_i = (_tip_i + 1) % TIPS.size()
	_tip.text = TIPS[_tip_i]


## `what`'s being made, `share` of the way there: shown, and a couple of frames drawn so it's seen
## before the next step holds the game up again.
func step(what: String, share: float) -> void:
	_what.text = what
	_bar.value = share
	_next_tip()
	await get_tree().process_frame
	await get_tree().process_frame


## All made: the bar full, a moment, and it fades out and goes.
func finish() -> void:
	_what.text = "Hazır"
	_bar.value = 1.0
	await get_tree().process_frame
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)
