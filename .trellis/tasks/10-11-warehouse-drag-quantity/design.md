# 技术设计：WarehouseNew 数量拖拽

## 1. 现状职责（改动前已核实）

| 文件 | 现状职责 |
|---|---|
| `core/ui/warehouse/warehouse_item_slot.gd` | `Button` 适配：`pressed` → `slot_clicked`；`_get_drag_data` 调 `controller.create_drag_data(side, slot_index)` 并在 `drag_started` 信号后 `set_drag_preview(TextureRect)`；`_can_drop_data` / `_drop_data` 转发给控制器。 |
| `core/ui/warehouse/warehouse_section_controller.gd` | `RefCounted`。每个 `ScrollContainer/SlotGrid` 一个实例，惰性实例化 `item_slot2.tscn` 并把脚本替换为 `warehouse_item_slot.gd`；把 `slot_clicked` 接到根控制器 `_on_slot_clicked`；把 `drag_started` 接到根控制器 `clear_selection`。刷新**复用节点**，仅在容量不足/超出时增删。 |
| `core/ui/warehouse/warehouse_new_controller.gd` | `Node2D` 根。单选、TooltipPanel、生命周期（`init` / `exit` / `_exit_tree`）、权威信号订阅、`refresh()`、`create_drag_data` / `can_drop_item` / `drop_item`。 |
| `core/ui/warehouse/warehouse_transfer.gd` | `RefCounted`。`snapshot` 读取权威；`can_move` 校验来源快照 + `CanReceiveItemFrom` + 满堆叠拒绝；`move` 提交**整组**移动（同区走 `MoveItem`，跨区走短期 `InventoryComponent` 行囊桥 + 写回 `SetCarryEntry`）。 |
| `resources/item/item_stack.gd` | `SetItem` 会**清空** `RolledAttributes`；`CopyFrom` 保留；`Add` 保留目标属性并返回溢出。 |
| `entities/components/inventory_component.gd` | `GetStackAt`、`CanReceiveItemFrom`、`MoveItem`、`MoveItemFromDeferred`、`_notify_inventory_changed`（含尾槽规则）。`GlobalWarehouse` 的脚本 `entities/components/warehouse_inventory_component.gd` 继承它。 |
| `core/autoloads/ItemsControl.gd` | 行囊权威：`GetCarryEntry` / `SetCarryEntry`（写入即 `carry_items_changed.emit()`）/ `ClearCarryEntry`；条目只有 `{item, count}`，**没有**洗炼属性。 |

## 2. 行为缺口与落点

缺口只有一处：现有链路只能整组搬运，**没有任何"按数量搬运"的原语**，也没有"拖动会话"这一层状态。因此新增一层仓库专用拖动会话，并把按数量搬运下沉到 `warehouse_transfer.gd`：

- 「按数量搬运」属于数据规则 → 放 `warehouse_transfer.gd`。
- 「会话、剩余数量、右键长按计时、目标查找、预览」属于交互状态 → 放新文件 `core/ui/warehouse/warehouse_drag_controller.gd`。
- 根控制器只负责装配、输入转发、刷新转发与 `@export`。
- 格子脚本只增加"把选中态交给控制器"和"预览由控制器构建"两处。

## 3. 数据模型：拖动会话

会话只在内存中存在，**不在拖动开始时从权威取走物品**。来源物品在每次实际放置前一直留在原权威位置，因此取消必然无损。

```
session = {
    side, index          # 来源格
    mode                 # &"full"（未选中，整组）或 &"half"（已选中，拆半）
    data                 # 当前来源快照 {item, amount, rolled} + {owner, side, index, token}
    remaining            # 剩余可放置数量（预览显示值）
    hold_time            # 本次右键按下的持续秒数
    accumulator          # 连续放置的帧间余量
    auto                 # 是否处于右键长按连续放置
}
```

