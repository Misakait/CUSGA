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
func CombatFeedbackDirector._on_damage_resolved(result: RefCounted) -> void
func CombatFeedbackDirector.play_monster_attack_feedback(monster: Node) -> void
```

### 3. Contracts

- `DeckManager.play_card` 必须先以 `remove_card_from_hand(card, false)` 让节点退出手牌布局，再把同一节点存入 `Action.presentation_card` 后入队；不能立即写入弃牌堆或调用渐隐销毁。
- `PlayerHand.draw_card_data` 的容量判断与 `PlayerHand.update_hand_positions` 的位置写入都必须先从 `player_hand_card` 清除已释放或已进入删除队列的节点，再为剩余有效卡牌计算位置；节点缓存不能替代 `is_instance_valid` 校验。
- 清理实现必须遵守 `Array[Node2D]` 的取值约束：读取元素用 `Variant` 接收，删除元素用 `remove_at(index)` 按下标移除。悬空实例既不能赋给 `Node2D` 类型变量（运行期类型赋值错误），也不能作为 `erase()` 的参数（TypedArray 校验会直接拒绝），这两种写法都会让“清理”本身变成运行期错误并中止函数，使失效引用反而清不掉。
- `BattleManager._execute_single_action` 是玩家卡牌施放展示的唯一编排者：卡牌行动在显式目标仍是场上怪物时飞向目标，随后立即执行原有效果结算并最终弃牌。它不得调用 `play_enemy_hit_feedback` 预判命中；`CombatFeedbackDirector` 必须在 `DamageResolved` 后以绝对结算数值的饱和曲线播放目标受力、浮字、震屏和 Hit Stop。
- 敌方 `SKILL` 与 `ATTACK` 行动开始时，`BattleManager` 仅请求 `CombatFeedbackDirector.play_monster_attack_feedback` 播放下冲，不得等待该 Tween 或让它改变伤害目标与结算顺序。
- `Action.presentation_card` 对怪物技能和普通攻击始终可选，调用方不得假设它非空；旧的五参数 `Action.new(...)` 构造方式必须继续可用。
- `DeckManager.play_card_to_enemy` 与 `DeckManager.play_enemy_hit_feedback` 在创建 Tween 前必须拒绝无效或已进入删除队列的目标；`DeckManager.complete_played_card` 是唯一允许写入主动出牌弃牌数据并启动渐隐销毁的出口，必须用节点元数据防止重复调用。
- `CombatFeedbackDirector` 的浮字、震屏和目标 Tween 都是非权威异步表现；它们不能被行动队列 `await`。怪物逻辑死亡后立即退出目标池，导演若成功认领死亡表现才在渐隐结束时调用 `FinalizeCombatDeathPresentation()`；未认领则由怪物延迟收尾安全释放。
- 多段与范围的每条 `DamageResolved` 都必须产生独立浮字配方。`HitIndex` 用于同锚点浮字的空间布局与顺序入场；每段的延迟等于已加速浮字时长乘以索引，确保同一目标的数字不同时漂浮。`HitCount` 用 `1 / sqrt(HitCount)` 缩短浮字时长，且不得低于 `CombatFeedbackProfile.multi_hit_popup_duration_scale_min`。同一目标的受击 FIFO 仅接收 `HitIndex` 小于 `CombatFeedbackProfile.multi_hit_feedback_max_count` 的请求（默认前三次）；后续段仍保留浮字。全局冲击通过屏幕 FIFO 消费请求，但同一连续批次只播放 `multi_hit_feedback_max_count` 次实际震屏，且只允许首个有效请求触发 Hit Stop。
- `RandomEnemy` 玩家卡牌必须在飞行前从当前敌人包装节点中随机一次，并把同一局部目标交给飞行、受击和 `SkillExecutionContext`；不能为表现和效果分别随机。自身、全体、扩散或目标失效的玩家卡牌继续跳过飞行与单体受击反馈，但仍从同一个完成出口仅一次弃牌。
- 动画原子操作复用 `CardAnimations.play_card`、`CardAnimations.hit` 和 `PlayerHand.play_discard_animation`；不要在 `BattleManager` 写入新的时长或缓动常量。

### 4. Validation & Error Matrix

| 条件 | 行为 | 结果 |
| --- | --- | --- |
| `presentation_card` 为空或节点已失效 | 跳过节点表现 | 既有行动结算不受影响 |
| `player_hand_card` 留有已释放或待删除节点 | 重排前剔除无效引用 | 新抽卡和剩余手牌照常布局，不会写入已释放节点 |
| 显式目标不是仍在场的怪物 | 跳过飞行 | 卡牌照常结算；实际伤害仍由 `DamageResolved` 统一反馈 |
| 显式目标已进入删除队列 | 拒绝创建飞行 | 不等待被终止的 Tween，行动队列继续推进 |
| `RandomEnemy` 有可用敌人 | 行动开始时随机一次并复用该节点 | 飞行、受击和伤害命中同一敌人 |
| `RandomEnemy` 没有可用敌人 | 局部目标保持空，跳过敌人表现 | 既有自身上下文回退和一次弃牌继续成立 |
| 反馈目标缺少 `Sprite2D` | 导演仅执行节点受力或跳过颜色闪白 | 不因特殊怪物场景中断行动队列 |
| 导演或浮字锚点缺失 | 仅跳过对应表现项 | 同步伤害、弃牌与回合继续推进 |
| 已完成卡牌再次调用 `complete_played_card` | 检查完成元数据并直接返回 | 不重复写入弃牌堆、不重复 `queue_free` |
| 玩家取消、改选、切换模式或失去回合 | `CardManager.clear_click_selection(true)` 交回 `PlayerHand` | 卡牌返回标准手牌布局，不产生行动或弃牌 |
| 再次点击已选卡牌 | `CardManager.clear_click_selection(true)` | 撤销整次选择、清除目标高亮并隐藏操作栏 |
| 再次点击已选敌人 | 仅将 `_selected_click_target` 置空后刷新预览 | 已选卡牌保持上移；自身与自动目标牌仍按自身或固有范围施放，需要显式敌人的卡牌转为“确定”禁用 |
| 未选敌人就请求确认（`SingleEnemy`、`AnySingleUnit`、`SpreadFromEnemy`） | `CardManager._is_click_selection_target_ready` 返回 false，保留当前选择 | 不扣能量、不入队、不弃牌，也不把玩家自身当作目标；玩家补选敌人后即可再次确认 |
| 点击模式确认施放 | `clear_click_selection(false)` 保留节点 | 不触发归位 Tween，从选中状态连续进入飞行 |

### 5. Good / Base / Bad Cases

- Good：点击模式选择一张卡和一个在场怪物，确认后卡牌飞至该怪物，再结算卡牌效果；每段真实伤害由导演播放结果反馈，卡牌只一次性进入弃牌堆渐隐。
- Good：随机敌人卡牌无论点击或拖拽时指向何处，都在行动开始时随机一次；卡牌飞向该实际敌人并对同一敌人结算伤害，命中表现由该段结算结果决定。
- Base：自身与自动目标牌可以不选敌人直接确认施放，并保留原有自身或固有范围结算；跳过敌人飞行与命中反馈，仍只在动作完成后弃置。单体、任意单体与扩散牌在未选中在场敌人时由确认入口直接拒绝，不产生任何结算。
- Bad：`DeckManager.play_card` 入队后立刻调用 `into_discard_pile(card)`。这会在动画开始前让节点渐隐销毁，使队列持有无效展示节点。

### 6. Tests Required

- 点击模式选中、取消、改选、模式切换和玩家失去回合：断言选中卡牌上移，并在每个非确认出口恢复 `hand_position` 且保留在 `player_hand_card`；再次点击已选卡牌必须走同一取消出口。
- 运行 `tests/godot/test_player_hand_cache_contract.gd`（套件 `player_hand_cache_contract`）：在缓存中保留一张已释放卡牌后触发 `update_hand_positions`，断言无效引用被清理、有效卡牌仍按索引写入正确 `hand_position`；已排队删除的卡牌、以及直接调用清理入口这两条路径各自独立断言。该套件由 `test_run` 执行，清理过程本身产生的 SCRIPT ERROR 会直接判为失败。
- 旧的 `tests/godot/player_hand_lifecycle_tests.gd` 是 `extends SceneTree` runner，`test_run` 不会发现它，也没有 SCRIPT ERROR 捕获，因此不能作为该契约的验收入口；保留它只作历史参考。
- 敌人目标取消：断言再次点击同一敌人只清空 `_selected_click_target`，已选卡牌与操作栏保持可用；自身与自动目标牌仍以玩家自身或固有范围结算，需要显式敌人的卡牌则把“确定”置为禁用。
- 点击模式目标确认：运行 `tests/godot/test_click_mode_target_contract.gd`（套件 `click_mode_target_contract`），断言单体、任意单体与扩散牌在未选中在场敌人时既不能确认，也不消耗能量、不提交行动队列、不弃牌；选中在场敌人后恢复可用，已离场敌人不得通过；自身与自动目标牌不受该限制。
- 显式敌人目标：断言 `Action.presentation_card` 与原手牌节点一致；断言节点先到目标位置、随后执行伤害结算，`discard_pile_data` 只新增一次。
- 随机敌人卡牌：断言飞行目标与 `SkillExecutionContext` 的主目标相同；显式点击敌人不覆盖随机结果，无敌人时跳过飞行并安全回退。
- 结果反馈：断言 `DamageResolved` 的闪避、护盾、暴击、击杀和多段元数据分别映射正确表现；同数值的多段浮字必须保持相同强度、随 `HitCount` 加速离场并按索引顺序显示；Profile 默认配置必须只允许索引 `0..2` 入局部受击 FIFO；高频全局冲击的前三条实际震屏后必须被置零，且批次只触发一次 Hit Stop；超高数值必须受 Profile 上限钳制，行动队列不得等待这些表现 Tween。
- 致死目标：断言效果使怪物立即退出活动目标池，视觉收尾结束后才释放节点；行动队列不会永久等待且玩家输入会恢复。
- 自身、全体、扩散和失效目标：断言不调用敌人飞行方法，仍完成既有 `SkillTargetingType` 结算和一次弃置。
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

当 `CardManager` 在点击选目标或拖拽落点预览期间，需要表达可选、悬停、主选、次选、次级悬停、不可选和自动选中状态时，必须通过统一的目标选择视觉状态驱动怪物卡面。该状态只服务于输入反馈，不能改变 `SkillTargetingType` 的实际目标结算、行动队列或资源消耗。

### 2. Signatures

`CardManager` 负责从卡牌目标类型和输入阶段计算 `TargetSelectionVisualState`，并通过 `_refresh_target_selection_visuals(card, primary_target, is_primary_selected, should_default_to_self, hovered_target)` 将状态同步到所有存活怪物。`Monster` 提供下列 GDScript 可调用的展示接口：

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
- `SingleEnemy`、`AnySingleUnit` 的可选敌人呼吸缩放；悬停放大；已确认点击或拖拽预览目标为主选状态。`SpreadFromEnemy` 的相邻受影响敌人为较小倍率的次选状态；悬停已选次级目标时进入 `SECONDARY_HOVERED`，仍保留次级描边并二次放大。
- 点击模式已经确认主目标但尚未点击“确定”时，主目标必须继续保留主选中描边；当前鼠标下的其他有效敌人同时切换为 `HOVERED` 放大。若该敌人原为 `SECONDARY_SELECTED`，必须改为 `SECONDARY_HOVERED` 而非普通 `HOVERED`，以保留浅绿色范围描边；该悬停状态不能改写 `_selected_click_target`、范围结算或主目标描边。
- 点击模式中，需要显式敌人的卡牌（`SingleEnemy`、`AnySingleUnit`、`SpreadFromEnemy`）在未选中敌人时不得把玩家当作缺省目标：`_refresh_target_selection_visuals` 的 `default_to_self` 必须为 `false`，从而既不高亮玩家时间轴，也不暗示这张牌可以对自己使用；只有 `Self` 牌才以玩家自身作为缺省预览目标。同一状态下操作栏的“确定”按钮必须处于禁用状态，判断依据由 `CardManager._can_confirm_click_selection()` 提供，`ClickModeActionBar` 只负责把可用性映射到按钮。
- `AllEnemies`、`RandomEnemy`、`AllUnits` 的全部受影响敌人直接处于主选状态并显示绿色描边；这仅表示自动选择范围，`RandomEnemy` 的实际随机结算保持原逻辑。
- `Self` 仅使敌人怪物卡面变暗，不缩放或变暗玩家生命/属性 UI。任何非普通状态切换前都要停止原有呼吸 Tween；结束选牌、结束拖拽或目标离场后必须恢复正常缩放、白色调制和隐藏描边。
- 视觉缓存只能包含怪物卡面节点，必须排除 `HealthBar`，以免输入反馈污染生命条。
- 可选目标呼吸半周期固定为 `0.25` 秒（完整放大缩小周期 `0.50` 秒）；主选中/自动选中描边宽度为 `2px`、颜色为 `Color(0.25, 1.00, 0.35, 1.00)`，次级目标及次级悬停同宽但必须使用 `Color(0.55, 1.00, 0.65, 0.80)`；默认次级选中缩放为 `1.60`，次级悬停缩放为 `1.64`，且两者均低于主选中 `1.66`。
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
- `target_selection_visual_tests.gd` 必须覆盖“已确认主目标 + 悬停其他敌人”：普通可选目标应为 `HOVERED`；已选次级目标应为 `SECONDARY_HOVERED`，并断言它仍显示浅绿色描边且缩放为 `1.64`。
- `target_selection_visual_tests.gd` 还必须断言主描边宽度为 `2px`、次级描边使用更淡颜色，以及怪物名称、元素和 `MonsterAttribute` 子控件会被输入白名单放行、无关 GUI 不会被放行。
- 运行 `tests/godot/initial_test_deck_targeting_tests.gd`，断言 `battle.tscn` 初始牌池共 21 张，目标枚举 `Self` 至 `SpreadFromEnemy` 各至少三张。
- 运行 `tests/godot/test_click_mode_target_contract.gd`（套件 `click_mode_target_contract`），覆盖点击模式确认可用性：目标类型矩阵（需要显式敌人的三类必须拒绝、自身与自动目标四类必须放行）、确认入口的拒绝路径，以及操作栏“确定”按钮的禁用与恢复。
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

## 拖拽虚影与真实手牌的状态契约

### 1. Scope / Trigger

当战斗卡牌拖拽需要“保留真实手牌、以临时副本跟随鼠标选目标”时，状态仍由 `CardManager` 本地拥有。该模式的关键风险是误将展示副本传入 `DeckManager`，从而让行动队列失去真实手牌节点或让复制的碰撞节点遮挡输入。

### 2. Signatures

```gdscript
@export_range(0.0, 1.0, 0.05) var card_drag_ghost_opacity: float = 0.5
var card_being_dragged: Node2D
var _card_drag_ghost: Node2D = null

