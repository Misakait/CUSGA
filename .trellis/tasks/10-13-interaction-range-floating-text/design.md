# Design — 交互距离不足飘字提示组件

## 1. Scope / Boundaries

### 新增

| 文件 | 角色 |
| --- | --- |
| `core/autoloads/floating_text.gd` | **服务**：全局 autoload（名 `FloatingText`）。持有自己的 `CanvasLayer`，负责坐标解析、去重、生命周期。唯一的公开调用面。 |
| `core/ui/feedback/floating_text_label.gd` | **表现组件**：`class_name FloatingTextLabel extends Label`。只负责「一次飘字怎么画、怎么动、什么时候释放」，不含任何业务与坐标知识。 |
| `tests/godot/test_floating_text_contract.gd` + `tests/test_floating_text_contract.gd` | 契约套件与顶层转发壳。 |

### 修改（仅「调用方」与「建筑提示机制」，不碰目标）

| 文件 | 改动 |
| --- | --- |
| `project.godot` | `[autoload]` 追加一行 `FloatingText`，插在 `SettlementManager` 之后、`_mcp_game_helper` 之前，保持 `SaveManager` 仍是第一项。 |
| `core/gameflow/world_interaction_coordinator.gd` | 解析 `FloatingText` 路径；在 `_report_out_of_range_interaction()` 里补一次调用。 |
| `core/building/building_controller.gd` | 解析 `FloatingText` 路径；拆出 `_is_record_in_range()`；**8 处 `_show_feedback` 全改飘字**；删除 `FeedbackSeconds` / `_feedback` / `_feedback_left`；简化 `_hint` 的三处 `_feedback` 引用。 |
| `docs/建筑系统.md` | 更新 `FeedbackSeconds` 参数行。 |

### 明确不改（AC-8）

`core/board/board_card_view.gd`、`core/board/board_controller.gd`、`core/building/building_view.gd`、`core/building/building_service.gd`、`scripts/battle_scripts/combat_feedback_*.gd`、任何 `scenes/**` 与 `.tres` —— **零改动**。

坐标由服务自行求得，目标不需要实现任何新方法或信号。

## 2. Contracts

### 2.1 `FloatingTextLabel`（表现组件）

```gdscript
extends Label
class_name FloatingTextLabel

## 播放结束后、节点释放前发出；供测试与上层确认动画真的走完。
signal finished

## 配置并启动一次飘字；结束后自动 queue_free 自身。
##
## 参数 text：显示文案。
## 参数 text_color：正文颜色。
## 参数 font：渲染字体；由服务传入游戏字体，组件不自带默认值，避免出现第二处字体来源。
## 参数 font_size：字号（像素）。
## 参数 outline_size：黑色描边宽度（像素）。
## 参数 outline_color：描边颜色。
## 参数 rise_distance：向上飘升的像素距离。
## 参数 duration：总时长（秒）。
## 返回值：无。
func play(text: String, text_color: Color, font: Font, font_size: int,
		outline_size: int, outline_color: Color,
		rise_distance: float, duration: float) -> void
```

**为什么参数这么多**：组件是纯表现，所有可调项由服务单点持有。这样「飘字长什么样」只有**一个**配置来源（服务里的 `const`），组件与任何未来消费方都不会各存一份数值，符合 `frontend/component-guidelines.md`「共享表现参数放在无状态配置脚本中，消费方通过 preload 读取，避免复制数值」。

`_ready()` 里必须做三件事：

1. `mouse_filter = Control.MOUSE_FILTER_IGNORE`（枚举 `2`）。**漏掉会吞掉其下所有鼠标输入**，是本项目规范里点名的坑。
2. `horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER`、`vertical_alignment = VERTICAL_ALIGNMENT_CENTER`。
3. 用 **theme override** 施加字体与描边（见 2.3）。

`play()` 用 `create_tween()` 并行做 `position.y -= rise_distance` 与 `modulate.a → 0`；`finished` 先 `emit`、再 `queue_free()`。节点自己释放自己，服务不持有注册表。

### 2.2 `FloatingText`（服务 / autoload）

