# 2026-09-30 — Feedback batch: sound levels, star gates, sling camera, escort, store, art

## Sound
- **Pattern:** per-file loudness trim (`Sfx.TRIM_DB`) measured with ffmpeg
  EBU R128 (everyday laser −22 LUFS; `Laser Gun.mp3` was −6, heavy guns −11…−13,
  big fly-by −13.6), applied wherever a library stream plays; plus a ceiling
  on positional loudness (`SPATIAL_MAX_DB`, enemy shots `SHOT_MAX_DB` with a
  smaller `SHOT_UNIT_SIZE`).
- **Rejected:** re-encoding the files (loses the originals, and the next file
  swap would need the same work), or lowering the SFX bus (quiets everything).
- Upgrade pips use a plain rising triad (`GameAudio.UI.upgrade`); SOUND/MUSIC
  default to 60% and cycle 100/80/60/40/20/OFF.

## Campaign
- **Stars alone open levels** (`LevelGen.stars_needed`): 0 for levels 1–3,
  then a share of every star the earlier levels could pay, climbing to 65%
  (τ = 6 levels): L4 1, L10 12, L20 35, L30 56. The fork opens the same way.
  Rejected: a flat per-level rate (the old 1.15/level) — too harsh early, too
  soft late.
- **Eras:** from level 20, every 10 levels, enemy hull ×1.22 and damage ×1.12
  per era, on top of the slow climb — so the garage's bigger hulls matter.
- No neutral giants in levels; the backdrop megastructure only frames bosses.
- Player gun damage has its own dial (`player_gun_damage`, 0.6) — a new dial
  because a changed default never reaches a saved juice file.

## Slingshot camera
- **Pattern:** while pulling, the chase frame is *held* (`follow_dir` → ZERO)
  and the view *turns* to look along the live aim (`look_ahead`,
  `sling_aim_look`). Rejected: the old swing round behind the ship
  (`sling_aim_cam_look`), which moved the camera to where the ship would go
  instead of looking there, and zeroed look-ahead (`sling_aim_cam_hold`).
- Rest distance / nearest / aim zoom / look-ahead settle time are new dials,
  surfaced in Settings → GAMEPLAY (tap-to-cycle, like every settings slab).
- A second finger during a pull looks around (`GestureReader.keep_primary` +
  `look_dragged`) instead of cancelling the pull; from then until release the
  auto camera leaves the view alone.
- Aim snaps bend 55% of the way (was 85%), so a launch reads as its pull.

## Escort
- "ESCORT DESTROYED" / "CARRIER DESTROYED"; a gentle leash to the guarded
  ship past 260 m (≤16 m/s²); a reveal at the start — the kill cam's swoop
  reused (`FlightCamera.show_ship`) with "PROTECT THIS SHIP!".

## Store (RevenueCat)
- **Pattern:** a static `CoinStore` façade (new `store` module) over the
  GodotX RevenueCat plugin singleton; consumable packs by product ID, coins
  granted by the game. Test Store key in debug builds only; release key empty
  until set (store shows CLOSED). Rejected: Godot's first-party
  GooglePlayBilling plugin (the user asked for RevenueCat, and it keeps iOS
  open), and entitlements/offerings (nothing here is a subscription).
- IDs and setup: `launch/launch.md` → In-app purchases.

## Art
- `LensGlare` (soft gradient textures, additive) replaces the stacked-disc
  bloom and one-pixel ray lines (visible rings and lines on the sun).
- Card pictures: 25 → 53 baked (six suns with glare, repainted worlds, every
  blast palette + nuke, more crews), plus a per-card colour grade.
- Art Studio module: every part of the store art on a dial; `banner_gen.gd`
  shares its builder.
- Loading wall: sprayed splats (soft mist, uneven blob, drips) instead of
  stacked translucent circles; user rejected an intermediate version with
  spray strokes and rectangles as messier.

## Follow-ups in the same session
- **Pull direction:** "into the screen" now runs along the line of sight
  through the ship (`MovePilot.depth_dir(..., ray)`), so the launch projects
  exactly opposite the pull (0.0° in move_profile_check); the view's forward
  axis made an off-centre ship seem to slide toward the middle.
- **Fling camera:** `sling_cam_follow_flight` (on) keeps it behind the real
  flight through bounces (the launch hold lost the ship after a bounce);
  follow frames turn at most `cam_max_turn_deg` (75°/s); look-ahead is capped
  at 0.55 × distance so the ship never leaves the shot.
- **Kill cam:** new `kill_cam_odds` 0.7 and `kill_cam_length` 0.6, only for a
  player kill whose blast is in view within 900 m; all in Settings → GAMEPLAY.
- **Stars:** `StarRating` (common/rules) — per-level seeded weights over hull,
  speed vs par and the guarded ship's hull; bars rise with difficulty (3★ at
  0.66 → 0.90). Shared by the campaign and the end card, which names the focus.
- **Missions:** PROTECT (escort with `hold_time`), VOYAGE (farthest named
  planet), the escort's dashed route line and "ROUTE n%", "N LEFT" (+ wave) on
  the phone HUD, guarded ships are `player_proof`.
- **Planet names** per system (`PlanetData.system_name`), labels too.
- **Boot:** the splash cross-fades into the loading card, which loads the menu
  plus songs, sounds and card pictures (kept cached) and fades once the menu
  has drawn; the first card ever says WELCOME TO THE UNION OF PEACE.

## Checks
move_profile (60/144), powerup (60/144), camera_feel (144; the 60 fps weave
test is flaky on committed code too), combat_feel, level_feel, mission,
campaign, menu, game_defaults, art_studio_shot (windowed) — all PASS.
