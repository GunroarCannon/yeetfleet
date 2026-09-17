## A complete, saveable planet definition: type, colours, ring parameters,
## atmosphere and noise seeds. Pure data, no scene references — the same
## pattern as [ShipDesign]: serialisable to JSON and saveable as a .tres
## resource file.
##
## Created by the planet editor or generated randomly, then handed to
## [Planet] to build the actual meshes and shaders from.
class_name PlanetData
extends Resource

enum PlanetType { GAS_GIANT, ROCKY }

const FORMAT_VERSION := 4

## Default palette — a warm rocky world.
const DEFAULT_PRIMARY := Color(0.45, 0.32, 0.22)
const DEFAULT_SECONDARY := Color(0.68, 0.55, 0.38)
const DEFAULT_WATER := Color(0.09, 0.22, 0.38)
const DEFAULT_RING_A := Color(0.75, 0.70, 0.62)
const DEFAULT_RING_B := Color(0.55, 0.48, 0.38)

@export var planet_name := "Untitled"
@export var planet_type: PlanetType = PlanetType.ROCKY
@export var seed_value: int = 0

# --- Appearance ---
@export var primary_color: Color = DEFAULT_PRIMARY
@export var secondary_color: Color = DEFAULT_SECONDARY
## Sea colour, rocky planets only. A third colour rather than a tint of
## [member secondary_color]: with water, lowland and peak all drawn from two
## pickers, every rocky planet came out one flat hue.
@export var water_color: Color = DEFAULT_WATER
## How frozen the planet is. Drives the polar caps and the snow line together, so
## one slider covers "tropical" through "iceball".
@export_range(0.0, 1.0, 0.01) var ice_amount := 0.45

# --- Rings ---
@export var ring_enabled := false
@export_range(0.1, 2.0, 0.01) var ring_inner_radius := 0.4
@export_range(0.5, 4.0, 0.01) var ring_outer_radius := 1.2
@export_range(0.0, 2.0, 0.01) var ring_dust_density := 1.0
@export_range(0.0, 1.0, 0.01) var ring_opacity := 0.75
## How many concentric bands the ring resolves into (a small number reads as a
## few broad bands, a large one as fine dust streaking).
@export_range(2, 24, 1) var ring_bands := 12
@export var ring_color_a: Color = DEFAULT_RING_A
@export var ring_color_b: Color = DEFAULT_RING_B

# --- Atmosphere ---
@export_range(0.0, 1.0, 0.01) var atmosphere_density := 0.0
@export var atmosphere_color: Color = Color(0.45, 0.72, 1.0, 1.0)

# --- Clouds ---
## Cloud coverage: 0 = clear, 1 = overcast. A separate translucent layer above
## the surface (see Planet's cloud sphere), so it can be tuned independently of
## the atmosphere.
@export_range(0.0, 1.0, 0.01) var cloud_density := 0.0
@export var cloud_color: Color = Color(0.95, 0.96, 1.0, 1.0)

# --- Motion / physics ---
## Gravity pull in game mass units. FlightRoot registers this planet's gravity
## body with this mass, so a high-gravity world pulls ships harder.
@export_range(0.0, 100.0, 0.5) var gravity_mass := 10.0

# --- Shader parameters ---
@export_range(0.0, 2.0, 0.01) var swirl_speed := 0.15
@export_range(0.0, 10.0, 0.1) var swirl_scale := 3.0
@export_range(2.0, 20.0, 0.5) var band_count := 8.0
@export_range(0.0, 1.0, 0.01) var detail_strength := 0.12
## Axial spin. See [method Planet._process] — the mesh actually turns at this
## times [constant Planet.SPIN_MULT] rad/s, so "axis rotation speed" is a real
## per-planet dial rather than a shared constant.
@export_range(0.0, 1.0, 0.01) var rotation_speed := 0.02

# --- Orbit ---
## Multiplier on this body's gravity-source strength — how hard *it* pulls its
## own moons/asteroids/neighbours — independent of [member gravity_mass], which
## is the player-facing surface pull used for landing/flight feel. A generator
## placing this body into a live [GravitySystem] scales the mass it registers
## by this, so two visually identical planets can hold their orbiters with
## different authority.
@export_range(0.1, 3.0, 0.05) var orbit_strength := 1.0
## Multiplier applied to the computed circular-orbit speed when this body is
## placed into orbit around a parent. 1.0 is a clean circular orbit; higher
## overshoots into a faster, more eccentric path, lower undershoots into one
## that dips closer to its parent each pass.
@export_range(0.2, 3.0, 0.05) var orbit_speed := 1.0

# --- Terrain ---
# What the seed actually drives. Fed to the two [FastNoiseLite] layers that
# [PlanetGenerator] displaces the cube-sphere with, so two planets with the same
# seed have the same coastlines and the same mountain ranges.

## Height of the tallest peak as a fraction of [member planet_radius]. Gas giants
## ignore this — see [method effective_terrain_height].
@export_range(0.0, 0.25, 0.005) var terrain_height := 0.06
## Continent size. Low values give a few big landmasses, high an archipelago.
@export_range(0.2, 4.0, 0.05) var continent_scale := 1.1
## Mountain-range size, as a multiple of the continent frequency.
@export_range(1.0, 12.0, 0.1) var mountain_scale := 4.0
## How much the ridged mountain layer adds on top of the continents.
@export_range(0.0, 1.0, 0.01) var ridge_strength := 0.45
## Where the waterline sits in the elevation range. Above it is land, below is sea.
@export_range(0.0, 1.0, 0.01) var sea_level := 0.48

