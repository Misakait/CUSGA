# 跨运行存档系统：局外仓库与玩家进度持久化

## Goal

为 CUSGA 建立**一套**跨运行存档层，让「关闭游戏再打开，局外进度还在」成为系统能力，而不是散落在各模块里的特例：

1. 本次落地**局外（跨局）存档**：仓库物品、带入栏、金币、仓库/带入栏容量升级等级。
   （等级与经验**不在**其中：它是局内概念，见 Out of Scope。）
2. 架构上预留**局内（单局）存档**扩展点：后续「存档每局游戏的进度」只需新增参与者，不改动存档层本身。

用户价值：玩家的局外经营成果不再随进程退出清零；后续局内进度存档有唯一、可被测试锁定的落点。

## Background（已核实事实，带证据锚点）

### 存档现状

- 已有**偏好设置**层 `SettingsManager`（`core/autoloads/SettingsManager.gd:8`）以 `ConfigFile` 持久化到 `user://settings.cfg`，契约见 `.trellis/spec/frontend/state-management.md`「本地持久化玩家偏好」。它当前服务的真实偏好是 `battle/operation_mode`（`scripts/card_scripts/card_manager.gd:194`）与 `battle/feedback_intensity`（`scripts/battle_scripts/combat_feedback_director.gd:642`）。
- 它同时被三个**玩法进度**拥有者当作存档层使用，但每个都被开关短路为「不持久化」，且在 `_ready()` 里主动删除旧键：
  - `PlayerWallet`（`core/autoloads/player_wallet.gd:19`）`PersistAcrossRuns = false`，键 `player/gold`。
  - `PlayerProgression`（`core/progression/player_progression.gd:17`）`PersistAcrossRuns = false`，键 `player/warehouse_level`、`player/carry_level`。
  - `PlayerLevel`（`core/progression/player_level.gd:26`）`PersistAcrossRuns = false`，键 `player/level`、`player/experience`。
  - 后果：现存的 `user://settings.cfg` 里**不存在**可迁移的玩法进度数据。
- `docs/游戏机制与玩法内容.md:217` 记录「等级与经验当前不跨运行保存……改为跨运行保存时无需改动读写逻辑」。
- **仓库内容从来没有被持久化过**：`GlobalWarehouse` 是 autoload（`project.godot` `GlobalWarehouse="*res://core/autoloads/global_warehouse.tscn"`），内容只在本次运行的进程内跨场景保留。

### 仓库与物品数据形状

- `GlobalWarehouse` 的脚本是 `entities/components/warehouse_inventory_component.gd`，它 `extends entities/components/inventory_component.gd`（仅覆盖拖拽来源标识 `SystemWarehouse`）。
- `InventoryComponent`（`entities/components/inventory_component.gd`）用**固定槽位数组** `_slots: Array` 持有 `ItemStack`，槽位里存的是**原始 `Resource` 引用**（`:5-6`、`:78`），不是可序列化值。
- `ItemStack`（`resources/item/item_stack.gd`）持有 `Item: Resource`、`Amount: int`、`RolledAttributes: Dictionary`。后者的键来自装备 `AttributeBonuses` 的 `AttributeType` **整型**枚举（实测形如 `{0: Vector2i(10,20), 4: Vector2i(-2,-1)}`，`tests/godot/test_reusable_gathering_interaction.gd:1428`）。
- 物品有稳定身份 `CardId`：`ItemsControl`（`core/autoloads/ItemsControl.gd:46-73`）在 `_ready()` 递归扫描 `res://items` 建立 `card_id → Resource` 索引，并提供 `get_item(card_id)`（`:81`）。**这是物品反序列化的唯一水合入口。**
- 容量由 `PlayerProgression._apply_warehouse_capacity()`（`player_progression.gd:151-156`）下发到 `GlobalWarehouse.SetCapacity(...)`；`InventoryComponent.SetCapacity` → `EnsureCapacityAtLeast` **只增不减**（`inventory_component.gd:140-152`）。仓容 0 级 27 格、每级 +9、上限 3 级（54 格）；带入栏 0 级 5 格、每级 +1、上限 5 级（10 格）。

### 带入栏数据形状

