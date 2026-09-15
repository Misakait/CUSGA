# Type Safety And Cross-Language Boundaries

CUSGA crosses between C#, GDScript, Godot resources, and wrapper nodes. Keep those boundaries explicit.

## Generated Enum Bridge

`SkillTargetingType` is the current cross-language enum pattern:

- Source of truth: `core/combat/skills/SkillTargetingType.cs`.
- Generator: `addons/skill_targeting_type_codegen/skill_targeting_type_codegen.gd`.
- Output: `scripts/generated/SkillTargetingType.gd`.
- Test: `tests/godot/skill_targeting_type_codegen_tests.gd`.

GDScript battle/card code should preload `scripts/generated/SkillTargetingType.gd` and use `SkillTargetingType.Value.*`. Do not parse C# source at runtime inside battle flow.

When changing `SkillTargetingType.cs`, regenerate the GDScript file and run the codegen test.

## C# Resource Types

GDScript often reads C# resource properties dynamically, for example `card_data.Skill.TargetingType` or `monster.MonsterName`. Guard dynamic reads with null checks where the current code already does so.

For new C# data used by GDScript:

- Use `[GlobalClass]` if the type must be created/assigned in Godot.
- Use exported properties for editor-visible fields.
- Prefer `StringName`, enums, `Array`, and `Dictionary` types that Godot serializes cleanly.
- Add a generated bridge or explicit wrapper if GDScript needs stable enum names or integer values.

## Wrapper Node Unwrapping

Battle GDScript may deal with wrapper nodes such as `PlayerManager` while C# effects need the real entity with `Components/...` children. `battle_manager.gd` uses `_unwrap_combat_entity` and comments why this is required before building `SkillExecutionContext`.

When adding combat behavior in GDScript, pass real C# entity nodes into C# contexts and effects. Do not pass UI wrappers unless the C# API explicitly expects wrappers.

## Dynamic Boundary Guards

Use `has_method`, `has_signal`, `get_node_or_null`, `is_instance_valid`, and null checks at C#/GDScript boundaries. Existing examples:

- `passage_guard_controller.gd` checks methods and signals before requesting passage guard combat.
- `card_manager.gd` checks whether cards have `Skill` and `TargetingType`.
- `battle_manager.gd` checks component availability before reading speed.
- `DamageEffect` validates damage candidates and handles missing `DamageReceiverComponent` with a warning.

Do not turn these dynamic boundaries into unchecked calls unless tests prove the path is always present.

Typed `Array[T]` calls such as `pop_back()` and `pop_front()` still cross a `Variant` return boundary in GDScript's static analyser. Declare the receiving variable explicitly as `T`; do not use `:=` for those results when warnings are treated as errors.

When calling a method whose parameter is `Array[T]` through `Object.call`, an array literal is an untyped `Array` and fails Godot's runtime element-type validation. Build a local `Array[T]` explicitly and pass that value instead.

## C# 伤害结果到 GDScript 战斗表现契约

### 1. Scope / Trigger

当 C# `DamageReceiverComponent` 的权威伤害结算需要驱动 GDScript 浮字、受力或 Hit Stop 时，必须通过只读结算结果信号跨语言传递事实。触发原因是表现层不能从卡牌飞行、血条差值或预估伤害反推闪避、暴击、护盾破裂和致死结果。

### 2. Signatures

```csharp
public DamageResolutionResult ReceiveDamage(DamagePayload payload);
[Signal] public delegate void DamageResolvedEventHandler(DamageResolutionResult result);

public int GetFeedbackInt(string propertyName);
public bool GetFeedbackBool(string propertyName);
public Node GetFeedbackNode(string propertyName);
```

```gdscript
func _on_damage_resolved(result: RefCounted) -> void
func _read_result_int(result: RefCounted, property_name: StringName) -> int
func _read_result_bool(result: RefCounted, property_name: StringName) -> bool
func _read_result_node(result: RefCounted, property_name: StringName) -> Node
```

