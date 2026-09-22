---
name: elite-clone-dev
description: >-
  Essential knowledge, architecture overview, and developer commands for the elite-clone Godot space game.
  Activate this skill when working on game logic, UI, physics, or visuals in this project.
---

# Elite Clone Developer Guide

This file contains crucial context for developing the `elite-clone` project. It documents the architecture, common pitfalls, and commands for testing.

## 📁 Codebase Layout

The project is structured into modules under `modules/`:
*   `core/`: Core settings like `session.gd` which holds default/active settings (`arcade_pivot`, `enhanced_lighting`, etc.).
*   `flight/`: The main flight simulation.
    *   `scripts/flight_root.gd`: Main scene manager. Handles spawning, keyboard shortcuts (F11/F12 debug, F10 palette), and ties systems together.
    *   `scripts/space_scene.gd`: Handles visual environment, stars, lighting, planets.
    *   `scripts/ui/flight_hud.gd`: The HUD. Uses `_overlay.draw_*` for custom 2D rendering (reticles, minimap, edge indicators).
*   `physics/`: A custom physics engine (`phys_world.gd`, `impulse_solver.gd`)!
    *   **Crucial:** Controllers (like `FlightModel`) run at physics priority 0 and write `velocity` but *do not move their nodes*. `PhysWorldDriver` runs at priority 100, detects collisions using `Broadphase`, resolves impulses, and *then* updates node positions.
    *   Collisions in `PhysWorld` are resolved using mathematical spheres via `HullFit`.
*   `large_craft_gen/`: Procedural mega-structures (stations, dreadnoughts).
    *   `large_craft_generator.gd` builds these using `StaticBody3D`. 
    *   Godot raycasts use `create_trimesh_shape()` for these structures to allow concave shapes (like rings).
    *   However, `PhysWorld` collision uses `get_collision_spheres()`, which must manually generate sphere paths for concave objects (e.g. rings).
*   `ship_builder/`: Ship visuals and procedural generation.
    *   `ship_part.gdshader` and `ship_materials.gd` control ship rendering. Opacity/Solidity is an important parameter to prevent ships from looking see-through against space.
*   `style/`: Handles visual profiles (`cartoony.tres`, `grounded.tres`) that define things like star count, star size, outline width, and color palettes.

## 🧠 Key Systems & "Gotchas"

1.  **Custom Physics vs Godot Physics**: 
    If a ship bounces off invisible walls on a mega-structure, it's usually because `large_craft_generator.gd`'s `get_collision_spheres()` is returning a single solid box `HullFit.spheres_for_box(part.aabb)` instead of a hollow shape. Godot's built-in `CollisionShape3D` is separate and used for raycasts/queries (use `create_trimesh_shape()` for static geometry).
2.  **Drawing on the HUD**:
    Adding elements to the HUD requires hooking into `_draw_instruments()` in `flight_hud.gd` and using `_overlay.draw_...` methods. To project 3D to 2D, use `camera.unproject_position(world_pos)` and guard against `camera.is_position_behind(world_pos)`.
3.  **Visuals and Lighting**:
    Changes to environmental lighting happen in `space_scene.gd` (`_build_environment`). Changes to ship rendering happen in `ship_materials.gd` (`apply_palette`).
4.  **Debug Toggles**:
    *   `F11` toggles Godot's built-in collision wireframes.
    *   `F12` toggles 3D geometry rendering (leaving only HUD/collisions).
    *   `F10` opens the palette/style menu.

## 🛠️ Developer Commands & Testing

You MUST use the correct Godot executable for this project.
**Godot Executable Path:** `C:\Users\hmmm\Godot_v4.4-stable_win64.exe`
**Godot Console Path (for checking syntax errors):** `C:\Users\hmmm\Godot_v4.4-stable_win64_console.exe`

### 1. Running Smoke Tests
Run the automated smoke test script to ensure you haven't broken the flight simulation:
```powershell
& "C:\Users\hmmm\Godot_v4.4-stable_win64.exe" --headless --script modules/flight/tools/flight_smoke.gd
```

### 2. Generating Visual Screenshots
If you modify shaders, styles, lighting, or generation, take a screenshot and present it to the user.
```powershell
& "C:\Users\hmmm\Godot_v4.4-stable_win64.exe" --headless --script modules/large_craft_gen/tools/large_craft_gen_lab_shot.gd --palette "toon" --style "cartoony"
```
*Screenshots will be output to the project directory or the agent's artifact directory. Verify with `Get-ChildItem -Filter *.png`.*

### 3. Checking Syntax Errors
If Godot fails to run silently, you likely have a GDScript parse error. Create a tiny dummy script to load the file you changed, then run it with the console executable to see the exact line number:
```powershell
Set-Content scratch/check.gd -Value "extends SceneTree`nfunc _init():`n    load('res://modules/flight/scripts/ui/flight_hud.gd')`n    quit()"
& "C:\Users\hmmm\Godot_v4.4-stable_win64_console.exe" --headless -s scratch/check.gd
```
*(This is critical because headless mode on the standard exe swallows script compilation errors.)*
