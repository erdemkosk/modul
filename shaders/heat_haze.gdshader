shader_type spatial;
// The air shimmering over a fire (Campfire): a quad standing over the flames, turned to face
// the camera about its upright axis, that bends what's seen through it with noise rippling
// upward. Strongest just over the flames, nothing at its edges; `heat` (per fire) scales it.
// Only drawn close in (the fire gives it a visibility range).
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform, fog_disabled;

global uniform vec3 weather_wind;

instance uniform float heat : hint_range(0.0, 1.0) = 1.0;
uniform float strength = 0.012;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	vec3 cam_z = INV_VIEW_MATRIX[2].xyz;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), cam_z));
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0);
	vec2 sc = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	h = max(VERTEX.y * sc.y, 0.0);
	vec3 world = origin + right * VERTEX.x * sc.x + vec3(0.0, h, 0.0);
	world.xz += weather_wind.xz * 15.0 * 0.06 * h * h; // (the hot air leans with the wind too)
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y);
	float mask = (1.0 - smoothstep(0.25, 1.0, abs(p.x))) * smoothstep(0.0, 0.18, p.y) * (1.0 - smoothstep(0.45, 1.0, p.y));
	vec2 q = vec2(p.x * 5.0, p.y * 4.0 - TIME * 3.2);
	vec2 off = vec2(vnoise(q) - 0.5, vnoise(q + vec2(7.3, 2.1)) - 0.5);
	off += 0.5 * vec2(vnoise(q * 2.3 + 3.0) - 0.5, vnoise(q * 2.1 - 5.0) - 0.5);
	// (only what lies behind it bends: nothing in front is pulled in)
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float behind = clamp((-sv.z / sv.w + VERTEX.z) / 0.4, 0.0, 1.0);
	float dist_fade = 1.0 / (1.0 + max(-VERTEX.z, 0.0) * 0.15);
	vec2 uv = SCREEN_UV + off * strength * heat * mask * behind * dist_fade * 3.0;
	ALBEDO = textureLod(screen_tex, uv, 0.0).rgb;
	ALPHA = mask * behind * clamp(heat * 2.0, 0.0, 1.0);
}
