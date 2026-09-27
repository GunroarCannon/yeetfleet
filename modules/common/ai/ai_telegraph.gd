## AiTelegraph: the warning an AI ship gives before it opens fire on the
## player — a hot glow swelling at its nose and a thin aim line reaching toward
## the player, both building over the wind-up ([member
## JuiceSettings.enemy_telegraph]) so a volley is readable before it lands.
##
## Owned by one [AiShip]; [method show_charge] every frame of the wind-up,
## [method hide_charge] when it ends. Unshaded additive, drawn over the depth
## so it reads against a bright planet or behind the ship's own hull.
class_name AiTelegraph
extends Node3D

const COLOR := Color(1.0, 0.25, 0.18)
const CORE := Color(1.0, 0.85, 0.6)

static var _sphere: SphereMesh = null
static var _box: BoxMesh = null

var _glow: MeshInstance3D
var _core: MeshInstance3D
var _line: MeshInstance3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_make_shared()
	_glow = _mesh(_sphere)
	_core = _mesh(_sphere)
	_line = _mesh(_box)
	visible = false


## One frame of the wind-up: [param t] 0..1 through it, the glow at
## [param nose] sized for a hull of [param hull_radius], the line toward
## [param aim_at].
func show_charge(nose: Vector3, aim_at: Vector3, hull_radius: float, t: float) -> void:
	visible = true
	var k := clampf(t, 0.0, 1.0)
	# A pulse that quickens as it charges.
	var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.001 * TAU * lerpf(3.0, 9.0, k))
	var r := hull_radius * lerpf(0.25, 0.7, k) * pulse
	_glow.global_transform = Transform3D(Basis().scaled(Vector3.ONE * r * 2.0), nose)
	_core.global_transform = Transform3D(Basis().scaled(Vector3.ONE * r * 0.9), nose)
	_tint(_glow, COLOR, 0.35 + 0.5 * k)
	_tint(_core, CORE, 0.5 + 0.5 * k)
	var to := aim_at - nose
	var length := to.length()
	if length < 1.0:
		_line.visible = false
		return
	# The line grows out toward the target as the charge builds.
	_line.visible = true
	var reach := length * lerpf(0.3, 0.85, k)
	var fwd := to / length
	var up := Vector3.UP if absf(fwd.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var b := Basis.looking_at(fwd, up)
	var w := maxf(hull_radius * 0.05, 0.12) * lerpf(0.6, 1.4, k)
	b = b.scaled_local(Vector3(w, w, reach))
	_line.global_transform = Transform3D(b, nose + fwd * reach * 0.5)
	_tint(_line, COLOR, 0.2 + 0.45 * k)


func hide_charge() -> void:
	visible = false


## Each part has its own material: only its alpha changes per frame.
func _mesh(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _tint(mi: MeshInstance3D, col: Color, alpha: float) -> void:
	(mi.material_override as StandardMaterial3D).albedo_color = Color(col, clampf(alpha, 0.0, 1.0))


static func _make_shared() -> void:
	if _sphere != null:
		return
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 16
	_sphere.rings = 8
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