- 权威是 `ItemsControl.carry_items`（`core/autoloads/ItemsControl.gd:29`）：固定 `CARRY_SLOT_CAPACITY = 10` 的位置化数组，元素形如 `{"item": Resource, "count": int}`。
- `ItemsControl._ready()` 调 `_reset_carry_items()` 把它复位为全空（`:39-42`），即**每次启动都清空**。
- 访问协议固定为 `GetCarryEntry` / `SetCarryEntry` / `ClearCarryEntry` / `HasCarryItems` / `TakeCarryItems`（`:85-183`）；`TakeCarryItems()` 是「带入即消耗」的唯一消费出口，取出后立即清空。
- 仓库界面 `scripts/warehouse/warehouse_control.gd` 只把带入栏当**视图**（`:8-14`），权威在 autoload。

### 等级与经验系统的实际状态（2026-09-24 复核 + 用户定调）

本 PRD 初稿把「等级与经验」当作与金币并列的局外进度。复核先发现两件事：**它没有任何经验来源**，且**单独持久化会永久销毁玩家已投入的属性点**；用户随后给出产品定调：**等级与经验是局内（一局之内）的概念，局外（主菜单、仓库）没有等级和经验，因此本任务不制作它。**

下面第一组证据说明「现有代码布局看起来像局外」——这是历史实现方式，**不构成产品定性**，用户已明确局内定性优先：

- `PlayerLevel` 是 Autoload（`project.godot:43`），不挂在任何场景上，天然跨场景存活；架构位置看起来就是全局状态。
- `core/progression/player_level.gd:6-13` 的设计注释明确：属性点走「挂起 + 领取」协议，理由是「等级规则层不应该知道玩家在哪里」。只有把等级当**跨场景/跨局**状态，才需要这套机制。
- `entities/player.gd:98-116` 的补领逻辑注释写的是「玩家可能在升级发生之后才进入场景（场景切换、重载、死亡后重建）」——即等级先于玩家存在。
- `docs/游戏机制与玩法内容.md:171-217` 有完整的「等级与经验系统」一节，第 217 行把它与金币、仓库容量升级**并列**为「当前不跨运行保存……改为跨运行保存时无需改动读写逻辑」。

推翻「可顺手一起持久化」的证据（关键，也是「局内定性」在代码侧的印证）：

- **经验目前没有任何来源。** `docs/游戏机制与玩法内容.md:200` 原文：「当前不接入任何玩法发放经验：击败怪物、采集、垂钓等行为都不会提供经验值。本系统只提供数值骨架与接口，由后续玩法逐个调用。」生产代码里 `AddExperience` 的**唯一调用者是契约测试** `tests/godot/test_player_level_contract.gd`；`TryLevelUp` 没有生产调用者；`AddLevels` 只被开发者面板的「增加一级」按钮调用（`core/ui/dev/dev_settings_ui.gd:189-193`）。
- **等级发的不是等级收益，是属性点**（每级 3 点，`player_level.gd:41`），而属性点被消费到**每局新建的玩家实体**上：
  - `entities/player.gd:134-146`：领到点数后调 `AttributeComponent.EarnPoints`。
  - `entities/components/attribute_component.gd:460-466`：`EarnPoints` 只加到实例字段 `AvailablePoints`（`:120`）。
  - `entities/components/attribute_component.gd:474-501`：`TryAllocatePoint` 把点数经 `_attributes[type].AddPoint(amount)` 投入属性——全部是实例状态。
  - `entities/components/attribute_component.gd:249-253`：`_ready()` 里 `InitializeWithData(InitialData)` 会 `_attributes.clear()` 后按基础值重建。
  - `scenes/player_scenes/player.tscn:46-48`：`AttributeComponent` 的 `InitialData` 是内联 `StartingStats` 子资源（基础值）。
  - 而 `player.tscn` 是 `scenes/Main.tscn` 的实例，**每局新建**。
