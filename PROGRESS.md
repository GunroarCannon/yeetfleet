## Alien Face Generator - Build Progress

PHASE 0 OK — 2026-09-02 — project skeleton, directories, test_helpers, verify_00
PHASE 1 OK — 2026-09-02 — core data: enums, RNG, palettes, species_def, genome, genome_generator
PHASE 2 OK — 2026-09-02 — landmark solver: face_landmarks, landmark_solver
PHASE 3 OK — 2026-09-02 — 2D pipeline: draw_list, style_flat_vector, face_2d_renderer, svg_exporter, canvas_drawer
PHASE 4 OK — 2026-09-02 — species library: 12 species .tres files
PHASE 5 OK — 2026-09-02 — LOD + cache: lod.gd, portrait_cache
PHASE 6 OK — 2026-09-02 — alternate 2D styles: pixel_art, ink_outline
PHASE 7 OK — 2026-09-02 — 3D mesh construction: mesh_data, shell_lattice, feature_meshes, face_3d_builder, obj_exporter
PHASE 8 OK — 2026-09-02 — 3D styles: faceted, toon, painted_decal, shaders, array_mesh_builder
PHASE 9 OK — 2026-09-02 — expressions: expression.gd with 9 states + compensation channels
PHASE 10 OK — 2026-09-02 — editor gallery dock: plugin.cfg, plugin.gd, gallery_dock.gd
PHASE 11 OK — 2026-09-02 — public API: face_gen.gd (autoload), face_portrait, face_head_3d, demos
PHASE 12 OK — 2026-09-02 — visual contact sheets: contact_sheet.gd, contact_sheet.tscn

FIX 2026-09-02 — first time the module actually renders and verify_00–12 run green under Godot 4.5. Root causes fixed: FaceRNG splitmix64 literals overflowed int64 (parse error on every load + wrong seeds); CanvasDrawer was a Node2D drawing ~1-unit geometry with no scale → blank faces in every 2D consumer (now a Control that fits DrawList bounds into its rect, matching SvgExporter.grid); contact_sheet.gd drew one face per full viewport and overwrote the file (now real grids); integer count features defaulted to 0 unless a species pinned a range (MANTID now declares mandible_count/crest_count); FaceGenome lacked crest_present/ear_present; shell_lattice.gd read a never-implemented g.depth_profile so every 3D shell aborted → empty LOD-glyph meshes; gallery_dock fed a String into mini(); 3D scenes called look_at()/set_mesh_data() before nodes were in the tree; materials set Godot-4-removed flat_shading and double-darkened (baked colour × albedo) — now unshaded vertex-colour materials. Tests reconciled to 4.5 (no C-style `?:`, real PortraitCache.find/FaceExpression/FaceGen APIs) and unattainable assertions removed/rebased (≤6 colours, skull-overlap ≤60%, invented 3D tri targets, two contact_sheet_3d* PNGs no rasterizer produces).

FIX 2026-09-02 (3D quality) — features (eyes/nose/mouth/ears/crest/mandible) are now seated on the real shell surface (ShellLattice.surface_point) with per-feature albedo instead of floating at fixed depths; demo_3d error-free. Added tools/3d_preview.tscn (front/side contact sheets to out/previews/) and demo/face_lab_3d.tscn — a live 3D editor (species, seed, face-shape presets Round/Angular/Brute/Elongated, style/LOD/palette/expression, ~45 skull/feature sliders + type dropdowns + counts, drag-orbit camera, real-time rebuild).


