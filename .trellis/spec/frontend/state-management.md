# State Management

Godot node ownership, autoloads, resources, and signals are the project's state management tools. There is no Redux, React state, server cache, or URL state layer.

## Local Node State

Keep state local when it belongs to one scene or component:

- `InventoryUI` tracks whether inventory, equipment, and deck slot views have been initialized.
- `EquipmentSlotUI` tracks the current equipment slot, stack, and pointer-inside state.
- `card_manager.gd` tracks the dragged card, drag offset, and highlighted entities.
- `battle_manager.gd` tracks battle state, action queue, and active entity.

Local state should be reset or disconnected in `_ExitTree` when it references external nodes, signals, or stack events.

## Component State

Reusable gameplay state belongs in C# components under an entity:

- `InventoryComponent` owns slots and emits `InventoryChanged`.
- `EquipmentComponent` owns equipped items and emits `EquipmentChanged`.
- `AttributeComponent` owns raw/effective attributes and recalculation queues.
- `StatusComponent` owns active statuses and hook processing.
- `VitalComponentBase` owns current/max health-like values and emits value/depleted signals.

UI should bind to these components rather than storing parallel gameplay state.

## Autoload State

Use existing autoloads for global state and cross-scene events:

- `TimeSystem` owns day/night, current day, time progress, and map move cost.
- `GlobalEventBus.gd` declares broad gameplay signals.
- `GlobalWarehouse` provides the global warehouse scene/inventory.
- `ScreenTransitions` owns fade transitions used by map movement and combat presentation.

Do not add a new global singleton for feature-local state. Start with local scene/component ownership, then escalate to an existing autoload only when multiple unrelated scenes need the state.

## Signals

Signals are the primary synchronization mechanism between state owners and presentation:

- Components emit changes (`InventoryChanged`, `EquipmentChanged`, `ValueChanged`, `StatusChanged`, `AttributeChanged`).
- `GameplayPort` converts input requests into UI/gameplay signals.
- `passage_guard_controller.gd` emits `guard_state_changed` after guard state changes.
- `WorldInteractionCoordinator` emits `PassageGuardEncounterFinished` after passage guard combat.

Connect before triggering operations that may emit synchronously. `passage_guard_controller.gd` explicitly connects to `PassageGuardEncounterFinished` before calling `RequestPassageGuardEncounter`.

## Resources As Configuration State

Godot `Resource` objects are configuration, not mutable runtime stores, unless a class explicitly models runtime state. `TerrainInstance` and `ItemStack` are runtime-like `RefCounted` objects; `ItemData`, `CombatSkillData`, `MonsterData`, recipes, and settings are editable content data.
