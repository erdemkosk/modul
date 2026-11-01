class_name BuildingDefs
extends RefCounted
## What can be built: each kind's name, footprint (x wide, z deep, the door on +z), what it costs,
## how long it takes, what it's for, and the pieces it's put together from (`recipe`), bottom up:
## a stone plinth sunk into the ground (it takes up a slope), then posts, walls, beams, the roof.
## A piece is {shape, size, pos, rot (degrees), mat}: shape "box", "prism" (a gable: a triangle in x-y
## stood along z), "cyl" (upright, size.x across, size.y tall), "xcyl" (lying along x: size.x long,
## size.y across) or "cone" (a four-sided spire: size.x across the base, size.y tall).
##
## Where a model's been built for a kind (assets/buildings/<kind>.glb, tools/blender/build_buildings.py)
## its pieces are that model's objects instead: {shape "mesh", mesh, xf, mat, tag}, each object's
## name "<stuff>-<n>" or "<stuff>-<tag>-<n>".

const RES_NAMES := {"odun": "Odun", "tas": "Taş", "yiyecek": "Yiyecek"}

const KINDS := ["meydan", "cankulesi", "ev", "tarla", "oduncu", "ormanci", "tasci", "toplayici", "ambar", "arabaci", "ahir", "kuyu", "fener", "kule", "kisla"]

