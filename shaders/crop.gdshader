shader_type spatial;
render_mode cull_disabled;

// A field's tufts (Crop): its colour per tuft (green, gold, black where it burnt) over the mesh's
// own shading, dark at the foot and light at the tips and ears. The stalks sway on the global wind,
// in waves rolling across the field, more the taller they've grown; wet, they droop a little.

global uniform vec3 weather_wind;
global uniform float weather_wetness;
global uniform float weather_snow;

varying float v_h;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float hf = clamp(VERTEX.y, 0.0, 1.3);
	float strength = length(weather_wind.xz);
	vec2 dir = strength > 0.001 ? weather_wind.xz / strength : vec2(1.0, 0.0);
	float along = dot(root.xz, dir);
	float wave = sin(along * 0.45 - TIME * (1.4 + strength * 0.4)) * 0.5 + 0.5;
	float flutter = sin(TIME * 3.1 + hash(root.xz) * 6.28);
	float bend = (0.05 + strength * 0.12) * (0.6 + 0.4 * flutter) + wave * (0.05 + strength * 0.14);
	world.xz += dir * bend * hf * hf;
	world.y -= (bend * 0.3 + weather_wetness * 0.06) * hf * hf;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
	v_h = hf;
}

void fragment() {
	vec3 c = COLOR.rgb;
	c = mix(c, vec3(0.86, 0.88, 0.9), weather_snow * smoothstep(0.6, 1.0, v_h) * 0.6);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	BACKLIGHT = c * 0.35; // (the low sun through the blades)
}
