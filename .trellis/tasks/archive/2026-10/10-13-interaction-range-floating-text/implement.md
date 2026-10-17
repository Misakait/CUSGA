# Implement — 交互距离不足飘字提示组件

> 前置：本文件与 `design.md` 必须经用户复核后才执行 `task.py start`。实施阶段每个检查点都要在 Godot 编辑器 MCP 上跑，不得用命令行 Godot 或 .NET 工具链。

## 步骤 0 — 环境与基线（不写代码）

- [ ] **0.1** 确认编辑器在线并已加载 CUSGA：
  `editor_manage(op="state")` → 期望 `readiness == "ready"`、`project_name == "CUSGA"`、`godot_version` 为 `4.7.1`。
  - 若未连接：**停下来要求用户打开 Godot 编辑器**，不得改用命令行 Godot。
- [ ] **0.2** 记录基线绿灯，避免把既有失败误算到本次改动：
  - `test_run(suite="world_interaction_coordinator_contract")`
  - `project_run(mode="custom", scene="res://tests/godot/building_system_tests.tscn")` → `logs_read(source="game")` → 记下 `[BuildingSystem] 建筑测试：N 项断言，M 项失败` 的原始 M。
  - ⚠️ `building_system_tests.gd` **不是** `test_*` 命名，`test_run` 发现不了它，只能按上面方式跑场景。不要写 `test_run(suite="building_system")`，那会报找不到套件。
- [ ] **0.3** 确认工作区干净：`git status --porcelain` 应为空（或只含用户既有改动，逐条记下）。

**Gate 0**：编辑器在线 + 两个基线结果已记录。未过不得进入步骤 1。

## 步骤 1 — 表现组件 `FloatingTextLabel`

- [ ] **1.1** 新建 `core/ui/feedback/floating_text_label.gd`：

```gdscript
extends Label
## 单条飘字的表现组件：只负责「怎么画、怎么动、何时释放」，不含业务与坐标知识。
class_name FloatingTextLabel

## 播放结束、节点释放前发出。
signal finished

func _ready() -> void:
	# 必须忽略鼠标，否则全屏宿主下的飘字会吞掉其下所有输入。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

## 配置并启动一次飘字；结束后自动释放自身。
## 参数与返回值说明见 design.md 2.1。
func play(text: String, text_color: Color, font: Font, font_size: int,
		outline_size: int, outline_color: Color,
		rise_distance: float, duration: float) -> void:
	self.text = text
	# 用 theme override 而非 LabelSettings：LabelSettings 一旦设置就会盖掉 font_color 覆盖项，
	# 导致每次调用传入的颜色失效（所有在飞飘字一起变色）。
	add_theme_font_override("font", font)
	add_theme_font_size_override("font_size", font_size)
	add_theme_color_override("font_color", text_color)
	add_theme_constant_override("outline_size", outline_size)
	add_theme_color_override("font_outline_color", outline_color)

	# 先按文字实际尺寸确定自身大小，再把锚点挪到中心，保证飘字以目标为中心展开。
	reset_size()
	pivot_offset = size * 0.5

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - rise_distance, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.finished.connect(_on_play_finished, CONNECT_ONE_SHOT)

func _on_play_finished() -> void:
	finished.emit()
	queue_free()
```

- [ ] **1.2** 关键点自查（写完立刻看，别等到运行）：
  - `mouse_filter` 是否真的设了（漏了会静默吞输入，不报错）。
  - 是否有 `queue_free()`，否则飘字永久堆积。
  - 是否**没有**出现 `label_settings`（出现就会盖掉 `font_color`）。
  - 全部注释为中文，公开方法与类都有 `##` 文档注释（含参数与返回值说明）。

- [ ] **1.3** 刷新文件系统：`filesystem_manage(op="scan")`，确认 `class_name FloatingTextLabel` 注册成功。
  - `logs_read(source="editor")` 确认没有新增 `Parse Error`。

**Gate 1**：`FloatingTextLabel` 可被扫描到、无解析错误。

## 步骤 2 — 服务 `FloatingText`

- [ ] **2.1** 新建 `core/autoloads/floating_text.gd`，按 `design.md` 2.2 实现：
  - 常量：`GAME_FONT` / `LABEL_SCRIPT` / `CANVAS_LAYER = 10` / `DEFAULT_TEXT_COLOR`（红）/ `FONT_SIZE` / `OUTLINE_SIZE` / `OUTLINE_COLOR`（黑）/ `RISE_DISTANCE` / `DURATION` / `DEDUPE_SECONDS` / `DEDUPE_RADIUS`。
  - **不声明 `class_name`**（避免与全局单例名 `FloatingText` 冲突）。
  - `_ready()`：建 `CanvasLayer`（`layer = CANVAS_LAYER`）→ 建全屏 `Control` 宿主（`set_anchors_and_offsets_preset(PRESET_FULL_RECT)`、`mouse_filter = MOUSE_FILTER_IGNORE`）。
  - 公开：`show_at_target(target, text, text_color = DEFAULT_TEXT_COLOR) -> Node`、`show_at_world(world_position, text, text_color = DEFAULT_TEXT_COLOR) -> Node`、`clear_all() -> void`。
  - 私有：`_resolve_target_screen_position(target)`（失效目标回退鼠标位置；`Control` 取尺寸中心；`Node2D` 取 `get_screen_transform().origin`）、`_spawn(...)`（含去重）、`_is_duplicate(text, screen_position)`。
  - 去重条目用 `Time.get_ticks_msec()` + `DEDUPE_SECONDS` 判定过期。

- [ ] **2.2** ⚠️ **检查点（design.md 5 的未决项 U1）**：确认 GDScript 是否接受同类 `const` 作默认参数值。
  - 若 `filesystem_manage(op="scan")` 或 `logs_read(source="editor")` 报解析错误 → 把 `text_color: Color = DEFAULT_TEXT_COLOR` 改为字面量默认值，并在常量处加中文注释说明二者同值。
  - 结论必须写回本文件，不要留在脑子里。

- [ ] **2.3** 注册 autoload：`autoload_manage(op="add", params={"name": "FloatingText", "path": "res://core/autoloads/floating_text.gd"})`
  - **顺序约束**：`SaveManager` 必须仍是 `[autoload]` **第一项**。用 `autoload_manage(op="list")` 核对；若工具把它插到了 `SaveManager` 之前，手工调整 `project.godot` 顺序使其位于 `SettlementManager` 之后、`_mcp_game_helper` 之前。

