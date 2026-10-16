# 掉落物自动拾取与缩小

## Goal

改造局内掉落物的呈现与拾取方式，共五条要求：

1. **缩小到现在的 40%** —— 掉落物的显示大小与鼠标命中区域都按当前尺寸的 40% 呈现。
2. **靠近自动拾取** —— 玩家进入掉落物的自动拾取半径后，掉落物**自动**进入背包。
3. **取消手动点击拾取** —— 不再支持用鼠标点击掉落物来拾取；点击掉落物不再产生任何拾取行为，也不再弹出「距离不够！」。
4. **拾取表现** —— 拾取成功时掉落物飞向玩家并缩小到消失。
5. **背包满则不触发** —— 背包放不下时**完全不触发**拾取：掉落物留在原地，不飞、不消失、不扣仓库记录。

## Background（已核实事实，带证据锚点）

### 生产掉落视图与遗留视图是两套，本次只改生产路径

- **生产掉落视图**：`scenes/Loot/Loot.tscn` → `scripts/loot_scripts/loot_view.gd`。
  `scenes/Main.tscn` 把 `BoardController.LootViewScene` 显式绑定为 `res://scenes/Loot/Loot.tscn`（`Main.tscn:7` 的 `ext_resource`，`Main.tscn:93` 的赋值）。
- **生产地形视图**：`scenes/ItemTerrian/Item.tscn` → `scripts/item_scripts/item_view.gd`（`Main.tscn` 的 `4_vcsgt`）。
- **遗留视图**：`scenes/board_card_scene/BoardCardView.tscn` → `core/board/board_card_view.gd`。它只在 `BoardController.LootViewScene` / `TerrainViewScene` 为空时作为回退（`core/board/board_controller.gd:81-86`），生产 `Main.tscn` 已显式绑定，因此**不在生产路径上**；目前只被 `tests/godot/board_card_view_tests.gd` 与 `tests/godot/test_board_card_view_contract.gd` 引用。
- **结论**：缩放只改 `loot_view.gd` + `Loot.tscn`。`board_card_view.gd` 的掉落分支保持原样，避免无生产收益地推翻 `test_board_card_view_contract.gd:65` 的「掉落卡静止缩放必须保持一倍」断言。

### 缩放的作用点已经被现成字段收敛

- `scripts/loot_scripts/loot_view.gd:29` 的 `_base_visual_scale: Vector2` 是**唯一**的视觉基准：
  - `InitializeLoot`（`:86`）把它设为 `Vector2.ONE`；
  - `RefreshView`（`:146`）把它写进 `_visuals.scale`；
  - `_configure_motion`（`:314` / `:322`）用它生成 Idle / Hover 两条动画轨道的关键帧；
  - `PlayScatterFrom`（`:181`）从 `Vector2.ZERO` 补间到它；
  - `_process` 飞行（`:218`）从它线性插值到 `Vector2.ZERO`。

  因此**只改这一处赋值**就能让待机、悬停、散射、飞入四种表现整体缩到 40%，不需要逐个动画改关键帧。
- 同级已存在同类导出先例：`scripts/item_scripts/item_view.gd:15` 的 `@export_range(0.25, 5.0, 0.05) var TerrainVisualScale: float = 1.0`（注释明确「不缩放碰撞形状」）。掉落物需要一个**同时缩放命中区域**的同类参数。

### 动画参数资源是共享的，不能把掉落缩放塞进去

- `resources/interaction/item_motion_config.tres` **同时**被 `scenes/Loot/Loot.tscn:6`（掉落）与 `scenes/ItemTerrian/Item.tscn` 经 `item_view.gd:11` 引用。
- 往 `item_motion_config.gd` 增加「掉落缩放」字段会**同时改变地形卡表现**，因此缩放参数必须放在 `loot_view.gd` 自己的导出上（序列化进 `Loot.tscn`），不放共享资源。

### 命中区域是场景里序列化的独立形状

