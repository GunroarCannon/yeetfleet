## Juice's two accessibility/taste knobs, persisted independently of any design.
##
## Kept apart from [Juice] itself so the load/save path can be exercised without
## a scene tree, and so a future settings screen has one small surface to bind
## to instead of reaching into the runtime.
class_name JuiceSettings
extends RefCounted

const SETTINGS_PATH := "user://juice.cfg"
const SECTION := "juice"

const INTENSITY_MIN := 0.0
const INTENSITY_MAX := 1.5
const INTENSITY_DEFAULT := 1.0

static var intensity := INTENSITY_DEFAULT
## When true, every entry point in [Juice] that produces motion — shake, hitstop,
## streaks, speed lines — is short-circuited to nothing. Colour and scale cues
## stay, because those carry information reduce_motion is not meant to hide.
static var reduce_motion := false

## Individually toggleable combat "juice" effects — one bool each rather than
## a single level, so a taste/perf pass can turn any one off without losing
## the rest. Each still scales with [member intensity] and respects [member
## reduce_motion] like everything else in [Juice]; the bool is a hard on/off
## on top of that. See combat_settings_modal.gd's "Juice & Feel" section.
static var near_miss_slowmo := true
static var kill_freeze_frame := true
static var hit_squash_stretch := true
static var hit_knockback := true
static var enemy_death_random_explosion := true
static var hit_screen_shake := true
static var collision_bump_zoom := true
## Once an AI has spotted the player, bias its steering toward staying ahead
## of the player instead of always closing straight in -- see
## [method AiBehaviour._steer_toward]. Playtest ask: enemies were hard to find.
static var ai_flank_enabled := true
## Popcorn enemies: weak archetypes flagged [code]popcorn[/code] in
## [AiFactions] get a low flat HP and break apart on any ramming hit.
static var popcorn_enemies_enabled := true
## Crosshair magnetism toward the predictive lead-reticle point -- see
## [TargetLeadReticle]. Not hit-forgiveness: an input-side nudge only.
static var aim_assist_enabled := true

## Multiplier on top of [AiBehaviour]'s own base flank chances (85% while
## pursuing/engaging, 20% while fleeing). 0 turns the behaviour off without
## flipping [member ai_flank_enabled] (kept separate so a settings slider and
## the on/off checkbox don't fight over the same field).
static var ai_flank_chance_mult := 1.0
## Strength of the aim-assist nudge, 0 (no pull) to 1 (snaps hard) -- see
## [TargetLeadReticle].
static var aim_assist_strength := 0.5
## Multiplier on ramming damage, on top of [FlightModel]'s own tuned
## coefficients -- the "manage it from the flight test" dial for the ramming
## rebalance.
static var ram_damage_mult := 1.0
## Global multiplier on hull HP (both the player's and every AI's) -- lower
## means faster kills across the board. See [method FlightModel._durability].
static var hull_hp_mult := 0.65
## The player's own extra durability, on top of [member hull_hp_mult] --
## replaces the old hardcoded ×2.5 in [method FlightModel._durability].
static var player_durability_mult := 1.8

# --- Camera dynamic zoom (see [member FlightCamera._zoom]) ---
## How far a full-strength hit pulls the camera out, as extra chase distance
## (0.6 = 60% further back). Planet/station crashes multiply this.
static var cam_zoom_amount := 0.7
## Seconds to ease out to the zoomed position (smaller = snappier).
static var cam_zoom_out_time := 0.3
## Seconds to hold out there after the last hit before easing back.
static var cam_zoom_hold := 0.5
## Seconds to ease back in to the normal framing.
static var cam_zoom_return_time := 1.4

# --- Chase camera feel (see [method FlightCamera._update_chase]) ---
## How fast the chase frame turns after the hull, per second. Lower = the ship
## visibly swings inside the frame through a turn and small wobbles in the
## hull's heading are filtered out instead of shaking the whole view.
static var cam_follow_rate := 9.0
## How fast the camera's position settles behind the hull, per second.
static var cam_position_smooth := 5.0
## How fast the camera's aim settles, per second.
static var cam_aim_smooth := 9.0
## How far the view looks into a turn: 0 aims along the smoothed frame, 1 aims
## where the nose actually points.
static var cam_turn_lead := 0.6
## Extra degrees of FOV at top speed: the "going fast" stretch.
static var cam_speed_fov := 9.0
## Multiplier on the chase view's roll into a turn.
static var cam_bank_mult := 1.0
## How far the camera swings to the outside of a turn, × hull radius.
static var cam_turn_swing := 0.35

# --- Combat feel ---
## In flight, every ship's capacitor recharges at least fast enough to keep
## this fraction of its active weapon firing flat out (0 = the design's real
## power budget only, as in the builder). Many designs and most AI hulls run
## a power deficit, which meant a few seconds of fire and then nothing.
static var weapon_sustain := 0.9
## How hard explosion shockwaves shove the player's ship (1 = as hard as an
## AI ship). Full strength flung the player hundreds of metres.
static var player_blast_push := 0.2
## How much a shockwave spins the player and locks out control (1 = full).
static var player_blast_spin := 0.25
## Per-shot recoil on the player's ship (1 = the weapon's full recoil). With
## a dozen muzzles, full recoil braked the ship every time it fired.
static var player_recoil := 0.1

# --- Hit effects ---
## Size of the hit sparks / explosions spawned on the player's own hull (0
## turns them off). They sit right in front of the chase camera, so full
## size could white out the whole screen.
static var hit_vfx_scale := 0.5
## Strength of the shield "forcefield" flash on each shield hit (0 = off,
## which also saves the effect's CPU/GPU cost). Also rate-limits how often it
## can respawn.
static var shield_fx_intensity := 0.35
## Multiplier on how hard a weapon hit knocks a ship off its line.
static var hit_knockback_strength := 0.5
## Multiplier on the screen shake from taking a hit. The shake mostly rotates
## the view, and in a chase camera that swings the ship sideways on screen,
## so full strength reads as the ship jumping rather than the camera reacting.
static var hit_shake_strength := 0.5
## Size of the reaction emotes that pop off ships (0 turns them off).
static var emote_size := 1.0

# --- Weapon sound pacing (see [method SpaceAudio.play_weapon_fire]) ---
## When on, a gun's sound plays at its own rhythm while it fires instead of
## once per shot, so the sounds never pile up on top of each other.
static var shot_sound_interval := true
## Gap between one shot sound starting and the next, as a percentage of the
## sound's own length: 100 = the next starts as the last ends, 50 = half
## overlap, 200 = a sound-length gap. 0 or below plays every shot (the old
## behaviour).
static var shot_sound_interval_pct := 100.0

# --- AI pacing ---
## Enemies attack in bursts with rests between, and only
## [member ai_max_attackers] may shoot at the player at once. The rest wait
## their turn instead of all bombarding together.
static var ai_attack_pacing := true
static var ai_max_attackers := 2.0
## Multiplier on the rest between an enemy's bursts (higher = calmer fights).
static var ai_rest_mult := 1.0
## A flanker that has got in front of the player matches the player's speed,
## backing off (even in reverse) to stay in view instead of being overrun or
## pulling away.
static var ai_speed_match := true

# --- Emotes ---
## Reaction emotes off the player's own ship / off enemy ships. Each side has
## its own on/off and its own chance per trigger (1 = every time).
static var player_emotes := true
static var enemy_emotes := true
static var player_emote_chance := 1.0
static var enemy_emote_chance := 0.6

# --- Kill explosions ---
## Chance (0..1) of the bigger secondary blast when a ship dies. Gated by
## [member enemy_death_random_explosion]; replaces the old hardcoded 33%.
static var kill_explosion_chance := 0.33
## Size multiplier on every ship-death explosion.
static var kill_explosion_size := 1.0
## Multipliers on the screen shake / flash a kill produces.
static var kill_shake := 1.0
static var kill_flash := 1.0

