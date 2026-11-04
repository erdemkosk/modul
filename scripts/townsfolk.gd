class_name Townsfolk
extends Node3D
## A townsman's body: a skinned, rigged man (assets/townsfolk/townsman.glb, the Mud Run survivor
## with a MakeHuman head; the army kit hidden) dressed as the taiga dressed in the years of the war
## and after: a wool coat or a canvas smock, or an old army greatcoat (khaki, or the prisoners'
## blue-grey), canvas trousers, boots, a knit cap, a slouch hat or a fur hat, a beard more often than
## not. The deserters who come raiding wear what's left of their uniforms. It moves by motion-captured clips (walking, carrying, picking up, eating, talking,
## a torch, pushing; Quaternius' UAL, CC0) and, for the work no clip has (felling, the pick, the
## sickle, the saw, the hammer...), by Villager._animate's numbers turned onto the bones over the
## standing clip (TownsfolkPose).

const SCENE := "res://assets/townsfolk/townsman.glb"
const UAL := "res://assets/townsfolk/anims/ual.res"
const HEADS_DIR := "res://assets/townsfolk/heads/"
const FACE_SHADER := preload("res://shaders/face_skin.gdshader")

## Kept: what a man of the town wears. Everything else on the model (plate carriers, helmets,
## packs, patches) stays hidden.
const COATS := ["Survivor_Jacket", "Survivor_JacketSmock"]
const HATS := ["Survivor_Headwear", "Survivor_Boonie", "Survivor_Ushanka", ""]
const ALWAYS := ["Survivor_Body", "Survivor_Trousers", "Survivor_Boots"]

const WOOL := [Color("#5a4632"), Color("#3e4440"), Color("#6b2e26"), Color("#4a4f3a"), Color("#2f3646"),
	Color("#7a6a4f"), Color("#5d5a52"), Color("#3b2f28"), Color("#55402e")]
## Army cloth: Russian khaki and the prisoners' (Austro-Hungarian) blue-grey, worn thin, the
## greatcoats a good many brought with them out of the war.
const SURPLUS := [Color("#5b5a3c"), Color("#4e4d34"), Color("#66634a"), Color("#5a6470"), Color("#4c5560")]
const CANVAS := [Color("#4a3d30"), Color("#3a3a38"), Color("#5b5444"), Color("#2e3340"), Color("#6a5a44")]
const KNIT := [Color("#7a2f25"), Color("#4a4a46"), Color("#6b5a3e"), Color("#2f3a4a"), Color("#8a7a5c")]
const FELT := [Color("#4b3a2a"), Color("#3a332c"), Color("#5e4e3a"), Color("#2c2826")]
const SKINS := [Color("#e0ac8a"), Color("#d29a78"), Color("#c48a68"), Color("#a8714f")]
const HAIR := [Color("#2a1d14"), Color("#4a3322"), Color("#6b4a2e"), Color("#8a6a44"), Color("#1a1714"), Color("#7a3a1e")]
const BOOTS := [Color("#3e2a1c"), Color("#2a2420"), Color("#5a4330")]
const SCARF := [Color("#7a2f25"), Color("#5a5040"), Color("#3a4a5a"), Color("#8a7a5c")]
## A woman's kerchief (tied over the head and under the chin) and her long skirt.
const KERCHIEF := [Color("#9a2a22"), Color("#c8b48a"), Color("#3a4f7a"), Color("#6a2f4a"), Color("#d8d0bc"), Color("#4a6a3a")]
const SKIRT := [Color("#3a2f28"), Color("#2f3646"), Color("#4a3a30"), Color("#55402e"), Color("#2c2826"), Color("#5a4a3a")]
const WOMAN_KEYS := ["JawNarrow", "ChinWeak", "NoseSmall", "LipsFull", "Cheekbones", "Gaunt"]
## The skin textures by age and beard (heads/), each with its mean colour over the face.
const SKIN_TEX := {
	"young": ["skin_young_light.png", Color("#df997c")], "tan": ["skin_young_tan.png", Color("#d28059")],
	"middle": ["skin_middle_light.png", Color("#d1957a")], "middle_beard": ["skin_middle_beard.png", Color("#ba8f7a")],
	"old": ["skin_old_light.png", Color("#e29d7a")], "old_beard": ["skin_old_beard.png", Color("#b28b77")],
}
const HEADS := ["Head_Base", "Head_Broad", "Head_Old", "Head_Lean"]
const FACE_KEYS := ["JawWide", "JawNarrow", "ChinStrong", "ChinWeak", "Cheekbones", "BrowHeavy", "NoseBig",
	"NoseSmall", "NoseHooked", "NoseBroken", "Heavy", "Gaunt", "FaceLong", "LipsFull", "LipsThin"]

