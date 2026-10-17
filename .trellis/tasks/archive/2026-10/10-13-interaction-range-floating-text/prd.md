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

---

# 增量（2026-10-14）：所需交互范围提示圈

> 用户追加需求：给「距离不够！」飘字组件**附加一个额外组件**，用来显示**所需的距离范围** ——
> 以目标物品为中心的**空心圈**，灰色半透明，出现后随「距离不够！」一起逐渐变透明消失，
> **与字体同步出现和消失**。覆盖范围经用户确认：**棋盘卡与建筑都显示**。

## Goal（增量）

在飘出「距离不够！」的**同一瞬间**，以该交互目标为中心画一个半径等于**所需交互距离**的空心圈，
让玩家一眼看出「该站到哪个范围内才能交互」，而不是只被告知「不够」。

## Source Requirements（增量）

| 编号 | 用户原话要点 | 对应验收 |
| --- | --- | --- |
| SR-10 | 给飘字组件附加一个额外组件，显示所需的距离范围 | AC-19 / AC-23 |
| SR-11 | 以目标物品为中心，空心圈，灰色半透明 | AC-20 / AC-21 |
| SR-12 | 随「距离不够」字体逐渐变透明消失，与字体同步出现和消失 | AC-22 |

## Acceptance Criteria（增量）

- [ ] **AC-19** 棋盘卡因距离超出 `InteractionRange` 被拒绝时，「距离不够！」飘字**同时**出现一个提示圈；两者由同一次调用产生，结构上不可能只出现其中一个。
- [ ] **AC-20** 圈心是交互目标的屏幕坐标（棋盘卡图标中心 / 建筑世界坐标），半径等于该交互的**所需距离**换算到屏幕的像素值：棋盘卡取 `InteractionRange`，建筑取该建筑 `data` 的 `InteractionRadius`。
- [ ] **AC-21** 圈是**空心**的（只描边、不填充），线色为灰色半透明，在任意地形贴图上可见。
- [ ] **AC-22** 圈的淡出与飘字使用**同一时长、同一缓动曲线**（`DURATION` + `TRANS_SINE`/`EASE_IN`），两者同时开始变透明、同时消失；圈播完自动 `queue_free`，不残留在场景树中。
- [ ] **AC-23** 圈**不随飘字上飘**：它必须始终以目标为中心，否则「所需范围」的语义会随动画漂移。
- [ ] **AC-24** 圈半径按**画布缩放**（相机 zoom）换算：地形卡自身有入场缩放与散布动画，用卡牌自己的 `scale` 会让圈随卡面动画胀缩；而交互距离是「玩家中心 → 目标中心」的世界距离，与目标的表现缩放无关。
- [ ] **AC-25** 同帧双发去重对**圈与字一并生效**：一次左键点击只出现一条飘字**和**一个圈；去重判定发生在生成任何节点之前。
- [ ] **AC-26** 既有契约测试全部继续通过（`test_interaction_range_gate`、`test_floating_text_contract` 的原断言逐条保留）。
- [ ] **AC-27** 建筑回归场景 `res://tests/godot/building_system_tests.tscn` 仍输出 `0 项失败`。
- [ ] **AC-28** Main 场景冒烟无 `SCRIPT ERROR` / `Parse Error` / `Failed to load script`；用 `game_eval` 断言圈的颜色、线宽、半径、空心与非残留，并截图确认。

## Out of Scope（增量）

- **不做**建造落点超 `PlacementRadius` 的范围圈：该路径的文案是「离角色太远了」而不是「距离不够！」，不属于本次要改的组件；要覆盖应另开需求。
- **不做**伤害数字、经验飘字等其它用途的圈。
- **不做**圈的美术资源化（不新增贴图或 shader，直接用 `draw_arc` 画）。
- **不改** `InteractionRange` / `InteractionRadius` / `PlacementRadius` 的数值与语义。
- **不改** `core/board/board_card_view.gd`、`core/building/building_view.gd` 等目标表现脚本。

## Notes（增量）

- 圈与字**必须由同一次 `_spawn` 产出**：`_spawn` 是唯一的去重门禁，把圈拆成第二次调用会让同帧双发叠出两个圈，也会失去「要么都有、要么都没有」的结构性保证。为此 `show_at_target` / `show_at_world` 追加**可选的第 4 个参数** `world_radius`（默认 `0.0` 表示不画圈），既有 3 参数调用点保持可用。
- **参数顺序的取舍**：半径排在颜色**之后**。这样建筑的飘字漏斗 `_show_world_floating_text` 与服务参数顺序逐位对齐，不存在静默换序的风险；代价是协调器只传半径时必须先给出颜色，因此协调器新增一个与服务 `DEFAULT_TEXT_COLOR` 同值的镜像常量。工程内已有同样做法的先例（`building_controller.gd` 的 `FAILURE_TEXT_COLOR`），权威定义仍在服务里。反过来「半径在前、颜色在后」虽然省掉这个常量，却会逼出一个静默的参数换序点，风险更高。
- 本次增量不改变飘字的文案、颜色、字体、描边、上飘距离与去重窗口，只**附加**一个新组件与它的半径入口。

