extends RefCounted

## 四界面真实鼠标验证的运行期夹具；不发送输入，不代替真实点击验收。
## 调用方先保护存档并暂停磁盘写入，再在游戏进程调用 prepare。

const INVENTORY: GDScript = preload("res://entities/components/inventory_component.gd")
const EQUIPMENT: GDScript = preload("res://entities/components/equipment_component.gd")
const DECK: GDScript = preload("res://entities/components/battle_deck_component.gd")
const CRAFTING: GDScript = preload("res://entities/components/crafting_component.gd")
const ITEM: GDScript = preload("res://resources/item/item_data.gd")
const EQUIPMENT_ITEM: GDScript = preload("res://resources/item/equipment/equipment_data.gd")
const STACK: GDScript = preload("res://resources/item/item_stack.gd")
const INGREDIENT: GDScript = preload("res://resources/recipe/crafting_ingredient.gd")
const RECIPE: GDScript = preload("res://resources/recipe/crafting_recipe.gd")
const BOOK: GDScript = preload("res://resources/recipe/recipe_book_data.gd")
const HOST_PATH: NodePath = ^"/root/SlotDeselectFixture/UIHost"

## 创建独立组件和四个生产界面。参数 tree 为真实游戏 SceneTree；返回创建结果。
## 局外两界面仍读取 autoload；本方法不改金币和现有仓库/行囊内容。
static func prepare(tree: SceneTree) -> Dictionary:
	if tree == null or Engine.is_editor_hint():
		return {"error": "必须在游戏进程调用"}
	var previous: Node = tree.root.get_node_or_null("SlotDeselectFixture")
	if previous != null:
		previous.free()
	var layer := CanvasLayer.new()
	layer.name = "SlotDeselectFixture"
	layer.layer = 20
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child(layer)
	var host := Control.new()
	host.name = "UIHost"
	host.size = tree.root.get_visible_rect().size
	layer.add_child(host)
	var components := Node.new()
	components.name = "Components"
	host.add_child(components)
	for component_name: String in ["AttributeComponent", "TagComponent"]:
		var node := Node.new()
		node.name = component_name
		components.add_child(node)
	var inventory: Node = INVENTORY.new()
	inventory.name = "InventoryComponent"
	inventory.set("Capacity", 12)
	components.add_child(inventory)
	var equipment: Node = EQUIPMENT.new()
	equipment.name = "EquipmentComponent"
	components.add_child(equipment)
	var deck: Node = DECK.new()
	deck.name = "BattleDeckComponent"
	components.add_child(deck)
	var material: Resource = _item("probe_material", "验证材料")
	var output: Resource = _item("probe_output", "验证产物")
	inventory.call("AddItem", material, 12)
	inventory.call("AddItem", output, 3)
	deck.call("AddItem", load("res://resources/skill_cards/fire_magic_huoshu.tres"), 2)
	var equip_item: Resource = EQUIPMENT_ITEM.new()
	equip_item.set("CardId", &"probe_equipment")
	equip_item.set("CardName", "验证装备")
	var valid_slots: Array[int] = [0]
	equip_item.set("ValidSlots", valid_slots)
	var stack: RefCounted = STACK.new()
	stack.call("SetItem", equip_item, 1)
	# 无属性、无标签的装备不会向两个占位组件写数据，仍通过生产 Equip 建立权威状态。
	equipment.call("Equip", stack, 0)
	var ingredient: Resource = INGREDIENT.new()
	ingredient.set("RequiredItem", material)
	ingredient.set("Amount", 2)
	var recipe: Resource = RECIPE.new()
	recipe.set("RecipeName", "验证配方")
	var inputs: Array[Resource] = [ingredient]
	recipe.set("Inputs", inputs)
	recipe.set("OutputItem", output)
	recipe.set("OutputAmount", 1)
	var book: Resource = BOOK.new()
	var recipes: Array[Resource] = [recipe]
	book.set("Recipes", recipes)
	var crafting: Node = CRAFTING.new()
	crafting.name = "CraftingComponent"
	crafting.set("RecipeBook", book)
	components.add_child(crafting)
	var tooltip: Node = (load("res://scenes/ui_scenes/TooltipPanel.tscn") as PackedScene).instantiate()
	tooltip.name = "TooltipPanel"
	host.add_child(tooltip)
	var backpack: Control = (load("res://scenes/inventory/OpenBackpack.tscn") as PackedScene).instantiate() as Control
	backpack.name = "Backpack"
	backpack.set("TooltipPanelPath", ^"../TooltipPanel")
	host.add_child(backpack)
	backpack.call("_bind_player_inventory", inventory)
	backpack.call("_bind_equipment", equipment)
	backpack.call("_bind_battle_deck", deck)
	backpack.call("_bind_sections")
	var crafting_ui: Control = (load("res://scenes/crafting/CraftingUI.tscn") as PackedScene).instantiate() as Control
	crafting_ui.name = "Crafting"
	crafting_ui.set("TooltipPanelPath", ^"../TooltipPanel")
	host.add_child(crafting_ui)
	crafting_ui.call("Open", crafting)
	(crafting_ui.get_node("DetailSection/OutPutCount/SpinBox") as SpinBox).value = 2
	for pair: Array in [["Warehouse", "res://scenes/Warehouse/WarehouseNew.tscn"], \
		["Shop", "res://scenes/Shop/ShopNew.tscn"]]:
		var ui: Node = (load(pair[1]) as PackedScene).instantiate()
		ui.name = pair[0]
		host.add_child(ui)
	show_ui(tree, "Backpack")
	return {"ready": true, "host": String(host.get_path()), "material": material.get_instance_id()}