- 开始时 `remaining = mode == full ? 来源数量 : ceil(来源数量 / 2)`。
- 每次成功放置 1 个后：`remaining -= 1`，并**立即重取来源快照**写回 `data`（保持 `can_move` 需要的"快照等于权威"不变式）。
- 会话期间 `data.amount == 来源权威数量` 始终成立（full 模式天然成立；half 模式的余量是 `ceil(原始数量 / 2)`，每次放置后来源与余量同步递减，投完余量后来源剩下 `floor(原始数量 / 2)`）。
- 每次提交前用 `snapshot` 与 `data` 比对来源；不一致（外部改过库存）→ 立刻 `cancel()`，不提交。
- 会话结束：投放成功、左键释放后无投放、来源失效、`exit()`、`_exit_tree()`。`end()` 必须幂等。

## 4. 新增文件：`core/ui/warehouse/warehouse_drag_controller.gd`

`extends RefCounted`。无 `_process`：由根控制器每帧调用 `tick(delta)`。

必须实现的公共接口（方法名、参数、返回值固定，文档与测试按此引用）：

```gdscript
## 绑定宿主、传输层与目标解析。参数 host 为根控制器（须提供 commit_placement /
## commit_group_drop / refresh_slot / set_drag_session_active）、transfer 为
## warehouse_transfer 实例、resolver 为无参 Callable（返回 [side, index] 或 []）；返回无。
func bind(host: Node, transfer: RefCounted, resolver: Callable) -> void

## 设置连续放置速率。三个参数单位均为"个/秒"，acceleration 为"个/秒²"；返回无。
func set_rates(initial: float, acceleration: float, maximum: float) -> void

## 是否处于拖动会话；返回布尔。
func is_active() -> bool

## 当前剩余可放置数量；返回整数，无会话时返回 0。
func remaining() -> int

## 开始会话。参数 side/index 为来源、selected 为按下前的持续选中态；
## 返回拖动载荷字典；不能拖动（空槽或无物品）时返回 {}。
func begin(side: StringName, index: int, selected: bool) -> Dictionary

## 构建拖动预览（含剩余数量）。参数 item 为来源物品；返回 Control，宿主用 set_drag_preview 使用。
func create_preview(item: Resource) -> Control

## 预检目标。参数 data 为载荷、side/index 为目标；返回布尔。
## full 模式沿用整组交换规则；half 模式只接受空格或同类未满格。
func can_drop(data: Dictionary, side: StringName, index: int) -> bool

## 提交剩余数量并结束会话。参数 data/side/index 同上；返回是否发生移动。
func drop(data: Dictionary, side: StringName, index: int) -> bool

## 处理右键按下：先在鼠标下的格子放 1 个，再开始连续放置计时。返回是否消费事件。
func press_secondary() -> bool

## 处理右键松开：停止连续放置（不结束会话）。返回无。
func release_secondary() -> void

## 每帧推进连续放置。参数 delta 为秒；返回无。
func tick(delta: float) -> void

## 左键释放后的收尾（由根控制器延迟调用），未投放时丢弃剩余并结束会话。返回无。
func finish_after_release() -> void

## 立即结束并丢弃会话（幂等）。返回无。
func cancel() -> void
```

内部规则：

