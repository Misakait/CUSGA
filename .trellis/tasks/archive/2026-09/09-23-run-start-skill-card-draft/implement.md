# 开局技能卡抽取（抽 5 选 2）—— 执行计划

## 0. 开工前检查

- 前置依赖已满足：`core/gameflow/run_start_initializer.gd` 已交付并归档，`RunStartInitialized` 信号在生产代码中存在（`grep` 可验）。
- 唯一允许改动的既有生产文件是 `scripts/card_scripts/skill_card.gd`（决策 D4=C1，用户已批准）与 `core/gameflow/run_start_initializer.gd`（纯新增方法）；其余改动都是新增文件或新增场景节点。
- 验证一律走**编辑器 MCP**（`test_run` / `project_run` + `logs_read(source="game")` / `game_eval`），不使用 `godot-mono` 命令行；本工程已无 `.cs` 文件，`dotnet build` 门禁不适用于本次改动。

## 1. 执行步骤

### S1 解耦战斗卡面（唯一的行为相关既有改动）

- 文件：`scripts/card_scripts/skill_card.gd`
- 改动：`_ready()` 里把
  ```gdscript
  get_parent().connect_card_signals(self)
  ```
  改为**存在性守卫**：父节点存在且提供 `connect_card_signals` 时才连接；否则跳过（不报错）。
- 约束：保留原有注释与 `_ready()` 的既有职责表述，只**追加** `【修订说明】` 说明为何加守卫（抽卡界面不在 `CardManager` 下），不改动其它任何方法。
- 验证：`test_run(suite="player_hand_cache_contract")` 与手牌相关套件保持全绿；战斗场景冒烟无 `SCRIPT ERROR`。

### S2 给开局初始化补一个可查询的完成状态

- 文件：`core/gameflow/run_start_initializer.gd`
- 改动：新增 `func HasInitialized() -> bool`（返回 `_has_initialized`），并在文件头文档注释里补一句用途（供后续开局环节在不依赖节点顺序的前提下确认时机）。
- 约束：**纯新增**，不改动 `Initialize()`、信号、既有导出的语义与默认值。
- 验证：`test_run(suite="run_start_loadout_contract")` 保持 9/9 全绿。

### S3 抽卡流程脚本

- 新增：`core/gameflow/run_start_skill_card_draft.gd`
- 内容要点：
  1. `const DRAW_COUNT: int = 5`、`const PICK_COUNT: int = 2`（不开放导出，避免与验收数值漂移）。
  2. `@export` 面：`InitializerPath`、`PlayerPath`、`InventoryComponentPath`、`CardPoolDirectory`、`CardScenePrefab`、`CardsContainer`、`ConfirmButton`、`HintLabel`；一律 `get_node_or_null` 解析 + `push_error` 报错。
  3. `_ready()`：解析依赖 → `connect(&"RunStartInitialized", ...)` → **补偿检查** `HasInitialized()`，为真则当场抽卡；用 `_has_drafted` 去重，保证每局恰好一次。
  4. 卡池枚举：递归扫描 `CardPoolDirectory` 的 `.tres`，入选需同时满足「资源暴露 `Skill` 字段」（与 `battle_deck_component.gd:18-24` 同协议，不按脚本路径判语言）与「文件名不以 `test_card_` 开头」；首次扫描后缓存。
  5. 洗牌：独立 `RandomNumberGenerator` + `randomize()` + Fisher-Yates（范式见 `resources/talents/talent_manager.gd:73-77`），取前 5 张（天然不重复）。
  6. 展示：为每张卡建一个 `Control` 占位（由 `CardsContainer` 布局）并居中挂载 `CardScenePrefab` 实例，调用卡面既有的 `init_card_data(card)`；点击由占位控件承接（**不**复用 `SkillCard.hovered`，那是战斗手牌语义）。
  7. 选择：点占位切换选中态（`modulate` + 轻微上移，最多 2 张，第 3 张无效）；每次刷新提示「已选 n/2」；`ConfirmButton` 仅在恰好 2 张时可用。
  8. 获取：按选择顺序对每张卡调用背包的 `AddItem(card, 1)`；返回值 > 0 时 `push_warning`（不重抽、不回池）；随后关闭界面并恢复暂停。
  9. 暂停：进入时记录 `_was_paused_before_open`，退出时**只归还自己造成的暂停**（沿用 `core/ui/hud/pause_menu.gd` 的既有约定）。
  10. 全部注释与文档字符串用中文；`@export` 置顶；缺失依赖用 `push_error`、降级路径用 `push_warning`。

### S4 抽卡界面场景

