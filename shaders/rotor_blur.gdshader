shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// The blurred disc of a rotor at speed (Helicopter): the blades' shadow, darker towards the hub,
// with the painted tips as a faint band at the rim and a few slow streaks (what the eye catches
// of the blades going round). `amount` fades it in as the blades themselves fade out.
// The disc lies in the mesh's XZ plane (main rotor) or ZY plane (`tail`), centred on the hub.

uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float radius = 10.0;
uniform float hub = 0.06; // inner edge, fraction of the radius
uniform float blades = 5.0;
uniform float drift = 0.35; // rev/s the streaks seem to turn at (strobing, not the real rate)
uniform bool tail = false;
uniform vec3 blade_color : source_color = vec3(0.07, 0.075, 0.07);
uniform vec3 tip_color : source_color = vec3(0.72, 0.58, 0.16);

varying vec2 p;

void vertex() {
	p = tail ? VERTEX.zy : VERTEX.xz;
}

void fragment() {
	float r = length(p) / radius;
	float a = atan(p.y, p.x);
	float streak = pow(0.5 + 0.5 * sin(a * blades - TIME * drift * 6.2831853), 6.0);
	float body = mix(0.34, 0.08, smoothstep(0.05, 0.9, r)) * (0.7 + 0.6 * streak);
	float tip = smoothstep(0.9, 0.93, r) * (1.0 - smoothstep(0.975, 0.995, r));
	float alpha = max(body, tip * 0.3);
	alpha *= smoothstep(hub, hub + 0.03, r) * (1.0 - smoothstep(0.99, 1.004, r));
	ALBEDO = mix(blade_color, tip_color, tip);
	ALPHA = clamp(alpha * amount, 0.0, 1.0);
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}
