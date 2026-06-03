# 多段伤害与随机分段目标设计规格

## 背景

当前技能卡由 `SkillCardData` 包装 `CombatSkillData`，`CombatSkillData` 决定技能元素、目标类型和效果列表，具体伤害由 `DamageEffect` 执行。现有模型已经能表达单体、全体、随机单体和扩散目标，但随机目标在 `battle_manager.gd` 创建 `SkillExecutionContext` 时只会选出一次。

新需求包含两类能力：

- 伤害段数：例如一张技能造成 5 次 10 点伤害。
- 分段随机：例如一张技能造成 5 次 10 点伤害，每一段都实时从随机敌人中重新选择目标，允许重复命中同一目标。

此外，需要支持伤害效果相关 Buff：

- 持续型段数 Buff：例如施法者获得一个状态后，状态持续期间伤害牌的段数增加 2，使原本 5 段的伤害按 7 段结算。
- 限次攻击牌 Buff：例如施法者获得一个状态后，接下来 1 张或 2 张攻击牌的每段基础伤害增加 10；若该牌本来是 5 段伤害，则 5 段全部增加 10。
- 限次攻击牌段数 Buff：例如施法者获得一个状态后，接下来 N 张攻击牌的段数增加 2，并在影响足够数量的攻击牌后消耗。

## 已确认规则

### 段数语义

- 每一段伤害都是一次完整独立的伤害事件。
- 5 段伤害会调用 5 次 `DamageReceiverComponent.ReceiveDamage()`。
- 每段都会独立触发闪避、暴击、护盾、状态 Hook、吸血、生命扣除和日志。
- 因此 `5 x 10` 和 `1 x 50` 是不同机制，不只是表现上的多跳数字。

### 字段归属

- `SkillCardData` 不增加伤害段数字段。
- `CombatSkillData` 不增加伤害段数字段。
- `DamageEffect` 增加段数与分段目标策略字段。
- 原因是段数是伤害效果自己的结算方式，不是卡牌物品壳，也不是整个技能的重复执行次数。

### 目标类型边界

- `SkillTargetingType` 继续只表达“释放技能时如何选目标”。
- 不新增 `RandomEnemyPerHit` 等组合型目标枚举。
- “每段是否重新随机”属于 `DamageEffect` 的目标分配策略，避免目标枚举膨胀。

### 分段随机

- 分段随机每一段都会重新选择目标。
- 允许多段重复命中同一个目标。
- 随机候选池在技能开始时锁定。
- 中途补出来的新怪不进入本次技能的候选池。
- 每段选择前，只从锁定候选池中重新过滤仍有效的目标。
- 如果候选池内目标全部死亡，剩余段数直接跳过，不报错，不退化为攻击自己，也不攻击新刷出的怪物。

### 有效目标判定

随机每段选择目标时，目标必须满足：

- Godot 实例仍有效。
- 节点没有进入 `queue_free` 等待删除状态。
- 目标存在 `Components/HealthComponent`。
- `HealthComponent.CurrentValue > 0`。

现有 `MonsterManager.active_monsters` 会在怪物生命归零时从场上列表移除怪物，`Monster.HandleDeath()` 也会 `QueueFree()`。但多段伤害可能在同一次技能执行期间跨越死亡事件，因此执行时仍需要对候选池做上述双保险过滤。

## 推荐架构

### `DamageEffect`

`DamageEffect` 负责伤害段数和每段目标策略。

建议新增字段：

```csharp
[Export] public int HitCount { get; set; } = 1;

[Export] public DamageHitTargetMode HitTargetMode { get; set; }
    = DamageHitTargetMode.ContextTargets;
```

建议新增枚举：

```csharp
public enum DamageHitTargetMode
{
    ContextTargets,
    RandomCandidatePerHit
}
```

语义：

