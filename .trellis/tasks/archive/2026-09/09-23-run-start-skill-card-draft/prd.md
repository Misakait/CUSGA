# 开局技能卡抽取（抽 5 选 2）

## Goal

每局开局在「角色与背包初始化」完成之后，触发一次技能卡抽取：从技能卡池随机抽出 **5 张**展示给玩家，玩家选中其中 **2 张**并获取，其余 3 张作废。本任务交付三部分：抽取逻辑、选卡界面、以及挂接到开局时机的触发点。

用户价值：让每局开局多一次「构筑选择」——玩家按当局策略挑卡进场，而不是拿着固定卡组开始一局。

## Background（已核实事实，带证据锚点）

### 开局时机与挂接点

- 每局开局的唯一时点是 `Main` 场景装配完成：主菜单 StartCard 直接 `get_tree().change_scene_to_file("res://scenes/Main.tscn")`（`scripts/normal_compoment/main_menu.gd:13`）。
- 开局初始化入口已由子任务 `09-23-run-start-loadout-init` 建立并归档：`core/gameflow/run_start_initializer.gd` 挂在 `scenes/Main.tscn`（排在 `Player` 之后），`_ready()` 同步执行初始化，完成后广播 `signal RunStartInitialized`。
- 该子任务的设计文档第 6 节是**对本任务的接口承诺**：`RunStartInitialized` 是唯一的开局初始化完成时点，抽卡环节**必须挂接它**，不得自行监听场景加载或另起初始化入口。挂接它同时保证顺序确定：抽卡产出发生在背包初始化之后，不会被「先清空背包」的逻辑清掉。

### 技能卡资产

- `resources/skill_cards/*.tres` 共 **69 张**，其中 `test_card_1` … `test_card_7` 共 7 张是测试资产，其余 62 张是生产卡（五行法术/物理、单体/全体/随机/扩散等）。
- 脚本 `resources/item/card/skill_card_data.gd`（`extends "res://resources/item/item_data.gd"`）：新增 `Skill` / `cost` / `CardTags` 字段，并覆盖 `_resolve_actual_max_stack_size()` 使其**恒为 1**，即单张技能卡占一个槽位。
- 现有代码里**没有**「全部技能卡」的池资源。`ItemsControl` 只从 `res://items` 递归加载物品（`core/autoloads/ItemsControl.gd` 的 `load_all_items_from_items_folder()`），技能卡不在该目录下。运行期可用的枚举方式：① 手工在检查器里挂满的池 `.tres`；② 运行时递归扫描 `res://resources/skill_cards`（项目已有 `DirAccess` 递归扫描先例）；③ 读 `card_table/skill_cards.csv`（构建期产物，运行期不可用，已排除）。这属于技术设计选择，默认按 ② 处理。

### 「获取」的落点：决定本任务功能是否在战斗中生效

- 玩家的**出战卡组** `entities/components/battle_deck_component.gd`（`extends inventory_component.gd`）只接受「暴露 `Skill` 字段」的物品资源（`:18-24`），并对外提供 `GetSkillCards()`（`:43-50`）。
- **战斗牌池的唯一来源就是出战卡组**：遇敌时 `EncounterRequested.emit(terrain, GetPlayerSkillCards(), scaled_monsters, ...)`（`core/application/gameplay_port.gd:140`），而 `GetPlayerSkillCards()` 读的是 `PlayerBattleDeck = Player.get_node_or_null(PlayerBattleDeckPath)`（路径默认 `Components/BattleDeckComponent`，同文件 `:14`、`:82`、`:145-155`）。
- 战斗侧 `scripts/card_scripts/deck_manager.gd:43 initialize_deck(starting_deck_data)` 把这份数组直接当抽牌堆；牌数少于 `min_start_cards_count = 20`（`:12`）时用 10 张基础法术填充（`:15-24`、`:167-176`）。这是既有行为，本任务不改。
- **背包与出战卡组之间的整理链路是既有能力**：背包界面同时绑定背包与卡组两套槽位（`core/ui/inventory_ui.gd:167-176`、`:207-209`），拖拽载荷带来源标识（`core/ui/slot_ui.gd:198-199`、`entities/components/inventory_component.gd:18`、`battle_deck_component.gd:10`），卡组槽位只接受带 `Skill` 字段的物品，而技能卡满足该条件。因此「抽到的卡进背包后，玩家可自行放进卡组」在既有系统内具备可行性，但**该链路不属于本任务交付物**。

