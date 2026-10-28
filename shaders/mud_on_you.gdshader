shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// Mud on the survivor (MudOnYou), drawn over the body as a material overlay. It builds up from
// the ground: the boots cake first, then the shins and knees, with spatter and drips higher up
// the more `amount` there is. Height is measured in the world from the feet (feet_y), the
// pattern in the mesh's own space. Fresh it is dark and glossy; dried,
// pale and matte.

uniform float amount = 0.0; // 0 clean .. 1 caked
uniform float wet = 1.0; // 1 fresh .. 0 dried
uniform float feet_y = 0.0;
uniform float snow = 0.0; // 0..1 snow caked on the boots and shins

varying vec3 lp;
varying float height;

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	lp = VERTEX; // (the body has no UVs; broad blotches only, so a leg moving under them hardly shows)
	height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - feet_y;
}

void fragment() {
	float blotch = noise(lp * 9.0) * 0.6 + noise(lp * 23.0) * 0.4;
	// Solid up to a ragged line: the boots at a little, the knees at a lot.
	float line = 0.12 + amount * 0.6 + (blotch - 0.5) * 0.1;
	float solid = smoothstep(0.0, 0.03, line - height) * smoothstep(0.0, 0.08, amount);
	// Spatter and drips above it, thinning out by the waist.
	float above = clamp(1.0 - (height - line) / 0.4, 0.0, 1.0);
	float spatter = smoothstep(0.68, 0.76, noise(lp * 40.0) + above * 0.2) * above * smoothstep(0.05, 0.4, amount);
	float m = max(solid, spatter);
	vec3 wet_c = vec3(0.23, 0.16, 0.095); // lighter than the trousers, or it would not show
	vec3 dry_c = vec3(0.42, 0.34, 0.24);
	ALBEDO = mix(dry_c, wet_c, wet) * (0.85 + 0.3 * blotch);
	ROUGHNESS = mix(0.9, 0.18, wet);
	// Snow packed on the boots and the trouser hems, white over the mud.
	float sline = 0.08 + snow * 0.3 + (blotch - 0.5) * 0.1;
	float s = smoothstep(0.0, 0.03, sline - height) * smoothstep(0.0, 0.1, snow) * smoothstep(0.35, 0.5, blotch + 0.2);
	ALBEDO = mix(ALBEDO, vec3(0.88, 0.9, 0.94), s);
	ROUGHNESS = mix(ROUGHNESS, 0.8, s);
	ALPHA = max(m * 0.95, s * 0.95);
}
