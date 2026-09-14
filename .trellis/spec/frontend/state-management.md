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
```

### 3. Contracts

- `DeckManager.play_card` 必须先以 `remove_card_from_hand(card, false)` 让节点退出手牌布局，再把同一节点存入 `Action.presentation_card` 后入队；不能立即写入弃牌堆或调用渐隐销毁。
- `BattleManager._execute_single_action` 是玩家卡牌展示的唯一编排者：显式目标仍是场上怪物时，顺序固定为“飞向目标 → 原有效果结算 → 目标抖动和闪白 → 最终弃牌”。
- `Action.presentation_card` 对怪物技能和普通攻击始终可选，调用方不得假设它非空；旧的五参数 `Action.new(...)` 构造方式必须继续可用。
- `DeckManager.complete_played_card` 是唯一允许写入主动出牌弃牌数据并启动渐隐销毁的出口，必须用节点元数据防止重复调用。
- 没有单一显式怪物目标（自身、全体、随机、扩散或目标失效）的玩家卡牌跳过飞行与单体受击反馈，但仍从同一个完成出口仅一次弃牌。
- 动画原子操作复用 `CardAnimations.play_card`、`CardAnimations.hit` 和 `PlayerHand.play_discard_animation`；不要在 `BattleManager` 写入新的时长或缓动常量。

### 4. Validation & Error Matrix

| 条件 | 行为 | 结果 |
| --- | --- | --- |
| `presentation_card` 为空或节点已失效 | 跳过节点表现 | 既有行动结算不受影响 |
| 显式目标不是仍在场的怪物 | 跳过飞行与受击反馈 | 卡牌照常结算并最终弃置 |
| 目标缺少 `Sprite2D` | 仅执行目标节点抖动 | 不因特殊怪物场景中断行动队列 |
| 已完成卡牌再次调用 `complete_played_card` | 检查完成元数据并直接返回 | 不重复写入弃牌堆、不重复 `queue_free` |
| 玩家取消、改选、切换模式或失去回合 | `CardManager.clear_click_selection(true)` 交回 `PlayerHand` | 卡牌返回标准手牌布局，不产生行动或弃牌 |
| 点击模式确认施放 | `clear_click_selection(false)` 保留节点 | 不触发归位 Tween，从选中状态连续进入飞行 |

### 5. Good / Base / Bad Cases

- Good：点击模式选择一张卡和一个在场怪物，确认后卡牌飞至该怪物、结算、怪物抖动闪白，再一次性进入弃牌堆并渐隐。
- Base：未选敌人确认施放，卡牌保留原有自身目标结算；跳过敌人飞行与命中反馈，仍只在动作完成后弃置。
- Bad：`DeckManager.play_card` 入队后立刻调用 `into_discard_pile(card)`。这会在动画开始前让节点渐隐销毁，使队列持有无效展示节点。

### 6. Tests Required

- 点击模式选中、取消、改选、模式切换和玩家失去回合：断言选中卡牌上移，并在每个非确认出口恢复 `hand_position` 且保留在 `player_hand_card`。
- 显式敌人目标：断言 `Action.presentation_card` 与原手牌节点一致；断言节点先到目标位置、目标反馈完成后才从场景树释放，`discard_pile_data` 只新增一次。
- 自身、随机、全体、扩散和失效目标：断言不调用敌人飞行/受击方法，仍完成既有 `SkillTargetingType` 结算和一次弃置。
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