const DEFS := {
	"ev": {"name": "Kütük ev", "size": Vector2(6, 5), "cost": {"odun": 14}, "time": 28.0, "role": "house", "beds": 4,
		"desc": "Dört kişilik kütük ev, taş bacalı. Soğukta ve gece ocağında odun yakar. Boş yatak varsa kasabaya yeni insanlar gelir."},
	"meydan": {"name": "Meydan", "size": Vector2(10, 10), "cost": {"odun": 8, "tas": 12}, "time": 30.0, "role": "square",
		"desc": "Kasabanın ortası: taş döşeli, ortada ateş çukuru, çevresinde banklar. Akşamları ateş yakılır, kasabalılar başında toplanıp oturur, konuşur; çocuklar orada oynar."},
	"cankulesi": {"name": "Çan kulesi", "size": Vector2(4, 4), "cost": {"odun": 20, "tas": 8}, "time": 36.0, "role": "bell",
		"desc": "Çan sabah işbaşını, akşam paydosu çalar. Baskında tehlike çanı çalınca kasabanın her yerindeki herkes saklanır."},
	"yol": {"name": "Tahta yol", "size": Vector2(2, 2), "cost": {"odun": 1}, "time": 0.0, "role": "road",
		"desc": "Basılı tutup sürükleyerek döşenir: her 2 m'si bir odun. Üstünde hızlı yüründü, araba saplanmaz, yağmurda çamur olmaz."},
	"tarla": {"name": "Tarla", "size": Vector2(14, 10), "cost": {"odun": 10}, "time": 12.0, "role": "farm", "slots": 4,
		"desc": "Çitle çevrili çavdar tarlası. Çiftçiler eker, ekin büyür (yağmurda hızlı, karda hiç), olgunlaşınca biçip 60 yiyecek getirirler. Olgun ekin yanar."},
	"oduncu": {"name": "Kesim kampı", "size": Vector2(7, 6), "cost": {"odun": 8}, "time": 18.0, "role": "work", "slots": 3,
		"res": "odun", "reach": 80.0, "station": Vector3(0, 0, 0.55), "face": Vector3(0, 0, -0.3), "pile": Vector3(2.3, 0, 1.9), "work": "saw",
		"desc": "Kesimciler ağacı devirir, budar, tomruklara böler; tomrukları omuzlayıp kampa getirir, sehpada testereyle biçerler. Biçilen odun kampta yığılır, depoya taşınır."},
	"ormanci": {"name": "Ormancı", "size": Vector2(6, 5), "cost": {"odun": 8}, "time": 16.0, "role": "forest", "slots": 2, "reach": 90.0,
		"desc": "Kesilen ağaçların kütüklerine fidan diker; fidan birkaç dakikada ağaç olur. Ormanı geri getirmek, çıplak yamaçların yağmurda kaymasını önler."},
	"tasci": {"name": "Taş ocağı", "size": Vector2(7, 6), "cost": {"odun": 14}, "time": 24.0, "role": "work", "slots": 3,
		"res": "tas", "reach": 130.0, "station": Vector3(0, 0, 0.45), "face": Vector3(0, 0, -0.3), "pile": Vector3(2.3, 0, 1.9), "work": "chisel",
		"desc": "Taşçılar kayadan blok kırar, bloğu ocağa taşır, tezgâhta keski ve tokmakla yontar. Yontulan taş ocakta yığılır, depoya taşınır."},
	"toplayici": {"name": "Toplayıcı", "size": Vector2(6, 5), "cost": {"odun": 6}, "time": 16.0, "role": "work", "slots": 3,
		"res": "yiyecek", "reach": 85.0, "station": Vector3(0, 0, 1.35), "face": Vector3(0, 0, 0.8), "pile": Vector3(-1.9, 0, 1.6), "work": "gather",
		"desc": "Çalılardan yaban mersini toplar, masada ayıklar. Yemiş kulübede yığılır, depoya taşınır. Toplanan çalı bir süre sonra yeniden verir."},
	"ambar": {"name": "Depo", "size": Vector2(9, 7), "cost": {"odun": 30, "tas": 6}, "time": 40.0, "role": "store",
		"desc": "Her şey burada saklanır. İşçiler yüklerini en yakın depoya götürür."},
	"arabaci": {"name": "Arabacı", "size": Vector2(6, 5), "cost": {"odun": 16}, "time": 22.0, "role": "carts", "slots": 3,
		"desc": "İşçileri el arabasıyla çalışır, bir seferde 12 yük taşır. Arabacı varken uzaktaki işyerleri malını kapısının önüne yığar; arabacılar yığınları depoya taşır. Araba patikayı çok aşındırır, yağmurda ve çamurda yavaşlar, saplanır."},
	"ahir": {"name": "Ahır", "size": Vector2(9, 6), "cost": {"odun": 26, "tas": 6}, "time": 34.0, "role": "oxen", "slots": 2,
		"desc": "Her işçisi bir öküz arabası sürer: bir seferde 30 yük. Yavaştır, yolu en derin o aşındırır, çamura en sık o saplanır. Her öküz bir kişi kadar yer."},
	"kuyu": {"name": "Kuyu", "size": Vector2(3, 3), "cost": {"tas": 8, "odun": 2}, "time": 14.0, "role": "well",
		"desc": "Yangında kasabalılar buradan su taşır. Kuyu yoksa yangın söndürülemez."},
	"fener": {"name": "Fener", "size": Vector2(1, 1), "cost": {"odun": 3, "tas": 1}, "time": 6.0, "role": "light", "light": 20.0,
		"desc": "Gece çevresini aydınlatır, çıra yakar (her gece bir odun; kasabalılar akşamüstü getirir). Bekçiler haydudu ve kurdu yalnızca aydınlıkta görür; haydutlar karanlıktan sızar. Rüzgârda kıvılcım saçabilir."},
	"kule": {"name": "Gözcü kulesi", "size": Vector2(4, 4), "cost": {"odun": 18, "tas": 10}, "time": 36.0, "role": "tower", "slots": 2,
		"desc": "Tüfekli bir gözcü çıkar, 70 m içinde aydınlıkta gördüğü haydudu ve kurdu vurur. Yaklaşanları duyar, kasabayı uyarır."},
	"kisla": {"name": "Bekçi karakolu", "size": Vector2(8, 6), "cost": {"odun": 24, "tas": 8}, "time": 34.0, "role": "barracks", "slots": 6,
		"desc": "Buraya verilen kasabalılar tüfekli bekçi olur; gördükleri haydutla ve kurtla çarpışır. Karanlıktakini göremezler."},
}

