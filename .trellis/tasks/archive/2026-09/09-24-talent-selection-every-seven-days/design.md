# 技术设计：天赋选择每七天弹出与十张测试天赋卡

## 1. 为什么是这三处改动

原始请求是「检查每七天选择一次天赋的相关代码，制作十张天赋卡，实装每七天跳出一次天赋选择，界面模仿开局技能卡选择界面」。核实后，这条链路上真正缺失的只有三处，其余环节已经可用：

| 环节 | 结论 |
|---|---|
| 触发逻辑 | **已存在且正确** —— `time_system.gd:88` 在 `_current_day % 7 == 0` 时发信号 |
| 选择管理器 | **已存在**，只依赖 `AllTalentsPool`，需要补池来源与暂停归还 |
| 效果应用 | **已存在** —— `player.gd:153` → `effect.Apply(self)` |
| 界面挂载 | **缺失** —— `talent_screen.tscn` 无任何生产引用 |
| 内容资产 | **缺失** —— `resources/talents/` 下 0 个 `.tres` |
| 界面视觉 | **缺失** —— 界面只有 1 个位置写死的 `HBoxContainer` |
| 属性效果生效 | **有缺陷** —— 见第 5 节 |

因此设计遵循「补缺口，不改已工作的部分」：不动时间系统的触发逻辑与信号序，不动 `player.gd` 的广播-应用链路，不动 `talent_card.tscn` 的卡面节点布局。

## 2. 边界与职责

| 组件 | 职责 | 本次改动 |
|---|---|---|
| `core/autoloads/time_system.gd` | 时间推进、每 7 天广播 | **不改** |
| `resources/talents/talent_manager.gd` | 池装配、界面开关、暂停归还、选择转发 | 改：加目录枚举、暂停记录、浮窗注入 |
| `resources/talents/talent_card.gd` | 单卡展示、悬停表现、点击转发 | 改：视觉数值改为共享常量、加浮窗 |
| `scenes/talents/talent_screen.tscn` | 界面视觉框架 | 改：补遮罩/标题/提示 |
| `scenes/Main.tscn` | 场景挂载 | 改：实例化 `TalentScreen` |
| `resources/talents/attribute_talent_effect.gd` | 属性永久加成 | 改：修组件解析路径 |
| `resources/talents/talent_night_*.tres` 等 10 个 | 天赋内容 | 新增 |
| `entities/player.gd` | 广播接收与效果迭代 | **不改** |

## 3. 数据流

```
玩家推进时间
  └─ TimeSystem.PassTime(amount)
       └─ _check_time_transitions()            已有：跨昼夜阶段逐段处理
            └─ _current_day % 7 == 0 时
                 └─ TalentSelectionTriggered.emit()        已有
                      └─ TalentManager._pop_up_talent_selection()   订阅点（已存在）
                           ├─ _available_talents 为空 → 记日志返回（不弹空界面）
                           ├─ _was_paused_before_open = 当前暂停状态   ← 新增
                           ├─ paused = true                        ← 已有
                           ├─ show() + _draw_three_talents()       ← 已有，补浮窗注入
                           └─ 玩家点击卡片
                                └─ TalentCard.OnCardClicked(data)
                                     └─ TalentManager.OnTalentSelected(data)
                                          ├─ _available_talents.erase(data)  ← 未选中的留在池内
                                          ├─ GlobalEventBus.on_player_acquired_talent.emit(data)
                                          │    └─ Player._absorb_talent(data)
                                          │         └─ 逐条 effect.Apply(player)
                                          │              └─ AttributeComponent.AddPermanentBonus(...)
                                          ├─ hide()
                                          └─ 归还暂停（只在本次造成时）        ← 新增
```

## 4. 天赋池装配契约

### 4.1 问题

`talent_manager.gd:31` 用 `_available_talents.assign(AllTalentsPool)` 装配池。而 `tests/godot/test_inventory_component_contract.gd:1593` 断言生产场景的 `AllTalentsPool` 必须为空数组。因此**不能**在 `talent_screen.tscn` 里直接挂 10 个资源引用。

### 4.2 方案：目录枚举，与技能卡抽取界面同范式

新增导出字段：

```gdscript
## 天赋卡池目录；递归扫描其中的 .tres。
@export var CardPoolDirectory: String = "res://resources/talents"
```

`_ready()` 里的装配改为：

```
_available_talents = 目录枚举(CardPoolDirectory)  # 按 resource_path 排序，顺序稳定
                      + AllTalentsPool            # 显式追加，去重；生产场景为空
```

