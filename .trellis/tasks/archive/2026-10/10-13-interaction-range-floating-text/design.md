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

---

# Design 增量（2026-10-14）— 所需交互范围提示圈

## 8. 变更边界

### 新增

| 文件 | 角色 |
| --- | --- |
| `core/ui/feedback/interaction_range_ring.gd` | **表现组件**：`class_name InteractionRangeRing extends Node2D`。只负责「在给定屏幕坐标画一个空心圈、按时长淡出、然后释放自己」。半径已由服务换算成屏幕像素，组件不含业务、不读交互距离、不依赖 autoload。 |

### 修改

| 文件 | 改动 |
| --- | --- |
| `core/autoloads/floating_text.gd` | 预载圈脚本；新增圈的样式常量；`show_at_target` / `show_at_world` 追加可选第 4 参 `world_radius`；`_spawn` 追加 `ring_radius` 并在**去重门禁之后**先建圈再建字；新增 `_world_to_screen_scale(source)`。 |
| `core/gameflow/world_interaction_coordinator.gd` | 新增镜像色 `FAILURE_TEXT_COLOR`；`_show_out_of_range_floating_text(card)` 追加把 `InteractionRange` 作为圈半径传入（**函数签名与调用字面量不变**，见 8.3）。 |
| `core/building/building_controller.gd` | `_show_world_floating_text` 追加可选第 4 参 `world_radius`；新增 `_record_interaction_radius(record)` 与 `_show_building_out_of_range(record)`；`_begin_demolition` 的距离不足分支改走新助手。 |
| `tests/godot/test_floating_text_contract.gd` | 追加圈契约断言（新增套件方法，不改既有断言）。 |
| `.trellis/spec/frontend/component-guidelines.md` | 在「飘字提示（FloatingText）」一节追加范围圈契约。 |

### 明确不改

`core/board/board_card_view.gd`、`core/building/building_view.gd`、`core/building/building_service.gd`、`core/board/board_controller.gd`、任何 `scenes/**` 与 `.tres`。`show_at_target` / `show_at_world` 的**前 3 个参数与返回语义不变**，因此既有调用点是纯增量兼容。

## 9. Contracts

### 9.1 `InteractionRangeRing`（表现组件）

```gdscript
extends Node2D
class_name InteractionRangeRing

## 淡出结束、节点释放前发出；与 FloatingTextLabel 对称，供上层与测试确认动画真的走完。
signal finished

## 空心圆的分段数。
const SEGMENTS: int = 64

## 在屏幕坐标处配置并启动一次提示圈；淡出结束后 queue_free 自身。
##
## @param center 圈心的屏幕坐标；与飘字锚点相同，圈因此始终以目标为中心。
## @param radius 圈的屏幕半径（像素），由调用方按「世界半径 × 画布缩放」换算。
## @param line_color 圈线颜色。
## @param line_width 圈线宽度（像素）。
## @param duration 淡出总时长（秒）；必须与同批飘字相同，两者才会同步消失。
## @return void 无返回值。
func play(center: Vector2, radius: float, line_color: Color, line_width: float,
		duration: float) -> void
```

**为什么是 `Node2D` 而不是 `Control`**：

1. 圈不参与任何布局，`Node2D.position` 直接就是屏幕坐标，不需要像 `Label` 那样先 `reset_size()` 再把锚点换算成左上角。
2. `Node2D` 天然不参与 GUI 命中测试，不存在「全屏宿主漏设 `mouse_filter` 会静默吞输入」那类故障面。
3. `CanvasItem.modulate` 在 `Node2D` 上同样可用，淡出写法与浮字一致。

**`_draw()` 用 `draw_arc`**：`draw_arc` 只描边不填充，因此**天然是空心圈**，不需要 `draw_circle(filled := false)` 的额外参数组合。

**必须 `queue_redraw()`**：`_draw()` 只在进树时与 `queue_redraw()` 之后执行。节点进树时半径还是 `0`，若不显式重绘，圈会**永远画不出来且不报任何错**——这是本组件最容易踩的静默故障。

**`process_mode = Node.PROCESS_MODE_ALWAYS`**：与浮字同理，`Tween` 默认跟随宿主处理状态，暂停时冻住会让圈永久停在画面上。

### 9.2 服务新增常量与签名

