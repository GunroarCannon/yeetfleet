class_name PortraitCache extends RefCounted

var _cache: Dictionary = {}  # key -> value
var _order: Array[String] = []  # LRU order (most recent at end)
var _capacity: int = 64


func _init(capacity: int = 64) -> void:
	_capacity = capacity


func find(species_id: StringName, seed_val: int, lod: int, style_id: StringName) -> Texture2D:
	var key := _make_key(species_id, seed_val, lod, style_id)
	if _cache.has(key):
		_touch(key)
		return _cache[key]
	return null


func put(species_id: StringName, seed_val: int, lod: int, style_id: StringName, texture: Texture2D) -> void:
	# Don't cache above LOD_CINEMATIC count 8 (memory)
	if lod > Lod.LOD_CINEMATIC and _cache.size() >= _capacity:
		return
	
	var key := _make_key(species_id, seed_val, lod, style_id)
	_cache[key] = texture
	_touch(key)
	
	# Evict if over capacity
	while _cache.size() > _capacity and _order.size() > 0:
		var oldest: String = _order.pop_front()
		_cache.erase(oldest)


func has(species_id: StringName, seed_val: int, lod: int, style_id: StringName) -> bool:
	return _cache.has(_make_key(species_id, seed_val, lod, style_id))


func clear() -> void:
	_cache.clear()
	_order.clear()


func size() -> int:
	return _cache.size()


func _make_key(species_id: StringName, seed_val: int, lod: int, style_id: StringName) -> String:
	return "%s|%d|%d|%s" % [String(species_id), seed_val, lod, String(style_id)]


func _touch(key: String) -> void:
	_order.erase(key)
	_order.append(key)
