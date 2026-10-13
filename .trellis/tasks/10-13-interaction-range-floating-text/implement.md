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
