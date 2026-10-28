shader_type spatial;
// The cage's audience (CageArena's MultiMesh): each a seated figure, its part told by UV.x (0 its
// body: the instance's colour, its shirt; 0.25 its legs; 0.5 its head; 1 its arms, UV.y which side).
// They sway a little all the time; `excite` (0 calm .. 1 on their feet) has them bounce and throw
// their arms up, each at its own moment (INSTANCE_CUSTOM.x its phase, .y how keen it is).

uniform float excite = 0.0;
uniform float lit = 0.0; // (light thrown on them from elsewhere: the stadium's at night)
uniform vec3 skin : source_color = vec3(0.78, 0.6, 0.48);
uniform vec3 trousers : source_color = vec3(0.12, 0.13, 0.16);

varying float part;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831;
	float keen = INSTANCE_CUSTOM.y;
	part = UV.x;
	float up = clamp(excite * 1.6 - keen * 0.7, 0.0, 1.0);
	// arms: about the shoulder, out and up
	if (part > 0.9) {
		float side = UV.y > 0.5 ? 1.0 : -1.0;
		vec2 sh = vec2(0.2 * side, 0.46);
		float a = side * mix(0.0, 2.7, up) * (0.85 + 0.15 * sin(TIME * 9.0 + phase));
		vec2 p = VERTEX.xy - sh;
		VERTEX.xy = sh + vec2(p.x * cos(a) - p.y * sin(a), p.x * sin(a) + p.y * cos(a));
	}
	// the sway, and the bounce of a crowd on its feet
	VERTEX.x += sin(TIME * 1.3 + phase) * 0.015;
	VERTEX.y += up * abs(sin(TIME * 7.0 + phase)) * 0.14;
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (part > 0.9 || (part > 0.4 && part < 0.6)) {
		c = skin * (0.85 + 0.3 * COLOR.r); // (skin a shade off with the shirt: no two alike)
	} else if (part > 0.2 && part < 0.3) {
		c = trousers;
	}
	ALBEDO = c;
	EMISSION = c * lit;
	ROUGHNESS = 0.85;
}
