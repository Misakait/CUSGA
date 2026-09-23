# 开局技能卡抽取（抽 5 选 2）—— 技术设计

## 1. 架构与边界

### 1.1 问题陈述

源需求 SR-2 是「开局触发技能卡抽取，抽 5 张，玩家选 2 张并获取」。表面上是一段随机抽取逻辑，实际要解决四个问题：**触发时机**（开局是哪个时点）、**卡池从哪来**（工程里没有现成的技能卡池资源）、**获取落到哪里**（背包与出战卡组是两套持有物，只有卡组进战斗）、**界面怎么来**（现成有两种选卡界面，字段协议与交互语义都不同）。

### 1.2 边界划分（改动后）

| 角色 | 归属 | 职责 |
| --- | --- | --- |
| 开局时机 | `core/gameflow/run_start_initializer.gd`（子任务 1 已交付） | 唯一的开局初始化完成时点，以 `RunStartInitialized` 广播 |
| 抽卡流程 | **新增** `core/gameflow/run_start_skill_card_draft.gd`，实例挂在 `scenes/Main.tscn` 的 `UI/HUDLayer/HUDRoot` 下（与 `PauseMenu` 同级同范式） | 监听时机 → 抽 5 张 → 展示 → 收集 2 张选择 → 写入背包 → 关闭并恢复 |
| 卡池 | 抽卡脚本自身 | 运行时扫描 `res://resources/skill_cards`，按「暴露 `Skill` 字段」判定，排除 `test_card_*` |
| 卡面视图 | **复用** `scenes/skill_card_scenes/SkillCard.tscn`（`scripts/card_scripts/skill_card.gd`） | 只负责显示与点击转发，不持有抽取逻辑 |
| 玩家背包 | `entities/components/inventory_component.gd` | 只经 `AddItem` 稳定协议写入 |
| 战斗手牌 | 不变 | 本次**不改**战斗内抽牌/出牌/牌堆规则 |

**为什么抽卡流程放在 `core/gameflow/`**：`.trellis/spec/backend/directory-structure.md` 规定该目录持有「世界 → 战斗」的流程脚本，开局流程正属于此；与子任务 1 的 `run_start_initializer.gd` 同目录也便于把「开局」这条链一眼看完。

**为什么界面挂在 `UI/HUDLayer/HUDRoot`**：`PauseMenu` 就在那里（`scenes/Main.tscn:241`），它是本项目「全屏遮罩型浮层」的既有范式；`CenterOverlay`（`Main.tscn:214`）承载的是背包/合成/仓库这类居中面板，语义不符。同层保证了抽卡层级高于 HUD 且与暂停菜单一致。

## 2. 数据流与契约

### 2.1 触发时序（本设计最关键的约束）

`RunStartInitializer._ready()` **同步**执行初始化并 `emit` 信号。Godot 的同级 `_ready` 按树顺序触发，而 `Main.tscn` 的子节点顺序是 `Player` → `RunStartInitializer` → `DebugLoadoutSeeder` → `UI` → …，抽卡界面挂在 `UI` 之下，**必然排在 `RunStartInitializer` 之后**——也就是说，如果只靠 `connect(RunStartInitialized)`，抽卡节点注册监听时信号已经发射完毕，它会**永远收不到信号**。

**解法（消除隐式节点顺序契约）**：

1. 在 `RunStartInitializer` 上**纯新增**一个只读查询 `HasInitialized() -> bool`（返回 `_has_initialized`），不改动任何既有行为。
2. 抽卡脚本 `_ready()` 的顺序固定为：解析 `@export InitializerPath` → `connect` 信号 → **立即补偿检查** `HasInitialized()`，为真则当场执行抽卡。
3. 两条路径都可能到达 `_start_draft()`，由 `_has_drafted` 标志去重，保证「每局恰好一次」。

不采用「把抽卡节点挪到 `RunStartInitializer` 之前」的做法：那会把正确性押在节点顺序这个不可见契约上，任何人日后调整场景顺序都会静默失效。补偿检查让顺序**不参与正确性**。

### 2.2 `RunStartInitializer` 新增契约

```gdscript
## 本次开局是否已经执行过初始化；供后续开局环节在不依赖节点顺序的前提下确认时机。
func HasInitialized() -> bool
```

### 2.3 抽卡脚本契约

