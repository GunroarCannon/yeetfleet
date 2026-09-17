## The place the flying happens: a star, a planet, a station and a lot of rocks.
##
## Space is the hardest setting in a game to make legible, because an empty volume
## gives the eye nothing to measure motion against. Every object here answers one
## of two questions — "which way am I facing" (star, planet, nebula band, the
## fixed starfield) or "how fast am I going" (asteroids, the station, the beacon
## ring) — and nothing is here for decoration alone.
##
## The scenery is generated with [LowPoly] and shaded with the ship part shader, so
## a hull never looks like it came from a different game than the rock it is
## flying past. The two exceptions are the planet and its moon, which are real
## [Planet] nodes built by the planet renderer from saved [PlanetData] — the same
## content the planet editor writes, so a planet made in the editor can be flown
## past here. Built once at load; nothing here allocates per frame.
class_name SpaceScene
extends Node3D

## Radius of the star dome. Far enough that no gameplay object reaches it, and
## the dome is re-centred on the camera every frame so it cannot be flown to.
const SKY_RADIUS := 14000.0
const STAR_COUNT := 900

## Points on a cartoony star. Five — the shape everyone draws.
const STAR_POINTS := 5
## How far in a star's valleys sit at full depth, as a fraction of its tip radius.
## Valleys at 0.45 of the tips is about what a drawn cartoon star uses — shallower
## than that and the points read as soft blobs rather than points.
const STAR_VALLEY_DEPTH := 0.55

## The asteroid belt the player flies through, in metres from the origin.
const BELT_INNER := 900.0
const BELT_OUTER := 2600.0
const BELT_THICKNESS := 160.0
const ASTEROID_COUNT := 260

const PLANET_RADIUS := 1400.0
const PLANET_CENTRE := Vector3(-6500.0, -2200.0, -10500.0)
const MOON_RADIUS := 300.0
## Moon orbital radius from Tarn IV centre. The moon orbits at this distance.
const MOON_ORBIT_RADIUS := 3500.0

const STATION_POS := Vector3(0.0, 40.0, -2500.0)
const STATION_RADIUS := 120.0

const PLANET2_CENTRE := Vector3(9000.0, -1200.0, 3600.0)
const PLANET2_RADIUS := 600.0
const PLANET3_CENTRE := Vector3(-3000.0, 5500.0, -7500.0)
const PLANET3_RADIUS := 220.0

## Asteroid spawning
const FLOATING_ASTEROID_COUNT := 50  # Number of floating asteroids to spawn
const FLOATING_ASTEROID_MIN_DIST := 5000.0  # Minimum distance from origin
const FLOATING_ASTEROID_MAX_DIST := 15000.0  # Maximum distance from origin

## Direction of the star, and the direction the key light comes from, so the lit
## side of a ship always faces the visible sun.
const SUN_DIR := Vector3(0.42, 0.28, 0.86)

## Scaled world layout. The constants above are the design values; these are
## multiplied by [Session]'s planet-size and spacing settings when the scene
## builds, and everything here — body placement, moon orbit, gravity, the spawn —
## reads these instead of the constants. Computed in _enter_tree so FlightRoot
## can register gravity with the scaled values before this scene is readied.
var planet_radius := PLANET_RADIUS
var planet_centre := PLANET_CENTRE
var moon_orbit_radius := MOON_ORBIT_RADIUS
var planet2_centre := PLANET2_CENTRE
var planet2_radius := PLANET2_RADIUS
var planet3_centre := PLANET3_CENTRE
var planet3_radius := PLANET3_RADIUS

var corona

func _enter_tree() -> void:
	var size_scale := Session.planet_scale
	var spacing := Session.planet_spacing
	planet_radius = PLANET_RADIUS * size_scale
	planet_centre = PLANET_CENTRE * spacing
	# The moon's orbit gap scales with the system spacing (bigger gaps, further
	# moon) and slightly with planet size so a huge world still has a moon at a
	# readable distance.
	moon_orbit_radius = MOON_ORBIT_RADIUS * spacing * sqrt(size_scale)
	planet2_centre = PLANET2_CENTRE * spacing
	planet2_radius = PLANET2_RADIUS * size_scale
	planet3_centre = PLANET3_CENTRE * spacing
	planet3_radius = PLANET3_RADIUS * size_scale

## Points of interest the HUD draws markers for: {name, position, radius, color}.
var landmarks: Array[Dictionary] = []

var _sky: Node3D
var _rng := RandomNumberGenerator.new()
## Positions and radii of every asteroid, stored from _build_belt so
## FlightModel can check collisions without touching MultiMesh instances.
var asteroid_data: Array[Dictionary] = []
## Per-asteroid rotation speed (rad/s), seeded from the same RNG.
var _asteroid_spin: Array[float] = []

## Floating asteroids (not in belts) for dynamic spawning
var floating_asteroid_data: Array[Dictionary] = []
var _floating_asteroid_spin: Array[float] = []
## The three belt MultiMesh instances, for per-frame tumbling updates.
var _belt_multimeshes: Array[MultiMeshInstance3D] = []
## Near-field close-pass rocks: small, close, the speed cue.
var _nearfield_mesh: MultiMeshInstance3D = null
## Moon orbit state: real Newtonian integration, not sine animation.
var _moon_node: Node3D = null
var _moon_velocity := Vector3.ZERO
## Reference to the gravity system — set by FlightRoot after it builds gravity.
var _gravity_ref: GravitySystem = null
## Parent for the per-rock collision anchors (M1b). Rocks are drawn by a
## MultiMesh with no per-rock node, but the PhysWorld needs a node per body to
## read positions from — these empty Node3Ds are that anchor, nothing else.
var _rock_holder: Node3D = null
## Rocks that have been knocked loose (M1, rock promotion): real free bodies the
## world integrates. Their MultiMesh instances are written from the body's node
## each frame so a flying rock is drawn where it actually is.
var _live_rocks: Array[PhysBody] = []


## 1 = normal, 2 = high detail. Reads [Session]'s toggle so that turning high-res
## on rebuilds the whole scene (it restarts) with denser, less low-poly geometry
## instead of just resizing the window.
func _detail() -> int:
	return 2 if Session.high_res else 1


func _ready() -> void:
	# A fixed seed, because a belt that reshuffles every launch makes it
	# impossible to tell a flight-model change from a different set of rocks.
	_rng.seed = 20250824
	# High-res rebuilds geometry at higher resolution (see _detail below). The
	# planet's atmosphere sphere lives in Planet, so hand the flag over first.
	Planet.high_detail = _detail() > 1
	_build_environment()
	_build_sky()
	_build_star()
	_build_planet()
	_setup_moon_orbit()
	_build_extra_planets()
	_build_station()
	_build_belt()
	_build_floating_asteroids()
	# Expose asteroid positions for collision in FlightModel.
	set_meta("asteroid_data", asteroid_data)
	set_meta("floating_asteroid_data", floating_asteroid_data)
	# star_count/star_size are shading dials (apply live); the starfield mesh is
	# built once at _ready like everything else in this scene, so a style change
	# needs an explicit rebuild rather than a per-frame read.
	StyleManager.instance().style_changed.connect(_on_style_changed)
	StyleManager.instance().palette_changed.connect(_on_palette_changed)


