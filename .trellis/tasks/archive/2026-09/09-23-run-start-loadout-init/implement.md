# 开局角色与背包初始化 —— 执行计划

> 开工前必须先执行 `trellis-before-dev`（本项目已确认 DSH 为 inline 工作流），并加载匹配的规范：
> `.trellis/spec/frontend/state-management.md`（autoload / init() 时机 / 信号契约）、
> `.trellis/spec/backend/directory-structure.md`（脚本归属）、
> `.trellis/spec/guides/code-reuse-thinking-guide.md`（常量与状态不要双份）。
> 本项目已无 C# 文件，禁用 `godot-mono` CLI；验证一律走编辑器 MCP。

## 步骤清单

### S1. `ItemsControl` 建立带入栏权威（纯新增）

- [x] 在 `core/autoloads/ItemsControl.gd` 新增 `CARRY_SLOT_CAPACITY := 10`、`carry_items: Array`，以及 `GetCarryEntry` / `SetCarryEntry` / `ClearCarryEntry` / `HasCarryItems` / `TakeCarryItems` 五个方法。
- [x] 在 `_ready()` 里按 `CARRY_SLOT_CAPACITY` 铺满空条目（`{"item": null, "count": 0}`），保证长度稳定。
- [x] 删除 `warehouse_to_player` / `warehouse_to_player_cnt`（design.md §3.1 已论证唯一读写方都在本次改动范围内）。
- [x] `player_to_warehouse` / `player_to_warehouse_cnt` **保持原样**，并新增注释说明它们是未实现的回写链路，本次不动。
- [x] 全部新增成员按项目规范逐行中文注释（作用、数据含义、取值范围、默认值原因）。

**验证**：`script_patch` 保存后读诊断无 Parse Error。

### S2. 仓库界面改为权威视图

- [x] `scripts/warehouse/warehouse_control.gd`：新增 `_carry_authority` 解析（`/root/ItemsControl`，解析失败时 `push_error` 并降级为「不带入」，不得让场景崩溃）。
- [x] `_carry_items` 保留变量名与既有注释，改为在 `_apply_init()` 中**从权威重建**。
- [x] 逐点改写全部写入位置（`_build_slot_views` 的铺空位、`_on_put_in_pressed`、`_on_take_out_pressed`、以及任何直接写 `_carry_items[...]` 的位置）为「写权威 → 刷新视图」，保持「先移出再写入、失败即回滚」的既有原子语义。
- [x] `exit()` 移除导出逻辑（`ItemsControl.warehouse_to_player` 已删除），保留 `_selected = {}` 复位与注释更新。
- [x] `CARRY_MAX_POSITIONS` 保留不改名不改值，新增一行注释说明它与 `ItemsControl.CARRY_SLOT_CAPACITY` 同值镜像。

**风险**：这是本次最易漏改的文件（628 行、5 处读写点）。改完必须全文复读一遍 `_carry_items` 的所有出现位置。

### S3. 新增开局初始化节点

- [x] 新建 `core/gameflow/run_start_initializer.gd`，按 design.md §2.3 的契约实现（`@export` 参数置顶、逐行中文注释、`signal RunStartInitialized`、`Initialize()` 幂等）。
- [x] 解析玩家与其 `Components/InventoryComponent`；一律 `get_node_or_null` + 方法协议（`Capacity` / `TryClearStackAt` / `AddItem` / `TakeCarryItems`），不直接写 `ItemsControl.` 标识符，也不访问玩家私有字段。
- [x] 溢出（`AddItem` 返回值 > 0）时 `push_warning`，不退回带入栏（消耗语义）。

### S4. 接线 `Main.tscn` 并让调试配置让位

- [x] 用编辑器 MCP（`node_create` + `script_attach` + `node_set_property`）在 `scenes/Main.tscn` 的 `Player` **之后**插入 `RunStartInitializer` 节点，确认 `PlayerPath` 指向同级 `Player`。
- [x] 把 `DebugLoadoutSeeder` 的 `Enabled` 显式设为 `false`（保留节点、脚本与 `default_inventory_loadout.tres`）。
- [x] `scene_save` 保存，并复核节点顺序（初始化必须在 `Player` 之后、`MapSystem` 之前或之后均可，但必须在 `Player` 之后）。

