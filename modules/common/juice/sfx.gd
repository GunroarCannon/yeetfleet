## The game's sound files, exposed as named streams.
##
## One place that knows where the sounds live and what each one is for. [SpaceAudio]
## asks here for the sounds that replace its procedural bank, and [AddonVfx]
## asks here for the one-shots it fires alongside an impact, so the files are
## wired in once rather than path-by-path at every call site.
##
## The old Sci-Fi Sound Library is no longer used (it sounded thin and harsh):
## these are the mixkit set and the loose sounds in [constant DIR]. An id with
## no file here ("warp", "alarm", the engine loops...) returns nothing, and
## [SpaceAudio]'s synth covers that slot.
##
## Streams are loaded once and cached. Every id that names several files
## resolves through [method random_stream] for variation; [method stream]
## returns the first variant for callers that want something deterministic. A
## missing file degrades to null rather than erroring.
##
## Nothing here plays anything: this is a pure library, and the module that
## wants the sound owns the player and the bus.
class_name Sfx
extends RefCounted

const DIR := "res://assets/sounds"
const MIX := "mixit-sounds/"

## id -> file names relative to [constant DIR]. Order matters: variants are
## picked from this list, so the first entry is the "default" sound. Each id is
## one job in the game (the sound list the ids were assigned from is in the
## comments); an id with several files picks one at random every time.
const FILES := {
	# --- Guns ---
	## The everyday laser.
	&"laser": [MIX + "mixkit-laser-weapon-shot-1681.mp3"],
	## A sweeping beam (sustained laser, hyper beam, cryo lance).
	&"laser_sweep": [MIX + "mixkit-long-sweeping-air-swoosh-167.mp3"],
	## The heavier laser (heavy pulse blaster).
	&"laser_power": [MIX + "mixkit-sci-fi-construction-complete-811.ogg"],
	## A very strong, short laser (gamma burst).
	&"laser_strong": ["Laser Gun.mp3"],
	## A small click of a shot (autocannon, flak pellets).
	&"click": [MIX + "mixkit-forceful-impact-item-3174.ogg"],
	## A powerful small shot: the drone moan (gauss slugger).
	&"drone_shot": [MIX + "mixkit-sci-fi-plasma-gun-power-1680.mp3"],
	## Very strong gun shots, one of the two at random (railgun, torpedo, plasma).
	&"gun_heavy": [MIX + "mixkit-gun-explosion-with-long-echo-1700.mp3"],
	&"fire_shot": [MIX + "mixkit-fire-spell-with-explosion-1338.mp3"],
	# Old ids the flight bank still asks for, pointed at the jobs above.
	&"kinetic": [MIX + "mixkit-forceful-impact-item-3174.ogg"],
	&"railgun": [MIX + "mixkit-gun-explosion-with-long-echo-1700.mp3", MIX + "mixkit-sci-fi-plasma-gun-power-1680.mp3"],
	&"plasma": [MIX + "mixkit-fire-spell-with-explosion-1338.mp3"],
	&"missile": [MIX + "mixkit-long-sweeping-air-swoosh-167.mp3"],
	# --- Hits ---
	## A shot landing on a hull.
	&"hit": [MIX + "mixkit-break-tech-impact-2952.ogg"],
	## A hull knocked by (or into) a big ship, nothing destroyed.
	&"impact": ["Impact_1.ogg"],
	# --- Explosions, smallest to biggest ---
	&"explosion_small": ["Scifi Explosion.mp3"],
	&"explosion": [MIX + "mixkit-fuel-explosion-1705.ogg"],
	&"shatter": [MIX + "mixkit-shatter-shot-explosion-1693.mp3"],
	&"shatter_big": [MIX + "mixkit-car-explosion-debris-1562.ogg"],
	&"explosion_big": [MIX + "mixkit-distant-thunder-explosion-1278.mp3"],
	## A planet or other rocky body going up.
	&"explosion_planet": [MIX + "mixkit-explosion-with-rocks-debris-1703.mp3"],
	## What a big blast sounds like from far away.
	&"explosion_far": [MIX + "mixkit-distant-explosion-1690.ogg"],
	&"explosion_heavy": [MIX + "mixkit-distant-thunder-explosion-1278.mp3"],
	# --- Ships going by ---
	## A ship zipping close past the player.
	&"flyby": [MIX + "mixkit-sci-fi-flyby-wobble-2733.mp3"],
	## A big ship passing close.
	&"big_flyby": [MIX + "mixkit-spaceship-landing-2735.mp3"],
	## A big ship's engines starting (it starts to move).
	&"big_engine": [MIX + "mixkit-industrial-metal-sliding-door-200.ogg"],
	## Now and then, near a megaship.
	&"megaship_near": [MIX + "mixkit-flying-spaceship-slowing-down-2736.mp3"],
	# --- The player's own ship ---
	## Something came off the player's ship.
	&"eject": [MIX + "mixkit-tech-device-glitch-2948.ogg", MIX + "mixkit-robot-glitch-malfunction-1401.ogg"],
	&"low_health": [MIX + "mixkit-synth-mechanical-notification-or-alert-650.ogg"],
	&"power_up": ["Power Up Gained.mp3"],
	# --- Menus and jingles ---
	&"menu_select": [MIX + "mixkit-forceful-impact-item-3174.ogg"],
	&"jingle_win": [MIX + "mixkit-medieval-show-fanfare-announcement-226.ogg"],
	&"jingle_lose": [MIX + "mixkit-sad-game-over-trombone-471.mp3"],
	&"jingle_achievement": [MIX + "mixkit-game-experience-level-increased-2062.mp3"],
	&"robot_activated": [MIX + "mixkit-steam-powered-mech-suit-activate-3165.mp3"],
	&"glitch": [MIX + "mixkit-tech-device-glitch-2948.ogg", MIX + "mixkit-robot-glitch-malfunction-1401.ogg"],
	&"swoosh": [MIX + "mixkit-long-sweeping-air-swoosh-167.mp3"],
	&"landing": [MIX + "mixkit-spaceship-landing-2735.mp3"],
}

