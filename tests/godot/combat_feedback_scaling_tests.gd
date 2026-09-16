extends SceneTree

# 正式 Profile 脚本用于验证绝对数值曲线与 Inspector 上限。
const COMBAT_FEEDBACK_PROFILE_SCRIPT := preload("res://scripts/battle_scripts/combat_feedback_profile.gd")
# 正式反馈导演脚本用于验证多段配方不再依赖段号缩放或延迟。
const COMBAT_FEEDBACK_DIRECTOR_SCRIPT := preload("res://scripts/battle_scripts/combat_feedback_director.gd")
# 正式全局冲击控制器用于验证每个入队请求都被 FIFO 完整消费。
const COMBAT_SCREEN_IMPULSE_SCRIPT := preload("res://scripts/battle_scripts/combat_screen_impulse.gd")

# 累积断言失败信息，使曲线、配方和队列回归能在同一次运行中完整报告。
var _failures: Array[String] = []

# 已开始全局冲击的 Hit Stop 时长集合，用于验证减弱模式不会写入时间缩放。
var _started_hit_stop_seconds: Array[float] = []

# 已开始全局冲击的震屏幅度集合，用于验证高频批次最多保留配置次数的实际震屏。
var _started_shake_pixels: Array[float] = []

# 已完整结束的全局冲击数量，用于验证同帧多段请求没有被覆盖或合并。
var _finished_impulse_count: int = 0


## 延迟到场景树稳定后运行聚焦回归用例。
## @return void 无返回值。
func _init() -> void:
	call_deferred(&"_run")


## 按顺序执行数值曲线、多段配方与全局 FIFO 验证。
## @return void 无返回值。
func _run() -> void:
	_test_absolute_value_curve_is_monotonic_and_capped()
	_test_multi_hit_feedback_caps_impact_and_accelerates_popups()
	await _test_impulse_queue_plays_hit_stop_once_per_batch_and_reduced_mode()
	_finish()


