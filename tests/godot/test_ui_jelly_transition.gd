@tool
extends McpTestSuite

## 检查四种轻量轨迹、请求取消、暂停推进以及精确复位。
const MOTION: GDScript = preload("res://core/ui/transitions/ui_transition.gd")
const LEGACY_MOTION: GDScript = preload("res://core/ui/ui_jelly_transition.gd")
const COMPONENT_FIXTURE: PackedScene = preload(
	"res://tests/godot/fixtures/ui_transition_component_fixture.tscn"
)

## 参数无；返回测试发现名称。
func suite_name() -> String:
	return "ui_jelly_transition"

## 检查四种轨迹的限幅、单调与反向连续性；参数无，返回无。
func test_four_styles_stay_monotonic_and_settle() -> void:
	var profiles: Array[Dictionary] = [
		{"style": MOTION.MotionStyle.SOFT_SCALE, "factor": Vector2(0.98, 0.98),
			"offset": Vector2.ZERO, "close_factor": Vector2(0.99, 0.99),
			"close_offset": Vector2.ZERO},
		{"style": MOTION.MotionStyle.RISE, "factor": Vector2.ONE,
			"offset": Vector2(0, 12), "close_factor": Vector2.ONE,
			"close_offset": Vector2(0, 6)},
		{"style": MOTION.MotionStyle.SLIDE, "factor": Vector2.ONE,
			"offset": Vector2(16, 0), "close_factor": Vector2.ONE,
			"close_offset": Vector2(8, 0)},
		{"style": MOTION.MotionStyle.FADE, "factor": Vector2.ONE,
			"offset": Vector2.ZERO, "close_factor": Vector2.ONE,
			"close_offset": Vector2.ZERO},
	]
	var settled: Dictionary = {"factor": Vector2.ONE, "offset": Vector2.ZERO, "alpha": 1.0}
	for profile: Dictionary in profiles:
		var motion: Node = track(MOTION.new()) as Node
		var targets: Array[CanvasItem] = []
		motion.call("setup", targets, 0.02, 0.22, 0.0, profile["style"])
		var start: Dictionary = {
			"factor": profile["factor"], "offset": profile["offset"], "alpha": 0.0
		}
		var closed: Dictionary = {
			"factor": profile["close_factor"], "offset": profile["close_offset"], "alpha": 0.0
		}
		var previous_open: Dictionary = start
		var previous_close: Dictionary = settled
		for step: int in range(5):
			var progress: float = float(step) * 0.25
			var opening: Dictionary = motion.call("_sample", progress, true, start)
			var closing: Dictionary = motion.call("_sample", progress, false, settled)
			_assert_toward_destination(opening, previous_open, settled)
			_assert_toward_destination(closing, previous_close, closed)
			previous_open = opening
			previous_close = closing
		assert_eq(previous_open, settled, "每种入场都精确收敛到原比例、原位置和完整透明度。")
		assert_eq(previous_close, closed, "每种退场都收敛到对应的小幅终点并完全透明。")
		var mid_open: Dictionary = motion.call("_sample", 0.4, true, start)
		assert_eq(motion.call("_sample", 0.0, false, mid_open), mid_open, "反向关闭不得重置初值。")
		var mid_close: Dictionary = motion.call("_sample", 0.4, false, mid_open)
		assert_eq(motion.call("_sample", 0.0, true, mid_close), mid_close, "反向打开不得重置初值。")


## 检查默认参数与旧四位置参数兼容，并限制旧高强度配置；参数无，返回无。
func test_defaults_and_legacy_setup_keep_scaling_small() -> void:
	var motion: Node = track(MOTION.new()) as Node
	var targets: Array[CanvasItem] = []
	var settled: Dictionary = {"factor": Vector2.ONE, "offset": Vector2.ZERO, "alpha": 1.0}
	motion.call("setup", targets)
	assert_eq(motion.get("_duration"), 0.22, "默认入场保持短促。")
	assert_eq(motion.get("_stagger"), 0.0, "多个目标默认同步播放。")
	var default_end: Dictionary = motion.call("_sample", 1.0, false, settled)
	assert_eq(default_end["factor"], Vector2(0.99, 0.99), "默认样式使用 2% 轻缩放。")
	motion.call("setup", targets, 0.22, 0.22, 0.0)
	var clamped_end: Dictionary = motion.call("_sample", 1.0, false, settled)
	assert_eq(clamped_end["factor"], Vector2(0.98, 0.98), "旧高强度参数最多使用 4% 轻缩放。")
	motion.call("setup", targets, -0.2)
	var zero_end: Dictionary = motion.call("_sample", 1.0, false, settled)
	assert_eq(zero_end["factor"], Vector2.ONE, "负强度不能变成放大。")


