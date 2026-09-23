# 开局流程：角色背包初始化与技能卡抽取

## Goal

把「从局外进入局内」这一瞬间统一成一个**显式、可验收的开局流程**，包含两个可独立交付、可独立验收的环节：

1. 初始化角色与其背包：新一局的角色背包里**只有**玩家在局外仓库「带入栏」中选定要带入的物品。
2. 开局技能卡抽取：开局触发一次抽卡，抽出 5 张技能卡供玩家选择，玩家选中其中 2 张并获取。

父任务持有**源需求集、子任务地图与跨子任务集成验收**，自身不承担实现（无直接交付物）。

## Background（已核实事实，带证据锚点）

- **局的边界**：主菜单「StartCard」直接 `get_tree().change_scene_to_file("res://scenes/Main.tscn")`（`scripts/normal_compoment/main_menu.gd:13`）。每次开局都会新建一份 `Main` 及其中的 `Player` 实例，因此「每局开局」在当前工程里唯一对应的时点就是 **Main 场景装配完成**那一刻。
- **仓库带入链路现状**：仓库界面离开场景时导出选择（`scripts/warehouse/warehouse_control.gd:111`），由 `scripts/map_scripts/map_control.gd:24` 消费。带入栏上限为 10 个栏位（`scripts/warehouse/warehouse_control.gd:18`）。
- **局内 → 局外回写尚未接通**：`ItemsControl.player_to_warehouse` 只有消费点（`scripts/warehouse/warehouse_control.gd:202`），**当前没有任何生产者**，即「局内物品带回局外仓库」这条链路实际未实现。
- **跨局持久化策略**：`PlayerWallet`（`core/autoloads/player_wallet.gd:19`）、`PlayerProgression`（`core/progression/player_progression.gd:17`）、`PlayerLevel`（`core/progression/player_level.gd:26`）三者的 `PersistAcrossRuns` 均为 `false`；`GlobalWarehouse` 是 autoload，其**内容**在本次运行内跨场景保留。
- **技能卡即物品**：`SkillCardData` 继承 `ItemData`（`resources/item/card/skill_card_data.gd:1`），单张占一槽（同文件 `:35`），因此技能卡天然可以放进背包与出战卡组。
- **既有选卡界面的可复用范式**：天赋系统已是「暂停 + 洗牌 + 展示 N 张 + 点选回调」的实现（`resources/talents/talent_manager.gd:60`、`:72`、`:50`），生产技能卡资源共 69 张（`resources/skill_cards/*.tres`）。

## Source Requirements

本父任务的源需求即用户原始要求，逐条映射到子任务：

| 源需求 | 内容 | 承接子任务 |
| --- | --- | --- |
| SR-1 | 每局游戏开始时初始化角色以及其背包，只带入仓库里选择带入游戏的物品 | `09-23-run-start-loadout-init` |
| SR-2 | 游戏开局触发技能卡抽取，抽取五张技能卡，玩家选择并获取其中两张 | `09-23-run-start-skill-card-draft` |

## Task Map

- `09-23-run-start-loadout-init` —— 开局角色与背包初始化：建立唯一的开局初始化入口，按带入栏重建背包，并解除当前与调试开局配置的冲突。
- `09-23-run-start-skill-card-draft` —— 开局技能卡抽取：抽 5 选 2 的抽取逻辑与选卡界面，挂接到开局时机。

两个子任务**可独立规划、实现、验收、归档**。父子结构不是依赖系统；若实现顺序有先后要求，写在各子任务自己的 `prd.md` / `implement.md` 中。

## Cross-Child Acceptance Criteria（集成验收，由父任务负责）

- [ ] 从主菜单点「Start」进入一局：开局序列完整执行 = ①角色与背包按带入栏初始化 → ②弹出技能卡抽取界面抽 5 选 2 → ③收起界面进入正常局内玩法。
- [ ] 两个环节**互不覆盖**：技能卡抽取的产出（2 张技能卡）在初始化之后结算，不会被初始化逻辑清掉；初始化也不会因为抽卡界面暂停/延迟而在错误时机重复执行。
- [ ] 开局流程期间游戏处于暂停或玩家不可操作状态，流程结束后才恢复操作。
- [ ] 连续重复开局（退出回主菜单再开一局）不会累积上一局的背包内容。
- [ ] `docs/游戏机制与玩法内容.md` 中存在一节完整描述「开局流程」，包含两个环节的触发时机、顺序与全部新增数值（抽取张数 5、选取张数 2、带入栏上限等）。

## Out of Scope（父任务层面明确不做）

- **不做**「局内物品带回局外仓库」的实现（`player_to_warehouse` 生产者）——当前链路为空，属于独立需求。
- **不做**跨局/跨运行存档（沿用现有 `PersistAcrossRuns = false` 策略）。
- **不做**仓库界面、商店界面本身的改造（除子任务确有必要的最小挂接点）。
- **不做**技能卡的战斗内抽牌/出牌规则（`scripts/card_scripts/deck_manager.gd` 等战斗内逻辑）。

## Open Questions

- 无（两个子任务各自持有自己的待决项；父任务层不遗留阻塞项）。

## Notes

- 本父任务由 2026-09-23 会话按 `trellis-start` 创建：用户确认**拆成两个独立任务**而非合成一个，因此采用「父任务持有需求集与集成验收 + 两个可独立归档的子任务」结构。
- 双环节共用「开局」这一时机，故必须有一个**唯一的开局初始化入口**；由 `09-23-run-start-loadout-init` 建立，`09-23-run-start-skill-card-draft` 复用它挂接触发点，避免两处各自监听场景加载导致顺序不确定。
