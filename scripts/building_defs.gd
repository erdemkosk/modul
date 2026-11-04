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

## What each brings, in a few words (the build bar's buttons).
const GIVES := {"ev": "+4 yatak", "ambar": "mal saklar", "kuyu": "su · yangına kova", "fener": "geceye ışık",
	"meydan": "akşam ateşi · çan", "istasyon": "tren durur · telgraf", "kamp": "ucuz çatı · 150 yük", "tarla": "60 yiyecek/hasat",
	"oduncu": "odun · taş · çamur · yemiş",
	"yol": "hızlı, çamursuz yol", "arabaci": "araba · öküz",
	"sur": "kazık duvar", "hapishane": "3 esir tutar", "sifaci": "yara sarar · sargı", "kapi": "sur kapısı", "kule": "gözcü", "silahlik": "tüfek · bekçi · milis",
	"okuma": "araştırma", "demirci": "tüfek · fişek", "siper": "milise siper", "tel": "engel", "makineli": "makineli tüfek"}

const RES_NAMES := {"odun": "Odun", "tas": "Taş", "yiyecek": "Yiyecek", "camur": "Çamur", "kerpic": "Kerpiç", "ot": "Sargı ve ot", "komur": "Kömür", "demir": "Demir"}

## Open yards: they sit down on the ground as it lies (their ground follows it), not up on a plinth.
const YARDS := ["oduncu", "tasci", "camur", "toplayici", "meydan"]
const CHAINED := ["tel", "siper"] ## laid end to end: each takes hold of the end of the last (Main._chain_snap)
const KINDS := ["meydan", "ev", "tarla", "oduncu", "tasci", "camur", "toplayici", "ambar", "arabaci", "kuyu", "fener", "kule", "silahlik", "hapishane", "sifaci", "okuma", "demirci", "siper", "tel", "makineli"]

