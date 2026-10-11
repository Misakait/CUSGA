# 执行计划：WarehouseNew 数量拖拽

## 审阅门槛

- [x] 用户批准为 WarehouseNew 数量拖拽创建独立 Trellis 任务并实施已展示方案。
- [x] 已核对 `warehouse-drag-plan-2026-10-11.md` 的边界规则与用户补充的 8 条实施要求一致。
- [x] 需求、技术设计、执行计划与实现/检查上下文清单已写入本任务。
- [x] 实施批准已取得；方案细节按 design.md 固定，不再重复询问。
- [x] 实施完成后委派独立修复子代理收尾，再由主会话执行编辑器 MCP 真实验收（结果见 `validation.md`）。

## 实现步骤

1. 阅读本任务 `prd.md` / `design.md` / `implement.md`、`AGENTS.md`、`agent.local.md`，以及 `.trellis/spec/frontend/component-guidelines.md` 的 WarehouseNew 契约段。
2. 在 `core/ui/warehouse/warehouse_transfer.gd` 新增 `can_receive_amount` / `move_amount`（按数量和搬运，只收空格或同类未满格，保留洗炼属性）。**先写这一步、先测这一步**。
3. 新建 `core/ui/warehouse/warehouse_drag_controller.gd`：会话、剩余数量、预览、右键加速计时、目标解析委托、载荷令牌。
4. 改 `core/ui/warehouse/warehouse_item_slot.gd`：把选中态传给 `create_drag_data`，预览改由控制器构建。
5. 改 `core/ui/warehouse/warehouse_new_controller.gd`：三个 `@export`、装配拖动控制器、`_input` / `_process` 转发、`commit_placement` / `commit_group_drop` / `refresh_slot` / `_resolve_hovered_slot`、`exit` 清理。
6. 新建 `tests/godot/test_warehouse_drag_quantity.gd`，`suite_name()` 返回 `warehouse_drag_quantity`，用宿主桩覆盖 design.md 第 9 节列出的全部纯逻辑边界。
7. `filesystem_manage(op="scan")` 后运行 `test_run` 聚焦本套件与 `warehouse_new_transfer` 回归；按 design.md 第 8 节做一次右键事件是否到达 `_input` 的运行时探针。

## 验证与复核

- `editor_state` 确认 CUSGA 4.7.1 已连接，`filesystem_manage(op="scan")` 刷新脚本。
- `test_run(suite="warehouse_drag_quantity")` 与 `test_run(suite="warehouse_new_transfer")` 必须全绿；`test_item_room_content.gd` 的既有 Parse Error 与本任务无关，不得算作本次失败。
- 真实运行：`project_run(mode="custom", scene="res://scenes/Warehouse/WarehouseNew.tscn")`，用 `game_manage` 的 `input_mouse` 完成：未选中左键按住拖动 → 预览剩余数量；选中后左键拖动 → 余量为 `ceil(数量/2)`（向上取整，数量 1 也照常拖走这 1 个）；右键按下不启动拖动；拖动期间在空格按右键 → 来源 −1、目标 +1；持续按住右键 → 放置次数随时间增加；松开右键 → 停止；松开左键到有效目标 → 余量入目标；松开到无效目标 → 余量留来源。
- `game_eval`（用 `Engine.get_main_loop()`，不用 `get_tree()`）断言：双区总数量、逐物品数量在每组操作前后守恒；失败目标无副作用；行囊条目数量与 UI 文案一致。
- `editor_screenshot(source="game")` 检查预览与格子数量显示。
- **验证前**备份 `%APPDATA%\Godot\app_userdata\CUSGA\save\game_save.json` 与 `game_save.json.bak`，**验证后**恢复，不能让测试数据残留。
- 每轮最后只 `project_manage(op="stop")`，保留编辑器；`logs_read(source="game")` 与 `logs_read(source="editor")` 检查阻塞错误。
- 主菜单冒烟：`project_run(mode="main")` 确认仓库/行囊缓存重入无报错。
- 全部完成后再跑一次 `git status` / `git log`，只保留本任务需要的改动，不覆盖用户已有改动，不提交、不推送。

## 文件边界

**产品修改**

- 新增 `core/ui/warehouse/warehouse_drag_controller.gd`
- 修改 `core/ui/warehouse/warehouse_transfer.gd`
- 修改 `core/ui/warehouse/warehouse_item_slot.gd`
- 修改 `core/ui/warehouse/warehouse_new_controller.gd`
- 新增 `tests/godot/test_warehouse_drag_quantity.gd`

**文档修改**

- `docs/游戏机制与玩法内容.md`（仓库段落的交互规则与全部数值/公式）
- `.trellis/spec/frontend/component-guidelines.md`（WarehouseNew 的 item_slot2 契约与拖动协议）
- 本任务目录内的规划与验证记录

**明确不改**

- `scenes/Warehouse/WarehouseNew.tscn`（用户未提交改动，原样保留）
- `scenes/Shop/ShopNew.tscn`、`core/ui/shop/**`、局内背包、`scenes/ui/item_slot2.tscn`、`project.godot`、存档格式
- `tests/godot/test_warehouse_new_transfer.gd`（保留为回归基线）
