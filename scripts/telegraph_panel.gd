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
var _sides: Label ## what moved the sides' goodwill lately
var _help_btns := {} ## side -> its YARDIM İSTE button
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
	# what's sent: the office's form, its boxes to tick
	var form := PanelContainer.new()
	form.add_theme_stylebox_override("panel", Ui.sheet("slip"))
	add_child(form)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 5)
	right.custom_minimum_size = Vector2(400, 0)
	form.add_child(right)
	var title := Ui.label(right, "GİDEN TELGRAF", 20, Ui.P_INK, "display")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Ui.double_rule(right)
	_heading(right, "Tren")
	_status = Ui.label(right, "", 14, Ui.P_INK, "type")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(400, 0)
	_train_btn = _button(right, "TREN ÇAĞIR, %d %s" % [Village.CALL_PRICE, Village.COIN], func() -> void:
		var why: String = game.village.call_train()
		if why != "":
			game.hud.toast(why, "bad")
			return
		send("TREN ISTIYORUZ STOP ACELE STOP", "ALINDI STOP TREN YARIN GELIR STOP"))
	_train_btn.tooltip_text = "Hatta telgraf çekilir: tren yarın gelir, gecikmez"
	_heading(right, "Yardım iste")
	var help := HBoxContainer.new()
	help.add_theme_constant_override("separation", 6)
	right.add_child(help)
	for side: String in Village.SIDES:
		var sd := side
		_help_btns[sd] = _button(help, "%s'E" % Ui.upper(str(Village.SIDES[sd])), func() -> void:
			var why: String = game.village.call_help(sd)
			if why != "":
				game.hud.toast(why, "bad")
				return
			send("ACIL YARDIM STOP KASABA TEHLIKEDE STOP ASKER GONDERIN STOP", "ALINDI STOP BIRLIK TOPLANIYOR STOP IKI SAATE YOLDA STOP")
			refresh())
	_heading(right, "Taraflar")
	_sides = Ui.label(right, "", 13, Ui.P_INK, "type")
	_sides.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sides.custom_minimum_size = Vector2(400, 0)
	_heading(right, "Ana kara")
	_announce = _button(right, "KÖYÜ BİLDİR", func() -> void:
		var why: String = game.village.announce()
		if why != "":
			game.hud.toast(why, "bad")
			return
		send("KORDAL HATTI UCUNDA YENI KOY KURULDU STOP %d CAN STOP GOCMEN BEKLIYORUZ STOP" % game.village.villagers.size(), "ZAROVYA MERKEZ STOP TEBRIKLER STOP GOCMENLER TRENLE YOLA CIKIYOR STOP")
		refresh())
	_heading(right, "Trene sat")
	var sell := HFlowContainer.new()
	sell.add_theme_constant_override("h_separation", 6)
	sell.add_theme_constant_override("v_separation", 4)
	sell.tooltip_text = "İşaretli mallar tren gelince satılır; her maldan %d kalır" % Village.KEEP
	right.add_child(sell)
	for r: String in Village.PRICES:
		_sell_btns[r] = _button(sell, "", func() -> void:
			var v: Village = game.village
			if r in v.selling:
				v.selling.erase(r)
			else:
				v.selling.append(r)
				send("SATILIK %s STOP" % _plain(BuildingDefs.RES_NAMES[r]), "")
			refresh())
		_sell_btns[r].tooltip_text = "%s: fiyat her trende değişir, kışın odun ve kömür pahalanır. İşaretliyse tren gelince fazlası satılır (her maldan %d kalır)." % [BuildingDefs.RES_NAMES[r], Village.KEEP]
	_heading(right, "Trenle getir")
	var buy := HFlowContainer.new()
	buy.add_theme_constant_override("h_separation", 6)
	buy.add_theme_constant_override("v_separation", 4)
	right.add_child(buy)
	for r: String in Trade.BUY:
		_buy_btns[r] = _button(buy, "", func() -> void:
			game.village.trade.send_for(r)
			send("%d %s GONDERIN STOP" % [Trade.LOT, _plain(BuildingDefs.RES_NAMES[r])], "")
			refresh())
		_buy_btns[r].tooltip_text = "Tıklayınca %d tane sipariş edilir, para tren gelince ödenir" % Trade.LOT
	_order_line = Ui.label(right, "", 13, Ui.P_INK, "type")
	# the contracts on a slip of their own, under the tape
	var deals_form := PanelContainer.new()
	deals_form.add_theme_stylebox_override("panel", Ui.sheet("slip"))
	deals_form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(deals_form)
	var deals_col := VBoxContainer.new()
	deals_col.add_theme_constant_override("separation", 4)
	deals_form.add_child(deals_col)
	_heading(deals_col, "Sözleşmeler")
	_deals = VBoxContainer.new()
	_deals.add_theme_constant_override("separation", 6)
	deals_col.add_child(_deals)


var _buy_btns := {}
var _order_line: Label
var _deals: VBoxContainer
var _deals_sig := ""


