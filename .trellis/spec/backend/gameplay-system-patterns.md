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

### Reusable Gathering Terrain Cards

Reusable resource cards use a `TerrainInteraction` subclass instead of the one-shot `GatheringInteraction` flow. The interaction resource owns the designer contract:

- `TimeCost`: base game-time cost for one completed harvest.
- `GatheringTag`: resource type used for encounter checks and matching tool bonuses.
- `MaxHarvestCount`: number of harvests available before cooldown.
- `RefreshTimeCost`: game-time cooldown after the count reaches zero.
- `MinimumTimeCost`: lower bound after equipment reductions.
- `EffectiveToolSlot`: the only equipment slot allowed to reduce this resource's hold time.

Runtime state belongs on `TerrainInstance`, not on the interaction resource, so multiple terrain cards can share one interaction asset:

- `RemainingGatheringCount`: `-1` means uninitialized; initialize from `MaxHarvestCount`.
- `RefreshReadyTotalTime`: total game time when a depleted card becomes usable again.

`BuildOps` for reusable gathering must include `PassTimeOp`, loot spawning, optional `CheckGatheringEncounterOp`, and a small record-state op. It must not add `RemoveSourceCardOp` or mark `IsHarvested`; depleted cards stay in their board cell, become disabled/gray in the card view, and refresh in place when `TimeSystem.TotalTimePassed` reaches `RefreshReadyTotalTime`.

Hold duration is derived from game-time cost at `10` game-time points per second. Equipment reduction is slot-gated and tag-gated: only the configured `EffectiveToolSlot` is queried, and the equipped `ToolData.TargetGatheringTag` must exactly match the resource `GatheringTag`. Cancelled holds do not consume time or grant drops; the progress resets and the interaction is only executed when the hold completes.

Tests for a new reusable gathering resource should assert:

- configured-slot tools reduce effective time, while other-slot tools do not;
- effective time never falls below `MinimumTimeCost`;
- depletion and refresh are based on game time and restore harvest count to full;
- the op list does not remove the source card;
- 全局鼠标圆环展示长按进度，且资源卡在冷却时禁用输入。

### 局外统一长按交互

#### 1. Scope / Trigger

当局外地图中的交互会消耗行动值（移动、采集、耕种、宝库或首领）时，必须通过 `WorldHoldInteractionController` 延迟执行原有业务逻辑。这样可避免每种目标各自维护 Tween、取消状态和输入反馈；行动值为零的掉落拾取等即时交互不得被强制等待。

#### 2. Signatures

```csharp
public const float WorldInteractionTiming.GameTimePointsPerHoldSecond = 10.0f;
public static float WorldInteractionTiming.GetHoldDurationSeconds(int actionPointCost);
public void WorldHoldInteractionController.BeginHold(Node owner, int actionPointCost, Callable onCompleted, Node progressTarget);
public void WorldHoldInteractionController.CancelHoldFor(Node owner);
public void WorldHoldInteractionController.CancelActiveHold();
public void WorldHoldProgressIndicator.SetHoldProgress(float progress);
public void WorldHoldProgressIndicator.SetHoldProgressTarget(Node target);
public void WorldHoldProgressIndicator.ClearHoldProgress();
public void WorldInteractionCoordinator.BeginWorldHoldForMap(Node owner, int actionPointCost, Node progressTarget);
public void WorldInteractionCoordinator.CancelWorldHoldFor(Node owner);
[Signal] public delegate void WorldHoldCompletedEventHandler(Node owner);
```

```gdscript
world_interaction_coordinator.connect(
	&"WorldHoldCompleted",
	Callable(self, "_on_world_hold_completed")
)
world_interaction_coordinator.call("BeginWorldHoldForMap", self, action_point_cost, hold_progress_target)
world_interaction_coordinator.call("CancelWorldHoldFor", self)
```

#### 3. Contracts

- 时长只由实际行动值计算：`seconds = max(0, actionPointCost) / 10.0`。不添加额外最短或最长时长；默认移动 `10` 点为 `1.0` 秒，默认地形 `20` 点为 `2.0` 秒。
- `owner` 是唯一活动长按的归属者。开始新请求必须取消旧请求；目标的松开只能取消它自己拥有的请求，全局鼠标松开或场景退出可无条件取消。
- `WorldHoldProgressIndicator` 只画目标右下角圆环，使用 `MouseFilter.Ignore`，不得拦截输入、扣除行动值或直接调用 `TerrainOp`。精灵使用自身可见矩形右下角、`Control` 使用自身尺寸右下角，并通过屏幕变换处理世界相机与 CanvasLayer；默认偏移为 `0px, 0px`，使圆心位于角点而约四分之一圆环位于目标内；目标缺失时才回退到鼠标位置。
- `WorldHoldInteractionController.ProgressIndicatorPath` 必须提供与主场景结构一致的非空默认值；场景可覆盖该路径，但不能把“场景文本写了导出属性”当作运行时已经注入的证据。控制器 `_Ready` 遇到空路径时必须恢复同一默认值并记录警告，随后验证目标类型；目标缺失或类型错误时抛出包含实际路径的错误。
- `onCompleted` 只能在进度满后调用；控制器必须在调用前先清空 Tween、owner 和圆环，避免回调重入导致重复结算。
- `ReusableGatheringInteraction` 在开始时快照工具减免后的有效时间，并将同一数值作为 `TerrainInteractionExecutor.Execute(..., effectiveTimeCostOverride)` 的覆盖值，以保证等待时长和实际扣除一致。
- `WorldInteractionCoordinator` 负责将正行动值棋盘地形接入控制器，并为 `map_button.gd` 提供 `BeginWorldHoldForMap` / `CancelWorldHoldFor` 与 `WorldHoldCompleted(owner)` 跨语言门面；地图脚本不得依赖该协调器内部子节点路径。地图读取 `TimeSystem.MapMoveTimeCost` 时应使用 `Object.get`，再以 `Variant` 转为整数。地图必须在按下前连接完成信号并快照目标坐标及实际可见的方向按钮精灵；不得将 GDScript `Callable` 作为参数经 `Object.call` 传给 C#，该封送路径可能退化为 `null::null`。`map_button.gd` 负责使用 `button_down` 开始、`button_up` 取消，并在完成信号中沿用既有驻守战斗、过场与移动流程。

