shader_type spatial;
// FxParticles' chunks: soil, stone chips, wood splinters, bits of glass thrown from where a round
// went in. Each a small lit box, tumbling as it flies, coming down on the floor under where it was
// struck (when it lands was worked out once, at its birth) and lying there a moment, then gone.
//   instance transform: origin p0, basis.x v0, basis.y size (x, y, z), basis.z (life, t_land, spin)
//   INSTANCE_CUSTOM: (born, seed, drag, floor_y)   COLOR: albedo (a = roughness)
render_mode blend_mix, cull_back, diffuse_lambert_wrap, shadows_disabled, skip_vertex_transform;

uniform float now = 0.0;
uniform float gravity = 9.8;

varying float v_rough;

mat3 axis_rot(vec3 ax, float a) {
	ax = normalize(ax);
	float s = sin(a);
	float c = cos(a);
	float oc = 1.0 - c;
	return mat3(vec3(oc * ax.x * ax.x + c, oc * ax.x * ax.y + ax.z * s, oc * ax.z * ax.x - ax.y * s),
		vec3(oc * ax.x * ax.y - ax.z * s, oc * ax.y * ax.y + c, oc * ax.y * ax.z + ax.x * s),
		vec3(oc * ax.z * ax.x + ax.y * s, oc * ax.y * ax.z - ax.x * s, oc * ax.z * ax.z + c));
}

void vertex() {
	vec3 p0 = MODEL_MATRIX[3].xyz;
	vec3 v0 = MODEL_MATRIX[0].xyz;
	vec3 size = MODEL_MATRIX[1].xyz;
	vec3 c = MODEL_MATRIX[2].xyz;
	float t = now - INSTANCE_CUSTOM.x;
	float life = max(c.x, 0.01);
	v_rough = COLOR.a;
	if (t < 0.0 || t > life) {
		VERTEX = (VIEW_MATRIX * vec4(p0, 1.0)).xyz;
		NORMAL = vec3(0.0, 0.0, 1.0);
	} else {
		float tt = min(t, c.y);
		float k = max(INSTANCE_CUSTOM.z, 0.01);
		vec3 gv = vec3(0.0, -gravity, 0.0);
		float e = (1.0 - exp(-k * tt)) / k;
		vec3 p = p0 + gv / k * tt + (v0 - gv / k) * e;
		p.y = max(p.y, INSTANCE_CUSTOM.w);
		float sd = INSTANCE_CUSTOM.y;
		vec3 ax = vec3(sin(sd * 12.9), cos(sd * 78.2), sin(sd * 37.7) + 0.3);
		mat3 r = axis_rot(ax, sd * 6.28 + c.z * tt);
		if (t > c.y) {
			// Down: lying flat-ish, the long side along the ground.
			r = axis_rot(vec3(0.0, 1.0, 0.0), sd * 6.28) * mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, -1.0), vec3(0.0, 1.0, 0.0));
		}
		float shrink = 1.0 - smoothstep(0.75, 1.0, t / life);
		vec3 local = r * (VERTEX * size * shrink);
		if (t > c.y) {
			local.y += size.z * 0.5 * shrink; // (resting on the floor, not in it)
		}
		VERTEX = (VIEW_MATRIX * vec4(p + local, 1.0)).xyz;
		NORMAL = normalize((VIEW_MATRIX * vec4(r * NORMAL, 0.0)).xyz);
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = v_rough;
}