- `ContextTargets`：每一段都使用 `TargetScope` 从 `SkillExecutionContext.Targets` 中选择目标。
- `RandomCandidatePerHit`：每一段从 `SkillExecutionContext.CandidateTargets` 中过滤有效目标后随机抽取一个目标。

本版 `RandomCandidatePerHit` 只用于敌方候选池，不支持随机友方、随机所有单位或随机次目标。配置该模式时，`TargetScope` 不参与每段目标选择，资源上仍建议保持 `PrimaryOnly` 以减少误解。

`HitCount` 的运行时有效值必须钳制到非负整数。`HitCount <= 0` 时不造成伤害。

### `SkillExecutionContext`

`SkillExecutionContext` 需要同时携带“本次已选目标”和“技能开始时锁定的候选池”。

建议新增属性：

```csharp
public Array<Node> CandidateTargets { get; }
```

建议所有工厂方法支持传入候选池，或提供重载：

- `Self(source, candidates)`
- `FromSingleTarget(source, target, candidates)`
- `FromPrimaryTargets(source, targetNodes, candidates)`
- `FromSpread(source, primaryTarget, secondaryTargets, candidates)`

`Targets` 继续表示效果默认命中的主目标/次目标。`CandidateTargets` 表示技能开始时由战斗场景传入的可随机目标池，不在 `DamageEffect` 内部查找场景树。

### `battle_manager.gd`

`battle_manager.gd` 继续负责：

- 判断施法者阵营。
- 收集当前敌人列表。
- 解包 GDScript 包装节点，得到真实 C# 战斗实体。
- 创建 `SkillExecutionContext`。
- 把技能开始时的候选池传入 `SkillExecutionContext`。

示例规则：

- `SingleEnemy`：`Targets = [选中的主目标]`，`CandidateTargets = 当前敌人池`。
- `RandomEnemy`：先从当前敌人池抽出主目标，`Targets = [主目标]`，`CandidateTargets = 当前敌人池`。
- `AllEnemies`：`Targets = 当前敌人池`，`CandidateTargets = 当前敌人池`。
- `SpreadFromEnemy`：`Targets = 主目标 + 相邻次目标`，`CandidateTargets = 当前敌人池`。
- `Self`：`Targets = [施法者]`，`CandidateTargets` 可为空或当前敌人池；`RandomCandidatePerHit` 不应配置给自我目标效果。

### 随机数边界

- 分段目标随机由 `DamageEffect` 使用局部 `RandomNumberGenerator` 处理。
- 不直接使用 `GD.Randf()` 或 `GD.Randi()`。
- 目标选择随机与 `DamageReceiverComponent` 内部的闪避、暴击、随机浮动分离。
- `DamageReceiverComponent` 仍然负责每段伤害进入接收者后的伤害公式随机。

## 段数 Buff 设计

### 目标

需要支持施法者状态对伤害段数进行运行时修正。持续型段数 Buff 示例：

```text
当前 DamageEffect.HitCount = 5
施法者拥有“后续伤害段数 +2”状态
本次 DamageEffect 有效段数 = 7
```

限次段数 Buff 示例：

```text
当前 DamageEffect.HitCount = 5
施法者拥有“接下来 2 张攻击牌段数 +2”状态
接下来第 1 张攻击牌执行时，该 DamageEffect 有效段数 = 7
接下来第 2 张攻击牌执行时，该 DamageEffect 有效段数 = 7
第 2 张攻击牌完整执行后，该状态被消耗
```

### 边界

- Buff 不直接修改 `DamageEffect.HitCount` 资源字段。
- Buff 只修改本次执行的有效段数。
- 段数 Buff 只作用于资源配置 `DamageEffect.HitCount > 1` 的多段伤害。
- 段数 Buff 不会把 `DamageEffect.HitCount = 1` 的单段伤害变成多段伤害。
- 状态结束后，后续技能自动回到资源配置段数。
- 段数修正属于施法者状态，不属于防御方状态。
- 段数修正在 `DamageEffect` 进入 hit loop 前计算一次，不在每段伤害内部重复计算。
- 限次段数 Buff 不能在段数修正 Hook 内立即移除，否则多段伤害或同一张牌内后续 `DamageEffect` 可能吃不到完整效果。
- 限次段数 Buff 只有在本张技能中实际修正过至少一个多段 `DamageEffect` 后才扣减次数；单段攻击牌不会消耗限次段数 Buff。

