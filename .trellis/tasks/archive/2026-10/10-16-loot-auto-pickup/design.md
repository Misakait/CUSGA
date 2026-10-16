# 掉落物自动拾取与缩小 —— 技术设计

## 1. 边界与职责归属

| 关注点 | 归属 | 文件 | 理由 |
| --- | --- | --- | --- |
| 掉落物视觉尺寸 | 掉落视图 | `scripts/loot_scripts/loot_view.gd` | `_base_visual_scale` 已是唯一视觉基准，所有动画轨道由它派生 |
| 掉落物命中区域尺寸 | 场景资源 | `scenes/Loot/Loot.tscn` | `Interaction` 与 `Visuals` 是兄弟节点，脚本缩放管不到碰撞形状 |
| 「掉落物是否还能被拾取」 | 掉落视图 | `scripts/loot_scripts/loot_view.gd` | 飞行状态与禁用状态都是视图私有状态，只有视图知道 |
| 拾取触发条件与结算 | 协调器 | `core/gameflow/world_interaction_coordinator.gd` | 结算链（入包、记账、删仓库记录、删卡）已全部集中在此 |
| 入包成败判定 | 玩家 / 库存组件 | `entities/player.gd` / `entities/components/inventory_component.gd` | 已有只读预检查 `CanAddItemStack`，**不改** |
| 渲染与物理 | Godot | —— | 无需新系统 |

**不做的事**：不新增 autoload、不新增碰撞层、不改 `RoomLootStore`、不改 `BoardController` 的卡牌生命周期、不改地形卡视图。

## 2. 契约（对外可见的接口变化）

### 2.1 新增：掉落视图导出

```gdscript
## 掉落物视觉基准倍率；同时决定待机、悬停、散射与飞入的起始大小。
## 命中区域不随本值变化，需要在 Loot.tscn 里单独调整碰撞形状。
@export_range(0.05, 2.0, 0.01) var LootVisualScale: float = 0.4
```

- 命名对齐既有先例 `scripts/item_scripts/item_view.gd:15` 的 `TerrainVisualScale`。
- 范围下界取 `0.05` 而不是 `item_view.gd` 的 `0.25`，因为需求值 `0.4` 必须落在范围内；上界取 `2.0` 保留放大的调试余地。
- **不放进** `resources/interaction/item_motion_config.gd`：该资源被 `Item.tscn`（地形）与 `Loot.tscn`（掉落）共享，加字段会串改地形表现。

### 2.2 新增：掉落视图可拾取协议

```gdscript
## 判断该掉落物当前是否还能被拾取。
## @return 有堆叠、未被禁用且不在飞入过程中时为 true。
func IsPickupAvailable() -> bool:
	return _loot_stack != null and not _interaction_disabled and _flight_target == null
```

- 解决的具体问题：`BoardController.DetachForFlight`（`board_controller.gd:297`）只 `reparent`、**不从 `_active_cards` 移除**，因此飞入中的掉落卡仍在 `GetActiveCardsSnapshot()` 里。没有这道判据就会二次拾取（重复入包、重复记账）。
- `_flight_target` 在 `PlayFlyTo` 里赋值、在 `_finish_flight` 里清空（`loot_view.gd:194`/`:275`），是准确的「飞行中」标志。
- 协调器用 `has_method` 兼容缺失该协议的视图（遗留 `board_card_view.gd`、测试假视图），缺失时视为「可拾取」，不改变既有行为。

### 2.3 新增：协调器导出

```gdscript
@export_group("Auto Pickup")
## 掉落物自动拾取半径（世界像素），取值范围 1～1000。
## 与 InteractionRange 分离：地形交互距离和掉落拾取手感需要能各自单独调。
## 默认 60 的语义是「必须贴到掉落物附近才拾取」。
@export_range(1.0, 1000.0, 1.0) var AutoPickupRange: float = 60.0
```

### 2.4 新增：协调器内部助手