```gdscript
extends Node
## 全局飘字服务。autoload 名 FloatingText，脚本内不声明 class_name 以免与全局单例名冲突。

## 游戏字体：工程内唯一字体资源，含 6769 个 CJK 表意文字（实测）。
const GAME_FONT: FontFile = preload("res://res/font/Uranus_Pixel_11Px.ttf")
## 表现组件脚本。
const LABEL_SCRIPT: GDScript = preload("res://core/ui/feedback/floating_text_label.gd")
## 承载层号：必须高于 UI/HUDLayer(2)。
const CANVAS_LAYER: int = 10
## 默认正文色（红）。
const DEFAULT_TEXT_COLOR: Color = Color(1.0, 0.25, 0.2, 1.0)
## 字号 / 黑色描边宽度 / 描边色。
const FONT_SIZE: int = 28
const OUTLINE_SIZE: int = 6
const OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)
## 上飘距离与总时长。
const RISE_DISTANCE: float = 48.0
const DURATION: float = 0.9
## 去重窗口（秒）与坐标容差（像素）。
const DEDUPE_SECONDS: float = 0.2
const DEDUPE_RADIUS: float = 8.0

## 在交互目标处显示飘字。目标坐标由本服务读取，调用方只传目标与文案。
func show_at_target(target: CanvasItem, text: String,
		text_color: Color = DEFAULT_TEXT_COLOR) -> Node

## 在世界坐标处显示飘字（用于没有存活目标节点的场景，如建筑已拆除、建造落点）。
func show_at_world(world_position: Vector2, text: String,
		text_color: Color = DEFAULT_TEXT_COLOR) -> Node

## 立即清空所有仍在飞的飘字；供场景切换与测试收尾使用。
func clear_all() -> void
```

**内部结构**：`_ready()` 建 `CanvasLayer`（`layer = CANVAS_LAYER`）→ 其下挂全屏 `Control` 宿主（`set_anchors_and_offsets_preset(PRESET_FULL_RECT)`、`mouse_filter = IGNORE`）。所有飘字作为宿主子节点，`position` 直接就是屏幕坐标。

- `show_at_target` → `_resolve_target_screen_position(target)` → `_spawn(...)`
- `show_at_world` → `get_viewport().get_canvas_transform() * world_position` → `_spawn(...)`

**坐标解析（AC-8 的核心）**：

```gdscript
func _resolve_target_screen_position(target: CanvasItem) -> Vector2:
	# 失效目标回退到鼠标位置：调用方可能持有刚被 queue_free 的卡牌（跨房卸载）。
	if target == null or not is_instance_valid(target):
		return get_viewport().get_mouse_position()
	if target is Control:
		# Control 以尺寸中心为锚，避免文字贴在左上角。
		var control: Control = target
		return control.get_screen_transform() * (control.size * 0.5)
	# Node2D：BoardCardView 的根、Icon、碰撞体全部位于原点，原点即图标中心。
	return target.get_screen_transform().origin
```

与 `core/ui/hud/world_hold_progress_indicator.gd:101-113` 同口径，复用已被 `world_hold_interaction_tests` 验证过的换算方式。

### 2.3 关键决策：用 theme override 而不是 `LabelSettings`

Godot 4 的 `Label` 在设置了 `label_settings` 时，**字体、字号、颜色、描边全部以 `LabelSettings` 为准，`theme_override_*` 被忽略**。若服务共享一份 `LabelSettings` 以省资源，那么每次调用想传不同 `text_color` 就会失效（只能改共享资源，导致所有在飞飘字一起变色）。

因此采用 **theme override**：

```gdscript
add_theme_font_override("font", font)
add_theme_font_size_override("font_size", font_size)
add_theme_color_override("font_color", text_color)
add_theme_constant_override("outline_size", outline_size)
add_theme_color_override("font_outline_color", outline_color)
```

零资源分配、每次调用颜色独立，且与工程既有场景写法（`theme_override_font_sizes/font_size`）一致。

### 2.4 调用方接入（解耦的关键约束）

**绝对禁止**在调用方直接书写 autoload 标识符 `FloatingText`。`test_run` 环境没有 autoload，裸标识符会让脚本连**解析**都过不去（`.trellis/spec/frontend/state-management.md:136`）。统一写法：

