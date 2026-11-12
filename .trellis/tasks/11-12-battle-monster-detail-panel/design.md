# 技术设计：战斗中怪物详情面板

## 1. 边界与放置

| 关注点 | 决定 | 理由 |
|---|---|---|
| 面板场景 | `scenes/battle_scenes/monster_detail_panel.tscn` | 只服务战斗，与 `battle.tscn` 同目录；可独立实例化做测试 |
| 面板脚本 | `scripts/battle_scripts/monster_detail_panel.gd` | 与其它战斗 UI 脚本同目录，符合 `frontend/directory-structure.md` |
| 面板宿主 | `battle.tscn` 新增 `MonsterDetailLayer`（`CanvasLayer`，`layer = 1`）+ 一个面板实例 | 全屏 `Control` 不能挂在 `Node2D` 下（anchors 会退化为 0×0，见 `component-guidelines.md` 全屏覆盖层一节）；`CanvasLayer` 提供视口尺寸的 `anchorable_rect` |
| 渲染顺序 | 默认 canvas（卡牌 z=1/2、`UI` 与 `Button` z=2000）→ `MonsterDetailLayer`(1) → `HUDLayer`(2) → `CombatFeedbackLayer`(20) | `CanvasLayer` 永远画在默认 canvas 之上；`layer=1` 保证面板压住战斗卡牌与战斗 UI，又不遮住暂停菜单。战斗中地图节点的同层 `CanvasLayer` 已隐藏，不会争用绘制 |
| 触发来源 | 怪物只发 `MonsterDetailRequested(monster)` 信号；`battle_manager.gd` 负责转给面板 | 怪物脚本不构建 UI、不读技能池；符合"怪物侧只传递查看哪个怪物" |

## 2. 怪物侧契约（`entities/monster.gd`）

- 新增 `signal MonsterDetailRequested(monster: Node2D)`。
- `_ready` 额外连接 `_area_2d.input_event` → `_on_area_2d_input_event(viewport, event, shape_idx)`。
- 处理规则：
  - `_is_combat_defeated` 时直接返回（死亡后 `input_pickable=false` 已经是第一层保险）。
  - 只接受 `InputEventMouseButton`、`pressed == true`、`button_index == MOUSE_BUTTON_RIGHT`。
  - 命中后 `MonsterDetailRequested.emit(self)`，并 `get_viewport().set_input_as_handled()`。
- 新增公共 `GetElementDisplayName(element: int) -> String`；原私有 `_get_element_display_name` 改为委托调用，保留旧入口供既有调用者使用，不复制映射表。
- `_exit_tree` 断开 `input_event` 连接。
- 不改动悬停提示（`mouse_entered` / `mouse_exited`）与左键物理拾取。

## 3. 面板契约（`monster_detail_panel.gd`）

公开接口：

```gdscript
signal PanelOpened              # 面板由隐藏变为显示
signal PanelClosed              # 面板由显示变为隐藏（幂等关闭也会发一次，仅在状态真正变化时）

func ShowMonster(monster: Node) -> void   # 打开并绑定怪物；已在显示时切换目标
func ClosePanel() -> void                  # 关闭并清理绑定；隐藏状态下调用为空操作
func IsPanelOpen() -> bool                  # 查询当前是否显示
func BuildSnapshot(monster: Node) -> Dictionary  # 只读展示快照，供 UI 与测试共用
```

`BuildSnapshot` 字段（全部为纯数据，避免 UI 直接依赖组件内部）：

```
name: String              # BaseData.MonsterName，缺失 -> "未知怪物"
element_id: int           # BaseData.ElementalProperty，缺失 -> 0
element_text: String      # 无/木/金/水/土/火
has_health: bool
current_hp: int
max_hp: int
attributes: Array[Dictionary]  # [{type:int, label:String, value:String}] 固定 5 项，缺失 -> "--"
skills: Array[Dictionary]      # [{name:String, description:String}] 按 GetSkillPreviews() 顺序
```

读取规则：
- 名称/五行/技能通过 `monster.get("BaseData")` + 字段读取（兼容 C#/GDScript 数据），不假设具体脚本类型。
- 生命通过 `monster.Health` 的 `CurrentValue` / `MaxValue`；组件缺失或字段不可读时 `has_health=false`，UI 显示 `-- / --`。
- 五项属性通过 `monster.Attributes.GetEffectiveValue(type)`，`type` 取 `0..4`（物攻、物防、法强、法抗、速度，与 `monster_attribute.gd` 一致），缺失返回 `null` → `"--"`。
- 技能通过 `monster.SkillComponent.GetSkillPreviews()`；组件或方法缺失时返回空数组 → UI 显示"暂无可展示的技能"。UI 不读 `SkillSet`、不判断 `VisibleInPreview`、不重排。