- [ ] **2.4** `filesystem_manage(op="scan")` + `logs_read(source="editor")` 确认零解析错误。

**Gate 2**：autoload 已注册且顺序正确，服务脚本无解析错误。

## 步骤 3 — 棋盘卡接入（协调器）

- [ ] **3.1** 在 `core/gameflow/world_interaction_coordinator.gd` 顶部常量区加：

```gdscript
## 飘字服务路径；必须走 NodePath，裸 autoload 标识符在 test_run（无 autoload）下会解析失败。
const FLOATING_TEXT_PATH: NodePath = ^"/root/FloatingText"
## 距离不足时的提示文案。
const OUT_OF_RANGE_TEXT: String = "距离不够！"
```

- [ ] **3.2** 加成员变量 `var _floating_text: Node = null`，并在 `_ready()`（现第 159 行起）内 `_floating_text = get_node_or_null(FLOATING_TEXT_PATH)`。

- [ ] **3.3** 在 `_report_out_of_range_interaction()`（现第 421 行）的 `print` **之后**追加调用，`print` 原样保留：

```gdscript
	# 画面反馈与调试日志共用同一漏斗：两处鼠标入口都会走到这里，不会漏提示。
	_show_out_of_range_floating_text(card)
```

- [ ] **3.4** 新增私有方法（按 `design.md` 2.4 的 `has_method` + `call` 写法，只传目标与文案，颜色用服务默认红）：

```gdscript
## 在交互目标处提示距离不足。
##
## 服务缺失时静默降级：只保留 _report_out_of_range_interaction 的调试日志，不报错。
## 这里用 has_method + call 而非 preload 服务脚本，使协调器与服务之间没有编译期耦合。
##
## @param target 被拒绝交互的卡牌视图。
## @return 无返回值。
func _show_out_of_range_floating_text(target: CanvasItem) -> void:
	if _floating_text == null or not is_instance_valid(_floating_text):
		return
	if not _floating_text.has_method("show_at_target"):
		return
	_floating_text.call("show_at_target", target, OUT_OF_RANGE_TEXT)
```

- [ ] **3.5** ⚠️ **回归红线**：新增的代码与注释**不得**出现字面量 `_card_display_name(`（名字 + 左括号）。既有契约测试 `test_interaction_range_gate` 断言协调器源码不含它。
  - 自检：`grep -n "_card_display_name(" core/gameflow/world_interaction_coordinator.gd` 必须**无输出**。

**Gate 3**：协调器改动完成，`_card_display_name(` 自检为空。

## 步骤 4 — 建筑接入（8 处离散提示 + 计时器移除）

> 本步骤改动面最大，且 `tests/godot/building_system_tests.gd` 会**直接继承**这个脚本并调用其私有方法。每完成一小段就重跑一次该场景（步骤 6.2），不要攒到最后。

- [ ] **4.1** 常量与成员：加 `FLOATING_TEXT_PATH`、`OUT_OF_RANGE_TEXT`（同 3.1）、`SUCCESS_TEXT_COLOR = Color(1.0, 1.0, 1.0, 1.0)`，加成员 `var _floating_text: Node = null`，在 `_ready()`（现第 80 行起）内解析。

- [ ] **4.2** 拆出距离入口，`_is_record_reachable()` 保持逐位等价（见 `design.md` 4.1）：

```gdscript
## 建筑是否在交互距离内。
##
## 与遮挡判定分离，使「距离不够」提示能区分原因；口径与 _is_record_reachable 完全一致。
##
## @param record 建筑仓库记录。
## @return 玩家与建筑中心的世界距离不超过 InteractionRadius 时为 true。
func _is_record_in_range(record: Dictionary) -> bool:
	var point: Vector2 = _room_scene.to_global(record["position"])
	return _player_body.global_position.distance_to(point) <= float(record["data"].get("InteractionRadius"))
```

并把 `_is_record_reachable()` 开头的距离判定换成 `if not _is_record_in_range(record): return false`，raycast 段原样保留。

- [ ] **4.3** 新增飘字助手（`design.md` 4.3）：

```gdscript
## 返回建筑的世界坐标；记录不存在时退回房间原点，保证提示不会跑到屏幕外。
func _building_world_position(instance_id: int) -> Vector2

## 在指定目标处显示飘字；目标或服务不可用时静默跳过。
func _show_floating_text_at(target: CanvasItem, message: String, text_color: Color) -> void

## 在世界落点处显示飘字；服务不可用时静默跳过。
func _show_world_floating_text(world_position: Vector2, message: String, text_color: Color) -> void

## 按服务结果分色显示建筑提示：成功白、失败红。
func _show_building_result(instance_id: int, result: Dictionary) -> void

## 在建筑处显示固定失败文案（红色）。
func _show_building_failure(instance_id: int, message: String) -> void
```

- [ ] **4.4** 逐处替换 8 个 `_show_feedback` 调用点（锚点与颜色见 `design.md` 第 3 节表格）：

| 行 | 替换为 |
| --- | --- |
| `:218`（F 键交互） | `_show_building_result(int(record["id"]), result)` |
| `:266`（落点预检失败） | `_show_world_floating_text(point, reason, 失败红)` |
| `:271`（配置无效） | `_show_world_floating_text(point, "建筑场景配置无效", 失败红)` |
| `:279`（放置结果） | `_show_world_floating_text(point, String(result.get("message", "")), 按 success 分色)` |
| `:422`（拆除距离/遮挡） | 见 4.5 |
| `:427`（不能拆除） | `_show_building_failure(instance_id, "这座建筑不能拆除")` |
| `:434`（暂时无法拆除） | `_show_building_failure(instance_id, "暂时无法拆除")` |
| `:471`（拆除结果） | `_show_building_result(instance_id, result)` |

- [ ] **4.5** 拆除入口 `_begin_demolition()`（现第 421-423 行）按 `design.md` 区分距离与遮挡：