```gdscript
## 抽卡环节完成信号（本项目内暂无消费者，供后续环节与测试观测）。
signal SkillCardDraftCompleted(selected_cards: Array)

## 开局初始化节点路径；默认取同级查找失败时的兜底写法。
@export var InitializerPath: NodePath = NodePath("../../RunStartInitializer")
## 玩家背包组件相对玩家节点的路径。
@export var PlayerPath: NodePath = NodePath("../../../Player")
@export var InventoryComponentPath: NodePath = NodePath("Components/InventoryComponent")
## 技能卡池目录。
@export var CardPoolDirectory: String = "res://resources/skill_cards"
## 卡面场景。
@export var CardScenePrefab: PackedScene
## 放置 5 张卡面的容器。
@export var CardsContainer: HBoxContainer
## 确认按钮。
@export var ConfirmButton: Button
## 提示标签（「已选 n/2」）。
@export var HintLabel: Label
## 抽取张数 / 选取张数（常量，不开放导出，避免与验收数值漂移）。
const DRAW_COUNT: int = 5
const PICK_COUNT: int = 2
```

- 上述 `@export` 路径的具体取值在接线时按 `Main.tscn` 实际层级校准，并以「即使路径写错也只报错不崩溃」的方式解析（`get_node_or_null` + `push_error`）。
- `ConfirmButton` 在选中数 < 2 时禁用；点击后执行获取并关闭。
- 卡面点击经 `SkillCard` 既有信号 `hovered` 转发，或由占位控件自己的 `gui_input` 接收。**注意**：`SkillCard` 是 `Node2D` + `Area2D`，其 `hovered` / `hovered_off` 是给战斗手牌用的悬停信号；抽卡侧不复用它们，而是用占位 `Control` 承接点击，避免与战斗语义混淆。

### 2.4 卡池枚举契约

- 递归扫描 `CardPoolDirectory`（`DirAccess`，复用项目既有递归扫描范式，见 `core/autoloads/ItemsControl.gd` 的 `load_items_recursively`）。
- 入选条件（两条同时满足）：
  1. 资源暴露 `Skill` 字段——与 `entities/components/battle_deck_component.gd:18-24` 的「技能卡判定协议」完全一致，**刻意不按脚本路径判语言**（该文件已记录这条理由）。
  2. 文件名不以 `test_card_` 开头（排除 7 张测试资产，落实决策 D2）。
- 池大小恒为 62（当前资产），大于 `DRAW_COUNT = 5`，因此**不存在「池不足 5 张」的分支**；仍保留 `mini(DRAW_COUNT, pool.size())` 的写法以防资产被删，但不对该分支做验收。

### 2.5 抽取与选择

- 用**独立** `RandomNumberGenerator` 并 `randomize()`，Fisher-Yates 原地洗牌（范式见 `resources/talents/talent_manager.gd:73-77`），不改动项目其它随机序列。
- 取洗牌后前 5 张，天然互不重复（同一个池元素只出现一次），满足 D2 的「5 张互不重复」。
- 选择交互：点卡面切换选中态；已选 2 张时再点未选卡面无效（并更新提示文案）；确认按钮仅在恰好 2 张时可用。

## 3. 卡面复用与「Node2D 不能进容器」的化解

`scenes/skill_card_scenes/SkillCard.tscn` 根节点是 `Node2D`（`:10`），**无法被 `HBoxContainer` 等 Container 布局**；同时 `skill_card.gd:28` 的 `_ready()` 无条件调用 `get_parent().connect_card_signals(self)`，父节点不是 `CardManager` 会直接报错。

两处分别处理：

1. **布局**：容器里放 5 个 `Control` 占位（占位由容器布局并随视口缩放），每个占位下挂一个 `SkillCard` 实例并居中。占位承担布局与选中态表现（`modulate` 变化 + 轻微上移），卡面只负责渲染。这样既不复制卡面视觉，也不需要 `Node2D` 参与布局。
2. **解耦**（决策 D4 = C1，用户已批准）：把 `skill_card.gd` 的 `_ready()` 改为**存在性守卫**——父节点没有 `connect_card_signals` 时跳过连接。这是本任务唯一一处对既有生产脚本的行为相关改动，改动量为一行判断；战斗侧父节点始终是 `CardManager`（`scripts/card_scripts/card_manager.gd:1019` 提供该方法），因此**战斗行为不变**，并需回归手牌相关套件与战斗场景。

选中态刻意不复用 `SkillCard.lock()` / `unlock()`：那两个方法服务于战斗的「锁定」语义（显示 `LockColor`），借用会让两处语义混在一起。选中表现放在占位控件上。

## 4. 兼容与迁移

