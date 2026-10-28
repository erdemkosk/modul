shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

// The helicopter's windows (Helicopter): thin, faintly green-grey glass you see straight through,
// with years on it: a film of dust thicker toward the lower edges, dried rain runs and dust streaks
// running down and back, fine scratches, and faint reflections that grow toward grazing angles.
// Worked in the helicopter's own coordinates (the Glass mesh sits at its origin), so it travels with
// the machine. Double-sided: the same pane seen from the cabin.

uniform vec3 tint : source_color = vec3(0.62, 0.7, 0.68);
uniform vec3 offset = vec3(0.0); // this mesh's origin in the helicopter's coordinates
uniform float clear = 0.08; // how much of the pane shows straight on, clean
uniform float dirt = 1.0;
uniform vec3 dust_color : source_color = vec3(0.56, 0.52, 0.44);

varying vec3 lp;
varying vec3 ln;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.1) * 0.3 + vnoise(p * 4.7 + 3.3) * 0.15;
}

void vertex() {
	lp = VERTEX + offset;
	ln = NORMAL;
}

void fragment() {
	// Pane coordinates: along the side (z) and up (y) on the side windows, across (x) and up on the
	// windscreen; y always runs up so the runs fall down.
	vec2 uv = abs(ln.x) > 0.6 ? vec2(lp.z, lp.y) : vec2(lp.x, lp.y + lp.z * 0.3);

	// Dust film: patchy, heavier low on the glass (the rotor wash throws it up there).
	float low = 1.0 - smoothstep(1.7, 2.6, lp.y);
	float film = fbm(uv * 2.6) * 0.55 + low * 0.35;
	film = smoothstep(0.3, 0.95, film);

	// Rain runs: thin, wavy lines falling down the pane, drying to a dusty edge; blown back in flight
	// (+z is aft).
	float wob = vnoise(vec2(uv.x * 3.0, uv.y * 2.0)) * 0.04;
	float col_id = floor((uv.x + wob + uv.y * 0.12) * 38.0);
	float cell = fract((uv.x + wob + uv.y * 0.12) * 38.0);
	float has_run = step(0.62, hash12(vec2(col_id, 3.1)));
	float run_len = mix(0.15, 0.6, hash12(vec2(col_id, 9.7)));
	float run_top = 1.7 + 1.2 * hash12(vec2(col_id, 5.3));
	float along = clamp((run_top - lp.y) / run_len, 0.0, 1.0);
	float run = has_run * smoothstep(0.42, 0.5, cell) * (1.0 - smoothstep(0.5, 0.58, cell))
		* step(lp.y, run_top) * (1.0 - along) * smoothstep(0.0, 0.05, run_top - lp.y);
	float drop = has_run * step(0.5, along) * (1.0 - smoothstep(0.0, 0.03, abs(lp.y - (run_top - run_len))));

	// Fine scratches: short straight arcs where the wipers and the rags went.
	vec2 sp = uv * vec2(1.0, 1.0);
	float sc = 0.0;
	for (int k = 0; k < 2; k++) {
		float a = 0.3 + float(k) * 1.9;
		vec2 d = vec2(cos(a), sin(a));
		float t = dot(sp, d) * 90.0;
		float line = 1.0 - smoothstep(0.0, 0.08, abs(fract(t) - 0.5) * 2.0 - 0.9);
		float seg = step(0.82, vnoise(vec2(floor(t), dot(sp, vec2(-d.y, d.x)) * 9.0)));
		sc = max(sc, line * seg * (1.0 - smoothstep(0.15, 0.6, fwidth(t)))); // gone before it shimmers
	}

	float d = clamp(film * 0.32 + run * 0.35 + drop * 0.25, 0.0, 1.0) * dirt;
	float ndv = clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fres = 0.04 + 0.96 * pow(1.0 - ndv, 5.0);

	ALBEDO = mix(tint * 0.08, dust_color, clamp(d * 1.6 + sc * 0.3, 0.0, 1.0));
	ROUGHNESS = mix(0.06, 0.65, clamp(d * 1.5, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.5;
	// The pane's own shade, a little dust, the reflection going up toward grazing.
	ALPHA = clamp(clear + d + sc * 0.06 + fres * 0.45, 0.0, 0.92);
}
