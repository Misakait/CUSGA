# Buff / Status 系统使用说明

本文档说明当前项目内 Buff / Status 系统的运行机制、卡牌效果接入方式，以及现有状态数据类的配置方法。

相关代码主要位于：

- `core/combat/status/`：状态系统核心数据、生命周期、叠层、持续时间、属性变化 Hook。
- `core/combat/buffs/`：具体 Buff / Debuff 实现。
- `core/combat/effects/`：卡牌效果，如施加状态、修改属性、护盾效果。
- `entities/components/StatusComponent.cs`：单位身上的状态容器，负责添加、移除、叠层、持续时间扣减和 Hook 分发。
- `entities/components/AttributeComponent.cs`：属性计算组件，会读取状态提供的属性修正。
- `entities/components/DamageReceiverComponent.cs`：受伤组件，会在伤害流程中调用状态 Hook。

---

## 1. 核心概念

### 1.1 StatusEffectData：状态资源配置

所有 Buff / Debuff 的数据资源都继承自 `StatusEffectData`。

常用字段：

| 字段 | 作用 |
| --- | --- |
| `Id` | 状态唯一标识。叠加、刷新、移除都依赖这个值。必须配置，不能留空。 |
| `DisplayName` | UI 显示名。为空时 UI 可回退显示 `Id`。 |
| `Description` | UI 描述文本。建议写清楚效果、持续时间和叠层规则。 |
| `Icon` | Buff 栏图标。 |
| `MaxStacks` | 最大层数。默认 `1`；设置为 `0` 时表示没有层数上限。 |
| `Policy` | 重复施加同 `Id` 状态时的刷新/叠加策略。 |
| `ExpirePolicy` | 多种持续时间同时配置时，如何判断过期。 |
| `DurationTickTiming` | 持续时间在回合/轮次开始还是结束扣减。 |
| `DefaultHookPriority` | 默认 Hook 优先级。数值越小越早执行。 |
| `InitOwnerTurnDuration` | 持续拥有者自己的 N 次行动。 |
| `InitGlobalTurnDuration` | 持续全场 N 次行动，不管是谁行动。 |
| `InitRoundDuration` | 持续 N 轮；一轮由战斗系统判定。 |

> 注意：如果三种持续时间都为 `0`，状态视为无限持续，不会自然过期。

### 1.2 StatusEffectInstance：运行时状态实例

`StatusEffectData` 只负责配置；真正挂到单位身上的对象是 `StatusEffectInstance`。

实例中保存：

- `Data`：对应的数据资源。
- `Id`：来自 `Data.Id`。
- `Source`：状态来源，例如施法者。
- `Owner`：状态拥有者，也就是被挂 Buff 的单位。
- `CurrentStacks`：当前层数，初始为 `1`。
- `OwnerTurnDuration` / `GlobalTurnDuration` / `RoundDuration`：运行时剩余持续时间。
- `AppliedSequence`：施加顺序，用于同优先级排序。

子类可以覆写各种 Hook：

| Hook | 触发时机 |
| --- | --- |
| `OnApply()` | 状态首次添加时。 |
| `OnRemove()` | 状态被移除时。 |
| `OnReapplied(incoming)` | 同 `Id` 状态重复施加时，在叠层前调用。 |
| `OnStackIncreased(currentStacks)` | 成功增加层数后。 |
| `OnStackRemoved(currentStacks)` | 层数因过期等原因减少后。 |
| `OnOwnerTurnStart()` | 拥有者行动开始。 |
| `OnOwnerTurnEnd()` | 拥有者行动结束。 |
| `OnGlobalTurnStart(currentActor)` | 任意单位行动开始。 |
| `OnGlobalTurnEnd(currentActor)` | 任意单位行动结束。 |
| `OnRoundStart()` | 战斗系统判定一轮开始。 |
| `OnRoundEnd()` | 战斗系统判定一轮结束。 |
| `OnBeforeAttributeChange(context)` | 属性最终值提交前，可取消或修改变化。 |
| `OnAfterAttributeChanged(context)` | 属性变化提交后，可触发额外效果。 |
| `OnModifyOutgoingDamage(payload, ref damage)` | 攻击方状态修正伤害。 |
| `OnModifyIncomingDamageBeforeMitigation(payload, ref damage)` | 防御方状态在元素/防御减伤前修正伤害。 |
| `OnModifyIncomingDamageAfterMitigation(payload, ref damage)` | 防御方状态在元素/防御减伤后修正伤害。 |
| `OnBeforeHealthDamage(payload, ref damage)` | 最终扣血前处理，例如护盾、伤害上限。 |
| `GetAttributeModifiers()` | 向属性系统提供动态属性修正。 |

