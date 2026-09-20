extends Control

## 合成界面的 GDScript 生产实现。
##
## UI 只负责配方展示、数量输入、库存变化刷新和 GameplayPort 请求转发；
## 合成规则继续由 CraftingComponent/CraftingService 通过稳定方法协议提供。

## GameplayPort 节点路径；由 Main.tscn 实例覆盖。
@export var GameplayPortPath: NodePath

## 接收合成请求的游戏端口。
var _gameplay_port: Node = null
## 当前绑定的合成组件，可为旧 C# 或新 GDScript Node。
var _crafting: Node = null
## 当前合成组件绑定的库存节点。
var _inventory: Node = null
## 配方按钮容器。
var _recipe_grid: GridContainer
## 材料行容器。
var _ingredient_list: VBoxContainer
## 产物图标。
var _output_icon: TextureRect
## 产物名称。
var _output_name_label: Label
## 产物说明。
var _output_description_label: Label
## 合成数量输入框。
var _quantity_spin_box: SpinBox
## 合成按钮。
var _craft_button: Button
## 操作结果文本。
var _status_label: Label
## 当前选中的配方 Resource。
var _selected_recipe: Variant = null
## 配方 Resource 到按钮的映射，用于刷新选中状态。
var _recipe_buttons: Dictionary = {}
## 面板隐藏期间库存变化后需要延迟刷新的标志。
var _needs_inventory_refresh: bool = false


## 初始化控件、连接 GameplayPort 请求和按钮事件，并保持初始隐藏。
func _ready() -> void:
	_recipe_grid = get_node("%RecipeGrid") as GridContainer
	_ingredient_list = get_node("%IngredientList") as VBoxContainer
	_output_icon = get_node("%OutputIcon") as TextureRect
	_output_name_label = get_node("%OutputNameLabel") as Label
	_output_description_label = get_node("%OutputDescriptionLabel") as Label
	_quantity_spin_box = get_node("%QuantitySpinBox") as SpinBox
	_craft_button = get_node("%CraftButton") as Button
	_status_label = get_node("%StatusLabel") as Label
	var close_button := get_node("%CloseButton") as Button
	if not close_button.pressed.is_connected(Close):
		close_button.pressed.connect(Close)
	if not _quantity_spin_box.value_changed.is_connected(_on_quantity_changed):
		_quantity_spin_box.value_changed.connect(_on_quantity_changed)
	if not _craft_button.pressed.is_connected(_on_craft_button_pressed):
		_craft_button.pressed.connect(_on_craft_button_pressed)
	_gameplay_port = get_node_or_null(GameplayPortPath) as Node
	_connect_signal(_gameplay_port, &"CraftingToggleRequested", Callable(self, "_handle_crafting_toggle_request"))
	_connect_signal(_gameplay_port, &"CraftingOpenRequested", Callable(self, "_handle_crafting_open_request"))
	_connect_signal(_gameplay_port, &"CraftingNodeToggleRequested", Callable(self, "_handle_crafting_toggle_request"))
	_connect_signal(_gameplay_port, &"CraftingNodeOpenRequested", Callable(self, "_handle_crafting_open_request"))
	visibility_changed.connect(_on_visibility_changed)
	hide()


## 响应合成切换请求。
## @param crafting 请求绑定的合成组件。
func _handle_crafting_toggle_request(crafting: Node) -> void:
	if crafting == null:
		push_error("CraftingUI 收到空 CraftingComponent。")
		return
	if visible:
		Close()
	else:
		Open(crafting)


## 响应幂等打开请求，不因当前可见状态而关闭面板。
## @param crafting 请求绑定的合成组件。
func _handle_crafting_open_request(crafting: Node) -> void:
	if crafting == null:
		push_error("CraftingUI 收到空 CraftingComponent。")
		return
	Open(crafting)


## 绑定合成组件、生成配方按钮并显示面板。
## @param crafting 请求绑定的合成组件。
func Open(crafting: Node) -> void:
	if crafting == null:
		return
	_bind_crafting(crafting)
	_generate_recipe_buttons()
	var recipes: Array = _recipes()
	if _selected_recipe == null or not recipes.has(_selected_recipe):
		_select_recipe(recipes[0] if not recipes.is_empty() else null)
	else:
		_refresh_selected_recipe()
	_needs_inventory_refresh = false
	show()


## 隐藏合成面板。
func Close() -> void:
	hide()


## 切换组件绑定并维护库存变化信号。
func _bind_crafting(crafting: Node) -> void:
	if _crafting == crafting:
		return
	_disconnect_signal(_inventory, &"InventoryChanged", Callable(self, "_on_inventory_changed"))
	_crafting = crafting
	_inventory = crafting.get("Inventory") as Node
	_connect_signal(_inventory, &"InventoryChanged", Callable(self, "_on_inventory_changed"))
	_selected_recipe = null
	_status_label.text = ""