# --- Freeze frames (see [method Juice.freeze]) ---
## A real freeze: time all but stops for a few real milliseconds. Each event
## has its own switch and length; [member kill_freeze_frame] is the master.
static var freeze_on_player_hit := true
static var freeze_on_enemy_hit := false
static var freeze_on_kill := true
static var freeze_hit_ms := 70.0
## A hit on the player only freezes when it takes at least this fraction of
## max hull (0 = every hit; a volley is rate-limited either way).
static var freeze_hit_threshold := 0.06
static var freeze_enemy_hit_ms := 35.0
static var freeze_kill_ms := 120.0
## How deep the freeze goes: 1 = a dead stop, 0.5 = half speed.
static var freeze_depth := 0.97

# --- Kill cam ---
## When the player destroys a ship: the game pauses (the camera does not),
## the camera swoops in on the wreck, holds, then returns and play resumes.
static var kill_cam := true
static var kill_cam_chance := 1.0
## Real seconds held on the wreck, after the swoop in.
static var kill_cam_hold := 1.0
## Real seconds for the swoop in, and again for the swoop back.
static var kill_cam_blend := 0.35
## Game speed during the kill cam (0 = fully paused, 1 = no slow-down).
static var kill_cam_time_scale := 0.04
## Kill cam: the swoop *in* takes this × the swoop time — a little slower
## than the swoop out, so the eye can follow onto the wreck.
static var kill_cam_ease_in := 1.4
## Camera distance from the wreck, in the wreck's hull radii.
static var kill_cam_distance := 3.0
## Real seconds after one kill cam before another may start.
static var kill_cam_cooldown := 4.0

# --- Hit feel ---
## Knockback moves the drawn hull and springs it back, instead of changing
## the ship's velocity. The velocity kick was fought straight back by the
## flight assist, which read as the ship jumping back and snapping home.
static var knockback_visual := true
## Seconds for a visual knockback to spring back home.
static var knockback_return_time := 0.3
## Multiplier on squash & stretch depth (hits and collisions).
static var squash_strength := 1.0

# --- Player & enemy stats (flight-test debugger, see CombatStatsPanel) ---
static var player_invulnerable := false
static var player_damage_taken_mult := 1.0
static var player_damage_dealt_mult := 1.0
static var player_shield_mult := 1.0
## Regeneration, in percent of max per second. The shield waits
## [member player_shield_regen_delay] seconds after a hit before refilling.
static var player_hp_regen := 0.0
static var player_shield_regen := 0.0
static var player_shield_regen_delay := 2.0
static var enemies_passive := false
static var one_hit_kills := false
static var enemy_hp_mult := 1.0
static var enemy_damage_mult := 1.0
static var enemy_fire_rate_mult := 1.0
## Chance (0..1) each enemy shot actually lands.
static var enemy_accuracy := 1.0

# --- Enemy fire patterns (see [AiFirePatterns]) ---
## Each enemy rolls a bullet-hell firing style — streams, bursts, slow fans,
## big slow orbs, spirals, sniper shots — instead of every gun firing at its
## weapon's flat rate. Off = the old uniform cadence.
static var ai_fire_patterns := true
## How far apart the rolled cadences land: 0 = every ship fires at its
## weapon's own rhythm, 1 = the full spread, 2 = extreme.
static var ai_fire_variety := 1.0
## Enemy shots are real projectiles that hit the player only if they touch
## the hull, so slow shots can be dodged. Off = the old dice roll per volley.
static var ai_real_projectiles := true
## Damage a real enemy projectile deals the player, as a fraction of its
## weapon's own per-shot damage (the player's guns deal the full amount).
static var enemy_shot_damage_scale := 0.22

# --- Player-favouring cheats ---
## A ship the player cannot see may fire at them only [member
## offscreen_shots] times per [member offscreen_window] seconds — and that
## clock only runs while the ship is out of view (see [method
## AiShip.fire_gate]). Ships fighting each other are not limited.
static var cheat_offscreen_mercy := true
static var offscreen_shots := 2.0
static var offscreen_window := 30.0
## A ship the player has tangled with and is chasing is carried along at the
## player's speed (without turning to it), so it stays ahead instead of being
## overrun. Only inside [member chase_assist_range] metres.
static var cheat_chase_assist := true
static var chase_assist_range := 450.0
## How much of the player's speed is lent: 1 = all of it.
static var chase_assist_strength := 0.9

# --- Movement profiles (swipe / slingshot) ---
## Slingshot: a tap while flying fires toward the tapped point.
static var sling_tap_fire := true
## Slingshot: touching the ship while it flies catches it for the next launch.
static var sling_catch := true
## Slingshot: the hull flies nose-first and rolls (a rocket) instead of tumbling.
static var sling_rocket_spin := false
## AI ships (a share of them, [member ai_sling_share]) fight by slingshot launches, whatever profile the player flies.
static var ai_slingshot := false
## Swipe: the speed a dash settles to, × top speed.
static var swipe_cruise := 0.45
## Swipe: the fastest dash (a long, quick swipe), × top speed.
static var swipe_dash := 1.6
## Swipe: how fast the flight path swings to a new heading, rad/s.
static var swipe_turn_rate := 5.0
## Swipe: how fast a dash bleeds off toward the cruise speed, per second.
static var swipe_drag := 1.2
## Swipe: the whole profile's speed, × the hull's.
static var swipe_speed_mult := 1.25
## Swipe: course correction looks for a target this far either side of the swipe.
static var swipe_assist_cone_deg := 40.0
## Swipe: how far the heading bends onto that target (1 = straight at it).
static var swipe_assist_strength := 0.7
## Swipe/slingshot: ramming damage the player deals, ×.
static var move_ram_dealt := 2.0
## Swipe/slingshot: ramming damage the player takes, ×.
static var move_ram_taken := 0.5
## Swipe/slingshot: the player's hull strength in a ram, ×.
static var move_durability := 1.3
## Slingshot: launch speed at a full pull, × top speed.
static var sling_power := 3.0
## Slingshot: share of the speed kept through each bounce.
static var sling_bounce_keep := 0.85
## Slingshot: how much a bounce turns toward the next body (0 = pure reflection).
static var sling_bounce_seek := 0.55
## Slingshot: a run ends below this speed, × top speed.
static var sling_end_speed := 0.25
## Slingshot: a run ends after this many seconds.
static var sling_max_time := 6.0
## Slingshot: speed lost per second in flight (fraction).
static var sling_drag := 0.25
## Slingshot: how far the camera pulls out at full launch speed.
static var sling_zoom := 1.2
## Slingshot: how hard a launch tumbles the hull, rad/s.
static var sling_spin := 6.0
## Share of AI ships that fight by slingshot when [member ai_slingshot] is on.
static var ai_sling_share := 0.35
## Swipe/slingshot: two fingers pinch to zoom the camera (mouse wheel on PC).
static var cam_pinch_zoom := true
## Swipe/slingshot: two fingers twist or drag together to swing the camera round the ship (right-drag on PC).
static var cam_twist_rotate := true
## Slingshot: the camera follows the flight smoothly instead of turning with the hull's spin.
static var sling_steady_cam := true
## Slingshot: the camera holds still while aiming (no swing behind the ship,
## no look-ahead), so the view never moves the aim under the thumb.
static var sling_aim_cam_hold := true
## Swipe/slingshot: glowing 3D chevron arrows show the heading and the launch.
static var move_arrows := true
## Swipe: only a swipe that starts on the ship moves it; a drag from anywhere else swings the camera round the ship.
static var swipe_from_ship := true
## FPS profile: dragging up looks down (flight-sim style).
static var fps_invert_y := false
## Swipe: how much further out than the normal chase the camera sits, × (0 = normal).
static var swipe_cam_zoom := 0.6
## Swipe/slingshot: how fast the two-finger swing turns the camera, ×.
static var cam_gesture_speed := 1.0
## FPS profile: look sensitivity, ×.
static var fps_look_speed := 1.0
## FPS profile: top speed at a full stick, × the hull's.
static var fps_speed_mult := 1.0
## FPS profile: how quickly the ship reaches the stick's speed, per second.
static var fps_accel := 2.5
## FPS profile: stick push past which the ship boosts (above 1 = never).
static var fps_boost_at := 0.92
## FPS profile: camera distance beyond the normal chase, ×.
static var fps_cam_zoom := 0.2
## The player's shots never fly slower than this (m/s), whatever ship or firing style they fly.
static var player_min_shot_speed := 900.0
## Graffiti targets: a ship that shoots on sight gets its red target the moment it is on screen, attacked or not.
static var markers_show_hostile := true
## Swipe/slingshot: the launch magnet also pulls toward friendly and harmless ships (hostiles still come first).
static var magnet_friendlies := true
## Losing a wing throws the player into an unsteady spiral, like the AI (off: the player just turns slower).
static var player_wing_spiral := false
## Slingshot: how far into the screen a pull back launches (0 = flat on the screen, 1 = straight in; pull sideways to aim left/right).
static var sling_aim_depth := 0.75
## Slingshot: how far the camera looks ahead along the aim and the flight, × its distance.
static var sling_look_ahead := 0.6
## Slingshot: how far the camera eases back in as the ship slows or nears another ship (fraction of its distance).
static var sling_close_zoom := 0.35
## Swipe/slingshot: size of the "on the ship" area a move drag must start in, × (smaller = more room to look around).
static var grab_radius_scale := 1.0
## Swipe/slingshot: how hard a launch bends onto a ship ahead of it (0 = none, 1 = homes in).
static var magnet_strength := 0.85
## Swipe/slingshot: how far off the launch line (degrees) the magnet looks for ships.
static var magnet_cone_deg := 50.0
## Swipe/slingshot: how hard the magnet target drifts into the player's path, m/s².
static var magnet_pull := 60.0
## The player's hull: every hit is divided by this.
static var player_toughness := 1.6
## The player's guns and rams: damage dealt ×.
static var player_power := 1.35
## The player's ram "hitbox": ships within this × the hull's radius take a ram without touching (attack only — the player takes nothing).
static var player_ram_reach := 1.8
## The player's shots hit a ship they pass within this × its radius (0 = only a direct hit).
static var player_shot_hit_scale := 1.8
## Enemy shots only hit the player within this × the hull's radius of its centre (smaller = more near misses).
static var enemy_shot_hit_scale := 0.6
## Seconds an enemy glows and draws its aim line before it opens fire on the player (0 = no warning).
static var enemy_telegraph := 0.45
## Swipe: the closest the camera may come in, × the normal chase distance (pinch, hits and dashes all stay inside).
static var swipe_cam_min := 0.7
## Swipe: the furthest the camera may pull out, × the normal chase distance.
static var swipe_cam_max := 2.6
## Swipe: how far the camera looks ahead of a moving/dashing ship, × its distance (more of what's ahead to tap at).
static var swipe_look_ahead := 0.55