#### 4. Validation & Error Matrix

| 条件 | 控制器或调用方行为 | 结果 |
| --- | --- | --- |
| 行动值 `<= 0` | 不创建 Tween，立即调用回调 | 零耗时交互保持单击即时响应 |
| 鼠标提前松开 | owner 调用 `CancelHoldFor` | 圆环隐藏，不执行回调、不消耗行动值 |
| 释放发生在目标范围外 | `WorldInteractionCoordinator._UnhandledInput` 调用 `CancelActiveHold` | 不留下后台 Tween 或延迟采集 |
| 新目标开始按住 | `BeginHold` 先取消旧请求 | 同一时刻只可能结算一个局外交互 |
| 场景或 owner 已失效 | 控制器退出时取消，完成前检查 owner 有效性 | 旧场景不会在新场景后执行回调 |
| HUD 场景导出值未反序列化或为空 | 控制器 `_Ready` 恢复与主场景一致的非空默认路径并记录警告 | 圆环与完成回调仍可正常初始化 |
| HUD 目标缺失或类型错误 | 控制器 `_Ready` 抛出包含实际路径的配置错误 | 尽早暴露场景配置错误，而不是后续点击时无反馈 |
| GDScript `Callable` 经 `Object.call` 进入 C# | 地图不传递 Callable；协调器以 C# `Callable.From` 发出 `WorldHoldCompleted(owner)` | 进度填满后能可靠进入地图移动协程 |
| 目标为地图按钮或地形卡 | 地图传递可见按钮精灵，地形传递 `Icon` 精灵 | 圆环稳定显示在目标右下角，约四分之一位于目标内，不随鼠标漂移 |

#### 5. Good / Base / Bad Cases

- Good：玩家按住默认树木 `2.0` 秒，圆环完成后才生成掉落、结算 `20` 点时间并记录资源点状态。
- Base：玩家按住默认地图方向 `1.0` 秒，完成后才进入原有驻守战斗与淡出移动协程。
- Bad：方向按钮仍连接 `pressed`，或卡牌在按下时直接执行 `TerrainInteractionExecutor.Execute`。这会绕过取消路径，使短按仍然消耗行动值。

#### 6. Tests Required

- C# 运行器覆盖 `0`、`10`、`20` 和负行动值的秒数换算，断言分别为 `0.0`、`1.0`、`2.0` 和 `0.0`。
- `tests/godot/world_hold_interaction_tests.gd` 覆盖圆环默认隐藏、零偏移、目标右下角锚点、设置进度后的可见性与复位，以及取消 `10` 点长按后 `1.1` 秒内回调仍为零次。
- 同一测试必须实例化控制器脚本并断言 `ProgressIndicatorPath` 的运行时默认值非空且指向主场景 HUD；仅检查 `.tscn` 文本中的属性赋值不能覆盖反序列化失败。
- 地图长按回归测试必须模拟 `BeginWorldHoldForMap(owner, cost, progressTarget)` 与 `WorldHoldCompleted(owner)`，并断言方向目标在完成信号到达后才进入原有移动协程、且可见方向按钮会作为圆环锚点。
- `tests/godot/board_card_view_tests.gd` 断言棋盘卡不再包含旧的 `HoldProgress` 线性条，并保留禁用状态断言。
- 场景接线检查必须确认四个地图方向按钮使用成对的 `button_down` / `button_up`，没有遗留 `pressed` 直接移动连接。

#### 7. Wrong vs Correct

```gdscript
# 错误：业务逻辑在按下时立即执行，之后再显示进度无法阻止行动值消耗。
func _on_up_button_button_down() -> void:
	await _try_move_to(_target_for_direction(0))
```

```gdscript
# 正确：圆环完成回调才启动原有移动协程，松开会先取消该 owner 的请求。
func _on_up_button_button_down() -> void:
	_begin_move_hold(0)

func _on_direction_button_button_up() -> void:
	_cancel_move_hold()
```

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

Treat stack and inventory notifications as two different contracts:

- `ItemStack.OnStackChanged` is the immediate, slot-level update for controls already bound to that stack reference.
- `InventoryChanged` is the inventory-level synchronization point for structure, aggregate counts, crafting, and other observers.
- A public single-stack transfer emits one source and one target `InventoryChanged` notification after mutation.
- A batch transfer keeps per-stack events immediate, suppresses repeated inventory-level notifications inside the loop, and emits one source and one target notification only when at least one item moved.
- Evaluate caller-supplied batch predicates before the first mutation. If a predicate throws, the method must not leave an internally-created partial batch that observers never received through `InventoryChanged`.

Batch-transfer regression tests must assert moved quantities, no notification for a no-op batch, one notification per inventory for a successful batch, predicate-failure atomicity, and any special capacity invariant such as the battle deck's trailing empty slot.

Equipment operations duplicate stacks when moving between systems and apply/remove attribute and tag effects at equip/unequip boundaries. If a new system moves item stacks, preserve copy/duplicate semantics so UI references and inventory slots do not accidentally alias each other.
