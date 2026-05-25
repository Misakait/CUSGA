# Passage Guard Monsters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the night-only guarded passage system described in `docs/superpowers/specs/2026-05-24-passage-guard-monsters-design.md`.

**Architecture:** Keep passage guard rules in testable C# core services, keep Godot scene/script integration in thin map adapters, and route battle entry through the existing world combat presenter. The guarded passage table stores occupied undirected edges only; per-room monster arrays are resolved from `map_attribute` encounter pools when buttons render.

**Tech Stack:** Godot 4.6 C#, GDScript map scripts, `env CI=true dotnet build` for compile validation, and `godot-mono --headless` runners for behavior that touches Godot runtime types. Do not treat plain `dotnet test` as behavior evidence in this project.

---

## File Structure

- Create `core/map/PassageGuardEdge.cs`: value object that normalizes an undirected map edge.
- Create `core/map/PassageGuardState.cs`: owns the current night guarded-edge set.
- Create `resources/map/PassageGuardSettings.cs`: Godot resource for global base chance, home-protection tag, and modifiers.
- Create `resources/map/PassageGuardProbabilityModifier.cs`: Godot resource for tag-gated additive and multiplicative chance effects.
- Create `resources/map/PassageGuardEncounterData.cs`: Godot resource containing one `Array<MonsterData>` encounter.
- Create `core/map/PassageGuardProbabilityProvider.cs`: calculates final chance with `(base + additiveSum) * multiplierProduct`.
- Create `core/map/PassageGuardMonsterResolver.cs`: caches per-room edge-to-encounter results.
- Create `scripts/map_scripts/passage_guard_controller.gd`: GDScript adapter that listens to `TimeSystem`, rolls edges from current map topology, resolves encounters, and coordinates guarded movement.
- Modify `resources/map/map_attribute.gd`: export `guard_encounter_pool`.
- Modify `scripts/map_scripts/map_button/map_button.gd`: render guard names on passage buttons and intercept guarded movement.
- Modify `core/gameflow/WorldCombatScenePresenter.cs`: add a combat method that resolves when battle ends.
- Modify `core/gameflow/WorldInteractionCoordinator.cs`: expose a guard encounter method and signal for GDScript.
- Modify `scenes/map_scenes/map_control.tscn`: add `PassageGuardController` node.
- Create `tests/godot/passage_guard_tests.gd`: executable Godot headless tests for state, chance, resolver stability, and the C#/GDScript result-wait protocol.

---

### Task 1: Core Passage Guard Tests

**Files:**
- Modify: `tests/CUSGA.Tests/Program.cs`
- Create later: `core/map/PassageGuardEdge.cs`
- Create later: `core/map/PassageGuardState.cs`

- [ ] **Step 1: Write failing tests**

Add tests that prove normalized edges are undirected, victory clears both directions, and dawn clears all state:

```csharp
tests.PassageGuardStateTreatsEdgesAsUndirected();
tests.PassageGuardStateClearsDefeatedAndDawnEdges();
```

- [ ] **Step 2: Run tests and verify RED**

Run: `env CI=true dotnet test tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore`

Expected: compile failure because `PassageGuardState` does not exist.

- [ ] **Step 3: Implement minimal core state**

Create `PassageGuardEdge` and `PassageGuardState` with `AddGuard`, `IsGuarded`, `ClearGuard`, and `ClearAll`.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `env CI=true dotnet test tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore`

Expected: all current tests and the new passage state tests pass.

### Task 2: Probability and Tag Modifiers

**Files:**
- Modify: `tests/CUSGA.Tests/Program.cs`
- Create: `resources/map/PassageGuardSettings.cs`
- Create: `resources/map/PassageGuardProbabilityModifier.cs`
- Create: `core/map/PassageGuardProbabilityProvider.cs`

- [ ] **Step 1: Write failing tests**

Add tests for `final = clamp((base + additiveSum) * multiplierProduct, 0, 1)` and tag-gated modifiers.

- [ ] **Step 2: Run tests and verify RED**

Run: `env CI=true dotnet test tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore`

Expected: compile failure because probability classes do not exist.

- [ ] **Step 3: Implement resources and provider**

