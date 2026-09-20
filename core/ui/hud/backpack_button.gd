extends Button

## 背包按钮输入桥。
##
## 按钮只负责把点击转发给 GameplayPort，不持有背包界面或库存状态。

## GameplayPort 节点路径；场景必须提供，运行时不应动态修改。
@export var GameplayPortPath: NodePath

## 接收背包切换请求的 GameplayPort；允许迁移期连接 C# 或 GDScript 实现。
var _gameplay_port: Node = null


## 解析按钮点击所需的 GameplayPort。
## 返回值：无。
func _ready() -> void:
	if GameplayPortPath.is_empty():
		push_error("BackpackButton.GameplayPortPath 未设置")
		return
	_gameplay_port = get_node(GameplayPortPath)


## 把一次按钮激活转发为背包切换请求。
## 返回值：无。
func _pressed() -> void:
	_gameplay_port.call("RequestToggleInventory")
