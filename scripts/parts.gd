class_name Parts
extends RefCounted
## What every part is: its footprint on the build grid (cells of CELL m: x across, y up, z along,
## the front being -z), its mass, what it does, its model (assets/parts/<id>.glb, built by
## tools/blender/build_parts.py with the same footprints) and its name.
##
## The numbers are a real machine's: a cab is a steel box with glass, ~150 kg; a diesel of 90 kW
## weighs ~180 kg; a wheel says how much it can carry (its tyre and spring) and its spring is that
## stiff, so an overloaded wheel sits on its bump stop and a heavy machine on small wheels drags its
## belly; a wide lugged tyre spreads its load and sinks less in mud and grips better there, a road
## tyre grips best on hard ground.
## A track is five road wheels' contacts along a belt that spreads its load (so it sinks less), turned
## by driving one side back. Electric things (a minigun's motor, turrets turning, loaders, lights) draw
## on the battery (the cab's own, and any battery parts); the engines' alternators charge it.

const CELL := 0.5

const DEFS := {
	"cab": {"name": "Kabin", "size": Vector3i(2, 2, 2), "mass": 150.0, "kind": "cab",
		"about": "Sürücü burada. Her araçta bir tane olur, sökülmez."},
	"frame": {"name": "Çelik kafes", "size": Vector3i(1, 1, 1), "mass": 14.0, "kind": "block",
		"about": "Kare profil kafes: hafif, iskelet için."},
	"armor": {"name": "Zırh bloğu", "size": Vector3i(1, 1, 1), "mass": 55.0, "kind": "block",
		"about": "Dolu çelik: ağır, sağlam; ağırlık merkezini aşağı çeker."},
	"wedge": {"name": "Kama", "size": Vector3i(1, 1, 1), "mass": 28.0, "kind": "wedge",
		"about": "Eğimli zırh: burun ve kuyruk için, engele tırmanır."},
	"wheel_s": {"name": "Yol tekerleği", "size": Vector3i(1, 2, 2), "mass": 32.0, "kind": "wheel",
		"radius": 0.38, "width": 0.26, "rated": 450.0, "travel": 0.16, "lugs": 0.0,
		"about": "r 0,38 m, 450 kg taşır. Sert zeminde iyi tutar, çamurda batar."},
	"wheel_l": {"name": "Arazi tekerleği", "size": Vector3i(2, 3, 3), "mass": 85.0, "kind": "wheel",
		"radius": 0.62, "width": 0.42, "rated": 1200.0, "travel": 0.28, "lugs": 1.0,
		"about": "r 0,62 m, 1200 kg taşır. Tırnaklı, geniş: çamurda yüzer ve tutar."},
	"track": {"name": "Palet", "size": Vector3i(2, 2, 6), "mass": 380.0, "kind": "track", "hp": 300.0,
		"radius": 0.215, "width": 0.4, "rated": 520.0, "travel": 0.05, "lugs": 1.0, "bogies": 5, "patch": 0.45,
		"about": "3 m çelik palet, 2600 kg taşır. Yükü geniş yayar: çamurda tekerlekten az batar, iyi tutar. Döndürmek için bir yanı geri sarar."},
	"engine": {"name": "Dizel motor", "size": Vector3i(2, 2, 2), "mass": 180.0, "kind": "engine", "power": 90.0,
		"alternator": 2.8,
		"about": "Turbo dizel, 90 kW. Alternatörü aküyü 2,8 kW ile doldurur. Birden fazlası güçlerini toplar."},
	"engine_l": {"name": "V8 dizel", "size": Vector3i(2, 2, 3), "mass": 320.0, "kind": "engine", "power": 200.0,
		"alternator": 4.5, "hp": 260.0,
		"about": "İki turbolu V8, 200 kW. Ağır ama güçlü: tank ve paletliler için. Alternatörü 4,5 kW."},
	"engine_s": {"name": "Küçük motor", "size": Vector3i(1, 1, 2), "mass": 70.0, "kind": "engine", "power": 40.0,
		"alternator": 1.5, "hp": 90.0,
		"about": "Benzinli, 40 kW. Hafif ve küçük: hafif akıncılar için, ya da yedek güç."},
	"battery": {"name": "Akü", "size": Vector3i(1, 1, 2), "mass": 60.0, "kind": "battery", "hp": 90.0, "kwh": 1.2,
		"about": "24 V, 1,2 kWh. Silahların motorları, kule dönüşü ve farlar buradan çeker; motorlar doldurur."},
	"light": {"name": "Far", "size": Vector3i(1, 1, 1), "mass": 4.0, "kind": "light", "hp": 20.0,
		"about": "Önüne doğru ışık. Gece için."},
	"minigun": {"name": "Minigun", "size": Vector3i(2, 1, 2), "mass": 110.0, "kind": "weapon", "hp": 120.0,
		"weapon": "minigun", "about": "Altı namlu, dakikada 2400 atım. Namlular önce dönmeli. Yakında yıkıcı."},
	"cannon": {"name": "Top", "size": Vector3i(2, 2, 2), "mass": 420.0, "kind": "weapon", "hp": 260.0,
		"weapon": "cannon", "about": "76 mm. 2,5 sn'de bir; mermi düşer, patlar, toprağı oyar. Geri tepmesi aracı iter."},
	"spike": {"name": "Koç başlığı", "size": Vector3i(1, 1, 1), "mass": 45.0, "kind": "ram", "hp": 260.0,
		"about": "Çivili çelik burun. Çarptığın yere çok daha ağır darbe vurur; ön yüze takılır."},
	"flamer": {"name": "Alev makinesi", "size": Vector3i(2, 1, 2), "mass": 90.0, "kind": "weapon", "hp": 110.0,
		"weapon": "flamer", "about": "14 m'ye alev püskürtür: önündeki her parçayı yakar. Yakın dövüş için."},
	"plate": {"name": "Çelik plaka", "size": Vector3i(1, 1, 1), "mass": 22.0, "kind": "block", "hp": 150.0,
		"about": "Hafif zırh: bloktan çok daha hafif, kafesten çok daha sağlam."},
	"rockets": {"name": "Roketatar", "size": Vector3i(2, 2, 2), "mass": 240.0, "kind": "weapon", "hp": 160.0,
		"weapon": "rockets", "about": "Altı tüplü: bir salvoda altı roket, sonra tüp tüp dolar (9 sn). Güdümsüz; motoru yanarken hızlanır, sonra düşer."},
}
const ORDER := ["frame", "armor", "wedge", "plate", "spike", "wheel_s", "wheel_l", "track", "engine_s", "engine",
	"engine_l", "battery", "light", "minigun", "cannon", "rockets", "flamer", "cab"]
