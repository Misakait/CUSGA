## 点击模式卡牌操作栏。
## 该组件仅负责呈现“确定”和“取消”按钮，并以信号告知 CardManager；
## 卡牌消耗、目标判定与状态清理由 CardManager 统一处理。
extends HBoxContainer

## 当玩家确认施放当前选中卡牌时发出。
signal confirm_requested

## 当玩家放弃当前卡牌选择时发出。
signal cancel_requested

## 用于确认当前选择并请求施放的按钮。
## 该节点必须保留在本组件根节点下的固定路径；它的可用性由本操作栏整体可见性控制。
@onready var _confirm_button: Button = $ConfirmButton

## 用于清除当前选择而不消耗卡牌的按钮。
## 该节点必须保留在本组件根节点下的固定路径；它的可用性由本操作栏整体可见性控制。
@onready var _cancel_button: Button = $CancelButton

## 连接按钮信号并在没有选择卡牌时保持隐藏。
## @return void 无返回值。
func _ready() -> void:
	hide()
	_confirm_button.pressed.connect(_on_confirm_button_pressed)
	_cancel_button.pressed.connect(_on_cancel_button_pressed)

## 设置操作栏是否对当前点击模式选择可用。
## @param is_available 为 true 时显示确认/取消按钮，为 false 时隐藏它们。
## @return void 无返回值。
func set_actions_available(is_available: bool) -> void:
	visible = is_available

## 转发确认意图。
## @return void 无返回值。
func _on_confirm_button_pressed() -> void:
	confirm_requested.emit()

## 转发取消意图。
## @return void 无返回值。
func _on_cancel_button_pressed() -> void:
	cancel_requested.emit()