- 因此「只持久化 `level` / `experience`」的后果是：玩家上一局升到 50 级、拿到 147 点并全部投进物攻；下次启动等级仍是 50，但玩家实体是全新的、`AvailablePoints = 0`、属性回到基础值；**因为等级已经是 50，再也不会发放任何属性点，147 点永久消失**。这不是"少存了一点"，而是存档系统主动毁掉玩家的成长成果。
- 注意 `PendingAttributePoints`（未领取的挂起点数）也不在初稿的存档字段里，它同样需要被一并考虑，否则「升级了但还没进过场景就退出」也会丢点。

结论（2026-09-24 用户定调）：**等级与经验是局内（一局之内）的概念，局外（主菜单、仓库）没有等级与经验，因此本任务不制作。** 它将来应作为「每局游戏的进度」的一部分进入 `data.run` 作用域，而不是进入本次的局外存档。

由此暴露一条**既有的、本任务不修**的缺口（留给后续「局内进度存档」任务作为锚点）：

- 按「等级是局内概念」的定性，每局开局应当把等级/经验归零。但 `core/progression/player_level.gd` 的公开面（`:69-282`）**没有任何重置入口**，且它是 Autoload、`_ready()` 只执行一次。因此今天的实际行为是：**进程内跨局继承**（第二局接着第一局的等级继续升），既不随局重置，也不跨进程保存——既不属于局内也不属于局外。这是"等级系统只交付了数值骨架"阶段的遗留状态，需在实现局内进度存档时一并收口。
- 同一批遗留：玩家 `AttributeComponent` 的属性分配与 `AvailablePoints` 每局由 `player.tscn` 的 `InitialData` 重建（`:249-253`），同样属于局内状态，将来应与等级/经验同批处理。

### Autoload 装配顺序

`project.godot` `[autoload]` 顺序：`GlobalEventBus` → `ItemsControl` → `GlobalWarehouse` → `SceneManager` → `ScreenTransitions` → `SettingsManager` → `WeatherManager` → `PlayerProgression` → `PlayerWallet` → `TimeSystem` → `PlayerLevel` → `_mcp_game_helper`。

关键后果：`GlobalWarehouse`（第 3）在 `PlayerProgression`（第 8）下发容量**之前**就进入场景树。若仓库在自己的 `_ready()` 里读档，此刻容量仍是默认 27，存档里第 27 格之后的物品会落进「存在但 UI 看不见」的槽位。

### 局的边界与局内状态

- 主菜单 `StartCard` 直接 `get_tree().change_scene_to_file("res://scenes/Main.tscn")`（`.trellis/tasks/09-23-game-start-flow/prd.md:14`），每局新建一份 `Main` 与 `Player`。
- 局内状态目前**没有**跨场景的权威容器：地图/房间地形在 `Main/RuntimeState/RoomTerrainStore`（节点内）、时间在 `TimeSystem`（autoload）、战斗在 `battle.tscn`（作为 `Main` 子节点挂载，见 `.trellis/spec/frontend/state-management.md`「局内战斗的 UI 宿主」）。
- `core/ui/hud/pause_menu.gd:11-13` 明确记录：退出游戏只是切回主菜单，**不结算、不保存任何东西**。
- `RunStartInitializer._ready()` 在 `scenes/Main.tscn:97` 上同步执行，并通过 `ItemsControl.TakeCarryItems()` 消费带入栏。**「存档何时生效」必须早于这一刻。**

### 验证工具链

- 项目**已无任何 `.cs` / `.csproj` / `.sln`**（C# 迁移已完成），因此 `AGENTS.md` 与部分 spec 里的 `dotnet build` 门禁在本仓库已无对象；可用门禁只有 Godot 编辑器 MCP（`test_run` / `project_run` + `logs_read` / `game_eval`）。
- `test_run` **只扫描 `res://tests` 顶层**且只认 `test_*.gd`，因此新套件需要「实现放 `tests/godot/test_*.gd` + 顶层 4 行转发壳」（`.trellis/spec/frontend/quality-guidelines.md`「MCP test_run 的套件发现路径与转发壳」）。
- 本项目把 `inference_on_variant` 提升为**错误**：不得用 `:=` 从 `Variant` 表达式推断类型；无 `class_name` 的脚本一律用 `call` / `set` / `connect` 字符串协议访问（同上「Variant 推断告警在本项目是硬错误」）。
- 已有套件**逐字锁定**了本次要反转的开关：`tests/godot/test_logic_family_contract.gd:304-330`（钱包 + 升级）断言 `PersistAcrossRuns = false`。本次必须同步更新该套件，否则门禁必然失败。`tests/godot/test_player_level_contract.gd:29`（等级）的同类断言**保持不变**——等级属局内概念，本任务不动它。
- 编辑器错误日志基线（2026-09-24 采集）中，`core/map/room_terrain_store.gd` 的负路径 `push_error`、`run_start_initializer.gd` 的夹具警告、`GlobalEventBus.gd` 的未使用信号警告均为**既有**输出；`test_talent_selection_contract.gd` 曾在旧日志里出现的 `TALENT_SCREEN_SCENE_PATH not declared` 已被修复（该常量现位于 `tests/godot/test_talent_selection_contract.gd:20`）。以上都不得当成本次回归。
- 工作区在任务开始时**已有一处与本任务无关的改动**：`M scenes/Main.tscn`。