## Called by FlightRoot to give the moon access to the gravity system.
func set_gravity(gravity: GravitySystem) -> void:
	_gravity_ref = gravity
	# Align the moon's gravity body with the moon node's actual spawn point. The
	# body is registered at a default offset in FlightRoot before this scene's
	# moon is positioned; until it moves to the moon node, the moon's own body
	# sits far away and the softmax gravity blend dilutes Tarn's pull, kicking
	# the moon into a too-high orbit on the first frame.
	if _moon_node != null and gravity != null and gravity._bodies.size() > 3:
		gravity._bodies[3].position = _moon_node.global_position


## Re-target the moon's orbital velocity to the gravity system's current force
## law, so applying or cycling a feel profile (which can change g and falloff)
## does not kick the moon off its orbit. The moon integrates through the same
## gravity each frame, so matching the circular speed keeps it stable.
func sync_moon_orbit(gravity: GravitySystem) -> void:
	if _moon_node == null or gravity == null:
		return
	var pos := _moon_node.global_position
	var body := gravity.find_dominant_body(pos)
	if body == null:
		return
	var v := gravity.circular_orbit_velocity(body, pos)
	if v.length_squared() < 0.001:
		return
	_moon_velocity = v


## Every static collision surface in the scene (M1b), for [PhysWorld]:
## planets, the moon and the station as STATIC kinematic bodies, plus every rock
## (belt + near-field) as a ROCK kinematic body. FlightRoot consumes this once
## when it builds the scene's world. Rocks are scenery for now — they collide
## and bounce a ship per the profile, but are not yet pushed themselves.
func collision_statics() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var planet := get_node_or_null("Planet")
	if planet != null:
		out.append({"node": planet, "radius": planet_radius, "layer": PhysBody.Layer.STATIC})
		var moon := planet.get_node_or_null("Moon")
		if moon != null:
			out.append({"node": moon, "radius": MOON_RADIUS, "layer": PhysBody.Layer.STATIC})
	var p2 := get_node_or_null("Planet2")
	if p2 != null:
		out.append({"node": p2, "radius": planet2_radius, "layer": PhysBody.Layer.STATIC})
	var p3 := get_node_or_null("Planet3")
	if p3 != null:
		out.append({"node": p3, "radius": planet3_radius, "layer": PhysBody.Layer.STATIC})
	var station := get_node_or_null("Station")
	if station != null:
		out.append({"node": station, "radius": STATION_RADIUS, "layer": PhysBody.Layer.STATIC})
	for rock in asteroid_data:
		var node: Node3D = rock.get("node")
		if node != null:
			out.append({"node": node, "radius": rock["radius"], "layer": PhysBody.Layer.ROCK})
	return out


## Set up the moon to orbit Tarn IV using real Newtonian mechanics.
## The moon gets an initial tangential velocity computed from
## v = sqrt(G * M / r), then each frame gravity accelerates it.
func _setup_moon_orbit() -> void:
	_moon_node = get_node_or_null("Planet/Moon")
	if _moon_node == null:
		return
	# Start the moon at a random angle around Tarn IV.
	var angle := _rng.randf() * TAU
	var pos := planet_centre + Vector3(
		cos(angle) * moon_orbit_radius,
		sin(angle * 0.3) * moon_orbit_radius * 0.08,
		sin(angle) * moon_orbit_radius
	)
	_moon_node.global_position = pos
	# Compute tangential velocity for a circular orbit: v = sqrt(G*M/r).
	# Use the shared game G so the moon's starting speed matches whatever
	# [GravitySystem.GAME_G] is tuned to. The planet mass is scaled with size
	# (mass ∝ radius², keeping surface gravity roughly constant) so the moon's
	# orbit stays stable when planets are scaled up.
	var G := GravitySystem.GAME_G
	var size_scale := Session.planet_scale
	var planet_mass := 10000000.0 * size_scale * size_scale
	var v_orbit := sqrt(G * planet_mass / moon_orbit_radius)
	var radial := (pos - planet_centre).normalized()
	# Tangential = perpendicular to radial in the XZ plane (with slight Y tilt
	# for a non-flat orbit).
	var tangent := Vector3(-radial.z, 0.0, radial.x).normalized()
	_moon_velocity = tangent * v_orbit


## Per-frame: integrate moon position via real gravity, then tumble asteroids.
## When gravity is OFF the moon drifts at constant velocity (no force applied).
func _process(delta: float) -> void:
	# Real Newtonian moon orbit — no sine hack. The moon rides the gravity
	# system's circular orbit for whatever force law is live, re-targeted every
	# frame: under a cartoon falloff (< 2) a true 1/r^n orbit is a rosette that
	# wanders and can plunge, so a scenery moon keeps a stable ring instead.
	if _moon_node != null and _gravity_ref != null:
		var moon_pos := _moon_node.global_position
		var dominant := _gravity_ref.find_dominant_body(moon_pos)
		if dominant != null:
			_moon_velocity = _gravity_ref.circular_orbit_velocity(dominant, moon_pos)
		moon_pos += _moon_velocity * delta
		_moon_node.global_position = moon_pos
		# Update the moon's gravity body so the player feels the moon
		# at its actual position, not its register-time position.
		if _gravity_ref._bodies.size() > 3:
			_gravity_ref._bodies[3].position = moon_pos
	elif _moon_node != null:
		# No gravity system — drift at constant velocity.
		_moon_node.global_position += _moon_velocity * delta
	# Asteroid tumble.
	for mm_inst in _belt_multimeshes:
		var mm: MultiMesh = mm_inst.multimesh
		if mm == null:
			continue
		var bucket_start: int = mm_inst.get_meta("bucket_start", 0)
		for j in mm.instance_count:
			var global_idx := bucket_start + j
			if global_idx >= _asteroid_spin.size():
				continue
			var spin_speed: float = _asteroid_spin[global_idx]
			var t: Transform3D = mm.get_instance_transform(j)
			var spin := Basis(Vector3(
				sin(float(global_idx) * 1.7),
				cos(float(global_idx) * 2.3),
				sin(float(global_idx) * 3.1)
			).normalized(), spin_speed * delta)
			t.basis = (spin * t.basis).orthonormalized()
			mm.set_instance_transform(j, t)
	# Near-field rocks tumble too.
	if _nearfield_mesh != null and _nearfield_mesh.multimesh != null:
		var mm: MultiMesh = _nearfield_mesh.multimesh
		var belt_count: int = ASTEROID_COUNT
		for j in mm.instance_count:
			var global_idx := belt_count + j
			if global_idx >= _asteroid_spin.size():
				continue
			var spin_speed: float = _asteroid_spin[global_idx]
			var t: Transform3D = mm.get_instance_transform(j)
			var spin := Basis(Vector3(
				sin(float(global_idx) * 1.7),
				cos(float(global_idx) * 2.3),
				sin(float(global_idx) * 3.1)
			).normalized(), spin_speed * delta)
			t.basis = (spin * t.basis).orthonormalized()
			mm.set_instance_transform(j, t)
	# Knocked-loose rocks are written from their PhysBody node, which the physics
	# world moves and rolls — so the rock on screen is the rock that flies.
	for body in _live_rocks:
		if body == null or body.node == null or not is_instance_valid(body.node):
			continue
		var mm := body.node.get_meta("mm") as MultiMeshInstance3D
		if mm == null or mm.multimesh == null:
			continue
		mm.multimesh.set_instance_transform(int(body.node.get_meta("j")), body.node.global_transform)