func start_drag(card: SkillCard) -> void
func _create_card_drag_ghost(card: SkillCard) -> Node2D
func _update_card_drag_ghost_position() -> Vector2
func _clear_card_drag_ghost() -> void
func finish_drag() -> void
```

### 3. Contracts

- `card_being_dragged` 始终指向真实 `SkillCard`；虚影只保存于 `_card_drag_ghost`，不得加入 `PlayerHand.player_hand_card`，更不能传给 `DeckManager.play_card` 或 `Action.presentation_card`。
- 虚影从真实卡完整复制，默认不透明度固定为 `0.5`，缩放复用 `card_drag_scale`；真实卡在拖拽开始后恢复普通手牌表现并保持原位置。
- 目标卡槽查询、手牌区释放判定和目标高亮必须使用虚影预览位置；卡牌目标类型与能量读取仍来自真实卡。
- 复制 `SkillCard` 后必须将所有虚影 `Area2D` 的碰撞层和掩码设为 `0`、关闭 `input_pickable`，并把后代 `Control.mouse_filter` 设为 `MOUSE_FILTER_IGNORE`。这是防止虚影拦截物理点查询和 GUI 鼠标的必要组合，不能只做其中一项。
- 有效释放时先隐藏并 `queue_free` 虚影，再以真实卡调用 `DeckManager.play_card`；无效释放、切换操作模式或失去玩家回合时只清理虚影和目标视觉，不产生能量、行动或弃牌副作用。

### 4. Validation & Error Matrix

| 条件 | 行为 | 结果 |
| --- | --- | --- |
| 虚影复制成功 | 将其设为 50% 不透明度、拖拽缩放并隔离输入 | 真实卡保持在手牌，虚影可安全跟随鼠标 |
| 虚影复制失败 | 记录警告，真实卡仍保持原位 | 不移动真实卡；目标判定按预览坐标安全退化 |
| 松开命中有效敌人卡槽 | 先清理虚影，再传入真实卡 | 既有行动链路从手牌区飞出真实卡 |
| 松开无效区域或手牌区 | 清理虚影与高亮 | 真实卡保留在手牌且不消耗能量 |
| 自身目标卡松开于手牌区外空白 | 清理虚影后传入真实卡 | 保留既有自身施放规则 |
| 模式切换、输入锁定或回合结束 | 调用统一虚影清理出口 | 无残留节点、卡槽高亮或过期拖拽状态 |

### 5. Good / Base / Bad Cases

- Good：拖到敌人时，玩家同时看到原位真实卡和 50% 透明虚影；松开后虚影消失，真实卡从手牌位置飞向该敌人。
- Base：拖到无效位置时，虚影消失，真实卡没有归位 Tween，因为它从未离开手牌布局。
- Bad：直接移动 `card_being_dragged` 作为拖拽预览，或把 `_card_drag_ghost` 传给 `DeckManager.play_card`。前者破坏“原卡留在原地”，后者会让行动展示与手牌数据脱节。

### 6. Tests Required

- `tests/godot/target_selection_visual_tests.gd` 必须断言虚影是独立节点、真实卡位置未变化、虚影不透明度为 `0.5` 且缩放等于 `card_drag_scale`。
- 同一测试必须断言虚影 `Area2D` 的碰撞层/掩码为 `0`、`input_pickable` 为 false，且卡面 `Control` 使用 `MOUSE_FILTER_IGNORE`。
- 手动或场景级流程需要覆盖：有效敌人释放只扣一次能量并让真实卡飞行；无效释放与模式/回合取消不残留虚影或目标高亮。

### 7. Wrong vs Correct

#### Wrong

```gdscript
# 移动的是真实卡，之后它不能从原手牌位置自然飞出。
card_being_dragged.position = get_global_mouse_position() + drag_offset
deck_manager.play_card(card_being_dragged, target)
```

#### Correct

```gdscript
# 虚影只承担预览；真实卡是唯一进入行动队列的节点。
_card_drag_ghost.position = _get_drag_preview_position()
_clear_card_drag_ghost()
deck_manager.play_card(card_being_dragged, target)
```

## Resources As Configuration State

Godot `Resource` objects are configuration, not mutable runtime stores, unless a class explicitly models runtime state. `TerrainInstance` and `ItemStack` are runtime-like `RefCounted` objects; `ItemData`, `CombatSkillData`, `MonsterData`, recipes, and settings are editable content data.

## 本地持久化玩家偏好

### 1. Scope / Trigger

**先分清两类跨运行数据，它们的正确行为不同，因此走两套机制：**

| 数据 | 机制 | 为什么 |
| --- | --- | --- |
| 玩家**偏好**（`battle/operation_mode`、`battle/feedback_intensity`） | `SettingsManager` → `user://settings.cfg` | 读坏了可以无痛回退默认值，丢掉不可惜 |
| 玩法**进度**（仓库物品、带入栏、金币、容量升级等级） | `SaveManager` → `user://save/game_save.json` | 读坏了必须保留现场、尽量恢复，绝不可静默丢档 |

