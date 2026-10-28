shader_type spatial;
render_mode cull_disabled;

// A vehicle that burnt out or rotted by the road. The original paint survives
// only in patches; the rest is soot, scorched primer gone pale grey, and rust
// that spreads from the bottom up and from the edges of the burnt areas.
// `burn` 0 = an old rusted wreck, 1 = a fresh war wreck, black with soot.
// The pattern comes from the model's own space, so each wreck differs by `seed`.

uniform vec3 paint : source_color = vec3(0.3, 0.32, 0.25);
uniform float burn : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;
uniform float ground_y = 0.0;
uniform float metal_part = 1.0; // 0 for tyres, wood, canvas: they char, they don't rust

varying vec3 local_pos;
varying float facing_up;

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
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

float fbm(vec3 p) {
	return noise(p) * 0.55 + noise(p * 2.3) * 0.28 + noise(p * 5.1) * 0.17;
}

void vertex() {
	local_pos = VERTEX + vec3(seed * 13.7, 0.0, seed * 7.1);
	facing_up = (MODEL_MATRIX * vec4(NORMAL, 0.0)).y;
}

void fragment() {
	float h = clamp((local_pos.y - ground_y) / 2.2, 0.0, 1.0);
	float big = fbm(local_pos * 1.4);
	float fine = fbm(local_pos * 9.0);
	// How badly each spot burnt: worst low down and towards the middle of the body.
	float heat = clamp(burn * (0.55 + big * 0.9 - h * 0.25), 0.0, 1.0);
	vec3 soot = vec3(0.012, 0.011, 0.01);
	vec3 ash = vec3(0.07, 0.065, 0.06); // paint burnt off to pale primer
	vec3 rust_dark = vec3(0.045, 0.014, 0.005);
	vec3 rust = vec3(0.16, 0.05, 0.015);
	vec3 faded = mix(paint, vec3(dot(paint, vec3(0.33))), 0.4) * 0.7;

	vec3 col = faded;
	// Rust: from the sills up, and in blotches.
	float rusty = smoothstep(0.35, 0.7, big * 0.8 + (1.0 - h) * 0.45 + fine * 0.2 - 0.15 + burn * 0.25);
	col = mix(col, mix(rust_dark, rust, fine), rusty * metal_part);
	// Fire: pale scorched rings round black soot.
	float scorch = smoothstep(0.35, 0.55, heat + fine * 0.15);
	col = mix(col, mix(ash, rust, fine * 0.6) * (metal_part > 0.5 ? 1.0 : 0.3), scorch * 0.6);
	float black = smoothstep(0.6, 0.85, heat + (fine - 0.5) * 0.3);
	col = mix(col, soot, black);
	// Dust and old leaves settle on what faces up.
	col = mix(col, vec3(0.08, 0.062, 0.04), smoothstep(0.6, 0.95, facing_up) * 0.35 * (1.0 - black));

	ALBEDO = col;
	ROUGHNESS = mix(0.7, 1.0, max(rusty, black));
	METALLIC = metal_part * (1.0 - max(rusty, black)) * 0.3;
}