判定标准是「资源暴露 `TalentName` 与 `Effects` 字段」，与 `run_start_skill_card_draft.gd:_is_skill_card`（判定 `Skill` 字段）同构，并沿用 `ItemsControl.load_items_recursively` 的递归扫描写法 —— 项目里「从 res:// 目录加载资源」保持只有一种写法。

**为什么不用「在场景里配数组」**：那样每加一张卡都要改场景文件，且会破坏既有契约断言。

**为什么不用 `class_name` 类型判定**：`talent_data.gd` 刻意不声明 `class_name`（与 `player.gd` 同样理由 —— 避免与退役中的 C# 全局类型重名）。按字段判定可让脚本换代时池装配不失效。

### 4.3 池耗尽语义（用户已确认）

保持现有 `erase` 语义并把它写成显式契约：**只有被选中的那张离开池**，本轮未选中的两张因为洗牌是对 `_available_talents` 原地进行、取前 3 张而不移除，自然留在池中，下一轮仍可出现。10 张卡会依次被学完，之后不再弹出。

`_available_talents` 为空时 `_pop_up_talent_selection` 已有 `print` 分支；本次把它明确为「记录一条可诊断日志并返回，不弹空界面」，避免玩家面对一个没有卡可选的死界面。

### 4.4 抽卡数量

保持 `mini(3, _available_talents.size())` 的 3 张。技能卡界面是「抽 5 选 2 + 确认」，天赋是「抽 3 选 1 + 立即生效」，两者语义不同，不强行对齐数量。

## 5. 缺陷修复：属性天赋静默失效

### 5.1 现象与证据

`resources/talents/attribute_talent_effect.gd:52`：

```gdscript
var attribute_component := target_player.get_node_or_null("AttributeComponent")
```

`target_player` 是玩家根节点（`player.gd:165` 传入 `self`）。而 `scenes/player_scenes/player.tscn` 的实际布局是：

```
Player
└── Components
    ├── AttributeComponent
    └── TagComponent
```

`player.gd` 把组件暴露为 `Attributes`（`:45`）与 `TagComponent`（`:53`）两个属性，**不存在**名为 `AttributeComponent` 的直接子节点。因此这行恒为 `null`，函数在第 54 行静默 `return` —— **属性类天赋永远不会生效**，且没有任何日志。

对照 `tag_talent_effect.gd:17` 用 `target_player.get("TagComponent")` 走属性协议，能正确命中 `player.gd:53` 的属性，所以标签类天赋是好的。两条效果路径一个走属性、一个走场景路径，这是不一致的根源。

### 5.2 修复

改为「先属性协议，再场景路径兜底，都没有就报警告」：

```gdscript
var attribute_component: Node = target_player.get("Attributes") as Node
if attribute_component == null:
    attribute_component = target_player.get_node_or_null("Components/AttributeComponent")
if attribute_component == null:
    push_warning(...)
    return
```

优先属性协议使它与 `tag_talent_effect.gd` 对称；场景路径兜底覆盖「目标不是 `player.gd` 而是别的宿主」的情况；`push_warning` 取代静默 `return`，让接线错误可诊断（与 `attribute_component.gd:512` 对未知属性报警告的做法一致）。

### 5.3 契约影响

`tests/godot/test_player_contract.gd:355` `test_talent_effects_accept_node_player` 断言的是**旧 C# 源文**里的 `targetPlayer.GetNodeOrNull<AttributeComponent>("AttributeComponent")`，并且开头就有 `if not CS_OPTIONAL.present(...): skip(...)`。已核实 `resources/talents/` 下**没有任何 `.cs` 文件**（C# 已退役），因此该用例走 `skip` 分支，修复不会与它冲突。

## 6. 界面设计

### 6.1 结构（对齐 `skill_card_draft_screen.tscn`）

```
TalentScreen            CanvasLayer  process_mode = ALWAYS(3)  script = talent_manager.gd
├── Overlay             ColorRect    全屏  Color(0,0,0,0.65)
└── Content             VBoxContainer 全屏  alignment=center  separation=18
    ├── TitleLabel      Label        "天赋觉醒"  font_size=30  居中
    ├── CardsContainer  HBoxContainer separation=12  居中
    └── HintLabel       Label        "选择一项天赋"  font_size=20  居中
```

与技能卡界面的差异：**没有 `ConfirmButton`**，因为天赋是「点击立即生效」。

`CardsContainer` 的导出引用从 `NodePath("HBoxContainer")` 改为 `NodePath("Content/CardsContainer")`；节点名从默认的 `HBoxContainer` 改为语义化的 `CardsContainer`。

### 6.2 卡面动态表现（用户要求：外观保留天赋卡场景，手感对齐技能卡）

