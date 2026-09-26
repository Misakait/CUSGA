@tool
extends McpTestSuite

## 昼夜屏幕滤镜（DayNightFilter）的行为契约套件。
##
## 锁定四条边界：
## 1. 昼夜两段各自按阶段进度做颜色插值（白天转暖、夜晚转亮）；
## 2. 过渡是逐帧渐变的，且必然收敛到目标色，不会跳变也不会停在中间；
## 3. 缺少 TimeSystem 时降级为中性色而不是崩溃；
## 4. 父级是 Node2D 时自动铺满视口，否则全屏 Control 会静默退化成 0×0。

## 待验证的滤镜脚本。
const DAY_NIGHT_FILTER_SCRIPT: GDScript = preload("res://core/ui/filters/day_night_filter.gd")

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
	assert_eq(day_start, NEUTRAL_COLOR, "白天起点必须完全不改变画面。")

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


## 验证过渡逐帧渐变、收敛到目标色，并且中途再次推进时间也能收敛到新目标。
## 返回值：无。
func test_day_night_filter_transition_is_smooth_and_converges() -> void:
	var fake := _install_fake_time_system()
	var filter: Node = _new_filter()
	fake.set("IsNight", false)
	fake.set("Progress", 0)
	filter.call("_process", 0.1)
	var start: Color = filter.call("get_current_color")
	assert_true(start.is_equal_approx(NEUTRAL_COLOR), "白天起点不应产生任何染色。")

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
