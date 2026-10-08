extends RefCounted

## 配方列表控制器。只管理配方格子的创建、排序和可合成外观。

const ITEM_SLOT_SCENE: PackedScene = preload("res://scenes/ui/item_slot1.tscn")
const ITEM_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

signal recipe_selected(recipe: Variant, slot: BaseButton)
signal item_hovered(item: Resource, slot: BaseButton)
signal item_left(slot: BaseButton)

var _container: GridContainer = null
var _crafting: Node = null
var _slots_by_recipe: Dictionary = {}
var _recipes: Array = []

## 绑定配方数据与格子容器。
## @param container RecipeSection 的 ScrollContainer 内的 GridContainer。
## @param crafting 提供 Recipes 与 MaxCraftableQuantity 的合成组件。
## @return 无。
func bind(container: GridContainer, crafting: Node) -> void:
	_container = container
	_crafting = crafting
	refresh()

## 按可合成优先顺序刷新格子，并复用相同配方的现有节点。
## @return 无。
func refresh() -> void:
	if _container == null:
		return
	_recipes = _sorted_recipes()
	for old_recipe: Variant in _slots_by_recipe.keys():
		if not _recipes.has(old_recipe):
			var old_slot: BaseButton = _slots_by_recipe[old_recipe]
			old_slot.queue_free()
			_slots_by_recipe.erase(old_recipe)
	for index: int in range(_recipes.size()):
		var recipe: Variant = _recipes[index]
		var slot: BaseButton = _slots_by_recipe.get(recipe)
		if slot == null:
			slot = _instantiate_slot()
			if slot == null:
				continue
			_container.add_child(slot)
			_slots_by_recipe[recipe] = slot
			slot.pressed.connect(_on_slot_pressed.bind(recipe, slot))
			slot.mouse_entered.connect(_on_slot_entered.bind(recipe, slot))
			slot.mouse_exited.connect(_on_slot_exited.bind(slot))
		_configure_slot(slot, recipe)
		_container.move_child(slot, index)

## 读取排序后的配方，用于首次选择和数据刷新。
## @return 可合成配方在前的资源数组。
func get_recipes() -> Array:
	return _recipes.duplicate()

## 设置列表中唯一的当前选择。
## @param selected_recipe 被选中的配方资源。
## @return 无。
func set_selected(selected_recipe: Variant) -> void:
	for recipe: Variant in _slots_by_recipe:
		var slot: BaseButton = _slots_by_recipe[recipe]
		slot.button_pressed = recipe == selected_recipe

func _sorted_recipes() -> Array:
	var craftable: Array = []
	var unavailable: Array = []
	if _crafting == null:
		return []
	var raw: Variant = _crafting.get("Recipes")
	if not (raw is Array):
		return []
	for recipe: Variant in raw:
		if recipe == null:
			continue
		if _max_craftable(recipe) > 0:
			craftable.append(recipe)
		else:
			unavailable.append(recipe)
	craftable.append_array(unavailable)
	return craftable

func _configure_slot(slot: BaseButton, recipe: Variant) -> void:
	slot.toggle_mode = true
	slot.custom_minimum_size = Vector2(72, 72)
	slot.modulate = Color.WHITE if _max_craftable(recipe) > 0 else Color(0.48, 0.48, 0.48)
	var output: Resource = _resource(recipe, "OutputItem")
	slot.tooltip_text = _recipe_name(recipe)
	var icon := slot.get_node_or_null("Icon") as TextureRect
	if icon != null:
		icon.texture = ITEM_COMPAT.call("get_display_icon", output, null) as Texture2D
	var name_label := slot.get_node_or_null("NameLabel") as Label
	if name_label != null:
		name_label.text = _recipe_name(recipe)
	var count_label := slot.get_node_or_null("CountLabel") as Label
	if count_label != null:
		count_label.hide()

func _instantiate_slot() -> BaseButton:
	# item_slot1 的根节点可以是 Button 或 TextureButton；统一收敛到 BaseButton，避免依赖具体按钮子类。
	var instance: Node = ITEM_SLOT_SCENE.instantiate()
	if not is_instance_valid(instance) or not (instance is BaseButton):
		if is_instance_valid(instance):
			instance.queue_free()
		push_error("配方格子场景的根节点必须继承 BaseButton。")
		return null
	return instance as BaseButton

func _max_craftable(recipe: Variant) -> int:
	return int(_crafting.call("MaxCraftableQuantity", recipe)) if _crafting != null and _crafting.has_method("MaxCraftableQuantity") else 0

func _on_slot_pressed(recipe: Variant, slot: BaseButton) -> void:
	recipe_selected.emit(recipe, slot)

func _on_slot_entered(recipe: Variant, slot: BaseButton) -> void:
	var output: Resource = _resource(recipe, "OutputItem")
	if output != null:
		item_hovered.emit(output, slot)

func _on_slot_exited(slot: BaseButton) -> void:
	item_left.emit(slot)

func _resource(value: Variant, property_name: StringName) -> Resource:
	if not (value is Object):
		return null
	var result: Variant = (value as Object).get(String(property_name))
	return result as Resource if result is Resource else null

func _recipe_name(recipe: Variant) -> String:
	if not (recipe is Object):
		return ""
	var raw_name: Variant = (recipe as Object).get("RecipeName")
	var recipe_name: String = "" if raw_name == null else String(raw_name)
	if not recipe_name.strip_edges().is_empty():
		return recipe_name
	return String(ITEM_COMPAT.call("get_display_name", _resource(recipe, "OutputItem"), ""))