## The clips (at their natural ground speed, m/s, for those that walk).
const WALK_SPEED := 1.6
const JOG_SPEED := 3.5
const CARRY_SPEED := 1.4
## Played over and over though made to play once.
const LOOPED := ["PickUp", "Throw", "MeleeSwing", "Interact", "Repair", "ual/UalConsume", "ual/UalPush",
	"ual/UalInteract", "ual/UalPickUpTable", "ual/UalFixKneeling"]

static var _scene: PackedScene
static var _ual: AnimationLibrary
static var _textures := {}
static var _looped := false

var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var pose: TownsfolkPose
var grip_ik: TownsfolkGrip
var coat_material: StandardMaterial3D ## (flashed red when it's struck)
var _hands: Array[Node3D] = [] ## left, right: what's held hangs here, axes as the old arms had them
var _weapon_mount: Node3D
var _clip := ""
var _dead := false
var _lying := false


static func available() -> bool:
	return ResourceLoader.exists(SCENE)


## Built and dressed: `kind` "man", "woman", "child" or "outlaw" (a deserter of the bands), or a
## side's soldier: "merkez" (the Centre's khaki) or "kordal" (Free Kordal's dark coats and red);
## `rng` picks the clothes and the face.
func build(kind: String, rng: RandomNumberGenerator) -> void:
	if _scene == null:
		_scene = load(SCENE) as PackedScene
		_ual = load(UAL) as AnimationLibrary if ResourceLoader.exists(UAL) else null
	model = _scene.instantiate() as Node3D
	add_child(model)
	skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
	player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _ual and not player.has_animation_library(&"ual"):
		player.add_animation_library(&"ual", _ual)
	if not _looped:
		_looped = true
		for c: String in LOOPED:
			if player.has_animation(c):
				player.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	pose = TownsfolkPose.new()
	skeleton.add_child(pose)
	grip_ik = TownsfolkGrip.new()
	skeleton.add_child(grip_ik)
	_kind = kind
	_seed = rng.randi() % 97
	_dress(kind, rng)
	# A man's build varies: a little taller or shorter, broader or leaner (a woman smaller).
	var tall := rng.randf_range(0.94, 1.03) if kind != "woman" else rng.randf_range(0.9, 0.96)
	var broad := rng.randf_range(0.88, 0.98) if kind != "woman" else rng.randf_range(0.82, 0.88)
	model.scale = Vector3(broad, tall, broad)
	for side in ["Left", "Right"]:
		_hands.append(_grip(side + "Hand"))
	play("Idle")
	player.seek(rng.randf() * 3.0, true)


## A holder on a hand bone, turned the way a haft lies in a fist: its -y out past the thumb, the
## wrist a little cocked (so a tool's head stands up and forward of the hand), its -z the way the
## knuckles face (an axe's or a hoe's blade, a hammer's face, toward what's struck). The axes the
## tools and lanterns are made for (Villager._hold, arm_with).
func _grip(bone: String) -> Node3D:
	var b := skeleton.find_bone(bone)
	var at := BoneAttachment3D.new()
	at.bone_name = bone
	skeleton.add_child(at)
	var rest := skeleton.get_bone_global_rest(b)
	var thumb := skeleton.find_bone(bone.replace("Hand", "ThumbProximal"))
	# (in the hand's own frame y runs along the fingers; the thumb's side is across them)
	var radial := rest.basis.orthonormalized().inverse() * (skeleton.get_bone_global_rest(thumb).origin - rest.origin) if thumb >= 0 else Vector3.RIGHT
	radial.y = 0.0
	radial = radial.normalized() if radial.length() > 0.001 else Vector3.RIGHT
	var fingers := Vector3(0, 1, 0)
	var head := (radial + fingers * 0.8).normalized()
	var blade := (fingers - head * fingers.dot(head)).normalized()
	var y := -head
	var z := -blade
	var g := Node3D.new()
	g.basis = Basis(y.cross(z), y, z)
	g.position = Vector3(0, 0.08, 0) + radial * 0.02 # (in the fist)
	at.add_child(g)
	return g


