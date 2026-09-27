// A face sticker: one textured quad, lit the way hulls are lit.
//
// Two placements share this shader. A hull sticker is an ordinary quad laid on
// the surface Whimsy found by raycast. A billboard face (rocks) turns to the
// camera and is pushed from the object's centre toward it by `push` -- on a
// roundish rock that lands the face on the very patch of surface the camera is
// looking at, so the rock appears to watch you. Its normal is the direction to
// the camera, which is also that patch's normal, so light falls on the face
// the way it falls on the rock around it.
//
// Lighting copies ship_part.gdshader's wrapped Lambert and hemisphere floor, so
// a face in shadow sits in the shadow rather than glowing like a decal.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled, skip_vertex_transform;

uniform sampler2D face_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float billboard : hint_range(0.0, 1.0) = 0.0;
// Billboard only: how far toward the camera to sit, in object units.
uniform float push = 0.9;
// Self-lit floor so the eyes still read on a shadowed hull.
uniform float floor_light : hint_range(0.0, 1.0) = 0.55;
uniform vec4 hemi_sky_color : source_color = vec4(0.80, 0.86, 1.0, 1.0);
uniform vec4 hemi_ground_color : source_color = vec4(0.52, 0.40, 0.64, 1.0);
uniform float wrap_amount : hint_range(0.0, 1.0) = 0.45;
// Fades the whole face, for expressions cross-fading or distance culling.
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
// A face on a light source (the star): no lighting, the art times `tint` is
// emitted as is. `tint` is linear and may exceed 1 to bloom.
uniform float unlit : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint = vec4(1.0);

varying float up_facing;

void vertex() {
	if (billboard > 0.5) {
		vec3 centre = MODEL_MATRIX[3].xyz;
		float scale = length(MODEL_MATRIX[0].xyz);
		vec3 cam = INV_VIEW_MATRIX[3].xyz;
		vec3 to_cam = normalize(cam - centre);
		vec3 side = cross(vec3(0.0, 1.0, 0.0), to_cam);
		// Looking straight up or down: any side vector will do.
		side = length(side) < 0.01 ? vec3(1.0, 0.0, 0.0) : normalize(side);
		vec3 up = cross(to_cam, side);
		vec3 world = centre + to_cam * push * scale + (side * VERTEX.x + up * VERTEX.y) * scale;
		up_facing = to_cam.y * 0.5 + 0.5;
		VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
		NORMAL = normalize((VIEW_MATRIX * vec4(to_cam, 0.0)).xyz);
	} else {
		up_facing = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y * 0.5 + 0.5;
		VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	}
}

void fragment() {
	vec4 t = texture(face_tex, UV);
	ALBEDO = t.rgb;
	ALPHA = t.a * opacity;
	vec3 hemi = mix(hemi_ground_color.rgb, hemi_sky_color.rgb, smoothstep(0.0, 1.0, up_facing));
	EMISSION = t.rgb * hemi * floor_light;
	if (unlit > 0.5) {
		ALBEDO = vec3(0.0);
		EMISSION = t.rgb * tint.rgb;
	}
}

void light() {
	float wrapped = clamp((dot(NORMAL, LIGHT) + wrap_amount) / (1.0 + wrap_amount), 0.0, 1.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * (wrapped * wrapped * (3.0 - 2.0 * wrapped) * ATTENUATION);
}
