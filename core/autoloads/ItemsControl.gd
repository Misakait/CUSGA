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

## 存档层 Autoload 路径。
##
## 用 `NodePath` + `get_node_or_null` 而不是直接写 `SaveManager.xxx`：`test_run` 环境没有
## autoload，直接引用标识符会让本脚本连同测试一起解析失败。
const SAVE_MANAGER_PATH: NodePath = ^"/root/SaveManager"

## 槽位编解码工具。
const SAVE_SLOT_CODEC: GDScript = preload("res://core/save/save_slot_codec.gd")

## 本参与者的存档键；发布后不可修改（改了等于玩家准备好的带入栏清零）。
const SAVE_KEY: String = "carry"

## 本参与者的作用域字面量，与 `SaveManager.SCOPE_GLOBAL` 同值（由契约套件断言）。
const SAVE_SCOPE: String = "global"

## 带入栏内容变化信号。
##
## 三个权威入口（SetCarryEntry / ClearCarryEntry / TakeCarryItems）在真正改变内容时发出它。
## 存档层订阅它做自动存档，界面也可以用它刷新，避免各自去轮询 carry_items。
signal carry_items_changed

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

## 节点就绪时建立 CardId 到原始物品 Resource 的索引，把带入栏复位为全空，再注册进存档层。
##
## 注册必须是最后一步：注册会**同步**应用存档，而应用要靠 `items` 反查 CardId，
## 索引还没建好时所有栏位都会被跳过，玩家的带入栏会静默变空。
func _ready() -> void:
	items = load_all_items_from_items_folder()
	_reset_carry_items()
	_register_with_save_manager()


## 向存档层注册自身。
## 返回值：无。
func _register_with_save_manager() -> void:
	var save_manager: Node = get_node_or_null(SAVE_MANAGER_PATH)
	if save_manager == null or not save_manager.has_method("register_participant"):
		push_error("ItemsControl: 未找到 SaveManager，带入栏将不会跨运行保存。")
		return

	save_manager.call("register_participant", self)

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
	carry_items_changed.emit()
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
	carry_items_changed.emit()
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
	# 只在真的有东西被取走时才广播：本来就空时清空不算变化，也不必惊动存档层。
	if not taken.is_empty():
		carry_items_changed.emit()
	return taken


# ── 存档参与者协议 ─────────────────────────────────────────────────────────
# 带入栏为什么属于局外存档：它是玩家**进入一局之前**做的准备，与「这一局打到哪儿」无关，
# 因此跨运行保留。开局带入会经由 TakeCarryItems 清空带入栏，这次清空同样会被采集，
# 于是「已经带进去了」也跨运行生效，同一批物品不会在下一局被重复带入。

## 返回稳定的存档键。
## 返回值："carry"。
func save_key() -> String:
	return SAVE_KEY

## 返回本参与者的作用域。
## 返回值："global"。
func save_scope() -> String:
	return SAVE_SCOPE

## 返回需要触发自动存档的信号名。
## 返回值：信号名数组。
func save_change_signals() -> Array:
	return ["carry_items_changed"]

## 采集当前带入栏。
##
## 只落 CardId 与数量。带入栏条目的结构里本来就没有洗炼属性（见 `carry_items` 的说明），
## 因此显式补一个空 `rolled`，让编码器走与仓库完全相同的路径，而不是另开一套格式。
##
## 返回值：{"slots": Array}，长度等于 CARRY_SLOT_CAPACITY，空栏位为 null。
func capture_save_data() -> Dictionary:
	_ensure_carry_capacity()
	var entries: Array = []
	for index: int in carry_items.size():
		var entry: Dictionary = carry_items[index]
		entries.append({
			"item": entry.get("item"),
			"amount": int(entry.get("count", 0)),
			"rolled": {},
		})
	return {"slots": SAVE_SLOT_CODEC.call("encode_slots", entries)}

## 用存档内容覆盖带入栏。
##
## 语义是**先整体复位再写入**：带入栏是一份「准备清单」，叠加会让玩家已经移走的物品
## 重新冒出来。结构损坏时按「没有存档」处理（空带入栏）并告警——带入栏不是资产本体，
## 让整次读档失败会连带毁掉仓库与金币的恢复。
##
## 参数 data：本参与者的存档载荷；空字典表示「没有存档」。
## 返回值：是否成功应用。
func apply_save_data(data: Dictionary) -> bool:
	_ensure_carry_capacity()
	var decode_result: Dictionary = SAVE_SLOT_CODEC.call(
		"decode_slots", data.get("slots", []), CARRY_SLOT_CAPACITY, Callable(self, "get_item")
	)

	if not bool(decode_result.get("ok")):
		push_warning(
			"ItemsControl: 带入栏存档结构不可用（%s），本次以空带入栏启动。"
			% str(decode_result.get("reasons", []))
		)
		_reset_carry_items()
		carry_items_changed.emit()
		return true

	var entries: Array = decode_result.get("entries", []) as Array
	var ok_status: String = String(SAVE_SLOT_CODEC.get_script_constant_map()["STATUS_OK"])
	_reset_carry_items()
	for index: int in mini(entries.size(), CARRY_SLOT_CAPACITY):
		var entry: Dictionary = entries[index]
		if String(entry.get("status", "")) != ok_status:
			continue
		carry_items[index] = {"item": entry.get("item"), "count": int(entry.get("amount"))}

	var skipped: int = int(decode_result.get("skipped", 0))
	if skipped > 0:
		push_warning(
			"ItemsControl: 带入栏存档中有 %d 个栏位无法水合，已跳过：%s"
			% [skipped, str(decode_result.get("reasons", []))]
		)
	# 这次广播发生在存档分发期间，存档层会丢弃由此产生的落盘请求，不会造成回声写入。
	carry_items_changed.emit()
	return true
