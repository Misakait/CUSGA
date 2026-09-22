extends PopupPanel

## 属性加点界面。
##
## 弹窗只维护一份「待分配」计数，点「确认」时才通过 AttributeComponent 的既有接口
## TryAllocatePoint 一次性写入。属性点每级只发 3 点且不可再生，先累计后确认让玩家可以
## 反复调整再落笔；点「取消」或直接关闭窗口都会丢弃本次累计。
##
## 本视图不参与任何属性计算：值只从 GetEffectiveValue 读，成长只用于显示预计值，
## 写入只走 TryAllocatePoint。

## 可加点属性的类型整数值，顺序即界面行顺序；必须与 AttributeType 枚举保持一致。
const ALLOCATABLE_TYPES: Array[int] = [0, 1, 2, 3, 4]

## 可加点属性的显示名，顺序与 ALLOCATABLE_TYPES 一一对应。
## 刻意与摘要区使用同一套措辞，避免同一个属性在背包里出现两种叫法。
const ALLOCATABLE_NAMES: Array[String] = ["物攻", "物防", "法强", "法抗", "速度"]

## 承载五行属性的网格容器。
@onready var _rows_grid: GridContainer = %AllocationGrid
## 顶部可用点数文本。
@onready var _points_label: Label = %PointsLabel
## 确认写入按钮。
@onready var _confirm_button: Button = %ConfirmButton
## 放弃本次累计的按钮。
@onready var _cancel_button: Button = %CancelButton

## 当前绑定的属性组件；为空表示弹窗不可用。
var _attributes: Node = null

## 待分配点数：属性类型 → 累计值。
var _pending: Dictionary = {}

## 每行的值标签：属性类型 → Label。
var _value_labels: Dictionary = {}

## 每行的加号按钮：属性类型 → Button。
var _plus_buttons: Dictionary = {}

## 每行的减号按钮：属性类型 → Button。
var _minus_buttons: Dictionary = {}


## 生成属性行、连接按钮，并初始化为不可用状态。
## 返回值：无。
func _ready() -> void:
	_build_rows()
	# 三个连接都做成幂等：节点入树时引擎已调用过一次 Ready，测试夹具还会再显式补调一次，
	# 重复 connect 会直接报错并让整个弹窗失效。
	if not _confirm_button.pressed.is_connected(_on_confirm_pressed):
		_confirm_button.pressed.connect(_on_confirm_pressed)
	if not _cancel_button.pressed.is_connected(_on_cancel_pressed):
		_cancel_button.pressed.connect(_on_cancel_pressed)
	# 关闭窗口（含点遮罩、Esc、外部代码调用 hide）同样必须丢弃累计，
	# 否则下次打开会带着上一次的残留值。
	if not popup_hide.is_connected(_on_popup_hide):
		popup_hide.connect(_on_popup_hide)
	# 弹窗只在玩家点击「分配」时才出现：Window 系节点在不同实例化路径下的默认可见性并不
	# 一致（新建场景时编辑器就会写进 visible = true），这里无条件隐藏，避免它一进游戏
	# 就浮在屏幕中央。
	hide()
	_refresh()


## 绑定属性组件并刷新显示。
## 参数 attributes：提供 AvailablePoints、GetEffectiveValue、GetAttribute 与
## TryAllocatePoint 的属性组件；传 null 表示解除绑定。
## 返回值：无。
func Bind(attributes: Node) -> void:
	if _attributes == attributes:
		_refresh()
		return

	_attributes = attributes
	_pending.clear()
	_refresh()


## 绑定属性组件、清空累计并弹出。
##
## 每次打开都必须是全新的一次分配，因此这里**无条件**清空累计，而不是只依赖 Bind：
## 传入同一个组件时 Bind 会走「重复绑定」分支并保留状态，那会把上一次的残留累计带进
## 新的一次分配。
##
## 参数 attributes：目标属性组件。
## 返回值：无。
func OpenFor(attributes: Node) -> void:
	Bind(attributes)
	_pending.clear()
	_refresh()
	popup_centered()


## 生成五行属性行。
##
## 行结构完全一致，且每行都要持有值标签与加减按钮的引用；在场景里声明会产生 20 多个
## 节点与同样多次唯一名绑定，因此这里一次性生成，之后不再重建。
## 返回值：无。
func _build_rows() -> void:
	# 重复进入 Ready 时不得重复生成：否则行数翻倍，值标签的引用也会被第二批覆盖，
	# 表现为界面上的值永远停在初始占位符。
	if not _value_labels.is_empty():
		return

	for index: int in ALLOCATABLE_TYPES.size():
		var attribute_type: int = ALLOCATABLE_TYPES[index]

		var name_label := Label.new()
		name_label.text = ALLOCATABLE_NAMES[index]
		_rows_grid.add_child(name_label)

		var value_label := Label.new()
		value_label.text = "-"
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_rows_grid.add_child(value_label)
		_value_labels[attribute_type] = value_label

		var minus_button := Button.new()
		minus_button.text = "-1"
		minus_button.pressed.connect(_on_minus_pressed.bind(attribute_type))
		_rows_grid.add_child(minus_button)
		_minus_buttons[attribute_type] = minus_button

		var plus_button := Button.new()
		plus_button.text = "+1"
		plus_button.pressed.connect(_on_plus_pressed.bind(attribute_type))
		_rows_grid.add_child(plus_button)
		_plus_buttons[attribute_type] = plus_button


## 读取当前的可用属性点数。
## 返回值：属性组件报告的可用点数；组件缺失或没有该字段时返回 0。
func _available_points() -> int:
	if _attributes == null:
		return 0

	# 跨语言兜底：属性组件应当暴露公开字段 AvailablePoints，取值前先确认类型。
	var raw: Variant = _attributes.get("AvailablePoints")
	return int(raw) if (raw is int or raw is float) else 0


