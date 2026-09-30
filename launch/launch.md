# Yeetfleet — launch kit

Everything for the Play Store listing lives in this folder, and the art is
drawn by the game's own code, so it can be regenerated whenever the look
changes.

```
launch/
  launch.md              this file
  feature_graphic.png    the current Play Store banner (1024×500)
  icon_512.png           the current store icon (512×512)
  banners/               every banner generated (feature_<seed>.png)
  icons/                 every icon generated (icon_<seed>.png)
  screenshots/           store screenshots (01_home.png … 06_flight_b.png)
  studio/                pictures saved from the Art Studio
  tools/banner_gen.gd    makes banners and icons (the Art Studio's builder)
  tools/store_shots.gd   takes the screenshots
```

## Regenerating

All three need a window (Godot's headless renderer draws nothing). `GD` is
the Godot 4.7 editor exe (`C:\Users\hmmm\Godot_v4.7-stable_win64_console.exe`).

```sh
# A new semi-random banner (new victim, crew, blast kind, angle, planet, sun,
# title tilt; the addon explosions go off a beat apart for a chaotic bang):
"$GD" --path . --audio-driver Dummy --script launch/tools/banner_gen.gd
# Get a banner you liked back by its seed (printed, and in the file name):
"$GD" --path . --audio-driver Dummy --script launch/tools/banner_gen.gd -- seed=2024
# A new icon:
"$GD" --path . --audio-driver Dummy --script launch/tools/banner_gen.gd -- icon
# Screenshots (landscape 1920×1080 by default; add -- 1080 1920 for portrait):
"$GD" --path . --audio-driver Dummy --script launch/tools/store_shots.gd
```

Each banner run writes `banners/feature_<seed>.png` and overwrites
`feature_graphic.png`; run it a few times and keep the one you like (copy it
back over `feature_graphic.png`, or rerun its seed). Screenshots run on a
scratch save; your own progress is never touched. Any Art Studio setting can
be fixed from here too: `-- seed=2024 blast=nuke fighters=8 glare=1.4`.

## Art Studio (by hand)

Home screen → DEBUG → MODULES → ART STUDIO (or run
`modules/art_studio/art_studio.tscn`). The picture on the left, every part of
it on a dial on the right: picture kind (feature / icon / landscape /
portrait / tablet), seed, sky, the wreck and how many parts blow off, the
main blast (fire, plasma, toxic, candy, nuke, none) and its size, small
blasts and their kind, particle explosions, fighters and their spread, bolts,
big ships, rocks, the planet (which, size, side), the sun and its glare
(strength, size, rays, ray length, streak, ghosts, colour), sunlight, the
camera (angle, height, distance, field of view, roll, lift) and the words
(title text, icon mark, size, tilt, drips, height).

NEW SEED / RANDOMISE ALL / REPLAY BLASTS; SAVE PNG writes
`launch/studio/<kind>_<seed>.png`; USE AS STORE ART also copies it over
`feature_graphic.png` or `icon_512.png`. Smoke:
`modules/art_studio/tools/art_studio_shot.gd` (windowed).

## In-app purchases (RevenueCat)

Coin packs are consumables sold through RevenueCat (`modules/store/scripts/coin_store.gd`,
the STORE slab on the home screen and the **+** beside the coins).

**Exact IDs** — create these *identically* in Play Console and RevenueCat:

| Product ID (Play + RevenueCat) | Type | Coins | Suggested price |
| --- | --- | --- | --- |
| `yeetfleet_coins_small` | Consumable (one-time product) | 500 | $0.99 |
| `yeetfleet_coins_medium` | Consumable | 1,500 | $2.99 |
| `yeetfleet_coins_large` | Consumable | 4,000 | $6.99 |
| `yeetfleet_coins_huge` | Consumable | 10,000 | $14.99 |

- Android package name: `com.critbox.yeetfleet` (already in the export preset).
- Store prices on screen come from the store (localised); the ones above are
  only the fallback shown before they load.
- No entitlements, offerings or paywalls are used: the game buys a product by
  its ID and grants the coins itself. (Optional: an offering `default` with
  the four packages, for RevenueCat's dashboards.)

**Keys** (in `coin_store.gd`):
- `TEST_API_KEY = "test_gulPvTrQEctYxIyvcbHcvUBzPuG"` — RevenueCat's **Test
  Store**, used by **debug builds only**. Purchases there are simulated by a
  RevenueCat dialog (succeed / fail / cancel) — no Play Console needed.
- `ANDROID_API_KEY = ""` — paste the Play app's public SDK key (`goog_…`,
  RevenueCat → Project → API keys) before a release build. With it empty the
  release store shows CLOSED. **Never ship the test key**: the SDK crashes a
  release build on purpose when it finds one, which is why the code never uses
  it outside debug builds.

**The plugin** (not bundled — RevenueCat has no first-party Godot SDK):
[GodotX RevenueCat](https://github.com/godot-x/revenuecat) (Godot 4.7+,
Asset Library #4493). Install into `addons/godotx_revenue_cat/` and
`android/revenuecat/`, enable it in Project Settings → Plugins, run Project →
Install Android Build Template, and in the Android export preset tick
**Use Gradle Build** and the **GodotxRevenueCat** plugin. Without the plugin,
debug builds on desktop fake a successful purchase so the flow can be tried.

**Setting it up in RevenueCat:**
1. Project → Apps → add a Play Store app, package `com.critbox.yeetfleet`, and
   upload the Play service-account JSON (RevenueCat's guide walks through the
   Google Cloud side).
2. Products → import or add the four IDs above (type: consumable).
3. Test first with the Test Store key (debug build, plugin installed): add the
   same four product IDs to the Test Store in RevenueCat.

**Do you need Play testing?** For the Test Store key: **no** — it works in any
debug build with the plugin, on a device or emulator, no Play upload. For
*real* Google Play purchases: **yes** — the app must be uploaded (an internal
testing track is enough, and the products must be active), the tester's Google
account added as a licence tester (Play Console → Settings → License testing)
so they are not charged, and the app installed from that track's opt-in link
(or at least signed with the same key and version as the upload).

Data safety form: with purchases, RevenueCat receives purchase history and an
anonymous app user ID — declare "Purchase history" (app functionality) in the
Data safety form.

## Play Store asset specs

| Asset | Size | Notes |
| --- | --- | --- |
| App icon | 512×512 PNG, 32-bit | No rounded corners or shadow; Play masks it. Max 1 MB. |
| Feature graphic | 1024×500 JPG or 24-bit PNG (no alpha) | Shown on the store page and in promos. Keep the title clear of the edges; Play may crop. |
| Phone screenshots | 2–8; 16:9 or 9:16; each side 320–3840 px | 1920×1080 or 1080×1920 are safe. At least 4 at 1080px+ to be eligible for featuring. |
| Tablet screenshots | optional, 7" and 10" | Same tool at 2560×1600. |

## Logo suggestion

The in-game title — YEETFLEET in the "From Street Art" spray face, lime to
teal fill, ink outline, drips and a halo — is the wordmark. For the **app
icon** it is too long to read at 48 px, so the suggestion is:

- **The mark:** a single graffiti **Y** (same face, fill, outline and halo as
  the title) over a frozen cartoon blast, with one ship being yeeted out of
  it. That is what `banner_gen.gd -- icon` draws.
- **Why:** the Y plus the blast reads at thumbnail size, carries the brand's
  spray-paint look, and says "explosions and ships" without words.
- **Keep it simple:** at 48 px only the Y, the halo and the blast's bright
  core survive; the crew ships are texture. If an icon run comes out busy,
  rerun with another seed.
- For the adaptive launcher icon (Android 8+), put the Y on the foreground
  layer and the blast on the background layer, so the mask can crop the
  blast safely. Set both in Project → Export → Android → Launcher Icons.

## Listing copy (draft)

- **Title (30 chars max):** Yeetfleet
- **Short description (80 chars max):** Sling your ship into space fights. Ram, blast and yeet your way to the stars.
- **Full description:**

  Pull back, let go, YEET. Yeetfleet is a one-thumb space brawler: drag from
  your ship to sling it across the fight, bounce off hulls, ram pirates to
  bits and stop time on every wreck.

  - A campaign of hand-shaped, seeded levels — the same for every pilot —
    that branches with the way you play.
  - Races through rings, cargo runs, escorts, carrier assaults, duels and
    all-out battles.
  - A garage of eleven ships, from nimble scouts to titans, each with its
    own upgrades.
  - Cartoon explosions, planet-wrecking nukes and a lot of noise.

- **Category:** Game → Action (or Arcade).
- **Tags:** space, arcade, slingshot, shooter, casual.

## Before publishing — checklist

- [ ] Export an **AAB** (Play requires it) with a release keystore; keep the
      keystore and its passwords out of git (`*.apk`, `*.aab`, `*.idsig` are
      already ignored; add the keystore path too).
- [ ] Target the current Play API level (Project → Export → Android → Target SDK).
- [ ] Set the version code and version name for every upload.
- [ ] Privacy policy URL (needed even with no data collection) and the Data
      safety form (the game saves only on the device).
- [ ] Content rating questionnaire (cartoon violence).
- [ ] Release build: the DEBUG chip on the home screen only exists in debug
      builds (`OS.is_debug_build()`), so check an exported release build
      doesn't show it.
- [ ] Font licences: "From Street Art" ships with its own licence file in
      `assets/fonts/`; check it allows commercial use, and the same for FOO
      and any other face used in the shipped UI.
- [ ] Credit the star model: "Star Shape" by Suphanee (check its licence).
