extends PanelContainer

## 刻印面板负责展示与交互；抽取规则和库存修改由独立服务负责。
## 五行展示顺序及其既有元素枚举值。
const ELEMENTS: Array[int] = [1, 4, 3, 5, 2]
## 五行显示名称。
const NAMES: Array[String] = ["木", "土", "水", "火", "金"]
## 各属性卡胚路径，与显示顺序一致。
const EMBRYOS: Array[String] = ["wood", "earth", "water", "fire", "metal"]
## 无状态的刻印业务服务。
const SERVICE: GDScript = preload("res://core/imprint/imprint_service.gd")

## 当前玩家库存。
var _inventory: Node
## 返回背包时需要恢复的原面板。
var _backpack: Control
## 当前选中的属性索引。
var _selected: int = 0
## 材料数量显示。
var _balance: Label
## 抽取结果显示。
var _result: Label

## 构造面板并绑定库存。
## 参数 inventory：玩家库存；backpack：返回时显示的背包；返回值：无。
func setup(inventory: Node, backpack: Control) -> void:
	_inventory = inventory
	_backpack = backpack
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(270, 120)
	custom_minimum_size = Vector2(760, 480)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	add_child(box)
	var title := Label.new()
	title.text = "刻印"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	box.add_child(title)
	_balance = Label.new()
	box.add_child(_balance)
	var tabs := HBoxContainer.new()
	box.add_child(tabs)
	for index in NAMES.size():
		var button := Button.new()
		button.text = NAMES[index]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_select.bind(index))
		tabs.add_child(button)
	_result = Label.new()
	_result.custom_minimum_size.y = 210
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_result)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	for count in [1, 10]:
		var button := Button.new()
		button.text = "单抽" if count == 1 else "十连"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_perform_draw.bind(count))
		actions.add_child(button)
	var back := Button.new()
	back.text = "返回背包"
	back.pressed.connect(_close)
	box.add_child(back)
	_select(0)

func _resource(index: int) -> Resource:
	return load("res://items/imprint/%s_embryo.tres" % EMBRYOS[index])

func _universal() -> Resource:
	return load("res://items/imprint/universal_embryo.tres")

func _select(index: int) -> void:
	_selected = index
	_result.text = "%s属性刻印" % NAMES[index]
	_refresh()

func _refresh() -> void:
	_balance.text = "%s卡胚：%d    通用卡胚：%d" % [NAMES[_selected], int(_inventory.call("ItemCnt", _resource(_selected))), int(_inventory.call("ItemCnt", _universal()))]

func _perform_draw(count: int) -> void:
	var outcome: Dictionary = SERVICE.new().draw(_inventory, ELEMENTS[_selected], _resource(_selected), _universal(), count)
	var names: Array[String] = []
	for card in outcome.cards:
		names.append("%s（%d星）" % [card.get("CardName"), card.get("StarLevel")])
	_result.text = String(outcome.message) + ("\n" + "、".join(names) if not names.is_empty() else "")
	_refresh()

func _close() -> void:
	if is_instance_valid(_backpack):
		_backpack.show()
	queue_free()
