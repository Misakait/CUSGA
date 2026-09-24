extends RefCounted

## 建筑规则服务；只操作传入的库存、仓库和时间系统，不读取场景树或输入。

## 同步交互锁，防止生命/时间信号回调在同一结算中重入。
var _interacting: bool = false
## 同步建造锁，防止库存信号在一次放置中重入。
var _placing: bool = false
## 同步拆除锁，防止仓库变更信号重入并重复发放掉落。
var _destroying: bool = false


## 检查落点；data 为建筑，point 为局部坐标，bounds 为可建区域。
## occupied 为建筑记录，blockers 为地形占用矩形；返回失败原因，空串表示合法。
func GetPlacementFailure(
	data: Resource, point: Vector2, bounds: Rect2, occupied: Array, blockers: Array
) -> String:
	if data == null or not data.has_method("IsBuildingCard") or not data.call("IsBuildingCard"):
		return "这张牌不能建造"
	if not point.is_finite():
		return "落点无效"
	# 以完整占地矩形校验边缘，避免中心合法但建筑越过房间边界。
	var footprint: Vector2 = data.get("Footprint")
	# 以落点为中心的完整矩形，防止只检查中心点而允许边缘越界。
	var area: Rect2 = Rect2(point - footprint / 2.0, footprint)
	if not bounds.encloses(area):
		return "请放在当前房间的地面内"
	for record: Dictionary in occupied:
		# 建筑尺寸来自配置，不把表现节点作为状态来源。
		var other_size: Vector2 = record["data"].get("Footprint")
		if area.intersects(Rect2(record["position"] - other_size / 2.0, other_size)):
			return "这里已有建筑"
	for blocker: Rect2 in blockers:
		if area.intersects(blocker):
			return "这里有地形或障碍物"
	return ""


## 放置建筑；data、room、point 指定建筑与落点，其他参数提供库存、仓库及地面约束。
## 返回 success/message/record；失败不扣牌，成功只扣一张。
func TryPlace(
	data: Resource, room: Vector2i, point: Vector2, bounds: Rect2,
	inventory: Node, store: Node, blockers: Array = []
) -> Dictionary:
	if _placing or _destroying or not is_instance_valid(inventory) or not is_instance_valid(store):
		return {"success": false, "message": "暂时无法建造"}
	# 确认瞬间重新读取仓库和库存，取消预览及失效请求不会消耗任何物品。
	var reason: String = GetPlacementFailure(data, point, bounds, store.call("GetBuildings", room), blockers)
	if not reason.is_empty():
		return {"success": false, "message": reason}
	_placing = true
	if not bool(inventory.call("TryRemoveItem", data, 1)):
		_placing = false
		return {"success": false, "message": "背包里已没有这张建筑牌"}
	# 仓库登记是同步且无失败分支的操作，扣牌与登记之间没有 await。
	var record: Dictionary = store.call("AddBuilding", room, data, point)
	_placing = false
	return {"success": true, "message": "已放置 %s" % data.get("CardName"), "record": record}


## 使用建筑；record 为仓库记录，context 为玩家组件，time_system 为时间节点。
## 返回策略执行结果；成功才按策略 ActionPointCost 推进时间一次。
func TryInteract(record: Dictionary, context: Dictionary, time_system: Node) -> Dictionary:
	if _interacting or _destroying or not is_instance_valid(time_system) or not time_system.has_method("PassTime"):
		return {"success": false, "message": "暂时无法交互"}
	# 不根据 CardId 分支；新增建筑只需接入新的策略资源。
	var data: Resource = record.get("data") as Resource
	# 当前建筑配置的策略资源，不通过建筑标识硬编码效果。
	var interaction: Resource = data.get("Interaction") as Resource if data != null else null
	if interaction == null or not interaction.has_method("execute") \
		or not interaction.has_method("get_unavailable_reason"):
		return {"success": false, "message": "建筑交互配置无效"}
	# 先固定成本，避免效果同步触发的信号改变本次结算数值。
	var cost: int = int(interaction.get("ActionPointCost"))
	if cost < 0:
		return {"success": false, "message": "行动值配置无效"}
	# 当前建筑独享的可变状态；不写回共享 Resource。
	var state: Dictionary = record.get("state", {})
	# 本次预检的失败原因；空字符串表示可以继续。
	var reason: String = interaction.call("get_unavailable_reason", context, state)
	if not reason.is_empty():
		return {"success": false, "message": reason}
	_interacting = true
	# 实际执行结果，成功标志决定后续扣费与反馈。
	var result: Dictionary = interaction.call("execute", context, state)
	if bool(result.get("success", false)):
		time_system.call("PassTime", cost)
	_interacting = false
	return result


## 拆除实例；room、instance_id 定位建筑，store 为本局仓库。
## 返回 success/message/drops/position；仅首次移除成功产生掉落，不消耗行动值。
func TryDemolish(room: Vector2i, instance_id: int, store: Node) -> Dictionary:
	if _destroying or _interacting or _placing or not is_instance_valid(store):
		return {"success": false, "message": "暂时无法拆除"}
	# 完成时按实例标识重查，不信任开始长按时保留的旧记录。
	var record: Dictionary = {}
	for candidate: Dictionary in store.call("GetBuildings", room):
		if int(candidate["id"]) == instance_id:
			record = candidate
			break
	if record.is_empty():
		return {"success": false, "message": "建筑已不存在"}
	# 掉落和时长来自资源配置，不按篝火标识分支。
	var data: Resource = record["data"]
	if not data.has_method("CanDemolish") or not bool(data.call("CanDemolish")):
		return {"success": false, "message": "这座建筑不能拆除"}
	_destroying = true
	# 拆除固定使用零产量加成，避免采集天赋改变配置的回收数量。
	var loot: Resource = data.get("DestructionLoot") as Resource
	# 空数组支持没有材料回收的建筑，成功移除前不交给表现层。
	var drops: Array = []
	if loot != null:
		drops = loot.call("RollLoot", 0)
	# 先从权威仓库移除，再允许调用方在原位置生成掉落。
	var removed: bool = bool(store.call("RemoveBuilding", room, instance_id))
	_destroying = false
	if not removed:
		return {"success": false, "message": "建筑已不存在"}
	return {"success": true, "message": "已拆除 %s" % data.get("CardName"),
		"drops": drops, "position": record["position"]}
