# 技术设计：掉落物从原物品处飞出

## 1. 缺陷定位（已实测确认）

飞入动画的**全部零件都已存在**，但触发它的那一步被一次重复生成抢先了：

| 环节 | 位置 | 状态 |
| --- | --- | --- |
| 视图侧散射动画 | `scripts/loot_scripts/loot_view.gd:186-201` `PlayScatterFrom` | 正常 |
| 收尾恢复 | `loot_view.gd:284-289` `_on_scatter_finished` | 正常 |
| 棋盘侧触发 | `core/board/board_controller.gd` `SpawnLootRecord` | **被同 id 早退吞掉** |
| 采集调用方 | `core/gameflow/world_interaction_coordinator.gd:952` | 已传破坏点 |
| 拆除调用方 | `core/building/building_controller.gd:507` | 已传破坏点 |
| 仓库信号 | `core/map/room_loot_store.gd:27` `LootAdded.emit` | **竞态起点** |
| 信号监听者 | `core/map/UIRoomBoardPresenter.gd:87` → `:195-203` | **抢先把卡建在最终落点** |

**时序（同一调用栈，中间不渲染任何一帧）**：

1. `SpawnLootCards` 调 `_loot_store.AddLoot(...)`。
2. `AddLoot` 登记记录后**同步**发出 `LootAdded`。
3. `UIRoomBoardPresenter._on_loot_added` 收到信号，用 3 参 `SpawnLootRecord(room_pos, record, root)` 把卡建在**最终落点**，并写入 `_loot_cards_by_id`。
4. `SpawnLootCards` 继续执行，带着破坏点调用 `SpawnLootRecord(..., spawn_origin)`。
5. `SpawnLootRecord` 命中 `if _loot_cards_by_id.has(id): return _loot_cards_by_id[id]` → **早退，散射分支永不执行**。

玩家因此只看到掉落物凭空出现在最终位置。

关键事实：`AddLoot` 在**生产代码中只有一个调用方**（`SpawnLootCards`），而 `SpawnLootCards` 自己就会生成卡牌，所以监听者的那次生成是**纯重复**，且它恰好抢走了带起点的第二次调用。

## 2. 被证伪的假设（存档，避免后人重走）

调研中期曾判定为「`SpawnLootRecord` 的第 4 个可选形参 `scatter_origin` 收不到实参，恒为 `null`」，并据此设计了「把起点放进 `record` 字典」「追查编译缓存」等方案。**该判定是错的**，实测证据如下：

| 观测 | 实测值 |
| --- | --- |
| 4 参 `SpawnLootRecordWithScatter` 的四个形参 | `room=6 record=27 root=24 origin=5 val=(111.0, 222.0)`，**全部正常绑定** |
| 另一个 4 参方法 `SpawnTerrainCardForRoom` 的第 4 参 | 正常绑定，卡牌确实挂在传入的 `root` 下 |
| `AddLoot` 之后立刻查 `_loot_cards_by_id` | `already=true` —— 监听者已抢先建卡 |

那些 `origin=<null>` 的打印来自 **`LootAdded` 监听者发出的 3 参调用**（第 4 参取默认值 `null`），与「丢参」无关。教训：`print` 型诊断若不能区分**调用来源**，会把「另一条调用路径」误读成「参数丢失」。

## 3. 修复设计

### 3.1 拆分签名，消除语义混淆

- `SpawnLootRecord(room, record, root) -> Node2D`：3 参，**不播飞出动画**，语义为「直接显示在记录位置」，供房间流式恢复使用（`UIRoomBoardPresenter.gd:180`、`:203`）。
- `SpawnLootRecordWithScatter(room, record, root, scatter_origin: Vector2) -> Node2D`：4 参，起点为**必填强类型 `Vector2`**，供破坏产出使用。

原签名把两种语义挤在一个「可选起点」参数里，正是读取方难以判断该走哪条路径的原因。

### 3.2 散射必须作用在已存在的卡上（本次修复的核心）

`SpawnLootRecordWithScatter` **不再**因为「卡已存在」而跳过散射：

```gdscript
var card: Node2D = SpawnLootRecord(room, record, root)
if card == null:
    return null
if card.has_method("PlayScatterFrom"):
    card.call("PlayScatterFrom", scatter_origin, card.global_position)
return card
```

理由：监听者的抢先建卡与本方法处在同一调用栈内、中间不渲染帧，所以那张卡对玩家而言仍是「刚出现」的；`card.global_position` 就是记录换算后的最终落点，直接作为散射终点，无需重做 `to_global`。

保留 `has_method("PlayScatterFrom")` 守卫：项目里存在遗留 `BoardCardView` 视图，动态调用必须先确认目标实现了该方法（`quality-guidelines.md`）。

### 3.3 未采用的替代方案

- **让监听者不再建卡**：能消除重复生成，但会改动 `UIRoomBoardPresenter` 的既有职责，且若将来有别的 `AddLoot` 调用方依赖视图自动生成就会静默失效。
- **把起点放进 `record` 字典**：前提（第 4 参不绑定）已被证伪，无必要把动画关注点混进数据记录。

## 4. 调用方改动

| 文件 | 现状 | 改为 |
| --- | --- | --- |
| `board_controller.gd`（`SpawnLootCards` 内） | `SpawnLootRecord(room, record, root, spawn_origin)` | `SpawnLootRecordWithScatter(room, record, root, spawn_origin)` |
| `core/map/UIRoomBoardPresenter.gd:180` / `:203` | `SpawnLootRecord(room_pos, record, root)` | **不改**——房间恢复不播飞出动画 |
| `board_controller.gd` `_spawn_single_loot_with_scatter` | 已直接调 `PlayScatterFrom` | **不改** |

## 5. 保持不变的部分

- `PlayScatterFrom` 的动画语义与时长（`ScatterDuration`，默认 `0.35` 秒）。
- 落点随机半径 `ScatterRadiusMin/Max` = 40~90 与 `_safe_loot_position` 的房间边界约束。
- 掉落物视觉基准 `LootVisualScale = 0.4`（同日任务已调整）。
- 飞行中不可拾取的语义（`input_pickable = false` → `_on_scatter_finished` 恢复）。
- `UIRoomBoardPresenter` 的重复建卡行为：本次未改动它，靠散射作用于已存在卡来兜住。

## 6. 顺带排查结论

按用户要求排查「其它多参动态调用是否被静默丢参」：**未发现任何丢参缺陷**。

- `SpawnTerrainCardForRoom(room, terrain_instance, local_position, root)`：4 参，第 4 参绑定正常。
- `SpawnLootRecordWithScatter(room, record, root, scatter_origin)`：4 参，全参绑定正常（形参落地打印已验证）。
- `SpawnLootCards(stacks: Array, spawn_origin: Vector2)`：2 参，第 2 参绑定正常。

即项目里不存在「4 参以上动态调用会丢参」的普遍问题。真正的坑是**同一逻辑被两条路径重复执行**（信号监听者 + 显式产出方），这类缺陷不会被参数检查发现，只能靠区分调用来源的日志/索引观测捕捉。

## 7. 回滚

改动集中在 `core/board/board_controller.gd` 一个文件：删除 `SpawnLootRecordWithScatter` 并把 `SpawnLootCards` 的调用改回 `SpawnLootRecord(room, record, root)` 即可。无数据迁移、无场景节点增删、无存档格式变化。
