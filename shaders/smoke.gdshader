shader_type spatial;
// Smoke off a fire (Campfire, GrassFire, Burning): soft, torn, slowly turning puffs facing the
// camera, lit by what's round them (the fire's own light makes the low smoke glow orange at
// night, the sun lights its top by day), carried off by the wind (weather_wind) more the older
// they are, so the column rises and bends over downwind. Soft against the ground and whatever
// it drifts into (the depth buffer). The particles' COLOR.a fades each puff in and out over its
// life; INSTANCE_CUSTOM: x its turn, y how far through its life it is.
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled, shadows_disabled, skip_vertex_transform;

global uniform vec3 weather_wind;

uniform vec3 tint : source_color = vec3(0.32, 0.31, 0.3);
uniform vec3 old_tint : source_color = vec3(0.5, 0.5, 0.5); // what it thins to, higher up
uniform float density = 0.4;
uniform float drift = 1.8; // m it's carried by the end of its life per m/s of wind
uniform float fire_glow = 0.0; // the fire under it, lighting the youngest puffs from inside
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

varying float v_seed;
varying float v_age;

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_seed = fract(float(INSTANCE_ID) * 0.6180339) * 37.0;
	vec3 centre = MODEL_MATRIX[3].xyz;
	// The wind carries it off, more and more as it ages (it starts with the fire's updraft).
	centre.xz += weather_wind.xz * 15.0 * drift * pow(v_age, 1.6);
	float s = length(MODEL_MATRIX[0].xyz);
	float ang = INSTANCE_CUSTOM.x + TIME * 0.12 * (fract(v_seed) - 0.5);
	vec2 c = vec2(cos(ang), sin(ang));
	vec2 v = vec2(VERTEX.x * c.x - VERTEX.y * c.y, VERTEX.x * c.y + VERTEX.y * c.x) * s;
	VERTEX = (VIEW_MATRIX * vec4(centre, 1.0)).xyz + vec3(v, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// Billowing, slowly churning inside; torn at the edge.
	float n = vnoise(UV * 2.6 + v_seed + vec2(0.0, TIME * 0.05)) * 0.55
		+ vnoise(UV * 5.3 - v_seed + vec2(TIME * 0.11, 0.0)) * 0.3
		+ vnoise(UV * 11.0 + v_seed * 2.0) * 0.15;
	float a = 1.0 - smoothstep(0.0, 0.95, r + (n - 0.5) * 0.8);
	a *= a * (3.0 - 2.0 * a);
	a *= 1.0 - smoothstep(0.62, 0.99, r); // (never anything at the quad's edge)
	a *= COLOR.a * density * (1.0 - 0.45 * v_age);
	// Soft against what it meets.
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	a *= clamp((-sv.z / sv.w + VERTEX.z) / 0.6, 0.0, 1.0);
	vec3 col = mix(tint, old_tint, smoothstep(0.1, 0.9, v_age));
	ALBEDO = col * (0.75 + 0.4 * n);
	ALPHA = clamp(a, 0.0, 1.0);
	// A rounded puff to the light: its edges wrap round.
	NORMAL = normalize(vec3(p * 0.75, 0.6));
	EMISSION = vec3(1.0, 0.36, 0.08) * fire_glow * pow(1.0 - v_age, 5.0) * (0.6 + 0.6 * n);
}
