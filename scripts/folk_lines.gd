class_name FolkLines
extends RefCounted
## What one of the folk might say just now, in a word with someone (FolkTalk shows it): drawn from
## what it's been thinking (its thoughts, by their ids), what's on everyone's mind (the season, the
## weather, the stores, the train), its family, the one it's talking to, what last happened in the
## town, who it is (its traits, where it came from) and how it feels. Each a short line in plain
## speech, the way people of a small taiga town would put it; picked at random by weight from those
## that fit, never the same as one said just before.

## By thought id: lines for it ("%s" the name in the thought's text, its first word).
const THOUGHTS := {
	"hungry": ["Karnım zil çalıyor.", "Ambarda bir lokma kalmadı mı?", "Açlıktan dizlerim titriyor.", "Bir somun ekmeğe can veririm."],
	"crowd": ["Evde ayak basacak yer yok.", "Bir oda daha lazım bize.", "Çocuklar yer yatağında yatıyor."],
	"home": ["Sobanın sıcağı başka.", "Evimiz küçük ama sıcak.", "Akşam olsa da evde otursam."],
	"fire": ["Dün akşam meydanda iyi oturduk.", "Ateş başında şarkı iyi geldi."],
	"grief": ["%s gözümün önünden gitmiyor.", "Zavallı %s... daha dün buradaydı.", "%s için mum yaktım."],
	"loss": ["Bir mezar daha kazıldı.", "Bu kasaba ölü kaldıramaz artık."],
	"funeral": ["Cenaze sessiz geçti.", "Mezarın başında kimse bir şey diyemedi."],
	"keen": ["Sevdiğim işi yapınca gün çabuk geçiyor.", "Elim işe alıştı, bak."],
	"unfit": ["Bu iş bana göre değil.", "Elim yatmıyor bu işe.", "Başka iş yok muydu bana?"],
	"relief": ["Askerler gelmeseydi halimiz yamandı.", "Bu sefer Merkez yüzümüze baktı."],
	"soldiers": ["Asker geliyormuş, hayra alamet değil.", "Askerler yine bir şey isteyecek."],
	"conscript": ["%s cepheye gitti, döner mi dersin?", "Cephe %s gibileri yutar."],
	"stood": ["Askere boyun eğmedik, iyi ettik.", "Diz çökseydik her şeyi alırlardı."],
	"repelled": ["Askerleri püskürttük, gördün mü?", "Bir daha gelmeye yürekleri yetmez."],
	"persuaded": ["Lafla geri çevirdik onları, inanır mısın?"],
	"talked": ["%s laf ebesidir, askerleri bile döndürdü."],
	"execution": ["O idam içime sinmedi.", "Darağacının gölgesi düştü kasabaya."],
	"forced": ["Hapistekileri zorla çalıştırıyorlar, doğru mu bu?"],
	"free": ["Yeni bir hayat, söz veriyorum.", "Bana bir şans verdiniz, unutmam."],
	"treated": ["Felçer yaramı iyi sardı.", "Sargıyı değiştirdiler, acı azaldı."],
	"saved": ["Kasaba beni sakladı, borcumu ödeyemem."],
	"betrayed": ["Birini devriyeye vermişler. Yazık.", "Kim ispiyonladı, bilen yok."],
	"left": ["%s çekip gitti, bir kişi daha eksildi.", "%s dayanamadı, gitti."],
	"hurt": ["Yaram sızlıyor.", "Hâlâ kanıyor mu, bir bakar mısın?"],
}
const SEASON := [
	["Yollar çamur deryası.", "Kar eriyor, toprak kokusu geliyor.", "Ekim vakti geldi, tohum yeter mi?"],
	["Ot kupkuru, bir kıvılcım yeter.", "Sivrisinekler canımı okudu.", "Bu sıcakta balık bile tutmaz."],
	["Kış yaklaşıyor, odun yetmez.", "Yapraklar döküldü bile.", "Kışlık ne kadar var ambarda?"],
	["Ayaz kemiğe işliyor.", "Kış uzun sürecek bu yıl.", "Kurtlar köye iniyormuş."],
]
## What last happened worth talking about (FolkTalk.last_event): by a word in the day-book's line.
const EVENTS := [
	[["Yangın", "tutuştu", "yanıyor"], ["Yangını gördün mü? Az kalsın hepsi gidiyordu.", "Kova taşımaktan kollarım koptu.", "Bir kıvılcım, koca dam gitti."]],
	[["çocuğu oldu"], ["Kasabaya bir bebek doğdu, hayırlı olsun.", "Bebeğin sesi gece boyu geldi."]],
	[["kampı dağıtıldı"], ["Firari kampını dağıttık, rahat bir nefes."]],
	[["Firari", "yağmaladı"], ["Firariler yine gelir mi dersin?", "Geceleri artık gözüme uyku girmiyor.", "Bir dahakine hazır olacağız."]],
	[["Kurt"], ["Kurtlar köye iniyor, çocuklara göz kulak olun.", "Dün gece ulumaları duydun mu?"]],
	[["Tren gecikti", "Hat karla", "hattı kapattı"], ["Tren yine gecikti.", "Hat kapalıyken dünyadan kopuk gibiyiz."]],
	[["Tren düdüğü", "Tren perona", "Trenden"], ["Trenle yeni yüzler geldi.", "Trende tuz var mıymış?", "Tren gelince kasaba bir canlanıyor."]],
	[["Gazete"], ["Gazetede ateşkes yazıyormuş, doğru mu acaba?", "Gazeteyi okudun mu? Başkent yine karışık."]],
	[["Postayla"], ["Postada bana bir şey var mıydı?"]],
	[["Zırhlı tren"], ["Zırhlı treni gördün mü? Koca bir demir yığını."]],
	[["motor sesleri", "askerleri yolda"], ["Kamyon sesleri... yine asker.", "Askerler ne isteyecek bu sefer?"]],
	[["gömüldü", "öldü"], ["Bir mezar daha.", "Toprak bol, insan az."]],
	[["yeni biri geldi", "göçmen iniyor"], ["Yeni gelenler nereli acaba?", "Yeni yüzler var, iyi."]],
	[["idam"], ["O idamı unutamıyorum."]],
	[["Araştırma tamam"], ["Okuma odasındakiler yine bir şey bulmuş."]],
]
const TRAITS := {
	"tembel": ["Biraz soluklanalım, iş kaçmıyor.", "Bugün de bitmez bu iş."],
	"caliskan": ["Boş durmak bana göre değil.", "Şu duvarı akşama bitiririz."],
	"obur": ["Akşama ne pişiyor acaba?", "Bir tas çorba olsa..."],
	"korkak": ["Ormandan ses geldi, duydun mu?", "Geceleri kapıyı iki kez sürgülüyorum."],
	"gozukara": ["Gelsinler bakalım, korkan yok.", "Firari dediğin bir avuç aç adam."],
	"sibir": ["Buna soğuk mu diyorsunuz? Bizim oralarda bahar sayılır."],
	"zeki": ["Bir okuma odası kursak fena olmaz.", "Şu değirmeni suyla döndürsek..."],
	"pehlivan": ["Şu kütüğü tek başıma kaldırırım.", "Ağır olanı bana bırakın."],
	"cevik": ["İstasyona gidip gelmem bir solukta."],
	"kanaatkar": ["Az olsun, temiz olsun.", "Doyduk ya, gerisi fazlalık."],
}
const ORIGINS := {
	"esir": ["Kampta bundan beterini gördüm.", "Esirken bu rayları biz döşedik."],
	"surgun": ["Bir gazete olsa da okusak.", "Sürgünde de kitaplarım vardı."],
	"demiryolcu": ["Rayların sesini özledim.", "Bu hatta makas bakımı lazım."],
	"asker": ["Cephede de böyle sessizdi, sonra...", "Tüfeğin yağını kim sildi?"],
	"koylu": ["Toprak iyi, ekersen verir.", "Yağmur yağsa da tarla sulansa."],
	"makinist": ["Şu buhar makinesini bir görsem.", "Bir torna olsa neler yapardım."],
	"felcer": ["Kaynamamış su içmeyin.", "Sargı bezi azaldı."],
	"papaz": ["Tanrı bizi unutmadı.", "Pazar günü bir dua edelim."],
	"tuccar": ["Bu kasabada iş var, görüyorum.", "Trende tuz pahalanmış."],
	"oduncu": ["Tayga insanı besler de öldürür de.", "Kuzey yamaçta iyi çam var."],
}
## The wound's place, as one says it of someone ("Ivan'ın sol kolu yaralı").
const PART_OF := {"bas": "başı", "govde": "karnı", "sol_kol": "sol kolu", "sag_kol": "sağ kolu", "sol_bacak": "sol bacağı", "sag_bacak": "sağ bacağı"}
## Said at a pastime, now and then, to whoever's by (`where` in a talk, or the pastime's anim).
const PLACES := {
	"fire": ["Ateşe bir odun daha atın.", "Bir şarkı söyle de ısınalım.", "Ateşin başı gibisi yok."],
	"fish": ["Bugün balık vurmuyor.", "Dün bir turna yakaladım, kolum kadardı."],
	"porch": ["Akşam serinliği iyi geliyor.", "Şu yorgunluk bir geçse."],
}