### S5. 移除地图控制器里的带入实现

- [x] `scripts/map_scripts/map_control.gd` 删除 `_ready()` 中的带入循环，新增注释说明职责已迁移到 `RunStartInitializer`，并保留其余既有逻辑与注释不动。

### S6. 新增契约测试套件

- [x] 新建 `tests/godot/test_run_start_loadout_contract.gd`（套件名 `run_start_loadout_contract`），覆盖：
  - 带入栏为空 → 背包为空、`RunStartInitialized` 仍广播一次；
  - 带入栏有 3 条 → 背包逐条一致（物品身份 + 堆叠数量）；
  - 重复调用 `Initialize()` → 不重复装入（幂等）；
  - `TakeCarryItems()` 取出后权威为空、再次调用返回空数组；
  - `CARRY_MAX_POSITIONS == CARRY_SLOT_CAPACITY` 常量镜像；
  - 溢出路径：容量不足时 `Initialize()` **仍返回 true**（容量不足不属于装配失败），背包只装入容量允许的部分，放不下的部分不退回带入栏并产生 warning；
  - 生产接线形状：Main 场景节点顺序、`DebugLoadoutSeeder.Enabled = false`、地图控制器与仓库界面已完成职责迁移。
- [x] 套件内**不得直接引用 `ItemsControl` 标识符**（`test_run` 无 autoload），一律用桩节点经 `CarrySourcePath` 注入。
- [x] **必须同时**新建顶层转发壳 `tests/test_run_start_loadout_contract.gd`（`@tool extends "res://tests/godot/test_run_start_loadout_contract.gd"`）。

> 【执行期修正】原计划只写了 `tests/godot/` 下的套件。但 `test_run` 按项目既有约定走「顶层 4 行转发壳 + `tests/godot/` 实体」的两文件结构（见 `tests/test_player_level_contract.gd`）；缺了转发壳，套件不会被发现。

**验证**：`test_run(suite="run_start_loadout_contract")` 全绿。

### S7. 文档与开发者反馈规范

- [x] 更新 `docs/游戏机制与玩法内容.md`：新增「开局流程」一节，写清带入栏权威、带入即消耗、开局初始化时机、带入栏上限（10）、调试开局配置默认关闭，以及数值来源。
- [x] 按 `agent.local.md` 规范三产出「学习反馈摘要」，规范四产出「Git 提交描述」，并按规范五把两者追加到根目录 `临时反馈文档.md`（带 `YYYY-MM-DD HH:MM` 时间戳）。

## 验证命令（编辑器 MCP）

| 步骤 | 调用 |
| --- | --- |
| 脚本诊断 | `script_patch` / `script_create` 的返回诊断 |
| 契约套件 | `test_run(suite="run_start_loadout_contract")` |
| Main 场景冒烟 | `project_run(mode="custom", scene="res://scenes/Main.tscn")` → `logs_read(source="game")` → `project_manage(op="stop")` |
| 主场景冒烟 | `project_run(mode="main")` → `logs_read(source="game")` → `project_manage(op="stop")` |
| 运行时行为断言 | 游戏运行中 `game_eval`：断言带入栏已清空、背包与带入内容一致 |
| 编辑器改动复核 | `git status`（编辑器会重写场景文件格式） |

**阻塞判定**：出现 `SCRIPT ERROR` / `Parse Error` / `Failed to load script` 一律先修再继续；只涉及本次未改动文件的资源 UID 警告视为既有问题。

## 回滚点

见 `design.md` §5.2。任一回滚点出问题时，先恢复到该点并记录现象，不得在未知状态下叠加新改动。

## 开工前检查（`task.py start` 之前）

- [x] `prd.md` 无遗留阻塞项，`Open Questions` 已折叠进正文。
- [x] `design.md` / `implement.md` 均已存在并与 `prd.md` 一致。
- [x] 开发者已看过最终规划摘要并**明确批准**。
- [x] `git status` 在工作开始前是干净的（当前已确认干净）。
