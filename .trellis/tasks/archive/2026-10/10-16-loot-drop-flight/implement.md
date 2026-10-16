# 实施计划：掉落物从原物品处飞出

## 前置检查

- [ ] 1.1 `editor_state` 确认 Godot 4.7.1 编辑器已打开并加载 CUSGA
- [ ] 1.2 `git status` 确认本任务开工前没有未提交的无关改动（本任务与 `10-16-loot-auto-pickup` 的改动可能同时存在，需能区分）
- [ ] 1.3 已读 `.trellis/spec/backend/gameplay-system-patterns.md`、`testing-guidelines.md` 与 `.trellis/spec/frontend/component-guidelines.md`

## Step 2：改 `core/board/board_controller.gd`

- [ ] 2.1 删除 `SpawnLootRecord` 那个**从未生效**的第 4 个可选参数，签名回到 `func SpawnLootRecord(room: Vector2i, record: Dictionary, root: Node2D) -> Node2D:`
- [ ] 2.2 同步删除函数体内已成死代码的 `if scatter_origin is Vector2:` 分支
- [ ] 2.3 更新 `SpawnLootRecord` 的 `##` 文档注释：说明它的语义是「直接出现在记录位置」，供房间流式恢复使用；并在注释里留一句「需要飞出动画请用 `SpawnLootRecordWithScatter`」，避免后来者再往签名上加可选参数
- [ ] 2.4 新增 `SpawnLootRecordWithScatter(room: Vector2i, record: Dictionary, root: Node2D, scatter_origin: Vector2) -> Node2D`：起点必填、强类型、无默认值
- [ ] 2.5 新方法内部**只在真正新建了卡时**播放散射：先查 `_loot_cards_by_id`，命中则直接返回旧卡且不重播动画（`SpawnLootRecord` 有同 id 早退分支，重复播放会把已在场的掉落物再飞一遍）
- [ ] 2.6 播放散射用 `card.call("PlayScatterFrom", scatter_origin, card.global_position)`，并保留 `card.has_method("PlayScatterFrom")` 守卫（项目里存在遗留 `BoardCardView` 视图）
- [ ] 2.7 全部新增/修改的公共函数写中文 `##` 文档注释，说明参数、返回值与「为什么要有这个专用入口」

## Step 3：改调用方

- [ ] 3.1 `board_controller.gd` 的 `SpawnLootCards` 内：`SpawnLootRecord(room, record, root, spawn_origin)` → `SpawnLootRecordWithScatter(room, record, root, spawn_origin)`
- [ ] 3.2 确认 `core/map/UIRoomBoardPresenter.gd:180` 与 `:203` **保持 3 参 `SpawnLootRecord`**（房间恢复不播飞出动画）
- [ ] 3.3 确认 `_spawn_single_loot_with_scatter` 的兜底路径未被破坏

## Step 4：真机验证参数绑定（关键闸门，先于动画验证）

- [ ] 4.1 `filesystem_manage(op="scan")` 刷新改动脚本
- [ ] 4.2 在 `SpawnLootRecordWithScatter` 内临时加一行 `print` 打印 `scatter_origin` 的 `typeof` 与 `is Vector2`
- [ ] 4.3 `project_run(mode="custom", scene="res://scenes/Main.tscn")` 后 `game_eval` 调用该方法
- [ ] 4.4 `logs_read(source="game")` 确认被调方**确实收到 `Vector2`**（`typeof=5`）而非 NIL
- [ ] 4.5 **若第 4 位仍丢参**：按 `design.md` §3.3 回退（先试 `record["scatter_origin"]`，再试移到第 2 位），并在任务记录里写明实际生效的方案
- [ ] 4.6 验证通过后**删除临时 `print`**，重新 `scan`

## Step 5：真机验证动画行为

- [ ] 5.1 **AC-1** 同一 eval 内采样：新生成的掉落卡首帧 `global_position` 等于破坏点，且 `_active_tween` 非空
- [ ] 5.2 **AC-2** `_active_tween.custom_step(时长/2)` 后位置严格位于起点与终点之间；再推进到满时长后位置等于最终落点、`Visuals.scale == _base_visual_scale`、`Interaction.input_pickable == true`
- [ ] 5.3 **AC-3** 走 `building_controller` 的拆除掉落入口复验一次（可直接调 `SpawnLootCards` 模拟同一透传路径）
- [ ] 5.4 **AC-4** 调 3 参 `SpawnLootRecord`（房间恢复路径）确认位置直接等于记录位置且 `_active_tween` 为空
- [ ] 5.5 **AC-5** 一次传入多件堆叠，确认每件都从同一破坏点飞出且最终落点互不相同
- [ ] 5.6 **AC-6** 飞行中调 `world_interaction_coordinator._should_auto_pickup(card)` 确认为 `false`
- [ ] 5.7 `project_manage(op="stop")` 停止游戏（**不得**关闭编辑器）

## Step 6：顺带排查其它多参动态调用

- [ ] 6.1 用 `rg` 列出所有 `.call(` 且实参 ≥ 4 的位置
- [ ] 6.2 对高风险候选（尤其是「第 4 位」形状）用临时 `print` 抽查是否被静默丢参
- [ ] 6.3 把结论写进本文件的「排查结论」小节：**只记录证据与建议，不在本任务内顺手修改**
- [ ] 6.4 排查用的临时 `print` 全部删除，`scan` 后确认 `git diff` 无诊断残留

