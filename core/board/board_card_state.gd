extends RefCounted

## 棋盘卡临时状态的 GDScript 实现。
## 该对象只保存初始化阶段的地形或掉落引用；卡牌集合、去重和视图生命周期仍由 BoardController 负责。

## 当前状态类型："terrain" 或 "loot"。
var _kind: String = ""
## 地形卡运行时实例，只有 terrain 状态使用。
var _terrain_instance: RefCounted = null
## 掉落卡物品堆叠，只有 loot 状态使用。
var _loot_stack: RefCounted = null


## 初始化地形卡状态，并保留 TerrainInstance 与 TerrainData 原始身份。
## @param terrain_instance 地形运行时实例，必须带有 TerrainData。
## @return 参数有效并完成初始化时返回 true。
func InitializeTerrain(terrain_instance: RefCounted) -> bool:
	if terrain_instance == null:
		return false
	var terrain_data: Variant = terrain_instance.get("TerrainData")
	if terrain_data == null or typeof(terrain_data) == TYPE_NIL:
		return false
	_kind = "terrain"
	_terrain_instance = terrain_instance
	_loot_stack = null
	return true


## 初始化掉落卡状态，并验证跨语言 ItemStack 的稳定字段协议。
## @param loot_stack 具有 Item、Amount、IsEmpty 属性和 SetItem 方法的堆叠对象。
## @return 堆叠有效并完成初始化时返回 true。
func InitializeLoot(loot_stack: RefCounted) -> bool:
	if loot_stack == null:
		return false
	if not loot_stack.has_method("SetItem"):
		return false
	var item: Variant = loot_stack.get("Item")
	var amount: int = int(loot_stack.get("Amount"))
	var is_empty: bool = bool(loot_stack.get("IsEmpty"))
	if item == null or amount <= 0 or is_empty:
		return false
	_kind = "loot"
	_loot_stack = loot_stack
	_terrain_instance = null
	return true


## 判断当前状态是否为掉落卡。
## @return 当前状态为 loot 时返回 true。
func IsLoot() -> bool:
	return _kind == "loot"


## 判断当前状态是否为地形卡。
## @return 当前状态为 terrain 时返回 true。
func IsTerrain() -> bool:
	return _kind == "terrain"


## 返回当前卡牌显示使用的原始 Resource。
## @return 掉落物品 Resource、地形 TerrainData 或 null。
func GetCardData() -> Resource:
	if IsLoot() and _loot_stack != null:
		return _loot_stack.get("Item") as Resource
	if IsTerrain() and _terrain_instance != null:
		return _terrain_instance.get("TerrainData") as Resource
	return null


## 返回掉落堆叠原始引用。
## @return 当前掉落堆叠；地形状态返回 null。
func GetLootStackOrNull() -> RefCounted:
	return _loot_stack if IsLoot() else null


## 返回地形运行时实例原始引用。
## @return 当前地形实例；掉落状态返回 null。
func GetTerrainInstanceOrNull() -> RefCounted:
	return _terrain_instance if IsTerrain() else null


## 返回掉落数量。
## @return 有效掉落数量；其他状态返回 0。
func GetStackAmount() -> int:
	return int(_loot_stack.get("Amount")) if IsLoot() and _loot_stack != null else 0


## 判断是否应该显示掉落数量标签。
## @return 数量大于 1 时返回 true。
func CanShowAmount() -> bool:
	return IsLoot() and GetStackAmount() > 1