```gdscript
## 飘字服务路径；必须走 NodePath，裸 autoload 标识符在 test_run（无 autoload）下会解析失败。
const FLOATING_TEXT_PATH: NodePath = ^"/root/FloatingText"

var _floating_text: Node = null

# _ready() 内：
_floating_text = get_node_or_null(FLOATING_TEXT_PATH)

## 在指定目标处显示飘字；服务缺失时静默降级。
func _show_floating_text_at(target: CanvasItem, message: String, text_color: Color) -> void:
	if target == null or message.is_empty():
		return
	if _floating_text == null or not is_instance_valid(_floating_text):
		return
	if not _floating_text.has_method("show_at_target"):
		return
	_floating_text.call("show_at_target", target, message, text_color)
```

用 `call` + `has_method` 做鸭子类型，调用方**不 `preload` 服务脚本** —— 服务与调用方之间没有编译期耦合，服务缺失时功能降级而非报错。

### 2.5 去重（AC-2）

服务内维护一个短小的 `Array[Dictionary]`，元素为 `{"text": String, "position": Vector2, "expires_at": int}`（`Time.get_ticks_msec()`）。

每次 `_spawn` 前：

1. 清掉 `expires_at` 已过的条目。
2. 若存在同 `text` 且坐标距离 ≤ `DEDUPE_RADIUS` 的条目 → **跳过**，返回 `null`。
3. 否则追加新条目并生成飘字。

`DEDUPE_SECONDS = 0.2` 覆盖 `board_card_view.gd:161-166` 的**同帧双发**（`Pressed` + `Clicked` 间隔为 0）。

**取舍**：不做「已存活则重启动画」。重启需要在服务里登记存活飘字并处理释放竞态，而收益只针对「0.2 秒内同点连点」这种边缘情形；那种情况下叠字反而直观表达「别点了」。保持飘字节点 fire-and-forget、服务无注册表，换取更低的耦合与更少的失效路径。

## 3. Data Flow

### 棋盘卡

```
鼠标左键
 └─ BoardCardView._input_event
     ├─ Pressed.emit  ─┐（同帧、同卡）
     └─ Clicked.emit  ─┘
         └─ BoardController → WorldInteractionCoordinator
             ├─ _on_board_card_pressed → _try_get_interaction_range → ok=false ─┐
             └─ _on_board_card_clicked → _try_get_interaction_range → ok=false ─┤
                                                                                │
                        _report_out_of_range_interaction(card, distance) ◄──────┘
                          ├─ print("[WorldInteraction] 拒绝超出范围的交互：…")   ← 原样保留
                          └─ _show_out_of_range_floating_text(card)
                               └─ FloatingText.show_at_target(card, "距离不够！")
                                   ├─ _resolve_target_screen_position(card)  ← 自读坐标
                                   ├─ 去重判定（同文案 + ≤8px + 0.2s）→ 第二次被拦掉
                                   └─ FloatingTextLabel.play(...) → 上飘 + 淡出 → queue_free
```

### 建筑（8 处离散提示 → 飘字）

| 原调用点 | 触发 | 锚点 | 颜色 |
| --- | --- | --- | --- |
| `_unhandled_input:218` | F 键交互结果 | 最近建筑世界坐标 | 按 `success` |
| `_confirm_placement:266` | 落点预检失败 | 鼠标世界落点 | 失败红 |
| `_confirm_placement:271` | 「建筑场景配置无效」 | 鼠标世界落点 | 失败红 |
| `_confirm_placement:279` | 放置服务结果 | 鼠标世界落点 | 按 `success` |
| `_begin_demolition:422` | 距离不足 / 遮挡 | 建筑世界坐标 | 失败红 |
| `_begin_demolition:427` | 「这座建筑不能拆除」 | 建筑世界坐标 | 失败红 |
| `_begin_demolition:434` | 「暂时无法拆除」 | 建筑世界坐标 | 失败红 |
| `_complete_demolition:471` | 拆除服务结果 | 建筑世界坐标（**拆除前固定**） | 按 `success` |

**为什么建筑一律用世界坐标而不是 `show_at_target(视图)`**：

1. `_complete_demolition` 提交后 `_store` 的 `BuildingsChanged` 会**同步重建 `_views`**，视图节点随即被释放 → 若传节点，`show_at_target` 会落到「失效目标回退鼠标位置」分支，飘字跑到鼠标上而不是建筑处。
2. 建筑视图的 `Icon` 子节点不保证存在，节点锚点需要额外兜底；而 `record["position"]` 是权威数据。
3. 建造失败时根本没有建筑节点，只有落点。

世界坐标统一由 `_room_scene.to_global(record["position"])` 求得，与 `_nearest_building:345`、`_is_record_in_range` 完全同一口径。

