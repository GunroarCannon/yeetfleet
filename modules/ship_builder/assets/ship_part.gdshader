// Shared material for every ship part.
//
// Parts carry no textures. Vertex COLOR.r is a *mask index* selecting one of
// three palette channels, so retinting a whole ship is three uniform writes with
// no texture rebake -- the requirement behind the faction colour system.
//
// Written for the GL Compatibility renderer, which has no reflection probes and
// no screen-space ambient occlusion. Everything that would normally come from
// those is faked here, because without them painted metal reads as backlit
// plastic: a hemisphere occlusion term weights ambient by how much sky a facet
// can see, a per-facet value break stops large panels reading as one poured
// surface, and the rim is kept to a thin sliver so it reads as a lightbank
// catching an edge rather than as light passing through the hull.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec4 primary_color : source_color = vec4(0.29, 0.33, 0.40, 1.0);
uniform vec4 accent_color : source_color = vec4(0.87, 0.55, 0.16, 1.0);
uniform vec4 trim_color : source_color = vec4(0.09, 0.10, 0.13, 1.0);

uniform float roughness_amount : hint_range(0.0, 1.0) = 0.82;
uniform float metallic_amount : hint_range(0.0, 1.0) = 0.05;
// Dielectric reflectance. Held low because a compat-renderer specular lobe with
// nothing to reflect but a flat ambient colour is exactly what "plastic" looks
// like.
uniform float specular_amount : hint_range(0.0, 1.0) = 0.28;

// Panel wear: a per-cell hash darkens facets slightly. Cheap stand-in for a
// weathering texture, and it scales with the part rather than the world.
uniform float weathering : hint_range(0.0, 1.0) = 0.0;
uniform float panel_scale : hint_range(0.5, 12.0) = 3.0;
// Always-on plate variation, separate from weathering: even a factory-fresh hull
// is assembled from panels that took paint slightly differently.
uniform float plate_variation : hint_range(0.0, 0.5) = 0.06;

// Ambient occlusion faked from facet orientation: a down-facing plate sees the
// ground, an up-facing one sees the sky. Without this every facet takes the same
// ambient and the model looks lit from inside.
uniform float ao_strength : hint_range(0.0, 1.0) = 0.32;

// Self-lit floor, as a fraction of the part's own albedo.
//
// This is the single term that makes a hull read as *solid*. The builder stage
// and open space are both very nearly black, so any facet the lights miss falls
// to the same value as the void behind it -- and a shape whose unlit side
// matches the background does not read as "in shadow", it reads as "you can see
// through it". Lifting every facet to a healthy fraction of its own paint means
// the darkest part of the hull is still unmistakably hull and opaque.
uniform float solidity : hint_range(0.0, 1.0) = 0.72;

uniform vec4 rim_color : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.16;
uniform float rim_power : hint_range(0.5, 12.0) = 7.0;

// Cartoony shading step, driven by StyleProfile.shading_bands. 0 leaves the
// smooth hemisphere gradient alone; 2-3 quantizes it into a friendly toon ramp.
// Stepping the occlusion term rather than a real N-dot-L only works because
// this shader has no real light() override to band -- see the comment above
// `sky` in fragment() for why occlusion carries the shape here anyway.
uniform float shading_bands : hint_range(0.0, 5.0) = 0.0;

// Global toon override, driven by [ToonOverride] rather than by the profile.
// Forcing the stepped path from here means every part-shader surface — hulls,
// asteroids, station shells — flips to toon shading at once, without rewriting
// each material's shading_bands (which is the profile's dial to own).
uniform float toon_override : hint_range(0.0, 1.0) = 0.0;

// Vector Arcade / Geometry Wars wireframe mode
uniform float wireframe_mode : hint_range(0.0, 1.0) = 0.0;
uniform vec4 wireframe_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);

// StyleProfile.spec_amount/rim_amount, as multipliers rather than a script-side
// rewrite of specular_amount/rim_strength. Kept separate so any number of style
// pushes stay idempotent -- setting these twice with the same profile always
// lands on the same look, where multiplying the base uniform in place would
// compound each time apply_style_dials() ran.
uniform float spec_mult : hint_range(0.0, 2.0) = 1.0;
uniform float rim_mult : hint_range(0.0, 2.0) = 1.0;

