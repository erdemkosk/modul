shader_type spatial;
// Wood on a fire (Campfire): bark and split wood that char black from where the flames lick it,
// and glow through the cracks as embers, breathing brighter and dimmer. `char_amount` and
// `glow` come from the fire (one material per fire); the billets are a MultiMesh.

uniform vec3 bark : source_color = vec3(0.30, 0.22, 0.15);
uniform vec3 split : source_color = vec3(0.70, 0.55, 0.36);
uniform float char_amount : hint_range(0.0, 1.0) = 0.0;
uniform float glow : hint_range(0.0, 1.0) = 0.0;
uniform float ash : hint_range(0.0, 1.0) = 0.0; // burnt through: grey-white ash over the char
instance uniform float coal_bed = 0.0; // the bed of coals under the wood (Campfire), not a billet

varying vec3 v_obj;
varying float v_low;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	v_obj = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_low = 1.0 - clamp((v_obj.y - NODE_POSITION_WORLD.y) / 0.5, 0.0, 1.0); // the low ends burn first
}

void fragment() {
	// Grain along the billet (its length is the mesh's Y), knots and fibres across.
	float grain = vnoise(vec3(v_obj.x * 40.0, v_obj.y * 4.0, v_obj.z * 40.0));
	float big = vnoise(v_obj * 9.0);
	// The flat split faces are pale wood, the round back is bark.
	float face = step(0.0, NORMAL.y) * 0.0 + smoothstep(0.35, 0.65, abs(dot(NORMAL, vec3(0.0, 1.0, 0.0))));
	vec3 wood = mix(bark * (0.7 + 0.5 * grain), split * (0.8 + 0.3 * grain), 0.35 + 0.3 * face);
	// Charring creeps up from the low ends, patchy.
	float c = clamp(char_amount * 1.6 - (1.0 - v_low) * 0.6 + (big - 0.5) * 0.5, 0.0, 1.0);
	vec3 coal = vec3(0.035, 0.03, 0.028) * (0.7 + 0.6 * grain);
	vec3 col = mix(wood, coal, c);
	col = mix(col, vec3(0.55, 0.53, 0.5) * (0.7 + 0.4 * big), ash * smoothstep(0.3, 0.8, big + 0.3));
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.75, c);
	// Embers: thin cracks in the char (alligatored, as burnt wood splits), glowing in patches,
	// breathing; the rest of the char black.
	float cr = abs(vnoise(v_obj * vec3(34.0, 12.0, 34.0)) - 0.5);
	float cracks = 1.0 - smoothstep(0.0, 0.045, cr);
	float patches = smoothstep(0.42, 0.72, vnoise(v_obj * 7.0 + vec3(0.0, TIME * 0.06, 0.0)));
	float breathe = 0.6 + 0.4 * sin(TIME * 2.3 + big * 12.0);
	float hotc = smoothstep(0.55, 1.0, c);
	float hot = glow * hotc * (cracks * patches * 1.1 + 0.08 * v_low * patches) * breathe * (1.0 - ash * 0.8);
	// Flames lick the wood: a moving glow on it low down.
	float lick = vnoise(vec3(v_obj.x * 6.0, v_obj.y * 5.0 - TIME * 1.8, v_obj.z * 6.0));
	hot += glow * hotc * smoothstep(0.6, 0.95, lick) * 0.25 * v_low;
	vec3 ember_col = mix(vec3(1.0, 0.16, 0.02), vec3(1.0, 0.48, 0.1), smoothstep(0.3, 1.0, hot));
	EMISSION = ember_col * hot * 4.5;
	if (coal_bed > 0.5) {
		// The coal bed: black lumps cracked all over, glowing through, the glow crawling.
		float crawl = vnoise(v_obj * 14.0 + vec3(0.0, 0.0, TIME * 0.3));
		float veins = 1.0 - abs(vnoise(v_obj * 30.0 + vec3(TIME * 0.04)) * 2.0 - 1.0);
		float bright = smoothstep(0.55, 0.95, veins) * 0.8 + smoothstep(0.5, 0.9, crawl) * 0.6;
		float g = clamp(glow * 1.2, 0.0, 1.0) * (0.7 + 0.3 * sin(TIME * 1.7 + big * 9.0)) * (1.0 - ash * 0.9);
		ALBEDO = mix(vec3(0.03, 0.025, 0.022) * (0.6 + 0.8 * grain), vec3(0.5, 0.48, 0.45) * (0.7 + 0.4 * big), ash);
		ROUGHNESS = 0.9;
		EMISSION = mix(vec3(0.9, 0.12, 0.02), vec3(1.0, 0.45, 0.1), bright) * (bright * bright + 0.05) * g * 3.5;
	}
}
