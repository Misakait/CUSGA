## 战斗反馈参数资源。
## 所有“果汁感”数值集中在这里，使完整与减弱模式能复用同一条表现逻辑。
class_name CombatFeedbackProfile
extends Resource

## 曲线参考值的绝对下限，避免 Inspector 意外设为零后发生除零。
const MINIMUM_CURVE_REFERENCE_AMOUNT: float = 0.001

## 是否允许导演层创建战斗反馈；关闭时结算与行动队列保持完全可用。
@export var enabled: bool = true

@export_group("数值强度曲线")
## 数值反馈曲线的参考伤害；等于该值时曲线已进入明显但未饱和的中强区间。
@export_range(1.0, 99999.0, 1.0) var response_reference_amount: float = 20.0
## 最小正数值对应的基础反馈强度，保证 1 点伤害仍保留可读的命中感。
@export_range(0.0, 1.0, 0.01) var minimum_feedback_intensity: float = 0.18

@export_group("浮字表现")
## 正数伤害、护盾或治疗浮字在曲线最小强度下使用的缩放倍率。
@export_range(0.10, 3.00, 0.01) var popup_scale_min: float = 1.00
## 正数伤害、护盾或治疗浮字接近曲线饱和时使用的缩放倍率。
@export_range(0.10, 3.00, 0.01) var popup_scale_max: float = 1.34
## 暴击在数值曲线缩放后的额外倍率，用颜色之外的大小强化关键结果。
@export_range(1.00, 2.00, 0.01) var critical_popup_scale_multiplier: float = 1.18
## 击杀在数值曲线缩放后的额外倍率，配合下划线突出终结一击。
@export_range(1.00, 2.00, 0.01) var lethal_popup_scale_multiplier: float = 1.12
## 所有结果语义加成后的浮字缩放硬上限，防止超高数值或叠加结果遮挡战场。
@export_range(0.10, 4.00, 0.01) var popup_scale_cap: float = 1.80
## 曲线最小强度下浮字的上升距离，保持小数值的阅读空间。
@export_range(0.0, 128.0, 1.0) var popup_rise_min: float = 34.0
## 曲线饱和时浮字的上升距离，增强高数值的爆发感。
@export_range(0.0, 128.0, 1.0) var popup_rise_max: float = 56.0
## 曲线最小强度下浮字的总播放时长。
@export_range(0.05, 1.00, 0.01) var popup_duration_min: float = 0.24
## 曲线饱和时浮字的总播放时长，保证高数值有足够停留时间。
@export_range(0.05, 1.00, 0.01) var popup_duration_max: float = 0.42
## 多段浮字按段数加速后的最小时长倍率；限制下限可避免高段数数字快到无法辨认。
@export_range(0.10, 1.00, 0.01) var multi_hit_popup_duration_scale_min: float = 0.35
## 同一锚点的多段浮字环绕分布半径；只改变位置，绝不改变段间强度或时序。
@export_range(0.0, 96.0, 1.0) var multi_hit_popup_spread_distance: float = 18.0
## 多段浮字环绕布局的纵向压缩比例，避免数字过多时遮挡怪物卡名。
@export_range(0.0, 1.0, 0.01) var multi_hit_popup_vertical_spread_ratio: float = 0.45

@export_group("结果颜色")
## 普通命中数字使用的高对比暖色。
@export var normal_damage_color: Color = Color(1.0, 0.36, 0.28, 1.0)
## 暴击数字使用的深红色，使其不依赖额外标签也能与普通伤害区分。
@export var critical_damage_color: Color = Color(0.62, 0.05, 0.08, 1.0)
## 护盾吸收提示使用的中性灰色，避免破盾状态额外抢占伤害数字。
@export var guard_color: Color = Color(0.68, 0.70, 0.74, 1.0)
## 闪避提示使用纯白色，保持结果文字在复杂背景中的可读性。
@export var evade_color: Color = Color.WHITE
## 生命实际恢复时使用的绿色数字。
@export var heal_color: Color = Color(0.28, 0.94, 0.40, 1.0)

