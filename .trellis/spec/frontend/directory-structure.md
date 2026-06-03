# Directory Structure

CUSGA's scene/UI layer is split between C# `Control` classes, GDScript scene scripts, Godot scenes, autoloads, and editor plugins.

## Scene And Script Areas

- `scenes/` contains `.tscn` scene files. Main gameplay, battle, inventory, warehouse, crafting, map, skill card, and UI scenes live here.
- `scripts/` contains GDScript scene logic. Current subareas include battle, cards, map, UI, animation, warehouse, generated enum files, and small reusable components.
- `core/ui/` contains C# UI controls and presenters that bind to gameplay components.
- `core/autoloads/` contains C# and GDScript autoload scripts referenced from `project.godot`.
- `addons/` contains editor plugins, including `skill_targeting_type_codegen`.
- `tests/godot/` contains Godot headless runtime test scripts.
- `scripts/generated/` contains generated GDScript output. Do not hand-edit generated files.

## Autoloads

`project.godot` currently registers these autoloads:

- `GlobalEventBus`
- `TimeSystem`
- `WeatherManager`
- `ItemsControl`
- `GlobalWarehouse`
- `SceneManager`
- `ScreenTransitions`

When adding a feature that needs global access, first check whether one of these existing autoloads already owns the state or signal. Add a new autoload only when there is no local owner and no existing global owner.

## Scenes And Node Paths

C# UI and gameplay scripts generally use exported `NodePath` fields or stable child names:

- `GameplayPort` exports paths for player, inventory, battle deck, health, crafting, and warehouse.
- `WorldInteractionCoordinator` exports board, gameplay, encounter, map, HUD, and transition paths.
- `InventoryUI` uses unique-name lookups such as `%SlotGrid`, `%EquipmentSlotGrid`, and `%CloseButton`.
- GDScript map scripts use `@onready` paths for sibling systems and `get_node_or_null("/root/...")` for autoloads.

When changing scenes, update the script path assumptions and add a Godot runtime check if the path is part of a tested flow.

## Avoid

- Do not introduce React terms such as hooks, props, routes, or CSS modules into this project.
- Do not store gameplay rules only in `.tscn` files when a C# `Resource`, `Component`, or service already owns that concept.
- Do not edit `scripts/generated/SkillTargetingType.gd` manually.