# --- Chains, combos and yeet combat ---
## Kills chained inside [member chain_window] seconds count up a combo (x2, x3 …) on the HUD.
static var combo_counter := true
## Seconds after a kill in which the next kill keeps the chain going.
static var chain_window := 2.5
## Swipe/slingshot: while a chain is live the ship is pulled toward the next enemy (0 = off, 1 = hard).
static var chain_magnet := 0.7
## Yeet combat: hostile ships the player can see dash (yeet) at them. The faster one along the clash wins: the player unhurt, or both hurt.
static var yeet_combat := true
## Yeet combat: seconds between one ship's dashes.
static var yeet_interval := 3.0
## Yeet combat: dash speed, × the ship's top speed.
static var yeet_speed := 2.2
## Yeet combat: how many ships may be mid-dash at the player at once.
static var yeet_max_ships := 2.0
## Yeet combat: seconds a ship winds up (glows, aims) before it dashes.
static var yeet_windup := 0.45
## Comic shouts (POW!, BAM! …) pop where the hit happened in the world, not over the HUD.
static var world_hit_words := true
## Planet pinball: a ram at least this fast (m/s, for a 1 km planet and an average hull; tougher hulls need less, bigger planets more) shatters the planet.
static var planet_smash_speed := 260.0
## Planet pinball: a slower ram at least this fast knocks the planet off its spot; it drifts back.
static var planet_knock_speed := 70.0
## Planet pinball: how far a knock sends the planet, ×.
static var planet_knock := 1.0

# --- Tap aim, auto fire, power-ups, shields, callouts ---
## Slingshot: a tap anywhere (not on the ship) auto-aims — at the ship near the tap, else the best target on screen — while resting or flying.
static var sling_tap_auto_aim := true
## Slingshot: while a launch is flying, the guns fire on their own at the target it is heading for.
static var sling_auto_fire := true
## Kills drop floating power-ups (EMP, boost, shield) that act when flown into.
static var power_ups := true
## Share of the player's kills that drop a power-up.
static var powerup_drop_chance := 0.35
## Seconds a dropped power-up floats before it fades away.
static var powerup_life := 25.0
## EMP: seconds the ripple freezes every ship it reaches.
static var powerup_emp_time := 4.0
## EMP: how far the ripple travels, m.
static var powerup_emp_radius := 900.0
## Boost: seconds it lasts.
static var powerup_boost_time := 8.0
## Boost: attack power ×.
static var powerup_boost_power := 1.8
## Boost: speed ×.
static var powerup_boost_speed := 1.35
## Shield: seconds the bubble lasts (picking another refills it, it never stacks).
static var powerup_shield_time := 15.0
## Shield: the bubble soaks this × the hull's max HP before it pops.
static var powerup_shield_hp := 0.6
## The old always-on shield from the ship design (off: shields come only from the power-up).
static var design_shields := false
## Some enemies spawn with a shield veil (a blue bubble that soaks hits first).
static var enemy_shields := true
## Share of armed enemies that spawn shielded.
static var enemy_shield_chance := 0.25
## An enemy veil soaks this × the ship's max HP.
static var enemy_shield_hp := 0.5
## Persona-style callouts from the player's ship (part lost, power-up, shield down …).
static var player_callouts := true
## Enemies pop comic "!" (noticed an enemy, going down) and "?" (hit by someone they didn't consider an enemy).
static var enemy_marks := true
## Seconds before one ship may pop another mark.
static var enemy_mark_cooldown := 8.0
## The short interactive tutorial runs on the first flight.
static var tutorial_on := true

# --- Interaction markers ---
## A spray-painted target over every ship the player has tangled with, in the
## ship's attitude colour, visible at any range.
static var interaction_markers := true
## Seconds a ship stays marked after the last interaction.
static var interaction_memory := 45.0

# --- Hit explosions ---
## Non-lethal hits can explode on the hull too — explosions are not only for
## deaths. Heavy hits always do; lighter ones roll [member hit_explosion_chance].
static var hit_explosions := true
static var hit_explosion_chance := 0.18
static var hit_explosion_size := 1.0

# --- Aim (the "shots not straight" suspects, see [ShotBugHunt]) ---
## Guns fire from the ship's flight frame rather than from the drawn hull,
## which squashes and springs about on hits and would shear the shots.
static var shot_stable_frame := true
## Legacy bug, kept to reproduce it: a held beam re-aims every frame along the
## camera's centre line instead of the ship's gunsight.
static var beam_camera_aim := false
## How far (degrees) a gun may bend its shot off its own barrel to converge on
## the gunsight. Canted mounts beyond this fire off to the side — the source of
## the scattered beams on many-gun hulls, so the default converges everything.
static var muzzle_convergence_deg := 180.0
## Guns whose barrel points more than [constant OFFAXIS_HOLD_DEG] from the
## nose (side and rear mounts) hold fire rather than shoot through the hull.
static var offaxis_guns_hold := true
const OFFAXIS_HOLD_DEG := 100.0
## Multipliers on each weapon's own random spread.
static var player_spread_mult := 0.3
static var enemy_spread_mult := 1.0

