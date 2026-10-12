# Sandbox mini goals

2026-10-12. Players could not tell what free flight was for: one hint line at
2.5 s, no score on screen, incidents with no progress.

## Chosen

A `SandboxGoals` control (flight module, `ui/`) owned by `SandboxLife`, drawn
down the left of the HUD under the health plate and above the radar: points and
a bar to the next coin, three mini goals each with a progress bar and a bonus,
and one line on what is happening out there (`SandboxLife.situation()`) or a
tip. It is fed by `SandboxLife.note()`, which `FlightRoot.tutorial_note()`
already calls for the events the tutorial hears (kill, powerup, launch, swipe)
plus "chain", "raid" and "rescue". A goal pays points into `FlightRoot.score`,
so the wreck card counts them into coins like any other points. Dying wipes
progress; hidden while the first-flight tutorial runs.

## Rejected

- A quest/event-bus system: nothing else in the game needs one, and the
  tutorial's `note()` names already say what the player did.
- Making the one hint line longer: easy to miss, and has no progress to show.
- Goals in the campaign module: the sandbox is flight-module only, and a
  module should not reach into another's state.

## Checks

`modules/flight/tools/sandbox_check.gd` (goals panel up, no duplicate, a fed
goal finishes, pays, and is replaced); screenshots with
`modules/flight/tools/sandbox_goals_shot.gd`. The sandbox check's raid and
"megastructure landmarks" lines are flaky on HEAD (same failures with these
changes stashed).
