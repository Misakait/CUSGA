# 开局角色与背包初始化 —— 技术设计

## 1. 架构与边界

### 1.1 问题陈述

「带入栏 → 局内背包」这条链路目前由三处各管一段：仓库界面在 `exit()` 导出（`scripts/warehouse/warehouse_control.gd:111`）、`ItemsControl` 当临时信箱（`core/autoloads/ItemsControl.gd:12`）、地图控制器在 `_ready()` 消费（`scripts/map_scripts/map_control.gd:24`）。结果是：

- 带入栏的**权威状态**（`warehouse_control._carry_items`，`scripts/warehouse/warehouse_control.gd:61`）活在**被 SceneManager 缓存复用的场景实例**里，Main 侧无法可靠地清空它；
- 开局初始化被 `DebugLoadoutSeeder` 的 deferred 调用覆盖（`core/debug/debug_loadout_seeder.gd:44`）；
- 初始化职责落在地图控制器上。

### 1.2 边界划分（改动后）

| 角色 | 归属 | 职责 |
| --- | --- | --- |
| 带入栏**权威状态** | `ItemsControl`（既有 autoload） | 持有带入栏权威数组，提供读取 / 写入 / 取出并清空的 API |
| 带入栏**界面视图** | `scripts/warehouse/warehouse_control.gd` | 只渲染与改写权威；`init()` 时从权威重建，不再自己长期持有内容 |
| **开局初始化入口** | 新增 `core/gameflow/run_start_initializer.gd`，挂在 `scenes/Main.tscn` | 唯一的开局初始化执行者：取出带入栏 → 清空带入栏 → 装入玩家背包 → 广播完成信号 |
| 玩家背包 | `entities/components/inventory_component.gd` | 只通过 `AddItem` / `TryClearStackAt` 等稳定协议被调用 |
| 调试开局配置 | `core/debug/debug_loadout_seeder.gd` | 保留为**手动**调试工具，默认不再生效 |

**为什么把权威状态上移到 `ItemsControl`**：
`SceneManager` 把仓库场景实例**长期缓存**（`core/autoloads/SceneManager.gd:13`、`:70`），`_carry_items` 不会随场景卸载而消失；因此如果没有一个场景外的权威，「开局带入后清空带入栏」这件事根本无法从 Main 侧完成——玩家退回主菜单再进仓库时，缓存实例会把已带入的物品重新导出一次，形成**无限重复带入**。这与 `warehouse_control.gd:8-10` 自己记录的教训（「界面副本一旦某条路径忘了写回就会丢改动」）是同一类问题，因此沿用同一解法：**把权威放在 autoload，界面只做视图**。

**为什么不新增 autoload**：`.trellis/spec/frontend/state-management.md:37` 明确要求「先局部归属，只有多个互不相关的场景都需要时才升级到既有 autoload」。带入栏天然被「仓库场景」与「Main 开局」两个场景需要，且 `ItemsControl` 本来就是「局外仓库的东西带入游戏」这一概念的唯一持有者（`core/autoloads/ItemsControl.gd:11`），因此选择**扩展现有 autoload**，而不是新建单例。

## 2. 数据流与契约

### 2.1 `ItemsControl` 新增契约

```gdscript
## 权威带入栏固定长度；与带入栏升级上限一致（基础 5 + 5 级 × 1）。
const CARRY_SLOT_CAPACITY: int = 10

## 带入栏权威内容。索引即栏位序号，元素形如 {"item": Resource, "count": int}。
var carry_items: Array = []

func GetCarryEntry(index: int) -> Dictionary      # 越界返回空条目 {"item": null, "count": 0}
func SetCarryEntry(index: int, item: Resource, count: int) -> bool   # 写入并返回是否成功
func ClearCarryEntry(index: int) -> bool                              # 清空单个栏位
func HasCarryItems() -> bool                                          # 是否还有待带入物品
func TakeCarryItems() -> Array                                        # 取出全部占用条目并清空带入栏
```

- `TakeCarryItems()` 返回 `[{"item": Resource, "count": int}, ...]`，只含 `item != null and count > 0` 的条目；返回后权威数组全部复位为空条目。它是「带入即消耗」的**唯一**消费出口。
- `carry_items` 必须在 autoload `_ready()` 阶段按 `CARRY_SLOT_CAPACITY` 铺满空条目，保证任何调用方拿到的数组长度都稳定（避免 `warehouse_control` 现有的「首次构建才铺空位」时序问题）。

### 2.2 `warehouse_control.gd` 的改造契约

- `_carry_items` **保留变量名与既有注释**（遵守项目的「尊重原版」约定），但语义由「自身持有的内容」变为「权威的视图」：
  - `init()` / `_apply_init()` 阶段：从 `ItemsControl` 权威**重建** `_carry_items`（长度 = `CARRY_MAX_POSITIONS`，逐位拷贝），确保缓存实例不会复活已带入的物品。
  - `_on_put_in_pressed()` / `_on_take_out_pressed()`：先写权威，再刷新视图（写权威失败时不改视图，保持现有「先移出再写入、失败即回滚」的原子语义）。
  - `exit()`：**不再导出**；保留 `_selected = {}` 的复位。
