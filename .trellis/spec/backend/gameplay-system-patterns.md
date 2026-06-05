# Gameplay System Patterns

These are the implementation patterns currently supported by CUSGA examples. Use them as starting points for new feature work.

## Components Under Entities

Entity behavior is decomposed into child components under a stable `Components` node. Examples:

- `Player.cs` resolves health, satiety, energy, equipment, attributes, tags, status, inventory, and battle deck from `Components/...`.
- `Monster.cs` resolves attributes, faction, health, status, loot, and skill components before initializing from `MonsterData`.
- `DamageEffect` and tests expect targets to expose `Components/HealthComponent` and `Components/DamageReceiverComponent`.

For new entity capabilities, prefer adding a focused `Node` component under `entities/components/` and wiring it through the scene, rather than growing `Player` or `Monster` with unrelated state.

## Signals And Lifecycle

Connect Godot signals in `_Ready` after required nodes are resolved, and disconnect in `_ExitTree` when the object owns the connection.

Current examples:

- `Player` subscribes to `SatietyComponent.Depleted`, `HealthComponent.Depleted`, and `GlobalEventBus`.
- `Monster` subscribes to health and mouse-area events, then unsubscribes in `_ExitTree`.
- `InventoryUI` and `CraftingUI` bind to component signals and disconnect when rebinding.
- `StatusComponent` exposes both Godot signals and a C# event for detailed status changes.

Do not leave long-lived signal subscriptions attached to UI or entity instances that can leave the tree.

## Service Classes For Testable Rules

When a rule can be expressed without scene nodes, put it behind a small service or helper and test it directly:

- `CraftingService` works through `ICraftingInventory` and has console-runner tests for material count, output-space simulation, failure reasons, and max quantity.
- `DamageFormula` has direct formula tests for mitigation, critical, evasion, variance, actual damage, and lifesteal.
- `RoomTerrainLayoutGenerator`, `RoomTerrainStore`, and `EncounterMonsterScaler` are tested through deterministic stubs.

Avoid embedding pure calculations only inside UI or scene callbacks.

## Terrain Interaction Ops

Terrain interaction follows a data-to-ops pipeline:

1. A `TerrainInteraction` resource builds an ordered `IReadOnlyList<TerrainOp>` from `TerrainInteractionBuildContext`.
2. `TerrainInteractionExecutor` converts runtime scene dependencies into `WorldInteractionContext` ports.
3. Each `TerrainOp.Apply` calls only the port it needs.

Current operations include pass time, mark harvested, spawn loot, check gathering encounter, remove source card, open warehouse/farming, and request encounters.

When adding a new terrain interaction, keep resource decisions in `BuildOps` and runtime side effects in small `TerrainOp` classes. Do not make resource classes reach directly into scene nodes beyond the supplied context.

## Combat Skills And Status Hooks

Combat effect data is C# resource-driven:

- `CombatSkillData` owns `TargetingType` and an array of `CardEffect`.
- `SkillCardData` is the player card wrapper and delegates actual execution to `CombatSkillData`.
- `CardEffect.Execute` is the extension point for new skill effects.
- `DamageEffect` calculates hit count, target selection, per-segment damage, and sends `DamagePayload` to `DamageReceiverComponent`.
- `StatusComponent` processes ordered hook phases and skips statuses removed earlier in the same hook pass.

For new buffs, create a `StatusEffectData` plus `StatusEffectInstance` pair. Override the narrow hook needed by the effect, and add tests around ordering, stack/duration policy, and consumption rules when relevant.

### Damage Payload Modifier Flags

Use `DamagePayload.DamageModifiers` with `DamageModifierFlags` to control direct-attack modifiers. Do not add one-off booleans for evasion, critical hits, random variance, or lifesteal.

Contracts:

- Plain skill damage should rely on the `DamagePayload` default of `DamageModifierFlags.DefaultCombat`.
- Status or buff damage should expose a resource-level modifier field when designers need configurability; DOT-like damage defaults to `DamageModifierFlags.None`.
- `DamageReceiverComponent.ReceiveDamage` should ask `payload.HasDamageModifier(...)` at each direct-attack modifier step instead of grouping unrelated modifiers behind one branch.
- Status damage modification hooks such as `ProcessModifyOutgoingDamage`, `ProcessModifyIncomingDamageBeforeMitigation`, and `ProcessModifyIncomingDamageAfterMitigation` are not part of the direct-attack modifier set yet. If they become configurable later, extend `DamageModifierFlags` rather than reshaping `DamagePayload`.

Good:

```csharp
payload.HasDamageModifier(DamageModifierFlags.Critical);
```

Bad:

```csharp
payload.AppliesDefaultCombatModifiers;
```

## Inventory And Equipment

Inventory-like systems use `ItemStack` as a mutable stack object with `OnStackChanged`. UI slots bind to stack references and refresh on stack events.

Equipment operations duplicate stacks when moving between systems and apply/remove attribute and tag effects at equip/unequip boundaries. If a new system moves item stacks, preserve copy/duplicate semantics so UI references and inventory slots do not accidentally alias each other.
