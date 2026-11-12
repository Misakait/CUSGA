## 界面共用的轻量过渡，只改变视图，不拥有库存、导航或暂停状态。
## 调用方先显示视图，再调用 play_open；关闭时在完成回调里隐藏视图。
class_name UITransition
extends Node

## 轻缩放、上浮、侧滑、淡入淡出；所有样式均单向收敛，不做回弹或非等比形变。
enum MotionStyle { SOFT_SCALE, RISE, SLIDE, FADE }

const CLOSE_DURATION: float = 0.14

@export_group("动画目标")
## 相对于本组件的目标路径；仅支持 Control 或 Node2D，不能同时选择父子节点。
@export var target_paths: Array[NodePath] = []

@export_group("动画效果")
## 打开方式；淡入淡出保持目标位置与比例不变。
@export var motion_style: MotionStyle = MotionStyle.SOFT_SCALE
## 等比缩放幅度；仅轻缩放样式使用，0.02 表示缩小 2% 后展开。
@export_range(0.0, 0.04, 0.001) var scale_strength: float = 0.02
## 单个目标的打开时长，单位为秒；关闭时长统一为 0.14 秒。
@export_range(0.1, 2.0, 0.01, "or_greater") var open_duration: float = 0.22
## 相邻目标开始打开的间隔，单位为秒；外框和内容需要同步时设为 0。
@export_range(0.0, 0.2, 0.005, "or_greater") var target_stagger: float = 0.0

var _configured: bool = false
var _targets: Array[CanvasItem] = []
var _entries: Array[Dictionary] = []
var _staged_colors: Dictionary = {}
var _strength: float = 0.02
var _duration: float = 0.22
var _stagger: float = 0.0
var _style: MotionStyle = MotionStyle.SOFT_SCALE
var _open_requested: bool = false
var _busy: bool = false
var _generation: int = 0
var _tween: Tween = null
var _completed: Callable
var _guard_layer: CanvasLayer = null
var _guard: Control = null


func _ready() -> void:
	# 代码在入树前传入的 setup 配置优先，避免检查器默认值覆盖有效配置。
	if not _configured and not target_paths.is_empty():
		configure_from_inspector()


## 从检查器重新读取目标和动画参数；已有动画只在全部配置有效时才重置。
## 参数无；全部路径有效且不重复驱动时返回 true，失败时保留上一份有效配置。
func configure_from_inspector() -> bool:
	var targets: Array[CanvasItem] = []
	for path: NodePath in target_paths:
		var target: Node = get_node_or_null(path) if not path.is_empty() else null
		if target == null or not (target is Control or target is Node2D):
			push_warning("UITransition：目标路径“%s”必须指向 Control 或 Node2D。" % path)
			return false
		for existing: CanvasItem in targets:
			if existing == target or existing.is_ancestor_of(target) or target.is_ancestor_of(existing):
				push_warning("UITransition：目标不能重复，也不能同时选择父节点及其子节点。")
				return false
		targets.append(target as CanvasItem)
	if targets.is_empty():
		push_warning("UITransition：请至少配置一个动画目标。")
		return false
	setup(targets, scale_strength, open_duration, target_stagger, motion_style)
	return true


## 配置参与过渡的独立视图，保留原始节点结构和缩放。
## 参数 targets：不能互为父子的 Control/Node2D；strength：轻缩放幅度，限制在 0..0.04；
## duration：打开秒数，最少 0.1 秒；stagger：相邻视图区的错峰秒数，默认同步；
## style：轻缩放、上浮、侧滑或淡入淡出，默认轻缩放。返回无。
func setup(
	targets: Array[CanvasItem], strength: float = 0.02,
	duration: float = 0.22, stagger: float = 0.0,
	style: MotionStyle = MotionStyle.SOFT_SCALE
) -> void:
	reset()
	_configured = true
	_targets.assign(targets)
	_strength = clampf(strength, 0.0, 0.04)
	_duration = maxf(duration, 0.1)
	_stagger = maxf(stagger, 0.0)
	_style = style
	process_mode = Node.PROCESS_MODE_ALWAYS


## 展开视图；重复打开不叠加动画，反向请求从当前比例、位置和透明度接续。
## 参数 completed：完成且仍是本次请求时执行的回调。返回无。
func play_open(completed: Callable = Callable()) -> void:
	if _open_requested:
		if completed.is_valid():
			if _busy:
				_completed = completed
			else:
				_call_if_current.call_deferred(_generation, true, completed)
		return
	_generation += 1
	_open_requested = true
	_completed = completed
	_kill_tween()
	_busy = true
	_set_guard(true)
	if not _entries.is_empty():
		_start_animation(true, _generation)
		return
	# 首次显示时 Container 还未排版，先只隐藏颜色，下一帧再读取真实位置。
	for value: Variant in _targets:
		if is_instance_valid(value):
			var target: CanvasItem = value as CanvasItem
			_staged_colors[target.get_instance_id()] = target.modulate
			var hidden_color: Color = target.modulate
			hidden_color.a = 0.0
			target.modulate = hidden_color
	_begin_open_after_layout.call_deferred(_generation)