# --- Player weapons ---
## Multiplier on the player's own weapon cooldown (0.7 = fires ~43% faster).
## The HUD's reload ring shows the cooldown either way.
static var player_cooldown_mult := 0.7

# --- Performance ---
## Every enemy projectile in flight, across the whole game. A ship whose shot
## would go past it holds fire; the player's guns never count against it.
static var max_enemy_shots := 160.0
## Explosion effects alive at once; past it the smallest new one is skipped.
static var max_live_explosions := 10.0
## Cosmetic effects (sparks, hit flashes, explosions) that would start outside
## the camera's view or very far off are not spawned at all. A culled effect
## is not drawn anyway, but its particles and scripts still ran every frame.
static var cull_offscreen_fx := true
## Reuse projectile nodes instead of building and freeing one per shot.
static var shot_pooling := true

# --- Respawn ---
## Seconds of invulnerability after a respawn, while enemies' shots already in
## the air pass through.
static var respawn_grace := 4.0

# --- Target markers ---
## Graffiti target size at [constant InteractionMarkers.NEAR_DIST] and nearer
## (largest) and at [constant InteractionMarkers.FAR_DIST] and beyond.
static var marker_max_scale := 1.4
static var marker_min_scale := 0.55


static func set_intensity(value: float) -> void:
	ensure_loaded()
	intensity = clampf(value, INTENSITY_MIN, INTENSITY_MAX)
	_save()


static func set_reduce_motion(value: bool) -> void:
	ensure_loaded()
	reduce_motion = value
	_save()


## Flip one of the per-effect toggles above by name (matches the field name
## exactly, e.g. "near_miss_slowmo"). A single setter rather than one method
## per field since the settings panel binds all seven the same way. Static
## vars are not reflected through [method Object.set], so this is a plain
## dispatch rather than `set(field, value)`.
## The newer bool toggles, loaded and saved by name (their defaults are the
## declarations above). The older ones keep their explicit load/save lines.
const BOOL_FIELDS := [
	"player_emotes",
	"enemy_emotes",
	"freeze_on_player_hit",
	"freeze_on_enemy_hit",
	"freeze_on_kill",
	"kill_cam",
	"knockback_visual",
	"player_invulnerable",
	"enemies_passive",
	"one_hit_kills",
	"ai_fire_patterns",
	"ai_real_projectiles",
	"cheat_offscreen_mercy",
	"cheat_chase_assist",
	"interaction_markers",
	"hit_explosions",
	"shot_stable_frame",
	"beam_camera_aim",
	"offaxis_guns_hold",
	"cull_offscreen_fx",
	"shot_pooling",
	"sling_tap_fire",
	"sling_catch",
	"sling_rocket_spin",
	"ai_slingshot",
	"cam_pinch_zoom",
	"cam_twist_rotate",
	"sling_steady_cam",
	"sling_aim_cam_hold",
	"move_arrows",
	"swipe_from_ship",
	"fps_invert_y",
	"markers_show_hostile",
	"magnet_friendlies",
	"player_wing_spiral",
	"combo_counter",
	"yeet_combat",
	"world_hit_words",
	"sling_tap_auto_aim",
	"sling_auto_fire",
	"power_ups",
	"design_shields",
	"enemy_shields",
	"player_callouts",
	"enemy_marks",
	"tutorial_on",
]


static func get_effect(field: String) -> bool:
	ensure_loaded()
	match field:
		"near_miss_slowmo": return near_miss_slowmo
		"kill_freeze_frame": return kill_freeze_frame
		"hit_squash_stretch": return hit_squash_stretch
		"hit_knockback": return hit_knockback
		"enemy_death_random_explosion": return enemy_death_random_explosion
		"hit_screen_shake": return hit_screen_shake
		"collision_bump_zoom": return collision_bump_zoom
		"ai_flank_enabled": return ai_flank_enabled
		"popcorn_enemies_enabled": return popcorn_enemies_enabled
		"aim_assist_enabled": return aim_assist_enabled
		"shot_sound_interval": return shot_sound_interval
		"ai_attack_pacing": return ai_attack_pacing
		"ai_speed_match": return ai_speed_match
		"player_emotes": return player_emotes
		"enemy_emotes": return enemy_emotes
		"freeze_on_player_hit": return freeze_on_player_hit
		"freeze_on_enemy_hit": return freeze_on_enemy_hit
		"freeze_on_kill": return freeze_on_kill
		"kill_cam": return kill_cam
		"knockback_visual": return knockback_visual
		"player_invulnerable": return player_invulnerable
		"enemies_passive": return enemies_passive
		"one_hit_kills": return one_hit_kills
		"ai_fire_patterns": return ai_fire_patterns
		"ai_real_projectiles": return ai_real_projectiles
		"cheat_offscreen_mercy": return cheat_offscreen_mercy
		"cheat_chase_assist": return cheat_chase_assist
		"interaction_markers": return interaction_markers
		"hit_explosions": return hit_explosions
		"shot_stable_frame": return shot_stable_frame
		"beam_camera_aim": return beam_camera_aim
		"offaxis_guns_hold": return offaxis_guns_hold
		"cull_offscreen_fx": return cull_offscreen_fx
		"shot_pooling": return shot_pooling
		"sling_tap_fire": return sling_tap_fire
		"sling_catch": return sling_catch
		"sling_rocket_spin": return sling_rocket_spin
		"ai_slingshot": return ai_slingshot
		"cam_pinch_zoom": return cam_pinch_zoom
		"cam_twist_rotate": return cam_twist_rotate
		"sling_steady_cam": return sling_steady_cam
		"sling_aim_cam_hold": return sling_aim_cam_hold
		"move_arrows": return move_arrows
		"swipe_from_ship": return swipe_from_ship
		"fps_invert_y": return fps_invert_y
		"markers_show_hostile": return markers_show_hostile
		"magnet_friendlies": return magnet_friendlies
		"player_wing_spiral": return player_wing_spiral
		"combo_counter": return combo_counter
		"yeet_combat": return yeet_combat
		"world_hit_words": return world_hit_words
		"sling_tap_auto_aim": return sling_tap_auto_aim
		"sling_auto_fire": return sling_auto_fire
		"power_ups": return power_ups
		"design_shields": return design_shields
		"enemy_shields": return enemy_shields
		"player_callouts": return player_callouts
		"enemy_marks": return enemy_marks
		"tutorial_on": return tutorial_on
	return false


static func set_effect(field: String, value: bool) -> void:
	ensure_loaded()
	_set_bool(field, value)
	_save()