// Selection / hover feedback, driven per part instance by the builder.
uniform vec4 highlight_color : source_color = vec4(1.0, 0.86, 0.25, 1.0);
uniform float highlight : hint_range(0.0, 1.0) = 0.0;
// Dim parts that are not the current selection, to make the selection pop
// without relying on colour alone.
uniform float dim : hint_range(0.0, 1.0) = 0.0;

// Glowing tech/visor/sensor strips (Image 1 cyan accents)
uniform vec4 glow_accent_color : source_color = vec4(0.0, 0.95, 1.0, 1.0);

// Atmospheric re-entry thermal glow
uniform float reentry_burn : hint_range(0.0, 1.0) = 0.0;
uniform vec4 reentry_color : source_color = vec4(1.0, 0.45, 0.1, 1.0);

varying vec3 local_pos;

varying vec3 world_normal;

void vertex() {
	local_pos = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	// One flag for "this surface is in toon mode", set by either the profile's
	// band dial or the global override — see the uniform's own comment.
	float toon = (shading_bands > 0.5 || toon_override > 0.5) ? 1.0 : 0.0;

	// COLOR.r: 0.0 primary, 0.5 accent, 1.0 trim.
	float mask = COLOR.r;
	vec3 base = mix(primary_color.rgb, accent_color.rgb, smoothstep(0.20, 0.45, mask));
	base = mix(base, trim_color.rgb, smoothstep(0.70, 0.95, mask));

	// Two frequencies of panel hash: large plates, then a finer break-up so a
	// long fuselage is not one flat tone from nose to tail. In toon mode, keep
	// panels clean and silky without noisy stippling.
	float plate = hash13(floor(local_pos * panel_scale));
	float fine = hash13(floor(local_pos * panel_scale * 3.7) + 19.0);
	float eff_pv = (toon > 0.5) ? (plate_variation * 0.15) : plate_variation;
	float eff_w = (toon > 0.5) ? (weathering * 0.15) : weathering;
	base *= 1.0 - eff_pv * (plate - 0.5) * 2.0;
	base *= 1.0 - eff_w * (0.17 * plate + 0.08 * fine);

	// In cartoon mode: add crisp comic panel seams
	vec3 tech_glow = vec3(0.0);
	if (toon > 0.5) {
		vec3 p_grid = fract(local_pos * panel_scale);
		vec3 p_dist = abs(p_grid - 0.5);
		float edge = max(p_dist.x, max(p_dist.y, p_dist.z));
		float seam = smoothstep(0.47, 0.495, edge);
		base *= mix(1.0, 0.78, seam);
	}

	// Hemisphere occlusion. Up-facing plate: full ambient. Down-facing: shaded,
	// as if the hull below it were blocking the sky.
	float sky = world_normal.y * 0.5 + 0.5;
	if (toon > 0.5) {
		// Quantize into flat steps before the square falloff, so the toon ramp
		// reads as bands of shade rather than the smooth hemisphere gradient.
		// The band count falls back to a sensible default when the override is
		// what turned toon on and the profile's dial is still at zero.
		float bands = max(shading_bands, toon_override * 3.0);
		sky = floor(sky * bands) / max(bands - 1.0, 1.0);
		sky = clamp(sky, 0.0, 1.0);
	}
	float ao = mix(1.0 - ao_strength, 1.0, sky * sky);
	base *= ao;

	base = mix(base, base * 0.42, dim);

	ALBEDO = base;
	ROUGHNESS = clamp(roughness_amount + weathering * 0.12, 0.06, 1.0);
	METALLIC = metallic_amount;
	SPECULAR = specular_amount * ao * spec_mult;

	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fresnel = pow(1.0 - facing, rim_power);
	float rim = smoothstep(0.55, 1.0, fresnel) * mix(0.25, 1.0, sky);
	if (toon > 0.5) {
		// Clean stylized cartoon rim contour
		rim = smoothstep(0.48, 0.60, fresnel) * (0.85 + 0.15 * sky);
	}

	vec3 re_glow = vec3(0.0);
	if (reentry_burn > 0.001) {
		float nose_heat = smoothstep(-0.8, 1.5, -local_pos.z) * reentry_burn;
		float comp_heat = pow(1.0 - facing, 2.5) * reentry_burn * 1.5;
		re_glow = reentry_color.rgb * (nose_heat * 2.2 + comp_heat);
	}

	// In cartoon mode, scale down the flat self-illumination so directional
	// sunlight still produces readable cel-shaded shadows, while keeping
	// the shadow side rich and colorful.
	float eff_solidity = (toon > 0.5) ? (solidity * 0.60) : solidity;

	EMISSION = base * eff_solidity * (1.0 - dim * 0.5)
		+ rim_color.rgb * rim * (rim_strength * 0.35) * rim_mult * (1.0 - dim * 0.6)
		+ highlight_color.rgb * highlight * (0.12 + 0.9 * fresnel)
		+ re_glow
		+ tech_glow;

	if (wireframe_mode > 0.5) {
		// Vector Arcade wireframe: glowing vector lines along silhouettes, creases, and panel seams
		vec3 wf_col = (wireframe_color.a > 0.05) ? wireframe_color.rgb : base;
		float max_c = max(wf_col.r, max(wf_col.g, wf_col.b));
		if (max_c > 0.01) {
			wf_col = wf_col / max_c;
		}

		float rim_wire = pow(1.0 - facing, 2.6);
		vec3 p_frac = abs(fract(local_pos * 1.6) - 0.5);
		vec3 p_line = 1.0 - smoothstep(vec3(0.0), fwidth(local_pos * 1.6) * 1.8 + vec3(0.035), p_frac);
		float rib = max(p_line.x, max(p_line.y, p_line.z));

		vec3 fw_n = fwidth(NORMAL);
		float crease = clamp(length(fw_n) * 4.5, 0.0, 1.0);
		float edge = max(rim_wire * 1.6, max(rib * 1.1, crease * 1.8));

		if (edge < 0.20) {
			discard;
		}

		ALBEDO = wf_col * 1.25;
		EMISSION = wf_col * (edge * 1.5) + highlight_color.rgb * highlight * 2.5;
		ROUGHNESS = 0.1;
		METALLIC = 0.0;
	}
}