## Step 7：测试与契约同步

- [ ] 7.1 检查 `tests/godot/test_board_controller_contract.gd` 是否需要纳入新方法名（当前它锁 `SpawnLootCard` 与 `SpawnLootCards`，未锁 `SpawnLootRecord`）
- [ ] 7.2 若新增了锁定字面量，必须同时确保 `test_run` 该套件通过
- [ ] 7.3 `test_run(suite="board_controller_contract")` 与基线对比（该套件有 1 项既有失败）
- [ ] 7.4 `test_run()` 全量，与基线 **561 通过 / 12 失败 / 39 跳过** 逐项对比，确认**无新增失败**

## Step 8：文档同步

- [ ] 8.1 `docs/游戏机制与玩法内容.md` 的掉落段落：写明「破坏产出时掉落物从原物品位置飞出到最终落点；房间流式恢复不播此动画」
- [ ] 8.2 `docs/建筑系统.md` 若有拆除掉落的描述，确认与实现一致
- [ ] 8.3 若排查出引擎级参数绑定结论，回写 `.trellis/spec/backend/gameplay-system-patterns.md` 或 `testing-guidelines.md`

## Step 9：收尾

- [ ] 9.1 `git status` 复核：只保留本任务需要的改动，未被 Godot 编辑器改写无关文件
- [ ] 9.2 记录最终验证数据（供 `check.jsonl` 与后续会话使用）

## 排查结论

按用户要求排查「其它多参动态调用是否被静默丢参」：**未发现任何丢参缺陷**。

| 方法 | 参数个数 | 第 N 参实测 |
| --- | --- | --- |
| `SpawnTerrainCardForRoom(room, terrain_instance, local_position, root)` | 4 | 第 4 参绑定正常（卡牌挂在传入 `root` 下） |
| `SpawnLootRecordWithScatter(room, record, root, scatter_origin)` | 4 | 四参全部正常（`origin=5 val=(111.0, 222.0)`） |
| `SpawnLootCards(stacks, spawn_origin)` | 2 | 第 2 参绑定正常（`(700,400)`） |

调研中期曾误判为「第 4 个可选位置参数收不到实参」，后查明那些 `origin=<null>` 打印来自 **`LootAdded` 监听者发出的 3 参调用**，并非丢参。结论与纠正过程已写入 `design.md` §2。

**真正的坑**：同一逻辑被两条路径重复执行（`LootAdded` 监听者 + 显式产出方）。这类缺陷无法靠参数检查发现，只能靠能区分**调用来源**的观测捕捉——本次是靠 `_loot_cards_by_id` 的 `already=true` 定位的。

**建议（未在本任务内修改）**：`UIRoomBoardPresenter._on_loot_added` 的建卡与 `SpawnLootCards` 的建卡互为重复，`AddLoot` 在生产代码中只有 `SpawnLootCards` 一个调用方。是否把生成职责收敛到产出方一处，留给用户决定。

## 实施结果

**改动文件：`core/board/board_controller.gd`（唯一生产代码改动）**

1. `SpawnLootRecord` 回到 3 参签名，删除那个从未参与语义的「可选散射起点」参数与死分支，文档注释明确其语义为「直接显示在记录位置」，并留注「不要在签名末尾再加可选散射起点」。
2. 新增 `SpawnLootRecordWithScatter(room, record, root, scatter_origin: Vector2)`：起点必填强类型，先建卡再照常播放散射——**即使卡已由 `LootAdded` 监听者抢先建出也照播**，这是本次修复的核心。
3. `SpawnLootCards` 内的调用改为 `SpawnLootRecordWithScatter`。
4. `UIRoomBoardPresenter.gd:180/:203` 保持 3 参调用不动，房间恢复不播飞出动画。

**真机验证数据（`game_eval`，run_token 16，走真实入口 `SpawnLootCards`）**

| 观测 | 实测 |
| --- | --- |
| 新建卡数 | 1（无重复生成） |
| 首帧位置 / 破坏点 | `[700,400]` / `[700,400]`，相等 |
| `_active_tween` | 非空 |
| 首帧缩放 / 命中 | `≈[0,0]` / `input_pickable=false` |
| 中点位置 | `[747.5,351.1]`，位于起终点之间 |
| 终点位置 | `[754.8,343.6]`（距起点 79.4px，落在 40~90 半径内） |
| 终点缩放 / 命中 / tween 清理 | `[0.4,0.4]` / `true` / 已清空 |
| AC-4 恢复路径 | `pos=[300,200]` == 记录位置，`_active_tween == null` |
| AC-5 三件掉落 | 3 张全部 `start=[500,400]`、全部带动画，落点距起点 76.8 / 41.7 / 65.0 px 互不相同 |

**回归**

- `test_run(suite="board_controller_contract")`：5 通过 / 1 失败 / 1 跳过；失败项 `test_shared_log_and_error_texts`（`BoardController.CardViewScene 未设置`）为既有失败。
- `test_run()` 全量：**561 通过 / 12 失败 / 39 跳过 / 612 总数 / 73 套件**，与基线逐项一致，**无新增失败**。
- `project_run(mode="custom", scene="res://scenes/Main.tscn")` 多次启动均 `recent_errors: []`，游戏日志除房间进入外无异常。

**诊断代码清理**：所有临时 `print` 已删除；`core/board/board_controller.gd` 除上述功能性改动外无残留。