1. `_rate_at(t) = minf(_max_rate, _initial_rate + _acceleration * t)`；参数 ≤ 0 时视为 0（不放置）。
2. `tick`：仅在 `_auto` 且会话有效时累加 `hold_time` 与 `accumulator`；`while accumulator >= 1.0 / _rate_at(hold_time)` 时尝试放 1 个并扣减 `accumulator`，单帧最多循环 60 次（安全阀）。放置失败（目标不接受）只退出本轮循环，**不结束**连续放置，允许玩家把鼠标滑到别的格子继续放。
3. `press_secondary`：用 `resolver` 取鼠标下格子 → 若等于来源或为空则返回 false；否则放 1 个，然后 `hold_time = 0`、`accumulator = 0`、`_auto = true`，返回 true。第二个及之后的右键**按下**事件（Godot 不重复派发按下，故无需处理重复）不得重复启动。
4. 放置一次：`can` 校验 → `host.commit_placement(data, side, index, 1)` → 成功则 `remaining -= 1`、重取来源快照、`_refresh_preview()`、`host.refresh_slot(来源)` 与 `host.refresh_slot(目标)`；`remaining == 0` 时停止 `_auto`（会话仍保留到左键释放，以便预览继续显示 0）。
5. `drop`：`full` 模式调用 `host.commit_group_drop(data, side, index)`（保留 `move()` 的不同物品交换）；`half` 模式调用 `host.commit_placement(data, side, index, remaining)`；成功后刷新两个格子并结束会话。`remaining <= 0` 时 `can_drop` 返回 false。
6. `can_drop`：会话未激活、`data` 与当前会话令牌不符、或 `remaining <= 0` → false。`full` → `transfer.can_move(...)`；`half` → `transfer.can_receive_amount(data, side, index, remaining)`。
7. `finish_after_release`：会话仍在时直接 `cancel()`（此时原生投放若已发生，`drop` 早已结束会话，本函数无副作用）。
8. 预览：`Control`（`custom_minimum_size` 56×56）+ 铺满的 `TextureRect`（物品图标）+ 右下对齐的 `Label`（文案 `"x%d" % remaining`）。只创建一次，`_preview_label` 持有引用用于刷新。图标用 `res://resources/item/item_data_compat.gd` 的 `get_display_icon(item, null)`，与 `warehouse_item_slot.gd` 一致。
9. 令牌：`data` 里写入稳定键 `token`（自增整数）与 `owner`（宿主 `get_instance_id()`），`can_drop` / `drop` 用它与当前会话比对，拒绝别的界面或过期载荷传来的字典。

## 5. 修改 `core/ui/warehouse/warehouse_transfer.gd`

新增两个方法（公共，中文 `##` 文档注释）：

```gdscript
## 判断目标能否按数量接收来源物品：只接受空格或同类未满格。
## 参数 data 为来源快照、side/index 为目标、amount 为希望接收的数量；返回布尔，无副作用。
func can_receive_amount(data: Dictionary, side: StringName, index: int, amount: int) -> bool

## 按数量把物品从来源搬到目标；只接受空格或同类未满格。
## 参数 data 为来源快照、side/index 为目标、amount 为希望移动的数量；
## 返回实际移动数量（0 表示未移动），失败时权威不变。
func move_amount(data: Dictionary, side: StringName, index: int, amount: int) -> int
```

`can_receive_amount` 的判定顺序（任一条不满足即 false）：

1. `amount > 0`；`side`/`index` 通过既有 `_valid_index`（含行囊解锁容量）。
2. 来源与目标不是同一格。
3. `data` 形状与 `can_move` 同源（`item` 为 Resource、`amount` 为 int、`rolled` 为 Dictionary、`side`/`index` 合法）。
4. `snapshot(来源) == data`（物品身份、数量、洗炼属性全等），否则视为过期快照。
5. 目标权威 `CanReceiveItemFrom(来源权威, 来源索引, 目标索引)` 为 true（复用跨区行囊桥与 `_can_store_item` 规则）。
6. 目标堆叠为空，或 `same_item` 且 `not IsFull`。

`move_amount` 的提交（先校验，再一次性改权威；`moved = mini(amount, 来源当前数量)`）：

- 仓库 → 仓库：直接操作两个 `ItemStack`。目标空 → 写入 `item/amount/rolled`；目标同类未满 → `Add(moved)`。来源扣减必须保留洗炼属性：先备份 `RolledAttributes`，调 `SetItem(item, amount - moved)`（内部会在 ≤ 0 时 `Clear`），剩余为正时再写回备份属性。最后调 `_warehouse.call("_notify_inventory_changed")`（保持尾槽规则）。
- 跨区：复用现有 `_carry_inventory()` 行囊桥。来源是仓库时先按上面的方式扣仓库、再改桥上的目标堆叠；来源是行囊时改桥上的来源堆叠并写回 `SetCarryEntry`。桥 → 权威的写回沿用 `move()` 已有的 `for position in _capacity` 对比循环。仓库参与时 `_warehouse.call("_notify_inventory_changed")`，行囊由 `SetCarryEntry` 自行广播。

