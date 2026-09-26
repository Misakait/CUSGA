extends RefCounted
## 局外交互的行动值与真实等待时长换算规则。
class_name WorldInteractionTiming

## 每个真实秒对应的游戏行动值，用于统一长按等待时长。
const GAME_TIME_POINTS_PER_HOLD_SECOND: float = 10.0

## 长按速度倍率的下界。
##
## 倍率在换算里是除数，取 0 会得到无穷时长，因此写入入口必须把它夹到一个正数。
## 0.1 的含义是「等待时长最多放慢到 10 倍」，够用又不会让长按变得不可完成。
const MIN_HOLD_SPEED_MULTIPLIER: float = 0.1

## 长按速度倍率的当前生效值。
##
## 用 static var 而不是 Autoload 或导出字段：倍率就是「行动值 ↔ 等待时长」这条换算
## 公式上的一个系数，与上面的常量同源，放在一起才读得出完整公式；同时面板与运行期
## 都能直接读写它，不必为它引入第二个节点依赖和配套的缓存挂回恢复逻辑。
##
## 它是进程内共享状态，测试之间会残留，因此触碰倍率的测试必须在结束时复位为 1.0。
static var _hold_speed_multiplier: float = 1.0


## 设置长按速度倍率。
##
## 参数 value：新倍率，大于 1 表示更快（等待时长按比例缩短），1 为原始速度。
## 返回值：无；非正值会被夹紧到下界，NaN 会被忽略并保留原值。
static func set_hold_speed_multiplier(value: float) -> void:
	# NaN 参与的比较恒为假，会一路污染到 Tween 时长，因此在入口拦掉并保留原值。
	if is_nan(value):
		return

	# 非正值在这个换算里是除数，会产生无穷或负时长，统一夹紧到下界。
	_hold_speed_multiplier = maxf(value, MIN_HOLD_SPEED_MULTIPLIER)


## 读取当前长按速度倍率。
## 返回值：当前生效的倍率，恒不小于 MIN_HOLD_SPEED_MULTIPLIER。
static func get_hold_speed_multiplier() -> float:
	return _hold_speed_multiplier


## 按当前倍率缩放一段基础等待时长。
##
## 倍率只作用在等待表现上，不改变任何行动值扣费：调试时可以让长按变快，而天数推进
## 与资源平衡仍按原始耗时结算。
##
## 参数 base_seconds：未经缩放的基础秒数。
## 返回值：缩放后的秒数；输入非正数时返回 0.0，保留零消耗交互的即时回调路径。
static func scale_hold_seconds(base_seconds: float) -> float:
	if base_seconds <= 0.0:
		return 0.0

	return base_seconds / _hold_speed_multiplier


## 将行动值转换为非负的真实等待秒数。
##
## 刻意不在这里施加长按速度倍率：本函数是纯换算契约，倍率由长按控制器在计时前统一施加，
## 这样既能覆盖所有长按入口，也避免同一次等待被缩放两次。
##
## 参数 action_point_cost：本次交互消耗的行动值，零或负数不产生等待。
## 返回值：按每 10 点行动值折算出的真实秒数。
static func get_hold_duration_seconds(action_point_cost: int) -> float:
	# 错误配置不能产生反向或负时长 Tween，因此先把输入归一化到零以上。
	return float(maxi(action_point_cost, 0)) / GAME_TIME_POINTS_PER_HOLD_SECOND
