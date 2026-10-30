extends SceneTree
## Headless check of the sounds:
##   godot --headless --path . -s res://tests/sound_check.gd
## 1. Every sound a script names (res://assets/audio/..., the %d / %s ones every way they're filled in)
##    is there and loads.
## 2. The engine loops are each engine's (small, diesel, big), loop, and the machine's biggest engine
##    part picks which.
## 3. EngineSound's crossfade: at idle only the idle loop sounds, flat out only the top one, never more
##    than two at once, their pitch always within 0.6-1.6, and louder on the throttle than off it.

var _fail := PackedStringArray()


func _initialize() -> void:
	_paths()


var _ran := false


func _process(_dt: float) -> bool:
	if _ran:
		return true
	_ran = true
	_engine()
	if _fail.is_empty():
		print("sound_check: ALL PASS")
	else:
		for f in _fail:
			printerr("FAIL: ", f)
	quit(0 if _fail.is_empty() else 1)
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail.append(what)


func _paths() -> void:
	var re := RegEx.new()
	re.compile("res://assets/audio/[A-Za-z0-9_/%.]+\\.(wav|ogg)")
	var n := 0
	for f in DirAccess.get_files_at("res://scripts"):
		if not f.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string("res://scripts/" + f)
		for m in re.search_all(text):
			var p := m.get_string()
			if p.begins_with("res://assets/audio/engine/"):
				continue # (EngineSound's: the engine check below)
			var fills: Array[String] = [p]
			if p.contains("%s"):
				fills = [p.replace("%s", "metal"), p.replace("%s", "dirt")]
			for q in fills:
				if q.contains("%d"):
					var any := false
					for k in range(1, 5):
						var r := q.replace("%d", str(k))
						if ResourceLoader.exists(r):
							any = true
							_check(load(r) is AudioStream, "%s: %s doesn't load" % [f, r])
							n += 1
						elif k <= 2:
							_check(false, "%s: %s missing" % [f, r])
					_check(any, "%s: nothing for %s" % [f, q])
				else:
					_check(ResourceLoader.exists(q) and load(q) is AudioStream, "%s: %s missing" % [f, q])
					n += 1
	_check(n > 40, "only %d sounds found in the scripts" % n)
	print("sounds named in scripts: %d checked" % n)


func _engine() -> void:
	for k: String in EngineSound.SETS:
		for i in (EngineSound.SETS[k].hz as Array).size():
			var p := "res://assets/audio/engine/%s_%d.ogg" % [k, i]
			var s := load(p) as AudioStreamOggVorbis
			_check(s != null, "%s missing" % p)
			if s:
				_check(s.get_length() > 3.0, "%s too short (%.1f s)" % [p, s.get_length()])
	_check(EngineSound.kind_of([{"id": "wood_frame"}, {"id": "engine_s"}]) == "small", "engine_s isn't the small engine")
	_check(EngineSound.kind_of([{"id": "engine"}, {"id": "engine_s"}]) == "diesel", "engine and engine_s isn't the diesel")
	_check(EngineSound.kind_of([{"id": "engine"}, {"id": "engine_l"}]) == "big", "engine_l isn't the big one")
	_check(EngineSound.kind_of([{"id": "cab"}]) == "", "no engine still makes a sound")
	var m := Machine.new()
	m.design = [{"id": "engine"}]
	var e := EngineSound.new()
	root.add_child(e)
	e.play()
	var dt := 1.0 / 60.0
	e.update(m, 0.0, 0.0, 0.0, dt)
	_check(e.kind == "diesel" and e._players.size() == 4, "the diesel's four loops aren't there")
	for p in e._players:
		_check((p.stream as AudioStreamOggVorbis).loop, "an engine loop doesn't loop")
	_check(e._players[0].volume_db > -40.0 and e._players[3].volume_db <= -79.0, "at idle it isn't the idle loop")
	e.update(m, 1.0, 1.0, 0.0, dt)
	_check(e._players[3].volume_db > -40.0 and e._players[0].volume_db <= -79.0, "flat out it isn't the top loop")
	for r in 21:
		var rpm := r / 20.0
		e.update(m, rpm, 1.0, 0.0, dt)
		var on := 0
		var loud_on := -80.0
		for p in e._players:
			if p.volume_db > -79.0:
				on += 1
				_check(p.pitch_scale >= 0.6 and p.pitch_scale <= 1.6, "pitch %.2f at rpm %.2f" % [p.pitch_scale, rpm])
				loud_on = maxf(loud_on, p.volume_db)
		_check(on >= 1 and on <= 2, "%d loops at rpm %.2f" % [on, rpm])
		e.update(m, rpm, 0.0, 0.0, dt)
		var loud_off := -80.0
		for p in e._players:
			loud_off = maxf(loud_off, p.volume_db)
		_check(rpm < 0.35 or loud_on > loud_off + 1.0, "no louder on the throttle at rpm %.2f" % rpm)
	m.design = [{"id": "engine_l"}]
	e._scan = 0.0
	e.update(m, 0.5, 0.5, 0.0, dt)
	_check(e.kind == "big", "changing the engine part doesn't change the sound")
	e.stop()
	_check(not e.playing and not e._players[0].playing, "stop() doesn't stop it")
	e.queue_free()
	m.free()