偏好走 `SettingsManager` 自动加载，而不是把偏好保存在单一场景节点或 `.tres` 资源中。当前实现位于 `core/autoloads/SettingsManager.gd`，并由 `project.godot` 以 `SettingsManager` 名称注册。

**进度绝不要写进 `SettingsManager`。** 2026-09-24 的存档系统任务把金币与容量升级等级从 `SettingsManager` 迁出，原因正是两者的损坏恢复策略会互相牵制：`ConfigFile` 读坏时只能清空回退默认值，而这个行为用在进度上等于静默删档。进度的接入方式见「存档系统与参与者协议」一节。

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
## 存档系统与参与者协议

### 1. Scope / Trigger

当某个系统的状态需要**跨游戏重启保留**，或需要**为新一局重置**时，接入 `SaveManager` 参与者协议。存档层位于 `core/save/`（`save_manager.gd` + `save_slot_codec.gd`），只负责文件生命周期、作用域分流与分发，不认识任何玩法数据。

### 2. Signatures

```gdscript
# 参与者必须实现的 5 个方法（缺任何一个都会被拒绝注册）
func save_key() -> String
func save_scope() -> String
func save_change_signals() -> Array
func capture_save_data() -> Dictionary
func apply_save_data(data: Dictionary) -> bool

# 参与者调用的存档层入口
SaveManager.register_participant(self)
SaveManager.request_save()
SaveManager.clear_run_scope()
```

