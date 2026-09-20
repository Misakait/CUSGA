extends RefCounted
## 局外交互的行动值与真实等待时长换算规则。
class_name WorldInteractionTiming

## 每个真实秒对应的游戏行动值，用于统一长按等待时长。
const GAME_TIME_POINTS_PER_HOLD_SECOND: float = 10.0


## 将行动值转换为非负的真实等待秒数。
##
## 参数 action_point_cost：本次交互消耗的行动值，零或负数不产生等待。
## 返回值：按每 10 点行动值折算出的真实秒数。
static func get_hold_duration_seconds(action_point_cost: int) -> float:
	# 错误配置不能产生反向或负时长 Tween，因此先把输入归一化到零以上。
	return float(maxi(action_point_cost, 0)) / GAME_TIME_POINTS_PER_HOLD_SECOND