## What each stuff is: its colour, hit points, whether it burns and how long it takes to burn through
## (s), how readily it catches from what's burning beside it, and how heavy it is (kg per m^3).
const STUFF := {
	"stone": {"color": Color(0.47, 0.46, 0.43), "hp": 500.0, "burns": false, "density": 2200.0},
	"wood": {"color": Color(0.4, 0.28, 0.17), "hp": 140.0, "burns": true, "burn": 34.0, "catch": 0.07, "density": 550.0},
	"dark": {"color": Color(0.25, 0.17, 0.1), "hp": 160.0, "burns": true, "burn": 40.0, "catch": 0.06, "density": 600.0},
	"plank": {"color": Color(0.52, 0.39, 0.25), "hp": 110.0, "burns": true, "burn": 26.0, "catch": 0.09, "density": 500.0},
	"plaster": {"color": Color(0.8, 0.76, 0.66), "hp": 150.0, "burns": true, "burn": 55.0, "catch": 0.035, "density": 900.0},
	"log": {"color": Color(0.43, 0.31, 0.2), "hp": 180.0, "burns": true, "burn": 48.0, "catch": 0.055, "density": 560.0},
	"thatch": {"color": Color(0.6, 0.48, 0.26), "hp": 70.0, "burns": true, "burn": 16.0, "catch": 0.2, "density": 250.0},
	"shingle": {"color": Color(0.36, 0.27, 0.2), "hp": 120.0, "burns": true, "burn": 30.0, "catch": 0.1, "density": 500.0},
	"window": {"color": Color(0.1, 0.08, 0.06), "hp": 40.0, "burns": false, "density": 400.0},
	"water": {"color": Color(0.06, 0.09, 0.1), "hp": 40.0, "burns": false, "density": 1000.0},
	"cloth": {"color": Color(0.55, 0.22, 0.14), "hp": 30.0, "burns": true, "burn": 8.0, "catch": 0.25, "density": 200.0},
}


static func def(kind: String) -> Dictionary:
	return DEFS[kind]


static func cost_text(kind: String) -> String:
	var parts: Array[String] = []
	var cost: Dictionary = DEFS[kind].cost
	for r: String in cost:
		parts.append("%d %s" % [cost[r], RES_NAMES[r].to_lower()])
	return " · ".join(parts)


const MODEL := "res://assets/buildings/%s.glb"
static var _models := {}


