## Headless log census: loads the flight test, lets the fleet fight the player
## for a while, and prints what wrote to the log the most — during start-up
## and during the fight, separately (see [LogCensus]).
##
##     godot --path . --headless --audio-driver Dummy --script modules/flight/tools/log_census_check.gd [-- <seconds>]
##
## Fails if the fight logs more than [constant FIGHT_LINES_PER_SEC] lines a
## second: a quiet game logs next to nothing once it is running.
extends SceneTree

const FIGHT_LINES_PER_SEC := 2.0


func _initialize() -> void:
	var census := LogCensus.install()
	var seconds := 20.0
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args[0].is_valid_float():
		seconds = float(args[0])
	var packed := load("res://modules/flight/flight_test.tscn") as PackedScene
	var flight := packed.instantiate() as FlightRoot
	root.add_child(flight)
	for i in 30:
		await process_frame
	var startup := census.report(12)
	census.reset()
	JuiceSettings.player_invulnerable = true
	var sp := flight.ensure_ai_spawner()
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
	var fight := census.report(15)
	var totals := census.totals()
	LogCensus.uninstall()
	print("── log census: start-up ──────────────────────────────────")
	print(startup)
	print("── log census: %.0f s of fighting (%d ships) ──────────────" % [seconds, sp.ships().size()])
	print(fight)
	var rate := float(totals["lines"]) / maxf(float(totals["seconds"]), 0.001)
	print("── %s (%.1f lines/s while fighting, limit %.1f) ──" % [
		"PASS" if rate <= FIGHT_LINES_PER_SEC else "FAIL", rate, FIGHT_LINES_PER_SEC])
	quit(0 if rate <= FIGHT_LINES_PER_SEC else 1)