### 3. Contracts

- `DamageResolutionResult` 是 `RefCounted` 的不可变快照。至少包含 `Target`、`ActualDamage`、`IsEvaded`、`IsCritical`、`IsLethal`、`ShieldAbsorbedDamage`、`ShieldWasBroken`、`HitIndex`、`HitCount` 和 `TargetRoleId`。
- `DamagePayload.ResolutionTrace` 只由状态 Hook 记录护盾吸收、破盾和伤害上限削减；`DamageReceiverComponent` 在 `HealthComponent.TakeDamage()` 后读取 trace 并创建结果，表现脚本不得写回 trace、生命、状态或行动队列。
- GDScript 必须优先调用 `GetFeedbackInt`、`GetFeedbackBool`、`GetFeedbackNode` 等公开桥接方法，而非假定 C# 自动属性一定能被 `Object.get()` 反射。兼容旧对象时可在 `has_method` 为 false 后安全回退到 `get()`。
- `DamageEffect` 必须为每段填入 `HitIndex`（从 0 开始）和有效 `HitCount`（至少 1）；这些字段只用于表现节流，绝不改变公式或目标选择。
- `CombatFeedbackDirector` 只消费 `DamageResolved` 和 `ValueChanged`；它只在生命值增加时从 `ValueChanged` 创建治疗浮字，不订阅 `StatusChanged` 或显示状态浮字。缺少节点或桥接方法时跳过该表现项，不中断同步伤害结算。

### 4. Validation & Error Matrix

| 条件 | C# 结算层 | GDScript 表现层 |
| --- | --- | --- |
| `payload` 为 null | 返回零伤害结果并记录错误 | 不生成浮字或冲击 |
| 闪避成功 | 发射 `IsEvaded=true`、`ActualDamage=0` 的结果 | 显示 `MISS`，不显示伤害数 |
| 护盾完全吸收 | trace 写入吸收值，结果实际伤害为 0 | 仅显示灰色吸收数值，不额外显示文字标签 |
| C# 字段没有稳定桥接方法 | 不能由表现层假定反射可用 | 仅在兼容回退安全时调用 `get()`，否则静默跳过 |
| 目标节点已无效 | 结果仍可返回给 C# 调用方 | `is_instance_valid` 失败时跳过反馈 |

### 5. Good / Base / Bad Cases

- Good：暴击使目标实际扣除生命后，`DamageResolved` 发送 `IsCritical=true` 和真实 `ActualDamage`；导演播放加粗、加大的深红数字、重受力和一次短 Hit Stop。
- Base：普通多段的中间段仍有独立结果，但导演只显示紧凑数字，不重复请求 Hit Stop。
- Bad：`BattleManager` 在飞卡结束后直接调用怪物抖动/闪白，并假定该卡必然命中；这会错误覆盖闪避、范围、敌方伤害和护盾结果。

### 6. Tests Required

- 在 `tests/CUSGA.Tests/Program.cs` 覆盖闪避、暴击致死、护盾吸收/破裂、实际扣血以及 `GetFeedbackInt`、`GetFeedbackBool`、`GetFeedbackNode` 的值。
- 覆盖 `DamageEffect` 多段执行时每段各发射一个结果，并断言段号为 `0..HitCount-1`、总段数一致。
- 有可用 Godot 运行时后，加载 `battle.tscn`，验证导演能连接玩家与新刷怪物，且 `reduced` 模式不写 `Engine.time_scale`。

### 7. Wrong vs Correct

#### Wrong

```gdscript
# 预结算表现既不知道闪避，也无法知道实际护盾吸收量。
await deck_manager.play_enemy_hit_feedback(monster_target)
combat_skill.Execute(context)
```

#### Correct

```gdscript
# 施放动画与命中结果分离；C# 完成结算后由 DamageResolved 驱动表现。
await deck_manager.play_card_to_enemy(action.presentation_card, monster_target)
combat_skill.Execute(context)
```