- 新增：`scenes/ui_scenes/skill_card_draft_screen.tscn`（与 `pause_menu.tscn` 同目录——本项目「界面场景」的既有归属；脚本放在 `core/gameflow/` 是因为它的身份是开局流程节点而非 HUD 常驻组件）。
- 结构：根 `Control`（full_rect，挂 S3 脚本）→ 全屏半透明遮罩 → `PanelContainer`/`VBoxContainer`（标题「开局技能卡抽取」→ `HBoxContainer` 卡容器 → 提示 `Label`「已选 0/2」→ 确认 `Button`）。
- 在场景里配置 `CardScenePrefab = res://scenes/skill_card_scenes/SkillCard.tscn` 以及容器/按钮/提示的 `@export` 引用。
- 用编辑器 MCP 创建并保存（`scene_manage` / `node_create` / `node_set_property` / `scene_save`），随后 `filesystem_manage(op="scan")` 刷新类缓存。

### S5 接线 `Main.tscn`

- 在 `UI/HUDLayer/HUDRoot` 下实例化 S4 场景（与 `PauseMenu` 同级同范式），节点名 `SkillCardDraftScreen`。
- 精确路径（按现有层级推导）：`InitializerPath = NodePath("../../../RunStartInitializer")`（`HUDRoot → HUDLayer → UI → Main`）、`PlayerPath = NodePath("../../../Player")`；接线后**必须在运行期验证路径可解析**，不能只靠推导。
- 不改动既有节点顺序与属性；`DebugLoadoutSeeder` 维持默认停用。
- 保存并 `filesystem_manage(op="scan")`。

### S6 契约套件

- 新增：`tests/godot/test_run_start_skill_card_contract.gd`（实体）+ `tests/test_run_start_skill_card_contract.gd`（顶层转发壳，**必须**：`test_run` 只发现 `res://tests` 顶层与 `tests/godot` 的 `test_*.gd`）。
- 用例（全部用桩节点，`test_run` 环境无 autoload）：
  1. 卡池枚举：不含 `test_card_`、数量 ≥ 5、每张都暴露 `Skill` 字段。
  2. 抽取：连续多次抽取均为 5 张且组内无重复。
  3. 选择：选满 2 张前确认不可用；第 3 张点击被拒且选中集合仍为 2。
  4. 获取：确认后真实 `InventoryComponent` 的对应槽位出现这 2 张卡，`ItemCnt` 正确。
  5. 未选中的 3 张不在背包中（逐张断言不存在）。
  6. 幂等：信号路径与补偿路径各触发一次，只抽一次。
  7. `HasInitialized()` 契约：初始化前为假、`Initialize()` 后为真。
  8. 卡面守卫：把 `SkillCard` 实例挂到普通 `Node` 下不产生 SCRIPT ERROR（负向断言用 `expect_script_error_containing` 覆盖可预期告警）。
  9. 生产接线形状：`Main.tscn` 文本含 `SkillCardDraftScreen` 节点；`skill_card_draft_screen.tscn` 含脚本引用与 `CardScenePrefab` 赋值。
- 运行：`test_run(suite="run_start_skill_card_contract")`。

### S7 运行链路验证（真实游戏）

1. `test_run`（全量）——确认新增套件全绿，且相对改动前的基线（360 passed / 2 failed）无新增红灯；那 2 条既有红灯（`crafting_recipe_contract`、`final_migration_audit_contract`）继续记录为**先于本任务存在**。
2. `project_run(mode="main")` → 从主菜单进入一局 → `logs_read(source="game")` 断言无 `SCRIPT ERROR`。
3. 在该局内用 `game_eval` 断言：抽卡界面可见、卡容器内恰好 5 张、确认按钮初始不可用；模拟选满 2 张后确认，断言背包新增 2 张且身份与展示一致、`paused` 已恢复、界面已隐藏。
4. 退出回主菜单再开一局，断言第二次抽卡独立发生且背包不累积上一局的选择。
5. `project_manage(op="stop")` 收尾。

### S8 文档同步

- `docs/游戏机制与玩法内容.md`：在已有的「开局流程与带入消耗」一节后补齐抽卡环节——触发时机（`RunStartInitialized` 之后）、抽取 5 张、选取 2 张、卡池范围（62 张生产卡，排除 `test_card_*`）、落点为背包，并**明确写出**「抽到的卡不会自动进入战斗牌池，需玩家自行放进出战卡组」。
- `临时反馈文档.md`：追加本次学习反馈摘要（5 节）与 Git 提交描述（编号行）。

### S9 质量门与收尾

- `trellis-check`（规范符合、跨层数据流、复用、一致性）→ 修复发现项 → Phase 3 提交 → 归档本任务。
- 提交前 `git status` 核对改动范围仅含：`scripts/card_scripts/skill_card.gd`、`core/gameflow/run_start_initializer.gd`、新增的抽卡脚本与场景、`scenes/Main.tscn`、测试文件、两份文档、任务目录。

## 2. 回滚点

| 序号 | 回滚单元 | 影响面 |
| --- | --- | --- |
| R1 | `skill_card.gd` 守卫 | 仅战斗卡面解耦 |
| R2 | `HasInitialized()` | 仅新增查询 |
| R3 | 抽卡脚本 + 界面场景 | 新增文件，删除即回滚 |
| R4 | `Main.tscn` 接线节点 | 单独可移除 |

