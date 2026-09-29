## ComboChain: kills the player chains close together.
##
## Every player kill inside [member JuiceSettings.chain_window] seconds of the
## last one adds to the chain (x2, x3 …); a gap longer than that drops it.
## [FlightRoot] feeds it ([method note_kill]); the HUD reads [member count] and
## [method fraction_left] for the counter, and the one-thumb pilots read
## [method is_live] for the chain magnet (a live chain pulls the ship toward
## the next enemy — see [method MovePilot.chain_bend]).
##
## Runs on real time, so a kill cam or a freeze-frame never eats the window.
class_name ComboChain
extends RefCounted

## The chain grew (or started): [param count] kills, the last at [param at].
signal extended(count: int, at: Vector3)
## The window ran out on a chain of [param count] (at least 2) kills.
signal dropped(count: int)

## Kills in the live chain (0 = none, 1 = one kill, the chain is open).
var count := 0
## The longest chain this session.
var best := 0
## Where the last kill in the chain happened.
var last_at := Vector3.ZERO
var _last_ms := -1000000


## A player kill at [param at]. Returns the chain length after it.
func note_kill(at: Vector3) -> int:
	_expire()
	count += 1
	best = maxi(best, count)
	last_at = at
	_last_ms = Time.get_ticks_msec()
	extended.emit(count, at)
	return count


## Whether a kill now would extend the chain.
func is_live() -> bool:
	_expire()
	return count > 0


## 1 just after a kill, falling to 0 as the window runs out.
func fraction_left() -> float:
	if not is_live():
		return 0.0
	var window := maxf(JuiceSettings.chain_window, 0.05) * 1000.0
	return clampf(1.0 - float(Time.get_ticks_msec() - _last_ms) / window, 0.0, 1.0)


func reset() -> void:
	count = 0
	_last_ms = -1000000


func _expire() -> void:
	if count == 0:
		return
	if Time.get_ticks_msec() - _last_ms > int(maxf(JuiceSettings.chain_window, 0.05) * 1000.0):
		var was := count
		count = 0
		if was >= 2:
			dropped.emit(was)