```gdscript
## 圈脚本。
const RING_SCRIPT: GDScript = preload("res://core/ui/feedback/interaction_range_ring.gd")
## 圈线颜色：灰色半透明。世界贴图明暗差异大，纯灰不透明会抢走飘字的注意力。
const RANGE_RING_COLOR: Color = Color(0.62, 0.62, 0.66, 0.5)
## 圈线宽度（像素）。
const RANGE_RING_WIDTH: float = 3.0

func show_at_target(target: CanvasItem, text: String,
		text_color: Color = DEFAULT_TEXT_COLOR, world_radius: float = 0.0) -> Node
func show_at_world(world_position: Vector2, text: String,
		text_color: Color = DEFAULT_TEXT_COLOR, world_radius: float = 0.0) -> Node

func _spawn(text: String, screen_position: Vector2, text_color: Color,
		ring_radius: float = 0.0) -> Node
func _world_to_screen_scale(source: CanvasItem) -> float
```

`test_service_api_shape` 断言的是 `"func show_at_target(target: CanvasItem, text: String,"` 这一**行前缀**，第 4 参写在续行上，断言不受影响。

### 9.3 关键决策：圈必须由同一次 `_spawn` 产出

`_spawn` 是**唯一**的去重门禁（`_is_duplicate`）。若把画圈做成第二次公开调用，会有两个后果：

1. 同帧双发（`Pressed` + `Clicked`）会叠出**两个圈**——文字被去重、圈没有；
2. 圈与字之间只剩「调用方记得两个都调」的约定，没有结构性保证。

因此半径作为参数进入 `_spawn`，在 `_is_duplicate` **返回 false 之后**、与 `Label` 同一个函数体内生成 ⇒ 圈与字要么都有、要么都没有（AC-19 / AC-25）。

**顺序**：先 `add_child(ring)` 再 `add_child(label)`。同一宿主下按子节点顺序绘制，圈因此画在文字**之下**，不会压住「距离不够！」。

### 9.4 关键决策：半径用画布变换换算，不用目标自身的变换

```gdscript
func _world_to_screen_scale(source: CanvasItem) -> float:
	var transform: Transform2D = get_viewport().get_canvas_transform()
	if source != null and is_instance_valid(source) and source.is_inside_tree():
		transform = source.get_canvas_transform()
	var scale: Vector2 = transform.get_scale()
	return scale.x if not is_zero_approx(scale.x) else 1.0
```

已核实的事实（本次改动前实测）：

- `core/board/board_card_view.gd:145` `scale = _get_resting_scale()`，`:174`/`:181`/`:195` 还有入场与散布的缩放 Tween；`board_card_view.gd:228` 的 `_get_resting_scale()` 对地形卡返回 `TerrainCardRestingScale`，**不是 `1.0`**。若用 `target.get_screen_transform().get_scale()` 求半径，圈会随卡面缩放动画一起胀缩，而交互距离是「玩家中心 → 目标中心」的世界距离，与目标表现缩放无关。
- `BoardCardView`、`MapInstantiator` 下的房间、`Main/PlayerChar` **都在默认 canvas**：`scenes/Main.tscn:99` 的 `CardsRoot` 是 `Node2D`，`scenes/map_scenes/map_control.tscn:36` 的 `MapInstantiator` 也是 `Node2D`（同场景 `:45` 的 `CanvasLayer` 只装 MiniMap）。因此 `viewport.get_canvas_transform()` 与卡牌所在画布的变换**是同一个**，`show_at_world` 的既有换算口径对它同样成立。
- `CanvasItem.get_canvas_transform() -> Transform2D` 已由 `api_manage` 确认存在（Godot 4.7.1）。

取 `Transform2D.get_scale()` 的 `x` 分量：`Camera2D` 的 zoom 与画布比例在本工程内始终均匀；退化时退回 `1.0`，保证不会画出 `NaN` 半径。

### 9.5 同步淡出的实现口径

圈与字各自持有自己的 `Tween`，但：

- 两者在**同一帧**创建（同一次 `_spawn`）；
- 使用**同一个 `DURATION`** 常量；
- 使用**同一条曲线**：`tween_property(self, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)`。

⇒ 两条 alpha 曲线逐帧相同，满足 AC-22「与字体同步出现和消失」。两边都是入场即满不透明（字不做淡入，圈也不做），因此「同步出现」同样成立。

圈**不**参与 `position:y` 的上飘 Tween（AC-23）：只有 `Label` 有上飘。

## 10. 调用方接入

### 10.1 协调器（棋盘卡）

