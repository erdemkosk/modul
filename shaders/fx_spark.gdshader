shader_type spatial;
// FxParticles' sparks: a hot fleck streaking along its path (a round off steel, burning powder out
// of a shotgun's muzzle, water thrown up as a bright drop). Moves here from what it was born with:
// thrown, slowed by the air, falling, stopping on the floor under where it started. Drawn as a short
// streak along the way it flies, white-hot cooling through orange to dull red (`hot` = 1), or as a
// lit drop (`hot` = 0: water).
//   instance transform: origin p0, basis.x v0, basis.y (life, drag, floor_y), basis.z (width, streak s, gravity)
//   INSTANCE_CUSTOM: (born, seed, brightness, hot)   COLOR: tint
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform, fog_disabled;

uniform float now = 0.0;

varying float v_fade;
varying float v_age;
varying float v_bright;
varying float v_hot;

vec3 pos_at(vec3 p0, vec3 v0, float k, float g, float t) {
	vec3 gv = vec3(0.0, -g, 0.0);
	float e = (1.0 - exp(-k * t)) / k;
	return p0 + gv / k * t + (v0 - gv / k) * e;
}

void vertex() {
	vec3 p0 = MODEL_MATRIX[3].xyz;
	vec3 v0 = MODEL_MATRIX[0].xyz;
	vec3 a = MODEL_MATRIX[1].xyz;
	vec3 b = MODEL_MATRIX[2].xyz;
	float t = now - INSTANCE_CUSTOM.x;
	float life = max(a.x, 0.01);
	float k = max(a.y, 0.01);
	v_bright = INSTANCE_CUSTOM.z;
	v_hot = INSTANCE_CUSTOM.w;
	if (t < 0.0 || t > life) {
		v_fade = 0.0;
		v_age = 1.0;
		VERTEX = (VIEW_MATRIX * vec4(p0, 1.0)).xyz;
	} else {
		vec3 head = pos_at(p0, v0, k, b.z, t);
		vec3 tail = pos_at(p0, v0, k, b.z, max(t - b.y, 0.0));
		head.y = max(head.y, a.z);
		tail.y = max(tail.y, a.z);
		v_age = t / life;
		v_fade = pow(1.0 - v_age, 1.2);
		vec3 hv = (VIEW_MATRIX * vec4(head, 1.0)).xyz;
		vec3 tv = (VIEW_MATRIX * vec4(tail, 1.0)).xyz;
		vec3 along = hv - tv;
		float len = length(along);
		vec3 dir = len > 1e-5 ? along / len : vec3(0.0, 1.0, 0.0);
		vec3 side = normalize(cross(dir, normalize(hv)) + vec3(1e-5));
		// A streak never thinner than about a pixel and a half: far off it still glints.
		float px = 1.5 * (-hv.z) / (PROJECTION_MATRIX[1][1] * 540.0);
		float w = max(b.x, px);
		vec3 at = mix(tv, hv, VERTEX.y + 0.5);
		at += dir * (VERTEX.y) * w; // (rounded ends)
		VERTEX = at + side * VERTEX.x * w * 2.0;
	}
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float m = 1.0 - smoothstep(0.2, 1.0, abs(p.x));
	m *= 1.0 - smoothstep(0.6, 1.0, abs(p.y));
	float hot = v_hot;
	vec3 cool = mix(vec3(1.0, 0.95, 0.75), mix(vec3(1.0, 0.45, 0.08), vec3(0.6, 0.08, 0.02), smoothstep(0.4, 1.0, v_age)), smoothstep(0.0, 0.45, v_age));
	vec3 col = mix(COLOR.rgb, cool * COLOR.rgb, hot);
	ALBEDO = col * v_bright * (hot > 0.5 ? 1.0 : 0.6);
	ALPHA = clamp(m * v_fade, 0.0, 1.0);
}
