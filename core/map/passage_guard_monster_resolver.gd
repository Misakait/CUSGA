extends RefCounted

## 当前房间驻守通道的怪物解析器。
##
## 解析器只负责规范化无向边、缓存 encounter 结果和读取 Monsters 字段；
## 驻守概率、状态清理与战斗请求仍由 PassageGuardController 负责。

var _resolved_by_edge: Dictionary = {}


## 开始解析新房间时清除旧房间的边缓存。
func BeginRoom() -> void:
	_resolved_by_edge.clear()


## 从旧 C# 或新 GDScript encounter 资源池中选择一组怪物。
## 参数 from：通道一端的地图坐标。
## 参数 to：通道另一端的地图坐标。
## 参数 encounter_pool：包含 Monsters 字段的 Resource 数组。
## 返回值：按原顺序过滤后的 MonsterData/Resource 数组。
func Resolve(from: Vector2i, to: Vector2i, encounter_pool: Array) -> Array:
	return ResolveResources(from, to, encounter_pool)


## 读取通用 Resource encounter 池，并按无向边缓存结果。
## 参数 from：通道一端的地图坐标。
## 参数 to：通道另一端的地图坐标。
## 参数 encounter_pool：由 C# 或 GDScript Resource 组成的 encounter 数组。
## 返回值：同一房间同一通道复用的怪物数组；无有效配置时为空数组。
func ResolveResources(from: Vector2i, to: Vector2i, encounter_pool: Array) -> Array:
	var edge_key := _edge_key(from, to)
	if _resolved_by_edge.has(edge_key):
		return _resolved_by_edge[edge_key]

	var resolved: Array = _pick_encounter(encounter_pool)
	_resolved_by_edge[edge_key] = resolved
	return resolved


## 从 encounter 池读取随机条目并过滤无效怪物对象。
func _pick_encounter(encounter_pool: Array) -> Array:
	if encounter_pool.is_empty():
		return []

	var valid_encounters: Array[Resource] = []
	for value in encounter_pool:
		if value is Resource:
			valid_encounters.append(value)
	if valid_encounters.is_empty():
		return []

	var encounter: Resource = valid_encounters[randi() % valid_encounters.size()]
	var raw_monsters: Variant = encounter.get("Monsters")
	if not (raw_monsters is Array):
		return []

	var monsters: Array = []
	for value in raw_monsters:
		if value is Resource:
			monsters.append(value)
	return monsters


## 生成与 C# PassageGuardEdge 相同的端点顺序稳定键。
func _edge_key(first: Vector2i, second: Vector2i) -> String:
	var a := first
	var b := second
	if _compare(a, b) > 0:
		var temporary := a
		a = b
		b = temporary
	return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]


## 按 X 再按 Y 比较两个坐标，保持旧值对象的规范化规则。
func _compare(left: Vector2i, right: Vector2i) -> int:
	if left.x != right.x:
		return left.x - right.x
	return left.y - right.y