`test_floating_text_contract::test_coordinator_wires_floating_text` 用 `_count_occurrences(coordinator, "_show_out_of_range_floating_text(card)") == 1` 锁定了这一行字面量，因此**函数签名与调用形态都不动**，半径在函数体内取成员 `InteractionRange`：

```gdscript
## 失败提示的正文色；与飘字服务的 DEFAULT_TEXT_COLOR 同值。
##
## 传色是因为服务把半径排在颜色之后：只传半径就必须先给出颜色。
## 权威定义仍在服务的 DEFAULT_TEXT_COLOR，这里只做镜像；
## building_controller.gd 的 FAILURE_TEXT_COLOR 是同一做法的既有先例。
const FAILURE_TEXT_COLOR: Color = Color(1.0, 0.25, 0.2, 1.0)

func _show_out_of_range_floating_text(card: Node2D) -> void:
	if _floating_text == null or not is_instance_valid(_floating_text):
		return
	if not _floating_text.has_method(FLOATING_TEXT_SHOW_AT_TARGET):
		return
	# 第 4 个参数是「所需交互范围」提示圈的世界半径：圈心是卡牌、半径是玩家的可交互距离，
	# 玩家因此能一眼看出该站到哪个范围内。半径取 InteractionRange，
	# 与 _try_get_interaction_range 的判定口径完全相同，不引入第二处距离来源。
	_floating_text.call(FLOATING_TEXT_SHOW_AT_TARGET, card, OUT_OF_RANGE_TEXT,
		FAILURE_TEXT_COLOR, InteractionRange)
```

### 10.2 建筑（拆除距离不足）

```gdscript
## 在世界坐标处显示飘字；world_radius > 0 时叠加同心的「所需交互范围」提示圈。
##
## 参数顺序与服务逐位对齐，避免静默换序；既有 3 参数调用点保持可用。
func _show_world_floating_text(world_position: Vector2, message: String, text_color: Color,
		world_radius: float = 0.0) -> void:
	if message.is_empty() or not _has_floating_text():
		return
	_floating_text.call(FLOATING_TEXT_SHOW_AT_WORLD, world_position, message,
		text_color, world_radius)


## 读取建筑的交互半径；配置缺失或非法时返回 0.0（此时只飘字、不画圈）。
func _record_interaction_radius(record: Dictionary) -> float:
	var data: Resource = record.get("data") as Resource
	if data == null:
		return 0.0
	return maxf(0.0, float(data.get("InteractionRadius")))


## 在建筑处显示「距离不够！」，并叠加该建筑的所需交互范围提示圈。
##
## 半径取建筑自己的 InteractionRadius：交互距离是「玩家中心 → 建筑中心」的世界距离，
## 所以圈的半径就是该建筑允许玩家进入的范围，与 _is_record_in_range 口径完全一致。
func _show_building_out_of_range(record: Dictionary) -> void:
	_show_world_floating_text(_room_scene.to_global(record["position"]),
		OUT_OF_RANGE_TEXT, FAILURE_TEXT_COLOR, _record_interaction_radius(record))
```

`_begin_demolition` 的分支只把 `_show_building_failure(..., OUT_OF_RANGE_TEXT)` 换成 `_show_building_out_of_range(record)`；纯遮挡分支与其余 7 处离散提示**一律不传半径**（默认 `0.0`，不画圈）。

## 11. Risks（增量）

| 风险 | 说明 | 处置 |
| --- | --- | --- |
| **`queue_redraw` 漏写** | 进树时半径为 0，不重绘则圈永远不可见且**无任何报错** | `play()` 末尾必须 `queue_redraw()`；契约测试锁该字面量 |
| **半径用了目标自身 scale** | 地形卡 resting scale ≠ 1 且有缩放 Tween，圈会随卡面胀缩 | 用 `get_canvas_transform()`（9.4）；契约测试锁 `_world_to_screen_scale` |
| **同帧双发叠两个圈** | 圈若拆成第二次调用则不被去重 | 圈与字同在 `_spawn` 的去重门禁之后生成（9.3） |
| **契约测试锁定字面量** | `_count_occurrences(..., "_show_out_of_range_floating_text(card)") == 1`、`func show_at_target(target: CanvasItem, text: String,`、`func show_at_world(world_position: Vector2, text: String,` | 均按「只加续行参数 / 不动函数签名」实现 |
| **暂停时圈不消失** | 与浮字同理，`Tween` 会随宿主冻结 | 圈组件设 `process_mode = PROCESS_MODE_ALWAYS` |
| **圈压住飘字** | 同宿主同 `z_index`，按子节点顺序绘制 | 先 `add_child(ring)` 再 `add_child(label)` |
| **相机 zoom 非 1 时半径错** | 世界单位 ≠ 屏幕像素 | 半径乘 `_world_to_screen_scale(...)`；`game_eval` 用 `canvas_transform.get_scale()` 反查断言 |
| **`Node2D` 挂 `Control` 宿主下** | 布局系统是否会干扰 | 宿主不是 `Container`，不参与子节点布局；`Node2D.position` 即宿主局部坐标（= 屏幕坐标） |