---

## 2. 状态容器 StatusComponent

单位需要挂载 `StatusComponent` 才能拥有 Buff。

主要能力：

- `AddStatus(instance)`：添加状态。
- `RemoveStatus(statusId)`：移除指定状态。
- `ClearAllStatuses()`：清空所有状态。
- `HasStatus(statusId)`：判断是否拥有状态。
- `GetStatusOrNull(statusId)`：获取状态实例。
- `ActiveStatuses`：当前激活状态集合。
- `GetActiveStatusesSnapshot()`：给 GDScript / UI 安全遍历的状态快照。

### 2.1 重复施加同 Id 状态

当新状态 `incoming.Id` 已存在时，`StatusComponent` 会：

1. 根据旧状态的 `Policy` 处理持续时间。
2. 调用旧状态 `existing.OnReapplied(incoming)`。
3. 调用 `existing.TryIncreaseStack()` 尝试增加 1 层。
4. 发出状态变化事件。

### 2.2 StackPolicy 叠加策略

| 策略 | 行为 |
| --- | --- |
| `ResetDuration` | 重复施加时重置持续时间。 |
| `AddDuration` | 重复施加时把新状态的初始持续时间累加到旧状态剩余时间上。 |
| `AddStackOnly` | 重复施加时不改持续时间，只尝试增加层数。 |

> 当前实现中，只要同 `Id` 重复施加，最后都会执行一次 `TryIncreaseStack()`；如果 `MaxStacks > 0` 且已达到 `MaxStacks`，层数不会继续增加；如果 `MaxStacks = 0`，则没有层数上限。

### 2.3 DurationExpirePolicy 过期策略

当配置了多种持续时间时：

| 策略 | 行为 |
| --- | --- |
| `FirstExpired` | 任意一种已配置持续时间到 `0` 即过期。 |
| `AllExpired` | 所有已配置持续时间都到 `0` 才过期；未配置的持续时间视为已满足。 |

### 2.4 DurationTickTiming 扣减时机

| 值 | 行为 |
| --- | --- |
| `Start` | 在行动/轮次开始阶段扣减。默认值。 |
| `End` | 在行动/轮次结束阶段扣减。 |

### 2.5 持续时间和层数过期逻辑

持续时间扣减后，如果状态过期：

1. 如果当前层数大于 `1`，先移除 1 层，并重置持续时间。
2. 如果当前层数已经是 `1`，直接移除状态。

也就是说，多层状态不是一次性完全消失，而是每次过期掉 1 层。

### 2.6 Hook 执行顺序

`StatusComponent` 会按以下规则排序：

1. `status.GetHookPriority(phase)`，数值越小越早执行。
2. `AppliedSequence`，越早施加越早执行。
3. `Id.ToString()`，作为稳定兜底排序。

---

## 3. 伤害流程中的 Buff Hook

`DamageReceiverComponent.ReceiveDamage(payload)` 的伤害处理顺序如下：

1. 读取攻击方属性：
   - 物理伤害：`damage += PhysAtk`，再乘 `1 + PhysDamageBoost`。
   - 魔法伤害：`damage += MagPower`，再乘 `1 + MagicDamageBoost`。
   - 真实伤害：不吃攻击属性加成。
2. 攻击方 `StatusComponent.ProcessModifyOutgoingDamage()`。
3. 防御方 `StatusComponent.ProcessModifyIncomingDamageBeforeMitigation()`。
4. 元素克制倍率。
5. 防御/抗性减伤：
   - 物理伤害读取 `PhysDef`。
   - 魔法伤害读取 `MagResist`。
   - 真实伤害跳过防御减伤。
   - 减伤公式：`100 / (100 + defense)`。
6. 防御方 `StatusComponent.ProcessModifyIncomingDamageAfterMitigation()`。
7. 防御方 `StatusComponent.ProcessBeforeHealthDamage()`。
8. 四舍五入为整数，调用 `HealthComponent.TakeDamage()`。

因此：

