## One face on one thing: a textured quad that changes expression, blinks, and
## does a little squash-and-stretch pop whenever its mood changes.
##
## Built by [method Whimsy.attach_billboard_face] / [method Whimsy.make_sun_face],
## never by hand. The node itself is the placement (position, orientation, size);
## the quad is a child so the pop can scale it without disturbing where it sits.
##
## Ships used to wear one of these too; they now get a one-shot [method
## Whimsy.emote] instead (see [EmotePopup]) -- this class is scenery/star-only.
##
## Moods: [member base] is what the face settles on ("happy", or "focused" while
## firing, ...). [method react] shows another expression for a moment and then
## returns to the base -- "ouch" on a hit, "grin" on a boost.
extends Node3D

## Seconds between blinks, randomised in this range.
const BLINK_EVERY := Vector2(2.2, 5.5)
const BLINK_TIME := 0.12
## The expressions that have open eyes worth blinking.
const BLINKS_FROM := ["happy", "focused", "wink"]

var quad: MeshInstance3D = null
var base := "happy"
## Set once the owner is gone (a destroyed ship): holds the current face forever
## instead of drifting back to happy.
var frozen := false

var _mat: ShaderMaterial = null
var _showing := ""
var _react_left := 0.0
var _blink_left := 0.0
var _next_blink := 3.0
var _pop_tween: Tween = null


func _init() -> void:
	quad = MeshInstance3D.new()
	quad.name = "Face"
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	quad.mesh = mesh
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = Whimsy.face_shader()
	# Drawn after the opaque hull it sits on.
	_mat.render_priority = 1
	quad.material_override = _mat
	add_child(quad)
	_next_blink = randf_range(BLINK_EVERY.x, BLINK_EVERY.y)


func _ready() -> void:
	_show(base)


## Turn this face into a camera-facing billboard pushed [param push] radii out
## from its centre. For roundish things (rocks) with no single "front".
func make_billboard(push := 0.9) -> void:
	_mat.set_shader_parameter("billboard", 1.0)
	_mat.set_shader_parameter("push", push)
	# The shader moves the quad away from where its AABB says it is (by up to a
	# star's radius), so frustum culling would drop it at the screen edge. A
	# handful of quads is cheaper than being wrong about that.
	quad.extra_cull_margin = 16384.0


## Draw the face as pure light in [param tint] instead of lit paint -- for a
## face on something that is itself a light source.
func make_unlit(tint: Color) -> void:
	_mat.set_shader_parameter("unlit", 1.0)
	_mat.set_shader_parameter("tint", tint)


## Settle on [param expression] as the resting face.
func set_base(expression: String) -> void:
	if frozen or expression == base:
		return
	base = expression
	if _react_left <= 0.0:
		_show(base, true)


## Show [param expression] for [param hold] seconds, then go back to the base.
## A zero hold keeps it until the next call.
func react(expression: String, hold := 0.8) -> void:
	if frozen:
		return
	_react_left = hold if hold > 0.0 else INF
	_show(expression, expression != _showing)


## Show [param expression] and never change again (a wrecked ship's last look).
func freeze(expression: String) -> void:
	frozen = false
	react(expression, 0.0)
	frozen = true


func _process(delta: float) -> void:
	if frozen:
		return
	if _react_left > 0.0:
		_react_left -= delta
		if _react_left <= 0.0:
			_show(base, true)
		return
	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0:
			_show(base)
		return
	_next_blink -= delta
	if _next_blink <= 0.0:
		_next_blink = randf_range(BLINK_EVERY.x, BLINK_EVERY.y)
		if _showing in BLINKS_FROM:
			_blink_left = BLINK_TIME
			_show("blink")


func _show(expression: String, pop := false) -> void:
	var tex := Whimsy.face_texture(expression)
	if tex == null:
		return
	_showing = expression
	_mat.set_shader_parameter("face_tex", tex)
	if pop and is_inside_tree() and not Juice.reduce_motion():
		_pop()


## Squash then overshoot back to size: a face that changes its mind should look
## like it did.
func _pop() -> void:
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	quad.scale = Vector3(1.25, 0.8, 1.0)
	_pop_tween = create_tween()
	_pop_tween.tween_property(quad, "scale", Vector3.ONE, 0.35) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
