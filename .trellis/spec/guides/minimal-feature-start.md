# Minimal Feature Start

Use this before starting the next feature task in CUSGA. The goal is to start small and load only the specs supported by current code examples.

## Task Creation

Do not create a Trellis task silently. Ask for consent first.

For a small feature touching one system, create a PRD-only task unless the user asks for deeper planning. For a feature touching multiple systems, write `prd.md`, `design.md`, and `implement.md` before starting implementation.

## First Scan

Identify the feature slice:

- C# gameplay/runtime: read backend directory, gameplay system, resource data, testing, and quality specs.
- Godot UI/GDScript/scene flow: read frontend directory, component, state, type safety, and quality specs.
- Cross-language combat or enum work: read both backend gameplay specs and frontend type-safety specs.

Use CodeGraph for C# symbols. Use native search/read for `.gd`, `.tscn`, `.tres`, and generated GDScript because CodeGraph currently indexes C# only.

If GitNexus reports stale data, run:

```bash
npx gitnexus analyze
```

## Before Editing

Before changing any C# symbol, run GitNexus impact analysis for the target symbol and report risk if it is HIGH or CRITICAL.

Before changing GDScript or scenes, find the script's scene/runtime callers with `rg` and pick the smallest Godot headless check that exercises that path.
Do not use GitNexus or CodeGraph to look up symbols in GDScript, as neither tool supports the GDScript language.

Keep collaborator-owned GDScript changes narrow. If the task is mainly diagnosis or the user says not to change friend-authored `.gd` code, report findings instead of editing those files.

## Minimal Implementation Shape

Prefer the existing local extension point:

- New terrain interaction: `TerrainInteraction.BuildOps` plus small `TerrainOp` classes.
- New combat card effect: `CardEffect` subclass and `CombatSkillData` resource wiring.
- New status/buff: `StatusEffectData` plus `StatusEffectInstance` hook override.
- New item/equipment data: `Resource` class or `.tres` content using existing tags, slots, and display fallbacks.
- New UI flow: bind UI to an existing component or `GameplayPort` signal.
- New map/battle GDScript behavior: preserve existing state-machine and signal-ordering patterns.

Do not introduce a new framework, database, global singleton, test framework, or generic architecture layer unless the current task explicitly requires it and the design explains why existing patterns cannot support it.

## Minimal Verification

Always build with `CI=true`:

```bash
env CI=true dotnet build CUSGA.sln --no-restore
```

Add focused validation based on changed files:

- C# runner build: `env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore`
- C# runner execution when GodotSharp resolves: `env CI=true dotnet run --no-restore --project tests/CUSGA.Tests/CUSGA.Tests.csproj`
- GDScript or scene runtime: `godot-mono --headless --path . --build-solutions --quit`
- Passage/map flow: `godot-mono --headless --path . --script res://tests/godot/passage_guard_tests.gd`
- Combat multi-hit/status bridge: `godot-mono --headless --path . --script res://tests/godot/multi_hit_damage_tests.gd`
- Skill targeting enum bridge: `godot-mono --headless --path . --script res://tests/godot/skill_targeting_type_codegen_tests.gd`
