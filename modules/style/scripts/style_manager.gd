## StyleManager: singleton that holds the current look and palette, and applies them.
##
## There is one global look (grounded, friendly or cartoony) and one global
## palette, both affecting all modules. The manager holds the current
## [StyleProfile] and [Palette] and provides an apply() method that modules call
## to update their appearance.
##
## Modules do not reach into the manager; they call StyleManager.apply() and
## receive the current profile as an argument, or read a role through
## [method Palette.color]. Colour flows the second way because every material
## builder needs a colour, not a profile.
##
## Emits: style_changed when the profile changes, palette_changed when the
## palette does. Both fire from [method set_profile] / [method set_palette], and
## [method apply] re-pushes whatever is current, so a consumer can listen to the
## one it cares about and call the other's accessor lazily.
##
## Consumes: StyleProfile (the current look), Palette (the current colours)
##
## See TECHNICAL_PLAN.md §3.3 for how this subsumes the three existing
## style statics (ShipMaterials.high_contrast, Planet.high_detail,
## Theme.high_contrast).

@tool
class_name StyleManager extends Node

# Singleton pattern
static var _instance: StyleManager

# The current look; null means use hardcoded defaults (today)
var current_profile: StyleProfile

## The current colours; null means every role falls back to
## [constant Palette.DEFAULTS], which is the look the game had before palettes
## existed.
var current_palette: Palette

# Signal for modules to listen to
signal style_changed(new_profile: StyleProfile)
signal palette_changed(new_palette: Palette)
## Fires when the global toon override is flipped. Consumers read
## [ToonOverride.enabled] rather than the argument, since the setting is owned
## by [StyleSettings].
signal toon_changed(enabled: bool)
## Fires when wireframe mode is toggled.
signal wireframe_changed(enabled: bool)

func _init() -> void:
	if _instance:
		push_error("StyleManager is a singleton! Use StyleManager.instance()")
	else:
		_instance = self

static func instance() -> StyleManager:
	if not _instance:
		# Auto-create on first access (lazy singleton)
		_instance = StyleManager.new()
		_instance.load_saved()
	return _instance


# --- Selecting --------------------------------------------------------------

## Switch to [param profile] and push it everywhere. Geometry dials need the mesh
## cache cleared and live ships re-assembled first, or a mesh built for the old
## look is reused under the new one — see [method requires_reload].
func set_profile(profile: StyleProfile, persist := true) -> void:
	if profile == null:
		return
	var changed := profile != current_profile
	current_profile = profile
	if persist:
		StyleSettings.set_profile_id(profile.id)
	if changed and requires_reload_of(profile):
		_reload_geometry()
	apply()


## Switch to [param palette] and push it everywhere. Purely a recolour — no mesh
## carries a palette colour, so nothing is rebuilt.
func set_palette(palette: Palette, persist := true) -> void:
	if palette == null:
		return
	current_palette = palette
	if persist:
		StyleSettings.set_palette_id(palette.id)
	apply()


## Force toon shading on or off globally and push the change everywhere, the same
## way a profile or palette change does. Stored on [StyleSettings] so it survives
## a restart.
func set_toon_shading(value: bool) -> void:
	StyleSettings.set_toon_shading(value)
	apply()
	emit_signal("toon_changed", value)


## True if wireframe mode is active either via StyleSettings toggle or profile.
func is_wireframe() -> bool:
	return StyleSettings.wireframe_mode or (current_profile != null and current_profile.wireframe)


func set_wireframe(value: bool) -> void:
	StyleSettings.set_wireframe_mode(value)
	apply()
	emit_signal("wireframe_changed", value)


func toggle_wireframe() -> bool:
	var next_val := not is_wireframe()
	set_wireframe(next_val)
	return next_val


## Switch to palette with id [param palette_id].
func set_palette_by_id(palette_id: String) -> void:
	var p := Palette.find_by_id(palette_id)
	if p != null:
		set_palette(p)


## Switch to profile with id [param profile_id].
func set_profile_by_id(profile_id: String) -> void:
	var p := find_profile(profile_id)
	if p != null:
		set_profile(p)


## Toggles the global art style between 'grounded' (realistic, sharp) and 'cartoony' (rounded, chunky, toon-shaded).
func toggle_art_style() -> StyleProfile:
	var is_cartoony := current_profile != null and current_profile.id == "cartoony"
	var target_id := "grounded" if is_cartoony else "cartoony"
	set_profile_by_id(target_id)
	return current_profile


## Restore the look and palette the player last chose. Called once at boot, before
## any scene builds its materials.
func load_saved() -> void:
	StyleSettings.load_from_disk()
	var target_id := StyleSettings.profile_id
	if target_id == "":
		target_id = "cartoony"
	var profile := find_profile(target_id)
	if profile != null:
		current_profile = profile
	if current_profile == null:
		current_profile = find_profile("cartoony")
	if StyleSettings.palette_id != "":
		var palette := Palette.find_by_id(StyleSettings.palette_id)
		if palette != null:
			current_palette = palette


## The built-in look with [param wanted] as its id, or null.
func find_profile(wanted: String) -> StyleProfile:
	for profile in StyleProfile.all():
		if profile.id == wanted:
			return profile
	return null


## Whether moving to [param profile] changes a geometry dial, and so needs the
## mesh cache dropped and live hulls rebuilt.
func requires_reload_of(profile: StyleProfile) -> bool:
	if current_profile == null:
		return false
	for dial in ["roundness", "chunkiness", "rock_potato"]:
		if not is_equal_approx(float(current_profile.get(dial)), float(profile.get(dial))):
			return true
	return false


## Drop every cached part mesh built under the old look and ask live scene trees
## to rebuild. Modules that instance meshes listen for [signal style_changed] and
## re-ask the factory; this only has to clear the stale entries.
func _reload_geometry() -> void:
	PartMeshFactory.clear_cache()


# --- Applying ---------------------------------------------------------------

func apply() -> void:
	# Modules call this to get the current profile. Planets are pushed even with
	# no profile, because the toon override and the palette do not need one.
	_push_to_planets(current_profile)
	emit_signal("style_changed", current_profile)
	emit_signal("palette_changed", current_palette)
	emit_signal("toon_changed", ToonOverride.enabled())
	emit_signal("wireframe_changed", is_wireframe())


## Push the planet shading dials onto every live [Planet], mirroring
## [method Planet.swap_all_atmosphere_shaders]'s group-walk pattern -- the
## precedent this module was built to subsume (see class doc). Both dials are
## shading dials (apply live, no mesh reload), so a [method Planet.refresh_appearance]
## is enough.
##
## Also walks the palette and the toon override down to the worlds, which is what
## makes "a palette change reaches every game element" true for planets as well
## as hulls: [method Planet.apply_palette] remaps the authored colours onto the
## palette's planet roles, and toon mode flattens the surface into bands.
func _push_to_planets(style: StyleProfile) -> void:
	var loop := Engine.get_main_loop()
	if loop == null:
		return
	var toon := ToonOverride.enabled()
	for node in loop.get_nodes_in_group("planets"):
		if node is Planet and node.data != null:
			if style != null:
				node.data.detail_strength = 0.0 if toon else style.planet_detail
				node.data.band_count = 14.0 if toon else lerpf(2.0, 20.0, style.planet_bands)
			node.apply_palette()
			node.refresh_appearance()

# Convenience for modules that want to check if a dial requires reload
static func requires_reload(dial_name: String) -> bool:
	var profile = instance().current_profile
	if profile:
		return profile.requires_reload(dial_name)
	return false  # Default to no reload if no profile
