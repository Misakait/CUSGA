# 交互距离不足飘字提示组件

## Goal

当玩家用鼠标点击或长按一个**交互目标**、而交互因**距离不足**被拒绝时，在**该交互目标处**显示一条红色、带黑色描边的飘字提示「距离不够！」。

同时，把建筑的**全部离散失败/结果提示**从屏幕底部的 `BuildingHint` 标签统一改到新的飘字组件上，让「建筑提示」和「棋盘卡提示」使用同一套表现。

必须满足四条硬约束：

1. **使用游戏的字体** —— 工程内唯一的字体资源 `res://res/font/Uranus_Pixel_11Px.ttf`，且该字体确实含所需汉字。
2. **红色 + 黑色描边** —— 正文红色，四周黑色描边，保证在任何地形贴图上都可读。
3. **组件化、解耦、可复用** —— 飘字能力做成独立组件；组件**自己读取目标坐标**，**不修改任何交互目标的代码**（`BoardCardView`、建筑视图脚本都不动）。
4. **建筑提示统一** —— 建筑不再用底部标签播报失败/结果，改由同一飘字组件在建筑处或落点处播报。

## Background（已核实事实，带证据锚点）

### 现状缺口

- `core/gameflow/world_interaction_coordinator.gd:421` 的 `_report_out_of_range_interaction()` **只 `print` 调试日志**，玩家在画面上看不到任何反馈。这是本次要补的核心缺口。
- 该函数是两个鼠标入口的**单一漏斗**：`_on_board_card_clicked`（`:457`，掉落拾取 + 零耗时地形交互）与 `_on_board_card_pressed`（`:544`，可长按地形）。契约测试 `tests/godot/test_world_interaction_coordinator_contract.gd:480` 已锁定「点击与长按两个交互入口都必须先做距离判定」，本次改动不得破坏该断言。

### 必须处理的坑（已核实）

- **同帧双发**：`core/board/board_card_view.gd:161-166` 在**一次**左键按下里先 `Pressed.emit(self)`、紧接着 `Clicked.emit(self)`。因此朴素接入会在同一帧生成**两条完全重叠**的飘字，必须在组件层去重。
- **每帧函数不能挂飘字**：`core/building/building_controller.gd:288` 的 `_placement_failure()` 返回「离角色太远了」，但该函数**每帧**被 `_process:235` 调用做落点预览。飘字只能挂在真实左键提交入口 `_confirm_placement:264`，否则会每秒刷出几十条。
- **距离与遮挡被合并**：`core/building/building_controller.gd:359` 的 `_is_record_reachable()` 把「距离不足」和「被遮挡」压成同一个 `false`，调用方 `:422` 只能给出合并文案「请靠近建筑，并确保中间没有障碍」。要只在**距离不足**时飘「距离不够！」，必须先能区分二者。
- **契约测试会因注释变红**：`test_interaction_range_gate` 断言协调器源码**不含** `_card_display_name(`（名字 + 左括号）。本次新增的注释与代码都不得写出这个字面量。

### 目标坐标可以自读（支撑「不修改目标代码」）

- `scenes/board_card_scene/BoardCardView.tscn` 的根 `Area2D`、`Icon`（Sprite2D，默认居中）、`CollisionShape2D` **全部位于原点** ⇒ 卡牌原点就是图标中心，`get_screen_transform().origin` 直接就是「交互目标处」的屏幕坐标，无需目标暴露任何新协议。
- 建筑侧用 `record["position"]`（房间局部）经 `_room_scene.to_global()` 得到世界坐标，同样不需要建筑视图实现任何接口。

### 已验证的世界 → 屏幕换算范式（复用，不新造）

- `core/ui/hud/world_hold_progress_indicator.gd:101-113` 用 `CanvasItem.get_screen_transform()` 把世界目标锚到 HUD CanvasLayer，已被 `tests/godot/world_hold_interaction_tests.gd` 覆盖。飘字沿用同一口径。

### 字体可用性（本次实测，非推测）