## 显示单个生产界面。参数 tree 为场景树、ui_name 为四界面之一；返回是否找到界面。
static func show_ui(tree: SceneTree, ui_name: String) -> bool:
	var host: Node = tree.root.get_node_or_null(HOST_PATH)
	if host == null:
		return false
	for name: String in ["Backpack", "Crafting", "Warehouse", "Shop"]:
		var ui: CanvasItem = host.get_node(name) as CanvasItem
		ui.visible = name == ui_name
	return host.has_node(ui_name)

## 读取真实格子与业务状态。参数 tree 为场景树；返回点击坐标、选中状态和库存快照。
## 调用方在真实左键、右键前后比较本结果；本方法不触发按钮或改选择。
static func read(tree: SceneTree) -> Dictionary:
	var host: Node = tree.root.get_node_or_null(HOST_PATH)
	if host == null:
		return {"error": "夹具尚未准备"}
	var result: Dictionary = {"slots": {}}
	var backpack: Node = host.get_node("Backpack")
	for pair: Array in [["inventory", "Item/ScrollContainer/SlotGrid"], \
		["equipment", "PlayerShow/ScrollContainer/EquipmentSlotGrid"], \
		["deck", "Deck/ScrollContainer/DeckSlotGrid"]]:
		result["slots"][pair[0]] = _slots(backpack.get_node(pair[1]).get_children(), true)
	var craft: Node = host.get_node("Crafting")
	result["slots"]["recipe"] = _slots(craft.get_node("RecipeSection/ScrollContainer/RecipeGrid").get_children(), false)
	var ingredients: Array = []
	for row: Node in craft.get_node("DetailSection/Ingredient/ScrollContainer/IngredientList").get_children():
		ingredients.append(row.get_child(0))
	result["slots"]["ingredient"] = _slots(ingredients, false)
	var ingredient_controller: RefCounted = craft.get("_ingredient_controller")
	var selected_ingredient: BaseButton = ingredient_controller.get("_selected_slot") as BaseButton
	result["ingredient_selected"] = selected_ingredient.get_instance_id() if is_instance_valid(selected_ingredient) else 0
	for ui_name: String in ["Warehouse", "Shop"]:
		var ui: Node = host.get_node(ui_name)
		result["slots"][ui_name + "_warehouse"] = _slots(ui.get_node("ItemSection/ScrollContainer/SlotGrid").get_children(), true)
		var path: String = "PackbackSection/ScrollContainer/SlotGrid" if ui_name == "Warehouse" else "Shop/ScrollContainer/SlotGrid"
		result["slots"][ui_name + "_other"] = _slots(ui.get_node(path).get_children(), true)
		result[ui_name + "_tooltip"] = (ui.get_node("TooltipLayer/TooltipPanel") as CanvasItem).visible
	result["hover_tooltip"] = (host.get_node("TooltipPanel") as CanvasItem).visible
	result["backpack_tooltip"] = (backpack.get("_selected_tooltip_panel") as CanvasItem).visible
	result["recipe"] = (craft.get("_selected_recipe") as Resource).get_instance_id()
	result["quantity"] = (craft.get_node("DetailSection/OutPutCount/SpinBox") as SpinBox).value
	result["craft_disabled"] = (craft.get_node("DetailSection/OutPutCount/Craft/CraftButton") as Button).disabled
	var shop: Node = host.get_node("Shop")
	var buy: RefCounted = shop.get("_buy")
	var buy_item: Resource = buy.get("_item") as Resource
	var sell: RefCounted = shop.get("_sell")
	result["buy_item"] = buy_item.get_instance_id() if buy_item != null else 0
	result["buy_quantity"] = (shop.get_node("Shop/BuyArea/BuyCount/SpinBox") as SpinBox).value
	result["sell_source"] = sell.call("source")
	result["sell_quantity"] = (shop.get_node("Shop/SellArea/SpinBox") as SpinBox).value
	result["inventory"] = _inventory_snapshot(host.get_node("Components/InventoryComponent"))
	result["deck"] = _inventory_snapshot(host.get_node("Components/BattleDeckComponent"))
	var equipped: Dictionary = host.get_node("Components/EquipmentComponent").get("_equipped_items")
	result["equipment"] = equipped.size()
	result["gold"] = tree.root.get_node("PlayerWallet").get("Gold")
	result["warehouse"] = _inventory_snapshot(tree.root.get_node("GlobalWarehouse"))
	result["carry"] = tree.root.get_node("ItemsControl").call("capture_save_data")
	return result

static func _slots(nodes: Array, custom_selected: bool) -> Array:
	var result: Array = []
	for value: Variant in nodes:
		var slot: BaseButton = value as BaseButton
		if slot == null:
			continue
		var center: Vector2 = slot.get_global_transform_with_canvas() * (slot.size * 0.5)
		result.append({"id": slot.get_instance_id(), "position": [center.x, center.y], \
			"selected": bool(slot.call("is_selected")) if custom_selected else slot.button_pressed, \
			"disabled": slot.disabled})
	return result

static func _inventory_snapshot(inventory: Node) -> Array:
	var result: Array = []
	var slots: Array = inventory.get("Slots")
	for stack: Variant in slots:
		var item: Resource = stack.get("Item") as Resource
		result.append([item.get_instance_id() if item != null else 0, int(stack.get("Amount"))])
	return result

static func _item(id: String, title: String) -> Resource:
	var item: Resource = ITEM.new()
	item.set("CardId", StringName(id))
	item.set("CardName", title)
	item.set("Description", "鼠标取消选中验证")
	item.set("MaxStackSize", 99)
	return item