### 3. Contracts

- 参与者在自己的 `_ready()` 里注册；`SaveManager` 必须是 `project.godot` `[autoload]` 的**第一项**。注册会**同步**把存档分发下去，因此参与者必须保证「`_ready()` 返回时已经能接收数据」。这个顺序是硬约束：`Main.tscn` 的开局初始化会在自己的 `_ready()` 里读取已恢复的带入栏，若存档层排在参与者之后，分发退化成延迟执行，带入内容会**静默消失**。该顺序由 `tests/test_save_system_contract.gd` 锁定。
- `save_key()` 是稳定标识，发布后不可修改；改键等价于清空该数据。
- `save_scope()` 只返回 `"global"`（跨运行）或 `"run"`（仅本局）。
- `apply_save_data()` 的语义是**先清空再写入**，不是叠加——存档是唯一真相源，叠加会产生「玩家已经挪走的物品重开游戏又出现」这类幽灵物品。
- `request_save()` 是 0.5 秒防抖的合并请求；`apply()` 期间到达的变更请求被**丢弃**而非延迟（那是读档造成的回声，落盘只会重写相同内容并掩盖真实写入错误）。
- 跨运行隔离靠开局调用 `clear_run_scope()`，**不是**靠不把 `run` 写进文件——`run` 数据要落盘，将来「继续本局」才有东西可读。
- 不要用 `:=` 从 `Variant` 表达式推断类型：本项目把 `inference_on_variant` 当错误。跨脚本访问走 `call` / `get` / `has_method`；脚本引用用 `const X: GDScript = preload(...)` 再 `.call("静态方法", ...)`。
- 参与者不要直接引用 autoload 标识符，用 `const X_PATH: NodePath = ^"/root/X"` + `get_node_or_null(X_PATH)`；否则 `test_run`（没有 autoload）连解析都过不去。
- 数值字段必须过类型校验再 `int()`：JSON 解析出的数字统一是 `float`。

### 4. Validation & Error Matrix

| 条件 | 存档层行为 | 参与者行为 |
| --- | --- | --- |
| 存档文件不存在 | `has_save()` 为 `false`，分发给参与者空数据 | 保持自身默认值 |
| `format_version` 不符 / JSON 非法 / `data` 非字典 | 损坏内容保留为 `.corrupt` → 尝试从 `.bak` 恢复 → 都不可用才以默认值启动，并 `push_error` 说明原因 | 收到空数据后回退默认值 |
| 存档里的 `card_id` 已不存在 | 只跳过该槽位并计数告警，其余槽位正常水合 | 正常写入能水合的槽位 |
| 存档内容越界（等级超过上限、金币为负） | 原样交给参与者 | 收窄到合法范围并告警（`_sanitize_*`） |
| 写入失败 | `push_error` 并返回 `false`，不假装成功 | 内存状态仍有效；日志必须让「没存上」这件事可见 |
| 参与者缺少协议方法 / 作用域非法 | 拒绝注册并给出可诊断错误，不进入注册表 | — |
| 同一 `save_key` 重复注册 | 替换旧参与者并**断开其声明的信号** | — |

### 5. Good / Base / Bad Cases

- Good：`GlobalWarehouse` 在 `_ready()` 里注册，`apply_save_data` 先 `EnsureCapacityAtLeast` 再清空重写，存档槽位多于当前容量时自动扩容而不是丢弃物品。
- Base：首次运行无存档，4 个参与者全部保持默认值（金币 1200、仓容 27、仓库与带入栏为空）。
- Bad：直接给 `player_level.gd` 加协议、只存 `level` / `experience`。每局的属性组件会按基础值重建，于是「等级 50」与「属性点 0」共存，而等级已满又永远不会再发放点数——**永久销毁 147 点属性点**。等级属于局内概念，其跨运行保存必须先设计局内进度的重启语义（`player_level.gd` 目前没有任何清零入口）。

### 6. Tests Required

`tests/godot/test_save_system_contract.gd`（经 `tests/test_save_system_contract.gd` 转发壳被 `test_run` 发现；`test_run` 只扫描 `res://tests` 顶层）：

- 脚本形状与注册：生产脚本存在、带 uid 旁车、无 `class_name`；`SaveManager` 是 `[autoload]` 第一项；4 个参与者都实现 5 个方法。
- 协议校验：缺方法的桩被拒绝注册且产生可诊断错误；非法作用域被拒绝；同键重复注册替换旧参与者并断开旧信号。
- 编解码：往返后物品身份/数量/洗炼属性/槽位序号逐一相等，空槽位保持 `null`；未知 `card_id` 只跳过该槽位。
- 洗炼属性：物品声明了 `AttributeBonuses` 时按声明求交集；**未声明时只做类型校验、不丢弃**（「无法判断」不等于「非法」）。
- 版本与损坏：版本不符 / 非法 JSON / `data` 非字典 → 保留 `.corrupt`、从 `.bak` 恢复、不抛错。
- 原子写入：`.tmp` 不残留、`.bak` 等于**上一次**写入的内容、主档等于最新内容。
- 防抖与回声：一次窗口内多次请求只写一次；`apply` 期间不产生落盘。
- 4 个参与者的 `capture → apply` 往返与越界收窄。

运行期（`test_run` 没有 autoload，覆盖不到时序）：`project_run(mode="custom", scene="res://scenes/Main.tscn")` + `game_eval` 断言二次启动后仓库/带入栏/金币/等级均已恢复，且**带入栏已被开局消费、内容出现在玩家背包里**——这是「注册即同步分发」唯一可被真正证伪的地方。

