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
	"flipper": {"name": "Çevirici", "size": Vector3i(2, 1, 3), "mass": 160.0, "kind": "flipper", "hp": 240.0,
		"about": "Pnömatik kol (F): üstündeki aracı havaya atıp ters çevirir. Ters dönünce seni de doğrultur. Aküden hava basar, 3 sn'de dolar."},
	"hinge": {"name": "Menteşe", "size": Vector3i(1, 1, 1), "mass": 40.0, "kind": "joint", "joint": "hinge", "hp": 220.0,
		"about": "Üstüne taktığını tuşla (yoksa E) 90° kaldırır, tekrar basınca indirir. Kapak, rampa, kepçe, kol."},
	"rotor": {"name": "Döner tabla", "size": Vector3i(2, 1, 2), "mass": 110.0, "kind": "joint", "joint": "rotor", "hp": 280.0,
		"about": "Üstüne taktığını tuşla döndürür (16 rad/sn). Bıçak takarsan dönen silah olur: hızla vuran yer ağır hasar alır."},
	"piston": {"name": "Piston", "size": Vector3i(1, 1, 1), "mass": 55.0, "kind": "joint", "joint": "piston", "hp": 200.0,
		"about": "Üstüne taktığını tuşla bir hücre iter, tekrar basınca çeker. Hızlı iter: üstündekini fırlatır."},
	"steer": {"name": "Direksiyon mafsalı", "size": Vector3i(1, 1, 1), "mass": 38.0, "kind": "joint", "joint": "steer", "hp": 200.0, "wood": 3,
		"about": "Üstüne bağladığını dik ekseni çevresinde sağa sola çevirir (35°): A/D ile, bisiklet gidonu gibi. Üstüne bir blok, onun yanına tekerlek tak: tekerlek döner. Arkadaysa ters çevirir (forklift gibi). Tuş verirsen (K) o tuşa basılı tuttukça döner, bırakınca ortalar: istediğin şeyi döndür."},
	"turret": {"name": "Taret", "size": Vector3i(2, 1, 2), "mass": 130.0, "kind": "joint", "joint": "turret", "hp": 300.0,
		"about": "Kendi kendine nişana döner: üstüne ne takarsan (silah, zırh, alev, diken) baktığın yere çevirir. Yük arttıkça yavaşlar. Tuş verirsen o tuşla önde kilitlenir."},
	"ammo": {"name": "Cephane sandığı", "size": Vector3i(1, 1, 1), "mass": 60.0, "kind": "ammo", "hp": 90.0,
		"about": "Yanına değen silahın taşıdığı cephaneyi bir kat artırır (en çok iki sandık). Cephane sınırlı: sandıksız silah çabuk biter. Kırılırsa patlar, yanındakileri de götürür."},
	"barrel": {"name": "Namlu takımı", "size": Vector3i(1, 1, 1), "mass": 45.0, "kind": "barrel", "hp": 140.0,
		"about": "Yanına değen silaha uzun namlu takar: mermi daha hızlı ve daha isabetli, alev daha uzağa gider; ama silah daha yavaş döner."},
	"plate": {"name": "Çelik plaka", "size": Vector3i(1, 1, 1), "mass": 22.0, "kind": "block", "hp": 150.0,
		"about": "Hafif zırh: bloktan çok daha hafif, kafesten çok daha sağlam."},
	"crane": {"name": "Vinç", "size": Vector3i(2, 1, 2), "mass": 260.0, "kind": "crane", "hp": 240.0, "lift": 1500.0,
		"about": "Döner vinç (Y): baktığın yere döner, kancası kolunda baktığın uzaklığa (0,8-2,5 m) kayar. Kanca yükün üstündeyken Y: tutar, sarıp kaldırır; kasanın üstüne çevir, Y: bırakır. 1,5 t kaldırır; ağır yük hafif aracı devirir."},
	"winch": {"name": "Çeki vinci", "size": Vector3i(1, 1, 2), "mass": 90.0, "kind": "winch", "hp": 180.0, "lift": 4000.0,
		"about": "Arkadan halat (N): 12 m'deki yükü ya da aracı bağlar, sarıp yanına çeker; yükü sürükle, saplanmış aracı çamurdan çek. N yine çözer. 4 t çeker."},
	"saw": {"name": "Testere", "size": Vector3i(2, 1, 2), "mass": 95.0, "kind": "saw", "hp": 160.0, "scrap": 12,
		"about": "Önde yatay dairesel testere (R: çalıştır/durdur). Dönerken ağaca sür: gövdeyi keser, ağaç devrilir ve kütüklere ayrılır; kütük ve kütükleri de doğrar. Aküden 3 kW çeker. Araca da keser."},
	"wood_cab": {"name": "Sürücü yeri", "size": Vector3i(2, 2, 2), "mass": 90.0, "kind": "cab", "hp": 420.0, "burns": true,
		"about": "Tahta sandık üstünde sürücü sırası, kalas çatı. Her araçta bir tane olur, sökülmez; yanar."},
	"wood_crane": {"name": "Ahşap vinç", "size": Vector3i(2, 1, 2), "mass": 85.0, "kind": "crane", "hp": 90.0, "lift": 450.0,
		"wood": 6, "burns": true, "reach": Vector2(0.5, 1.7), "tip": Vector3(0.0, 1.45, -1.8), "root": Vector3(0.0, 1.25, -0.1), "hang": 1.1, "wind": 1.4,
		"about": "Kısa kollu döner vinç (6 odun) (Y): baktığın yere döner. Kanca kütüğün üstündeyken Y: tutar, kaldırır; kasanın üstüne çevir, Y: bırakır. 450 kg kaldırır."},
	"wood_rail": {"name": "Parmaklık", "size": Vector3i(1, 2, 1), "mass": 9.0, "kind": "rail", "hp": 35.0, "wood": 1, "burns": true,
		"about": "Bir metre boyunda tahta parmaklık (1 odun): kasanın kenarına diz, üstüne koyduğun kütükler düşmesin."},
	"wood_frame": {"name": "Ahşap kafes", "size": Vector3i(1, 1, 1), "mass": 34.0, "kind": "block", "hp": 45.0, "wood": 2, "burns": true,
		"about": "Elde yontulmuş kalaslardan kafes (2 odun). Çelik kafesten iki kat ağır, kolay kırılır, alev alır."},
	"wood_plate": {"name": "Kalas kaplama", "size": Vector3i(1, 1, 1), "mass": 20.0, "kind": "block", "hp": 60.0, "wood": 1, "burns": true,
		"about": "Çivili kalınca kalaslar (1 odun). Mermiyi biraz tutar, ateşte yanar."},
	"wood_wedge": {"name": "Ahşap kama", "size": Vector3i(1, 1, 1), "mass": 30.0, "kind": "wedge", "hp": 70.0, "wood": 2, "burns": true,
		"about": "Eğik çakılmış kalaslar (2 odun): burun ve kuyruk için. Yanar, kırılır."},
	"wood_wheel": {"name": "Ahşap tekerlek", "size": Vector3i(1, 2, 2), "mass": 62.0, "kind": "wheel", "hp": 60.0,
		"radius": 0.42, "width": 0.12, "rated": 380.0, "travel": 0.05, "lugs": 0.0, "iron": true, "wood": 3, "burns": true,
		"about": "Tahta jantlı, demir çemberli araba tekerleği (3 odun). Yaysız, dar: sarsar, çamura gömülür, kayar; ağırdır, kırılır, yanar."},
	"ballista": {"name": "Arbalet", "size": Vector3i(2, 1, 2), "mass": 75.0, "kind": "weapon", "hp": 90.0, "weapon": "ballista",
		"wood": 5, "burns": true,
		"about": "Döner kaideli büyük yay (5 odun): 2,4 sn'de bir ok, 80 m/s. Delip arkasındaki parçaya da işler. Yanına katran fıçısı takarsan oklar yanar: ahşabı tutuşturur. Aküsüz çalışır."},
	"catapult": {"name": "Mancınık", "size": Vector3i(2, 2, 3), "mass": 190.0, "kind": "weapon", "hp": 140.0, "weapon": "catapult",
		"wood": 8, "burns": true,
		"about": "Burgulu halat mancınığı (8 odun): 5 sn'de bir taş, kavisle 150 m'ye. Taş parçaları koparır, siperi kırar. Yanında katran fıçısı varsa yanan çömlek atar: düştüğü yer yanar."},
	"oilpot": {"name": "Kaynar yağ", "size": Vector3i(2, 1, 2), "mass": 95.0, "kind": "weapon", "hp": 80.0, "weapon": "oil",
		"wood": 4, "burns": true,
		"about": "Mangal üstünde devrilen yağ fıçısı (4 odun): 8 m'ye kadar önüne yanan yağ döker; yer 8 sn yanar, üstündekini yakar. Yakın dövüş için."},
	"pitch": {"name": "Katran fıçısı", "size": Vector3i(1, 1, 1), "mass": 45.0, "kind": "pitch", "hp": 40.0, "wood": 2, "burns": true,
		"about": "Yanına değen arbaletin okları, mancınığın çömlekleri yanar (2 odun). Kırılırsa alev alır, yanındakini tutuşturur."},
	"rockets": {"name": "Roketatar", "size": Vector3i(2, 2, 2), "mass": 240.0, "kind": "weapon", "hp": 160.0,
		"weapon": "rockets", "about": "Altı tüplü: bir salvoda altı roket, sonra tüp tüp dolar (9 sn). Güdümsüz; motoru yanarken hızlanır, sonra düşer."},
}
const ORDER := ["wood_frame", "wood_plate", "wood_rail", "wood_wedge", "wood_wheel", "wood_crane", "ballista", "catapult", "oilpot", "pitch", "frame", "armor", "wedge", "plate", "spike", "wheel_s", "wheel_l", "track", "engine_s", "engine",
	"engine_l", "battery", "light", "minigun", "cannon", "rockets", "flamer", "flipper", "hinge", "rotor", "piston", "steer", "turret", "ammo", "barrel", "crane", "winch", "saw", "cab", "wood_cab"]
