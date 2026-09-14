# State Management

Godot node ownership, autoloads, resources, and signals are the project's state management tools. There is no Redux, React state, server cache, or URL state layer.

## Local Node State

Keep state local when it belongs to one scene or component:

- `InventoryUI` tracks whether inventory, equipment, and deck slot views have been initialized.
- `EquipmentSlotUI` tracks the current equipment slot, stack, and pointer-inside state.
- `card_manager.gd` tracks the dragged card, drag offset, and highlighted entities.
- `battle_manager.gd` tracks battle state, action queue, and active entity.

Local state should be reset or disconnected in `_ExitTree` when it references external nodes, signals, or stack events.

## Component State

Reusable gameplay state belongs in C# components under an entity:

- `InventoryComponent` owns slots and emits `InventoryChanged`.
- `EquipmentComponent` owns equipped items and emits `EquipmentChanged`.
- `AttributeComponent` owns raw/effective attributes and recalculation queues.
- `StatusComponent` owns active statuses and hook processing.
- `VitalComponentBase` owns current/max health-like values and emits value/depleted signals.

UI should bind to these components rather than storing parallel gameplay state.

## Autoload State

Use existing autoloads for global state and cross-scene events:

- `TimeSystem` owns day/night, current day, time progress, and map move cost.
- `GlobalEventBus.gd` declares broad gameplay signals.
- `GlobalWarehouse` provides the global warehouse scene/inventory.
- `ScreenTransitions` owns fade transitions used by map movement and combat presentation.

Do not add a new global singleton for feature-local state. Start with local scene/component ownership, then escalate to an existing autoload only when multiple unrelated scenes need the state.

## Signals

Signals are the primary synchronization mechanism between state owners and presentation:

- Components emit changes (`InventoryChanged`, `EquipmentChanged`, `ValueChanged`, `StatusChanged`, `AttributeChanged`).
- `GameplayPort` converts input requests into UI/gameplay signals.
- `passage_guard_controller.gd` emits `guard_state_changed` after guard state changes.
- `WorldInteractionCoordinator` emits `PassageGuardEncounterFinished` after passage guard combat.

Connect before triggering operations that may emit synchronously. `passage_guard_controller.gd` explicitly connects to `PassageGuardEncounterFinished` before calling `RequestPassageGuardEncounter`.

## 战斗卡牌展示节点与弃牌时序

### 1. Scope / Trigger

当玩家打出卡牌需要跨越 `CardManager` 输入状态、`PlayerHand` 手牌布局、`DeckManager` 牌堆数据、`Action` 队列载荷和 `BattleManager` 结算表现时，必须把“卡牌数据何时入弃牌堆”和“卡牌节点何时销毁”作为同一时序契约维护。触发原因是节点在飞行期间仍需存活，而牌堆数据不能被 UI 动画重复写入。

### 2. Signatures

```gdscript
class Action:
	var presentation_card: Node2D = null

	func _init(
		p_source: Variant,
		p_targets: Array,
		p_card_data: Resource = null,
		p_animation_name: String = "",
		p_action_type: String = "CARD",
		p_presentation_card: Node2D = null
	) -> void

func PlayerHand.remove_card_from_hand(card, should_play_discard_animation: bool = true) -> void
func PlayerHand.play_discard_animation(card: Node2D) -> void
func DeckManager.complete_played_card(card: Node2D) -> void
func DeckManager.play_card_to_enemy(card: Node2D, target: Node2D) -> void
func DeckManager.play_enemy_hit_feedback(target: Node2D) -> void
func CardAnimations.hit(node: Node2D, sprite: Sprite2D) -> void
```

### 3. Contracts