const DEFS := {
	"ev": {"name": "Kütük ev", "size": Vector2(6, 5), "cost": {"odun": 14}, "time": 28.0, "role": "house", "beds": 4,
		"desc": "Dört kişilik kütük ev, taş bacalı. Soğukta ve gece ocağında odun yakar. Boş yatak varsa kasabaya yeni insanlar gelir. Arkasına bir oda eklenerek altı kişilik büyütülebilir."},
	"meydan": {"name": "Meydan", "size": Vector2(10, 10), "cost": {"odun": 8, "tas": 12}, "time": 30.0, "role": "square",
		"desc": "Kasabanın ortası: taş döşeli, ortada ateş çukuru, çevresinde banklar, çan, ilan panosu ve pazar tezgâhı. Boş vakitlerinde kasabalılar banklara oturup sohbet eder, morali yükselir; akşamları ateş yakılır, çocuklar orada oynar. Çan sabah işbaşını, akşam paydosu çalar; baskında tehlike çanı çalınınca kasabanın her yerindeki herkes saklanır. Meydan yoksa firariyi ancak yakınındakiler fark eder."},
	"istasyon": {"name": "İstasyon", "size": Vector2(7, 5), "cost": {"odun": 30, "tas": 6}, "time": 30.0, "role": "store", "holds": 200,
		"desc": "Rayın yanına kurulur. Tren artık burada durur, göçmen getirir, mal alır; telgraf da buradan çalışır. Depo olarak 200 yük alır."},
	"yigin": {"name": "Yük yığını", "size": Vector2(6, 4), "cost": {}, "time": 0.0, "role": "store", "holds": 1000, "open": true,
		"desc": "Trenin rayın yanına bıraktığı sandıklar ve çuvallar. Üstünde çatı yok: yiyecek ve odun açıkta yavaş yavaş bozulur, yağmurda daha hızlı. Bir depo kurulunca köylüler yığını oraya taşır, boşalınca kaldırılır."},
	"kamp": {"name": "Kamp deposu", "size": Vector2(6, 5), "cost": {"odun": 10}, "time": 14.0, "role": "store", "holds": 150,
		"desc": "Direkler ve bir çatı: 150 yük alır, altındakiler bozulmaz. İstediğin yere kur; yükü köylüler sırtlarında taşır, yani yer seçimi önemli."},
	"sur": {"name": "Kazık sur", "size": Vector2(1, 1), "cost": {"odun": 1}, "time": 0.0, "role": "wall",
		"desc": "Sivri kütüklerden çit: nokta nokta çiz, kasabalılar parça parça diker (4 kazığa bir odun). Kapı kendiliğinden konmaz: SUR KAPISI ile sen koyarsın, kapısız surdan kasabalılar geçemez. Firariler ancak kırarak geçer."},
	"kapi": {"name": "Sur kapısı", "size": Vector2(3, 1), "cost": {"odun": 6}, "time": 0.0, "role": "gate",
		"desc": "Surun üstüne ya da ucuna konur. Hep kapalı durur, kasabalılar geçerken açılır. Kartından KİLİTLE: kimse geçemez, kasabalılar başka kapıya gider. Firari ancak kırarak geçer."},
	"yol": {"name": "Tahta yol", "size": Vector2(2, 2), "cost": {"odun": 1}, "time": 0.0, "role": "road",
		"desc": "Basılı tutup sürükleyerek döşenir: her 2 m'si bir odun. Üstünde hızlı yüründü, araba saplanmaz, yağmurda çamur olmaz."},
	"tarla": {"name": "Tarla", "size": Vector2(14, 10), "cost": {"odun": 10}, "time": 12.0, "role": "farm", "slots": 4, "holds": 60,
		"desc": "Çitle çevrili çavdar tarlası. Çiftçiler eker, ekin büyür (yağmurda hızlı, karda hiç), olgunlaşınca biçip 60 yiyecek getirirler. Olgun ekin yanar."},
	"oduncu": {"name": "Atölye", "size": Vector2(7, 6), "cost": {"odun": 8}, "time": 18.0, "role": "work", "slots": 3,
		"res": "odun", "reach": 80.0, "station": Vector3(0, 0, 0.55), "face": Vector3(0, 0, -0.3), "pile": Vector3(2.3, 0, 1.9), "work": "saw",
		"desc": "Her türlü toplama işi için bir atölye: kartından ne üreteceğini seç (odun, ağaç dikimi, taş, çamur, yemiş; araştırınca demir, kömür), içi ona göre değişir. Odun için: Kesimciler ağacı devirir, budar, tomruklara böler; tomrukları omuzlayıp kampa getirir, sehpada testereyle biçerler. Biçilen odun kampta yığılır, depoya taşınır. AĞAÇ DİK seçilirse ağaç kesmez, kesilen ağaçların kütüklerine fidan diker; fidan birkaç dakikada ağaç olur."},
	"tasci": {"name": "Atölye", "size": Vector2(7, 6), "cost": {"odun": 14}, "time": 24.0, "role": "work", "slots": 3,
		"res": "tas", "reach": 130.0, "station": Vector3(0, 0, 0.45), "face": Vector3(0, 0, -0.3), "pile": Vector3(2.3, 0, 1.9), "work": "chisel",
		"desc": "Atölye, taş (ya da demir, kömür) için kurulu: Taşçılar kayadan blok kırar, bloğu ocağa taşır, tezgâhta keski ve tokmakla yontar. Yontulan taş ocakta yığılır, depoya taşınır. Madencilik araştırılınca demir ve kömür damarlarından da çıkarabilir."},
	"camur": {"name": "Atölye", "size": Vector2(6, 5), "cost": {"odun": 10}, "time": 20.0, "role": "work", "slots": 3,
		"res": "camur", "reach": 45.0, "station": Vector3(0, 0, 1.35), "face": Vector3(0, 0, 0.6), "pile": Vector3(2.4, 0, 1.8), "work": "gather",
		"desc": "Atölye, çamur için kurulu: Islak zemine, kıyıya kurulur. Çamurcular yakındaki çamuru kürekle kazar, ocağa getirip yığar. Kerpiç yaptırılırsa çamuru kalıba döküp rafa dizerler; güneşte kurur (yağmurda yavaş, karda hiç)."},
	"toplayici": {"name": "Atölye", "size": Vector2(6, 5), "cost": {"odun": 6}, "time": 16.0, "role": "work", "slots": 3,
		"res": "yiyecek", "reach": 85.0, "station": Vector3(0, 0, 1.35), "face": Vector3(0, 0, 0.8), "pile": Vector3(-1.9, 0, 1.6), "work": "gather",
		"desc": "Atölye, yemiş için kurulu: Çalılardan yaban mersini toplar, masada ayıklar. Yemiş kulübede yığılır, depoya taşınır. Toplanan çalı bir süre sonra yeniden verir."},
	"ambar": {"name": "Depo", "size": Vector2(9, 7), "cost": {"odun": 30, "tas": 6}, "time": 40.0, "role": "store", "holds": 400,
		"desc": "Her şey burada saklanır: 400 yük alır. İşçiler ve arabacılar yükleri yeri olan en yakın depoya götürür. Depolar dolunca işyerlerinin yığınları dolar, üretim durur."},
	"arabaci": {"name": "Arabacı", "size": Vector2(6, 5), "cost": {"odun": 16}, "time": 22.0, "role": "carts", "slots": 3,
		"desc": "İşçileri el arabasıyla çalışır, bir seferde 15 yük taşır, yürüyenden hızlıdır. Arabacı varken uzaktaki işyerleri malını kapısının önüne yığar; arabacılar yığınları depoya taşır. Araba patikayı çok aşındırır, yağmurda ve çamurda yavaşlar, saplanır. Kartından ÖKÜZ AL ile arabalar öküz arabası olur: bir seferde 30 yük, ama daha yavaş, yolu daha çok aşındırır; her öküz bir kişi kadar yer."},
	"kuyu": {"name": "Kuyu", "size": Vector2(3, 3), "cost": {"tas": 8, "odun": 2}, "time": 14.0, "role": "well",
		"desc": "Yangında kasabalılar buradan su taşır. Kuyu yoksa yangın söndürülemez."},
	"fener": {"name": "Fener", "size": Vector2(1, 1), "cost": {"odun": 3, "tas": 1}, "time": 6.0, "role": "light", "light": 20.0,
		"desc": "Gece çevresini aydınlatır, çıra yakar (her gece bir odun; kasabalılar akşamüstü getirir). Bekçiler firariyi ve kurdu yalnızca aydınlıkta görür; firariler karanlıktan sızar. Rüzgârda kıvılcım saçabilir."},
	"sifaci": {"name": "Felçer kulübesi", "size": Vector2(5, 4), "cost": {"odun": 12, "tas": 2}, "time": 20.0, "role": "healer", "slots": 2,
		"res": "ot", "reach": 110.0, "station": Vector3(0, 0, 1.2), "face": Vector3(0, 0, 0.5), "pile": Vector3(2.0, 0, 1.6), "work": "gather",
		"desc": "Felçer, köyün doktor yardımcısı: yaralıların yarasını sarar, kanamayı durdurur, iyileşmeyi hızlandırır, kalıcı iz kalmasını çoğu zaman önler. Her tedavi bir sargı ya da şifalı ot ister. Yaralı yoksa ilkbahar ve yazda ormandan ot toplar; kışın ot yetişmez. Her tren de felçere birkaç sargı bezi ve ilaç bırakır."},
	"hapishane": {"name": "Hapishane", "size": Vector2(5, 4), "cost": {"odun": 16, "tas": 8}, "time": 26.0, "role": "jail", "cells": 3,
		"desc": "Kalın kütüklü, demir parmaklıklı küçük bir hücre: üç esir alır. Baskında yaralı düşen firarileri köylüler buraya taşır. Esirleri kazanabilir (köye katılırlar), çalıştırabilir ya da serbest bırakabilirsin. Esirler de yer; köy aç kalırsa kaçmaya çalışırlar."},
	"kule": {"name": "Gözcü kulesi", "size": Vector2(4, 4), "cost": {"odun": 18, "tas": 10}, "time": 36.0, "role": "tower", "slots": 2,
		"desc": "Tüfekli bir gözcü çıkar, 70 m içinde aydınlıkta gördüğü firariyi ve kurdu vurur. Yaklaşanları duyar, kasabayı uyarır."},
	"okuma": {"name": "Okuma odası", "size": Vector2(6, 5), "cost": {"odun": 20, "tas": 6}, "time": 30.0, "role": "research", "slots": 2,
		"desc": "Kitaplar, gazeteler, bir masa ve lamba. Buraya verilenler okur, yazar, hesap yapar: seçtiğin konu araştırılır. Okuryazarlığı yüksek olan çok daha çabuk ilerler. Telgraf, madencilik, demircilik buradan açılır."},
	"demirci": {"name": "Demirci", "size": Vector2(5, 4), "cost": {"odun": 14, "tas": 10}, "time": 30.0, "role": "smith", "slots": 1, "needs": "demircilik",
		"desc": "Körük, örs, ocak. Demirci depodan demir ve kömür alıp tüfek (3 demir, 2 kömür) ve fişek (1 demir, 1 kömürden 10 fişek) döver, silahlığa taşır."},
	"siper": {"name": "Kum torbası mevzi", "size": Vector2(3, 2), "cost": {"tas": 3, "odun": 1}, "time": 8.0, "role": "post",
		"desc": "Toprak doldurulmuş çuvallardan alçak bir duvar. Tehlike çanında milis, firarilerin geldiği yöne en yakın mevzinin arkasına geçer: siperdeki adamı vurmak iki kat zordur."},
	"tel": {"name": "Dikenli tel", "size": Vector2(3.8, 1), "cost": {"odun": 2, "demir": 1}, "time": 4.0, "role": "obstacle",
		"desc": "Çarpı kazıklara gerilmiş dikenli tel. Kasabalılar geçmez, firariler dolaşır. Yol bulamayan firari teli keser: kesene kadar durur, yaralanır, sen de vurursun; kesilen parça gedik açar."},
	"makineli": {"name": "Maxim yuvası", "size": Vector2(3, 3), "cost": {"odun": 4, "tas": 6, "demir": 8}, "time": 24.0, "role": "mg", "slots": 2, "needs": "makineli",
		"station": Vector3(0, 0, -0.9),
		"desc": "Kum torbası çember içinde tekerlekli bir Maxim makineli tüfeği. İki kişi verilir: biri ateş eder, öteki şeridi besler. 65 m içinde gördüğü düşmana kısa kısa taramalar yapar; her tarama silahlıktan bir fişek yer. Fişek yoksa susar."},
	"silahlik": {"name": "Silahlık", "size": Vector2(5, 4), "cost": {"odun": 16, "tas": 6}, "time": 26.0, "role": "barracks", "slots": 6,
		"desc": "Kasabanın tüfekleri, yayları, okları ve fişekleri burada durur. Buraya verilenler tüfekli bekçi olur: gördükleri firariyle ve kurtla çarpışır (karanlıktakini göremezler). Kartından tüfekçi ya da okçu yetiştir; milis işaretli kasabalılar tehlike çanında buradan silah alıp mevziye geçer. FİŞEK DÖK ve YAY YAP açıksa her sabah depodan alınanla fişek, yay ve ok yapılır."},
}

