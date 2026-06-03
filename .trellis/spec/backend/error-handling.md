# Error Handling

CUSGA uses Godot runtime diagnostics plus `Try*`/`Can*` methods for recoverable gameplay failures. There is no HTTP response or exception-mapping layer.

## Recoverable Gameplay Checks

Use `Can*` and `Try*` pairs when a player action can fail as part of normal gameplay:

- `EquipmentComponent.CanEquipStack`, `CanEquipFromInventory`, `EquipFromInventory`, `CanMoveEquipment`, and `MoveEquipment`.
- `InventoryComponent.TrySetStackAt`, `TryClearStackAt`, and `AddItem` returning the amount that did not fit.
- `CraftingService.TryCraft` returning `false` plus `CraftingFailureReason`.
- `Player.TryAddItemToInventory` returning whether the whole stack fit.

When adding a new user action, prefer this shape over throwing. The caller should be able to update UI or leave state unchanged.

## Failure Reason Enums

Use an explicit failure enum when UI needs to show a specific outcome. `CraftingFailureReason` is the current pattern: `CraftingUI` maps it to Chinese status text after `CraftingComponent.TryCraft`.

Only add a new enum when callers need to distinguish failure cases. Simple invalid moves can return `false`.

## Godot Diagnostics

Use `GD.PushError` for broken bindings or invalid runtime state that prevents the requested operation, such as missing `GlobalWarehouseInventory`, null skill context, or missing `WorldInteractionCoordinator`.

Use `GD.PushWarning` for degraded but survivable conditions, such as missing optional status handling, unknown stack policy, or falling back when configured data is absent.

Use `GD.Print` for gameplay trace output that already appears throughout systems like interaction, encounters, status, and battle. Keep new print messages focused on state transitions or debugging evidence.

## Exceptions

Throw only for required configuration that should be fixed in the scene/editor before runtime, as in `GameplayPort._Ready` and `HUDController._Ready` when exported `NodePath` values are empty.

Use `ArgumentNullException.ThrowIfNull` at internal boundaries where null would indicate a caller bug, such as `TerrainInteractionExecutor.OnBoardCardClicked` and `EnterVaultOp.Apply`.

## State Safety

Preserve the local pattern that validation happens before mutation. `CraftingService.TryCraft` checks recipe validity, materials, and post-consumption output space before removing items. `EquipmentComponent` duplicates stacks before moving equipment between inventory and equipment slots.

Avoid partial mutation on failure. If a new operation must touch multiple systems, either validate all preconditions first or add focused tests proving rollback behavior.