- 易伤类想被防御减伤影响，应放在 `OnModifyIncomingDamageBeforeMitigation`。
- 护盾、最终伤害上限应放在 `OnBeforeHealthDamage`。
- 需要攻击方增伤时，应放在 `OnModifyOutgoingDamage`。

---

## 4. 属性流程中的 Buff Hook

`AttributeComponent` 计算最终属性时，会遍历当前 `StatusComponent.ActiveStatuses`，读取每个状态的 `GetAttributeModifiers()`。

最终属性公式：

```text
(baseValue + flatAdd) * (1 + percentAdd) * percentMul
```

其中：

- `baseValue` = 基础值 + 永久 Bonus + 已分配属性点成长。
- `flatAdd`：所有 `FlatAdd` 修正相加。
- `percentAdd`：所有 `PercentAdd` 修正相加。
- `percentMul`：每个 `PercentMul` 按层数连乘，当前实现为 `Pow(1 + ValuePerStack, Stacks)`。

属性变化流程：

1. 属性系统计算尝试变化后的值。
2. 构造 `AttributeChangeContext`。
3. 调用 `StatusComponent.ProcessBeforeAttributeChange()`。
4. 如果没有取消，写入最终值。
5. 发送 `AttributeChanged` 信号。
6. 调用 `StatusComponent.ProcessAfterAttributeChanged()`。

`AttributeChangeContext` 常用字段：

| 字段 / 方法 | 作用 |
| --- | --- |
| `Owner` | 属性拥有者。 |
| `Source` | 变化来源。 |
| `Type` | 属性类型。 |
| `Reason` | 属性变化原因。 |
| `OldValue` | 旧值。 |
| `OriginalNewValue` | 初始尝试新值。 |
| `NewValue` | 可被 Buff 修改的最终候选值。 |
| `Delta` | `NewValue - OldValue`。 |
| `IsIncrease` | 是否增加。 |
| `IsDecrease` | 是否降低。 |
| `Cancel()` | 取消本次属性变化。 |
| `MatchesDirection(direction)` | 判断变化方向是否匹配。 |

---

## 5. 卡牌效果

### 5.1 ApplyStatusCardEffect

路径：`core/combat/effects/ApplyStatusCardEffect.cs`

作用：对目标施加任意 `StatusEffectData`。

导出字段：

| 字段 | 作用 |
| --- | --- |
| `Status` | 要施加的状态资源。必须配置。 |
| `TargetScope` | 目标范围，默认 `AllTargets`。 |

执行逻辑：

1. 检查 `Status` 是否为空。
2. 根据 `TargetScope` 从 `SkillExecutionContext` 选择目标节点。
3. 在目标节点查找 `Components/StatusComponent`。
4. 调用 `Status.CreateInstance(context.Source, target)` 创建实例。
5. 调用 `statusComponent.AddStatus(instance)` 添加状态。

适合用途：

- 给敌人挂灼烧、易伤等 Debuff。
- 给自己或队友挂属性提升、属性保护等 Buff。
- 通过资源配置复用同一个状态逻辑。

注意事项：

- 当前 `ApplyStatusCardEffect` 查找路径是 `Components/StatusComponent`。
- 目标单位节点结构必须匹配这个路径，否则会报错 `Target has no StatusComponent`。

### 5.2 ApplyShieldCardEffect

路径：`core/combat/effects/ApplyShieldCardEffect.cs`

作用：专门施加 `ShieldStatusData`，并使用 `DefaultShieldAmount` 创建护盾实例。

导出字段：

| 字段 | 作用 |
| --- | --- |
| `ShieldStatus` | 护盾状态资源。必须配置。 |
| `TargetScope` | 目标范围，默认 `AllTargets`。 |

执行逻辑：

1. 检查 `context` 和 `ShieldStatus`。
2. 根据 `TargetScope` 选择目标节点。
3. 在目标节点查找 `StatusComponent`。
4. 调用 `ShieldStatus.CreateInstance(context.Source, target, ShieldStatus.DefaultShieldAmount)`。
5. 添加到目标状态容器。

注意事项：

- 当前 `ApplyShieldCardEffect` 查找路径是 `StatusComponent`，不是 `Components/StatusComponent`。
- 如果单位实际组件都放在 `Components/` 子节点下，需要确认节点结构或统一路径。

### 5.3 ModifyAttributeEffect