```gdscript
	if not _is_record_reachable(record):
		# 距离不足统一用与棋盘卡相同的文案；纯遮挡只讲障碍，
		# 避免距离充足时旧合并文案还叫玩家「靠近建筑」。
		if not _is_record_in_range(record):
			_show_building_failure(int(record["id"]), OUT_OF_RANGE_TEXT)
		else:
			_show_building_failure(int(record["id"]), "中间有障碍，无法拆除")
		return
```

- [ ] **4.6** `_complete_demolition()`：**在 `_cancel_demolition()` 之前**固定 `instance_id`（现有 `:461` 已有），并用它播报结果。**不要**传视图节点 —— 拆除成功会同步重建 `_views`，节点随即释放，飘字会回退到鼠标位置。

- [ ] **4.7** ⚠️ **不要**把飘字加进 `_placement_failure()` —— 它每帧被 `_process` 调用做预览。落点飘字只在 `_confirm_placement()`（现第 264 行起）的真实左键提交分支触发。

- [ ] **4.8** 移除离散提示计时器：
  - 删 `@export_range(0.1, 10.0) var FeedbackSeconds: float = 2.5`（`:37`）
  - 删 `var _feedback: String = ""`（`:72`）、`var _feedback_left: float = 0.0`（`:74`）
  - 删 `:153`、`:223`、`:438` 三处 `_feedback_left` 写入
  - 删 `_show_feedback()`（`:619-621`）整个函数
  - `_process(delta)` 不再用 `delta` → 参数改名 `_delta`
  - 自检：`grep -n "FeedbackSeconds\|_feedback" core/building/building_controller.gd` 必须**无输出**

- [ ] **4.9** 简化 `_hint` 的三处 `_feedback` 引用，**保留** `_hint` 与 `HintPath`（每帧实时状态，AC-11）：
  - `:238-240` → `"左键放置 %s · 右键 / Esc 取消\n%s" % [_placing_data.get("CardName"), "可以放置" if reason.is_empty() else reason]`
  - `:250` → 原样保留
  - `:255` → `_hint.text = _interaction_prompt(record)`

- [ ] **4.10** 同步更新 `docs/建筑系统.md`：删除或改写 `FeedbackSeconds | 2.5 秒 | 一次结果提示的显示时长` 所在行，说明建筑结果提示已改由 `FloatingText` 飘字承担。

**Gate 4**：建筑改动完成；`FeedbackSeconds`/`_feedback` 自检为空；`_placement_failure` 内无飘字；`_hint` 仍被解析。

## 步骤 5 — 契约测试

- [ ] **5.1** 新建 `tests/godot/test_floating_text_contract.gd`（`@tool` + `extends McpTestSuite`），按 `design.md` 第 7 节的断言清单实现，全部为静态源码形状断言。
- [ ] **5.2** 新建顶层转发壳 `tests/test_floating_text_contract.gd`：

```gdscript
@tool
extends "res://tests/godot/test_floating_text_contract.gd"
```

  - 原因：`test_run` 只扫描 `res://tests` **顶层**；真实套件放 `tests/godot/`，顶层壳负责转发（与 `tests/test_world_interaction_coordinator_contract.gd` 同一做法）。

- [ ] **5.3** `filesystem_manage(op="scan")` 后运行 `test_run(suite="floating_text_contract")`。

**Gate 5**：新套件全绿。

## 步骤 6 — 回归与运行期验证

- [ ] **6.1** 回归既有 `test_run` 套件：
  `test_run(suite="world_interaction_coordinator_contract")`
  `test_run(suite="floating_text_contract")`
  - 期望：与 Gate 0 记录的基线一致，**无新增失败**。重点看 `test_interaction_range_gate`。

- [ ] **6.2** ⚠️ **建筑回归场景（AC-15，唯一验证方式）**：
  `project_run(mode="custom", scene="res://tests/godot/building_system_tests.tscn")`
  `logs_read(source="game")` → 必须出现 `[BuildingSystem] 建筑测试：N 项断言，0 项失败`，且 N 不低于 Gate 0 的基线。
  - 若出现 `push_error` 行，逐条对照是否为本次改动引入。
  - `project_manage(op="stop")`。

- [ ] **6.3** 冒烟启动主场景：
  `project_run(mode="custom", scene="res://scenes/Main.tscn")`
  `logs_read(source="game")` → 不得出现 `SCRIPT ERROR` / `Parse Error` / `Failed to load script`。
  - 特别注意：协调器历史上曾因误用未定义助手而「整个脚本解析失败、游戏启动即卡 debugger break」。若 `game_status.status == "break"`，先 `project_manage(op="stop")`，再查 `logs_read(source="editor")`。

- [ ] **6.4** `game_eval` 验证服务与表现样式：

```gdscript
var svc := get_node("/root/FloatingText")
var n1 = svc.show_at_world(Vector2(400, 300), "距离不够！")
return {
  "text": n1.text if n1 != null else "",
  "outline_size": n1.get_theme_constant("outline_size") if n1 != null else -1,
  "outline_color": str(n1.get_theme_color("font_outline_color")) if n1 != null else "",
  "font_color": str(n1.get_theme_color("font_color")) if n1 != null else "",
  "font_path": n1.get_theme_font("font").resource_path if n1 != null else "",
  "mouse_filter": n1.mouse_filter if n1 != null else -1,
}
```

  - 断言：`text == "距离不够！"`、`outline_size > 0`、`outline_color` 为黑、`font_color` 为红、`font_path == "res://res/font/Uranus_Pixel_11Px.ttf"`、`mouse_filter == 2`。

- [ ] **6.5** `game_eval` 验证自动释放：等待 `DURATION + 0.3` 秒后断言该节点 `is_instance_valid() == false`。

- [ ] **6.6** `game_eval` 验证去重：同一次调用里连续两次 `show_at_target(同一张卡, "距离不够！")`，断言第二次返回 `null`、宿主子节点数只增加 1。

- [ ] **6.7** **真实鼠标**复现棋盘卡「距离不足」：
  - 用 `game_eval` 读取玩家与某张卡的世界坐标，确认二者距离 > `InteractionRange`（160）。
  - `game_manage(op="input_mouse", ...)` 在该卡屏幕位置发送左键按下 + 松开。
  - `editor_screenshot(source="game")` 截图确认：飘字在**卡牌图标处**、红色、有黑色描边、「距离不够！」五个汉字完整无豆腐块、**只有一条**（验证同帧双发去重）。

