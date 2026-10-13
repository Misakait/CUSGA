extends ScrollContainer

## 可滚动描述区域，管理直接 Descript 标签。
## 参数通过 set_description 或 add_description 传入；描述查询返回原文。

var _description: String = ""

## 替换整段描述，支持进入场景树之前调用。
## 参数 text：新描述；返回值：无。
func set_description(text: String) -> void:
	_description = text
	_refresh()

## 保留现有描述并换行追加；空文本不会产生空行。
## 参数 text：额外描述；返回值：无。
func add_description(text: String) -> void:
	if text.is_empty():
		return
	_description += ("\n" if not _description.is_empty() else "") + text
	_refresh()

## 读取显示原文，供未来开发和验证使用。
## 返回值：按追加顺序保留的完整描述。
func get_description() -> String:
	return _description

func _ready() -> void:
	_refresh()

func _refresh() -> void:
	if is_node_ready():
		(get_node("Descript") as Label).text = _description