- `DeckManager.play_card` 必须先以 `remove_card_from_hand(card, false)` 让节点退出手牌布局，再把同一节点存入 `Action.presentation_card` 后入队；不能立即写入弃牌堆或调用渐隐销毁。
- `BattleManager._execute_single_action` 是玩家卡牌展示的唯一编排者：显式目标仍是场上怪物时，顺序固定为“飞向目标 → 目标抖动和闪白 → 原有效果结算 → 最终弃牌”。受击必须先于可能同步 `QueueFree()` 目标的伤害结算，避免外层行动队列等待已被删除节点的 Tween。
- `Action.presentation_card` 对怪物技能和普通攻击始终可选，调用方不得假设它非空；旧的五参数 `Action.new(...)` 构造方式必须继续可用。
- `DeckManager.play_card_to_enemy` 与 `DeckManager.play_enemy_hit_feedback` 在创建 Tween 前必须拒绝无效或已进入删除队列的目标；`DeckManager.complete_played_card` 是唯一允许写入主动出牌弃牌数据并启动渐隐销毁的出口，必须用节点元数据防止重复调用。
- `CardAnimations.hit` 同时启动抖动和闪白时，必须立即等待其中一个 Tween，并在之后仅等待另一个仍有效且运行中的 Tween。`Tween.finished` 是一次性信号，不能先等待较长 Tween 再无条件等待可能已经完成的较短 Tween，否则行动队列会永久保持控制锁。
- `RandomEnemy` 玩家卡牌必须在飞行前从当前敌人包装节点中随机一次，并把同一局部目标交给飞行、受击和 `SkillExecutionContext`；不能为表现和效果分别随机。自身、全体、扩散或目标失效的玩家卡牌继续跳过飞行与单体受击反馈，但仍从同一个完成出口仅一次弃牌。
- 动画原子操作复用 `CardAnimations.play_card`、`CardAnimations.hit` 和 `PlayerHand.play_discard_animation`；不要在 `BattleManager` 写入新的时长或缓动常量。

### 4. Validation & Error Matrix

| 条件 | 行为 | 结果 |
| --- | --- | --- |
| `presentation_card` 为空或节点已失效 | 跳过节点表现 | 既有行动结算不受影响 |
| 显式目标不是仍在场的怪物 | 跳过飞行与受击反馈 | 卡牌照常结算并最终弃置 |
| 显式目标已进入删除队列 | 拒绝创建飞行或受击 Tween | 不等待被终止的 Tween，行动队列继续推进 |
| `RandomEnemy` 有可用敌人 | 行动开始时随机一次并复用该节点 | 飞行、受击和伤害命中同一敌人 |
| `RandomEnemy` 没有可用敌人 | 局部目标保持空，跳过敌人表现 | 既有自身上下文回退和一次弃牌继续成立 |
| 并行受击中的较短 Tween 已完成 | 跳过对其 `finished` 的二次等待 | 避免等待不会补发的信号，行动队列继续推进 |
| 目标缺少 `Sprite2D` | 仅执行目标节点抖动 | 不因特殊怪物场景中断行动队列 |
| 已完成卡牌再次调用 `complete_played_card` | 检查完成元数据并直接返回 | 不重复写入弃牌堆、不重复 `queue_free` |
| 玩家取消、改选、切换模式或失去回合 | `CardManager.clear_click_selection(true)` 交回 `PlayerHand` | 卡牌返回标准手牌布局，不产生行动或弃牌 |
| 再次点击已选卡牌 | `CardManager.clear_click_selection(true)` | 撤销整次选择、清除目标高亮并隐藏操作栏 |
| 再次点击已选敌人 | 仅将 `_selected_click_target` 置空后刷新预览 | 已选卡牌保持上移，确认按默认自身目标施放 |
| 点击模式确认施放 | `clear_click_selection(false)` 保留节点 | 不触发归位 Tween，从选中状态连续进入飞行 |

### 5. Good / Base / Bad Cases

- Good：点击模式选择一张卡和一个在场怪物，确认后卡牌飞至该怪物、怪物抖动闪白、再结算卡牌效果并一次性进入弃牌堆渐隐；即使敌人保持存活或该效果击败怪物，行动队列都不会等待已完成或被删除节点的 Tween。
- Good：随机敌人卡牌无论点击或拖拽时指向何处，都在行动开始时随机一次；卡牌飞向该实际敌人、播放受击并对同一敌人结算伤害。
- Base：未选敌人确认施放，卡牌保留原有自身目标结算；跳过敌人飞行与命中反馈，仍只在动作完成后弃置。
- Bad：`DeckManager.play_card` 入队后立刻调用 `into_discard_pile(card)`。这会在动画开始前让节点渐隐销毁，使队列持有无效展示节点。

### 6. Tests Required