- `scenes/Loot/Loot.tscn:20-21` 定义 `RectangleShape2D_interaction`，`size = Vector2(93, 137)`，由 `Loot.tscn:121-122` 的 `Interaction/CollisionShape2D` 使用。
- 该形状**不随** `_visuals.scale` 变化：`Visuals` 是根 `Area2D` 的子节点（`Loot.tscn:72`），`Interaction` 是根 `Area2D` 的另一个子节点（`Loot.tscn:117`），两者是兄弟关系，缩放 `Visuals` 不会影响 `Interaction` 的碰撞形状。
- 因此「命中区域一起缩到 40%」必须**直接改场景里的形状尺寸**，改脚本缩放做不到。
- 40% 后的尺寸：`93 × 0.4 = 37.2`，`137 × 0.4 = 54.8`。

### 拾取结算已经集中在一个入口，且只差一个触发源

- `core/gameflow/world_interaction_coordinator.gd:513` 的 `_handle_loot_card_clicked(card, stack)` 已经完整实现「入包 → 记结算 → 删仓库记录 → 关闭命中 → 脱离房间 → 飞向玩家 → 飞行结束删卡」：
  - `:516` `_gameplay_port.call("TryAddItemToInventory", stack)`；
  - `:518-519` **失败直接 `return`**，不删记录、不动画 —— 「背包满不触发」的语义**已经存在**，本次只需保证新触发源也走同一道门；
  - `:528` `_loot_store.call("RemoveLoot", room, loot_id)`；
  - `:535-536` `_board_controller.call("DetachForFlight", card)`；
  - `:540` `card.call("PlayFlyTo", target, ...)`；
  - `:547` `_on_loot_fly_finished` → `RemoveCard`。
- **飞向玩家 + 缩小到消失**已由 `loot_view.gd:189-220` 的 `PlayFlyTo` 实现：目标为 `PlayerChar` 节点时每帧追踪玩家当前位置（`:217`），`_visuals.scale` 从 `_base_visual_scale` 线性插值到 `Vector2.ZERO`（`:218`），到 1.0 时回调 `_finish_flight`（`:219-220`）。本次**不需要重写飞行动画**，只需要它从新的 40% 基准开始缩。
- 因此本次改动的实质是：**换触发源（点击 → 靠近），并删掉点击路径**。

### 距离判定助手被契约测试逐字锁定，不能加第三个调用点

- `tests/godot/test_world_interaction_coordinator_contract.gd:480-484` 断言协调器源码中
  `var range_check: Dictionary = _try_get_interaction_range(card)` 恰好出现 **2 次**（点击入口 + 长按入口）。
- 同文件 `:468-477` 还逐字锁定 `_try_get_interaction_range` 的**函数体两行**：
  - `var distance: float = _player_char.global_position.distance_to(card.global_position)`
  - `return {"ok": distance <= InteractionRange, "distance": distance}`
- **结论**：自动拾取必须走**自己的**判定助手与**自己的**半径导出，不能复用 `_try_get_interaction_range` 来「省一次计算」，否则要么撞上 2 次的计数断言，要么被迫改锁定字面量。

### 自动拾取半径的用户决策

- 用户明确选择：**新增独立导出 `AutoPickupRange`，默认值取小（60）**，语义是「必须真的贴到掉落物附近才拾取」。
- 与 `InteractionRange`（`:95`，默认 160，地形交互用）分离，便于后续独立调拾取手感。

### 背包满的判定是只读的

- `entities/player.gd:213` `TryAddItemToInventory(stack)` = `:222` `CanAddItemStack` 预检查 + `:224` `AddItemStack`，注释明确「世界掉落只有完整成功才会被删除，预检查避免部分放入后仍留下完整掉落卡」。
- `entities/components/inventory_component.gd:323` 的 `CanAddItemStack` 文档明确「能完整加入时为 true，**不修改库存**」；`:283` 的 `AddItemStack` 才写槽位。
- 因此「每帧尝试、满了就失败」不会产生副作用；且一旦玩家腾出空间，**后续帧的尝试就会成功**，天然实现「原地等待、腾出即拾取」，不需要额外的冷却或重试计时器。

### 掉落卡也在棋盘快照里，可被统一轮询