## Requirements

### R1 存档层（统一入口与文件契约）

- R1.1 新增 Autoload `SaveManager`（`core/save/save_manager.gd`），是玩法进度持久化的**唯一**读写出口；`SettingsManager` 回归为纯偏好层（`battle/operation_mode`、`battle/feedback_intensity` 继续留在 `user://settings.cfg`）。
- R1.2 存档文件为 `user://save/game_save.json`，顶层含 `format_version`（整型）、`saved_at_unix`、`data.global`、`data.run` 四个键；空槽位统一写 `null` 且不省略下标。
- R1.3 读取时 `format_version` 不等于 `SaveManager.FORMAT_VERSION`、JSON 不合法、或 `data` 不是字典：不崩溃、不静默丢档——保留损坏现场、以默认值启动、并 `push_error` 给出可诊断原因。
  - **2026-09-24 实现期修正**：本条原表述为「把原文件保留为 `.bak`」，实现改为**把损坏内容另存为 `.corrupt` → 尝试从 `.bak` 恢复 → 两者都不可用才回退默认值**。理由：`.bak` 的意义是「上一份**好**档」，是主档损坏时唯一的自动恢复来源；把损坏内容写进去正好毁掉这条恢复路径。`has_save()` 相应定义为「成功读出了一份可用存档（来自主档或 `.bak`）」。详见 `design.md` §2.1 / §2.3。
- R1.4 写入必须是**原子**的：先写 `.tmp` 再替换目标文件；替换前把上一版复制为 `.bak`。写入失败必须 `push_error` 并返回 `false`，不得假装成功。
- R1.5 `SaveManager` 提供 `has_save()` / `register_participant(node)` / `capture()` / `apply(data)` / `request_save()` / `save_now()` / `erase_save()` / `clear_run_scope()` / `get_loaded_data()`。
- R1.6 `request_save()` 必须是**合并延迟**的：0.5 秒去抖窗口内多次请求只落盘一次；去抖必须对 `get_tree().paused` **免疫**（`process_mode = PROCESS_MODE_ALWAYS` + 自己的 `_process`，不用受暂停影响的 `Timer`）。
- R1.7 `apply(data)` 期间到达的变更请求被**丢弃**而非延迟（它们是读档造成的回声，落盘只会重写相同内容并掩盖真实写入错误）。
- R1.8 存档路径必须是可被测试改指的（`@export var SaveFilePath`），使契约测试可以使用临时路径而不触碰真实存档。

### R2 参与者协议（扩展点）

- R2.1 玩法模块以「参与者」身份接入，实现 5 个方法：`save_key() -> String`、`save_scope() -> String`（`"global"` / `"run"`）、`save_change_signals() -> Array`、`capture_save_data() -> Dictionary`、`apply_save_data(data: Dictionary) -> bool`。
- R2.2 `register_participant()` 在注册时用 `has_method()` 校验协议齐全，缺失时 `push_error` 并**拒绝注册**（把协议错误暴露在启动期，而不是等到关窗存档时）。
- R2.3 读取时 `data.global.<save_key>` 缺失视为「该参与者没有存档」：参与者必须回退自身默认值，不得报错、不得清空无关数据。`data` 为空字典即表示「无存档」。
- R2.4 写入时只写参与者的 `capture_save_data()` 返回值；存档层不解释参与者的内部结构；未知的 `data.global` 键忽略并 `push_warning`（不视为损坏）。
- R2.5 参与者除注册那一行外**不得反向依赖** `SaveManager`：变更信号由 `save_change_signals()` 声明、由存档层订阅。这使参与者能在无 autoload 的 `test_run` 环境里被独立断言。
- R2.6 `save_scope() == "run"` 的参与者数据**不进入**跨运行文件（`data.run` 本次恒为空对象，但分流必须已生效并被测试锁定）。

