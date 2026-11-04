class_name Trade
extends RefCounted
## The line's business, the town's living: what the goods fetch this week (each train's market, up
## and down, wood and coal dearer in the cold), contracts wired by the two sides (so much of this and
## that on the train by such a day, for money and goodwill, the other side not pleased), and goods
## sent for by wire, paid for and put off the next train.

const BUY := {"demir": 8, "komur": 6, "tas": 3, "kerpic": 5, "yiyecek": 3} ## mirka a piece, before the market
const LOT := 10 ## how many a click sends for
const WANTS := {"merkez": ["odun", "tas", "kerpic", "demir"], "isyan": ["yiyecek", "odun", "komur", "demir"]}
const MAX_OPEN := 2 ## contracts offered at once
const OFFER_DAYS := 3 ## days an offer stands before it goes elsewhere
const FAIL_REP := 10 ## goodwill lost on a contract missed
const RIVAL_REP := 3 ## what the other side thinks of it

var v: Node ## the Village
var market := {} ## good -> this week's multiple of its price
var offers: Array = [] ## {side, goods, left, due, pay, rep, ends}
var active: Array = [] ## the same, taken on
var order := {} ## good -> how many sent for
var next_offer := 3 ## the day the next contract's wired


func _init(village: Node) -> void:
	v = village
	new_market()


## The market as the next train finds it: each price wandered a little from where it stood.
func new_market() -> void:
	for r: String in Village.PRICES:
		market[r] = clampf(float(market.get(r, 1.0)) + randf_range(-0.28, 0.28), 0.6, 1.8)


func _season_mul(r: String) -> float:
	var winter: bool = v.seasons != null and v.seasons.winter()
	return 1.4 if winter and r in ["odun", "komur"] else (1.25 if winter and r == "yiyecek" else 1.0)


## What the train pays for one, as things stand.
func price(r: String) -> int:
	return maxi(1, roundi(float(Village.PRICES[r]) * float(market.get(r, 1.0)) * _season_mul(r)))


## What one costs to send for.
func buy_price(r: String) -> int:
	return maxi(1, roundi(float(BUY[r]) * float(market.get(r, 1.0)) * _season_mul(r)))


## Up, down or level against its usual price: for the form.
func trend(r: String) -> String:
	var m := float(market.get(r, 1.0)) * _season_mul(r)
	return "▲" if m > 1.15 else ("▼" if m < 0.85 else "")


## The goods to go on the train: marked for sale, and what the contracts taken on still want.
func to_load() -> Array[String]:
	var out: Array[String] = []
	for r: String in v.selling:
		out.append(r)
	for c: Dictionary in active:
		for r: String in c.left:
			if int(c.left[r]) > 0 and not r in out:
				out.append(r)
	return out


## Each morning: contracts gone by, offers gone elsewhere, a new one wired now and then.
func morning() -> void:
	var day: int = v.day
	for c: Dictionary in active.duplicate():
		if day > int(c.due):
			active.erase(c)
			v._shift(c.side, -FAIL_REP)
			v.message.emit("%s sözleşmesi zamanında dolmadı: itibar düştü (-%d)." % [Village.SIDES[c.side], FAIL_REP], "bad")
	for c: Dictionary in offers.duplicate():
		if day > int(c.ends):
			offers.erase(c)
	if day >= next_offer and offers.size() < MAX_OPEN and v.depot() != null and not v.line_shut():
		next_offer = day + 3 + randi() % 3
		var c := _new_contract()
		offers.append(c)
		v.message.emit("Telgraf: %s %s istiyor (%d %s). İstasyondaki telgraftan kabul et." % [Village.SIDES[c.side], goods_text(c.goods), int(c.pay), Village.COIN], "info")


