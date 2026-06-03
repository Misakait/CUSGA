# Quality Guidelines

These rules apply to Godot scenes, GDScript, C# UI controls, and cross-language integration.

## GDScript Style

Follow the existing GDScript style:

- Use typed variables and return types when practical.
- Use `@export`, `@export_group`, and `@onready` for scene dependencies.
- Use `StringName` signal names with `&"signal_name"` where the current code does.
- Keep explanatory comments in Chinese.
- Use `push_error` for missing required scene dependencies and `push_warning` for degraded fallbacks.

## Scene Safety

When adding or changing scene scripts:

- Check required exported paths and autoloads.
- Use `get_node_or_null` for optional dependencies.
- Disconnect signals in `_exit_tree` when the script created the connection.
- Consider synchronous signal emission before awaiting. The passage guard controller connects before requesting combat because C# may emit the result immediately.
- Smoke-test changed scenes when practical.

## Generated Files

Do not hand-edit generated files under `scripts/generated/`. Change the source C# enum or generator, then run:

```bash
godot-mono --headless --path . --script res://tests/godot/skill_targeting_type_codegen_tests.gd
```

## Runtime Validation

For GDScript, scenes, resources, C# `[GlobalClass]` changes, autoload access, or scene/runtime integration, use Godot headless validation:

```bash
godot-mono --headless --path . --build-solutions --quit
godot-mono --headless --path . --check-only --script res://path/to/changed_script.gd
godot-mono --headless --path . --script res://tests/godot/passage_guard_tests.gd
godot-mono --headless --path . --scene res://scenes/Main.tscn --quit-after 5
```

Run only the focused Godot tests that match the changed area, plus build-solutions when C# resources/global classes changed.

## Do Not Generalize Beyond Current Examples

Do not add web accessibility, React hook, CSS, browser routing, or server-state requirements. The current UI is Godot UI and card/scene interaction. If a future feature introduces a new UI framework, create a new spec from actual code at that time.