### 7. Wrong vs Correct

#### Wrong

```gdscript
# 把进度当偏好存：ConfigFile 读坏只能清空回退默认值，用在进度上等于静默删档。
_settings_manager.set_setting("player", "gold", Gold)

# 参与者注册排在存档层之前 → 开局读到的是空带入栏。
# project.godot: GlobalWarehouse=... 写在 SaveManager=... 之前
```

#### Correct

```gdscript
# 参与者只声明自己的键、作用域与触发信号，文件生命周期全部交给存档层。
const SAVE_MANAGER_PATH: NodePath = ^"/root/SaveManager"

func _ready() -> void:
	var save_manager: Node = get_node_or_null(SAVE_MANAGER_PATH)
	if save_manager != null:
		save_manager.call("register_participant", self)

func save_key() -> String:
	return "player_wallet"

func save_scope() -> String:
	return "global"

func save_change_signals() -> Array:
	return ["GoldChanged"]
```

## SceneManager 的 init() 会在初始场景进树之前被调用

### 1. Scope / Trigger

当场景控制器把 `init()` / `exit()` 作为 SceneManager 的生命周期入口（`warehouse_control.gd`、`shop_control.gd`），并且需要在 `init()` 里访问自己场景的子节点时，必须遵守本节契约。触发原因是 `SceneManager._ready()` 会对**初始场景**调用 `init()`，而那一刻该场景**还没有进入场景树**。

### 2. Signatures

```gdscript
# core/autoloads/SceneManager.gd
func _ready() -> void:
	var initial_scene: Node = get_tree().current_scene
	if initial_scene:
		_cache["main_menu"] = initial_scene
		_current_id = "main_menu"
	GlobalEventBus.scene_requested.connect(_on_scene_requested)
	if initial_scene and initial_scene.has_method("init"):
		initial_scene.init()          # ← 此时 initial_scene 尚未 add_child

func _switch_to(target_id: String, target_path: String) -> void:
	...
	get_tree().root.add_child(target)  # ← 切换场景时才是先入树
	get_tree().current_scene = target
	...
	if target.has_method("init"):
		target.init()
```

### 3. Contracts

- 场景控制器**不得**用 `@onready` 保存自己场景内的节点引用并在 `init()` 里使用：`@onready` 只在进入树时求值，初始场景路径下它全是 `null`。
- 需要子节点引用时，在 `init()` 里用 `get_node_or_null("路径")` 解析。子节点在 `instantiate()` 之后就存在，与是否入树无关。
- `@export var x: Node2D` / `@export var x: Control` 形式的 NodePath 导出**可以**安全使用：它们在实例化时求值，不受入树时机影响。`warehouse_control.gd` 与 `inventory_control.gd` 用的是这一种。
- 同一个场景控制器还要能在被 `_switch_to` 切换进入时正确工作，因此节点解析要么每次 `init()` 都重做，要么做成幂等且不依赖入树状态。
- 若控制器想让「直接用 `--scene res://场景.tscn` 运行」也能看到完整界面，可以在自己的 `_ready()` 里再调一次 `init()`；前提是 `init()` 幂等（不重复创建子节点、不重复连接信号）。

### 4. Validation & Error Matrix

| 条件 | 症状 | 结果 |
|---|---|---|
| 控制器用 `@onready` 存子节点，且该场景被当作初始场景运行 | `Cannot call method 'X' on a null value`、`Invalid assignment ... on a base object of type 'Nil'` | 整屏引用集体失效 |
| 控制器用 `@onready` 存子节点，走 SceneManager 正常切换进入 | 无异常 | `add_child` 先于 `init()`，`@onready` 已求值 |
| 子节点自己（例如格子的脚本）也用 `@onready` | 即使父节点已入树，若父节点**未**入树则 `add_child` 不会触发子节点的 `_ready`，其 `@onready` 仍为 `null` | 格子绑定物品时报 null |
| 找不到节点 | 后续操作在 `null` 上逐条报错 | 应在解析处 `push_error` 一次性给出明确指向 |
| 解析失败但已把「已构建」标志置位 | 之后再也不重试 | 只有解析成功才置位，让下一次 `init()` 有机会重试 |

### 5. Good / Base / Bad Cases

- Good：`shop_control.gd` 在 `init()` 开头调 `_resolve_nodes()`，用 `get_node_or_null` 解析全部 UI 引用；`_ready()` 也调一次 `init()`，因此直接运行 `Shop.tscn` 与经 SceneManager 切换进入都能正常显示。
- Base：`warehouse_control.gd` 用 `@export var inventory_grid: Node2D` / `@export var inventory_control: Control`，导出路径在实例化时解析，绕开了这个时机问题。
- Bad：在场景控制器里写 `@onready var _status_label: Label = $UILayer/Root/StatusLabel`，然后在 `init()` 里 `_status_label.text = ...`。直接运行该 `.tscn` 时 `_status_label` 为 `null`，界面一片空白且报一堆 `Nil` 错误。

### 6. Tests Required

- 行 `godot --headless --path . --scene res://<场景>.tscn --quit-after 10` 直接运行场景，断言输出中没有 `SCRIPT ERROR`、`Cannot call method ... on a null value`、`Invalid assignment ... 'Nil'`。这条命令走的正是「初始场景」路径，是唯一能廉价覆盖该时机的检查。
- 断言场景的 `init()` 连续调用两次不产生重复子节点、不产生重复信号连接。

### 7. Wrong vs Correct

#### Wrong

```gdscript
# @onready 在初始场景路径下尚未求值，init() 里访问全是 null。
@onready var _status_label: Label = $UILayer/Root/StatusLabel

func init() -> void:
	_status_label.text = ""     # Cannot assign to null
```

#### Correct

```gdscript
# 子节点在 instantiate() 之后就存在，与是否入树无关，因此在 init() 里解析。
var _status_label: Label = null

func init() -> void:
	_resolve_nodes()
	_status_label.text = ""

func _resolve_nodes() -> void:
	_status_label = get_node_or_null("UILayer/Root/StatusLabel")
	if _status_label == null:
		push_error("场景节点结构与脚本预期不符，请检查 UILayer/Root 下的子节点名称。")
```

### 已知的既有缺陷（未修复）

`warehouse_control.gd` 的 `init()` 会访问 `inventory_control.inventory`，而 `inventory` 是 `inventory_control.gd` 的 `@onready` 变量。把 `Warehouse.tscn` 当作初始场景直接运行时必然报 `Invalid call. Nonexistent function 'CopySlotsFrom' in base 'Nil'`。走 `main_menu` 启动再经 SceneManager 切换进入仓库不会触发。新增场景控制器时不要复制这个写法。

## 开局信号是同步广播的，晚就绪的消费方必须补一次状态查询

### 1. Scope / Trigger

