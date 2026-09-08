## Writes the two starter feel profiles as .tres resources.
##
##     godot --headless --path . --script modules/physics/tools/make_profiles.gd
##
## PhysProfile is authored in the physics lab once that scene exists; until
## then, this tool keeps grounded.tres and cartoony.tres in sync with the
## values below so the shipped resources exist and load. `grounded` is the
## code's pre-M1 numbers (ships 0.4, rocks 0.25, planets 0.6 — a scout and a
## hauler bounced identically, which the profile exists to fix); `cartoony` is
## the exaggerated target for the physics lab to tune from.
extends SceneTree


func _initialize() -> void:
	var dir := "res://modules/physics/data/profiles"
	DirAccess.make_dir_recursive_absolute(dir)
	var grounded := PhysProfile.new()
	# Defaults stand: restitution_ship 0.4 / rock 0.25 / planet 0.6, exact
	# momentum (knock_transfer 1), ccd at half-radius travel.
	_save(grounded, dir, "grounded.tres")

	var cartoony := PhysProfile.new()
	cartoony.restitution_ship = 0.75
	cartoony.restitution_rock = 0.6
	cartoony.restitution_planet = 0.55
	cartoony.knock_transfer = 1.4
	cartoony.impulse_to_spin = 0.85
	cartoony.friction = 0.15
	cartoony.position_correction = 0.3
	cartoony.spin_damp_induced = 2.5
	# Cartoony keeps the knocked tumble going longer and freezes the frame harder,
	# and lets the consequence breathe before the assists grab the ship back.
	cartoony.spin_damp_assist = 6.0
	cartoony.assist_lockout_on_impact = 0.35
	cartoony.hitstop_scale = 1.2
	cartoony.hitstop_max = 0.09
	# Cartoon gravity: same constant, but a shallower falloff (1.75 instead of
	# inverse-square 2.0) so it reaches further and slingshots get dramatic.
	cartoony.gravity_g = 3.0
	cartoony.gravity_falloff = 1.75
	_save(cartoony, dir, "cartoony.tres")
	quit(0)


func _save(profile: PhysProfile, dir: String, file_name: String) -> void:
	var path := dir.path_join(file_name)
	var err := ResourceSaver.save(profile, path)
	if err == OK:
		print("wrote %s" % path)
	else:
		push_error("failed to write %s (err %d)" % [path, err])
