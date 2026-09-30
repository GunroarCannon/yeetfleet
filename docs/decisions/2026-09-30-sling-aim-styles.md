# Slingshot aim styles (classic / dome / smart) — 2026-09-30

**Ask:** the slingshot shouldn't throw straight opposite the pull; the pull
should sit on the half-sphere it was pulled on, so pulling back throws the
ship forward, not up. That is the default. Also a smarter option.

**Picked:** one new dial, `JuiceSettings.sling_aim_style` (0 classic, 1 dome
= default, 2 smart), stored as a float dial so it saves and bakes like the
rest. It's a new dial, not a changed default, so it reaches players who
already have saved settings.

- **Dome** (`SlingshotPilot.dome_dir`): the band sits on the half-sphere round
  the ship that faces the camera. Pulling down wraps round toward the camera,
  so the launch runs along the line of sight through the ship (forward). Up
  throws down and sideways throws sideways. Every pull also leans
  `sling_aim_depth × DOME_LEAN` into the screen.
- **Smart:** the dome, plus wider snap cones (28° ships / 38° goals against
  12° / 22°), a 0.9 bend onto the lead point, and at least the pull power
  that reaches the pick before the run ends. That power is solved from the
  exponential drag, the end speed and the time limit, with a ×1.3 margin.

**Rejected:** a virtual-trackball mapping (pull distance = how far round the
dome). Distance already sets the power, and with a trackball a long pull
straight down threw the ship mostly *up* — the opposite of the ask.

**UI:** a Classic / Dome / Smart button row in 🎮 Controls → Slingshot, and
FLING AIM (CLASSIC / DOME / SMART) in the menu's GAMEPLAY page.

**Checks:** `move_profile_check` (60 and 144): the launch check expects the
dome, the "looks opposite on screen" check runs on classic, and a new aim
styles check covers dome directions and smart lock plus power.