# Floating asteroids tumble.
	if floating_asteroid_data.size() > 0:
		for i in floating_asteroid_data.size():
			var anchor: Node3D = floating_asteroid_data[i]["node"]
			if anchor == null:
				continue
			var spin_speed: float = _floating_asteroid_spin[i]
			var t: Transform3D = anchor.transform
			var spin := Basis(Vector3(
				sin(float(i) * 1.7),
				cos(float(i) * 2.3),
				sin(float(i) * 3.1)
			).normalized(), spin_speed * delta)
			t.basis = (spin * t.basis).orthonormalized()
			anchor.transform = t

## The dome and the starfield have no parallax, so they must ride with the camera
## or the player flies out of the sky. Called by the camera rig each frame.
func recentre(camera_position: Vector3) -> void:
	if _sky != null:
		_sky.global_position = camera_position


# --- Environment and lights -------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.color("background")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Space has no bounce light, but a pitch-black shadow side turns a ship into
	# a featureless silhouette — and any camera pointed at the night side (the
	# rear view, a chase view into shadow) goes completely dark. A cold, fairly
	# strong ambient keeps geometry readable from every angle.
	env.ambient_light_color = Palette.color("ambient")
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	# Lower than the flight test volume's 4.0: refs 3 and 4 both clip bright
	# emissives — plumes, tracers, the sun disc — to white rather than merely
	# tinting them, and the additive halos in the juice layer are built to carry
	# that look on their own even where glow is unavailable. See the glow
	# decision below.
	env.tonemap_white = 2.6
	# gl_compatibility's glow support is real but modest: verified by render, not
	# by reasoning (see `juice-and-more.md` §3.2). Kept subtle and thresholded
	# well above 1.0 so it only catches emissives, never the diffuse hull.
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.05
	env.glow_bloom = 0.15
	var holder := WorldEnvironment.new()
	holder.name = "Environment"
	holder.environment = env
	add_child(holder)

	var key := DirectionalLight3D.new()
	key.name = "SunLight"
	key.light_energy = 2.2 if Session.enhanced_lighting else 1.5
	# The palette's star colour, pulled most of the way to white: this is the
	# light the star *casts*, not the star's own disc, and a saturated light
	# tints every hull in the system.
	key.light_color = Palette.color("star").lerp(Color.WHITE, 0.2 if Session.enhanced_lighting else 0.5)
	key.shadow_enabled = Session.enhanced_lighting
	key.look_at_from_position(Vector3.ZERO, -SUN_DIR, Vector3.UP)
	add_child(key)

	# A dim fill from the planet's side, so the unlit flank still reads as a
	# shape rather than a hole cut in the starfield.
	var fill := DirectionalLight3D.new()
	fill.name = "PlanetFill"
	fill.light_energy = 0.32
	fill.light_color = Palette.color("ambient").lightened(0.35)
	fill.shadow_enabled = false
	fill.look_at_from_position(Vector3.ZERO, planet_centre.normalized(), Vector3.UP)
	add_child(fill)

	# Enhanced background: solar corona, a distant galaxy and nebula dust. A
	# per-session toggle (Settings → Quality) so it can be switched off for a
	# plain starfield; changed dials apply on the next scene restart.
	if Session.render_backdrop:
		# Solar corona - extended glow around the sun
		corona = _make_glow_sphere(800.0, Color(Palette.color("star"), 0.1), 3)
		corona.name = "SolarCorona"
		corona.position = Vector3.ZERO
		corona.scale = Vector3.ONE * 2.0
		add_child(corona)

		# Inner corona - brighter and more compact
		var inner_corona := _make_glow_sphere(
			400.0, Color(Palette.color("star").lerp(Color.WHITE, 0.35), 0.2), 2
		)
		inner_corona.name = "InnerSolarCorona"
		inner_corona.position = Vector3.ZERO
		add_child(inner_corona)

		# Space clouds - additional nebula layers for depth
		var deep_space := Node3D.new()
		deep_space.name = "DeepSpace"
		add_child(deep_space)

		# Distant galaxy simulation (as a faint, large nebula)
		var galaxy := _make_distant_galaxy()
		galaxy.name = "DistantGalaxy"
		galaxy.scale = Vector3.ONE * 10.0
		deep_space.add_child(galaxy)

		# Floating space dust clouds
		var dust_clouds := _make_space_dust_clouds()
		dust_clouds.name = "SpaceDustClouds"
		deep_space.add_child(dust_clouds)


# --- Sky --------------------------------------------------------------------

func _build_sky() -> void:
	_sky = Node3D.new()
	_sky.name = "Sky"
	add_child(_sky)
	_sky.add_child(_make_starfield())
	_sky.add_child(_make_nebula_band())


## Apply a look change to the sky and the scenery.
##
## The starfield is rebuilt rather than the whole sky, since the nebula bands read
## neither [member StyleProfile.star_count] nor [member StyleProfile.star_size].
## Rocks are re-skinned in place: [method _make_rock] is deterministic per variant,
## so the new meshes are the same rock at the new look rather than a reshuffled
## field, and the existing MultiMesh transforms keep the belt where it was.
func _on_style_changed(_profile: StyleProfile) -> void:
	if _sky != null:
		var old := _sky.get_node_or_null("Stars")
		if old != null:
			_sky.remove_child(old)
			old.free()
		_sky.add_child(_make_starfield())
	_restyle_scenery()


func _on_palette_changed(_palette: Palette) -> void:
	if _sky != null:
		var old_stars := _sky.get_node_or_null("Stars")
		if old_stars != null:
			_sky.remove_child(old_stars)
			old_stars.free()
		_sky.add_child(_make_starfield())

		var old_nebula := _sky.get_node_or_null("Nebula")
		if old_nebula != null:
			_sky.remove_child(old_nebula)
			old_nebula.free()
		_sky.add_child(_make_nebula_band())
	_restyle_scenery()
	var env_node := get_node_or_null("Environment") as WorldEnvironment
	if env_node != null and env_node.environment != null:
		env_node.environment.background_color = Palette.color("background")
		env_node.environment.ambient_light_color = Palette.color("ambient")


## The rock material family each rock variant is drawn with. Mirrors the choices
## [method _build_belt], [method _build_nearfield] and
## [method _build_floating_asteroids] make: the three belt variants deliberately
## share one family so a belt reads as one field of stone, while the near-field and
## floating rocks are a different family each so they do not read as belt strays.
const ROCK_VARIANT_FAMILY := {0: 1, 1: 1, 2: 1, 3: 3, 4: 2}


## Rebuild every rock's geometry for the current look and re-apply the scenery
## materials, leaving instance transforms and rock positions untouched.
##
## [method _make_rock] is deterministic per variant, so these are the same rocks at
## the new look rather than a reshuffled field — a rock_potato change must not move
## a single asteroid the player was flying towards.
func _restyle_scenery() -> void:
	var variant_meshes := {}
	for node in get_children():
		var inst := node as MultiMeshInstance3D
		if inst == null or inst.multimesh == null:
			continue
		if not inst.has_meta("rock_variant"):
			continue
		var variant := int(inst.get_meta("rock_variant"))
		if not variant_meshes.has(variant):
			variant_meshes[variant] = _make_rock(variant)
		inst.multimesh.mesh = variant_meshes[variant]
		inst.material_override = _rock_material(int(ROCK_VARIANT_FAMILY.get(variant, 1)))
	_restyle_tagged_scenery(self)