### 推荐 Hook

现有状态系统的伤害 Hook 都发生在 `DamageReceiverComponent.ReceiveDamage()` 内部，粒度是“单段伤害已经开始结算”。段数 Buff 需要发生在 `DamageEffect` 开始循环前，因此不应复用 `OnModifyOutgoingDamage()`。

建议新增一个执行前 Hook：

```csharp
public virtual void OnModifyDamageHitCount(
    DamageEffectHitCountContext context,
    ref int hitCount
) { }
```

建议新增状态阶段：

```csharp
ModifyDamageHitCount
```

建议新增上下文：

```csharp
public sealed class DamageEffectHitCountContext
{
    public Node Source { get; }
    public SkillExecutionContext SkillContext { get; }
    public DamageEffect Effect { get; }
    public int BaseHitCount { get; }
}
```

`DamageEffect.Execute()` 的流程应为：

1. 读取资源配置 `HitCount`。
2. 从 `context.Source` 查找 `StatusComponent`。
3. 调用施法者状态的 `ProcessModifyDamageHitCount()`。
4. 将结果钳制为 `>= 0`。
5. 按有效段数进入 hit loop。

### 推荐 Buff 数据类

可以新增 `HitCountModifierStatusData` 和 `HitCountModifierStatusInstance`。

建议字段：

```csharp
[Export] public int FlatHitCountBonusPerStack { get; set; } = 0;
```

本版只做固定段数加成：

```text
if HitCount > 1:
    effectiveHitCount = HitCount + FlatHitCountBonusPerStack * CurrentStacks
else:
    effectiveHitCount = HitCount
```

例如 `FlatHitCountBonusPerStack = 2` 且当前 1 层，就使 5 段变成 7 段。
如果 `HitCount = 1`，则仍然只造成 1 段伤害，并且不会消耗限次段数 Buff。

暂不做百分比段数修正、按元素筛选、按伤害类型筛选等复杂规则。需要这些能力时再扩展上下文字段和状态数据。

### 状态持续时间与消费

本版段数 Buff 复用现有 `StatusEffectData` 的持续时间和层数系统：

- 可以配置 `MaxStacks`。
- 可以配置 `StackPolicy`。
- 可以配置 `InitOwnerTurnDuration`、`InitGlobalTurnDuration`、`InitRoundDuration`。
- 持续型状态只要仍在施法者身上，施法者执行的 `DamageEffect` 就会被修正。
- 限次状态可以同时拥有持续时间；如果在持续时间内没有执行足够数量的符合条件攻击牌，则按正常持续时间过期。

## 限次攻击牌 Buff 设计

### 目标

需要支持影响接下来 N 张攻击牌，并在足够数量的攻击牌完整执行后消耗的 Buff。例如：

```text
施法者拥有“接下来 2 张攻击牌每段基础伤害 +10”
第 1 张攻击牌是 5 段伤害
第 1 张攻击牌 5 段每一段的 DamagePayload.Damage 都增加 10
第 2 张攻击牌完整执行后，该 Buff 被消耗
```

### 攻击牌定义

本版不依赖 `SkillCardData.CardTags` 判断攻击牌，避免把技能执行逻辑耦合到卡牌物品包装层。

本版把“攻击牌”定义为：

```text
施法者执行的 CombatSkillData 中，Effects 至少包含一个 DamageEffect。
```

这个定义同时适用于玩家技能卡和怪物技能。没有 `DamageEffect` 的纯 Buff、纯治疗、纯护盾技能不会触发或消耗限次攻击牌类状态。

### 执行边界