## 旧路径继续继承同一内核及公开接口；参数无，返回无。
func test_legacy_path_inherits_the_component() -> void:
	assert_eq(LEGACY_MOTION.get_base_script(), MOTION, "兼容入口必须只继承唯一内核。")
	assert_eq(LEGACY_MOTION.MotionStyle.FADE, MOTION.MotionStyle.FADE, "旧路径继承样式枚举。")
	assert_eq(LEGACY_MOTION.CLOSE_DURATION, MOTION.CLOSE_DURATION, "旧路径继承退场时长。")
	var legacy: Node = track(LEGACY_MOTION.new()) as Node
	for method: String in ["setup", "play_open", "play_close", "reset", "configure_from_inspector"]:
		assert_true(legacy.has_method(method), "兼容入口保留方法 %s。" % method)
	var targets: Array[CanvasItem] = []
	legacy.call("setup", targets, 0.02, 0.22, 0.0, LEGACY_MOTION.MotionStyle.FADE)
	var sample: Dictionary = legacy.call(
		"_sample", 0.5, true, {"factor": Vector2.ONE, "offset": Vector2.ZERO, "alpha": 0.0}
	)
	assert_eq(sample["factor"], Vector2.ONE, "旧路径淡入也不改变比例。")
	assert_eq(sample["offset"], Vector2.ZERO, "旧路径淡入也不改变位置。")


func _assert_toward_destination(
	current: Dictionary, previous: Dictionary, destination: Dictionary
) -> void:
	for key: String in ["factor", "offset"]:
		var current_value: Vector2 = current[key]
		var previous_value: Vector2 = previous[key]
		var destination_value: Vector2 = destination[key]
		var bounded: Vector2 = current_value.clamp(
			previous_value.min(destination_value), previous_value.max(destination_value)
		)
		assert_true(current_value.is_equal_approx(bounded), "%s 必须单调收敛且不越过终点。" % key)
	var factor: Vector2 = current["factor"]
	assert_true(is_equal_approx(factor.x, factor.y), "过渡不能额外拉伸或压扁界面。")
	var alpha: float = current["alpha"]
	var previous_alpha: float = previous["alpha"]
	var destination_alpha: float = destination["alpha"]
	assert_true(
		alpha >= minf(previous_alpha, destination_alpha) - 0.000001
		and alpha <= maxf(previous_alpha, destination_alpha) + 0.000001,
		"透明度必须在 0..1 内单调变化，不能闪回。"
	)