### 颜色规则（AC-10）

`building_service.gd` 的 `message` **同时承载成功与失败**（`"已放置 %s"`:58、`"已拆除 %s"`:121 是成功；`"这里已有建筑"`:32、`"这座建筑不能拆除"`:108 是失败）。因此：

- 有 `success` 字段的结果 → `bool(result["success"])` 为真用**白色**（沿用底部标签原本的默认观感），为假用服务默认**红**。
- 纯失败文案（预检原因、配置无效、不能拆除）→ 直接走服务默认**红**。

白色常量定义在建筑控制器内（`SUCCESS_TEXT_COLOR`），红色**只在服务里定义一次**（`DEFAULT_TEXT_COLOR`），建筑失败分支不传颜色参数、直接用服务默认值 ⇒ 红色不存在第二份副本。

## 4. `building_controller.gd` 的三处结构性改动

### 4.1 拆分距离门禁（行为逐位等价）

```gdscript
## 建筑是否在交互距离内；与遮挡判定分离，供「距离不够」提示区分原因。
func _is_record_in_range(record: Dictionary) -> bool:
	var point: Vector2 = _room_scene.to_global(record["position"])
	return _player_body.global_position.distance_to(point) <= float(record["data"].get("InteractionRadius"))


func _is_record_reachable(record: Dictionary) -> bool:
	# 交互与拆除共享同一距离门禁，不允许隔墙远程破坏。
	if not _is_record_in_range(record):      # ← 只把距离段换成独立入口
		return false
	# ... raycast 遮挡判定原样保留 ...
```

`_is_record_reachable()` 的既有调用方（`_nearest_building:348`、`_can_continue_demolition:452`、`_begin_demolition:421`）语义完全不变。

### 4.2 删除离散提示计时器，保留 `_hint` 的实时状态

**删除**：`@export FeedbackSeconds`（`:37`）、`_feedback`（`:72`）、`_feedback_left`（`:74`），以及 `:153`、`:223`、`:438` 三处 `_feedback_left` 写入。`_process(delta)` 不再使用 `delta`，参数改名为 `_delta`。

**保留并简化** `_hint`（它承担每帧实时状态，AC-11）：

```gdscript
# :238-240 建造预览：去掉 _feedback 分支，只留实时预检原因
_hint.text = "左键放置 %s · 右键 / Esc 取消\n%s" % [
	_placing_data.get("CardName"),
	"可以放置" if reason.is_empty() else reason]

# :250 拆除进行中：原样保留
_hint.text = "正在拆除 · 松开左键或移开鼠标取消"

# :255 交互提示：去掉 _feedback 分支
_hint.text = _interaction_prompt(record)
```

`HintPath` 导出与 `_hint` 节点继续保留 —— `tests/godot/building_system_tests.gd:354/361` 会注入一个真实 `Label` 并依赖它被解析。

### 4.3 飘字助手

```gdscript
## 建筑成功提示的颜色；沿用底部提示原本的白色，避免成功也显示成报错。
const SUCCESS_TEXT_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)

## 返回建筑的世界坐标；记录不存在时退回房间原点，保证提示不会跑到屏幕外。
func _building_world_position(instance_id: int) -> Vector2

## 按服务结果分色显示建筑提示。
func _show_building_result(instance_id: int, result: Dictionary) -> void

## 在建筑处显示固定失败文案。
func _show_building_failure(instance_id: int, message: String) -> void

## 在世界落点处显示提示。
func _show_world_floating_text(world_position: Vector2, message: String, text_color: Color) -> void
```

`_complete_demolition` 必须**在 `_cancel_demolition()` / `TryDemolish` 之前**固定 `instance_id`（现有代码已在 `:461` 固定 `instance_id`），锚点用 `_building_world_position(instance_id)` 提前求出；若取不到则退回 `result["position"]`（`TryDemolish` 成功时返回的房间局部坐标，`:122`）。

## 5. Compatibility & Risks