显示规则：
- 左列（`PanelContainer`，`custom_minimum_size.x = 260`，纵向布局）：名称（大字）、五行、生命标题 + 进度条 + `当前/最大` 文本、分隔线、五项属性表。
- 右列（`VBoxContainer`，`size_flags_horizontal = EXPAND_FILL`）：标题行（"技能池" + "关闭"按钮），下方 `ScrollContainer`（仅纵向滚动）内 `VBoxContainer`；按技能数动态生成 `Label(名称)`、`Label(描述, autowrap_mode = WORD_SMART, size_flags_horizontal = FILL)`，条目之间插入 `HSeparator`。最后一项后不插入分割线。
- 空技能池插入一条居中占位 `Label`。
- 每次重绑/刷新前清空动态条目（`queue_free` 后立即从父节点移除，避免同一帧内残留旧条目）。

生命周期：
- `ShowMonster`：`monster == null` 或已释放 → 直接 `ClosePanel()`；否则先 `_unbind_monster()` 再绑定，重建 UI，`show()`，`set_process(true)`，发 `PanelOpened`（仅在状态从关到开时）。
- 绑定内容：`Health.ValueChanged` → 刷新生命区（只更新数值，不重建技能列表）；同一怪物重复 `ShowMonster` 只刷新快照，不重复连接。
- 每帧（仅显示期间）`_process`：`not is_instance_valid(_monster) or _monster.is_queued_for_deletion()` → `ClosePanel()`。这是死亡、`queue_free`、场景拆除的统一兜底。
- `Health.Depleted` 只作为即时关闭的加速路径，与每帧兜底等价。
- `ClosePanel`：`hide()`、`set_process(false)`、`_unbind_monster()`（断开 `ValueChanged`/`Depleted`）、清空动态条目、清空缓存快照，发 `PanelClosed`（仅状态真正变化时）。
- `_exit_tree`：`ClosePanel()` 但不发信号给已退出的宿主；断开全部连接。
- 全程不写入 `SceneTree.paused`。

输入：
- 根 `Control`：`anchors_preset = FULL_RECT`、`mouse_filter = STOP`。遮罩 `ColorRect` 也 `STOP` 并在 `gui_input` 里关闭面板。
- `_input(event)`（仅显示时生效）：若事件是 `pause_game`（`InputMap.has_action` 时用动作判断）或 `KEY_ESCAPE` 的首次按下 → `ClosePanel()` + `get_viewport().set_input_as_handled()`。因为 `pause_menu.gd` 的开关走 `_unhandled_input`，在 `_input` 里消费即可保证不误触暂停菜单。
- 不调用 `grab_focus()`：聚焦的 `Button` 会先吞掉 `ui_cancel`，导致第一次 `Esc` 只丢焦点。

## 4. 战斗侧协调（`battle_manager.gd`）

- 新增 `@onready var card_manager = $CardManager`、`@onready var monster_detail_panel = $MonsterDetailLayer/MonsterDetailPanel`。
- `_ready`：连接面板的 `PanelOpened` / `PanelClosed`；`monster_manager.monsters_spawned` 回调里为每只怪物连接 `MonsterDetailRequested`（幂等，`is_connected` 判重）。
- `_on_monster_detail_requested(monster)`：`monster_detail_panel.ShowMonster(monster)`。
- `_on_monster_detail_panel_opened()`：
  - `card_manager.clear_click_selection()`（清理点击模式待确认选卡）；
  - 调用 `card_manager.call("_cancel_active_drag")`（若拖拽中打开面板则回收虚影，避免虚影留在遮罩上）；
  - `card_manager.set_process_input(false)`：面板显示期间不再处理 `_input` 的世界射线，彻底阻断"点遮罩却抓到下面卡牌"的穿透路径；
  - 隐藏共享提示面板（`tooltip_panel` 组），避免旧悬停气泡压在遮罩上。
- `_on_monster_detail_panel_closed()`：`card_manager.set_process_input(true)`。
- `_handle_combat_end()`：先 `monster_detail_panel.ClosePanel()`，再锁控制并广播战果。
- 不修改行动队列、回合状态机或任何数值。