```gdscript
## 判断卡牌是否为掉落卡。
func _is_loot_card(card: Node2D) -> bool

## 判断掉落卡当前是否应该被自动拾取（纯判定，不产生副作用）。
func _should_auto_pickup(card: Node2D) -> bool

## 判断掉落卡是否落在自动拾取半径内。
func _is_loot_within_auto_pickup_range(card: Node2D) -> bool

## 每帧扫描棋盘快照并拾取所有满足条件的掉落卡。
func _process_auto_pickup() -> void

## 把地形长按取消逻辑从 _process 抽出，保持单一职责。
func _process_terrain_hold_input() -> void
```

### 2.5 改名：拾取入口

`_handle_loot_card_clicked(card, stack)` → `_handle_loot_card_pickup(card, stack)`（函数体语义不变，仅改名与改注释）。

> **改名不是装饰**：该函数不再由「点击」触发，名字里的 `clicked` 会误导后续读者；同时 `test_world_interaction_coordinator_contract.gd` 没有断言这个名字，改名是安全的。

## 3. 数据流

### 3.1 自动拾取（新路径）

```
每帧 _process
  └─ _process_auto_pickup()
       ├─ 门禁：_is_run_ending() 或 not CanUseWorld() → 直接返回
       │        （CanUseWorld 已覆盖：暂停 / _is_transitioning / 棋盘不可见）
       ├─ _board_controller.call("GetActiveCardsSnapshot")  → Array[Node2D]
       └─ 逐张卡：
            ├─ _should_auto_pickup(card)
            │    ├─ card 有效？
            │    ├─ GetLootStackOrNull() 非空？        → 掉落卡判定
            │    ├─ IsPickupAvailable() 为真？（缺失协议则放行）
            │    └─ _is_loot_within_auto_pickup_range(card)
            │         └─ _player_char.global_position.distance_to(card.global_position) <= AutoPickupRange
            └─ 命中 → _handle_loot_card_pickup(card, stack)
                 ├─ _gameplay_port.call("TryAddItemToInventory", stack)
                 │    └─ player.TryAddItemToInventory
                 │         ├─ CanAddItemStack   ← 只读预检查，背包满时 false
                 │         └─ AddItemStack      ← 仅预检查通过才写槽位
                 ├─ 失败 → return（不记账、不删记录、不动画、不删卡）★背包满分支
                 ├─ SettlementManager.record_resource   ← 记账
                 ├─ _loot_store.call("RemoveLoot", room, loot_id)  ← 删仓库记录
                 ├─ card.DisableForPickup()             ← 关闭命中
                 ├─ _board_controller.call("DetachForFlight", card) ← 脱离房间
                 └─ card.PlayFlyTo(_player_char, _on_loot_fly_finished.bind(card))
                      └─ loot_view 每帧追踪玩家 + _visuals.scale → Vector2.ZERO
                           └─ 结束 → _on_loot_fly_finished → _board_controller.call("RemoveCard", card)
```

**关键性质**：背包满时整个链路在第一步就返回，**没有任何**副作用。下一帧仍会重试，因此玩家一腾出空间就立即拾取（AC-10），不需要冷却或状态机。

### 3.2 鼠标路径（取消拾取）

```
_on_board_card_clicked(card)
  ├─ _is_run_ending() → 返回
  ├─ _is_loot_card(card) → 返回            ★新增：掉落物点击被吞掉，不做距离提示
  ├─ range_check = _try_get_interaction_range(card)   ← 锁定字面量，仍恰好出现在 2 处
  └─ 地形分支（不变）

_on_board_card_pressed(card)
  ├─ _is_run_ending() → 返回
  ├─ _hold_interaction_controller 门禁 → 返回
  ├─ _is_loot_card(card) → 返回            ★新增：掉落物按下不再弹「距离不够！」
  ├─ range_check = _try_get_interaction_range(card)   ← 锁定字面量
  └─ 可长按地形分支（不变）
```

`_is_loot_card` 放在距离判定**之前**，因此掉落物的点击/按下既不拾取、也不产生「距离不够！」飘字与调试日志（AC-6 / AC-7），而地形卡的两道门禁逐字不变。

### 3.3 缩放的数据流

