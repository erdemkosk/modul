class_name TelegraphPanel
extends HBoxContainer
## The telegraph office (the station card's TELGRAF): on the left the key, a brass lever on a
## wooden base that's keyed as a message goes out (each stroke a click of the sounder), and the
## paper tape running under it, the dots and dashes printed on it and the words read off beneath
## them; the line's answer comes back the same way in red ink. On the right what's wired: the town's
## founding announced to the mainland (the settlers come by train since), the train called, goods
## marked to be sold; the purse and the repute.

const DOT := 0.07 ## s a dot's held down (a dash three times as long)
const MORSE := {"A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.", "G": "--.", "H": "....",
	"I": "..", "J": ".---", "K": "-.-", "L": ".-..", "M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-",
	"R": ".-.", "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-", "Y": "-.--", "Z": "--..",
	"0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-", "5": ".....", "6": "-....", "7": "--...",
	"8": "---..", "9": "----."}
const PLAIN := {"Ç": "C", "Ş": "S", "Ğ": "G", "Ü": "U", "Ö": "O", "İ": "I", "I": "I"}

var game: Node
var _key: KeyArt
var _tape: Tape
var _queue: Array = [] ## [text, ink] still to be keyed
var _sending := false
var _click_down: AudioStreamWAV
var _click_up: AudioStreamWAV
var _sounder: AudioStreamPlayer
var _status: Label
var _train_btn: Button
var _announce: Button
var _sell_btns := {}


func _ready() -> void:
	add_theme_constant_override("separation", 18)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sounder = AudioStreamPlayer.new()
	_sounder.volume_db = -6.0
	add_child(_sounder)
	_click_down = _click(0.012, 1900.0, 0.9)
	_click_up = _click(0.008, 1300.0, 0.5)
	# the key and the tape
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	_key = KeyArt.new()
	_key.custom_minimum_size = Vector2(360, 170)
	left.add_child(_key)
	_tape = Tape.new()
	_tape.custom_minimum_size = Vector2(360, 120)
	left.add_child(_tape)
	# what's sent
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size = Vector2(380, 0)
	add_child(right)
	Ui.label(right, "TREN", 13, Ui.ACCENT, "head")
	_status = Ui.label(right, "", 13, Ui.INK)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(380, 0)
	_train_btn = _button(right, "TREN ÇAĞIR · %d ruble" % Village.CALL_PRICE, func() -> void:
		var why: String = game.village.call_train()
		if why != "":
			game.hud.toast(why, "bad")
			return
		send("TREN ISTIYORUZ STOP ACELE STOP", "ALINDI STOP TREN YARIN GELIR STOP"))
	_train_btn.tooltip_text = "Hatta telgraf çekilir: tren yarın gelir, gecikmez"
	Ui.label(right, "ANA KARA", 13, Ui.ACCENT, "head")
	_announce = _button(right, "KÖYÜ BİLDİR: kurulduğumuzu ana karaya haber ver", func() -> void:
		var why: String = game.village.announce()
		if why != "":
			game.hud.toast(why, "bad")
			return
		send("YENI KOY KURULDU STOP %d CAN STOP GOCMEN BEKLIYORUZ STOP" % game.village.villagers.size(), "TEBRIKLER STOP GOCMENLER TRENLE YOLA CIKIYOR STOP")
		refresh())
	_announce.tooltip_text = "Bir kez: bundan böyle göçmenler yürüyerek değil, her trenle gelir (boş yatak kadar)"
	Ui.label(right, "TRENE SAT  (her maldan %d'u kalır)" % Village.KEEP, 13, Ui.ACCENT, "head")
	var sell := HBoxContainer.new()
	sell.add_theme_constant_override("separation", 4)
	right.add_child(sell)
	for r: String in Village.PRICES:
		_sell_btns[r] = _button(sell, "%s %d" % [Ui.upper(BuildingDefs.RES_NAMES[r]), int(Village.PRICES[r])], func() -> void:
			var v: Village = game.village
			if r in v.selling:
				v.selling.erase(r)
			else:
				v.selling.append(r)
				send("SATILIK %s STOP" % _plain(BuildingDefs.RES_NAMES[r]), "")
			refresh())
		_sell_btns[r].tooltip_text = "%s: tane başı %d ruble. İşaretliyse tren gelince fazlası satılır." % [BuildingDefs.RES_NAMES[r], int(Village.PRICES[r])]


