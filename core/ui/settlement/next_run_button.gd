extends Button

## 下一局按钮只向所属结算面板提交导航意图，无参数和返回值。

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	var panel: Node = owner
	if panel != null and panel.has_method("request_navigation"):
		panel.call("request_navigation", "next_run")
