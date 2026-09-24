extends "res://resources/buildings/building_interaction.gd"

## 回复生命的建筑策略；篝火、床铺等可共用脚本并分别配置数值。

## 单次回复生命值，实际回复由生命组件按上限钳制，运行时可调整。
@export_range(1, 100000) var HealAmount: int = 200


## 返回休息提示；无参数，返回行动消耗及最大恢复量。
func get_prompt() -> String:
	return "%s · %d 行动值 / 恢复 %d 生命" % [ActionLabel, ActionPointCost, HealAmount]


## 检查生命状态；context 提供 health 组件，state 为建筑状态。
## 返回不可用原因，空字符串表示可以使用。
func get_unavailable_reason(context: Dictionary, _state: Dictionary) -> String:
	# 不直接设置生命值，沿用组件的上限、信号和死亡规则。
	var health: Node = context.get("health") as Node
	if not is_instance_valid(health) or not health.has_method("Add"):
		return "无法读取角色生命值"
	if int(health.get("CurrentValue")) <= 0:
		return "角色已死亡"
	if HealAmount <= 0:
		return "建筑回复量配置无效"
	return ""


## 执行一次休息；context 提供 health，state 保留给后续燃料或次数限制。
## 返回 success、message 和实际恢复量 healed，失败时不改变生命值。
func execute(context: Dictionary, state: Dictionary) -> Dictionary:
	# 完成时重新预检，避免提示出现后角色状态已发生变化。
	var reason: String = get_unavailable_reason(context, state)
	if not reason.is_empty():
		return {"success": false, "message": reason}
	# Add 会同步通知 HUD；系统只在此操作成功后推进时间。
	var healed: int = int(context["health"].call("Add", HealAmount))
	# 休息本身就是成功交互，满血时回复为零也照常消耗行动值。
	return {"success": true, "message": "休息完成，恢复了 %d 点生命值" % healed, "healed": healed}