**回滚形状**：删 `core/ui/feedback/interaction_range_ring.gd`，再把三处参数与两处调用点回退。因为 `world_radius` 是**带默认值的尾参**，回退调用点即可让圈整体消失，服务与组件可独立留在树上不产生副作用。

## 12. Test Strategy（增量）

### 契约套件（`test_run(suite="floating_text_contract")`，全部为静态源码形状断言）

- 圈脚本存在、`extends Node2D`、`class_name InteractionRangeRing`、有 `signal finished`。
- 圈脚本含 `process_mode = Node.PROCESS_MODE_ALWAYS`、含 `queue_redraw()`、含 `draw_arc(`、含 `modulate:a`、含 `queue_free()`。
- 圈脚本**不含**填充圆（`draw_circle(`），保证是空心圈。
- 服务侧：`preload("res://core/ui/feedback/interaction_range_ring.gd")`、`RANGE_RING_COLOR`（四通道 alpha 在 `(0,1)` 开区间 ⇒ 半透明）、`RANGE_RING_WIDTH`、`_world_to_screen_scale`、`source.get_canvas_transform()`、`ring_radius`。
- 协调器：`FAILURE_TEXT_COLOR` 存在；`InteractionRange` 作为第 4 个实参传给 `show_at_target`。
- 建筑：`world_radius` 尾参、`_record_interaction_radius`、`_show_building_out_of_range`、`InteractionRadius` 参与半径。
- **回归**：`_count_occurrences(coordinator, "_show_out_of_range_floating_text(card)")` 仍为 1（既有断言，不改）。

### 运行期（MCP 实证）

- `test_run(suite="floating_text_contract")` 与 `test_run(suite="world_interaction_coordinator_contract")` 全绿。
- `project_run(mode="custom", scene="res://tests/godot/building_system_tests.tscn")` → `0 项失败`。
- Main 冒烟无脚本错误；`game_eval`：
  - 调 `show_at_world(pos, "距离不够！", <红>, 160.0)` 后断言宿主下同时存在 1 个 `InteractionRangeRing` 与 1 个 `FloatingTextLabel`；圈 `position == pos`；圈 `modulate.a == 1`。
  - 断言圈半径满足 `|world_radius * canvas_scale - 期望|` 关系（用 `get_viewport().get_canvas_transform().get_scale().x` 反查）。
  - 去重：同帧连续两次同目标同文案调用，断言第二次返回 `null` 且圈的数量只增加 1。
  - 同步淡出：等 `DURATION * 0.5` 后断言圈的 `modulate.a` 与字的 `modulate.a` 差值小于 0.02；等 `DURATION + 0.3` 后断言两者都已释放、宿主子节点数回到 0。
- 真实鼠标复现棋盘卡「距离不足」并截图，确认圈以卡牌为中心、空心、灰色半透明、与飘字同时可见。
- `project_manage(op="stop")` 收尾，**不关编辑器**。

# Design 增量二（2026-10-14）— 圈与字锁定在目标处

## 13. 变更边界（增量二）

### 新增

| 文件 | 作用 |
| --- | --- |
| `core/ui/feedback/floating_text_anchor.gd` | `class_name FloatingTextAnchor`（`extends RefCounted`）——「如何在任意时刻求出屏幕坐标」的值对象，是本次唯一的新增类型。 |

### 修改

