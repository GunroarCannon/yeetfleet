# Project Nebula — working notes for Claude Code

Godot 4.5 (GL Compatibility), GDScript. Modules under `modules/`, each with a
`class_name` façade, `scripts/`, optional `tools/` (headless smokes) and
`data/`. Execution order and the feel contract live in `TECHNICAL_PLAN.md`;
`GAMEDOC.md` is the design bible.

## The rules that matter (a condensed, always-true core)

- **Match the surrounding code exactly.** Tabs for indentation, `##` doc
  comments above classes/functions/significant vars, `:=` inference,
  snake_case with `_` private prefix, typed returns (`-> void`), section
  banners like `# --- Translation ---`. GDScript is whitespace-sensitive: one
  wrong indent is a parse error.
- **The Godot exe is NOT on PATH.** Use
  `"C:\Users\hmmm\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Godot_v4.5-stable_win64.exe"`
  (export it as `GD`). Rescan the class cache after adding any `class_name`
  (`"$GD" --headless --editor --quit --path .`).
- **Headless verification, always.** Module smokes:
  - physics: `"$GD" --path . --headless --script modules/physics/tools/physics_smoke.gd`
  - flight↔physics bridge: `... --script modules/flight/tools/flight_bridge_smoke.gd`
  - flight scene orbit: `... --script modules/flight/tools/orbit_check.gd`
  - profile cycle / rock promote / control modes: the matching `*_check.gd`.
- **Module isolation.** One `class_name` per module; a module talks to another
  only through that façade's public API (signals out / calls in). No `get_parent()`
  reach-across for new code. `Session` (core) holds statics that survive scene
  reloads.
- **Memory gotchas** (see the auto-memory `godot-headless-smoke-gotchas`):
  the class-cache rescan does not compile script bodies — parse errors surface
  when a script is loaded; nodes added under `SceneTree.root` are not in the
  tree until the loop runs (`await process_frame` ×2); GDScript lambdas capture
  outer locals by value — use bound methods + instance fields to hand data back;
  a model with `_physics_process` is auto-stepped during any `await`, so settle
  moving ships at rest first.

## Editing files correctly (positive + negative examples)

Use `Edit` with a **small, exact** `old_string` copied verbatim from the file —
never retype code you think you remember. Then make the new text differ only in
what must change. Prefer many small edits over one huge replacement; only
`Write` a whole file when you have just read the whole file and are rebuilding
most of it.

- Positive: replace one method's body:
  ```text
  old: "\tvar step := thrust * ASSIST_AUTHORITY * delta"
  new: "\tvar step := thrust * assist_authority * delta"
  ```
  (Note the leading tab character — GDScript indentation.)
- Positive: when a block spans several lines, include enough unique context
  (the `func` header or a neighbouring comment) so the match is unique, and keep
  unrelated lines identical.
- Negative — never do this: guess at the text. The read line numbers are NOT
  part of the file; do not include `123:`. If `Edit` says "String to replace not
  found", `Read` the file and copy the exact bytes (tabs, trailing spaces,
  the `✕`-style characters) — do not retry a slightly-different guess.
- Negative: don't paste a giant `old_string` spanning dozens of lines; if a big
  block is genuinely being rewritten and `Edit` keeps failing, rewrite the file
  with `Write` instead (you must have read it first).
- The Edit tool is preferred over `sed`/`perl` for source changes — it surfaces
  mismatches instead of silently doing the wrong thing.

Windows note: paths in tools are `/c/Users/...`-style for the Bash tool, and
`C:\Users\...`-style when the absolute Windows path is needed. In GDScript
resources are always `res://...`.