`talent_card.gd` 现状硬编码 `Vector2(1.05, 1.05)` 与 `0.15` 秒，且 `z_index` 固定为 1/0。改为读取 `core/card_visual_config.gd`：

| 行为 | 取值来源 | 说明 |
|---|---|---|
| 悬停放大 | `CARD_HOVER_SCALE` (1.05) | 与战斗手牌、开局抽卡一致 |
| 缩放时长 | `SCALE_TWEEN_DURATION` (0.08) | 比现状 0.15 更跟手，且三处统一 |
| 悬停置顶 | `CARD_Z_INDEX_HOVER` (2) / `CARD_Z_INDEX_NORMAL` (1) | 现状是 1/0，改用共享常量 |

**不引入选中抬升**（`CLICK_SELECTED_LIFT_DISTANCE`）：天赋没有「选中后等待确认」的状态，点击即生效并关闭界面，抬升动画会被立刻销毁。

`pivot_offset` 保持在 `_ready()` 里按「底部中心」设置（`Vector2(size.x / 2.0, size.y)`），与现状一致，保证缩放轴心不漂。

### 6.3 悬停详情浮窗

由 `TalentManager` 解析共享浮窗并把引用注入每张卡：

- `talent_manager.gd` 新增 `@export var TooltipPanelPath: NodePath = NodePath("../TooltipPanel")`（`TalentScreen` 与 `TooltipPanel` 同为 `HUDRoot` 的直接子节点，与 `run_start_skill_card_draft.gd` 的 `TooltipPanelPath` 默认值完全相同）。
- `talent_card.gd` 新增公开方法 `SetTooltipPanel(panel: Node)`；卡片在悬停进入/离开时调用 `show_tooltip(name, desc)` / `hide_tooltip()`，调用点用 `has_method` 守卫。

**为什么由管理器注入而不是卡片自己导出路径**：卡片是可复用的生产场景，写死「距浮窗几层」会把卡片的可用位置限死；而管理器本来就是界面根，知道自己在 `HUDRoot` 下的位置。这也避免 `Initialize(data)` 的签名变更（契约测试断言 `has_method("Initialize")`，签名保持原样最稳）。

浮窗接口已核实：`scripts/ui_scripts/tooltip_panel.gd:77 show_tooltip(title_text, desc_text)` 与 `:141 hide_tooltip()`。浮窗缺失只降级为警告，不阻断选择流程（与开局抽卡一致）。

### 6.4 暂停归还

`talent_manager.gd:55` 现状无条件 `get_tree().paused = false`。改为 `pause_menu.gd:47-51` 与 `run_start_skill_card_draft.gd:130,253-254,686-688` 的既有约定：

```
打开前：_was_paused_before_open = get_tree().paused
关闭时：get_tree().paused = _was_paused_before_open
```

这消除了「把别的系统造成的暂停一起解除」的隐患，也与 `docs/游戏机制与玩法内容.md:102` 记录的约定一致。

## 7. 内容设计：10 张天赋卡

全部为 `AttributeTalentEffect`（属性永久加成），覆盖基础攻防、法术、资源上限、穿透、暴击、闪避六类，使效果路径当场可验证。按用户决策，**不使用标签效果**（不接触入夜通道玩法）。

| # | 文件 | TalentName | TargetAttribute | 数值 |
|---|---|---|---|---|
| 1 | `talent_brute_force.tres` | 蛮力觉醒 | `0` PhysAtk | +5.0 |
| 2 | `talent_iron_body.tres` | 铁壁体魄 | `1` PhysDef | +5.0 |
| 3 | `talent_arcane_affinity.tres` | 秘法亲和 | `2` MagPower | +5.0 |
| 4 | `talent_warding.tres` | 魔抗屏障 | `3` MagResist | +5.0 |
| 5 | `talent_swift_step.tres` | 疾风步 | `4` Speed | +3.0 |
| 6 | `talent_vitality.tres` | 强健体魄 | `5` MaxHealth | +20.0 |
| 7 | `talent_vigorous.tres` | 精力充沛 | `6` MaxEnergy | +10.0 |
| 8 | `talent_armor_piercer.tres` | 破甲专精 | `7` FixedPhysPenetration | +3.0 |
| 9 | `talent_deadly_instinct.tres` | 致命直觉 | `11` CritRate | +0.05 |
| 10 | `talent_phantom_step.tres` | 幻影身法 | `13` EvasionRate | +0.05 |

