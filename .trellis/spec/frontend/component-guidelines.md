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

For inventory-like repeated controls, synchronize bindings and structure incrementally:

- A `Bind` call should return early when the owner, index, and bound model reference are unchanged. Content changes arrive through the model's change event; reference changes caused by sorting must still perform a full unbind/rebind.
- Capacity growth should instantiate only the missing child views, and capacity reduction should remove only surplus views. Do not release and recreate still-valid controls.
- Keep one-time child configuration such as shared tooltip presenters and shortcut handlers on the creation path, then bind the new views in the normal rebind pass.

Long-lived UI may remain subscribed while hidden, but an expensive signal callback that only maintains presentation should guard with `IsVisibleInTree()`. Mark the presentation dirty while hidden, refresh once from current model state when `VisibilityChanged` reports effective visibility again, and let an explicit open path clear the dirty flag after its own complete refresh. This covers both direct `Hide()` calls and ancestor `CanvasLayer`/`CanvasItem` visibility changes. Do not defer gameplay state mutation.

Keep durable Godot runtime tests for structural UI optimizations. Assert stable child instance IDs across ordinary rebinds, preservation of existing child IDs during capacity growth, correct model references after sorting, and deferred refresh after ancestor visibility is restored.

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
