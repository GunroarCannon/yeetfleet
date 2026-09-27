## SpaceAudio: 3D Spatial Audio & Dynamic Sound Mixing.
##
## Features:
##   - Dynamic Audio Buses: "Cockpit" (crisp full-range punch) vs "Exterior"
##     (vacuum space sounds muffled through a low-pass filter conducting through the hull).
##   - Procedural 16-bit PCM AudioStreamWAV synthesis for zero-asset retro-scifi SFX.
##   - Fixed Spatial SFX Pooling with AudioStreamPlayer3D, Doppler tracking and pitch variance.
##   - Dynamic Engine Spool tied to throttle, boost, and RCS maneuvers.
class_name SpaceAudio
extends Node

static var _instance: SpaceAudio = null

static func instance() -> SpaceAudio:
	return _instance

# Audio Buses
const BUS_MASTER := &"Master"
const BUS_COCKPIT := &"Cockpit"
const BUS_EXTERIOR := &"Exterior"
const BUS_ENGINES := &"Engines"
const BUS_WEAPONS := &"Weapons"

# SFX Bank. Typed as AudioStream rather than AudioStreamWAV because the bank is
# filled from two sources: the Sci-Fi Sound Library's MP3s where one exists, and
# the procedural synth below where it does not.
var sound_laser: AudioStream
var sound_laser_pulse: AudioStream
var sound_laser_heavy: AudioStream
var sound_autocannon: AudioStream
var sound_gauss: AudioStream
var sound_kinetic: AudioStream
var sound_railgun: AudioStream
var sound_antimatter: AudioStream
var sound_plasma: AudioStream
var sound_plasma_heavy: AudioStream
var sound_gamma: AudioStream
var sound_missile_launch: AudioStream
var sound_missile_heavy: AudioStream
var sound_torpedo: AudioStream
var sound_flak_detonation: AudioStream
var sound_cryo_beam: AudioStream
var sound_solar_flame: AudioStream
var sound_beam_loop: AudioStream
var sound_explosion_small: AudioStream
var sound_explosion_heavy: AudioStream
var sound_singularity_hum: AudioStream
var sound_collision_impact: AudioStream
var sound_shield_hit: AudioStream
var sound_alarm: AudioStream
var sound_engine_loop: AudioStream
var sound_light_switch: AudioStream
var sound_hit: AudioStream
var sound_planet_destruction: AudioStream

# Cockpit & Engine Players (2D non-spatial for pilot)
var _cockpit_player: AudioStreamPlayer
var _engine_player: AudioStreamPlayer
var _alarm_player: AudioStreamPlayer
var _beam_player: AudioStreamPlayer
var _beam_target_vol := -80.0
var _spatial_beam_player: AudioStreamPlayer3D = null

# 3D Spatial Audio Pool
const POOL_SIZE := 16
var _spatial_pool: Array[AudioStreamPlayer3D] = []
var _pool_idx := 0

## Simple leaky-bucket auto-duck for AI weapon fire: every non-player shot adds
## to [member _fire_duck_level] and is itself quieted by the level it just
## raised, then the level drains in [method _process]. A squad all firing at
## once is loud on the first shot and gets progressively quieter within the
## same burst instead of every voice stacking at full volume -- unthrottled,
## the pool has no polyphony limit at all, and a dozen weapons round-robining
## through it at once read as a wall of noise rather than a firefight.
var _fire_duck_level := 0.0
const FIRE_DUCK_PER_SHOT := 1.0
const FIRE_DUCK_MAX_DB := 13.0
const FIRE_DUCK_DECAY := 2.2
## Shooter key -> time (s) its next shot sound may start. See [method
## _shot_sound_due].
var _next_shot_sound := {}

# Engine spool state
var _current_engine_pitch := 0.65
var _current_engine_vol_db := -20.0


func _enter_tree() -> void:
	_instance = self


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _ready() -> void:
	_setup_audio_buses()
	_synthesize_sound_bank()
	_setup_players()


# --- 1. Audio Bus Architecture ---

