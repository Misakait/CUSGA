# State Management

## Model、View、Controller 分工

- **Model**：保存资源配置、玩家和地图状态，执行合法性校验与状态变更，并通过信号广播事实。
- **View**：根据 Model 当前状态实例化场景、刷新 UI 和表现，不决定业务规则。
- **Controller**：解释键盘、鼠标和按钮输入，调用 Model 的方法，协调 View 的刷新时机。

单向数据流为：输入 → Controller → Model → 信号 → View。View 不绕过 Controller 修改 Model，Model 不访问 View 节点。

## 节点状态

- 只在单个场景有效的临时状态放在拥有它的节点上。
- 跨场景仍需保留的玩家进度、钱包、时间和设置放在已有 autoload 或专用 Model 资源中。
- **常驻 autoload 的状态不会随场景切换自动复位**：只要该状态属于「一局」，新一局开始时就必须由开局入口显式把它拨回初始值。`TimeSystem` 正是这种情况——它跨场景保留累计时间与昼夜状态，若新局不重置，玩家在黑夜退回主菜单再开一局会直接以黑夜开场，天数也沿用上一局。重置点放在开局初始化节点的「非接续存档」分支，并且必须早于依赖该状态的组件完成 `_ready()` 吸附（`Main.tscn` 中初始化节点排在 `DayNightFilterLayer` 之前，这条顺序依赖由 `test_run_start_loadout_contract` 锁定，不要靠「碰巧排在前面」）。
- 重置常驻状态时优先复用已有的「把状态放到指定值」入口，不要在 autoload 上新增语义重叠的方法：`TimeSystem.RestoreSnapshot` 只广播 `TimeChanged`、不广播 `DayNightToggled`，因此用它重置不会误触发跨阶段副作用。
- 新增全局状态前先检查 `project.godot` 的 `[autoload]`，不要把同一状态复制到多个节点。
- 导出 `NodePath` 必须有可工作的默认值；`_ready` 中检查路径解析结果，并在错误消息中包含实际路径。

## 信号与生命周期

- 生产者只发出事实信号，不直接调用具体 View 的刷新方法。
- 连接前检查 `is_connected`，退出树时使用同一个 `Callable` 断开。
- 可能同步发射结果的调用，必须先连接信号再请求操作。
- 连接方进入场景树后应能从 Model 主动查询一次当前状态，避免错过已经发出的初始信号。
- 节点可能被 `queue_free` 时，缓存清理应先用 `is_instance_valid` 或 `is_queued_for_deletion` 判断，再按下标移除。

## 持久化与资源

- 可保存的数据使用 `Resource` 或现有 autoload 的持久化接口；View 不负责序列化。
- `.tres` 字段名、数组顺序和资源身份属于兼容协议，改名或复制资源前先检查所有引用。
- 缓存运行时实例时，同时保存其坐标或资源键；释放实例后必须移除缓存登记。

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

当某个系统的状态需要**跨游戏重启保留**，或需要**为新一局重置**时，接入 `SaveManager` 参与者协议。存档层位于 `core/save/`（`save_manager.gd` + `save_slot_codec.gd`），处理文件生命周期、作用域与分发；另持有唯一纯数据 PlayerProfile，并以自身作为 `player_profile` 参与者编解码新增档案字段。旧库存、带入、钱包和容量等级仍由旧参与者负责，避免重复编码。

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
- `clear_run_scope()` 显式清空局内数据；轮回结束后持续跳过仍在树里的旧局参与者采集，不能重新写回已结束世界。`begin_run_write_hold()` 在新局消费带入前打开写入门禁并清理旧快照/冻结标志，当前生产 Main 不恢复旧局。旧 `SESSION_ONLY` / `DISK` 协议不能绕过轮回门禁。
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
- Base：首次运行无存档，旧四个参与者保持金币 1200、仓容 27、空仓库与带入栏；新增 Profile 保持代币 0、收获容量 5 和空的已结算/待领取集合。默认测试策略只改内存。
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

## 轮回账本、持久化门禁与结算显示