## Assign one bool toggle by name without saving — shared by [method
## set_effect] and [method load_from_disk].
static func _set_bool(field: String, value: bool) -> void:
	match field:
		"near_miss_slowmo": near_miss_slowmo = value
		"kill_freeze_frame": kill_freeze_frame = value
		"hit_squash_stretch": hit_squash_stretch = value
		"hit_knockback": hit_knockback = value
		"enemy_death_random_explosion": enemy_death_random_explosion = value
		"hit_screen_shake": hit_screen_shake = value
		"collision_bump_zoom": collision_bump_zoom = value
		"ai_flank_enabled": ai_flank_enabled = value
		"popcorn_enemies_enabled": popcorn_enemies_enabled = value
		"aim_assist_enabled": aim_assist_enabled = value
		"shot_sound_interval": shot_sound_interval = value
		"ai_attack_pacing": ai_attack_pacing = value
		"ai_speed_match": ai_speed_match = value
		"player_emotes": player_emotes = value
		"enemy_emotes": enemy_emotes = value
		"freeze_on_player_hit": freeze_on_player_hit = value
		"freeze_on_enemy_hit": freeze_on_enemy_hit = value
		"freeze_on_kill": freeze_on_kill = value
		"kill_cam": kill_cam = value
		"knockback_visual": knockback_visual = value
		"player_invulnerable": player_invulnerable = value
		"enemies_passive": enemies_passive = value
		"one_hit_kills": one_hit_kills = value
		"ai_fire_patterns": ai_fire_patterns = value
		"ai_real_projectiles": ai_real_projectiles = value
		"cheat_offscreen_mercy": cheat_offscreen_mercy = value
		"cheat_chase_assist": cheat_chase_assist = value
		"interaction_markers": interaction_markers = value
		"hit_explosions": hit_explosions = value
		"shot_stable_frame": shot_stable_frame = value
		"beam_camera_aim": beam_camera_aim = value
		"offaxis_guns_hold": offaxis_guns_hold = value
		"cull_offscreen_fx": cull_offscreen_fx = value
		"shot_pooling": shot_pooling = value
		"sling_tap_fire": sling_tap_fire = value
		"sling_catch": sling_catch = value
		"sling_rocket_spin": sling_rocket_spin = value
		"ai_slingshot": ai_slingshot = value
		"cam_pinch_zoom": cam_pinch_zoom = value
		"cam_twist_rotate": cam_twist_rotate = value
		"sling_steady_cam": sling_steady_cam = value
		"sling_aim_cam_hold": sling_aim_cam_hold = value
		"move_arrows": move_arrows = value
		"swipe_from_ship": swipe_from_ship = value
		"fps_invert_y": fps_invert_y = value
		"markers_show_hostile": markers_show_hostile = value
		"magnet_friendlies": magnet_friendlies = value
		"player_wing_spiral": player_wing_spiral = value
		"combo_counter": combo_counter = value
		"yeet_combat": yeet_combat = value
		"world_hit_words": world_hit_words = value
		"sling_tap_auto_aim": sling_tap_auto_aim = value
		"sling_auto_fire": sling_auto_fire = value
		"power_ups": power_ups = value
		"design_shields": design_shields = value
		"enemy_shields": enemy_shields = value
		"player_callouts": player_callouts = value
		"enemy_marks": enemy_marks = value
		"tutorial_on": tutorial_on = value
		_: push_warning("JuiceSettings.set_effect: unknown field %s" % field)


## Allowed range for each float dial set through [method set_float].
const FLOAT_RANGES := {
	"cam_zoom_amount": Vector2(0.0, 2.0),
	"cam_zoom_out_time": Vector2(0.05, 1.5),
	"cam_zoom_hold": Vector2(0.0, 2.0),
	"cam_zoom_return_time": Vector2(0.2, 4.0),
	"cam_follow_rate": Vector2(2.0, 40.0),
	"cam_position_smooth": Vector2(1.0, 15.0),
	"cam_aim_smooth": Vector2(2.0, 25.0),
	"cam_turn_lead": Vector2(0.0, 1.5),
	"cam_speed_fov": Vector2(0.0, 25.0),
	"cam_bank_mult": Vector2(0.0, 2.5),
	"cam_turn_swing": Vector2(0.0, 1.5),
	"weapon_sustain": Vector2(0.0, 1.5),
	"player_blast_push": Vector2(0.0, 1.0),
	"player_blast_spin": Vector2(0.0, 1.0),
	"player_recoil": Vector2(0.0, 1.0),
	"hit_vfx_scale": Vector2(0.0, 1.5),
	"shield_fx_intensity": Vector2(0.0, 1.0),
	"hit_knockback_strength": Vector2(0.0, 1.5),
	"hit_shake_strength": Vector2(0.0, 1.5),
	"emote_size": Vector2(0.0, 3.0),
	"shot_sound_interval_pct": Vector2(-200.0, 200.0),
	"ai_max_attackers": Vector2(1.0, 12.0),
	"ai_rest_mult": Vector2(0.0, 3.0),
	"kill_explosion_chance": Vector2(0.0, 1.0),
	"kill_explosion_size": Vector2(0.0, 3.0),
	"player_emote_chance": Vector2(0.0, 1.0),
	"enemy_emote_chance": Vector2(0.0, 1.0),
	"kill_shake": Vector2(0.0, 2.0),
	"kill_flash": Vector2(0.0, 2.0),
	"freeze_hit_ms": Vector2(0.0, 400.0),
	"freeze_hit_threshold": Vector2(0.0, 0.5),
	"freeze_enemy_hit_ms": Vector2(0.0, 200.0),
	"freeze_kill_ms": Vector2(0.0, 600.0),
	"freeze_depth": Vector2(0.0, 1.0),
	"kill_cam_chance": Vector2(0.0, 1.0),
	"kill_cam_hold": Vector2(0.2, 4.0),
	"kill_cam_blend": Vector2(0.1, 1.5),
	"kill_cam_ease_in": Vector2(0.5, 3.0),
	"kill_cam_time_scale": Vector2(0.0, 1.0),
	"kill_cam_distance": Vector2(1.0, 8.0),
	"kill_cam_cooldown": Vector2(0.0, 30.0),
	"knockback_return_time": Vector2(0.08, 1.5),
	"squash_strength": Vector2(0.0, 3.0),
	"player_damage_taken_mult": Vector2(0.0, 5.0),
	"player_damage_dealt_mult": Vector2(0.0, 10.0),
	"player_shield_mult": Vector2(0.0, 5.0),
	"player_hp_regen": Vector2(0.0, 50.0),
	"player_shield_regen": Vector2(0.0, 50.0),
	"player_shield_regen_delay": Vector2(0.0, 10.0),
	"enemy_hp_mult": Vector2(0.1, 10.0),
	"enemy_damage_mult": Vector2(0.0, 5.0),
	"enemy_fire_rate_mult": Vector2(0.1, 4.0),
	"enemy_accuracy": Vector2(0.0, 1.0),
	"ai_fire_variety": Vector2(0.0, 2.0),
	"enemy_shot_damage_scale": Vector2(0.0, 2.0),
	"offscreen_shots": Vector2(0.0, 10.0),
	"offscreen_window": Vector2(5.0, 120.0),
	"chase_assist_range": Vector2(50.0, 2000.0),
	"chase_assist_strength": Vector2(0.0, 1.5),
	"interaction_memory": Vector2(5.0, 300.0),
	"hit_explosion_chance": Vector2(0.0, 1.0),
	"hit_explosion_size": Vector2(0.0, 3.0),
	"muzzle_convergence_deg": Vector2(0.0, 180.0),
	"player_spread_mult": Vector2(0.0, 3.0),
	"enemy_spread_mult": Vector2(0.0, 3.0),
	"player_cooldown_mult": Vector2(0.2, 2.0),
	"max_enemy_shots": Vector2(20.0, 600.0),
	"max_live_explosions": Vector2(2.0, 40.0),
	"respawn_grace": Vector2(0.0, 10.0),
	"marker_max_scale": Vector2(0.3, 3.0),
	"marker_min_scale": Vector2(0.2, 2.0),
	"swipe_cruise": Vector2(0.0, 1.5),
	"swipe_dash": Vector2(0.2, 4.0),
	"swipe_turn_rate": Vector2(0.5, 20.0),
	"swipe_drag": Vector2(0.1, 6.0),
	"swipe_speed_mult": Vector2(0.5, 3.0),
	"swipe_assist_cone_deg": Vector2(0.0, 90.0),
	"swipe_assist_strength": Vector2(0.0, 1.0),
	"move_ram_dealt": Vector2(0.5, 6.0),
	"move_ram_taken": Vector2(0.0, 2.0),
	"move_durability": Vector2(0.5, 4.0),
	"sling_power": Vector2(0.5, 8.0),
	"sling_bounce_keep": Vector2(0.3, 1.0),
	"sling_bounce_seek": Vector2(0.0, 1.0),
	"sling_end_speed": Vector2(0.05, 1.0),
	"sling_max_time": Vector2(1.0, 20.0),
	"sling_drag": Vector2(0.0, 3.0),
	"sling_zoom": Vector2(0.0, 3.0),
	"sling_spin": Vector2(0.0, 18.0),
	"ai_sling_share": Vector2(0.0, 1.0),
	"swipe_cam_zoom": Vector2(0.0, 3.0),
	"cam_gesture_speed": Vector2(0.2, 3.0),
	"fps_look_speed": Vector2(0.2, 4.0),
	"fps_speed_mult": Vector2(0.3, 3.0),
	"fps_accel": Vector2(0.3, 10.0),
	"fps_boost_at": Vector2(0.5, 1.01),
	"fps_cam_zoom": Vector2(0.0, 3.0),
	"player_min_shot_speed": Vector2(0.0, 3000.0),
	"sling_aim_depth": Vector2(0.0, 1.0),
	"sling_look_ahead": Vector2(0.0, 2.0),
	"sling_close_zoom": Vector2(0.0, 0.8),
	"grab_radius_scale": Vector2(0.4, 3.0),
	"magnet_strength": Vector2(0.0, 1.0),
	"magnet_cone_deg": Vector2(0.0, 120.0),
	"magnet_pull": Vector2(0.0, 300.0),
	"player_toughness": Vector2(0.2, 10.0),
	"player_power": Vector2(0.2, 10.0),
	"player_ram_reach": Vector2(1.0, 5.0),
	"player_shot_hit_scale": Vector2(0.0, 5.0),
	"enemy_shot_hit_scale": Vector2(0.2, 1.5),
	"enemy_telegraph": Vector2(0.0, 1.5),
	"swipe_cam_min": Vector2(0.3, 2.0),
	"swipe_cam_max": Vector2(1.0, 6.0),
	"swipe_look_ahead": Vector2(0.0, 2.0),
	"chain_window": Vector2(0.5, 8.0),
	"chain_magnet": Vector2(0.0, 1.0),
	"yeet_interval": Vector2(0.5, 12.0),
	"yeet_speed": Vector2(0.5, 5.0),
	"yeet_max_ships": Vector2(1.0, 8.0),
	"yeet_windup": Vector2(0.0, 1.5),
	"planet_smash_speed": Vector2(40.0, 2000.0),
	"planet_knock_speed": Vector2(10.0, 1000.0),
	"planet_knock": Vector2(0.0, 5.0),
	"powerup_drop_chance": Vector2(0.0, 1.0),
	"powerup_life": Vector2(5.0, 90.0),
	"powerup_emp_time": Vector2(0.5, 15.0),
	"powerup_emp_radius": Vector2(100.0, 4000.0),
	"powerup_boost_time": Vector2(1.0, 30.0),
	"powerup_boost_power": Vector2(1.0, 5.0),
	"powerup_boost_speed": Vector2(1.0, 3.0),
	"powerup_shield_time": Vector2(2.0, 60.0),
	"powerup_shield_hp": Vector2(0.1, 3.0),
	"enemy_shield_chance": Vector2(0.0, 1.0),
	"enemy_shield_hp": Vector2(0.1, 3.0),
	"enemy_mark_cooldown": Vector2(1.0, 30.0),
}