```
loot_view.gd  LootVisualScale = 0.4
   └─ InitializeLoot: _base_visual_scale = Vector2.ONE * LootVisualScale
        ├─ RefreshView:               _visuals.scale = _base_visual_scale
        ├─ _configure_motion:         Idle/Hover 关键帧 = _base_visual_scale × 各自倍率
        ├─ PlayScatterFrom:           Vector2.ZERO → _base_visual_scale
        └─ PlayFlyTo / _process:      _base_visual_scale → Vector2.ZERO
```

因为四条表现路径全部以 `_base_visual_scale` 为起点或终点，**只改 `InitializeLoot` 的一处赋值**即可整体缩到 40%，不存在基准不一致（AC-1）。

`Loot.tscn` 的 `RectangleShape2D_interaction.size = Vector2(37.2, 54.8)` 独立于上面的缩放，是命中区域（AC-2）。

## 4. 为什么不复用 `_try_get_interaction_range`

三个理由，任何一个都足以否决复用：

1. **契约测试锁定了调用次数**：`test_world_interaction_coordinator_contract.gd:480-484` 断言 `var range_check: Dictionary = _try_get_interaction_range(card)` 恰好出现 **2 次**。自动拾取若复用该助手，计数会变成 3，断言失败。
2. **语义不同**：`InteractionRange` 是「地形交互距离」，`AutoPickupRange` 是「拾取手感」，用户明确要求后者取小（60）且独立可调。把两者绑在一个值上会让「只想调拾取手感」被迫连带改地形交互。
3. **门禁结果不同**：地形交互超范围要弹「距离不够！」，掉落物超范围**不应有任何提示**（自动拾取是静默的）。共用一个返回 `ok` 的字典会诱导把飘字逻辑也带进拾取路径。

新助手 `_is_loot_within_auto_pickup_range` 里写的是
`return _player_char.global_position.distance_to(card.global_position) <= AutoPickupRange`，
与测试锁定的那行字面量（带 `var distance: float =` 前缀）**字符串不同**，因此既不会干扰 `:480-484` 的计数，也不会与 `:468-477` 的锁定内容冲突。`_try_get_interaction_range` 的函数体**一个字符都不改**。

## 5. 兼容性与取舍

### 5.1 遗留视图不受影响

`core/board/board_card_view.gd` + `scenes/board_card_scene/BoardCardView.tscn` 的掉落缩放与点击行为保持原样：

- 生产 `Main.tscn` 已显式把 `LootViewScene` 绑定到 `Loot.tscn`（`Main.tscn:93`），遗留视图只在导出为空时回退（`board_controller.gd:83-84`）。
- `test_board_card_view_contract.gd:65` 的「掉落卡静止缩放必须保持一倍」断言因此继续有效。
- 协调器侧对遗留视图是安全的：遗留 `board_card_view.gd` 没有 `IsPickupAvailable`，`has_method` 分支会放行；它的 `PlayFlyTo`（`board_card_view.gd:187`）签名与 `loot_view.gd` 一致，拾取动画仍可用。

### 5.2 命中区域变小的已知取舍

命中区域缩到 `37.2×54.8` 后悬停热区极小（用户明确选择「一起缩到 40%」）。判定为可接受，因为手动点击拾取已取消，悬停动画不再是拾取的必要路径。若后续觉得热区太小，可单独把 `RectangleShape2D_interaction` 调大，不影响视觉尺寸。

### 5.3 每帧轮询的开销

`_process_auto_pickup` 每帧遍历棋盘快照。开销上界：

- 一屏内掉落卡数量通常为个位数（散射半径 40～90 像素，见 `board_controller.gd:56-58`）。
- 每张卡在**通过距离判定之后**才会调用 `TryAddItemToInventory`，而距离判定是两次 `global_position` 读取加一次浮点比较。
- 背包满时确实会每帧重复调用 `CanAddItemStack`，但该函数文档明确「不修改库存」（`inventory_component.gd:322`），槽位数在几十量级，代价可忽略；换来的是「腾出空间立即拾取」的零额外状态机实现。

**不引入**节流/冷却：节流会破坏 AC-10（腾出空间后应自动拾取），得不偿失。

### 5.4 门禁复用 `CanUseWorld()`