| 风险 | 说明 | 处置 |
| --- | --- | --- |
| **autoload 顺序** | `SaveManager` 必须是 `[autoload]` **第一项**（`state-management.md:129`）。 | `FloatingText` 追加在 `SettlementManager` 之后、`_mcp_game_helper` 之前，不动已有顺序。 |
| **test_run 无 autoload** | 裸标识符 → 解析失败。 | 强制 `NodePath` + `get_node_or_null` + `has_method`（2.4）。 |
| **建筑回归场景直接继承控制器** | `building_system_tests.gd:84` 有 `class ControllerInputProbe extends "res://core/building/building_controller.gd"`，会直接调 `_unhandled_input`/`_input`/`_begin_demolition`/`_process`/`_placement_failure`/`_complete_demolition`。 | 该文件**无** `FeedbackSeconds`/`_feedback`/`_hint.text` 断言（已 rg 确认）；飘字调用在 `/root/FloatingText` 缺失或目标无效时静默返回 ⇒ 断言不受影响。仍必须实跑该场景确认 `0 项失败`。 |
| **删除 `FeedbackSeconds` 留下失效场景字段** | `scenes/Main.tscn` 的 `BuildingController` 只序列化 `script`；全仓 `.tscn` 未序列化该字段。 | 已核实无残留，无需场景迁移。 |
| **文档漂移** | `docs/建筑系统.md:37` 记录了 `FeedbackSeconds`。 | AC-13 要求同步更新。 |
| **契约测试断言源码字面量** | `test_interaction_range_gate` 断言协调器**不含** `_card_display_name(`。 | 新增代码与注释都不得写出该字面量；实现后必须重跑该套件。 |
| **每帧函数触发飘字** | `_placement_failure()` 每帧调用。 | 飘字只挂 `_confirm_placement`；`_hint` 的实时原因行保留但**不**飘字。 |
| **`mouse_filter` 吞输入** | 全屏 Control 默认 `STOP` 会挡掉其下所有输入。 | 宿主与飘字都设 `MOUSE_FILTER_IGNORE`。 |
| **跨房卸载导致目标失效** | 卡牌可能在被提示前就被 `queue_free`。 | `_resolve_target_screen_position` 对失效目标回退鼠标位置；建筑侧一律用世界坐标，不依赖节点存活。 |
| **CanvasLayer 层级** | 飘字必须压在世界与 HUD 之上。 | 独立 `CanvasLayer`，`layer = 10`（> HUD 的 2）。 |
| **`const` 作默认参数值** | `text_color: Color = DEFAULT_TEXT_COLOR` 需要 GDScript 接受同类 `const` 作默认值。 | `implement.md` 设检查点：`filesystem_manage(op="scan")` 后若报解析错误，退回字面量默认值并在服务内注释说明。 |
| **暂停时动画** | 暂停菜单打开时飘字会冻结。 | 可接受：暂停期间交互本就被 `_has_open_overlay()` 拦住，不会产生新飘字。 |
| **成功文案被染红** | `message` 兼含成功与失败。 | AC-10 要求按 `success` 分色（2.3 节颜色规则）。 |

**回滚形状**：四处改动彼此独立、可分别回退 —— ① 删 `project.godot` 的 autoload 行（服务失效后所有调用方静默降级）；② 回退协调器一处调用；③ 回退建筑控制器（8 处调用 + 计时器删除 + 距离拆分）；④ 回退文档一行。新增文件直接删除即可，无数据/存档格式变更，无场景迁移。

## 6. 被否掉的备选方案

| 方案 | 否掉原因 |
| --- | --- |
| 复用 `CombatFeedbackPopup` | 用户明确选择新建独立组件以隔离战斗风险；取舍与代价已记入 `prd.md` 的 Notes（含技术债说明）。 |
| 飘字做成 `Main.tscn` 的 HUD 节点 + 各调用方 `@export` 路径 | 每接一个新调用方都要改场景 + 加导出路径，跨场景复用差；用户明确选了 autoload 服务。 |
| 世界空间 `Node2D` + `Label` 挂在卡牌位置 | 卡牌会被跨房卸载/飞行移出；且默认 canvas 内会与昼夜滤镜、地图层发生 `z_index` 竞争。屏幕空间方案彻底绕开。 |
| 要求 `BoardCardView` 暴露 `get_floating_text_anchor()` 协议 | 直接违反用户「不修改目标代码」的要求。 |
| 在 `_report_out_of_range_interaction()` 内直接 `new Label` 并手写字体/描边 | 不可复用、无去重、业务与表现耦合，正是要避免的写法。 |
| 用 `LabelSettings` 共享一份资源 | 见 2.3：会让每次调用的 `text_color` 失效。 |
| 把去重放在协调器里（记住上一张卡 + 上一帧） | 建筑侧要再写一份；组件侧统一去重才是可复用的做法。 |
| 建筑提示一律用红色 | 会把「已放置 / 已拆除」显示成报错。见 2.3 颜色规则。 |
| 建筑提示传视图节点（`show_at_target`） | 拆除成功后视图被同步重建释放 → 飘字回退到鼠标位置。见第 3 节说明。 |
| 把 `_hint` 的实时状态也改飘字 | 每帧刷新会持续刷屏；用户已确认只改离散提示。 |