func _new_contract() -> Dictionary:
	var day: int = v.day
	var side: String = "merkez" if randf() < 0.5 else "isyan"
	var pool: Array = (WANTS[side] as Array).duplicate()
	pool.shuffle()
	var goods := {}
	var worth := 0
	for k in 1 + randi() % 2:
		var r: String = pool[k]
		# (the dearer the good, the fewer asked for; more as the town grows)
		var n: int = snappedi(int((16.0 + day * 2.0) * randf_range(0.8, 1.3) / sqrt(float(Village.PRICES[r]))), 5)
		goods[r] = maxi(n, 5)
		worth += goods[r] * price(r)
	var friendly: bool = v.standing(side) >= Village.FRIENDLY
	var pay := roundi(worth * (1.9 if friendly else 1.6))
	return {"side": side, "goods": goods, "left": goods.duplicate(), "due": day + 9 + randi() % 5, "pay": pay, "rep": 6 + goods.size() * 3, "ends": day + OFFER_DAYS}


static func goods_text(goods: Dictionary) -> String:
	var parts: Array[String] = []
	for r: String in goods:
		parts.append("%d %s" % [int(goods[r]), str(BuildingDefs.RES_NAMES[r]).to_lower()])
	return ", ".join(parts)


func accept(c: Dictionary) -> void:
	offers.erase(c)
	active.append(c)
	v.message.emit("Sözleşme kabul edildi: %d. güne kadar %s trene yüklenecek." % [int(c.due), goods_text(c.goods)], "good")


func refuse(c: Dictionary) -> void:
	offers.erase(c)


## What's owed the contracts put on the train from the platform, before anything's sold; those filled
## are paid. Returns the room left.
func load_train(on: Array[Building], room: int) -> int:
	var spare: Dictionary = v.stock
	for c: Dictionary in active.duplicate():
		var put: Array[String] = []
		for r: String in c.left:
			var n: int = v.take_platform(r, mini(room, int(c.left[r])), on, spare)
			if n > 0:
				c.left[r] = int(c.left[r]) - n
				room -= n
				put.append("%d %s" % [n, str(BuildingDefs.RES_NAMES[r]).to_lower()])
		var left := 0
		for r: String in c.left:
			left += int(c.left[r])
		if left <= 0:
			active.erase(c)
			v.rubles += int(c.pay)
			v._shift(c.side, int(c.rep))
			var other: String = "isyan" if c.side == "merkez" else "merkez"
			v._shift(other, -RIVAL_REP)
			v.message.emit("%s sözleşmesi tamam: kasaya %d %s girdi, itibar +%d." % [Village.SIDES[c.side], int(c.pay), Village.COIN, int(c.rep)], "good")
		elif not put.is_empty():
			v.message.emit("Sözleşme için trene yüklendi: %s. Kalan: %s." % [", ".join(put), goods_text(c.left)], "info")
	return room


## `r` sent for by wire (LOT more), or taken off the list.
func send_for(r: String) -> void:
	order[r] = int(order.get(r, 0)) + LOT


func clear_order() -> void:
	order.clear()


## What's sent for comes down with the train, as far as the purse reaches; the market moves on.
func arrive(st: Node3D) -> void:
	var got: Array[String] = []
	var short := false
	for r: String in order:
		var n := int(order[r])
		var each := buy_price(r)
		var can: int = mini(n, int(v.rubles) / each)
		if can < n:
			short = true
		if can <= 0:
			continue
		v.rubles -= can * each
		v.add_anywhere(r, can, st.global_position)
		got.append("%d %s" % [can, str(BuildingDefs.RES_NAMES[r]).to_lower()])
	order.clear()
	if not got.is_empty():
		v.message.emit("Trenle sipariş geldi: %s%s." % [", ".join(got), " (kasa yetmedi, kalanı gelmedi)" if short else ""], "good")
	elif short:
		v.message.emit("Sipariş gelmedi: kasada para yok.", "bad")
	new_market()


func save() -> Dictionary:
	return {"market": market, "offers": offers, "active": active, "order": order, "next_offer": next_offer}


func restore(d: Dictionary) -> void:
	market = d.get("market", market)
	offers = d.get("offers", [])
	active = d.get("active", [])
	order = d.get("order", {})
	next_offer = int(d.get("next_offer", next_offer))