| 文件 | 改动 |
| --- | --- |
| `core/ui/feedback/floating_text_label.gd` | 锚点参数由 `Vector2` 换成 `FloatingTextAnchor`；上飘由 `position:y` 的 Tween 改为 `_rise` 标量，位置每帧由 `锚点 - size*0.5 - (0, _rise)` 合成。 |
| `core/ui/feedback/interaction_range_ring.gd` | 锚点参数换成 `FloatingTextAnchor`，半径参数由**屏幕**半径改回**世界**半径；`_process` 每帧重算圈心与半径。 |
| `core/autoloads/floating_text.gd` | `_spawn` 改收锚点对象；**删除** `_resolve_target_screen_position` 与 `_world_to_screen_scale`；`show_at_target` / `show_at_world` 只负责构造锚点。 |
| `tests/godot/test_floating_text_contract.gd` | 把两处指向服务的换算断言改为指向锚点文件，并新增「每帧重新求值」的回归护栏。 |

### 明确不改

- **调用方零改动**：`world_interaction_coordinator.gd` 与 `building_controller.gd` 一个字都不动。`show_at_target(target, text, text_color, world_radius)` / `show_at_world(world_position, text, text_color, world_radius)` 的签名与语义逐字保留（AC-32）。
- 层号 `CANVAS_LAYER = 10`、宿主结构、去重口径、时长、上飘距离、字体与颜色常量全部不变。

## 14. Contracts

### 14.1 `FloatingTextAnchor`（新增值对象）

```gdscript
extends RefCounted
class_name FloatingTextAnchor

## 锚点种类。TARGET 跟随一个存活节点，WORLD 跟随一个世界坐标。
enum Kind { TARGET, WORLD }

static func at_target(target: CanvasItem) -> FloatingTextAnchor
static func at_world(world_position: Vector2) -> FloatingTextAnchor

func resolve(viewport: Viewport) -> Vector2   ## 当前屏幕坐标
func world_scale(viewport: Viewport) -> float ## 当前「世界单位 → 屏幕像素」缩放
```

- `resolve()` 对 `Control` 目标取 `get_screen_transform() * (size * 0.5)`（左上角不是「目标处」），对 `Node2D` 目标取 `get_screen_transform().origin`——**与重构前的 `_resolve_target_screen_position` 逐位等价**，只是从「调用一次」变成「可反复调用」。
- `world_scale()` 用 `get_canvas_transform().get_scale().x`，**刻意不用** `get_screen_transform().get_scale()`（后者含目标自身的入场/散布缩放，会让圈随卡面胀缩——上一轮已实测：卡牌 `scale = 1.7` 会得到 `272` 而非 `160`）。比例退化时返回 `1.0`，保证不会算出 `NaN` 半径。
- 目标失效时的语义（`Kind.TARGET`）：
  - **生成时就已失效**（跨房卸载后调用方还握着旧节点）→ 退回 `viewport.get_mouse_position()`，与重构前的兜底一致；
  - **落位之后才失效** → 沿用最后一次成功求出的坐标，原地淡出。飘字只有 0.9 秒，中途跳位比停在旧位置更像故障。
- 依赖方向：锚点不知道调用方是谁、不引用任何 autoload，因此标签与圈仍然满足「组件不依赖任何 autoload」的既有约束（`floating_text_label.gd:5`）。

### 14.2 两个组件的签名变化

```gdscript
# floating_text_label.gd
func play(text: String, text_color: Color, font: Font, font_size: int,
		outline_size: int, outline_color: Color,
		anchor: FloatingTextAnchor, rise_distance: float, duration: float) -> void

# interaction_range_ring.gd
func play(anchor: FloatingTextAnchor, world_radius: float, line_color: Color,
		line_width: float, duration: float) -> void
```

两者都新增 `func _process(_delta: float) -> void` 每帧调用同一个 `_refresh()`：

```gdscript
# FloatingTextLabel
position = anchor.resolve(get_viewport()) - size * 0.5 - Vector2(0.0, _rise)

# InteractionRangeRing
position = anchor.resolve(get_viewport())
var radius: float = world_radius * anchor.world_scale(get_viewport())
if not is_equal_approx(radius, _radius):
    _radius = radius
    queue_redraw()
```

圈只在**半径**变化时 `queue_redraw()`：`_draw()` 画在 `Vector2.ZERO` 上，移动节点本身不需要重画。

### 14.3 服务的删除清单与 `_spawn`

```gdscript
func _spawn(text: String, anchor: FloatingTextAnchor, text_color: Color,
		world_radius: float = 0.0) -> Node
```

