shader_type spatial;
// Sparks and embers going up off a fire (Campfire, GrassFire, Burning): tiny glowing flecks drawn
// as short streaks along the way they fly (the particles align their Y to their velocity), cooling
// from yellow-white through orange to a dull red as they age, twinkling, and blown along by the
// wind (weather_wind) the longer they've been up. Additive, one draw per emitter.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, skip_vertex_transform;

global uniform vec3 weather_wind;

uniform float size = 0.011; // m across
uniform float stretch = 3.5; // how long the streak is next to its width
uniform float drift = 1.2; // m carried by the end of its life per m/s of wind
uniform float energy = 6.0;

varying float v_age;
varying float v_rand;

void vertex() {
	v_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	v_rand = fract(float(INSTANCE_ID) * 0.7548776 + 0.31);
	vec3 centre = MODEL_MATRIX[3].xyz;
	centre.xz += weather_wind.xz * 15.0 * drift * v_age * v_age;
	// Wandering a little as they cool (embers flutter, they don't fly straight).
	centre.x += sin(TIME * (3.0 + v_rand * 4.0) + v_rand * 30.0) * 0.06 * v_age;
	centre.z += cos(TIME * (2.5 + v_rand * 3.0) + v_rand * 17.0) * 0.06 * v_age;
	vec3 up = MODEL_MATRIX[1].xyz;
	float len = length(up);
	up = len > 0.0001 ? up / len : vec3(0.0, 1.0, 0.0);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - centre);
	vec3 side = cross(up, to_cam);
	side = length(side) > 0.001 ? normalize(side) : vec3(1.0, 0.0, 0.0);
	float s = size * length(MODEL_MATRIX[0].xyz) * (1.0 - 0.5 * v_age);
	float l = s * mix(stretch, 1.4, v_age); // (slowing as they cool: shorter streaks)
	vec3 world = centre + side * VERTEX.x * s * 2.0 + up * VERTEX.y * l * 2.0;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = 1.0 - smoothstep(0.0, 1.0, length(p));
	a *= a;
	vec3 hot = mix(vec3(1.0, 0.85, 0.5), vec3(1.0, 0.35, 0.05), smoothstep(0.0, 0.45, v_age));
	hot = mix(hot, vec3(0.6, 0.06, 0.01), smoothstep(0.45, 1.0, v_age));
	float twinkle = 0.65 + 0.35 * sin(TIME * (14.0 + v_rand * 20.0) + v_rand * 60.0);
	float fade = (1.0 - smoothstep(0.7, 1.0, v_age)) * smoothstep(0.0, 0.04, v_age);
	ALBEDO = hot * a * energy * twinkle * fade * COLOR.a;
}