- `core/board/board_controller.gd:353` `GetActiveCardsSnapshot()` 返回全部活动卡牌，已在 `world_interaction_coordinator.gd:653`（时间变化刷新）被使用，契约测试 `:329` 锁定该调用片段存在。
- 掉落卡与地形卡靠 `card.call("GetLootStackOrNull")` 区分：掉落视图返回堆叠（`loot_view.gd:102`），地形视图不返回堆叠。
- `DetachForFlight`（`board_controller.gd:297`）只 `reparent`、**不从 `_active_cards` 移除**，所以飞行中的卡仍在快照里，必须有「已在拾取中」的判据避免二次拾取。
- 协调器已有每帧 `_process`（`world_interaction_coordinator.gd:217`，当前用于键盘接管时取消地形长按），可直接承载轮询；`CanUseWorld()`（`:162`）已提供「非暂停、非过场、棋盘可见」的现成门禁。

### 需要一并封掉的第二个点击入口

- `world_interaction_coordinator.gd:571` 的 `_on_board_card_pressed` 在 `:577-580` **先做距离判定**，之后 `:582` 才判断是否可长按地形。
- 因此当前**按下掉落物**也会走到 `_report_out_of_range_interaction` 弹出「距离不够！」。取消点击拾取后，这条对掉落物的误报也必须一起封掉。

### 文档影响面

- `docs/游戏机制与玩法内容.md:31` 记录 `InteractionRange` 默认 160 及其依据。
- `docs/游戏机制与玩法内容.md:532` 记录地形卡与掉落物的场景分工、命中区域与动画时长来源。

## Source Requirements

| 编号 | 用户原话要点 | 对应验收 |
| --- | --- | --- |
| SR-1 | 将掉落物的大小变为现在的 40% | AC-1 / AC-2 |
| SR-2 | 拾取改为玩家靠近掉落物自动拾取到背包 | AC-3 / AC-4 / AC-5 |
| SR-3 | 不再支持手动点击掉落物拾取 | AC-6 / AC-7 |
| SR-4 | 拾取时掉落物飞向玩家并缩小到消失 | AC-8 |
| SR-5 | 背包满了则不会触发拾取 | AC-9 / AC-10 |

## Acceptance Criteria

### 尺寸

- [ ] **AC-1** 掉落物显示大小为改动前的 **40%**：待机呼吸、悬停挤压、散射入场、飞入四种表现都从 40% 基准出发，不出现「待机是 40% 但悬停弹回 100%」这类基准不一致。
- [ ] **AC-2** 掉落物的鼠标命中区域（`Loot.tscn` 的 `RectangleShape2D_interaction`）尺寸从 `93×137` 变为 `37.2×54.8`，与视觉保持同一比例。

### 自动拾取

- [ ] **AC-3** 玩家与掉落物的世界坐标距离 **≤ `AutoPickupRange`（默认 60）** 时，掉落物自动入包，**无需任何鼠标操作**。
- [ ] **AC-4** 自动拾取成功时完整走通既有结算链：物品进背包 → `SettlementManager.record_resource` 记账 → `RoomLootStore.RemoveLoot` 删除该房间记录 → 关闭命中 → 脱离房间 → 飞向玩家 → 飞行结束删卡。
- [ ] **AC-5** `AutoPickupRange` 是独立于 `InteractionRange` 的导出，可在检查器中单独调整；默认值 **60**。

### 取消点击拾取

- [ ] **AC-6** 鼠标点击掉落物**不会**拾取：物品不入包、仓库记录不删、不播放飞入动画。
- [ ] **AC-7** 点击或按下掉落物**不会**弹出「距离不够！」飘字，也不再输出对应的「拒绝超出范围的交互」调试日志。地形卡的点击/长按距离门禁与飘字**保持不变**。

### 拾取表现

- [ ] **AC-8** 拾取时掉落物从当前位置飞向玩家（飞行中持续追踪玩家移动），同时从 40% 基准缩小到 0，缩到 0 后节点被移除，不在场景树中残留。

### 背包满

