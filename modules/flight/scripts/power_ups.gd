## PowerUps: the floating pick-ups kills drop, and what they do.
##
## A kill by the player may drop one ([member JuiceSettings.powerup_drop_chance]):
## a see-through blue sci-fi orb (glowing grid lines, [code]powerup_orb.gdshader[/code])
## with its symbol floating inside, bobbing and turning where the ship blew
## up. Flying into it (with a little pull once close) takes it, with a
## callout from the player's ship ([method FlightRoot.player_callout]).
##
## - [b]EMP[/b]: a ripple spreads out from the player; every other ship it
##   reaches is frozen ([method AiShip.emp_freeze]) for
##   [member JuiceSettings.powerup_emp_time] seconds.
## - [b]Boost[/b]: attack power and speed up for a while
##   ([member AiShip.player_power_boost], [method FlightModel.rescale_speed]).
## - [b]Shield[/b]: an always-visible bubble round the player that soaks
##   every hit until it breaks or runs out. It does not stack: another one
##   refills it.
##
## Timers run on game time. The dials are all [JuiceSettings] fields.
class_name PowerUps
extends Node3D

enum Kind { EMP, BOOST, SHIELD }
const NAMES := ["EMP", "BOOST", "SHIELD"]
const ICONS := [
	"res://assets/icons/fire/lorc/plasma-bolt.png",
	"res://assets/icons/fire/lorc/flaming-arrow.png",
	"res://assets/icons/hands/delapouite/attached-shield.png",
]
const ORB_SHADER := preload("res://modules/common/juice/shaders/powerup_orb.gdshader")
const RIPPLE_SHADER := preload("res://modules/common/juice/shaders/shield_bubble.gdshader")
const TINT := Color(0.45, 0.9, 1.0)
## The pickup wash: a light, see-through cyan (a dark blue sheet over the
## whole screen hid the fight).
const WASH := Color("8fe6ff")
## Most orbs floating at once; the oldest goes first.
const MAX_ORBS := 8
## Within this many metres (plus the hull) an orb drifts to the ship.
const PULL_RANGE := 45.0
## Seconds the EMP ripple takes to reach its full radius.
const EMP_SPREAD := 0.9

signal picked(kind: int)

var _root: FlightRoot = null
## Live orbs: {node, kind, t, radius, mat, base, beacon}.
var _orbs: Array[Dictionary] = []
## Orbs stay put and never blink out (the tutorial's orb waits for the player).
var hold := false
var _icon_tex: Array[Texture2D] = []
## Game seconds left on the boost and the shield bubble.
var boost_left := 0.0
var shield_left := 0.0
var _bubble: ShieldBubble = null
## The EMP ripple in flight: its shell, age, origin and who it already froze.
var _ripple: MeshInstance3D = null
var _ripple_t := 0.0
var _ripple_from := Vector3.ZERO
var _ripple_hit: Dictionary = {}


func setup(root: FlightRoot) -> void:
	_root = root


func _ready() -> void:
	name = "PowerUps"
	for path in ICONS:
		_icon_tex.append(load(path) as Texture2D)


# --- Drops ------------------------------------------------------------------------

## Roll the drop chance for a kill at [param pos].
func maybe_drop(pos: Vector3) -> void:
	if not JuiceSettings.power_ups or randf() >= JuiceSettings.powerup_drop_chance:
		return
	drop(randi() % NAMES.size(), pos)