## 根据当前配方列表重建按钮，并保留输出图标、标题和提示文本。
func _generate_recipe_buttons() -> void:
	for child in _recipe_grid.get_children():
		child.queue_free()
	_recipe_buttons.clear()
	for recipe: Variant in _recipes():
		var button := Button.new()
		button.custom_minimum_size = Vector2(64, 56)
		button.toggle_mode = true
		button.icon = _get_item_icon(recipe)
		button.expand_icon = true
		button.text = "" if button.icon != null else _get_recipe_title(recipe)
		button.tooltip_text = _get_recipe_title(recipe)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(Callable(self, "_select_recipe").bind(recipe))
		_recipe_grid.add_child(button)
		_recipe_buttons[recipe] = button


## 设置当前选中配方并刷新右侧详情。
## @param recipe 配方 Resource 或 null。
func _select_recipe(recipe: Variant) -> void:
	_selected_recipe = recipe
	_status_label.text = ""
	_refresh_selected_recipe()


## 刷新选中状态、产物信息、材料列表和可合成数量。
func _refresh_selected_recipe() -> void:
	for recipe: Variant in _recipe_buttons:
		var button: Button = _recipe_buttons[recipe] as Button
		button.button_pressed = recipe == _selected_recipe
	if _selected_recipe == null:
		_output_icon.texture = null
		_output_name_label.text = ""
		_output_description_label.text = ""
		_clear_ingredient_list()
		_quantity_spin_box.value = 1
		_quantity_spin_box.editable = false
		_craft_button.disabled = true
		return
	var output_item: Resource = _get_resource(_selected_recipe, "OutputItem")
	if output_item == null:
		_output_icon.texture = null
		_output_name_label.text = _get_recipe_title(_selected_recipe)
		_output_description_label.text = ""
		_clear_ingredient_list()
		_quantity_spin_box.value = 1
		_quantity_spin_box.editable = false
		_craft_button.disabled = true
		return
	_output_icon.texture = _get_item_icon(_selected_recipe)
	_output_name_label.text = _get_recipe_title(_selected_recipe)
	_output_description_label.text = _get_string(output_item, "DisplayDescription", "")
	var max_craftable: int = int(_crafting.call("MaxCraftableQuantity", _selected_recipe))
	_quantity_spin_box.min_value = 1
	_quantity_spin_box.max_value = maxi(1, max_craftable)
	_quantity_spin_box.editable = max_craftable > 0
	if _quantity_spin_box.value < 1:
		_quantity_spin_box.value = 1
	elif _quantity_spin_box.value > _quantity_spin_box.max_value:
		_quantity_spin_box.value = _quantity_spin_box.max_value
	_craft_button.disabled = max_craftable <= 0
	_refresh_ingredient_list(_get_craft_quantity())


## 按当前数量刷新材料行。
## @param quantity 合成次数。
func _refresh_ingredient_list(quantity: int) -> void:
	_clear_ingredient_list()
	for requirement: Variant in _build_ingredient_totals(_selected_recipe, quantity):
		var item: Resource = requirement[0]
		var amount: int = int(requirement[1])
		var owned: int = int(_inventory.call("ItemCnt", item)) if _inventory != null else 0
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 36)
		var icon := TextureRect.new()
		icon.texture = _get_resource(item, "DisplayIcon")
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var label := Label.new()
		label.text = "%s  需要 %d / 拥有 %d" % [_get_item_name(item), amount, owned]
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if owned < amount:
			label.add_theme_color_override("font_color", Color(1.0, 0.32, 0.24))
		row.add_child(label)
		_ingredient_list.add_child(row)


## 清理旧材料行。
func _clear_ingredient_list() -> void:
	for child in _ingredient_list.get_children():
		child.queue_free()


## 数量变化时刷新材料需求。
## @param value SpinBox 新值。
func _on_quantity_changed(_value: float) -> void:
	if _selected_recipe != null:
		_refresh_ingredient_list(_get_craft_quantity())


## 调用 CraftingComponent 合成并显示与 C# UI 一致的结果文本。
func _on_craft_button_pressed() -> void:
	if _selected_recipe == null or _crafting == null:
		return
	var quantity: int = _get_craft_quantity()
	var failure_reason: int
	if _crafting.has_method("TryCraftWithReason"):
		failure_reason = int(_crafting.call("TryCraftWithReason", _selected_recipe, quantity))
	else:
		var crafted: bool = bool(_crafting.call("TryCraft", _selected_recipe, quantity))
		failure_reason = 0 if crafted else _infer_failure_reason(_selected_recipe, quantity)
	if failure_reason == 0:
		var output_amount: int = int(_get_property(_selected_recipe, "OutputAmount", 0)) * quantity
		_status_label.text = "已合成 %s x%d" % [_get_item_name(_get_resource(_selected_recipe, "OutputItem")), output_amount]
	else:
		_status_label.text = _failure_text(failure_reason)
	_refresh_selected_recipe()