- 去重键仍需要一个坐标：`_is_duplicate(text, anchor.resolve(get_viewport()))`，只在生成那一帧求一次值，语义不变。
- 圈与字**共用同一个锚点实例**：`ring.call("play", anchor, world_radius, ...)` 与 `label.call("play", ..., anchor, ...)`。这是「要么都锁在目标上、要么都没有」的结构性保证（AC-34）。
- 删除 `_resolve_target_screen_position()` 与 `_world_to_screen_scale()`，换算逻辑只在锚点里存在一份（AC-33 / SR-17）。

## 15. 关键决策（增量二）

### 15.1 为什么是「每帧重算屏幕坐标」而不是「把飘字挪进世界空间」

备选 A：把飘字层放进默认世界画布，让相机变换自然带着它走。**被否**：① 飘字层在 `CanvasLayer(10)` 是为了**盖住 HUD**（`layer = 10 > HUDLayer = 2`），搬回默认画布就会掉到 HUD 之下；② 世界空间里文字会被相机 zoom 一起缩放，40px 的字在 2 倍变焦下变成 80px，这是用户没要求的视觉回归，要抵消它就得再加反向缩放，复杂度反而更高。

备选 B：让 `CanvasLayer.transform` 跟随 `viewport.get_canvas_transform()`，节点仍存世界坐标。**被否**：同样会让文字随 zoom 缩放；而且 `show_at_target` 原有的「目标失效→鼠标位置」兜底是**屏幕**坐标，改成世界坐标会把这个兜底的语义也一起改掉，波及面比收益大。

选定方案：保留屏幕空间承载，把「屏幕坐标」从**一个值**升级为**每帧可求值的锚点**。文字尺寸天然恒定，z 序不变，调用方零改动。

### 15.2 为什么锚点必须是独立对象，而不是在组件里各写一份

标签与圈都需要「目标 → 屏幕坐标」与「世界 → 屏幕缩放」这两件事。若各自实现，就是两份必须同步演进的换算逻辑（上一轮已经因为「半径该用画布变换还是目标变换」踩过一次坑）。抽成 `FloatingTextAnchor` 后，这条规则只有一个实现点，两个组件都退化为「向锚点要坐标」。

### 15.3 上飘必须从 `position:y` 的 Tween 改成标量偏移

重构前标签直接 Tween `position:y`，而 `_process` 又要每帧改写 `position`——两条写入路径会互相覆盖，表现为上飘抖动或被吃掉。因此上飘改为 Tween 一个标量 `_rise`（`0 → rise_distance`），`_process` 每帧用 `锚点 - size*0.5 - (0, _rise)` 合成最终位置：**每帧只有一个写入者**。

注意 Tween 的曲线语义保持不变：上飘 `TRANS_SINE`/`EASE_OUT`，淡出 `TRANS_SINE`/`EASE_IN`。

### 15.4 组件的 `process_priority` 必须晚于相机

`FloatingText` 是 autoload，在场景树里排在主场景**之前**，默认情况下它的子节点 `_process` 会在 `PlayerChar/Camera2D` **之前**执行：于是飘字用的是上一帧的画布变换，而世界是按这一帧的变换绘制的，快速平移时会看到圈与目标之间有一帧的「游泳」。给标签与圈设一个较晚的 `process_priority`（常量 `PROCESS_PRIORITY_LATE = 1000`）即可让它们总在相机更新之后求值。

## 16. Risks（增量二）

| 风险 | 影响 | 对策 |
| --- | --- | --- |
| `Tween` 无法驱动下划线私有成员 `_rise` | 上飘完全失效，且 Tween 在启动时就报错 | `tween_property` 走 `Object.set()`，脚本变量无论命名都是属性；仍由契约测试断言 `tween_property(self, "_rise"` 存在。 |
| `_process` 在 `play()` 之前就开始跑 | 锚点为 `null` 时访问崩溃 | `_refresh()` 首行判空直接返回；`_ready` 只设 `mouse_filter`/`process_mode`，不预设锚点。 |
| 半径每帧重算导致 `queue_redraw()` 抖动 | 每帧重画，纯浪费 | 仅当 `not is_equal_approx(新半径, 旧半径)` 时才 `queue_redraw()`。 |
| 圈与字拿到**不同**的锚点实例 | 两者可能锁在不同的位置上 | 同一次 `_spawn` 内构造一次、传给两者；契约测试断言 `_spawn` 内 `FloatingTextAnchor` 的构造只出现一次。 |
| 目标中途被 `queue_free()` | 访问已释放对象 → 运行时报错 | `resolve()` 每次先 `is_instance_valid()` + `is_inside_tree()`，失效即用缓存坐标。 |
| 删掉服务里的换算助手后测试未同步 | 契约套件变红（正是本次要防的） | 同步把 `test_service_api_shape` / `test_service_wires_range_ring` 的断言指向锚点文件，并新增锚点契约测试。 |