## The cab's own small battery (kWh), there without a battery part.
const CAB_KWH := 0.3
## Hit points by part (what a hit takes off; at 0 it comes off), if a part doesn't say its own.
const HP := {"cab": 600.0, "frame": 70.0, "armor": 320.0, "wedge": 220.0, "wheel": 140.0, "engine": 180.0}


static func def(id: String) -> Dictionary:
	return DEFS.get(id, {})


static func hp_of(id: String) -> float:
	var d := def(id)
	if d.has("hp"):
		return float(d.hp)
	return float(HP.get(id, HP.get(str(d.kind), 100.0)))


static func model(id: String) -> String:
	return "res://assets/parts/%s.glb" % id


## The footprint turned `rot` quarter turns about +y (x and z swap on odd turns).
static func size_of(id: String, rot: int) -> Vector3i:
	var s: Vector3i = DEFS[id].size
	return Vector3i(s.z, s.y, s.x) if rot % 2 == 1 else s


## Every cell a part covers, its footprint's low corner at `at`.
static func cells_of(id: String, at: Vector3i, rot: int) -> Array[Vector3i]:
	var s := size_of(id, rot)
	var out: Array[Vector3i] = []
	for x in s.x:
		for y in s.y:
			for z in s.z:
				out.append(at + Vector3i(x, y, z))
	return out


## The part's node transform in the machine's space: its footprint's centre, turned.
static func xform_of(id: String, at: Vector3i, rot: int) -> Transform3D:
	var s := size_of(id, rot)
	var c := (Vector3(at) + Vector3(s) * 0.5) * CELL
	return Transform3D(Basis(Vector3.UP, rot * PI * 0.5), c)