### R3 仓库存档

- R3.1 `WarehouseInventoryComponent` 作为参与者 `warehouse` 实现 R2.1 协议；**不得改动共享基类** `inventory_component.gd`（玩家背包也用它）。
- R3.2 槽位序列化为**稀疏定长数组**（索引即槽位序号，空槽为 `null`），每项形如 `{"card_id": String, "amount": int, "rolled": {int: int}}`；`rolled` 只有带洗炼属性的装备才有内容。
- R3.3 读档经 `ItemsControl.get_item(card_id)` 水合；`card_id` 已不存在于 `res://items` 时**跳过该槽位并计数告警**，不得让整档读取失败。`rolled` 中不属于该物品 `AttributeBonuses` 键集合的项同样丢弃并计数。
- R3.4 读档顺序固定为**先清空全部槽位、再按存档写入**，保证「读档结果 == 存档内容」而不是与默认内容叠加。
- R3.5 读档前按存档槽位数 `EnsureCapacityAtLeast(...)` 防御性扩容，避免物品落进不可见槽位。
- R3.6 仓库存档**不含容量数值**：容量是由 `warehouse_level` 推导的规则值（`27 + 9×level`），存两份会产生两个真相源。

### R4 局外玩家进度存档

- R4.1 `PlayerWallet` 作为参与者 `player_wallet` 持久化 `gold`。
- R4.2 `PlayerProgression` 作为参与者 `player_progression` 持久化 `warehouse_level` 与 `carry_level`（容量本身由等级推导，见 R3.6）。
- R4.3 两者的 `PersistAcrossRuns` 常量与「主动删除旧键」逻辑一并移除：跨运行保存成为唯一行为，开关与其短路分支都不再有意义。**不新增**对 `user://settings.cfg` 里 `player/*` 残留键的清理代码（那批键从未被真正写入过，属惰性数据）。
- R4.4 数值校验规则保持不变（金币非负；升级等级收窄到各自上限），读档越界时告警并使用收窄值。
- R4.5 **读档时机采用「注册即应用 + 迟到补应用」**：`SaveManager` 在 `_ready()` 里只把文件读进内存，不在此处分发；`register_participant()` 在加载完成后**立刻同步**把该参与者的数据分发下去。因此每个参与者都在自己的 `_ready()` 里拿到存档，`ItemsControl` 的带入栏在 `Main.tscn` 的 `RunStartInitializer` 消费它之前就已是存档内容。
- R4.6 `SaveManager` 必须注册为 `[autoload]` 的**第一项**，使其在每个参与者注册之前就存在。`register_participant()` 对「尚未加载完成」也必须兜底（记为待分发，加载完成后补发），使顺序被误改时退化为「延迟分发」而不是静默丢档。
- R4.7 `core/progression/player_level.gd` **完全不动**（含 `PersistAcrossRuns = false`），`tests/godot/test_player_level_contract.gd` 也完全不动——其既有断言继续充当「等级系统不得私自持久化」的守卫。等级与经验属局内概念，见 Out of Scope；相关既有缺口的锚点见 Background「等级与经验系统的实际状态」。

### R5 带入栏存档

- R5.1 `ItemsControl` 作为参与者 `carry` 持久化 `carry_items`（固定 10 格，空槽为 `null`）。
- R5.2 `ItemsControl._ready()` 不再无条件复位带入栏：改为 `_ensure_carry_capacity()`（仅在长度不符时重建为空），有存档则随后由 R4.4 的同步分发覆盖。
- R5.3 读档沿用既有权威协议写入（`SetCarryEntry`），不新增第二份带入栏状态。
- R5.4 新增信号 `carry_items_changed`（纯追加，不改任何既有签名），在 `SetCarryEntry` / `ClearCarryEntry` / `TakeCarryItems` **实际改变了内容**时发出；它既是自动存档的触发面，也让「带入即消耗」的落盘成为必然。