- `CARRY_MAX_POSITIONS`（`scripts/warehouse/warehouse_control.gd:18`）**保留不改名不改值**，新增一行注释说明它与 `ItemsControl.CARRY_SLOT_CAPACITY` 是同值镜像；由测试断言两者相等，防止漂移。

### 2.3 `run_start_initializer.gd` 契约

```gdscript
## 开局初始化完成信号；抽卡环节应挂接此信号，而不是自己监听场景加载。
signal RunStartInitialized

## 玩家节点相对本节点的路径。
@export var PlayerPath: NodePath = NodePath("../Player")
## 带入栏权威来源；默认指向 ItemsControl autoload，测试可改指桩节点。
@export var CarrySourcePath: NodePath = NodePath("/root/ItemsControl")
## 玩家背包组件相对玩家节点的路径。
@export var InventoryComponentPath: NodePath = NodePath("Components/InventoryComponent")
## 是否输出初始化细节日志。
@export var VerboseLog: bool = false

func Initialize() -> bool      # 幂等；成功返回 true
```

- **执行时机**：在 `_ready()` 中**同步**执行 `Initialize()`。理由：`Main.tscn` 中 `Player`（`scenes/Main.tscn:92`）排在本节点之前，Godot 的同级 `_ready` 按树顺序触发，因此玩家的 `InventoryComponent._ready()`（建立空槽位）必然已完成；而 `DebugLoadoutSeeder` 走的是 `call_deferred`，同步执行天然排在它之前，顺序确定、不依赖帧时序。
- **幂等**：内部 `_has_initialized` 标志，重复调用直接返回 `true` 且不重复装入。
- **背包写入**：先按 `Capacity` 逐位 `TryClearStackAt` 清空，再对每个带入条目调用 `AddItem(item, count)`；返回值是**未放入的剩余数量**，`> 0` 时 `push_warning` 并计入失败（物品按「消耗」语义不退回带入栏，因此必须可诊断）。
- **访问方式**：一律 `get_node_or_null` + 方法协议调用（`AddItem` / `TryClearStackAt` / `Capacity`），不读写玩家的私有字段，因此同时兼容 C# 与 GDScript 组件。带入栏来源也走导出路径 + 方法协议，**不在脚本里直接写 `ItemsControl.` 标识符**——这样 `test_run`（无 autoload 环境）可以用桩节点覆盖。

### 2.4 开局序列（本任务负责第 0..1 步）

```
主菜单 Start → change_scene_to_file(Main.tscn)
  ├─ [0] DebugLoadoutSeeder 不再生效（Enabled=false）
  ├─ [1] RunStartInitializer._ready()  ← 本任务
  │        ItemsControl.TakeCarryItems() → 清空带入栏 → 清空背包 → AddItem 逐条装入
  │        → emit RunStartInitialized
  └─ [2] 抽卡环节挂接 RunStartInitialized   ← 由 09-23-run-start-skill-card-draft 实现
```

## 3. 兼容与迁移

### 3.1 `ItemsControl.warehouse_to_player` / `warehouse_to_player_cnt` 的处置

**决定：删除这两个字段**（`core/autoloads/ItemsControl.gd:12-13`），由位置化的 `carry_items` 权威取代。

依据（已核实无其它引用方）：

- 唯一写入方是 `warehouse_control.exit()`（`scripts/warehouse/warehouse_control.gd:112-122`），本任务会重写该出口；
- 唯一读取方是 `map_control._ready()`（`scripts/map_scripts/map_control.gd:24-30`），本任务会移除该实现；
- 全工程 `rg` 检索（含 `tests/`）没有第三处引用。

保留这两个「紧凑列表」还会引入**位置丢失**：它们只存占用条目，而带入栏是有序栏位（`取出` 按下标操作，`scripts/warehouse/warehouse_control.gd:437`），用它们做权威会让栏位在重新进入仓库时被重新压紧。`ItemsControl.player_to_warehouse` / `player_to_warehouse_cnt`（同文件 `:16-17`）**保持原样不动**：它们属于未实现的「局内 → 局外回写」链路，本次明确不在范围内。

### 3.2 `map_control.gd` 的处置

移除 `_ready()` 中的带入循环（`scripts/map_scripts/map_control.gd:23-30`），并新增注释说明带入职责已迁移到 `RunStartInitializer`。地图控制器不再触碰玩家背包。

### 3.3 `DebugLoadoutSeeder` 的处置