路径：`core/combat/effects/ModifyAttributeEffect.cs`

作用：直接修改目标 `AttributeComponent` 的永久 Bonus，不是临时 Buff。

导出字段：

| 字段 | 作用 |
| --- | --- |
| `TargetAttribute` | 要修改的属性，默认 `Speed`。 |
| `Amount` | 修改量，默认 `20.0`。正数增加，负数减少。 |
| `TargetScope` | 目标范围，默认 `PrimaryOnly`。 |

执行逻辑：

1. 检查 `context`。
2. 根据 `TargetScope` 选择目标。
3. 在目标单位查找 `Components/AttributeComponent`。
4. 调用 `AddPermanentBonus(TargetAttribute, Amount, context.Source)`。
5. 打印修改后的最终属性值。

适合用途：

- 永久成长、战斗外养成、一次性永久奖励。

不适合用途：

- 临时加速、临时加攻击等有持续时间的 Buff。此类效果应使用 `AttributeModifierStatusData`。

---

## 6. 目标范围 SkillEffectTargetScope

| 值 | 作用 |
| --- | --- |
| `Source` | 效果来源自己。 |
| `AllTargets` | 所有目标。 |
| `PrimaryOnly` | 只选择主要目标。 |
| `SecondaryOnly` | 只选择次要目标。 |

目标从 `SkillExecutionContext.Targets` 中读取。`SkillExecutionContext` 支持：

- `Self(source)`：自己作为主目标。
- `FromSingleTarget(source, target)`：单个目标。
- `FromPrimaryTargets(source, targetNodes)`：多个主目标。
- `FromSpread(source, primaryTarget, secondaryTargets)`：一个主目标 + 多个次目标。

---

## 7. 现有 Buff / Debuff 数据类

## 7.1 AttributeModifierStatusData：属性修正 Buff

路径：

- `core/combat/buffs/AttributeModifierStatusData.cs`
- `core/combat/buffs/AttributeModifierStatusInstance.cs`

作用：通过状态提供动态属性修正。只要状态存在，属性系统就会读取它；状态移除后修正自然消失。

导出字段：

| 字段 | 作用 |
| --- | --- |
| `Modifiers` | `AttributeModifierData` 数组，每项定义一种属性修正。 |

`AttributeModifierData` 字段：

| 字段 | 作用 |
| --- | --- |
| `Type` | 要修正的属性。 |
| `Mode` | 修正模式。 |
| `ValuePerStack` | 每层提供多少修正值。 |

`AttributeModifierMode`：

| 值 | 说明 | 示例 |
| --- | --- | --- |
| `FlatAdd` | 固定值加成。 | 每层 `+10` 速度。 |
| `PercentAdd` | 加算百分比。 | 每层 `+0.2`，最终进入 `1 + percentAdd`。 |
| `PercentMul` | 乘算百分比。 | 每层 `+0.1`，3 层为 `1.1^3`。 |

层数影响：

- 每个 `AttributeModifier` 会携带当前 `CurrentStacks`。
- `FlatAdd` / `PercentAdd` 按 `ValuePerStack * Stacks` 计算。
- `PercentMul` 按 `Pow(1 + ValuePerStack, Stacks)` 计算。

配置建议：

- 临时加属性：配置持续时间，例如 `InitOwnerTurnDuration = 2`。
- 可叠加加属性：设置 `MaxStacks > 1`，并选择合适的 `Policy`；如果需要无限叠层，设置 `MaxStacks = 0`。
- 永久属性变化不要用它，应使用 `ModifyAttributeEffect`。

示例：给自己临时加速

```text
ApplyStatusCardEffect
  TargetScope = Source
  Status = AttributeModifierStatusData
    Id = speed_up
    DisplayName = 加速
    MaxStacks = 3
    Policy = ResetDuration
    InitOwnerTurnDuration = 2
    Modifiers = [
      AttributeModifierData
        Type = Speed
        Mode = FlatAdd
        ValuePerStack = 10
    ]
```

项目内示例：

- `resources/effects/strength.tres`：使用 `ApplyStatusCardEffect` 施加 `AttributeModifierStatusData`。
- `resources/combat_skills/test_card_1.tres`：测试卡使用 `AttributeModifierStatusData` 给自身提高速度。

---

## 7.2 AttributeChangeGuardStatusData：属性变化拦截 Buff