限次攻击牌 Buff 必须以“整张技能/卡牌执行”为作用域：

- 在 `CombatSkillData.Execute()` 开始执行效果前，开启一次技能执行作用域。
- 技能内所有 `DamageEffect` 都在该作用域内读取施法者状态修正。
- 技能内所有段数和所有分段伤害都能享受该作用域中的一次性 Buff。
- 在 `CombatSkillData.Execute()` 完成所有 `Effects` 后，再统一扣减标记为本次已使用状态的剩余攻击牌次数。
- 不在 `DamageEffect` 的单段循环中移除状态。
- 不在 `DamageReceiverComponent.ReceiveDamage()` 中移除状态。

这样可以保证“接下来 N 张攻击牌伤害 +10”会作用于每张攻击牌的全部段数，而不是第一段伤害后就被扣减或消耗。

### 推荐技能执行 Hook

建议在状态系统新增技能执行作用域 Hook：

```csharp
public virtual void OnBeforeSkillExecution(
    SkillExecutionModifierContext context
) { }

public virtual void OnAfterSkillExecution(
    SkillExecutionModifierContext context
) { }
```

建议新增状态阶段：

```csharp
BeforeSkillExecution
AfterSkillExecution
```

建议新增上下文：

```csharp
public sealed class SkillExecutionModifierContext
{
    public Node Source { get; }
    public CombatSkillData Skill { get; }
    public SkillExecutionContext SkillContext { get; }
    public bool HasDamageEffect { get; }
    public bool IsAttackSkill => HasDamageEffect;

    public void MarkStatusForConsumption(StringName statusId);
}
```

`StatusComponent` 应负责在 `AfterSkillExecution` 后统一处理被标记消费的状态。消费应作为一次小型事务处理：先完成技能效果执行，再移除或扣减状态，最后发出状态变化通知。

### 限次状态消费规则

限次攻击牌状态的推荐规则：

- 只有 `IsAttackSkill == true` 的技能会触发并消费。
- 非攻击技能不会触发，不消费。
- 每张攻击牌最多扣减 1 次剩余次数，即使该技能内有多个 `DamageEffect` 或多个伤害段。
- 扣减发生在整张攻击牌执行结束后。
- 限次段数 Buff 只有在本张攻击牌里实际修正过多段 `DamageEffect` 时才扣减；只包含单段伤害的攻击牌不扣减。
- `RemainingAttackSkillUses` 扣到 0 后移除状态。
- 如果状态有多层，本版推荐所有当前层数都参与每次攻击牌修正；层数不改变剩余攻击牌次数。
- 如果未来需要“每层各自拥有剩余次数”，再新增更复杂的层级计数模型，不在本版复杂化。

### 下一张攻击牌基础伤害加成

“接下来 N 张攻击牌每段基础伤害 +10”应作用在 `DamageEffect` 生成 `DamagePayload` 前，而不是使用现有 `OnModifyOutgoingDamage()`。

原因：

- `OnModifyOutgoingDamage()` 发生在 `DamageReceiverComponent.ReceiveDamage()` 内部，已经进入单段伤害公式流程。
- 限次攻击牌 Buff 需要覆盖整张技能中的所有段数，并在技能结束后统一扣减剩余次数。
- “每段基础伤害 +10”应表现为每段 `DamagePayload.Damage` 增加 10，再进入后续伤害公式和接收者 Hook。

具体时机：

- 先由 `DamageEffect.CalculateDamageForTarget()` 计算本段准备造成的 payload damage。
- 再调用施法者状态的分段基础伤害修正 Hook。
- 最后使用修正后的 damage 创建 `DamagePayload`。

因此本版的“每段伤害 +10”不是最终扣血值强行 +10，而是每段进入 `DamageReceiverComponent` 前的 `DamagePayload.Damage` 增加 10。

建议新增执行前伤害段上下文：

