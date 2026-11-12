@tool
extends McpTestSuite

## 昼夜屏幕滤镜（DayNightFilter）的行为契约套件。
##
## 锁定六条边界：
## 1. 昼夜两段各自按阶段进度做颜色插值（白天转暖、夜晚转亮）；
## 2. 每推进一次行动值（阶段长度的十分之一）都要产生可见的天色变化；
## 3. 过渡是逐帧渐变的，且必然收敛到目标色，不会跳变也不会停在中间；
## 4. 缺少 TimeSystem 时降级为中性色而不是崩溃；
## 5. 父级是 Node2D 时自动铺满视口，否则全屏 Control 会静默退化成 0×0；
## 6. 探索场景把滤镜挂在 CanvasLayer 下，避免随相机移出画面。

## 待验证的滤镜脚本。
const DAY_NIGHT_FILTER_SCRIPT: GDScript = preload("res://core/ui/filters/day_night_filter.gd")

## 卡牌视觉层级常量的唯一来源。
const CARD_VISUALS: GDScript = preload("res://core/card_visual_config.gd")

## 战斗背景复制器，读取其背景层级常量。
const BACKGROUND_RESOLVER_SCRIPT: GDScript = preload("res://core/gameflow/UICurrentMapBackgroundResolver.gd")

## 中性色：乘法混合下等价于「完全不改变画面」。
const NEUTRAL_COLOR := Color(1.0, 1.0, 1.0, 1.0)


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：昼夜滤镜契约套件名。
func suite_name() -> String:
	return "day_night_filter_contract"


## 提供滤镜需要的稳定协议：IsNight 属性、get_PhaseProgress() 方法与 PhaseLength 常量。
## PhaseLength 必须是真正的脚本常量，这样才能验证滤镜是通过常量表读取阶段长度，
## 而不是在滤镜里复制了一份阶段长度。
class FakeTimeSystem extends Node:
	## 阶段长度，与生产 TimeSystem 保持一致。
	const PhaseLength: int = 100

	## 当前是否夜晚。
	var IsNight: bool = false
	## 当前阶段内进度。
	var Progress: int = 0

	## 返回当前阶段内进度。
	## 返回值：阶段进度。
	func get_PhaseProgress() -> int:
		return Progress


## 验证颜色曲线：白天向黄昏转暖，夜晚由最暗向黎明转亮。
## 返回值：无。
func test_day_night_filter_interpolates_phase_colors() -> void:
	var fake := _install_fake_time_system()
	var filter: Node = _new_filter()
	fake.set("IsNight", false)
	fake.set("Progress", 0)
	var day_start: Color = filter.call("get_target_color")
	assert_true(day_start.b >= day_start.r, "清晨应当偏冷，蓝通道不低于红通道。")
	assert_true(day_start.b >= 0.95, "清晨必须保持明亮，不能明显压暗画面。")

	fake.set("Progress", 99)
	var day_end: Color = filter.call("get_target_color")
	assert_true(day_end.b < day_start.b, "白天末尾必须比清晨更暖，蓝通道要被压低。")
	assert_true(day_end.r >= day_start.r, "白天末尾的红通道不应低于清晨。")

	fake.set("IsNight", true)
	fake.set("Progress", 0)
	var night_start: Color = filter.call("get_target_color")
	assert_true(night_start.r < day_end.r, "入夜必须明显压暗，红通道要低于黄昏。")
	assert_true(night_start.b > night_start.r, "夜色必须偏冷，蓝通道高于红通道。")

	fake.set("Progress", 99)
	var night_end: Color = filter.call("get_target_color")
	assert_true(night_end.r > night_start.r, "夜晚末尾必须比入夜更亮，向天亮过渡。")
	assert_true(night_end.g > night_start.g, "夜晚末尾必须比入夜更亮，向天亮过渡。")
	assert_true(night_end.b > night_start.b, "夜晚末尾必须比入夜更亮，向天亮过渡。")

	_free_filter(filter)
	_remove_fake_time_system()