func _setup_audio_buses() -> void:
	# 1. Cockpit Bus
	var cockpit_idx := AudioServer.get_bus_index(BUS_COCKPIT)
	if cockpit_idx == -1:
		cockpit_idx = AudioServer.bus_count
		AudioServer.add_bus(cockpit_idx)
		AudioServer.set_bus_name(cockpit_idx, BUS_COCKPIT)
		AudioServer.set_bus_send(cockpit_idx, BUS_MASTER)
		AudioServer.set_bus_volume_db(cockpit_idx, 0.0)

	# 2. Exterior Bus (Vacuum sound muffled through hull vibrations)
	var ext_idx := AudioServer.get_bus_index(BUS_EXTERIOR)
	if ext_idx == -1:
		ext_idx = AudioServer.bus_count
		AudioServer.add_bus(ext_idx)
		AudioServer.set_bus_name(ext_idx, BUS_EXTERIOR)
		AudioServer.set_bus_send(ext_idx, BUS_MASTER)
		AudioServer.set_bus_volume_db(ext_idx, -1.5)
		
		# Low-pass filter to emulate vibration transmission through solid hull plates
		var lpf := AudioEffectLowPassFilter.new()
		lpf.cutoff_hz = 950.0
		lpf.resonance = 1.15
		AudioServer.add_bus_effect(ext_idx, lpf)

	# 3. Weapons Sub-bus
	var weap_idx := AudioServer.get_bus_index(BUS_WEAPONS)
	if weap_idx == -1:
		weap_idx = AudioServer.bus_count
		AudioServer.add_bus(weap_idx)
		AudioServer.set_bus_name(weap_idx, BUS_WEAPONS)
		AudioServer.set_bus_send(weap_idx, BUS_COCKPIT)
		AudioServer.set_bus_volume_db(weap_idx, 1.0)

	# 4. Engines Sub-bus
	var eng_idx := AudioServer.get_bus_index(BUS_ENGINES)
	if eng_idx == -1:
		eng_idx = AudioServer.bus_count
		AudioServer.add_bus(eng_idx)
		AudioServer.set_bus_name(eng_idx, BUS_ENGINES)
		AudioServer.set_bus_send(eng_idx, BUS_EXTERIOR)
		AudioServer.set_bus_volume_db(eng_idx, -2.0)


# --- 2. Procedural Sound Bank Synthesis ---

## Fill the bank. The Sci-Fi Sound Library supplies the sounds it has (weapons,
## the engine loop, alarms, UI, the singularity drone); the procedural synth
## fills every slot the library cannot cover — impacts, explosions, collisions —
## and fills all of them when [member FxSettings.library_sounds] is off, which is
## the A/B switch for comparing the two.
func _synthesize_sound_bank() -> void:
	FxSettings.ensure_loaded()
	if FxSettings.library_sounds:
		_load_library_bank()
	# Each slot is guarded rather than overwritten, so a stream the library did
	# supply survives and only the gaps are synthesised.
	if sound_laser == null:
		sound_laser = _synth_laser()
	if sound_laser_pulse == null:
		sound_laser_pulse = _synth_laser_pulse()
	if sound_laser_heavy == null:
		sound_laser_heavy = _synth_laser_heavy()
	if sound_autocannon == null:
		sound_autocannon = _synth_autocannon()
	if sound_gauss == null:
		sound_gauss = _synth_gauss()
	if sound_antimatter == null:
		sound_antimatter = _synth_antimatter()
	if sound_kinetic == null:
		sound_kinetic = _synth_kinetic()
	if sound_railgun == null:
		sound_railgun = _synth_railgun()
	if sound_plasma == null:
		sound_plasma = _synth_plasma()
	if sound_plasma_heavy == null:
		sound_plasma_heavy = _synth_plasma()
	if sound_gamma == null:
		sound_gamma = _synth_laser_heavy()
	if sound_missile_launch == null:
		sound_missile_launch = _synth_missile_launch()
	if sound_missile_heavy == null:
		sound_missile_heavy = _synth_missile_launch()
	if sound_torpedo == null:
		sound_torpedo = _synth_explosion(true)
	if sound_flak_detonation == null:
		sound_flak_detonation = _synth_flak()
	if sound_cryo_beam == null:
		sound_cryo_beam = _synth_cryo()
	if sound_solar_flame == null:
		sound_solar_flame = _synth_solar_flame()
	if sound_beam_loop == null:
		sound_beam_loop = _synth_beam_loop()
	if sound_explosion_small == null:
		sound_explosion_small = _synth_explosion(false)
	if sound_explosion_heavy == null:
		sound_explosion_heavy = _synth_explosion(true)
	if sound_singularity_hum == null:
		sound_singularity_hum = _synth_singularity_hum()
	if sound_collision_impact == null:
		sound_collision_impact = _synth_collision()
	if sound_shield_hit == null:
		sound_shield_hit = _synth_shield_hit()
	if sound_alarm == null:
		sound_alarm = _synth_alarm()
	if sound_engine_loop == null:
		sound_engine_loop = _synth_engine_loop()
	if sound_light_switch == null:
		sound_light_switch = _synth_light_switch()
	if sound_hit == null:
		sound_hit = _synth_kinetic()
	if sound_planet_destruction == null:
		sound_planet_destruction = _synth_planet_cataclysm()


