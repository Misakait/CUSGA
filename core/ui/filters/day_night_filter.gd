extends ColorRect

## 昼夜动态滤镜组件。
##
## 职责单一：把 TimeSystem 的时间状态换算成一层「世界层滤镜颜色」，并按时长平滑跟随。
## 组件不感知自己被挂在哪个场景、哪一层 —— 探索场景用 CanvasLayer 分层、战斗场景用
## z_index 分层，因此层级策略由宿主场景自行决定，组件本身保持可复用。
##
## 混合前提：本节点预期配合 CanvasItemMaterial 的 BLEND_MODE_MUL 使用，
## 最终像素 = 源像素 × color。白色 (1,1,1,1) 表示完全不改变画面，颜色越暗压暗越强。
##
## 挂载方式：配套场景 day_night_filter.tscn 的根是普通 Node（DayNightFilter），
## 真正绘制的是它的子节点 FilterRect（ColorRect，本脚本挂在它身上）。
## 这层宿主不是多余的：Control 的 anchors 以父级 CanvasItem 的 anchorable rect 为参考，
## 而 Node2D 的 anchorable rect 是空矩形，会让全屏 ColorRect 的 size 退化成 0×0、
## 静默地什么都画不出来（实测：战斗场景根节点是 Node2D，直接挂 ColorRect 时滤镜完全失效）；
## 父级是普通 Node 时才会回退到视口矩形。因此必须连同内置宿主一起实例化，
## 不要把 FilterRect 单独挂到 Node2D 或其它非 Control 的 CanvasItem 下面。
##
## 颜色由 TimeSystem 的昼夜状态与阶段进度共同决定：
##   白天：day_color → dusk_color（清晨通透 → 黄昏转暖）
##   夜晚：night_color → dawn_color（入夜最暗 → 黎明转亮）
## 阶段边界的两个端点不相等，这个跳变由平滑跟随吸收，这正是「有过渡」的来源。

## TimeSystem autoload 的绝对路径。
## 用 NodePath 而不是直接引用 autoload 标识符，因为 test_run 环境没有 autoload，
## 直接引用会让脚本在测试环境里连解析都过不去。
const TIME_SYSTEM_PATH: NodePath = ^"/root/TimeSystem"

## 读取不到 TimeSystem.PhaseLength 时使用的回退阶段长度，与生产实现保持一致。
## TimeSystem 把阶段长度声明为脚本常量，Object.get() 读不到常量，
## 因此正常路径是 get_script_constant_map()，本常量只作为最后兜底。
const DEFAULT_PHASE_LENGTH: int = 100

## 中性滤镜颜色：乘法混合下白色等价于「完全不改变画面」，用于关闭滤镜与缺少时间系统时。
const NEUTRAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)

## 指数平滑的时间常数占 transition_time 的比例。
## transition_time 的语义是「约 95% 收敛所需秒数」，而 3 倍时间常数对应约 95% 收敛，
## 所以时间常数取它的三分之一，让导出参数的语义直观可调。
const SMOOTHING_TAU_RATIO: float = 1.0 / 3.0

## 时间常数下限（秒）。防止 transition_time 被设为 0 或负数时除零。
const MIN_TAU: float = 0.001

@export_group("开关")

## 是否启用滤镜。关闭时画面固定为中性色，便于调试对比。
## 运行期可动态修改，修改后立即生效。
@export var enabled: bool = true

@export_group("昼夜颜色")

## 白天阶段起点（阶段进度为 0）的滤镜颜色，即清晨。
## 乘法混合下 (1,1,1,1) 表示完全不改变画面；调暗会让整个白天一起变暗。
@export var day_color: Color = Color(1.0, 1.0, 1.0, 1.0)

## 白天阶段终点（阶段进度接近满）的滤镜颜色，即黄昏。
## 默认偏暖黄且几乎不压暗，只做色温偏移；这是「白天随时间变暖」的来源。
@export var dusk_color: Color = Color(1.0, 0.86, 0.68, 1.0)

## 夜晚阶段起点（刚入夜）的滤镜颜色，即最暗的夜色。
## 默认冷蓝，整体亮度约为原始的一半，沿用改造前地图背景夜色的观感量级，
## 避免本次改造让夜晚亮度出现明显落差。
@export var night_color: Color = Color(0.40, 0.46, 0.70, 1.0)

## 夜晚阶段终点（即将天亮）的滤镜颜色，即黎明。
## 默认淡青白，取值向 day_color 靠拢，保证跨入白天时不产生突兀跳变。
@export var dawn_color: Color = Color(0.82, 0.90, 0.96, 1.0)

@export_group("过渡")

