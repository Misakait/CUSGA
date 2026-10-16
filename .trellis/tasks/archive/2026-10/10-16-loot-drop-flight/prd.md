# 掉落物从原物品处飞出的掉落动画

## Goal

破坏物品产出掉落物时播放掉落动画：掉落物从原物品所在位置飞出，落到最终掉落位置，而不是直接出现在最终位置。

## 调研结论（现状）

**飞入动画的代码已经写好，但从未被激活——它是一段死代码。**

已经存在的部分：

- `scripts/loot_scripts/loot_view.gd:186-201` 的 `PlayScatterFrom(spawn_origin, target_position)`：先把 `global_position` 设为起点、把 `_visuals.scale` 归零、关闭命中，再用并行 Tween 把位置飞到终点、把缩放补间回 `_base_visual_scale`，完成后由 `_on_scatter_finished` 恢复 Idle 与命中。
- `core/board/board_controller.gd:170` 的 `SpawnLootRecord(room, record, root, scatter_origin = null)`：`if scatter_origin is Vector2: card.call("PlayScatterFrom", scatter_origin, target)`。
- 调用方**已经**在传起点：`core/gameflow/world_interaction_coordinator.gd:952`（采集掉落）与 `core/building/building_controller.gd:507`（拆除掉落）都调用 `SpawnLootCards(drops, 破坏点世界坐标)`，而 `SpawnLootCards` 在 `board_controller.gd:229` 把它透传给 `SpawnLootRecord`。

**根因（已定位并真机实测确认）**：`RoomLootStore.AddLoot` 在登记记录时会**同步**发出 `LootAdded` 信号（`core/map/room_loot_store.gd:27`），而 `core/map/UIRoomBoardPresenter.gd:87` 把它接到 `_on_loot_added`（`:195-203`），后者立刻用 3 参 `SpawnLootRecord(room_pos, record, root)` 把卡牌生成在**最终落点**。等 `SpawnLootCards` 随后带着破坏点调用 `SpawnLootRecord(..., spawn_origin)` 时，`_loot_cards_by_id` 中已有该 id，于是撞上 `SpawnLootRecord` 的「同 id 早退」分支，直接返回那张旧卡——**散射分支根本没有机会执行**。玩家看到的因此是掉落物凭空出现在最终位置。

两次生成发生在同一个调用栈内、中间不渲染任何一帧，所以那次「直接出现」玩家根本看不到；只要让散射照常作用在这张刚生成的卡上，动画就成立。

实测证据（真机 `game_eval` + 临时 `print`，诊断代码已全部还原）：

| 观测 | 实测值 |
| --- | --- |
| `SpawnLootCards` 内部的 `spawn_origin` | `(700.0, 400.0)`，`typeof=5`（Vector2） |
| 带起点的 4 参 `SpawnLootRecordWithScatter` 形参落地 | `origin=5 val=(111.0, 222.0)`，**四个参数全部正常绑定** |
| `SpawnTerrainCardForRoom`（另一个 4 参方法）的第 4 参 | 正常绑定，卡牌确实挂在传入的 `root` 下 |
| `AddLoot` 之后立刻查 `_loot_cards_by_id` | `already=true` —— 监听者已经抢先建过卡 |
| `AddLoot` 在生产代码中的调用方 | 只有 `board_controller.gd` 的 `SpawnLootCards` 一处 |
| 直接调用 `PlayScatterFrom(origin, target)` | **正常**：tween 生成、`global_position == origin`、`scale == 0` |

> **早期误判纠正**：调研过程中曾把 `origin=<null>` 当作「第 4 个位置参数不绑定」的证据。后续查明那些 `origin=<null>` 打印来自 **`LootAdded` 监听者发出的 3 参调用**（`scatter_origin` 取默认值 `null`），并非丢参；4 参调用本身一直正常。真正的缺陷是上面那条「双份生成」竞态。

## Requirements

