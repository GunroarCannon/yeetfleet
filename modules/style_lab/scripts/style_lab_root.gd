## StyleLabRoot: the lab scene for tuning the global look.
##
## A standalone scene for authoring StyleProfile resources. It shows
## a ship and a planet side by side, with sliders for every field in
## StyleProfile between them. The sliders live-edit a StyleProfile
## resource, with geometry changes requiring a reload (handled via
## an Apply button).
##
## Features:
## - Ship and planet preview to see style changes in real-time
## - Live sliders for shading dials (apply immediately)
## - Reload button for geometry dials (roundness, chunkiness, rock_potato)
## - Save profile as .tres
##
## Consumes: StyleProfile (edited live)
## Emits: none (standalone tool)

@tool
class_name StyleLabRoot extends Node3D

# Exported so the lab scene can set it
@export var profile: StyleProfile

# Preview objects
@onready var ship_preview: Node3D = $ShipPreview
@onready var planet_preview: Node3D = $PlanetPreview

# Track which dials require reload to batch geometry changes
var _pending_reload := false
const GEOMETRY_DIALS := ["roundness", "chunkiness", "rock_potato"]

func _ready() -> void:
	# Apply the initial profile
	_apply_profile()

	# Connect to style manager to get live updates when profile changes externally
	StyleManager.instance().connect("style_changed", Callable(self, "_on_external_profile_changed"))

func _process(delta: float) -> void:
	# In a full implementation, we might animate the preview objects
	pass

func _on_external_profile_changed(new_profile: StyleProfile) -> void:
	# Called when StyleManager changes (e.g., from game settings)
	if profile == new_profile:
		return  # Avoid infinite loop
	profile = new_profile
	_apply_profile()

func _apply_profile() -> void:
	# Apply the current profile to preview objects
	# In a full implementation, this would:
	# 1. Update ship preview materials based on profile
	# 2. Update planet preview materials based on profile
	# 3. For live dials (shading, outline, etc.), apply immediately
	# 4. For geometry dials, mark as pending reload

	_pending_reload = false
	for dial in GEOMETRY_DIALS:
		# In a real implementation, we'd check if the dial changed
		# and set _pending_reload = true if so
		pass

	# Update preview immediately for live dials
	_update_preview_live()

func _update_preview_live() -> void:
	# Apply shading dials, outline, spec/rim, palette, star settings, etc.
	# These take effect immediately without requiring a reload
	pass

func _on_apply_button_pressed() -> void:
	# Called when user clicks Apply button (for geometry dials)
	if _pending_reload:
		# In a full implementation, this would:
		# 1. Signal PartMeshFactory to clear its cache
		# 2. Request a scene reload
		# 3. Notify user that changes take effect after reload
		_pending_reload = false
		# For now, just apply everything
		_apply_profile()

func _on_save_profile_requested() -> void:
	# TODO: Implement save dialog
	pass

# GUI signal forwarders for individual dials (to be connected in scene)
func _on_roundness_changed(value: float) -> void:
	profile.roundness = value
	_pending_reload = true

func _on_chunkiness_changed(value: float) -> void:
	profile.chunkiness = value
	_pending_reload = true

func _on_rock_potato_changed(value: float) -> void:
	profile.rock_potato = value
	_pending_reload = true

func _on_shading_bands_changed(value: int) -> void:
	profile.shading_bands = value
	_update_preview_live()  # Live update

func _on_outline_width_changed(value: float) -> void:
	profile.outline_width = value
	_update_preview_live()  # Live update

# ... similar functions for other dials would go here ...