## 5. 点击穿透的第二道防线（`card_manager.gd`）

`_handle_drag_mode_input` 的按下分支补一条与点击模式同源的守卫：

```gdscript
var hovered_control := get_viewport().gui_get_hovered_control()
if hovered_control and not _is_monster_card_presentation_control(hovered_control):
    return
```

- 只在"按下并可能开始拖拽"时判断，松开仍走 `finish_drag()`，不会中断已开始的拖拽。
- 正常战斗里手牌是 `Node2D`，鼠标在牌上时 `gui_get_hovered_control()` 为 `null`，守卫不改变既有拖拽手感；只有鼠标下有 `Control`（按钮、面板遮罩）时才阻止误抓。
- 这是纵深防御：主防线是面板 `STOP` + `set_process_input(false)`，即便将来面板改成非模态也不会漏。

## 6. 权衡

- **为什么用 `CanvasLayer(1)` 而不是 `UI` 下的 `Control`**：`UI` 是 `Marker2D`（`Node2D`），全屏 `Control` 的 anchors 会算出 0×0 且不报错。`CanvasLayer` 同时解决尺寸与层级。
- **为什么在 `_input` 里消费 `Esc`**：暂停菜单的开与关分别走 `_unhandled_input` 与菜单自身的 `_input`；面板显示时消费事件即可"只关闭自己"，不引入暂停所有权交接。
- **为什么不暂停**：用户已确认。代价是面板打开期间敌方仍会行动、玩家无法操作；收益是实现不触碰全局暂停，不会与暂停菜单、天赋选择等既有暂停方互相解除。
- **为什么不自己解析技能**：`GetSkillPreviews()` 已是可见性、描述覆盖、顺序的单一权威；复制规则会在下次改动时静默分叉。

## 7. 兼容与回滚

- 改动全部是新增节点/信号/方法；`GetElementDisplayName` 只是把既有映射提升为公共入口，旧私有方法保留。
- 回滚点：`battle.tscn` 删除 `MonsterDetailLayer`、`monster.gd` 撤回信号与 `input_event`、`battle_manager.gd` 撤回协调代码、`card_manager.gd` 撤回拖拽守卫；新文件整体删除即可。
- 不触碰存档、资源 `.tres`、行动值或时间系统。

## 8. 验证策略

- 单元契约（`test_run(suite="battle_monster_detail_panel_contract")`）：
  1. 用真实 `monster_skill_component.gd` + 三个技能条目（可见+覆盖描述、可见+原描述、隐藏）构造怪物数据，断言快照顺序、数量、描述回退与隐藏排除。
  2. 空技能池、缺失 `Health`/`Attributes`/`SkillComponent` 的怪物 → 快照占位且不报错。
  3. 面板实例：`ShowMonster` 后可见、`PanelOpened` 只发一次；重复 `ShowMonster` 同一怪物不重复连接；切换到第二只怪物后快照与 UI 文本均为新怪物；`ClosePanel` 后隐藏、断开 `ValueChanged`、`PanelClosed` 只发一次。
  4. 面板打开时怪物 `queue_free` → 下一帧 `_process` 自动关闭（测试中直接调用 `_process` 或等待一帧）。
  5. `Esc`：构造 `InputEventKey(KEY_ESCAPE, pressed)` 调用面板 `_input`，断言面板关闭且 `viewport.is_input_handled()` 为真。
  6. 场景装配：`battle.tscn` 存在 `MonsterDetailLayer` 且 `layer=1`、面板是唯一实例、`mouse_filter=STOP`。
- 真实运行（`project_run(mode="custom", scene="res://scenes/battle_scenes/battle.tscn")` + `game_eval`）：
  - 用 `viewport.push_input(InputEventMouseButton)` 在怪物屏幕坐标发送右键，断言面板可见且绑定目标正确。
  - 面板打开时向面板区域再次发右键，断言绑定目标不变（未穿透）。
  - 发 `Esc`，断言面板关闭且游戏未暂停（`SceneTree.paused == false`，暂停菜单 `_is_menu_open == false`）。
  - 对怪物造成伤害，断言面板生命文本随 `ValueChanged` 更新。
  - `editor_screenshot(source="game")` 人工确认左窄右宽布局、分割线与滚动。
  - 读取 `logs_read(source="game")`，确认本次无 `SCRIPT ERROR` / `Parse Error` / 资源加载错误。