需要挂接 `Main.tscn` 里某个开局流程节点的完成信号，而消费方在**树顺序**上排在生产者之后时。典型：`core/gameflow/run_start_initializer.gd` 广播 `RunStartInitialized`，抽卡界面挂在 `UI/HUDLayer/HUDRoot` 下。

### 2. Signatures

```gdscript
# 生产者：core/gameflow/run_start_initializer.gd
signal RunStartInitialized
func _ready() -> void:
	Initialize()                   # 同步完成
	RunStartInitialized.emit()     # 同步广播——此刻晚就绪的兄弟节点还没 _ready
func HasInitialized() -> bool:     # 供消费方查询完成态
	return _has_initialized

# 消费方：core/gameflow/run_start_skill_card_draft.gd
func _connect_initializer() -> void:
	if initializer.has_signal(&"RunStartInitialized"):
		initializer.connect(&"RunStartInitialized", Callable(self, "_on_run_start_initialized"))
	# 订阅之后必须再补一次完成态查询：只 connect 会永远等不到那次同步广播
	if initializer.has_method("HasInitialized") and bool(initializer.call("HasInitialized")):
		_on_run_start_initialized()
```

### 3. Contracts

- 同级 `_ready` 按**树顺序**触发。生产者排在前面时，它的同步广播发生在消费方 `_ready` 之前，消费方的 `connect()` 不可能收到那一次信号。
- 正确做法是**订阅 + 完成态补偿查询**：`connect()` 覆盖"以后才完成"，查询覆盖"已经完成"，两条路径汇入同一个处理函数，由内部的幂等标志（如 `_has_drafted`）去重。
- **不要**用"把消费方节点挪到生产者之前"来规避：那只是把时序依赖藏进场景文件，日后谁调整节点顺序，功能就静默失效。
- 生产者侧只暴露一个纯查询方法即可，**不要**把同步流程改成异步（`call_deferred`、`await get_tree().process_frame`、定时器）来迁就消费方——那会把确定性的开局时机变成竞态。

### 4. Validation & Error Matrix

| 现象 | 真实原因 | 处理 |
|---|---|---|
| 开局环节完全不触发，且日志无任何报错 | 消费方只 `connect()`，广播已在其 `_ready` 之前发完 | 加完成态补偿查询 |
| 开局环节触发两次 | 订阅路径与补偿路径都命中，处理函数缺幂等标志 | 处理函数首行查标志并置位 |

### 5. Good / Base / Bad Cases

- Good：`run_start_skill_card_draft.gd` 的 `Setup()` → `_connect_initializer()`，两条路径都由 `_has_drafted` 去重，且运行期 `game_eval` 证实补偿路径就是生产实际走的那条。
- Bad：`initializer.connect(&"RunStartInitialized", ...)` 之后就认为"已经挂好了"。

### 6. Tests Required

- 契约测试必须**分别**驱动两条路径：夹具用桩的 `Initialized` 开关造出"未完成"（随后手动广播信号）与"已完成"（构造即触发）两种情形。
- 因为广播同步、消费方可能晚就绪，只测信号路径**无法**发现"补偿缺失"——两条断言缺一不可。
- 夹具要复刻生产层级，使脚本里 `../../../../` 这类相对导出默认值也被真实解析。

### 7. Wrong vs Correct

#### Wrong

```gdscript
func _ready() -> void:
	initializer.connect(&"RunStartInitialized", _on_run_start_initialized)
	# 生产者已在本节点 _ready 之前广播过 → 这一行之后再也不会触发
```

#### Correct

```gdscript
func _ready() -> void:
	initializer.connect(&"RunStartInitialized", _on_run_start_initialized)
	if bool(initializer.call("HasInitialized")):     # 补上"已经完成"这一格
		_on_run_start_initialized()
```

## 全局暂停会冻住过渡动画与局内 UI

### 1. Scope / Trigger

代码里出现 `get_tree().paused = true`（暂停菜单、天赋界面、开局抽卡界面等），并且场景中还存在依赖 `AnimationPlayer` / `Tween` 的**全局视觉反馈**（`ScreenTransitions` 的场景切换黑幕就是），或者需要玩家在暂停期间继续操作的界面。

### 2. Signatures

```gdscript
# 暂停方
get_tree().paused = true

# 暂停期间仍要能点：在**界面场景的根节点**上设 PROCESS_MODE_ALWAYS（.tscn 里是 process_mode = 3）
[node name="SkillCardDraftScreen" type="Control"]
process_mode = 3

# 全局过渡也必须无视暂停（ScreenTransitions.tscn 根节点）
[node name="SceneTransitions" type="Node"]
process_mode = 3
```

### 3. Contracts

- `paused = true` 会停住所有 `PROCESS_MODE_INHERIT` / `PROCESS_MODE_PAUSABLE` 节点的处理，**其中包含 `AnimationPlayer` 与 `Tween`**。这不是"逻辑不动"，而是"动画时间轴停住"。
- 因此 `ScreenTransitions.fade_in()` 这类实现（`show()` → `play()` → `await animation_finished` → `hide()`）一旦在中途遇到暂停，就**永远等不到 `animation_finished`**，黑幕永久停在 `alpha = 1`。表现是**整屏像素级全黑**，而所有业务数据（抽卡张数、背包内容、`paused` 标志）全部正常——极易误诊为"某块遮罩太黑"。
- 暂停期间仍要接受点击的界面必须在**场景根节点**设 `process_mode = 3`：Godot 的 GUI 分发用 `Control.can_process()` 过滤事件，INHERIT 的控件在暂停下 `can_process()` 为 `false`，**按钮点不动且没有任何报错**。既有先例：`scenes/ui_scenes/pause_menu.tscn`、`scenes/talents/talent_screen.tscn`。
- 判断某个 CanvasItem 是否受暂停影响，用 `can_process()` 直接读，不要靠推理：ALWAYS 下为 `true`，INHERIT 下为 `false`。
- **不要**用"让调用方先等过渡结束再暂停"来绕过：那会把时序依赖散到每个调用点，且新调用点必然再犯。

### 4. Validation & Error Matrix

| 现象 | 真实原因 | 处理 |
|---|---|---|
| 暂停后整屏全黑，业务数据全对 | 过渡黑幕的动画被暂停冻住，`FadeToBlack` 永久 `alpha = 1`，且它在高 `layer` 上盖住一切 | 给过渡节点设 `process_mode = 3` |
| 暂停期间按钮点不动、无报错 | 控件为 INHERIT，暂停下 `can_process()` 为 `false`，GUI 事件被过滤 | 界面场景根节点设 `process_mode = 3` |
| 看不到界面但 `visible` 为 `true`、尺寸正常 | 有更高 `layer` 的 CanvasLayer 盖住（如过渡层 `layer = 20`） | 列出所有 CanvasLayer 比较 `layer` |

