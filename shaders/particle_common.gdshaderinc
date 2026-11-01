// Shared by fire.gdshader and smoke.gdshader (FireFx): a particle quad turned to face the view
// (turned on its own axis by the particle's angle, CUSTOM.x), cheap noise for the shapes to boil
// with, and soft edges where a quad cuts into the ground or a wall.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

float p_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float p_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(p_hash(i), p_hash(i + vec2(1.0, 0.0)), f.x), mix(p_hash(i + vec2(0.0, 1.0)), p_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float p_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		v += a * p_noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

// (call in vertex(): the quad faces the view, keeping the particle's scale)
void p_billboard(inout mat4 modelview, mat4 model, mat4 view, mat4 inv_view, float angle) {
	mat4 w = mat4(normalize(inv_view[0]), normalize(inv_view[1]), normalize(inv_view[2]), model[3]);
	w = w * mat4(vec4(cos(angle), -sin(angle), 0.0, 0.0), vec4(sin(angle), cos(angle), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	modelview = view * w * mat4(vec4(length(model[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(model[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(model[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

// 0 where the quad meets what's behind it, 1 `soft` m in front of it.
float p_soft(vec2 screen_uv, vec3 vertex, mat4 inv_projection, float soft) {
	float d = texture(depth_tex, screen_uv).r;
	vec4 v = inv_projection * vec4(screen_uv * 2.0 - 1.0, d, 1.0);
	float scene = -v.z / v.w;
	return clamp((scene + vertex.z) / soft, 0.0, 1.0);
}
