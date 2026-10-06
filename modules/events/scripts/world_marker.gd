## A 3D billboarded marker that indicates in-world points of interest.
##
## Carries the icon vocabulary defined in GAMEDOC.md §9 (🚨, 🎯, 📦, ◆, !) as
## its [member symbol], but shows each as a short word in the game's head
## face ([method word_for]: SOS, FIGHT, CARGO…) — no emoji on screen.
## Billboards toward the camera, scales smoothly across distances, and modulates
## its glow/pulse for distress and threat signals.
class_name WorldMarker
extends Node3D

# --- Constants --------------------------------------------------------------

const DEFAULT_COLOR := Color(1.0, 0.2, 0.2)
const MAX_DISTANCE := 3500.0
const MIN_DISTANCE := 15.0
## What each icon key reads as on screen.
const WORDS := {
	"🚨": "SOS", "🎯": "FIGHT", "📦": "CARGO", "◆": "LOOT", "!": "!",
	"▲": "ENEMY", "●": "PAL",
}

# --- Exported / Configurable ------------------------------------------------

var symbol: String = "🚨"
var marker_color: Color = DEFAULT_COLOR
var pulse: bool = false
var target_node: Node3D = null
var offset_position := Vector3(0.0, 4.0, 0.0)

# --- Internal Nodes ---------------------------------------------------------

var _label: Label3D
var _dist_label: Label3D
var _time := 0.0
var _base_scale := 1.0


# --- Lifecycle --------------------------------------------------------------

func _ready() -> void:
	_build_visuals()


func _process(delta: float) -> void:
	_time += delta

	# Track target node if attached
	if is_instance_valid(target_node):
		global_position = target_node.global_position + offset_position

	# Distance to camera and visibility
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam != null:
		var dist := global_position.distance_to(cam.global_position)
		if dist > MAX_DISTANCE or dist < MIN_DISTANCE:
			visible = false
			return
		visible = true

		# Update distance display
		if _dist_label != null:
			if dist < 1000.0:
				_dist_label.text = "%dm" % int(dist)
			else:
				_dist_label.text = "%.1fkm" % (dist / 1000.0)

		# Distance compensation scaling: keep readable without growing massive
		var factor := clampf(dist / 35.0, 1.0, 6.0)
		var pulse_factor := 1.0
		if pulse:
			pulse_factor = 1.0 + 0.2 * sin(_time * 7.0)
		scale = Vector3.ONE * factor * pulse_factor
	else:
		# Fallback when running without camera / in tests
		if pulse:
			var pulse_factor := 1.0 + 0.15 * sin(_time * 7.0)
			scale = Vector3.ONE * pulse_factor


# --- Construction & Configuration -------------------------------------------

func _build_visuals() -> void:
	if _label != null:
		return

	_label = Label3D.new()
	_label.name = "Icon"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.render_priority = 10
	_label.pixel_size = 0.03
	_label.font = GraffitiStyle.head_font()
	_label.font_size = 44
	_label.outline_size = 14
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_label.modulate = marker_color
	_label.text = word_for(symbol)
	add_child(_label)

	_dist_label = Label3D.new()
	_dist_label.name = "Distance"
	_dist_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_dist_label.no_depth_test = true
	_dist_label.render_priority = 10
	_dist_label.pixel_size = 0.02
	_dist_label.font = GraffitiStyle.head_font()
	_dist_label.font_size = 24
	_dist_label.outline_size = 6
	_dist_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_dist_label.modulate = marker_color.lightened(0.2)
	_dist_label.position = Vector3(0.0, -1.8, 0.0)
	_dist_label.text = ""
	# The range is small print: the developer's read-out, not the player's.
	_dist_label.visible = Session.debug_mode
	add_child(_dist_label)


## Configure marker from an icon data dictionary or type key.
func configure(icon_key: String, target: Node3D = null, data_dict: Dictionary = {}) -> void:
	target_node = target
	if not data_dict.is_empty():
		symbol = String(data_dict.get("symbol", "🚨"))
		marker_color = Color.from_string(String(data_dict.get("color", "#FF3344")), DEFAULT_COLOR)
		pulse = bool(data_dict.get("pulse", false))
	else:
		_apply_key_defaults(icon_key)

	if _label != null:
		_label.text = word_for(symbol)
		_label.modulate = marker_color
	if _dist_label != null:
		_dist_label.modulate = marker_color.lightened(0.2)


## The word an icon key reads as ([constant WORDS]); anything unknown shows
## as itself.
static func word_for(icon: String) -> String:
	return String(WORDS.get(icon, icon))


func _apply_key_defaults(key: String) -> void:
	match key:
		"distress":
			symbol = "🚨"
			marker_color = Color(1.0, 0.2, 0.27)
			pulse = true
		"wanted":
			symbol = "🎯"
			marker_color = Color(1.0, 0.13, 0.0)
			pulse = false
		"cargo":
			symbol = "📦"
			marker_color = Color(0.0, 0.9, 1.0)
			pulse = false
		"resource":
			symbol = "◆"
			marker_color = Color(1.0, 0.84, 0.0)
			pulse = false
		"discovery":
			symbol = "!"
			marker_color = Color(1.0, 0.67, 0.0)
			pulse = true
		"enemy":
			symbol = "▲"
			marker_color = Color(1.0, 0.09, 0.27)
			pulse = true
		"friendly":
			symbol = "●"
			marker_color = Color(0.0, 0.9, 0.46)
			pulse = false
		_:
			symbol = "●"
			marker_color = Color.WHITE
			pulse = false
