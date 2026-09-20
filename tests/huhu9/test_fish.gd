extends Button

## 仓库场景中的手动调试按钮，用于向全局仓库加入一个指定物品。
##
## 该脚本只服务编辑器内的“测试：加鱼”入口，不参与正式发放流程；物品以通用
## Resource 传递，从而同时兼容 GDScript 普通物品和保留的 C# 派生物品。

## 点击按钮时加入仓库的物品资源。
@export var test_item: Resource


## 节点就绪时绑定按钮事件，避免场景文件额外保存信号连接。
func _ready() -> void:
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


## 把一个测试物品加入全局仓库，并刷新仓库场景显示。
func _on_pressed() -> void:
	if test_item == null:
		push_warning("Warehouse test button: 未配置 test_item。")
		return

	var warehouse := get_node_or_null("/root/GlobalWarehouse")
	if warehouse == null or not warehouse.has_method("AddItem"):
		push_error("Warehouse test button: GlobalWarehouse 不可用。")
		return

	var leftover: int = int(warehouse.call("AddItem", test_item, 1))
	if leftover > 0:
		push_warning("Warehouse test button: 仓库已满，测试物品未加入。")
		return

	var controller := get_parent()
	if controller != null and controller.has_method("_refresh_all"):
		controller.call("_refresh_all")
