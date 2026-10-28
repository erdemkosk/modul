shader_type spatial;
render_mode cull_disabled, depth_draw_always;

// Lake and river surface (scripts/world_decor.gd). Waves are two scrolling noise normal layers
// (along UV.x for the river, which follows the flow), depth from the depth buffer tints shallow
// water clear and deep water dark, the screen behind is refracted, and the sky reflects through
// Fresnel. Rain adds ripple rings.

uniform float flow_speed = 0.0;   // m/s along UV.x (river); 0 for the lake
uniform vec3 shallow_color : source_color = vec3(0.16, 0.36, 0.36);
uniform vec3 deep_color : source_color = vec3(0.05, 0.22, 0.26);
uniform float clarity = 3.0;      // metres of water before it is fully deep-coloured
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

global uniform vec3 weather_wind;
global uniform float weather_rain;
global uniform float weather_daylight;

varying vec3 world_pos;

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

float waves(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += vnoise(p) * a;
		p = mat2(vec2(1.7, 1.1), vec2(-1.1, 1.7)) * p;
		a *= 0.5;
	}
	return s;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 wind = weather_wind.xz;
	float choppy = 0.4 + length(wind) * 1.4 + weather_wind.y * 0.6;
	vec2 p1;
	vec2 p2;
	if (flow_speed > 0.0) {
		// UV: x along the river (m), y across it (m).
		p1 = vec2(UV.x * 0.5 - TIME * flow_speed, UV.y) * 0.22;
		p2 = vec2(UV.x * 0.4 - TIME * flow_speed * 1.3, UV.y * 1.2 + 4.0) * 0.5;
	} else {
		p1 = world_pos.xz * 0.05 - wind * TIME * 0.04;
		p2 = world_pos.xz * 0.13 + vec2(TIME * 0.03, -TIME * 0.02);
	}
	float e = 0.05;
	float w0 = waves(p1) + waves(p2) * 0.5;
	float wx = waves(p1 + vec2(e, 0.0)) + waves(p2 + vec2(e, 0.0)) * 0.5;
	float wz = waves(p1 + vec2(0.0, e)) + waves(p2 + vec2(0.0, e)) * 0.5;
	vec3 n = normalize(vec3((w0 - wx) * choppy * 0.9, 1.0, (w0 - wz) * choppy * 0.9));
	// A mountain river is broken water: small fast ripples riding on the swell, and white
	// streaks of foam drawn out along the current, thickest where it is shallow and fast.
	float foam = 0.0;
	if (flow_speed > 0.0) {
		vec2 q = vec2(UV.x * 1.6 - TIME * flow_speed * 2.2, UV.y * 1.9);
		float r0 = waves(q);
		float rx = waves(q + vec2(e, 0.0));
		float rz = waves(q + vec2(0.0, e));
		n = normalize(n + vec3((r0 - rx) * 1.6, 0.0, (r0 - rz) * 1.6));
		vec2 s = vec2(UV.x * 0.35 - TIME * flow_speed * 1.1, UV.y * 2.4);
		foam = smoothstep(0.66, 0.86, waves(s) + waves(s * 2.3 + 7.0) * 0.35 - 0.12);
	}
	if (weather_rain > 0.01) {
		vec2 rp = world_pos.xz * 1.5;
		vec2 ci = floor(rp);
		float t = TIME * 1.6 + hash12(ci) * 9.0;
		vec2 d = fract(rp) - 0.5 - (vec2(hash12(ci + 3.0), hash12(ci + 7.0)) - 0.5) * 0.5;
		float r = length(d);
		float ring = sin((r - fract(t) * 0.5) * 45.0) * smoothstep(0.5, 0.0, r) * (1.0 - fract(t));
		n.xz += normalize(d + 1e-4) * ring * 0.25 * weather_rain;
		n = normalize(n);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float thickness = clamp((-view.z) - (-VERTEX.z), 0.0, 100.0);
	float deep = 1.0 - exp(-thickness / clarity);
	vec2 refr_uv = SCREEN_UV + n.xz * 0.025 * clamp(thickness, 0.0, 1.0);
	vec3 behind = textureLod(screen_tex, refr_uv, 0.0).rgb;
	vec3 water = mix(behind * shallow_color * 2.6, deep_color, deep);
	float edge_foam = (1.0 - smoothstep(0.0, 0.25, thickness)) * 0.35;
	// Foam in the shallows and over stones, where the water is thin over the bed.
	foam = max(foam * mix(0.5, 1.0, 1.0 - smoothstep(0.3, 1.6, thickness)), 0.0) * step(0.001, flow_speed);
	foam = max(foam, (1.0 - smoothstep(0.05, 0.6, thickness)) * smoothstep(0.45, 0.7, waves(world_pos.xz * 1.3 - TIME * flow_speed)) * step(0.001, flow_speed));
	ALBEDO = vec3(0.82, 0.85, 0.84) * foam;
	// (the deep colour is drawn as light of its own: it dims with the daylight, or the river
	// glowed cyan through the night)
	EMISSION = (mix(behind * shallow_color * 2.6, deep_color * weather_daylight, deep) * (1.0 - edge_foam) + vec3(0.7) * edge_foam * 0.4 * weather_daylight) * (1.0 - foam);
	ROUGHNESS = mix(0.14 + weather_rain * 0.1, 0.8, foam);
	METALLIC = 0.0;
	SPECULAR = mix(0.5, 0.2, foam);
	ALPHA = clamp(0.35 + deep * 0.65 + edge_foam + foam, 0.0, 1.0);
}