@export_group("目标受力")
## 曲线最小强度下目标横向受力位移。
@export_range(0.0, 64.0, 1.0) var impact_offset_min: float = 6.0
## 曲线饱和时目标横向受力位移。
@export_range(0.0, 64.0, 1.0) var impact_offset_max: float = 22.0
## 暴击对数值曲线受力位移施加的额外倍率。
@export_range(1.00, 2.00, 0.01) var critical_impact_offset_multiplier: float = 1.10
## 击杀对数值曲线受力位移施加的额外倍率。
@export_range(1.00, 2.00, 0.01) var lethal_impact_offset_multiplier: float = 1.16
## 护盾破裂对数值曲线受力位移施加的额外倍率。
@export_range(1.00, 2.00, 0.01) var shield_break_impact_offset_multiplier: float = 1.08
## 所有结果语义加成后的目标受力硬上限。
@export_range(0.0, 96.0, 1.0) var impact_offset_cap: float = 28.0
## 曲线最小强度下目标受力与颜色闪白的总时长。
@export_range(0.02, 0.60, 0.01) var impact_duration_min: float = 0.10
## 曲线饱和时目标受力与颜色闪白的总时长。
@export_range(0.02, 0.60, 0.01) var impact_duration_max: float = 0.20
## 同一高频冲击批次最多保留的局部受击动画与全局震屏次数；后续段仍保留浮字。
@export_range(1, 10, 1) var multi_hit_feedback_max_count: int = 3

@export_group("屏幕冲击")
## 曲线最小强度下完整模式的震屏位移。
@export_range(0.0, 48.0, 1.0) var screen_shake_pixels_min: float = 2.0
## 曲线饱和时完整模式的震屏位移。
@export_range(0.0, 48.0, 1.0) var screen_shake_pixels_max: float = 14.0
## 暴击在数值曲线震屏幅度上的额外像素加成。
@export_range(0.0, 24.0, 1.0) var critical_screen_shake_pixels_bonus: float = 2.0
## 击杀在数值曲线震屏幅度上的额外像素加成。
@export_range(0.0, 24.0, 1.0) var lethal_screen_shake_pixels_bonus: float = 3.0
## 护盾破裂在数值曲线震屏幅度上的额外像素加成。
@export_range(0.0, 24.0, 1.0) var shield_break_screen_shake_pixels_bonus: float = 1.0
## 所有结果语义加成后的完整模式震屏硬上限。
@export_range(0.0, 64.0, 1.0) var screen_shake_pixels_cap: float = 18.0
## 曲线最小强度下的震屏总时长。
@export_range(0.02, 0.60, 0.01) var screen_shake_duration_min: float = 0.06
## 曲线饱和时的震屏总时长。
@export_range(0.02, 0.60, 0.01) var screen_shake_duration_max: float = 0.14
## 减弱模式下相对完整模式保留的震屏比例；数值曲线保持相同，只缩放最终幅度。
@export_range(0.0, 1.0, 0.05) var reduced_screen_shake_ratio: float = 0.40

@export_group("Hit Stop")
## 曲线最小强度下完整模式 Hit Stop 时长；每个有效命中都会计算该值，实际触发由屏幕冲击控制器按连续批次限制。
@export_range(0.0, 0.15, 0.001) var hit_stop_seconds_min: float = 0.012
## 曲线饱和时完整模式 Hit Stop 时长。
@export_range(0.0, 0.15, 0.001) var hit_stop_seconds_max: float = 0.055
## 暴击在数值曲线 Hit Stop 时长上的额外秒数加成。
@export_range(0.0, 0.10, 0.001) var critical_hit_stop_seconds_bonus: float = 0.008
## 击杀在数值曲线 Hit Stop 时长上的额外秒数加成。
@export_range(0.0, 0.10, 0.001) var lethal_hit_stop_seconds_bonus: float = 0.012
## 护盾破裂在数值曲线 Hit Stop 时长上的额外秒数加成。
@export_range(0.0, 0.10, 0.001) var shield_break_hit_stop_seconds_bonus: float = 0.006
## 所有结果语义加成后的 Hit Stop 时长硬上限。
@export_range(0.0, 0.20, 0.001) var hit_stop_seconds_cap: float = 0.075
## Hit Stop 期间的时间缩放；接近零能产生停顿但不会让恢复计时器失效。
@export_range(0.01, 1.0, 0.01) var hit_stop_time_scale: float = 0.05

@export_group("敌方攻击表现")
## 怪物发起攻击时向玩家方向下冲的像素距离；只影响表现位置，不改变碰撞或目标规则。
@export_range(0.0, 96.0, 1.0) var monster_attack_lunge_distance: float = 30.0
## 怪物下冲并归位的总时长；应短于行动结算尾部等待，避免阻塞回合。
@export_range(0.05, 0.60, 0.01) var monster_attack_lunge_duration: float = 0.22

