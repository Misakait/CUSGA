@tool
extends McpTestSuite

## 新美术合成界面的场景绑定契约和运行期回归入口。
## 编辑器中的非工具生产脚本为占位实例，套件只核对结构；真实按钮和库存行为
## 必须在游戏运行后通过 run_runtime_checks 执行，不能把结构检查当作合成通过。

const UI_SCENE: PackedScene = preload("res://scenes/crafting/CraftingUI.tscn")
const UI_SCRIPT: GDScript = preload("res://core/ui/crafting/crafting_ui_controller.gd")
const INVENTORY_SCRIPT: GDScript = preload("res://entities/components/inventory_component.gd")
const CRAFTING_SCRIPT: GDScript = preload("res://entities/components/crafting_component.gd")
const ITEM_SCRIPT: GDScript = preload("res://resources/item/item_data.gd")
const INGREDIENT_SCRIPT: GDScript = preload("res://resources/recipe/crafting_ingredient.gd")
const RECIPE_SCRIPT: GDScript = preload("res://resources/recipe/crafting_recipe.gd")
const BOOK_SCRIPT: GDScript = preload("res://resources/recipe/recipe_book_data.gd")


## 提供编辑器测试发现使用的稳定名称。
## @return 合成界面契约套件名。
func suite_name() -> String:
	return "crafting_ui_contract"


## 核对控制器实际使用的路径能在生产场景中解析到正确控件。
## @return 无。
func test_production_scene_resolves_controller_controls() -> void:
	var ui: Control = track(UI_SCENE.instantiate()) as Control
	assert_eq(ui.get_script(), UI_SCRIPT, "新美术场景必须挂载当前合成控制器。")
	# 编辑器可能保留旧脚本常量缓存；读取当前源码才会检查本轮实际绑定路径。
	var quantity_path: NodePath = _read_path_constant("QUANTITY_PATH")
	var button_path: NodePath = _read_path_constant("CRAFT_BUTTON_PATH")
	assert_false(quantity_path.is_empty(), "控制器必须声明真实数量框路径。")
	assert_false(button_path.is_empty(), "控制器必须声明真实按钮路径。")
	if quantity_path.is_empty() or button_path.is_empty():
		return
	assert_true(ui.get_node_or_null(quantity_path) is SpinBox, "控制器数量路径必须指向新场景的 SpinBox。")
	assert_true(ui.get_node_or_null(button_path) is Button, "控制器按钮路径必须指向新场景的合成按钮。")
	assert_true(
		ui.get_node_or_null("RecipeSection/ScrollContainer/RecipeGrid") is GridContainer,
		"配方区必须保留实际容器。",
	)
	assert_true(
		ui.get_node_or_null("DetailSection/Ingredient/ScrollContainer/IngredientList") is VBoxContainer,
		"材料区必须保留实际容器。",
	)


func _read_path_constant(constant_name: String) -> NodePath:
	var source: String = FileAccess.get_file_as_string(
		"res://core/ui/crafting/crafting_ui_controller.gd"
	)
	for line: String in source.split("\n"):
		if line.strip_edges().begins_with("const %s: NodePath = ^\"" % constant_name):
			var parts: PackedStringArray = line.split("\"")
			if parts.size() >= 3:
				return NodePath(parts[1])
	return NodePath()