- 解析 `res/font/Uranus_Pixel_11Px.ttf` 的 cmap：共 **7610** 个码位，其中 **6769** 个 CJK 统一表意文字。
- 逐字验证：`距`U+8DDD ✅、`离`U+79BB ✅、`不`U+4E0D ✅、`够`U+591F ✅、全角`！`U+FF01 ✅。
- 工程内**只有这一个**字体文件（`res/font/` 下仅 `Uranus_Pixel_11Px.ttf`），且多处场景以 `FontFile` 直接引用它 ⇒ 它就是「游戏的字体」。

### 建筑现有提示机制（本次要重构的对象）

- `core/building/building_controller.gd` 用 `@export FeedbackSeconds`（`:37`，默认 2.5 秒）+ `_feedback`/`_feedback_left`（`:72`/`:74`）实现一个「离散结果提示」计时器，由 `_show_feedback(message)`（`:619`）写入、由 `_process` 渲染到 `_hint`（`HintPath` → `UI/HUDLayer/HUDRoot/BuildingHint`，`scenes/Main.tscn:165`）。
- `_show_feedback` 共 **8 个调用点**：`:218`（F 键交互结果）、`:266`/`:271`/`:279`（建造提交三处）、`:422`/`:427`/`:434`（拆除开始三处）、`:471`（拆除完成结果）。
- 提示文案**同时包含成功与失败**：`core/building/building_service.gd` 返回 `"已放置 %s"`（`:58`）、`"已拆除 %s"`（`:121`）等成功文案，以及 `"这里已有建筑"`（`:32`）、`"这座建筑不能拆除"`（`:108`）等失败文案。因此**不能一律用红色**，必须按 `success` 分色。
- `_hint` 还承担**每帧实时状态**：建造预览说明 + 失败原因（`:238-240`）、拆除进行中（`:250`）、F 交互提示（`:255`）。这三类是持续状态，不是离散提示。
- 测试影响面（已核实）：`tests/godot/building_system_tests.gd` 会 `preload` 并**继承** `building_controller.gd`（`:11`、`:84`），注入 `HintPath` 为真实 `Label`（`:354`、`:361`），并直接调用 `_unhandled_input`、`_input`、`_begin_demolition`、`_process`、`_placement_failure`、`_complete_demolition`。该文件**没有任何**对 `FeedbackSeconds` / `_feedback` / `_hint.text` 的断言（全仓 `rg` 已确认），因此移除计时器不破坏它。
- 场景序列化面（已核实）：`scenes/Main.tscn` 的 `BuildingController` 节点**只序列化 `script`**，没有 `FeedbackSeconds`；全仓 `.tscn` 均未序列化 `FeedbackSeconds` / `InteractionRange` / `HintPath`。因此删除该导出不会留下失效的场景字段。
- 文档影响面：`docs/建筑系统.md:37` 有 `| FeedbackSeconds | 2.5 秒 | 一次结果提示的显示时长 |`，必须同步更新。

### 层级与全局服务现状

- `scenes/Main.tscn`：`DayNightFilterLayer` = `layer 0`、`UI/HUDLayer` = `layer 2`（`MapSystem` 的 CanvasLayer 在实例场景内，规范记为 1）。飘字层必须高于 HUD，取 `10`。
- `project.godot` 的 `[autoload]` 现有 15 项，**第一项是 `SaveManager`**（`:34`，紧随 `[autoload]` 之后），最后一项是 `_mcp_game_helper`。没有任何飘字/提示类全局服务。
- **硬约束**：`test_run` 环境**没有 autoload**。调用方不得直接书写 autoload 标识符，必须 `const X_PATH: NodePath = ^"/root/X"` + `get_node_or_null`，否则脚本连解析都过不去（`.trellis/spec/frontend/state-management.md:136`）。

## Source Requirements