## What's found out in a reading room, one at a time: what it takes (points of work at the desk),
## what it must come after, what it opens.
const TECHS := {
	"telgraf": {"name": "Telgraf", "pts": 40.0, "desc": "İstasyona telgraf teli: köyün kuruluşu ana karaya bildirilir, göçmenler trenle gelir; trene mal satılır, tren çağrılır."},
	"madencilik": {"name": "Madencilik", "pts": 60.0, "desc": "Atölye demir ve kömür damarlarından da çıkarabilir (kartında ÜRET: DEMİR, KÖMÜR)."},
	"dekovil": {"name": "Dekovil", "pts": 70.0, "after": "telgraf", "desc": "Dar hatlı yan hat: atölyelere ve depolara ray döşenir (demir ve odun ister). Tren yükünü oradan doğrudan alır, perona taşımak gerekmez."},
	"kar_sabani": {"name": "Kar Sabanı", "pts": 50.0, "after": "telgraf", "desc": "Lokomotiflere kar sabanı: hatta kar daha yavaş birikir, her tren çoğunu temizler; hat ancak çok derin karda kapanır."},
	"patlayici": {"name": "Patlayıcılar", "pts": 70.0, "after": "madencilik", "desc": "Kara mayını döşenebilir (EMİRLER > MAYIN): kömür tozu ve demir kapta barut. Üstüne basan düşman da, kamyon da, tank da havaya uçar; köylüler yerini bilir."},
	"makineli": {"name": "Makineli tüfek", "pts": 110.0, "after": "demircilik", "desc": "Maxim yuvası kurulabilir: kum torbası çember içinde bir makineli tüfek. Dikenli tel ile birlikte kasabayı kaleye çevirir."},
	"demircilik": {"name": "Demircilik", "pts": 90.0, "after": "madencilik", "desc": "Demirci kurulabilir: demir ve kömürden tüfek ve fişek döver."},
}


const OX_COST := {"odun": 20, "tas": 6} ## a carter's oxen bought (ÖKÜZ AL)
const BOW := {"odun": 2} ## a bow, made at the armoury of a morning (YAY YAP)
const ARROWS := {"odun": 1} ## twelve arrows


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
	"canvas": {"color": Color(0.5, 0.45, 0.33), "hp": 30.0, "burns": true, "burn": 8.0, "catch": 0.25, "density": 200.0},
	"sand": {"color": Color(0.48, 0.42, 0.3), "hp": 400.0, "burns": false, "density": 1600.0},
}


static func def(kind: String) -> Dictionary:
	return DEFS[kind]


static func cost_text(kind: String) -> String:
	return cost_text_of(DEFS[kind].cost)