## 17. Test Strategy（增量二）

### 契约套件（`test_run(suite="floating_text_contract")`，静态源码形状断言）

- 新增 `test_anchor_component_shape`：断言锚点文件存在 `class_name FloatingTextAnchor`、`static func at_target(`、`static func at_world(`、`func resolve(viewport: Viewport) -> Vector2`、`func world_scale(viewport: Viewport) -> float`、`is_instance_valid(` 缓存分支、以及 `get_canvas_transform().get_scale()`。
- 新增 `test_components_re_resolve_anchor_each_frame`（**本次缺陷的回归护栏**）：断言两个组件都含 `func _process(`、都在 `_process` 路径里调用 `_anchor.resolve(`，且标签含 `tween_property(self, "_rise"` 而**不含** `tween_property(self, "position:y"`。
- 改写 `test_service_api_shape`：`_resolve_target_screen_position(target)` 与 `target.get_screen_transform().origin` 两条断言改到 `ANCHOR_GD` 上；服务侧改断言 `FloatingTextAnchor.at_target(target)`。
- 改写 `test_service_wires_range_ring`：`func _world_to_screen_scale(...)` 与 `source.get_canvas_transform()` 两条断言改到 `ANCHOR_GD`；`_spawn` 的尾参断言由 `ring_radius: float = 0.0` 改为 `world_radius: float = 0.0`。
- 既有断言（去重、层号、字体、`RING_SCRIPT.new()` 只出现一次、协调器 `_count_occurrences == 1`）全部保留不动。

### 运行期（MCP 实证，`test_run` 覆盖不到）

- **AC-29 / AC-30（本次核心）**：在 Main 场景里对一张真实卡牌调 `show_at_target(card, ...)`，然后**在同一段 `game_eval` 内**用 `camera.position += Vector2(120, 80)` 平移相机，断言：
  - 圈的 `position` 与字的中心仍等于 `card.get_screen_transform().origin`（容差 1px）；
  - 断言「若按生成时坐标不动」的旧值**已经不再相等**（证明相机确实移动了、断言不是空转）；
  - 相机 `zoom` 改变后圈半径等于 `InteractionRange × 新画布缩放`。
- **AC-31**：`card.queue_free()` 后再推进若干帧，断言圈与字的 `position` 不再变化、无报错、到时长后正常释放。
- **AC-34**：断言宿主下圈与字的锚点为**同一个对象**（`ring._anchor == label._anchor`）。（增量三已作废，见第 18 节）
- 既有运行期断言（同批产出、去重、同步淡出 alpha 差值、释放后宿主归零）全部复跑。
- `project_manage(op="stop")` 收尾，**不关编辑器**。

---

# 增量三 Design（2026-10-17 第三轮）— 世界坐标定位

> 本节**取代**第 13～17 节的全部设计结论（那三节描述的是「锚点 + 每帧重算」，已废弃）。
> 第 8～12 节（提示圈本身）除「半径换算」一处外仍然有效。

## 18. 变更边界（增量三）

| 文件 | 变更 |
| --- | --- |
| `core/autoloads/floating_text.gd` | `_ready()` 加 `follow_viewport_enabled = true`、宿主改为固定在原点；新增 `_resolve_target_world_position()`；`_spawn` 收世界坐标；删除 `PROCESS_PRIORITY_LATE`。 |
| `core/ui/feedback/floating_text_label.gd` | 删除 `_anchor` / `_rise` / `_process` / `_refresh`；`play()` 收 `center: Vector2`（世界坐标）写一次，上飘恢复 `Tween position:y`。 |
| `core/ui/feedback/interaction_range_ring.gd` | 删除 `_anchor` / `_world_radius` / `_process` / `_refresh`；`play()` 收世界坐标与**世界半径**，写一次；恢复无条件 `queue_redraw()`。 |
| `core/ui/feedback/floating_text_anchor.gd` | **删除**（连同 `.gd.uid`）。 |
| `tests/godot/test_floating_text_contract.gd` | 删 `test_anchor_component_shape`；`test_components_re_resolve_anchor_each_frame` 换成反向护栏 `test_hints_are_world_anchored_not_resolved_per_frame`。 |
| `core/gameflow/world_interaction_coordinator.gd`、`core/building/building_controller.gd` | **零改动**（增量一/二的调用点继续有效）。 |