## The left hand onto `marker` (a point on what the right hand holds), or let go (null).
func grip(marker: Node3D) -> void:
	if marker == null or not marker.is_inside_tree():
		grip_ik.on = false
		return
	var bone := _hands[1].get_parent() as Node3D # (the right hand's attachment: the bone's frame)
	grip_ik.hold = bone.global_transform.affine_inverse() * marker.global_transform
	grip_ik.on = true


## What a hand holds hangs from (0 left, 1 right).
func hand(i: int) -> Node3D:
	return _hands[i]


## A rifle's mount: the rifle's grip as the rifle clips hold it (barrel along -z).
func weapon_mount() -> Node3D:
	if _weapon_mount == null:
		var at := BoneAttachment3D.new()
		at.bone_name = "Weapon"
		skeleton.add_child(at)
		_weapon_mount = Node3D.new()
		at.add_child(_weapon_mount)
	return _weapon_mount


## The two sides' cloth, so a man can be told from above by his coat alone: the Centre's soldiers
## in khaki from cap to puttees, a leather belt and pouches; Free Kordal's in dark coats (whatever
## was to hand, dyed black or near it), a red band on the arm and a red rag at the neck.
const KHAKI := Color("#6b6844")
const KHAKI_DARK := Color("#55533a")
const KORDAL_COAT := [Color("#23201d"), Color("#2b2622"), Color("#1f2226")]
const KORDAL_RED := Color("#9a1c14")