## Float a [param kind] orb at [param pos]. A [param beacon] orb (the
## tutorial's) is bigger and wears a wide, steady glow, so a first-time player
## can't miss it.
func drop(kind: int, pos: Vector3, beacon := false) -> Node3D:
	var hull_r := _root.camera_rig.hull_radius if _root != null and _root.camera_rig != null else 3.0
	# Bigger than the ship's own hull and glowing, so one is easy to spot
	# before it is grabbed.
	var radius := maxf(hull_r * 1.25, 4.0) * (1.5 if beacon else 1.0)
	var orb := Node3D.new()
	orb.name = "PowerUp_" + String(NAMES[kind])
	var shell := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 20
	sphere.rings = 10
	shell.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = ORB_SHADER
	mat.set_shader_parameter("tint", TINT)
	shell.material_override = mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.add_child(shell)
	var icon := Sprite3D.new()
	icon.texture = _icon_tex[kind]
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.shaded = false
	icon.modulate = Color(1.0, 1.0, 1.0)
	icon.no_depth_test = true
	var width := float(icon.texture.get_width()) if icon.texture != null else 64.0
	icon.pixel_size = radius * 1.2 / maxf(width, 1.0)
	orb.add_child(icon)
	# A soft additive halo round it that breathes (see [method _tick_orbs]).
	var halo := Sprite3D.new()
	halo.name = "Halo"
	halo.texture = _halo_texture()
	halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	halo.shaded = false
	halo.transparent = true
	halo.modulate = Color(TINT, 0.8)
	halo.pixel_size = radius * (5.0 if beacon else 3.2) / 128.0
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb.add_child(halo)
	add_child(orb)
	orb.global_position = pos
	orb.scale = Vector3.ONE * 0.05
	var tw := orb.create_tween()
	tw.tween_property(orb, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_orbs.append({"node": orb, "kind": kind, "t": 0.0, "radius": radius, "mat": mat, "base": pos, "beacon": beacon})
	while _orbs.size() > MAX_ORBS:
		var old: Dictionary = _orbs.pop_front()
		(old["node"] as Node3D).queue_free()
	return orb


func orb_count() -> int:
	return _orbs.size()


## Where the floating orbs are now, oldest first (the tutorial's hand points
## at one).
func orb_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for o in _orbs:
		var node := o["node"] as Node3D
		if node != null and is_instance_valid(node):
			out.append(node.global_position)
	return out


# --- Effects ------------------------------------------------------------------------

## Apply [param kind] to the player now (a pickup, or a check).
func grant(kind: int) -> void:
	_pickup_moment(kind)
	match kind:
		Kind.EMP:
			_start_emp()
		Kind.BOOST:
			var fresh := boost_left <= 0.0
			boost_left = JuiceSettings.powerup_boost_time
			if fresh:
				_set_boost(true)
		Kind.SHIELD:
			_raise_shield()
	picked.emit(kind)


## A pickup is an event: the game stops for a breath, the screen washes
## blue and the power-up's name slams across it.
func _pickup_moment(kind: int) -> void:
	var blue := WASH
	Juice.freeze(0.3, 1.0)
	Juice.flash(blue, 0.2, 0.3)
	Juice.vignette(blue, 0.25, 0.5)
	var names := {Kind.EMP: ["FREEZE", "THEY CAN'T MOVE"], Kind.BOOST: ["BOOST", "FASTER & HARDER"], Kind.SHIELD: ["SHIELD", "BUBBLE UP"]}
	var n: Array = names.get(kind, ["POWER", ""])
	_root.big_notice(String(n[0]), String(n[1]), Color("35c8ff"), 0.7)
	GameAudio.ui(&"power_up")


func boost_active() -> bool:
	return boost_left > 0.0


func shield_active() -> bool:
	return shield_left > 0.0


## The bubble soaked a hit (the flight root's take_damage).
func shield_hit() -> void:
	if _bubble != null and is_instance_valid(_bubble):
		_bubble.hit_flash()


## The bubble's HP ran out: it pops.
func shield_broken() -> void:
	if shield_left <= 0.0:
		return
	shield_left = 0.0
	_drop_bubble()
	_root.player_callout("SHIELD DOWN!", Color("ff2a4a"))


## Back to nothing running (a respawn).
func clear_effects() -> void:
	if boost_left > 0.0:
		_set_boost(false)
	boost_left = 0.0
	if shield_left > 0.0:
		shield_left = 0.0
		_drop_bubble()


func _raise_shield() -> void:
	shield_left = JuiceSettings.powerup_shield_time
	_root.player_max_shield = _root.player_max_hp * JuiceSettings.powerup_shield_hp
	_root.player_shield = _root.player_max_shield
	if _bubble != null and is_instance_valid(_bubble):
		return
	var ship := _root.model
	if ship == null:
		return
	# Snug: the hull radius is a bounding sphere, and the chase camera sits
	# only a few of them back — any bigger and the rim runs off the screen.
	var r := (_root.camera_rig.hull_radius if _root.camera_rig != null else 3.0) * 0.8
	_bubble = ShieldBubble.attach(ship, r, Color(0.3, 0.7, 1.0), 1.6)
	if _root.view != null:
		_bubble.position = _root.view.aabb.get_center()


func _drop_bubble() -> void:
	if _bubble != null and is_instance_valid(_bubble):
		_bubble.pop_out()
	_bubble = null
	_root.restore_design_shield()


func _set_boost(on: bool) -> void:
	AiShip.player_power_boost = JuiceSettings.powerup_boost_power if on else 1.0
	var m := _root.model
	if m != null:
		var s := _root.player_speed_base() * (JuiceSettings.powerup_boost_speed if on else 1.0)
		m.speed_scale = s
		m.rescale_speed(s)


func _start_emp() -> void:
	if _root.model == null:
		return
	_ripple_from = _root.model.global_position
	_ripple_t = 0.0
	_ripple_hit.clear()
	if _ripple == null or not is_instance_valid(_ripple):
		_ripple = MeshInstance3D.new()
		_ripple.name = "EmpRipple"
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 32
		sphere.rings = 16
		_ripple.mesh = sphere
		var mat := ShaderMaterial.new()
		mat.shader = RIPPLE_SHADER
		mat.set_shader_parameter("tint", Color(0.45, 0.85, 1.0))
		mat.set_shader_parameter("rim_alpha", 0.8)
		_ripple.material_override = mat
		_ripple.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_ripple)
	_ripple.visible = true
	_ripple.global_position = _ripple_from
	_ripple.scale = Vector3.ONE * 0.1
	Juice.flash(Color("6ec6ff"), 0.35, 0.3)
	Juice.ring(Transform3D(Basis(), _ripple_from), 6.0, Color("6ec6ff"), 0.5)
	AddonVfx.electric(self, _ripple_from, 2.0, true)


