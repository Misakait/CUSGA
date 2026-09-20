extends RefCounted

## 物品悬停提示框的跨语言展示适配器。
##
## Presenter 只把 ItemStack 或 ItemData 转为标题和描述，再调用现有 TooltipPanel；
## 它不持有库存状态，也不改变物品或堆叠，因此新旧语言对象继续保持原始引用身份。

const ITEM_DATA_COMPAT: GDScript = preload("res://resources/item/item_data_compat.gd")

static var _empty_presenter: RefCounted = null

var _tooltip_panel: Node = null


## 创建绑定到指定提示框节点的 Presenter。
## 参数 tooltip_panel：实现 show_tooltip_now 与 hide_tooltip 的现有提示框；允许为空。
func _init(tooltip_panel: Node = null) -> void:
	_tooltip_panel = tooltip_panel


## 返回共享的空 Presenter，供尚未绑定提示框的 UI 安全调用。
## 返回值：绑定空节点且可重复复用的 Presenter。
static func Empty() -> RefCounted:
	if _empty_presenter == null:
		var presenter_script: GDScript = load("res://core/ui/item_tooltip_presenter.gd") as GDScript
		_empty_presenter = presenter_script.new()
	return _empty_presenter


## 立即显示堆叠或物品的名称与描述；空值、空堆叠或无效物品会改为隐藏。
## 参数 value：旧 C# 或并行 GDScript ItemStack，亦可直接传入对应 ItemData Resource。
## 返回值：无。
func Show(value: Variant) -> void:
	var item: Variant = _resolve_item(value)
	if item == null or not bool(ITEM_DATA_COMPAT.call("is_item_resource", item)):
		Hide()
		return
	if not _has_tooltip_panel():
		return

	_tooltip_panel.call("show_tooltip_now", _get_item_name(item), _get_item_description(item))


## 隐藏当前提示框；未绑定或已经释放的节点保持无操作。
## 返回值：无。
func Hide() -> void:
	if _has_tooltip_panel():
		_tooltip_panel.call("hide_tooltip")


## 从直接 ItemData 或 ItemStack 中解析原始物品 Resource。
func _resolve_item(value: Variant) -> Variant:
	if value is Resource:
		return value
	if not (value is Object):
		return null

	var stack: Object = value as Object
	# C# 的非导出公共属性可由 Object.get 读取，但不会完整出现在 get_property_list；
	# 因此先用两种实现共同保留的行为协议识别 ItemStack，再读取稳定属性。
	if not stack.has_method("Clear") or not stack.has_method("SetItem") or not stack.has_method("Duplicate"):
		return null
	var is_empty: Variant = stack.get("IsEmpty")
	if is_empty == null or bool(is_empty):
		return null
	return stack.get("Item")


## 读取展示名称，并精确保留 C# 对纯空白 DisplayName 回退到 CardName 的规则。
func _get_item_name(item: Variant) -> String:
	var display_name: String = String(ITEM_DATA_COMPAT.call("get_display_name", item, ""))
	if not display_name.strip_edges().is_empty():
		return display_name
	var card_name: Variant = (item as Object).get("CardName")
	return "" if card_name == null else String(card_name)


## 读取展示描述，并保留空白描述显示“暂无描述”的既有文案。
func _get_item_description(item: Variant) -> String:
	var description: String = String(ITEM_DATA_COMPAT.call("get_display_description", item, ""))
	return "暂无描述" if description.strip_edges().is_empty() else description


## 判断提示框节点仍可由 Godot 调用。
func _has_tooltip_panel() -> bool:
	return _tooltip_panel != null and is_instance_valid(_tooltip_panel)