```csharp
public sealed class DamageEffectSegmentContext
{
    public Node Source { get; }
    public SkillExecutionContext SkillContext { get; }
    public DamageEffect Effect { get; }
    public SkillEffectTargetSelection Target { get; }
    public int HitIndex { get; }
    public int EffectiveHitCount { get; }
}
```

建议新增施法者状态 Hook：

```csharp
public virtual void OnModifyDamageEffectSegmentDamage(
    DamageEffectSegmentContext context,
    ref int damage
) { }
```

对应 `StatusComponent` 方法：

```csharp
ProcessModifyDamageEffectSegmentDamage(context, ref damage)
```

该 Hook 修改的是 `DamageEffect` 本段准备写入 `DamagePayload.Damage` 的值。结果仍需钳制为 `>= 0`。

### 推荐限次 Buff 数据类

可以新增独立数据类，也可以通过现有段数 Buff 数据类增加消费配置。为了保持职责清晰，本规格推荐先分开：

- `HitCountModifierStatusData`：负责持续或一次性的段数修正。
- `NextAttackDamageBonusStatusData`：负责接下来 N 张攻击牌的每段基础伤害修正。

`HitCountModifierStatusData` 建议增加：

```csharp
[Export] public int FlatHitCountBonusPerStack { get; set; } = 0;
[Export] public int AttackSkillUses { get; set; } = 0;
```

`NextAttackDamageBonusStatusData` 建议字段：

```csharp
[Export] public int FlatSegmentDamageBonusPerStack { get; set; } = 0;
[Export] public int AttackSkillUses { get; set; } = 1;
```

`AttackSkillUses` 语义：

- `0` 表示不按攻击牌次数消耗，作为持续型状态使用。
- `1` 表示影响接下来 1 张攻击牌。
- `2` 表示影响接下来 2 张攻击牌。

示例：

```text
接下来 2 张攻击牌每段基础伤害 +10
FlatSegmentDamageBonusPerStack = 10
AttackSkillUses = 2
```

```text
下一张攻击牌段数 +2
FlatHitCountBonusPerStack = 2
AttackSkillUses = 1
```

```text
持续期间所有攻击牌段数 +2
FlatHitCountBonusPerStack = 2
AttackSkillUses = 0
```

## 执行流程

### 固定目标多段

```text
DamageEffect.Execute(context)
  effectiveHitCount = CalculateEffectiveHitCount(context)
  repeat effectiveHitCount times:
    selectedTargets = SkillEffectTargetScopeUtility.SelectTargets(context, TargetScope)
    foreach selectedTarget:
      ApplyDamageToNode(source, selectedTarget.Unit, damage)
```

示例：

```text
BaseDamage = 10
HitCount = 5
HitTargetMode = ContextTargets
TargetScope = PrimaryOnly
```

结果：对主目标造成 5 次独立的 10 点基础伤害。

### 每段随机目标

```text
DamageEffect.Execute(context)
  effectiveHitCount = CalculateEffectiveHitCount(context)
  repeat effectiveHitCount times:
    validCandidates = FilterAliveCandidates(context.CandidateTargets)
    if validCandidates empty:
      break hit loop
    target = PickRandom(validCandidates)
    ApplyDamageToNode(source, target, damage)
```

示例：

```text
CombatSkillData.TargetingType = RandomEnemy
BaseDamage = 10
HitCount = 5
HitTargetMode = RandomCandidatePerHit
```

结果：技能开始时锁定当时敌人池；每段从仍存活的锁定敌人里随机抽 1 个，允许重复。

## 与现有资源和工具的关系

- 当前 `card_table/export_current_cards.py` 由单独维护者负责，本规格不要求修改该工具。
- 现有导出工具目前只生成或更新 `CombatSkillData` 基础字段，并保留 `Effects` 子资源。
- 多段伤害字段先作为 `DamageEffect` 子资源上的 Inspector 配置项处理。
- 如果未来需要卡表批量配置段数，再由卡表维护者把 `HitCount` 和 `HitTargetMode` 加入效果表或对应导入流程。