- [ ] **6.8** 建筑提示验证：
  - 落点超 `PlacementRadius` → 截图确认落点处红色「距离不够！」。
  - 拆除超 `InteractionRadius` → 截图确认建筑处红色「距离不够！」。
  - **成功放置**一栋建筑 → 截图确认提示为**白色**（不是红），验证 AC-10 分色。
  - 确认底部 `BuildingHint` 不再出现失败文案，但仍显示实时状态（建造预览说明 / 拆除进行中 / F 交互提示）。

- [ ] **6.9** `project_manage(op="stop")` 停止游戏。**不得关闭 Godot 编辑器。**

**Gate 6**：无脚本错误；建筑回归场景 `0 项失败`；服务行为符合断言；截图确认视觉、位置与分色；同帧双发只有一条。

## 步骤 7 — 收尾

- [ ] **7.1** `git status --porcelain` 复查：只保留本次任务需要的改动。
  - Godot 编辑器可能改写版本控制文件（`.godot/`、`*.uid` 等）；不得覆盖用户既有改动。
  - 新增脚本会生成 `.gd.uid` 旁车，属于本任务产物，保留。
- [ ] **7.2** 按 `.trellis/spec/frontend/quality-guidelines.md` 复核：制表符缩进、LF、显式返回类型、中文 `##` 注释齐全。
- [ ] **7.3** 更新 spec（走 `trellis-update-spec`）：
  - `.trellis/spec/frontend/component-guidelines.md` 写入飘字组件契约与「工程内存在两个浮字节点」的已知技术债。
  - 记录 `LabelSettings` 会盖掉 `theme_override` 颜色这一坑。
- [ ] **7.4** 归档任务：`python ./.trellis/scripts/task.py archive 10-13-interaction-range-floating-text`（先确认质量门通过）。

## 回滚点

| 回滚点 | 操作 | 影响 |
| --- | --- | --- |
| R1（Gate 2 后） | 删除两个新脚本 + `autoload_manage(op="remove", params={"name": "FloatingText"})` | 完全回到初始状态，调用方尚未改动。 |
| R2（Gate 4 后） | 回退协调器 1 处调用 + 建筑控制器全部改动 + 文档一行 | 服务保留但无消费方，功能等价于未接入。 |
| R3（任意时刻） | 只删 `project.godot` 的 autoload 行 | 所有调用方静默降级（建筑不再有任何离散提示、棋盘卡只剩日志），不报错、不影响交互判定。**注意**：建筑侧此时会丢失全部离散提示，回滚时须一并恢复 `_show_feedback` 机制。 |

无存档格式、`.tres` 字段或节点路径变更，因此不存在需要数据迁移的回滚。

## 待办：实施期需回报的未决项

- [ ] **U1** GDScript 是否接受同类 `const` 作默认参数值（步骤 2.2 的结论）。
- [ ] **U2** `autoload_manage(op="add")` 的插入位置是否满足 `SaveManager` 仍为第一项（步骤 2.3）。
- [ ] **U3** 像素字体在 `font_size = 28` / `outline_size = 6` 下的实际可读性与描边观感，必要时微调并回报。
- [ ] **U4** 建筑失败提示改飘字后，是否仍需保留某种「最近一次结果」的驻留（当前为 0.9 秒飘字后消失，比原 2.5 秒底部提示短）。若观感上信息量不足，回报用户再定。

---

# Implement 增量（2026-10-14）— 所需交互范围提示圈

> 前置：`design.md` 第 8-12 节。本增量是**纯追加**：`show_at_target` / `show_at_world` 的前 3 个参数与返回语义不变，`world_radius` 是带默认值的尾参。

## 步骤 8 — 圈表现组件

- [ ] **8.1** 新建 `core/ui/feedback/interaction_range_ring.gd`（`design.md` 9.1）：`extends Node2D` + `class_name InteractionRangeRing`；`signal finished`；`const SEGMENTS: int = 64`；`play(center, radius, line_color, line_width, duration)`；`_draw()` 用 `draw_arc(Vector2.ZERO, _radius, 0.0, TAU, SEGMENTS, _line_color, _line_width, true)`。
- [ ] **8.2** 关键点自查（写完立刻看，别等到运行）：
  - `_ready()` 是否设了 `process_mode = Node.PROCESS_MODE_ALWAYS`（漏了暂停时圈会永久残留）。
  - `play()` 末尾是否有 `queue_redraw()`（漏了圈**永远不可见且不报错**）。
  - 是否**没有** `draw_circle(`（那是实心圆，本次要空心）。
  - 是否有 `queue_free()`；`_exit_tree()` 是否 kill 了 Tween。
  - 全部注释为中文，类与公开方法都有 `##` 文档注释（含参数与返回值说明）。
- [ ] **8.3** `filesystem_manage(op="scan")` → `logs_read(source="editor")` 确认无 `Parse Error`，`class_name InteractionRangeRing` 注册成功。

**Gate 8**：圈组件可被扫描到、无解析错误。

## 步骤 9 — 服务接入圈

- [ ] **9.1** `core/autoloads/floating_text.gd` 顶部追加（`design.md` 9.2）：

```gdscript
## 所需交互范围提示圈的表现组件。
const RING_SCRIPT: GDScript = preload("res://core/ui/feedback/interaction_range_ring.gd")
## 圈线颜色：灰色半透明。
const RANGE_RING_COLOR: Color = Color(0.62, 0.62, 0.66, 0.5)
## 圈线宽度（像素）。
const RANGE_RING_WIDTH: float = 3.0
```

- [ ] **9.2** 给 `show_at_target` / `show_at_world` 追加尾参 `world_radius: float = 0.0`（**第 1、2 行前缀必须逐字不变**，契约测试按行前缀断言），并把半径乘上 `_world_to_screen_scale(...)` 后交给 `_spawn`。
- [ ] **9.3** 新增 `_world_to_screen_scale(source: CanvasItem) -> float`（`design.md` 9.4）：用 `get_canvas_transform()`，`source` 为空/失效/不在树上时退回 `get_viewport().get_canvas_transform()`；`get_scale().x` 为 0 时退回 `1.0`。
- [ ] **9.4** `_spawn` 追加尾参 `ring_radius: float = 0.0`，并在 `_is_duplicate` **返回 false 之后**、`Label` **之前**插入建圈代码（`design.md` 9.3）：
  - 先 `add_child(ring)` 再 `add_child(label)`（圈画在字下面）。
  - 圈用同一个 `DURATION`，因此与字同步淡出。