## Recolour any scenery node tagged with a `scenery` meta. Walks the whole tree
## because the station hangs off its own holder rather than being a direct child,
## and the tag is what makes it findable without this function knowing the shape of
## the scene it is walking.
func _restyle_tagged_scenery(node: Node) -> void:
	for child in node.get_children():
		var inst := child as MeshInstance3D
		if inst != null and inst.has_meta("scenery"):
			if String(inst.get_meta("scenery")) == "station":
				inst.material_override = _station_material()
		_restyle_tagged_scenery(child)


## Stars as small discs rather than quads: GL Compatibility point-size support
## is unreliable across mobile drivers, and triangle-fan discs look round from
## every angle.
##
## [member StyleProfile.star_five_point] bends the disc into a five-pointed cartoon
## star. The silhouette comes from one radius function rather than a second mesh:
## the outline radius alternates between the star's outer and inner radius on a
## raised-cosine pulse, so a depth of 0 is a plain circle and a depth of 1 is a
## star whose tips and valleys are both filleted. A cosine pulse is what makes it
## read as *rounded* — a sharp star would need a sawtooth in the same place.
func _make_starfield() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var detail := _detail()
	# Twice the stars and rounder discs at high detail, so the denser sky keeps
	# its depth instead of going sparse at the higher render scale. The user star
	# density dial (Settings → Quality) scales the count; it applies on restart.
	#
	# StyleProfile.star_count/star_size override the base count and per-star
	# size: "900 small -> few big soft" is the intended range, so a low count
	# with a large size_mult is the friendly-look end of the dial.
	var style := StyleManager.instance().current_profile
	var base_count := STAR_COUNT
	var size_mult := 1.0
	var star_depth := 0.0
	if style:
		base_count = style.star_count
		size_mult = style.star_size
		star_depth = style.star_five_point
	# A star needs enough segments to resolve ten corners; a disc does not, and at
	# 900 stars the difference is real.
	var star_seg := (14 if star_depth > 0.0 else 8) * detail
	for i in int(base_count * detail * Session.star_density):
		var dir := _random_direction()
		# Mostly faint, a few bright. A uniform field looks like television
		# static; a weighted one looks like a sky.
		var bright: float = pow(_rng.randf(), 2.6)
		# Small dots: a starfield is points, not blotches. Large discs read as
		# noise and, piled up at the same depth, are the first thing to z-fight
		# when the camera moves — smaller dots keep the sky crisp.
		var size: float = SKY_RADIUS * (0.0006 + bright * 0.0016) * size_mult
		var centre := dir * SKY_RADIUS
		var right := dir.cross(Vector3.UP)
		if right.length() < 0.001:
			right = Vector3.RIGHT
		right = right.normalized() * size
		var up := dir.cross(right).normalized() * size
		# Build a triangle-fan centred on `dir * SKY_RADIUS`, its radius modulated
		# into a star when the look asks for one.
		for s in star_seg:
			var a0 := TAU * float(s) / float(star_seg)
			var a1 := TAU * float(s + 1) / float(star_seg)
			st.add_vertex(centre)
			st.add_vertex(centre + right * cos(a0) * _star_radius(a0, star_depth)
				+ up * sin(a0) * _star_radius(a0, star_depth))
			st.add_vertex(centre + right * cos(a1) * _star_radius(a1, star_depth)
				+ up * sin(a1) * _star_radius(a1, star_depth))
	var inst := MeshInstance3D.new()
	inst.name = "Stars"
	inst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Palette.color("star").lerp(Color.WHITE, 0.45)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The dome rides with the camera, so stars are always at the same depth.
	# Disabling the depth test stops them z-fighting each other at 14 km — the
	# coarse depth values there make them flicker as the camera moves. Drawn
	# first (priority below everything) and never depth-tested, they still get
	# correctly covered by anything closer that draws after.
	mat.no_depth_test = true
	mat.render_priority = -10
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = SKY_RADIUS
	return inst


## The star silhouette's radius multiplier at [param angle], for a look of
## [param depth].
##
## Depth 0 is a plain circle of radius 1. As depth rises, the radius is pulled in
## on a raised-cosine pulse with five lobes: the tips stay where the circle was and
## the valleys between them are carved inward. Because the pulse is a cosine rather
## than a sawtooth, both the tips and the inner corners come out filleted — which
## is the whole difference between a cartoon star and the sharp one this
## deliberately is not.
func _star_radius(angle: float, depth: float) -> float:
	if depth <= 0.0:
		return 1.0
	# Five lobes over a full turn, peaking at angle 0.
	var phase := fmod(angle * STAR_POINTS / TAU, 1.0)
	var pulse := 0.5 * (1.0 + cos(TAU * phase))
	return 1.0 - depth * STAR_VALLEY_DEPTH * (1.0 - pulse)


## Two crossed gradient bands — ref 3's nebula wash — rather than one thin
## stripe. Each ribbon fades from transparent at its edges to a saturated core,
## which needs a per-vertex colour a flat [BaseMaterial3D.albedo_color] cannot
## give it, so this builds the mesh directly with [SurfaceTool] instead of
## going through [LowPoly]'s three-channel system (which exists for the ship
## part shader's primary/accent/trim split, not an unshaded additive wash).
func _make_nebula_band() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Three crossed washes rather than two: the extra tilt breaks up the
	# symmetric X that two bands make, and the brighter cores give the sky a
	# banded depth instead of a flat tint.
	#
	# Each wash takes the palette's nebula pair at its own hue offset, so a palette
	# gets a sky that reads as one cloud rather than three unrelated stripes —
	# the old hardcoded trio were three fixed hues that happened to sit near each
	# other, which is a thing a palette cannot reproduce and should not have to.
	_add_nebula_ribbon(st, deg_to_rad(22.0), _nebula_wash(0, 0.22))
	_add_nebula_ribbon(st, deg_to_rad(-33.0), _nebula_wash(1, 0.20))
	_add_nebula_ribbon(st, deg_to_rad(71.0), _nebula_wash(2, 0.14))
	var inst := MeshInstance3D.new()
	inst.name = "Nebula"
	inst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = -11
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = SKY_RADIUS
	return inst


## One crossed wash's two colours, from the palette's nebula pair, with the
## centreline opacity this ribbon wants. The hue relationships live on
## [method Palette.nebula_wash] so the sky and the background gas clouds agree.
func _nebula_wash(index: int, core_alpha: float) -> Dictionary:
	var wash := Palette.nebula_wash(index)
	var outer: Color = wash["edge"]
	outer.a = 0.0
	var inner: Color = wash["core"]
	inner.a = core_alpha
	return {"edge": outer, "core": inner}