- `RunStartInitializer` 只新增 `HasInitialized()`，既有 `Initialize()` / `RunStartInitialized` 语义不变，子任务 1 的契约套件应继续全绿。
- `skill_card.gd` 的守卫不改变战斗路径（父节点是 `CardManager` 时守卫恒为真，连接照旧发生）。
- `scenes/Main.tscn` 只新增一个界面实例节点，不改动既有节点顺序与属性；`DebugLoadoutSeeder` 维持子任务 1 的默认停用状态。
- 无存档格式、无资源格式、无 autoload 注册变化。

## 5. 权衡、风险与回滚

### 5.1 已做取舍

| 取舍 | 选择 | 理由 |
| --- | --- | --- |
| 获取落点 | 背包（D1，用户决定） | 后果已写入 PRD：抽到的卡不进战斗牌池，需玩家自行整理；本任务不验收该链路 |
| 触发方式 | 信号 + 补偿检查 | 仅靠信号在本场景必然失效；仅靠轮询则丢掉显式时机。两者结合后节点顺序不参与正确性 |
| 界面 | 复用战斗卡面（D3/D4） | 视觉与战斗一致、只有一份卡面定义；代价是动战斗脚本一行 |
| 选中态 | 放在占位 Control 上 | 避免与 `SkillCard.lock()` 的战斗语义混用 |
| 卡池来源 | 运行时扫描目录 | 工程里没有现成池资源；扫描能自动跟随美术新增卡，不需维护第二份清单 |

### 5.2 风险与对策

| 风险 | 影响 | 对策 |
| --- | --- | --- |
| 误改战斗手牌行为 | 战斗卡面悬停/缩放异常 | 守卫只在父节点缺方法时跳过；回归 `test_run` 手牌相关套件 + 战斗场景冒烟 |
| 暂停状态不归还 | 抽卡结束后整屏无响应 | 记录进入前的 `paused` 状态，关闭时只归还自己造成的那次暂停（沿用暂停菜单的既有约定，`core/ui/hud/pause_menu.gd`） |
| 背包放不下 2 张卡 | 物品无声消失 | `AddItem` 返回值 > 0 时 `push_warning`，不重抽、不回池（R7） |
| 抽卡重复触发 | 玩家多拿卡 | `_has_drafted` 标志保证每局一次；两条触发路径共用同一入口 |
| 路径导出在场景里配错 | 抽卡报错或静默不触发 | 一律 `get_node_or_null` + `push_error`；并在契约测试里用桩节点覆盖 |
| 目录扫描拖慢开局 | 开局卡顿 | 只在首次抽卡时扫描一次并缓存；62 个 `.tres` 的加载成本远低于场景装配 |

### 5.3 回滚点

1. `skill_card.gd` 守卫改动 → 单独可回滚（不影响其它改动）。
2. 抽卡脚本 + 卡面视图 → 新增文件，删除即回滚。
3. `Main.tscn` 接线 → 单独可回滚。
4. `RunStartInitializer.HasInitialized()` → 纯新增，回滚即删除方法。

## 6. 验收与验证方式

| 目标 | 方式 |
| --- | --- |
| 卡池枚举正确（62 张、无测试卡、≥5） | 契约套件直接对生产脚本调用内部枚举并断言 |
| 抽取不重复、只取 5 张 | 契约套件对多次抽取结果去重后断言大小 |
| 恰好选 2 张、第 3 张被拒 | 契约套件用桩卡面驱动选择路径 |
| 选中的 2 张进背包、未选中的不进 | 契约套件用真实 `InventoryComponent` 实例断言 `ItemCnt` |
| 幂等 | 两条触发路径都调用一次，断言只抽一次 |
| 「无 CardManager 父节点不报错」 | 契约套件把 `SkillCard` 实例挂到普通 `Node` 下断言不产生 SCRIPT ERROR |
| 真实开局行为 | `project_run(mode="main")` 后用 `game_eval` 断言抽卡界面出现、确认后背包 +2 |
| 战斗未被破坏 | `test_run` 全量 + 战斗场景冒烟 |
| 文档同步 | 更新 `docs/游戏机制与玩法内容.md` 的「开局流程」一节 |

**已知既有缺陷，不作为本任务验收项**：把 `Warehouse.tscn` 当初始场景直接运行会因 `inventory_control.gd` 的 `@onready` 时机报错（`state-management.md:491` 已记录）；`player.tscn` 未包含 `crafting_recipe.gd` 字面量与 `map_control.tscn` 的两个 UID 声明，是两处**先于本任务存在**的全量套件红灯（已在本会话取证），本任务不修。
