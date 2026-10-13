extends Node2D

## 描述容器协调直接 ScrollContainer 子节点，避免上层访问其内部标签。
## 参数通过公开文案接口传入，均无返回值。

## 替换描述。
## 参数 text：完整描述；返回值：无。
func set_description(text: String) -> void:
	get_node("ScrollContainer").call("set_description", text)

## 换行追加描述。
## 参数 text：额外描述；返回值：无。
func add_description(text: String) -> void:
	get_node("ScrollContainer").call("add_description", text)