- [ ] **9.5** `filesystem_manage(op="scan")` → `logs_read(source="editor")` 零解析错误。

**Gate 9**：服务可扫描、两个入口签名前两行未变。

## 步骤 10 — 调用方传入半径

- [ ] **10.1** `core/gameflow/world_interaction_coordinator.gd`：常量区加 `FAILURE_TEXT_COLOR`（与服务 `DEFAULT_TEXT_COLOR` 同值，注释说明是镜像）；`_show_out_of_range_floating_text(card)` **签名与调用形态保持不变**，只在函数体内把 `call` 补成 4 参、第 4 参传 `InteractionRange`。
- [ ] **10.2** ⚠️ **回归红线**：自检字面量 `_show_out_of_range_floating_text(card)` 在协调器源码中仍只出现 **1** 次（定义行写作 `_show_out_of_range_floating_text(card: Node2D)`，不匹配该字面量）。
  - 同时自检 `_card_display_name(` 仍**无输出**。
- [ ] **10.3** `core/building/building_controller.gd`：
  - `_show_world_floating_text` 追加尾参 `world_radius: float = 0.0`，`call` 补第 5 个实参（参数顺序与服务逐位对齐，不换序）。
  - 新增 `_record_interaction_radius(record) -> float` 与 `_show_building_out_of_range(record) -> void`。
  - `_begin_demolition` 距离不足分支：`_show_building_failure(int(record["id"]), OUT_OF_RANGE_TEXT)` → `_show_building_out_of_range(record)`。
  - 纯遮挡分支与其余 7 处离散提示**不传半径**（默认 0 = 不画圈）。
- [ ] **10.4** `filesystem_manage(op="scan")` → `logs_read(source="editor")` 零解析错误。

**Gate 10**：两条交互路径都在「距离不够」时带上半径；其它提示不带。

## 步骤 11 — 契约测试与验证

- [ ] **11.1** `tests/godot/test_floating_text_contract.gd` 追加套件方法（**不改既有断言**，断言清单见 `design.md` 第 12 节）。
- [ ] **11.2** `filesystem_manage(op="scan")` → `test_run(suite="floating_text_contract")` 全绿。
- [ ] **11.3** 回归 `test_run(suite="world_interaction_coordinator_contract")`。
- [ ] **11.4** `project_run(mode="custom", scene="res://tests/godot/building_system_tests.tscn")` → `logs_read(source="game")` 必须 `0 项失败`；`project_manage(op="stop")`。
- [ ] **11.5** Main 冒烟：`project_run(mode="custom", scene="res://scenes/Main.tscn")`，`logs_read(source="game")` 无 `SCRIPT ERROR` / `Parse Error` / `Failed to load script`。
- [ ] **11.6** `game_eval` 断言（`design.md` 第 12 节）：圈与字同批产生、圈心 = 锚点、半径 = 世界半径 × 画布缩放、去重后圈只增 1、半程 alpha 同步、`DURATION + 0.3` 后双双释放且宿主子节点归零。
- [ ] **11.7** 真实鼠标复现棋盘卡「距离不足」，`editor_screenshot(source="game")` 截图确认圈以卡牌为中心、空心、灰色半透明、与飘字同时可见。
- [ ] **11.8** `project_manage(op="stop")` 停游戏。**不得关闭 Godot 编辑器。**

**Gate 11**：两套契约测试全绿；建筑回归 `0 项失败`；运行期断言与截图通过。

## 步骤 12 — 收尾（增量）

- [ ] **12.1** `.trellis/spec/frontend/component-guidelines.md` 的「飘字提示（FloatingText）」一节追加范围圈契约：组件路径与职责、`world_radius` 尾参语义、半径必须用画布变换而非目标自身 scale、圈与字必须在同一次 `_spawn` 内产出、`queue_redraw` 与 `process_mode` 两个静默故障点。
- [ ] **12.2** `git status --porcelain` 复查：只保留本增量需要的改动；Godot 编辑器改写的版本控制文件不得覆盖用户改动。

## 回滚点（增量）

| 回滚点 | 操作 | 影响 |
| --- | --- | --- |
| R4（任意时刻） | 只回退两处调用点的第 4/5 个实参 | 圈整体消失，飘字完全不受影响（`world_radius` 默认 0）。 |
| R5 | 再回退服务 `_spawn` 的建圈分支与 `_world_to_screen_scale` | 回到增量前状态；圈组件脚本可留在树上不被引用。 |
| R6 | 删除 `core/ui/feedback/interaction_range_ring.gd` | 彻底回到原状。**须同时确认 R4/R5 已回退**，否则 `preload` 会报错。 |

## 验证结果（增量，2026-10-14 实测）

