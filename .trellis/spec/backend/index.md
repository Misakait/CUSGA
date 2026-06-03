# C# Gameplay Runtime Specs

This layer covers the C# side of the Godot project: gameplay services, entity components, Godot `Resource` data, combat effects, map/crafting systems, and the C# console-style test runner.

Only use these specs for patterns already demonstrated in the current repository. Do not infer web backend, database, API route, ORM, or server logging conventions for this project.

## Guides

| Guide | Use when |
|---|---|
| [Directory Structure](./directory-structure.md) | Choosing where C# gameplay, component, resource, UI, and test files belong. |
| [Gameplay System Patterns](./gameplay-system-patterns.md) | Adding or changing combat, crafting, interaction, map, inventory, encounter, or time systems. |
| [Resource Data Guidelines](./resource-data-guidelines.md) | Creating or changing Godot `Resource` data classes and `.tres`-backed configuration. |
| [Error Handling](./error-handling.md) | Choosing between `Try*`, failure enums, warnings, errors, and hard configuration exceptions. |
| [Testing Guidelines](./testing-guidelines.md) | Adding C# console runner coverage or choosing Godot runtime runners. |
| [Quality Guidelines](./quality-guidelines.md) | Applying local C# style, docs, comments, impact checks, and validation commands. |

## Current Evidence Base

- Godot/.NET setup: `CUSGA.csproj`, `CUSGA.sln`, `project.godot`.
- Core C# examples: `core/application/GameplayPort.cs`, `core/gameflow/WorldInteractionCoordinator.cs`, `core/gameflow/TerrainInteractionExecutor.cs`.
- Component examples: `entities/components/InventoryComponent.cs`, `entities/components/EquipmentComponent.cs`, `entities/components/AttributeComponent.cs`, `entities/components/StatusComponent.cs`.
- Data examples: `resources/item/ItemData.cs`, `resources/item/card/SkillCardData.cs`, `resources/monster/MonsterData.cs`, `resources/interaction/TerrainInteraction.cs`.
- Tests: `tests/CUSGA.Tests/Program.cs`.