static func recipe(kind: String) -> Array[Dictionary]:
	if ResourceLoader.exists(MODEL % kind):
		return _from_model(kind)
	var out: Array[Dictionary] = []
	match kind:
		"ev":
			_hall(out, 6.0, 5.0, 2.3, 1.8, "log", "shingle", 1.0)
			_p(out, "box", Vector3(0.6, 5.2, 0.6), Vector3(1.9, 3.0, -1.7), "stone")
		"kisla":
			_hall(out, 8.0, 6.0, 2.6, 2.2, "log", "shingle", 1.6)
			_p(out, "box", Vector3(0.12, 1.8, 0.12), Vector3(-2.8, 1.3, 3.7), "wood")
			_p(out, "box", Vector3(0.12, 1.8, 0.12), Vector3(-1.4, 1.3, 3.7), "wood")
			_p(out, "box", Vector3(1.6, 0.1, 0.1), Vector3(-2.1, 1.9, 3.7), "dark")
			for k in 4:
				_p(out, "box", Vector3(0.04, 2.0, 0.04), Vector3(-2.65 + k * 0.33, 1.4, 3.6), "wood", Vector3(8, 0, 0))
			_p(out, "box", Vector3(0.14, 1.9, 0.14), Vector3(2.6, 1.35, 3.8), "wood")
			_p(out, "box", Vector3(1.1, 0.12, 0.12), Vector3(2.6, 1.9, 3.8), "wood")
			_p(out, "box", Vector3(0.5, 0.7, 0.3), Vector3(2.6, 1.5, 3.8), "thatch")
		"ambar":
			_hall(out, 9.0, 7.0, 3.0, 2.6, "log", "shingle", 2.2)
			for k in 3:
				_p(out, "box", Vector3(0.8, 0.8, 0.8), Vector3(-3.6 + k * 0.95, 0.75, 4.1), "plank")
			_p(out, "cyl", Vector3(0.7, 0.9, 0.7), Vector3(3.4, 0.8, 4.1), "dark")
			_p(out, "cyl", Vector3(0.7, 0.9, 0.7), Vector3(3.4, 1.7, 4.1), "dark")
		"oduncu":
			_shed(out, 5.0, 5.0, "plank", "shingle")
			for k in 4:
				_p(out, "xcyl", Vector3(3.6, 0.42, 0.42), Vector3(-0.3, 0.56 + (k / 3) * 0.38, -1.4 + (k % 3) * 0.44 + (k / 3) * 0.22), "wood")
			_p(out, "cyl", Vector3(0.7, 0.6, 0.7), Vector3(1.5, 0.65, 1.3), "wood")
		"ormanci":
			_shed(out, 5.0, 5.0, "plank", "thatch")
			for k in 5:
				_p(out, "cyl", Vector3(0.35, 0.3, 0.35), Vector3(-1.6 + k * 0.7, 0.6, -1.3), "plank")
				_p(out, "cone", Vector3(0.45, 0.6, 0.45), Vector3(-1.6 + k * 0.7, 1.05, -1.3), "thatch")
		"tasci":
			_shed(out, 5.0, 5.0, "plank", "shingle")
			_p(out, "box", Vector3(1.0, 0.6, 0.8), Vector3(-1.2, 0.65, -1.3), "stone")
			_p(out, "box", Vector3(0.9, 0.55, 0.7), Vector3(0.1, 0.63, -1.4), "stone")
			_p(out, "box", Vector3(0.8, 0.5, 0.7), Vector3(-0.6, 1.2, -1.35), "stone")
			_p(out, "box", Vector3(1.2, 0.8, 0.9), Vector3(1.3, 0.75, 1.0), "stone")
		"toplayici":
			_shed(out, 5.0, 5.0, "plank", "thatch")
			for k in 3:
				_p(out, "cyl", Vector3(0.6, 0.5, 0.6), Vector3(-1.4 + k * 0.8, 0.6, -1.4), "thatch")
			_p(out, "box", Vector3(0.1, 1.6, 0.1), Vector3(1.6, 1.15, 0.3), "wood")
			_p(out, "box", Vector3(0.1, 1.6, 0.1), Vector3(1.6, 1.15, 1.7), "wood")
			_p(out, "box", Vector3(0.08, 0.08, 1.6), Vector3(1.6, 1.9, 1.0), "wood")
			_p(out, "box", Vector3(0.05, 0.7, 1.3), Vector3(1.6, 1.5, 1.0), "cloth")
		"arabaci":
			_shed(out, 6.0, 5.0, "plank", "shingle")
			_p(out, "box", Vector3(1.0, 0.12, 1.2), Vector3(-1.2, 1.0, -0.4), "plank")
			_p(out, "xcyl", Vector3(0.08, 0.74, 0.74), Vector3(-1.78, 0.82, -0.6), "dark")
			_p(out, "xcyl", Vector3(0.08, 0.74, 0.74), Vector3(-0.62, 0.82, -0.6), "dark")
			_p(out, "box", Vector3(0.08, 0.7, 0.7), Vector3(1.6, 0.85, -1.4), "dark", Vector3(0, 0, 12))
			_p(out, "box", Vector3(0.08, 0.7, 0.7), Vector3(1.75, 0.85, -1.4), "dark", Vector3(0, 0, 12))
		"ahir":
			_hall(out, 9.0, 6.0, 2.6, 2.4, "plank", "thatch", 2.6)
			for k in 3:
				_p(out, "box", Vector3(1.0, 0.6, 0.6), Vector3(3.4, 0.75 + (k / 2) * 0.6, 3.6 + (k % 2) * 0.65 - 0.3), "thatch")
			_p(out, "box", Vector3(0.12, 1.2, 0.12), Vector3(-4.3, 1.0, 3.6), "wood")
			_p(out, "box", Vector3(0.12, 1.2, 0.12), Vector3(-2.3, 1.0, 3.6), "wood")
			_p(out, "box", Vector3(2.1, 0.1, 0.08), Vector3(-3.3, 1.35, 3.6), "wood")
			_p(out, "box", Vector3(2.1, 0.1, 0.08), Vector3(-3.3, 0.85, 3.6), "wood")
			_p(out, "box", Vector3(1.4, 0.4, 0.5), Vector3(-3.3, 0.6, 3.1), "plank")
		"tarla":
			_fence(out, 14.0, 10.0)
		"kuyu":
			_p(out, "box", Vector3(3.2, 3.5, 3.2), Vector3(0, -1.4, 0), "stone")
			_p(out, "cyl", Vector3(1.9, 0.9, 1.9), Vector3(0, 0.8, 0), "stone")
			_p(out, "cyl", Vector3(1.5, 0.04, 1.5), Vector3(0, 1.27, 0), "water")
			_p(out, "box", Vector3(0.16, 2.0, 0.16), Vector3(-0.95, 2.25, 0), "wood")
			_p(out, "box", Vector3(0.16, 2.0, 0.16), Vector3(0.95, 2.25, 0), "wood")
			_p(out, "xcyl", Vector3(2.2, 0.14, 0.14), Vector3(0, 2.9, 0), "dark")
			_p(out, "box", Vector3(2.6, 0.1, 1.3), Vector3(0, 3.45, 0.5), "shingle", Vector3(28, 0, 0))
			_p(out, "box", Vector3(2.6, 0.1, 1.3), Vector3(0, 3.45, -0.5), "shingle", Vector3(-28, 0, 0))
			_p(out, "cyl", Vector3(0.3, 0.35, 0.3), Vector3(0.3, 2.3, 0), "dark")
		"fener":
			_p(out, "box", Vector3(0.5, 1.6, 0.5), Vector3(0, -0.5, 0), "stone")
			_p(out, "box", Vector3(0.16, 3.2, 0.16), Vector3(0, 1.9, 0), "dark")
			_p(out, "box", Vector3(0.9, 0.1, 0.1), Vector3(0.35, 3.4, 0), "dark")
			_p(out, "box", Vector3(0.32, 0.4, 0.32), Vector3(0.7, 3.1, 0), "window")
			_p(out, "cone", Vector3(0.5, 0.25, 0.5), Vector3(0.7, 3.42, 0), "dark", Vector3(0, 45, 0))
		"kule":
			_p(out, "box", Vector3(4.4, 3.5, 4.4), Vector3(0, -1.4, 0), "stone")
			_p(out, "box", Vector3(3.8, 2.0, 3.8), Vector3(0, 1.35, 0), "stone")
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_p(out, "box", Vector3(0.32, 7.0, 0.32), Vector3(sx * 1.6, 5.85, sz * 1.6), "dark")
			for side in 4:
				var a := side * 90.0
				var n := Vector3(sin(deg_to_rad(a)), 0, cos(deg_to_rad(a))) * 1.62
				_p(out, "box", Vector3(0.14, 4.4, 0.14), n + Vector3(0, 4.6, 0), "wood", Vector3(0, a, 38))
				_p(out, "box", Vector3(0.14, 4.4, 0.14), n + Vector3(0, 7.3, 0), "wood", Vector3(0, a, -38))
			_p(out, "box", Vector3(4.6, 0.22, 4.6), Vector3(0, 9.45, 0), "plank")
			for side in 4:
				var a := side * 90.0
				var n := Vector3(sin(deg_to_rad(a)), 0, cos(deg_to_rad(a))) * 2.22
				_p(out, "box", Vector3(4.5, 0.9, 0.1), n + Vector3(0, 10.0, 0), "plank", Vector3(0, a, 0))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_p(out, "box", Vector3(0.14, 2.0, 0.14), Vector3(sx * 2.1, 10.56, sz * 2.1), "dark")
			_p(out, "cone", Vector3(6.2, 2.6, 6.2), Vector3(0, 12.85, 0), "shingle", Vector3(0, 45, 0))
	return out