| 项 | 结果 |
| --- | --- |
| `filesystem_manage(op="scan")` | `scan_completed: true`，无新增 GDScript 错误（清空日志后重扫无 `new_errors`）。 |
| `script_manage(op="find_symbols")` 三个生产脚本 | 全部解析成功；`InteractionRangeRing`、`_world_to_screen_scale`、`_record_interaction_radius`、`_show_building_out_of_range` 均注册。 |
| `test_run(suite="floating_text_contract")` | **10/10 passed, 0 failed**（含 3 个新增方法：`test_range_ring_component_shape` 9 断言、`test_service_wires_range_ring` 9 断言、`test_range_radius_comes_from_interaction_distance` 5 断言）。既有 7 个方法逐条继续通过。 |
| `test_run(suite="world_interaction_coordinator_contract")` | 6 passed / **3 failed（均为改动前既有失败）** / 1 skipped。**`test_interaction_range_gate` 未失败**，`_count_occurrences(..., "_show_out_of_range_floating_text(card)") == 1` 仍成立。 |
| `project_run(mode="custom", scene="res://scenes/Main.tscn")` | `status: live`，无 `SCRIPT ERROR` / `Parse Error` / `Failed to load script`。 |
| `game_eval` 同批产出 | `show_at_world(pos, "距离不够！", 红, 160)` → 宿主下恰好 1 个 `Node2D` 圈 + 1 个 `Label`；圈 `position == (400,300)`、`_radius == 160.0`、`_line_color == (0.62,0.62,0.66,0.5)`、`_line_width == 3.0`、`process_mode == 3`（ALWAYS）。 |
| `game_eval` 去重 | 同帧两次同目标同文案：第 1 次非 null、第 2 次 `null`，圈与字各只增 1（`children_before == 0` 的干净基线下复测）。 |
| `game_eval` 同步淡出 | 半程 `modulate.a`：圈 `0.708689212799072`、字 `0.708689212799072`，**差值 `0.0`**；`DURATION + 0.8s` 后圈与字均 `is_instance_valid == false`，宿主子节点数回到 `0`。 |
| `game_eval` 无半径兼容 | 3 参数调用（不传半径）→ 圈 `0` 个、字 `1` 个，既有调用点行为不变。 |
| `game_eval` 建筑路径 | `_record_interaction_radius({"data": campfire}) == campfire.InteractionRadius == 120.0`；`_record_interaction_radius({}) == 0.0`；`_show_building_out_of_range(...)` → 圈心 = 建筑的 `to_global` 屏幕坐标、半径 `120.0`、文案「距离不够！」、色 `(1,0.25,0.2,1)`。 |
| `game_eval` 棋盘卡路径（AC-24 决定性证据） | 用**真实 `BoardCardView.tscn`** 实例并强制 `scale = (1.7, 1.7)`：`card.get_screen_transform().get_scale().x == 1.7`、`canvas_scale == 1.0`，`ring._radius == 160.0`（=`InteractionRange × canvas_scale`），**若误用目标自身变换会得到 `272.0`**；圈心与卡牌屏幕原点完全吻合。 |
| 像素级空心验证 | `SubViewport(transparent_bg)` 光栅化后采样：圈心 alpha `0.0`、圈内 alpha `0.0`、圈外 alpha `0.0`，仅半径处出现中性灰半透明像素（`R≈G≈B`）⇒ **空心**、非实心、半径正确。 |
| 编辑器截图 | 已截取，但当前模型无图像输入能力，**未能由本人目视确认**，故改以上面的像素采样作为客观替代证据。 |

### 改动前既有失败（不是本增量引入，已逐条核实）

1. **`test_world_interaction_coordinator_contract` 的 3 个失败**：`test_production_script_shape` 断言 `func _run_screen_transition(method_name: String, completed_signal: StringName) -> void:`，而 `HEAD` 的生产代码早就是 3 参签名（多一个 `arguments: Array = []`，见 `git grep` 命中 `HEAD:core/gameflow/world_interaction_coordinator.gd:1332`）⇒ 测试相对代码过期。另两个失败（`fade_complete`、`无法加载战斗背景解析器`）同类。`git diff --unified=0` 证明本次只动了 3 个 hunk，均不涉及这些位置。
2. **`res://tests/godot/building_system_tests.tscn` 无法跑完（AC-27 因此不可验证）**：`_test_recipe_and_crafting()` 在 `:178` 读 `inputs[1]`，而 `resources/recipe/res/campfire_recipe.tres:15` 的 `Inputs` **只有 1 个元素**（测试期望「三树枝一火」= 2 项）⇒ `Out of bounds get index '1'`，游戏停在调试器 break。该函数在 `_run():152` 被调用，早于 `_test_controller_inputs():157`，所以**建筑控制器的输入用例根本没机会执行**。`resources/`、`items/`、`core/crafting/` 在本次改动中 `git status` 为空，可确认与本次改动无关。
   ⇒ **U5（待用户决断）**：修复该测试/配方数据属于另一个任务的范围（配方内容或测试期望二选一），本任务不擅自改动。

---

# Implement 增量二（2026-10-14）— 圈与字锁定在目标处

前置：先执行 `trellis-before-dev` 加载编码规范；编辑器 MCP 已连上 CUSGA。

## 步骤 13 — 新建锚点值对象

新建 `core/ui/feedback/floating_text_anchor.gd`：

- `extends RefCounted` + `class_name FloatingTextAnchor`。
- `enum Kind { TARGET, WORLD }`；字段 `_kind`、`_target: CanvasItem`、`_world_position: Vector2`、`_last_screen: Vector2`、`_has_last: bool`。
- 三个静态构造：`at_target(target)`、`at_world(world_position)`（第三个 `at_screen` 刻意不做，见 design 15.1 的兜底取舍）。
- `resolve(viewport) -> Vector2`：`TARGET` 分支先判 `is_instance_valid()` + `is_inside_tree()`；有效则刷新缓存，无效且从未落位则退回鼠标位置，无效但已落位则返回缓存。
- `world_scale(viewport) -> float`：`get_canvas_transform().get_scale().x`，退化返回 `1.0`。
- 全部公开成员写 `##` 文档注释，说明「为什么」需要可反复求值（相机每帧移动）。

验证门：`filesystem_manage(op="scan")` 后 `global_classes_registered_delta` 包含该类；无 parse error。

## 步骤 14 — 重构两个表现组件

`floating_text_label.gd`：

- 新增字段 `_anchor: FloatingTextAnchor`、`_rise: float`。
- `play(...)` 的 `anchor_position: Vector2` 改为 `anchor: FloatingTextAnchor`；`reset_size()` 后调一次 `_refresh()`。
- Tween 由 `position:y` 改为 `_rise`（曲线保持 `TRANS_SINE`/`EASE_OUT`）；`modulate:a` 那条不动。
- 新增 `_process(_delta)` → `_refresh()`；`_refresh()` 合成 `position = center - size*0.5 - (0, _rise)`。
- `_ready()` 保持只设 `mouse_filter` / 对齐 / `process_mode`。**`process_priority` 由服务在创建节点时统一设置**（见步骤 15），组件本身不需要知道相机与 autoload 的先后关系，常量也因此只有一处定义。

`interaction_range_ring.gd`：

- 字段改为 `_anchor`、`_world_radius`、`_radius`、`_line_color`、`_line_width`。
- `play(anchor, world_radius, line_color, line_width, duration)`：存值 → `_refresh()` → Tween `modulate:a`。
- `_process(_delta)` → `_refresh()`：重算 `position`，半径变化时才 `queue_redraw()`。
- `_draw()` 保持 `draw_arc`（空心）不变；`_ready()` 同样不碰 `process_priority`，由服务设置。

