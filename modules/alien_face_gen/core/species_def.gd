class_name SpeciesDef extends Resource

const PRESENCE_REQUIRED := 2.0
const PRESENCE_FORBIDDEN := -1.0

@export var id: StringName = &""
@export var display_name: String = ""
@export var ranges: Dictionary = {}  # field_name -> Vector2(min, max), normalised
@export var presence: Dictionary = {}  # slot_name -> PRESENCE_REQUIRED / _FORBIDDEN / float prob
@export var enum_weights: Dictionary = {}  # enum_field -> { value:int -> weight:float }
@export var allowed_palettes: Array[StringName] = []
@export var symmetry_mode: int = FaceEnums.SymmetryMode.BILATERAL
@export var radial_count: int = 2
@export var default_style_2d: StringName = &"flat_vector"
@export var default_style_3d: StringName = &"faceted"
@export var depth_profile: Curve = null
@export var silhouette_tag: StringName = &""
