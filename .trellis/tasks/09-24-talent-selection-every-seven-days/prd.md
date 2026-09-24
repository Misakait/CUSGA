# 天赋选择每七天弹出与十张测试天赋卡

## Goal

让「每七天选一次天赋」这条链路在游戏中真实可用：玩家推进到第 7/14/21… 天时，游戏暂停并弹出天赋选择界面，界面视觉与动态手感对齐开局技能卡抽取界面；同时补齐 10 张可抽取的天赋卡内容，使功能能被实际观察与验证。

用户价值：天赋系统从「有代码、没有内容、也不弹出、且属性效果静默失效」的断链状态，变成一条可玩、可观察、可继续扩展的完整通路。

## Background

### 现有链路

| 环节 | 文件 | 现状 |
|---|---|---|
| 触发源 | `core/autoloads/time_system.gd:88` | 已有 `TalentSelectionTriggered`，在 `_current_day % 7 == 0` 时发出（第 7/14/21… 天）。**逻辑正确，不改**。 |
| 选择管理器 | `resources/talents/talent_manager.gd` | 订阅信号 → 暂停 → 抽 3 张卡。依赖 `@export AllTalentsPool`。 |
| 卡面视图 | `resources/talents/talent_card.gd` + `scenes/talents/talent_card.tscn` | 能显示名称/描述/图片，点击发 `OnCardClicked`；已有悬浮缩放但数值硬编码。 |
| 界面场景 | `scenes/talents/talent_screen.tscn` | 只有 1 个位置写死的 `HBoxContainer`，无遮罩/标题/提示。 |
| 效果应用 | `entities/player.gd:153` `_absorb_talent` | 订阅 `GlobalEventBus.on_player_acquired_talent` 并逐条 `Apply`。**链路完整，不改**。 |
| 效果类型 | `attribute_talent_effect.gd` / `tag_talent_effect.gd` | 属性永久加成 / 标签授予。 |

### 三处断链与一处缺陷

1. **界面未挂载**：`scenes/talents/talent_screen.tscn` 在整个生产工程里没有任何引用（只在 `tests/godot/test_inventory_component_contract.gd:62` 被当作路径常量引用），因此 `TalentSelectionTriggered` 没有生产订阅者，界面永不弹出。
2. **内容为空**：`resources/talents/` 下只有 6 个 `.gd` 与 `.uid`，**0 个 `.tres`**。即使挂上界面，池也是空的。
3. **界面是空壳**：缺少半透明遮罩、标题与提示，无法与开局技能卡抽取界面（`scenes/ui_scenes/skill_card_draft_screen.tscn`）的观感对齐。
4. **属性天赋静默失效（缺陷）**：`attribute_talent_effect.gd:52` 用 `target_player.get_node_or_null("AttributeComponent")` 取组件，但 `scenes/player_scenes/player.tscn` 的实际布局是 `Player/Components/AttributeComponent`，玩家根下**没有**这个名字的子节点。该行恒为 `null`，函数随即静默 `return`——**属性类天赋永远不生效且无任何日志**。对照 `tag_talent_effect.gd:17` 走的是 `target_player.get("TagComponent")` 属性协议，能正确命中 `player.gd:53`，因此标签类是好的。

### 不可破坏的契约

- `tests/godot/test_inventory_component_contract.gd:1593` 断言生产场景的 `AllTalentsPool` 必须为空数组 → **不能**用「在 `talent_screen.tscn` 里直接挂 10 个资源引用」的方式填池。
- 同文件 `:1524-1629` 锁定：天赋卡场景与脚本路径、`Initialize` 方法、`OnCardClicked` 信号、`TalentName`/`Description`/`TalentTexture`/`Effects` 字段名、`TalentEffect.Apply` 协议、`TagToGrant` 为 `StringName`、界面 `PROCESS_MODE_ALWAYS`。
- 同文件 `:1587,1597` 通过根下直接子节点名 `HBoxContainer` 锁定界面结构。本次界面为**有意重构**，该断言需同步更新（只改路径，不删断言，见 `design.md` 第 8 节）。
- `core/ui/hud/pause_menu.gd:42-58` 与 `docs/游戏机制与玩法内容.md:102` 记录了「天赋界面与暂停菜单共用全局暂停开关、各自只归还自己造成的那次暂停」的约定。
- `tests/godot/test_player_contract.gd:355` 的天赋用例只断言旧 C# 源文，且开头有 `CS_OPTIONAL.present()` 守卫；已核实 `resources/talents/` 下无任何 `.cs`（C# 已退役），该用例走 `skip`，修复属性效果不会与它冲突。

