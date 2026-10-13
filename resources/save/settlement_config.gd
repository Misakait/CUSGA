class_name SettlementConfig
extends Resource

## 轮回配置与纯奖励计算入口；不修改资产、节点或磁盘。
## 持久化开关在进程启动时由 SaveManager 固定，修改后需要重新运行。
@export var persistence_enabled: bool = false
## 开启时每局死亡赠送一个真实物品；通关和主动结束不赠送。
@export var enable_death_test_reward: bool = true
## 死亡测试使用的实际物品资源，数量固定为一个。
@export var death_test_item: Resource = preload("res://items/items/wheat.tres")
## 正式轮回资格列表；默认空，因此普通背包物品不自动带出。
@export var allowed_resources: Array[Resource] = []


## 统一计算一局奖励，后续规则可以在派生配置脚本中覆写此方法。
## 参数 harvest 为已经选择或授予的真实 ItemStack 数组，_statistics 为本局统计副本，
## _reason 为 death/win/abandon；返回 {harvest: 独立堆叠副本数组, tokens: 非负代币增量}。
## 当前没有确定换算规则，因此原样保留真实物品，代币增量固定为 0。
func calculate_rewards(harvest: Array, _statistics: Dictionary, _reason: String) -> Dictionary:
	var copies: Array = []
	for stack: RefCounted in harvest:
		copies.append(stack.call("Duplicate"))
	return {"harvest": copies, "tokens": 0}