### 已有的技能卡卡面（可复用的字段协议）

- `scenes/skill_card_scenes/SkillCard.tscn` + `scripts/card_scripts/skill_card.gd`（`class_name SkillCard`，`extends Node2D`）是战斗手牌使用的技能卡卡面；它的 `init_card_data(card_data)` 按稳定显示字段刷新内容：`DisplayName` / `DisplayDescription` / `DisplayTag` / `cost`，并经 `card_data.Skill.Element` 显示五行属性（`:56-83`）。
- **它不能直接搬到抽卡界面**：`_ready()` 里执行 `get_parent().connect_card_signals(self)`，脚本注释也明确「该节点必须挂载在 CardManager 下」（`:26-28`），而抽卡界面没有 `CardManager`。
- 可复用的是**字段协议**：抽卡卡片视图照 `DisplayName` / `DisplayDescription` / `DisplayTag` / `cost` 读取，即可与战斗卡面显示一致。

### 可复用的选卡界面范式

- 天赋系统已经是「暂停 + 原地洗牌 + 展示 N 张 + 点选回调」的完整实现，见 `resources/talents/talent_manager.gd`：
  - `_ready()` 里 `hide()`、把池拷进 `_available_talents`、`_random.randomize()`、订阅长生命周期 autoload 的触发信号（`:29-34`），并在 `_exit_tree()` 解除订阅（`:39-43`）。
  - `_pop_up_talent_selection()` 里 `get_tree().paused = true` + `show()`（`:60-67`）。
  - `_draw_three_talents()` 做 Fisher-Yates 原地洗牌（`:73-77`），清空容器后按 `mini(3, 池大小)` 实例化卡片，并 `new_card.call("Initialize", data)` + `new_card.connect(&"OnCardClicked", OnTalentSelected)`（`:79-88`）。
  - `OnTalentSelected()` 从池里 `erase`、经 `/root/GlobalEventBus` 广播获取、`hide()` 并 `get_tree().paused = false`（`:50-55`）。
- 该管理器的可配置面全部是 `@export`：`AllTalentsPool: Array[Resource]`、`CardScenePrefab: PackedScene`、`CardsContainer: HBoxContainer`（`:9-15`）。
- 全局暂停开关 `get_tree().paused` 与暂停菜单、属性分配弹窗共用同一套语义。

## Decisions（已由用户确认）

- **D1 获取落点 = 玩家背包 `InventoryComponent`**（不是出战卡组）。
  - 直接后果：抽到的 2 张技能卡进入 `Components/InventoryComponent`，玩家能在背包界面看到。战斗牌池只读出战卡组，因此这 2 张**不会自动出现在战斗中**；玩家若想在对局里用它们，需自行经背包界面的卡组区域整理（该能力属既有 UI，见上文）。
  - 因此本任务的验收**不包含**「抽到的卡可在战斗中打出」，只验收「确实进入玩家背包、数量正确、无残留副本」。

- **D2 卡池 = 62 张生产技能卡**，排除 `test_card_1` … `test_card_7` 共 7 张测试资产。
  - 一次抽取的 5 张**互不重复**（同一张卡不会在 5 张里出现两次）。
  - **不排除**「玩家已拥有」的卡：技能卡堆叠上限为 1，抽到已有的卡会在背包里另占一个槽位，这是可接受的结果。
  - 池大小 62 恒大于抽取数 5，因此不存在「池不足 5 张」的分支。

- **D3 抽卡界面以战斗卡面 `SkillCard.tscn` 为视觉基础**（不使用天赋卡片场景 `scenes/talents/talent_card.tscn`，因为其脚本读的是 `TalentName` / `Description` / `TalentTexture`，与技能卡字段协议不同）。
  - 已确认的两个技术障碍：
    1. `SkillCard.tscn` 根节点是 `Node2D`（`scenes/skill_card_scenes/SkillCard.tscn:10`），**无法被 `HBoxContainer` 等 Container 布局**，抽卡界面必须自行处理 5 张卡的摆放。
    2. `skill_card.gd` 的 `_ready()` 无条件执行 `get_parent().connect_card_signals(self)`（`:28`），父节点不是 `CardManager` 时会直接报错；该方法的实现见 `scripts/card_scripts/card_manager.gd:1019`，负责把手牌的 `hovered` / `hovered_off` 接到战斗表现上。
  - 落地形态见 D4 结论。