## Requirements

- **R1 触发**：玩家推进到第 7 天及此后每个 7 的倍数天（14/21/28…）时，天赋选择界面弹出。沿用 `TimeSystem.TalentSelectionTriggered`，不新增第二条时间通路，不改时间系统代码。
- **R2 资产**：新增 10 张天赋卡资源，全部可被抽取。每张包含非空的 `TalentName`、`Description`、`TalentTexture`，以及至少 1 条带 `Apply` 方法的效果。
- **R3 进池方式**：天赋池按目录枚举获得，使 `talent_screen.tscn` 的 `AllTalentsPool` 保持空数组；新增 `.tres` 无需改场景即可进池。
- **R4 挂载**：`talent_screen.tscn` 被实际实例化进 `Main.tscn` 的 `UI/HUDLayer/HUDRoot` 层级，与 `SkillCardDraftScreen` 同级。
- **R5 界面框架**：补齐与技能卡抽取界面一致的视觉框架（半透明遮罩 + 标题 + 卡片容器 + 提示文案）；卡面继续使用 `scenes/talents/talent_card.tscn`，不换成 `SkillCard.tscn`。
- **R6 动态效果**：卡面悬停放大、悬停置顶；视觉数值统一取自 `core/card_visual_config.gd`，与战斗手牌和开局抽卡共用同一份定义。
- **R7 悬停详情**：悬停某张天赋卡时经共享 `TooltipPanel` 显示该天赋的名称与描述，移出时隐藏；浮窗缺失只降级为警告，不阻断选择流程。
- **R8 交互**：点击任意一张卡**立即生效并关闭界面**（保持现有语义，不引入「选中 + 确认」两段式）。
- **R9 池耗尽语义**：只有被选中的那张离开池；本轮未选中的卡留在池中，下一轮仍可抽到。10 张卡依次被学完后不再弹出，且池空时记录一条可诊断日志并返回，不弹空界面。
- **R10 暂停归还**：天赋界面只归还自己在打开时造成的那次暂停（记录打开前状态），与 `pause_menu.gd`、`run_start_skill_card_draft.gd` 的既有约定一致。
- **R11 修复属性天赋**：`AttributeTalentEffect.Apply` 必须能真正取到玩家的属性组件并应用永久加成；取不到时留下警告而不是静默返回。
- **R12 内容构成**：10 张卡全部使用属性永久加成效果，覆盖基础攻防、法术、资源上限、穿透、暴击、闪避六类。**不使用标签效果、不接触入夜通道玩法。**

## Acceptance Criteria

