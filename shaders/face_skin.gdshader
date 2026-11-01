shader_type spatial;
render_mode diffuse_lambert_wrap;

// The realistic heads' skin (CharacterLook.apply on Survivor_Body's HeadSkin surface): a
// photographic MakeHuman skin (assets/character/heads/skin_*.png, CC0) tinted to the look's skin
// colour, with what the look adds on top: the shaved beard's shadow, a short crop of the hair's
// colour on the scalp, the ground under a worn beard darker, a little shade round the eyes, pores,
// a sheen on the forehead and nose. Graded a touch toward the painted world (less saturated,
// slightly warm) so a real face sits among painted clothes.
// mask_tex (build_heads.py): R where a beard grows, G round the eyes, B the scalp's hair.

uniform sampler2D skin_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D mask_tex : hint_default_black, filter_linear, repeat_disable; // (no mip maps)
// the skin's relief (pores, creases, wrinkles) and sheen, shared by every skin (skin_normal.png,
// skin_rough.png: Mindfront's CC0 "Aksel" skin, build_heads.py)
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float normal_depth = 0.3; // (the map is a weathered man's: kept faint on the living)
uniform vec3 tint : source_color = vec3(0.77, 0.54, 0.41); // the look's skin colour
uniform vec3 tex_mean : source_color = vec3(0.87, 0.6, 0.49); // the skin texture's mean over the face
uniform float tint_amount = 0.8;
uniform vec3 hair_color : source_color = vec3(0.29, 0.19, 0.13);
uniform float stubble = 0.35; // a shaved beard's shadow
uniform float beard = 0.0; // 1: a beard is worn over it
uniform float crop = 0.85; // the hair cropped short on the scalp
uniform float age = 0.25; // 0 young .. 1 old: a little paler and greyer, the hair greying
uniform float grade = 0.14; // toward the painted world: desaturated this much
uniform float roughness = 0.55;
uniform float specular = 0.3;

global uniform float weather_wetness;

float hash(vec2 p) {
	p = fract(p * vec2(0.1031, 0.1030));
	p += dot(p, p.yx + 33.33);
	return fract((p.x + p.y) * p.x);
}

float noise(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

vec3 bumped(vec3 n, vec3 pos, float h) {
	vec3 dpx = dFdx(pos);
	vec3 dpy = dFdy(pos);
	float dhx = dFdx(h);
	float dhy = dFdy(h);
	vec3 r1 = cross(dpy, n);
	vec3 r2 = cross(n, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	return normalize(abs(det) * n - grad);
}

void fragment() {
	vec3 tex = texture(skin_tex, UV).rgb;
	vec3 m = texture(mask_tex, UV).rgb;
	// tinted to the look's skin: the texture's detail kept, its overall colour the look's
	vec3 ratio = tint / max(tex_mean, vec3(0.02));
	vec3 c = tex * mix(vec3(1.0), ratio, tint_amount);
	vec2 px = UV * vec2(1024.0, 2048.0); // texels of the sheet (about 0.25 mm on the face)
	float fine = noise(px * 1.3);
	float dots = smoothstep(0.45, 0.85, hash(floor(px * 1.6)));
	vec3 hair = mix(hair_color, vec3(0.62, 0.6, 0.58), smoothstep(0.55, 1.0, age) * 0.6);
	// the shaved beard: dark dots of stubble in the skin, denser under a worn beard
	float st = m.r * clamp(stubble + beard * 0.6, 0.0, 1.0);
	c = mix(c, c * mix(vec3(1.0), hair * 1.4 + 0.05, 0.75), st * (0.45 + 0.55 * dots));
	// the scalp's short crop: hair's colour in fine strands
	float cr = m.b * crop;
	c = mix(c, hair * mix(0.45, 1.0, fine), cr * (0.78 + 0.2 * dots));
	// a little shade in the sockets, the lids' redness (the texture's) toned toward the skin's hue
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	c = mix(c, lum * tint / max(dot(tint, vec3(0.3, 0.59, 0.11)), 0.01), m.g * 0.4);
	c *= mix(1.0, 0.86, m.g * 0.6);
	// older: paler, greyer
	c = mix(c, vec3(dot(c, vec3(0.3, 0.59, 0.11))), age * 0.1);
	// graded toward the painted world
	c = mix(vec3(dot(c, vec3(0.3, 0.59, 0.11))), c, 1.0 - grade);
	c *= vec3(1.02, 1.0, 0.97);
	c *= mix(1.0, 0.72, weather_wetness * 0.5);
	// pores, finer on the face, the crop's stubble on the scalp
	float bump = noise(px * 2.2) * 0.00004 + cr * dots * 0.00008;
	NORMAL = bumped(NORMAL, VERTEX, bump);
	ALBEDO = c;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth * (1.0 - cr * 0.7);
	// the map's roughness (0.55 on average) about this skin's; a sheen where there's no hair
	float r = roughness + (texture(rough_tex, UV).r - 0.55) - (1.0 - m.r) * (1.0 - m.b) * 0.06;
	ROUGHNESS = mix(mix(r, 0.85, cr), 0.4, weather_wetness * 0.5);
	SPECULAR = mix(specular, 0.45, weather_wetness * 0.5);
	SSS_STRENGTH = 0.3;
}