路径：

- `core/combat/status/AttributeChangeGuardStatusData.cs`
- `core/combat/status/AttributeChangeGuardStatusInstance.cs`

作用：在属性变化提交前拦截变化，可取消、缩放变化量、限制最小值/最大值。

导出字段：

| 字段 | 作用 |
| --- | --- |
| `TargetAttribute` | 要监听/拦截的属性。 |
| `Direction` | 拦截方向：任意、增加、降低。 |
| `CancelChange` | 为 `true` 时直接取消本次属性变化。 |
| `DeltaMultiplier` | 对变化量做倍率修正。`0.5` 表示变化减半，`2.0` 表示变化翻倍。 |
| `EnableMinValue` | 是否启用最终值下限。 |
| `MinValue` | 最终值下限。 |
| `EnableMaxValue` | 是否启用最终值上限。 |
| `MaxValue` | 最终值上限。 |

执行逻辑：

1. 只处理 `context.Type == TargetAttribute` 的属性。
2. 只处理变化方向匹配 `Direction` 的变化。
3. 如果 `CancelChange = true`，调用 `context.Cancel()` 并结束。
4. 否则把新值改为：`OldValue + Delta * DeltaMultiplier`。
5. 如果启用下限/上限，再对 `NewValue` 做夹取。

使用场景：

- 抵抗减速：`TargetAttribute = Speed`，`Direction = Decrease`，`DeltaMultiplier = 0.5`。
- 免疫降攻：`TargetAttribute = PhysAtk`，`Direction = Decrease`，`CancelChange = true`。
- 属性封顶：`EnableMaxValue = true`，设置 `MaxValue`。
- 属性保底：`EnableMinValue = true`，设置 `MinValue`。

注意事项：

- 它只影响通过 `AttributeComponent` 重算流程产生的最终属性变化。
- 如果变化后最终值和旧值近似相等，则不会触发 `AfterAttributeChanged`。

---

## 7.3 AttributeChangeTriggerStatusData：属性变化触发 Buff

路径：

- `core/combat/status/AttributeChangeTriggerStatusData.cs`
- `core/combat/status/AttributeChangeTriggerStatusInstance.cs`

作用：在指定属性变化成功提交后，自动执行一组 `CardEffect`。

导出字段：

| 字段 | 作用 |
| --- | --- |
| `TargetAttribute` | 要监听的属性。 |
| `Direction` | 触发方向：任意、增加、降低。 |
| `Effects` | 属性变化后要执行的卡牌效果数组。 |

执行逻辑：

1. 如果当前正在执行自身效果，直接返回，防止递归死循环。
2. 检查属性类型是否匹配。
3. 检查变化方向是否匹配。
4. 如果 `Effects` 为空则不做事。
5. 对每个非空效果创建上下文：
   - `source = context.Source ?? Source ?? Owner`
   - `target = Owner`
6. 执行效果。

使用场景：

- 当速度提高时，给自己护盾。
- 当物攻降低时，抽牌或触发反击效果。
- 当法强提高时，对自身施加另一个 Buff。

注意事项：

- `Effects` 中如果继续改同一个属性，实例内 `_isExecuting` 会阻止自身递归执行。
- 它监听的是属性已经成功变化之后的事件；如果变化被 `AttributeChangeGuardStatusData` 取消，就不会触发。

项目内示例：

- `resources/buffs/draw_when_physAtk_decreased.tres`：配置了 `Direction = Decrease`，`Id = Draw_When_PhysAtk_Decreased`，用于监听物攻降低方向的触发状态。

---

## 7.4 BossDamageCapStatusData：Boss 单次伤害上限

路径：

- `core/combat/buffs/BossDamageCapStatusData.cs`
- `core/combat/buffs/BossDamageCapStatusInstance.cs`

作用：限制拥有者每次最终扣血前可受到的最大伤害。

导出字段：

| 字段 | 作用 |
| --- | --- |
| `MaxHealthDamageRatio` | 每次最多受到最大生命值多少比例的伤害，范围 `0 ~ 1`，默认 `0.10`。 |

执行时机：

- Hook：`OnBeforeHealthDamage()`。
- 优先级：`BeforeHealthDamage` 阶段返回 `1000`。

执行逻辑：

