#这是一个全局脚本

extends Node

## 物品数据的跨语言字段协议；普通物品已由 GDScript 提供，装备与技能卡仍可来自 C#。
const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

## 带入栏的权威栏位数量（硬上限）。
##
## 数值来源：带入栏基础 5 格（PlayerProgression.CarryBaseValue）、每级 +1
## （CarryValuePerLevel）、上限 5 级（CarryMaxLevel），因此硬上限恒为 5 + 1 × 5 = 10。
## 仓库界面 `scripts/warehouse/warehouse_control.gd` 的 CARRY_MAX_POSITIONS 是同值镜像
## （界面必须按这个数量铺格子），两者由契约测试断言相等——只改一处会被测试拦下。
const CARRY_SLOT_CAPACITY: int = 10

#存放cardid对应的item -- {cardID：itemdata}
var items: Dictionary = {}

#局外仓库的东西带入游戏
#
#这里是「待带入物品」的**权威来源**：索引即带入栏位序号（0..CARRY_SLOT_CAPACITY-1），
#元素形如 {"item": Resource, "count": int}，空栏位为 {"item": null, "count": 0}。
#
#为什么必须放在 Autoload 而不是仓库场景里：仓库场景实例会被 SceneManager 长期缓存复用，
#内容若留在场景实例上，Main 侧就无法在「开局带入」之后把它清空——玩家退回主菜单、
#再次进入仓库时会重新看到已经带进游戏的物品，同一批物品会被重复带入。
#这与 warehouse_control.gd 自己记录的教训（界面副本一旦忘了写回就会丢改动）是同一类问题，
#因此沿用同一解法：权威放 Autoload，界面只做视图。
var carry_items: Array = []

#游戏的东西带入局外仓库
#
#注意：下面两个数组是「局内 → 局外回写」链路的预留字段，**当前没有任何生产者**
#（唯一的消费点是 warehouse_control.gd 的 _absorb_items_brought_back）。
#「开局带入即消耗」不依赖它们：把局内物品带回仓库属于另一条独立需求，本次不动。
var player_to_warehouse: Array[Resource] = []
var player_to_warehouse_cnt: Array[int] = []

## 节点就绪时建立 CardId 到原始物品 Resource 的索引，并把带入栏复位为全空。
func _ready() -> void:
	items = load_all_items_from_items_folder()
	_reset_carry_items()

## 递归加载生产物品目录。
## 返回值：以稳定 CardId 为键、原始 Resource 为值的字典。
func load_all_items_from_items_folder() -> Dictionary:
	var loaded_items: Dictionary = {}
	load_items_recursively("res://items", loaded_items)
	return loaded_items

## 把目录中的 ItemData 兼容资源加入给定索引。
## 参数 dir_path：需要扫描的 res:// 目录。
## 参数 target_items：接收 CardId → Resource 映射的字典。
func load_items_recursively(dir_path: String, target_items: Dictionary) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			var full_path: String = dir_path + "/" + file_name

			# 跳过当前目录和上级目录的标记
			if file_name != "." and file_name != "..":
				# 如果是目录，递归进入
				if dir.current_is_dir():
					load_items_recursively(full_path, target_items)
				# 如果是 .tres 文件，加载它
				elif file_name.ends_with(".tres"):
					var item: Resource = load(full_path) as Resource
					if bool(ITEM_DATA_COMPAT.call("is_item_resource", item)):
						var card_id: StringName = ITEM_DATA_COMPAT.call("get_card_id", item, &"")
						if not card_id.is_empty():
							target_items[card_id] = item

			file_name = dir.get_next()
		dir.list_dir_end()

## 按稳定 CardId 返回原始物品 Resource。
## 参数 id：物品的 CardId。
## 返回值：找到时返回 GDScript 或 C# 物品 Resource，否则返回 null。
func get_item(id: StringName) -> Resource:
	return items.get(id, null) as Resource


# ── 带入栏权威接口 ─────────────────────────────────────────────────────────
# 以下方法构成带入栏的唯一权威入口：读取用 GetCarryEntry，写入用 SetCarryEntry /
# ClearCarryEntry，跨局带走用 TakeCarryItems。仓库界面与开局初始化都只经这些入口，
# 不允许任何调用方自己维护一份带入栏副本。

