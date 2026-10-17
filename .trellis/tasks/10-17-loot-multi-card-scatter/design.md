# 设计：掉落物多张卡牌化与随机落点

对应 PRD：`.trellis/tasks/10-17-loot-multi-card-scatter/prd.md`

## 1. 边界与不变量

改动集中在**世界卡牌生成层**（`BoardController`），不改掉落数值层（`LootTableData`）。

保持不变的对外契约：

| 契约 | 位置 | 本轮处理 |
|---|---|---|
| `RollLoot(yield_growth) -> Array[RefCounted]` 产出形状 | `resources/loot/loot_table.gd` | 完全不改 |
| `SpawnLootCards(stacks: Array, spawn_origin: Vector2) -> void` | `board_controller.gd` | 签名不变，内部改为逐单位生成 |
| `SpawnLootCard(stack, global_position) -> Node2D` | 同上 | 不变 |
| `SpawnLootRecord(room, record, root)` / `SpawnLootRecordWithScatter(...)` | 同上 | 不变 |
| `RoomLootStore` 记录结构 `{id, stack, position}` | `room_loot_store.gd` | 结构不变，语义细化为「一条记录 = 一件」 |
| 掉落卡视图 `InitializeLoot` / `Amount` 标签节点 | `loot_view.gd`、`Loot.tscn` | 节点与逻辑保留，仅加注释 |

新增的不变量（本任务建立）：

> **世界掉落卡恒为单件**：`AddLoot()` 与 `SpawnLootCard()` 收到的掉落堆叠 `Amount == 1`（旧快照恢复路径除外，见 §6）。

## 2. 关键技术决策

### D1 拆分放在 `BoardController`，不放在 `LootTableData.RollLoot`

理由：

1. **唯一咽喉**：采集破坏（`world_interaction_coordinator`）、建筑拆除（`building_controller`）、怪物掉落（`loot_component` → `on_entity_dropped`）、房间流式恢复（`UIRoomBoardPresenter`）最终都汇到 `SpawnLootCards` / `SpawnLootRecord`。在源头分散改要动 4 条链路，在棋盘改只动 1 处。
2. **不动玩法数值契约**：`RollLoot()` 目前对普通物品返回单个 `Amount == N` 堆叠，`tests/godot/test_reusable_gathering_interaction.gd:987` 断言「2 件基础 + 3 额外 = 数量 5」。在棋盘拆分，该测试与掉落表语义全部无需改动；在源头拆则会连带改掉落表文档注释、装备/普通物两条分支与多处断言。
3. **向前兼容新掉落源**：任何未来新增的掉落产出方（含遗留 C#、测试桩）只要走棋盘入口，就自动获得「一张卡一件」。
4. **装备不被二次拆分**：`RollLoot()` 已逐件生成装备，单位化逻辑对 `Amount == 1` 直接放行，天然幂等。

被否决的替代方案：

- **在 `RollLoot()` 拆分**：会把表现层需求下沉成数据层契约，掉落表不再是「经济产出」而是「卡牌产出」；且与「保留原有单堆掉落形状」的既有注释直接冲突。
- **在掉落卡视图层拆分**：视图拿不到原点与相邻卡牌位置，无法做间距控制，也无法登记仓库记录。

### D2 单位化堆叠的构造

`_expand_loot_units(stacks) -> Array[RefCounted]`：

- 逐项跳过不满足 `_is_readable_item_stack()` 的条目（沿用现有校验）。
- `Amount == 1` → 原引用直接加入结果（不创建对象，装备路径零开销）。
- `Amount > 1` → 循环 N 次，每次 `unit = stack.Duplicate()` 后 `unit.Amount = 1`：
  - `item_stack.gd::Duplicate()` 保留 `RolledAttributes` 并置 `_stats_initialized = true`，因此**不会**在后续 `RollRandomStats()` 时重随机，符合「掉落已生成实例属性」的既有约束（`entities/player.gd` 同款注释）。
  - 回退：若堆叠对象无 `Duplicate()`（理论上仅遗留 C# 类型），改用 `item_stack.gd` 新建 `SetItem(item, 1)` 并深拷贝源 `RolledAttributes`，不调用 `RollRandomStats()`。
- **绝不修改入参堆叠**：调用方（如 `building_service`）可能仍持有 `drops` 数组；就地改 `Amount` 会让上层看到被掏空的掉落。

### D3 落点分配：随机 + 最小间距重试 + 半径自适应

`_plan_loot_positions(origin, count, bounds) -> Array[Vector2]`：

```
d       = LootMinSeparation（默认 56.0）
Rmin    = ScatterRadiusMin（场景 40）
Rmax    = max(ScatterRadiusMax, sqrt(Rmin^2 + count * 0.866 * d^2 / PI))
```

