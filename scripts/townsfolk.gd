class_name Townsfolk
extends Node3D
## A townsman's body: a skinned, rigged man (assets/townsfolk/townsman.glb, the Mud Run survivor
## with a MakeHuman head; all his own kit put away but the head and hands) dressed as the taiga
## dressed in 1918, in clothes made in Blender like the buildings and skinned to his bones
## (assets/townsfolk/kit.glb, tools/blender/build_villagers.py): a linen shirt belted with a cord
## or a quilted jacket, an army tunic or greatcoat brought home, in the winter the sheepskin coat;
## wool trousers, boots, bast shoes and leg wraps, felt boots; a peaked cap, a fur hat; a woman's
## blouse, long skirt and apron, her kerchief, her winter shawl; a beard more often than not. The
## sides' soldiers in their uniforms, the deserters who come raiding in what's left of theirs. It moves by motion-captured clips (walking, carrying, picking up, eating, talking,
## a torch, pushing; Quaternius' UAL, CC0) and, for the work no clip has (felling, the pick, the
## sickle, the saw, the hammer...), by Villager._animate's numbers turned onto the bones over the
## standing clip (TownsfolkPose).

const SCENE := "res://assets/townsfolk/townsman.glb"
const UAL := "res://assets/townsfolk/anims/ual.res"
const HEADS_DIR := "res://assets/townsfolk/heads/"
const FACE_SHADER := preload("res://shaders/face_skin.gdshader")

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
	"ual/UalInteract", "ual/UalPickUpTable", "ual/UalFixKneeling", "TurnInPlace", "RifleTurnInPlace", "CarryBoxIdle",
	"CarrySideIdle", "CarrySideWalk", "CarryBoxWalk"]

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
## in khaki from cap to boots, a peaked cap with a cockade, a leather belt and pouches; Free
## Kordal's in dark coats (whatever was to hand, dyed black or near it), the pointed cloth helmet
## with its red star, a red band on the arm and a red rag at the neck.
const KHAKI := Color("#6b6844")
const KHAKI_DARK := Color("#55533a")
const KHAKI_COAT := Color("#6a6650")
const KORDAL_COAT := [Color("#23201d"), Color("#2b2622"), Color("#2a2724")]
const KORDAL_RED := Color("#9a1c14")

## The clothes (assets/townsfolk/kit.glb, tools/blender/build_villagers.py): skinned to this same
## skeleton, each piece dyed per person by its materials' names.
const KIT := "res://assets/townsfolk/kit.glb"
## Every Survivor_ piece but the head and the hands is put away when the kit is worn.
const KEEP := ["Survivor_Body", "Survivor_Hands", "Survivor_Gloves"]

## The cloth of the town, cold and worn: bleached and unbleached linen, a madder red gone pale,
## undyed wool and wool dyed with bark, the army's khaki and grey brought home from the war.
const LINEN := [Color("#c4bca8"), Color("#b5ab94"), Color("#a69a7e"), Color("#7e5446"), Color("#7e7a70"), Color("#957c52"), Color("#bab4a6")]
const WOOL := [Color("#5a4632"), Color("#3e4440"), Color("#4a4f3a"), Color("#6b5e4a"), Color("#5d5a52"), Color("#3b2f28"),
	Color("#55402e"), Color("#46423a"), Color("#6b2e26")]
const SURPLUS := [Color("#5b5a3c"), Color("#4e4d34"), Color("#66634a"), Color("#6a6a62"), Color("#5c5a54")]
const HIDE := [Color("#b89a6e"), Color("#a5835a"), Color("#c4aa80"), Color("#8a6a48"), Color("#9c7c56")]
const FLEECE := [Color("#e0d6c2"), Color("#cfc2a8"), Color("#d8cdb6"), Color("#8a7458")]
const FUR := [Color("#2a221c"), Color("#4a3a2c"), Color("#5e4a36"), Color("#3a302a"), Color("#6a5a48")]
const TROUSERS := [Color("#3a3a36"), Color("#4a3d30"), Color("#5b5444"), Color("#2c2a26"), Color("#6a5a44"), Color("#55524a")]
const FELT := [Color("#d8d2c4"), Color("#bdb5a5"), Color("#7a7268"), Color("#4a4440"), Color("#5e544a")]
const LEATHER := [Color("#2a2420"), Color("#3e2a1c"), Color("#1c1a18"), Color("#4a3322")]
const CAP := [Color("#2c2a26"), Color("#3a3631"), Color("#4a4238"), Color("#3b3a30")]
const EMBROIDERY := [Color("#a3352a"), Color("#8a2a22"), Color("#b04a30"), Color("#3a3028")]
const SKINS := [Color("#e0ac8a"), Color("#d29a78"), Color("#c48a68"), Color("#a8714f")]
const HAIR := [Color("#2a1d14"), Color("#4a3322"), Color("#6b4a2e"), Color("#8a6a44"), Color("#1a1714"), Color("#7a3a1e"), Color("#a08a64")]
## A woman's kerchief, her skirt and apron, her winter shawl.
const KERCHIEF := [Color("#8a2e26"), Color("#b4a27e"), Color("#5e3444"), Color("#c4bca8"), Color("#4a5440"), Color("#94602e"), Color("#cfcabd")]
const SKIRT := [Color("#3a2f28"), Color("#4a3a30"), Color("#55402e"), Color("#2c2826"), Color("#5a4a3a"), Color("#6a2a24"), Color("#4a4a3a")]
const APRON := [Color("#c4bca8"), Color("#b5ab94"), Color("#ccc6b6"), Color("#a69a7e")]
const SHAWL := [Color("#8a7a5c"), Color("#5a4a3a"), Color("#c8bca4"), Color("#6a2a24"), Color("#4a4238"), Color("#9a8a6a")]
const RAG := [Color("#4a4236"), Color("#1c1a18"), Color("#3a2e24"), Color("#5a5040")] ## (an outlaw's: never the red, that's Kordal's)
const WOMAN_KEYS := ["JawNarrow", "ChinWeak", "NoseSmall", "LipsFull", "Cheekbones", "Gaunt"]

static var _kit := {} ## piece -> [mesh, kit skin]
static var _kit_skins := {} ## piece -> the skin rebound to the townsman's own rest
static var _mats := {} ## "material:colour" -> a shared material

var _summer: Array = [] ## [piece, {material: colour}] worn out of the winter
var _winter_fit: Array = [] ## ... and in it
var _militia_fit: Array = [] ## what a man of the militia puts on over his own
var _worn: Array[MeshInstance3D] = []
var _blend := {} ## the face's blend shapes (the head's and what sits on it)
var _kind := ""
var _winter := false
var _militia := false
var _girl := false


