extends Control

## 新美术 CraftingUI 的根控制器。
## 根节点协调 GameplayPort、配方区和详情区，合成规则仍由 CraftingComponent/Service 负责。

const RECIPE_CONTROLLER_SCRIPT: GDScript = preload("res://core/ui/crafting/recipe_section_controller.gd")
const INGREDIENT_CONTROLLER_SCRIPT: GDScript = preload("res://core/ui/crafting/ingredient_section_controller.gd")
const ITEM_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

## GameplayPort 节点路径，由 Main.tscn 实例覆盖。
@export var GameplayPortPath: NodePath
## HUDRoot 共享 TooltipPanel 的相对路径。
@export var TooltipPanelPath: NodePath = NodePath("../../TooltipPanel")

var _gameplay_port: Node = null
var _crafting: Node = null
var _inventory: Node = null
var _selected_recipe: Variant = null
var _recipe_controller: RefCounted
var _ingredient_controller: RefCounted
var _tooltip_panel: Node = null
var _output_icon: TextureRect = null
var _output_name: Label = null
var _output_name_compat: Label = null
var _output_description: Label = null
var _quantity: SpinBox = null
var _craft_button: Button = null
var _status: Label = null
var _needs_inventory_refresh: bool = false

## 初始化新场景节点、控制器和 GameplayPort 请求，并保持初始隐藏。
func _ready() -> void:
	_output_icon = get_node_or_null("DetailSection/OutPut/OutputIcon") as TextureRect
	_output_name = get_node_or_null("DetailSection/OutPut/OutPutLabel") as Label
	_output_name_compat = get_node_or_null("%OutputNameLabel") as Label
	_output_description = get_node_or_null("DetailSection/OutPut/DescriptionContainer/OutPutDescription") as Label
	var recipe_grid := get_node_or_null("RecipeSection/ScrollContainer/RecipeGrid") as GridContainer
	var ingredient_list := get_node_or_null("DetailSection/Ingredient/ScrollContainer/IngredientList") as VBoxContainer
	_recipe_controller = RECIPE_CONTROLLER_SCRIPT.new()
	_ingredient_controller = INGREDIENT_CONTROLLER_SCRIPT.new()
	_recipe_controller.recipe_selected.connect(_select_recipe)
	_recipe_controller.item_hovered.connect(_show_item_tooltip)
	_recipe_controller.item_left.connect(_hide_tooltip)
	_ingredient_controller.item_selected.connect(_on_ingredient_selected)
	_ingredient_controller.item_hovered.connect(_show_item_tooltip)
	_ingredient_controller.item_left.connect(_hide_tooltip)
	_recipe_controller.bind(recipe_grid, null)
	_ingredient_controller.bind(ingredient_list, null)
	_quantity = get_node_or_null("DetailSection/Quantity") as SpinBox
	_craft_button = get_node_or_null("DetailSection/CraftButton") as Button
	_status = get_node_or_null("DetailSection/StatusLabel") as Label
	if _quantity != null and not _quantity.value_changed.is_connected(_on_quantity_changed):
		_quantity.value_changed.connect(_on_quantity_changed)
	if _craft_button != null and not _craft_button.pressed.is_connected(_craft_selected):
		_craft_button.pressed.connect(_craft_selected)
	_gameplay_port = get_node_or_null(GameplayPortPath) if not GameplayPortPath.is_empty() else null
	_tooltip_panel = get_node_or_null(TooltipPanelPath)
	_connect_signal(_gameplay_port, &"CraftingToggleRequested", Callable(self, "_handle_toggle"))
	_connect_signal(_gameplay_port, &"CraftingOpenRequested", Callable(self, "_handle_open"))
	_connect_signal(_gameplay_port, &"CraftingNodeToggleRequested", Callable(self, "_handle_toggle"))
	_connect_signal(_gameplay_port, &"CraftingNodeOpenRequested", Callable(self, "_handle_open"))
	var close_button := get_node_or_null("CloseButton") as Button
	if close_button != null and not close_button.pressed.is_connected(Close):
		close_button.pressed.connect(Close)
	visibility_changed.connect(_on_visibility_changed)
	hide()

## 响应 GameplayPort 的切换请求。
## @param crafting 请求绑定的合成组件。
func _handle_toggle(crafting: Node) -> void:
	if visible:
		Close()
	else:
		Open(crafting)

## 响应 GameplayPort 的幂等打开请求。
## @param crafting 请求绑定的合成组件。
func _handle_open(crafting: Node) -> void:
	Open(crafting)

