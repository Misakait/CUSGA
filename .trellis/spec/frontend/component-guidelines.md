# Component Guidelines

Godot UI and scene components use a mix of C# `Control` classes and GDScript scripts. Follow the existing Godot lifecycle and binding patterns.

## C# UI Controls

Use C# `Control` classes when the UI binds tightly to C# gameplay components.

Current examples:

- `InventoryUI` binds `InventoryComponent`, `EquipmentComponent`, and `BattleDeckComponent`, generates slot views once, then rebinds on inventory/equipment/deck changes.
- `CraftingUI` binds `CraftingComponent`, builds recipe buttons dynamically, refreshes ingredient rows, and maps `CraftingFailureReason` to status text.
- `SlotUI` and `EquipmentSlotUI` implement Godot drag/drop overrides and update visuals from `ItemStack.OnStackChanged`.

Pattern:

1. Resolve child controls and exported paths in `_Ready`.
2. Bind gameplay components through explicit `Bind*` methods.
3. Disconnect old component signals before rebinding.
4. Regenerate child view nodes only when capacity or slot count changes.
5. Use `QueueFree` for generated child controls.
6. Hide tooltips and unsubscribe stack events in `_ExitTree`.

## Drag And Drop

Inventory/equipment drag data is carried by `DraggableData`. UI controls should call component-level `Can*` methods in `_CanDropData` and component-level mutation methods in `_DropData`.

Do not duplicate inventory/equipment rules in UI code. `SlotUI` delegates to `InventoryComponent.CanReceiveItemFrom` and `MoveItemFrom`; `EquipmentSlotUI` delegates to `EquipmentComponent.CanEquipFromInventory`, `EquipFromInventory`, `CanMoveEquipment`, and `MoveEquipment`.

## GDScript Scene Scripts

Use GDScript when the behavior is primarily scene control, pointer input, animation, map buttons, battle turn flow, or editor tooling.

Current examples:

- `map_button.gd` handles direction buttons, passage guard checks, fade transitions, and map move time.
- `passage_guard_controller.gd` owns guard state, guard roll probability, and async battle requests.
- `battle_manager.gd` owns the battle state machine and delegates C# combat skill execution after target resolution.
- `card_manager.gd` owns card dragging, target highlighting, and input gating during player turns.

Prefer exported fields and `@onready` references for scene dependencies. Guard optional dependencies with null checks and `has_method`/`has_signal` before calling across a dynamic boundary.

## Tooltips

The current tooltip patterns are:

- C# item slots use `ItemTooltipPresenter`.
- `Monster.cs` searches the `tooltip_panel` group and falls back to a valid panel.
- `HoverTooltipComponent.gd` can auto-connect to parent `Control`, `Area2D`, or custom hover signals.

For new tooltip behavior, reuse these patterns instead of introducing a second global tooltip system.
