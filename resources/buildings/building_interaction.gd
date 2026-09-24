extends Resource

## 建筑交互策略接口；只处理单次效果，输入、距离和时间结算由系统统一负责。
## context 提供 health、inventory、player、gameplay_port；state 是每栋建筑独立的可变字典。
## 扩展必须同步执行，失败不得改变玩家或建筑状态，禁止自行扣除行动值。

## 成功使用一次所消耗的行动值；沿用 TimeSystem.PassTime 的局外时间语义。
@export_range(0, 10000) var ActionPointCost: int = 0
## 提示中的动作名称；制作台可配置为“制作”，床铺可配置为“休息”。
@export var ActionLabel: String = "使用"


## 返回提示文案；无参数，返回动作名称与本次行动值消耗。
func get_prompt() -> String:
	return "%s（消耗 %d 行动值）" % [ActionLabel, ActionPointCost]


## 预检交互；context 为玩家上下文，state 为实例状态，空字符串表示可用。
func get_unavailable_reason(_context: Dictionary, _state: Dictionary) -> String:
	return "该建筑尚未配置交互效果"


## 同步执行效果；context 为玩家上下文，state 为实例状态。
## 返回包含 success: bool 和 message: String 的字典；仅成功结果会结算时间。
func execute(_context: Dictionary, _state: Dictionary) -> Dictionary:
	return {"success": false, "message": "该建筑尚未配置交互效果"}