## 将绝对显示数值映射为连续、单调且饱和的反馈强度。
## @param amount 本次显示或碰撞使用的绝对数值。
## @return float 位于 0 到 1 之间的钳制反馈强度。
func resolve_feedback_intensity(amount: float) -> float:
	# 正数值是曲线唯一输入，零或负数仅保留最小安全强度。
	var safe_amount: float = maxf(amount, 0.0)
	# 参考值必须大于零，避免 Inspector 配置错误破坏运行时表现。
	var safe_reference_amount: float = maxf(response_reference_amount, MINIMUM_CURVE_REFERENCE_AMOUNT)
	# 指数饱和曲线使高数值逐步接近上限，而不会无限放大视觉幅度。
	var normalized_intensity: float = 1.0 - exp(-safe_amount / safe_reference_amount)
	# 最小强度保证微小数值仍可读，最终钳制防止浮点误差越出合法范围。
	return clampf(lerpf(minimum_feedback_intensity, 1.0, normalized_intensity), 0.0, 1.0)

## 将曲线强度插值为普通浮字缩放。
## @param intensity 已钳制的数值反馈强度。
## @return float 普通浮字缩放倍率。
func resolve_popup_scale(intensity: float) -> float:
	# 规范化强度避免外部调用者传入越界值影响 Inspector 上限。
	var safe_intensity: float = clampf(intensity, 0.0, 1.0)
	# 公共映射在基础缩放阶段就执行总上限，确保伤害、护盾和治疗数字都不会绕过安全钳制。
	var popup_scale: float = lerpf(popup_scale_min, popup_scale_max, safe_intensity)
	return minf(popup_scale, popup_scale_cap)

## 将曲线强度插值为浮字上升距离。
## @param intensity 已钳制的数值反馈强度。
## @return float 浮字上升距离。
func resolve_popup_rise_distance(intensity: float) -> float:
	# 规范化强度避免外部调用者传入越界值影响 Inspector 上限。
	var safe_intensity: float = clampf(intensity, 0.0, 1.0)
	return lerpf(popup_rise_min, popup_rise_max, safe_intensity)

## 将曲线强度插值为浮字总时长。
## @param intensity 已钳制的数值反馈强度。
## @return float 浮字总时长。
func resolve_popup_duration(intensity: float) -> float:
	# 规范化强度避免外部调用者传入越界值影响 Inspector 上限。
	var safe_intensity: float = clampf(intensity, 0.0, 1.0)
	return lerpf(popup_duration_min, popup_duration_max, safe_intensity)

## 按多段总数缩短浮字时长，使高频数字更快离场而不丢失每段结算。
## @param base_duration 当前数值曲线计算出的单段浮字时长。
## @param hit_count 当前多段伤害的总段数。
## @return float 应用于本段浮字的加速后时长。
func resolve_multi_hit_popup_duration(base_duration: float, hit_count: int) -> float:
	# 非法或缺失的段数按单段处理，避免开方与除法使用零值。
	var safe_hit_count: int = maxi(hit_count, 1)
	# 根号衰减让段数增加时持续加速，同时避免线性缩短导致常见三段伤害过快消失。
	var dynamic_duration_scale: float = 1.0 / sqrt(float(safe_hit_count))
	# Inspector 值即使被运行时脚本改写，也必须保持可读性所需的合法范围。
	var minimum_duration_scale: float = clampf(multi_hit_popup_duration_scale_min, 0.01, 1.0)
	return maxf(base_duration, 0.0) * maxf(dynamic_duration_scale, minimum_duration_scale)

## 计算同一目标多段浮字的顺序入场延迟，确保下一段在前一段离场后再显示。
## @param popup_duration 已按总段数加速后的单段浮字时长。
## @param hit_index 当前伤害在多段序列中的零基索引。
## @param hit_count 当前多段伤害的总段数。
## @return float 当前浮字开始显示前的延迟时长。
func resolve_multi_hit_popup_delay(popup_duration: float, hit_index: int, hit_count: int) -> float:
	# 总段数与索引均做安全钳制，避免异常跨语言数据制造过长等待。
	var safe_hit_count: int = maxi(hit_count, 1)
	# 超出范围的段号按末段处理，负数按首段处理。
	var safe_hit_index: int = clampi(hit_index, 0, safe_hit_count - 1)
	# 每段间隔等于自身的加速后时长，保证同一目标的数字不会同时漂浮。
	return maxf(popup_duration, 0.0) * float(safe_hit_index)