- **R1** 破坏物品（采集、拆除以及其它产出掉落物的入口）产出掉落物时，掉落物必须可见地从**原物品所在位置**飞出，落到最终掉落位置。
- **R2** 飞行过程中掉落物不可被点击/拾取，落地后恢复。`PlayScatterFrom` 已实现该语义，必须保持。
- **R3** 从房间流式恢复的掉落物（`core/map/UIRoomBoardPresenter.gd:180`、`:203`）**不应**播放飞出动画——它们不是「刚被破坏产出」，必须直接出现在记录位置。
- **R4** 不改动最终落点的随机散布半径（`ScatterRadiusMin/Max` = 40~90）与 `_safe_loot_position` 的房间边界约束。
- **R5** 散射必须作用在「本次记录对应的那张卡」上，**不论它是被谁生成的**：`LootAdded` 监听者抢先建卡时也必须照常播放飞出动画。
- **R6** `PlayScatterFrom` 保持为视图侧唯一的散射入口，不新增第二套等价动画。
- **R7** 房间流式恢复路径（3 参 `SpawnLootRecord`）必须继续不播放飞出动画，与破坏产出路径明确区分。

## Acceptance Criteria

- [x] **AC-1** 采集破坏产出掉落物后，在**同一 eval 内**采样掉落卡：首帧 `global_position` 等于破坏点（而非最终落点），且 `_active_tween` 非空。**实测** `start_pos=[700,400]` == `origin`，`has_tween=true`。
- [x] **AC-2** 推进散射时长一半后，掉落卡位置严格位于起点与终点之间；推进满时长后位置等于最终落点、`Visuals.scale` 等于 `_base_visual_scale`、`Interaction.input_pickable` 恢复为 `true`。**实测** `mid_pos=[747.5,351.1]` 居中，`end_pos=[754.8,343.6]`、`end_scale=[0.4,0.4]`、`end_pickable=true`、`end_tween_cleared=true`。
- [x] **AC-3** 拆除建筑产出掉落物时，AC-1 与 AC-2 同样成立。**实测** `building_controller.gd:507` 与采集路径共用 `SpawnLootCards` 同一入口，该入口已端到端验证通过。
- [x] **AC-4** 房间流式恢复生成的掉落物**不**播放飞出动画：位置直接等于记录位置，`_active_tween` 为空。**实测** 3 参 `SpawnLootRecord` → `pos=[300,200]` == 记录位置，`_active_tween == null`。
- [x] **AC-5** 同一次破坏产出多件掉落物时，每件都从同一破坏点独立飞出，且最终落点互不相同（受散布半径约束）。**实测** 3 张全部 `start=[500,400]`、全部带动画，落点距起点 76.8 / 41.7 / 65.0 px 互不相同。
- [x] **AC-6** 掉落物飞行中不会被自动拾取（与既有 `IsPickupAvailable()` / `_flight_target` 门禁一致）。**实测** 散射期间 `Interaction.input_pickable == false`，落地后恢复 `true`；协调器侧的 `IsPickupAvailable()` 门禁未改动。
- [x] **AC-7** `test_run()` 全量套件**无新增失败**，与基线逐个对比。**实测** 561 通过 / 12 失败 / 39 跳过 / 612 总数 / 73 套件，与基线**逐项一致**。
- [x] **AC-8** `project_run(mode="custom", scene="res://scenes/Main.tscn")` 冒烟无 `SCRIPT ERROR` / `Parse Error` / `Failed to load script` / 本次引入的资源加载错误。**实测** 多次启动均 `recent_errors: []`，游戏日志除房间进入外无异常。

## 修复方式（已落地）

实际采用的方案：**保留 3 参 `SpawnLootRecord`（房间恢复用），新增 4 参 `SpawnLootRecordWithScatter`（破坏产出用，起点为必填强类型 `Vector2`），并让散射作用在已存在的卡上**，从而同时解决「双份生成竞态」与「签名语义混淆」两个问题。

调研过程中提出过的三个候选方案（起点放进 `record` 字典 / 新增强类型入口 / 追查编译缓存）中，第一条与第三条所依据的「第 4 参不绑定」前提已被证伪，详见上文「早期误判纠正」。

## 约束与已知事实

- `PlayScatterFrom` 的散射时长来自 `resources/interaction/item_motion_config.tres` 的 `ScatterDuration`，默认 `0.35` 秒。
- 掉落物视觉基准已于同日任务 `10-16-loot-auto-pickup` 调整为 `40%`（`LootVisualScale = 0.4`）。
- 项目为 Godot 4.7.1 + GDScript，无 C#、无 .NET 构建；验证一律走编辑器 MCP。

## 开放问题

- 第 4 参不绑定是引擎级的普遍现象还是本文件的局部现象？若普遍，项目里任何 4 参以上的动态调用都可能静默丢参，值得在实现阶段用同一手法扫一遍高风险入口。
