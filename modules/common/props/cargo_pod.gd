## CargoPod: a toy cargo canister — a fat gold capsule with two ink bands,
## end caps and a glowing stripe — for salvage pods in flight and the level
## pictures. Replaces the plain box that read as a primitive cube.
##
## [method build] returns a Node3D about [param length] long along its
## local X. Meshes and materials are shared by every pod.
class_name CargoPod
extends RefCounted

static var _body: CapsuleMesh = null
static var _band: TorusMesh = null
static var _cap: CylinderMesh = null
static var _stripe: BoxMesh = null
static var _mats := {}


static func build(length := 14.0, col := Color("ffcc1a")) -> Node3D:
	_ensure_meshes()
	var n := Node3D.new()
	n.name = "CargoPod"
	var k := length / 2.0
	var body := MeshInstance3D.new()
	body.mesh = _body
	body.material_override = _mat(col, 0.35)
	body.rotation_degrees = Vector3(0, 0, 90)
	body.scale = Vector3.ONE * k
	n.add_child(body)
	for side: float in [-0.45, 0.45]:
		var band := MeshInstance3D.new()
		band.mesh = _band
		band.material_override = _mat(Color("2a2238"), 0.0)
		band.rotation_degrees = Vector3(0, 0, 90)
		band.position = Vector3(side * k, 0, 0)
		band.scale = Vector3.ONE * k
		n.add_child(band)
		var cap := MeshInstance3D.new()
		cap.mesh = _cap
		cap.material_override = _mat(Color("2a2238"), 0.0)
		cap.rotation_degrees = Vector3(0, 0, 90)
		cap.position = Vector3(side * 2.15 * k, 0, 0)
		cap.scale = Vector3.ONE * k
		n.add_child(cap)
	var stripe := MeshInstance3D.new()
	stripe.mesh = _stripe
	stripe.material_override = _mat(Color(0.4, 0.9, 1.0), 2.0)
	stripe.position = Vector3(0, 0, 0.47 * k)
	stripe.scale = Vector3.ONE * k
	n.add_child(stripe)
	return n


static func _ensure_meshes() -> void:
	if _body != null:
		return
	_body = CapsuleMesh.new()
	_body.radius = 0.5
	_body.height = 2.0
	_body.radial_segments = 16
	_body.rings = 6
	_band = TorusMesh.new()
	_band.inner_radius = 0.47
	_band.outer_radius = 0.58
	_band.rings = 20
	_band.ring_segments = 8
	_cap = CylinderMesh.new()
	_cap.top_radius = 0.18
	_cap.bottom_radius = 0.26
	_cap.height = 0.14
	_cap.radial_segments = 10
	_stripe = BoxMesh.new()
	_stripe.size = Vector3(0.5, 0.12, 0.06)


static func _mat(col: Color, glow: float) -> StandardMaterial3D:
	var key := "%s/%.2f" % [col.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	if glow >= 1.0:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col * glow
	else:
		m.albedo_color = col
		m.roughness = 0.55
		m.emission_enabled = glow > 0.0
		m.emission = col * glow
		m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	_mats[key] = m
	return m
