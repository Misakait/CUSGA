# Reusable resource gathering cards implementation plan

## Pre-Edit Checks

- Read relevant specs before code edits:
  - `.trellis/spec/backend/gameplay-system-patterns.md`
  - `.trellis/spec/backend/resource-data-guidelines.md`
  - `.trellis/spec/backend/testing-guidelines.md`
  - `.trellis/spec/backend/quality-guidelines.md`
  - `.trellis/spec/frontend/component-guidelines.md`
  - `.trellis/spec/frontend/state-management.md`
  - `.trellis/spec/frontend/quality-guidelines.md`
- Before editing C# symbols, run GitNexus impact analysis and report HIGH or CRITICAL risk:
  - `TerrainInstance`
  - `TerrainInteraction`
  - `EquipmentComponent`
  - `ToolData`
  - `BoardCardView`
  - `WorldInteractionCoordinator`
  - `RoomBoardPresenter` if refresh-on-time or spawn refresh touches it.
- Use CodeGraph for C# structure. Use `rg` and direct file reads for `.tscn`, `.tres`, and `.gd`.

## Implementation Steps

1. Add reusable gathering data/state contracts.
   - Add `ReusableGatheringInteraction`.
   - Add reusable harvest counters and refresh timestamp to `TerrainInstance`.
   - Add helper methods if needed to initialize, deplete, and refresh reusable state.

2. Add equipment time reduction.
   - Add `GatheringTimeReduction` to `ToolData`.
   - Add slot-specific `EquipmentComponent` lookup that checks:
     - configured slot only.
     - item is `ToolData`.
     - `TargetGatheringTag` matches resource `GatheringTag`.
   - Keep existing `GetGatheringYieldBonus` behavior for drop quantity compatibility.

3. Add reusable gathering execution.
   - Build ops that pass final effective time, spawn drops, check gathering encounter, and update remaining count.
   - Do not remove source card for reusable resources.
   - Do not set `IsHarvested` for reusable depletion.
   - Preserve old `GatheringInteraction` behavior.

4. Add hold progress UI to `BoardCardView`.
   - Add `ProgressBar` to `scenes/board_card_scene/BoardCardView.tscn`.
   - Add methods to start/cancel/complete hold progress.
   - Add disabled visual state with gray color and input blocking.
   - Keep loot and old terrain click pickup behavior intact.

5. Wire reusable interaction in `WorldInteractionCoordinator`.
   - On card press/click for reusable terrain, calculate effective game time and hold seconds.
   - Start hold progress instead of immediate execution.
   - On successful hold completion, execute reusable gathering.
   - On early release, cancel and reset progress.

6. Add refresh handling.
   - Refresh reusable terrain before card spawn and before interaction.
   - Refresh visible exhausted cards when game time changes while the player remains in the room.
   - Ensure room re-entry preserves remaining counts and cooldown through `RoomTerrainStore`.

7. Add sample resources for verification.
   - Add or modify a minimal sample reusable resource card.
   - Convert only the sample effective tool resource to `ToolData` if needed.
   - Configure examples for tree/axe and/or mineral/pickaxe behavior.

8. Add focused tests.
   - C# tests for effective time calculation, slot-specific tool matching, minimum time clamp, remaining count depletion, refresh restoration.
   - Godot test or scene smoke for `BoardCardView` progress/disabled state if practical.
   - Regression coverage that old `GatheringInteraction` still removes source card.

## Validation Commands

- Build solution:
  ```bash
  env CI=true dotnet build CUSGA.sln --no-restore
  ```
- Build C# test runner:
  ```bash
  env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
  ```
- Run C# test runner if GodotSharp resolves in the environment:
  ```bash
  env CI=true dotnet run --no-restore --project tests/CUSGA.Tests/CUSGA.Tests.csproj
  ```
- Refresh Godot C# and global classes:
  ```bash
  godot-mono --headless --path . --build-solutions --quit
  ```
- Run focused board card runtime test:
  ```bash
  godot-mono --headless --path . --script res://tests/godot/board_card_view_tests.gd
  ```
- Smoke-test main scene if scene/resources are edited:
  ```bash
  godot-mono --headless --path . --scene res://scenes/Main.tscn --quit-after 5
  ```

## Review Gates Before `task.py start`

- User reviews and approves `prd.md`, `design.md`, and `implement.md`.
- No blocking product questions remain.
- Implementation starts only after `python3 ./.trellis/scripts/task.py start 06-09-reusable-resource-gathering-cards`.

## Rollback Points

- After C# data/state changes but before scene edits.
- After `BoardCardView` UI changes but before wiring long-hold execution.
- After sample resources, because `.tres` changes may include generated UID/resource noise.