`scenes/Main.tscn:94-97` 的节点把 `Enabled` 显式写为 `false`（当前未写，取脚本默认 `true`）。脚本与 `resources/debug/default_inventory_loadout.tres` **原样保留**，作为手动调试工具——重新启用它即表示「有意用调试配置覆盖开局带入」，这是显式选择，不再默认发生。

### 3.4 与仓库容量 / 带入栏升级的关系

带入栏**可用**栏位数由 `PlayerProgression.GetCarrySlotCount()` 决定（`core/progression/player_progression.gd:101`，基础 5 + 每级 1、上限 5 级 = 10）；`CARRY_SLOT_CAPACITY = 10` 只是硬上限。开局初始化**不校验**可用栏位数——写入带入栏时已由仓库界面校验过，越权条目不应存在。

## 4. 权衡与备选方案

| 备选 | 为什么未采用 |
| --- | --- |
| 开局时通过 `SceneManager` 拿到缓存的仓库实例，直接清 `_carry_items` | 需要给 `SceneManager` 开一个「取缓存实例」的公开口子，把场景缓存细节泄漏给玩法层；且仓库从未被访问时无实例可清，逻辑出现两分支 |
| 保留紧凑数组当权威，界面重建时重新压紧栏位 | 改变了既有栏位保序行为（`取出` 按下标操作），是用户可感知的回归 |
| 新建 `CarryBar` autoload | 违反 `state-management.md:37`「不要为功能局部状态新增全局单例」；`ItemsControl` 已是该概念的所有者 |
| 用 `call_deferred` 执行初始化以「排到最后一个写者」 | 顺序仍然依赖帧内延迟链，且会让 `RunStartInitialized` 的时序不可预测，抽卡环节挂接时容易出现竞态 |
| 保留 `DebugLoadoutSeeder` 作为「带入栏为空时兜底」 | 已被开发者否决：会破坏「背包内容严格等于带入栏」这条验收 |

## 5. 风险、回滚与验证

### 5.1 风险点

- `scripts/warehouse/warehouse_control.gd` 是 628 行的既有文件，且 `_carry_items` 被 5 个内部函数读写。改造必须**逐个写入点**改为「写权威 + 刷新视图」，漏一处就会出现视图与权威分叉。
- `tests/godot/` 的运行环境**没有 autoload**（见 `state-management.md:543`）。任何 `test_run` 套件都不能依赖 `/root/ItemsControl` 真实存在，必须用桩节点 + 导出路径注入。
- `Main.tscn` 与 `player.tscn` 由编辑器 MCP 改动后会被编辑器重写格式化，需在提交前 `git status` 复核。

### 5.2 回滚点

1. `ItemsControl` 权威与 API 落地后（纯新增，可单独回滚）。
2. `warehouse_control` 改为视图后（此时新旧路径可并存：`exit()` 仍可临时恢复导出以对照验证）。
3. `RunStartInitializer` + `Main.tscn` 接线 + `map_control` 移除消费代码（一次性回滚单元）。
4. `DebugLoadoutSeeder` 关闭（单独一行改动，可单独回滚以便调试）。

### 5.3 验证方式（本项目禁用 `godot-mono` CLI，一律走编辑器 MCP）

| 目标 | 手段 |
| --- | --- |
| 脚本语法与解析 | `script_patch` / `script_create` 保存后读取返回诊断 |
| 契约单测（带入栏 API、初始化幂等、空带入栏、溢出告警） | 新增 `tests/godot/test_run_start_loadout_contract.gd`，`test_run(suite="run_start_loadout_contract")`，用桩节点注入 `CarrySourcePath` |
| 常量镜像（`CARRY_MAX_POSITIONS == CARRY_SLOT_CAPACITY`） | 同一套件内断言 |
| 场景装配合规 | `project_run(mode="custom", scene="res://scenes/Main.tscn")` + `logs_read(source="game")`，断言无 `SCRIPT ERROR` / `Nil` |
| 主场景冒烟 | `project_run(mode="main")` + `logs_read(source="game")`，随后 `project_manage(op="stop")` |
| 真实开局行为（autoload 参与） | 运行中游戏里用 `game_eval` 断言：带入栏清空、背包条目与带入内容一致 |
| 文档同步 | 更新 `docs/游戏机制与玩法内容.md` |

**已知既有缺陷，不作为本任务验收项**：把 `Warehouse.tscn` 当初始场景直接运行会因 `inventory_control.gd` 的 `@onready` 时机报错（`state-management.md:491` 已记录）。因此仓库侧验证走「主菜单 → 仓库」的正常路径。

## 6. 对后续子任务的接口承诺

- `RunStartInitialized` 信号是**唯一**的开局初始化完成时点；`09-23-run-start-skill-card-draft` 必须挂接它，不得自行监听场景加载或另起初始化入口。
- 抽卡产出（2 张技能卡）发生在初始化之后，因此不会被本任务的「清空背包」逻辑清掉。
