shader_type canvas_item;

// Looking through binoculars: two overlapping round fields side by side, black outside,
// the image darkening and going a little green-grey towards the rim of each lens.
// `fade` blacks it out as the binoculars come up to the eyes or go down.

uniform float aspect = 1.777;
uniform float fade : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float r = 0.46;
	float sep = 0.235;
	float d = min(length(p - vec2(-sep, 0.0)), length(p - vec2(sep, 0.0)));
	float inside = 1.0 - smoothstep(r - 0.018, r, d);
	float rim = smoothstep(r * 0.45, r, d); // 0 in the middle, 1 at the edge of the field
	vec3 tint = vec3(0.02, 0.045, 0.035);
	float a = mix(1.0, 0.05 + rim * rim * 0.55, inside);
	COLOR = vec4(mix(tint, vec3(0.0), 1.0 - inside), max(a, fade));
}
