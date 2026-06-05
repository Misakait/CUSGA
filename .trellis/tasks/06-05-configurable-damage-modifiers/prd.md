# 可配置伤害修饰流程

## Goal

让不同来源的伤害可以按配置选择是否触发闪避、暴击、随机浮动、吸血，提高 buff、debuff、DOT、普通技能伤害之间的表现灵活性。

## User Value

- 普通技能伤害继续默认走完整战斗修饰流程。
- buff/status 造成的伤害默认不走闪避、暴击、吸血等默认直接攻击修饰。
- 单个 buff/status 可以显式打开部分修饰，例如“撕咬 debuff”每回合造成伤害，但该伤害可以暴击。
- 伤害流程的可配置项可继续扩展，不需要每新增一种伤害表现就新增一个 bool。

## Confirmed Facts

- commit `fe2b1f88fca8f72cbcfef24233d8d84b228a85d2` 给 `DamagePayload` 增加了 `AppliesDefaultCombatModifiers` bool。
- 当前 bool 会把闪避、暴击、随机浮动、吸血绑定成一个整体，不能表达“只暴击但不闪避/不吸血”。
- `DamageReceiverComponent.ReceiveDamage` 当前顺序包括：闪避、基础伤害、暴击、攻击方状态修正、受击方防御前状态修正、五行倍率、受击方防御后状态修正、扣血前 Hook、随机浮动、扣血、吸血。
- `BurnStatusInstance.OnOwnerTurnStart` 当前构造 `DamagePayload` 并设置 `AppliesDefaultCombatModifiers = false`。
- 已有状态 Hook 包括 `VulnerableStatusInstance.OnModifyIncomingDamageBeforeMitigation`、`ShieldStatusInstance.OnBeforeHealthDamage`、`BossDamageCapStatusInstance.OnBeforeHealthDamage`。
- 现有测试已经覆盖 DOT 跳过默认修饰、普通伤害仍默认应用默认修饰、DOT 仍走护盾等扣血前 Hook。
- 用户明确要求不要保留 `DamagePayload.AppliesDefaultCombatModifiers` 兼容属性，直接重构为新的配置字段。

## Requirements

- `DamagePayload` 必须支持按项配置默认直接攻击修饰，而不是只支持一个总 bool。
- 普通技能伤害 payload 默认必须保持旧行为：默认应用闪避、暴击、随机浮动、吸血。
- buff/status 伤害默认必须跳过默认直接攻击修饰。
- buff/status 伤害必须能配置为只启用某些修饰，例如启用暴击但不启用闪避、随机浮动或吸血。
- 必须移除 `DamagePayload.AppliesDefaultCombatModifiers`，并将现有调用点迁移到新的按项配置字段。
- 本轮不把攻击方/受击方状态伤害修正 Hook 纳入可配置范围，但新设计不能堵死未来扩展这类 Hook 的入口。
- 代码注释和新增 public API XML docs 必须符合项目要求，代码注释使用中文。
- 验证命令必须使用 `env CI=true`，不能运行 plain `dotnet build` 或 `dotnet test`。

## Acceptance Criteria

- [x] 有测试证明普通 `DamagePayload` 默认仍会触发闪避等默认直接攻击修饰。
- [x] 有测试证明状态/buff 伤害默认不触发闪避、暴击、随机浮动、吸血。
- [x] 有测试证明状态/buff 伤害可配置为触发暴击，并且不会因此触发未配置的闪避、随机浮动或吸血。
- [x] 有测试覆盖 DOT 或状态伤害仍按预期经过保留的通用扣血保护流程，例如护盾或伤害上限。
- [x] `BurnStatusData` 或等价状态数据层暴露可配置项，使具体 buff 资源可以配置伤害修饰。
- [x] `DamageReceiverComponent.ReceiveDamage` 的流程判断不再依赖单个总 bool 控制多个互不相同的修饰。
- [x] `env CI=true dotnet build CUSGA.sln --no-restore` 通过。

## Out Of Scope

- 不改 GDScript、场景、`.tres` 资源文件，除非后续发现 C# 资源导出字段必须通过 Godot runtime 验证。
- 不重新设计整个状态系统、技能系统或生命组件。
- 不引入新测试框架。
- 不改变普通技能伤害的默认数值表现。
- 不在本轮配置 `ProcessModifyOutgoingDamage`、`ProcessModifyIncomingDamageBeforeMitigation`、`ProcessModifyIncomingDamageAfterMitigation` 这三类状态伤害修正 Hook。

## Resolved Question

- “增幅”指 `StatusComponent.ProcessModifyOutgoingDamage`、`ProcessModifyIncomingDamageBeforeMitigation`、`ProcessModifyIncomingDamageAfterMitigation` 对应的状态伤害修正 Hook，例如 `VulnerableStatusInstance` 的物理伤害乘以 1.5。本轮不纳入配置，但实现要为未来纳入保留清晰扩展点。