属性整数值取自 `attribute_talent_effect.gd:6-22` 的 `ATTRIBUTE_NAMES` 顺序（与 `AttributeComponent` 枚举一致）。`CritRate` / `EvasionRate` 是 0~1 比率（`attribute_component.gd:360,368` 用 `ReadStat(data, "BaseCritRate")` 直接作为比率），所以取 `0.05` 而非 `5`。

图标复用工程既有贴图（`res/element_icon/*.png`、`res/items/*.png`），不自造美术资产。

`.tres` 手写并沿用 `resources/skill_cards/fire_phys_huoji.tres` 的序列化形状：根 `script` 指向 `talent_data.gd`，`Effects = Array[Resource]([SubResource("...")])`，子资源 `script` 指向 `attribute_talent_effect.gd`。

## 8. 契约测试的调整（显式记录）

`tests/godot/test_inventory_component_contract.gd:1587,1597` 通过根下直接子节点名锁定界面结构：

```gdscript
var cards_container := screen.get_node("HBoxContainer") as HBoxContainer
assert_true(screen.get("CardsContainer") == cards_container, "CardsContainer 必须继续引用 HBoxContainer。")
```

本次是**有意重构**界面结构（用户明确要求对齐技能卡界面），因此这两行必须同步更新为 `Content/CardsContainer`。

调整原则：
- **只改路径，不删断言** —— 「`CardsContainer` 导出必须指向那个卡面容器节点」这条语义原样保留。
- **净增防护** —— 同时断言新结构里的 `Overlay` 与 `TitleLabel` 存在，使界面框架本身也受契约保护。
- 其余断言（`AllTalentsPool` 为空、`CardScenePrefab` 路径、`OnTalentSelected` 存在、`process_mode == ALWAYS`）一律保持不动。

## 9. 兼容与回滚

- **兼容**：`AllTalentsPool` 导出字段保留且默认空，既有场景与契约不动；`OnTalentSelected(data)`、`Initialize(data)`、`OnCardClicked(data)` 三个公开协议全部不变；`talent_card.tscn` 的 `TitleText` / `DescText` / `Texture` / `ClickArea` 节点名与层级不动。
- **回滚**：改动集中在 6 个文件 + 10 个新资源。回滚 = 删除 10 个 `.tres` + 还原 `talent_manager.gd` / `talent_card.gd` / `talent_screen.tscn` / `Main.tscn` / `attribute_talent_effect.gd` + 还原 1 处契约断言。没有数据迁移、没有存档格式变化。

## 10. 验证策略

按 AGENTS.md：Godot 侧一律走编辑器 MCP（编辑器已确认在线：会话 `cusga@5fea6c0f9f459e02`，Godot 4.7.1，`readiness: ready`），C# 侧走 `env CI=true dotnet build`。

1. **静态**：`filesystem_manage(op="scan")` 让编辑器登记新资源 → `resource_manage(op="load")` 逐个校验 10 个 `.tres` 的字段。
2. **契约**：`test_run(suite="inventory")` 覆盖 `test_inventory_component_contract.gd`。
3. **运行**：`project_run(mode="main")` 起主场景 → 用 `game_eval` 直接 `PassTime` 推进到第 7 天边界，或经 `DevSettingsUI` 的「下一天」按钮 → `editor_screenshot(source="game")` 确认界面弹出 → `logs_read(source="game")` 确认选择与效果日志 → `project_manage(op="stop")`。
4. **编译**：`env CI=true dotnet build CUSGA.sln --no-restore`（本次不新增 C# 代码，用于确认没有连带破坏）。

自然玩法到达第 7 天需要 1200 时间点（6 天 × 200 点，地图移动 10 点/次 ≈ 120 次移动），因此运行验证必须借助 DevSettingsUI 或 `game_eval` 直接推进时间 —— 这一点写进 `implement.md` 的验证步骤。

## 11. 已考虑的替代方案

| 方案 | 未采用的原因 |
|---|---|
| 在 `talent_screen.tscn` 里直接挂 10 个资源引用 | 破坏 `AllTalentsPool` 必须为空的既有契约；每加一张卡都要改场景 |
| 给 `talent_data.gd` 加 `class_name` 后按类型判定 | 与「不声明 `class_name` 以避免和退役 C# 类型重名」的既有决策冲突 |
| 天赋界面换成 `SkillCard.tscn` 卡面 | 用户明确要求保留天赋卡自己的场景外观 |
| 加「选中 + 确认」两段式交互 | 用户明确要求点击立即生效；且三选一场景下多一次点击无收益 |
| 让标签卡接上 `HomeProtectionTag` 影响入夜通道 | 用户明确表示不需要入夜通道，缩小改动面 |
| 改 `time_system.gd` 的 `% 7` 判定 | 逻辑已正确；动它只会扩大风险面 |
