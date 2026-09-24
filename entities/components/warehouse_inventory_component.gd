extends "res://entities/components/inventory_component.gd"

## 全局仓库库存的并行 GDScript 来源标识，同时是「局外存档」的参与者（key = warehouse）。
##
## 为什么仓库属于局外存档：仓库是玩家在主菜单 / 仓库界面里摆好的经营成果，与「这一局打到
## 哪里」无关。它和带入栏同属一类——都是「下次打开游戏还应该在」的东西。
##
## 为什么参与者就在组件自己身上：仓库槽位的唯一权威是 `InventoryComponent._slots`，
## 让组件自己采集 / 恢复可以避免任何外部代码去碰 `_slots`（那会绕开堆叠身份与信号规则）。

## 存档层 Autoload 路径。
##
## 用 `NodePath` + `get_node_or_null` 而不是直接写 `SaveManager.xxx`：`test_run` 环境没有
## autoload，直接引用标识符会让本脚本连同测试一起解析失败（项目里所有 autoload 访问都
## 遵循这条约定）。
const SAVE_MANAGER_PATH: NodePath = ^"/root/SaveManager"

## 物品目录 Autoload 路径；水合槽位时按 CardId 反查原始 Resource。
const ITEMS_CONTROL_PATH: NodePath = ^"/root/ItemsControl"

## 槽位编解码工具。
const SAVE_SLOT_CODEC: GDScript = preload("res://core/save/save_slot_codec.gd")

## 本参与者的存档键；发布后不可修改（改了等于玩家仓库清零）。
const SAVE_KEY: String = "warehouse"

## 本参与者的作用域字面量。
##
## 刻意写死字面量而不是引用 `SaveManager.SCOPE_GLOBAL`：见 `SAVE_MANAGER_PATH` 的说明。
## 两者同值由契约套件断言。
const SAVE_SCOPE: String = "global"

## 水合槽位用的 `card_id -> Resource` 查表函数覆盖点。
##
## 默认为空，此时按 `/root/ItemsControl.get_item` 解析（生产路径）。测试与任何没有 autoload
## 的环境可以注入自己的查表函数——否则所有槽位都会因为「查不到物品」被跳过，水合行为就
## 无法被断言。
var SaveItemLookup: Callable = Callable()

## 仓库拖拽来源标识，保持 C# WarehouseInventoryComponent 的字符串值。
func _init() -> void:
	DragSourceSystem = &"SystemWarehouse"


## 进入场景树时先按基类建立槽位，再把自己注册进存档层。
##
## `super()` 必须在注册之前：基类 `_ready()` 负责按 `Capacity` 建立槽位对象，注册会立刻
## 分发存档并写入槽位，没有槽位可写就会丢内容。
##
## @return 无返回值。
func _ready() -> void:
	super()
	_register_with_save_manager()


## 向存档层注册自身。
##
## @return 无返回值。
func _register_with_save_manager() -> void:
	var save_manager: Node = get_node_or_null(SAVE_MANAGER_PATH)
	if save_manager == null or not save_manager.has_method("register_participant"):
		push_error("Warehouse: 未找到 SaveManager，仓库内容将不会跨运行保存。")
		return

	save_manager.call("register_participant", self)


# ── 存档参与者协议 ───────────────────────────────────────────────────────

## 返回稳定的存档键。
##
## @return `"warehouse"`。
func save_key() -> String:
	return SAVE_KEY


## 返回本参与者的作用域。
##
## @return `"global"`。
func save_scope() -> String:
	return SAVE_SCOPE


## 返回需要触发自动存档的信号名。
##
## 只订阅 `InventoryChanged`：它是仓库内容发生结构性变化的统一出口，买入、拖拽、整理都
## 会经过它，因此不需要再单独挂别的触发点。
##
## @return 信号名数组。
func save_change_signals() -> Array:
	return ["InventoryChanged"]


