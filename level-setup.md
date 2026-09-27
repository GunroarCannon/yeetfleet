# level-setup.md — Level design rules for Project Nebula

**Companion to:** `GAMEDOC.md` · derived from the market/structure discussion, 2026-09
**Model:** UGG/Katamari-style scenario levels on top of the free sandbox — not linear courses.

---

## 1. The one rule

> **A level is a seed + a spawn manifest, not a hand-placed course.**

Deterministic sim (`--seed=<n>`) does the rest. We author the setup, the
simulation authors the story. Predictable rules, unpredictable situations —
levels obey §2 of the gamedoc, never break it.

## 2. Level anatomy

```
LEVEL = seed (hash of level_id + grammar_version)
      + bodies        (one planet / a belt / a black hole …)
      + factions      (0–2 of the archetype table)
      + ship_lock     (ANY | SCOUT | HAULER | FIGHTER | DRIFT)
      + chain         (mission chain from the M4 grammar)
      + win condition (physical: "3 pods intact within 50m of dock")
      + budget        (bodies ≤ 300, pairs ≤ 1500 — the mobile cap is an authoring dial)
      + medals        (3 per level, same-seed = skill claims)
```

## 3. Levels 1–10 — one physics rule each

| # | Name | Teaches |
|---|---|---|
| 1 | Wrecking Ball | Mass is momentum (hauler + crates, no enemies) |
| 2 | Gravity Is Free | Slingshots (boost locked, planet between you and the goal) |
| 3 | NOPE Button | Boost as recovery (belt crossing, high restitution) |
| 4 | Somebody Saw That | Factions + witnesses (grudge only if observed) |
| 5 | The Drain | Extreme gravity + tow (black-hole rescue) |
| 6–10 | Ship swaps, magnetic faction, explosive chain reactions, escort, chapter final combining all five |

Hand-tune these ten, then lock their seeds.

## 4. The generator (1000+ levels from ~40 authored tables)

```
seed → rng picks:  scenario × hazard × factions × ship_lock × mutators × params
scenario: DELIVER | COLLECT | DESTROY | ESCORT | SURVIVE | RACE | TOW
hazard:   NONE | BELT | BLACK_HOLE | METEOR_STORM | GRAVITY_WELL | BINARY_PLANETS
mutators: FRAGILE_CARGO | DRY_CAPACITOR | NO_ASSIST | DENSE_BELT | LOW_GRAVITY | PIRATE_SEASON | …
params:   scaled by d(N) — one smooth difficulty curve, tuned once
```

- **Validate, don't vibe:** every generated level passes a headless check
  (path exists, body budget, medal reachable by bot pilot) before playable;
  failures reroll the seed. Build this harness alongside M4, not after.
- **Names from the seed** via wordbank ("Belt of the Angry Magnet").
- **Medals are the content multiplier:** 3 × every level, no extra content cost.
- **Mutator table is the anti-sameness budget** — keep adding mutators in updates.

## 5. Determinism gives us two features for free

- **Level codes:** "try #743" is a complete level definition in one number.
- **Daily level:** seed = hash(date). Everyone plays the same level today.

## 6. Mode split (two front-ends, one simulation)

- **Campaign** — scenario levels: onboarding, structure, D7 meta, demo for Next Fest.
- **Free Sandbox** — endless toy: clip generator, home of "the universe remembers".
  Faction memory persists within a level; a light cross-level notoriety flag
  carries grudges into occasional "consequence levels".

Cross-level arcs, run mode, and the meta loop live in `level-gen.md`.

## 7. Anti-goal check

Level select is a menu, not a quest menu — fine. Missions inside a level still
appear only as 🚨/📦/🎯 in the world. No briefings, no pause, no fail-reload
(failed objectives respawn or escalate; chaos is never punishment).
