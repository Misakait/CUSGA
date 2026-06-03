# Quality Guidelines

These rules are limited to patterns already visible in the current C# codebase and project instructions.

## Style

- C# uses spaces, four-space indentation, LF line endings, and Allman braces per `.editorconfig`.
- Keep namespaces aligned to folders under `CUSGA`.
- Prefer explicit access modifiers for new C# members.
- Use braces for control flow.
- Use `partial` on Godot C# classes that derive from `Node`, `Control`, or `Resource`.
- Add `[GlobalClass]` only when the class must be available in Godot editor/resource creation.

## Documentation And Comments

Project instructions require XML docs for public classes, methods, and functions, including parameters and return values. Existing code is not fully consistent, but new or changed public C# APIs should follow the requirement.

Write code comments in Chinese. Comments should explain why a guard, ordering rule, or cross-language bridge exists. Good examples include:

- `battle_manager.gd` comments explaining wrapper-node unwrapping before C# skill execution.
- `passage_guard_controller.gd` comments explaining why the result signal is connected before requesting combat.
- `AttributeComponent` comments explaining recalculation queues and status-driven recalculation.

Avoid comments that only restate the next line of code.

## Impact Checks

Before editing any C# symbol, run GitNexus impact analysis for that symbol and report the blast radius. If GitNexus says the index is stale, run `npx gitnexus analyze` first.

CodeGraph currently indexes C# only. Use it for C# symbol lookup, callers, callees, and file structure. Use native search/read tools for `.gd`, `.tscn`, `.tres`, and generated GDScript files.

## Data And State Safety

- Validate before mutating gameplay state.
- Duplicate or copy `ItemStack` when moving between inventory and equipment boundaries.
- Preserve current health/energy when recalculating maxima unless the feature explicitly changes that behavior.
- Keep generated files marked as generated and update the generator or source enum instead of hand-editing generated output.

## Verification

For C# changes, build the solution with:

```bash
env CI=true dotnet build CUSGA.sln --no-restore
```

For Godot runtime integration, also use `godot-mono --headless` as described in [Testing Guidelines](./testing-guidelines.md). Treat `SCRIPT ERROR`, parse errors, failed script loading, and C# build failures as blockers.

Do not run plain `dotnet build` or `dotnet test` in this repo because the project has Husky setup hooks that must be bypassed with `CI=true`.
