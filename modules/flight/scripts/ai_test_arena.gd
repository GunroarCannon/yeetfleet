## The AI test arena: a small translucent box the fleet fights inside.
##
## Visual only — ships fly freely (gravity is off, no walls collide). The box
## gives the eye a spatial frame so a team battle reads as happening in a place,
## not in an infinite void, and the bright edges make the bounds obvious.
class_name AiTestArena
extends Node3D

## Half-extents of the box, metres.
const ARENA_HALF := Vector3(2000.0, 1000.0, 2000.0)

var _wall_mesh: MeshInstance3D
var _edge_mesh: MeshInstance3D


func _ready() -> void:
	_build_walls()
	_build_edges()


## Six translucent faces. Drawn as a single unshaded, additive quad mesh so the
## walls are a faint blue glass rather than a solid cube.
func _build_walls() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var minp := -ARENA_HALF
	var maxp := ARENA_HALF
	# Six faces, each two triangles, wound outward.
	var faces := [
		# Bottom
		[Vector3(minp.x, minp.y, minp.z), Vector3(maxp.x, minp.y, minp.z), Vector3(maxp.x, minp.y, maxp.z), Vector3(minp.x, minp.y, maxp.z)],
		# Top
		[Vector3(minp.x, maxp.y, minp.z), Vector3(minp.x, maxp.y, maxp.z), Vector3(maxp.x, maxp.y, maxp.z), Vector3(maxp.x, maxp.y, minp.z)],
		# Back
		[Vector3(minp.x, minp.y, minp.z), Vector3(minp.x, maxp.y, minp.z), Vector3(maxp.x, maxp.y, minp.z), Vector3(maxp.x, minp.y, minp.z)],
		# Front
		[Vector3(minp.x, minp.y, maxp.z), Vector3(maxp.x, minp.y, maxp.z), Vector3(maxp.x, maxp.y, maxp.z), Vector3(minp.x, maxp.y, maxp.z)],
		# Left
		[Vector3(minp.x, minp.y, minp.z), Vector3(minp.x, minp.y, maxp.z), Vector3(minp.x, maxp.y, maxp.z), Vector3(minp.x, maxp.y, minp.z)],
		# Right
		[Vector3(maxp.x, minp.y, minp.z), Vector3(maxp.x, maxp.y, minp.z), Vector3(maxp.x, maxp.y, maxp.z), Vector3(maxp.x, minp.y, maxp.z)],
	]
	for face in faces:
		st.set_color(Color(0.25, 0.45, 0.8, 0.07))
		st.add_vertex(face[0])
		st.set_color(Color(0.25, 0.45, 0.8, 0.07))
		st.add_vertex(face[1])
		st.set_color(Color(0.25, 0.45, 0.8, 0.07))
		st.add_vertex(face[2])
		st.set_color(Color(0.25, 0.45, 0.8, 0.07))
		st.add_vertex(face[0])
		st.set_color(Color(0.25, 0.45, 0.8, 0.07))
		st.add_vertex(face[2])
		st.set_color(Color(0.25, 0.45, 0.8, 0.07))
		st.add_vertex(face[3])
	_wall_mesh = MeshInstance3D.new()
	_wall_mesh.name = "Walls"
	_wall_mesh.mesh = st.commit()
	var wall_mat := StandardMaterial3D.new()
	wall_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_mat.vertex_color_use_as_albedo = true
	wall_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wall_mat.no_depth_test = false
	_wall_mesh.material_override = wall_mat
	_wall_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wall_mesh)


## The 12 box edges, drawn bright so the arena bounds are unambiguous.
func _build_edges() -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var minp := -ARENA_HALF
	var maxp := ARENA_HALF
	var corners := [
		Vector3(minp.x, minp.y, minp.z), Vector3(maxp.x, minp.y, minp.z),
		Vector3(maxp.x, minp.y, maxp.z), Vector3(minp.x, minp.y, maxp.z),
		Vector3(minp.x, maxp.y, minp.z), Vector3(maxp.x, maxp.y, minp.z),
		Vector3(maxp.x, maxp.y, maxp.z), Vector3(minp.x, maxp.y, maxp.z),
	]
	var edges := [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]
	var col := Color(0.55, 0.7, 1.0, 0.6)
	for e in edges:
		im.surface_set_color(col)
		im.surface_add_vertex(corners[e[0]])
		im.surface_set_color(col * 0.8)
		im.surface_add_vertex(corners[e[1]])
	im.surface_end()
	_edge_mesh = MeshInstance3D.new()
	_edge_mesh.name = "Edges"
	_edge_mesh.mesh = im
	var edge_mat := StandardMaterial3D.new()
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.no_depth_test = true
	edge_mat.vertex_color_use_as_albedo = true
	edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_edge_mesh.material_override = edge_mat
	_edge_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_edge_mesh)