void light() {
	if (wireframe_mode <= 0.5) {
		float NdotL = dot(NORMAL, LIGHT);
		float toon = (shading_bands > 0.5 || toon_override > 0.5) ? 1.0 : 0.0;
		if (toon > 0.5) {
			// High-quality stepped cel-shading reflecting the shading_bands dial
			float num_bands = max(shading_bands, (toon_override > 0.5 ? 3.0 : 2.0));
			float band = 0.42;
			if (num_bands <= 2.0) {
				band = smoothstep(-0.20, -0.10, NdotL) * 0.40 + smoothstep(0.12, 0.22, NdotL) * 0.60;
			} else {
				float normalized_light = clamp((NdotL + 0.35) / 1.35, 0.0, 1.0);
				float stepped = floor(normalized_light * num_bands) / (num_bands - 1.0);
				float frac_part = fract(normalized_light * num_bands);
				float transition = smoothstep(0.0, 0.10, frac_part);
				band = mix(stepped, (floor(normalized_light * num_bands) + 1.0) / (num_bands - 1.0), transition * 0.20);
			}
			band = clamp(max(band, 0.42), 0.42, 1.0);
			vec3 toon_diffuse = LIGHT_COLOR * (band * ATTENUATION);
			DIFFUSE_LIGHT += ALBEDO * toon_diffuse;

			// Cartoon circular specular glint: crisp, tight glint
			vec3 half_vec = normalize(VIEW + LIGHT);
			float NdotH = max(dot(NORMAL, half_vec), 0.0);
			float spec_power = max(36.0 * (1.0 - ROUGHNESS * 0.5), 20.0);
			float spec = smoothstep(0.92, 0.97, pow(NdotH, spec_power));
			SPECULAR_LIGHT += LIGHT_COLOR * (spec * spec_mult * ATTENUATION * 0.65);
		} else {
			// Grounded standard lambert diffuse
			float diff = max(NdotL, 0.0);
			DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * (diff * ATTENUATION);

			// Grounded specular
			vec3 half_vec = normalize(VIEW + LIGHT);
			float NdotH = max(dot(NORMAL, half_vec), 0.0);
			float spec = pow(NdotH, 16.0 / max(ROUGHNESS * ROUGHNESS, 0.01));
			SPECULAR_LIGHT += LIGHT_COLOR * (spec * specular_amount * spec_mult * ATTENUATION);
		}
	}
}