`CanUseWorld()`（`:162`）已覆盖「在树内、未暂停、非过场、棋盘可见」四个条件，且是建筑系统共用的公开门禁。复用它而不是另写一套暂停/战斗判断，可以保证「什么时候允许局外操作」这件事只有一个定义。

补充 `_is_run_ending()`（结算收尾，见 `:1126`）：该状态不属于过场，`CanUseWorld()` 覆盖不到（AC-12）。

### 5.5 回滚形态

改动集中在 5 个文件：`loot_view.gd`、`Loot.tscn`、`world_interaction_coordinator.gd`、契约测试、文档。无数据迁移、无存档格式变化、无场景节点增删。回滚 = `git checkout` 这几个文件。

## 6. 验证策略

沿用本仓库既有分工（`test_world_interaction_coordinator_contract.gd:451-455` 的注释明确记录了这条分工）：

| 层次 | 手段 | 覆盖 |
| --- | --- | --- |
| 源码形状 | 契约测试（源码字符串断言） | 新导出/新助手存在；锁定字面量未漂移；`_try_get_interaction_range` 仍是 2 次 |
| 场景形状 | 契约测试（`.tscn` 字符串断言） | `RectangleShape2D_interaction.size = Vector2(37.2, 54.8)` |
| 真实行为 | `game_eval` 在主场景运行中验证 | `_should_auto_pickup` 判定、靠近入包、背包满不拾取、点击不拾取、飞入缩小消失、飞入中不二次拾取 |

### 为什么不在编辑器测试里做运行时断言

两条仓库规范直接禁止这条路径：

- `.trellis/spec/backend/testing-guidelines.md:39`：「`PackedScene.instantiate()` 对非 `@tool` 的生产脚本只会得到占位实例，**方法不可调用**……改为在冒烟阶段用 `game_eval` 断言真实运行期结果；套件侧只保留数据契约与源码形状断言」。
- `.trellis/spec/frontend/component-guidelines.md:16`：「编辑器内非 `@tool` 场景脚本的占位实例**不能替代游戏进程验证**」。

`world_interaction_coordinator.gd` 与 `loot_view.gd` 都不是 `@tool`，因此：

- 新套件**只写源码形状与场景形状断言**，并在套件注释里写明这条限制（照 `test_interaction_range_gate` 的写法）。
- `_should_auto_pickup` 的判定行为改在**运行中的游戏**里用 `game_eval` 直接调用真实协调器实例验证，而不是在编辑器里伪造实例。
- 「飞入缩小消失」的时序用 `Tween.custom_step(delta)` 在同步 eval 内精确推进（`testing-guidelines.md:72`），不依赖帧率、也不受窗口后台化影响。

### `game_eval` 的硬性写法约束（`testing-guidelines.md:65-73`）

- **不用 `get_tree()`**：eval 上下文里它返回 `null`。改用 `Engine.get_main_loop() as SceneTree`，再经 `tree.root` 取节点。
- **运行期错误会冻结游戏**：断言要写成先取值再比较，不要在 eval 里制造异常；出错后只能 `project_manage(op="stop")` 重开。
- **窗口不能后台化**：主循环冻结时任何 `await` 都会挂到 `EVAL_HUNG`。

### 套件发现的前置条件（`testing-guidelines.md:21-28`）

`test_run` 只扫描 `res://tests` **顶层**、不递归。新套件除了 `tests/godot/test_loot_auto_pickup_contract.gd`，还必须在 `tests/` 顶层放两行壳文件：

```gdscript
@tool
extends "res://tests/godot/test_loot_auto_pickup_contract.gd"
```

漏掉壳文件会得到 `No suite named 'loot_auto_pickup_contract' is registered`；补壳后必须重新 `filesystem_manage(op="scan")`（重载插件不会刷新该缓存）。

### 否定断言不能直接 `contains()`（`testing-guidelines.md:41-49`）

套件里解释「不要再调用旧入口」的注释本身会包含旧标识符，`assert_false(source.contains("旧名"))` 会因此变红。因此本任务的断言只做**正向存在性**检查（新助手、新导出、新协议都在），不对旧标识符做否定匹配。