## 从当前颜色收敛到目标颜色约 95% 所需的秒数。
## 时间推进是离散跳变（例如地图移动一次 +10 点），靠它把跳变抹成可见渐变。
## 取值越小越跟手，越大越柔和。
@export var transition_time: float = 1.0

## 时间系统节点；_ready 时解析，缺失时为 null 并保持中性颜色。
var _time_system: Node = null

## 当前显示中的滤镜颜色，作为平滑追踪的状态量。
var _current_color: Color = NEUTRAL_COLOR


## 解析时间系统并直接吸附到当前时刻应有的颜色。
## 出场即吸附而不播放过渡，避免场景切换（例如进入战斗）时补播一次多余渐变。
## 参数：无。返回值：无。
func _ready() -> void:
	_fit_to_viewport()
	_time_system = get_node_or_null(TIME_SYSTEM_PATH)
	if _time_system == null:
		# 可降级依赖：没有时间系统时保持中性，不影响游戏继续运行。
		push_warning("DayNightFilter 未找到 TimeSystem，昼夜滤镜保持中性颜色。")
	_current_color = get_target_color()
	color = _current_color


## 每帧把显示颜色朝目标颜色推进。
## 参数 delta：距上一帧经过的秒数。
## 返回值：无。
func _process(delta: float) -> void:
	var target_color: Color = get_target_color()
	if not enabled:
		# 关闭时目标落到中性色，但仍走同一套平滑逻辑，避免开关瞬间闪一下。
		target_color = NEUTRAL_COLOR
	if _current_color.is_equal_approx(target_color):
		# 差值已不可见时直接吸附，避免无限逼近却永远到不了目标。
		_current_color = target_color
	else:
		# 帧率无关的指数平滑：混合系数只由 delta 与时间常数决定，
		# 因此掉帧、连续推进时间或重复赋值都不会累积误差，也不会停在中途。
		var tau: float = maxf(transition_time * SMOOTHING_TAU_RATIO, MIN_TAU)
		var blend: float = 1.0 - exp(-delta / tau)
		_current_color = _current_color.lerp(target_color, blend)
	color = _current_color


## 计算当前时间状态对应的目标滤镜颜色。
## 参数：无。
## 返回值：目标颜色；未解析到 TimeSystem 时返回中性色。
func get_target_color() -> Color:
	if _time_system == null:
		return NEUTRAL_COLOR
	var is_night: bool = bool(_time_system.get("IsNight"))
	var progress_ratio: float = _resolve_phase_ratio()
	if is_night:
		return night_color.lerp(dawn_color, progress_ratio)
	return day_color.lerp(dusk_color, progress_ratio)


## 读取当前显示中的滤镜颜色，供测试、调试与运行时检查使用。
## 参数：无。
## 返回值：当前颜色。
func get_current_color() -> Color:
	return _current_color


## 把阶段进度归一化为 0..1 的比例。
## 参数：无。
## 返回值：归一化进度；阶段长度不可用时返回 0.0（等价于「阶段刚开始」）。
func _resolve_phase_ratio() -> float:
	var phase_length: int = _resolve_phase_length()
	if phase_length <= 0:
		return 0.0
	var progress: int = int(_time_system.call("get_PhaseProgress"))
	return clampf(float(progress) / float(phase_length), 0.0, 1.0)


## 解析 TimeSystem 的阶段长度常量。
## PhaseLength 是脚本常量，Object.get() 拿不到常量，只能通过常量表读取；
## 这样可以避免在滤镜里复制一份阶段长度，防止两边数值漂移。
## 参数：无。
## 返回值：正数阶段长度；所有读取方式都失败时返回 DEFAULT_PHASE_LENGTH。
func _resolve_phase_length() -> int:
	var script: GDScript = _time_system.get_script() as GDScript
	if script != null:
		var constants: Dictionary = script.get_script_constant_map()
		if constants.has("PhaseLength"):
			var raw_length: int = int(constants["PhaseLength"])
			if raw_length > 0:
				return raw_length
	return DEFAULT_PHASE_LENGTH


## 确保滤镜铺满整个视口。
## 为什么需要自愈：Control 的 anchors 以父级 CanvasItem 的 anchorable rect 为参考，
## 而 Node2D 的 anchorable rect 是空矩形 —— 当滤镜被挂在 Node2D（例如战斗场景的根节点）下时，
## 全屏 anchors 会算出 0×0 的尺寸，滤镜静默失效且不产生任何报错。
## 因此检测到退化尺寸时改用「左上角锚点 + 显式视口尺寸」，不再依赖父级矩形。
## 参数：无。返回值：无。
func _fit_to_viewport() -> void:
	if size.x > 0.0 and size.y > 0.0:
		return
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = get_viewport_rect().size
	position = Vector2.ZERO