## A built model's pieces (read once per kind).
static func _from_model(kind: String) -> Array[Dictionary]:
	if _models.has(kind):
		return _models[kind]
	var root := (load(MODEL % kind) as PackedScene).instantiate()
	var out: Array[Dictionary] = []
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var parts := String(mi.name).split("-")
		var stuff := parts[0] if STUFF.has(parts[0]) else "wood"
		var xf := Transform3D.IDENTITY
		var at: Node = mi
		while at != root and at is Node3D:
			xf = (at as Node3D).transform * xf
			at = at.get_parent()
		out.append({"shape": "mesh", "mesh": mi.mesh, "xf": xf, "mat": stuff, "tag": parts[1] if parts.size() >= 3 else "",
			"size": Vector3.ONE, "pos": xf.origin, "rot": Vector3.ZERO})
	root.free()
	_models[kind] = out
	return out


static func _p(out: Array[Dictionary], shape: String, size: Vector3, pos: Vector3, mat: String, rot := Vector3.ZERO) -> void:
	out.append({"shape": shape, "size": size, "pos": pos, "mat": mat, "rot": rot})


## A walled, gabled house: plinth, floor, corner posts, walls (a door in the front), windows, the wall
## plates, gables and the two slopes of the roof.
static func _hall(out: Array[Dictionary], w: float, d: float, wall_h: float, rise: float, wall: String, roof: String, door_w: float) -> void:
	var hx := w * 0.5 - 0.15
	var hz := d * 0.5 - 0.15
	var y0 := 0.47
	var top := y0 + wall_h
	_p(out, "box", Vector3(w + 0.3, 3.5, d + 0.3), Vector3(0, -1.4, 0), "stone")
	_p(out, "box", Vector3(w - 0.1, 0.12, d - 0.1), Vector3(0, 0.41, 0), "plank")
	var log := wall == "log"
	if log:
		_log_walls(out, w, d, hx, hz, y0, wall_h, door_w)
	else:
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_p(out, "box", Vector3(0.26, wall_h + 0.1, 0.26), Vector3(sx * hx, y0 + (wall_h + 0.1) * 0.5, sz * hz), "dark")
	var cy := y0 + wall_h * 0.5
	var side := (w - 0.55 - door_w) * 0.5
	var door_h := minf(2.0, wall_h - 0.4)
	if not log:
		_p(out, "box", Vector3(w - 0.55, wall_h, 0.18), Vector3(0, cy, -hz), wall)
		_p(out, "box", Vector3(0.18, wall_h, d - 0.55), Vector3(-hx, cy, 0), wall)
		_p(out, "box", Vector3(0.18, wall_h, d - 0.55), Vector3(hx, cy, 0), wall)
		_p(out, "box", Vector3(side, wall_h, 0.18), Vector3(-(door_w + side) * 0.5, cy, hz), wall)
		_p(out, "box", Vector3(side, wall_h, 0.18), Vector3((door_w + side) * 0.5, cy, hz), wall)
		_p(out, "box", Vector3(door_w, wall_h - door_h, 0.18), Vector3(0, y0 + door_h + (wall_h - door_h) * 0.5, hz), wall)
	_p(out, "box", Vector3(door_w - 0.1, door_h, 0.07), Vector3(0, y0 + door_h * 0.5, hz + 0.12), "dark")
	var wo := 0.18 if log else 0.1 # (out past the logs' faces)
	_p(out, "box", Vector3(0.06, 0.6, 0.7), Vector3(-hx - wo, y0 + wall_h * 0.6, 0), "window")
	_p(out, "box", Vector3(0.06, 0.6, 0.7), Vector3(hx + wo, y0 + wall_h * 0.6, 0), "window")
	_p(out, "box", Vector3(0.7, 0.6, 0.06), Vector3(-(door_w + side) * 0.5, y0 + wall_h * 0.6, hz + wo), "window")
	_p(out, "box", Vector3(w + 0.2, 0.2, 0.26), Vector3(0, top + 0.1, -hz), "dark")
	_p(out, "box", Vector3(w + 0.2, 0.2, 0.26), Vector3(0, top + 0.1, hz), "dark")
	_p(out, "box", Vector3(0.26, 0.2, d - 0.3), Vector3(-hx, top + 0.1, 0), "dark")
	_p(out, "box", Vector3(0.26, 0.2, d - 0.3), Vector3(hx, top + 0.1, 0), "dark")
	var gable := "plank" if log else wall
	_p(out, "prism", Vector3(w - 0.2, rise, 0.18), Vector3(0, top + 0.2 + rise * 0.5, -hz), gable)
	_p(out, "prism", Vector3(w - 0.2, rise, 0.18), Vector3(0, top + 0.2 + rise * 0.5, hz), gable)
	# The slopes: from the ridge over the middle down past the walls by an overhang.
	var over := 0.55
	var run := hz + over
	var drop := rise * run / hz
	var eave := top + 0.2 + rise - drop
	var length := sqrt(run * run + drop * drop) + 0.15
	var ang := rad_to_deg(atan2(drop, run))
	var mid_y := (top + 0.2 + rise + eave) * 0.5 + 0.12
	_p(out, "box", Vector3(w + 0.9, 0.22, length), Vector3(0, mid_y, run * 0.5), roof, Vector3(ang, 0, 0))
	_p(out, "box", Vector3(w + 0.9, 0.22, length), Vector3(0, mid_y, -run * 0.5), roof, Vector3(-ang, 0, 0))
	_p(out, "xcyl", Vector3(w + 1.0, 0.24, 0.24), Vector3(0, top + 0.32 + rise, 0), "dark")