## Pull every stream the Sci-Fi Sound Library can supply. Slots with no library
## equivalent are left null for [method _synthesize_sound_bank] to fill.
func _load_library_bank() -> void:
	sound_laser = Sfx.stream(&"laser")
	sound_kinetic = Sfx.stream(&"kinetic")
	sound_railgun = Sfx.stream(&"railgun")
	sound_plasma = Sfx.stream(&"plasma")
	sound_missile_launch = Sfx.stream(&"missile")
	sound_singularity_hum = Sfx.stream(&"ambience_blackhole")
	sound_alarm = Sfx.stream(&"alarm")
	sound_engine_loop = Sfx.stream(&"engine_loop_small")
	sound_light_switch = Sfx.stream(&"menu_select")
	sound_hit = Sfx.stream(&"hit")
	sound_beam_loop = Sfx.stream(&"warp")
	var lasers := Sfx.streams(&"laser")
	if lasers.size() > 4:
		sound_laser_pulse = lasers[0]
		sound_laser_heavy = lasers[3]
	var kinetics := Sfx.streams(&"kinetic")
	if not kinetics.is_empty():
		sound_autocannon = kinetics[0]
	var railguns := Sfx.streams(&"railgun")
	if railguns.size() > 1:
		sound_gauss = railguns[0]
		sound_antimatter = railguns[1]
	# No library sounds exist for these yet, so leave them for the synth.
	# (Kept explicit so the next pass at the library has an obvious place to land.)
	sound_flak_detonation = null
	sound_cryo_beam = null
	sound_solar_flame = null
	sound_explosion_small = null
	sound_explosion_heavy = null
	sound_collision_impact = null
	sound_shield_hit = null


## Re-pick the whole bank and re-point the running engine loop at whatever the
## new bank chose. Called when the library-sounds toggle flips, so the switch is
## audible immediately rather than at the next scene load.
func refresh_bank() -> void:
	_synthesize_sound_bank()
	if _engine_player != null:
		_engine_player.stream = sound_engine_loop
		if _engine_player.playing:
			_engine_player.play()