## Set one of the newer float dials by name, clamped to [constant
## FLOAT_RANGES]. The counterpart of [method set_effect] for floats: static
## vars aren't reachable through [method Object.set], so it's a dispatch.
static func set_float(field: String, value: float) -> void:
	ensure_loaded()
	if not FLOAT_RANGES.has(field):
		push_warning("JuiceSettings.set_float: unknown field %s" % field)
		return
	_load_float(field, value)
	_save()


static func get_float(field: String) -> float:
	ensure_loaded()
	match field:
		"cam_zoom_amount": return cam_zoom_amount
		"cam_zoom_out_time": return cam_zoom_out_time
		"cam_zoom_hold": return cam_zoom_hold
		"cam_zoom_return_time": return cam_zoom_return_time
		"cam_follow_rate": return cam_follow_rate
		"cam_position_smooth": return cam_position_smooth
		"cam_aim_smooth": return cam_aim_smooth
		"cam_turn_lead": return cam_turn_lead
		"cam_speed_fov": return cam_speed_fov
		"cam_bank_mult": return cam_bank_mult
		"cam_turn_swing": return cam_turn_swing
		"weapon_sustain": return weapon_sustain
		"player_blast_push": return player_blast_push
		"player_blast_spin": return player_blast_spin
		"player_recoil": return player_recoil
		"hit_vfx_scale": return hit_vfx_scale
		"shield_fx_intensity": return shield_fx_intensity
		"hit_knockback_strength": return hit_knockback_strength
		"hit_shake_strength": return hit_shake_strength
		"emote_size": return emote_size
		"shot_sound_interval_pct": return shot_sound_interval_pct
		"ai_max_attackers": return ai_max_attackers
		"ai_rest_mult": return ai_rest_mult
		"kill_explosion_chance": return kill_explosion_chance
		"kill_explosion_size": return kill_explosion_size
		"player_emote_chance": return player_emote_chance
		"enemy_emote_chance": return enemy_emote_chance
		"kill_shake": return kill_shake
		"kill_flash": return kill_flash
		"freeze_hit_ms": return freeze_hit_ms
		"freeze_hit_threshold": return freeze_hit_threshold
		"freeze_enemy_hit_ms": return freeze_enemy_hit_ms
		"freeze_kill_ms": return freeze_kill_ms
		"freeze_depth": return freeze_depth
		"kill_cam_chance": return kill_cam_chance
		"kill_cam_hold": return kill_cam_hold
		"kill_cam_blend": return kill_cam_blend
		"kill_cam_ease_in": return kill_cam_ease_in
		"kill_cam_time_scale": return kill_cam_time_scale
		"kill_cam_distance": return kill_cam_distance
		"kill_cam_cooldown": return kill_cam_cooldown
		"knockback_return_time": return knockback_return_time
		"squash_strength": return squash_strength
		"player_damage_taken_mult": return player_damage_taken_mult
		"player_damage_dealt_mult": return player_damage_dealt_mult
		"player_shield_mult": return player_shield_mult
		"player_hp_regen": return player_hp_regen
		"player_shield_regen": return player_shield_regen
		"player_shield_regen_delay": return player_shield_regen_delay
		"enemy_hp_mult": return enemy_hp_mult
		"enemy_damage_mult": return enemy_damage_mult
		"enemy_fire_rate_mult": return enemy_fire_rate_mult
		"enemy_accuracy": return enemy_accuracy
		"ai_fire_variety": return ai_fire_variety
		"enemy_shot_damage_scale": return enemy_shot_damage_scale
		"offscreen_shots": return offscreen_shots
		"offscreen_window": return offscreen_window
		"chase_assist_range": return chase_assist_range
		"chase_assist_strength": return chase_assist_strength
		"interaction_memory": return interaction_memory
		"hit_explosion_chance": return hit_explosion_chance
		"hit_explosion_size": return hit_explosion_size
		"muzzle_convergence_deg": return muzzle_convergence_deg
		"player_spread_mult": return player_spread_mult
		"enemy_spread_mult": return enemy_spread_mult
		"player_cooldown_mult": return player_cooldown_mult
		"max_enemy_shots": return max_enemy_shots
		"max_live_explosions": return max_live_explosions
		"respawn_grace": return respawn_grace
		"marker_max_scale": return marker_max_scale
		"marker_min_scale": return marker_min_scale
		"swipe_cruise": return swipe_cruise
		"swipe_dash": return swipe_dash
		"swipe_turn_rate": return swipe_turn_rate
		"swipe_drag": return swipe_drag
		"swipe_speed_mult": return swipe_speed_mult
		"swipe_assist_cone_deg": return swipe_assist_cone_deg
		"swipe_assist_strength": return swipe_assist_strength
		"move_ram_dealt": return move_ram_dealt
		"move_ram_taken": return move_ram_taken
		"move_durability": return move_durability
		"sling_power": return sling_power
		"sling_bounce_keep": return sling_bounce_keep
		"sling_bounce_seek": return sling_bounce_seek
		"sling_end_speed": return sling_end_speed
		"sling_max_time": return sling_max_time
		"sling_drag": return sling_drag
		"sling_zoom": return sling_zoom
		"sling_spin": return sling_spin
		"ai_sling_share": return ai_sling_share
		"swipe_cam_zoom": return swipe_cam_zoom
		"cam_gesture_speed": return cam_gesture_speed
		"fps_look_speed": return fps_look_speed
		"fps_speed_mult": return fps_speed_mult
		"fps_accel": return fps_accel
		"fps_boost_at": return fps_boost_at
		"fps_cam_zoom": return fps_cam_zoom
		"player_min_shot_speed": return player_min_shot_speed
		"sling_aim_depth": return sling_aim_depth
		"sling_look_ahead": return sling_look_ahead
		"sling_close_zoom": return sling_close_zoom
		"grab_radius_scale": return grab_radius_scale
		"magnet_strength": return magnet_strength
		"magnet_cone_deg": return magnet_cone_deg
		"magnet_pull": return magnet_pull
		"player_toughness": return player_toughness
		"player_power": return player_power
		"player_ram_reach": return player_ram_reach
		"player_shot_hit_scale": return player_shot_hit_scale
		"enemy_shot_hit_scale": return enemy_shot_hit_scale
		"enemy_telegraph": return enemy_telegraph
		"swipe_cam_min": return swipe_cam_min
		"swipe_cam_max": return swipe_cam_max
		"swipe_look_ahead": return swipe_look_ahead
		"chain_window": return chain_window
		"chain_magnet": return chain_magnet
		"yeet_interval": return yeet_interval
		"yeet_speed": return yeet_speed
		"yeet_max_ships": return yeet_max_ships
		"yeet_windup": return yeet_windup
		"planet_smash_speed": return planet_smash_speed
		"planet_knock_speed": return planet_knock_speed
		"planet_knock": return planet_knock
		"powerup_drop_chance": return powerup_drop_chance
		"powerup_life": return powerup_life
		"powerup_emp_time": return powerup_emp_time
		"powerup_emp_radius": return powerup_emp_radius
		"powerup_boost_time": return powerup_boost_time
		"powerup_boost_power": return powerup_boost_power
		"powerup_boost_speed": return powerup_boost_speed
		"powerup_shield_time": return powerup_shield_time
		"powerup_shield_hp": return powerup_shield_hp
		"enemy_shield_chance": return enemy_shield_chance
		"enemy_shield_hp": return enemy_shield_hp
		"enemy_mark_cooldown": return enemy_mark_cooldown
	return 0.0