## Ids whose streams should loop forever when played.
const LOOPING := []

## Per file (relative to [constant DIR]), the gain in dB that brings it level
## with the rest. Measured with ffmpeg's EBU R128 integrated loudness: the
## everyday laser sits at -22 LUFS, so the guns are pulled toward about -21
## and the fly-bys under that (a ship going past is scenery, not a hit). A
## file that is not listed plays as mastered.
const TRIM_DB := {
	"Laser Gun.mp3": -14.0, # -6 LUFS: the loudest file in the set.
	MIX + "mixkit-sci-fi-construction-complete-811.ogg": -9.0, # -11.9
	MIX + "mixkit-sci-fi-plasma-gun-power-1680.mp3": -10.0, # -11.3
	MIX + "mixkit-gun-explosion-with-long-echo-1700.mp3": -9.0, # -13.2
	MIX + "mixkit-fire-spell-with-explosion-1338.mp3": -10.0, # -11.5
	MIX + "mixkit-forceful-impact-item-3174.ogg": -7.0, # -12.9
	MIX + "mixkit-long-sweeping-air-swoosh-167.mp3": -7.0, # -12.9
	MIX + "mixkit-break-tech-impact-2952.ogg": -4.0, # -14.3
	MIX + "mixkit-sci-fi-flyby-wobble-2733.mp3": -7.0, # -19.4
	MIX + "mixkit-spaceship-landing-2735.mp3": -13.0, # -13.6
	MIX + "mixkit-industrial-metal-sliding-door-200.ogg": -8.0, # -11.5, peaks +3
	MIX + "mixkit-flying-spaceship-slowing-down-2736.mp3": -6.0, # -16.9
}

static var _cache: Dictionary = {}
## Loaded stream -> its [constant TRIM_DB] gain.
static var _trims: Dictionary = {}


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


## The gain, dB, that levels [param s] with the rest of the library (see
## [constant TRIM_DB]); 0 for a stream that is not one of the library's.
static func trim_db(s: AudioStream) -> float:
	return float(_trims.get(s, 0.0)) if s != null else 0.0


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
		_trims[res] = float(TRIM_DB.get(relative, 0.0))
		return res as AudioStream
	return null
