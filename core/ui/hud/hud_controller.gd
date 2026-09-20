extends Control

## HUD 输入桥。
##
## 负责把背包与合成快捷键转发给 GameplayPort，并保持输入在请求发出后才被消费。

## GameplayPort 节点路径；场景必须提供，运行时不应动态修改。
@export var GameplayPortPath: NodePath
## 背包按钮节点路径；仅用于保持原场景依赖校验，不在此重复连接点击事件。
@export var BackpackButtonPath: NodePath

## 合成界面的输入动作名。
const TOGGLE_CRAFTING_ACTION: StringName = &"toggle_crafting"
## 背包界面的输入动作名。
const TOGGLE_INVENTORY_ACTION: StringName = &"toggle_inventory"

## 接收 HUD 请求的 GameplayPort；允许迁移期连接 C# 或 GDScript 实现。
var _gameplay_port: Node = null
## 已校验的背包按钮引用；按钮自身脚本负责点击转发。
var _backpack_button: BaseButton = null


## 解析场景依赖，并保持原实现对两个导出路径的必需约束。
## 返回值：无。
func _ready() -> void:
	if GameplayPortPath.is_empty():
		push_error("HUDController.GameplayPortPath 未设置")
		return
	if BackpackButtonPath.is_empty():
		push_error("HUDController.BackpackButtonPath 未设置")
		return

	_gameplay_port = get_node(GameplayPortPath)
	_backpack_button = get_node(BackpackButtonPath) as BaseButton
	if _backpack_button == null:
		push_error("HUDController.BackpackButtonPath 未指向 BaseButton")


## 在普通输入阶段处理合成快捷键。
## 参数 event：Godot 当前分发的输入事件。
## 返回值：无。
func _input(event: InputEvent) -> void:
	if _is_action_pressed_once(event, TOGGLE_CRAFTING_ACTION):
		_gameplay_port.call("RequestToggleCrafting")
		get_viewport().set_input_as_handled()


## 在未处理输入阶段处理背包快捷键，避免抢占更靠前的 UI 输入。
## 参数 event：尚未被其他节点消费的输入事件。
## 返回值：无。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_INVENTORY_ACTION):
		_gameplay_port.call("RequestToggleInventory")
		get_viewport().set_input_as_handled()


## 判断动作是否为一次非键盘重复的按下。
## 参数 event：待检查的输入事件。
## 参数 action：InputMap 中的动作名。
## 返回值：动作本次首次按下时返回 true，键盘 echo 或未按下时返回 false。
func _is_action_pressed_once(event: InputEvent, action: StringName) -> bool:
	if not event.is_action_pressed(action):
		return false
	return not (event is InputEventKey) or not (event as InputEventKey).echo