# --- Per frame -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _root == null:
		return
	_tick_orbs(delta)
	_tick_ripple(delta)
	if boost_left > 0.0:
		boost_left -= delta
		if boost_left <= 0.0:
			boost_left = 0.0
			_set_boost(false)
			_root.player_callout("BOOST OVER", Color("ffb000"))
	if shield_left > 0.0:
		shield_left -= delta
		if shield_left <= 0.0:
			shield_left = 0.0
			_drop_bubble()
			_root.player_callout("SHIELD GONE", Color("3fa9ff"))


func _tick_orbs(delta: float) -> void:
	var ship := _root.active_ship_node()
	var ship_pos := ship.global_position if ship != null and not _root.is_player_dead() else Vector3.INF
	var hull_r := _root.camera_rig.hull_radius if _root.camera_rig != null else 3.0
	var keep: Array[Dictionary] = []
	for o in _orbs:
		var node := o["node"] as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var t := float(o["t"]) + delta
		if hold:
			t = minf(t, 1.0)
		o["t"] = t
		var life := JuiceSettings.powerup_life
		if t >= life:
			node.queue_free()
			continue
		var r := float(o["radius"])
		var base: Vector3 = o["base"]
		if ship_pos != Vector3.INF:
			var to := ship_pos - base
			var d := to.length()
			if d < hull_r + r * 1.3:
				_take(o)
				continue
			if d < hull_r + r + PULL_RANGE:
				# Drift to the ship, faster the closer it is.
				var k := 1.0 - (d - hull_r - r) / PULL_RANGE
				base += to / d * minf(d, (8.0 + 60.0 * k * k) * delta)
				o["base"] = base
		node.global_position = base + Vector3.UP * sin(t * 2.2) * r * 0.25
		node.rotate_y(delta * 0.9)
		# Blink out over its last three seconds.
		var fade := 1.0
		if life - t < 3.0:
			fade = 0.35 + 0.65 * absf(sin((life - t) * 6.0))
		(o["mat"] as ShaderMaterial).set_shader_parameter("fade", fade)
		var halo := node.get_node_or_null("Halo") as Sprite3D
		if halo != null:
			var glow := 0.55 + 0.35 * sin(t * 4.0)
			if bool(o.get("beacon", false)):
				glow = 0.8 + 0.2 * sin(t * 4.0)
			halo.modulate.a = glow * fade
		keep.append(o)
	_orbs = keep


static var _halo_tex: Texture2D = null


## A round soft glow, white in the middle fading out (tinted per use).
static func _halo_texture() -> Texture2D:
	if _halo_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 0.9))
		g.set_color(1, Color(1, 1, 1, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 128
		tex.height = 128
		_halo_tex = tex
	return _halo_tex


func _take(o: Dictionary) -> void:
	var node := o["node"] as Node3D
	var pos := node.global_position
	Juice.burst(BurstPresets.Preset.RING_SPARK, Transform3D(Basis(), pos), 1.2, TINT)
	Juice.light_pop(pos, TINT, 6.0, 0.2)
	node.queue_free()
	grant(int(o["kind"]))


func _tick_ripple(delta: float) -> void:
	if _ripple == null or not is_instance_valid(_ripple) or not _ripple.visible:
		return
	_ripple_t += delta
	var k := clampf(_ripple_t / EMP_SPREAD, 0.0, 1.0)
	var reach := JuiceSettings.powerup_emp_radius * (1.0 - pow(1.0 - k, 2.0))
	_ripple.scale = Vector3.ONE * maxf(reach, 0.1)
	(_ripple.material_override as ShaderMaterial).set_shader_parameter("fade", 1.0 - k * k)
	for s in _root.live_enemies():
		if _ripple_hit.has(s.get_instance_id()) or s == _root.controlled_ai:
			continue
		if s.global_position.distance_to(_ripple_from) <= reach:
			_ripple_hit[s.get_instance_id()] = true
			s.emp_freeze(JuiceSettings.powerup_emp_time)
	if k >= 1.0:
		_ripple.visible = false
