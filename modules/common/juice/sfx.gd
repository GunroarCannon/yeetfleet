## The bundled Sci-Fi Sound Library, exposed as named streams.
##
## One place that knows where the MP3s live and what each one is for. [SpaceAudio]
## asks here for the sounds that replace its procedural bank, and [AddonVfx]
## asks here for the one-shots it fires alongside an impact, so the asset
## library is wired in once rather than path-by-path at every call site.
##
## Streams are loaded once and cached. Every id that names several files
## (the ten lasers) resolves through [method random_stream] for variation;
## [method stream] returns the first variant for callers that want something
## deterministic. A missing file degrades to null rather than erroring, so a
## stripped build that ships without the MP3s still boots — the synth fallback
## in [SpaceAudio] covers it.
##
## Nothing here plays anything: this is a pure library, and the module that
## wants the sound owns the player and the bus.
class_name Sfx
extends RefCounted

const DIR := "res://assets/sounds/SciFi Sound Library"

## id -> file names relative to [constant DIR]. Order matters: variants are
## picked from this list, so the first entry is the "default" sound.
const FILES := {
	&"laser": [
		"Laser/Laser_00.mp3", "Laser/Laser_01.mp3", "Laser/Laser_02.mp3",
		"Laser/Laser_03.mp3", "Laser/Laser_04.mp3", "Laser/Laser_05.mp3",
		"Laser/Laser_06.mp3", "Laser/Laser_07.mp3", "Laser/Laser_08.mp3",
		"Laser/Laser_09.mp3",
	],
	&"kinetic": ["Laser/Laser_02.mp3", "Laser/Laser_05.mp3", "Laser/Laser_08.mp3"],
	&"railgun": ["Laser/Laser_03.mp3", "Laser/Laser_09.mp3"],
	&"plasma": ["Laser/Laser_06.mp3", "Laser/Laser_07.mp3"],
	&"missile": ["Laser/Laser_04.mp3"],
	&"hit": ["Laser/Laser_01.mp3", "Laser/Laser_09.mp3"],
	&"engine_loop_small": ["SpaceShip_Engine_Small_Loop_00.mp3"],
	&"engine_loop_medium": ["SpaceShip_Engine_Medium_Loop_00.mp3"],
	&"engine_loop_large": ["SpaceShip_Engine_Large_Loop_00.mp3"],
	&"warp": ["WarpDrive_00.mp3", "WarpDrive_01.mp3", "WarpDrive_02.mp3"],
	&"menu_select": ["Menu_Select_00.mp3", "Menu_Select_01.mp3"],
	&"alarm": ["Alarm_Loop_00.mp3", "Alarm_Loop_01.mp3"],
	&"jingle_win": ["Jingle_Win_00.mp3", "Jingle_Win_01.mp3"],
	&"jingle_lose": ["Jingle_Lose_00.mp3"],
	&"jingle_achievement": ["Jingle_Achievement_00.mp3"],
	&"robot_talk": ["Robot_Talk_00.mp3", "Robot_Talk_01.mp3", "Robot_Talk_02.mp3"],
	&"robot_activated": ["Robot_Activated_00.mp3"],
	&"alien_language": ["Alien_Language_00.mp3"],
	&"ambience_space": ["Ambience_Space_00.mp3"],
	&"ambience_planet": ["Ambience_AlienPlanet_00.mp3"],
	&"ambience_hive": ["Ambience_AlienHive_00.mp3"],
	&"ambience_blackhole": ["Ambience_BlackHole_00.mp3"],
}

## Ids whose streams should loop forever when played.
const LOOPING := [
	&"engine_loop_small", &"engine_loop_medium", &"engine_loop_large",
	&"warp", &"alarm", &"ambience_space", &"ambience_planet",
	&"ambience_hive", &"ambience_blackhole",
]

static var _cache: Dictionary = {}


## The first, canonical stream for [param id], or null when the library has no
## such id or the file is missing.
static func stream(id: StringName) -> AudioStream:
	var variants := streams(id)
	return variants[0] if not variants.is_empty() else null


## A random variant for [param id]. Falls back to null exactly like
## [method stream], so a caller can always guard one way.
static func random_stream(id: StringName) -> AudioStream:
	var variants := streams(id)
	if variants.is_empty():
		return null
	return variants[randi() % variants.size()]


## Every loaded variant for [param id], in the order declared above. The array is
## cached, so this is cheap enough to call every shot.
static func streams(id: StringName) -> Array[AudioStream]:
	if _cache.has(id):
		return _cache[id]
	var out: Array[AudioStream] = []
	var files: Array = FILES.get(id, [])
	for file_name: String in files:
		var s := _load(String(file_name), id in LOOPING)
		if s != null:
			out.append(s)
	_cache[id] = out
	return out


## Whether the library can supply anything at all. Checked before the flight
## module commits to the library bank.
static func available() -> bool:
	return stream(&"laser") != null


## Every id the library knows, for a settings screen that wants to audition them.
static func ids() -> Array:
	return FILES.keys()


static func _load(relative: String, looping: bool) -> AudioStream:
	var path := DIR.path_join(relative)
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	if res is AudioStreamMP3 and looping:
		# Mutating the cached resource is fine: a loop id only ever wants to loop,
		# and the MP3 import already owns the stream instance.
		(res as AudioStreamMP3).loop = true
	if res is AudioStream:
		return res as AudioStream
	return null