- 点击模式选中、取消、改选、模式切换和玩家失去回合：断言选中卡牌上移，并在每个非确认出口恢复 `hand_position` 且保留在 `player_hand_card`；再次点击已选卡牌必须走同一取消出口。
- 敌人目标取消：断言再次点击同一敌人只清空 `_selected_click_target`，已选卡牌与操作栏保持可用，确认时以玩家自身为默认目标。
- 显式敌人目标：断言 `Action.presentation_card` 与原手牌节点一致；断言节点先到目标位置、目标反馈先于伤害结算完成，`discard_pile_data` 只新增一次。
- 随机敌人卡牌：断言飞行和受击目标与 `SkillExecutionContext` 的主目标相同；显式点击敌人不覆盖随机结果，无敌人时跳过表现并安全回退。
- 并行受击：断言闪白先于抖动完成时，`CardAnimations.hit` 直接收尾而不等待已发射的 `finished` 信号；动作仍进入效果、弃牌并恢复输入。
- 致死目标：断言效果使怪物进入删除队列时，受击 Tween 已完成，行动队列不会永久等待且玩家输入会恢复。
- 自身、全体、扩散和失效目标：断言不调用敌人飞行/受击方法，仍完成既有 `SkillTargetingType` 结算和一次弃置。
- 重复收尾保护：对同一节点连续调用两次 `complete_played_card`，断言弃牌堆只增加一张数据，且只请求一次节点销毁。
- 兼容性：以旧五参数构造怪物 `SKILL`、`ATTACK` 行动，断言不访问展示节点且行动队列继续推进。

### 7. Wrong vs Correct

#### Wrong

```gdscript
# 节点会在 BattleManager 尚未开始飞行动画前被回收。
var action = Action.new(source, targets, card.data, "", "CARD")
battle_manager.enqueue_action(action)
into_discard_pile(card)
```

#### Correct

```gdscript
# Action 持有展示节点；唯一收尾出口负责数据入堆与渐隐。
player_hand.remove_card_from_hand(card, false)
var action = Action.new(source, targets, card.data, "", "CARD", card)
battle_manager.enqueue_action(action)

# BattleManager 行动完成后：
await deck_manager.complete_played_card(action.presentation_card)
```

## 目标选择视觉状态与怪物卡面接口

### 1. Scope / Trigger

当 `CardManager` 在点击选目标或拖拽落点预览期间，需要表达可选、悬停、主选、次选、不可选和自动选中状态时，必须通过统一的目标选择视觉状态驱动怪物卡面。该状态只服务于输入反馈，不能改变 `SkillTargetingType` 的实际目标结算、行动队列或资源消耗。

### 2. Signatures

`CardManager` 负责从卡牌目标类型和输入阶段计算 `TargetSelectionVisualState`，并通过 `_refresh_target_selection_visuals(card, primary_target, is_primary_selected, should_default_to_self)` 将状态同步到所有存活怪物。`Monster` 提供下列 GDScript 可调用的展示接口：

```csharp
public void ApplyTargetSelectionVisual(
    Vector2 targetSpriteScale,
    bool isDimmed,
    Color dimColor,
    bool showOutline,
    Color outlineColor,
    float outlineWidth,
    double duration);
public void StartTargetSelectionPulse(
    Vector2 minimumSpriteScale,
    Vector2 maximumSpriteScale,
    double halfCycleDuration);
public void StopTargetSelectionPulse();
public void ResetTargetSelectionVisual(Vector2 normalSpriteScale, double duration);
```

```gdscript
@export var target_selection_pulse_half_duration: float = 0.25
@export var target_selection_secondary_outline_color: Color = Color(0.55, 1.0, 0.65, 0.80)
@export_range(1.0, 12.0, 0.5) var target_selection_outline_width: float = 2.0
func _is_monster_card_presentation_control(control: Control) -> bool
```

### 3. Contracts

