## ProximityAudio: the sounds of other ships near the player — a fighter
## zipping past (the fly-by wobble), a big ship sliding by (the landing roar),
## a big ship's engines starting up as it gets moving, and now and then the
## slowing-down whine while the player hangs around a megaship.
##
## A child of [FlightRoot], polled a few times a second (never per frame, never
## per ship per frame). It only reads positions and velocities — the ships and
## the big craft do not know it exists — and plays through [SpaceAudio].
extends Node

## Seconds between polls.
const POLL := 0.1
## A small ship counts as passing close inside this many metres (plus its hull).
const FLYBY_RADIUS := 40.0
## A big ship: this many of its own hull radii.
const BIG_FLYBY_RADII := 2.5
## Closing speed (m/s, player vs ship) a pass needs to be a fly-by at all.
const FLYBY_MIN_SPEED := 22.0
## Seconds before the same ship can fly by again, and between any two.
const FLYBY_SHIP_COOLDOWN := 5.0
const FLYBY_GAP := 0.7
## Speed (m/s) under which a big ship counts as parked, and over which it is
## under way: crossing it from parked plays the engine start.
const PARKED_SPEED := 1.5
const MOVING_SPEED := 4.0
## Within this many hull radii of a megaship the player is "near" it; the
## slowing-down whine then plays at a random gap in [constant NEAR_GAP].
const NEAR_RADII := 4.0
const NEAR_GAP := Vector2(14.0, 30.0)

var _root: FlightRoot
var _clock := 0.0
var _last_flyby := -100.0
var _near_clock := 0.0
## Per tracked thing (instance id): {d, t, pos, moving}.
var _seen := {}


func setup(root: FlightRoot) -> void:
	_root = root
	_near_clock = randf_range(NEAR_GAP.x, NEAR_GAP.y)


func _process(delta: float) -> void:
	_clock += delta
	if _clock < POLL:
		return
	var dt := _clock
	_clock = 0.0
	var audio := SpaceAudio.instance()
	var me := _root.active_model() if _root != null else null
	if audio == null or me == null or _root._player_dead:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var near_mega := Vector3.INF
	var keep := {}
	for ship in _root.live_enemies():
		if ship == _root.controlled_ai or ship.model == null:
			continue
		var big := ship.scale_multiplier >= AiShip.BIG_SHIP_SCALE
		var body := ship.model.phys_body()
		var r := body.radius if body != null else 3.0 * ship.scale_multiplier
		var pos := ship.model.global_position
		_track(audio, ship.get_instance_id(), pos, ship.model.velocity, r, big, me, now, dt)
		keep[ship.get_instance_id()] = true
		if big and me.global_position.distance_to(pos) < r * NEAR_RADII:
			near_mega = pos
	for gen in _root.large_craft():
		if not is_instance_valid(gen) or not gen.is_inside_tree():
			continue
		var id := gen.get_instance_id()
		var pos := gen.global_position
		var prev: Dictionary = _seen.get(id, {})
		var vel := (pos - Vector3(prev["pos"])) / dt if prev.has("pos") else Vector3.ZERO
		var r := maxf(gen.approx_extent(), 30.0)
		_track(audio, id, pos, vel, r, true, me, now, dt)
		keep[id] = true
		if me.global_position.distance_to(pos) < r * NEAR_RADII:
			near_mega = pos
	for id in _seen.keys():
		if not keep.has(id):
			_seen.erase(id)
	# Hanging around a megaship: the whine, now and then.
	if near_mega != Vector3.INF:
		_near_clock -= dt
		if _near_clock <= 0.0:
			_near_clock = randf_range(NEAR_GAP.x, NEAR_GAP.y)
			audio.play_megaship_near(me.global_position.lerp(near_mega, 0.3))


## One ship's (or big craft's) poll: its fly-by and, for a big one, its engines.
func _track(
	audio: SpaceAudio, id: int, pos: Vector3, vel: Vector3, radius: float, big: bool,
	me: FlightModel, now: float, _dt: float
) -> void:
	var prev: Dictionary = _seen.get(id, {})
	var d := me.global_position.distance_to(pos)
	var st := {"d": d, "t": float(prev.get("t", -100.0)), "pos": pos, "moving": bool(prev.get("moving", false))}
	# Fly-by: it was inside the pass radius, closing fast, and has just started
	# to pull away (the closest point of the pass).
	var reach := radius * BIG_FLYBY_RADII if big else FLYBY_RADIUS + radius
	var closing := (me.velocity - vel).length()
	if prev.has("d") and float(prev["d"]) < reach and d > float(prev["d"]) \
			and closing >= FLYBY_MIN_SPEED and now - st["t"] >= FLYBY_SHIP_COOLDOWN \
			and now - _last_flyby >= FLYBY_GAP:
		audio.play_flyby(pos, big)
		st["t"] = now
		_last_flyby = now
	# A big ship's engines: parked, then under way.
	if big and prev.has("pos"):
		var speed := vel.length()
		if not st["moving"] and speed > MOVING_SPEED:
			st["moving"] = true
			audio.play_big_engine(pos)
		elif st["moving"] and speed < PARKED_SPEED:
			st["moving"] = false
	elif big:
		st["moving"] = vel.length() > MOVING_SPEED
	_seen[id] = st
