// The ink line round a drawing (tools/ink_icons.gd): the thing again, grown out along its normals
// and drawn from inside, so only its rim shows behind it, a little uneven like a pen's.
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec3 ink : source_color = vec3(0.16, 0.12, 0.09);
uniform float width = 0.03;

void vertex() {
	float wobble = 0.75 + 0.5 * fract(sin(dot(VERTEX.xz, vec2(12.9898, 78.233))) * 43758.5453);
	VERTEX += NORMAL * width * wobble;
}

void fragment() {
	ALBEDO = ink;
}