## 19. 关键决策（增量三）

### 19.1 用 `follow_viewport_enabled` 让承载层变成世界坐标

```gdscript
_layer = CanvasLayer.new()
_layer.layer = CANVAS_LAYER
_layer.follow_viewport_enabled = true   # 子节点的 position 于是就是世界坐标
```

- **实测**：`host.get_canvas_transform() == get_viewport().get_canvas_transform()` → `true`。
- **收益**：位置只在 `play()` 里写一次；相机移动/缩放由引擎负责；`_process`、处理优先级、
  目标失效缓存、上飘标量合成**全部不再需要**。
- **保留 `CanvasLayer` 而非挂进世界画布**：层号 `10` 必须高于 HUD(2) 与昼夜滤镜(0)。
  实测运行期 `layer=10 / hud=2 / daynight=0`，`above_hud` 与 `above_daynight_filter` 均为 `true`。

### 19.2 宿主固定在原点，不用全屏 preset

`_host.position = Vector2.ZERO`。**不**使用 `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`：
anchors 以父级 CanvasItem 的 `anchorable_rect` 为参考，而跟随相机变换后该矩形不再固定在屏幕上，
会把所有飘字整体平移。实测宿主 `position` 为 `(0,0)`，且飘字世界坐标与目标 `global_position` 完全相等。

### 19.3 坐标语义

```gdscript
func show_at_target(...):
    return _spawn(text, _resolve_target_world_position(target), text_color, world_radius)

func show_at_world(world_position: Vector2, ...):
    return _spawn(text, world_position, text_color, world_radius)
```

`_resolve_target_world_position` 用 `get_global_transform()`（**不是** `get_screen_transform()`）：
`Control` 取 `* (size * 0.5)`，`Node2D` 取 `.origin`；目标已失效时把鼠标屏幕坐标用
`viewport.get_canvas_transform().affine_inverse()` 换算成世界坐标（**只在生成时一次**）。

### 19.4 半径不做任何换算

`world_radius` 直接交给圈组件：宿主层已带相机变换，`world_radius` 本身就是世界单位。
`_world_to_screen_scale` 与锚点的 `world_scale()` 一并删除。

## 20. Risks（增量三）

| 风险 | 说明 | 处置 |
| --- | --- | --- |
| **`follow_viewport_enabled` 被误删** | 一旦删掉，`position` 立刻退回屏幕语义，缺陷重现 | 契约测试锁 `_layer.follow_viewport_enabled = true` |
| **有人重新用全屏 preset 定位宿主** | 会整体平移所有飘字，且**不报错** | 契约测试锁 `_host.position = Vector2.ZERO` 且禁止该 preset 调用 |
| **有人把「每帧重算」重新引入** | 复杂度会成倍回来 | 契约测试反向断言两个组件都**不含** `func _process(` 与 `_anchor` |
| **测试用 `contains` 误伤注释** | 服务里讲解「不要用 PRESET_FULL_RECT」的注释会命中裸关键字 | 断言写成完整调用串；本文件已有 `_has_declaration_line()` 处理同类问题 |

## 21. Test Strategy（增量三）

- **契约套件**：`test_hints_are_world_anchored_not_resolved_per_frame`（14 条断言）反向锁定「没有每帧逻辑」，
  并锁定 `follow_viewport_enabled`、宿主原点、两个组件不含 `_process`/`_anchor`、
  上飘为 `Tween position:y`、圈 `position = center`、圈不含 `world_scale`。
- **运行期（核心）**：对真实 `BoardCardView` 调 `show_at_target(card, ..., 160)`，记录圈的 `position`
  与其屏幕坐标，然后 `camera.global_position += Vector2(120, 80)`，断言：
  - 圈的 `position` == 卡牌 `global_position`（世界坐标，AC-37）；
  - 平移后圈的 `position` **一字未改**（AC-36 前半）；
  - 平移后圈的屏幕坐标与卡牌 `get_screen_transform().origin` **逐位相等，漂移 `0.0px`**（AC-36 后半）；
  - `ring.is_processing() == false`、`label.is_processing() == false`（AC-35）。
- **AC-39**：`card.queue_free()` 后圈的世界坐标不变、日志无报错。
- **回归**：增量一的运行期断言全部复跑（无半径、去重、同步淡出、自释放、宿主归零）。
