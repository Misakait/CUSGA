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
- `tests/godot/inventory_ui_performance_tests.gd` loads `Main.tscn` to cover inventory slot reuse, sorting rebinds, battle-deck capacity growth, and deferred crafting refresh across ancestor visibility changes.

Use a Godot runner when the behavior depends on GDScript, scene tree timing, C# script loading from `res://`, generated GDScript files, or signal ordering across languages.

> **GodotAI 工具态 C# 静态方法限制**：MCP 的 `McpTestSuite` 在编辑器工具态加载 `.cs` 时，返回对象可能只暴露为 `CSharpScript`，此时生产运行期可用的静态工厂（例如 `SkillExecutionContext.FromSingleTarget`）会报告方法不存在。Resource 迁移测试应在工具态验证 C# Resource 可赋值、方法协议与对象身份，再通过真实 battle/Main 场景验证静态工厂和执行链；不要为迎合工具态而改写生产 C# API，也不得把该工具限制掩盖成通过的断言。

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
godot-mono --headless --path . --script res://tests/godot/inventory_ui_performance_tests.gd
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