**约束**：`move_amount` 不得调用 `MoveItem` / `MoveItemFromDeferred`（它们是整组语义）。

## 6. 修改 `core/ui/warehouse/warehouse_item_slot.gd`

- `_get_drag_data`：改为 `_controller.call("create_drag_data", side, slot_index, is_selected())`；拿到非空字典后 `drag_started.emit()`，再 `set_drag_preview(_controller.call("create_drag_preview", item))`，其中 `item` 为本地 `_item`。空字典 → 返回 null（不能拖动时不启动原生拖动，例如空槽）。
- 其余（`configure`、`bind_content`、`set_selected`、`is_selected`、`_can_drop_data`、`_drop_data`）不改。
- 不新增右键处理：右键由根控制器的 `_input` 在输入阶段统一处理。

## 7. 修改 `core/ui/warehouse/warehouse_new_controller.gd`

新增导出（名称固定，文档与检查器按此引用）：

```gdscript
@export var drag_place_initial_rate: float = 4.0    ## 拖动期间右键连续放置的初始速率（个/秒）
@export var drag_place_acceleration: float = 8.0    ## 连续放置速率的加速度（个/秒²）
@export var drag_place_max_rate: float = 30.0       ## 连续放置速率的最高上限（个/秒）
```

其余新增成员与方法：

- `var _drag: RefCounted = DRAG.new()`，`const DRAG: GDScript = preload("res://core/ui/warehouse/warehouse_drag_controller.gd")`。
- `_ready`/`_setup_view` 之后（`init()` 成功路径末尾）调用一次 `_drag.bind(self, _transfer, Callable(self, "_resolve_hovered_slot"))` 与 `_drag.set_rates(drag_place_initial_rate, drag_place_acceleration, drag_place_max_rate)`；`set_process(false)` 作为初始帧处理开关。
- `_process(delta)`：`if _drag != null: _drag.call("tick", delta)`。
- `_input(event)`：`_active` 且 `_drag.is_active()` 时才处理。右键按下 → `_drag.press_secondary()`；右键松开 → `_drag.release_secondary()`；两者都 `get_viewport().set_input_as_handled()`（拖动期间右键只服务数量分配，不泄漏给其它界面逻辑）。左键松开 → `_drag.call_deferred("finish_after_release")`（原生投放发生在 GUI 阶段，必须等本帧输入处理结束后再收尾）。
- `set_drag_session_active(active: bool)`：`set_process(active)`。
- `create_drag_data(side, index, selected) -> Dictionary`：委托 `_drag.begin(side, index, selected)`；`_active` 为 false 时返回 {}。
- `create_drag_preview(item) -> Control`：委托 `_drag.create_preview(item)`。
- `can_drop_item(data, side, index) -> bool`：`_active and not _moving and _drag.can_drop(...)`。
- `drop_item(data, side, index) -> bool`：`can_drop_item` 通过后 `var moved := _drag.drop(...)`，然后 `clear_selection()` + `refresh()`，返回 `moved`。**不再自行设置 `_moving`**（`_moving` 由 `commit_placement` / `commit_group_drop` 拥有）。
- `commit_placement(data, side, index, amount) -> int`：`_moving = true` → `_transfer.move_amount(...)` → `_moving = false` → 返回实际移动数量。
- `commit_group_drop(data, side, index) -> bool`：`_moving = true` → `_transfer.move(...)` → `_moving = false`。
- `refresh_slot(side, index) -> void`：只重绑一个格子的内容（`snapshot` → `bind_content`），并刷新 `PackbackSection/CapacityLabel` 的占用计数；不重建节点，避免打断正在进行的原生拖动。
- `_resolve_hovered_slot() -> Array`：依次遍历 `[warehouse, carry]` 两区，要求鼠标点同时落在该区 `ScrollContainer` 的全局矩形与某个格子的全局矩形内（用 `slot.get_global_rect().has_point(slot.get_global_mouse_position())`，滚动裁切用 `ScrollContainer.get_global_rect()`），返回 `[side, index]`；未命中返回 `[]`。
- `exit()` / `_exit_tree()`：追加 `_drag.cancel()`。
- `refresh()`：把容量文案更新抽成一个小函数，供 `refresh_slot` 复用；其余逻辑（选中失效检查等）不变。

