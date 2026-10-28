shader_type spatial;
render_mode cull_disabled;

// The test strip's ground, painted like the open world (the art direction): each surface's
// colour per 1 m cell, broken into broad soft patches, with only a faint 4 m grid left so
// speed and slope can still be read while tuning. Cells covered by a SoftPatch are cut out.
uniform sampler2D surface_mask : source_color, filter_nearest;
uniform float half_size = 128.0;
uniform vec3 line_color : source_color = vec3(0.12, 0.1, 0.08);
uniform float cell_size = 4.0;
uniform float grid_strength = 0.08; // (how much of the grid shows: faint, or none)
uniform sampler2D surface_soft : source_color, filter_linear; // (the mask again, read smooth for colour)

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ivec2 cell = clamp(ivec2(floor(world_pos.xz + half_size)), ivec2(0), textureSize(surface_mask, 0) - ivec2(1));
	vec4 surface = texelFetch(surface_mask, cell, 0);
	if (surface.a > 0.5) {
		discard;
	}
	vec2 xz = world_pos.xz;
	// the colour from the mask read smoothly, its edges pushed about by noise: zones run into each
	// other raggedly over a metre or two, not along a ruler
	vec2 warp = vec2(vnoise(xz * 0.35), vnoise(xz * 0.35 + 17.0)) * 2.4 - 1.2;
	vec2 suv = (xz + warp + half_size) / vec2(textureSize(surface_mask, 0));
	vec3 col = texture(surface_soft, suv).rgb;
	float patches = vnoise(xz * 0.05) * 0.7 + vnoise(xz * 0.21) * 0.3;
	float grain = vnoise(xz * 1.7) * 0.6 + vnoise(xz * 6.3) * 0.4;
	vec3 base = col * mix(0.86, 1.1, patches) * mix(0.92, 1.05, grain);
	base = mix(vec3(dot(base, vec3(0.3, 0.59, 0.11))), base, 1.2) * vec3(1.04, 1.0, 0.95); // warm, rich
	vec2 p = xz / cell_size;
	vec2 d = abs(fract(p - 0.5) - 0.5) / fwidth(p);
	float line = 1.0 - clamp(min(d.x, d.y), 0.0, 1.0);
	ALBEDO = mix(base, line_color, line * grid_strength);
	ROUGHNESS = 0.9;
}
