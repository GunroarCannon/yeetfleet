## MenuScreen: what every front-end screen shares — a handle on the
## [MenuRoot], and three hooks the root calls.
class_name MenuScreen
extends Control

var menu: MenuRoot


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## The screen has just been shown. Refresh from [Campaign], play its entrance.
func opened() -> void:
	pass


## The window changed size or shape; re-place anything positioned by hand.
func layout() -> void:
	pass


## Back / Escape: close something of this screen's own and return true, or
## return false to let the root go home.
func back() -> bool:
	return false


func viewport_size() -> Vector2:
	return get_viewport_rect().size


## A type size scaled for the window (see [method GraffitiStyle.fit]).
func fit(px: int) -> int:
	return GraffitiStyle.fit(px, viewport_size())


## One design pixel at this window: the short side over 720. Every size cap
## is multiplied by it — under the project's canvas_items stretch a portrait
## phone's canvas is ~1280×1775, and unscaled caps left it half-size.
func unit() -> float:
	var s := viewport_size()
	return maxf(minf(s.x, s.y) / 720.0, 0.5)


## The top bar's height, shared by every screen that has one.
func bar_height() -> float:
	return clampf(viewport_size().y * 0.11, 58.0, 92.0 * unit())


func portrait() -> bool:
	var s := viewport_size()
	return s.y > s.x
