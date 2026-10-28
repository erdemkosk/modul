shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_back, shadows_disabled;
// Over a hurt part (its material_overlay): soot blackening in broken patches and the pocks of rounds,
// more of both the more it's hurt (`wear` 0 whole .. 1 about to come off). Multiplies what's under it,
// so it only ever darkens.

instance uniform float wear = 0.0;

varying vec3 wp;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wp = VERTEX; // (the part's own space: the soot stays put on it as it moves)
}

void fragment() {
	float n = noise(wp * 6.0) * 0.6 + noise(wp * 17.0) * 0.4;
	float soot = smoothstep(1.0 - wear * 1.1, 1.05 - wear * 0.7, n);
	// pocks: small dark dots, more as it's hurt
	vec3 cell = floor(wp * 22.0);
	float r = hash(cell);
	vec3 f = fract(wp * 22.0) - 0.5;
	float pock = (r < wear * 0.5) ? 1.0 - smoothstep(0.12, 0.22, length(f)) : 0.0;
	float dark = max(soot * 0.82, pock * 0.9);
	ALBEDO = vec3(1.0 - dark) * mix(vec3(1.0), vec3(0.9, 0.85, 0.8), soot);
}