## A line for `v` to say to `to` (or to no one), `where` the talk is ("fire", "porch", "" ...).
static func line(v: Villager, to: Villager = null, where := "") -> String:
	var village: Node = v.village
	var pool: Array = [] ## [weight, text]
	# what it's been thinking, the strongest first
	for t: Dictionary in v.thoughts:
		var id := str(t.id)
		var name := str(t.text).split(" ")[0]
		var w := 2.0 + absf(float(t.value)) / 6.0
		match id:
			"night":
				var tx := str(t.text)
				if tx.begins_with("Açıkta"):
					_add(pool, w, ["Toprakta yatmaktan sırtım tutuldu.", "Bir damın altı olsa yeter bana."])
				elif float(t.value) < 0.0:
					_add(pool, w, ["Dün gece donduk.", "Ocakta odun bitmişti, sabaha kadar titredik."])
				else:
					_add(pool, 1.0, ["Gece soba harıl harıl yandı.", "Sıcak yatak gibisi yok."])
			"letter":
				_add(pool, w, ["Mektup geldi, yüzüm güldü.", "Evden haber var, iyiler.", "Mektubu üç kez okudum."] if float(t.value) > 0.0 \
					else ["Kötü haber aldım, sorma.", "Mektubu okuyunca elim ayağım kesildi.", "Keşke o mektup hiç gelmeseydi."])
			"scar":
				_add(pool, w, ["Bu tek kolla ne iş yapılır?"] if "tek_kol" in v.scars else (["Değnekle nereye kadar?"] if "tek_bacak" in v.scars else ["İzi kalacak, biliyorum."]))
			_:
				if THOUGHTS.has(id):
					var lines: Array = THOUGHTS[id]
					_add(pool, w, lines.map(func(l: String) -> String: return l % name if "%s" in l else l))
	var seasons: Node = village.get("seasons")
	var weather: Node = village.get("weather")
	var season := int(seasons.get("season")) if seasons else -1
	if season >= 0:
		_add(pool, 1.2, SEASON[season])
	if weather:
		var temp := float(weather.get("temperature"))
		if float(weather.get("snow_intensity")) > 0.3:
			_add(pool, 1.5, ["Kar dizi buldu.", "Bu kar dinmeyecek galiba."])
		elif Weather.rain_now > 0.3:
			_add(pool, 1.5, ["Yağmur dinmek bilmiyor.", "Yollar yine çamur olacak."])
		elif float(weather.get("fog_amount")) > 0.4:
			_add(pool, 1.2, ["Sis inmiş, göz gözü görmüyor."])
		if temp < -12.0:
			_add(pool, 1.5, ["Tükürsen buz olur.", "Böyle ayazda kurt bile inine çekilir."])
		elif temp > 24.0:
			_add(pool, 1.0, ["Bu sıcakta iş mi yapılır?"])
		if weather.has_method("is_night") and bool(weather.call("is_night")):
			_add(pool, 0.8, ["Gece çöktü, kurtlar ulur şimdi.", "Yıldızlar ne parlak bu gece."])
	var stock: Variant = village.get("stock")
	if stock is Dictionary:
		var food := int((stock as Dictionary).get("yiyecek", 0))
		var wood := int((stock as Dictionary).get("odun", 0))
		if food < 20:
			_add(pool, 2.5, ["Ambar boşalıyor.", "Kışa ekmek yetmez bu gidişle.", "Yarın ne yiyeceğiz, bilen var mı?"])
		elif food > 150:
			_add(pool, 0.8, ["Ambar dolu, şükür.", "Bu kış aç kalmayız."])
		if wood < 12 and (season >= 2 or (weather and float(weather.get("temperature")) < 3.0)):
			_add(pool, 2.0, ["Kış yaklaşıyor, odun yetmez.", "Odun stoğu dibe vurdu."])
	# the train
	if village.has_method("line_shut") and bool(village.call("line_shut")):
		_add(pool, 2.0, ["Hat karla kapandı, tren gelmez.", "Kar kürenmeden tren göremeyiz."])
	elif village.get("next_train") != null:
		var due := int(village.get("next_train")) - int(village.get("day"))
		if due >= 2:
			_add(pool, 1.2, ["Trenden haber yok.", "Tren ne zaman gelecek, bilen var mı?"])
		elif due == 1:
			_add(pool, 1.5, ["Yarın tren gelecekmiş.", "Yarın trenle tuz gelir belki."])
		elif due == 0:
			_add(pool, 1.5, ["Bugün tren gelecek, kulağın düdükte olsun."])
	# family: someone of its own hurt, its children
	for o: Villager in village.get("villagers"):
		if o == v or o.dead or o.family != v.family or v.family == "":
			continue
		if not o.wounds.is_empty() or o.down or o.recovering:
			var part := str(PART_OF.get(str(o.wounds[0].part), "")) if not o.wounds.is_empty() else ""
			var first := o.display_name.split(" ")[0]
			var who := gen(first)
			_add(pool, 3.5, ["%s %s yaralı." % [who, part] if part != "" else "%s yarası kötü." % who, "%s iyileşir inşallah." % first])
		elif o.is_child and not v.is_child:
			_add(pool, 1.0, ["Bizim %s çabuk büyüyor." % o.display_name.split(" ")[0], "%s bütün gün dışarıda, eve girmiyor." % o.display_name.split(" ")[0]])
	# the one it's talking to
	if to and is_instance_valid(to):
		if not to.wounds.is_empty() or to.bleeding:
			_add(pool, 3.0, ["Yaran nasıl?", "Kolunu bir göreyim.", "Felçere göründün mü?"])
		if to.mood < 25.0:
			_add(pool, 2.0, ["Kendini bırakma, geçer bunlar.", "Yüzün asık, ne oldu?"])
		if v.is_child and to.is_child:
			_add(pool, 4.0, ["Sen ebesin!", "Hadi saklambaç!", "Ben daha hızlıyım!"])
	# what last happened in the town
	var talk := FolkTalk.of(village)
	if talk and Time.get_ticks_msec() / 1000.0 - talk.last_event_at < 300.0:
		for e: Array in EVENTS:
			var hit := false
			for word: String in e[0]:
				if talk.last_event.contains(word):
					hit = true
					break
			if hit:
				_add(pool, 3.0, e[1])
				break
	if PLACES.has(where):
		_add(pool, 2.0, PLACES[where])
	if v.is_child:
		_add(pool, 2.0, ["Bana da tüfek verecekler mi?", "Annem eve çağırıyor.", "Istasyona gidelim mi?"])
	else:
		for t: String in v.traits:
			if TRAITS.has(t):
				_add(pool, 0.9, TRAITS[t])
		if ORIGINS.has(v.origin):
			_add(pool, 0.9, ORIGINS[v.origin])
	var m := v.mood
	if m >= 75.0:
		_add(pool, 1.0, ["Bugün içim rahat.", "Güzel bir gün."])
	elif m < 25.0:
		_add(pool, 2.0, ["Her şey üstüme geliyor.", "Daha ne kadar dayanırım bilmiyorum."])
	return _pick(pool, talk)


