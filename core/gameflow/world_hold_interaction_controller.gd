extends Node
## 管理局外长按的唯一活动状态、进度反馈、取消处理与完成回调。
class_name WorldHoldInteractionController

## 主场景 HUD 的稳定相对路径；导出值为空时也使用此默认值。
const DEFAULT_PROGRESS_INDICATOR_PATH := NodePath("../../../UI/HUDLayer/HUDRoot/WorldHoldProgressIndicator")

## 负责显示进度圆环的 HUD 节点路径。
@export var progress_indicator_path: NodePath = DEFAULT_PROGRESS_INDICATOR_PATH

## 当前是否存在尚未完成或取消的局外长按；只读状态属性。
var is_holding: bool:
	get:
		return _active_owner != null

var _progress_indicator: WorldHoldProgressIndicator
var _hold_tween: Tween
var _active_owner: Node
var _completion_callback: Callable


func _ready() -> void:
	if progress_indicator_path.is_empty():
		# 编辑器热重载可能使导出路径暂时为空，恢复默认值避免运行时失去 HUD 依赖。
		push_warning("WorldHoldInteractionController.progress_indicator_path 为空，已恢复主场景默认圆环路径。")
		progress_indicator_path = DEFAULT_PROGRESS_INDICATOR_PATH

	_progress_indicator = get_node_or_null(progress_indicator_path) as WorldHoldProgressIndicator
	if _progress_indicator == null:
		push_error("WorldHoldInteractionController 无法解析圆环节点：%s" % progress_indicator_path)
		return
	_progress_indicator.clear_hold_progress()


func _exit_tree() -> void:
	cancel_active_hold()


## 开始一次由行动值决定时长的局外长按。
##
## 传进来的是**未经倍率缩放**的基础秒数：长按速度倍率统一由 begin_timed_hold 施加，
## 这里若再缩放一次就会变成倍率的平方。
##
## 参数 hold_owner：发起交互的有效节点，新目标会取消旧目标。
## 参数 action_point_cost：本次交互实际消耗的行动值。
## 参数 on_completed：仅在进度完成时调用的无参回调。
## 参数 progress_target：用于绘制圆环的可见目标节点。
## 返回值：无；零或负行动值会立即调用回调。
func begin_hold(hold_owner: Node, action_point_cost: int, on_completed: Callable, progress_target: Node) -> void:
	begin_timed_hold(hold_owner, WorldInteractionTiming.get_hold_duration_seconds(action_point_cost),
		on_completed, progress_target)


## 开始按真实秒数计时的长按，供拆除等不消耗行动值的操作复用圆环。
##
## 长按速度倍率在这里统一施加：本方法是唯一的计时执行点，按行动值换算的 begin_hold 与
## 直接给秒数的拆除等调用都会经过它，因此只缩放这一处就能覆盖全部局外长按。
##
## 参数 hold_owner 为拥有者，duration_seconds 为未经倍率缩放的基础时长，
## on_completed 为完成回调，progress_target 为圆环锚点。
## 返回值：无；仅管理等待与取消，不负责业务扣费，缩放后仍为零的时长保持即时回调。
func begin_timed_hold(hold_owner: Node, duration_seconds: float, on_completed: Callable, progress_target: Node) -> void:
	if hold_owner == null:
		return

	cancel_active_hold()

	# 用缩放后的有效时长驱动 Tween；倍率只改变等待表现，调用方的行动值扣费保持原值。
	var effective_seconds: float = WorldInteractionTiming.scale_hold_seconds(duration_seconds)

	# 零消耗交互转换为零时长，保留原有即时点击体验，不创建无意义的 Tween。
	if effective_seconds <= 0.0:
		if on_completed.is_valid():
			on_completed.call()
		return

	if _progress_indicator == null:
		push_error("WorldHoldInteractionController 尚未初始化圆环节点。")
		return

	_active_owner = hold_owner
	_completion_callback = on_completed
	_progress_indicator.set_hold_progress_target(progress_target)
	_progress_indicator.set_hold_progress(0.0)

	_hold_tween = create_tween()
	_hold_tween.tween_method(_progress_indicator.set_hold_progress, 0.0, 1.0, effective_seconds)
	_hold_tween.finished.connect(_complete_active_hold, CONNECT_ONE_SHOT)


## 仅取消指定 owner 持有的长按。
##
## 参数 hold_owner：请求取消的交互节点；非当前 owner 时不产生影响。
## 返回值：无。
func cancel_hold_for(hold_owner: Node) -> void:
	if hold_owner == null or _active_owner != hold_owner:
		return
	cancel_active_hold()


## 无条件取消当前长按，供场景退出和全局鼠标释放使用。
##
## 返回值：无；取消会清理 Tween、回调和圆环状态。
func cancel_active_hold() -> void:
	if _hold_tween != null and _hold_tween.is_valid():
		_hold_tween.kill()

	_hold_tween = null
	_active_owner = null
	_completion_callback = Callable()
	if _progress_indicator != null:
		_progress_indicator.clear_hold_progress()


func _complete_active_hold() -> void:
	var completed_owner := _active_owner
	var completed_callback := _completion_callback

	_hold_tween = null
	_active_owner = null
	_completion_callback = Callable()
	if _progress_indicator != null:
		_progress_indicator.clear_hold_progress()

	# 先清空状态再调用业务回调，避免回调重入时重复结算。
	if completed_owner != null and is_instance_valid(completed_owner) and completed_callback.is_valid():
		completed_callback.call()
