# Testing Guidelines

CUSGA currently uses a small custom C# console runner plus focused Godot headless script runners. Do not assume xUnit, NUnit, Playwright, or web test frameworks exist.

## C# Console Runner

The C# test entry point is `tests/CUSGA.Tests/Program.cs`. It manually instantiates `TerrainRandomizationTests`, calls each test method, and prints `All CUSGA tests passed.` when every assertion succeeds.

Local patterns in this runner:

- Use small method-per-behavior tests with descriptive names.
- Keep helper factories and test doubles in the same file unless they become production abstractions.
- Use `RuntimeHelpers.GetUninitializedObject` for Godot resources when tests need data-only stubs without editor construction.
- Use the local `Assert` class (`True`, `False`, `Equal`, `Approximately`, `Same`, `NotSame`).
- Build temporary `Node` trees manually for component integration, such as `Components/HealthComponent`, `DamageReceiverComponent`, and `StatusComponent`.
- Add focused regression tests beside the behavior they protect.

Use this runner for C# gameplay rules, formulas, resource-driven services, and component behavior that can run without a full scene.

## Godot Runtime Script Runners

The current Godot runners inherit `SceneTree`, call `_run` with `call_deferred`, collect failures in `_failures`, and call `quit(0)` or `quit(1)`.

Current files:

- `tests/godot/passage_guard_tests.gd` covers map movement order, passage guard state/probability/resolver, synchronous result signals, and background resolving.
- `tests/godot/skill_targeting_type_codegen_tests.gd` covers the C# enum parser, renderer, regeneration checks, and generated-file sync.
- `tests/godot/multi_hit_damage_tests.gd` mirrors multi-hit combat coverage through Godot runtime loading.

Use a Godot runner when the behavior depends on GDScript, scene tree timing, C# script loading from `res://`, generated GDScript files, or signal ordering across languages.

## Validation Commands

Always include `CI=true` for dotnet build commands in this repo:

```bash
env CI=true dotnet build CUSGA.sln --no-restore
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

Run focused Godot checks when touching GDScript, scenes, resources, C# `[GlobalClass]` types, generated enum bridges, or runtime integration:

```bash
godot-mono --headless --path . --build-solutions --quit
godot-mono --headless --path . --script res://tests/godot/passage_guard_tests.gd
godot-mono --headless --path . --script res://tests/godot/skill_targeting_type_codegen_tests.gd
godot-mono --headless --path . --script res://tests/godot/multi_hit_damage_tests.gd
```

Use the C# runner when the environment can resolve GodotSharp:

```bash
env CI=true dotnet run --no-restore --project tests/CUSGA.Tests/CUSGA.Tests.csproj
```

If `dotnet run` fails only because `GodotSharp` is unavailable outside the Godot runtime, report that as an environment limitation and rely on build plus relevant Godot runners.

## Coverage Expectations

For a new feature, add the smallest test that covers the local pattern being changed:

- Pure calculations or services: C# runner.
- Scene timing, signals, GDScript, autoloads, or generated bridge behavior: Godot runner.
- Resource schema changes that affect editor/runtime loading: Godot build-solutions plus a focused runtime runner.