适用于 `RunSessionData`、`PlayerProfile`、`SettlementManager`、SaveManager 写入入口及 Settlement 场景。当前模块说明为 [轮回结算系统](../../../docs/轮回结算系统.md)，规则与数值唯一汇总为 [游戏机制与玩法内容](../../../docs/游戏机制与玩法内容.md)。

- `RunSessionData` 是纯内存账本，只由 SettlementManager 持有；它不访问节点或文件。RunSnapshot 是世界采集/恢复协议，不能作为轮回资格或第二份收益账本。
- Profile 是局外数据的唯一生产对象，由 SaveManager 最先创建/加载。钱包与升级适配绑定同一对象，沿用 `player_wallet` / `player_progression` 旧键；新增字段只用 `player_profile` 编码。单独未入树夹具可使用本地 Profile，不能在生产创建第二份可写余额或等级。
- 持久化策略来自共享 `settlement_config.tres.persistence_enabled`，默认关闭，启动时锁定；不能运行中打开把测试收益带进真实存档。门禁必须覆盖 `request_save`、防抖、`save_now`、退出兜底、删除、损坏文件复制与最终原子写入；只在经理跳过一次保存不足以保证零写入。
- 正式局内先调用 `begin_run_write_hold()` 再消费带入；战斗、拾取和退出不能写盘。结束后仓库、Profile 和入账编号一起提交，`data.run` 清空。保存失败只重试保存，不能再次注入测试奖励或重复入账。
- 测试模式可读取旧档而不修改主档、备份、临时档或损坏现场。玩家偏好仍走 SettingsManager，不承载玩法收益；偏好文件不受玩法门禁控制。独立文件测试必须先使用 `configure_test_persistence("user://test_...", enabled)`，不得覆盖真实存档。
- 普通战斗获胜不等于整局通关。死亡与战斗失败共用结束去重；结束后异步过场不能恢复输入或普通回世界。暂停菜单退出只请求主动结束，结算导航才解除暂停。
- 立即死亡测试操作仅在暂停菜单实例的局内参数设置页显示。共享的 `option_panel.tscn` 默认关闭 `show_death_button`，登录菜单不覆盖此值；点击只发 `death_requested`，由 PauseMenu 调用玩家 `HealthComponent.TakeDamage(CurrentValue, 0)`。处理前收起暂停浮层但不恢复 `SceneTree.paused`，确保正常 `Depleted`/`player_died` 顺序进入唯一死亡结算。
- 收获和死亡赠品都使用统一账本添加和 `GlobalWarehouse.AddItemStack`。仓库入口只读来源，返回余量，保留槽对象/资源身份和独立洗炼字典；满仓余量进入 Profile 待领取，不能静默截断。
- 固定结果里的 ItemStack 必须逐项复制，`Dictionary.duplicate(true)` 不会自动复制 RefCounted 对象。显示不能绑定死亡玩家的可写背包，也不能通过结果格子再发一次物品。
- 收获容量默认 5，空格照样生成；永久容量更新只影响下局，本局结果持有开局容量。面板容量刷新只负责显示。正式名单默认空，拾取统计和测试赠品不授予正式资格。
- 建筑本期只保留资格/选择/取消/读取接口。选择与取消验证基础参数后明确返回未接入错误，无资产副作用；实际移转、容量、来源数量和重复请求规则由建筑任务确定，不能在本期预留接口里提前扣除或归还。
- 面板根只协调区域与导航；Harvest、Data、Description、ButtonSection 各管理自身直接区域。`set_description` 替换，`add_description` 按顺序换行追加，空追加不生空行。两个导航按钮有独立脚本，保存失败禁用导航并显示重试入口。

验证要求：数据用 `run_settlement_flow`、文件/兼容用 `settlement_persistence_contract` 与 `save_system_contract`、真实堆叠用 `settlement_warehouse_contract`。生产生命周期用 Godot MCP 运行 Main 与 Settlement，核验死亡去重、5 格空态、关闭/开启赠品、追加描述、暂停计时、满仓余量、保存失败重试、菜单和全新下一把；建筑占位调用前后源库存与账本必须相等。

