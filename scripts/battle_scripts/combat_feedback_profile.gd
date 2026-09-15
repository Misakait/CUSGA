## 战斗反馈参数资源。
## 所有“果汁感”数值集中在这里，使完整与减弱模式能复用同一条表现逻辑。
class_name CombatFeedbackProfile
extends Resource

## 是否允许导演层创建战斗反馈；关闭时结算与行动队列保持完全可用。
@export var enabled: bool = true

## 普通命中数字向上移动的像素距离。
@export_range(16.0, 96.0, 1.0) var popup_rise_distance: float = 44.0

## 普通命中数字的显示时长。
@export_range(0.10, 1.00, 0.01) var popup_duration: float = 0.36

## 多段伤害浮字相对普通浮字的时长倍率；缩短时长可加快上浮速度并保证每段独立可见。
@export_range(0.20, 1.00, 0.05) var multi_hit_popup_duration_multiplier: float = 0.55

## 多段伤害相邻浮字的延迟间隔；逐段错开避免同步结算时多个数字完全重叠。
@export_range(0.00, 0.20, 0.005) var multi_hit_popup_stagger_seconds: float = 0.045

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

## 普通命中对目标施加的最大横向受力位移。
@export_range(0.0, 32.0, 1.0) var normal_impact_offset: float = 8.0

## 暴击或击杀对目标施加的最大横向受力位移。
@export_range(0.0, 48.0, 1.0) var heavy_impact_offset: float = 15.0

## 普通目标闪白/冲击颜色的保持时间。
@export_range(0.02, 0.30, 0.01) var impact_duration: float = 0.14

## 怪物发起攻击时向玩家方向下冲的像素距离；只影响表现位置，不改变碰撞或目标规则。
@export_range(0.0, 96.0, 1.0) var monster_attack_lunge_distance: float = 30.0

## 怪物下冲并归位的总时长；应短于行动结算尾部等待，避免阻塞回合。
@export_range(0.05, 0.60, 0.01) var monster_attack_lunge_duration: float = 0.22

## 完整模式下高优先级结果的最大根节点震屏位移。
@export_range(0.0, 32.0, 1.0) var full_screen_shake_pixels: float = 12.0

## 减弱模式下相对完整模式保留的震屏比例。
@export_range(0.0, 1.0, 0.05) var reduced_screen_shake_ratio: float = 0.40

## Hit Stop 之间的最小间隔，避免范围技能多目标重复减速。
@export_range(20, 500, 5) var hit_stop_cooldown_msec: int = 120

## 实际扣血达到该值时视为高额命中，会使用重受力和短 Hit Stop；不会改变伤害数值。
@export_range(1, 9999, 1) var high_damage_hit_stop_threshold: int = 30

## 暴击触发的完整模式 Hit Stop 时长。
@export_range(0.0, 0.15, 0.005) var critical_hit_stop_seconds: float = 0.045

## 高额实际伤害触发的完整模式 Hit Stop 时长。
@export_range(0.0, 0.15, 0.005) var high_damage_hit_stop_seconds: float = 0.040

## 护盾破裂触发的完整模式 Hit Stop 时长。
@export_range(0.0, 0.15, 0.005) var shield_break_hit_stop_seconds: float = 0.040

## 击杀触发的完整模式 Hit Stop 时长。
@export_range(0.0, 0.15, 0.005) var lethal_hit_stop_seconds: float = 0.065

## Hit Stop 期间的时间缩放；接近零能产生停顿但不会让恢复计时器失效。
@export_range(0.01, 1.0, 0.01) var hit_stop_time_scale: float = 0.05