## 面板隐藏期间暂存库存变化，重新显示时合并刷新。
func _on_inventory_changed() -> void:
	if not is_visible_in_tree():
		_needs_inventory_refresh = true
		return
	if _selected_recipe != null:
		_refresh_selected_recipe()
	_needs_inventory_refresh = false


## 面板重新可见后执行延迟刷新。
func _on_visibility_changed() -> void:
	if not _needs_inventory_refresh or not is_visible_in_tree():
		return
	if _selected_recipe != null:
		_refresh_selected_recipe()
	_needs_inventory_refresh = false


## 将数量输入限制为至少一次。
## @return 当前整数合成数量。
func _get_craft_quantity() -> int:
	return maxi(1, int(round(_quantity_spin_box.value)))


## 汇总重复材料，保持 C# CraftingUI 的数量计算。
## @param recipe 当前配方。
## @param quantity 合成次数。
## @return [ItemData, required_amount] 数组。
func _build_ingredient_totals(recipe: Variant, quantity: int) -> Array:
	var totals: Dictionary = {}
	if recipe == null:
		return []
	var inputs: Variant = recipe.get("Inputs")
	if not (inputs is Array):
		return []
	for ingredient: Variant in inputs:
		var item: Resource = _get_resource(ingredient, "RequiredItem")
		var amount: int = int(_get_property(ingredient, "Amount", 0))
		if item == null or amount <= 0:
			continue
		totals[item] = int(totals.get(item, 0)) + amount * quantity
	var result: Array = []
	for item: Resource in totals:
		result.append([item, int(totals[item])])
	return result


## 在旧 C# 组件没有原因码入口时推断失败类别。
func _infer_failure_reason(recipe: Variant, quantity: int) -> int:
	if recipe == null or quantity <= 0 or _get_resource(recipe, "OutputItem") == null:
		return 1
	for requirement: Variant in _build_ingredient_totals(recipe, quantity):
		if _inventory == null or int(_inventory.call("ItemCnt", requirement[0])) < int(requirement[1]):
			return 3
	return 4


## 返回稳定的失败提示文本。
func _failure_text(reason: int) -> String:
	match reason:
		3:
			return "材料不足"
		4:
			return "背包空间不足"
		2:
			return "数量无效"
		_:
			return "配方无效"


## 读取配方书数组并过滤空资源。
func _recipes() -> Array:
	if _crafting == null:
		return []
	var raw: Variant = _crafting.get("Recipes")
	if raw is Array:
		return raw
	return []


## 读取对象字段并在缺失时回退。
func _get_property(value: Variant, property_name: StringName, fallback: Variant = null) -> Variant:
	if not (value is Object):
		return fallback
	var result: Variant = (value as Object).get(String(property_name))
	return fallback if result == null else result


## 读取 Resource 字段。
func _get_resource(value: Variant, property_name: StringName) -> Resource:
	var result: Variant = _get_property(value, property_name, null)
	return result as Resource if result is Resource else null


## 读取字符串字段。
func _get_string(value: Variant, property_name: StringName, fallback: String) -> String:
	var result: Variant = _get_property(value, property_name, fallback)
	return fallback if result == null else String(result)


## 获取输出物品图标。
func _get_item_icon(recipe: Variant) -> Texture2D:
	var output: Resource = _get_resource(recipe, "OutputItem")
	return _get_resource(output, "DisplayIcon") as Texture2D


## 获取配方标题。
func _get_recipe_title(recipe: Variant) -> String:
	var recipe_name: String = _get_string(recipe, "RecipeName", "")
	return recipe_name if not recipe_name.strip_edges().is_empty() else _get_item_name(_get_resource(recipe, "OutputItem"))


## 获取物品显示名。
func _get_item_name(item: Resource) -> String:
	if item == null:
		return ""
	var display_name: String = _get_string(item, "DisplayName", "")
	return display_name if not display_name.strip_edges().is_empty() else _get_string(item, "CardName", "")


## 安全连接跨语言信号。
func _connect_signal(source: Node, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)


## 安全断开跨语言信号。
func _disconnect_signal(source: Node, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and source.is_connected(signal_name, callback):
		source.disconnect(signal_name, callback)


## 退出场景树时断开信号，避免旧端口继续持有界面回调。
func _exit_tree() -> void:
	_disconnect_signal(_gameplay_port, &"CraftingToggleRequested", Callable(self, "_handle_crafting_toggle_request"))
	_disconnect_signal(_gameplay_port, &"CraftingOpenRequested", Callable(self, "_handle_crafting_open_request"))
	_disconnect_signal(_gameplay_port, &"CraftingNodeToggleRequested", Callable(self, "_handle_crafting_toggle_request"))
	_disconnect_signal(_gameplay_port, &"CraftingNodeOpenRequested", Callable(self, "_handle_crafting_open_request"))
	_disconnect_signal(_inventory, &"InventoryChanged", Callable(self, "_on_inventory_changed"))
