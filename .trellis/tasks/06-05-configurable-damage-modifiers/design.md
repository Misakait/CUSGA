# 可配置伤害修饰流程设计

## Architecture

当前 `AppliesDefaultCombatModifiers` 是一个过粗的开关。它把闪避、暴击、随机浮动、吸血绑成一个包，因此不能表达“状态伤害默认不走直接攻击流程，但某个状态伤害可以暴击”。

设计方向是把 payload 上的默认直接攻击修饰控制改成 flags：

- `DamageModifierFlags.None`
- `DamageModifierFlags.Evasion`
- `DamageModifierFlags.Critical`
- `DamageModifierFlags.RandomVariance`
- `DamageModifierFlags.Lifesteal`
- `DamageModifierFlags.DefaultCombat`

按用户要求，直接移除 `DamagePayload.AppliesDefaultCombatModifiers`，不保留兼容属性或迁移入口。普通技能伤害默认使用 `DefaultCombat`，状态伤害数据默认使用 `None`。

## Data Flow

普通技能伤害：

1. `DamageEffect.ApplyDamageToNode` 创建 `DamagePayload`。
2. 未显式配置时，payload 使用 `DamageModifierFlags.DefaultCombat`。
3. `DamageReceiverComponent.ReceiveDamage` 按 flags 分别判断闪避、暴击、随机浮动、吸血。

状态/buff 伤害：

1. `BurnStatusData` 暴露 `DamageModifiers` 配置，默认 `None`。
2. `BurnStatusInstance.OnOwnerTurnStart` 创建 `DamagePayload` 时把 `_data.DamageModifiers` 写入 payload。
3. 默认灼烧不触发默认直接攻击修饰。
4. 新的“撕咬 debuff”类状态可以复用相同字段，把 `DamageModifiers` 配成 `Critical` 或其它组合。

## Contracts

- `DamagePayload` 是伤害流程配置的单一入口。
- `DamageReceiverComponent` 不关心伤害来源是技能还是 buff，只读 payload 的 flags。
- `StatusEffectData` 子类负责把资源配置转成 payload flags。
- 护盾、伤害上限、扣血本身属于通用生存/保护流程，默认不被 `DefaultCombat` flags 关闭，除非用户明确希望把这类 Hook 也纳入配置。

## Compatibility

- 旧的 `AppliesDefaultCombatModifiers = false` 调用点必须改为 `DamageModifiers = DamageModifierFlags.None` 或等价的新字段赋值。
- 旧的默认 payload 行为必须保持 `DefaultCombat`。
- 不保留 `AppliesDefaultCombatModifiers`，因此编译器会暴露所有未迁移调用点。

## Tradeoffs

- flags 比多个 bool 更适合扩展，也能表达任意组合。
- flags 会让资源配置更抽象，需要命名清楚，测试必须覆盖常见组合。
- 如果把所有状态 Hook 也纳入同一个 flags，配置能力更强，但流程复杂度和测试矩阵会明显增加。

## Damage Amplification Hook Meaning

这里讨论的“增幅”不是暴击、随机浮动或五行倍率，而是状态系统里的伤害修正 Hook：

- `StatusComponent.ProcessModifyOutgoingDamage` 调用攻击方状态的 `OnModifyOutgoingDamage`。
- `StatusComponent.ProcessModifyIncomingDamageBeforeMitigation` 调用受击方状态的 `OnModifyIncomingDamageBeforeMitigation`。
- `StatusComponent.ProcessModifyIncomingDamageAfterMitigation` 调用受击方状态的 `OnModifyIncomingDamageAfterMitigation`。

现有例子是 `VulnerableStatusInstance.OnModifyIncomingDamageBeforeMitigation`：当 payload 是物理伤害时把伤害乘以 `1.5f`。这类 Hook 可以代表易伤、减伤、攻击方增伤等“状态提供的伤害修正”。护盾和 Boss 伤害上限属于 `OnBeforeHealthDamage`，更接近扣血前保护流程，不建议和默认直接攻击修饰混在同一批开关里。

本轮决策是不配置这三类状态伤害修正 Hook。为了给未来扩展留空间，flags 类型和判断方法应避免命名成只能覆盖四个固定项的结构。推荐使用 `DamageModifierFlags` 和 `HasDamageModifier(...)` 这类泛化命名；本轮 `DefaultCombat` 只组合闪避、暴击、随机浮动、吸血。未来如果要纳入状态 Hook，可以新增类似 `OutgoingStatusModifiers`、`IncomingStatusModifiersBeforeMitigation`、`IncomingStatusModifiersAfterMitigation` 的 flag，而不需要再改 payload 的基本形状。

## Recommendation

第一步先把 commit 中已经归为“默认直接攻击修饰”的四项拆成 flags：闪避、暴击、随机浮动、吸血。状态增幅 Hook 本轮暂不纳入配置，但命名和 helper 应为未来扩展保留空间。