# 增量（2026-10-14 第二轮）：圈与字必须锁定在交互目标处

## Goal（增量二）

飘字与提示圈在**整个播放期间**始终贴在交互目标上。相机移动（玩家走动，`PlayerChar/Camera2D` 跟随）时，圈与字必须跟着目标一起在屏幕上移动，而不是留在生成时的屏幕位置上被目标甩掉。

## Background（增量二，已核实事实）

- 症状根因：`FloatingText` 挂在 `CanvasLayer(10)` 上，属于**屏幕空间**；`_spawn` 只在生成的那一帧把锚点算成屏幕坐标（`_resolve_target_screen_position(target)` / `viewport.get_canvas_transform() * world_position`），之后标签与圈的 `position` 再没有任何更新。而飘字时长 `DURATION = 0.9s`，玩家在这 0.9 秒里继续走动时，世界中的目标随相机变换持续改变屏幕坐标，圈与字却停在原地——表现为**从目标身上滑走**。
- 相机确实会持续移动：世界相机是 `PlayerChar/Camera2D`（`scenes/player_scenes/PlayerChar.tscn:228`，`PlayerChar.gd:4` 持有；`world_interaction_coordinator.gd:1234` 会 `make_current()`）。`tests/godot/test_day_night_filter_contract.gd:185` 也把「跟随玩家的 Camera2D」写成既有事实。
- 棋盘卡与建筑都挂在**默认世界画布**上（前一轮增量已核实），因此 `target.get_screen_transform()` / `target.get_canvas_transform()` 对两者都成立。
- 提示圈的半径是**世界距离**，因此相机缩放（`Camera2D.zoom`）变化时半径也应同步换算，不能只在生成时算一次。

## Source Requirements（增量二）

- **SR-13**：圈与字的屏幕坐标必须在**播放期间每帧重新求值**，来源是同一个交互目标（或同一个世界坐标）。
- **SR-14**：目标在播放途中被卸载/离树时，圈与字**沿用最后一次有效坐标**原地淡出，不得跳到鼠标位置、`(0,0)` 或屏幕外。
- **SR-15**：提示圈的半径必须在播放期间按当前画布缩放重新换算（世界半径不因相机 zoom 改变），且仍然**不得**使用目标自身的 `scale`。
- **SR-16**：公开入口 `show_at_target` / `show_at_world` 的签名与全部调用方**保持不变**，调用方零改动。
- **SR-17**：「世界 → 屏幕」的换算逻辑只能存在于**一处**，不得在标签与圈里各抄一份。

## Acceptance Criteria（增量二）

- **AC-29**：播放中改变相机（平移画布变换）后，圈的 `position` 与字的中心仍等于目标当前屏幕位置（容差 1px）。
- **AC-30**：播放中改变相机缩放后，圈半径仍满足 `世界半径 × 当前画布缩放`。
- **AC-31**：目标在播放途中 `queue_free()` 后，圈与字**不报错**，并保持最后一次坐标直到淡出结束、正常释放。
- **AC-32**：`show_at_target` / `show_at_world` 的前两行签名逐字不变；协调器与建筑控制器的调用点零改动；既有 `_count_occurrences(coordinator, "_show_out_of_range_floating_text(card)") == 1` 仍成立。
- **AC-33**：`_resolve_target_screen_position` 与 `_world_to_screen_scale` 从服务中移除后，服务里不再残留任何屏幕坐标换算；换算只在锚点对象里实现一次。
- **AC-34**：圈与字在同一次 `_spawn` 内产出、共用同一个锚点对象（结构性保证「要么都锁在目标上、要么都没有」）。

## Out of Scope（增量二）

- 不改飘字时长、上飘距离、文案、颜色、字体、描边与去重窗口。
- 不改 `CanvasLayer(10)` 的层号与「屏幕空间承载」这一架构选择（改为世界空间会让文字随相机 zoom 一起放大）。
- 不改 `combat_feedback_director.gd` 的战斗飘字（独立系统，不在本任务范围）。
- 不修「目标离屏时应否隐藏飘字」——本轮只保证它锁在目标处。

## Notes（增量二）