static func cost_text_of(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for r: String in cost:
		parts.append("%d %s" % [cost[r], RES_NAMES[r].to_lower()])
	return " · ".join(parts)


## The workshop (ATÖLYE), one building for every sort of gathering: what it can be set to, the
## kind it's fitted out as for that (its yard and its gear) and the mode on that kind. Iron and coal
## wait on mining.
const WORKSHOP := {
	"odun": {"kind": "oduncu", "name": "ODUN", "word": "odun"},
	"fidan": {"kind": "oduncu", "mode": "fidan", "name": "AĞAÇ DİK", "word": "ağaç dikimi"},
	"tas": {"kind": "tasci", "name": "TAŞ", "word": "taş"},
	"camur": {"kind": "camur", "name": "ÇAMUR", "word": "çamur"},
	"yiyecek": {"kind": "toplayici", "name": "YEMİŞ", "word": "yemiş"},
	"demir": {"kind": "tasci", "mode": "demir", "name": "DEMİR", "word": "demir", "needs": "madencilik"},
	"komur": {"kind": "tasci", "mode": "komur", "name": "KÖMÜR", "word": "kömür", "needs": "madencilik"},
	"kar": {"kind": "oduncu", "mode": "kar", "name": "HAT KÜRE", "word": "hat küreme"},
}


const WORKSHOP_KINDS := ["oduncu", "tasci", "camur", "toplayici"]


## What a workshop's set to make just now ("" if `b` isn't one).
static func workshop_of(b: Building) -> String:
	for what: String in WORKSHOP:
		var w: Dictionary = WORKSHOP[what]
		if w.kind == b.kind and str(w.get("mode", "")) == ("" if b.kind == "camur" else b.mode):
			return what
	return ""


## A house made better, each once, as its card offers: a back room against its back wall (two more
## beds), its logs plastered with mud (less firewood), a brick stove (less still, its flue up through
## the roof). Each is carried in and built like a mending.
const UPGRADES := {
	"oda": {"name": "ODA EKLE", "cost": {"odun": 10, "tas": 6}, "time": 24.0, "tip": "Arkasına bir oda: 6 yatak"},
	"siva": {"name": "SIVA", "cost": {"camur": 8}, "time": 16.0, "tip": "Kütükleri çamurla sıvar: %30 daha az yakacak"},
	"soba": {"name": "SOBA", "cost": {"kerpic": 12, "tas": 4}, "time": 20.0, "tip": "Kerpiç soba: %40 daha az yakacak, gece boyu sıcak"},
}
const ANNEX := Rect2(-3.3, -6.1, 3.9, 3.6) ## the back room's ground, roof and logs' ends, in the house's space (x, z)
const UPGRADE_BEDS := 6
const SIVA_FUEL := 0.7 ## what a plastered house burns, of what it did
const SOBA_FUEL := 0.6


## The brick stove's flue: up through the roof, whitewashed, a cap on it (the model, ev_soba; plain
## boxes if it hasn't been built).
static func stove() -> Array[Dictionary]:
	if ResourceLoader.exists(MODEL % "ev_soba"):
		return _from_model("ev_soba").duplicate()
	var out: Array[Dictionary] = []
	_p(out, "box", Vector3(0.75, 3.2, 0.75), Vector3(-1.4, 4.7, 0.35), "plaster")
	_p(out, "box", Vector3(0.9, 0.16, 0.9), Vector3(-1.4, 6.38, 0.35), "stone")
	return out


## The back room: a stone plinth, a plank floor, log walls on three sides (the fourth is the
## house's), a shuttered window at the back and a lean-to roof running up under the house's eaves
## (the model, ev_oda; plain boxes if it hasn't been built).
static func annex() -> Array[Dictionary]:
	if ResourceLoader.exists(MODEL % "ev_oda"):
		return _from_model("ev_oda").duplicate()
	var out: Array[Dictionary] = []
	var c := ANNEX.get_center()
	var w := ANNEX.size.x
	var d := ANNEX.size.y
	var hx := w * 0.5 - 0.15
	var back := c.y - d * 0.5 + 0.15
	var y0 := 0.47
	var wall_h := 2.1
	var dia := 0.3
	_p(out, "box", Vector3(w + 0.3, 3.5, d), Vector3(c.x, -1.4, c.y - 0.15), "stone")
	_p(out, "box", Vector3(w + 0.4, 0.35, 0.45), Vector3(c.x, 0.17, back - 0.05), "stone")
	_p(out, "box", Vector3(0.45, 0.35, d - 0.3), Vector3(c.x - hx - 0.05, 0.17, c.y + 0.1), "stone")
	_p(out, "box", Vector3(w - 0.1, 0.12, d - 0.1), Vector3(c.x, 0.41, c.y), "plank")
	for k in roundi(wall_h / dia):
		var y := y0 + dia * 0.5 + k * dia
		_p(out, "xcyl", Vector3(w + 0.5, dia, dia), Vector3(c.x, y, back), "log")
		for sx in [-1.0, 1.0]:
			_p(out, "xcyl", Vector3(d + 0.2, dia, dia), Vector3(c.x + sx * hx, y, c.y + 0.1), "log", Vector3(0, 90, 0))
	_p(out, "box", Vector3(0.9, 0.7, 0.1), Vector3(c.x, y0 + 1.3, back - 0.17), "window")
	for sx in [-1.0, 1.0]:
		_p(out, "box", Vector3(0.45, 0.78, 0.05), Vector3(c.x + sx * 0.7, y0 + 1.3, back - 0.2), "plank")
	var low := y0 + wall_h
	var high := 3.1
	var run := d
	var ang := rad_to_deg(atan2(high - low, run))
	_p(out, "box", Vector3(w + 0.3, 0.16, 0.22), Vector3(c.x, low + 0.08, back), "dark")
	_p(out, "box", Vector3(w + 0.7, 0.14, sqrt(run * run + (high - low) * (high - low)) + 0.5), Vector3(c.x, (low + high) * 0.5 + 0.2, c.y - 0.1), "shingle", Vector3(-ang, 0, 0))
	for sx in [-1.0, 1.0]:
		_p(out, "box", Vector3(0.1, high - low, d * 0.55), Vector3(c.x + sx * hx, low + (high - low) * 0.5 - 0.05, c.y + d * 0.2), "plank")
	return out


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
		"meydan":
			_square(out)
		"yigin": # (a stake at its corner: what's there is the goods themselves, Building.show_heap)
			_p(out, "box", Vector3(0.1, 0.6, 0.1), Vector3(-2.9, 0.3, -1.9), "wood")
		"kamp": # (a log-walled lean-to: a plank floor, a tarpaulin lashed over poles, the stores stacked under it)
			_p(out, "box", Vector3(6.1, 3.5, 5.1), Vector3(0, -1.4, 0), "dark")
			_p(out, "box", Vector3(5.9, 0.1, 4.9), Vector3(0, 0.4, 0), "plank")
			for k in 7: # (the floor's boards)
				_p(out, "box", Vector3(0.05, 0.03, 4.8), Vector3(-2.4 + k * 0.8, 0.46, 0), "dark")
			for sx in [-2.75, 0.0, 2.75]: # (posts, the front ones the taller, peeled poles)
				_p(out, "cyl", Vector3(0.26, 3.2, 0.26), Vector3(sx, 2.0, 2.2), "log")
				_p(out, "cyl", Vector3(0.26, 2.3, 0.26), Vector3(sx, 1.55, -2.2), "log")
			for sx in [-2.75, 2.75]: # (knee braces at the front corners)
				_p(out, "box", Vector3(0.12, 1.15, 0.12), Vector3(sx + signf(-sx) * 0.42, 3.0, 2.2), "wood", Vector3(0, 0, signf(sx) * 40.0))
			for k in 5: # (the back wall, logs laid up between the posts, chinked dark)
				_p(out, "xcyl", Vector3(5.7, 0.3, 0.3), Vector3(0, 0.62 + k * 0.29, -2.2), "log")
				if k < 4:
					_p(out, "box", Vector3(5.4, 0.06, 0.08), Vector3(0, 0.77 + k * 0.29, -2.05), "dark")
			for sx in [-2.8, 2.8]: # (the sides: a rail and half-wall of boards)
				for k in 3:
					_p(out, "box", Vector3(0.1, 0.34, 3.9), Vector3(sx, 0.68 + k * 0.42, -0.2), "plank")
				_p(out, "box", Vector3(0.1, 0.1, 4.3), Vector3(sx, 1.72, -0.1), "dark")
			_p(out, "xcyl", Vector3(6.2, 0.26, 0.26), Vector3(0, 3.62, 2.2), "dark")
			_p(out, "xcyl", Vector3(6.2, 0.26, 0.26), Vector3(0, 2.72, -2.2), "dark")
			var pitch := rad_to_deg(atan2(0.9, 4.4))
			for sx in [-2.4, -1.2, 0.0, 1.2, 2.4]: # (rafters)
				_p(out, "box", Vector3(0.14, 0.14, 5.3), Vector3(sx, 3.3, 0.0), "wood", Vector3(-pitch, 0, 0))
			_p(out, "box", Vector3(6.9, 0.07, 5.9), Vector3(0, 3.46, 0.0), "canvas", Vector3(-pitch, 0, 0))
			for k in 6: # (the tarpaulin's folds, and its hem hanging at the front)
				_p(out, "box", Vector3(0.1, 0.05, 5.8), Vector3(-2.75 + k * 1.1, 3.52, 0.0), "canvas", Vector3(-pitch, 0, 0))
			for k in 9:
				_p(out, "box", Vector3(0.72, 0.16 + 0.07 * (k % 2), 0.03), Vector3(-3.0 + k * 0.75, 3.38, 2.92), "canvas")
			for sx in [-3.1, 3.1]: # (guy ropes to pegs in the ground)
				_p(out, "box", Vector3(0.03, 3.3, 0.03), Vector3(sx * 1.08, 2.0, 2.7), "dark", Vector3(18.0, 0, -signf(sx) * 12.0))
				_p(out, "box", Vector3(0.1, 0.4, 0.1), Vector3(sx * 1.17, 0.2, 3.2), "wood")
			# crates in a stack against the back, their battens dark
			for c: Array in [[-2.1, 0.86, -1.6, 0.0], [-1.15, 0.86, -1.6, 7.0], [-0.2, 0.86, -1.65, -5.0], [-1.65, 1.67, -1.6, 12.0], [-0.65, 1.67, -1.6, -8.0], [-1.2, 2.45, -1.6, 20.0]]:
				_p(out, "box", Vector3(0.84, 0.76, 0.84), Vector3(c[0], c[1], c[2]), "plank", Vector3(0, c[3], 0))
				_p(out, "box", Vector3(0.88, 0.07, 0.88), Vector3(c[0], c[1] + 0.26, c[2]), "dark", Vector3(0, c[3], 0))
				_p(out, "box", Vector3(0.88, 0.07, 0.88), Vector3(c[0], c[1] - 0.26, c[2]), "dark", Vector3(0, c[3], 0))
			# barrels, hooped
			for c: Array in [[1.25, -1.6], [2.05, -1.55], [1.65, -0.85]]:
				_p(out, "cyl", Vector3(0.68, 0.92, 0.68), Vector3(c[0], 0.92, c[1]), "wood")
				for y in [0.68, 1.16]:
					_p(out, "cyl", Vector3(0.71, 0.07, 0.71), Vector3(c[0], y, c[1]), "dark")
			# sacks, heaped to the right at the front
			for c: Array in [[1.2, 0.8], [1.95, 0.85], [1.55, 1.25], [1.6, 0.95]]:
				_p(out, "cyl", Vector3(0.66, 0.42, 0.9), Vector3(c[0], 0.67 if c != [1.6, 0.95] else 1.05, c[1]), "canvas", Vector3(0, 30.0 * c[0], 0))
			# a coil of rope, an axe's block, a lantern on the middle post
			_p(out, "cyl", Vector3(0.6, 0.16, 0.6), Vector3(-1.9, 0.55, 1.3), "thatch")
			_p(out, "cyl", Vector3(0.5, 0.5, 0.5), Vector3(-0.9, 0.7, 1.45), "log")
			_p(out, "box", Vector3(0.05, 0.42, 0.05), Vector3(-0.8, 1.06, 1.45), "wood", Vector3(0, 0, 18.0))
			_p(out, "box", Vector3(0.16, 0.24, 0.16), Vector3(0, 2.55, 2.38), "window")
			_p(out, "box", Vector3(0.2, 0.04, 0.2), Vector3(0, 2.69, 2.38), "dark")
		"ambar":
			_hall(out, 9.0, 7.0, 3.0, 2.6, "log", "shingle", 2.2)
			for k in 3:
				_p(out, "box", Vector3(0.8, 0.8, 0.8), Vector3(-3.6 + k * 0.95, 0.75, 4.1), "plank")
			_p(out, "cyl", Vector3(0.7, 0.9, 0.7), Vector3(3.4, 0.8, 4.1), "dark")
			_p(out, "cyl", Vector3(0.7, 0.9, 0.7), Vector3(3.4, 1.7, 4.1), "dark")
		"sifaci": # (a herb-drying hut: bundles hung from the eaves, a bench with bowls)
			_shed(out, 5.0, 4.0, "plank", "thatch")
			for k in 6:
				_p(out, "cone", Vector3(0.22, 0.45, 0.22), Vector3(-1.9 + k * 0.75, 2.1, -1.2), "thatch")
			_p(out, "box", Vector3(1.6, 0.08, 0.6), Vector3(0.6, 0.85, -1.3), "plank")
			for k in 3:
				_p(out, "cyl", Vector3(0.22, 0.12, 0.22), Vector3(0.1 + k * 0.45, 0.95, -1.3), "wood")
		"okuma": # (a log reading room: a long table, shelves of books, a lamp in the window)
			_hall(out, 6.0, 5.0, 2.4, 1.8, "log", "shingle", 1.0)
			_p(out, "box", Vector3(1.4, 0.9, 0.12), Vector3(-1.8, 1.3, 2.62), "window")
			_p(out, "box", Vector3(1.4, 0.9, 0.12), Vector3(1.8, 1.3, 2.62), "window")
			_p(out, "box", Vector3(2.0, 0.1, 0.8), Vector3(0.0, 0.9, 3.4), "plank")
			for k in 3:
				_p(out, "box", Vector3(0.3 + k * 0.05, 0.08, 0.22), Vector3(-0.5 + k * 0.4, 0.99 + k * 0.02, 3.4), "cloth")
		"siper": # (a low U of sandbags, three courses, staggered)
			for c in 3:
				for k in 5:
					_p(out, "box", Vector3(0.58, 0.22, 0.36), Vector3(-1.2 + k * 0.6 + (0.3 if c % 2 == 1 else 0.0) * (1.0 if k < 4 else 0.0), 0.11 + c * 0.22, 0.65), "sand", Vector3(0, float((k * 7 + c * 3) % 9) - 4.0, 0))
				for sx in [-1.0, 1.0]:
					for k in 2:
						_p(out, "box", Vector3(0.36, 0.22, 0.58), Vector3(sx * 1.32, 0.11 + c * 0.22, 0.05 - k * 0.6 + (0.25 if c % 2 == 1 else 0.0)), "sand", Vector3(0, float((k * 5 + c) % 7) - 3.0, 0))
		"tel": # (crossed stakes, the wire strung between, a coil along the bottom)
			for x in [-1.8, 0.0, 1.8]:
				for s in [-1.0, 1.0]:
					_p(out, "box", Vector3(0.07, 1.3, 0.07), Vector3(x, 0.55, 0), "wood", Vector3(0, 0, s * 32.0))
			for h in [0.35, 0.65, 0.95]:
				_p(out, "box", Vector3(3.8, 0.015, 0.015), Vector3(0, h, 0), "dark")
			for k in 12:
				_p(out, "box", Vector3(0.015, 0.4, 0.015), Vector3(-1.75 + k * 0.32, 0.2, 0.0), "dark", Vector3(fmod(k * 30.0, 180.0) - 90.0, 0, 35.0))
		"makineli": # (a ring of sandbags open at the back, the Maxim on its wheeled mount, its shield, a box of belts)
			for c in 4:
				for k in 9:
					if c == 3 and k == 4:
						continue # (the embrasure the gun looks out of)
					var a := deg_to_rad(-120.0 + k * 30.0 + (15.0 if c % 2 == 1 else 0.0))
					_p(out, "box", Vector3(0.6, 0.22, 0.36), Vector3(sin(a) * 1.25, 0.11 + c * 0.22, cos(a) * 1.25), "sand", Vector3(0, rad_to_deg(a), 0))
			_p(out, "box", Vector3(1.0, 0.36, 1.1), Vector3(0, 0.18, 0.15), "sand")
			for sx in [-1.0, 1.0]:
				_p(out, "cyl", Vector3(0.42, 0.06, 0.42), Vector3(sx * 0.32, 0.57, 0.0), "dark", Vector3(0, 0, 90))
			_p(out, "box", Vector3(0.5, 0.08, 0.9), Vector3(0, 0.67, -0.15), "dark")
			_p(out, "cyl", Vector3(0.17, 0.75, 0.17), Vector3(0, 0.95, 0.4), "dark", Vector3(90, 0, 0))
			_p(out, "cyl", Vector3(0.05, 0.45, 0.05), Vector3(0, 0.95, 0.98), "dark", Vector3(90, 0, 0))
			_p(out, "box", Vector3(0.2, 0.18, 0.32), Vector3(0, 0.95, -0.08), "dark")
			_p(out, "box", Vector3(0.62, 0.5, 0.03), Vector3(0, 1.0, 0.16), "dark")
			_p(out, "box", Vector3(0.35, 0.22, 0.2), Vector3(0.45, 0.11, -0.5), "wood")
		"demirci": # (a smithy: a stone forge with its chimney, an anvil on a block, a quench tub)
			_shed(out, 5.0, 4.0, "plank", "shingle")
			_p(out, "box", Vector3(1.3, 1.0, 1.0), Vector3(-1.3, 0.95, -0.9), "stone")
			_p(out, "box", Vector3(0.6, 3.2, 0.6), Vector3(-1.3, 2.6, -1.2), "stone")
			_p(out, "cyl", Vector3(0.5, 0.6, 0.5), Vector3(0.6, 0.75, 0.2), "log")
			_p(out, "box", Vector3(0.55, 0.22, 0.22), Vector3(0.6, 1.15, 0.2), "dark")
			_p(out, "cyl", Vector3(0.7, 0.5, 0.7), Vector3(1.6, 0.7, 1.0), "plank")
		"hapishane": # (a squat log lock-up, barred windows, a heavy door with iron straps)
			_hall(out, 5.0, 4.0, 2.2, 1.2, "log", "shingle", 0.9)
			for sx in [-1.0, 1.0]:
				for k in 4:
					_p(out, "box", Vector3(0.04, 0.55, 0.04), Vector3(sx * 2.4, 1.55, -0.35 + k * 0.22), "dark")
			_p(out, "box", Vector3(0.95, 0.06, 0.06), Vector3(0, 1.0, 1.93), "dark")
			_p(out, "box", Vector3(0.95, 0.06, 0.06), Vector3(0, 1.8, 1.93), "dark")
		"oduncu":
			_shed(out, 5.0, 5.0, "plank", "shingle")
			for k in 4:
				_p(out, "xcyl", Vector3(3.6, 0.42, 0.42), Vector3(-0.3, 0.56 + (k / 3) * 0.38, -1.4 + (k % 3) * 0.44 + (k / 3) * 0.22), "wood")
			_p(out, "cyl", Vector3(0.7, 0.6, 0.7), Vector3(1.5, 0.65, 1.3), "wood")
		"tasci":
			_shed(out, 5.0, 5.0, "plank", "shingle")
			_p(out, "box", Vector3(1.0, 0.6, 0.8), Vector3(-1.2, 0.65, -1.3), "stone")
			_p(out, "box", Vector3(0.9, 0.55, 0.7), Vector3(0.1, 0.63, -1.4), "stone")
			_p(out, "box", Vector3(0.8, 0.5, 0.7), Vector3(-0.6, 1.2, -1.35), "stone")
			_p(out, "box", Vector3(1.2, 0.8, 0.9), Vector3(1.3, 0.75, 1.0), "stone")
		"camur":
			_shed(out, 5.0, 5.0, "plank", "thatch")
			_p(out, "box", Vector3(2.2, 0.12, 1.2), Vector3(-0.9, 0.48, -1.3), "dark") # (the mixing pit)
			_p(out, "box", Vector3(2.4, 0.3, 0.12), Vector3(-0.9, 0.6, -0.65), "plank")
			_p(out, "box", Vector3(1.0, 0.18, 0.6), Vector3(1.2, 0.95, -1.3), "plank") # (the moulding table)
			for k in 4:
				_p(out, "box", Vector3(0.22, 0.1, 0.4), Vector3(0.85 + k * 0.24, 1.1, -1.3), "plaster")
			_p(out, "box", Vector3(0.1, 0.9, 0.1), Vector3(0.75, 0.6, -1.05), "wood")
			_p(out, "box", Vector3(0.1, 0.9, 0.1), Vector3(1.65, 0.6, -1.05), "wood")
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
## The town's square: a round of laid stone with a kerb, the fire in its stone ring in the middle with
## a pot on a tripod, four benches facing it, the bell in its frame, the notice board, a market
## stall under a striped awning, lamps on posts, the flag. (Village.SQUARE_SEATS: the benches.)
static func _square(out: Array[Dictionary]) -> void:
	var y := 0.35
	_p(out, "cyl", Vector3(10.0, 1.2, 10.0), Vector3(0, y - 0.56, 0), "stone")
	for k in 28: # (the kerb)
		var a := k * TAU / 28.0
		_p(out, "box", Vector3(1.05, 0.14, 0.32), Vector3(cos(a) * 4.9, y + 0.05, sin(a) * 4.9), "sand", Vector3(0, -rad_to_deg(a) + 90.0, 0))
	for ring: Array in [[1.75, 14], [2.2, 18], [2.65, 22], [3.1, 26], [3.55, 30], [4.0, 34], [4.45, 38]]: # (setts laid in rings, the mortar dark between)
		for k in int(ring[1]):
			var a := (k + 0.5 * (int(ring[1]) % 4)) * TAU / float(ring[1])
			_p(out, "box", Vector3(0.34, 0.05, 0.36), Vector3(cos(a) * float(ring[0]), y + 0.05, sin(a) * float(ring[0])), "sand" if k % 3 == 0 else "stone", Vector3(0, -rad_to_deg(a) + 90.0, 0))
	# the fire: a ring of stones, logs laid in, a pot over it
	for k in 10:
		var a := k * TAU / 10.0
		_p(out, "box", Vector3(0.42, 0.3, 0.34), Vector3(cos(a) * 1.05, y + 0.15, sin(a) * 1.05), "stone", Vector3(0, -rad_to_deg(a) + 8.0 * (k % 3), 0))
	_p(out, "cyl", Vector3(1.8, 0.06, 1.8), Vector3(0, y + 0.03, 0), "dark")
	for k in 4:
		_p(out, "xcyl", Vector3(1.2, 0.16, 0.16), Vector3(0, y + 0.16 + (k % 2) * 0.13, 0), "log", Vector3(0, k * 45.0, 0))
	out[out.size() - 1]["tag"] = "fire"
	for k in 3:
		var a := k * TAU / 3.0 + 0.5
		_p(out, "box", Vector3(0.06, 2.1, 0.06), Vector3(cos(a) * 0.5, y + 1.0, sin(a) * 0.5), "dark", Vector3(sin(a) * 14.0, 0, -cos(a) * 14.0))
	_p(out, "cyl", Vector3(0.5, 0.34, 0.5), Vector3(0, y + 1.0, 0), "dark")
	# four benches round it, each with a back
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var turn := -rad_to_deg(a) + 90.0
		var at := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-at.z, 0, at.x)
		_p(out, "box", Vector3(2.5, 0.09, 0.42), at * 2.7 + Vector3.UP * (y + 0.44), "plank", Vector3(0, turn, 0))
		_p(out, "box", Vector3(2.5, 0.34, 0.07), at * 2.93 + Vector3.UP * (y + 0.8), "plank", Vector3(0, turn, 0))
		for s in [-1.05, 1.05]:
			_p(out, "box", Vector3(0.1, 0.44, 0.4), at * 2.7 + side * s + Vector3.UP * (y + 0.2), "dark", Vector3(0, turn, 0))
			_p(out, "box", Vector3(0.1, 1.0, 0.1), at * 2.95 + side * s + Vector3.UP * (y + 0.5), "dark", Vector3(0, turn, 0))
	# the bell, in its frame, on the north side, a shingled cap over it
	var bx := 0.0
	var bz := -4.1
	for s in [-0.9, 0.9]:
		_p(out, "box", Vector3(0.26, 3.0, 0.26), Vector3(bx + s, y + 1.5, bz), "dark")
		_p(out, "box", Vector3(0.12, 1.5, 0.12), Vector3(bx + s, y + 0.75, bz + 0.55), "wood", Vector3(26.0, 0, 0))
	_p(out, "box", Vector3(2.3, 0.26, 0.3), Vector3(bx, y + 3.0, bz), "dark")
	_p(out, "box", Vector3(2.6, 0.1, 1.1), Vector3(bx, y + 3.3, bz + 0.24), "shingle", Vector3(16.0, 0, 0))
	_p(out, "box", Vector3(2.6, 0.1, 1.1), Vector3(bx, y + 3.3, bz - 0.24), "shingle", Vector3(-16.0, 0, 0))
	_p(out, "cone", Vector3(0.62, 0.7, 0.62), Vector3(bx, y + 2.45, bz), "stone")
	out[out.size() - 1]["tag"] = "bell"
	_p(out, "box", Vector3(0.03, 1.9, 0.03), Vector3(bx + 0.34, y + 1.5, bz), "thatch")
	# the notice board, papers pinned to it
	var nx := 4.0
	var nz := -2.2
	for s in [-0.75, 0.75]:
		_p(out, "box", Vector3(0.14, 2.1, 0.14), Vector3(nx, y + 1.05, nz + s), "dark")
	_p(out, "box", Vector3(0.07, 1.05, 1.6), Vector3(nx, y + 1.45, nz), "plank")
	_p(out, "box", Vector3(0.5, 0.06, 1.9), Vector3(nx, y + 2.12, nz), "shingle", Vector3(0, 0, 8.0))
	for c: Array in [[-0.42, 1.68], [0.05, 1.56], [0.48, 1.7], [-0.2, 1.22], [0.34, 1.2]]:
		_p(out, "box", Vector3(0.02, 0.34, 0.27), Vector3(nx - 0.05, y + float(c[1]), nz + float(c[0])), "plaster")
	# a market stall, a striped awning on four poles, goods on its counter
	var mx := -2.9
	var mz := 3.3
	for c: Array in [[-1.1, -0.7], [1.1, -0.7], [-1.1, 0.7], [1.1, 0.7]]:
		_p(out, "box", Vector3(0.1, 2.3 if float(c[1]) > 0.0 else 1.9, 0.1), Vector3(mx + float(c[0]), y + (1.15 if float(c[1]) > 0.0 else 0.95), mz + float(c[1])), "wood")
	for k in 6:
		_p(out, "box", Vector3(0.44, 0.05, 2.0), Vector3(mx - 1.2 + k * 0.44 + 0.1, y + 2.15, mz), "cloth" if k % 2 == 0 else "plaster", Vector3(-15.0, 0, 0))
	_p(out, "box", Vector3(2.2, 0.08, 0.7), Vector3(mx, y + 0.86, mz - 0.1), "plank")
	_p(out, "box", Vector3(2.1, 0.8, 0.08), Vector3(mx, y + 0.42, mz - 0.42), "plank")
	for k in 4:
		_p(out, "cyl", Vector3(0.3, 0.16, 0.3), Vector3(mx - 0.75 + k * 0.5, y + 0.98, mz - 0.12), "thatch")
	_p(out, "box", Vector3(0.6, 0.5, 0.6), Vector3(mx + 1.55, y + 0.25, mz + 0.1), "plank", Vector3(0, 18.0, 0))
	_p(out, "cyl", Vector3(0.56, 0.8, 0.56), Vector3(mx - 1.55, y + 0.4, mz + 0.2), "wood")
	# lamps on posts, and the flag
	for c: Array in [[3.5, 3.5], [-3.5, -3.5]]:
		_p(out, "cyl", Vector3(0.14, 2.9, 0.14), Vector3(c[0], y + 1.45, c[1]), "dark")
		_p(out, "box", Vector3(0.5, 0.06, 0.06), Vector3(float(c[0]) * 0.93, y + 2.8, c[1]), "dark")
		_p(out, "box", Vector3(0.2, 0.3, 0.2), Vector3(float(c[0]) * 0.9, y + 2.6, c[1]), "window")
	_p(out, "cyl", Vector3(0.12, 5.2, 0.12), Vector3(3.9, y + 2.6, 2.2), "wood")
	_p(out, "box", Vector3(0.9, 0.5, 0.03), Vector3(3.42, y + 4.9, 2.2), "cloth")


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
