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