## 统计本次累计的总点数。
## 返回值：所有待分配项之和。
func _pending_total() -> int:
	var total: int = 0
	for attribute_type: int in _pending:
		total += int(_pending[attribute_type])

	return total


## 刷新可用点数、每行值与按钮的可用状态。
##
## 用 _rows_grid 而不是 is_node_ready() 作为就绪判断：_ready 执行期间 is_node_ready()
## 仍为 false，用它会把 _ready 里的首次刷新一并挡掉。
## 返回值：无。
func _refresh() -> void:
	if _rows_grid == null:
		return

	var available: int = _available_points()
	var remaining: int = available - _pending_total()
	var can_allocate: bool = _attributes != null and _attributes.has_method("TryAllocatePoint")

	# 显示"还能再分配多少"而不是组件里的点数总量：累计尚未写入组件，若显示总量，
	# 玩家点 +1 后数字纹丝不动，会误以为没生效。
	_points_label.text = "剩余可分配点数：%d" % maxi(remaining, 0)

	for index: int in ALLOCATABLE_TYPES.size():
		var attribute_type: int = ALLOCATABLE_TYPES[index]
		var pending: int = int(_pending.get(attribute_type, 0))

		var value_label: Label = _value_labels[attribute_type]
		value_label.text = _format_value_text(attribute_type, pending)

		# 减号只在真的累计过之后可用；加号在余额耗尽或组件不可用时禁用。
		(_minus_buttons[attribute_type] as Button).disabled = pending <= 0
		(_plus_buttons[attribute_type] as Button).disabled = not can_allocate or remaining <= 0

	_confirm_button.disabled = _pending_total() <= 0 or not can_allocate


## 生成某一行的值文本。
##
## 累计加点时属性组件尚未被改动，只显示当前值会让玩家以为「+1 没生效」，因此有待分配
## 点数时额外显示加点后的预计值；没有累计时保持最简的一列当前值。
##
## 参数 attribute_type：属性类型整数值。
## 参数 pending：该属性当前的待分配点数。
## 返回值：供值标签显示的文本。
func _format_value_text(attribute_type: int, pending: int) -> String:
	# 与摘要区保持同一种降级表现：没有属性组件时不显示 0，而是占位符。
	if _attributes == null:
		return "-"

	var current: float = _get_effective_value(attribute_type)
	var current_text: String = _format_number(current)
	if pending <= 0:
		return current_text

	var projected: float = current + pending * _get_growth_per_point(attribute_type)
	return "%s → %s" % [current_text, _format_number(projected)]


## 读取每投入 1 点的成长值。
##
## 只用于显示预计值，不参与写入：属性怎么算始终由属性组件决定。
## 参数 attribute_type：属性类型整数值。
## 返回值：每点成长值；组件缺少接口时返回 0。
func _get_growth_per_point(attribute_type: int) -> float:
	if _attributes == null or not _attributes.has_method("GetAttribute"):
		return 0.0

	var attribute: RefCounted = _attributes.call("GetAttribute", attribute_type)
	if attribute == null:
		return 0.0

	return float(attribute.get("GrowthPerPoint"))


## 通过稳定方法名读取属性组件的最终值。
## 参数 attribute_type：属性类型整数值。
## 返回值：最终属性值；组件缺少方法时返回 0。
func _get_effective_value(attribute_type: int) -> float:
	if _attributes == null or not _attributes.has_method("GetEffectiveValue"):
		return 0.0

	return float(_attributes.call("GetEffectiveValue", attribute_type))


## 把整数显示为无小数文本，其余按一位小数呈现。
## 参数 value：需要呈现的数值。
## 返回值：整数或一位小数文本。
func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))

	return "%.1f" % value


## 处理加号：累计 1 点。
## 参数 attribute_type：目标属性类型整数值。
## 返回值：无。
func _on_plus_pressed(attribute_type: int) -> void:
	# 上限以最新可用点数为准，避免累计超出余额后到确认时才失败。
	if _pending_total() >= _available_points():
		return

	_pending[attribute_type] = int(_pending.get(attribute_type, 0)) + 1
	_refresh()


## 处理减号：撤回 1 点累计。
## 参数 attribute_type：目标属性类型整数值。
## 返回值：无。
func _on_minus_pressed(attribute_type: int) -> void:
	var pending: int = int(_pending.get(attribute_type, 0))
	if pending <= 0:
		return

	_pending[attribute_type] = pending - 1
	_refresh()


## 处理确认：把累计一次性写入属性组件。
##
## 逐项调用 TryAllocatePoint 并传入该项的累计总数，任一项失败都停止写入并保持弹窗打开，
## 让玩家看见失败后的真实状态；全部成功才关闭弹窗。
## 返回值：无。
func _on_confirm_pressed() -> void:
	if _attributes == null or not _attributes.has_method("TryAllocatePoint"):
		return

	var pending_total: int = _pending_total()
	if pending_total <= 0:
		return

	# 打开期间点数可能被外部改变（例如又升了一级，或别处消费了点数），
	# 因此这里按最新余额重新校验，而不是沿用累计时的判断。
	if pending_total > _available_points():
		_refresh()
		return

	for attribute_type: int in _pending:
		var pending: int = int(_pending[attribute_type])
		if pending <= 0:
			continue

		if not bool(_attributes.call("TryAllocatePoint", attribute_type, pending)):
			_refresh()
			return

	_pending.clear()
	hide()


## 处理取消：放弃本次累计并关闭。
## 返回值：无。
func _on_cancel_pressed() -> void:
	_pending.clear()
	hide()


## 处理窗口关闭：与取消一致地丢弃累计。
## 返回值：无。
func _on_popup_hide() -> void:
	_pending.clear()
