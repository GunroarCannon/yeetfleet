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
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

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
// through it". Lifting every facet to a small fraction of its own paint means
// the darkest part of the hull is still unmistakably hull. Kept low enough that
// the lit side still carries the form.
uniform float solidity : hint_range(0.0, 0.5) = 0.17;

uniform vec4 rim_color : source_color = vec4(0.55, 0.75, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.16;
uniform float rim_power : hint_range(0.5, 12.0) = 7.0;

// Selection / hover feedback, driven per part instance by the builder.
uniform vec4 highlight_color : source_color = vec4(1.0, 0.86, 0.25, 1.0);
uniform float highlight : hint_range(0.0, 1.0) = 0.0;
// Dim parts that are not the current selection, to make the selection pop
// without relying on colour alone.
uniform float dim : hint_range(0.0, 1.0) = 0.0;

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
	// COLOR.r: 0.0 primary, 0.5 accent, 1.0 trim.
	float mask = COLOR.r;
	vec3 base = mix(primary_color.rgb, accent_color.rgb, smoothstep(0.20, 0.45, mask));
	base = mix(base, trim_color.rgb, smoothstep(0.70, 0.95, mask));

	// Two frequencies of panel hash: large plates, then a finer break-up so a
	// long fuselage is not one flat tone from nose to tail.
	float plate = hash13(floor(local_pos * panel_scale));
	float fine = hash13(floor(local_pos * panel_scale * 3.7) + 19.0);
	base *= 1.0 - plate_variation * (plate - 0.5) * 2.0;
	base *= 1.0 - weathering * (0.17 * plate + 0.08 * fine);

	// Hemisphere occlusion. Up-facing plate: full ambient. Down-facing: shaded,
	// as if the hull below it were blocking the sky.
	float sky = world_normal.y * 0.5 + 0.5;
	float ao = mix(1.0 - ao_strength, 1.0, sky * sky);
	base *= ao;

	base = mix(base, base * 0.42, dim);

	ALBEDO = base;
	ROUGHNESS = clamp(roughness_amount + weathering * 0.12, 0.06, 1.0);
	METALLIC = metallic_amount;
	SPECULAR = specular_amount * ao;

	// Rim: a thin edge sliver only, biased to the upper half of the hull so it
	// reads as a light source above the ship rather than a glass shell.
	//
	// The abs() is not a stylistic choice. Under GL Compatibility this VIEW comes
	// back pointing the opposite way to the Vulkan convention, so the textbook
	// `1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0)` clamps to zero and hands back a
	// fresnel of 1.0 on *every* pixel -- a full-strength emissive glaze over the
	// whole hull, which is what made the ships read as backlit plastic and made
	// selecting a part repaint it end to end. Taking the magnitude gives the same
	// edge falloff whichever way the renderer hands the vector over.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fresnel = pow(1.0 - facing, rim_power);
	// Clip the sliver to the last few degrees of grazing angle. A fresnel that
	// still has value at 45 degrees is a glaze over the whole facet, and a glaze
	// over a facet is what glass looks like.
	float rim = smoothstep(0.55, 1.0, fresnel) * mix(0.25, 1.0, sky);
	// Selection reads as a lit edge, not a wash. A flat emissive flood repaints
	// the part in the highlight colour -- and since the chassis is what the
	// builder has selected at rest, that flood meant every ship first appeared in
	// selection gold rather than its own paint. The brackets and the dimming of
	// everything else carry the rest of the message.
	EMISSION = base * solidity * (1.0 - dim * 0.5)
		+ rim_color.rgb * rim * rim_strength * (1.0 - dim * 0.6)
		+ highlight_color.rgb * highlight * (0.12 + 0.9 * fresnel);
}