## The contracts on the form: those offered, to take or leave; those taken on, what's left to send.
func _fill_deals() -> void:
	var tr: Trade = game.village.trade
	var sig := str(tr.offers) + str(tr.active)
	if sig == _deals_sig:
		return
	_deals_sig = sig
	for c in _deals.get_children():
		c.queue_free()
	if tr.offers.is_empty() and tr.active.is_empty():
		Ui.label(_deals, "Şimdilik sipariş yok.", 13, Ui.P_DIM, "type")
	for c: Dictionary in tr.offers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_deals.add_child(row)
		var l := Ui.label(row, "%s: %s\n%d. güne · %d %s · itibar +%d" % [Village.SIDES[c.side], Trade.goods_text(c.goods), int(c.due), int(c.pay), Village.COIN, int(c.rep)], 13, Ui.P_INK, "type")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var deal := c
		_button(row, "KABUL", func() -> void:
			tr.accept(deal)
			send("SOZLESME KABUL STOP", "ALINDI STOP %d GUNE KADAR BEKLIYORUZ STOP" % maxi(int(deal.due) - game.village.day, 0))
			refresh())
		_button(row, "RET", func() -> void:
			tr.refuse(deal)
			refresh())
	for c: Dictionary in tr.active:
		Ui.label(_deals, "✓ %s: kalan %s (%d gün)" % [Village.SIDES[c.side], Trade.goods_text(c.left), maxi(int(c.due) - game.village.day, 0)], 13, Ui.P_BLUE, "type")


## A heading on the form, printed small, a dotted line run out after it.
func _heading(parent: Node, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0, 24)
	parent.add_child(row)
	var l := Ui.label(row, Ui.upper(text), 12, Ui.P_RED, "head")
	l.size_flags_vertical = Control.SIZE_SHRINK_END
	var dots := Ui.label(row, ". ".repeat(80), 10, Color(Ui.P_INK, 0.4), "type")
	dots.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dots.size_flags_vertical = Control.SIZE_SHRINK_END


func _button(parent: Node, text: String, f: Callable) -> Button:
	var b := Ui.ink_button(Button.new(), Ui.P_INK, 14, "type_bold")
	b.text = text
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
	var line := "Tren istasyonda." if is_instance_valid(v.train) else ("Tren bugün bekleniyor." if due <= 0 else "Sonraki tren ~%d gün sonra." % due)
	if v.express:
		line = "Tren çağrıldı: yarın gelir."
	if v.line_state() != "":
		line = v.line_state() + "\n" + line
	_status.text = "%s\nKasada %d mirka. %s" % [line, v.rubles,
		("Her trenle %d göçmen." % v.settlers_due()) if v.announced else "Köy bildirilmedi: göçmen gelmiyor."]
	_status.tooltip_text = "Trenler gecikebilir. Göçmen boş yatak kadar gelir."
	_status.mouse_filter = Control.MOUSE_FILTER_PASS
	_train_btn.disabled = is_instance_valid(v.train) or v.express or due <= 1 or v.line_shut()
	var rows: Array[String] = []
	for side: String in Village.SIDES:
		rows.append("%-14s %+d" % [str(Village.SIDES[side]).to_upper(), v.standing(side)])
	for e: Array in v.standing_log.slice(0, 5):
		rows.append("Gün %d  %s %+d%s" % [int(e[0]), Village.SIDES[e[1]], int(e[2]), (", " + str(e[3])) if str(e[3]) != "" else ""])
	_sides.text = "\n".join(rows)
	for side: String in _help_btns:
		var why: String = v.help_why_not(side)
		(_help_btns[side] as Button).disabled = why != ""
		(_help_btns[side] as Button).tooltip_text = ("Yardım gelmez: " + why + "\n\n" if why != "" else "") + "Asker gönderirler (yaklaşık %d saat sonra yola çıkarlar); kasabanın yanında çatışmaya girerler. Bedeli: o tarafın gözünde -%d itibar. Yalnızca +%d ve üstü dost taraf yollar." % [int(Village.HELP_HOURS), Village.HELP_COST, Village.FRIENDLY]
	_announce.disabled = v.announced
	_announce.text = "KÖY BİLDİRİLDİ" if v.announced else "KÖYÜ BİLDİR"
	_announce.tooltip_text = "Kurulduğumuzu Zarovya merkezine bildir. Bir kez: bundan böyle göçmenler yürüyerek değil, her trenle gelir (boş yatak kadar)."
	for r: String in _sell_btns:
		var on := r in v.selling
		(_sell_btns[r] as Button).add_theme_stylebox_override("normal", Ui.ink_box(Ui.P_INK, 0.0, 0.55, on))
		(_sell_btns[r] as Button).text = ("✓ " if on else "") + "%s %d%s" % [Ui.upper(BuildingDefs.RES_NAMES[r]), v.trade.price(r), v.trade.trend(r)]
	for r: String in _buy_btns:
		(_buy_btns[r] as Button).text = "%s %d%s" % [Ui.upper(BuildingDefs.RES_NAMES[r]), v.trade.buy_price(r), v.trade.trend(r)]
	var want: Array[String] = []
	var cost := 0
	for r: String in v.trade.order:
		want.append("%d %s" % [int(v.trade.order[r]), str(BuildingDefs.RES_NAMES[r]).to_lower()])
		cost += int(v.trade.order[r]) * v.trade.buy_price(r)
	_order_line.text = "Siparişte: %s (~%d %s)" % [", ".join(want), cost, Village.COIN] if not want.is_empty() else ""
	_fill_deals()


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
		var f := Ui.font("type_bold")
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
