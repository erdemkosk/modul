shader_type spatial;

// Weathered surfaces for the open world's built places (scripts/world_pois.gd): nothing out
// there is factory-clean. The base colour is mottled; vertical faces carry rain streaks running
// down; everything near the ground is splashed with mud up to knee height; upward faces gather
// dust and lichen. Paint chips and rusts, wood shows its grain along the boards.

uniform vec3 albedo : source_color = vec3(0.5);
uniform float roughness = 0.9;
uniform float metallic = 0.0;
uniform int kind = 0; // 0 plain, 1 wood, 2 painted metal, 3 bare metal, 4 stone/concrete, 5 cloth
uniform float wear = 1.0; // 0 = clean
instance uniform float ground_y = -10000.0; // world height of the ground the piece stands on

global uniform float weather_wetness;

varying vec3 w_pos;
varying vec3 w_nrm;

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
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p;
		a *= 0.5;
	}
	return s;
}

float tri(vec3 p, vec3 w, float s) {
	return fbm(p.zy * s) * w.x + fbm(p.xz * s) * w.y + fbm(p.xy * s) * w.z;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 w = pow(abs(w_nrm), vec3(4.0));
	w /= w.x + w.y + w.z;
	vec3 p = w_pos;
	float mottle = tri(p, w, 1.3);
	float big = tri(p, w, 0.25);
	vec3 c = albedo * mix(0.82, 1.12, mottle) * mix(0.9, 1.06, big);
	float rough = roughness;
	float metal = metallic;

	if (kind == 1) {
		c = mix(c, vec3(dot(c, vec3(0.33))) * vec3(1.05, 0.98, 0.9), 0.4 * wear); // sun and rain bleach it
		// Boards: grain runs along the longest side of the plank, here along world x or z.
		vec2 g = abs(w_nrm.x) > 0.5 ? p.zy : (abs(w_nrm.z) > 0.5 ? p.xy : p.xz);
		float grain = sin(g.x * 40.0 + fbm(g * vec2(0.6, 6.0)) * 12.0) * 0.5 + 0.5;
		c *= mix(0.85, 1.08, grain * 0.6 + fbm(g * vec2(1.5, 14.0)) * 0.4);
		c = mix(c, vec3(0.32, 0.31, 0.28) * 0.9, smoothstep(0.55, 0.85, big) * 0.35 * wear); // silvered by sun
	} else if (kind == 2) {
		// Paint chipped at edges and blotches, rust bleeding from the chips and running down.
		float chip = smoothstep(0.66, 0.72, tri(p, w, 1.6) + (big - 0.5) * 0.3) * wear; // a few broad worn patches, not speckle
		vec3 rust = mix(vec3(0.17, 0.09, 0.05), vec3(0.27, 0.14, 0.07), mottle);
		c = mix(c, rust, chip);
		float run = smoothstep(0.6, 0.85, fbm(vec2(p.x * 2.5 + p.z * 2.5, p.y * 0.35))) * (1.0 - w.y) * wear;
		c = mix(c, rust, run * 0.3);
		rough = mix(rough, 0.95, chip);
		metal = mix(metal, 0.2, chip);
	} else if (kind == 3) {
		float rust = smoothstep(0.45, 0.8, tri(p, w, 1.8) + (big - 0.5) * 0.5) * wear;
		c = mix(c, mix(vec3(0.2, 0.1, 0.05), vec3(0.3, 0.16, 0.08), mottle), rust * 0.8);
		rough = mix(rough, 0.9, rust);
		metal = mix(metal, 0.1, rust);
	} else if (kind == 4) {
		float pits = smoothstep(0.7, 0.75, tri(p, w, 6.0));
		c *= 1.0 - pits * 0.25;
	}

	// Rain streaks down vertical faces: dark lines falling from the top edges.
	float vertical = 1.0 - w.y;
	float streak = smoothstep(0.55, 0.8, fbm(vec2((p.x + p.z) * 4.0, p.y * 0.25))) * vertical * wear;
	c *= 1.0 - streak * 0.22;
	// Mud splashed up from the ground, to knee height above the place's footing (ground_y).
	float above = w_pos.y - ground_y;
	float splash = 1.0 - smoothstep(0.05, 0.45 + fbm(vec2(p.x + p.z, 0.0) * 1.5) * 0.5, above);
	splash *= smoothstep(0.3, 0.55, fbm(vec2(p.x + p.z, p.y) * 4.0) + 0.15) * vertical * wear;
	c = mix(c, vec3(0.17, 0.13, 0.09), splash * 0.75);
	rough = mix(rough, 0.95, splash);
	// Dust and lichen on top faces.
	float up = smoothstep(0.6, 0.95, w_nrm.y);
	float lichen = smoothstep(0.62, 0.8, fbm(p.xz * 1.7 + 4.0)) * up * wear * (kind == 1 || kind == 4 ? 1.0 : 0.3);
	c = mix(c, vec3(0.28, 0.3, 0.17), lichen * 0.5);
	c = mix(c, vec3(0.36, 0.32, 0.26), up * 0.15 * wear);
	// Wet: darker and glossier.
	c *= mix(1.0, 0.65, weather_wetness * (kind == 2 || kind == 3 ? 0.4 : 1.0));
	rough = mix(rough, 0.3, weather_wetness * 0.7);
	// Painted: richer colour, and a soft shade from the foot up, as a model lit from above.
	c = mix(vec3(dot(c, vec3(0.3, 0.59, 0.11))), c, 1.25);
	c *= mix(0.82, 1.05, smoothstep(0.0, 3.0, above));
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.4;
}