## 验证阶段内每推进一次行动值都能产生可感知的天色变化。
## 一次地图移动推进 10 点（阶段长度 100 的十分之一）；若单步变化太小，玩家在白天或夜晚
## 期间会以为天色根本没动，只有昼夜切换那一瞬才有感觉 —— 这正是本需求要避免的表现。
## 返回值：无。
func test_each_action_step_produces_visible_color_shift() -> void:
	const STEP: int = 10
	const MIN_CHANNEL_DELTA: float = 0.04
	var fake := _install_fake_time_system()
	var filter: Node = _new_filter()
	for is_night in [false, true]:
		fake.set("IsNight", is_night)
		var previous: Color = _target_at(filter, fake, 0)
		var progress: int = STEP
		while progress <= 100:
			var current: Color = _target_at(filter, fake, progress)
			var delta: float = maxf(
				absf(current.r - previous.r),
				maxf(absf(current.g - previous.g), absf(current.b - previous.b))
			)
			assert_true(
				delta >= MIN_CHANNEL_DELTA,
				"昼夜状态 %s 下每推进 %d 点进度必须产生可见的天色变化，当前最大通道差仅 %.4f。" % [str(is_night), STEP, delta]
			)
			previous = current
			progress += STEP
	_free_filter(filter)
	_remove_fake_time_system()


## 验证过渡逐帧渐变、收敛到目标色，并且中途再次推进时间也能收敛到新目标。
## 返回值：无。
func test_day_night_filter_transition_is_smooth_and_converges() -> void:
	var fake := _install_fake_time_system()
	var filter: Node = _new_filter()
	fake.set("IsNight", false)
	fake.set("Progress", 0)
	var day_zero_target: Color = filter.call("get_target_color")
	filter.call("_process", 0.1)
	var start: Color = filter.call("get_current_color")
	assert_true(start.is_equal_approx(day_zero_target), "白天起点应直接吸附到当前时刻的目标色，不产生额外染色。")

	fake.set("IsNight", true)
	fake.set("Progress", 0)
	var target: Color = filter.call("get_target_color")
	filter.call("_process", 0.1)
	var after_one_frame: Color = filter.call("get_current_color")
	assert_true(after_one_frame != target, "单帧推进不应直接跳到终点，必须保留过渡中间态。")
	assert_true(after_one_frame.b > target.b, "首帧颜色应当仍靠近起始色，而不是瞬间变暗。")

	for _step in range(80):
		filter.call("_process", 0.1)
	var settled: Color = filter.call("get_current_color")
	assert_true(settled.is_equal_approx(target), "过渡最终必须收敛到目标色。")

	# 过渡尚未开始时再次推进时间：必须继续朝新的目标收敛，而不是停在旧终点。
	fake.set("Progress", 99)
	var next_target: Color = filter.call("get_target_color")
	for _step in range(80):
		filter.call("_process", 0.1)
	var settled_again: Color = filter.call("get_current_color")
	assert_true(settled_again.is_equal_approx(next_target), "过渡途中再次推进时间后，仍必须收敛到新的目标色。")

	_free_filter(filter)
	_remove_fake_time_system()


## 验证缺少 TimeSystem 时降级为中性色，不崩溃也不染色。
## 返回值：无。
func test_day_night_filter_degrades_to_neutral_without_time_system() -> void:
	_remove_fake_time_system()
	var filter: Node = _new_filter()
	var target: Color = filter.call("get_target_color")
	assert_eq(target, NEUTRAL_COLOR, "缺少 TimeSystem 时目标色必须回退为中性色。")

	filter.call("_process", 0.5)
	var current: Color = filter.call("get_current_color")
	assert_true(current.is_equal_approx(NEUTRAL_COLOR), "缺少 TimeSystem 时不得产生任何染色。")

	_free_filter(filter)


## 验证父级是 Node2D 时滤镜自愈铺满视口。
## Node2D 的 anchorable rect 是空矩形，全屏 anchors 会算出 0×0 并让滤镜静默失效，
## 这条测试锁住「无论如何挂载都必须铺满视口」的边界。
## 返回值：无。
func test_day_night_filter_fits_viewport_under_node2d_parent() -> void:
	_remove_fake_time_system()
	var scene_tree := Engine.get_main_loop() as SceneTree
	var parent := Node2D.new()
	parent.name = "Node2DParentProbe"
	scene_tree.root.add_child(parent)

	var filter: Node = DAY_NIGHT_FILTER_SCRIPT.new()
	filter.name = "DayNightFilterUnderNode2D"
	filter.call("set_process", false)
	parent.add_child(filter)

	var viewport_size: Vector2 = scene_tree.root.get_visible_rect().size
	var filter_size: Vector2 = filter.get("size")
	assert_true(filter_size.x > 0.0 and filter_size.y > 0.0, "滤镜尺寸不能退化成 0×0，否则整层滤镜静默失效。")
	assert_eq(filter_size, viewport_size, "父级是 Node2D 时滤镜必须自愈铺满视口。")

	parent.remove_child(filter)
	filter.free()
	parent.free()


