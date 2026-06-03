# Godot Scene And UI Specs

This layer covers Godot scenes, GDScript, C# UI controls, autoload-facing scripts, editor plugins, and cross-language UI/combat glue. It is called `frontend` by Trellis scaffolding, but this is not a web frontend.

## Guides

| Guide | Use when |
|---|---|
| [Directory Structure](./directory-structure.md) | Choosing where scenes, GDScript, UI controls, generated scripts, and plugins belong. |
| [Component Guidelines](./component-guidelines.md) | Adding C# `Control`/UI classes, GDScript scene scripts, or reusable UI helper components. |
| [State Management](./state-management.md) | Working with Godot autoloads, exported paths, signals, local node state, and scene flow. |
| [Type Safety](./type-safety.md) | Crossing between C#, GDScript, generated enums, wrapper nodes, and resource types. |
| [Quality Guidelines](./quality-guidelines.md) | Validating GDScript, scenes, UI, generated files, and runtime integration. |

## Current Evidence Base

- Godot project config: `project.godot`.
- C# UI examples: `core/ui/InventoryUI.cs`, `core/ui/crafting/CraftingUI.cs`, `core/ui/SlotUI.cs`, `core/ui/EquipmentSlotUI.cs`.
- GDScript examples: `scripts/map_scripts/passage_guard_controller.gd`, `scripts/map_scripts/map_button/map_button.gd`, `scripts/battle_scripts/battle_manager.gd`, `scripts/card_scripts/card_manager.gd`.
- Cross-language generation: `addons/skill_targeting_type_codegen/skill_targeting_type_codegen.gd`, `scripts/generated/SkillTargetingType.gd`.
- Runtime tests: `tests/godot/*.gd`.