## 验证低、中、高绝对数值会单调增强，并且结果语义加成仍受 Profile 上限钳制。
## @return void 无返回值。
func _test_absolute_value_curve_is_monotonic_and_capped() -> void:
	# 正式 Profile 实例用于直接验证资源拥有的纯数值映射。
	var profile: CombatFeedbackProfile = COMBAT_FEEDBACK_PROFILE_SCRIPT.new()
	# 低伤害样本代表最小可读命中。
	var low_intensity: float = profile.resolve_feedback_intensity(1.0)
	# 中伤害样本接近默认参考值，必须明显强于低伤害。
	var medium_intensity: float = profile.resolve_feedback_intensity(profile.response_reference_amount)
	# 超高伤害样本验证指数曲线饱和后不会越过一。
	var high_intensity: float = profile.resolve_feedback_intensity(999999.0)
	_assert(low_intensity < medium_intensity, "绝对数值曲线应让中伤害强于低伤害。")
	_assert(medium_intensity < high_intensity, "绝对数值曲线应让高伤害继续强于中伤害。")
	_assert(high_intensity <= 1.0, "绝对数值曲线必须钳制在 0 到 1 之间。")

	# 低伤害配方用于对比数值驱动的受力与震屏最小值。
	var low_recipe: Dictionary = _build_impact_recipe(profile, 1)
	# 中伤害配方用于对比数值驱动的受力与震屏中间值。
	var medium_recipe: Dictionary = _build_impact_recipe(profile, int(profile.response_reference_amount))
	# 超高伤害配方用于验证各种动画幅度不会超过配置硬上限。
	var high_recipe: Dictionary = _build_impact_recipe(profile, 999999)
	_assert(float(low_recipe["popup_scale"]) < float(medium_recipe["popup_scale"]), "浮字缩放应随伤害数值单调增强。")
	_assert(float(low_recipe["popup_rise"]) < float(medium_recipe["popup_rise"]), "浮字上浮距离应随伤害数值单调增强。")
	_assert(float(low_recipe["popup_duration"]) < float(medium_recipe["popup_duration"]), "浮字时长应随伤害数值单调增强。")
	_assert(float(low_recipe["offset"]) < float(medium_recipe["offset"]), "受力位移应随伤害数值单调增强。")
	_assert(float(low_recipe["impact_duration"]) < float(medium_recipe["impact_duration"]), "受力时长应随伤害数值单调增强。")
	_assert(float(medium_recipe["screen_shake_pixels"]) < float(high_recipe["screen_shake_pixels"]), "震屏幅度应随伤害数值单调增强。")
	_assert(float(low_recipe["screen_shake_duration"]) < float(medium_recipe["screen_shake_duration"]), "震屏时长应随伤害数值单调增强。")
	_assert(float(low_recipe["hit_stop_seconds"]) < float(medium_recipe["hit_stop_seconds"]), "Hit Stop 时长应随伤害数值单调增强。")
	_assert(float(high_recipe["popup_scale"]) <= profile.popup_scale_cap, "超高伤害普通浮字不得超过 Profile 安全上限。")
	_assert(float(high_recipe["offset"]) <= profile.impact_offset_cap, "超高伤害受力不得超过 Profile 硬上限。")
	_assert(float(high_recipe["screen_shake_pixels"]) <= profile.screen_shake_pixels_cap, "超高伤害震屏不得超过 Profile 硬上限。")
	_assert(float(high_recipe["hit_stop_seconds"]) <= profile.hit_stop_seconds_cap, "超高伤害 Hit Stop 不得超过 Profile 硬上限。")

	# 暴击与击杀叠加后的超高伤害受力用于验证语义加成同样不会绕过硬上限。
	var emphasized_offset: float = profile.resolve_impact_offset(high_intensity, true, true, true)
	_assert(emphasized_offset <= profile.impact_offset_cap, "暴击、击杀和破盾叠加后受力仍必须受硬上限约束。")
	# 正式导演用于验证暴击与击杀叠加后的浮字缩放同样经过最终硬上限。
	var director: CombatFeedbackDirector = COMBAT_FEEDBACK_DIRECTOR_SCRIPT.new()
	director.profile = profile
	# 极高致命暴击覆盖结果语义在数值曲线后的最终缩放钳制。
	var emphasized_display: Dictionary = director.call("_build_damage_display", 999999, false, true, true, 0)
	_assert(float(emphasized_display["scale"]) <= profile.popup_scale_cap, "暴击与击杀叠加后浮字仍必须受硬上限约束。")
	director.queue_free()