## A field's fence: posts sunk deep (the ground under a field isn't level), two rails between, a gap
## for a gate in the front.
static func _fence(out: Array[Dictionary], w: float, d: float) -> void:
	var hx := w * 0.5
	var hz := d * 0.5
	var sides := [[Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz)], [Vector3(hx, 0, -hz), Vector3(hx, 0, hz)],
		[Vector3(-hx, 0, hz), Vector3(-hx, 0, -hz)], [Vector3(-hx, 0, hz), Vector3(-1.2, 0, hz)], [Vector3(1.2, 0, hz), Vector3(hx, 0, hz)]]
	for s: Array in sides:
		var a: Vector3 = s[0]
		var b: Vector3 = s[1]
		var n := maxi(1, int(ceil(a.distance_to(b) / 3.5)))
		for k in n + 1:
			_p(out, "box", Vector3(0.13, 3.0, 0.13), a.lerp(b, float(k) / n) + Vector3(0, -0.5, 0), "wood")
		var mid := (a + b) * 0.5
		var yaw := rad_to_deg(atan2(b.x - a.x, b.z - a.z)) - 90.0
		for y in [0.4, 0.8]:
			_p(out, "box", Vector3(a.distance_to(b), 0.08, 0.06), mid + Vector3(0, y, 0), "wood", Vector3(0, yaw, 0))


