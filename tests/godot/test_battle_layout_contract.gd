@tool
extends McpTestSuite

## 战斗布局契约：初始排布不被旧 Tween 覆盖，行动条保持左侧纵向展示。

## 生产怪物排布脚本，测试使用普通 Node2D 替代战斗实体。
const MONSTER_MANAGER: GDScript = preload("res://scripts/battle_scripts/monster_manager.gd")
## 生产行动条脚本，位置计算不需要启动战斗状态机。
const TIMELINE: GDScript = preload("res://scripts/ui_scripts/action_timeline.gd")


## 返回编辑器测试入口；返回值：稳定套件名。
func suite_name() -> String:
	return "battle_layout_contract"


## 立即排布后，即使等待旧入场动画时长也不能把怪物拉回初始原点。
## 返回值：无。
func test_initial_layout_cancels_previous_motion() -> void:
	# 加入编辑器树以获得真实视口与 Tween 时钟，但不生成真实怪物或触发战斗。
	var manager: Node2D = track(MONSTER_MANAGER.new()) as Node2D
	# 测试时的场景树仅用于驱动排布 Tween。
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(manager)
	# 两个无业务组件的实体足以复现连续重排与立即定位之间的竞争。
	var first: Node2D = Node2D.new()
	var second: Node2D = Node2D.new()
	manager.add_child(first)
	manager.add_child(second)
	manager.set("active_monsters", [first, second])
	# 首次立即排布时还没有 Tween 元数据，也必须安全完成。
	manager.call("update_monsters_position", true)
	manager.call("update_monsters_position")
	manager.call("update_monsters_position", true)
	# 记录即时结果，等待后再次断言，避免只检查尚未被旧 Tween 覆盖的同一帧。
	var first_position: Vector2 = first.position
	var second_position: Vector2 = second.position
	assert_eq(first_position.y, float(manager.get("monster_height")), "第一只怪物必须立即到达排布高度。")
	assert_eq(second_position.x - first_position.x, float(manager.get("monster_spacing")), "两只怪物必须保持配置间距。")
	await tree.create_timer(0.4).timeout
	assert_eq(first.position, first_position, "旧 Tween 不能覆盖已经完成的开场布局。")
	assert_eq(second.position, second_position, "连续生成时也不能留下竞争位置的旧 Tween。")


## 纵向行动槽的位置严格由高度和间距计算。
## 返回值：无。
func test_timeline_keeps_vertical_slot_spacing() -> void:
	# 不进入场景树，只检查与行动算法独立的位置映射。
	var timeline: Control = track(TIMELINE.new()) as Control
	timeline.set("ui_item_size", Vector2(112, 26))
	timeline.set("slot_spacing", 8)
	assert_eq(timeline.call("_slot_position", 0), Vector2.ZERO, "当前行动者必须位于起点。")
	assert_eq(timeline.call("_slot_position", 3), Vector2(0, 102), "行动轴必须只沿纵向排列。")


## 贴图式血条的缓冲层必须拥有独立副本，不能污染共享填充资源。
## 返回值：无。
func test_texture_vital_bar_keeps_shared_style_unchanged() -> void:
	# 同一份血条资源同时用于玩家和怪物，测试保护实例间的样式隔离。
	var fill: StyleBoxTexture = load("res://res/battle_ui/health_fill.tres") as StyleBoxTexture
	# 正式控件接受真实九宫格样式，初始化后应生成同类型缓冲填充。
	var bar: ProgressBar = _build_stat_bar(fill)
	# 从动态缓冲条读取实际生效的样式，而不是只检查资源文件字段。
	var catchup: ProgressBar = bar.get("catchup_bar") as ProgressBar
	var catchup_style: StyleBox = catchup.get_theme_stylebox("fill")
	assert_true(catchup_style is StyleBoxTexture, "九宫格填充的缓冲区必须保留切角。")
	assert_true(catchup_style != fill, "缓冲层只能修改自己的资源副本。")
	assert_eq(fill.modulate_color, Color.WHITE, "共享填充资源必须保留原始颜色。")
	bar.call("update_stat", 43.0, 100.0, true)
	assert_eq(bar.value, 43.0, "瞬时更新必须写入真实值。")
	assert_eq(catchup.value, 43.0, "缓冲层必须同步瞬时更新。")
	assert_eq((bar.get("text_label") as Label).text, "43/100", "样式替换不能改变生命数值文字。")


## 共用血条脚本仍须兼容其它界面的纯色样式。
## 返回值：无。
func test_flat_vital_bar_keeps_existing_catchup_behavior() -> void:
	# 原有界面使用纯色填充，不能因战斗重绘被迫更换资源。
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = Color.RED
	var bar: ProgressBar = _build_stat_bar(fill)
	var catchup: ProgressBar = bar.get("catchup_bar") as ProgressBar
	var catchup_style: StyleBoxFlat = catchup.get_theme_stylebox("fill") as StyleBoxFlat
	assert_true(catchup_style != null, "纯色血条仍应生成纯色缓冲区。")
	assert_eq(catchup_style.bg_color, Color.WHITE, "纯色血条继续使用原有白色扣血缓冲。")
	bar.call("update_stat", 80.0, 120.0, true)
	assert_eq(bar.max_value, 120.0, "生命上限必须继续支持变化。")
	assert_eq((bar.get("text_label") as Label).text, "80/120", "数值格式必须保持兼容。")


## 用正式血条脚本建立隔离实例；参数 fill：填充样式；返回值：已初始化控件。
func _build_stat_bar(fill: StyleBox) -> ProgressBar:
	# 不进入场景树，手动初始化控件，避免运行其它玩法脚本。
	var bar: ProgressBar = track(load("res://scripts/ui_scripts/stat_bar.gd").new()) as ProgressBar
	# 文本节点名称沿用正式场景的探测协议。
	var label: Label = Label.new()
	label.name = "HealthText"
	bar.add_child(label)
	bar.add_theme_stylebox_override("background", StyleBoxFlat.new())
	bar.add_theme_stylebox_override("fill", fill)
	bar.call("_ready")
	return bar
