## GameAudio: the game's music and its non-positional sounds (menu taps,
## jingles, coins, power-ups), plus the two buses the settings screen turns:
## [b]Music[/b] and [b]SFX[/b]. Everything else that makes a noise (the
## flight module's [SpaceAudio], [AddonVfx]'s pool) routes into SFX too, so
## SOUND and MUSIC in settings are independent.
##
## A static façade: the first call parks one host node under the tree root,
## so music keeps playing across scene changes (menu → loading → flight).
## Two players crossfade when the playlist changes.
##
## Playlists are folders under [constant SONGS]: [code]main[/code] for the
## home screen, [code]submenus[/code] for the map and settings,
## [code]gameplay[/code] for flight, plus the loose songs in the root folder
## that [constant EXTRA_TRACKS] hands to a playlist ([code]garage[/code] is
## only such a song). A menu playlist loops its track; gameplay plays a track
## through and moves on to another it has not just played.
##
## A change of song is an equal-power crossfade: the old one eases out while
## the new one, a beat later, eases in, so there is never a hole or a bump.
class_name GameAudio
extends RefCounted

const SONGS := "res://assets/sounds/songs"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
## Seconds the old song takes to fade out, and the new one to fade in, on a
## change; the new one starts [constant FADE_LAG] seconds into the fade-out.
const FADE_OUT := 1.8
const FADE_IN := 2.4
const FADE_LAG := 0.5
## Loose songs in [constant SONGS] and the playlist each belongs to.
const EXTRA_TRACKS := {
	"gameplay": ["mixkit-at-the-barn-789.ogg"],
	"garage": ["mixkit-happy-and-all-that-514.ogg"],
}
## SOUND and MUSIC for a player who has never touched them (0–1).
const DEFAULT_VOLUME := 0.6
## Music sits under the effects: the songs are mastered hot.
const MUSIC_DB := -7.0

## The non-positional one-shots: id → files (a random one plays).
const UI := {
	## A button pressed: a small click.
	&"tap": ["res://assets/sounds/mixit-sounds/mixkit-forceful-impact-item-3174.ogg"],
	## Some sort of back: either tone.
	&"back": ["res://assets/sounds/Tone1C_MajorTriadUp.ogg", "res://assets/sounds/Tone1D_FourthOctaveDown.ogg"],
	## A submenu opening and closing.
	&"open": ["res://assets/sounds/JDSherbert - Sci Fi UI SFX Pack - Popup Open - 1.mp3"],
	&"close": ["res://assets/sounds/JDSherbert - Sci Fi UI SFX Pack - Popup Close - 1.mp3"],
	## Something that cannot be had yet: the negative box.
	&"locked": ["res://assets/sounds/mixit-sounds/mixkit-open-special-box-3190.mp3"],
	&"coin": ["res://assets/sounds/mixit-sounds/mixkit-game-experience-level-increased-2062.mp3"],
	## A single upgrade pip bought: a small, plain rising chime.
	&"upgrade": ["res://assets/sounds/Tone1C_MajorTriadUp.ogg"],
	## A ship bought.
	&"buy": ["res://assets/sounds/mixit-sounds/mixkit-game-experience-level-increased-2062.mp3"],
	&"win": ["res://assets/sounds/mixit-sounds/mixkit-medieval-show-fanfare-announcement-226.ogg"],
	&"lose": ["res://assets/sounds/mixit-sounds/mixkit-sad-game-over-trombone-471.mp3"],
	&"power_up": ["res://assets/sounds/Power Up Gained.mp3"],
	&"alert": ["res://assets/sounds/mixit-sounds/mixkit-synth-mechanical-notification-or-alert-650.ogg"],
	&"launch": ["res://assets/sounds/mixit-sounds/mixkit-long-sweeping-air-swoosh-167.mp3"],
	&"garage": ["res://assets/sounds/JDSherbert - Sci Fi UI SFX Pack - Popup Open - 1.mp3"],
	## The next ship along in the garage.
	&"ship": ["res://assets/sounds/mixit-sounds/mixkit-steam-powered-mech-suit-activate-3165.mp3"],
}
## Loudness per id, dB, where a file is mastered louder or quieter than the rest.
const UI_DB := {
	&"tap": -10.0, &"back": -6.0, &"open": -4.0, &"close": -4.0, &"coin": -3.0,
	&"launch": -5.0, &"garage": -4.0, &"upgrade": -4.0, &"win": -2.0, &"lose": -2.0, &"ship": -5.0,
}
## Per id, the pitch it plays at (before the jitter): the click is pitched up
## to stay small.
const UI_PITCH := {&"tap": 1.35, &"upgrade": 1.2}
const UI_POOL := 6