## 收拢视图，动画完成前由宿主继续保留原暂停与输入所有权。
## 参数 completed：通常负责隐藏宿主并恢复其暂停状态。返回无。
func play_close(completed: Callable = Callable()) -> void:
	if not _open_requested and not _busy:
		if completed.is_valid():
			_call_if_current.call_deferred(_generation, false, completed)
		return
	_generation += 1
	_open_requested = false
	_completed = completed
	_kill_tween()
	if not _staged_colors.is_empty():
		# 尚未显示的面板不必先闪现再收起。
		_restore_staged_colors()
		_finish(_generation)
		return
	if _entries.is_empty():
		_capture_entries()
	_busy = true
	_set_guard(true)
	_start_animation(false, _generation)


## 外部视图直接恢复显示后，接管为“已打开且空闲”的基准状态。
## 用于覆盖面板关闭时复用缓存界面：取消未完成的退场，不重复播放入场。
## 参数无；返回无。
func resume_open() -> void:
	reset()
	_open_requested = true


## 取消动效与旧回调，恢复基准属性；缓存离场和销毁时调用。
## 参数无；返回无。
func reset() -> void:
	_generation += 1
	_kill_tween()
	_restore_staged_colors()
	_restore_entries()
	_entries.clear()
	_completed = Callable()
	_busy = false
	_open_requested = false
	_set_guard(false)


## 返回最新请求是否为打开，供快捷键反向切换，不能用可见性代替。
## 参数无；返回目标打开状态。
func is_open_requested() -> bool:
	return _open_requested


## 返回是否正在等布局或播放动画，供宿主拦截交易、拖动等操作。
## 参数无；返回动画是否占用视图。
func is_animating() -> bool:
	return _busy


func _begin_open_after_layout(generation: int) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if generation != _generation or not is_inside_tree():
		return
	_restore_staged_colors()
	_capture_entries()
	var initial_factor := Vector2.ONE
	var initial_offset := Vector2.ZERO
	match _style:
		MotionStyle.SOFT_SCALE:
			initial_factor = Vector2.ONE * (1.0 - _strength)
		MotionStyle.RISE:
			initial_offset = Vector2(0, 12)
		MotionStyle.SLIDE:
			initial_offset = Vector2(16, 0)
	for entry: Dictionary in _entries:
		entry["factor"] = initial_factor
		entry["offset"] = initial_offset
		entry["alpha"] = 0.0
	_start_animation(true, generation)


func _capture_entries() -> void:
	_entries.clear()
	var center: Vector2 = get_viewport().get_visible_rect().get_center()
	if _targets.size() == 1 and is_instance_valid(_targets[0]) and _targets[0] is Control:
		var single: Control = _targets[0] as Control
		center = single.get_global_transform_with_canvas() * (single.size * 0.5)
	for value: Variant in _targets:
		if not is_instance_valid(value) or not (value is Control or value is Node2D):
			continue
		var target: CanvasItem = value as CanvasItem
		var position_value: Vector2
		var scale_value: Vector2
		var pivot_value := Vector2.ZERO
		if target is Control:
			var control: Control = target as Control
			position_value = control.position
			scale_value = control.scale
			pivot_value = control.pivot_offset
		else:
			var node: Node2D = target as Node2D
			position_value = node.position
			scale_value = node.scale
		# 把共同屏幕中心换算到每个目标的父坐标，避免多个分区各自乱飞。
		var parent_to_screen: Transform2D = target.get_global_transform_with_canvas() \
			* target.get_transform().affine_inverse()
		var screen_to_parent: Transform2D = parent_to_screen.affine_inverse()
		_entries.append({"target": target, "position": position_value, "scale": scale_value,
			"pivot": pivot_value, "center": screen_to_parent * center, "basis": screen_to_parent,
			"color": target.modulate, "factor": Vector2.ONE, "offset": Vector2.ZERO, "alpha": 1.0})


func _start_animation(opening: bool, generation: int) -> void:
	if not is_inside_tree() or _entries.is_empty():
		_finish(generation)
		return
	var starts: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		starts.append({"factor": entry["factor"], "offset": entry["offset"], "alpha": entry["alpha"]})
	var total: float = _duration + _stagger * maxf(_entries.size() - 1, 0) \
		if opening else CLOSE_DURATION
	_advance(0.0, opening, starts, total)
	_tween = create_tween()
	# 地图和暂停菜单先暂停游戏；表现层仍需推进且不受战斗时间倍率影响。
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_ignore_time_scale(true)
	_tween.tween_method(_advance.bind(opening, starts, total), 0.0, 1.0, total)
	_tween.tween_callback(_finish.bind(generation))