## 生成一个空带入栏条目。
## 返回值：{"item": null, "count": 0}，语义为「可用但为空的栏位」。
func _empty_carry_entry() -> Dictionary:
	return {"item": null, "count": 0}

## 把带入栏复位为全空条目。
## 返回值：无。
func _reset_carry_items() -> void:
	carry_items.clear()
	for _i: int in CARRY_SLOT_CAPACITY:
		carry_items.append(_empty_carry_entry())

## 保证权威数组长度恒等于 CARRY_SLOT_CAPACITY。
##
## 存在的理由：_ready() 只在节点进入场景树时执行一次，而契约测试与部分调用方会直接
## `脚本.new()` 构造实例（此时 _ready 尚未运行）。把长度校验下沉到每个入口，
## 可以让任何调用顺序都得到稳定长度的数组，而不是让越界读写出错。
## 返回值：无。
func _ensure_carry_capacity() -> void:
	if carry_items.size() != CARRY_SLOT_CAPACITY:
		_reset_carry_items()

## 读取指定带入栏位的条目。
## 参数 index：栏位序号，取值范围 0..CARRY_SLOT_CAPACITY-1。
## 返回值：条目副本；越界时返回空条目（不报错，让界面按「空栏位」自然降级）。
func GetCarryEntry(index: int) -> Dictionary:
	_ensure_carry_capacity()
	if index < 0 or index >= carry_items.size():
		return _empty_carry_entry()

	var entry: Dictionary = carry_items[index]
	# 返回副本：调用方拿到的是快照，就地修改不会污染权威。
	return entry.duplicate()

## 写入指定带入栏位。
## 参数 index：栏位序号，取值范围 0..CARRY_SLOT_CAPACITY-1。
## 参数 item：要带入的物品 Resource；传 null 等价于清空该栏位。
## 参数 count：堆叠数量；非正数等价于清空该栏位。
## 返回值：写入成功（或按空值语义清空成功）时为 true；栏位越界时为 false。
func SetCarryEntry(index: int, item: Resource, count: int) -> bool:
	_ensure_carry_capacity()
	if index < 0 or index >= CARRY_SLOT_CAPACITY:
		push_error("ItemsControl: 带入栏位序号 %d 越界（上限 %d）。" % [index, CARRY_SLOT_CAPACITY])
		return false

	if item == null or count <= 0:
		return ClearCarryEntry(index)

	carry_items[index] = {"item": item, "count": count}
	return true

## 清空指定带入栏位。
## 参数 index：栏位序号，取值范围 0..CARRY_SLOT_CAPACITY-1。
## 返回值：清空成功时为 true；栏位越界时为 false。
func ClearCarryEntry(index: int) -> bool:
	_ensure_carry_capacity()
	if index < 0 or index >= CARRY_SLOT_CAPACITY:
		push_error("ItemsControl: 带入栏位序号 %d 越界（上限 %d）。" % [index, CARRY_SLOT_CAPACITY])
		return false

	carry_items[index] = _empty_carry_entry()
	return true

## 判断带入栏是否还有待带入物品。
## 返回值：存在 item 非空且数量为正的栏位时为 true。
func HasCarryItems() -> bool:
	_ensure_carry_capacity()
	for index: int in carry_items.size():
		var entry: Dictionary = carry_items[index]
		if entry.get("item") != null and int(entry.get("count", 0)) > 0:
			return true

	return false

## 取出全部待带入物品，并把带入栏清空。
##
## 这是「带入即消耗」的**唯一消费出口**：开局初始化调用它一次，物品随返回值进入局内背包，
## 带入栏从此为空，同一批物品不会在下一局被重复带入。
## 返回值：[{"item": Resource, "count": int}, ...]，只含实际占用的栏位，顺序即栏位顺序。
func TakeCarryItems() -> Array:
	_ensure_carry_capacity()
	var taken: Array = []
	for index: int in carry_items.size():
		var entry: Dictionary = carry_items[index]
		var item: Resource = entry.get("item") as Resource
		var count: int = int(entry.get("count", 0))
		if item == null or count <= 0:
			continue
		taken.append({"item": item, "count": count})

	# 取出即消耗：无论调用方是否成功装入背包，权威都必须清空，
	# 否则「放不下」会退化成「下一局还能再拿一次」。
	_reset_carry_items()
	return taken