- [x] **AC1** 运行 `Main.tscn` 并推进到第 7 天，天赋选择界面自动弹出，且游戏处于暂停状态。
- [x] **AC2** 弹出界面带半透明遮罩、居中标题与提示文案，观感与开局技能卡抽取界面一致；卡面是天赋卡场景而非技能卡场景。
- [x] **AC3** 弹出的 3 张卡都来自新增的 10 张资源，卡面显示正确的名称与描述。
- [x] **AC4** 悬停卡片时卡面放大并浮到其他卡之上，同时 `TooltipPanel` 显示该天赋的名称与描述；移出后复原并隐藏浮窗。
- [x] **AC5** 点击任意一张卡后界面关闭、游戏恢复运行，且**玩家属性数值真实变化**（可在 `Components/AttributeComponent` 上读到变化，并在游戏日志中看到「天赋生效：<属性> 永久增加了 <值>」）。
- [x] **AC6** 推进到第 14 天时再次弹出，已学过的卡不出现在可选池中，未选中的卡仍可出现。
- [x] **AC7** `resources/talents/` 下存在 10 个 `.tres`，逐个校验 `TalentName`/`Description`/`TalentTexture` 非空、`Effects` 至少 1 条且每条带 `Apply` 方法。
- [x] **AC8** `talent_screen.tscn` 的 `AllTalentsPool` 仍为空数组；`test_inventory_component_contract.gd` 与 `test_player_contract.gd` 全绿。
- [x] ~~**AC9** `env CI=true dotnet build CUSGA.sln --no-restore` 通过。~~ **作废：C# 已完全退役**，仓库内不存在任何 `.cs` / `.csproj` / `.sln`（见下方偏差 D2）。
- [x] **AC10** 改动后 `git status` 没有混入编辑器自动产生的无关改动（`.cs` 缩进、`CUSGA.csproj` 版本号）。

## 实测记录与偏差

验证均通过编辑器 MCP 完成，无一项依赖命令行 Godot。实测数值：

| 判据 | 实测值 |
| --- | --- |
| 第 7 天弹出 | `day=7`、`visible=true`、`paused=true`、`card_count=3` |
| 悬停 | `z_index 2 → 1`（移出复原）、`scale=1.05`、浮窗 `visible=true` 且标题为「疾风步」 |
| 点击生效 | PhysDef `100 → 105`（`delta=5`）、界面 `visible=false`、`paused=false` |
| 池语义 | 池 `10 → 9`，已学的「疾风步」不在池中，第 14 天抽出的 3 张也不含它 |
| 第 14 天 | `day=14`、`visible=true`、`paused=true` |

**D1 — 运行验证必须用 `mode="custom"`，不能用 `mode="main"`。**
`project.godot` 的 `run/main_scene` 是 UID 引用 `uid://qwckbjjp11ca`，它指向的是**主菜单** `scenes/main_menu_scenes/main_menu.tscn`（见 `README.md:92`），而不是 `Main.tscn`。用 `mode="main"` 起的是主菜单，`/root/Main` 根本不存在，`game_eval` 会以 `Node not found` 失败。正确入口是 `project_run(mode="custom", scene="res://scenes/Main.tscn")`。

**D2 — `AC9` 的编译步骤不适用。**
本机检出中已无任何 C# 产物（`**/*.cs`、`**/*.csproj`、`**/*.sln` 均为 0 个匹配），`dotnet build CUSGA.sln --no-restore` 报 `MSB1009: 项目文件不存在`。这也意味着 `AC10` 关心的两类编辑器副产物（`.cs` 缩进、`CUSGA.csproj` 版本号）已不可能出现。**AGENTS.md 中该条命令已过时**，建议后续修订。

**D3 — 编辑器自动补全了一处 `uid`。**
`scenes/talents/talent_card.tscn` 的脚本 `ext_resource` 被编辑器自动补上 `uid="uid://vsqi24bi2ils"`。该改动无害且与 `Main.tscn` 现有风格一致，予以保留。

**D4 — `Main.tscn` 被编辑器 autosave 补全了一批等价属性。**
`project_run(autosave=true)` 会把编辑器内存中的场景状态写回磁盘，于是 HEAD 里缺失的一批 overridden 属性被补上（`Player.script`、`InventoryUI`/`CraftingUI`/`WarehouseUI` 的 `type`/`script`/`SlotPrefab`/`custom_minimum_size` 等）。这些值与各自实例化场景根节点的默认值相同，属等价序列化，非行为变更（补全前的全量测试 386 项通过即为佐证）。同时它删掉了我给 `TalentScreen` 加的 `layout_mode = 1`——该属性对当时的 `CanvasLayer` 根节点本就无意义，删除是正确清理。一并保留。

## 修复轮次 2（用户实机验收反馈）

用户复看后报告两处观感缺陷，均已修复并回归验证：