### R6 自动存档

- R6.1 触发面：仓库内容变化（`GlobalWarehouse.InventoryChanged`）、带入栏变化（`carry_items_changed`）、金币变化（`GoldChanged`）、升级成功（`UpgradeChanged`）。（等级/经验不在其中，见 Out of Scope。）
- R6.2 进程退出兜底：`NOTIFICATION_WM_CLOSE_REQUEST` 与 `NOTIFICATION_EXIT_TREE` 各做一次同步 `save_now()`（幂等；后者覆盖编辑器「停止运行」这条不触发 WM_CLOSE 的路径）。
- R6.3 不提供玩家可见的存档 UI（用户选择「全自动，无 UI」）。

### R7 契约测试

- R7.1 新增 `tests/godot/test_save_system_contract.gd` + `tests/test_save_system_contract.gd` 转发壳，覆盖：脚本形状与注册、协议校验、槽位编解码往返、未知 `card_id` 跳过并计数、洗炼属性校验（声明了 `AttributeBonuses` 时求交集，未声明时只做类型校验）、版本不符 / 非法 JSON / `data` 非字典的回退与损坏现场 `.corrupt` / `.bak` 恢复、无存档默认值、原子写入（`.tmp` 不残留、`.bak` 等于上一次内容）、两个作用域互不污染、去抖只写一次、`apply` 幂等、4 个参与者的 `capture → apply` 往返与越界收窄。
- R7.2 更新 `tests/godot/test_logic_family_contract.gd` 中已被需求反转的 `PersistAcrossRuns = false` 断言（从「必须保留 false」改为「不再声明该常量且实现存档协议」），而不是删除该测试。`tests/godot/test_player_level_contract.gd` **不动**（R4.7）。
- R7.3 断言 `project.godot` 里 `SaveManager` 位于**所有参与者之前**，锁定 R4.5 的前提。

### R8 文档

- R8.1 `docs/游戏机制与玩法内容.md:217` 的结论「等级与经验不跨运行保存」**依然成立**，保留该句；但需补一句指向新增的「存档系统」一节，说明局外存档已建立、而等级/经验属局内（将来随局内进度存档处理），避免读者误以为"整个存档系统还没做"。
- R8.2 在 `docs/游戏机制与玩法内容.md` 新增「存档系统」一节：存档文件位置、存档范围、自动存档时机、手动清档方法（删除 `user://save/game_save.json`）、以及「局内进度存档尚未实现，`data.run` 为预留落点」。

## Acceptance Criteria

### 仓库物品跨运行

- [ ] 在仓库里放入若干不同物品（含一堆数量 > 1 的物品，以及一件带洗炼属性的装备），停止游戏进程再启动：仓库格子内容、物品身份、堆叠数量、洗炼属性与关闭前逐一相同。
- [ ] 仓库槽位顺序（第几格放什么）与关闭前一致。
- [ ] 存档中槽位数超过 27（仓库已升级）时，读档后所有物品仍然可见。

### 带入栏跨运行

- [ ] 在仓库界面选好带入栏内容，停止进程再启动：带入栏内容与关闭前一致。
- [ ] 带存档启动进入一局后：带入栏内容**已被开局带入消费**（带入栏为空），且玩家背包里确实出现了那批物品——证明读档发生在 `RunStartInitializer` 之前。
- [ ] 带入消费造成的清空本身也被持久化（再次重启不会让物品复原）。

### 局外玩家进度跨运行

- [ ] 金币在停止进程再启动后保持不变；存档里为负数时回退到默认值 1200 并告警。
- [ ] 仓库容量升级等级与带入栏升级等级在停止进程再启动后保持不变，且仓容实际生效（可见格子数等于该等级对应值）。
- [ ] 等级与经验**不受影响**：`player_level.gd` 未被改动，其既有契约套件（`test_player_level_contract`）继续通过。

### 存档层健壮性

