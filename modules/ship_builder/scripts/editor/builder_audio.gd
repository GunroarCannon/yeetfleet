## Tiny UI feedback SFX for the ship builder editor: a click for a plain notice,
## a confirming chime for a "good" one, a buzz for an "error" one.
##
## Deliberately not [SpaceAudio]'s scale: no buses per weapon type, no 3D pool —
## the builder is a 2D-UI-over-a-3D-viewport editor, not a cockpit, so every
## sound here is a plain non-spatial [AudioStreamPlayer]. Same "zero-asset
## procedural WAV" convention as [SpaceAudio] though, so the builder never ships
## silent while waiting on real asset drops.
##
## Wired by [BuilderRoot] to its own [signal BuilderRoot.notice] (one connection
## covers every place/remove/swap/save/load/error in the editor). Anything that
## wants its own distinct cue — a button press, a drag pick-up — can call
## [method play_click] directly; that seam is what a future sound-authoring
## pass (browsing/previewing/assigning clips per event) would plug into instead
## of these three procedural synths.
class_name BuilderAudio
extends Node

static var _instance: BuilderAudio = null

static func instance() -> BuilderAudio:
	return _instance

const BUS_EDITOR := &"Editor"

var _sound_click: AudioStreamWAV
var _sound_good: AudioStreamWAV
var _sound_error: AudioStreamWAV

const POOL_SIZE := 4
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx := 0


func _enter_tree() -> void:
	_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ready() -> void:
	_setup_bus()
	_sound_click = _synth_click()
	_sound_good = _synth_good()
	_sound_error = _synth_error()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "BuilderSfx_%d" % i
		p.bus = BUS_EDITOR
		add_child(p)
		_pool.append(p)


func _setup_bus() -> void:
	var idx := AudioServer.get_bus_index(BUS_EDITOR)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, BUS_EDITOR)
		AudioServer.set_bus_send(idx, &"Master")
		AudioServer.set_bus_volume_db(idx, -4.0)


## Play the cue that matches a [signal BuilderRoot.notice] kind ("good",
## "error", or anything else for a plain click).
func play_for_kind(kind: String) -> void:
	match kind:
		"good": play_good()
		"error": play_error()
		_: play_click()


func play_click() -> void:
	_play(_sound_click, 1.0)


func play_good() -> void:
	_play(_sound_good, 0.0)


func play_error() -> void:
	_play(_sound_error, -2.0)


func _play(stream: AudioStreamWAV, volume_db: float) -> void:
	if stream == null or _pool.is_empty():
		return
	var p := _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()
	p.stop()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.97, 1.03)
	p.play()


func _synth_click() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.045
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var env := exp(-t * 70.0)
		var tick := sin(TAU * 1400.0 * t) * env
		buf.encode_s16(i * 2, clampi(int(tick * 22000.0), -32768, 32767))
	return _make_wav(buf, rate)


func _synth_good() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.14
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		# A short two-note upward chirp reads as "accepted" without a real asset.
		var f := lerpf(660.0, 990.0, clampf(t / dur, 0.0, 1.0))
		var env := exp(-t * 10.0)
		var sample := (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * env
		buf.encode_s16(i * 2, clampi(int(sample * 26000.0), -32768, 32767))
	return _make_wav(buf, rate)


func _synth_error() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.16
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		# The mirror of the "good" chirp: a short downward buzz.
		var f := lerpf(320.0, 160.0, clampf(t / dur, 0.0, 1.0))
		var env := exp(-t * 9.0)
		var buzz := sin(TAU * f * t) + 0.5 * sin(TAU * f * 1.9 * t)
		var sample := buzz * env
		buf.encode_s16(i * 2, clampi(int(sample * 27000.0), -32768, 32767))
	return _make_wav(buf, rate)


func _make_wav(data: PackedByteArray, mix_rate: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	return wav