1. 如果当前伤害 `<= 0`，不处理。
2. 从拥有者查找 `HealthComponent`。
3. 计算 `maxAllowedDamage = health.MaxValue * MaxHealthDamageRatio`。
4. 最终伤害取 `Min(damage, maxAllowedDamage)`。

使用场景：

- Boss 机制：单次伤害不能超过最大生命值 10%。
- 防止爆发伤害秒杀关键单位。

注意事项：

- 当前查找路径是 `Owner.GetNodeOrNull<HealthComponent>("HealthComponent")`。
- 由于优先级为 `1000`，默认会晚于护盾 `ShieldStatusInstance` 的 `100` 执行。也就是先护盾吸收，再限制剩余扣血伤害。

---

## 7.5 BurnStatusData：灼烧

路径：

- `core/combat/buffs/BurnStatusData.cs`
- `core/combat/buffs/BurnStatusDataInstance.cs`

作用：拥有者行动开始时，按层数受到持续伤害。

导出字段：

| 字段 | 作用 |
| --- | --- |
| `DamagePerStack` | 每层造成多少基础伤害，默认 `5`。 |
| `DamageType` | 伤害类型，默认 `Magic`。 |
| `Element` | 元素类型，默认 `Fire`。 |

执行时机：

- Hook：`OnOwnerTurnStart()`。
- 当拥有者自己的回合开始时触发。

执行逻辑：

1. 如果 `DamagePerStack <= 0`，不处理。
2. 从拥有者查找 `Components/DamageReceiverComponent`。
3. 伤害为 `DamagePerStack * CurrentStacks`。
4. 构造 `DamagePayload`：
   - `Source = Source ?? Owner`
   - `Target = Owner`
   - `Damage = (int)damage`
   - `Type = DamageType`
   - `Element = Element`
5. 调用 `receiver.ReceiveDamage(payload)`。

配置建议：

```text
BurnStatusData
  Id = burn
  DisplayName = 灼烧
  Description = 回合开始时受到火属性法术伤害。
  MaxStacks = 3
  Policy = ResetDuration 或 AddStackOnly
  InitOwnerTurnDuration = 2
  DamagePerStack = 5
  DamageType = Magic
  Element = Fire
```

项目内示例：

- `resources/combat_skills/bmob.tres`：炸弹卡对主要目标施加 `bomb_burn`，最大 3 层。

注意事项：

- 灼烧造成的是一次完整 `ReceiveDamage`，因此会走攻击属性、状态增伤、易伤、防御、护盾等伤害流程。
- 当前 `DamagePayload.Damage` 是 `int`，`DamagePerStack * CurrentStacks` 会先转成整数。
- 当前查找路径是 `Components/DamageReceiverComponent`。

---

## 7.6 ShieldStatusData：护盾

路径：

- `core/combat/buffs/ShieldStatusData.cs`
- `core/combat/buffs/ShieldStatusInstance.cs`

作用：在最终扣血前吸收伤害。

导出字段：

| 字段 | 作用 |
| --- | --- |
| `DefaultShieldAmount` | 默认护盾值。 |

执行时机：

- Hook：`OnBeforeHealthDamage()`。
- 优先级：`BeforeHealthDamage` 阶段返回 `100`。

运行时字段：

| 字段 | 作用 |
| --- | --- |
| `ShieldAmount` | 当前剩余护盾值。创建时会被限制为不小于 `0`。 |

执行逻辑：

1. 如果伤害 `<= 0` 或护盾值 `<= 0`，不处理。
2. `absorbed = Min(ShieldAmount, damage)`。
3. `ShieldAmount -= absorbed`。
4. `damage -= absorbed`。
5. 如果护盾耗尽，移除该状态。

重复施加逻辑：

- `OnReapplied(incoming)` 中，如果 incoming 也是 `ShieldStatusInstance`，会把新护盾值加到旧护盾值上。
- 然后 `StatusComponent` 仍会尝试增加层数。

创建方式：

- 普通 `CreateInstance(source, owner)` 使用 `DefaultShieldAmount`。
- 专用 `CreateInstance(source, owner, shieldAmount)` 可指定护盾值。
- `ApplyShieldCardEffect` 使用 `DefaultShieldAmount` 创建。

注意事项：

- 当前护盾耗尽时调用 `Owner.GetNodeOrNull<StatusComponent>("StatusComponent")?.RemoveStatus(Id)`。
- 如果单位的 `StatusComponent` 实际放在 `Components/StatusComponent` 下，这里可能无法自动移除，需要统一节点路径或调整实现。