- [ ] 删除 `user://save/game_save.json` 后启动：回退默认值（金币 1200、仓容 27、仓库与带入栏为空），无 `SCRIPT ERROR`。
- [ ] 把存档内容改成非法 JSON 后启动：正常启动、回退默认值、损坏内容保留为 `.corrupt`、日志有明确错误、无崩溃。
- [ ] 存档里引用一个已不存在的 `card_id`：其余物品正常读回，缺失项被跳过且日志有告警。
- [ ] 暂停状态下修改仓库内容并触发落盘：改动被成功写入文件。
- [ ] 连续多次 `request_save()` 在一次去抖窗口内只产生一次磁盘写入。

### 扩展点

- [ ] `save_scope() == "run"` 的参与者数据不进入跨运行文件（由契约测试用桩参与者锁定）。
- [ ] 新增一个参与者不需要修改 `SaveManager` 内部逻辑（由契约测试用桩参与者证明）。

### 门禁

- [ ] `test_run(suite="save_system_contract")` 通过且 `total > 0`（`total == 0` 表示套件**未被发现**，不算通过）。
- [ ] 全量 `test_run` 的 `failed == 0`，且 `save_system_contract` 出现在 `suites_run` 中。
- [ ] `test_run(suite="logic_family_contract")` 在断言反转后通过；`test_run(suite="player_level_contract")` **未经修改即通过**（等级系统未被本任务触碰）。
- [ ] `project_run(mode="custom", scene="res://scenes/main_menu_scenes/main_menu.tscn")` 与 `res://scenes/Main.tscn` 冒烟：`logs_read(source="game")` 无新增 `SCRIPT ERROR`。
- [ ] `game_eval` 在运行中的游戏里断言：`/root/SaveManager` 存在、4 个参与者已注册、读档后的金币/仓容与存档文件一致。
- [ ] `git status --porcelain` 复查：除本任务文件与任务开始前既有的 `M scenes/Main.tscn` 外，无非预期改动。

## Out of Scope

- **不实现局内（run）进度的具体字段**（地图位置、房间地形、天数、牌堆、战斗状态…）。本次只交付 `run` 作用域的分流与 `clear_run_scope()`，具体参与者留给后续任务。
- **不做玩家可见的存档 UI**（无「保存 / 读取 / 新游戏」菜单、无存档槽位选择、无读档确认弹窗、无开发者面板「删除存档」按钮）。清档本次只提供 `erase_save()` API 与手动删除文件两条路径。
- **不做自动迁移**：三个进度拥有者从未真正写入过 `player/*` 键，故不存在需要迁移的数据；也不新增残留键清理代码。
- **不做存档加密、防篡改或云同步**；不做多存档槽位。
- **不改仓库界面、商店界面的交互**（含不把界面刷新改为订阅 `carry_items_changed`）。
- **不改 `ItemsControl.player_to_warehouse` 那条「局内→局外回写」链路**（当前无生产者，属独立需求）。
- **不改共享基类 `entities/components/inventory_component.gd`**。
- **不在本任务里大改**仍在讲 `dotnet build` / `CUSGA.sln` 的 `AGENTS.md` 与 backend spec 段落（只在相关节内注明「本仓库已无 C#，该门禁无对象」）。

## Open Questions

- 无。全部用户决策已确认（见 Notes）。

## Notes

- 本任务由 2026-09-24 会话按 `trellis-start` 创建。用户确认的四项决策：
  1. 允许创建 Trellis 任务并进入规划阶段。
  2. 存档范围**包含金币**（让局外进度自洽）。**「等级与经验」在复核后被用户撤回**：用户定调它是局内（一局之内）的概念，局外（主菜单、仓库）没有等级和经验，因此本次不制作；它属于将来「每局游戏的进度」的 `data.run`。
  3. 存档**全自动、无 UI**。
  4. **带入栏一并跨运行存档**（它和仓库物品同属「在仓库里摆好的局外进度」）。
- 架构方案（`SaveManager` + 参与者协议 + 版本化 JSON + `global`/`run` 作用域分流 + 注册即应用的读档时机）的选择理由、被否决的备选方案与取舍见 `design.md`；执行顺序、验证命令与回滚点见 `implement.md`。