## The cab's own small battery (kWh), there without a battery part.
const CAB_KWH := 0.3
## Hit points by part (what a hit takes off; at 0 it comes off), if a part doesn't say its own.
const HP := {"cab": 600.0, "frame": 70.0, "armor": 320.0, "wedge": 220.0, "wheel": 140.0, "engine": 180.0}


static func def(id: String) -> Dictionary:
	return DEFS.get(id, {})


## A driver's place (the cab, or the wood age's seat): one to a machine, never taken off.
static func is_cab(id: String) -> bool:
	return str(def(id).get("kind", "")) == "cab"


## The valley's parts come to hand a few at a time: one's shown in the builder once this much wood
## has been brought home all told (Inventory.delivered); what isn't here is there from the start.
const OPENS := {"wood_wedge": 10, "steer": 10, "pitch": 40, "ballista": 25, "oilpot": 40, "catapult": 70}


static func hp_of(id: String) -> float:
	var d := def(id)
	if d.has("hp"):
		return float(d.hp)
	return float(HP.get(id, HP.get(str(d.kind), 100.0)))


## The valley's ages: wood first (what's made of the forest), then metal: a metal part's made (out of
## scrap) only once its plan's been found (in the old works, a giant's heart, a long haul's pay). A
## part held (taken off a wreck, given) can always go on; what isn't on a plan (wood, the saw, the bin,
## the steering joint) needs none.
const PLANS := {
	"celik": {"name": "Çelik işleri", "parts": ["frame", "plate", "wedge", "armor", "spike"]},
	"teker": {"name": "Tekerlek ve palet", "parts": ["wheel_s", "wheel_l", "track"]},
	"motor": {"name": "Motor ve akü", "parts": ["engine_s", "engine", "engine_l", "battery", "light"]},
	"makine": {"name": "Makine işleri", "parts": ["hinge", "rotor", "piston", "turret", "flipper", "crane", "winch"]},
	"barut": {"name": "Ateşli silahlar", "parts": ["minigun", "cannon", "rockets", "flamer", "ammo", "barrel"]},
}
const PLAN_ORDER := ["celik", "teker", "motor", "makine", "barut"]