**半径自适应依据**：环带面积 `π(Rmax² − Rmin²)` 需容纳 `count` 个直径 `d` 的互不重叠圆盘；六边形最密排布下每个圆心占 `0.866·d²`（常量 `CIRCLE_PACKING_AREA_FACTOR`）。解出 `Rmax` 即可保证够放。代入 d=56：count=5 → 77、count=6 → 82、count=8 → 92、count=20 → 137，即 8 张以上才会突破原 90 上限；1~7 张（覆盖常见掉落量级）的落点范围与原实现完全一致。

**单点选取**（每点最多 `SCATTER_PLACEMENT_ATTEMPTS = 16` 次）：

1. `candidate = origin + 随机单位方向 * randf_range(Rmin, Rmax)`（纯随机角度，符合已确认的「随机 + 最小间距重试」，不做角度均分）。
2. 有边界时先 `clamp` 到边界（房间局部沿用现有 `x∈[90,1190]、y∈[90,630]`，提为常量 `LOOT_AREA_MIN/MAX` 消除魔法数字）。
3. 与已接受的所有落点比较，`distance < d` 则重试。
4. 16 次全失败 → 直接采用当前候选，不打印、不中断（注释说明这是有意的降级：原点贴近房间角落时环带互相重叠，硬性间距不可满足，保底保证函数必返回 `count` 个点）。

**为什么先夹取再判间距**：`_safe_loot_position()` 原本先随机再夹取，夹取会把贴边候选压到同一边界线；先夹后判才能让「夹完仍然太近」的情况进入重试。

### D4 两条生成分支统一

`SpawnLootCards` 新流程：

```
units = _expand_loot_units(stacks)
if _loot_store != null and _map_view != null and root != null:
    local_origin = root.to_local(spawn_origin)
    positions    = _plan_loot_positions(local_origin, units.size(), LOOT_AREA_BOUNDS)
    for i, unit in units:
        record = AddLoot(room, unit, positions[i])
        if not record.is_empty(): SpawnLootRecordWithScatter(room, record, root, spawn_origin)
    return
positions = _plan_loot_positions(spawn_origin, units.size(), 无边界)
for i, unit in units:
    card = SpawnLootCard(unit, positions[i])
    if card != null: card.PlayScatterFrom(spawn_origin, positions[i])
```

要点：

- 仓库分支的散射起点仍是**同一个** `spawn_origin`，因此 N 张卡看起来是「从被破坏物一起炸开」，符合视觉预期；落点各自独立。
- `_spawn_single_loot_with_scatter()` 被上面第二分支取代，**删除**该函数（它一次只处理一个堆叠，与新流程重复）。删除前确认无其它引用（当前只有 `SpawnLootCards` 调用）。
- `AddLoot` 会同步 `emit LootAdded`，`UIRoomBoardPresenter` 可能在同一调用栈内抢先生成卡；`SpawnLootRecord` 按 `id` 去重返回既有卡并照常播放散射，N 张时该路径依然成立（每张有独立 id）。

### D5 数量标签「暂时不使用」

按已确认决策：**不改节点、不删分支**，只在三处补中文注释说明现状与保留原因。

| 文件 | 位置 | 处理 |
|---|---|---|
| `scripts/loot_scripts/loot_view.gd` | `RefreshView()` 的 `amount > 1` 分支 | 加注释：掉落链路保证单件，本分支暂时不生效，保留作旧快照/绕过拆分入口的兜底 |
| `core/board/board_card_view.gd` | 同上 | 同上 |
| `core/board/board_card_state.gd` | `CanShowAmount()` | 同上 |

这样 `test_board_card_view_contract.gd:64`（标签显示 "3"）与 `test_reusable_gathering_interaction.gd:1063`（`CanShowAmount()` 为 true）继续通过。

### D6 存档与房间恢复

- 拆分发生在 `AddLoot` **之前**，所以新产生的记录天然一条一件；`SnapshotEncoded()` 的 `amount` 字段恒为 1，无需改编码格式。
- `RestoreEncoded()` 与 `SpawnLootRecord()` **不拆分**旧记录：恢复时位置是权威数据，按记录原样建卡；旧局里 `amount > 1` 的记录会恢复成一张带数字的卡，正是 §D5 保留标签的原因。
- 快照条数会从 1 条变成 N 条。N 为常见量级（1~5），可接受；`RemoveLoot()` 是线性查找，N 增长带来的成本可忽略。

## 3. 数据流