- `CardManager` 独占“目标类型 → 视觉状态”的决策权；`Monster` 只应用缩放、变暗和描边，不能自行推断技能目标类型。
- `SingleEnemy`、`AnySingleUnit` 的可选敌人呼吸缩放；悬停放大；已确认点击或拖拽预览目标为主选状态。`SpreadFromEnemy` 的相邻受影响敌人为较小倍率的次选状态。
- `AllEnemies`、`RandomEnemy`、`AllUnits` 的全部受影响敌人直接处于主选状态并显示绿色描边；这仅表示自动选择范围，`RandomEnemy` 的实际随机结算保持原逻辑。
- `Self` 仅使敌人怪物卡面变暗，不缩放或变暗玩家生命/属性 UI。任何非普通状态切换前都要停止原有呼吸 Tween；结束选牌、结束拖拽或目标离场后必须恢复正常缩放、白色调制和隐藏描边。
- 视觉缓存只能包含怪物卡面节点，必须排除 `HealthBar`，以免输入反馈污染生命条。
- 可选目标呼吸半周期固定为 `0.25` 秒（完整放大缩小周期 `0.50` 秒）；主选中/自动选中描边宽度为 `2px`、颜色为 `Color(0.25, 1.00, 0.35, 1.00)`，次级目标同宽但必须使用 `Color(0.55, 1.00, 0.65, 0.80)`。
- 点击模式检查 `gui_get_hovered_control()` 时，只有 `_is_monster_card_presentation_control` 通过父链定位到怪物根节点的展示控件可以继续执行物理卡槽点查询。设置、确认、取消、结束回合及任何非怪物 GUI 都必须继续中止世界目标选择；不得通过硬编码 `MonsterAttribute`、标签等具体节点名绕过拦截。

### 4. Validation & Error Matrix

| 条件 | 期望行为 |
| --- | --- |
| 怪物实现展示接口 | 使用 `Monster` 接口，状态变更时才创建或停止 Tween。 |
| 自定义怪物缺少展示接口 | `CardManager` 退化为操作其 `Sprite2D`，且不得中断出牌。 |
| 描边节点缺失 | 安全跳过描边，缩放和变暗仍可执行。 |
| 选牌取消、拖拽释放或目标删除 | 清空状态缓存并复位仍存活目标，不能遗留呼吸或绿色边框。 |
| 行动结算开始缩放卡面 | 必须先停止目标选择呼吸 Tween，避免两个缩放 Tween 竞争。 |
| 鼠标位于怪物名称、元素或 `MonsterAttribute` 子控件 | 沿父链识别怪物根节点后继续卡槽查询 | 点击仍选择对应敌人。 |
| 鼠标位于设置、确认、取消、结束回合或其他 GUI | 保持 GUI 输入拦截 | 不会误选怪物或改写临时目标。 |

### 5. Good / Base / Bad

- **Good：** 点击扩散牌选中主目标后，主目标以主选倍率显示绿色边框，左右相邻的实际受影响敌人以较小倍率显示更淡的绿色边框；取消选牌后全部还原。
- **Base：** 自身牌仅将所有敌人卡面变暗，同时保留原有时间轴高亮和出牌结算。
- **Bad：** 为了显示随机敌人的自动选择，提前写入随机结果或改写 `_selected_click_target`；这样会把视觉预览错误地变成结算数据。
- **Good：** 点击被 `MonsterAttribute` 标签覆盖的敌人时，卡槽仍成为主目标；点击确认按钮时则仍由 GUI 接收，不能产生敌人目标。
- **Bad：** 对所有 `gui_get_hovered_control()` 直接放行，或仅对白名单中的某个固定属性节点放行；前者会造成操作栏误触，后者会在动态状态图标或新标签出现后再次遮挡点击。

### 6. Tests Required

- 运行 `tests/godot/target_selection_visual_tests.gd`，验证主选缩放与绿色描边、不可选变暗、呼吸开始后的复位行为。
- `target_selection_visual_tests.gd` 还必须断言主描边宽度为 `2px`、次级描边使用更淡颜色，以及怪物名称、元素和 `MonsterAttribute` 子控件会被输入白名单放行、无关 GUI 不会被放行。
- 运行 `tests/godot/initial_test_deck_targeting_tests.gd`，断言 `battle.tscn` 初始牌池共 21 张，目标枚举 `Self` 至 `SpreadFromEnemy` 各至少三张。
- 手动覆盖点击与拖拽：单体、任意单位、扩散、自身、全体敌人、随机敌人和全体单位；确认悬停、确认选中、取消和释放后均无残留状态。
- 对随机敌人额外断言：视觉上可显示全部敌人自动选中，但行动结算仍由原随机目标逻辑决定。

### 7. Wrong vs Correct

#### Wrong

```gdscript
# 展示层直接决定随机结果，会改变原有结算语义。
if targeting_type == SKILL_TARGETING_TYPE.Value.RandomEnemy:
    targets = battle_manager.monster_manager.active_monsters
```