func _dress(kind: String, rng: RandomNumberGenerator) -> void:
	var soldier := kind in ["merkez", "kordal"]
	var child := kind == "child"
	var outlaw := kind == "outlaw"
	var woman := kind == "woman"
	var age := 0.0 if child else rng.randf_range(0.05, 1.0)
	var beard := not child and not woman and rng.randf() < (0.8 if outlaw else 0.65)
	var mask := outlaw and rng.randf() < 0.5
	var coat: String = COATS[rng.randi() % COATS.size()]
	var hat: String = HATS[rng.randi() % HATS.size()]
	if outlaw:
		coat = "Survivor_Jacket" if rng.randf() < 0.7 else "Survivor_JacketSmock"
		mask = rng.randf() < 0.12
		hat = "" if mask else ("Survivor_Ushanka" if rng.randf() < 0.6 else "Survivor_Headwear")
	if mask:
		hat = ""
		beard = false
	if woman:
		hat = "Survivor_Headwear" # (the kerchief: the knit cap in its colours, the neckerchief the knot under the chin)
		coat = "Survivor_Jacket"
	var extra: Array[String] = [] ## (kit worn over the clothes: a belt and pouches, an armband)
	if soldier:
		mask = false
		coat = "Survivor_Jacket"
		extra.append("Survivor_BeltGear")
		if kind == "merkez":
			hat = "Survivor_PatrolCap" if rng.randf() < 0.75 else "Survivor_CapBack"
		else:
			hat = ["Survivor_Ushanka", "Survivor_CapBack", "Survivor_Headwear"][rng.randi() % 3]
			extra.append("Survivor_Armband")
	var scarf := outlaw or woman or kind == "kordal" or (not soldier and rng.randf() < 0.3)
	var gloves := not child and rng.randf() < 0.2
	var wool: Color = WOOL[rng.randi() % WOOL.size()]
	if outlaw:
		# (khaki gone dark with the woods, or a coat taken off someone)
		wool = (SURPLUS[rng.randi() % 3] if rng.randf() < 0.5 else WOOL[rng.randi() % WOOL.size()]).darkened(rng.randf_range(0.1, 0.3))
	elif not child and rng.randf() < 0.3:
		wool = SURPLUS[rng.randi() % SURPLUS.size()]
	var hair: Color = HAIR[rng.randi() % HAIR.size()]
	var grey := hair.lerp(Color(0.62, 0.6, 0.58), smoothstep(0.55, 1.0, age) * 0.7)
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	var hat_c: Color = (KNIT if hat == "Survivor_Headwear" else FELT)[rng.randi() % (KNIT if hat == "Survivor_Headwear" else FELT).size()]
	var trousers: Color = CANVAS[rng.randi() % CANVAS.size()]
	var boots: Color = BOOTS[rng.randi() % BOOTS.size()]
	var scarf_c: Color = SCARF[rng.randi() % SCARF.size()]
	if woman:
		hat_c = KERCHIEF[rng.randi() % KERCHIEF.size()]
		scarf_c = hat_c
		trousers = SKIRT[rng.randi() % SKIRT.size()]
	if kind == "merkez":
		wool = KHAKI.darkened(rng.randf_range(0.0, 0.12))
		trousers = KHAKI_DARK.darkened(rng.randf_range(0.0, 0.1))
		hat_c = KHAKI_DARK
	elif kind == "kordal":
		wool = KORDAL_COAT[rng.randi() % KORDAL_COAT.size()]
		trousers = Color("#2a2a2a").lightened(rng.randf_range(0.0, 0.08))
		hat_c = Color("#1e1c1a")
		scarf_c = KORDAL_RED
	var patch := wool.darkened(0.06)
	var trouser_patch := trousers.darkened(0.17)
	if outlaw:
		scarf_c = [Color("#4a4236"), Color("#1c1a18"), Color("#3a2e24"), Color("#5a5040")][rng.randi() % 4] # (rags: never the red, that's Kordal's)
		trousers = (SURPLUS[rng.randi() % 3] if rng.randf() < 0.6 else CANVAS[rng.randi() % CANVAS.size()]).darkened(0.3)
		hat_c = SURPLUS[rng.randi() % 3].darkened(0.2)
		# what's left of a uniform, ragged: patched with whatever cloth came to hand, the knees out
		patch = WOOL[rng.randi() % WOOL.size()].lightened(0.08)
		trouser_patch = CANVAS[rng.randi() % CANVAS.size()].lightened(0.12)
	var colours := {
		"Jacket": wool, "JacketDark": wool.darkened(0.2), "Patch": patch,
		"Trousers": trousers, "TrouserPatch": trouser_patch,
		"Boot": boots, "Leather": boots.lightened(0.08), "Glove": Color("#6a4a33"), "GloveDark": Color("#4e3626"),
		"Skin": skin, "Beanie": hat_c, "Boonie": hat_c, "BoonieDark": hat_c.darkened(0.3),
		"UshankaTop": Color("#4a3426"), "LeatherBand": Color("#3a2a1e"),
		"Scarf": scarf_c, "Hoodie": scarf_c.darkened(0.25), "Balaclava": Color("#2a2826"),
		"HeadBrow": grey.darkened(0.2), "HeadBrowHeavy": grey.darkened(0.15), "HeadLash": hair.darkened(0.3),
		"HeadBeard": grey, "HeadMoustache": grey,
		"FieldCap": hat_c, "FieldCapDark": hat_c.darkened(0.3), "Badge": Color("#8a6a2a"),
		"Webbing": Color("#4a3322"), "Metal": Color("#5a5650"), "PackDark": Color("#3a2a1e"), "Handle": Color("#3a2a1e"),
		"HiVis": KORDAL_RED, "Reflect": KORDAL_RED.darkened(0.2), "PatchWhite": KORDAL_RED, "PatchMark": KORDAL_RED.darkened(0.35),
	}
	var head: String = HEADS[rng.randi() % HEADS.size()] if not child else "Head_Base"
	if age > 0.8 and rng.randf() < 0.6:
		head = "Head_Old"
	var keys := {}
	for k in 3:
		if woman:
			keys[WOMAN_KEYS[rng.randi() % WOMAN_KEYS.size()]] = rng.randf_range(0.35, 0.8)
		else:
			keys[FACE_KEYS[rng.randi() % FACE_KEYS.size()]] = rng.randf_range(0.15, 0.6)
	if woman:
		head = "Head_Lean" if rng.randf() < 0.6 else "Head_Base"
	if head == "Head_Old" or age > 0.85:
		keys["Old"] = rng.randf_range(0.4, 1.0)
	var heavy_brows := not woman and rng.randf() < 0.35
	var beard_cut: Array = [[0.3, 0.32], [2.0, 0.3], [0.52, 0.4]][rng.randi() % 3]
	for node in model.find_children("Survivor_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var n := String(mi.name)
		var show := n in ALWAYS or n == coat or n == hat or n in extra
		match n:
			"Survivor_Beard":
				show = beard
			"Survivor_Neckwear":
				show = scarf
			"Survivor_Gloves":
				show = gloves
			"Survivor_Hands":
				show = not gloves
			"Survivor_Balaclava":
				show = mask
		mi.visible = show
		if not show:
			continue
		# (small things not worth drawing from far off)
		if n in ["Survivor_Beard", "Survivor_Hands", "Survivor_Gloves", "Survivor_Neckwear"]:
			mi.visibility_range_end = 70.0
		var mesh := mi.mesh
		for b in mesh.get_blend_shape_count():
			var key := String(mesh.get_blend_shape_name(b))
			var v := float(keys.get(key, 0.0))
			if key.begins_with("Head_"):
				v = 1.0 if key == head else 0.0
			elif key == "Layer":
				v = 0.0
			mi.set_blend_shape_value(b, v)
		for s in mesh.get_surface_count():
			var base := mesh.surface_get_material(s) as BaseMaterial3D
			if base == null:
				continue
			var name := base.resource_name
			if name == "HeadSkin":
				mi.set_surface_override_material(s, _face(age, beard, skin, hair, rng))
				continue
			if not colours.has(name):
				continue
			var m := base.duplicate() as StandardMaterial3D
			m.albedo_color = colours[name]
			if name in ["HeadBeard", "HeadMoustache"]:
				m.alpha_scissor_threshold = beard_cut[0 if name == "HeadBeard" else 1]
			elif name in ["HeadBrow", "HeadBrowHeavy", "HeadLash"]:
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				if name != "HeadLash":
					m.albedo_color.a = 1.0 if heavy_brows == (name == "HeadBrowHeavy") else 0.0
			mi.set_surface_override_material(s, m)
			if name == "Jacket":
				coat_material = m
	if woman:
		_skirt(trousers)


## The fur hat and the scarf for the winter (a woman's kerchief stays): the summer's hat put away.
## One of the militia wears a soldier's field cap in place of his own (not over a fur hat in the
## winter) and a leather belt with its pouches: told from the others from above, nothing more.
var _summer := {} ## mesh name -> visible, as dressed
var _kind := ""
var _winter := false
var _militia := false


func set_winter(on: bool) -> void:
	_winter = on
	_refit()


func set_militia(on: bool) -> void:
	if on == _militia:
		return
	_militia = on
	_refit()


func _refit() -> void:
	if model == null or _kind in ["outlaw", "merkez", "kordal"]:
		return
	var man := _kind != "woman"
	for node in model.find_children("Survivor_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var n := String(mi.name)
		if not _summer.has(n):
			_summer[n] = mi.visible
		var vis := mi.visible
		if n in HATS and n != "":
			if not man:
				continue
			vis = (n == "Survivor_Ushanka") if _winter else (bool(_summer[n]) and not _militia)
		elif n == "Survivor_PatrolCap":
			vis = man and _militia and not _winter
		elif n == "Survivor_BeltGear":
			vis = _militia
		elif n == "Survivor_Neckwear":
			if not man:
				continue
			vis = _winter or bool(_summer[n])
		else:
			continue
		mi.visible = vis
		if not vis or mi.has_meta("kitted"):
			continue
		mi.set_meta("kitted", true)
		# (first worn: coloured as a man of the town would have it)
		_colour(mi, {"UshankaTop": Color("#4a3426"), "LeatherBand": Color("#3a2a1e"), "Fur": Color("#5a4632"),
			"FieldCap": Color("#4f5240"), "FieldCapDark": Color("#3a3c30"), "Badge": Color("#7a5a26"),
			"Leather": Color("#4a3322"), "Webbing": Color("#4a3322"), "Metal": Color("#5a5650"), "PackDark": Color("#3a2a1e"), "Handle": Color("#3a2a1e")})


## Each of `mi`'s surfaces with a colour in `colours` (by its material's name) painted so.
func _colour(mi: MeshInstance3D, colours: Dictionary) -> void:
	for s in mi.mesh.get_surface_count():
		var base := mi.mesh.surface_get_material(s) as BaseMaterial3D
		if base == null or not colours.has(base.resource_name):
			continue
		var m := base.duplicate() as StandardMaterial3D
		m.albedo_color = colours[base.resource_name]
		mi.set_surface_override_material(s, m)


## A long skirt to the ankles, hung from the hips: a cone of wool over the trousers.
func _skirt(c: Color) -> void:
	var at := BoneAttachment3D.new()
	at.bone_name = "Hips"
	skeleton.add_child(at)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.19
	cm.bottom_radius = 0.33
	cm.height = 0.78
	cm.radial_segments = 14
	cm.cap_top = false
	cm.cap_bottom = false
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	at.add_child(mi)
	# (the hips' bone points up the spine: the skirt hangs down from it, in the model's own scale)
	var hips := skeleton.get_bone_global_rest(skeleton.find_bone("Hips"))
	var down := hips.basis.inverse() * Vector3.DOWN
	mi.position = down.normalized() * 0.36
	mi.basis = Basis(Quaternion(Vector3.DOWN, down.normalized())) if down.normalized().dot(Vector3.DOWN) < 0.999 else Basis.IDENTITY


func _face(age: float, beard: bool, skin: Color, hair: Color, rng: RandomNumberGenerator) -> ShaderMaterial:
	var which := "young" if age < 0.3 else ("middle" if age < 0.75 else "old")
	if beard and age >= 0.3:
		which += "_beard"
	elif age < 0.3 and rng.randf() < 0.4:
		which = "tan"
	var m := ShaderMaterial.new()
	m.shader = FACE_SHADER
	m.set_shader_parameter("mask_tex", _tex("head_mask.png"))
	m.set_shader_parameter("normal_tex", _tex("skin_normal.png"))
	m.set_shader_parameter("rough_tex", _tex("skin_rough.png"))
	var e: Array = SKIN_TEX[which]
	m.set_shader_parameter("skin_tex", _tex(e[0]))
	m.set_shader_parameter("tex_mean", e[1])
	m.set_shader_parameter("tint", skin)
	m.set_shader_parameter("hair_color", hair)
	m.set_shader_parameter("age", age)
	m.set_shader_parameter("stubble", 0.0 if age < 0.05 else rng.randf_range(0.3, 0.9))
	m.set_shader_parameter("beard", 1.0 if beard else 0.0)
	return m


static func _tex(file: String) -> Texture2D:
	if not _textures.has(file):
		_textures[file] = load(HEADS_DIR + file)
	return _textures[file]


var cold := false ## (set by the villager: in the cold, the arms are folded more often)
var _seed := 0


## Standing about: mostly the plain stand, now and then the arms folded (often in the cold).
func _idle_clip() -> String:
	var beat := int(Time.get_ticks_msec() / 7000 + _seed) % 6
	if cold:
		return "ual/UalIdleFoldArms" if beat != 0 else "Idle"
	return "ual/UalIdleFoldArms" if beat == 3 else "Idle"


func play(clip: String, speed := 1.0, blend := 0.25) -> void:
	if _dead:
		return
	if not player.has_animation(clip):
		clip = "Idle"
	if clip != _clip:
		_clip = clip
		player.play(clip, blend)
	player.speed_scale = speed


## Struck and still on its feet: a short jerk back (`clip`, HitReact or RifleHit), played through
## over whatever it was doing, then back to it.
var _flinch_t := 0


func flinch(clip: String) -> void:
	if _dead or _lying or not player.has_animation(clip):
		return
	_flinch_t = Time.get_ticks_msec() + 450
	_clip = clip
	player.play(clip, 0.06)
	player.seek(0.05, true)
	player.speed_scale = 1.5


## Moves for `anim` (Villager._anim): a clip, and over it (for the work no clip has) the numbers
## Villager._animate worked out. `speed` is how fast it's going over the ground, `rate` the game's.
func drive(anim: String, walking: bool, speed: float, rate: float, carrying: String, vehicle: String,
		armed: bool, v: Dictionary) -> void:
	if _lying or Time.get_ticks_msec() < _flinch_t:
		return
	var clip := "Idle"
	var pace := rate
	var procedural := false
	if walking:
		var real := speed / maxf(rate, 0.01)
		if carrying in ["tas", "yiyecek", "su", "camur", "kerpic", "tufek"] or vehicle == "hand":
			clip = "CarryBoxWalk"
			pace = speed / CARRY_SPEED
		elif armed:
			clip = "RifleWalk" if real < 2.6 else "RifleJog"
			pace = speed / (WALK_SPEED if real < 2.6 else JOG_SPEED)
		elif real < 2.6:
			clip = "Walk"
			pace = speed / WALK_SPEED
		else:
			clip = "Jog"
			pace = speed / JOG_SPEED
		procedural = carrying in ["odun", "yarali"] or vehicle == "ox"
	else:
		match anim:
			"idle", "look", "stretch":
				clip = "RifleIdle" if armed else _idle_clip()
				procedural = anim != "idle"
			"chat":
				# (talking with the hands, now and then a nod or a shake of the head)
				var beat := int(Time.get_ticks_msec() / 6000 + _seed) % 5
				clip = ["ual/UalIdleTalking", "ual/UalIdleTalking", "SoldierTalk", "ual/UalIdleNo", "ual/UalIdleTalking"][beat]
			"listen":
				# (hearing the other out: standing easy or the arms folded, nodding now and then)
				clip = "ual/UalIdleFoldArms" if (_seed % 3 == 0 or cold) and pose.seat < 0.0 else "Idle"
			"sit", "fish", "whittle", "pipe", "warm", "pray", "wash", "drink":
				# (the work no clip has, at one's ease: the numbers over the plain stand, the legs
				# sat if there's a seat)
				clip = "Idle"
				procedural = true
			"eat":
				clip = "ual/UalConsume"
			"gather", "draw":
				clip = "PickUp"
			"throw":
				clip = "Throw"
			"strike":
				clip = "MeleeSwing"
			"aim":
				clip = "RifleAim"
			"torch":
				clip = "ual/UalIdleTorch"
			"push":
				clip = "ual/UalPush"
			_:
				clip = "Idle"
				procedural = true
	if side_step != "" and not walking:
		# shouldered aside where it stands: a step or two that way, the feet going with it
		clip = side_step
		pace = side_pace
		procedural = false
	pose.nod = 1.0 if anim == "listen" else 0.0
	pose.bow = 1.0 if anim == "pray" else 0.0
	play(clip, pace)
	pose.want(v if procedural else {}, rate)


## (Villager: shouldered aside while standing, the step's clip, WalkLeft and so on, and its pace)
var side_step := ""
var side_pace := 1.0


## Sat down on a seat `seat` m up from where its feet are (a lorry's bench, a stump), the hands on
## the knees, and left so: for the men riding in a lorry, not driven by a villager's moves.
func sit(seat := 0.45, speed := 1.0) -> void:
	pose.seat = seat
	play("Idle", speed, 0.0)
	pose.want({"arm_l": -0.55, "arm_r": -0.5, "el": 0.8, "er": 0.75, "lean": 0.12, "kn": 0.05}, 1.0)


## Down, wounded: the fall, then lying there.
func lie() -> void:
	_lying = true
	pose.seat = -1.0
	side_step = ""
	_clip = "Death"
	player.play("Death", 0.15)
	player.speed_scale = 1.0
	pose.want({}, 1.0)


func stand() -> void:
	_lying = false
	_clip = ""
	play("Idle")


func die() -> void:
	play("Death", 1.0, 0.15)
	_dead = true
	pose.want({}, 1.0)