func _dress(kind: String, rng: RandomNumberGenerator) -> void:
	_girl = kind == "girl"
	if _girl:
		kind = "child"
	_kind = kind
	var soldier := kind in ["merkez", "kordal"]
	var child := kind == "child"
	var outlaw := kind == "outlaw"
	var woman := kind == "woman"
	var age := 0.0 if child else rng.randf_range(0.05, 1.0)
	var beard := not child and not woman and rng.randf() < (0.8 if outlaw else 0.65)
	var hair: Color = HAIR[rng.randi() % HAIR.size()]
	var grey := hair.lerp(Color(0.62, 0.6, 0.58), smoothstep(0.55, 1.0, age) * 0.7)
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	var gloves := not child and not woman and rng.randf() < 0.15
	# the face
	var head: String = HEADS[rng.randi() % HEADS.size()] if not child else "Head_Base"
	if age > 0.8 and rng.randf() < 0.6:
		head = "Head_Old"
	var keys := {}
	for k in 3:
		if woman or _girl:
			keys[WOMAN_KEYS[rng.randi() % WOMAN_KEYS.size()]] = rng.randf_range(0.35, 0.8)
		else:
			keys[FACE_KEYS[rng.randi() % FACE_KEYS.size()]] = rng.randf_range(0.15, 0.6)
	if woman:
		head = "Head_Lean" if rng.randf() < 0.6 else "Head_Base"
	if head == "Head_Old" or age > 0.85:
		keys["Old"] = rng.randf_range(0.4, 1.0)
	keys[head] = 1.0
	_blend = keys
	var heavy_brows := not woman and not child and rng.randf() < 0.35
	# (the walk goes with it: the old stooped, a woman's sway, a child's skip)
	pose.age = age
	pose.female = woman or _girl
	pose.child = child
	# the clothes, summer and winter, chosen now (so the same each time the seed is built)
	_summer = _outfit(kind, false, rng, grey, age, beard)
	_winter_fit = _outfit(kind, true, rng, grey, age, beard)
	var torso_s := str(_summer[0][0])
	var belt := "belt_kit_thin" if torso_s in ["shirt", "tunic", "smock", "blouse"] else "belt_kit"
	_militia_fit = [["furazhka", {"Cloth": Color("#4f5240"), "Band": Color("#2e2c26"), "Sole": Color("#1c1a18"), "Metal": Color("#8a6a2a")}],
		[belt, {"Leather": Color("#4a3322"), "Metal": Color("#6a6050")}]]
	var colours := {"Skin": skin, "Glove": Color("#6a4a33"), "GloveDark": Color("#4e3626"),
		"HeadBrow": grey.darkened(0.2), "HeadBrowHeavy": grey.darkened(0.15), "HeadLash": hair.darkened(0.3)}
	for node in model.find_children("Survivor_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var n := String(mi.name)
		var show := n in KEEP and (n != "Survivor_Gloves" or gloves) and (n != "Survivor_Hands" or not gloves)
		mi.visible = show
		if not show:
			continue
		if n in ["Survivor_Hands", "Survivor_Gloves"]:
			mi.visibility_range_end = 70.0
		_shape(mi)
		var mesh := mi.mesh
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
			if name in ["HeadBrow", "HeadBrowHeavy", "HeadLash"]:
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				if name != "HeadLash":
					m.albedo_color.a = 1.0 if heavy_brows == (name == "HeadBrowHeavy") else 0.0
			mi.set_surface_override_material(s, m)
	_winter = Weather.snow_cover_now > 0.3 # (a body built in the winter comes dressed for it)
	_wear()


## A blend shape per key in `_blend` (the head chosen, the face's own), on `mi`.
func _shape(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	for b in mesh.get_blend_shape_count():
		var key := String(mesh.get_blend_shape_name(b))
		mi.set_blend_shape_value(b, 0.0 if key == "Layer" else float(_blend.get(key, 0.0)))


func _pick(list: Array, rng: RandomNumberGenerator) -> Color:
	return list[rng.randi() % list.size()]


## What `kind` wears in the summer or the winter: [[piece, {material: colour}], ...], the coat (or
## the shirt) first. Each call takes the same draws from `rng` whatever it chooses.
func _outfit(kind: String, winter: bool, rng: RandomNumberGenerator, hair: Color, age: float, beard: bool) -> Array:
	var r: Array[float] = [rng.randf(), rng.randf(), rng.randf(), rng.randf(), rng.randf(), rng.randf()]
	var wool := _pick(WOOL, rng)
	var linen := _pick(LINEN, rng)
	var trousers := _pick(TROUSERS, rng)
	var leather := _pick(LEATHER, rng)
	var felt := _pick(FELT, rng)
	var hide := _pick(HIDE, rng)
	var fleece := _pick(FLEECE, rng)
	var fur := _pick(FUR, rng)
	var cap := _pick(CAP, rng)
	var trim := _pick(EMBROIDERY, rng)
	var kerchief := _pick(KERCHIEF, rng)
	var skirt := _pick(SKIRT, rng)
	var apron := _pick(APRON, rng)
	var shawl := _pick(SHAWL, rng)
	var surplus := _pick(SURPLUS, rng)
	var rag := _pick(RAG, rng)
	var sash := _pick([Color("#8a2a22"), Color("#5a4a32"), Color("#6a5a3a"), Color("#3a3028")], rng)
	var out: Array = []
	var feet := ""
	var legs := "trousers"
	var on_head := ""
	var head_c := {}
	var brass := Color("#8a6a2a")
	var buttons := Color("#2a2420")
	var shirt := {"Cloth": linen, "Trim": trim, "Belt": sash, "Metal": Color("#c8c0ac")}
	var padded := {"Cloth": wool.darkened(0.1), "ClothDark": wool.darkened(0.3), "Button": buttons}
	var shinel := {"Cloth": surplus, "ClothDark": surplus.darkened(0.15), "Metal": brass, "Leather": leather.lightened(0.1)}
	var tulup := {"Hide": hide, "Fur": fleece, "Belt": sash}
	match kind:
		"man", "outlaw":
			if winter:
				out.append(["tulup", tulup] if r[0] < 0.35 else (["shinel", shinel] if r[0] < 0.6 else ["padded", padded]))
				feet = "valenki" if r[1] < 0.65 else "boots"
				on_head = "ushanka" if r[2] < 0.55 else "papakha"
			else:
				if r[0] < 0.55:
					out.append(["shirt", shirt])
				elif r[0] < 0.75:
					out.append(["padded", padded])
				elif r[0] < 0.9:
					out.append(["tunic", {"Cloth": surplus, "Leather": leather.lightened(0.1), "Metal": brass}])
				else:
					out.append(["shinel", shinel])
				feet = "boots" if r[1] < 0.6 else "lapti"
				on_head = "kartuz" if r[2] < 0.5 else ("" if r[2] < 0.78 else ("papakha" if r[2] < 0.9 else "ushanka"))
			if kind == "outlaw":
				# what's left of a uniform, gone dark with the woods; a rag at the neck
				for e: Array in out:
					var c: Dictionary = (e[1] as Dictionary).duplicate()
					for k: String in c:
						if k in ["Cloth", "ClothDark", "Hide"]:
							c[k] = (c[k] as Color).darkened(0.25)
					e[1] = c
				if r[3] < 0.6:
					out.append(["neck_rag", {"Cloth": rag}])
				if on_head == "kartuz" or on_head == "":
					on_head = "ushanka" if r[4] < 0.5 else "papakha"
				feet = "boots"
			if feet == "lapti":
				legs = "trousers_long"
			head_c = {"Cloth": cap, "ClothDark": cap.darkened(0.2), "Leather": Color("#1c1a18"), "Fur": fur, "Top": cap, "Trim": cap.darkened(0.3)}
		"woman":
			if winter:
				var long_coat := {"Cloth": wool, "ClothDark": wool.darkened(0.2), "Metal": buttons, "Leather": sash}
				out.append(["tulup", tulup] if r[0] < 0.45 else (["padded", padded] if r[0] < 0.75 else ["shinel", long_coat]))
				out.append(["skirt", {"Cloth": skirt, "Trim": skirt.darkened(0.3), "ClothDark": skirt.darkened(0.2)}])
				on_head = "shawl_head"
				head_c = {"Cloth": shawl, "Trim": shawl.darkened(0.25)}
				feet = "valenki"
			else:
				out.append(["blouse", {"Cloth": linen if r[0] < 0.6 else linen.lerp(Color("#d8d0bc"), 0.6), "Trim": trim}])
				out.append(["skirt", {"Cloth": skirt, "Trim": skirt.darkened(0.3), "ClothDark": skirt.darkened(0.2)}])
				if r[1] < 0.6:
					out.append(["apron", {"Apron": apron}])
				if r[3] < 0.3:
					out.append(["shawl", {"Cloth": shawl, "Trim": shawl.darkened(0.25)}])
				on_head = "kerchief"
				head_c = {"Cloth": kerchief}
				feet = "boots" if r[2] < 0.7 else "lapti"
			legs = ""
		"child":
			if winter:
				out.append(["tulup", tulup] if r[0] < 0.5 else ["padded", padded])
				feet = "valenki"
				on_head = "shawl_head" if _girl else "ushanka"
				head_c = {"Cloth": shawl, "Trim": shawl.darkened(0.25)} if _girl else {"Cloth": cap, "Fur": fur}
			else:
				out.append(["smock", shirt])
				feet = "lapti" if r[1] < 0.6 else "boots"
				on_head = "kerchief" if _girl else ("kartuz" if r[2] < 0.35 else "")
				head_c = {"Cloth": kerchief} if _girl else {"Cloth": cap, "ClothDark": cap.darkened(0.2), "Leather": Color("#1c1a18")}
			if _girl and not winter:
				out.append(["skirt", {"Cloth": skirt, "Trim": skirt.darkened(0.3), "ClothDark": skirt.darkened(0.2)}])
				legs = ""
			elif feet == "lapti":
				legs = "trousers_long"
		"merkez":
			var kh := KHAKI.darkened(r[5] * 0.12)
			if winter:
				out.append(["shinel", {"Cloth": KHAKI_COAT.darkened(r[5] * 0.1), "ClothDark": KHAKI_DARK, "Metal": brass, "Leather": Color("#4a3322")}])
				out.append(["belt_kit", {"Leather": Color("#4a3322"), "Metal": Color("#6a6050")}])
				on_head = "papakha" if r[2] < 0.5 else "ushanka"
				head_c = {"Fur": Color("#5e5648") if r[3] < 0.5 else Color("#2a221c"), "Top": KHAKI_DARK, "Trim": brass, "Cloth": KHAKI_DARK}
				feet = "valenki" if r[1] < 0.4 else "boots"
			else:
				out.append(["tunic", {"Cloth": kh, "Leather": Color("#4a3322"), "Metal": brass}])
				out.append(["belt_kit_thin", {"Leather": Color("#4a3322"), "Metal": Color("#6a6050")}])
				on_head = "furazhka"
				head_c = {"Cloth": KHAKI_DARK, "Band": Color("#2e2c26"), "Sole": Color("#1c1a18"), "Metal": brass}
				feet = "boots"
			trousers = KHAKI_DARK.darkened(r[4] * 0.1)
			leather = Color("#2a2420")
		"kordal":
			var coat: Color = KORDAL_COAT[int(r[5] * 3) % 3]
			if winter:
				out.append(["shinel", {"Cloth": coat, "ClothDark": coat.darkened(0.2), "Metal": Color("#5a5650"), "Leather": Color("#2a2420")}] if r[0] < 0.6 else
					["tulup", {"Hide": Color("#4a3a2c"), "Fur": Color("#2a221c"), "Belt": KORDAL_RED}])
				out.append(["armband_wide", {"Star": KORDAL_RED}])
				out.append(["belt_kit" if r[0] < 0.6 else "belt_kit_wide", {"Leather": Color("#2a2420"), "Metal": Color("#5a5650")}])
				feet = "valenki" if r[1] < 0.5 else "boots"
			else:
				out.append(["padded", {"Cloth": coat, "ClothDark": coat.darkened(0.2), "Button": Color("#1a1816")}])
				out.append(["armband", {"Star": KORDAL_RED}])
				out.append(["belt_kit", {"Leather": Color("#2a2420"), "Metal": Color("#5a5650")}])
				feet = "boots"
			out.append(["neck_rag", {"Cloth": KORDAL_RED}])
			on_head = "budenovka" if (winter or r[2] < 0.6) else "kartuz"
			head_c = {"Cloth": Color("#2e2b27"), "ClothDark": Color("#262420"), "Metal": Color("#5a5650"), "Star": KORDAL_RED, "Leather": Color("#1c1a18")}
			trousers = Color("#2a2a2a").lightened(r[4] * 0.08)
			legs = "trousers"
	if legs != "":
		out.append([legs, {"Cloth": trousers}])
	match feet:
		"boots":
			out.append(["boots", {"Leather": leather, "Sole": Color("#1a1614")}])
		"valenki":
			out.append(["valenki", {"Felt": felt}])
		"lapti":
			out.append(["lapti", {"Linen": Color("#cfc5ad"), "Bast": Color("#b39a62")}])
	if on_head != "":
		out.append([on_head, head_c])
	if kind in ["man", "outlaw", "merkez", "kordal"]:
		var bald := age > 0.7 and r[4] < 0.35
		if not bald:
			out.append(["hair", {"Hair": hair}])
		# (a beard a shade lighter than the hair, so it reads as hair and not a mask)
		var bc := hair.lerp(Color("#6a5440"), 0.18)
		if beard:
			out.append([("beard_full" if age > 0.45 or kind == "outlaw" else "beard_short") if r[5] < 0.75 else "moustache", {"Hair": bc}])
		elif r[5] < 0.3:
			out.append(["moustache", {"Hair": bc}])
	return out


static func _load_kit() -> void:
	if not _kit.is_empty() or not ResourceLoader.exists(KIT):
		return
	var root := (load(KIT) as PackedScene).instantiate()
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var names: Array[String] = []
		var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		for i in mi.skin.get_bind_count():
			var bn := String(mi.skin.get_bind_name(i))
			if bn == "" and sk:
				bn = sk.get_bone_name(mi.skin.get_bind_bone(i))
			names.append(bn)
		_kit[String(mi.name)] = [mi.mesh, names]
	root.free()


## The piece's skin bound to this skeleton's rest (the kit was made on the same rest pose).
func _skin_for(piece: String) -> Skin:
	if _kit_skins.has(piece):
		return _kit_skins[piece]
	var s := Skin.new()
	for bn: String in _kit[piece][1]:
		var b := skeleton.find_bone(bn)
		s.add_named_bind(bn, skeleton.get_bone_global_rest(b).affine_inverse() if b >= 0 else Transform3D.IDENTITY)
	_kit_skins[piece] = s
	return s


func _material(name: String, c: Color, own := false) -> StandardMaterial3D:
	var key := "%s:%s" % [name, c.to_html()]
	if not own and _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_color = c
	m.roughness = {"Leather": 0.6, "Sole": 0.55, "Metal": 0.45, "Button": 0.6, "Band": 0.85}.get(name, 0.95)
	if name == "Metal":
		m.metallic = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED # (peaks, flaps, a shawl's edge: seen from either side)
	if not own:
		_mats[key] = m
	return m


## The clothes for now (the winter's or the summer's, the militia's over them) put on.
func _wear() -> void:
	_load_kit()
	if _kit.is_empty():
		return
	for mi in _worn:
		mi.free() # (now: two changes in one frame would otherwise draw both sets once)
	_worn.clear()
	var fit: Array = (_winter_fit if _winter else _summer).duplicate()
	if _militia and _kind == "man":
		var hats := ["kartuz", "papakha", "ushanka", ""]
		if not _winter:
			fit = fit.filter(func(e: Array) -> bool: return not str(e[0]) in hats)
			fit.append(_militia_fit[0])
		var belt := str(_militia_fit[1][0])
		var torso := str(fit[0][0])
		if torso == "tulup":
			belt = "belt_kit_wide"
		elif torso in ["shinel", "padded"]:
			belt = "belt_kit"
		fit.append([belt, _militia_fit[1][1]])
	coat_material = null
	for e: Array in fit:
		var piece := str(e[0])
		if not _kit.has(piece):
			continue
		var colours: Dictionary = e[1]
		var mi := MeshInstance3D.new()
		mi.name = "Kit_" + piece
		mi.mesh = _kit[piece][0]
		skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
		mi.skin = _skin_for(piece)
		if piece in ["hair", "beard_full", "beard_short", "moustache", "armband", "armband_wide", "neck_rag"]:
			mi.visibility_range_end = 70.0 # (small things not worth drawing from far off)
		var first := coat_material == null
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s)
			var name := base.resource_name.trim_prefix("kit_") if base else "Cloth"
			var c: Color = colours.get(name, Color(0.5, 0.48, 0.44))
			var own := first and name in ["Cloth", "Hide"]
			var m := _material(name, c, own)
			mi.set_surface_override_material(s, m)
			if own:
				coat_material = m
		_shape(mi)
		_worn.append(mi)
	if coat_material == null:
		coat_material = _material("Cloth", Color(0.5, 0.48, 0.44), true)


## In the winter: the winter's clothes, fur and felt; out of it, the summer's.
func set_winter(on: bool) -> void:
	if on == _winter:
		return
	_winter = on
	_wear()


## One of the militia wears a service cap in place of his own (not over a fur hat in the winter)
## and a leather belt with its pouches and strap: told from the others from above, nothing more.
func set_militia(on: bool) -> void:
	if on == _militia:
		return
	_militia = on
	_wear()


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
	var shaven := _kind in ["woman", "child"] or age < 0.05
	var st := rng.randf_range(0.3, 0.9) if age >= 0.05 else 0.0 # (drawn as before, so a seed keeps its face)
	m.set_shader_parameter("stubble", 0.0 if shaven else st)
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


## ---- Named poses (TownsfolkPose.want's numbers), for anyone to hold or flash ----------------
## Townsfolk.pose_preset(name) gives a copy; register_pose(name, v) adds one (combat, the daily
## round...). Keys as TownsfolkPose.want.
const POSES := {
	"hands_on_knees": {"arm_l": -0.55, "arm_r": -0.5, "el": 0.8, "er": 0.75, "lean": 0.12},
	"arms_out": {"abd_l": 0.6, "abd_r": 0.6, "el": 0.3, "er": 0.3},
	"shrug": {"sh_l": 0.18, "sh_r": 0.18, "abd_l": 0.15, "abd_r": 0.15, "el": 0.9, "er": 0.9, "head": -0.05},
	"bent_low": {"lean": 0.85, "hip_y": 0.12, "head": -0.2, "arm_l": -0.4, "arm_r": -0.4, "el": 0.3, "er": 0.3},
	"crouch": {"hip_y": 0.38, "hip_z": 0.08, "lean": 0.35, "arm_l": -0.5, "arm_r": -0.5, "el": 0.6, "er": 0.6},
	"brace": {"hip_y": 0.08, "lean": 0.18, "roll": 0.0, "arm_l": -0.6, "arm_r": -0.6, "el": 1.2, "er": 1.2},
	"look_up": {"head": -0.35, "lean": -0.08},
	"weary": {"sh_l": -0.12, "sh_r": -0.12, "lean": 0.12, "head": 0.2},
}
static var _poses := {}


static func pose_preset(name: String) -> Dictionary:
	if _poses.has(name):
		return (_poses[name] as Dictionary).duplicate()
	return (POSES.get(name, {}) as Dictionary).duplicate()


static func register_pose(name: String, v: Dictionary) -> void:
	_poses[name] = v.duplicate()


## Held in a named pose (or a dictionary of numbers) over the standing clip, as `sit` holds one:
## for whoever isn't driven by a villager's moves (Villager.drive puts its own each frame).
func hold(pose_name_or_v: Variant, rate := 1.0) -> void:
	var v: Dictionary = pose_preset(pose_name_or_v) if pose_name_or_v is String else pose_name_or_v
	pose.want(v, rate)


## ---- One-shot moves played over whatever drive() says --------------------------------------
## gesture(clip): the clip played once through from its start (PutDown, PickUp, GetUp,
## GetUpFromProne, SoldierWave, RifleReload, Interact...), then back to what it was doing; `still`
## asks the villager to stand where it is till it's done (Villager._walk waits on busy()).
## flash(v, secs): a set of numbers (TownsfolkPose.want's) swelled in over whatever's driven and
## let go again (a wince, a wave of the hand, a startle).
var _shot := ""
var _shot_t := 0.0
var _shot_len := 0.0
var _shot_speed := 1.0
var _shot_still := false
var _flash := {}
var _flash_t := -1.0
var _flash_len := 1.0


func gesture(clip: String, speed := 1.0, still := true, blend := 0.15) -> void:
	if _dead or not player.has_animation(clip):
		return
	_shot = clip
	_shot_t = 0.0
	_shot_speed = maxf(speed, 0.05)
	_shot_len = player.get_animation(clip).length / _shot_speed
	_shot_still = still
	_clip = clip
	player.play(clip, blend)
	player.seek(0.0, true)
	player.speed_scale = _shot_speed


## Playing a one-shot that wants the feet kept still.
func busy() -> bool:
	return _shot != "" and _shot_still


func flash(v: Dictionary, secs := 0.8) -> void:
	_flash = v
	_flash_len = maxf(secs, 0.05)
	_flash_t = 0.0


## ---- What's carried and how --------------------------------------------------------------
## carry(load, res, n): the load Villager made (_hand_load) put where it's carried, the clip and
## the hands to go with it: "box" a crate, a hod of stone, bricks, a basket of mud held in front
## in both hands (the hands on its sides); "armful" split firewood against the chest; "log" a log
## on the right shoulder, the right hand steadying it; "sack" a sack over the right shoulder on the
## back, the hand at its neck; "side" a bucket of water or a basket of herbs hanging from the right
## hand, the body leaning away from it, the free arm out. put_down(load) sets it down (the PutDown
## clip; the load freed as it touches the ground).
const CARRY := {"tas": "box", "komur": "box", "demir": "box", "kerpic": "box", "camur": "box", "tufek": "box",
	"yiyecek": "sack", "su": "side", "ot": "side", "odun": "log"}
## Per style: [bone, offset (body frame), turn (euler), upright, left hand, right hand] (hands as
## offsets from the bone, INF: the clip's own).
const MOUNT := {
	"box": ["Cargo", Vector3(0, 0.12, 0.0), Vector3.ZERO, false, Vector3(-0.28, 0.12, 0.0), Vector3(0.28, 0.12, 0.0)],
	"armful": ["Cargo", Vector3(0, 0.15, 0.08), Vector3.ZERO, false, Vector3(-0.17, 0.06, 0.07), Vector3(0.17, 0.06, 0.07)],
	"log": ["UpperChest", Vector3(0.15, 0.21, 0.06), Vector3(PI * 0.5 + 0.1, 0.06, 0.0), false, Vector3.INF, Vector3(0.19, 0.11, -0.3)],
	"sack": ["UpperChest", Vector3(0.07, 0.0, 0.22), Vector3(-0.2, 0.0, -0.32), false, Vector3.INF, Vector3(0.19, 0.12, -0.05)],
	"side": ["Cargo", Vector3(0, 0.06, 0.0), Vector3.ZERO, true, Vector3.INF, Vector3.INF],
}
## How high each load's own origin sits over where the clip holds it (a hod's middle, the foot of
## a stack of bricks...).
const LOAD_LIFT := {"kerpic": -0.06, "camur": 0.0, "ot": 0.08, "su": 0.0}
var _carry: Node3D
var _carry_style := ""
var _carry_lift := 0.0
var _ghost: Node3D ## (being set down)
var _ghost_style := ""
var _ghost_lift := 0.0
var _hooked := false


func carry(load: Node3D, res: String, n: int) -> void:
	_carry = load
	_carry_style = ""
	if load == null or res == "" or n <= 0 or not CARRY.has(res):
		return
	_carry_style = CARRY[res]
	if res == "odun" and n > 3 and n < 10:
		_carry_style = "armful"
	_carry_lift = float(LOAD_LIFT.get(res, 0.0))
	_hook()


## Set down where it stands (the clip bending to the ground with it): true if the body takes
## `load` and frees it itself.
func put_down(load: Node3D) -> bool:
	var style := _carry_style if load == _carry else ""
	_carry = null
	_carry_style = ""
	if style == "" or _lying or _dead or not is_visible_in_tree():
		return false
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = load
	_ghost_style = style
	_ghost_lift = _carry_lift
	gesture("PutDown", 1.3)
	_hook()
	return true


func _hook() -> void:
	if not _hooked:
		_hooked = true
		skeleton.skeleton_updated.connect(_place_loads)


## (after the bones are posed: the loads where the body holds them)
func _place_loads() -> void:
	if is_instance_valid(_carry) and _carry_style != "":
		_place(_carry, _carry_style, _carry_lift)
	elif _carry != null:
		_carry = null
		_carry_style = ""
	if is_instance_valid(_ghost):
		if _shot != "PutDown" or _shot_t > _shot_len * 0.55:
			_ghost.queue_free()
			_ghost = null
		else:
			_place(_ghost, _ghost_style, _ghost_lift)


func _place(load: Node3D, style: String, lift: float) -> void:
	var m: Array = MOUNT[style]
	var f := skeleton.global_transform * pose.frame(m[0])
	var at: Vector3 = f * ((m[1] as Vector3) + Vector3(0, lift, 0))
	var b: Basis
	if m[3]:
		b = global_basis.orthonormalized() # (it hangs: upright, whatever the hand does)
		at = f.origin + Vector3(0, ((m[1] as Vector3).y + lift) * global_basis.get_scale().y, 0)
	else:
		b = f.basis.orthonormalized() * Basis.from_euler(m[2])
	load.global_transform = Transform3D(b, at)


## The hands on the load (while it's to be seen: put by while the work's done).
func _carry_hands() -> void:
	var on := is_instance_valid(_carry) and _carry_style != "" and _carry.visible and not busy()
	if not on:
		if _hands_on:
			_hands_on = false
			pose.release(0)
			pose.release(1)
		return
	_hands_on = true
	var m: Array = MOUNT[_carry_style]
	for i in 2:
		var at: Vector3 = m[4 + i]
		if at == Vector3.INF:
			pose.release(i)
		else:
			pose.reach(i, at + Vector3(0, _carry_lift, 0), m[0], 1.0)


var _hands_on := false


## ---- The moves for what it's doing --------------------------------------------------------
## Moves for `anim` (Villager._anim): a clip, and over it (for the work no clip has) the numbers
## Villager._animate worked out. `speed` is how fast it's going over the ground, `rate` the game's.
var _was_walking := false
var _yaw_prev := INF
var _turn_t := 0.0
var _turn_dir := 0.0
var _kick_t := 0.0
var _kick_sign := 0.0
var _work_t := 0.0 ## s of its own work cycle (the spade, the herbs, the berries)
var _beat_prev := 0.0
var _bite := 0.0 ## (a blow just landed: the body jolted by it, easing off)
var _stuck_t := -1.0 ## (the axe bitten in and wrenched out: s into it)
var _stuck_v := {}
var _basket: Node3D


func drive(anim: String, walking: bool, speed: float, rate: float, carrying: String, vehicle: String,
		armed: bool, v: Dictionary) -> void:
	var real_dt := get_process_delta_time()
	var dt := real_dt * maxf(rate, 0.01) # (the game's seconds)
	_track(walking, real_dt, dt)
	if _lying or Time.get_ticks_msec() < _flinch_t:
		return
	_carry_hands()
	if _shot != "":
		_shot_t += dt
		player.speed_scale = _shot_speed * rate
		if _shot_t < _shot_len - 0.12:
			pose.want({}, rate)
			pose.walking = false
			return
		_shot = ""
		_clip = ""
	var clip := "Idle"
	var pace := rate
	var procedural := false
	var style := _carry_style if is_instance_valid(_carry) and _carry.visible else ""
	var scale_now := maxf(global_basis.get_scale().y * model.scale.y, 0.2) # (a child's legs are short)
	var stride := 1.0
	_show_basket(anim)
	if walking:
		var real := speed / maxf(rate, 0.01) / scale_now
		var box := style in ["box", "armful"] or (style == "" and carrying in ["tas", "yiyecek", "su", "camur", "kerpic", "tufek"])
		if box or vehicle == "hand":
			clip = "CarryBoxWalk"
			pace = speed / CARRY_SPEED
		elif style == "side":
			clip = "CarrySideWalk"
			pace = speed / WALK_SPEED
		elif armed:
			clip = "RifleWalk" if real < 2.6 else "RifleJog"
			pace = speed / (WALK_SPEED if real < 2.6 else JOG_SPEED)
		elif real < 2.6:
			clip = "Walk"
			pace = speed / WALK_SPEED
		else:
			clip = "Jog"
			pace = speed / JOG_SPEED
		pace /= scale_now
		procedural = (style == "" and carrying == "odun") or carrying == "yarali" or vehicle == "ox"
		stride = _stride()
		pace /= stride
	else:
		match anim:
			"idle", "look", "stretch":
				clip = "RifleIdle" if armed else _idle_clip()
				procedural = anim != "idle"
				if style in ["box", "armful"] and anim != "stretch":
					clip = "CarryBoxIdle"
					procedural = false
				elif style == "side" and anim != "stretch":
					clip = "CarrySideIdle"
					procedural = false
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
			"berry":
				# down on the knees at the bush (the clip kneels, then works with the hands: held
				# there, not stood up again each time round), a hand to the berries and back to
				# the basket at the knee
				clip = "ual/UalFixKneeling"
				procedural = true
				v = _berry(dt)
			"herb":
				clip = "Idle"
				procedural = true
				v = _herb(dt)
			"dig":
				clip = "Idle"
				procedural = true
				v = _dig(dt)
			"chop", "limb", "mine", "build":
				clip = "Idle"
				procedural = true
				v = _blow(anim, v, dt)
			"chisel":
				clip = "Idle"
				procedural = true
				v = _chisel(v)
			"saw":
				clip = "Idle"
				procedural = true
				v = _saw(v)
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
	elif _turn_t > 0.0 and not walking and pose.seat < 0.0 and clip in ["Idle", "ual/UalIdleFoldArms", "RifleIdle", "CarryBoxIdle", "CarrySideIdle", "ual/UalIdleTalking", "SoldierTalk", "ual/UalIdleNo"]:
		# turning where it stands: the feet stepping round under it, not the body spun on them
		clip = "RifleTurnInPlace" if armed else "TurnInPlace"
		pace = rate * 1.3
	pose.nod = 1.0 if anim == "listen" else 0.0
	pose.bow = 1.0 if anim == "pray" else 0.0
	pose.stride = stride
	pose.walking = walking
	play(clip, pace)
	if clip == "ual/UalFixKneeling" and player.current_animation_position > 4.7:
		player.seek(1.6, true) # (kept on its knees)
	if walking:
		var len := player.current_animation_length
		pose.phase = player.current_animation_position / len if len > 0.0 else 0.0
	var out: Dictionary = v if procedural else {}
	out = _carry_body(style, walking, anim, out)
	if _flash_t >= 0.0:
		_flash_t += dt
		var e := sin(clampf(_flash_t / _flash_len, 0.0, 1.0) * PI)
		if _flash_t >= _flash_len:
			_flash_t = -1.0
		else:
			out = out.duplicate()
			for k: String in _flash:
				out[k] = lerpf(float(out.get(k, TownsfolkPose.REST.get(k, 0.0))), float(_flash[k]), e)
	pose.want(out, rate)


## The turn where it stands and the lean starting off and stopping, read off how the body moves.
func _track(walking: bool, real_dt: float, dt: float) -> void:
	var yaw := global_rotation.y
	if _yaw_prev != INF and real_dt > 0.0:
		var dy := angle_difference(_yaw_prev, yaw)
		if not walking and absf(dy) / real_dt > 1.4 and absf(dy) < 1.0:
			_turn_t = 0.5
			_turn_dir = signf(dy)
	_yaw_prev = yaw
	_turn_t = maxf(_turn_t - dt, 0.0)
	pose.turn_lead = _turn_dir * 0.4 if _turn_t > 0.0 else 0.0
	if walking != _was_walking:
		_kick_t = 0.45
		_kick_sign = 1.0 if walking else -0.6
	_was_walking = walking
	_kick_t = maxf(_kick_t - dt, 0.0)
	pose.lean_kick = _kick_sign * 0.13 * sin(_kick_t / 0.45 * PI)


## How long its step is against the clip's (shorter: quicker steps for the same ground).
func _stride() -> float:
	var s := 1.0 - 0.22 * smoothstep(0.6, 1.0, pose.age)
	if pose.female:
		s *= 0.93
	s *= 1.0 - 0.12 * pose.tired
	s *= 1.0 - 0.18 * pose.snow
	s *= 1.0 - 0.2 * pose.mud
	return s


## The body under what it carries: leaning away from a bucket, under a sack, off a log.
func _carry_body(style: String, walking: bool, anim: String, out: Dictionary) -> Dictionary:
	if style == "" or not (walking or anim in ["idle", "look", "listen", "chat"]):
		return out
	var add: Dictionary
	match style:
		"side":
			add = {"roll": -0.09, "abd_l": 0.3, "el": 0.25}
		"sack":
			add = {"lean": 0.14, "roll": -0.05, "head": -0.08}
		"log":
			add = {"roll": -0.06, "head": 0.04}
		"box":
			add = {"lean": -0.03}
		_:
			return out
	out = out.duplicate()
	for k: String in add:
		out[k] = float(out.get(k, TownsfolkPose.REST[k])) + float(add[k])
	return out


## A table of keys [u, {numbers}] played at `u` (0..1): eased between, the last stretch (back to
## the first) quickening all the way in (a blow).
static func _keyed(table: Array, u: float, blow_last := true) -> Dictionary:
	var n := table.size()
	for i in n:
		var a: Array = table[i]
		var last := i == n - 1
		var b: Array = table[0] if last else table[i + 1]
		var t1 := 1.0 if last else float(b[0])
		if u >= float(a[0]) and u < t1:
			var k := (u - float(a[0])) / maxf(t1 - float(a[0]), 0.001)
			k = k * k if last and blow_last else smoothstep(0.0, 1.0, k)
			var out := {}
			var da: Dictionary = a[1]
			var db: Dictionary = b[1]
			for key: String in da:
				out[key] = lerpf(float(da[key]), float(db.get(key, da[key])), k)
			return out
	return (table[0][1] as Dictionary).duplicate()


## The spade: driven in with the weight on it, levered back, the load lifted and thrown off to the
## right, the blade brought round again.
const DIG := [
	[0.0, {"arm_l": -0.75, "arm_r": -0.8, "el": 0.65, "er": 0.6, "lean": 0.25, "hip_y": 0.03, "twist": 0.05, "kn": 0.05}],
	[0.2, {"arm_l": -0.42, "arm_r": -0.38, "el": 0.35, "er": 0.28, "lean": 0.5, "hip_y": 0.12, "twist": 0.0, "kn": 0.05}],
	[0.38, {"arm_l": -0.3, "arm_r": -0.22, "el": 0.55, "er": 0.45, "lean": 0.32, "hip_y": 0.07, "twist": 0.0, "kn": 0.05}],
	[0.55, {"arm_l": -0.9, "arm_r": -0.95, "el": 0.95, "er": 0.85, "lean": 0.22, "hip_y": 0.05, "twist": 0.1, "kn": 0.05}],
	[0.7, {"arm_l": -1.05, "arm_r": -1.15, "el": 0.7, "er": 0.6, "lean": 0.12, "hip_y": 0.03, "twist": -0.65, "kn": 0.05}],
	[0.8, {"arm_l": -0.95, "arm_r": -1.05, "el": 0.6, "er": 0.5, "lean": 0.15, "hip_y": 0.03, "twist": -0.75, "kn": 0.05}],
]


func _dig(dt: float) -> Dictionary:
	_work_t += dt
	return _keyed(DIG, fmod(_work_t + _seed * 0.13, 2.4) / 2.4, false)


## The mallet on the chisel: drawn up slow, held a beat at the top (the chest lifting with it),
## brought down quick; the jolt of it, the mallet bouncing off.
const CHISEL := [
	[0.0, {"arm_l": -0.72, "arm_r": -1.12, "el": 0.82, "er": 0.42, "lean": 0.4, "head": 0.1}],
	[0.1, {"arm_l": -0.7, "arm_r": -1.2, "el": 0.8, "er": 0.6, "lean": 0.39, "head": 0.08}],
	[0.55, {"arm_l": -0.7, "arm_r": -1.65, "el": 0.8, "er": 1.35, "lean": 0.33, "head": 0.04}],
	[0.75, {"arm_l": -0.7, "arm_r": -1.78, "el": 0.8, "er": 1.55, "lean": 0.3, "head": 0.02}],
]


func _chisel(v: Dictionary) -> Dictionary:
	var u := float(v.get("beat", fmod(Time.get_ticks_msec() * 0.001, 0.9) / 0.9))
	var out := _keyed(CHISEL, u)
	out["hip_y"] = 0.03 + (0.02 if u < 0.08 else 0.0)
	return out


## The saw drawn to and fro: the body rocking with each stroke, the knees soft.
func _saw(v: Dictionary) -> Dictionary:
	var s := clampf((1.1 - float(v.get("el", 1.1))) / 0.5, -1.0, 1.0)
	var out := v.duplicate()
	out["hip_z"] = -s * 0.045
	out["hip_y"] = 0.06 + absf(s) * 0.015
	out["lean"] = float(v.get("lean", 0.3)) + s * 0.06
	out["head"] = 0.12
	return out


## An axe, a pick, a hammer, as Villager swings it (its beat): the jolt of the blow through the
## body, the tool bouncing back off the wood; now and then the axe bites in and sticks, and is
## worked free and wrenched out, the body thrown back with it.
func _blow(anim: String, v: Dictionary, dt: float) -> Dictionary:
	var u := float(v.get("beat", -1.0))
	var out := v.duplicate()
	if u >= 0.0:
		if u < _beat_prev - 0.5:
			_bite = 1.0
			if anim == "chop" and _stuck_t < 0.0 and randf() < 0.16:
				_stuck_t = 0.0
				_stuck_v = v.duplicate()
		_beat_prev = u
	_bite = maxf(_bite - dt * 6.0, 0.0)
	var b := _bite * _bite
	out["hip_y"] = 0.035 + b * 0.05
	out["lean"] = float(out.get("lean", 0.0)) + b * 0.06
	out["head"] = b * 0.08
	out["arm_l"] = float(out.get("arm_l", 0.0)) - b * 0.1 # (the haft springing back up off it)
	out["arm_r"] = float(out.get("arm_r", 0.0)) - b * 0.1
	if _stuck_t >= 0.0:
		_stuck_t += dt
		var t := _stuck_t / 1.5
		if t >= 1.0:
			_stuck_t = -1.0
		else:
			var held := _stuck_v.duplicate()
			var tug := 0.0
			if t < 0.25:
				tug = sin(t / 0.25 * PI) * 0.4 # (a first pull: it holds)
			elif t < 0.6:
				var e := (t - 0.25) / 0.35
				tug = 0.5 + e * 0.5 + sin(e * TAU * 3.0) * 0.12 # (worked side to side, leaning into it)
				held["twist"] = float(held.get("twist", 0.0)) + sin(e * TAU * 3.0) * 0.12
			else:
				tug = 1.0 - smoothstep(0.6, 0.72, t) * 1.6 # (it gives: thrown back a step)
			held["lean"] = float(held.get("lean", 0.0)) - tug * 0.28
			held["hip_y"] = 0.05 + absf(tug) * 0.08
			held["hip_z"] = tug * 0.06
			held["arm_l"] = float(held.get("arm_l", 0.0)) + tug * 0.3
			held["arm_r"] = float(held.get("arm_r", 0.0)) + tug * 0.3
			held["el"] = float(held.get("el", 0.3)) + tug * 0.25
			held["er"] = float(held.get("er", 0.3)) + tug * 0.25
			var back := smoothstep(0.72, 1.0, t) # (and back to the swing)
			for k: String in held:
				out[k] = lerpf(float(held[k]), float(out.get(k, held[k])), back)
	return out


## Berries: on the knees, the right hand to the bush and back to the basket at the left knee.
func _berry(dt: float) -> Dictionary:
	_work_t += dt
	var u := fmod(_work_t + _seed * 0.21, 2.6) / 2.6
	var to_bush := smoothstep(0.0, 0.3, u) * (1.0 - smoothstep(0.55, 0.8, u))
	var pick := sin(u * TAU * 4.0) * 0.06 * to_bush
	return {"arm_r": -0.15 - to_bush * 0.55 + pick, "er": 0.6 - to_bush * 0.35, "twist": 0.25 * (1.0 - to_bush),
		"arm_l": -0.15, "el": 0.4, "lean": 0.1 + to_bush * 0.12, "head": 0.15}


## Herbs: bent low over them, the left hand gathering the stalks, the sickle drawn through under
## it; straightening a little now and then to lay a handful in the basket.
func _herb(dt: float) -> Dictionary:
	_work_t += dt
	var u := fmod(_work_t + _seed * 0.17, 4.0) / 4.0
	var up := smoothstep(0.72, 0.82, u) * (1.0 - smoothstep(0.9, 1.0, u))
	var cut := maxf(sin(u * TAU * 5.0), 0.0) * (1.0 - up)
	return {"lean": 1.25 - up * 0.4, "hip_y": 0.2 - up * 0.07, "hip_z": 0.07, "head": -0.35, "kn": 0.05,
		"arm_l": -0.5 - up * 0.2, "el": 0.35 + up * 0.5, "arm_r": -0.35 - cut * 0.3 + up * 0.1, "er": 0.35 + cut * 0.4,
		"twist": -0.1 + up * 0.35, "abd_l": 0.1}


## The basket by it, picking berries or cutting herbs.
func _show_basket(anim: String) -> void:
	var want := anim in ["berry", "herb"]
	if want and _basket == null:
		_basket = Node3D.new()
		add_child(_basket)
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.17
		c.bottom_radius = 0.12
		c.height = 0.2
		c.radial_segments = 10
		mi.mesh = c
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.55, 0.42, 0.25)
		m.roughness = 1.0
		mi.material_override = m
		mi.position.y = 0.1
		_basket.add_child(mi)
		var fill := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.15
		s.height = 0.08
		s.radial_segments = 8
		s.rings = 4
		fill.mesh = s
		fill.position.y = 0.19
		_basket.add_child(fill)
		_basket.set_meta("fill", fill)
	if _basket:
		_basket.visible = want
		if want:
			_basket.position = Vector3(-0.42, 0.0, -0.32) if anim == "berry" else Vector3(0.45, 0.0, 0.15)
			var fill := _basket.get_meta("fill") as MeshInstance3D
			if fill.material_override == null or fill.get_meta("for", "") != anim:
				var fm := StandardMaterial3D.new()
				fm.albedo_color = Color(0.35, 0.08, 0.12) if anim == "berry" else Color(0.35, 0.5, 0.22)
				fill.material_override = fm
				fill.set_meta("for", anim)


