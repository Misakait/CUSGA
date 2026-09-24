# Godot Editor MCP Setup

This project is a Godot 4.7.1 GDScript project. Static relationships are inspected with native repository tools; runtime behavior is validated through the connected Godot editor.

## Static Analysis

Use `rg` and direct file reads to trace GDScript, scenes, resources, autoloads, signals, and node paths:

```text
rg -n "class_name|signal|\.instantiate\(|get_node\(|preload\(|load\(" --glob "*.gd" --glob "*.tscn" --glob "*.tres" --glob "project.godot"
```

Review the affected `.gd`, `.tscn`, `.tres`, and `project.godot` files together. Do not install or generate an external code graph for this repository.

## Runtime Validation

1. Confirm the Godot editor is open with the CUSGA project loaded.
2. Use `project_run(mode="custom", scene="res://...")` for the changed scene and the main scene when relevant.
3. Read `logs_read(source="game")`; treat script parse errors, failed loads, and runtime errors as blockers.
4. Use `game_eval`, `test_run`, or `editor_screenshot` for focused assertions and visual checks.
5. Stop the game with `project_manage(op="stop")`. Leave the editor open.

The editor MCP is the source of truth for dynamic scene wiring, autoload behavior, and runtime resource loading.
