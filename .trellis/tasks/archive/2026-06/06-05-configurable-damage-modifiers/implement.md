# 实施计划

## Pre-implementation Gates

- 已创建 Trellis task：`.trellis/tasks/06-05-configurable-damage-modifiers`
- 已完成 PRD、design、implement 初稿。
- 用户已确认进入实现。

## Impact Analysis Already Run

- `DamagePayload` upstream impact：MEDIUM，直接影响 `BurnStatusInstance.OnOwnerTurnStart`、`DamageEffect.ApplyDamageToNode` 和伤害测试。
- `DamageReceiverComponent.ReceiveDamage` upstream impact：LOW，GitNexus 看到直接测试调用。
- `BurnStatusInstance.OnOwnerTurnStart` upstream impact：LOW。
- 未发现 HIGH 或 CRITICAL 风险。

## Implementation Checklist

- [x] 先补失败测试：状态/buff 伤害默认跳过直接攻击修饰，但可配置为只触发暴击。
- [x] 新增 `DamageModifierFlags` enum，定义 `None`、`Evasion`、`Critical`、`RandomVariance`、`Lifesteal`、`DefaultCombat`。
- [x] 更新 `DamagePayload`：新增 flags 属性，删除 `AppliesDefaultCombatModifiers`。
- [x] 更新 `DamageReceiverComponent.ReceiveDamage`：用 flags 分别控制闪避、暴击、随机浮动、吸血。
- [x] 更新 `BurnStatusData`：暴露状态伤害修饰配置，默认 `None`。
- [x] 更新 `BurnStatusInstance`：从 `_data` 读取配置并写入 payload。
- [x] 更新现有测试名称和断言，使它们描述 flags 行为而不是单个 bool 行为。
- [x] 不增加状态 Hook 相关 flags 和测试；但新增 flags/helper 时保持命名泛化，避免未来纳入 Hook 时重做 payload 形状。

## Validation

- [x] 先运行聚焦测试，确认新增测试在实现前失败。
- [x] 实现后运行聚焦测试，确认新增测试通过。
- [x] 运行 `env CI=true dotnet build CUSGA.sln --no-restore`。
- [x] 如果触碰 `[GlobalClass]` 资源导出字段后 dotnet build 不足以覆盖 Godot editor/resource 加载，再运行 `godot-mono --headless --path . --build-solutions --quit`。
- [x] 实现完成后运行 `gitnexus_detect_changes(scope: "all")` 检查影响范围。

## Validation Results

- Red: `env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore` failed before implementation because `BurnStatusData.DamageModifiers` and `DamageModifierFlags` did not exist.
- Green: `env CI=true dotnet build tests/CUSGA.Tests/CUSGA.Tests.csproj --no-restore` passed after implementation.
- Green: `env CI=true dotnet build CUSGA.sln --no-restore` passed.
- Green: `godot-mono --headless --path . --build-solutions --quit` passed.
- Green: `godot-mono --headless --path . --script res://tests/godot/multi_hit_damage_tests.gd` passed with pre-existing item resource UID warnings.
- Brooks accepted finding fixed: added `godot-mono --headless --path . --script res://tests/godot/status_damage_modifier_tests.gd`; it passed with the same pre-existing item resource UID warnings and now executes `BurnStatusData.DamageModifiers` behavior in Godot runtime.
- Brooks accepted finding fixed: extracted direct-attack modifier probe setup in `tests/CUSGA.Tests/Program.cs` to reduce duplicated extreme-stat setup.
- Limited: `env CI=true dotnet run --no-restore --project tests/CUSGA.Tests/CUSGA.Tests.csproj` still fails outside Godot runtime because `GodotSharp, Version=4.6.3.0` is unavailable to plain `dotnet run`.
- GitNexus: `detect_changes(scope: "all")` reported medium risk, with affected processes focused on `DamagePayload` and `ReceiveDamage`.

## Rollback Points

- 如果 flags 导致资源导出或 Godot 序列化不稳定，回退 `BurnStatusData` 的导出方式，先只在代码层支持 payload flags。
- 如果实现过程中发现状态 Hook 必须同步调整，停止实现并回到规划；当前任务只交付直接攻击修饰 flags，把 Hook 配置保留为后续扩展。