static var _host: Node = null
static var _music: Array[AudioStreamPlayer] = []
static var _live := 0
static var _playlist := ""
static var _last_tracks: Array[String] = []
static var _pool: Array[AudioStreamPlayer] = []
static var _pool_i := 0
static var _streams := {}
static var _fade: Tween
## Each music player's fade gain (0–1) and the duck on top of both, dB.
static var _gain: Array[float] = [1.0, 1.0]
static var _duck_db := 0.0

static var current_song: AudioStreamPlayer


# --- Buses ------------------------------------------------------------------------

## Make sure the Music and SFX buses exist (both send to Master).
static func ensure_buses() -> void:
	for b: StringName in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(b) >= 0:
			continue
		var i := AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, b)
		AudioServer.set_bus_send(i, &"Master")


## Push the saved SOUND and MUSIC levels (Session prefs, 0–1) onto the buses.
static func apply_volumes() -> void:
	ensure_buses()
	_set_bus(BUS_SFX, float(Session.pref("master_volume", DEFAULT_VOLUME)))
	_set_bus(BUS_MUSIC, float(Session.pref("music_volume", DEFAULT_VOLUME)))


static func _set_bus(bus: StringName, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	v = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(i, v <= 0.001)


# --- Music ------------------------------------------------------------------------

## Play [param playlist] ("main", "submenus" or "gameplay"). Already playing it:
## nothing changes, so hopping between menu screens never restarts a song.
static func music(playlist: String, callback = null) -> void:
	if playlist == _playlist and _host != null and is_instance_valid(_host):
		return
	_playlist = playlist
	var track := _pick(playlist)
	if track == "":
		return
	if _ensure_host():
		_crossfade(track)
	else:
		# The host joins the tree at the end of this frame: start after it.
		_crossfade.call_deferred(track)
		if callback:
			callback.call_deferred()


## Fade the music out (e.g. under a jingle), and back in with [param back].
static func duck(on: bool) -> void:
	if not _ensure_host():
		return
	var tw := _host.create_tween()
	tw.tween_method(_set_duck, _duck_db, -14.0 if on else 0.0, 0.4)


## Every song in a playlist: the folder's files, plus the root's loose songs
## for the menu screens.
static func tracks(playlist: String) -> Array[String]:
	var out: Array[String] = []
	var dir := SONGS.path_join(playlist)
	var files := DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray()
	for f in files:
		# An exported build lists "<name>.ogg.import" / ".remap".
		var name := f.trim_suffix(".import").trim_suffix(".remap")
		if name.get_extension().to_lower() in ["ogg", "mp3", "wav"] and not (dir.path_join(name) in out):
			out.append(dir.path_join(name))
	for extra: String in EXTRA_TRACKS.get(playlist, []):
		if ResourceLoader.exists(SONGS.path_join(extra)):
			out.append(SONGS.path_join(extra))
	# The looping cut of a song stands in for its full cut on a menu.
	var cut := out.filter(func(p: String) -> bool: return p.get_file().to_lower().contains("_looping"))
	for c: String in cut:
		var base := c.get_file().to_lower().replace("_looping", "").replace("_", " ").get_basename()
		out = out.filter(func(p: String) -> bool:
			return p == c or p.get_file().to_lower().replace("_", " ").get_basename() != base)
	out.sort()
	return out


static func _pick(playlist: String) -> String:
	var all := tracks(playlist)
	if all.is_empty():
		return ""
	var fresh := all.filter(func(p: String) -> bool: return not (p in _last_tracks))
	if fresh.is_empty():
		fresh = all
	var t: String = fresh[randi() % fresh.size()]
	_last_tracks.append(t)
	while _last_tracks.size() > maxi(all.size() - 1, 1):
		_last_tracks.pop_front()
	return t


static func _crossfade(path: String) -> void:
	if not _ensure_host():
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	# Menus loop their song; gameplay moves on to another (see _on_track_done).
	var loop := _playlist != "gameplay"
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop
	var old_i := _live
	var old := _music[old_i]
	_live = 1 - _live
	var new_i := _live
	var nu := _music[new_i]
	if _fade != null and _fade.is_valid():
		_fade.kill()
	nu.stop()
	nu.stream = stream
	_set_gain(new_i, 0.0)
	current_song = nu
	# Equal-power: the old song's gain runs down a cosine while the new one's
	# runs up a sine, so the sum never dips or bumps. The new one starts a
	# beat into the fade-out, from silence, and takes a little longer.
	_fade = _host.create_tween().set_parallel(true)
	if old.playing:
		var from := _gain[old_i]
		_fade.tween_method(func(t: float) -> void: _set_gain(old_i, from * cos(t * PI * 0.5)),
			0.0, 1.0, FADE_OUT)
		_fade.tween_callback(old.stop).set_delay(FADE_OUT)
		_fade.tween_callback(nu.play).set_delay(FADE_LAG)
		_fade.tween_method(func(t: float) -> void: _set_gain(new_i, sin(t * PI * 0.5)),
			0.0, 1.0, FADE_IN).set_delay(FADE_LAG)
	else:
		nu.play()
		_fade.tween_method(func(t: float) -> void: _set_gain(new_i, sin(t * PI * 0.5)),
			0.0, 1.0, FADE_IN)


## Player [param i]'s loudness, 0–1 (the fades), under the music level and
## any duck.
static func _set_gain(i: int, g: float) -> void:
	_gain[i] = clampf(g, 0.0, 1.0)
	_music[i].volume_db = MUSIC_DB + _duck_db + linear_to_db(maxf(_gain[i], 0.0001))


static func _set_duck(db: float) -> void:
	_duck_db = db
	for i in _music.size():
		_set_gain(i, _gain[i])


static func _on_track_done(which: int) -> void:
	if which != _live or _playlist != "gameplay":
		return
	var t := _pick(_playlist)
	if t != "":
		_crossfade(t)


# --- One-shots ---------------------------------------------------------------------

## Play the menu/game one-shot [param id] (see [constant UI]). With
## [param fade_in] seconds it swells in from silence (the win fanfare).
static func ui(id: StringName, pitch_jitter := 0.04, fade_in := 0.0) -> void:
	var files: Array = UI.get(id, [])
	if files.is_empty() or not _ensure_host():
		return
	var stream := _stream(String(files[randi() % files.size()]))
	if stream == null:
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stop()
	p.stream = stream
	var db := float(UI_DB.get(id, 0.0))
	p.volume_db = db
	p.pitch_scale = float(UI_PITCH.get(id, 1.0)) * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()
	if fade_in > 0.0:
		p.volume_db = -40.0
		var swell := _host.create_tween()
		swell.tween_property(p, "volume_db", db, fade_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) as AudioStream if ResourceLoader.exists(path) else null
	return _streams[path]


## True once the host is in the tree and can play. The first call makes it
## (added deferred: the root may be busy adding the main scene), so that one
## returns false.
static func _ensure_host() -> bool:
	if _host != null and is_instance_valid(_host):
		return _host.is_inside_tree()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return false
	ensure_buses()
	_host = Node.new()
	_host.name = "GameAudio"
	# Menu taps and the music carry on while the game is paused.
	_host.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(_host)
	_music.clear()
	_gain = [1.0, 1.0]
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = BUS_MUSIC
		m.volume_db = MUSIC_DB
		m.finished.connect(_on_track_done.bind(i))
		_host.add_child(m)
		_music.append(m)
	_pool.clear()
	for i in UI_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		_host.add_child(p)
		_pool.append(p)
	return false
