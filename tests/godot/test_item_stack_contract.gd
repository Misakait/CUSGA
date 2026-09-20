@tool
extends McpTestSuite

## ItemStack GDScript 并行实现的最小行为契约套件。
##
## 测试只覆盖数据对象的引用、数量和通知语义，不替换 C# Inventory/Shop/Crafting
## 消费端，也不加载生产物品资产，避免跨语言边界尚未迁移时产生副作用。

const ITEM_DATA_SCRIPT: GDScript = preload("res://resources/item/item_data.gd")
const ITEM_STACK_SCRIPT: GDScript = preload("res://resources/item/item_stack.gd")


## 返回套件名称，便于 MCP 精确运行这一批测试。
func suite_name() -> String:
	return "item_stack_contract"


## 验证 GDScript ItemStack 保留引用、数量、溢出、复制和变化通知契约。
func test_item_stack_gdscript_contract_preserves_stack_semantics() -> void:
	var item: Resource = ITEM_DATA_SCRIPT.new()
	item.set("CardId", &"stack_probe")
	item.set("MaxStackSize", 5)

	var stack = ITEM_STACK_SCRIPT.new()
	var signal_state: Dictionary = {"count": 0}
	stack.OnStackChanged.connect(func(_stack: Variant) -> void:
		signal_state["count"] = int(signal_state.get("count", 0)) + 1
	)
	assert_true(bool(stack.IsEmpty), "新建 GDScript ItemStack 必须为空。")
	assert_eq(int(stack.AvailableSpace), 0, "空堆叠的可用空间必须为 0。")

	stack.SetItem(item, 2)
	assert_false(bool(stack.IsEmpty), "设置正数量后堆叠不得为空。")
	assert_false(bool(stack.IsFull), "数量未达到上限时堆叠不得为满。")
	assert_eq(int(stack.AvailableSpace), 3, "可用空间必须按物品实际上限计算。")

	var overflow: int = stack.Add(4)
	assert_eq(overflow, 1, "超过可用空间时必须返回未放入的溢出数量。")
	assert_eq(int(stack.Amount), 5, "Add 必须只增加可容纳的数量。")
	assert_true(bool(stack.IsFull), "达到上限后堆叠必须为满。")
	assert_eq(int(stack.AvailableSpace), 0, "满堆叠的可用空间必须为 0。")
	assert_eq(int(signal_state["count"]), 2, "SetItem 和 Add 都必须发出一次变化通知。")

	stack.RolledAttributes[7] = 3
	var copy = stack.Duplicate()
	assert_true(copy.Item == item, "Duplicate 必须保留同一份 Item Resource 引用。")
	assert_eq(int(copy.Amount), 5, "Duplicate 必须复制数量。")
	assert_eq(int(copy.GetBonus(7)), 3, "Duplicate 必须复制洗炼属性。")

	var target = ITEM_STACK_SCRIPT.new()
	target.CopyFrom(copy)
	assert_true(target.Item == item, "CopyFrom 必须保留来源物品引用。")
	assert_eq(int(target.Amount), 5, "CopyFrom 必须复制来源数量。")
	assert_eq(int(target.GetBonus(7)), 3, "CopyFrom 必须复制来源洗炼属性。")

	target.SetItem(item, 0)
	assert_true(bool(target.IsEmpty), "设置非正数量必须清空目标堆叠。")
	assert_eq(int(target.Amount), 0, "清空后的数量必须为 0。")