func _synth_laser() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.16
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var f := lerpf(1200.0, 180.0, pow(t / dur, 0.4))
		var env := exp(-t * 18.0)
		var sample := (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * env
		buf.encode_s16(i * 2, clampi(int(sample * 30000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


## Softened per playtest feedback: with the player holding the trigger down
## almost constantly, the old 1800 Hz ceiling and a full-weight second
## harmonic made this the one gun that turned into a piercing, unvarying
## whine over a long fight. Lower ceiling, a lighter harmonic, and a one-pole
## smoothing pass ([method _soften_highs]) take the edge off; per-shot pitch/
## volume jitter (so repeats don't sound identical) lives in the caller,
## [method play_weapon_fire].
func _synth_laser_pulse() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.11
	var frames := int(rate * dur)
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for i in frames:
		var t := float(i) / float(rate)
		var f := lerpf(1300.0, 260.0, pow(t / dur, 0.35))
		var env := exp(-t * 26.0)
		samples[i] = (sin(TAU * f * t) + 0.15 * sin(TAU * f * 2.0 * t)) * env
	_soften_highs(samples, 0.55)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		buf.encode_s16(i * 2, clampi(int(samples[i] * 31000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


## One-pole low-pass smoothing over a synthesized sample buffer, in place.
## [param alpha] 0..1: how much of each output sample is the raw input versus
## the carried-over previous output — lower keeps more top end, higher smooths
## harder. A cheap way to soften a procedural tone's brightness without
## reshaping its envelope or frequency sweep.
func _soften_highs(samples: PackedFloat32Array, alpha: float) -> void:
	var prev := 0.0
	for i in samples.size():
		prev = lerpf(prev, samples[i], alpha)
		samples[i] = prev


func _synth_laser_heavy() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.22
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var f := lerpf(850.0, 110.0, pow(t / dur, 0.4))
		var env := exp(-t * 12.0)
		var punch := sin(TAU * 120.0 * t) * 0.4
		var sample := ((sin(TAU * f * t) + 0.35 * sin(TAU * f * 1.5 * t)) * env + punch * exp(-t * 30.0))
		buf.encode_s16(i * 2, clampi(int(sample * 31000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_autocannon() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.08
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var env := exp(-t * 38.0)
		var crack := randf_range(-1.0, 1.0) * 0.75
		var mechanical := sin(TAU * 450.0 * t) * 0.5 + sin(TAU * 180.0 * t) * 0.5
		var sample := (crack + mechanical) * env
		buf.encode_s16(i * 2, clampi(int(sample * 32000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_gauss() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.48
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var crack := randf_range(-1.0, 1.0) * exp(-t * 50.0) * 0.95
		var f := lerpf(480.0, 55.0, pow(t / dur, 0.5))
		var bass := sin(TAU * f * t) * exp(-t * 7.5) * 0.8
		var punch := sin(TAU * 85.0 * t) * exp(-t * 14.0) * 0.6
		var sample := crack * 0.5 + bass + punch
		buf.encode_s16(i * 2, clampi(int(sample * 32000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_antimatter() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.70
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var rip := randf_range(-1.0, 1.0) * exp(-t * 35.0) * 0.9
		var sub := sin(TAU * lerpf(240.0, 32.0, pow(t / dur, 0.6)) * t) * exp(-t * 5.0)
		var boom := sin(TAU * 52.0 * t) * exp(-t * 4.0) * 0.8
		var sample := rip * 0.6 + sub * 0.7 + boom * 0.7
		buf.encode_s16(i * 2, clampi(int(sample * 32700.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_cryo() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.35
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var env := exp(-t * 8.0)
		var chime := sin(TAU * 1650.0 * t) * 0.4 + sin(TAU * 2420.0 * t) * 0.3 + sin(TAU * 880.0 * t) * 0.3
		var sample := chime * env
		buf.encode_s16(i * 2, clampi(int(sample * 28000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_solar_flame() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.28
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var roar := (randf_range(-1.0, 1.0) + randf_range(-1.0, 1.0)) * 0.5
		var low := sin(TAU * 140.0 * t) * 0.4
		var env := smoothstep(0.0, 0.04, t) * exp(-t * 5.5)
		var sample := (roar * 0.7 + low) * env
		buf.encode_s16(i * 2, clampi(int(sample * 30000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_beam_loop() -> AudioStreamWAV:
	var rate := 22050
	var dur := 1.0
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var fundamental := sin(TAU * 180.0 * t) * 0.5
		var overtone := sin(TAU * 360.0 * t) * 0.25 + sin(TAU * 720.0 * t) * 0.15
		var buzz := sin(TAU * 55.0 * t) * 0.1
		var sample := fundamental + overtone + buzz
		buf.encode_s16(i * 2, clampi(int(sample * 26000.0), -32768, 32767))
	return _make_wav(buf, rate, true)


func _synth_kinetic() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.12
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var env := exp(-t * 28.0)
		var noise := randf_range(-1.0, 1.0) * 0.7
		var punch := sin(TAU * 140.0 * t) * 0.6
		var sample := (noise + punch) * env
		buf.encode_s16(i * 2, clampi(int(sample * 32000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_railgun() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.55
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var crack := randf_range(-1.0, 1.0) * exp(-t * 40.0) * 0.9
		var f := lerpf(380.0, 45.0, t / dur)
		var bass := sin(TAU * f * t) * exp(-t * 6.5)
		var sample := (crack * 0.6 + bass * 0.7)
		buf.encode_s16(i * 2, clampi(int(sample * 32000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_plasma() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.32
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var mod := sin(TAU * 25.0 * t) * 0.4
		var f := lerpf(300.0, 80.0, t / dur) + mod * 40.0
		var env := exp(-t * 9.0)
		var sample := (sin(TAU * f * t) + randf_range(-0.2, 0.2)) * env
		buf.encode_s16(i * 2, clampi(int(sample * 31000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_missile_launch() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.40
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var env := smoothstep(0.0, 0.05, t) * exp(-t * 4.0)
		var hiss := randf_range(-1.0, 1.0) * 0.6
		var whoosh := sin(TAU * lerpf(120.0, 360.0, t / dur) * t) * 0.5
		var sample := (hiss + whoosh) * env
		buf.encode_s16(i * 2, clampi(int(sample * 28000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_flak() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.65
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var crack := randf_range(-1.0, 1.0) * exp(-t * 45.0) * 0.8
		var rumble_env := smoothstep(0.0, 0.04, t) * exp(-t * 5.0)
		var rumble := (randf_range(-1.0, 1.0) * 0.5 + sin(TAU * 55.0 * t) * 0.5) * rumble_env
		var sample := crack + rumble
		buf.encode_s16(i * 2, clampi(int(sample * 31000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_explosion(heavy: bool) -> AudioStreamWAV:
	var rate := 22050
	var dur := 1.2 if heavy else 0.55
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	var decay := 3.2 if heavy else 7.5
	var f_bass := 45.0 if heavy else 90.0
	for i in frames:
		var t := float(i) / float(rate)
		var env := exp(-t * decay)
		var noise := randf_range(-1.0, 1.0) * 0.6
		var bass := sin(TAU * f_bass * t) * 0.65
		var sub := sin(TAU * (f_bass * 0.5) * t) * 0.4 if heavy else 0.0
		var sample := (noise + bass + sub) * env
		buf.encode_s16(i * 2, clampi(int(sample * 32000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_planet_cataclysm() -> AudioStreamWAV:
	var rate := 22050
	var dur := 4.2
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var env := exp(-t * 0.95)
		# Low sub-bass frequency downward sweep: starts at 72Hz, sweeps down to 26Hz
		var f_sweep := lerpf(72.0, 26.0, clampf(t / 2.8, 0.0, 1.0))
		var sub_bass := sin(TAU * f_sweep * t) * 0.70
		var sub_sub := sin(TAU * (f_sweep * 0.5) * t) * 0.45
		var sub_harm := sin(TAU * (f_sweep * 1.5) * t) * 0.25
		# Tectonic rumble tremolo (low frequency modulation)
		var tremor := 0.75 + 0.25 * sin(TAU * 7.5 * t)
		# Harsh impact crack at the epicentre start (0.0 to 0.4s)
		var crack_env := exp(-t * 7.0) * 0.8
		var crack_noise := randf_range(-1.0, 1.0) * crack_env
		# Roaring rolling debris / mantle explosion noise
		var roar_noise := randf_range(-1.0, 1.0) * (0.35 * exp(-t * 1.4))
		var sample := ((sub_bass + sub_sub + sub_harm) * tremor + crack_noise + roar_noise) * env
		buf.encode_s16(i * 2, clampi(int(sample * 31500.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_singularity_hum() -> AudioStreamWAV:
	var rate := 22050
	var dur := 1.2
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var f1 := 48.0 + sin(TAU * 2.5 * t) * 12.0
		var f2 := 96.0 + cos(TAU * 3.7 * t) * 18.0
		var f3 := 192.0 + sin(TAU * 5.0 * t) * 24.0
		var sample := sin(TAU * f1 * t) * 0.55 + sin(TAU * f2 * t) * 0.3 + sin(TAU * f3 * t) * 0.15
		# Soft window edges for loop
		var edge := smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(dur - 0.05, dur, t))
		buf.encode_s16(i * 2, clampi(int(sample * edge * 28000.0), -32768, 32767))
	var wav := _make_wav(buf, rate, true)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = frames
	return wav


func _synth_collision() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.45
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var env := exp(-t * 9.0)
		var thud := sin(TAU * 70.0 * t) * 0.7
		var ring := sin(TAU * 420.0 * t) * exp(-t * 22.0) * 0.4
		var sample := (thud + ring + randf_range(-0.15, 0.15)) * env
		buf.encode_s16(i * 2, clampi(int(sample * 32000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_shield_hit() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.28
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var f := lerpf(800.0, 240.0, t / dur)
		var env := exp(-t * 14.0)
		var shimmer := sin(TAU * f * t) * 0.7 + sin(TAU * (f * 1.5) * t) * 0.3
		var sample := shimmer * env
		buf.encode_s16(i * 2, clampi(int(sample * 30000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_alarm() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.18
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var f := 980.0 if t < 0.09 else 1320.0
		var env := exp(-fmod(t, 0.09) * 16.0)
		var sample := sin(TAU * f * t) * env
		buf.encode_s16(i * 2, clampi(int(sample * 26000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _synth_engine_loop() -> AudioStreamWAV:
	var rate := 22050
	var dur := 1.0
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var hum := sin(TAU * 65.0 * t) * 0.45 + sin(TAU * 130.0 * t) * 0.25
		var hiss := randf_range(-0.35, 0.35)
		var sample := hum + hiss
		buf.encode_s16(i * 2, clampi(int(sample * 24000.0), -32768, 32767))
	var wav := _make_wav(buf, rate, true)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = frames
	return wav


func _synth_light_switch() -> AudioStreamWAV:
	var rate := 22050
	var dur := 0.05
	var frames := int(rate * dur)
	var buf := PackedByteArray()
	buf.resize(frames * 2)
	for i in frames:
		var t := float(i) / float(rate)
		var env := exp(-t * 90.0)
		var click := sin(TAU * 2400.0 * t) * env
		buf.encode_s16(i * 2, clampi(int(click * 28000.0), -32768, 32767))
	return _make_wav(buf, rate, false)


func _make_wav(data: PackedByteArray, mix_rate: int, looping: bool) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = data
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = data.size() / 2
	return wav


# --- 3. Players & Pooling Setup ---

func _setup_players() -> void:
	# Cockpit 2D audio
	_cockpit_player = AudioStreamPlayer.new()
	_cockpit_player.name = "CockpitAudio"
	_cockpit_player.bus = BUS_COCKPIT
	add_child(_cockpit_player)

	_alarm_player = AudioStreamPlayer.new()
	_alarm_player.name = "AlarmAudio"
	_alarm_player.bus = BUS_COCKPIT
	add_child(_alarm_player)

	# Continuous beam loop player for the active cockpit
	_beam_player = AudioStreamPlayer.new()
	_beam_player.name = "BeamAudio"
	_beam_player.bus = BUS_WEAPONS
	_beam_player.stream = sound_beam_loop
	_beam_player.volume_db = -80.0
	add_child(_beam_player)

	# Engine 2D loop for active pilot
	_engine_player = AudioStreamPlayer.new()
	_engine_player.name = "EngineAudio"
	_engine_player.bus = BUS_ENGINES
	_engine_player.stream = sound_engine_loop
	_engine_player.volume_db = -30.0
	add_child(_engine_player)
	_engine_player.play()

	# Spatial 3D Pool
	_spatial_pool.clear()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.name = "SpatialSFX_%d" % i
		p.bus = BUS_EXTERIOR
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		p.unit_size = 18.0
		p.max_distance = 3200.0
		p.max_db = 6.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		add_child(p)
		_spatial_pool.append(p)


# --- 4. Spatial Playback Methods ---

func play_spatial(
	stream: AudioStream,
	pos: Vector3,
	unit_size: float = 18.0,
	max_distance: float = 3200.0,
	pitch_range: float = 0.12,
	bus: StringName = BUS_EXTERIOR
) -> AudioStreamPlayer3D:
	if stream == null or _spatial_pool.is_empty():
		return null
	var player := _spatial_pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _spatial_pool.size()

	player.stop()
	player.bus = bus
	player.global_position = pos
	player.unit_size = unit_size
	player.max_distance = max_distance
	player.pitch_scale = randf_range(1.0 - pitch_range, 1.0 + pitch_range)
	player.stream = stream
	player.play()
	return player


## Play a weapon shot sound, selecting a unique voice by weapon id or category.
## [param shooter_id] identifies the firing ship (any stable id, e.g. its
## instance id) for the shot-sound interval — see [method _shot_sound_due].
## [param gap_mult] and [param pitch_mult] come from the shooter's firing
## style (see [AiFirePatterns]): a stream spaces its sounds further apart, an
## orb-lobber sounds lower, so a crowded fight is a mix of voices and rhythms.
func play_weapon_fire(
	w_type: String, pos: Vector3, is_player: bool = false, w_id: String = "",
	shooter_id: int = 0, gap_mult: float = 1.0, pitch_mult: float = 1.0
) -> void:
	var stream: AudioStream = sound_laser
	var p_scale := randf_range(0.96, 1.04)

	match w_id:
		"pulse_laser":
			stream = sound_laser_pulse if sound_laser_pulse != null else sound_laser
			# Wider and lower-centred than the old 1.08-1.16: that band was narrow
			# enough that sustained fire sounded like the same sample replayed,
			# and skewed high enough to read as shrill on top of it.
			p_scale = randf_range(0.92, 1.10)
		"heavy_pulse_blaster":
			stream = sound_laser_heavy if sound_laser_heavy != null else sound_laser
			p_scale = randf_range(0.84, 0.90)
		"twin_autocannon":
			stream = sound_autocannon if sound_autocannon != null else sound_kinetic
			p_scale = randf_range(0.98, 1.12)
		"gauss_slugger":
			stream = sound_gauss if sound_gauss != null else sound_railgun
			p_scale = randf_range(0.92, 1.02)
		"plasma_annihilator":
			stream = sound_plasma_heavy if sound_plasma_heavy != null else sound_plasma
			p_scale = randf_range(0.88, 0.98)
		"gamma_burst":
			stream = sound_gamma if sound_gamma != null else sound_laser_heavy
			p_scale = randf_range(1.20, 1.32)
		"antimatter_railgun":
			stream = sound_antimatter if sound_antimatter != null else sound_railgun
			p_scale = randf_range(0.80, 0.88)
		"seeker_missiles":
			stream = sound_missile_launch
			p_scale = randf_range(1.10, 1.22)
		"hellfire_missiles":
			stream = sound_missile_heavy if sound_missile_heavy != null else sound_missile_launch
			p_scale = randf_range(0.82, 0.90)
		"nova_torpedo":
			stream = sound_torpedo if sound_torpedo != null else sound_missile_launch
			p_scale = randf_range(0.60, 0.72)
		"flak_scatter":
			stream = sound_flak_detonation
			p_scale = randf_range(1.04, 1.15)
		"cryo_lance":
			stream = sound_cryo_beam if sound_cryo_beam != null else sound_laser
			p_scale = randf_range(1.18, 1.26)
		"solar_flamer":
			stream = sound_solar_flame if sound_solar_flame != null else sound_plasma
			p_scale = randf_range(0.92, 1.02)
		_:
			match w_type:
				"kinetic": stream = sound_kinetic
				"railgun": stream = sound_railgun
				"plasma": stream = sound_plasma
				"missile": stream = sound_missile_launch
				"singularity": stream = sound_singularity_hum
				"flak": stream = sound_flak_detonation
				_: stream = sound_laser

	# Loudness jitter on top of the per-weapon pitch range above, so repeated
	# shots from the same gun don't sound like the exact same sample played
	# back-to-back. Widened from the original (-2.5, 1.0) — that range was
	# barely audible shot-to-shot on a weapon fired near-continuously.
	var v_jitter := randf_range(-4.0, 1.5)

	p_scale *= pitch_mult
	var key := shooter_id if shooter_id != 0 else (-1 if is_player else hash(w_type + w_id))
	if not _shot_sound_due(key, stream, p_scale, gap_mult):
		return

	if is_player:
		_cockpit_player.stream = stream
		_cockpit_player.pitch_scale = p_scale
		_cockpit_player.volume_db = v_jitter
		_cockpit_player.bus = BUS_WEAPONS
		_cockpit_player.play()
	else:
		var duck_db := minf(_fire_duck_level * 2.0, FIRE_DUCK_MAX_DB)
		var p := play_spatial(stream, pos, 24.0, 2600.0, 0.12, BUS_EXTERIOR)
		if p != null:
			p.pitch_scale = p_scale
			p.volume_db += v_jitter - duck_db
		_fire_duck_level += FIRE_DUCK_PER_SHOT


## Shot-sound interval ([member JuiceSettings.shot_sound_interval]): while a
## gun keeps firing, its sound plays at its own rhythm instead of once per
## shot. The next one is due [member JuiceSettings.shot_sound_interval_pct]
## percent of this sound's (pitch-adjusted) length after it starts: 100% is
## back to back, never overlapping. 0% or below, or the setting off, plays
## every shot as before.
func _shot_sound_due(key: int, stream: AudioStream, pitch: float, gap_mult := 1.0) -> bool:
	var pct := JuiceSettings.shot_sound_interval_pct
	if not JuiceSettings.shot_sound_interval or pct <= 0.0 or stream == null:
		return true
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(_next_shot_sound.get(key, 0.0)):
		return false
	var length := stream.get_length() / maxf(pitch, 0.01)
	_next_shot_sound[key] = now + length * pct / 100.0 * gap_mult
	if _next_shot_sound.size() > 128:
		for k: int in _next_shot_sound.keys():
			if float(_next_shot_sound[k]) < now:
				_next_shot_sound.erase(k)
	return true


## Start or sustain a continuous beam audio loop (cockpit for player, spatial for AI).
func start_beam_loop(w_id: String, is_player: bool = false, pos: Vector3 = Vector3.ZERO) -> void:
	if is_player:
		if _beam_player != null:
			var s: AudioStream = sound_beam_loop
			if w_id == "cryo_lance" and sound_cryo_beam != null:
				s = sound_cryo_beam
			elif w_id == "solar_flamer" and sound_solar_flame != null:
				s = sound_solar_flame
			if _beam_player.stream != s:
				_beam_player.stream = s
			_beam_target_vol = -4.0
			_beam_player.pitch_scale = 1.05 if w_id == "cryo_lance" else (0.86 if w_id == "hyper_beam" else 1.0)
			if not _beam_player.playing:
				_beam_player.volume_db = -18.0
				_beam_player.play()
	else:
		if _spatial_beam_player == null or not is_instance_valid(_spatial_beam_player):
			_spatial_beam_player = play_spatial(sound_beam_loop, pos, 24.0, 2800.0, 0.05, BUS_EXTERIOR)
		elif _spatial_beam_player != null:
			_spatial_beam_player.global_position = pos


## Stop or decay continuous beam audio loop.
func stop_beam_loop(_w_id: String = "") -> void:
	_beam_target_vol = -80.0
	if _spatial_beam_player != null and is_instance_valid(_spatial_beam_player):
		_spatial_beam_player.stop()
		_spatial_beam_player = null


func play_explosion(pos: Vector3, heavy: bool = false) -> void:
	var stream := sound_explosion_heavy if heavy else sound_explosion_small
	play_spatial(stream, pos, 38.0 if heavy else 22.0, 4500.0 if heavy else 2800.0, 0.18, BUS_EXTERIOR)


func play_planet_destruction(pos: Vector3) -> void:
	if sound_planet_destruction == null:
		sound_planet_destruction = _synth_planet_cataclysm()
	# 1. 3D spatial cataclysm audible across tens of kilometers
	play_spatial(sound_planet_destruction, pos, 250.0, 45000.0, 0.05, BUS_EXTERIOR)
	# 2. Hull-conducted rumble in cockpit for visceral physical feedback
	if _cockpit_player != null and is_instance_valid(_cockpit_player):
		_cockpit_player.stream = sound_planet_destruction
		_cockpit_player.pitch_scale = randf_range(0.94, 1.04)
		_cockpit_player.volume_db = 2.0
		_cockpit_player.bus = BUS_COCKPIT
		_cockpit_player.play()


func play_flak_detonation(pos: Vector3) -> void:
	play_spatial(sound_flak_detonation, pos, 28.0, 3500.0, 0.15, BUS_EXTERIOR)


func play_singularity_pulse(pos: Vector3) -> void:
	play_spatial(sound_singularity_hum, pos, 35.0, 4000.0, 0.08, BUS_EXTERIOR)


func play_collision_sound(pos: Vector3, impact_speed: float, is_player: bool = false) -> void:
	if is_player:
		_cockpit_player.stream = sound_collision_impact
		_cockpit_player.pitch_scale = clampf(0.8 + impact_speed * 0.005, 0.7, 1.4)
		_cockpit_player.bus = BUS_COCKPIT
		_cockpit_player.play()
	else:
		var p := play_spatial(sound_collision_impact, pos, 26.0, 2500.0, 0.15, BUS_EXTERIOR)
		if p:
			p.pitch_scale = clampf(0.8 + impact_speed * 0.005, 0.7, 1.4)


func play_shield_hit_sound(pos: Vector3, is_player: bool = false) -> void:
	if is_player:
		_cockpit_player.stream = sound_shield_hit
		_cockpit_player.pitch_scale = randf_range(0.95, 1.08)
		_cockpit_player.bus = BUS_COCKPIT
		_cockpit_player.play()
	else:
		play_spatial(sound_shield_hit, pos, 20.0, 2000.0, 0.12, BUS_EXTERIOR)


## A shot landing on a hull, as opposed to a shot leaving one. Distinct from
## [method play_explosion] so a hit can be small, quick and frequent.
func play_hit(pos: Vector3, is_player: bool = false) -> void:
	if is_player:
		var p := play_spatial(sound_hit, pos, 20.0, 1400.0, 0.12, BUS_EXTERIOR)
		if p:
			p.volume_db = -6.0
	else:
		play_spatial(sound_hit, pos, 22.0, 2200.0, 0.14, BUS_EXTERIOR)


## The UI click, from the library's menu-select pair.
func play_ui_select() -> void:
	if sound_light_switch == null:
		return
	_cockpit_player.stream = sound_light_switch
	_cockpit_player.pitch_scale = randf_range(0.98, 1.02)
	_cockpit_player.bus = BUS_COCKPIT
	_cockpit_player.play()


func play_alarm_beep() -> void:
	_alarm_player.stream = sound_alarm
	_alarm_player.play()


func play_light_switch_sound() -> void:
	_cockpit_player.stream = sound_light_switch
	_cockpit_player.bus = BUS_COCKPIT
	_cockpit_player.play()


# --- 5. Dynamic Engine Spool ---

func update_engine_spool(throttle: float, boosting: bool, strafe_speed: float, delta: float) -> void:
	if _engine_player == null:
		return

	# Calculate target pitch and volume
	var t := clampf(absf(throttle), 0.0, 1.0)
	var target_pitch := 0.65 + t * 0.50
	var target_vol_db := -22.0 + t * 16.0

	if boosting and t > 0.05:
		target_pitch += 0.45
		target_vol_db += 4.5

	# Strafe maneuvers add mechanical spool whine
	var s := clampf(strafe_speed / 60.0, 0.0, 1.0)
	target_pitch += s * 0.20
	target_vol_db += s * 2.0

	# Smooth lerp
	_current_engine_pitch = lerpf(_current_engine_pitch, target_pitch, clampf(delta * 4.5, 0.0, 1.0))
	_current_engine_vol_db = lerpf(_current_engine_vol_db, target_vol_db, clampf(delta * 4.0, 0.0, 1.0))

	_engine_player.pitch_scale = _current_engine_pitch
	_engine_player.volume_db = _current_engine_vol_db


func _process(delta: float) -> void:
	if _beam_player != null and _beam_player.playing:
		_beam_player.volume_db = move_toward(_beam_player.volume_db, _beam_target_vol, delta * 85.0)
		if _beam_target_vol <= -70.0 and _beam_player.volume_db <= -70.0:
			_beam_player.stop()
	_fire_duck_level = maxf(_fire_duck_level - FIRE_DUCK_DECAY * delta, 0.0)
