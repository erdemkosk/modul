class_name Crop
extends MultiMeshInstance3D
## A field's crop (a Building with role "farm"): rows of tufts over the field, lying on the ground
## wherever it is. Fallow it's bare earth. Sown (`sown` goes 0..1 as its farmers walk the rows), it
## comes up green and grows (`growth`, faster in the rain, not at all in snow), turns gold when
## ripe, and is reaped row by row (`reaped`), each sheaf carried off as food. A ripe or nearly ripe
## crop burns: a fire in it runs across the field and leaves it black and fallow.

const GROW_TIME := 360.0 ## s from sown to ripe, in fair weather
const YIELD := 60 ## food a ripe field gives
const STEP_X := 1.0
const STEP_Z := 0.75

var field: Building
var nav: Nav
var stage := "fallow" ## fallow, sowing, growing, ripe
var sown := 0.0
var growth := 0.0
var reaped := 0 ## food taken off it so far
var burning := 0.0 ## > 0 while the crop's alight: seconds it has burnt

var _spots: Array[Vector3] = [] ## each tuft, in the field's space (on the ground)
var _t := 0.0
var _flames: Array[GPUParticles3D] = []


func _ready() -> void:
	var sz: Vector2 = field.def.size
	var inv := field.global_transform.affine_inverse()
	var x := -sz.x * 0.5 + 0.8
	while x < sz.x * 0.5 - 0.7:
		var z := -sz.y * 0.5 + 0.8
		while z < sz.y * 0.5 - 0.6:
			var w := field.global_transform * Vector3(x, 0, z)
			w.y = nav.terrain.height_at(w.x, w.z)
			_spots.append(inv * w)
			z += STEP_Z
		x += STEP_X
	var mesh := _tuft_mesh()
	var m := ShaderMaterial.new()
	m.shader = TUFT_SHADER
	mesh.surface_set_material(0, m)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = _spots.size()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_draw()


const TUFT_SHADER := preload("res://shaders/crop.gdshader")


## One tuft, a metre tall from its foot: a sheaf of tapering blades bent out from the middle, the
## middle ones carrying an ear. Darker at the foot (vertex colour; the crop's own colour over it).
static func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var lean := rng.randf_range(0.12, 0.38) if k > 2 else rng.randf_range(0.02, 0.1)
		var tall := rng.randf_range(0.75, 1.0) if k > 2 else 1.0
		var w := 0.035
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		for j in 5: # (a blade in four bends, curving out as it goes up)
			var f := j / 4.0
			var c := out * lean * f * f + Vector3.UP * tall * f + out * 0.03
			var half := w * (1.0 - f * 0.9)
			var l := c - side * half
			var r := c + side * half
			if j > 0:
				var g0 := lerpf(0.45, 1.0, (j - 1) / 4.0)
				var g1 := lerpf(0.45, 1.0, f)
				_quad(st, prev_l, prev_r, r, l, Color(g0, g0, g0), Color(g1, g1, g1))
			prev_l = l
			prev_r = r
		if k <= 2: # an ear on the middle stalks: a slim spindle at the top
			var top := out * lean + Vector3.UP * tall
			var ear := Color(1, 1, 1)
			for q in 3:
				var b := TAU * q / 3.0
				var d := Vector3(cos(b), 0, sin(b)) * 0.045
				_quad(st, top + Vector3.DOWN * 0.02, top + Vector3.DOWN * 0.02, top + d + Vector3.UP * 0.1, top + Vector3.UP * 0.24, ear, ear)
				_quad(st, top + Vector3.DOWN * 0.02, top + Vector3.DOWN * 0.02, top + Vector3.UP * 0.24, top - d + Vector3.UP * 0.1, ear, ear)
	st.generate_normals()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, lo: Color, hi: Color) -> void:
	for v in [[a, lo], [b, lo], [c, hi], [a, lo], [c, hi], [d, hi]]:
		st.set_color(v[1])
		st.add_vertex(v[0])


## A place in the field to work at, on the ground, in the world.
func spot() -> Vector3:
	var p := field.global_transform * _spots[randi() % _spots.size()]
	p.y = nav.height(p.x, p.z)
	return p


