shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// Dirt over the whole truck, drawn as a material overlay on every mesh.
// `mud` builds up from the bottom: tyres, sills and wheel arches first, then
// streaks and spatter higher up; the roof stays mostly clean even fully
// coated. `snow` cakes the lower body and wheel arches and settles on flat,
// upward-facing panels (hood, roof, bed rails).
// Height comes from the truck's own frame (truck_inv); the spatter pattern
// from each part's own space, so it sticks to spinning wheels too.

uniform float mud : hint_range(0.0, 1.0) = 0.0;
uniform float snow : hint_range(0.0, 1.0) = 0.0;
uniform float fresh : hint_range(0.0, 1.0) = 0.0; // still wet (glossy, dark) -> dried to a pale crust
uniform vec3 wet_mud : source_color = vec3(0.13, 0.09, 0.055);
uniform vec3 dry_mud : source_color = vec3(0.30, 0.24, 0.17);
uniform vec3 snow_color : source_color = vec3(0.88, 0.9, 0.94);
uniform float ground_y = -0.99; // tyre contact height in the truck's space
uniform float roof_y = 1.35;
uniform mat4 truck_inv; // world -> truck space, set every frame by TruckMudFx

varying vec3 local_pos;
varying float height; // 0 at the ground, 1 at the roof
varying float facing_up; // world normal's y

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0); // quintic: no blocky creases
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
				   mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
				   mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return noise(p) * 0.5 + noise(p * 2.03) * 0.3 + noise(p * 4.1) * 0.2;
}

void vertex() {
	local_pos = VERTEX;
	vec3 in_truck = (truck_inv * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	height = clamp((in_truck.y - ground_y) / (roof_y - ground_y), 0.0, 1.0);
	facing_up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	float h = height;
	float blotch = fbm(local_pos * 3.5);
	float speck = fbm(local_pos * 11.0);
	// Run-off: dirt dribbles down in vertical streaks.
	float streak = fbm(vec3(local_pos.x * 9.0, local_pos.y * 1.5, local_pos.z * 9.0));

	// Solid mud up to a ragged line that climbs with `mud`...
	float line = mud * 0.75 + (blotch - 0.5) * 0.3;
	float solid = smoothstep(0.0, 0.06, line - h);
	// ...then spatter and streaks fading out above it, never reaching the roof much.
	float above = clamp(1.0 - (h - line) / 0.35, 0.0, 1.0);
	float spatter = smoothstep(0.62, 0.72, speck + above * 0.25) * above * smoothstep(0.05, 0.3, mud);
	float runs = smoothstep(0.55, 0.7, streak) * above * smoothstep(0.2, 0.6, mud) * 0.7;
	float m = max(solid, max(spatter, runs));
	// Wet and dark low down, drying paler and thinner higher up.
	vec3 mud_col = mix(wet_mud, dry_mud, clamp(h * 1.6 + (blotch - 0.5) * 0.4, 0.0, 1.0));
	// Still wet: dark and glossy all over; dried: the pale, dusty crust takes over.
	mud_col = mix(mix(mud_col, dry_mud * 1.1, 0.35), mix(mud_col, wet_mud * 0.8, 0.6), fresh);
	float mud_alpha = m * mix(0.95, 0.75, h);

	// Snow: caked on the lower body, settled on flat tops.
	float caked = smoothstep(0.0, 0.08, snow * 0.45 + (fbm(local_pos * 2.5) - 0.5) * 0.25 - h);
	float settled = smoothstep(0.75, 0.9, facing_up) * smoothstep(0.35, 0.55, fbm(local_pos * 1.8) + snow * 0.4) * snow;
	float s = max(caked, settled);

	ALBEDO = mix(mud_col, snow_color, s);
	ROUGHNESS = mix(mix(mix(0.6, 0.95, h), mix(0.12, 0.45, h), fresh), 0.8, s); // wet mud has a sheen, dried and snow are matte
	ALPHA = max(mud_alpha, s * 0.97);
}
