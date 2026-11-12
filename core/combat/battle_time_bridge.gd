extends RefCounted

## 战斗行动值 → 局外时间点的换算桥。
##
## 职责单一：把 ATB 每次结算消耗的行动值按倍率折算成整数时间点，并保留不足 1 点的
## 小数余量。时间权威仍由 `TimeSystem` 持有，本类不读取或修改时间状态。
##
## 为什么需要余量：小倍率下单次行动值可能只折算 0.x 点，若每回合直接四舍五入，
## 长时间战斗会永远凑不出 1 点，表现为「战斗完全不推进时间」。

## 尚未折算成整数时间点的余量，始终落在 `[0, 1)`。
var _pending_time_points: float = 0.0


## 累积一次战斗行动值，并返回本次应转交的整数局外时间点。
##
## 参数 action_value：本次 ATB 结算实际消耗的战斗行动值；非正数忽略。
## 参数 multiplier：每 1 点战斗行动值折算的局外时间点倍率；0 或负数关闭联动。
## 返回值：本次可以交给 `TimeSystem.PassTime` 的整数点数；不足 1 点返回 0。
func Accumulate(action_value: float, multiplier: float) -> int:
	if action_value <= 0.0 or multiplier <= 0.0:
		return 0

	_pending_time_points += action_value * multiplier
	# 浮点累加可能把 0.4 × 3 算成 1.199999… 或 0.999999…；用极小容差避免少转交 1 点。
	var whole_points: int = int(floorf(_pending_time_points + 0.000001))
	if whole_points <= 0:
		return 0

	_pending_time_points -= float(whole_points)
	if _pending_time_points < 0.0:
		_pending_time_points = 0.0
	return whole_points


## 清空当前余量，通常只用于测试或重新开始一轮战斗。
##
## 返回值：无。
func Reset() -> void:
	_pending_time_points = 0.0


## 读取尚未折算成整数点的余量。
##
## 返回值：当前余量，范围 `[0, 1)`。
func GetPendingPoints() -> float:
	return _pending_time_points
