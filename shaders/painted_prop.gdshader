shader_type spatial;

// The painted-miniature look for props and vehicles (scripts/painted_look.gd): the model's
// own flat colour, lit soft, a touch lighter on top faces, and darkened toward the
// silhouette, so every crate, tank and bonnet carries a soft painted outline of its own.
// `camo`: a two-tone net. Its pattern is drawn here in world space as soft blobs, so the
// net's overlapping patches can all share one material, with nothing to fight over at range.

uniform vec3 albedo : source_color = vec3(0.5);
uniform vec3 albedo_b : source_color = vec3(0.46, 0.41, 0.3);
uniform float roughness = 0.7;
uniform float metallic = 0.0;
uniform float rim = 0.38; // how dark the edge goes
uniform bool use_vertex_color = false;
uniform bool camo = false;

global uniform float weather_wetness;
global uniform float weather_snow;

varying vec3 w_normal;
varying vec3 w_pos;

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

void vertex() {
	w_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = albedo * (use_vertex_color ? COLOR.rgb : vec3(1.0));
	if (camo) {
		float n = vnoise(w_pos.xz * 0.55 + w_pos.y * 0.3) * 0.7 + vnoise(w_pos.xz * 1.6) * 0.3;
		c = mix(albedo, albedo_b, smoothstep(0.42, 0.58, n));
	}
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	c *= 1.0 - rim * pow(1.0 - facing, 2.2);
	c *= mix(1.0, 1.1, smoothstep(0.5, 0.95, w_normal.y));
	c *= mix(1.0, 0.75, weather_wetness * 0.6);
	float snow = smoothstep(0.4, 0.8, w_normal.y * weather_snow * 1.3);
	c = mix(c, vec3(0.88, 0.9, 0.95), snow);
	ALBEDO = c;
	ROUGHNESS = mix(roughness, 0.4, weather_wetness * 0.6);
	METALLIC = metallic;
	SPECULAR = 0.35;
}
