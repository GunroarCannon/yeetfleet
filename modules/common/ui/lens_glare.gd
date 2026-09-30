## LensGlare: a sun's glare drawn in screen space — a wide soft bloom, a hot
## white core, soft tapered rays, a long anamorphic streak and a line of
## ghosts through the frame's centre.
##
## Everything is drawn from smooth gradient textures with additive blending,
## so there are no rings from stacked discs and no hard one-pixel ray lines
## (what the old store-art flare did). Put the Control full-rect over a view
## and set [member sun] (pixels); every look is a property, so the store art,
## the level-card bake and the Art Studio share one glare.
class_name LensGlare
extends Control

## Where the sun is on screen, pixels.
@export var sun := Vector2.ZERO
## Overall strength (0 = nothing, 1 = the default glare, up to 2).
@export_range(0.0, 2.0) var strength := 1.0
## Size of the bloom, × the shorter screen side.
@export_range(0.05, 1.5) var bloom_size := 0.55
## The hot core's size, × the shorter screen side.
@export_range(0.0, 0.3) var core_size := 0.06
## How many rays, and how long (× the shorter side) and wide (pixels at the root).
@export_range(0, 24) var rays := 6
@export_range(0.0, 1.5) var ray_length := 0.32
@export_range(1.0, 40.0) var ray_width := 9.0
## Turns the rays (radians).
@export var ray_angle := 0.25
## The anamorphic streak across the frame (0 = none).
@export_range(0.0, 1.0) var streak := 0.6
## How many ghosts along the line through the centre (0 = none).
@export_range(0, 8) var ghosts := 4
## The glare's colour (the core stays white).
@export var tint := Color(1.0, 0.82, 0.55)

static var _soft: Texture2D = null
static var _ray: Texture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func _draw() -> void:
	paint(self, sun, size, self)


## Draw a glare on [param ci] at [param at] for a view of [param view] pixels,
## with [param look]'s settings (a LensGlare, or null for the defaults).
## Useful where a separate Control cannot go; additive blending comes from
## [param ci]'s own material (a LensGlare node sets it up itself).
static func paint(ci: CanvasItem, at: Vector2, view: Vector2, look: LensGlare = null) -> void:
	var g: LensGlare = look if look != null else LensGlare.new()
	var k := clampf(g.strength, 0.0, 2.0)
	if k <= 0.0:
		return
	var s := minf(view.x, view.y)
	var soft := _soft_tex()
	# The bloom: two soft layers, wide and warm, then tighter and brighter.
	var b := s * g.bloom_size
	ci.draw_texture_rect(soft, Rect2(at - Vector2.ONE * b, Vector2.ONE * b * 2.0), false, Color(g.tint, 0.28 * k))
	ci.draw_texture_rect(soft, Rect2(at - Vector2.ONE * b * 0.4, Vector2.ONE * b * 0.8), false, Color(g.tint.lightened(0.3), 0.5 * k))
	# The streak: the soft disc squashed flat and stretched across the frame.
	if g.streak > 0.0:
		var sw := view.x * 1.4 * g.streak
		var sh := s * 0.035
		ci.draw_texture_rect(soft, Rect2(at - Vector2(sw, sh), Vector2(sw, sh) * 2.0), false, Color(g.tint.lightened(0.2), 0.55 * k))
		ci.draw_texture_rect(soft, Rect2(at - Vector2(sw * 0.5, sh * 0.35), Vector2(sw, sh * 0.7)), false, Color(1, 1, 1, 0.45 * k))
	# Rays: soft tapered spikes, alternating long and short.
	if g.rays > 0 and g.ray_length > 0.0:
		var ray := _ray_tex()
		for i in g.rays:
			var a := g.ray_angle + TAU * i / g.rays
			var len := s * g.ray_length * (1.0 if i % 2 == 0 else 0.6)
			ci.draw_set_transform(at, a)
			ci.draw_texture_rect(ray, Rect2(Vector2(0, -g.ray_width * 0.5), Vector2(len, g.ray_width)), false, Color(g.tint.lightened(0.4), 0.7 * k))
		ci.draw_set_transform(Vector2.ZERO)
	# The core: a white-hot disc with a soft edge.
	var c := s * g.core_size
	if c > 0.0:
		ci.draw_texture_rect(soft, Rect2(at - Vector2.ONE * c * 2.2, Vector2.ONE * c * 4.4), false, Color(1, 0.97, 0.9, 0.9 * k))
		ci.draw_texture_rect(soft, Rect2(at - Vector2.ONE * c, Vector2.ONE * c * 2.0), false, Color(1, 1, 1, 1.0 * minf(k, 1.0)))
	# Ghosts: soft coloured discs along the line from the sun through the middle.
	if g.ghosts > 0:
		var mid := view * 0.5
		var cols: Array[Color] = [Color(0.5, 1.0, 0.7), Color(1.0, 0.5, 0.8), Color(0.5, 0.8, 1.0), Color(1.0, 0.9, 0.4)]
		for i in g.ghosts:
			var t := 0.4 + 1.3 * float(i) / maxf(g.ghosts - 1, 1)
			var p := at.lerp(mid, t)
			var r := s * (0.025 + 0.02 * (i % 3))
			ci.draw_texture_rect(soft, Rect2(p - Vector2.ONE * r, Vector2.ONE * r * 2.0), false, Color(cols[i % cols.size()], 0.16 * k))


## A round falloff, white in the middle to clear at the edge (smooth, no rings).
static func _soft_tex() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 256
		t.height = 256
		_soft = t
	return _soft


## A ray: bright at its root fading to nothing at its tip, soft across.
static func _ray_tex() -> Texture2D:
	if _ray == null:
		var img := Image.create(128, 16, false, Image.FORMAT_RGBA8)
		for x in 128:
			var along := pow(1.0 - x / 127.0, 1.6)
			for y in 16:
				var across := 1.0 - absf(y - 7.5) / 8.0
				img.set_pixel(x, y, Color(1, 1, 1, along * across * across))
		_ray = ImageTexture.create_from_image(img)
	return _ray