**自检**：两个组件都不得出现 `_ready` 里访问 `_anchor` 的路径；`_refresh()` 首行必须判空。

## 步骤 15 — 重构服务

`core/autoloads/floating_text.gd`：

- `_spawn(text: String, anchor: FloatingTextAnchor, text_color: Color, world_radius: float = 0.0) -> Node`。
- 去重键改为 `_is_duplicate(text, anchor.resolve(get_viewport()))`。
- 圈与字传**同一个** `anchor`；圈的 `play` 传**世界**半径。
- `show_at_target` → `_spawn(text, FloatingTextAnchor.at_target(target), text_color, world_radius)`。
- `show_at_world` → `_spawn(text, FloatingTextAnchor.at_world(world_position), text_color, world_radius)`。
- **删除** `_resolve_target_screen_position()` 与 `_world_to_screen_scale()`。
- `show_at_target` / `show_at_world` 的**第一、二行签名逐字不动**（AC-32）；`viewport == null` 的提前返回保留在世界入口里。

验证门：`script_manage(op="find_symbols")` 解析通过；`rg` 确认全仓库再无 `_resolve_target_screen_position` / `_world_to_screen_scale` 引用（测试文件除外，下一步同步）。

## 步骤 16 — 测试与 spec 同步 + 运行期实证

- 按 design 17 改写/新增契约测试。
- 更新 `.trellis/spec/frontend/component-guidelines.md` 的飘字小节：补「锚点必须每帧重新求值」与 `process_priority` 两条。
- 运行期按 design 17 的清单逐条 `game_eval` 断言（**核心是相机平移后圈仍锁在卡牌上**），最后 `project_manage(op="stop")`。
- `git status --porcelain` 复核，只保留本次改动。

## 回滚点（增量二）

| 编号 | 操作 | 后果 |
| --- | --- | --- |
| R7 | 把 `_spawn` 的 `anchor` 参数改回 `screen_position: Vector2` | 回到「生成时算一次」的旧行为；需同时还原两个组件的 `play` 签名与上飘实现。 |
| R8 | 删除 `core/ui/feedback/floating_text_anchor.gd` | 彻底回到原状。**必须先回滚 R9**，否则服务与两个组件的类型引用会解析失败。 |
| R9 | 还原两个组件的 `play` 签名与 `_process` | 上飘需改回 `position:y` 的 Tween，否则 `_rise` 无人消费。 |

## 待办：实施期需回报的未决项（增量二）

- **U6**：组件 `process_priority` 的具体数值。`1000` 是「足够晚」的取值，若日后有更晚的自定义 `_process` 需要压过飘字，需要重新评估。**决策人：LisBam**。

## 验证结果（增量二，2026-10-14 实测）

| 项 | 结果 |
| --- | --- |
| `filesystem_manage(op="scan")` | `global_class_count` 125 → **126**，`FloatingTextAnchor` 注册成功。 |
| `script_manage(op="find_symbols")` ×4 | 四个脚本全部解析通过；服务函数数由 8 降为 **6**（两个换算助手已删除）；两个组件均新增 `_process` / `_refresh`。 |
| `test_run(suite="floating_text_contract")` | **12/12 passed, 0 failed**（新增 `test_anchor_component_shape` 16 断言、`test_components_re_resolve_anchor_each_frame` 14 断言）。`load_errors` 仍是既有的 `test_item_room_content.gd`，与本任务无关。 |
| `project_run(mode="custom", scene="res://scenes/Main.tscn")` | `status: live`；`logs_read(source="game")` 仅 5 条 info（房间切换），**无任何报错**。 |
| **AC-29 相机平移**（核心） | 对真实 `BoardCardView` 调 `show_at_target(card, ..., 160)`，相机平移后：卡牌屏幕位置 `(600,420) → (480,340)`，圈 `(600,420) → (480,340)`，**漂移 `0.0px`**；再平移 `(-90,60)` 时圈位移 `(-90,60)`、与卡牌**逐位相等**。 |
| **AC-29 字的中心** | 冻结上飘后 `label.position + size*0.5 + (0,_rise)` 与锚点**逐位相等（漂移 `0.0px`）**，平移前后都是 `0.0`。未冻结时出现的 `0.52~0.69px` 已定位为「读取时刻 vs 刷新时刻」的 `_rise` 竞争，不是缺陷。 |
| **AC-30 相机缩放** | `camera.zoom` 由 `1` 改 `2`：画布缩放 `1.0 → 2.0`，圈半径 `160 → 320`（=`160 × 缩放`）；圈位移与卡牌位移**逐位相等**。 |
| **AC-31 目标中途失效** | `card.queue_free()` 后：圈漂移 `0.0px`、字漂移 `0.175px`（同上竞争），**停留在最后坐标**；相机再平移时圈**不再跟随**（`0.0px`），`modulate.a` 继续正常淡出，游戏日志无报错。 |
| **AC-33 单一实现点** | `assert_false(service.contains("get_canvas_transform()"))`、`assert_false(... "_resolve_target_screen_position")`、`assert_false(... "_world_to_screen_scale")` 全通过——服务里已无任何坐标数学。 |
| **AC-34 共用锚点** | `ring._anchor == label._anchor` → `true`。 |
| 增量一回归 | 无半径调用仍只出字不出圈（圈 `0` / 字 `1`）；同帧双发第 2 次返回 `null`、圈与字各只增 1；换位置不会被误去重；半程 alpha 差值 `0.0`；`DURATION` 后双双释放、宿主归零；圈与字 `process_priority` 实测均为 `1000`。 |

### 本次新增的可复用教训（已写入 spec）

- **`node == null` 在已释放对象上会返回 `true`**：`game_eval` 里把 `first != null` 写在**延迟求值**的字典字面量中，会因为在 `return` 前经过了 `await`（节点已淡出释放）而假报 `false`，看起来像「第一次调用就被去重了」。布尔结果必须在调用当下取出。该现象在本任务中连续踩到两次。
- **autoload 的 `_process` 顺序早于主场景**：凡是要读相机变换的表现组件都必须显式设晚的 `process_priority`，否则会稳定地慢一帧。**（增量三已不适用：飘字不再有每帧逻辑，整条约束连同 `PROCESS_PRIORITY_LATE` 一起删除。）**

---