## Symmetric fade — transparent at both edges, peaking at the centreline —
## rather than a one-sided ramp: a ribbon that goes straight from nothing to
## fully saturated has a hard mesh-boundary line on its bright side, which
## reads as a glass panel rather than a wash of gas.
func _add_nebula_ribbon(st: SurfaceTool, tilt_deg: float, wash: Dictionary) -> void:
	var edge_color: Color = wash["edge"]
	var core_color: Color = wash["core"]
	# High detail doubles the ribbon segments so the band edge stops looking
	# faceted when the camera is close.
	var segments := 64 * _detail()
	var tilt := Basis(Vector3(0.3, 0.0, 0.95).normalized(), tilt_deg)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		# A third of the frame, not a stripe — see the class doc comment. The
		# second sine makes the width wobble, so the edge isn't a smooth circle.
		var width := 0.32 + 0.12 * sin(a0 * 3.0) + 0.06 * sin(a0 * 7.0 + tilt_deg)
		var lo0 := tilt * _band_point(a0, -width)
		var mid0 := tilt * _band_point(a0, 0.0)
		var hi0 := tilt * _band_point(a0, width)
		var lo1 := tilt * _band_point(a1, -width)
		var mid1 := tilt * _band_point(a1, 0.0)
		var hi1 := tilt * _band_point(a1, width)
		_tri(st, lo0, edge_color, lo1, edge_color, mid1, core_color)
		_tri(st, lo0, edge_color, mid1, core_color, mid0, core_color)
		_tri(st, mid0, core_color, mid1, core_color, hi1, edge_color)
		_tri(st, mid0, core_color, hi1, edge_color, hi0, edge_color)


func _tri(
	st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color
) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


func _band_point(angle: float, height: float) -> Vector3:
	return Vector3(cos(angle), height, sin(angle)).normalized() * (SKY_RADIUS * 0.98)


# --- Bodies -----------------------------------------------------------------

func _build_star() -> void:
	var pos := SUN_DIR.normalized() * (SKY_RADIUS * 0.9)
	# On the sky node, so the star stays a fixed direction rather than something
	# the player can fly to and discover is 240 metres wide.
	var disc := _make_glow_sphere(120.0, Color("fff6e0"), 1)
	disc.name = "Star"
	disc.position = pos
	_sky.add_child(disc)
	var halo := _make_glow_sphere(300.0, Color(1.0, 0.85, 0.55, 0.18), 1)
	halo.name = "StarHalo"
	halo.position = pos
	_sky.add_child(halo)

	# A handful of billboarded petals around the disc, at increasing radius and
	# falling opacity — a cheap stand-in for a true screen-space flare (which
	# would need a camera-relative pass; not worth it while the disc itself is
	# the thing selling "there is a sun here").
	for i in 3:
		var t := float(i) / 2.0
		var petal := _make_flare_petal(
			lerpf(70.0, 220.0, t), Color(1.0, 0.82, 0.6, 0.22 - t * 0.14)
		)
		petal.name = "StarFlare%d" % i
		petal.position = pos
		_sky.add_child(petal)