### 5. Good / Base / Bad Cases

- Good：`ScreenTransitions.tscn` 根节点设 `process_mode = 3`；`skill_card_draft_screen.tscn` 同样设 3。运行期验证：暂停中调 `fade_in()`，1 秒后 `FadeToBlack.visible == false` 且 `get_tree().paused` 仍为 `true`。
- Base：`PauseMenu` 与天赋界面早已是 `process_mode = 3`，新界面照抄即可。
- Bad：只断言"界面 `visible = true`、尺寸 1280×720、`modulate` 正常"就认为界面可见——这些在整屏全黑时同样成立。

### 6. Tests Required

- 场景形状断言：抽卡/暂停类界面场景的根节点含 `process_mode = 3`；过渡场景也含 `process_mode = 3`（去掉它就会让黑屏回归）。
- 运行期断言：`get_viewport().get_texture().get_image()` 全屏网格采样，非黑像素比例必须 > 0；只做业务数据断言无法发现全黑屏。
- 运行期断言：暂停中调 `ScreenTransitions.fade_in()` 后等待，断言黑幕 `visible == false`。

### 7. Wrong vs Correct

#### Wrong

```gdscript
# 暂停了游戏，又指望依赖 AnimationPlayer 的过渡动画自己走完
get_tree().paused = true
fade_in()                       # await animation_finished 永远不返回 → 黑幕永久 alpha=1
```

#### Correct

```ini
; ScreenTransitions.tscn —— 过渡动画无视暂停
[node name="SceneTransitions" type="Node"]
process_mode = 3
```

## 局内战斗的 UI 宿主：battle.tscn 是 Main 的子节点

### 1. Scope / Trigger

当需要新增一个「在局外游玩与局内战斗中都可用」的 HUD 浮层、快捷键或调试面板时。触发原因是局内战斗**不切换 `current_scene`**，因此挂在 `Main` 上的 UI 在战斗期间依然存活——这决定了浮层该挂在哪里。

### 2. Signatures

```gdscript
# core/gameflow/world_interaction_coordinator.gd
const BATTLE_SCENE_PATH: String = "res://scenes/battle_scenes/battle.tscn"
```

```text
Main                                  ← current_scene，始终存活
├─ UI
│  └─ HUDLayer (CanvasLayer)          ← 局外与局内战斗都存活
│     └─ HUDRoot (Control)
│        ├─ TopLeftPanel / BackpackButton / CenterOverlay / TooltipPanel
│        └─ DevSettingsUI             ← 开发者设置浮层挂在这里
└─ <battle.tscn 实例>                  ← 战斗期间作为 Main 的子节点挂载
```

### 3. Contracts

- 局内战斗把 `battle.tscn` 作为 `Main` 的**子节点**挂载，`get_tree().current_scene` 仍然是 `Main`。`scripts/ui_scripts/status_effect_bar.gd` 的注释（「局内触发的战斗会把 battle.tscn 挂在世界主场景 Main 之下」）是同一事实的另一处记录。
- 因此 `Main/UI/HUDLayer/HUDRoot` 是**唯一**在两种状态下都存活的 UI 宿主。需要跨状态可用的浮层挂在这里，不必新增 Autoload，也不必在 battle 场景里重复一份。
- 战斗场景内定位玩家/怪物时不能依赖 `current_scene`，也不能依赖全局分组的首顺位，必须沿祖先链找最近的战斗节点（`status_effect_bar.gd` 就是这么做的）。
- 独立运行 `battle.tscn`（`project_run(mode="custom", scene="res://scenes/battle_scenes/battle.tscn")`）时没有 `Main` 祖先，只挂在 `Main` 上的 UI 不会出现——这是预期行为，不是缺陷。
- 全屏浮层的根 `Control` 应设 `mouse_filter = MOUSE_FILTER_IGNORE` 并默认 `visible = false`，避免隐藏时仍拦截 HUD 的鼠标事件；需要居中的内容交给全屏 `CenterContainer`，不要只给子面板设 0.5 锚点（offsets 为 0 会把它推到右下角）。

### 4. Validation & Error Matrix

| 条件 | 结果 |
|---|---|
| 浮层挂在 `Main/UI/HUDLayer`，局外游玩 | 可用 |
| 浮层挂在 `Main/UI/HUDLayer`，局内战斗 | 可用（`Main` 仍是 `current_scene`） |
| 浮层挂在 `battle.tscn` 内，局外游玩 | 不可用 |
| 浮层用 `get_tree().current_scene` 反查自身 | 战斗中拿到 `Main`，可能取到错误节点 |
| 浮层根节点 `mouse_filter` 保持默认且 `visible = false` | 隐藏时仍可能吞掉 HUD 点击 |

### 5. Good / Base / Bad Cases

- Good：开发者设置浮层挂在 `Main/UI/HUDLayer/HUDRoot`，用 `_unhandled_input` 监听隐藏序列，局外与局内战斗都能打开。
- Base：战斗专用 UI（`BattleSettingsPanel`）挂在 `battle.tscn` 内，只在战斗中存在，职责清晰。
- Bad：为了「全局可用」而新增一个 Autoload 承载 HUD 浮层——项目已有 `Main/UI/HUDLayer` 这个跨状态宿主，新增 Autoload 只会扩大全局面。

### 6. Tests Required

- 场景冒烟：分别 `project_run(mode="custom", scene="res://scenes/Main.tscn")` 与 `res://scenes/battle_scenes/battle.tscn`，`logs_read(source="game")` 断言无 `SCRIPT ERROR`。
- 若浮层需要在真实游戏里可用，必须用 `game_eval` 在**运行中的游戏进程**里断言：节点存在、`visible` 状态正确、`get_tree().paused` 未被意外改变。编辑器 `test_run` 的环境没有 Autoload 与 `Main` 实例，无法覆盖这条。

### 7. Wrong vs Correct

#### Wrong

```gdscript
# 战斗中 current_scene 是 Main，这个反查会拿到世界主场景而不是战斗场景。
var battle := get_tree().current_scene
```

#### Correct

```gdscript
# 从自身沿祖先链向上查找最近的战斗节点（status_effect_bar.gd 的做法），
# 独立运行 battle.tscn 时结果同样正确。
var battle_root := _find_ancestor_battle_root()
```

### 附注：GDScript 脚本常量可以经实例读取

`TimeSystem` 的阶段长度是脚本常量 `PhaseLength`，它**可以**通过实例动态读取：

```gdscript
var phase_length: int = int(TimeSystem.get("PhaseLength"))
```