static func set_ai_flank_chance_mult(value: float) -> void:
	ensure_loaded()
	ai_flank_chance_mult = clampf(value, 0.0, 1.5)
	_save()


static func set_aim_assist_strength(value: float) -> void:
	ensure_loaded()
	aim_assist_strength = clampf(value, 0.0, 1.0)
	_save()


static func set_ram_damage_mult(value: float) -> void:
	ensure_loaded()
	ram_damage_mult = clampf(value, 0.5, 2.0)
	_save()


static func set_hull_hp_mult(value: float) -> void:
	ensure_loaded()
	hull_hp_mult = clampf(value, 0.1, 5.0)
	_save()


static func set_player_durability_mult(value: float) -> void:
	ensure_loaded()
	player_durability_mult = clampf(value, 0.2, 20.0)
	_save()


## Whether the saved settings have been read yet — see [method ensure_loaded].
static var _loaded := false


## Read the saved settings once. Everything that reads or writes a dial calls
## this first: the file used to be read only when [JuiceRuntime] first came up
## (the first effect played), so a flight read the defaults until then, and
## changing one dial before it saved every other one at its default —
## overwriting what the player had set.
static func ensure_loaded() -> void:
	if not _loaded:
		load_from_disk()


static func load_from_disk() -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if GameDefaults.load_layered(cfg, SETTINGS_PATH, JuiceSettings.load_from_disk) != OK:
		return
	intensity = clampf(
		float(cfg.get_value(SECTION, "intensity", INTENSITY_DEFAULT)), INTENSITY_MIN, INTENSITY_MAX
	)
	reduce_motion = bool(cfg.get_value(SECTION, "reduce_motion", false))
	near_miss_slowmo = bool(cfg.get_value(SECTION, "near_miss_slowmo", true))
	kill_freeze_frame = bool(cfg.get_value(SECTION, "kill_freeze_frame", true))
	hit_squash_stretch = bool(cfg.get_value(SECTION, "hit_squash_stretch", true))
	hit_knockback = bool(cfg.get_value(SECTION, "hit_knockback", true))
	enemy_death_random_explosion = bool(cfg.get_value(SECTION, "enemy_death_random_explosion", true))
	hit_screen_shake = bool(cfg.get_value(SECTION, "hit_screen_shake", true))
	collision_bump_zoom = bool(cfg.get_value(SECTION, "collision_bump_zoom", true))
	ai_flank_enabled = bool(cfg.get_value(SECTION, "ai_flank_enabled", true))
	popcorn_enemies_enabled = bool(cfg.get_value(SECTION, "popcorn_enemies_enabled", true))
	aim_assist_enabled = bool(cfg.get_value(SECTION, "aim_assist_enabled", true))
	ai_flank_chance_mult = clampf(float(cfg.get_value(SECTION, "ai_flank_chance_mult", ai_flank_chance_mult)), 0.0, 1.5)
	aim_assist_strength = clampf(float(cfg.get_value(SECTION, "aim_assist_strength", aim_assist_strength)), 0.0, 1.0)
	ram_damage_mult = clampf(float(cfg.get_value(SECTION, "ram_damage_mult", ram_damage_mult)), 0.5, 2.0)
	hull_hp_mult = clampf(float(cfg.get_value(SECTION, "hull_hp_mult", hull_hp_mult)), 0.1, 5.0)
	player_durability_mult = clampf(float(cfg.get_value(SECTION, "player_durability_mult", player_durability_mult)), 0.2, 20.0)
	shot_sound_interval = bool(cfg.get_value(SECTION, "shot_sound_interval", shot_sound_interval))
	ai_attack_pacing = bool(cfg.get_value(SECTION, "ai_attack_pacing", ai_attack_pacing))
	ai_speed_match = bool(cfg.get_value(SECTION, "ai_speed_match", ai_speed_match))
	for field: String in BOOL_FIELDS:
		if cfg.has_section_key(SECTION, field):
			_set_bool(field, bool(cfg.get_value(SECTION, field)))
	for field: String in FLOAT_RANGES:
		if cfg.has_section_key(SECTION, field):
			_load_float(field, float(cfg.get_value(SECTION, field)))