## The plan `id`'s made by ("": none, it's wood or it's found only).
static func plan_of(id: String) -> String:
	for k: String in PLANS:
		if id in PLANS[k].parts:
			return k
	return ""


## What making one of `id` takes in scrap once its plan's known (its weight's worth); a few (the
## saw, the bin) the workshop can always knock up out of scrap, with no plan.
static func metal_cost(id: String) -> int:
	if def(id).has("scrap"):
		return int(def(id).scrap)
	return maxi(ceili(float(def(id).mass) / 15.0), 1) if plan_of(id) != "" else 0


## What making one of `id` takes in wood (0: it isn't made, only found).
static func wood_cost(id: String) -> int:
	return int(def(id).get("wood", 0))


## Wood: it catches fire.
static func burns(id: String) -> bool:
	return bool(def(id).get("burns", false))


static func model(id: String) -> String:
	return "res://assets/parts/%s.glb" % id


## How a part can lie: `rot` is its turn about up (0-3 quarter turns) plus 4 times its tilt (0
## upright, 1 tipped forward, 2 upside down, 3 tipped back, 4 on its right side, 5 on its left).
## Old designs (0-3) are upright.
const TILTS := [Basis.IDENTITY, Basis(Vector3.RIGHT, -PI * 0.5), Basis(Vector3.RIGHT, PI), Basis(Vector3.RIGHT, PI * 0.5),
	Basis(Vector3.BACK, -PI * 0.5), Basis(Vector3.BACK, PI * 0.5)]
const TILT_NAMES := ["dik", "öne yatık", "ters", "arkaya yatık", "sağ yanı üstü", "sol yanı üstü"]


static func basis_of(rot: int) -> Basis:
	return Basis(Vector3.UP, (rot % 4) * PI * 0.5) * TILTS[(rot / 4) % 6]


## What can lie any way (wheels, tracks and the cab only stand upright: they work that way up).
static func can_tilt(id: String) -> bool:
	return not str(def(id).kind) in ["wheel", "track", "cab"]


## The footprint as the part lies.
static func size_of(id: String, rot: int) -> Vector3i:
	var s: Vector3i = DEFS[id].size
	if rot < 4:
		return Vector3i(s.z, s.y, s.x) if rot % 2 == 1 else s
	var v := basis_of(rot) * Vector3(s)
	return Vector3i(roundi(absf(v.x)), roundi(absf(v.y)), roundi(absf(v.z)))


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
	return Transform3D(basis_of(rot), c)
