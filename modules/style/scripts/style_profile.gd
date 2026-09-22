## StyleProfile: every dial that decides the global look.
##
## A Resource rather than a pile of consts so that a look is an object you can
## save, name and hand around. Three looks ship with the module — grounded,
## friendly and cartoony — and the style lab (M3's companion scene) is where new
## ones are authored: every field below is a live slider there, except the
## geometry dials (roundness, chunkiness, rock_potato) which require a reload.
##
## Shading dials apply live; geometry dials reload the scene.
##
## See TECHNICAL_PLAN.md §3.3 for the reload problem and honest answer.
class_name StyleProfile
extends Resource

## Stable id, matching the file name. What [StyleSettings] saves and what the
## picker reports back when the player flips the toggle.
@export var id := ""
## Name shown in the picker.
@export var display_name := "Untitled"

## Geometry dials (require mesh cache reload)
@export_range(0.0, 1.0) var roundness := 0.0    # Bevel width + normal smoothing
@export_range(0.0, 1.0) var chunkiness := 0.0   # Proportion scaling — fatter/stubbier
@export_range(0.0, 1.0) var rock_potato := 0.0  # Subdivision + noise on asteroids

## Shading dials (apply live)
@export_range(0, 5) var shading_bands := 2      # 0=smooth gradient, 2-3=friendly ramp
@export_range(0, 0.1) var outline_width := 0.02 # Ink outline on hulls and rocks
@export var outline_color := Color(0, 0, 0, 1)  # Black outline
@export_range(0.0, 2.0) var spec_amount := 1.0  # Kill specular for soft look
@export_range(0.0, 2.0) var rim_amount := 1.0   # Kill rim for soft look
@export_range(0.0, 2.0) var palette_saturation := 1.0  # Pastel-ise palette
@export_range(-0.5, 0.5) var palette_lift := 0.0    # Lift pastel effect
@export_range(0.0, 1.0) var planet_detail := 0.0  # Noisy realistic -> flat bands
@export_range(0.0, 1.0) var planet_bands := 0.0   # Flat colour bands strength
@export_range(0, 900) var star_count := 100     # 900 small -> few big soft
@export_range(0.1, 5.0) var star_size := 1.0    # Star size multiplier
## Star silhouette: 0 draws round dots, 1 draws a five-pointed cartoon star with
## rounded tips and valleys. Continuous rather than a bool because the same radius
## function produces both — a dot is a star of depth zero.
@export_range(0.0, 1.0) var star_five_point := 0.0

## Live impact deformation (consumes PhysProfile.squash_amount)
@export var squash_enabled := false  # Consumes PhysProfile.squash_amount for impact deformation

## Vector Arcade wireframe mode
@export var wireframe := false

## Utility: whether a dial requires reload
func requires_reload(dial_name: String) -> bool:
	return dial_name in ["roundness", "chunkiness", "rock_potato"]


## Where the built-in looks live.
const DIR := "res://modules/style/data/profiles"


## Load every profile in [constant DIR], sorted by display name, for the picker.
## Returns an empty array rather than erroring when the directory is missing, so a
## stripped build still boots.
static func all() -> Array[StyleProfile]:
	var out: Array[StyleProfile] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		# Exported projects report the stripped name; the editor reports the
		# full one.
		if not (file_name.ends_with(".tres") or file_name.ends_with(".tres.remap")):
			continue
		var res := load(DIR.path_join(file_name.trim_suffix(".remap")))
		if res is StyleProfile:
			out.append(res)
	out.sort_custom(func(a: StyleProfile, b: StyleProfile) -> bool: return a.display_name < b.display_name)
	return out