#### Correct

```gdscript
# 输入层只投影视觉状态；原目标解析函数继续承担结算结果。
_refresh_target_selection_visuals(card, hovered_target, true, false)
var targets = _resolve_intended_targets(card, hovered_target, false)
```

#### Wrong

```gdscript
# 任何 GUI 都被放行，确认按钮和设置按钮会同时触发世界输入。
if get_viewport().gui_get_hovered_control() != null:
	pass
```

#### Correct

```gdscript
# 只允许属于怪物节点树的纯展示控件穿透 GUI 拦截。
var hovered_control: Control = get_viewport().gui_get_hovered_control()
if hovered_control and not _is_monster_card_presentation_control(hovered_control):
	return
```

## Resources As Configuration State

Godot `Resource` objects are configuration, not mutable runtime stores, unless a class explicitly models runtime state. `TerrainInstance` and `ItemStack` are runtime-like `RefCounted` objects; `ItemData`, `CombatSkillData`, `MonsterData`, recipes, and settings are editable content data.

## 本地持久化玩家偏好

### 1. Scope / Trigger

当设置需要跨场景、跨战斗或跨游戏重启保留时，使用 `SettingsManager` 自动加载，而不是把偏好保存在单一场景节点或 `.tres` 资源中。当前实现位于 `core/autoloads/SettingsManager.gd`，并由 `project.godot` 以 `SettingsManager` 名称注册。

### 2. Signatures

```gdscript
func get_setting(section: String, key: String, default_value: Variant) -> Variant
func set_setting(section: String, key: String, value: Variant) -> bool
```

### 3. Contracts

- 存储文件固定为 `user://settings.cfg`；它是玩家本地数据，不能写入 `res://` 或项目配置文件。
- 读取方必须提供自己的安全默认值，并在读取后校验领域值。例如战斗操作模式只接受 `click` 或 `drag`，无效值回退到 `click`。
- 键使用稳定英文 `section/key`，显示文本与已保存键值分离。例如 `battle/operation_mode` 的显示文案可以变化，但存储值保持稳定。
- UI 组件只发出设置变更意图；领域拥有者负责值校验、写入 `SettingsManager`，并清理相关临时状态。

### 4. Validation & Error Matrix

| 条件 | `SettingsManager` 行为 | 调用方行为 |
| --- | --- | --- |
| 文件不存在 | 返回调用方默认值，不记录错误 | 使用默认值继续运行 |
| 文件无法读取或内容损坏 | 清空内存配置并记录警告 | 使用默认值继续运行 |
| 已保存值不属于领域允许值 | 原样返回给调用方 | 领域拥有者校验后回退默认值并发出警告 |
| 文件保存失败 | 保留内存中的新值并记录错误，返回 `false` | 当前会话继续使用新值；不得假称已跨重启保存 |

### 5. Good / Base / Bad Cases

- Good：战斗 `CardManager` 读取 `battle/operation_mode`，验证值后在玩家切换时调用 `set_setting`，并清除当前选卡与目标状态。
- Base：首次运行没有文件时，`get_setting(..., "click")` 直接得到点击模式。
- Bad：每个场景各自调用 `ConfigFile.load`、各自选择路径或把玩家偏好写进 `Resource`，会导致默认值和损坏恢复规则漂移。

### 6. Tests Required

- 缺失 `user://settings.cfg`：断言读取返回调用方默认值。
- 损坏设置文件：断言自动加载不阻塞场景启动，读取回退默认值并产生警告。
- 保存后重新创建自动加载：断言相同 `section/key` 返回已保存值。
- 领域校验：断言无效的 `battle/operation_mode` 进入战斗时回退为 `click`。
- UI 流程：断言设置组件仅发出模式信号，`CardManager` 才负责写入并清理临时目标选择。

### 7. Wrong vs Correct

#### Wrong

```gdscript
# 每个场景都维护自己的文件路径和默认值，未来无法保证行为一致。
var config := ConfigFile.new()
config.load("user://battle.cfg")
var mode := config.get_value("battle", "operation_mode", "click")
```

#### Correct

```gdscript
# 设置服务统一处理文件生命周期；领域代码只声明自己的稳定键和安全默认值。
var mode := str(SettingsManager.get_setting("battle", "operation_mode", "click"))
if mode != "click" and mode != "drag":
	mode = "click"
```
