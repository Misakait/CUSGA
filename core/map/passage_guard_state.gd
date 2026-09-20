extends RefCounted

## 保存当前夜晚已经被怪物驻守的地图通道。
##
## 该脚本不声明 class_name，避免迁移期间与 C# PassageGuardState 全局类重名；
## 运行时入口由 passage_guard_controller.gd 通过 preload 显式绑定。

## 规范化后的无向通道键集合。
var _guarded_edges: Dictionary = {}

## 当前被驻守的通道数量。
var Count: int:
	get:
		return _guarded_edges.size()


## 标记一条通道被驻守。
##
## 参数 from：通道的一端。
## 参数 to：通道的另一端。
func AddGuard(from: Vector2i, to: Vector2i) -> void:
	_guarded_edges[_edge_key(from, to)] = true


## 查询一条通道当前是否被驻守。
##
## 参数 from：通道的一端。
## 参数 to：通道的另一端。
## 返回值：任意方向查询到同一条被驻守通道时返回 true。
func IsGuarded(from: Vector2i, to: Vector2i) -> bool:
	return _guarded_edges.has(_edge_key(from, to))


## 清除一条已经被击败的驻守通道。
##
## 参数 from：通道的一端。
## 参数 to：通道的另一端。
func ClearGuard(from: Vector2i, to: Vector2i) -> void:
	_guarded_edges.erase(_edge_key(from, to))


## 清空当前夜晚所有驻守通道。
func ClearAll() -> void:
	_guarded_edges.clear()


## 生成端点顺序稳定的无向边键，保持 C# PassageGuardEdge 的字典序规则。
func _edge_key(first: Vector2i, second: Vector2i) -> String:
	var a := first
	var b := second
	if _compare_points(a, b) > 0:
		var swap := a
		a = b
		b = swap
	return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]


## 按 X 再按 Y 比较两个端点，返回负数、零或正数。
func _compare_points(left: Vector2i, right: Vector2i) -> int:
	if left.x != right.x:
		return left.x - right.x
	return left.y - right.y
