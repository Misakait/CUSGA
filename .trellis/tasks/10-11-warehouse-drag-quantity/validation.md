# 验证记录：WarehouseNew 数量拖拽

## 环境与口径

- 引擎：Godot 4.7.1-stable (official)，编辑器 MCP 会话 `cusga@52ba69b21036707d`（编辑器 PID 18464），当前场景 `res://scenes/Warehouse/WarehouseNew.tscn`。
- 验证方式：`test_run` 聚焦套件 + `project_run(mode="custom", scene="res://scenes/Warehouse/WarehouseNew.tscn")` 下的完整鼠标事件序列（`Input.parse_input_event`，事件显式带 `position` / `relative` / `button_mask`）+ `game_eval` 权威数量断言 + `editor_screenshot(source="game")`。
- 光标口径：Godot 的 GUI 命中与根控制器 `_resolve_hovered_slot()` 都用**真实光标**；注入的 motion 只驱动 GUI 悬停与拖动目标。因此每个目标点都先用 `DisplayServer.warp_mouse(窗口内坐标)` 定位真实光标（本机 1280×720，仓库格中心 x=108/188/268/348、y=175，行囊格中心 y=165、x=733/813/893）。
- 拖动启动口径：motion 事件必须带 `relative`，按下/松开必须显式给 `pressed` 与正确的 `button_mask`；缺 `relative` 时 Godot 不会开始原生拖动。
- 存档保护：每轮验证前先复制 `%APPDATA%\Godot\app_userdata\CUSGA\save\game_save.json` 与 `game_save.json.bak`，结束只 `project_manage(op="stop")`，随后覆盖还原并对比 SHA256、删除备份文件。存档由用户自己使用同一份游戏写盘，实测过两个版本：1027 B / sha256 `0E2AD53E…D21A894`（本任务首次验证时）与 1470 B / sha256 `77ECFDED…B41FBCD`（用户自己玩过一局后的当前版本）。每次验证都以运行前的真实文件为准，不复用旧备份。

## 测试结果

| 套件 | 结果 | 备注 |
|---|---|---|
| `warehouse_drag_quantity`（新增，14 例） | passed 14 / failed 0 | 覆盖按数量搬运、属性保留、拒绝路径、拆半向上取整（含数量 1 照常拖动）、加速曲线、取消守恒 |
| `warehouse_new_transfer`（回归基线，5 例） | passed 5 / failed 0 | 原有整组转移契约未被破坏 |

`load_errors` 只含既有问题：`test_item_room_content.gd (cannot instantiate — abstract or broken; reload=Parse error)`。

## 运行时验收矩阵

夹具为直接写入权威的确定性数据（`GetStackAt(i).SetItem(item, n)` + `emit_signal("InventoryChanged")`）。

| 编号 | 需求 | 观察值 |
|---|---|---|
| F1 | 未选中拖动全部 | 来源 9 → `begin`：`remaining=9`、`mode=full`、`_preview` 已创建、`gui_is_dragging()=true` |
| F2 | 已选中拖一半向上取整 | 点击选中（`is_selected()=true`）后拖动：`remaining=5`、`mode=half`、`amount=9`、来源仍 9（不预扣）；另测 3→2、1→1（`ceil(1/2)=1`，数量 1 也照常拖走这 1 个） |
| F3 | 右键不能启动拖动 | 无会话时右键按下并保持 0.4 s：`is_active()` 恒为 false、来源 9 / 目标 3 不变 |
| F4 | 拖动中右键放 1 个 | 半拆余量 5 → 右键一次：来源 8、目标 1、余量 4、`_auto=true` |
| F5 | 长按加速 | 来源 200：第 1 秒 +8 个（995 ms）、第 2~4 秒 +70 个（3001 ms，≈23.3 个/秒）、第 5 秒 +30 个（1000 ms，达上限） |
| F6 | 松开右键停止 | 松开后 0.3~0.6 s 内余量不变（4→4、91→91），`_auto=false` |
| F7 | 松开左键投放余量 | 未选中 9 个投到空格：来源 0 / 目标 9；半拆 9 拖 5、右键 1 个后投余量 4：来源 4 / 目标 5 |
| F8 | 取消保留来源 | 余量 91 时在格子外 (640,600) 松开：`_resolve_hovered_slot()=[]`、来源 91 / 目标 109、双区总数 200 不变、会话结束；半拆在无效目标松开：来源 9 / 目标 3、总数 12 不变 |
| F9 | 只接受空格或同类未满格 | 半拆悬停"验收木料×3"的不同物品格按右键并保持 0.4 s：三方数量全不变、`_auto=false`；在该格松开左键：不移动、会话结束；单测另覆盖来源格自身、满堆叠、未解锁行囊格、无命中 |
| F10 | 整组保留不同物品交换 | 未选中拖槽 2（验收矿石×1）到槽 3（验收木料×3）：交换为槽 2=木料×3、槽 3=矿石×1，总数不变 |
| F11 | 三个 `@export` | `game_eval` 读到 4.0 / 8.0 / 30.0，`PROPERTY_USAGE_EDITOR` 已置位（检查器可调）；场景文件不序列化这三个值 |
| F12 | 预览显示剩余数量 | 拖动中 `_preview_label.text="x91"`（与 `remaining` 一致）；截图可见预览浮在光标处显示剩余数量 |
| F13 | 放置后刷新格子 | 拖动中格子文案 `x91` / `x109` 与权威一致；交换后文案变 `x3` / `x1`；行囊占用文案同步 |
| F14 | 数量守恒 | 每个场景都对双区总数取前后快照：15 / 200 / 12 / 13 全部不变 |