| 编号 | 用户原话要点 | 对应验收 |
| --- | --- | --- |
| SR-1 | 鼠标点击交互时，距离不够则在交互目标处飘字 | AC-1 / AC-2 / AC-5 |
| SR-2 | 文案「距离不够！」 | AC-1 / AC-5 |
| SR-3 | 使用游戏的字体 | AC-3 |
| SR-4 | 附加黑色描边 | AC-4 |
| SR-5 | 以组件形式实现，尽量解耦且可复用 | AC-6 / AC-7 |
| SR-6 | 不修改目标代码，组件直接取目标坐标 | AC-7 / AC-8 |
| SR-7 | 建筑的距离提示也统一成新增的提示方式 | AC-5 / AC-9 |
| SR-8 | 建筑全部失败提示都改飘字 | AC-9 / AC-10 |
| SR-9 | 只改离散失败提示，保留实时状态 | AC-11 |

## Acceptance Criteria

### 功能

- [ ] **AC-1** 棋盘卡交互（掉落拾取 / 地形采集 / 可长按地形）因距离超出 `InteractionRange` 被拒绝时，在**该卡牌图标中心处**出现红色文字「距离不够！」。
- [ ] **AC-2** 一次左键点击**只出现一条**飘字；不得因为 `Pressed` 与 `Clicked` 同帧双发而叠出两条。
- [ ] **AC-3** 飘字使用 `res://res/font/Uranus_Pixel_11Px.ttf` 渲染，「距离不够！」五个字全部正常显示，无豆腐块/空白。
- [ ] **AC-4** 飘字为红色正文 + 黑色描边。
- [ ] **AC-5** 建筑的距离不足统一使用与棋盘卡**相同**的文案「距离不够！」：
  - 左键确认建造但落点超出 `PlacementRadius` → 在**鼠标落点**处飘「距离不够！」；
  - 左键按下拆除但建筑超出 `InteractionRadius` → 在**该建筑世界坐标处**飘「距离不够！」。
- [ ] **AC-6** 飘字出现后向上飘升并淡出，播完自动释放节点，不残留在场景树中。

### 建筑提示统一

- [ ] **AC-9** `building_controller.gd` 中**全部 8 个** `_show_feedback(...)` 调用点改为飘字，锚点规则：
  - 与具体建筑相关（拆除开始 / 拆除完成 / F 键交互）→ **该建筑的世界坐标**；
  - 与落点相关（建造提交）→ **鼠标世界落点**。
- [ ] **AC-10** 飘字按 `result["success"]` **分色**：成功为白色（沿用底部标签原本的观感），失败为红色。不得把「已放置 / 已拆除」这类成功文案显示成报错红。
- [ ] **AC-11** 移除离散提示计时器：删除 `@export FeedbackSeconds`、`_feedback`、`_feedback_left` 及其全部读写点；`_hint` **保留**并继续承担每帧实时状态（建造预览说明与失败原因、拆除进行中、F 交互提示），不得改成飘字。
- [ ] **AC-12** 拆除的遮挡分支不再复用合并文案：距离不足走「距离不够！」，纯遮挡走只讲障碍的文案（原「请靠近建筑，并确保中间没有障碍」在距离充足时会误导玩家「靠近」）。
- [ ] **AC-13** `docs/建筑系统.md` 中 `FeedbackSeconds` 所在行同步更新，不留失效参数说明。

### 解耦与复用

- [ ] **AC-7** 飘字能力是一个独立组件，具备可被任意系统调用的公开入口；调用方只传「目标/坐标」与「文案」，不需要知道字体、描边、Tween、层级中的任何一项。
- [ ] **AC-8** `core/board/board_card_view.gd`、`core/building/building_view.gd` 及任何建筑表现脚本 **零改动**；组件通过读取目标的变换或世界坐标自行求屏幕位置。

### 回归与验证

- [ ] **AC-14** 既有契约测试继续通过，特别是 `test_world_interaction_coordinator_contract.gd::test_interaction_range_gate`（含「协调器源码不得出现 `_card_display_name(`」这条）。
- [ ] **AC-15** 建筑系统回归场景 `res://tests/godot/building_system_tests.tscn` 输出 `0 项失败`（该文件被 `building_controller.gd` 的改动直接覆盖，必须实跑）。
- [ ] **AC-16** 新增的契约测试套件通过 `test_run` 全绿。
- [ ] **AC-17** Main 场景冒烟：无 `SCRIPT ERROR` / `Parse Error` / `Failed to load script`；用真实鼠标输入复现「距离不足」并截图确认飘字的位置、颜色与描边。
- [ ] **AC-18** 验证结束后 `git status` 只包含本次任务需要的改动，Godot 编辑器改写的版本控制文件不得被覆盖。

