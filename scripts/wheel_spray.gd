class_name WheelSpray
extends Node3D
## What a wheel throws: clods of mud (or snow) off the tread back and up, a lot more spinning than
## rolling, falling back onto the ground and lying there a moment (they collide with the
## Machine's heightfield); dust off dry dirt and gravel going fast. One per wheel, moved to its
## contact patch each step by MachineWheel.

## Surface label -> [clod colour, clods (0..), dust (0..)].
const KINDS := {
	"mud": [Color(0.16, 0.11, 0.07), 1.0, 0.0], "bog": [Color(0.13, 0.1, 0.07), 1.2, 0.0],
	"wet": [Color(0.22, 0.17, 0.11), 0.5, 0.0], "grass": [Color(0.2, 0.17, 0.1), 0.15, 0.1],
	"dirt": [Color(0.36, 0.29, 0.2), 0.25, 0.8], "gravel": [Color(0.4, 0.35, 0.28), 0.1, 1.0],
	"snow": [Color(0.9, 0.92, 0.96), 0.9, 0.0], "snowpack": [Color(0.9, 0.91, 0.94), 0.5, 0.0],
}

var clods: GPUParticles3D
var dust: GPUParticles3D
var _clod_mat: ParticleProcessMaterial
var _dust_mat: ParticleProcessMaterial
var _look: StandardMaterial3D
var _dust_look: StandardMaterial3D


func _ready() -> void:
	top_level = true
	if DisplayServer.get_name() == "headless":
		return
	_look = StandardMaterial3D.new()
	_look.vertex_color_use_as_albedo = true
	_look.roughness = 0.25 # wet clods catch the light
	var blob := SphereMesh.new()
	blob.radius = 0.035
	blob.height = 0.05
	blob.radial_segments = 6
	blob.rings = 3
	blob.material = _look
	_clod_mat = ParticleProcessMaterial.new()
	_clod_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_clod_mat.emission_box_extents = Vector3(0.1, 0.03, 0.05)
	_clod_mat.gravity = Vector3(0, -9.8, 0)
	_clod_mat.spread = 22.0
	_clod_mat.initial_velocity_min = 2.0
	_clod_mat.initial_velocity_max = 5.0
	_clod_mat.scale_min = 0.6
	_clod_mat.scale_max = 2.2
	_clod_mat.angular_velocity_min = -400.0
	_clod_mat.angular_velocity_max = 400.0
	_clod_mat.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	_clod_mat.collision_friction = 0.9
	_clod_mat.collision_bounce = 0.05
	clods = GPUParticles3D.new()
	clods.process_material = _clod_mat
	clods.draw_pass_1 = blob
	clods.amount = 90
	clods.lifetime = 2.2
	clods.local_coords = false
	clods.emitting = false
	clods.visibility_aabb = AABB(Vector3(-8, -3, -8), Vector3(16, 8, 16))
	add_child(clods)
	_dust_look = StandardMaterial3D.new()
	_dust_look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_dust_look.vertex_color_use_as_albedo = true
	_dust_look.albedo_texture = _puff()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	quad.material = _dust_look
	_dust_mat = ParticleProcessMaterial.new()
	_dust_mat.gravity = Vector3(0, 0.15, 0)
	_dust_mat.spread = 50.0
	_dust_mat.initial_velocity_min = 0.4
	_dust_mat.initial_velocity_max = 1.2
	_dust_mat.damping_min = 0.6
	_dust_mat.damping_max = 1.0
	_dust_mat.scale_min = 0.8
	_dust_mat.scale_max = 2.0
	var grow := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.0))
	grow.curve = c
	_dust_mat.scale_curve = grow
	var fade := GradientTexture1D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.35))
	g.set_color(1, Color(1, 1, 1, 0.0))
	fade.gradient = g
	_dust_mat.color_ramp = fade
	dust = GPUParticles3D.new()
	dust.process_material = _dust_mat
	dust.draw_pass_1 = quad
	dust.amount = 24
	dust.lifetime = 2.5
	dust.local_coords = false
	dust.emitting = false
	dust.visibility_aabb = AABB(Vector3(-10, -2, -10), Vector3(20, 8, 20))
	add_child(dust)


## This step: at the contact patch `at`, rolling `back` (the way the tread throws: behind the
## wheel), `speed` m/s on `label` ground, `slip` m/s of wheelspin, wet 0..1.
func spray(at: Vector3, back: Vector3, speed: float, slip: float, label: String, wet: float) -> void:
	if clods == null:
		return
	global_position = at
	var k: Array = KINDS.get(label, [Color(0.3, 0.25, 0.18), 0.0, 0.0])
	var throw := float(k[1]) * clampf(absf(speed) / 6.0 + slip * 0.6, 0.0, 2.0)
	if label in ["grass", "dirt", "gravel"]:
		throw += wet * 0.5 * clampf(absf(speed) / 6.0, 0.0, 1.0) # (soaked by the rain)
	clods.emitting = throw > 0.05
	if clods.emitting:
		clods.amount_ratio = clampf(throw * 0.5, 0.05, 1.0)
		_clod_mat.color = k[0]
		_clod_mat.direction = (back + Vector3.UP * (0.9 + slip * 0.15)).normalized()
		_clod_mat.initial_velocity_max = 3.0 + slip * 1.5 + absf(speed) * 0.25
	var puff := float(k[2]) * clampf((absf(speed) - 3.0) / 10.0, 0.0, 1.0) * (1.0 - wet)
	dust.emitting = puff > 0.05
	if dust.emitting:
		dust.amount_ratio = clampf(puff, 0.1, 1.0)
		_dust_mat.color = (k[0] as Color).lightened(0.25)
		_dust_mat.direction = (back + Vector3.UP * 0.6).normalized()


static func _puff() -> ImageTexture:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.8))
	return ImageTexture.create_from_image(img)
