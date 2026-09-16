extends SceneTree

const WORLD_HOLD_CONTROLLER_SCRIPT := "res://core/gameflow/WorldHoldInteractionController.cs"
const WORLD_HOLD_INDICATOR_SCRIPT := "res://core/ui/hud/WorldHoldProgressIndicator.cs"

# 收集断言失败文本，保持项目现有 Godot 运行器的退出约定。
var _failures: Array[String] = []


# 记录长按完成回调次数，验证取消路径不会执行局外业务逻辑。
class CompletionTracker:
	# 完成回调实际被执行的次数。
	var call_count: int = 0

	# 由长按控制器在圆环填满时调用。
	func mark_completed() -> void:
		call_count += 1


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_test_controller_has_default_indicator_path()
	await _test_indicator_visibility_and_progress_reset()
	await _test_cancelled_hold_does_not_complete()
	_finish()


func _test_controller_has_default_indicator_path() -> void:
	# 默认路径必须在场景导出值未加载时仍可解析主场景 HUD，防止控制器初始化为空。
	var controller: Node = load(WORLD_HOLD_CONTROLLER_SCRIPT).new()
	# 通过动态属性读取验证 C# 构造后的真实默认值，而不是只检查场景文本。
	var progress_indicator_path: NodePath = controller.get("ProgressIndicatorPath")

	_assert(not progress_indicator_path.is_empty(), "长按控制器必须提供非空的默认圆环节点路径。")
	_assert(
		str(progress_indicator_path) == "../../../UI/HUDLayer/HUDRoot/WorldHoldProgressIndicator",
		"长按控制器的默认圆环路径必须指向主场景 HUD 组件。"
	)
	controller.free()


func _test_indicator_visibility_and_progress_reset() -> void:
	# 独立实例化 HUD 组件，避免测试依赖完整主场景的游戏状态。
	var indicator: Control = load(WORLD_HOLD_INDICATOR_SCRIPT).new()
	root.add_child(indicator)
	await process_frame

	_assert(not bool(indicator.get("IsHoldProgressVisible")), "鼠标圆环默认应隐藏。")
	_assert(is_equal_approx(float(indicator.get("RingRadius")), 16.0), "鼠标圆环默认半径应为 16 像素。")
	_assert(is_equal_approx(float(indicator.get("RingWidth")), 6.0), "鼠标圆环默认线宽应为 6 像素。")
	_assert(Vector2(indicator.get("CursorOffset")).is_equal_approx(Vector2.ZERO), "圆环默认偏移应为零，确保圆心落在目标右下角。")
	# 构造具有确定矩形边界的可见目标，验证 HUD 使用其右下角而非鼠标坐标。
	var target: Control = Control.new()
	target.position = Vector2(100.0, 50.0)
	target.size = Vector2(80.0, 40.0)
	root.add_child(target)
	await process_frame
	indicator.call("SetHoldProgressTarget", target)
	# 读取公开锚点坐标，避免测试依赖不可见的 DrawArc 像素输出。
	var target_anchor: Vector2 = indicator.get("CurrentHoldTargetScreenPosition")
	_assert(target_anchor.is_equal_approx(Vector2(180.0, 90.0)), "圆环应锚定到交互目标的右下角。")
	indicator.call("SetHoldProgress", 0.5)
	_assert(bool(indicator.get("IsHoldProgressVisible")), "开始长按后应显示鼠标圆环。")
	_assert(is_equal_approx(float(indicator.get("CurrentProgress")), 0.5), "圆环应保存传入的归一化进度。")

	indicator.call("ClearHoldProgress")
	_assert(not bool(indicator.get("IsHoldProgressVisible")), "取消或完成后圆环应立即隐藏。")
	_assert(is_equal_approx(float(indicator.get("CurrentProgress")), 0.0), "清理圆环时应将进度复位为零。")

	target.queue_free()
	indicator.queue_free()
	await process_frame


func _test_cancelled_hold_does_not_complete() -> void:
	# 控制器与圆环使用局部节点树，验证目标松开只取消而不会调用业务回调。
	var controller: Node = load(WORLD_HOLD_CONTROLLER_SCRIPT).new()
	# 圆环必须先成为控制器子节点，确保导出路径在 _ready 时可解析。
	var indicator: Control = load(WORLD_HOLD_INDICATOR_SCRIPT).new()
	indicator.name = "Indicator"
	controller.add_child(indicator)
	controller.set("ProgressIndicatorPath", NodePath("Indicator"))
	root.add_child(controller)
	await process_frame

	# 独立 owner 模拟方向按钮或棋盘卡牌。
	var owner := Node.new()
	root.add_child(owner)
	# 回调用小对象计数，避免将测试结果耦合到具体业务交互。
	var tracker := CompletionTracker.new()
	controller.call("BeginHold", owner, 10, Callable(tracker, "mark_completed"), owner)
	await process_frame
	controller.call("CancelHoldFor", owner)
	await create_timer(1.1).timeout

	_assert(tracker.call_count == 0, "提前松开长按不得执行局外交互回调。")
	_assert(not bool(indicator.get("IsHoldProgressVisible")), "提前松开后不得残留鼠标圆环。")

	owner.queue_free()
	controller.queue_free()
	await process_frame


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("All world hold interaction Godot tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)