## 将曲线强度和结果语义插值为目标受力位移。
## @param intensity 已钳制的数值反馈强度。
## @param is_critical 是否为暴击结果。
## @param is_lethal 是否为击杀结果。
## @param shield_broken 是否为护盾破裂结果。
## @return float 受力位移，始终不超过配置硬上限。
func resolve_impact_offset(intensity: float, is_critical: bool, is_lethal: bool, shield_broken: bool) -> float:
	# 规范化强度保证基础位移始终落在导出最小值与最大值之间。
	var safe_intensity: float = clampf(intensity, 0.0, 1.0)
	# 基础位移完全由当前数值曲线决定，不再依赖固定高额伤害阈值。
	var offset: float = lerpf(impact_offset_min, impact_offset_max, safe_intensity)
	if is_critical:
		offset *= critical_impact_offset_multiplier
	if is_lethal:
		offset *= lethal_impact_offset_multiplier
	if shield_broken:
		offset *= shield_break_impact_offset_multiplier
	return minf(offset, impact_offset_cap)

## 将曲线强度插值为目标受力总时长。
## @param intensity 已钳制的数值反馈强度。
## @return float 目标受力总时长。
func resolve_impact_duration(intensity: float) -> float:
	# 规范化强度避免外部调用者传入越界值影响 Inspector 上限。
	var safe_intensity: float = clampf(intensity, 0.0, 1.0)
	return lerpf(impact_duration_min, impact_duration_max, safe_intensity)

## 判断某段多段伤害是否仍可播放目标受击动画。
## @param hit_index 当前伤害在多段序列中的零基索引。
## @return bool 是否处于配置允许的受击动画次数内。
func should_play_multi_hit_impact(hit_index: int) -> bool:
	# 最大次数最少为一，防止运行时错误配置令任何有效命中都失去基础受击反馈。
	var safe_maximum_count: int = maxi(multi_hit_feedback_max_count, 1)
	return hit_index >= 0 and hit_index < safe_maximum_count

## 将曲线强度和结果语义插值为完整模式震屏幅度。
## @param intensity 已钳制的数值反馈强度。
## @param is_critical 是否为暴击结果。
## @param is_lethal 是否为击杀结果。
## @param shield_broken 是否为护盾破裂结果。
## @return float 震屏幅度，始终不超过配置硬上限。
func resolve_screen_shake_pixels(intensity: float, is_critical: bool, is_lethal: bool, shield_broken: bool) -> float:
	# 规范化强度保证基础震屏始终落在导出最小值与最大值之间。
	var safe_intensity: float = clampf(intensity, 0.0, 1.0)
	# 基础震屏完全由当前数值曲线决定，不再以结果优先级跳过普通命中。
	var shake_pixels: float = lerpf(screen_shake_pixels_min, screen_shake_pixels_max, safe_intensity)
	if is_critical:
		shake_pixels += critical_screen_shake_pixels_bonus
	if is_lethal:
		shake_pixels += lethal_screen_shake_pixels_bonus
	if shield_broken:
		shake_pixels += shield_break_screen_shake_pixels_bonus
	return minf(shake_pixels, screen_shake_pixels_cap)

## 将曲线强度插值为震屏总时长。
## @param intensity 已钳制的数值反馈强度。
## @return float 震屏总时长。
func resolve_screen_shake_duration(intensity: float) -> float:
	# 规范化强度避免外部调用者传入越界值影响 Inspector 上限。
	var safe_intensity: float = clampf(intensity, 0.0, 1.0)
	return lerpf(screen_shake_duration_min, screen_shake_duration_max, safe_intensity)

## 将曲线强度和结果语义插值为完整模式 Hit Stop 时长。
## @param intensity 已钳制的数值反馈强度。
## @param is_critical 是否为暴击结果。
## @param is_lethal 是否为击杀结果。
## @param shield_broken 是否为护盾破裂结果。
## @return float Hit Stop 时长，始终不超过配置硬上限。
func resolve_hit_stop_seconds(intensity: float, is_critical: bool, is_lethal: bool, shield_broken: bool) -> float:
	# 规范化强度保证基础停顿始终落在导出最小值与最大值之间。
	var safe_intensity: float = clampf(intensity, 0.0, 1.0)
	# 基础停顿完全由当前数值曲线决定，不再以高额伤害阈值筛掉任一命中。
	var hit_stop_seconds: float = lerpf(hit_stop_seconds_min, hit_stop_seconds_max, safe_intensity)
	if is_critical:
		hit_stop_seconds += critical_hit_stop_seconds_bonus
	if is_lethal:
		hit_stop_seconds += lethal_hit_stop_seconds_bonus
	if shield_broken:
		hit_stop_seconds += shield_break_hit_stop_seconds_bonus
	return minf(hit_stop_seconds, hit_stop_seconds_cap)