## 7. Test Strategy

### `tests/godot/test_floating_text_contract.gd`（`@tool extends McpTestSuite`，由 `tests/test_floating_text_contract.gd` 顶层壳转发）

只做**静态形状断言**（与 `test_world_interaction_coordinator_contract.gd` 同口径 —— 非 `@tool` 生产脚本在编辑器中实例化后方法不可调用，因此套件锁源码形状，真实效果交给运行期）：

- 服务脚本存在，含必需常量：`GAME_FONT` 指向 `res://res/font/Uranus_Pixel_11Px.ttf`、`OUTLINE_COLOR` 为黑、`DEFAULT_TEXT_COLOR` 为红、`CANVAS_LAYER` 大于 2、`DEDUPE_SECONDS` 大于 0。
- 服务三个公开方法签名存在：`show_at_target` / `show_at_world` / `clear_all`。
- 服务用 `get_screen_transform()` 自读坐标（不依赖目标协议）。
- 表现组件 `mouse_filter` 设为 `MOUSE_FILTER_IGNORE`；用 `add_theme_color_override("font_outline_color", ...)` 与 `add_theme_constant_override("outline_size", ...)` 施加描边；**不出现** `label_settings`。
- 协调器：`FLOATING_TEXT_PATH` 为 `NodePath`；源码**不含**裸 `FloatingText.` 调用；`_report_out_of_range_interaction` 内既有 `print` 与新增调用同时存在。
- 协调器回归：源码**仍不含** `_card_display_name(`。
- 建筑控制器：`_is_record_in_range` 存在且被 `_is_record_reachable` 调用；`_placement_failure` 内**没有**飘字调用（防每帧刷屏）；`FeedbackSeconds` / `_feedback` / `_feedback_left` 已彻底移除；`_show_feedback` 已不存在；`SUCCESS_TEXT_COLOR` 存在；`_hint` 仍被解析。
- 目标零改动：`board_card_view.gd`、`building_view.gd`、`combat_feedback_popup.gd` 源码不含 `FloatingText` / `show_at_target`。
- `project.godot`：`[autoload]` 中 `SaveManager` 仍是第一项、`FloatingText` 已注册。
- `docs/建筑系统.md`：不再出现 `FeedbackSeconds`。

### 运行期（`test_run` 覆盖不到，必须用 MCP 实证）

- `project_run(mode="custom", scene="res://scenes/Main.tscn")`，`logs_read(source="game")` 确认无 `SCRIPT ERROR` / `Parse Error` / `Failed to load script`。
- `project_run(mode="custom", scene="res://tests/godot/building_system_tests.tscn")`，`logs_read(source="game")` 必须出现 `[BuildingSystem] 建筑测试：N 项断言，0 项失败`。**这是 AC-15 的唯一验证方式** —— 该文件不是 `test_*` 命名，`test_run` 不会发现它。
- `game_eval` 直接调服务验证样式与生命周期：生成一条飘字后断言 `text` / `font_outline_color`（黑）/ `outline_size` > 0 / `font_color`（红）/ `get_theme_font("font").resource_path` 为游戏字体 / `mouse_filter == 2`；等待 `DURATION + 余量` 后断言节点已自动释放。
- `game_eval` 验证去重：同帧连续两次 `show_at_target(同一张卡, "距离不够！")`，第二次返回 `null` 且宿主子节点只增加 1。
- 真实鼠标复现棋盘卡「距离不足」，`editor_screenshot(source="game")` 确认飘字在**卡牌处**、红色、有黑描边、五个汉字无豆腐块、**只有一条**。
- 建筑两条入口各验证一次（落点超 `PlacementRadius`、拆除超 `InteractionRadius`），并验证成功放置显示**白色**而非红色。
- 收尾：`project_manage(op="stop")` 停游戏，**不关编辑器**。