## 验证多段伤害限制目标受击动画次数，并按总段数加速且顺序显示浮字，段号仅影响空间位置。
## @return void 无返回值。
func _test_multi_hit_feedback_caps_impact_and_accelerates_popups() -> void:
	# 正式 Profile 提供多段位置分布参数与数值曲线。
	var profile: CombatFeedbackProfile = COMBAT_FEEDBACK_PROFILE_SCRIPT.new()
	# 正式导演提供浮字配方与段号布局函数，避免测试复制运行时规则。
	var director: CombatFeedbackDirector = COMBAT_FEEDBACK_DIRECTOR_SCRIPT.new()
	director.profile = profile
	# 单段配方作为多段加速前的基准。
	var single_display: Dictionary = director.call("_build_damage_display", 12, false, false, false, 0, 1)
	# 同数值首段配方代表三段伤害中的第一条真实结算结果。
	var first_display: Dictionary = director.call("_build_damage_display", 12, false, false, false, 0, 3)
	# 同数值中段配方必须沿用同一总段数，因此具有相同的加速时长。
	var middle_display: Dictionary = director.call("_build_damage_display", 12, false, false, false, 0, 3)
	# 同数值末段配方不能因索引不同而再次缩放或改变时长。
	var last_display: Dictionary = director.call("_build_damage_display", 12, false, false, false, 0, 3)
	_assert(first_display["scale"] == middle_display["scale"] and middle_display["scale"] == last_display["scale"], "相同数值的多段浮字不得因段号缩小。")
	_assert(float(first_display["duration"]) < float(single_display["duration"]), "多段浮字必须按总段数加速离场。")
	_assert(first_display["duration"] == middle_display["duration"] and middle_display["duration"] == last_display["duration"], "同一多段序列的浮字时长不得因段号而不一致。")
	# 第一段立即显示，后续段以加速后时长为间隔顺序出现，避免同一锚点数字重叠。
	var first_popup_delay: float = profile.resolve_multi_hit_popup_delay(float(first_display["duration"]), 0, 3)
	var middle_popup_delay: float = profile.resolve_multi_hit_popup_delay(float(middle_display["duration"]), 1, 3)
	var last_popup_delay: float = profile.resolve_multi_hit_popup_delay(float(last_display["duration"]), 2, 3)
	_assert(is_zero_approx(first_popup_delay), "多段首个浮字必须立即入场。")
	_assert(is_equal_approx(middle_popup_delay, float(middle_display["duration"])), "第二段浮字必须在第一段加速后时长结束时入场。")
	_assert(is_equal_approx(last_popup_delay, float(last_display["duration"]) * 2.0), "末段浮字必须按段号顺序延后，不能与前段同时漂浮。")
	_assert(profile.should_play_multi_hit_impact(0) and profile.should_play_multi_hit_impact(1) and profile.should_play_multi_hit_impact(2), "默认配置必须保留多段伤害的前三次受击动画。")
	_assert(not profile.should_play_multi_hit_impact(3), "默认配置下第四段及后续命中不得继续播放目标受击动画。")

	# 首段位置只用于验证位置布局仍可保留数字可读性。
	var first_offset: Vector2 = director.call("_resolve_hit_popup_offset", 0, 3)
	# 中段位置只用于验证空间分布不会退化为完全重叠。
	var middle_offset: Vector2 = director.call("_resolve_hit_popup_offset", 1, 3)
	_assert(first_offset != middle_offset, "多段浮字只能以空间偏移区分，不能以缩放或时序节流区分。")

	director.queue_free()


## 验证全局冲击 FIFO 在高频批次只保留前三次震屏与一次 Hit Stop；减弱模式仍将停顿置零。
## @return void 无返回值。
func _test_impulse_queue_plays_hit_stop_once_per_batch_and_reduced_mode() -> void:
	# 独立战斗根节点提供正式冲击控制器所需的位置恢复目标。
	var battle_root: Node2D = Node2D.new()
	battle_root.name = "CombatFeedbackScalingHarness"
	root.add_child(battle_root)
	# 正式冲击控制器实例用于测试 FIFO，而不是复刻其请求队列实现。
	var impulse: CombatScreenImpulse = COMBAT_SCREEN_IMPULSE_SCRIPT.new()
	impulse.battle_root_path = NodePath("..")
	battle_root.add_child(impulse)
	impulse.impulse_started.connect(_on_impulse_started)
	impulse.impulse_finished.connect(_on_impulse_finished)
	await process_frame

	# 开始记录前清空历史信号，避免未来增加的测试顺序影响本用例断言。
	_started_hit_stop_seconds.clear()
	_started_shake_pixels.clear()
	_finished_impulse_count = 0
	impulse.enqueue_impulse(2.0, 0.01, 0.015, 0.05)
	impulse.enqueue_impulse(6.0, 0.01, 0.015, 0.05)
	impulse.enqueue_impulse(12.0, 0.01, 0.015, 0.05)
	impulse.enqueue_impulse(18.0, 0.01, 0.015, 0.05)
	await create_timer(0.20, true, false, true).timeout
	_assert(_started_hit_stop_seconds.size() == 4, "高频冲击请求必须安全完成 FIFO 消费，即使超出实际震屏上限。")
	_assert(_finished_impulse_count == 4, "高频批次中的节流请求也必须完整结束，不能阻塞后续战斗反馈。")
	if _started_hit_stop_seconds.size() == 4 and _started_shake_pixels.size() == 4:
		_assert(_started_shake_pixels[0] > 0.0 and _started_shake_pixels[1] > 0.0 and _started_shake_pixels[2] > 0.0, "高频批次必须保留前三次震屏。")
		_assert(is_zero_approx(_started_shake_pixels[3]), "高频批次第四次及后续请求不得继续震屏。")
		_assert(_started_hit_stop_seconds[0] > 0.0, "连续命中的首条请求必须保留 Hit Stop。")
		_assert(is_zero_approx(_started_hit_stop_seconds[1]) and is_zero_approx(_started_hit_stop_seconds[2]) and is_zero_approx(_started_hit_stop_seconds[3]), "范围或高频连续命中的后续请求不得叠加 Hit Stop。")

	# 正式 Profile 用于生成减弱模式仍应使用的同一份数值冲击配方。
	var profile: CombatFeedbackProfile = COMBAT_FEEDBACK_PROFILE_SCRIPT.new()
	# 正式导演通过动态私有入口请求减弱模式冲击，验证偏好只禁用 Hit Stop。
	var director: CombatFeedbackDirector = COMBAT_FEEDBACK_DIRECTOR_SCRIPT.new()
	director.profile = profile
	director.set("_feedback_intensity", "reduced")
	director.set("_screen_impulse", impulse)
	# 高数值冲击配方确保减弱模式测试覆盖原本会触发明显 Hit Stop 的路径。
	var reduced_recipe: Dictionary = _build_impact_recipe(profile, 1000)
	_started_hit_stop_seconds.clear()
	_started_shake_pixels.clear()
	director.call("_request_value_scaled_impulse", reduced_recipe)
	await create_timer(0.20).timeout
	_assert(_started_hit_stop_seconds.size() == 1, "减弱模式仍必须保留每一条震屏请求。")
	if _started_hit_stop_seconds.size() == 1:
		_assert(is_zero_approx(_started_hit_stop_seconds[0]), "减弱模式的每条冲击请求都必须禁用 Hit Stop。")

	director.queue_free()
	battle_root.queue_free()
	await process_frame