**F1 — 天赋卡描述被截断。**
`talent_card.tscn` 的 `DescText` 原本是写死的 `113×40` 像素矩形，而描述文本实际需要 90 高，被静默裁掉约一半（`desc_clipped: true`）。改为锚定卡片右下（`anchor_right/bottom = 1.0`，左右各留 40px）并开启 `autowrap_mode = 3`。实测 `need=46 have=190 w=220`，三张卡 `clipped_cards: []`。

**F2 — 悬停详情浮窗被遮罩盖住。**
天赋界面原本是 `CanvasLayer`（`layer = 1`），与 `HUDLayer`（同为 `layer = 1`）同层却后进树，绘制压在共享浮窗 `TooltipPanel` 之上。修法是两点：把天赋界面根节点改为 `Control`（与开局技能卡抽取界面同范式），并把 `TooltipPanel` 的声明移到 `TalentScreen` 之后，让绘制顺序回归"同层兄弟按声明次序"。

**未采用的方案**：把 `TooltipPanel` 移进独立的高 layer CanvasLayer。`status_effect_bar.gd:152` 与 `status_bar_binding_tests.gd:33,55` 表明浮窗依赖随 `HUDLayer.hide()` 一起退场（战斗切换机制），移出该层会让它在战斗中残留。改为 `Control` 后该行为原样保留，实测 `hidden_with_hud: true`。

**这一轮改动的连带**：根节点类型变更使 `test_inventory_component_contract.gd` 中两处 `instantiate() as CanvasLayer` 失效，已同步改为 `as Control`（该断言锁定的正是根节点类型，属于本次有意变更的一部分）。另新增 3 条防回归断言：浮窗必须声明在天赋界面之后、根节点必须是 `Control` 且 `process_mode == ALWAYS`、描述区必须自动换行且锚定到右下。

**回归结果**：全量 `test_run` **424 项 / 389 通过 / 33 跳过 / 2 失败**，两条失败均与修复前完全相同（C# 配方脚本迁移遗留、`map_control.tscn` 自身的 uid 声明），无新增回归；通过数 386 → 389 正是新增的 3 条测试。实机复测完整链路：点击后属性 `100 → 105`、界面关闭、暂停归还（下一轮 `_was_paused_before_open` 为 `false` 佐证）、池 `10 → 9`、第 14 天再次弹出且不含已学卡。

## Out of Scope

- 天赋的稀有度、等级需求、互斥、洗练、重置等进阶机制。
- 天赋界面的美术重做（卡面继续使用现有 `talent_card.tscn` 布局与节点结构）。
- 标签类天赋的资产与玩法接线：本次不含标签效果卡；`HomeProtectionTag` 与入夜通道逻辑保持现状，不做配置。
- 把天赋接入存档 / 跨局持久化。
- 暂停菜单与天赋界面叠加时的 UI 层级重排（沿用现有「共用全局暂停开关」约定）。
- 用命令行 `godot-mono` 做验证（AGENTS.md 已声明该路径在本机不可用）。

## Key Decisions

| # | 决策 | 依据 |
|---|---|---|
| D1 | 创建 Trellis 任务并先规划 | 用户明确选择 |
| D2 | 10 张卡**进生产池**，让功能真的能跑起来看到效果 | 用户明确选择；因此用目录枚举而非场景内引用 |
| D3 | 交互为「点击立即生效」 | 用户明确要求 |
| D4 | 卡面外观保留天赋卡自己的场景，但动态效果与悬停详情对齐技能卡 | 用户明确要求 |
| D5 | 池耗尽语义：未选中回池、学过的移除 | 用户明确选择 |
| D6 | 第 10 张卡改为属性效果，不接触入夜通道 | 用户明确要求 |
| D7 | 不改 `time_system.gd` 的 `% 7` 判定 | 逻辑已正确，改动只扩大风险面 |
| D8 | 更新界面结构契约断言而非保留旧结构 | 界面重构是本次的明确需求；只改路径不删断言并净增防护 |