---

## 7.7 VulnerableStatusData：易伤

路径：

- `core/combat/buffs/VulnerableStatusData.cs`
- `core/combat/buffs/VulnerableStatusInstance.cs`

作用：让拥有者在防御减伤前受到更多指定类型伤害。

导出字段：

| 字段 | 作用 |
| --- | --- |
| `TargetDamageType` | 目标伤害类型，默认 `Physical`。 |
| `DamageMultiplier` | 伤害倍率，默认 `1.5`。 |

执行时机：

- Hook：`OnModifyIncomingDamageBeforeMitigation()`。
- 在元素倍率和防御/抗性减伤之前执行。

当前实际执行逻辑：

```text
如果 payload.Type 不是 Physical：不处理
否则 damage *= 1.5
```

使用场景：

- 受到物理伤害 +50%，然后再被防御减伤。

重要注意事项：

- 当前实现没有使用 `VulnerableStatusData.TargetDamageType` 和 `DamageMultiplier` 两个导出字段，而是硬编码为 `Physical` 和 `1.5`。
- 如果希望资源里配置的类型和倍率生效，需要把实例逻辑改为读取 `_data.TargetDamageType` 和 `_data.DamageMultiplier`。

建议配置：

```text
VulnerableStatusData
  Id = vulnerable_physical
  DisplayName = 物理易伤
  Description = 受到的物理伤害提高 50%，该加成在防御减伤前结算。
  MaxStacks = 1
  InitOwnerTurnDuration = 2
  TargetDamageType = Physical
  DamageMultiplier = 1.5
```

---

## 8. 配置一个新 Buff 的推荐流程

### 8.1 纯属性 Buff

适合：加速、加攻击、减防、增伤等。

1. 新建 `AttributeModifierStatusData` 资源。
2. 配置 `Id`、`DisplayName`、`Description`、`Icon`。
3. 配置 `MaxStacks`、`Policy`、持续时间；`MaxStacks = 0` 表示无层数上限。
4. 在 `Modifiers` 中添加一个或多个 `AttributeModifierData`。
5. 在卡牌效果里使用 `ApplyStatusCardEffect` 施加。

### 8.2 持续伤害 Buff

适合：灼烧、中毒、流血等。

1. 如果效果和灼烧一致，只需新建 `BurnStatusData` 资源并改名、伤害类型、元素。
2. 配置 `DamagePerStack`、`MaxStacks`、持续时间；`MaxStacks = 0` 表示无层数上限。
3. 使用 `ApplyStatusCardEffect` 施加。

### 8.3 护盾 Buff

适合：固定值护盾。

1. 新建 `ShieldStatusData`。
2. 配置 `DefaultShieldAmount`。
3. 用 `ApplyShieldCardEffect` 或 `ApplyStatusCardEffect` 施加。
4. 如果需要根据技能数值动态护盾，应扩展新的效果类或调用 `CreateInstance(source, owner, shieldAmount)`。

### 8.4 属性变化反应 Buff

适合：属性变化后触发额外技能效果。

1. 新建 `AttributeChangeTriggerStatusData`。
2. 配置 `TargetAttribute` 和 `Direction`。
3. 在 `Effects` 里放入要触发的 `CardEffect`。
4. 使用 `ApplyStatusCardEffect` 施加到监听者身上。

### 8.5 属性变化保护 Buff

适合：免疫减速、减少降攻幅度、属性上下限保护。

1. 新建 `AttributeChangeGuardStatusData`。
2. 配置 `TargetAttribute` 和 `Direction`。
3. 需要完全免疫时设置 `CancelChange = true`。
4. 需要削弱变化时设置 `DeltaMultiplier`。
5. 需要上下限时启用 `EnableMinValue` / `EnableMaxValue`。

---

## 9. 节点路径注意事项

当前代码中不同系统查找组件的路径不完全一致：

| 代码位置 | 查找路径 |
| --- | --- |
| `ApplyStatusCardEffect` | `Components/StatusComponent` |
| `ModifyAttributeEffect` | `Components/AttributeComponent` |
| `BurnStatusInstance` | `Components/DamageReceiverComponent` |
| `ApplyShieldCardEffect` | `StatusComponent` |
| `ShieldStatusInstance` 护盾耗尽移除 | `StatusComponent` |
| `BossDamageCapStatusInstance` | `HealthComponent` |
| `DamageReceiverComponent` 内部查找攻击/防御属性与状态 | `AttributeComponent`、`StatusComponent`、`HealthComponent` |