func ripe() -> bool:
	return stage == "ripe"


func left() -> int:
	return YIELD - reaped if stage == "ripe" else 0


## A farmer's stint sowing. True once it's all sown.
func sow(amount: float) -> bool:
	if stage == "fallow":
		stage = "sowing"
	sown = minf(sown + amount, 1.0)
	if sown >= 1.0:
		stage = "growing"
		growth = 0.0
	_draw()
	return stage == "growing"


## A farmer's stint hoeing: it helps a little.
func tend() -> void:
	if stage == "growing":
		growth = minf(growth + 0.012, 1.0)


## Reaps up to `n`; what it got. Reaped bare, the field lies fallow again.
func reap(n: int) -> int:
	if stage != "ripe":
		return 0
	var k := mini(n, YIELD - reaped)
	reaped += k
	if reaped >= YIELD:
		_fallow()
	_draw()
	return k


func _fallow() -> void:
	stage = "fallow"
	sown = 0.0
	growth = 0.0
	reaped = 0


## A fire in it, if it's grown enough to burn. False if it isn't.
func ignite() -> bool:
	if burning > 0.0 or not (stage == "ripe" or (stage == "growing" and growth > 0.3)):
		return false
	burning = 0.01
	return true


func _process(dt: float) -> void:
	_t += dt
	if burning > 0.0:
		burning += dt
		if burning > 10.0 or Weather.rain_now > 0.7 and randf() < dt * 0.1:
			var was := burning > 10.0
			burning = 0.0
			for f in _flames:
				f.emitting = false
			if was:
				nav.scorch(field.global_position, field.radius, 0.8)
				_fallow()
				_draw()
		else:
			_burn_fx()
	if _t < 1.0:
		return
	if stage == "growing" and burning <= 0.0:
		var rate := (1.0 + Weather.rain_now * 0.6) * (1.0 - clampf(Weather.snow_cover_now * 2.0, 0.0, 1.0))
		growth = minf(growth + _t / GROW_TIME * rate, 1.0)
		if growth >= 1.0:
			stage = "ripe"
	_t = 0.0
	_draw()


func _burn_fx() -> void:
	if _flames.is_empty():
		for k in 4:
			var f := FireFx.flames()
			f.amount = 60
			field.add_child(f)
			_flames.append(f)
	var sz: Vector2 = field.def.size
	var front := clampf(burning / 10.0, 0.0, 1.0)
	for k in _flames.size():
		var f := _flames[k]
		f.position = Vector3(lerpf(-sz.x * 0.45, sz.x * 0.45, front), 0.6, -sz.y * 0.4 + k * sz.y * 0.27)
		(f.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(1.2, 0.3, sz.y * 0.14)
		f.emitting = true


func _draw() -> void:
	var n := _spots.size()
	var green := Color(0.34, 0.52, 0.16)
	var gold := Color(0.86, 0.68, 0.3)
	var cut := int(float(reaped) / YIELD * n) if stage == "ripe" else 0
	var burnt := int(clampf(burning / 10.0, 0.0, 1.0) * n)
	for i in n:
		var h := 0.0
		var c := green
		match stage:
			"sowing":
				h = 0.08 if float(i) / n < sown else 0.0
			"growing":
				h = 0.05 + growth * 0.85
				c = green.lerp(gold, smoothstep(0.7, 1.0, growth))
			"ripe":
				h = 0.95 if i >= cut else 0.1
				c = gold if i >= cut else gold.darkened(0.35) # (the stubble)
		if burning > 0.0 and i < burnt:
			h = 0.06
			c = Color(0.05, 0.04, 0.03)
		var p := _spots[i]
		var wob := sin(float(i) * 12.9898) * 0.15
		if h <= 0.0:
			multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), p))
		else:
			var wide := lerpf(1.6, 1.0, clampf(h, 0.0, 1.0)) * (1.0 + wob) # (a shoot sprawls; the grown stalk stands)
			multimesh.set_instance_transform(i, Transform3D(Basis(Vector3.UP, wob * 20.0).scaled(Vector3(wide, h, wide)), p))
		multimesh.set_instance_color(i, c)