## 参数 tree：真实游戏 SceneTree。返回检查结果；调用方必须 await。
static func run_runtime_checks(tree: SceneTree) -> Dictionary:
	var result: Dictionary = {"checks": 0, "failures": [], "passed": false}
	var host := CanvasLayer.new()
	host.name = "JellyContractFixture"
	tree.root.add_child(host)
	var panel := Control.new()
	panel.position = Vector2(100, 80)
	panel.size = Vector2(320, 200)
	panel.scale = Vector2(1.2, 0.9)
	panel.modulate = Color(0.8, 0.7, 0.6, 0.85)
	host.add_child(panel)
	var motion: Node = MOTION.new()
	host.add_child(motion)
	var targets: Array[CanvasItem] = [panel]
	motion.call("setup", targets)
	motion.call("play_open")
	_expect(result, is_zero_approx(panel.modulate.a), "等待首次排版时保持完全透明。")
	await tree.process_frame
	await tree.process_frame
	var tween: Tween = motion.get("_tween") as Tween
	_expect(result, tween != null, "布局后建立真实 Tween。")
	if tween == null:
		host.free()
		return result
	# 先把测试时钟归零再采样真实 Tween 中点，避免首次加载耗时改变采样位置。
	# stop 不删除 Tween 的轨道，后面的手动步进仍执行生产动效及其真实目标变换。
	tween.stop()
	tween.custom_step(0.22 * 0.5)
	var middle_factor: Vector2 = panel.scale / Vector2(1.2, 0.9)
	_expect(result, middle_factor.x > 0.98 and middle_factor.x < 1.0, "真实中间帧仅轻微缩放。")
	_expect(result, is_equal_approx(middle_factor.x, middle_factor.y), "真实中间帧没有非等比形变。")
	_expect(result, panel.modulate.a > 0.0 and panel.modulate.a < 0.85, "真实中间帧正在淡入。")
	var events: Array[String] = []
	motion.call("play_close", func() -> void: events.append("old_close"))
	var closing: Tween = motion.get("_tween") as Tween
	closing.pause()
	closing.custom_step(0.05)
	var reversed_scale: Vector2 = panel.scale
	var reversed_position: Vector2 = panel.position
	var reversed_color: Color = panel.modulate
	motion.call("play_open")
	_expect(result, panel.scale.is_equal_approx(reversed_scale), "反向打开从当前尺度接续。")
	_expect(result, panel.position.is_equal_approx(reversed_position), "反向打开从当前位置接续。")
	_expect(result, panel.modulate.is_equal_approx(reversed_color), "反向打开从当前透明度接续。")
	var reopened: Tween = motion.get("_tween") as Tween
	reopened.custom_step(1.0)
	_expect(result, events.is_empty(), "过期关闭回调不能执行。")
	_expect(result, panel.position.is_equal_approx(Vector2(100, 80)), "原位置恢复。")
	_expect(result, panel.scale.is_equal_approx(Vector2(1.2, 0.9)), "非单位缩放恢复。")
	_expect(result, panel.modulate.is_equal_approx(Color(0.8, 0.7, 0.6, 0.85)), "原颜色透明度恢复。")
	var was_paused: bool = tree.paused
	tree.paused = true
	motion.call("play_close", func() -> void: events.append("paused_close"))
	await tree.create_timer(0.3, true, false, true).timeout
	_expect(result, events == ["paused_close"], "暂停期间完成关闭。")
	_expect(result, not bool(motion.call("is_animating")), "收尾没有动画锁。")
	tree.paused = was_paused
	motion.call("play_open")
	motion.call("play_close")
	await tree.process_frame
	await tree.process_frame
	_expect(result, not bool(motion.call("is_open_requested")), "首帧关闭不被延迟打开反转。")
	_expect(result, not bool(motion.call("is_animating")), "首帧取消释放遮罩。")
	events.clear()
	motion.call("play_close", func() -> void: events.append("deferred_old_close"))
	motion.call("play_open")
	await tree.process_frame
	await tree.process_frame
	_expect(result, events.is_empty(), "已关闭状态的排队回调也必须被新打开取消。")
	var last_tween: Tween = motion.get("_tween") as Tween
	panel.free()
	last_tween.custom_step(1.0)
	_expect(result, not bool(motion.call("is_animating")), "目标被释放后仍能安全释放动画锁。")
	await _check_group_motion(tree, host, motion, result)
	await _check_component_configuration(tree, result)
	host.free()
	result["passed"] = (result["failures"] as Array).is_empty()
	return result


static func _check_group_motion(
	tree: SceneTree, host: CanvasLayer, motion: Node, result: Dictionary
) -> void:
	var first := Control.new()
	first.position = Vector2(40, 30)
	first.modulate.a = 0.8
	host.add_child(first)
	var second := Control.new()
	second.position = Vector2(400, 180)
	second.scale = Vector2(3, 3)
	second.modulate.a = 0.5
	host.add_child(second)
	var targets: Array[CanvasItem] = [first, second]
	motion.call("setup", targets, 0.02, 0.22, 0.0, MOTION.MotionStyle.RISE)
	motion.call("play_open")
	_expect(
		result, is_zero_approx(first.modulate.a) and is_zero_approx(second.modulate.a),
		"上浮目标在等待首次排版时完全透明。"
	)
	await tree.process_frame
	await tree.process_frame
	var tween: Tween = motion.get("_tween") as Tween
	_expect(result, tween != null, "多目标过渡建立真实 Tween。")
	if tween == null:
		return
	tween.stop()
	# 零秒步进不会重放 Tween；正的小步进才能检查真实轨道在起点附近的值。
	var early_step: float = 0.0001
	tween.custom_step(early_step)
	_expect(result, first.position.distance_to(Vector2(40, 42)) < 0.02, "上浮极早期接近下方 12px。")
	_expect(result, first.modulate.a >= 0.0 and first.modulate.a < 0.002, "上浮极早期仅有极小淡入。")
	tween.custom_step(0.22 * 0.5 - early_step)
	var first_offset: Vector2 = first.position - Vector2(40, 30)
	var second_offset: Vector2 = second.position - Vector2(400, 180)
	_expect(result, first_offset.y > 0 and first_offset.y < 12, "真实上浮中间帧位于小幅范围内。")
	_expect(result, first_offset.is_equal_approx(second_offset), "多目标默认保持相同位移节奏。")
	_expect(result, first.scale == Vector2.ONE and second.scale == Vector2(3, 3), "上浮不改缩放。")
	_expect(
		result, is_equal_approx(first.modulate.a / 0.8, second.modulate.a / 0.5),
		"不同原始透明度的目标使用相同淡入进度。"
	)
	tween.custom_step(1.0)
	_expect(result, first.position == Vector2(40, 30), "多目标首项回到原位。")
	_expect(result, second.position == Vector2(400, 180), "多目标末项回到原位。")