static func _add(pool: Array, w: float, lines: Array) -> void:
	for l: Variant in lines:
		pool.append([w / float(lines.size()), str(l)])


static func _pick(pool: Array, talk: FolkTalk) -> String:
	var total := 0.0
	for e: Array in pool:
		if talk == null or not talk.said_lately(str(e[1])):
			total += float(e[0])
	if total <= 0.0:
		return ""
	var r := randf() * total
	for e: Array in pool:
		if talk != null and talk.said_lately(str(e[1])):
			continue
		r -= float(e[0])
		if r <= 0.0:
			return str(e[1])
	return ""


## `name` with the genitive ending, as Turkish writes a name's: "Ivan'ın", "Olga'nın", "Pyotr'un".
static func gen(name: String) -> String:
	var low := name.to_lower()
	var last := ""
	for i in range(low.length() - 1, -1, -1):
		var ch := low[i]
		if ch in "aeıioöuü":
			last = ch
			break
	var suffix := "ın"
	match last:
		"e", "i":
			suffix = "in"
		"o", "u":
			suffix = "un"
		"ö", "ü":
			suffix = "ün"
	var ends_vowel := low.length() > 0 and low[low.length() - 1] in "aeıioöuü"
	return "%s'%s%s" % [name, "n" if ends_vowel else "", suffix]
