extends Node2D

const main_menu_scene = preload("res://scenes/main_menu_scenes/main_menu.tscn")

@export var inventory_grid: Node2D
@export var inventory_control: Control

# 获取可以被带入游戏的card
# 使用 inventory_grid[index].item_data 来获取item
# 使用 inventory_grid[index].item_cnt 来获取其数量
func get_user_card() -> Array:
	return inventory_grid.get_user_card()

# 往仓库 添加物品，移除物品,一键排序
func add_item_by_item(item: ItemData, cnt: int):
	inventory_control.add_item_by_item(item, cnt)

func add_item_by_name(cardid: StringName, cnt: int):
	inventory_control.add_item_by_name(cardid, cnt)

func remove_item_by_item(item: ItemData, cnt: int):
	inventory_control.add_item_by_item(item, cnt)

func remove_item_by_name(cardid: StringName, cnt: int):
	inventory_control.remove_item_by_name(cardid, cnt)

func sort_by_card_name():
	inventory_control.sort_by_card_name()


func _on_exit_button_button_down() -> void:
	GlobalEventBus.scene_requested.emit("main_menu")