Create `PassageGuardSettings`, `PassageGuardProbabilityModifier`, and `PassageGuardProbabilityProvider`. The provider accepts a `TagComponent` and only applies modifiers whose `RequiredTag` is empty or present.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `env CI=true dotnet test tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore`

Expected: all tests pass.

### Task 3: Encounter Pool and Resolver

**Files:**
- Modify: `tests/CUSGA.Tests/Program.cs`
- Create: `resources/map/PassageGuardEncounterData.cs`
- Create: `core/map/PassageGuardMonsterResolver.cs`
- Modify later: `resources/map/map_attribute.gd`

- [ ] **Step 1: Write failing tests**

Add tests proving the resolver returns the same monster array for the same room edge until `BeginRoom()` is called again, then can resolve again.

- [ ] **Step 2: Run tests and verify RED**

Run: `env CI=true dotnet test tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore`

Expected: compile failure because encounter resolver classes do not exist.

- [ ] **Step 3: Implement encounter data and resolver**

Create `PassageGuardEncounterData` with `Array<MonsterData> Monsters`. Create `PassageGuardMonsterResolver` with room-scoped cache and injected deterministic index picker for tests.

- [ ] **Step 4: Run tests and verify GREEN**

Run: `env CI=true dotnet test tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore`

Expected: all tests pass.

### Task 4: Combat Result Bridge

**Files:**
- Modify: `core/gameflow/WorldCombatScenePresenter.cs`
- Modify: `core/gameflow/WorldInteractionCoordinator.cs`

- [ ] **Step 1: Add tests if practical**

No unit test is planned because this depends on live Godot scene instantiation and battle signals. Coverage comes from keeping the new public method as a thin wrapper around existing presenter behavior and verifying compilation.

- [ ] **Step 2: Implement result-returning combat path**

Add `EnterCombatAndWaitForResultAsync` to `WorldCombatScenePresenter`. Add `PassageGuardEncounterFinished(bool isVictory)` signal and `RequestPassageGuardEncounter(Array<MonsterData> monsters)` to `WorldInteractionCoordinator`.

- [ ] **Step 3: Run build**

Run: `env CI=true dotnet build CUSGA.sln --no-restore`

Expected: build succeeds.

### Task 5: Map Adapter Integration

**Files:**
- Create: `scripts/map_scripts/passage_guard_controller.gd`
- Modify: `resources/map/map_attribute.gd`
- Modify: `scripts/map_scripts/map_button/map_button.gd`
- Modify: `scenes/map_scenes/map_control.tscn`

- [ ] **Step 1: Add map adapter**

Create a GDScript controller that owns the runtime `PassageGuardState`, listens to `TimeSystem.DayNightToggled`, rolls unique undirected edges from `scene_to_scene`, uses `map_attribute.guard_encounter_pool` for current map type encounters, and awaits `WorldInteractionCoordinator.PassageGuardEncounterFinished`.

- [ ] **Step 2: Connect buttons**

Update `map_button.gd` so visible direction buttons ask the controller for guard encounters. Guarded buttons display monster names; unguarded buttons restore normal direction labels and icons.

- [ ] **Step 3: Connect scene**

Add `PassageGuardController` as a child of `MapControl` and let `map_button.gd` find it by sibling path. Export `guard_encounter_pool` from `map_attribute`.

- [ ] **Step 4: Run build and tests**

Run: `godot-mono --headless --path . --script res://tests/godot/passage_guard_tests.gd`

Run: `env CI=true dotnet build CUSGA.sln --no-restore`

Expected: Godot runtime tests and C# build pass.

### Task 6: Final Scope Check

**Files:**
- Review: `docs/superpowers/specs/2026-05-24-passage-guard-monsters-design.md`
- Review: `docs/superpowers/plans/2026-05-24-passage-guard-monsters.md`

- [ ] **Step 1: Run GitNexus change detection**

Run GitNexus `detect_changes(scope: "all")` and confirm affected flows match map passage guard, combat entry, and test changes.

- [ ] **Step 2: Verify full requested scope**

Check each spec bullet against implementation: night lifecycle, undirected edges, home exclusion by tag, global configurable chance, additive/multiplicative modifiers, per-map encounter pools, multiple names, victory-only movement, and dawn clear.

- [ ] **Step 3: Report residual risk**

Report any behavior that cannot be automatically verified, especially GDScript UI layout and real battle-scene interaction.