## Out of Scope

- **不做** F 键建筑交互在**距离不足**时的提示。该路径由 `_nearest_building()` 静默跳过超范围建筑，`record.is_empty()` 时直接返回（`building_controller.gd:211-212`），因此**不存在**距离不足的 F 键分支可提示。F 键的**服务结果**提示按 AC-9 改飘字，但距离门禁语义不变。
- **不做** 建筑**每帧实时状态**的飘字化（建造预览说明与失败原因、拆除进行中、F 交互提示）。这三类每帧刷新，改飘字会持续刷屏（AC-11）。
- **不做** 伤害数字、经验飘字、拾取数量等其它飘字用途的接入 —— 只把组件做成可复用，不主动接别的调用方。
- **不做** 飘字的美术资源化（不新增字体、贴图或动画资源）。
- **不改** `InteractionRange` / `InteractionRadius` / `PlacementRadius` 的数值与语义。
- **不重构** `_is_record_reachable()` 的遮挡判定逻辑；只把「距离」这一段提取成可单独查询的入口，行为保持逐位等价。
- **不复用** 战斗浮字节点 `CombatFeedbackPopup`。这是一个**有意识的取舍**，理由见 Notes。

## Open Questions

无。用户已在会话中确认：接入方式选 **autoload 服务**；覆盖范围为**棋盘卡 + 建筑**；浮字节点**新建独立组件**而非复用 `CombatFeedbackPopup`；建筑**只改离散失败提示**、保留每帧实时状态；视觉参数沿用设计原值。

## Notes

### 关于「不复用 CombatFeedbackPopup」的有意识取舍

`.trellis/spec/frontend/component-guidelines.md:38` 要求「复用已有提示节点和 Presenter 协议；不要为同一种提示创建第二套全局系统」。工程内确实已有一个浮字节点：`scripts/battle_scripts/combat_feedback_popup.gd`（`class_name CombatFeedbackPopup`，自我文档为「可复用的战斗浮字节点」），它已实现上飘 + 淡出 + 描边 + 屏幕坐标定位 + 对象池回收。

**用户明确选择新建独立组件**，取舍理由（已向用户呈现并确认）：

- **风险隔离**：`CombatFeedbackPopup` 被战斗结算链使用，其常量（暴击描边宽度、击杀下划线）与生命周期（由 `CombatFeedbackDirector` 对象池持有、不自行释放）都为战斗调优。要让它服务世界提示，必须新增字体/字号/描边色/描边宽度四个覆盖入口并改写 `play_feedback` 的样式施加逻辑，等于把一个战斗组件改成通用组件。
- **生命周期不同**：战斗浮字由导演池化复用；世界提示是低频、瞬时的，自行释放更简单。
- **职责域不同**：战斗伤害数字与世界交互提示是两类提示语义（数字随伤害值缩放/变色 vs. 固定文案）。

**代价必须被记录**：工程内因此存在两个浮字节点类型。后续若要收敛，应在不影响战斗表现的前提下把两者统一到 `core/ui/` 下的共享节点，并把战斗专属特性（下划线、强调描边、多段延迟）做成可选配置。本任务**不做**这次收敛，但把它记为已知技术债。

### 其它

- 本任务由 2026-10-13 会话经 `trellis-start` 创建。用户明确要求「尽量采用解耦的方式，不修改目标代码，例如可以直接获取目标的坐标来生成」，因此组件定位为**自取坐标的服务**，而不是要求目标实现接口的协议。
- 任务复杂度判定：**复杂**（跨 3 个生产脚本 + 1 个文档、新增 autoload、需要区分距离与遮挡、有同帧双发去重需求、需要按成功/失败分色），因此除 `prd.md` 外还必须产出 `design.md` 与 `implement.md`。
- 提示文案由**调用方**传入，不写死进组件；组件只负责渲染。这样同一组件可复用于其它提示文案。