## 规则变更：拆半改为向上取整（2026-10-11）

用户后续明确要求「改一下，向上取整」，并在两个可选方案中选定「取消『数量 1 不启动』」：拆半数量从 `floor(数量 / 2)` 改为 `ceil(数量 / 2)`，已选中且数量为 1 的格子改为照常拖走这 1 个（此前 `floor(1 / 2) = 0`，不启动拖动）。

同步改动：`warehouse_drag_controller.gd` 的 `begin()`（`floori` → `ceili`，并删除因此不可达的「结果不足 1」兜底分支）、`tests/godot/test_warehouse_drag_quantity.gd` 的期望值与注释、`docs/游戏机制与玩法内容.md`、`.trellis/spec/frontend/component-guidelines.md`，以及本任务的 `prd.md`（F2 行与数值公式并保留用户原话）、`design.md`、`implement.md`。

变更后重跑与重测（同一套口径）：

| 项目 | 观察值 |
|---|---|
| 测试套件 | `warehouse_drag_quantity` passed 14 / failed 0；`warehouse_new_transfer` passed 5 / failed 0 |
| 未选中拖动 | 9 → 余量 9；1 → 余量 1（不受本次变更影响） |
| 已选中拖动（真实点击选中后走 `create_drag_data`） | 9 → 余量 **5**、`mode=half`、`amount=9`；3 → 余量 **2**；1 → 余量 **1**（载荷非空，拖动照常启动） |
| 半拆整条链路（真实鼠标事件） | 选中 9 → 余量 5；右键一次 → 来源 8 / 目标 1 / 余量 4；松开右键 0.3 s 后余量仍 4；松开左键投放到空格 → 来源 4 / 目标 5，双区总数 9 不变、会话结束 |
| 存档保护 | 备份（1470 B，sha256 `77ECFDEDCD6EE3B576E097C10C1F095E6C8F938200C79369A99047D6EB41FBCD`）→ 运行 → 只 `stop` → 覆盖还原并对比哈希一致（`restored_ok=True`）、备份文件删除 |

上表中 F2 / F4 / F6 / F7 的余量读数已按新规则重测；F1 / F3 / F5 / F8–F14 的结论不依赖拆半数值，原有读数仍然成立。

## 验证中发现并修复的两个缺口

**缺口 1：design.md §8 的「失焦 → cancel」未实现。**
通读 `warehouse_new_controller.gd` 确认只有 `_input` / `_process` / `exit()`，没有任何焦点通知处理。
修复：处理 `NOTIFICATION_APPLICATION_FOCUS_OUT` → `_drag.cancel()`（不用 `NOTIFICATION_WM_WINDOW_FOCUS_OUT`，那是 Window/MainLoop 通知，普通 Node 收不到）。
复验（`loop.root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)`，与 SceneTree 实际派发路径一致）：`active [true→false]`、来源 9 不变、目标 0 不变。

**缺口 2：Godot 自己结束原生拖动时会残留会话。**
实测：会话进行中、左键仍按住时再收到一次左键按下，Godot 结束自己的拖动且 `_input` 收不到左键松开，出现 `gui_is_dragging()=false` 而 `is_active()=true`；此时若 `remaining>0`，之后一次普通右键会从旧来源放出 1 个。
修复：`warehouse_item_slot.gd` 的 `NOTIFICATION_DRAG_END` → `on_drag_finished()`；控制器用 `_drag.call_deferred("finish_after_release")` 收尾（同步取消会抢在同一帧的 `_drop_data` 之前，使合法投放失效）。
复验：第二次左键按下后 `[gui_is_dragging=false, is_active=false]`、来源 9 不变；随后在 `["warehouse",4]` 上右键仍为来源 9 / 目标 0 不变。回归投放正常：来源 0 / 目标 9、会话与拖动同时结束。

## 既有问题（非本次改动引入）

- `tests/godot/test_item_room_content.gd` 的 Parse Error 使 `load_errors` 出现该条；两套聚焦测试均为 0 失败。
- 编辑器 Debugger Errors 面板曾有两条无时间戳的 `Invalid call. Nonexistent 'int' constructor.`（指向测试文件 183/422 行）；当前 183/422 行是单参数 `int(...)`，文件内不存在双参数 `int()` 调用，且两次 `test_run` 均为 0 失败，判为更早版本测试文件的陈旧行。

## 未做与待决定

- 未跑 `project_run(mode="main")` 主菜单冒烟：本次改动只涉及仓库拖动会话（`_input` / `_process` / 焦点通知 / 拖动结束通知），未改场景缓存与重入逻辑；如需可作为补充。
- 未新建 `docs/仓库系统.md`：超出本次批准的文件范围（批准范围见 `implement.md` 的文件边界）。若需要一份与 `docs/商店系统.md` 对应的独立仓库模块文档，需另行批准。
- `Input.parse_input_event` 注入无法模拟"拖动到其它窗口后再松开"这种真实 OS 级失焦/丢事件；该路径由 `NOTIFICATION_APPLICATION_FOCUS_OUT` 与 `NOTIFICATION_DRAG_END` 两条收尾通道覆盖。