- **D4 落地形态 = 给 `SkillCard._ready()` 加存在性守卫**：父节点未提供 `connect_card_signals` 时跳过连接，使同一份战斗卡面在抽卡界面也能实例化。
  - 收益：只有**一份**卡面视觉定义，抽卡与战斗显示完全一致。
  - 代价：这是本任务唯一一处行为相关的既有脚本改动（一行守卫）。战斗路径下父节点始终是 `CardManager`，守卫恒为真、连接照旧发生，因此需回归手牌相关套件与战斗场景冒烟来证明「战斗行为不变」。

## Requirements（草案，待收敛）

- **R1 触发时机**：每局开局恰好触发**一次**抽卡；触发点挂接 `RunStartInitialized`，不自行监听场景加载。
- **R2 抽取**：从技能卡池随机抽出 5 张供选择；5 张之间互不重复。
- **R3 选择**：玩家从 5 张中恰好选择 2 张；未选满 2 张时无法结束抽卡（依据源需求 SR-2「玩家选择并获取其中两张」的字面要求）。
- **R4 获取**：选中的 2 张通过背包组件的稳定写入协议进入玩家背包 `Components/InventoryComponent`；未选中的 3 张不进入任何玩家持有物、不残留。
- **R5 阻塞**：抽卡期间玩家不可操作局内玩法，选满 2 张并确认后才恢复。
- **R6 幂等与隔离**：同一次开局不重复抽卡；连续两局各自独立抽取一次，不携带上一局的选择结果。
- **R7 溢出可诊断**：若背包放不下（背包容量 27，技能卡单张占一槽），必须留下可诊断的警告，且不得把物品无声丢弃、也不得回流到卡池或重抽。

## Acceptance Criteria（草案）

- [ ] 每局开局恰好弹出一次抽卡界面，界面内恰好 5 张互不重复的技能卡。
- [ ] 抽取结果全部来自 62 张生产技能卡，不含 `test_card_1` … `test_card_7`。
- [ ] 未选满 2 张时无法结束抽卡；选满 2 张并确认后界面关闭、游戏恢复可操作。
- [ ] 选中的 2 张确实进入玩家背包 `Components/InventoryComponent`（数量与身份一致、无多余副本），且不会被开局初始化逻辑清掉。
- [ ] 未选中的 3 张不进入玩家背包、出战卡组或任何其它持有物。
- [ ] 连续两局开局各抽一次；第二局的抽取不会因上一局而缺卡/多卡，也不带上上一局选中的卡。
- [ ] 抽卡界面与初始化环节互不覆盖：抽卡产出在初始化之后结算，初始化不会因抽卡暂停而在错误时机重复执行。
- [ ] `docs/游戏机制与玩法内容.md` 的「开局流程」一节补齐抽卡环节：触发时机、与初始化的先后顺序、抽取张数 5、选取张数 2、卡池范围、落点为背包，以及「不自动进入战斗牌池」这一事实。

## Out of Scope

- 不改战斗内的抽牌 / 出牌 / 牌堆 / 洗牌规则（`scripts/card_scripts/deck_manager.gd` 等）。
- 不改 `DeckManager.min_start_cards_count = 20` 的基础卡填充行为（开局只多 2 张卡时战斗仍会被基础卡补足，这是既有规则）。
- 不做「背包 → 出战卡组」的自动搬运；不验收该整理链路的可用性。
- 不做卡牌升级、合成、分解、稀有度表现与抽卡演出动画（除非后续明确要求）。
- 不做消耗货币/资源的重抽机制。
- 不做跨局存档（沿用现有 `PersistAcrossRuns = false` 策略）。

## Open Questions

- 无（D1~D4 均已由用户确认；设计层面的选择写在 `design.md`，并在最终规划摘要中一并呈现供审阅）。

## Notes

- 本任务由父任务 `09-23-game-start-flow` 拆分而来（父任务持有源需求集与跨子任务集成验收，自身不实现）。源需求为 SR-2：游戏开局触发技能卡抽取，抽取五张技能卡，玩家选择并获取其中两张。
- 与子任务 1 的**实现顺序依赖**：本任务挂接的 `RunStartInitialized` 信号由 `09-23-run-start-loadout-init` 提供，该子任务已实现并归档，信号在生产代码中已存在，因此本任务无前置阻塞。
- 父任务的集成验收要求「两个环节互不覆盖」与「连续开局不累积」，因此 R6 的隔离性必须由本任务的验收覆盖。