static func _expect(result: Dictionary, condition: bool, message: String) -> void:
	result["checks"] = int(result["checks"]) + 1
	if not condition:
		(result["failures"] as Array).append(message)


static func _check_component_configuration(tree: SceneTree, result: Dictionary) -> void:
	var fixture: Node = COMPONENT_FIXTURE.instantiate()
	tree.root.add_child(fixture)
	var component: Node = fixture.get_node("UITransition")
	var targets: Array = component.get("_targets")
	_expect(result, targets.size() == 2, "组件场景重载后自动解析两个目标路径。")
	_expect(result, targets[0] is Control and targets[1] is Node2D, "组件支持界面与二维节点目标。")
	_expect(result, int(component.get("_style")) == MOTION.MotionStyle.FADE, "场景保存的样式生效。")
	_expect(result, is_equal_approx(float(component.get("_duration")), 0.27), "场景保存的时长生效。")
	component.call("play_open")
	var tween: Tween = await _wait_for_tween(tree, component)
	_expect(result, tween != null, "检查器配置可直接建立动画。")
	if tween != null:
		tween.custom_step(1.0)
		_expect(result, not bool(component.call("is_animating")), "检查器配置动画完成后释放门禁。")
	var valid_targets: Array = (component.get("_targets") as Array).duplicate()
	var invalid_paths: Array[NodePath] = [^"../Missing"]
	component.set("target_paths", invalid_paths)
	_expect(result, not bool(component.call("configure_from_inspector")), "不存在的目标返回配置失败。")
	_expect(result, component.get("_targets") == valid_targets, "配置失败保留上次有效目标。")
	var duplicate_paths: Array[NodePath] = [^"../Panel", ^"../Panel"]
	component.set("target_paths", duplicate_paths)
	_expect(result, not bool(component.call("configure_from_inspector")), "拒绝重复目标。")
	var child := Control.new()
	child.name = "Child"
	fixture.get_node("Panel").add_child(child)
	var nested_paths: Array[NodePath] = [^"../Panel", ^"../Panel/Child"]
	component.set("target_paths", nested_paths)
	_expect(result, not bool(component.call("configure_from_inspector")), "拒绝父子同时参与动画。")
	var explicit: Node = MOTION.new()
	var configured_paths: Array[NodePath] = [^"../Panel"]
	explicit.set("target_paths", configured_paths)
	explicit.set("motion_style", MOTION.MotionStyle.FADE)
	var explicit_targets: Array[CanvasItem] = [fixture.get_node("Accent") as CanvasItem]
	explicit.call("setup", explicit_targets, 0.02, 0.33, 0.0, MOTION.MotionStyle.RISE)
	fixture.add_child(explicit)
	_expect(result, int(explicit.get("_style")) == MOTION.MotionStyle.RISE, "入树前显式配置优先。")
	_expect(result, explicit.get("_targets") == explicit_targets, "检查器不会覆盖显式目标。")
	component.set("target_paths", configured_paths)
	_expect(result, bool(component.call("configure_from_inspector")), "有效配置可重新应用。")
	fixture.remove_child(component)
	fixture.add_child(component)
	_expect(result, (component.get("_targets") as Array).size() == 1, "缓存移出重入保留配置。")
	fixture.free()


static func _wait_for_tween(tree: SceneTree, motion: Node) -> Tween:
	# 复杂场景的延迟布局可能超过两帧，等待真实轨道比固定帧数稳定。
	for frame: int in range(30):
		var tween: Tween = motion.get("_tween") as Tween
		if tween != null:
			return tween
		await tree.process_frame
	return null