## 延期能力

### 0 血继续命中与濒死状态

本版不支持继续命中 0 血目标。剩余段数在候选池无有效目标时跳过。

未来如果需要“爽感型继续打完所有段数”或“超杀表现”，应先引入明确的濒死/待清算状态：

- 目标生命归零后先进入可表现的 pending-death 状态。
- 多段技能结束后再统一移除目标。
- `DamageReceiverComponent`、`HealthComponent`、`MonsterManager` 和表现层都要识别该状态。

不应直接攻击已经 `QueueFree()`、已从 `active_monsters` 移除、或生命为 0 且无待清算语义的节点。

### 更复杂的段数与一次性修正

本版支持固定段数加成、限次攻击牌段数加成、限次攻击牌每段基础伤害加成。以下能力延期：

- 按元素筛选段数加成。
- 按物理/法术/真实伤害筛选段数加成。
- 百分比段数修正。
- 对每个 `DamageEffect` 只生效一次后消耗层数。
- 对整个技能的总段数做全局上限。
- 每层各自拥有独立剩余攻击牌次数。
- 根据 `SkillCardData.CardTags` 判断攻击牌类型。

## 测试关注点

- `HitCount = 5` 时，对固定目标调用 5 次 `ReceiveDamage()`。
- 每段伤害独立进入 `DamageReceiverComponent`，不会合并成一次大伤害。
- `HitTargetMode = ContextTargets` 时，每段使用 `TargetScope` 选目标。
- `HitTargetMode = RandomCandidatePerHit` 时，每段从 `CandidateTargets` 选择目标。
- 随机每段允许重复命中同一目标。
- 中途死亡目标不会继续成为有效候选。
- 中途补出的新怪不会进入本次技能候选池。
- 候选池全部死亡后，剩余段数跳过且不报错。
- `HitCountModifierStatusData` 能把 5 段修正为 7 段。
- `HitCountModifierStatusData` 不会把 1 段伤害修正为多段伤害。
- 单段攻击牌不会消耗限次段数 Buff，后续多段攻击牌仍可使用该 Buff。
- 段数 Buff 不修改 `DamageEffect.HitCount` 资源值。
- 段数 Buff 叠层时按 `FlatHitCountBonusPerStack * CurrentStacks` 生效。
- 段数 Buff 过期后，有效段数恢复为资源配置段数。
- `HitCount <= 0` 或被 Buff 修正到 0 时，不造成伤害。
- 接下来 2 张攻击牌每段基础伤害 +10 时，前 2 张攻击牌每一段写入 `DamagePayload.Damage` 前都增加 10。
- 限次基础伤害 Buff 在整张攻击牌执行结束后扣减 1 次剩余次数，不在第一段伤害后扣减。
- 下一张攻击牌段数 +2 时，5 段伤害按 7 段执行，并在整张攻击牌执行结束后扣减 1 次剩余次数。
- 没有 `DamageEffect` 的非攻击技能不会消耗限次攻击牌类状态。
- 限次状态多层时，本版按所有层数参与本次攻击牌修正；层数不改变剩余攻击牌次数。

## 成功标准

- 设计能表达“5 次 10 点伤害”。
- 设计能表达“5 次 10 点伤害，每段实时随机敌人，允许重复”。
- 设计能避免打到技能释放后才补出来的新怪。
- 设计能避免命中已死亡、已移除或等待删除的节点。
- 设计能支持施法者 Buff 在运行时增加伤害段数。
- 设计能支持“接下来 N 张攻击牌每段基础伤害 +10”，并覆盖每张攻击牌多段伤害的全部段数。
- 设计能支持“接下来 N 张攻击牌段数 +2”，并在每张攻击牌完整执行后扣减一次剩余次数。
- 设计不把段数写入 `SkillCardData`，不污染卡牌物品层。
- 设计不把分段随机扩散到 `SkillTargetingType` 枚举。