## Clamp to [constant FLOAT_RANGES] and assign, without saving — shared by
## [method set_float] and [method load_from_disk].
static func _load_float(field: String, value: float) -> void:
	var r: Vector2 = FLOAT_RANGES[field]
	var v := clampf(value, r.x, r.y)
	match field:
		"cam_zoom_amount": cam_zoom_amount = v
		"cam_zoom_out_time": cam_zoom_out_time = v
		"cam_zoom_hold": cam_zoom_hold = v
		"cam_zoom_return_time": cam_zoom_return_time = v
		"cam_follow_rate": cam_follow_rate = v
		"cam_position_smooth": cam_position_smooth = v
		"cam_aim_smooth": cam_aim_smooth = v
		"cam_turn_lead": cam_turn_lead = v
		"cam_speed_fov": cam_speed_fov = v
		"cam_bank_mult": cam_bank_mult = v
		"cam_turn_swing": cam_turn_swing = v
		"weapon_sustain": weapon_sustain = v
		"player_blast_push": player_blast_push = v
		"player_blast_spin": player_blast_spin = v
		"player_recoil": player_recoil = v
		"hit_vfx_scale": hit_vfx_scale = v
		"shield_fx_intensity": shield_fx_intensity = v
		"hit_knockback_strength": hit_knockback_strength = v
		"hit_shake_strength": hit_shake_strength = v
		"emote_size": emote_size = v
		"shot_sound_interval_pct": shot_sound_interval_pct = v
		"ai_max_attackers": ai_max_attackers = v
		"ai_rest_mult": ai_rest_mult = v
		"kill_explosion_chance": kill_explosion_chance = v
		"kill_explosion_size": kill_explosion_size = v
		"player_emote_chance": player_emote_chance = v
		"enemy_emote_chance": enemy_emote_chance = v
		"kill_shake": kill_shake = v
		"kill_flash": kill_flash = v
		"freeze_hit_ms": freeze_hit_ms = v
		"freeze_hit_threshold": freeze_hit_threshold = v
		"freeze_enemy_hit_ms": freeze_enemy_hit_ms = v
		"freeze_kill_ms": freeze_kill_ms = v
		"freeze_depth": freeze_depth = v
		"kill_cam_chance": kill_cam_chance = v
		"kill_cam_hold": kill_cam_hold = v
		"kill_cam_blend": kill_cam_blend = v
		"kill_cam_ease_in": kill_cam_ease_in = v
		"kill_cam_time_scale": kill_cam_time_scale = v
		"kill_cam_distance": kill_cam_distance = v
		"kill_cam_cooldown": kill_cam_cooldown = v
		"knockback_return_time": knockback_return_time = v
		"squash_strength": squash_strength = v
		"player_damage_taken_mult": player_damage_taken_mult = v
		"player_damage_dealt_mult": player_damage_dealt_mult = v
		"player_shield_mult": player_shield_mult = v
		"player_hp_regen": player_hp_regen = v
		"player_shield_regen": player_shield_regen = v
		"player_shield_regen_delay": player_shield_regen_delay = v
		"enemy_hp_mult": enemy_hp_mult = v
		"enemy_damage_mult": enemy_damage_mult = v
		"enemy_fire_rate_mult": enemy_fire_rate_mult = v
		"enemy_accuracy": enemy_accuracy = v
		"ai_fire_variety": ai_fire_variety = v
		"enemy_shot_damage_scale": enemy_shot_damage_scale = v
		"offscreen_shots": offscreen_shots = v
		"offscreen_window": offscreen_window = v
		"chase_assist_range": chase_assist_range = v
		"chase_assist_strength": chase_assist_strength = v
		"interaction_memory": interaction_memory = v
		"hit_explosion_chance": hit_explosion_chance = v
		"hit_explosion_size": hit_explosion_size = v
		"muzzle_convergence_deg": muzzle_convergence_deg = v
		"player_spread_mult": player_spread_mult = v
		"enemy_spread_mult": enemy_spread_mult = v
		"player_cooldown_mult": player_cooldown_mult = v
		"max_enemy_shots": max_enemy_shots = v
		"max_live_explosions": max_live_explosions = v
		"respawn_grace": respawn_grace = v
		"marker_max_scale": marker_max_scale = v
		"marker_min_scale": marker_min_scale = v
		"swipe_cruise": swipe_cruise = v
		"swipe_dash": swipe_dash = v
		"swipe_turn_rate": swipe_turn_rate = v
		"swipe_drag": swipe_drag = v
		"swipe_speed_mult": swipe_speed_mult = v
		"swipe_assist_cone_deg": swipe_assist_cone_deg = v
		"swipe_assist_strength": swipe_assist_strength = v
		"move_ram_dealt": move_ram_dealt = v
		"move_ram_taken": move_ram_taken = v
		"move_durability": move_durability = v
		"sling_power": sling_power = v
		"sling_bounce_keep": sling_bounce_keep = v
		"sling_bounce_seek": sling_bounce_seek = v
		"sling_end_speed": sling_end_speed = v
		"sling_max_time": sling_max_time = v
		"sling_drag": sling_drag = v
		"sling_zoom": sling_zoom = v
		"sling_spin": sling_spin = v
		"ai_sling_share": ai_sling_share = v
		"swipe_cam_zoom": swipe_cam_zoom = v
		"cam_gesture_speed": cam_gesture_speed = v
		"fps_look_speed": fps_look_speed = v
		"fps_speed_mult": fps_speed_mult = v
		"fps_accel": fps_accel = v
		"fps_boost_at": fps_boost_at = v
		"fps_cam_zoom": fps_cam_zoom = v
		"player_min_shot_speed": player_min_shot_speed = v
		"sling_aim_depth": sling_aim_depth = v
		"sling_look_ahead": sling_look_ahead = v
		"sling_close_zoom": sling_close_zoom = v
		"grab_radius_scale": grab_radius_scale = v
		"magnet_strength": magnet_strength = v
		"magnet_cone_deg": magnet_cone_deg = v
		"magnet_pull": magnet_pull = v
		"player_toughness": player_toughness = v
		"player_power": player_power = v
		"player_ram_reach": player_ram_reach = v
		"player_shot_hit_scale": player_shot_hit_scale = v
		"enemy_shot_hit_scale": enemy_shot_hit_scale = v
		"enemy_telegraph": enemy_telegraph = v
		"swipe_cam_min": swipe_cam_min = v
		"swipe_cam_max": swipe_cam_max = v
		"swipe_look_ahead": swipe_look_ahead = v
		"chain_window": chain_window = v
		"chain_magnet": chain_magnet = v
		"yeet_interval": yeet_interval = v
		"yeet_speed": yeet_speed = v
		"yeet_max_ships": yeet_max_ships = v
		"yeet_windup": yeet_windup = v
		"planet_smash_speed": planet_smash_speed = v
		"planet_knock_speed": planet_knock_speed = v
		"planet_knock": planet_knock = v
		"powerup_drop_chance": powerup_drop_chance = v
		"powerup_life": powerup_life = v
		"powerup_emp_time": powerup_emp_time = v
		"powerup_emp_radius": powerup_emp_radius = v
		"powerup_boost_time": powerup_boost_time = v
		"powerup_boost_power": powerup_boost_power = v
		"powerup_boost_speed": powerup_boost_speed = v
		"powerup_shield_time": powerup_shield_time = v
		"powerup_shield_hp": powerup_shield_hp = v
		"enemy_shield_chance": enemy_shield_chance = v
		"enemy_shield_hp": enemy_shield_hp = v
		"enemy_mark_cooldown": enemy_mark_cooldown = v


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "intensity", intensity)
	cfg.set_value(SECTION, "reduce_motion", reduce_motion)
	cfg.set_value(SECTION, "near_miss_slowmo", near_miss_slowmo)
	cfg.set_value(SECTION, "kill_freeze_frame", kill_freeze_frame)
	cfg.set_value(SECTION, "hit_squash_stretch", hit_squash_stretch)
	cfg.set_value(SECTION, "hit_knockback", hit_knockback)
	cfg.set_value(SECTION, "enemy_death_random_explosion", enemy_death_random_explosion)
	cfg.set_value(SECTION, "hit_screen_shake", hit_screen_shake)
	cfg.set_value(SECTION, "collision_bump_zoom", collision_bump_zoom)
	cfg.set_value(SECTION, "ai_flank_enabled", ai_flank_enabled)
	cfg.set_value(SECTION, "popcorn_enemies_enabled", popcorn_enemies_enabled)
	cfg.set_value(SECTION, "aim_assist_enabled", aim_assist_enabled)
	cfg.set_value(SECTION, "ai_flank_chance_mult", ai_flank_chance_mult)
	cfg.set_value(SECTION, "aim_assist_strength", aim_assist_strength)
	cfg.set_value(SECTION, "ram_damage_mult", ram_damage_mult)
	cfg.set_value(SECTION, "hull_hp_mult", hull_hp_mult)
	cfg.set_value(SECTION, "player_durability_mult", player_durability_mult)
	cfg.set_value(SECTION, "shot_sound_interval", shot_sound_interval)
	cfg.set_value(SECTION, "ai_attack_pacing", ai_attack_pacing)
	cfg.set_value(SECTION, "ai_speed_match", ai_speed_match)
	for field: String in BOOL_FIELDS:
		cfg.set_value(SECTION, field, get_effect(field))
	for field: String in FLOAT_RANGES:
		cfg.set_value(SECTION, field, get_float(field))
	cfg.save(SETTINGS_PATH)
	GameDefaults.note_saved(SETTINGS_PATH)
