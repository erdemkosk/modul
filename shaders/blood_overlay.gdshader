shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert_wrap;

// Blood on what you carry (BloodOnYou: the gun, the first-person arms), drawn over the
// surface as a material overlay. Patches fixed on the piece (model space), more of it the more
// `amount`; wet and dark red with a gloss while fresh, drying to near black and matte.

uniform float amount = 0.0; // 0 clean .. 1 covered
uniform float wet = 1.0;    // 1 fresh .. 0 dried

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	// Broad splashes with spatter round their edges.
	float n = noise(lp * 16.0) * 0.65 + noise(lp * 45.0) * 0.35;
	float thr = 1.0 - amount * 0.42; // (at most about a third of it: a gun painted red all over reads as a red gun)
	float m = smoothstep(thr, thr + 0.05, n);
	if (m <= 0.002) {
		discard;
	}
	ALBEDO = mix(vec3(0.09, 0.008, 0.006), vec3(0.30, 0.016, 0.012), wet);
	ALPHA = m * 0.93;
	ROUGHNESS = mix(0.85, 0.14, wet);
	SPECULAR = mix(0.15, 0.6, wet);
}