- 术语：**锚点（anchor）** 指「如何在任意时刻求出圈与字的屏幕坐标」，而不是某一帧算出的那个 `Vector2`。重构的实质就是把后者换成前者。
- 目标失效用**缓存最后一次坐标**而不是回退鼠标：飘字是 0.9 秒的短命表现，中途跳位比停在旧位置更像故障；而生成时就已经失效的目标仍保留原有的鼠标兜底（与重构前行为一致）。
- 组件依然**不依赖任何 autoload**：锚点是一个普通 `RefCounted`，由服务构造后注入，组件只调用它的方法。

---

# 增量（2026-10-14 第三轮）：改为世界坐标定位，废弃「每帧重算」

> 用户对增量二的实现提出否决：「这种方法太蠢了吧！没有不用每帧重新求值吗！只需要确定一个位置就可以了！
> 只要显示在世界上就好了！不用让他在屏幕计算世界的位置！」
>
> 该意见成立。增量二的实质是在**屏幕空间里手工模拟世界空间**：把「跟随相机」这件引擎本来就会做的事，
> 变成了组件自己的每帧职责。本增量**整体废弃增量二的做法**。

## Goal（增量三）

飘字与提示圈在**播放期间不执行任何每帧逻辑**，位置只在生成时按**世界坐标**写一次；
相机平移与缩放全部由引擎的相机变换负责。

## Background（增量三，已核实事实）

- `CanvasLayer.follow_viewport_enabled = true` 时，该层的画布变换与 `viewport.get_canvas_transform()`
  **完全相等**（实测 `host.get_canvas_transform() == viewport.get_canvas_transform()` 为 `true`），
  因此层内子节点的 `position` 直接就是**世界坐标**，且**保留层号带来的绘制顺序**。
- 本项目**没有任何代码修改 `PlayerChar/Camera2D.zoom`**：`rg "zoom"` 的全部命中都属于小地图
  （`UIMiniMap.gd`、`UIOptionPanel.gd`）、大地图平移缩放（`UIMapPanZoomController.gd`）与悬停缩放。
  因此增量二「改为世界空间会让文字随 zoom 一起放大」这条否决理由**并不成立**。
- 承载层 `layer = 10` 必须继续高于 `UI/HUDLayer(2)` 与 `DayNightFilterLayer(0)`：
  若改为把飘字挂进世界画布的普通节点下，飘字会掉到 HUD 面板与昼夜滤镜**下面**。
  `follow_viewport_enabled` 让「世界坐标定位」与「独立层级」**同时**成立。

## Source Requirements（增量三）

| 编号 | 要点 |
| --- | --- |
| SR-18 | 飘字与提示圈**不得**包含任何每帧逻辑（无 `_process`、无逐帧 `resolve()`）。 |
| SR-19 | 位置的**唯一**来源是一个世界坐标，只在生成时写入一次。 |
| SR-20 | 相机平移与缩放期间，圈与字仍贴在目标上；圈半径仍等于所需交互距离（世界单位）。 |
| SR-21 | 公开入口与调用方零改动；层号与绘制顺序不变（仍在 HUD 与昼夜滤镜之上）。 |

## Acceptance Criteria（增量三）

- [ ] **AC-35** 两个表现组件均不含 `func _process(`；运行期 `ring.is_processing()` 与 `label.is_processing()` 均为 `false`。
- [ ] **AC-36** 移动相机后，圈的**世界坐标一字未改**，而其**屏幕坐标与目标逐位相等（漂移 `0.0px`）**。
- [ ] **AC-37** 圈的 `position` 与目标的 `global_position` 相等（证明宿主无偏移、坐标确为世界坐标）。
- [ ] **AC-38** `_process` / `_refresh` / `FloatingTextAnchor` / `_rise` / `PROCESS_PRIORITY_LATE` / `_world_to_screen_scale` 全部从代码库中消失。
- [ ] **AC-39** 目标在播放途中 `queue_free()` 时**不需要任何专门处理**：圈保持其世界坐标、不报错、正常淡出。
- [ ] **AC-40** 运行期断言 `layer = 10 > HUDLayer(2) > DayNightFilterLayer(0)`。
- [ ] **AC-41** 增量一的行为全部不回归：无半径只出字、同帧双发去重、同步淡出、自释放、宿主归零。

## 取代关系（重要）

- 增量二 `Out of Scope` 中「不改屏幕空间承载（改为世界空间会让文字随相机 zoom 一起放大）」**作废**：
  该理由经核实不成立（本项目无相机 zoom 变更），且世界空间正是本增量采用的方案。
- 增量二的 SR-13～SR-17 与 AC-29～AC-34 中关于「每帧重新求值」「共用同一个锚点对象」
  「缓存最后一次有效坐标」的表述**全部作废**，由 SR-18～SR-21、AC-35～AC-41 取代。
- 增量二仍然有效的结论只有一条：**半径是世界距离，与目标自身的表现缩放无关**
  （现由「不做任何换算」从结构上保证，不再依赖换算函数）。