## 以正式 Profile 生成与导演一致的局部和全局冲击配方，供纯曲线断言复用。
## @param profile 当前测试使用的战斗反馈配置。
## @param amount 本次碰撞使用的绝对数值。
## @return Dictionary 已钳制的冲击配方。
func _build_impact_recipe(profile: CombatFeedbackProfile, amount: int) -> Dictionary:
	# 数值曲线强度是局部受力、震屏与 Hit Stop 的共同输入。
	var intensity: float = profile.resolve_feedback_intensity(float(amount))
	return {
		"popup_scale": profile.resolve_popup_scale(intensity),
		"popup_rise": profile.resolve_popup_rise_distance(intensity),
		"popup_duration": profile.resolve_popup_duration(intensity),
		"offset": profile.resolve_impact_offset(intensity, false, false, false),
		"impact_duration": profile.resolve_impact_duration(intensity),
		"screen_shake_pixels": profile.resolve_screen_shake_pixels(intensity, false, false, false),
		"screen_shake_duration": profile.resolve_screen_shake_duration(intensity),
		"hit_stop_seconds": profile.resolve_hit_stop_seconds(intensity, false, false, false)
	}


## 记录每条 FIFO 请求实际开始时的震屏幅度与 Hit Stop 时长。
## @param shake_pixels 当前请求的震屏幅度。
## @param hit_stop_seconds 当前请求的 Hit Stop 时长。
## @return void 无返回值。
func _on_impulse_started(shake_pixels: float, hit_stop_seconds: float) -> void:
	_started_shake_pixels.append(shake_pixels)
	_started_hit_stop_seconds.append(hit_stop_seconds)


## 记录每条 FIFO 请求完整结束的次数。
## @return void 无返回值。
func _on_impulse_finished() -> void:
	_finished_impulse_count += 1


## 记录失败断言，保证全部检查完成后再以退出码通知测试运行器。
## @param condition 断言条件。
## @param message 断言失败时输出的说明。
## @return void 无返回值。
func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## 根据累计断言结果结束测试进程。
## @return void 无返回值。
func _finish() -> void:
	if _failures.is_empty():
		print("All combat feedback scaling Godot tests passed.")
		quit(0)
		return

	for failure: String in _failures:
		push_error(failure)
	quit(1)