# Implement 增量三（2026-10-17 第三轮）— 改为世界坐标定位

> 前置：`design.md` 第 18～21 节。**本节取代增量二的全部实施步骤**（步骤 13～16 描述的锚点与逐帧刷新已废弃）。

## 步骤 17 — 删除锚点方案

- [x] **17.1** 删除 `core/ui/feedback/floating_text_anchor.gd` 与 `floating_text_anchor.gd.uid`。
- [x] **17.2** `interaction_range_ring.gd`：删除 `_anchor` / `_world_radius` / `_process` / `_refresh`；
      `play(center: Vector2, radius: float, line_color, line_width, duration)` 只写一次 `position = center`；
      恢复无条件 `queue_redraw()`（圈心移动不再由重绘承担）。
- [x] **17.3** `floating_text_label.gd`：删除 `_anchor` / `_rise` / `_process` / `_refresh`；
      `play(..., center: Vector2, rise_distance, duration)` 写一次 `position = center - size * 0.5`；
      上飘恢复 `tween_property(self, "position:y", ...)`（位置只写一次，无第二条写入路径）。

## 步骤 18 — 承载层改为世界坐标

- [x] **18.1** `floating_text.gd` 的 `_ready()`：加 `_layer.follow_viewport_enabled = true`。
- [x] **18.2** 宿主改为 `_host.position = Vector2.ZERO`，**移除** `set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)`
      （跟随相机变换后 `anchorable_rect` 不再固定在屏幕上，会把飘字整体平移）。
- [x] **18.3** 新增 `_resolve_target_world_position(target)`：`get_global_transform()`；`Control` 取尺寸中心，
      `Node2D` 取原点；目标失效时用 `get_canvas_transform().affine_inverse()` 把鼠标位置换成世界坐标。
- [x] **18.4** `_spawn(text, world_position, text_color, world_radius)`；`show_at_target` / `show_at_world`
      的**前两行签名逐字不变**。
- [x] **18.5** 删除 `PROCESS_PRIORITY_LATE` 常量与两处 `process_priority` 赋值（没有每帧逻辑就不需要与相机抢求值顺序）。

## 步骤 19 — 契约测试改为反向护栏

- [x] **19.1** 删除 `test_anchor_component_shape` 与 `ANCHOR_GD`。
- [x] **19.2** 新增 `test_hints_are_world_anchored_not_resolved_per_frame`：断言两个组件**不含** `func _process(`
      与 `_anchor`；断言 `follow_viewport_enabled`、`_host.position = Vector2.ZERO`、
      上飘为 `Tween position:y`、圈 `position = center`、圈不含 `world_scale`。
- [x] **19.3** 修 `test_service_api_shape`（`get_global_transform()`、禁止 `get_screen_transform()`、禁止服务有 `_process`）
      与 `test_service_wires_range_ring`（`ring.call("play", world_position, world_radius,`）。

**Gate 19**：`test_run(suite="floating_text_contract")` **11/11 通过，0 失败**。

## 验证结果（增量三，2026-10-17 实测）

| 项 | 结果 |
| --- | --- |
| `filesystem_manage(op="scan")` | `global_class_count` 126 → **125**，`FloatingTextAnchor` 已随文件删除而注销。 |
| `find_symbols` ×3 | 服务 7 个函数（无 `_process`）；飘字 5 个（`_process`/`_refresh` 已消失）；圈 6 个（同上）。 |
| `test_run(suite="floating_text_contract")` | **11/11 passed, 0 failed**（`test_hints_are_world_anchored_not_resolved_per_frame` 14 断言全绿）。 |
| **AC-37 世界坐标** | 圈的 `position` == 卡牌 `global_position`（`600,420`）→ `true`；宿主 `position` 实测 `(0,0)`。 |
| **AC-36 平移后仍锁在目标（核心）** | 相机平移 `(120,80)`：卡牌屏幕位移 `(-120,-80)`，圈屏幕位移 `(-120,-80)`、**漂移 `0.0px`**；而圈的**世界坐标一字未改**。 |
| **AC-35 无每帧逻辑** | `ring_has_process: false`、`label_has_process: false`、`ring_is_processing: false`、`label_is_processing: false`。 |
| **AC-40 层级** | 运行期 `layer=10`、`hud=2`、`daynight=0`；`above_hud: true`、`above_daynight_filter: true`；`follow_viewport_enabled: true`；`host_canvas_transform_matches_viewport: true`。 |
| **AC-39 目标中途释放** | `card.queue_free()` 后圈的世界坐标不变（`ring_kept_world_position: true`）、无报错、继续淡出。 |
| **AC-38 旧机制清除** | 全库 `rg` 仅剩契约测试里那条**反向**断言命中 `PROCESS_PRIORITY_LATE`；`FloatingTextAnchor` / `ANCHOR_GD` / `floating_text_anchor` 零命中。 |
| **AC-41 回归** | 无半径只出字（圈 `0` / 字 `1`）；同帧双发第 2 次 `null` 且圈字各只增 1；换位置不被误去重；半程 alpha 差值 `0.0`；到时长双双释放、宿主归零；游戏日志全程无报错。 |
| `game_eval` ×4 + `project_manage(op="stop")` | Main `status: live`，日志仅 5 条 info（房间切换）；已 stop，**编辑器未关**。 |

### 本轮教训（已写入 spec）

- **不要用「每帧重算」去模拟引擎本来就会做的事**：把表现节点放进带相机变换的层，
  比在屏幕空间里逐帧反算世界坐标简单一个数量级，且能同时保住绘制层级。
- **否决一个方案前先核实它的前提**：增量二以「改为世界空间会让文字随相机 zoom 放大」为由排除了世界空间，
  但本项目根本没有代码改过 `Camera2D.zoom`（`rg "zoom"` 全部命中都属小地图/大地图），
  这条理由从一开始就不成立。**推测出来的约束必须验证，否则会为一个不存在的状态设计一整套机制。**
- **`contains()` 断言不要用裸关键字**：服务里讲解「不要用 `PRESET_FULL_RECT`」的注释会让
  `assert_false(service.contains("PRESET_FULL_RECT"))` 变红。断言要写完整调用串。
- **`node == null` 在已释放对象上返回 `true`**：布尔结果必须在调用当下取出，不能留在延迟求值的表达式里。
