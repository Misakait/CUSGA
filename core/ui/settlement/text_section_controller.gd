extends Node2D

## 时间或结局的小区域，只管理其直接 Label 子节点。
## 参数通过 set_text 传入，接口不返回数据。

var _text: String = ""

## 更新本区域文字，支持进入场景树之前调用。
## 参数 text：要显示的完整文字；返回值：无。
func set_text(text: String) -> void:
	_text = text
	if is_node_ready():
		(get_node("Label") as Label).text = _text

func _ready() -> void:
	(get_node("Label") as Label).text = _text