## 绑定合成组件并显示新美术界面。
## @param crafting 请求绑定的合成组件。
func Open(crafting: Node) -> void:
	if crafting == null:
		return
	_crafting = crafting
	_disconnect_signal(_inventory, &"InventoryChanged", Callable(self, "_on_inventory_changed"))
	_inventory = crafting.get("Inventory") as Node
	_connect_signal(_inventory, &"InventoryChanged", Callable(self, "_on_inventory_changed"))
	_recipe_controller.bind(get_node("RecipeSection/ScrollContainer/RecipeGrid"), _crafting)
	_ingredient_controller.bind(get_node("DetailSection/Ingredient/ScrollContainer/IngredientList"), _inventory)
	var recipes: Array = _recipe_controller.get_recipes()
	_selected_recipe = recipes[0] if not recipes.is_empty() else null
	_refresh_details()
	_needs_inventory_refresh = false
	show()

## 隐藏界面并关闭合成提示。
func Close() -> void:
	_hide_tooltip(null)
	hide()

func _select_recipe(recipe: Variant, _slot: BaseButton = null) -> void:
	_selected_recipe = recipe
	_recipe_controller.set_selected(recipe)
	_show_item_tooltip(_resource(recipe, "OutputItem"), _slot)
	_refresh_details()

func _on_ingredient_selected(item: Resource, slot: BaseButton) -> void:
	_show_item_tooltip(item, slot)

func _refresh_details() -> void:
	if _output_name == null:
		return
	if _selected_recipe == null:
		_output_name.text = ""
		if _output_name_compat != null:
			_output_name_compat.text = ""
		_output_description.text = ""
		_output_icon.texture = null
		_ingredient_controller.refresh(null)
		return
	var output := _resource(_selected_recipe, "OutputItem")
	_output_name.text = String(ITEM_COMPAT.call("get_display_name", output, _recipe_name(_selected_recipe)))
	if _output_name_compat != null:
		_output_name_compat.text = _recipe_name(_selected_recipe)
	_output_description.text = String(ITEM_COMPAT.call("get_display_description", output, "暂无描述"))
	_output_icon.texture = ITEM_COMPAT.call("get_display_icon", output, null) as Texture2D
	var max_quantity := int(_crafting.call("MaxCraftableQuantity", _selected_recipe)) if _crafting != null else 0
	if _quantity != null:
		_quantity.max_value = maxi(1, max_quantity)
		_quantity.editable = max_quantity > 0
	if _craft_button != null:
		_craft_button.disabled = max_quantity <= 0
	_ingredient_controller.refresh(_selected_recipe, int(_quantity.value) if _quantity != null else 1)

func _on_quantity_changed(_value: float) -> void:
	if _selected_recipe != null:
		_ingredient_controller.refresh(_selected_recipe, int(_quantity.value))

func _craft_selected() -> void:
	if _crafting == null or _selected_recipe == null:
		return
	var reason := int(_crafting.call("TryCraftWithReason", _selected_recipe, int(_quantity.value)))
	if _status != null:
		_status.text = "已合成" if reason == 0 else ("材料不足" if reason == 3 else "无法合成")
	_refresh_details()

func _on_inventory_changed() -> void:
	if not is_visible_in_tree():
		_needs_inventory_refresh = true
		return
	_recipe_controller.refresh()
	_refresh_details()
	_needs_inventory_refresh = false

func _on_visibility_changed() -> void:
	if visible and _needs_inventory_refresh:
		_recipe_controller.refresh()
		_refresh_details()
		_needs_inventory_refresh = false

func _show_item_tooltip(item: Resource, _slot: BaseButton = null) -> void:
	if item == null or _tooltip_panel == null:
		return
	_tooltip_panel.call("show_tooltip_now", String(ITEM_COMPAT.call("get_display_name", item, "")), String(ITEM_COMPAT.call("get_display_description", item, "暂无描述")))

func _hide_tooltip(_slot: BaseButton = null) -> void:
	if _tooltip_panel != null:
		_tooltip_panel.call("hide_tooltip")

func _resource(value: Variant, property_name: StringName) -> Resource:
	if not (value is Object):
		return null
	var result: Variant = (value as Object).get(String(property_name))
	return result as Resource if result is Resource else null

func _recipe_name(recipe: Variant) -> String:
	if not (recipe is Object):
		return ""
	var raw_name: Variant = (recipe as Object).get("RecipeName")
	return String(raw_name) if raw_name != null and not String(raw_name).is_empty() else ""

func _connect_signal(source: Node, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)

func _disconnect_signal(source: Node, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and source.is_connected(signal_name, callback):
		source.disconnect(signal_name, callback)

func _exit_tree() -> void:
	_disconnect_signal(_inventory, &"InventoryChanged", Callable(self, "_on_inventory_changed"))
	_disconnect_signal(_gameplay_port, &"CraftingToggleRequested", Callable(self, "_handle_toggle"))
	_disconnect_signal(_gameplay_port, &"CraftingOpenRequested", Callable(self, "_handle_open"))
	_disconnect_signal(_gameplay_port, &"CraftingNodeToggleRequested", Callable(self, "_handle_toggle"))
	_disconnect_signal(_gameplay_port, &"CraftingNodeOpenRequested", Callable(self, "_handle_open"))