## Walls of logs laid course on course, the ends crossing past the corners; the front's courses
## below the lintel in two, either side of the door.
static func _log_walls(out: Array[Dictionary], w: float, d: float, hx: float, hz: float, y0: float, wall_h: float, door_w: float) -> void:
	var dia := 0.3
	var courses := maxi(4, roundi(wall_h / dia))
	var door_h := minf(2.0, wall_h - 0.4)
	for c in courses:
		var y := y0 + dia * 0.5 + c * dia
		_p(out, "xcyl", Vector3(w + 0.5, dia, dia), Vector3(0, y, -hz), "log")
		_p(out, "xcyl", Vector3(d + 0.5, dia, dia), Vector3(-hx, y, 0), "log", Vector3(0, 90, 0))
		_p(out, "xcyl", Vector3(d + 0.5, dia, dia), Vector3(hx, y, 0), "log", Vector3(0, 90, 0))
		if y < y0 + door_h:
			var half := (w + 0.5) * 0.5 - door_w * 0.5
			_p(out, "xcyl", Vector3(half, dia, dia), Vector3(-(door_w * 0.5 + half * 0.5), y, hz), "log")
			_p(out, "xcyl", Vector3(half, dia, dia), Vector3(door_w * 0.5 + half * 0.5, y, hz), "log")
		else:
			_p(out, "xcyl", Vector3(w + 0.5, dia, dia), Vector3(0, y, hz), "log")


## An open work shed: plinth, a plank floor, four posts (the front ones taller), a back wall, a
## half wall each side and a lean-to roof.
static func _shed(out: Array[Dictionary], w: float, d: float, wall: String, roof: String) -> void:
	var hx := w * 0.5 - 0.2
	var hz := d * 0.5 - 0.2
	_p(out, "box", Vector3(w + 0.2, 3.5, d + 0.2), Vector3(0, -1.4, 0), "stone")
	_p(out, "box", Vector3(w - 0.1, 0.1, d - 0.1), Vector3(0, 0.4, 0), "plank")
	var back_h := 2.3
	var front_h := 3.0
	for sx in [-1.0, 1.0]:
		_p(out, "box", Vector3(0.24, back_h, 0.24), Vector3(sx * hx, 0.45 + back_h * 0.5, -hz), "dark")
		_p(out, "box", Vector3(0.24, front_h, 0.24), Vector3(sx * hx, 0.45 + front_h * 0.5, hz), "dark")
		_p(out, "box", Vector3(0.14, 1.1, d - 0.6), Vector3(sx * hx, 1.0, 0), wall)
	_p(out, "box", Vector3(w - 0.5, back_h, 0.14), Vector3(0, 0.45 + back_h * 0.5, -hz), wall)
	_p(out, "box", Vector3(w + 0.2, 0.18, 0.22), Vector3(0, 0.45 + back_h + 0.09, -hz), "dark")
	_p(out, "box", Vector3(w + 0.2, 0.18, 0.22), Vector3(0, 0.45 + front_h + 0.09, hz), "dark")
	var rise := front_h - back_h
	var run := hz * 2.0
	var ang := rad_to_deg(atan2(rise, run))
	_p(out, "box", Vector3(w + 0.8, 0.18, sqrt(run * run + rise * rise) + 1.2), Vector3(0, 0.45 + (back_h + front_h) * 0.5 + 0.3, 0), roof, Vector3(-ang, 0, 0))