**不修改**：`_on_slot_clicked`、`_subscribe`、`sort_items`、升级与导航逻辑、`_ignore_decoration`。`scenes/Warehouse/WarehouseNew.tscn` 一个字节都不改（导出字段的默认值由脚本提供，检查器可见）。

## 8. 拖动收尾的时序（关键，必须在真实验证中确认）

1. 左键按下 → （移动超过阈值）Godot 调 `_get_drag_data` → 会话开始。
2. 拖动期间 `_input` 收到右键按下/松开 → 单个或连续放置。`_process` 推动加速计时。
3. 松开左键：`_input` 先收到（只安排延迟收尾），随后 GUI 阶段投放到目标槽 → `_drop_data` → `drop_item` → `_drag.drop()` 同步结束会话。
4. 若松开在无效目标/格子外：`_drop_data` 不触发，本帧末尾 `finish_after_release` 取消会话。
5. 失焦、`exit()`、`_exit_tree()` → 立即 `cancel()`。会话未成交时物品本就在来源，不需要归还。

**已知风险**：Godot 原生拖动期间，被拖控件之外的格子可能收不到 `gui_input`；本设计因此把右键放在根控制器的 `_input`（输入阶段，早于 GUI 阶段）处理，并用宿主矩形自查找目标，而不是依赖格子回调。实施时必须用 `game_manage` 真实鼠标输入确认右键事件确实到达 `_input` 且不会取消原生拖动；若某些事件序列仍被原生拖动吃掉，`tick` 的连续放置不得受影响（连续放置只需要 `_input` 的按下/松开与 `_process`）。

## 9. 测试边界

- 单元测试（`tests/godot/test_warehouse_drag_quantity.gd`，`extends McpTestSuite`，`suite_name()` 返回 `"warehouse_drag_quantity"`）覆盖全部**纯逻辑**：按数量搬运守恒、属性保留、只收空格/同类未满格、过期快照拒绝、拆半向上取整、右键单个放置、加速曲线与上限、松开右键停止、取消保留余量、整组交换、行囊侧按数量搬运。
- 会话逻辑测试用**宿主桩**：脚本内 `class StubHost extends Node`，提供 `commit_placement` / `commit_group_drop` / `refresh_slot` / `set_drag_session_active`，内部转发到真实的 `warehouse_transfer` 实例；`resolver` 用返回固定目标或 `[]` 的 `Callable`。这样不需要真实 UI，也不伪造结果。
- 真实鼠标输入、预览画面、原生拖动是否被中断、格子在拖动期间是否正确刷新，属于运行验证，必须走编辑器 MCP，不能在单元测试里伪造通过。
- 不改动 `tests/godot/test_warehouse_new_transfer.gd`（保持原有 5 例，作为回归基线）。

## 10. 不做什么

- 不重构 `warehouse_transfer.move()` 的既有整组逻辑，只新增并行方法。
- 不为行囊新增洗炼属性（存档格式不变）。
- 不改 `item_slot2.tscn`、`TooltipPanel`、`ItemTooltipPresenter`。
- 不新增 autoload、不改 `project.godot`、不改商店与局内背包。