## (Villager: shouldered aside while standing, the step's clip, WalkLeft and so on, and its pace)
var side_step := ""
var side_pace := 1.0


## Sat down on a seat `seat` m up from where its feet are (a lorry's bench, a stump), the hands on
## the knees, and left so: for the men riding in a lorry, not driven by a villager's moves.
func sit(seat := 0.45, speed := 1.0) -> void:
	pose.seat = seat
	play("Idle", speed, 0.0)
	pose.want(pose_preset("hands_on_knees"), 1.0)


## Down, wounded: the fall, then lying there.
func lie() -> void:
	_lying = true
	_shot = ""
	pose.seat = -1.0
	side_step = ""
	_clip = "Death"
	player.play("Death", 0.15)
	player.speed_scale = 1.0
	pose.want({}, 1.0)
	pose.release(0)
	pose.release(1)


## On its feet again: up off the ground the way one gets up from lying on one's front (it fell
## so), then whatever it was doing.
func stand() -> void:
	var was := _lying
	_lying = false
	_clip = ""
	if was and not _dead:
		gesture("GetUpFromProne", 1.0)
	else:
		play("Idle")


func die() -> void:
	play("Death", 1.0, 0.15)
	_dead = true
	_shot = ""
	pose.want({}, 1.0)
	pose.release(0)
	pose.release(1)
