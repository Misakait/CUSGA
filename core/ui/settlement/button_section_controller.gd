extends Node2D

## 按钮区域管理导航门禁和保存失败反馈，不负责结算或发奖。
## 参数通过 set_navigation_state 传入，重试通过信号通知根控制器。

## 玩家请求重新保存；无参数。
signal retry_requested

func _ready() -> void:
	(get_node("RetryButton") as Button).pressed.connect(_on_retry_pressed)

## 更新按钮状态和错误提示。
## 参数 pending：导航正在处理；error：经理报告的保存或导航错误；返回值：无。
func set_navigation_state(pending: bool, error: String) -> void:
	(get_node("BackToMenu/Button") as Button).disabled = pending or not error.is_empty()
	(get_node("BackToMenu2/Button") as Button).disabled = pending or not error.is_empty()
	var retry: Button = get_node("RetryButton") as Button
	retry.visible = not error.is_empty()
	retry.disabled = pending
	var status: Label = get_node("Status") as Label
	status.visible = not error.is_empty()
	status.text = error + "；收获仍在内存中。" if not error.is_empty() else ""

func _on_retry_pressed() -> void:
	retry_requested.emit()