## 采集当前仓库槽位。
##
## 只落 CardId / 数量 / 洗炼属性，不落 Resource 路径或数值，理由见 `save_slot_codec.gd`。
##
## @return `{"slots": Array}`，长度等于当前容量，空槽位为 null。
func capture_save_data() -> Dictionary:
	var entries: Array = []
	for stack: Variant in Slots:
		entries.append(SAVE_SLOT_CODEC.call("stack_to_entry", stack))
	return {"slots": SAVE_SLOT_CODEC.call("encode_slots", entries)}


## 用存档内容覆盖仓库槽位。
##
## 语义是**先清空再写入**，而不是叠加：存档是唯一真相源，叠加会让「玩家在仓库界面挪走
## 一件物品后重开游戏又出现」这种幽灵物品。
##
## @param data 本参与者的存档载荷；空字典表示「没有存档」，此时仓库保持默认空状态。
## @return 是否成功应用（结构损坏、个别物品缺失都按成功 + 告警处理，不让整档作废）。
func apply_save_data(data: Dictionary) -> bool:
	var decode_result: Dictionary = SAVE_SLOT_CODEC.call(
		"decode_slots", data.get("slots", []), Capacity, _resolve_item_lookup()
	)

	if not bool(decode_result.get("ok")):
		push_warning(
			"Warehouse: 存档中的槽位结构不可用（%s），本次以空仓库启动。"
			% str(decode_result.get("reasons", []))
		)
		_clear_all_slots()
		_notify_inventory_changed()
		return true

	var entries: Array = decode_result.get("entries", []) as Array
	# 先扩容再写入：存档槽位数可能多于当前容量（例如升级等级读取晚于本组件），
	# 不扩容就会把高序号槽位的物品写进不存在的下标。
	EnsureCapacityAtLeast(entries.size())
	_write_entries(entries)
	_report_decode_issues(decode_result)
	_notify_inventory_changed()
	return true


## 解析水合用的查表函数。
##
## @return 注入的查表函数优先；否则尝试 `/root/ItemsControl.get_item`；都没有时返回空 Callable。
func _resolve_item_lookup() -> Callable:
	if SaveItemLookup.is_valid():
		return SaveItemLookup

	var items_control: Node = get_node_or_null(ITEMS_CONTROL_PATH)
	if items_control != null and items_control.has_method("get_item"):
		return Callable(items_control, "get_item")

	return Callable()


## 清空全部槽位。
##
## @return 无返回值。
func _clear_all_slots() -> void:
	for stack: Variant in Slots:
		stack.call("Clear")


## 把解码结果写入槽位。
##
## @param entries `decode_slots` 返回的条目数组。
## @return 无返回值。
func _write_entries(entries: Array) -> void:
	_clear_all_slots()
	var ok_status: String = String(SAVE_SLOT_CODEC.get_script_constant_map()["STATUS_OK"])

	for index: int in entries.size():
		var entry: Dictionary = entries[index]
		if String(entry.get("status", "")) != ok_status:
			continue

		var stack: Variant = Slots[index]
		stack.call("SetItem", entry.get("item"), int(entry.get("amount")))
		# 洗炼属性必须在 SetItem 之后写入：SetItem 的语义包含「清空上一次的洗炼结果」。
		var rolled: Variant = entry.get("rolled")
		if rolled is Dictionary and not (rolled as Dictionary).is_empty():
			var target: Dictionary = stack.get("RolledAttributes")
			for key: Variant in rolled:
				target[key] = (rolled as Dictionary)[key]


## 把被跳过的槽位与被丢弃的洗炼属性记进日志。
##
## @param decode_result `decode_slots` 的返回值。
## @return 无返回值。
func _report_decode_issues(decode_result: Dictionary) -> void:
	var skipped: int = int(decode_result.get("skipped", 0))
	if skipped > 0:
		push_warning(
			"Warehouse: 存档中有 %d 个槽位无法水合，已跳过：%s"
			% [skipped, str(decode_result.get("reasons", []))]
		)
	var dropped: int = int(decode_result.get("rolled_dropped", 0))
	if dropped > 0:
		push_warning("Warehouse: 存档中有 %d 个洗炼属性不属于对应物品，已丢弃。" % dropped)