func _advance(progress: float, opening: bool, starts: Array[Dictionary], total: float) -> void:
	for index: int in _entries.size():
		var entry: Dictionary = _entries[index]
		var local_progress: float = clampf(
			(progress * total - index * _stagger) / _duration, 0, 1
		) if opening else progress
		var sample: Dictionary = _sample(local_progress, opening, starts[index])
		entry["factor"] = sample["factor"]
		entry["offset"] = sample["offset"]
		entry["alpha"] = sample["alpha"]
		_apply_entry(entry)


func _sample(progress: float, opening: bool, start: Dictionary) -> Dictionary:
	var target_factor := Vector2.ONE
	var target_offset := Vector2.ZERO
	if not opening:
		match _style:
			MotionStyle.SOFT_SCALE:
				target_factor = Vector2.ONE * (1.0 - _strength * 0.5)
			MotionStyle.RISE:
				target_offset = Vector2(0, 6)
			MotionStyle.SLIDE:
				target_offset = Vector2(8, 0)
	var weight: float = clampf(progress, 0.0, 1.0)
	weight = 1.0 - pow(1.0 - weight, 3.0) if opening else smoothstep(0.0, 1.0, weight)
	# 只从本次请求接手的实际状态插值，反向操作不重新套用初始比例或偏移。
	var start_factor: Vector2 = start["factor"]
	var start_offset: Vector2 = start["offset"]
	var start_alpha: float = start["alpha"]
	return {
		"factor": start_factor.lerp(target_factor, weight),
		"offset": start_offset.lerp(target_offset, weight),
		"alpha": lerpf(start_alpha, 1.0 if opening else 0.0, weight),
	}


func _apply_entry(entry: Dictionary) -> void:
	var value: Variant = entry["target"]
	if not is_instance_valid(value):
		return
	var target: CanvasItem = value as CanvasItem
	var factor: Vector2 = entry["factor"]
	var base_position: Vector2 = entry["position"]
	var pivot: Vector2 = entry["pivot"]
	var center: Vector2 = entry["center"]
	var basis: Transform2D = entry["basis"]
	var offset: Vector2 = entry["offset"]
	var position_value: Vector2 = base_position \
		+ (base_position + pivot - center) * (factor - Vector2.ONE) \
		+ basis.basis_xform(offset)
	var scale_value: Vector2 = entry["scale"] * factor
	if target is Control:
		(target as Control).position = position_value
		(target as Control).scale = scale_value
	else:
		(target as Node2D).position = position_value
		(target as Node2D).scale = scale_value
	var color: Color = entry["color"]
	color.a *= float(entry["alpha"])
	target.modulate = color


func _finish(generation: int) -> void:
	if generation != _generation:
		return
	_restore_entries()
	_entries.clear()
	_busy = false
	_set_guard(false)
	var callback: Callable = _completed
	_completed = Callable()
	if callback.is_valid():
		callback.call()


func _call_if_current(generation: int, opening: bool, callback: Callable) -> void:
	# 已完成请求也要检查代次；下一次打开不能被上一帧排队的关闭回调隐藏。
	if generation == _generation and opening == _open_requested \
			and is_inside_tree() and callback.is_valid():
		callback.call()


func _restore_entries() -> void:
	for entry: Dictionary in _entries:
		entry["factor"] = Vector2.ONE
		entry["offset"] = Vector2.ZERO
		entry["alpha"] = 1.0
		_apply_entry(entry)


func _restore_staged_colors() -> void:
	for value: Variant in _targets:
		if is_instance_valid(value):
			var target: CanvasItem = value as CanvasItem
			if _staged_colors.has(target.get_instance_id()):
				target.modulate = _staged_colors[target.get_instance_id()]
	_staged_colors.clear()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _set_guard(enabled: bool) -> void:
	if enabled and _guard_layer == null and is_inside_tree():
		_guard_layer = CanvasLayer.new()
		_guard_layer.name = "MotionInputGuard"
		_guard_layer.layer = 1000
		add_child(_guard_layer)
		_guard = Control.new()
		_guard.mouse_filter = Control.MOUSE_FILTER_STOP
		_guard.focus_mode = Control.FOCUS_NONE
		_guard_layer.add_child(_guard)
	if is_instance_valid(_guard_layer):
		_guard_layer.visible = enabled
		if enabled:
			_guard.size = get_viewport().get_visible_rect().size


func _exit_tree() -> void:
	reset()