## 验证探索场景把滤镜挂在 CanvasLayer 下。
## 若滤镜直接挂在场景根（默认 canvas）下，它会随跟随玩家的 Camera2D 一起移出画面，
## 表现为「滤镜完全没生效」且不报任何错，因此这条结构契约必须锁定。
## 返回值：无。
func test_exploration_scene_hosts_filter_under_canvas_layer() -> void:
	var text := _read_scene_text("res://scenes/Main.tscn")
	assert_true(text.contains("name=\"DayNightFilterLayer\""), "探索场景必须有 DayNightFilterLayer（CanvasLayer）承载滤镜。")
	assert_true(
		text.contains("name=\"DayNightFilter\" parent=\"DayNightFilterLayer\""),
		"滤镜必须挂在 DayNightFilterLayer 下，不能直接挂在场景根下。"
	)
	assert_false(
		text.contains("name=\"DayNightFilter\" parent=\".\""),
		"滤镜不得回到场景根（默认 canvas），否则会随相机移出画面。"
	)


## 验证战斗场景滤镜位于背景之上、全部游戏内容之下。
## 战斗 HUD 已经在滤镜之上；修正的关键是让卡牌/怪物卡/玩家也高于滤镜，
## 否则夜晚会整屏压暗手牌，玩家看不清卡面信息。
## 返回值：无。
func test_battle_filter_layers_between_background_and_gameplay() -> void:
	var battle_text := _read_scene_text("res://scenes/battle_scenes/battle.tscn")
	var filter_block := _read_node_block(battle_text, 'name="DayNightFilter" parent="."')
	var filter_z: int = _read_node_z_index(battle_text, 'name="DayNightFilter" parent="."')
	var background_z: int = _read_node_z_index(battle_text, 'name="测试背景"')
	var ui_z: int = _read_node_z_index(battle_text, 'name="UI" type="Marker2D" parent="."')
	var constants := BACKGROUND_RESOLVER_SCRIPT.get_script_constant_map()
	assert_true(
		filter_block.contains("z_index = -1"),
		"战斗场景必须显式覆盖滤镜层级；实例场景默认 1500，省略覆盖会重新盖住卡牌。"
	)
	assert_true(constants.has("MAP_BACKGROUND_Z_INDEX"), "战斗背景层级必须由复制器集中声明，不能散落在场景里。")
	var map_background_z: int = int(constants.get("MAP_BACKGROUND_Z_INDEX", 0))
	assert_true(filter_z > background_z, "滤镜必须高于静态背景，否则背景不会被昼夜染色。")
	assert_true(filter_z > map_background_z, "滤镜必须高于运行时复制的 MapBackground，否则房间背景不会被染色。")
	assert_true(
		filter_z < CARD_VISUALS.CARD_Z_INDEX_NORMAL,
		"滤镜必须低于卡牌常态层级，否则夜晚会压暗手牌；当前滤镜 %d、卡牌 %d。" % [
			filter_z, CARD_VISUALS.CARD_Z_INDEX_NORMAL
		]
	)
	assert_true(ui_z > filter_z, "战斗 HUD 必须继续位于滤镜之上。")


