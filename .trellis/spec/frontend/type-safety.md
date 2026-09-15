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

`Object.get()`、可空三元表达式和 `Callable.bind()` 同样可能跨越 `Variant` 推断边界。读取跨语言结果时应显式声明 `Variant`，可空节点路径应声明为 `Node`，绑定回调应声明为 `Callable`；不要依赖 `:=` 让严格警告配置猜测类型。

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
func CombatFeedbackProfile.resolve_feedback_intensity(amount: float) -> float
func CombatScreenImpulse.enqueue_impulse(shake_pixels: float, shake_duration: float, hit_stop_seconds: float, time_scale: float) -> void
```

### 3. Contracts

- `DamageResolutionResult` 是 `RefCounted` 的不可变快照。至少包含 `Target`、`ActualDamage`、`IsEvaded`、`IsCritical`、`IsLethal`、`ShieldAbsorbedDamage`、`ShieldWasBroken`、`HitIndex`、`HitCount` 和 `TargetRoleId`。
- `DamagePayload.ResolutionTrace` 只由状态 Hook 记录护盾吸收、破盾和伤害上限削减；`DamageReceiverComponent` 在 `HealthComponent.TakeDamage()` 后读取 trace 并创建结果，表现脚本不得写回 trace、生命、状态或行动队列。
- GDScript 必须优先调用 `GetFeedbackInt`、`GetFeedbackBool`、`GetFeedbackNode` 等公开桥接方法，而非假定 C# 自动属性一定能被 `Object.get()` 反射。兼容旧对象时可在 `has_method` 为 false 后安全回退到 `get()`。
- `DamageEffect` 必须为每段填入 `HitIndex`（从 0 开始）和有效 `HitCount`（至少 1）；这些字段只用于浮字空间布局，绝不改变公式、目标选择、表现强度或播放时序。
- `CombatFeedbackDirector` 只消费 `DamageResolved` 和 `ValueChanged`；它只在生命值增加时从 `ValueChanged` 创建治疗浮字，不订阅 `StatusChanged` 或显示状态浮字。缺少节点或桥接方法时跳过该表现项，不中断同步伤害结算。
- `CombatFeedbackProfile.resolve_feedback_intensity` 只能接收结算后的绝对显示数值，并以连续饱和曲线返回 `0..1`；所有浮字、受力、震屏和 Hit Stop 参数都必须通过该强度与各自导出上限生成，不能在调用方重新引入固定高额阈值。
- `CombatScreenImpulse.enqueue_impulse` 的每个参数都由导演完成数值映射后提供。控制器必须按入队顺序逐条播放、在每条结束时恢复 `Engine.time_scale`，并在退出场景时清空队列；不得以段号、范围、冷却或新 Tween 覆盖旧请求。

### 4. Validation & Error Matrix

| 条件 | C# 结算层 | GDScript 表现层 |
| --- | --- | --- |
| `payload` 为 null | 返回零伤害结果并记录错误 | 不生成浮字或冲击 |
| 闪避成功 | 发射 `IsEvaded=true`、`ActualDamage=0` 的结果 | 显示 `MISS`，不显示伤害数 |
| 护盾完全吸收 | trace 写入吸收值，结果实际伤害为 0 | 仅显示灰色吸收数值，不额外显示文字标签 |
| 同帧多段或范围伤害 | 每条伤害均发射独立结果 | 每条请求进入目标与屏幕 FIFO；段号仅影响浮字位置 |
| 超高显示数值 | 权威伤害不受表现层影响 | 曲线趋近 Profile 上限，浮字、受力、震屏与 Hit Stop 均不得越界 |
| 冲击节点离开场景 | 不影响已完成的同步结算 | 清空未播放请求、恢复根节点位置与先前时间缩放 |
| C# 字段没有稳定桥接方法 | 不能由表现层假定反射可用 | 仅在兼容回退安全时调用 `get()`，否则静默跳过 |
| 目标节点已无效 | 结果仍可返回给 C# 调用方 | `is_instance_valid` 失败时跳过反馈 |

### 5. Good / Base / Bad Cases

- Good：暴击使目标实际扣除生命后，`DamageResolved` 发送 `IsCritical=true` 和真实 `ActualDamage`；导演以绝对数值的饱和曲线播放加粗、加大的深红数字、受力、震屏和一次短 Hit Stop，并由硬上限保护高数值。
- Base：普通多段的每一段都有独立、等强度的数值配方；段号只改变浮字位置，每段都进入局部与全局 FIFO，不重复丢弃或缩减 Hit Stop。
- Bad：`BattleManager` 在飞卡结束后直接调用怪物抖动/闪白，并假定该卡必然命中；这会错误覆盖闪避、范围、敌方伤害和护盾结果。

### 6. Tests Required

- 在 `tests/CUSGA.Tests/Program.cs` 覆盖闪避、暴击致死、护盾吸收/破裂、实际扣血以及 `GetFeedbackInt`、`GetFeedbackBool`、`GetFeedbackNode` 的值。
- 覆盖 `DamageEffect` 多段执行时每段各发射一个结果，并断言段号为 `0..HitCount-1`、总段数一致。
- 有可用 Godot 运行时后，加载 `battle.tscn`，验证导演能连接玩家与新刷怪物，完整模式按请求恢复 `Engine.time_scale`，且 `reduced` 模式的每条冲击请求都不写 `Engine.time_scale`。

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

#### Wrong

```gdscript
# 段号被用来缩减或跳过反馈，会让真实命中在范围和多段中丢失。
if result.GetFeedbackInt("HitIndex") > 0:
	return
screen_impulse.request_impulse(12.0, 0.12, 0.04, 0.05)
```

#### Correct

```gdscript
# 每条权威结果先映射为自身数值配方，再完整加入各自 FIFO。
var recipe: Dictionary = _build_impact_recipe(impact_amount, is_critical, is_lethal, shield_broken)
_enqueue_target_impact(target, impact_color, recipe)
_screen_impulse.enqueue_impulse(
	float(recipe["screen_shake_pixels"]),
	float(recipe["screen_shake_duration"]),
	float(recipe["hit_stop_seconds"]),
	profile.hit_stop_time_scale
)
```