四者互相独立，S1/S2 即使保留也不改变既有行为。

## 3. 完成判据

- PRD 的 7 条 Acceptance Criteria 全部可复现地通过（含真实开局的一次 `game_eval` 证据）。
- 新增契约套件全绿；全量套件无新增红灯。
- 战斗场景与手牌相关套件未因 S1 回归。
- 文档与临时反馈文档已同步。

## 4. 实际实现偏离记录（实现完成后追加）

1. **S3 的导出面由「节点引用」改为 `NodePath`**：计划写的是 `@export CardsContainer: HBoxContainer` 这类直接节点引用，实际改为 `CardsContainerPath` / `ConfirmButtonPath` / `HintLabelPath`（默认 `Content/...`），统一在 `_resolve_view_nodes()` 里解析。原因：编辑器 MCP 把**相对** NodePath 写进 `.tscn` 会被 `VALUE_OUT_OF_RANGE: Path must start with res://, uid://, or user://` 拒绝（`batch_execute` 的同名 `set_property` 也一样）。改成带默认值的路径导出是当前工具约束下唯一能落地的写法，且与 `run_start_initializer.gd` 的既有范式一致。
2. **新增公开入口 `Setup()`（计划外）**：`_ready()` 的内容抽成 `Setup()`。原因：编辑器测试无法用 `PackedScene.instantiate()` 构造非 `@tool` 脚本的界面（拿到的是占位实例，方法不可调用），只能用 `脚本.new()` 构造；`Setup()` 让测试能够驱动与生产 `_ready()` **完全相同**的初始化路径。这是一处为可测性服务的公开面扩张，注释里写明了理由。
3. **S5 的路径层级修正**：计划里的 `../../../RunStartInitializer` 少了一层，实际为 `../../../../RunStartInitializer`——`HUDRoot → HUDLayer → UI → Main` 是**四**层。由契约测试夹具复刻生产层级后当场失败暴露，正是计划里那句「接线后必须在运行期验证路径可解析」要防的事。
4. **S6 用例调整（计划 9 条 → 实际 11 条）**：
   - 计划用例 8（把真实 `SkillCard` 挂到普通 `Node` 下断言不产生 `SCRIPT ERROR`）在编辑器里**无法成立**：真实卡面是非 `@tool` 脚本，`instantiate()` 只能得到占位实例，`_ready` 根本不执行。改为用**源码形状断言**锁定守卫（存在 `has_method("connect_card_signals")` 判定 + 仍照旧 `call("connect_card_signals", self)`），真实实例化行为改由运行期 `game_eval` 覆盖（已断言卡面脚本路径为 `skill_card.gd`、卡名标签与抽出的卡一致）。
   - 计划用例 7（`HasInitialized()` 契约）并入「时机」两条用例：分别驱动订阅路径与补偿路径，其中「已完成」那条本身就是对 `HasInitialized()` 的验证。
   - 新增计划外用例 `test_drawn_cards_are_bound_to_card_views`：用 `PackedScene.new() + pack()` 现场造一个 `@tool` 桩卡面场景，断言「每个卡槽的卡面收到的正是它自己那张卡」——这比只断言容器里有 5 个子节点更有价值。
   - 卡池/暂停这类编辑器覆盖不到或不该覆盖的点，改用源码形状断言（`DRAW_COUNT = 5`、`PICK_COUNT = 2`、`_was_paused_before_open` 记录与归还、默认路径字面量）。
5. **S7 的启动方式修正**：`project_run(mode="main")` 进的是主菜单场景（`uid://qwckbjjp11ca`），真实开局验证改用 `project_run(mode="custom", scene="res://scenes/Main.tscn")`。两次开局各做一次断言：第一次完成完整链路（5 张卡面实例化、选 2 张、背包 +2、未选不入包、界面收起、暂停归还），第二次确认新局抽卡状态独立（`drawn = 5`、`selected = 0`）；另确认 `user://` 下不存在任何存档文件，故背包内容不会跨局残留。
6. **计划外修复：未入树节点不得直接调 `get_tree()`**。夹具不入树时，`_is_tree_paused()` / `_set_tree_paused()` 调用 `get_tree()` 会打印引擎级错误 `Parameter "data.tree" is null`——返回值同样是 `null`，逻辑没错，但把日志刷满噪音、掩盖真问题。改为先用 `is_inside_tree()` 收口，并已收录进 `.trellis/spec/frontend/quality-guidelines.md`。
7. **Spec 同步（计划外产物）**：向 `.trellis/spec/frontend/state-management.md` 新增「开局信号是同步广播的，晚就绪的消费方必须补一次状态查询」，向 `.trellis/spec/frontend/quality-guidelines.md` 的夹具约束章节补充「未入树 `get_tree()`」与「夹具必须复刻生产层级以验证路径默认值」两条。前者是本任务最核心的通用教训，后者是本任务真实踩到的两个坑。