func _button(parent: Node, text: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", Ui.font("head"))
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(f)
	parent.add_child(b)
	return b


## The words as the line spells them: upper case, no Turkish letters.
static func _plain(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		out += str(PLAIN.get(ch, ch))
	return out


## `text` keyed out on the line, and (if any) the line's `answer` coming back after it.
func send(text: String, answer: String) -> void:
	_queue.append([text, false])
	if answer != "":
		_queue.append([answer, true])
	if not _sending:
		_key_out()


func _key_out() -> void:
	_sending = true
	while not _queue.is_empty():
		var item: Array = _queue.pop_front()
		var text := _plain(str(item[0]))
		var red: bool = item[1]
		if red:
			await get_tree().create_timer(0.8, true, false, true).timeout # (a pause, and the line answers)
		_tape.new_line(red)
		for ch in text:
			if not is_inside_tree():
				return
			if ch == " ":
				_tape.add_gap(3)
				await get_tree().create_timer(DOT * 5.0, true, false, true).timeout
				continue
			var code: String = MORSE.get(ch, "")
			for sym in code:
				var hold := DOT * (3.0 if sym == "-" else 1.0)
				_key.down = true
				_play(_click_down)
				_tape.add_mark(sym == "-")
				await get_tree().create_timer(hold, true, false, true).timeout
				_key.down = false
				_play(_click_up)
				await get_tree().create_timer(DOT, true, false, true).timeout
			_tape.add_letter(ch)
			_tape.add_gap(1)
			await get_tree().create_timer(DOT * 2.0, true, false, true).timeout
	_sending = false


func _play(s: AudioStreamWAV) -> void:
	_sounder.stream = s
	_sounder.play()


## A sounder's click: a short knock with a ringing edge (`secs` long, about `hz`).
static func _click(secs: float, hz: float, loud: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * (secs + 0.03))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var s := (sin(TAU * hz * t) * 0.6 + sin(TAU * hz * 2.7 * t) * 0.25 + (randf() - 0.5) * 0.4) * exp(-t / secs * 2.5) * loud
		data.encode_s16(i * 2, clampi(int(s * 26000.0), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


## The train's state and the buttons as they stand.
func refresh() -> void:
	var v: Village = game.village
	var due := v.next_train - v.day
	var line := "Tren istasyonda" if is_instance_valid(v.train) else ("Tren bugün bekleniyor" if due <= 0 else "Sonraki tren ~%d gün sonra (gecikebilir)" % due)
	if v.express:
		line = "Tren çağrıldı: yarın gelir"
	_status.text = "%s\nKasa %d ruble · İtibar %d%s" % [line, v.rubles, v.repute,
		(" · her trenle %d göçmen (boş yatak kadar)" % v.settlers_due()) if v.announced else " · köy henüz bildirilmedi: göçmen gelmiyor"]
	_train_btn.disabled = is_instance_valid(v.train) or v.express or due <= 1
	_announce.disabled = v.announced
	_announce.text = "KÖY BİLDİRİLDİ: göçmenler trenle geliyor" if v.announced else "KÖYÜ BİLDİR: kurulduğumuzu ana karaya haber ver"
	for r: String in _sell_btns:
		var on := r in v.selling
		(_sell_btns[r] as Button).add_theme_stylebox_override("normal", Ui.glass(false, 5.0, Color(1.0, 0.56, 0.14, 0.4) if on else Color(1, 1, 1, 0.06), Ui.ACCENT if on else Ui.EDGE))


## The key: a wooden base, the brass lever on its pivot, its knob, the contact under it; down while a
## stroke's held.
class KeyArt extends Control:
	var down := false:
		set(on):
			down = on
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var base_y := h * 0.72
		# the bench and the wooden base
		draw_rect(Rect2(0, base_y + 22, w, h - base_y - 22), Color(0.16, 0.11, 0.08))
		draw_rect(Rect2(w * 0.12, base_y, w * 0.76, 24), Color(0.36, 0.22, 0.12))
		draw_rect(Rect2(w * 0.12, base_y, w * 0.76, 4), Color(0.48, 0.31, 0.18))
		# the wires off the back
		draw_polyline(PackedVector2Array([Vector2(w * 0.14, base_y + 6), Vector2(w * 0.04, base_y - 30), Vector2(0, base_y - 70)]), Color(0.55, 0.32, 0.18), 2.0, true)
		draw_polyline(PackedVector2Array([Vector2(w * 0.16, base_y + 10), Vector2(w * 0.07, base_y - 20), Vector2(w * 0.03, base_y - 75)]), Color(0.3, 0.3, 0.32), 2.0, true)
		var brass := Color(0.78, 0.6, 0.28)
		var brass_dark := Color(0.5, 0.37, 0.16)
		# the pivot post and the contact
		var pivot := Vector2(w * 0.3, base_y - 22)
		draw_rect(Rect2(pivot.x - 9, pivot.y, 18, 22), brass_dark)
		draw_circle(pivot, 9.0, brass)
		var contact := Vector2(w * 0.66, base_y - 6)
		draw_rect(Rect2(contact.x - 6, contact.y, 12, 6), brass_dark)
		# the lever, tipped down a little while it's pressed
		var ang := 0.09 if down else -0.02
		var tip := pivot + Vector2(cos(ang), sin(ang)) * (w * 0.5)
		draw_line(pivot, tip, brass, 7.0, true)
		draw_line(pivot + Vector2(0, -2), tip + Vector2(0, -2), Color(0.95, 0.82, 0.5), 2.0, true)
		# the spring behind and the knob at the end
		draw_line(pivot + Vector2(-24, 0), pivot + Vector2(-24, 18), brass_dark, 3.0)
		draw_circle(tip, 16.0, Color(0.12, 0.08, 0.06))
		draw_circle(tip + Vector2(-4, -5), 6.0, Color(0.3, 0.22, 0.16))
		# a spark at the contact while it's closed
		if down:
			draw_circle(contact + Vector2(0, -3), 3.5, Color(1.0, 0.9, 0.55))


## The paper tape: lines of dots and dashes, the words read off beneath them, the newest at the
## right, scrolling left as it runs; the line's answers in red.
class Tape extends Control:
	var _lines: Array = [] ## {red, marks: [[x, dash]], letters: [[x, ch]], x}
	const STEP := 7.0

	func new_line(red: bool) -> void:
		_lines.append({"red": red, "marks": [], "letters": [], "x": 0.0})
		if _lines.size() > 2:
			_lines.pop_front()
		queue_redraw()

	func add_mark(dash: bool) -> void:
		var l: Dictionary = _lines[-1]
		(l.marks as Array).append([l.x, dash])
		l.x = float(l.x) + (STEP * 2.5 if dash else STEP * 1.4)
		queue_redraw()

	func add_gap(units: int) -> void:
		var l: Dictionary = _lines[-1]
		l.x = float(l.x) + STEP * units
		queue_redraw()

	func add_letter(ch: String) -> void:
		var l: Dictionary = _lines[-1]
		(l.letters as Array).append([l.x, ch])
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.12, 0.09, 0.07))
		var strip := Rect2(0, 10, w, h - 20)
		draw_rect(strip, Color(0.86, 0.8, 0.66))
		for k in 6: # (the paper's grain)
			draw_line(Vector2(0, strip.position.y + 8 + k * 16), Vector2(w, strip.position.y + 8 + k * 16), Color(0.78, 0.72, 0.58), 1.0)
		var f := Ui.font("head")
		for i in _lines.size():
			var l: Dictionary = _lines[i]
			var y := strip.position.y + 22 + i * 46
			var ink := Color(0.62, 0.12, 0.08) if l.red else Color(0.12, 0.1, 0.09)
			var shift := minf(0.0, w - 24.0 - float(l.x)) # (the newest at the right, the rest run off to the left)
			for m: Array in l.marks:
				var x := 12.0 + float(m[0]) + shift
				if x < -20.0:
					continue
				if m[1]:
					draw_line(Vector2(x, y), Vector2(x + STEP * 1.8, y), ink, 3.0)
				else:
					draw_circle(Vector2(x + 2, y), 2.2, ink)
			for t: Array in l.letters:
				var x := 12.0 + float(t[0]) + shift - STEP * 2.0
				if x < -10.0:
					continue
				draw_string(f, Vector2(x, y + 20), str(t[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