## 在真实游戏场景树中执行生产场景、库存和制作组件的同步回归。
## @param tree 当前游戏的 SceneTree，必须由 Engine.get_main_loop 取得。
## @return 包含检查次数、失败说明和通过标记的字典；夹具离树后立即释放。
static func run_runtime_checks(tree: SceneTree) -> Dictionary:
	var result: Dictionary = {"checks": 0, "failures": [], "passed": false}
	if Engine.is_editor_hint() or tree == null:
		_expect(result, false, "真实合成回归必须在游戏运行期执行。")
		return result
	var host := Node.new()
	host.name = "CraftingUIContractFixture"
	tree.root.add_child(host)
	var components := Node.new()
	host.add_child(components)
	var inventory: Node = INVENTORY_SCRIPT.new()
	inventory.name = "InventoryComponent"
	inventory.set("Capacity", 4)
	components.add_child(inventory)
	var material: Resource = _new_item(&"crafting_contract_material", "回归材料")
	var output: Resource = _new_item(&"crafting_contract_output", "回归产物")
	var ingredient: Resource = INGREDIENT_SCRIPT.new()
	ingredient.set("RequiredItem", material)
	ingredient.set("Amount", 2)
	var recipe: Resource = RECIPE_SCRIPT.new()
	recipe.set("RecipeName", "回归配方")
	var inputs: Array[Resource] = [ingredient]
	recipe.set("Inputs", inputs)
	recipe.set("OutputItem", output)
	recipe.set("OutputAmount", 2)
	var book: Resource = BOOK_SCRIPT.new()
	var recipes: Array[Resource] = [recipe]
	book.set("Recipes", recipes)
	var crafting: Node = CRAFTING_SCRIPT.new()
	crafting.name = "CraftingComponent"
	crafting.set("RecipeBook", book)
	components.add_child(crafting)
	var events: Dictionary = {"completed": 0, "failed": 0, "quantity": 0, "output_amount": 0}
	crafting.connect("CraftingCompleted", func(_recipe: Variant, quantity: int, amount: int) -> void:
		events["completed"] = int(events["completed"]) + 1
		events["quantity"] = quantity
		events["output_amount"] = amount
	)
	crafting.connect("CraftingFailed", func(_recipe: Variant, _quantity: int, _reason: int) -> void:
		events["failed"] = int(events["failed"]) + 1
	)
	_expect(result, int(inventory.call("AddItem", material, 6)) == 0, "夹具应完整加入六份材料。")
	var ui: Control = UI_SCENE.instantiate() as Control
	host.add_child(ui)
	_expect(result, not ui.visible, "真实生命周期初始化后界面应隐藏。")
	var quantity := ui.get_node_or_null("DetailSection/OutPutCount/SpinBox") as SpinBox
	var button := ui.get_node_or_null("DetailSection/OutPutCount/Craft/CraftButton") as Button
	_expect(result, quantity != null and button != null, "实际生产场景应包含数量框和按钮。")
	if quantity == null or button == null:
		host.free()
		return result
	_expect(result, button.disabled, "尚未绑定配方时禁止合成。")
	ui.call("Open", crafting)
	_expect(result, ui.visible, "绑定真实制作组件后应显示界面。")
	_expect(result, quantity.value == 1 and quantity.min_value == 1, "默认合成一次，最小次数为一。")
	_expect(result, quantity.step == 1 and quantity.rounded, "数量框只能提交整数次数。")
	_expect(result, quantity.max_value == 3 and quantity.editable, "六份材料应允许最多三次合成。")
	_expect(result, button.pressed.is_connected(Callable(ui, "_craft_selected")), "真实按钮必须连接制作入口。")
	_expect(
		result,
		quantity.value_changed.is_connected(Callable(ui, "_on_quantity_changed")),
		"真实数量框必须连接材料预览。",
	)
	_expect(result, not button.disabled, "材料充足时合成按钮应可用。")
	button.pressed.emit()
	_expect(result, int(inventory.call("ItemCnt", material)) == 4, "默认按钮合成应扣除两份材料。")
	_expect(result, int(inventory.call("ItemCnt", output)) == 2, "默认按钮合成应加入两份产物。")
	_expect(result, int(events["completed"]) == 1 and int(events["quantity"]) == 1, "一次点击只能完成一次合成请求。")
	_expect(result, quantity.max_value == 2, "扣料信号应立即收窄可合成次数。")
	quantity.value = 0
	_expect(result, quantity.value == 1, "零数量应被限制为一次。")
	quantity.value = 1.4
	_expect(result, quantity.value == 1, "小数数量应归一为整数。")
	quantity.value = 2
	var row := ui.get_node("DetailSection/Ingredient/ScrollContainer/IngredientList").get_child(0)
	var required_label := row.get_node("QuantityLabel") as Label
	_expect(result, required_label.text.contains("需要 4 / 拥有 4"), "两次合成预览应与实际材料需求一致。")
	_expect(result, int(inventory.call("ItemCnt", material)) == 4, "改变数量不得提前扣料。")
	quantity.value = 1
	# 模拟尚未失焦的键盘输入，验证按钮会先提交文本再保存请求次数。
	quantity.get_line_edit().text = "2"
	button.pressed.emit()
	_expect(result, int(inventory.call("ItemCnt", material)) == 0, "输入两次后点击应扣除剩余四份材料。")
	_expect(result, int(inventory.call("ItemCnt", output)) == 6, "两次追加合成应再产出四份，总计六份。")
	_expect(
		result,
		int(events["completed"]) == 2
			and int(events["quantity"]) == 2
			and int(events["output_amount"]) == 4,
		"同步库存刷新不能改变本次两次合成的请求和产出信号。",
	)
	_expect(result, button.disabled and not quantity.editable, "材料耗尽后按钮和数量编辑应禁用。")
	button.pressed.emit()
	_expect(
		result,
		int(events["completed"]) == 2 and int(events["failed"]) == 0,
		"禁用按钮即使被外部发出信号也不得重复调用组件。",
	)
	inventory.call("AddItem", material, 2)
	_expect(
		result,
		not button.disabled and quantity.editable and quantity.max_value == 1,
		"外部补充材料后应恢复合成。",
	)
	crafting.set("RecipeBook", BOOK_SCRIPT.new())
	ui.call("Open", crafting)
	_expect(result, button.disabled and not quantity.editable, "重新绑定空配方书必须撤销旧可合成状态。")
	_expect(
		result,
		(ui.get_node("DetailSection/OutPut/OutPutLabel") as Label).text.is_empty(),
		"空配方书应清空产物详情。",
	)
	button.pressed.emit()
	_expect(
		result,
		int(inventory.call("ItemCnt", material)) == 2
			and int(inventory.call("ItemCnt", output)) == 6,
		"空配方执行不得改变库存。",
	)
	_expect(result, int(events["completed"]) == 2 and int(events["failed"]) == 0, "空配方不得向制作组件提交请求。")
	host.free()
	result["passed"] = (result["failures"] as Array).is_empty()
	return result


static func _new_item(identifier: StringName, display_name: String) -> Resource:
	var item: Resource = ITEM_SCRIPT.new()
	item.set("CardId", identifier)
	item.set("CardName", display_name)
	item.set("MaxStackSize", 99)
	return item


static func _expect(result: Dictionary, condition: bool, message: String) -> void:
	result["checks"] = int(result["checks"]) + 1
	if not condition:
		(result["failures"] as Array).append(message)
