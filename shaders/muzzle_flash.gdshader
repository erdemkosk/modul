shader_type spatial;
// A muzzle flash's parts (MuzzleFx), each a quad drawn here as one of:
//   mode 0  the star: facing the eye at the muzzle, a hot core and a few ragged prongs. Far off it
//           never shrinks below a few pixels, brighter at night: the flash you see from a ridge
//           away before the sound comes.
//   mode 1  a tongue of flame: along the quad's own -Z (the bore, or a brake's port), turned about
//           that line to face the eye, torn at the edge, white-yellow at the root going orange.
//   mode 2  the fireball: facing the eye, a soft lumpy orange ball (a Mosin's, a shotgun's bloom).
// A different shape every shot (`seed`); HDR bright so the glow takes it.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

global uniform float weather_daylight;

instance uniform float mode = 0.0;
instance uniform float seed = 0.0;
instance uniform float intensity = 1.0;
instance uniform vec2 size = vec2(0.1, 0.1); // mode 1: (length, width); else (diameter, -)
instance uniform vec3 tint = vec3(1.0, 0.62, 0.25);
instance uniform float rays = 4.0;
instance uniform float far_min_px = 0.0; // mode 0: never smaller than this (m: a few pixels where it is)

varying float v_boost;
varying float v_far; // how far past its own size it was grown (seen from afar): a round glow then, not prongs

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

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 3.7) * 0.3 + vnoise(p * 4.3 - 1.3) * 0.15;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - origin;
	float dist = length(to_cam);
	to_cam /= max(dist, 1e-4);
	v_boost = 1.0;
	v_far = 0.0;
	vec3 world;
	if (mode > 0.5 && mode < 1.5) {
		vec3 axis = -normalize(MODEL_MATRIX[2].xyz);
		vec3 side = cross(axis, to_cam);
		float sl = length(side);
		side = sl > 0.05 ? side / sl : normalize(MODEL_MATRIX[0].xyz);
		world = origin + axis * (VERTEX.y + 0.5) * size.x + side * VERTEX.x * size.y;
	} else {
		vec3 right = normalize(INV_VIEW_MATRIX[0].xyz);
		vec3 up = normalize(INV_VIEW_MATRIX[1].xyz);
		float d = size.x;
		if (far_min_px > 0.0) {
			float px = far_min_px; // (the smallest it may be, in metres there: worked out by MuzzleFx)
			float night = 1.0 - clamp(weather_daylight, 0.0, 1.0);
			px *= mix(0.6, 1.4, night);
			if (px > d) {
				v_boost = mix(1.2, 2.5, night);
				v_far = clamp(px / d - 1.0, 0.0, 1.0);
				d = px;
			}
		}
		float a = seed * 6.2831;
		vec2 c = vec2(cos(a), sin(a));
		vec2 q = vec2(VERTEX.x * c.x - VERTEX.y * c.y, VERTEX.x * c.y + VERTEX.y * c.x) * d;
		world = origin + right * q.x + up * q.y + to_cam * 0.01;
	}
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

vec3 ramp(float h) {
	// dull red at the edge -> orange -> yellow -> white at the heart
	vec3 c = mix(tint * vec3(0.9, 0.35, 0.12), tint, smoothstep(0.0, 0.45, h));
	c = mix(c, vec3(1.0, 0.86, 0.55), smoothstep(0.4, 0.8, h));
	return mix(c, vec3(1.0, 0.97, 0.9), smoothstep(0.8, 1.0, h));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float s = seed * 17.0;
	float m = 0.0;
	float heat = 0.0;
	if (mode > 0.5 && mode < 1.5) {
		// u: 0 at the root (the muzzle), 1 at the tip; v: across.
		float u = 1.0 - UV.y;
		float v = p.x;
		float n = fbm(vec2(u * 3.5 + s, v * 1.5 - s));
		float w = (0.35 + 0.65 * smoothstep(0.0, 0.25, u)) * pow(max(1.0 - u, 0.0), 0.8);
		w *= 0.55 + 0.75 * n;
		m = 1.0 - smoothstep(w * 0.55, w, abs(v));
		m *= 1.0 - smoothstep(0.75 + 0.2 * n, 1.0, u);
		// broken into licks along it, not one smooth blade
		m *= 0.55 + 0.45 * smoothstep(0.25, 0.6, fbm(vec2(u * 7.0 - s * 2.0, v * 3.0)));
		heat = (1.0 - abs(v) / max(w, 1e-3)) * (1.0 - u * 0.75);
	} else if (mode < 0.5) {
		float r = length(p);
		float a = atan(p.y, p.x);
		float k = max(rays, 2.0);
		float sector = floor((a / 6.2831 + 0.5) * k);
		float len = 0.45 + 0.55 * hash(vec2(sector, s));
		float prong = pow(abs(cos((a + s) * k * 0.5)), 10.0) * len;
		float n = fbm(vec2(a * 2.0 + s, r * 4.0));
		float reach = max(prong, 0.0) * (0.8 + 0.4 * n);
		m = (1.0 - smoothstep(reach * 0.4, reach, r)) * smoothstep(0.0, 0.05, reach);
		float core = exp(-r * r * 26.0);
		m = max(m * 0.85, core);
		m = mix(m, exp(-r * r * 2.5), v_far);
		core = mix(core, exp(-r * r * 3.5), v_far);
		heat = max(core, (1.0 - r / max(reach, 1e-3)) * 0.7);
	} else {
		float r = length(p);
		float n = fbm(p * 2.2 + s);
		float edge = 0.62 + 0.35 * n;
		m = 1.0 - smoothstep(edge * 0.4, edge, r);
		m *= 0.6 + 0.4 * fbm(p * 5.0 - s);
		heat = (1.0 - r / edge) * 0.75;
	}
	m = clamp(m, 0.0, 1.0);
	vec3 col = ramp(clamp(heat, 0.0, 1.0));
	ALBEDO = col * intensity * v_boost * (1.5 + 5.0 * heat);
	ALPHA = m;
}