func _make_flare_petal(radius: float, color: Color) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE * radius
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = ShipMaterials.glow_material(color, true)
	(inst.material_override as StandardMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = radius
	return inst


## The planet and its moon, built by the planet renderer from the saved planets in
## res://data/planets.
##
## These used to be two hand-built banded spheres and a glow shell, which meant the
## thing the player actually flies past shared nothing with the planet renderer —
## a change in the editor could not be seen here, and a planet made in the editor
## could not be flown to. Now both are [Planet] nodes reading [PlanetData], so the
## editor and the flight scene show the same planet.
func _build_planet() -> void:
	var pivot := Node3D.new()
	pivot.name = "Planet"
	pivot.position = planet_centre
	add_child(pivot)

	pivot.add_child(_make_planet("Body", "tarn_iv", planet_radius, Vector3.ZERO, _fallback_planet()))
	# Offset far enough to read as a separate body at a glance, and close enough
	# that both are in frame from the belt.
	pivot.add_child(_make_planet(
		"Moon", "tarn_iv_moon", MOON_RADIUS,
		Vector3(planet_radius * 1.9, planet_radius * 0.55, planet_radius * 0.7),
		_fallback_moon()
	))

	landmarks.append({
		"name": "Tarn IV",
		"position": planet_centre,
		"radius": planet_radius,
		"color": Color("6fa8ff"),
	})
	# Moon landmark — position updated each frame by _process.
	landmarks.append({
		"name": "Tarn IV Moon",
		"position": planet_centre + Vector3(moon_orbit_radius, 0.0, 0.0),
		"radius": MOON_RADIUS,
		"color": Color("b0b8c0"),
		"dynamic": true,
	})


## One [Planet] from a saved id, sized to [param radius].
##
## The radius override is load-bearing, not cosmetic: [FlightModel] pushes the ship
## out of [constant PLANET_CENTRE] at [constant PLANET_RADIUS] + 5, so the rendered
## surface has to sit exactly on that sphere or the ship will bounce off open space
## — or sink into the ground. Saved planets are authored at editor scale (a dozen
## metres) and every other number in [PlanetData] is a ratio or a colour, so
## scaling is a single assignment.
func _make_planet(node_name: String, id: String, radius: float, offset: Vector3, fallback: PlanetData) -> Planet:
	var data := PlanetLibrary.instance().get_data(id)
	if data == null:
		# Missing content must not cost the player the scene: the fallback is a
		# plausible planet, and the warning says which file to author.
		push_warning("SpaceScene: %s/%s.tres not found, using the built-in default" % [
			PlanetLibrary.PLANETS_DIR, id,
		])
		data = fallback
	data.planet_radius = radius
	if _detail() > 1:
		# Don't mutate the library's shared resource — duplicate, then raise the
		# mesh resolution so the surface is genuinely less faceted at high res.
		data = data.duplicate()
		data.sphere_resolution = mini(int(data.sphere_resolution * 1.6), 128)

	var planet := Planet.new()
	planet.name = node_name
	planet.position = offset
	# The surface shader is unshaded and lights from this vector, so it has to
	# agree with the star the player can actually see.
	planet.sun_direction = SUN_DIR
	planet.configure(data)
	return planet


## Used only when res://data/planets is missing or unreadable. Deliberately close
## to the committed tarn_iv.tres — a fallback that looks different from the real
## thing hides the fact that the real thing failed to load.
func _fallback_planet() -> PlanetData:
	var d := PlanetData.new()
	d.planet_name = "Tarn IV"
	d.seed_value = 19870506
	d.sphere_resolution = 24
	d.terrain_height = 0.12
	d.continent_scale = 0.7
	d.mountain_scale = 3.0
	d.ridge_strength = 0.6
	d.sea_level = 0.45
	d.primary_color = Color(0.42, 0.58, 0.32)
	d.secondary_color = Color(0.68, 0.55, 0.35)
	d.water_color = Color(0.15, 0.35, 0.65)
	d.ice_amount = 0.35
	d.detail_strength = 0.06
	d.rotation_speed = 0.006
	d.atmosphere_density = 0.4
	d.atmosphere_color = Color(0.45, 0.72, 1.0)
	return d


func _fallback_moon() -> PlanetData:
	var d := PlanetData.new()
	d.planet_name = "Tarn IV Moon"
	d.seed_value = 4471
	d.sphere_resolution = 16
	d.terrain_height = 0.10
	d.continent_scale = 1.2
	d.mountain_scale = 5.0
	d.ridge_strength = 0.7
	d.sea_level = 0.0
	d.primary_color = Color(0.58, 0.56, 0.60)
	d.secondary_color = Color(0.40, 0.38, 0.42)
	d.ice_amount = 0.15
	d.detail_strength = 0.04
	d.rotation_speed = 0.003
	d.atmosphere_density = 0.0
	return d


## Two additional planets at different positions in the system, adding variety
## and navigation landmarks. Each uses the planet renderer with fallback data
## so a missing .tres file never costs the scene.
func _build_extra_planets() -> void:
	# A small volcanic world
	var pivot2 := Node3D.new()
	pivot2.name = "Planet2"
	pivot2.position = planet2_centre
	add_child(pivot2)
	pivot2.add_child(_make_planet(
		"Ashara", "ashara", planet2_radius, Vector3.ZERO,
		_fallback_planet_ashara()
	))
	landmarks.append({
		"name": "Ashara",
		"position": planet2_centre,
		"radius": planet2_radius,
		"color": Color("ff6a3d"),
	})

	# A small ice moon
	var pivot3 := Node3D.new()
	pivot3.name = "Planet3"
	pivot3.position = planet3_centre
	add_child(pivot3)
	pivot3.add_child(_make_planet(
		"Glacius", "glacius", planet3_radius, Vector3.ZERO,
		_fallback_planet_glacius()
	))
	landmarks.append({
		"name": "Glacius",
		"position": planet3_centre,
		"radius": planet3_radius,
		"color": Color("a0d4ff"),
	})


func _fallback_planet_ashara() -> PlanetData:
	var d := PlanetData.new()
	d.planet_name = "Ashara"
	d.seed_value = 77300123
	d.sphere_resolution = 20
	d.terrain_height = 0.14
	d.continent_scale = 1.0
	d.mountain_scale = 4.0
	d.ridge_strength = 0.7
	d.sea_level = 0.0
	d.primary_color = Color(0.85, 0.35, 0.15)
	d.secondary_color = Color(0.55, 0.20, 0.10)
	d.water_color = Color(0.15, 0.08, 0.05)
	d.ice_amount = 0.0
	d.detail_strength = 0.04
	d.rotation_speed = 0.008
	d.atmosphere_density = 0.25
	d.atmosphere_color = Color(0.85, 0.5, 0.3)
	return d


func _fallback_planet_glacius() -> PlanetData:
	var d := PlanetData.new()
	d.planet_name = "Glacius"
	d.seed_value = 55298
	d.sphere_resolution = 16
	d.terrain_height = 0.08
	d.continent_scale = 1.2
	d.mountain_scale = 3.5
	d.ridge_strength = 0.4
	d.sea_level = 0.55
	d.primary_color = Color(0.85, 0.92, 1.0)
	d.secondary_color = Color(0.60, 0.72, 0.88)
	d.water_color = Color(0.18, 0.30, 0.55)
	d.ice_amount = 0.80
	d.detail_strength = 0.03
	d.rotation_speed = 0.004
	d.atmosphere_density = 0.35
	d.atmosphere_color = Color(0.65, 0.80, 1.0)
	return d


## The station is the only built landmark, and doubles as the speed reference you
## can aim at: a torus reads as a ring at any distance and its apparent size
## changes fast enough to feel closing speed.
func _build_station() -> void:
	var station := Node3D.new()
	station.name = "Station"
	station.position = STATION_POS
	add_child(station)

	var lp := LowPoly.new()
	var sides := 18 * _detail()
	var tube := 22.0
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var channel := LowPoly.CH_PRIMARY if i % 3 else LowPoly.CH_ACCENT
		lp.add_ring_wall(
			_torus_ring(a0, STATION_RADIUS, tube, 8),
			_torus_ring(a1, STATION_RADIUS, tube, 8),
			channel
		)
	# Hub and spokes, so the ring reads as a structure and not a smoke ring.
	lp.add_box(Vector3.ZERO, Vector3(46, 46, 46), LowPoly.CH_TRIM)
	for i in 4:
		var angle := TAU * float(i) / 4.0
		var dir := Vector3(cos(angle), sin(angle), 0.0)
		lp.add_box(dir * STATION_RADIUS * 0.5, Vector3(
			maxf(absf(dir.x) * STATION_RADIUS, 9.0),
			maxf(absf(dir.y) * STATION_RADIUS, 9.0),
			9.0
		), LowPoly.CH_TRIM)

	var inst := MeshInstance3D.new()
	inst.name = "Hull"
	inst.mesh = lp.commit("station")
	inst.material_override = _station_material()
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = STATION_RADIUS
	# Tagged so a look change can recolour it along with the rocks.
	inst.set_meta("scenery", "station")
	station.add_child(inst)

	# Approach lights: a ring of beacons the player can pick out at range.
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var beacon := _make_glow_sphere(4.0, Color("ff8a3d") if i % 2 else Color("6ff0d0"), 0)
		beacon.position = Vector3(cos(angle), sin(angle), 0.0) * (STATION_RADIUS + tube)
		station.add_child(beacon)

	landmarks.append({
		"name": "Ceres Gate",
		"position": STATION_POS,
		"radius": STATION_RADIUS,
		"color": Color("6ff0d0"),
	})


# --- Belt -------------------------------------------------------------------

## Asteroids are drawn with a [MultiMesh]: one draw call per rock variant for the
## whole belt, which matters on the GL Compatibility renderer this project
## targets. Three meshes, randomly scaled and rotated, hide the repeat entirely at
## flight speed.
func _build_belt() -> void:
	var shapes: Array[ArrayMesh] = [_make_rock(0), _make_rock(1), _make_rock(2)]
	var material := _rock_material(1)
	var buckets: Array[Array] = [[], [], []]

	# One invisible anchor per rock, for the PhysWorld (M1b). See _rock_holder.
	_rock_holder = Node3D.new()
	_rock_holder.name = "PhysRocks"
	add_child(_rock_holder)

	for i in ASTEROID_COUNT:
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(BELT_INNER, BELT_OUTER)
		var height := _rng.randfn(0.0, BELT_THICKNESS * 0.5)
		var pos := Vector3(cos(angle) * radius, height, sin(angle) * radius)
		# Big rocks are rare. Uniformly sized boulders give no depth cue; a few
		# giants among many pebbles do.
		var size: float = lerpf(6.0, 70.0, pow(_rng.randf(), 3.0))
		var basis := Basis.from_euler(Vector3(
			_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU
		)).scaled(Vector3.ONE * size)
		buckets[i % 3].append(Transform3D(basis, pos))
		var anchor := Node3D.new()
		anchor.name = "Rock%d" % i
		anchor.position = pos
		_rock_holder.add_child(anchor)
		asteroid_data.append({"position": pos, "radius": size, "node": anchor})
		# Tumble speed: slow, random per axis, seeded from the same RNG.
		_asteroid_spin.append(_rng.randf_range(0.05, 0.25))

	for i in 3:
		var transforms: Array = buckets[i]
		if transforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = shapes[i]
		mm.instance_count = transforms.size()
		for j in transforms.size():
			mm.set_instance_transform(j, transforms[j])
		var inst := MultiMeshInstance3D.new()
		inst.name = "Belt%d" % i
		inst.multimesh = mm
		inst.material_override = material
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.set_meta("bucket_start", i * (ASTEROID_COUNT / 3))
		# Which rock variant this instance draws, so a look change can rebuild its
		# geometry from [method _make_rock] without regenerating the belt layout.
		inst.set_meta("rock_variant", i)
		add_child(inst)
		_belt_multimeshes.append(inst)

	# Near-field close-pass rocks: small, close to the flight path.
	# These streak past at cruise speed and are the primary speed cue.
	_build_nearfield()
	# Remember which MultiMesh instance draws each rock, so a rock that is knocked
	# loose can have its visual tracked from its PhysBody node.
	_bind_rock_visuals()


## Record, on each rock's collision anchor, which MultiMesh instance draws it.
## Belt rock `g` lives in instance g%3 at slot g/3 (rocks were appended to each
## bucket in ascending order); the twelve near-field rocks are instance g-260 of
## the near-field mesh.
func _bind_rock_visuals() -> void:
	for g in asteroid_data.size():
		var anchor: Node3D = asteroid_data[g]["node"]
		if g < ASTEROID_COUNT:
			anchor.set_meta("mm", _belt_multimeshes[g % 3])
			anchor.set_meta("j", g / 3)
		else:
			anchor.set_meta("mm", _nearfield_mesh)
			anchor.set_meta("j", g - ASTEROID_COUNT)


## Floating asteroids for dynamic spawning
func _build_floating_asteroids() -> void:
	var shape := _make_rock(4)  # A fifth rock variant for floating asteroids
	var material := _rock_material(2)

	# Physics anchor holder for floating asteroids
	var floating_rock_holder := Node3D.new()
	floating_rock_holder.name = "FloatingPhysRocks"
	add_child(floating_rock_holder)

	# The distant-asteroid density dial (Settings → Quality) scales the count;
	# at 0 they disappear entirely. Applies on the next scene restart.
	var float_count := maxi(0, int(FLOATING_ASTEROID_COUNT * Session.asteroid_density))
	for i in float_count:
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(FLOATING_ASTEROID_MIN_DIST, FLOATING_ASTEROID_MAX_DIST)
		var height := _rng.randfn(-1000.0, 1000.0)  # Full 3D distribution
		var pos := Vector3(cos(angle) * radius, height, sin(angle) * radius)

		# Floating asteroids have more varied sizes
		var size: float = lerpf(3.0, 50.0, pow(_rng.randf(), 2.5))
		var basis := Basis.from_euler(Vector3(
			_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU
		)).scaled(Vector3.ONE * size)

		var anchor := Node3D.new()
		anchor.name = "FloatingRock%d" % i
		anchor.position = pos
		floating_rock_holder.add_child(anchor)
		floating_asteroid_data.append({"position": pos, "radius": size, "node": anchor})
		# Tumble speed: varied for floating asteroids
		_floating_asteroid_spin.append(_rng.randf_range(0.02, 0.15))

	# Create MultiMesh instances for rendering (one for simplicity since count is low)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = shape
	mm.instance_count = floating_asteroid_data.size()
	for j in floating_asteroid_data.size():
		mm.set_instance_transform(j, floating_asteroid_data[j]["node"].transform)
	var inst := MultiMeshInstance3D.new()
	inst.name = "FloatingAsteroids"
	inst.multimesh = mm
	inst.material_override = material
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.set_meta("rock_variant", 4)
	add_child(inst)

	# Remember which MultiMesh instance draws each rock for physics synchronization
	for g in floating_asteroid_data.size():
		var anchor: Node3D = floating_asteroid_data[g]["node"]
		anchor.set_meta("mm", inst)
		anchor.set_meta("j", g)


## Add or remove a rock from the live set: its MultiMesh instance is then written
## from its PhysBody node every frame instead of tumbling in place.
func set_rock_visual_live(body: PhysBody, live: bool) -> void:
	if live:
		if _live_rocks.has(body) or body.node == null:
			return
		# Carry the rock's current orientation onto the anchor so it does not pop
		# to an identity pose the instant it is knocked loose.
		var mm := body.node.get_meta("mm") as MultiMeshInstance3D
		if mm != null and mm.multimesh != null:
			var xform := mm.multimesh.get_instance_transform(int(body.node.get_meta("j")))
			body.node.global_transform = Transform3D(xform.basis, body.node.global_position)
		_live_rocks.append(body)
	else:
		_live_rocks.erase(body)


## A handful of small rocks placed very close to the origin, well inside the
## main belt. They are the speed reference that makes cruise feel fast.
func _build_nearfield() -> void:
	var shape := _make_rock(3)  # A fourth rock variant, unique seed.
	var material := _rock_material(3)
	var count := 12
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = shape
	mm.instance_count = count
	for i in count:
		var angle := _rng.randf() * TAU
		var radius := _rng.randf_range(30.0, 180.0)
		var height := _rng.randf_range(-40.0, 40.0)
		var pos := Vector3(cos(angle) * radius, height, sin(angle) * radius)
		var size := _rng.randf_range(1.0, 3.5)
		var basis := Basis.from_euler(Vector3(
			_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU
		)).scaled(Vector3.ONE * size)
		mm.set_instance_transform(i, Transform3D(basis, pos))
		var anchor := Node3D.new()
		anchor.name = "RockNear%d" % i
		anchor.position = pos
		_rock_holder.add_child(anchor)
		asteroid_data.append({"position": pos, "radius": size, "node": anchor})
		_asteroid_spin.append(_rng.randf_range(0.1, 0.4))
	_nearfield_mesh = MultiMeshInstance3D.new()
	_nearfield_mesh.name = "NearField"
	_nearfield_mesh.multimesh = mm
	_nearfield_mesh.material_override = material
	_nearfield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_nearfield_mesh.set_meta("rock_variant", 3)
	add_child(_nearfield_mesh)


## A lumpy unit-radius solid. Built by jittering the rings of a lathe rather than
## by subdividing a sphere: fewer triangles for the same read, and the flat facets
## catch the light the way the ship parts do.
func _make_rock(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 991 + variant * 37
	var lp := LowPoly.new()
	lp.begin_shape()
	var detail := _detail()
	var stacks := 5 + (3 if detail > 1 else 0)
	var sides := 7 + (4 if detail > 1 else 0)
	var rings: Array = []
	for s in range(stacks + 1):
		var t := float(s) / float(stacks)
		var y := cos(t * PI)
		var r: float = sqrt(maxf(1.0 - y * y, 0.0))
		var ring := PackedVector3Array()
		for i in sides:
			var a := TAU * float(i) / float(sides)
			var jitter := rng.randf_range(0.72, 1.24)
			ring.append(Vector3(
				cos(a) * r * jitter,
				y * rng.randf_range(0.85, 1.1),
				sin(a) * r * jitter
			))
		rings.append(ring)
	lp.add_loft(rings, LowPoly.CH_PRIMARY, true, true)
	lp.end_shape()
	var mesh := lp.commit("rock%d" % variant)
	var style := StyleManager.instance().current_profile
	if style and style.rock_potato > 0.0:
		var rounding := MeshRounding.new()
		rounding.is_asteroid = true
		rounding.rock_potato = style.rock_potato
		mesh = rounding.apply(mesh) as ArrayMesh
	return mesh


# --- Small builders ---------------------------------------------------------

func _torus_ring(angle: float, major: float, minor: float, sides: int) -> PackedVector3Array:
	var out_dir := Vector3(cos(angle), sin(angle), 0.0)
	var centre := out_dir * major
	var ring := PackedVector3Array()
	for i in sides:
		var a := TAU * float(i) / float(sides)
		ring.append(centre + out_dir * (cos(a) * minor) + Vector3(0, 0, sin(a) * minor))
	return ring


func _make_glow_sphere(radius: float, color: Color, detail: int) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10 + detail * 6
	mesh.rings = 6 + detail * 4
	var inst := MeshInstance3D.new()
	inst.name = "Glow"
	inst.mesh = mesh
	inst.material_override = ShipMaterials.glow_material(color, color.a < 1.0)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = radius
	return inst


## Scenery reuses the ship part shader so rocks, hulls and stations share one
## lighting model. The three colours map to the three vertex channels [LowPoly]
## writes.
func _scenery_material(primary: Color, accent: Color, trim: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ShipMaterials.part_shader()
	mat.set_shader_parameter("primary_color", Palette.get_sat_lifted_color(primary))
	mat.set_shader_parameter("accent_color", Palette.get_sat_lifted_color(accent))
	mat.set_shader_parameter("trim_color", Palette.get_sat_lifted_color(trim))
	mat.set_shader_parameter("metallic_amount", 0.12)
	mat.set_shader_parameter("roughness_amount", 0.9)
	mat.set_shader_parameter("specular_amount", 0.14)
	# Rock and concrete want more plate variation than a painted hull, and no
	# rim: a rim light on an asteroid reads as a glowing outline, not as stone.
	mat.set_shader_parameter("plate_variation", 0.14)
	mat.set_shader_parameter("rim_strength", 0.12)
	mat.set_shader_parameter("ao_strength", 0.55)
	# Higher solidity so rocks read as solid against the near-black void
	# rather than blending into it — the see-through problem.
	mat.set_shader_parameter("solidity", 0.65)
	ShipMaterials.apply_style_dials(mat)
	ShipMaterials.apply_outline(mat)
	return mat


## A rock's material: one of [constant Palette.ROCK_FAMILIES] tone triples.
func _rock_material(family: int) -> ShaderMaterial:
	var tones := Palette.rock_family(family)
	return _scenery_material(tones["primary"], tones["accent"], tones["trim"])


## The station's material: the palette's metal tones rather than a rock family, so
## a built structure does not read as a very tidy asteroid.
func _station_material() -> ShaderMaterial:
	return _scenery_material(
		Palette.color("metal_light"), Palette.color("rock_accent"), Palette.color("metal_dark")
	)


func _random_direction() -> Vector3:
	# Uniform on the sphere: sampling z uniformly avoids the pole clustering that
	# a naive pair of angles produces.
	var z := _rng.randf_range(-1.0, 1.0)
	var a := _rng.randf() * TAU
	var r := sqrt(maxf(1.0 - z * z, 0.0))
	return Vector3(cos(a) * r, z, sin(a) * r)


## Create a faint, distant galaxy effect for background depth.
func _make_distant_galaxy() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Create a spiral galaxy-like structure with scattered points
	var detail := _detail() * 4
	var point_count := 300 * detail
	
	for i in point_count:
		# Spiral galaxy distribution
		var t := float(i) / float(point_count)
		var radius := lerpf(500.0, 2000.0, pow(t, 0.5))  # Concentrated center
		var angle := t * TAU * 8.0 + sin(t * 10.0) * 0.5  # Spiral with noise
		var height := (_rng.randf() - 0.5) * 200.0 * sin(t * TAU * 4.0)  # Warped disk
		
		var pos := Vector3(
			cos(angle) * radius,
			height,
			sin(angle) * radius
		)
		
		# Create small quads for each point (better than points for GL compatibility)
		var size := lerpf(2.0, 8.0, _rng.randf())
		var angle_var := _rng.randf() * TAU
		var dx := cos(angle_var) * size * 0.5
		var dy := sin(angle_var) * size * 0.5
		
		# Create a quad facing roughly toward camera (simplified)
		st.add_vertex(pos + Vector3(-dx, -dy, 0))
		st.add_vertex(pos + Vector3(dx, -dy, 0))
		st.add_vertex(pos + Vector3(dx, dy, 0))
		
		st.add_vertex(pos + Vector3(-dx, -dy, 0))
		st.add_vertex(pos + Vector3(dx, dy, 0))
		st.add_vertex(pos + Vector3(-dx, dy, 0))
	
	var inst := MeshInstance3D.new()
	inst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = false
	mat.albedo_color = Color(0.8, 0.7, 1.0, 0.02)  # Very faint bluish
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = -20  # Behind everything
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst

## Create floating space dust clouds for ambient texture.
func _make_space_dust_clouds() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var detail := _detail() * 2
	var cloud_count := 150 * detail
	
	for i in cloud_count:
		# Distributed throughout a large volume
		var pos := Vector3(
			(_rng.randf() - 0.5) * 10000.0,
			(_rng.randf() - 0.5) * 6000.0,
			(_rng.randf() - 0.5) * 10000.0
		)

		# Cloud density varies - denser regions form nebula-like patches
		var density := pow(_rng.randf(), 3.0)  # Mostly sparse with dense clumps
		var size := lerpf(10.0, 100.0, density)

		# Create a simple sphere-ish cloud
		var segments := maxi(4, int(8.0 * density))
		var rings := maxi(3, int(6.0 * density))
		
		if segments < 3 or rings < 2:
			# Just create a few points for very sparse dust
			var point_size := size * 0.1
			st.add_vertex(pos + Vector3(-point_size, 0, 0))
			st.add_vertex(pos + Vector3(point_size, 0, 0))
			st.add_vertex(pos + Vector3(0, point_size, 0))
			
			st.add_vertex(pos + Vector3(point_size, 0, 0))
			st.add_vertex(pos + Vector3(0, -point_size, 0))
			st.add_vertex(pos + Vector3(0, point_size, 0))
		else:
			# Create a simple lathe-based cloud
			var point_step := TAU / float(segments)
			var ring_step := 1.0 / float(rings)
			
			for ring_idx in rings:
				var v0 := float(ring_idx) * ring_step
				var v1 := v0 + ring_step
				var y0 := cos(v0 * PI) * size * 0.5
				var y1 := cos(v1 * PI) * size * 0.5
				var r0 := sin(v0 * PI) * size * 0.5
				var r1 := sin(v1 * PI) * size * 0.5
				
				if r0 < 0.1 or r1 < 0.1:
					continue
				
				for seg_idx in segments:
					var a0 := float(seg_idx) * point_step
					var a1 := a0 + point_step
					
					var x0 := cos(a0) * r0
					var z0 := sin(a0) * r0
					var x1 := cos(a1) * r0
					var z1 := sin(a1) * r0
					var x2 := cos(a1) * r1
					var z2 := sin(a1) * r1
					var x3 := cos(a0) * r1
					var z3 := sin(a0) * r1
					
					# Create two triangles per quad
					st.add_vertex(Vector3(x0, y0, z0))
					st.add_vertex(Vector3(x1, y0, z1))
					st.add_vertex(Vector3(x2, y1, z2))
					
					st.add_vertex(Vector3(x0, y0, z0))
					st.add_vertex(Vector3(x2, y1, z2))
					st.add_vertex(Vector3(x3, y1, z3))
	
	var inst := MeshInstance3D.new()
	inst.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = false
	mat.albedo_color = Color(0.9, 0.8, 1.0, 0.01)  # Extremely faint
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = -25  # Even further back
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst
