# 战斗属性与伤害结算扩展设计规格

## 背景

当前伤害流程已经从旧的“攻击加成 + 防御减伤”迁移到基础公式：

```text
物理基础伤害 = 技能威力 × (攻击者物攻 + 全局常数C) / (防御方有效物抗 + 全局常数C)

法术基础伤害 = 技能威力 × (攻击者法强 + 全局常数C) / (防御方有效法抗 + 全局常数C)

有效物抗 = Max( 防御方原始物抗 × (1 - 攻击者物理穿透率) - 攻击者固定物理穿透, 0 )

有效法抗 = Max( 防御方原始法抗 × (1 - 攻击者法术穿透率) - 攻击者固定法术穿透, 0 )

最终伤害 = 取整( 基础伤害 × 综合修正系数 × 随机浮动系数 )

综合修正系数 = 暴击修正 × 增伤修正 × 减伤修正 × 属性克制修正 × 其他修正
```

新的设计继续扩展这套公式：加入暴击率、暴击伤害、闪避率、吸血、固定穿透、百分比穿透、随机浮动，并把生命上限和玩家能量上限纳入 `AttributeComponent` 管理。属性摘要 UI 只保留最初五维，详细属性通过独立弹窗查看。

## 已确认规则

### 属性维度

- 基础五维仍为：物攻、物抗、法强、法抗、速度。
- 新增生存资源属性：
  - `MaxHealth`：生命上限，所有战斗单位都有。
  - `MaxEnergy`：能量上限，只对拥有 `EnergyComponent` 的单位生效；怪物没有能量。
- 新增伤害修正属性：
  - `CritRate`：暴击率，百分比属性。
  - `CritDamage`：暴击总倍率，默认 `1.5`，UI 显示为 `150%`。
  - `EvasionRate`：闪避率，百分比属性。
  - `LifestealRate`：吸血百分比，按最终实际伤害统一吸血，不区分物理或法术。
- 穿透拆成固定穿透和百分比穿透：
  - `FixedPhysPenetration`
  - `PhysPenetrationRate`
  - `FixedMagicPenetration`
  - `MagicPenetrationRate`
- 百分比类属性使用 `0.3 = 30%` 的内部表示。
- 固定穿透、生命上限、能量上限、攻击、防御、法强、法抗都不能为负。
- 速度最小值保持 `1`。
- 暴击伤害最小值为 `1`，避免暴击降低伤害。

### 基础属性配置

- `StartingStats` 是生命上限、玩家能量上限和战斗属性的基础配置来源。
- `StartingStats` 新增：
  - `BaseMaxHealth` / `MaxHealthGrowth`
  - `BaseMaxEnergy` / `MaxEnergyGrowth`
  - 各新增高级战斗属性的基础值和成长值。
- `AttributeComponent.InitializeWithData()` 使用 `StartingStats` 初始化全部属性维度。
- `AttributeComponent` 初始化或重算生命上限后，同步同宿主的 `HealthComponent.InitializeMax()`。
- `AttributeComponent` 初始化或重算能量上限后，只在宿主存在 `EnergyComponent` 时同步 `EnergyComponent.InitializeMax()`。
- 怪物没有能量资源，因此怪物场景不需要 `EnergyComponent`，怪物初始化不会创建或同步能量。

### 怪物生命上限迁移

- 停止使用 `MonsterData.MaxHealth` 作为怪物生命上限来源。
- 怪物生命上限来自 `MonsterData.InitialAttributes.BaseMaxHealth`，运行时经 `AttributeComponent` 初始化并同步到 `HealthComponent`。
- `Monster.Initialize()` 不再调用 `Health.InitializeMax(data.MaxHealth)`。
- `EncounterMonsterScaler` 不再缩放 `MonsterData.MaxHealth`，改为缩放 `StartingStats.BaseMaxHealth`。
- 现有怪物资源需要把旧 `MonsterData.MaxHealth` 的值迁移到对应 `StartingStats.BaseMaxHealth`。

### 伤害公式

- 全局常数 `C` 仍是同一个常数，默认值沿用当前 `CombatConstants.DamageFormulaConstant`。
- 有效抗性公式：

```text
有效物抗 = Max(防御方原始物抗 * (1 - 攻击者物理穿透率) - 攻击者固定物理穿透, 0)
有效法抗 = Max(防御方原始法抗 * (1 - 攻击者法术穿透率) - 攻击者固定法术穿透, 0)
```

- 物理伤害使用物攻、物抗、物理穿透率、固定物理穿透。
- 法术伤害使用法强、法抗、法术穿透率、固定法术穿透。
- 真实伤害的基础伤害为技能威力，不使用攻击、防御或穿透；但仍进入通用最终修正流程。

### 伤害结算顺序

一次伤害结算按以下顺序执行：

1. 防御方按 `EvasionRate` 进行闪避判定。
2. 闪避成功时，本次伤害结束，不扣血，不吸血。
3. 按伤害类型计算基础伤害。
4. 攻击方按 `CritRate` 进行暴击判定。
5. 暴击成功时，暴击修正为 `CritDamage`；未暴击时为 `1.0`。
6. 应用状态、增伤、减伤和其他伤害修正。
7. 应用属性克制修正。
8. 应用随机浮动系数。
9. 对结果 `RoundToInt` 得到最终伤害。
10. 对防御方扣除生命。
11. 攻击方按最终实际伤害和 `LifestealRate` 计算吸血量。
12. 吸血量使用 `RoundToInt(finalActualDamage * LifestealRate)`，最小为 `0`。
13. 攻击方存在 `HealthComponent` 时恢复吸血量。

### 最终实际伤害

- 最终实际伤害是本次实际从防御方生命中扣除的值。
- 如果最终伤害大于防御方当前生命，最终实际伤害按防御方当前生命截断。
- `HealthComponent.TakeDamage()` 或等价方法需要能返回最终实际扣除值，供吸血使用。

### 随机浮动

- 随机浮动必须真实启用。
- 随机浮动范围可配置。
- 默认范围采用保守值 `0.95` 到 `1.05`。
- 每次非闪避伤害在范围内随机得到一个系数。
- 范围配置需要保证最小值和最大值都不小于 `0`；如果配置反向，运行时按较小值作为下限、较大值作为上限。

### 随机数边界

- `DamageReceiverComponent` 维护 Godot `RandomNumberGenerator`，负责运行时闪避、暴击和随机浮动 roll。
- 纯公式和结算模型使用显式 roll 值输入，方便测试固定结果。
- 不直接使用 `GD.Randf()`，避免测试和复现困难。

### 状态修正兼容

- 保留现有 `StatusComponent` 伤害修改 hook。
- 旧的“防御减伤阶段”不再存在；防御已经进入基础公式。
- `ProcessModifyOutgoingDamage`、`ProcessModifyIncomingDamageBeforeMitigation`、`ProcessModifyIncomingDamageAfterMitigation`、`ProcessBeforeHealthDamage` 继续作为“增伤、减伤、其他修正”的兼容入口。
- 现有护盾、Boss 单次伤害上限等在 `BeforeHealthDamage` 阶段继续生效。

## UI 设计

### 基础属性摘要

- `AttributeSummaryUI` 默认只显示最初五维：
  - 物攻
  - 物抗
  - 法强
  - 法抗
  - 速度
- 基础面板新增一个“详情”按钮。
- 基础面板不再直接显示穿透、暴击、闪避、吸血、生命上限或能量上限。

### 详细属性弹窗

- 点击“详情”打开独立弹窗，不在原面板内展开。
- 弹窗显示完整属性，按组组织：
  - 基础：物攻、物抗、法强、法抗、速度
  - 资源：生命上限、能量上限
  - 穿透：物理穿透、法术穿透
  - 战斗修正：暴击率、暴击伤害、闪避率、吸血
- 玩家详细属性显示生命上限和能量上限。
- 怪物详细属性如果复用该 UI，只显示生命上限，不显示能量上限。
- 穿透合并展示：

```text
物理穿透  186 | 30%
法术穿透  186 | 30%
```

- 穿透左侧是固定穿透，右侧是百分比穿透。
- 百分比属性统一显示为百分比，例如 `30%`、`150%`。
- 非百分比属性保留现有整数/一位小数格式。

## 推荐架构

### `AttributeComponent`

- 继续作为运行时属性所有者。
- 负责从 `StartingStats` 初始化属性字典。
- 负责通过现有属性修正机制计算有效值。
- 负责在 `MaxHealth` 或 `MaxEnergy` 有效值变化后同步对应 `VitalComponentBase`。
- 不负责伤害随机判定，也不负责 UI 格式化。

### `StartingStats`

- 作为战斗单位基础属性配置。
- 包含生命上限和玩家能量上限的基础值和成长值。
- 替代 `MonsterData.MaxHealth` 作为怪物生命上限来源。

### `DamageFormula`

- 保持为框架无关的纯 C# 公式层。
- 提供基础伤害、有效抗性、完整伤害结算的纯计算入口。
- 完整结算入口接收显式 roll 值，不直接访问 Godot RNG 或场景节点。

### `DamageReceiverComponent`

- 继续作为 Godot 场景树适配层。
- 从攻击方和防御方查找 `AttributeComponent`、`StatusComponent`、`HealthComponent`。
- 维护运行时 `RandomNumberGenerator`。
- 把属性快照和随机 roll 传给纯结算逻辑。
- 根据结算结果执行扣血、吸血和日志输出。

### `VitalComponentBase`

- 继续作为生命和能量资源的共同基类。
- 需要支持返回实际扣除值，便于吸血按最终实际伤害计算。
- `HealthComponent` 和 `EnergyComponent` 仍只负责资源值，不负责属性计算。

### `AttributeSummaryUI`

- 基础面板只绑定和显示五维。
- 详情弹窗负责高级属性展示。
- UI 只读取 `AttributeComponent` 的有效值，不计算伤害规则。

## 测试关注点

- `DamageFormula` 正确计算固定穿透和百分比穿透后的有效物抗/法抗。
- `DamageFormula` 正确应用同一个全局常数 `C`。
- 闪避 roll 命中时最终伤害为 `0`，且吸血为 `0`。
- 暴击 roll 命中时使用 `CritDamage` 作为总倍率。
- 暴击伤害默认 `1.5` 时，UI 显示 `150%`。
- 随机浮动使用配置范围内的系数。
- 吸血按最终实际伤害 `RoundToInt` 计算。
- 过量伤害只按实际扣除生命计算吸血。
- `AttributeComponent.InitializeWithData()` 初始化新增属性维度。
- `MaxHealth` 初始化后同步 `HealthComponent.MaxValue`。
- `MaxEnergy` 只在宿主存在 `EnergyComponent` 时同步。
- 怪物没有 `EnergyComponent` 时不会因为 `MaxEnergy` 报错。
- `Monster.Initialize()` 使用 `StartingStats.BaseMaxHealth` 路径初始化生命上限。
- `EncounterMonsterScaler` 缩放 `StartingStats.BaseMaxHealth`，不再依赖 `MonsterData.MaxHealth`。
- `AttributeSummaryUI` 默认只显示五维。
- 点击“详情”能打开独立详细属性弹窗。
- 详细弹窗中物理穿透和法术穿透按 `固定值 | 百分比` 展示。
- 详细弹窗中百分比属性格式正确。

## 验证命令

- C# 编译：

```bash
env CI=true dotnet build CUSGA.sln --no-restore
```

- 测试项目编译：

```bash
env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore
```

- Godot C# 全局类和场景集成：

```bash
godot-mono --headless --path . --build-solutions --quit
```

- 触碰 GDScript 或场景时，额外 smoke test：

```bash
godot-mono --headless --path . --scene res://scenes/inventory/AttributeSummaryUI.tscn --quit-after 5
godot-mono --headless --path . --scene res://scenes/main_menu_scenes/main_menu.tscn --quit-after 5
```