使用 Buff 前需要确认单位场景结构是否与对应路径一致。

如果单位组件统一放在 `Components/` 子节点下，则部分直接查找 `StatusComponent` / `HealthComponent` 的逻辑可能无法命中。

---

## 10. 常见问题

### Q1：临时加属性应该用 `ModifyAttributeEffect` 吗？

不建议。`ModifyAttributeEffect` 调用的是 `AddPermanentBonus()`，属于永久 Bonus。临时属性应使用 `AttributeModifierStatusData`。

### Q2：为什么重复施加 Buff 后持续时间和层数都变了？

当前 `StatusComponent.AddStatus()` 在同 `Id` 重复施加时，会先按 `Policy` 处理持续时间，然后无论哪种策略都会尝试 `TryIncreaseStack()`。

### Q3：多个 Buff 同时修改伤害，谁先执行？

先按对应 Hook 的 `GetHookPriority()` 排序，数值越小越早。优先级相同则按施加顺序，再按 `Id`。

### Q4：护盾和 Boss 伤害上限谁先结算？

当前护盾 `BeforeHealthDamage` 优先级是 `100`，Boss 上限是 `1000`。因此先护盾吸收，再对剩余伤害套 Boss 上限。

### Q5：易伤资源里改了倍率为什么没效果？

当前 `VulnerableStatusInstance` 写死了物理伤害和 `1.5` 倍，没有读取 `VulnerableStatusData` 的导出字段。这是当前实现限制。

### Q6：灼烧会触发易伤和护盾吗？

会。灼烧通过 `DamageReceiverComponent.ReceiveDamage()` 造成伤害，因此会走完整伤害流程，包括攻击/防御属性、状态 Hook、护盾等。

---

## 11. 快速配置模板

### 加速 Buff

```text
AttributeModifierStatusData
  Id = speed_up
  DisplayName = 加速
  Description = 速度提高 10 点，持续 2 次自身行动。
  MaxStacks = 3
  Policy = ResetDuration
  InitOwnerTurnDuration = 2
  Modifiers:
    - AttributeModifierData
        Type = Speed
        Mode = FlatAdd
        ValuePerStack = 10
```

### 灼烧 Debuff

```text
BurnStatusData
  Id = burn
  DisplayName = 灼烧
  Description = 行动开始时每层受到 5 点火属性魔法伤害。
  MaxStacks = 3
  Policy = ResetDuration
  InitOwnerTurnDuration = 2
  DamagePerStack = 5
  DamageType = Magic
  Element = Fire
```

### 物理易伤 Debuff

```text
VulnerableStatusData
  Id = vulnerable_physical
  DisplayName = 物理易伤
  Description = 受到的物理伤害提高 50%。
  MaxStacks = 1
  InitOwnerTurnDuration = 2
  TargetDamageType = Physical
  DamageMultiplier = 1.5
```

> 注意：当前代码仍硬编码为物理 1.5 倍，上述字段是资源设计意图。

### 护盾 Buff

```text
ShieldStatusData
  Id = shield
  DisplayName = 护盾
  Description = 吸收接下来受到的伤害。
  MaxStacks = 1
  DefaultShieldAmount = 30
```

### Boss 伤害上限

```text
BossDamageCapStatusData
  Id = boss_damage_cap
  DisplayName = 伤害上限
  Description = 单次受到伤害不超过最大生命值的 10%。
  MaxHealthDamageRatio = 0.10
```

### 免疫降速 Buff

```text
AttributeChangeGuardStatusData
  Id = immune_speed_down
  DisplayName = 免疫减速
  Description = 速度不会被降低。
  TargetAttribute = Speed
  Direction = Decrease
  CancelChange = true
```

### 物攻降低后触发效果

```text
AttributeChangeTriggerStatusData
  Id = trigger_when_phys_atk_down
  DisplayName = 物攻降低触发
  Description = 物攻降低后执行配置的效果。
  TargetAttribute = PhysAtk
  Direction = Decrease
  Effects = [CardEffect 资源列表]
```