原因是 Godot 的 `GDScriptInstance::get()` 先查成员变量，再沿脚本继承链查常量表。因此 UI 不必再复制一份 `const PHASE_LENGTH = 100`（`time_panel_ui.gd` 的旧写法）就能跟随时间系统的值；`core/ui/dev/dev_settings_ui.gd` 用这条路径计算「下一天」。仍应保留本地兜底值：读不到时不能让面板整体失效。

## 内联子资源的运行时可变态由所有场景实例共享

### 1. Scope / Trigger

当 `.tscn` 用 `[sub_resource]` 内联一个脚本资源，而该脚本声明了**非 `@export` 的可变字段**，并且承载它的场景会被重复实例化时。既有实例：`main_menu.tscn` 的 `Resource_v5kme`（`Snapper.snapped_cards`）与 `Resource_r5auf`（`Draggable.dragging` / `drag_offset`）。

### 2. Signatures

```gdscript
# resources/draggable/snapper.gd
var snapped_cards: Dictionary = {}          # {card: snap_position} —— 跨实例共享
func can_snap(card, pos: Vector2) -> bool   # 判据是 snapped_cards.values().has(pos)
func prune_snapped_cards() -> int           # 丢弃已释放 / 已离场的记录

# resources/draggable/snapper_binder.gd
func update_snapper_positions() -> void     # 在 _ready() 中调用
```

### 3. Contracts

- `[sub_resource]` 在 Godot 实例化场景时**逐实例复用同一个对象**。因此非 `@export` 的可变字段是**跨实例的共享状态**，不是「每个场景一份」。
- 依赖这类字段做占用判定时，必须显式定义**记录的生命周期**。`Snapper.snapped_cards` 的不变量是「记录只能属于此刻仍在场景树上的卡牌」，因此 `SnapperBinder.update_snapper_positions()` 必须在重建吸附坐标前调用 `prune_snapped_cards()`。
- 清理失效引用必须**先 `is_instance_valid(obj)` 再 `obj as Node` 收窄类型**；顺序颠倒会让清理函数自身在已释放对象上抛错，失效引用反而清不掉（与 TypedArray 的清理约束同源）。
- 本函数在 `_ready()` 中调用，此刻本实例的卡牌刚进树、尚未参与拖拽，因此清理不会误删本轮的有效记录。
- `Draggable.dragging` / `drag_offset` 是同类共享字段，但每次鼠标按下都会重算，故当前无害；给这类资源新增字段时不要假设它属于单个实例。

### 4. Validation & Error Matrix

| 条件 | 行为 | 结果 |
|---|---|---|
| 旧实例的卡牌已被释放 | `is_instance_valid` 为 false | 记录在重建吸附坐标时被清理 |
| 旧实例的卡牌仍存活但已离场 | `is_inside_tree()` 为 false | 同上 |
| 本实例的卡牌刚进树 | 两条判据都为 true | 记录保留，不误删 |

### 5. Good / Base / Bad Cases

- Good：`SnapperBinder._ready()` → `update_snapper_positions()` 先 prune 再重建坐标，主菜单在多轮「进游戏 / 进仓库 / 回主菜单」之后仍能拖动任意卡牌。
- Base：`Draggable` 的共享字段每次按下都被覆盖，行为可接受。
- Bad：让 `Snapper.snapped_cards` 永久保留旧记录。吸附点坐标被已离场卡牌占死，`can_snap()` 恒返回 false，`drag_func.finish_drag()` 因 `snapped == false` 永不发射 `card_be_snapper`，表现为主菜单所有卡牌拖进吸附点毫无反应——既进不了游戏也打不开仓库。

### 6. Tests Required

- 运行期断言（`game_eval`）：走完「主菜单 → 开始游戏 → 暂停退出 → 进仓库 → 操作仓库 → 回主菜单」后，断言新主菜单实例的 `snapped_cards.size() == 0`，且拖动任一卡牌能真正切换场景。
- 同一路径上还要断言 `SceneManager._cache` 的值全部 `is_instance_valid`，且 `get_tree().root` 下只有一个场景实例。

### 7. Wrong vs Correct

#### Wrong

```gdscript
func update_snapper_positions():
	if target_snapper:
		target_snapper.snap_positions.clear()   # 只重置坐标，旧记录继续占位
```

#### Correct

```gdscript
func update_snapper_positions():
	if target_snapper:
		target_snapper.prune_snapped_cards()    # 先丢弃已离场实例的记录
		target_snapper.snap_positions.clear()
```

## SceneManager 只复用缓存池里的实例，临时场景必须释放

### 1. Scope / Trigger

当 `SceneManager._switch_to()` 要移除「当前场景」，而该场景**不在 `_cache` 中**时。产生这种场景的路径是 `main_menu.gd`（开始游戏）与 `pause_menu.gd`（退出游戏）用 `change_scene_to_file` 直接加载场景：它们让新场景成为 `current_scene`，但 `_cache` 与 `_current_id` 仍停在旧值。

### 2. Signatures

```gdscript
# core/autoloads/SceneManager.gd
func _switch_to(target_id: String, target_path: String) -> void
```

### 3. Contracts

- `_cache` 里的实例才允许「`remove_child` 后留着复用」；其余必须 `queue_free()`。
- 判据用 `_cache.values().has(current)`，不要用「`_current_id` 是否命中」：上述路径下 `_current_id` 与 `current_scene` 本就不同步。
- 未释放的临时场景会变成**永久孤儿**：子节点、内联子资源与信号连接继续存活，并污染后续同场景实例的状态（见上一节）。
- 「先判 `is_instance_valid` 再决定移除谁」的既有逻辑保持不变。

### 4. Validation & Error Matrix

| 条件 | 行为 | 结果 |
|---|---|---|
| 当前场景在 `_cache` 中 | 只 `remove_child` | 保留复用，符合缓存设计 |
| 当前场景不在 `_cache` 中 | `remove_child` + `queue_free()` | 不产生孤儿节点 |
| 缓存实例已被 Godot 释放 | `is_instance_valid` 为 false → erase → 回退到 `current_scene` | 不撞已释放实例 |

### 5. Good / Base / Bad Cases

- Good：进仓库时把 `change_scene_to_file` 载入的临时主菜单释放掉，切换前后孤儿节点数不增长。
- Bad：一律 `remove_child` 而不释放。孤儿节点与其共享子资源持续累积，最终让主菜单卡牌全部失灵。

### 6. Tests Required

- `game_eval` 走完整场景循环后断言 `Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)` 不增长。**断言点必须选在「缓存实例正挂在树上」的时刻**：缓存池里的场景整体不在树上时，它的整棵子树本来就会计入该计数器，直接对比绝对零值会误判。

### 7. Wrong vs Correct

#### Wrong

```gdscript
current.get_parent().remove_child(current)   # 临时场景从此无人引用，成为孤儿
```

#### Correct

```gdscript
current.get_parent().remove_child(current)
if not _cache.values().has(current):
	current.queue_free()
```