```
LootTableData.RollLoot()          ← 不改：普通物品仍是 1 个 Amount=N 堆叠
        │
        ▼
BoardController.SpawnLootCards()
        ├─ _expand_loot_units()    ← 新增：N 件 → N 个 Amount=1 堆叠
        ├─ _plan_loot_positions()  ← 新增：N 个带最小间距的随机落点
        │
        ├─ 仓库分支 ── RoomLootStore.AddLoot(room, unit, pos)  (×N 条记录)
        │                  └─ LootAdded → UIRoomBoardPresenter 抢先生成（按 id 去重）
        │              BoardController.SpawnLootRecordWithScatter(×N 张卡 + 散射)
        │
        └─ 遗留分支 ── SpawnLootCard(unit, pos) + PlayScatterFrom(spawn_origin, pos)
                                (×N 张卡)
```

## 4. 新增配置项

| 属性 | 默认 | 说明 |
|---|---|---|
| `@export var LootMinSeparation: float = 56.0` | 56.0 | 卡牌落点最小圆心距。取自掉落卡实际可视尺寸：`Loot.tscn` 的 `PlayerView` 为 100×140，按 `LootVisualScale`(0.4) 缩放后约 40×56，取较长边保证两张卡不叠成一张。新增导出不影响已有 `.tscn` 反序列化（缺字段取默认）。 |
| `const SCATTER_PLACEMENT_ATTEMPTS` | 16 | 每点重试上限，脚本常量，不做导出。 |
| `const LOOT_AREA_MIN / LOOT_AREA_MAX` | (90,90) / (1190,630) | 提自现有 `_safe_loot_position()` 的魔法数字。 |

## 5. 风险与对策

| 风险 | 对策 |
|---|---|
| 遗留 C# 堆叠无 `Duplicate()` | `_expand_loot_units()` 内含新建堆叠回退分支 |
| 原点贴房间角落导致间距无法满足 | 16 次重试后接受候选并注释说明；不抛错、不阻塞生成 |
| 记录条数与快照体积随 N 增长 | 记录结构不变，N 为小量级；文档记录该取舍 |
| `_spawn_single_loot_with_scatter` 被删除后仍有动态调用 | 删除前 `rg` 全量确认；该函数为私有（前缀 `_`），无跨语言调用方 |
| 拆分后被拾取的堆叠与库存合并语义变化 | 单位堆叠仍是标准 `ItemStack`，`TryAddItemToInventory(stack)` 逐张入包，与逐件掉落的装备路径一致 |

## 6. 回滚形状

改动文件：`core/board/board_controller.gd`（主）、`scripts/loot_scripts/loot_view.gd`、`core/board/board_card_view.gd`、`core/board/board_card_state.gd`（均为注释）、`tests/godot/`（新增测试）。

回滚点：`git checkout -- core/board/board_controller.gd` 并删除新增测试文件即可完全恢复；注释类改动与新增 `@export` 不影响运行时行为，可单独保留。

## 7. 验证策略

1. `filesystem_manage(op="scan")` 刷新脚本。
2. `test_run(suite=...)` 跑新增契约测试 + 既有掉落相关测试（board_controller / board_card_view / reusable_gathering / item_room / building_system / equipment_configuration）。
3. `project_run(mode="custom", scene="res://scenes/Main.tscn")` 冒烟：破坏产出多件的资源，`logs_read(source="game")` 确认无 `SCRIPT ERROR`，`game_eval` 统计 `RoomLootStore` 记录数与各卡 `Amount`。
4. 落点核验：`game_eval` 读取每张掉落卡的 `global_position` 并计算最小两两距离，断言 ≥ `LootMinSeparation`。**不要依赖 `editor_screenshot`**：当前模型不声明图像输入，截图无法被阅读，几何数据才是可复核证据。
5. `project_manage(op="stop")` 收尾；`git status` 复核只保留本任务改动。

### 7.1 核验陷阱：SceneTree 被暂停时 Tween 不推进

首次几何核验时 3 张卡牌的 `global_position` 全部等于掉落原点，看似「随机落点没生效」。实际原因是 `debug_status` 报告 `tree_paused: true`（`settlement_manager.gd` 的结算流程会暂停整棵树），暂停状态下 `PlayScatterFrom()` 的 Tween 一帧都不推进，卡牌自然停在起点。

排查顺序：先 `game_manage(op="debug_status")` 看 `tree_paused`，必要时 `game_eval` 里 `tree.paused = false` 再复测。解暂停后同一批卡牌落点为 `(970,617) / (1115,630) / (1084,536)`，最小间距 99.18，与 `RoomLootStore` 记录里的规划位置逐位一致。**记录位置是权威数据，卡牌坐标只在 Tween 结束后才等于它。**
