shader_type spatial;
// FxParticles' puffs: gun smoke, impact dust, a fine mist of blood. Every puff is one instance of
// a MultiMesh and moves on its own here, from what it was born with (nothing per frame on the
// CPU): its start, its push (slowed by the air), the wind carrying it off more and more, a slow
// rise. Lit by what's round it (a muzzle flash lights the smoke it just made, the sun its top),
// soft against what it drifts into.
//   instance transform: origin p0, basis.x v0, basis.y (size0, size1, life), basis.z (drag, rise, wind_k)
//   INSTANCE_CUSTOM: (born, seed, opacity, glow)   COLOR: tint
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert_wrap, specular_disabled, shadows_disabled, skip_vertex_transform;

uniform float now = 0.0;
uniform vec3 wind = vec3(0.0); // m/s
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying float v_age;
varying float v_alpha;
varying float v_seed;
varying float v_glow;
varying float v_t;

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
	vec3 p0 = MODEL_MATRIX[3].xyz;
	vec3 v0 = MODEL_MATRIX[0].xyz;
	vec3 sz = MODEL_MATRIX[1].xyz;
	vec3 mv = MODEL_MATRIX[2].xyz;
	float t = now - INSTANCE_CUSTOM.x;
	v_t = t;
	float life = max(sz.z, 0.01);
	v_seed = INSTANCE_CUSTOM.y;
	v_glow = INSTANCE_CUSTOM.w;
	if (t < 0.0 || t > life) {
		v_age = 1.0;
		v_alpha = 0.0;
		VERTEX = (VIEW_MATRIX * vec4(p0, 1.0)).xyz; // (all four corners on one point: nothing drawn)
	} else {
		float k = max(mv.x, 0.01);
		float e = (1.0 - exp(-k * t)) / k;
		vec3 p = p0 + v0 * e + wind * mv.z * (t - e) + vec3(0.0, mv.y * t, 0.0);
		float a = t / life;
		v_age = a;
		float s = mix(sz.x, sz.y, 1.0 - pow(1.0 - a, 2.6));
		v_alpha = INSTANCE_CUSTOM.z * smoothstep(0.0, 0.05, a) * pow(1.0 - a, 1.4);
		float ang = v_seed * 6.2831 + t * 0.25 * (fract(v_seed * 7.0) - 0.5);
		vec2 c = vec2(cos(ang), sin(ang));
		vec2 q = vec2(VERTEX.x * c.x - VERTEX.y * c.y, VERTEX.x * c.y + VERTEX.y * c.x) * s;
		VERTEX = (VIEW_MATRIX * vec4(p, 1.0)).xyz + vec3(q, 0.0);
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float sd = v_seed * 31.0;
	float n = vnoise(UV * 2.4 + sd) * 0.55 + vnoise(UV * 5.1 - sd + vec2(now * 0.07, 0.0)) * 0.3 + vnoise(UV * 10.0 + sd * 2.0) * 0.15;
	float a = 1.0 - smoothstep(0.0, 0.95, r + (n - 0.5) * 0.9);
	a *= a * (3.0 - 2.0 * a);
	a *= 1.0 - smoothstep(0.6, 0.99, r);
	a *= v_alpha;
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	a *= clamp((-sv.z / sv.w + VERTEX.z) / 0.25, 0.0, 1.0);
	// (very close to the eye: thinned, so a puff over the sights doesn't white the view out)
	a *= clamp((-VERTEX.z - 0.05) / 0.35, 0.0, 1.0);
	ALBEDO = COLOR.rgb * (0.78 + 0.35 * n);
	ALPHA = clamp(a, 0.0, 1.0);
	NORMAL = normalize(vec3(p * 0.7, 0.65));
	EMISSION = vec3(1.0, 0.5, 0.18) * v_glow * exp(-v_t * 40.0) * a * 1.5; // (lit by its own flash for a frame or two)
}