# --- Geometry ---
@export_range(16, 128, 4) var sphere_resolution := 48
@export_range(0.5, 100.0, 0.5) var planet_radius := 5.0
@export_range(4, 64, 2) var ring_segments := 48
@export_range(8, 128, 4) var ring_radial_segments := 16


func is_gas_giant() -> bool:
	return planet_type == PlanetType.GAS_GIANT


## Displacement actually applied. A gas giant has no solid surface to raise
## mountains on, so the slider is ignored rather than hidden: switching the type
## back brings the terrain you had straight back.
func effective_terrain_height() -> float:
	return 0.0 if is_gas_giant() else terrain_height


func type_label() -> String:
	match planet_type:
		PlanetType.GAS_GIANT: return "Gas Giant"
		_: return "Rocky"


## Build a deterministic RNG from the seed. Used by both the editor
## (for "Generate Random") and by [Planet] for noise seeds.
func seeded_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- Serialisation ---------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"format": FORMAT_VERSION,
		"name": planet_name,
		"type": planet_type,
		"seed": seed_value,
		"primary": primary_color.to_html(false),
		"secondary": secondary_color.to_html(false),
		"water": water_color.to_html(false),
		"ice": ice_amount,
		"ring_enabled": ring_enabled,
		"ring_inner": ring_inner_radius,
		"ring_outer": ring_outer_radius,
		"ring_dust": ring_dust_density,
		"ring_opacity": ring_opacity,
		"ring_bands": ring_bands,
		"ring_color_a": ring_color_a.to_html(false),
		"ring_color_b": ring_color_b.to_html(false),
		"atmo_density": atmosphere_density,
		"atmo_color": atmosphere_color.to_html(false),
		"cloud_density": cloud_density,
		"cloud_color": cloud_color.to_html(false),
		"gravity_mass": gravity_mass,
		"swirl_speed": swirl_speed,
		"swirl_scale": swirl_scale,
		"band_count": band_count,
		"detail": detail_strength,
		"rotation": rotation_speed,
		"orbit_strength": orbit_strength,
		"orbit_speed": orbit_speed,
		"resolution": sphere_resolution,
		"radius": planet_radius,
		"terrain_height": terrain_height,
		"continent_scale": continent_scale,
		"mountain_scale": mountain_scale,
		"ridge_strength": ridge_strength,
		"sea_level": sea_level,
	}


static func from_dict(d: Dictionary) -> PlanetData:
	var p := PlanetData.new()
	p.planet_name = String(d.get("name", "Untitled"))
	p.planet_type = int(d.get("type", PlanetType.ROCKY))
	p.seed_value = int(d.get("seed", 0))
	p.primary_color = Color.from_string(String(d.get("primary", "")), DEFAULT_PRIMARY)
	p.secondary_color = Color.from_string(String(d.get("secondary", "")), DEFAULT_SECONDARY)
	# Format 2 and earlier had no sea colour: the ocean was a darkened
	# secondary_color. Deriving the same shade keeps those files looking like
	# themselves rather than suddenly growing blue oceans on a desert world.
	p.water_color = Color.from_string(
		String(d.get("water", "")), p.secondary_color.darkened(0.45)
	)
	p.ice_amount = float(d.get("ice", 0.45))
	p.ring_enabled = bool(d.get("ring_enabled", false))
	p.ring_inner_radius = float(d.get("ring_inner", 0.4))
	p.ring_outer_radius = float(d.get("ring_outer", 1.2))
	p.ring_dust_density = float(d.get("ring_dust", 1.0))
	p.ring_opacity = float(d.get("ring_opacity", 0.75))
	p.ring_bands = int(d.get("ring_bands", 12))
	p.ring_color_a = Color.from_string(String(d.get("ring_color_a", "")), DEFAULT_RING_A)
	p.ring_color_b = Color.from_string(String(d.get("ring_color_b", "")), DEFAULT_RING_B)
	p.atmosphere_density = float(d.get("atmo_density", 0.0))
	p.atmosphere_color = Color.from_string(String(d.get("atmo_color", "")), Color(0.45, 0.72, 1.0))
	p.cloud_density = float(d.get("cloud_density", 0.0))
	p.cloud_color = Color.from_string(String(d.get("cloud_color", "")), Color(0.95, 0.96, 1.0))
	p.gravity_mass = float(d.get("gravity_mass", 10.0))
	p.swirl_speed = float(d.get("swirl_speed", 0.15))
	p.swirl_scale = float(d.get("swirl_scale", 3.0))
	p.band_count = float(d.get("band_count", 8.0))
	p.detail_strength = float(d.get("detail", 0.12))
	p.rotation_speed = float(d.get("rotation", 0.02))
	# Format 3 and earlier predate these two — default to "plain circular orbit,
	# ordinary gravitational authority" so an old file's bodies behave exactly
	# as they always did.
	p.orbit_strength = float(d.get("orbit_strength", 1.0))
	p.orbit_speed = float(d.get("orbit_speed", 1.0))
	p.sphere_resolution = int(d.get("resolution", 48))
	p.planet_radius = float(d.get("radius", 5.0))
	# Format 1 predates terrain entirely, so those files load with the defaults.
	p.terrain_height = float(d.get("terrain_height", 0.06))
	p.continent_scale = float(d.get("continent_scale", 1.1))
	p.mountain_scale = float(d.get("mountain_scale", 4.0))
	p.ridge_strength = float(d.get("ridge_strength", 0.45))
	p.sea_level = float(d.get("sea_level", 0.48))
	return p


func to_json(pretty := true) -> String:
	return JSON.stringify(to_dict(), "  " if pretty else "")


static func from_json(text: String) -> PlanetData:
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return from_dict(parsed)
	return null