- [ ] **AC-9** 背包放不下时**不触发**拾取：掉落物留在原地、不飞、不缩小、不消失；`RoomLootStore` 记录保留；不产生结算记账。
- [ ] **AC-10** 玩家仍站在范围内、之后腾出背包空间时，拾取**自动发生**，不需要走开再回来。

### 边界与回归

- [ ] **AC-11** 同一掉落物在飞行动画期间不会被二次拾取（不出现重复入包或重复记账）。
- [ ] **AC-12** 战斗过场、进入/退出战斗、结算收尾（`_is_run_ending()`）与暂停状态下**不**触发自动拾取。
- [ ] **AC-13** 既有契约测试全部继续通过，特别是 `test_world_interaction_coordinator_contract.gd` 中：
  - `PlayFlyTo` 调用字面量（`:332`）保持不变；
  - `_try_get_interaction_range` 调用**恰好 2 次**（`:480-484`）与 `_try_get_interaction_range` 函数体两行字面量（`:468-477`）保持不变；
  - `GetActiveCardsSnapshot` / `RemoveCard` 协议片段（`:329` / `:330`）保持不变。
- [ ] **AC-14** 新增自动拾取契约测试套件，覆盖「范围内触发」「范围外不触发」「背包满不触发」「腾出空间后触发」「点击不拾取」「飞入中不二次拾取」。
- [ ] **AC-15** Main 场景冒烟：无 `SCRIPT ERROR` / `Parse Error` / `Failed to load script` / 本次改动引入的资源加载错误；用真实运行画面确认 40% 尺寸、飞入缩小消失、背包满不拾取三种行为。
- [ ] **AC-16** `docs/游戏机制与玩法内容.md` 同步更新：掉落物尺寸、命中区域、自动拾取半径与「不再点击拾取」的说明。
- [ ] **AC-17** 验证结束后 `git status` 只包含本任务需要的改动，不覆盖 Godot 编辑器改写的版本控制文件。

## Out of Scope

- **不改** 遗留视图 `core/board/board_card_view.gd` 与 `scenes/board_card_scene/BoardCardView.tscn` 的掉落缩放与点击行为。用户已确认只改生产路径；`test_board_card_view_contract.gd:65` 的「掉落卡静止缩放必须保持一倍」断言保持有效。
- **不改** 地形卡（`Item.tscn` / `item_view.gd`）的尺寸、命中区域、点击与长按交互。
- **不改** `InteractionRange` 的数值与语义，也不改地形卡的「距离不够！」飘字。
- **不重写** 飞行动画实现：`loot_view.gd` 的 `PlayFlyTo` 已满足「飞向玩家 + 缩小到消失」，本次只让它从新的缩放基准出发。
- **不新增** 背包已满的画面提示（例如「背包已满」飘字）。用户只要求「不触发拾取」，未要求提示。
- **不做** 掉落物的磁吸/加速吸附效果，只做「进入半径即拾取」。
- **不引入** 新的 autoload、新的碰撞层或新的全局服务。

## Open Questions

无。用户已在会话中确认两项设计分叉：

1. 命中区域**跟随视觉一起缩到 40%**（而非保持原尺寸或彻底移除鼠标交互）。
2. 自动拾取半径**新增独立导出且默认取小（60）**（而非复用 `InteractionRange` 或取 160）。

## Notes

- 任务复杂度判定：**复杂**。跨 2 个生产脚本 + 1 个场景资源 + 1 个契约测试套件 + 1 份文档，且需要新增运行时验证路径，因此除 `prd.md` 外还必须产出 `design.md` 与 `implement.md`。
- 本任务由 2026-10-16 会话经 `trellis-start` 创建。
- **已知取舍**：命中区域缩到 `37.2×54.8` 后，掉落物的悬停热区会非常小，鼠标悬停动画变得很难触发。这是用户明确选择「一起缩到 40%」的直接后果；由于手动点击拾取已被取消，悬停动画不再是拾取的必要路径，因此判定为可接受。若后续觉得热区过小，可单独把 `RectangleShape2D_interaction` 调大而不影响视觉尺寸。
