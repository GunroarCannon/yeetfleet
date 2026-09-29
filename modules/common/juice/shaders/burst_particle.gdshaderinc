// Shared body of the burst particle shaders (burst_glow / burst_chunk).
// A MultiMesh quad per particle: the instance transform carries the position
// and a uniform size; INSTANCE_CUSTOM carries the world velocity direction
// (xyz) and how much to stretch along it (w). The quad is turned to face the
// camera here and its long axis laid along the velocity as seen on screen, so
// a spark is a streak in the direction it flies from every angle — the old
// quads lay flat in the world and read as white slivers and squares.

// A per-particle number for the fragment stage (INSTANCE_ID is vertex-only).
varying float particle_seed;

void vertex() {
	particle_seed = float(INSTANCE_ID);
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 vdir = (VIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 0.0)).xyz;
	vec2 d = vdir.xy;
	float l = length(d);
	vec2 axis = l > 0.0001 ? d / l : vec2(0.0, 1.0);
	vec2 side = vec2(-axis.y, axis.x);
	float stretch = 1.0 + INSTANCE_CUSTOM.w;
	vec2 off = side * VERTEX.x * size + axis * VERTEX.y * size * stretch;
	VERTEX = centre + vec3(off, 0.0);
	NORMAL = vec3(0.0, 0.0, 1.0);
}