## 验证战斗背景复制器真的把复制出的背景放到滤镜之下。
## 只看常量声明不够：若赋值处又写回 -1，滤镜与背景同层，运行时加入顺序会让背景盖住滤镜。
## 返回值：无。
func test_battle_background_copy_sits_below_filter() -> void:
	var constants := BACKGROUND_RESOLVER_SCRIPT.get_script_constant_map()
	var expected_z: int = int(constants.get("MAP_BACKGROUND_Z_INDEX", 0))
	var map_system := Node.new()
	map_system.name = "MapSystemProbe"
	var instantiator := Node.new()
	instantiator.name = "MapInstantiator"
	map_system.add_child(instantiator)
	var room := Node2D.new()
	room.name = "RoomProbe"
	var background := Sprite2D.new()
	background.name = "Background"
	room.add_child(background)
	instantiator.add_child(room)

	var resolver: RefCounted = BACKGROUND_RESOLVER_SCRIPT.new()
	var duplicated_value: Variant = resolver.call("DuplicateCurrentBackground", map_system)
	var duplicated: Sprite2D = duplicated_value as Sprite2D
	assert_true(duplicated != null, "背景复制器必须能从当前房间复制 Background。")
	if duplicated == null:
		map_system.free()
		return
	assert_eq(duplicated.name, "MapBackground", "复制出的背景必须使用稳定名称。")
	assert_eq(duplicated.z_index, expected_z, "复制背景必须落在滤镜之下的声明层级。")
	assert_false(duplicated.z_as_relative, "复制背景不得继承父节点层级，否则场景根抬升会失效。")

	duplicated.free()
	map_system.free()


## 读取场景文本中某个节点块的 z_index。
## 参数 text：场景全文。
## 参数 header_fragment：节点头部的稳定片段，例如 name="UI" type="Marker2D" parent="."。
## 返回值：该节点的 z_index；节点不存在或未声明时返回 0。
func _read_node_z_index(text: String, header_fragment: String) -> int:
	var block := _read_node_block(text, header_fragment)
	var marker := "z_index = "
	var index := block.find(marker)
	if index < 0:
		return 0
	var value_start := index + marker.length()
	var value_end := block.find("\n", value_start)
	if value_end < 0:
		value_end = block.length()
	return int(block.substr(value_start, value_end - value_start).strip_edges())


## 截取从指定节点头到下一个节点头之前的文本。
## 参数 text：场景全文。
## 参数 header_fragment：节点头部的稳定片段。
## 返回值：节点块文本；找不到头部时返回空字符串。
func _read_node_block(text: String, header_fragment: String) -> String:
	var start := text.find(header_fragment)
	if start < 0:
		return ""
	var line_end := text.find("\n", start)
	if line_end < 0:
		return text.substr(start)
	var next_node := text.find("\n[node ", line_end)
	if next_node < 0:
		return text.substr(start)
	return text.substr(start, next_node - start)


## 创建并挂载一个滤镜节点，并关闭引擎驱动以便测试手动控制帧推进。
## 返回值：已进入场景树的滤镜节点。
func _new_filter() -> Node:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var filter: Node = DAY_NIGHT_FILTER_SCRIPT.new()
	filter.name = "DayNightFilterContractProbe"
	filter.call("set_process", false)
	scene_tree.root.add_child(filter)
	return filter


## 从场景树移除并释放滤镜节点。
## 参数 filter：待释放的滤镜节点。
## 返回值：无。
func _free_filter(filter: Node) -> void:
	if filter == null or not is_instance_valid(filter):
		return
	var parent := filter.get_parent()
	if parent != null:
		parent.remove_child(filter)
	filter.free()


## 在场景树根节点安装名为 TimeSystem 的假时间系统。
## 返回值：已挂载的假时间系统。
func _install_fake_time_system() -> Node:
	_remove_fake_time_system()
	var scene_tree := Engine.get_main_loop() as SceneTree
	var fake := FakeTimeSystem.new()
	fake.name = "TimeSystem"
	scene_tree.root.add_child(fake)
	return fake


## 移除场景树根节点上的 TimeSystem，避免污染其它套件。
## 返回值：无。
func _remove_fake_time_system() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	var existing := scene_tree.root.get_node_or_null("TimeSystem")
	if existing != null:
		scene_tree.root.remove_child(existing)
		existing.free()


## 读取指定昼夜状态与阶段进度下的目标颜色。
## 参数 filter：滤镜节点。
## 参数 fake：已安装的假时间系统。
## 参数 progress：阶段进度。
## 返回值：该状态下的目标颜色。
func _target_at(filter: Node, fake: Node, progress: int) -> Color:
	fake.set("Progress", progress)
	return filter.call("get_target_color")


## 读取项目内文本文件的内容。
## 参数 path：res:// 路径。
## 返回值：文件全文；无法读取时返回空字符串。
func _read_scene_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
