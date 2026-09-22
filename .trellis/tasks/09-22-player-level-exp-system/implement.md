# 执行计划：玩家等级与经验值系统

> 状态：**步骤 1–7 全部完成**，全量回归与运行时端到端验证均通过。任务保持 `in_progress`，等待开发者复核后提交与归档。

## 前置检查

- [x] 确认 Godot 编辑器已打开且载入 CUSGA 项目：会话 `cusga@a3eb2fa7ac967b58`（Godot 4.7.1-stable），插件重载后为 `cusga@ecc5f064f74d6ec4`。
- [x] 记录改动前工作区状态：12 个既有 `resources/combat_skills/*.tres` 改动（编辑器自动清理未使用的 `ext_resource` 行，与本次无关，未触碰）。

## 步骤 1：新增等级系统 Autoload —— 完成

- [x] 新建 `core/progression/player_level.gd`：常量区、三项状态、三个信号、九个公开接口、经验结算循环与持久化读写全部按设计实现。uid 旁车 `uid://bc6e14tb73lqw` 随扫描生成。
- [x] `autoload_manage(op="add")` 注册 `PlayerLevel`，落在 `SettingsManager` 之后（`project.godot` 第 44 行），依赖顺序正确。

**实际结果**：`editor` 日志无该脚本的 `Parse Error` / `Failed to load script`；缩进全 Tab（119 行），无 `.cs` 字面量、无 `TODO`。

## 步骤 2：玩家实体消费属性点 —— 完成

- [x] `entities/player.gd` 新增 `PLAYER_LEVEL_PATH`（`NodePath`）、`_player_level` 字段、`_bind_player_level()`、`_on_attribute_points_granted()`、`_grant_pending_attribute_points()`；`_ready()` 末尾绑定；`_exit_tree()` 精确断开。
- [x] 只新增、未改动既有成员：`test_player_contract` 全绿。

**实际结果**：`test_run(suite="player_contract")` 通过；全量回归中该套件无失败。

## 步骤 3：属性栏显示等级 —— 完成

- [x] `scenes/inventory/AttributeSummaryUI.tscn`：`LevelLabel` 与 `LevelValue` 插入 `AttributeGrid` 内、`PhysAtkLabel` **之前**，成为属性栏第一行。
- [x] `core/ui/attribute_summary_ui.gd`：新增路径常量、两个字段、`BindPlayerLevel()` 注入点、`_refresh_level()`、`_on_level_changed()`、信号连接/解除与跨语言兜底读取；`_refresh()` 内统一刷新等级行。

**实际结果**：运行时断言标签路径为 `.../AttributeSummaryUI/VBoxContainer/AttributeGrid/LevelValue`，文本 `"3"`，背包面板 `visible: true`。

**过程中修正的缺陷**：第一版把 `_ready()` 末尾写成 `if _player_level == null: BindPlayerLevel(...) else: _refresh()`，导致 `_player_level` 为 null 时不执行统一刷新，五项属性标签不再初始化。已改为绑定后**无条件**调用 `_refresh()`。

## 步骤 4：契约测试 —— 完成

- [x] 新建 `tests/godot/test_player_level_contract.gd`（13 个用例，覆盖形状锁定、曲线、边界、满级、接口、信号载荷）。
- [x] **补转发壳** `tests/test_player_level_contract.gd`：`test_run` 只扫 `res://tests` 顶层，缺壳则套件不被发现。
- [x] 修改 `tests/godot/test_attribute_summary_ui_contract.gd`：夹具标签列表补 `LevelValue`（否则 `_ready()` 取节点失败）、夹具末尾显式 `BindPlayerLevel(null)` 固定基线、新增 3 个等级行用例。

**实际结果**：`player_level_contract` **13/13 通过**；`attribute_summary_ui_contract` **7/7 通过**。

## 步骤 5：全量回归 —— 完成

- [x] `test_run()` 全量：**41 套件 / 312 通过 / 0 失败 / 33 跳过**，`player_level_contract` 已出现在 `suites_run` 中。

**实际结果**：编辑器日志新增的 2 条 `error` 经单独复跑 `room_terrain_store_contract` 确认来自该套件**故意触发的负面路径**（重复地形、空 `terrain_data`），非本次回归。

## 步骤 6：运行时验证 —— 完成

- [x] `project_run(mode="main")`：`game_status.status = "live"`、`helper_live: true`、`recent_errors: []`。
- [x] 主菜单阶段（无玩家实体）：`AddExperience(100)` → 等级 2、经验 0、挂起点 3 —— 验证点数在玩家缺席时不丢失。
- [x] 进程内 `change_scene_to_file("res://scenes/Main.tscn")`（不重启，避免 autoload 重置）：玩家 `_ready` 补领后 `AvailablePoints = 3`、挂起点 0。
- [x] 玩家在场时 `AddExperience(150)` → 等级 3、点数 3 → 6、挂起点 0（信号即时发放）。
- [x] `TryAllocatePoint` 成功：物攻 `100 → 125`，剩余 5 点（验证「玩家自行分配」闭环）。
- [x] 属性栏 `LevelValue` 文本为 `"3"`；`editor_screenshot(source="game")` 已捕获（当前模型不支持图像输入，未做目视判读，改以标签路径与文本断言替代）。
- [x] `project_manage(op="stop")` 已停止游戏。

## 步骤 7：文档与收尾 —— 完成

- [x] `docs/游戏机制与玩法内容.md` 新增「等级与经验系统」章节（接口说明、发点机制、挂起补领、以及「当前不接入任何玩法」的现状）与「数值一览」表。
- [x] 学习反馈摘要 + Git 提交描述已追加至 `临时反馈文档.md`（时间戳 `2026-09-22 19:24–19:40`）。
- [x] `git status` 复核：本次改动集中在 6 个文件 + 6 个新增文件；12 个 `combat_skills/*.tres` 为会话前既有改动。
- [ ] **提交与归档待开发者确认**：工作区含 12 个与本次无关的既有 `.tres` 改动，不宜由 AI 擅自纳入同一次提交；`task.py archive` 同样待确认后执行。

## 回滚点

| 回滚点 | 操作 |
| --- | --- |
| 步骤 1 后 | 删除 `core/progression/player_level.gd`（含 `.uid`）并注销 autoload；仓库回到改动前 |
| 步骤 2 后 | 还原 `entities/player.gd`；等级系统仍独立可用 |
| 步骤 3 后 | 还原两个 UI 文件；等级逻辑与发点不受影响 |
| 任意步骤 | 三处改动互相独立，均可单独回滚且不产生运行时报错（全链路走能力探测与 `get_node_or_null`） |

## Review Gate

步骤 2、3 的完成标志着「逻辑链路」与「展示链路」分别打通。实际执行中，步骤 3 的缺陷（初始化出口被条件分支绕开）正是在该 gate 的测试复核阶段被发现的，验证了 gate 的必要性。

## 流程偏差记录

`trellis-before-dev` 要求读全相关 spec。本次动手前只读了 `frontend/index.md`、`state-management.md`、`directory-structure.md`、`backend/index.md`，**漏读了 `frontend/quality-guidelines.md`** —— 而「MCP test_run 的套件发现路径与转发壳」一节（该文件第 303 行起）早已完整记录了转发壳约定与 `room_terrain_store` 的既有 `push_error` 陷阱。结果在步骤 4 额外花了一轮排查才发现缺壳。

**已沉淀**：动手前必须按 index 指向**逐篇**读完 layer 内的 guideline，而不是只读 index 本身。
