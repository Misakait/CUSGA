# Reusable resource gathering cards design

## Current Evidence

- `GatheringInteraction.BuildOps` 当前负责一次性采集：`PassTimeOp(TimeCost)`、`MarkHarvestedOp()`、按 `DropTable.RollLoot(extraYield)` 掉落、`CheckGatheringEncounterOp(GatheringTag)`、最后 `RemoveSourceCardOp()`。
- `TerrainInstance` 当前保留房间内地形状态：位置、地形数据、是否已采集、成长阶段等。`RoomTerrainStore` 会按房间和局部格子复用同一个 `TerrainInstance`，适合作为可重复资源点的状态归属。
- `RoomBoardPresenter` 当前有 `HideHarvestedTerrain`，会跳过 `terrain.IsHarvested` 的地形卡。新资源卡不能用 `IsHarvested` 表示冷却耗尽，否则会被隐藏。
- `BoardCardView` 当前只有 `Title`、`Amount`、`Icon`、`CollisionShape2D`，点击时立即发出 `Clicked` 信号，没有进度条或禁用态。
- `ToolData` 当前已有 `TargetGatheringTag` 和 `YieldGrowth`，但没有减少采集时间的字段；部分 `items/tool/*.tres` 当前仍是 `ItemData`，只靠 `ItemTags` 参与装备槽位兜底。
- `EquipmentComponent` 当前用装备槽位保存 `ItemStack`，并已有按标签计算采集额外产量的 `GetGatheringYieldBonus(StringName gatheringTag)`。

## Architecture

新增独立的可重复采集交互，避免改变旧 `GatheringInteraction` 的一次性语义。

Recommended C# additions:

- `ReusableGatheringInteraction : TerrainInteraction`
  - `GatheringTag`
  - `DropTable`
  - `MaxHarvestCount`
  - `RefreshTimeCost`
  - `MinimumTimeCost`
  - `EffectiveToolSlot`
- `TerrainInstance` state fields for reusable gathering:
  - `RemainingHarvestCount`
  - `RefreshReadyTotalTime`
  - optional helpers such as `IsGatheringDepleted`.
- `ToolData`
  - add `GatheringTimeReduction`, measured in game time points.
- `EquipmentComponent`
  - add a slot-specific lookup such as `GetGatheringTimeReduction(StringName gatheringTag, EquipmentSlot slot)`.
  - lookup must read only the configured slot, then verify the equipped item is `ToolData` and its `TargetGatheringTag` matches.
- `BoardCardView`
  - add a compact `ProgressBar` child for hold progress.
  - add methods/signals for hold progress and visual enabled/disabled state.
- `WorldInteractionCoordinator`
  - keep immediate click behavior for loot and old terrain interactions.
  - for `ReusableGatheringInteraction`, start a hold session instead of executing immediately.
  - on hold completion, execute the reusable gathering operation.

## Data Flow

```
TerrainCardData.InteractionBehavior
  -> WorldInteractionCoordinator detects interaction type
  -> ReusableGatheringInteraction calculates effective game-time cost
  -> BoardCardView displays hold progress for effective seconds
  -> hold complete
  -> TerrainInteractionExecutor applies ops
  -> TimeSystem.PassTime(finalCost)
  -> DropTable.RollLoot(existing yield bonus path)
  -> SpawnLootOp + CheckGatheringEncounterOp
  -> decrement TerrainInstance remaining count
  -> exhausted state updates BoardCardView gray/non-interactive
  -> TimeSystem.TimeChanged or room re-entry refreshes when total time reaches RefreshReadyTotalTime
```

## Time And Hold Conversion

The interaction should define one conversion constant or exported setting for game time points to real hold seconds. For the first version, use the user-approved mapping:

- 20 game time points -> 2 seconds.
- Therefore 10 game time points -> 1 second.

Implementation can express this as `seconds = effectiveTimeCost / 10.0f`. The final game time cost remains an integer and is charged once on completion.

Effective cost:

```
effective = max(MinimumTimeCost, TimeCost - equipmentReduction)
```

The equipment reduction is read only from the configured equipment slot and only if the equipped tool targets the same `GatheringTag`.

## State And Refresh

Reusable resource state belongs to the terrain instance, not the card view. The view is recreated when entering rooms, while `RoomTerrainStore` keeps room terrain instances.

Refresh should be lazy and event-driven:

- Before spawning a terrain card for a room, refresh reusable terrain if `TimeSystem.TotalTimePassed >= RefreshReadyTotalTime`.
- Before starting a hold interaction, refresh the same way.
- While the player remains in a room, subscribe to time changes or trigger a refresh pass after time-consuming interactions so exhausted visible cards can restore without requiring room re-entry.

When a resource is depleted:

- set remaining count to 0.
- set `RefreshReadyTotalTime = TimeSystem.TotalTimePassed + RefreshTimeCost`.
- update the card view to gray and non-interactive.
- do not call `RemoveSourceCardOp`.
- do not set `IsHarvested`, because existing room presentation uses it to hide old harvested terrain.

## Compatibility

- Old `GatheringInteraction` stays unchanged unless a small shared helper is extracted for loot/encounter duplication. Any helper extraction must preserve old op order and old removal behavior.
- Existing terrain resources can continue pointing to `GatheringInteraction`.
- New reusable resources can be added as separate `.tres` examples.
- Existing item tags remain valid for equipping tools, but tools that need time reduction must use `ToolData` so the numeric reduction can be configured.

## UI Contract

- `BoardCardView` remains the owner of visual card feedback: progress bar, gray disabled state, input blocking.
- World/gameplay code owns whether a card can be interacted with and how long the hold takes.
- The progress bar should be hidden by default, visible only while holding, and reset to 0 on cancel or completion.
- Disabled cards should keep their icon/title visible but gray, and should not start a hold session.

## Risks

- Changing `BoardCardView` input can regress loot card click pickup and old terrain card click interactions. Keep existing `Clicked` behavior intact unless tests are updated to cover replacement behavior.
- Existing `HideHarvestedTerrain` can accidentally hide reusable resources if `IsHarvested` is reused. Use new state fields instead.
- Godot resource migration can be noisy. Limit `.tres` edits to the sample resources needed for validation.
- Some tool `.tres` files currently use `ItemData`; converting every tool is broader than this feature. Convert only required sample tools unless the implementation shows broader conversion is necessary.

## Rollback Shape

The feature can be rolled back by:

- Removing new reusable interaction resources and sample `.tres` wiring.
- Reverting `BoardCardView` progress/disabled additions.
- Reverting new reusable state fields and equipment time reduction methods.
- Existing `GatheringInteraction` should remain valid throughout, so old terrain cards keep working even if reusable resources are disabled.
