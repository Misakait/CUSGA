extends Node2D

const main_menu_scene = preload("res://scenes/main_menu_scenes/main_menu.tscn")

@export var inventory_grid: Node2D
@export var inventory_control: Control

## 进入仓库时由 SceneManager 调用。
## @remarks
## 判据必须是 is_node_ready() 而不是 is_inside_tree()：SceneManager 会对**初始场景**在它就绪之前
## 就调用 init()（见 core/autoloads/SceneManager.gd）。实测那一刻场景其实**已经进树**
## （is_inside_tree() 为 true），但 _ready 还没传播，子树中 InventoryControl 的 InventoryComponent
## 引用尚未建立，因此直接同步执行必然访问到 null——把 Warehouse.tscn 当初始场景直接运行即可复现。
## 未就绪时推迟到本帧空闲再执行；那时整棵子树已经就绪，效果与「场景切换进入」完全一致。
func init():
	if not is_node_ready():
		_apply_init.call_deferred()
		return

	_apply_init()


## 执行真正的仓库初始化。只有子树就绪后才会被调用。
func _apply_init():
	if inventory_control:
		if GlobalWarehouse:
			inventory_control.inventory.CopySlotsFrom(GlobalWarehouse)

		for i in ItemsControl.player_to_warehouse.size():
			var item_data = ItemsControl.player_to_warehouse[i]
			var item_cnt = ItemsControl.player_to_warehouse_cnt[i]
			inventory_control.add_item_by_item(item_data,item_cnt)
		ItemsControl.player_to_warehouse.clear()
		ItemsControl.player_to_warehouse_cnt.clear()

		if GlobalWarehouse:
			GlobalWarehouse.CopySlotsFrom(inventory_control.inventory)
		inventory_control.refresh_ui()
	else:
		print("inventory_control没有定义")

func exit():
	if inventory_control and GlobalWarehouse:
		GlobalWarehouse.CopySlotsFrom(inventory_control.inventory)

	if inventory_grid:
		ItemsControl.warehouse_to_player.clear()
		ItemsControl.warehouse_to_player_cnt.clear()

		for i in range(1,6):
			var usercard_path: NodePath = "usercard_%d" % i
			var grid = inventory_grid.get_node(usercard_path)
			if grid != null and grid.item_data != null :
				ItemsControl.warehouse_to_player.append(grid.item_data)
				ItemsControl.warehouse_to_player_cnt.append(grid.item_cnt)
	else:
		print("inventory_control没有定义")
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

# 局外商店入口。
# 走 SceneManager 的场景切换，因此本场景的 exit() 会先把界面上的库存副本写回 GlobalWarehouse，
# 商店再从这个权威库存读取，两边的数据不会错位。
func _on_shop_button_button_down() -> void:
	GlobalEventBus.scene_requested.emit("shop")
