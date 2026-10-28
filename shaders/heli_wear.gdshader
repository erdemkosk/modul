shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// Years of use on the helicopter (Helicopter), drawn over its paint as a material overlay:
// - dust and dried mud thrown up on the belly and the lower sides, in splashes;
// - soot from the two exhausts, blown back along the engine deck and the boom;
// - rain and oil streaks running down the sides from the cowling and the seams;
// - grime gathered in patches, and the paint worn through to grey primer here and there.
// Inside the cabin it's only a trace of all that.
// Worked in the helicopter's own coordinates (`offset` = this mesh's origin in them), so it
// travels with the machine.

uniform vec3 offset = vec3(0.0);
uniform float amount = 1.0;

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
	// Surface coordinates that don't stretch on the sides, the top or the ends.
	vec2 side_uv = vec2(lp.z, lp.y);
	vec2 top_uv = vec2(lp.x, lp.z);
	vec2 uv = abs(ln.y) > 0.7 ? top_uv : (abs(ln.x) > abs(ln.z) ? side_uv : vec2(lp.x, lp.y));

	// Mud and dust from below.
	float low = 1.0 - smoothstep(0.7, 2.3, lp.y);
	float splash = smoothstep(0.42, 0.8, fbm(uv * 3.2) + low * 0.35);
	float mud = low * (0.35 + 0.65 * splash);

	// Exhaust soot: from the outlets at the sides of the engine deck, back along the deck and boom.
	float behind = lp.z + 0.5;
	float soot_y = 3.25 - max(behind, 0.0) * 0.07;
	float soot = smoothstep(-0.3, 0.6, behind) * exp(-max(behind, 0.0) / 6.5)
		* exp(-pow((lp.y - soot_y) / (0.45 + max(behind, 0.0) * 0.05), 2.0))
		* smoothstep(0.35, 0.95, abs(lp.x)) * (0.55 + 0.45 * vnoise(vec2(lp.z * 0.8, lp.y * 6.0)));

	// Streaks running down the sides, long and thin.
	float vert = 1.0 - abs(ln.y);
	float run = smoothstep(0.62, 0.95, vnoise(vec2((lp.z + lp.x) * 6.5, lp.y * 0.35)))
		* smoothstep(0.6, 2.6, lp.y) * vert;

	// Grime patches and worn paint.
	float grime = smoothstep(0.5, 0.85, fbm(uv * 0.9 + 11.0)) * 0.45;
	float chip = smoothstep(0.84, 0.9, vnoise(uv * 23.0)) * smoothstep(0.55, 0.75, fbm(uv * 1.7 + 5.0));

	vec3 mud_c = vec3(0.24, 0.19, 0.13);
	vec3 soot_c = vec3(0.03, 0.028, 0.025);
	vec3 run_c = vec3(0.12, 0.11, 0.08);
	vec3 chip_c = vec3(0.3, 0.3, 0.27);
	vec3 c = mud_c;
	float a = mud * 0.75;
	c = mix(c, run_c, step(a, run * 0.45));
	a = max(a, run * 0.45);
	c = mix(c, run_c, step(a, grime));
	a = max(a, grime);
	c = mix(c, chip_c, step(a, chip * 0.7));
	a = max(a, chip * 0.7);
	c = mix(c, soot_c, clamp(soot * 1.6, 0.0, 1.0));
	a = max(a, clamp(soot * 0.9, 0.0, 0.9));
	// Inside the cabin and cockpit (inner faces of the skin, the floor, benches): only a little grime.
	bool in_box = abs(lp.x) < 1.235 && lp.y > 0.95 && lp.y < 3.02 && lp.z > -7.0 && lp.z < 3.05;
	float inside = in_box && sign(lp.x) * ln.x < 0.35 ? 1.0 : 0.0;
	a *= mix(1.0, 0.08, inside);
	ALBEDO = c;
	ALPHA = clamp(a * amount, 0.0, 0.95);
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
}
