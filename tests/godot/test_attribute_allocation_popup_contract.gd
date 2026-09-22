@tool
extends McpTestSuite

## AttributeAllocationPopup 加点弹窗的行为契约套件。
##
## 套件聚焦「累计不写入、确认才写入」这条核心不变量：点加号之后，属性组件的调用记录与
## 可用点数必须纹丝不动，只有确认才让它们整体变化。

## 待验证的加点弹窗脚本。
const ALLOCATION_POPUP_SCRIPT: GDScript = preload("res://core/ui/attribute_allocation_popup.gd")
## 生产加点弹窗场景路径，用于锁定实际脚本引用与唯一名契约。
const ALLOCATION_POPUP_SCENE_PATH: String = "res://scenes/inventory/AttributeAllocationPopup.tscn"
## 生产属性值载体脚本，使替身的 GetAttribute 返回真实字段结构。
const ATTRIBUTE_VALUE_SCRIPT: GDScript = preload("res://core/attributes/attribute_value.gd")

## 弹窗内每行占用的列数：名称、值、减号、加号。
const COLUMNS_PER_ROW: int = 4
## 行内各列的偏移量。
const COLUMN_NAME: int = 0
## 行内值标签的列偏移。
const COLUMN_VALUE: int = 1
## 行内减号按钮的列偏移。
const COLUMN_MINUS: int = 2
## 行内加号按钮的列偏移。
const COLUMN_PLUS: int = 3

## 可加点属性的类型整数值顺序，与生产弹窗保持一致。
const ALLOCATABLE_TYPES: Array[int] = [0, 1, 2, 3, 4]


## 提供加点弹窗所需接口、并真实记录写入的属性组件替身。
##
## GetAttribute 返回生产用的 attribute_value 实例，因此 GrowthPerPoint 的字段名一旦被改名，
## 本套件会立刻失败，而不是静默把成长当成 0。
class FakeAttributeComponent extends Node:
	## 任一最终属性变化时携带不透明变更对象。
	signal AttributeChanged(change_event)
	## 可用属性点变化时携带最新点数。
	signal AvailablePointsChanged(available_points)

	## 可用属性点，与生产组件同为公开字段。
	var AvailablePoints: int = 0
	## 以属性类型索引的基础值。
	var base_values: Dictionary = {}
	## 以属性类型索引的每点成长值。
	var growth_per_point: Dictionary = {}
	## 以属性类型索引的已投入点数。
	var allocated_points: Dictionary = {}
	## 每次 TryAllocatePoint 的调用记录，元素为 {type, amount}。
	var allocate_calls: Array = []
	## 置为 true 后 TryAllocatePoint 一律失败，用于覆盖写入被拒绝的路径。
	var refuse_allocation: bool = false

	## 读取指定属性的最终值。
	## 参数 attribute_type：属性类型整数值。
	## 返回值：基础值加上已投入点数带来的成长。
	func GetEffectiveValue(attribute_type: int) -> float:
		return (
			float(base_values.get(attribute_type, 0.0))
			+ float(allocated_points.get(attribute_type, 0))
			* float(growth_per_point.get(attribute_type, 0.0))
		)


	## 返回生产使用的属性值载体。
	## 参数 attribute_type：属性类型整数值。
	## 返回值：已按当前配置初始化的 attribute_value 实例。
	func GetAttribute(attribute_type: int) -> RefCounted:
		var attribute: RefCounted = ATTRIBUTE_VALUE_SCRIPT.new()
		attribute.call(
			"Initialize",
			attribute_type,
			"属性%d" % attribute_type,
			float(base_values.get(attribute_type, 0.0)),
			float(growth_per_point.get(attribute_type, 0.0))
		)
		return attribute


	## 真实的加点写入：记调用、扣点数、记成长并发出两个信号。
	## 参数 target_attribute_type：目标属性类型整数值。
	## 参数 amount：投入点数。
	## 返回值：成功投入返回 true。
	func TryAllocatePoint(target_attribute_type: int, amount: int) -> bool:
		allocate_calls.append({"type": target_attribute_type, "amount": amount})
		if refuse_allocation or amount <= 0 or AvailablePoints < amount:
			return false

		AvailablePoints -= amount
		allocated_points[target_attribute_type] = (
			int(allocated_points.get(target_attribute_type, 0)) + amount
		)
		AvailablePointsChanged.emit(AvailablePoints)
		AttributeChanged.emit(null)
		return true


	## 直接改变可用点数并按生产组件的行为发出信号。
	## 参数 available_points：新的可用点数。
	## 返回值：无。
	func set_available_points(available_points: int) -> void:
		AvailablePoints = available_points
		AvailablePointsChanged.emit(AvailablePoints)


## 返回套件名称，供 GodotAI 精确筛选本批测试。
## 返回值：固定套件名。
func suite_name() -> String:
	return "attribute_allocation_popup_contract"


## 验证生产弹窗场景挂载 GDScript 实现且保留全部唯一名契约。
## 返回值：无。
func test_production_popup_scene_uses_gdscript_and_unique_names() -> void:
	## 强制从磁盘重新加载生产场景，避免缓存干扰。
	var packed_scene := ResourceLoader.load(
		ALLOCATION_POPUP_SCENE_PATH,
		"PackedScene",
		ResourceLoader.CACHE_MODE_REPLACE
	) as PackedScene
	assert_true(packed_scene != null, "加点弹窗生产场景必须能够加载。")
	if packed_scene == null:
		return

	## 未进入场景树的生产弹窗实例。
	var popup := packed_scene.instantiate() as PopupPanel
	assert_true(popup != null, "加点弹窗场景根节点必须是 PopupPanel。")
	if popup == null:
		return

	## 生产根节点当前实际挂载的脚本。
	var script := popup.get_script() as Script
	assert_true(script != null, "加点弹窗根节点必须保留脚本。")
	if script != null:
		assert_eq(
			script.resource_path,
			"res://core/ui/attribute_allocation_popup.gd",
			"生产场景必须使用 GDScript 加点弹窗。"
		)

	# 四个唯一名是弹窗与外部唯一的定位契约。
	for unique_name: String in ["PointsLabel", "AllocationGrid", "ConfirmButton", "CancelButton"]:
		assert_true(
			popup.get_node_or_null("%%%s" % unique_name) != null,
			"生产弹窗必须保留唯一名节点 %s。" % unique_name
		)

	# 网格列数决定每行「名称、值、减号、加号」的排布，必须由生产场景固定下来。
	var grid := popup.get_node("%AllocationGrid") as GridContainer
	assert_eq(grid.columns, COLUMNS_PER_ROW, "生产弹窗的加点网格必须固定为四列。")

	# 生产场景不得把弹窗写成默认可见，否则它一进游戏就会浮在屏幕上。
	assert_false(
		FileAccess.get_file_as_string(ALLOCATION_POPUP_SCENE_PATH).contains("visible = true"),
		"生产弹窗场景不得序列化 visible = true。"
	)

	popup.free()


## 验证弹窗默认隐藏，只有 OpenFor 才让它出现，且重新打开不残留上次累计。
## 返回值：无。
func test_popup_stays_hidden_until_opened() -> void:
	var popup := _new_popup()
	if popup == null:
		return
	var attributes := _new_attributes()
	attributes.AvailablePoints = 2

	assert_false(popup.visible, "刚构造出来的加点弹窗必须保持隐藏，不得一进游戏就浮在屏幕上。")

	popup.call("Bind", attributes)
	assert_false(popup.visible, "仅绑定属性组件不得让弹窗显示出来。")

	popup.call("OpenFor", attributes)
	assert_true(popup.visible, "OpenFor 必须真正打开弹窗。")

	# 关掉前先累计一点，验证重新打开是从零开始。
	var grid := popup.get_node("%AllocationGrid") as GridContainer
	(_cell(grid, 0, COLUMN_PLUS) as Button).pressed.emit()
	popup.call("OpenFor", attributes)
	assert_eq(
		_value_text(grid, 0),
		"10",
		"重新打开必须清空上一次的残留累计。"
	)

	popup.hide()
	_dispose_popup(popup)


## 验证弹窗按要求生成五行四列，并显示各属性当前值。
## 返回值：无。
func test_rows_cover_five_allocatable_attributes() -> void:
	var popup := _new_popup()
	if popup == null:
		return
	var attributes := _new_attributes()
	attributes.AvailablePoints = 0
	popup.call("Bind", attributes)

	## 承载属性行的生产网格。
	var grid := popup.get_node("%AllocationGrid") as GridContainer
	assert_eq(
		grid.get_child_count(),
		ALLOCATABLE_TYPES.size() * COLUMNS_PER_ROW,
		"五项属性必须各生成一行。"
	)

	for index: int in ALLOCATABLE_TYPES.size():
		assert_eq(
			_cell(grid, index, COLUMN_NAME).text,
			["物攻", "物防", "法强", "法抗", "速度"][index],
			"第 %d 行必须显示对应属性名。" % index
		)
	assert_eq(_value_text(grid, 0), "10", "物攻必须显示属性组件报告的当前值。")
	assert_eq(_value_text(grid, 4), "50", "速度必须显示属性组件报告的当前值。")

	_dispose_popup(popup)


## 验证点加号只动弹窗内部计数，绝不触碰属性组件。
## 返回值：无。
func test_plus_accumulates_without_touching_component() -> void:
	var popup := _new_popup()
	if popup == null:
		return
	var attributes := _new_attributes()
	attributes.AvailablePoints = 5
	popup.call("Bind", attributes)
	var grid := popup.get_node("%AllocationGrid") as GridContainer

	assert_eq(_value_text(grid, 0), "10", "未累计时值标签必须只显示当前值。")

	(_cell(grid, 0, COLUMN_PLUS) as Button).pressed.emit()

	# 核心不变量：这一步只允许改弹窗自己的计数。
	assert_eq(attributes.allocate_calls.size(), 0, "点加号不得调用 TryAllocatePoint。")
	assert_eq(attributes.AvailablePoints, 5, "点加号不得扣减可用点数。")
	assert_eq(int(attributes.GetEffectiveValue(0)), 10, "点加号不得改变属性值。")
	assert_eq(_value_text(grid, 0), "10 → 12", "累计后必须显示加点后的预计值。")
	assert_true(
		(_cell(grid, 0, COLUMN_MINUS) as Button).disabled == false,
		"累计过之后减号必须可用，玩家才能反悔。"
	)
	# 剩余可分配点数必须实时跟随累计量，而不是等确认之后才动。
	assert_eq(
		(popup.get_node("%PointsLabel") as Label).text,
		"剩余可分配点数：4",
		"累计 1 点后剩余可分配点数必须立即从 5 变成 4。"
	)

	_dispose_popup(popup)


## 验证累计总量被可用点数封顶，且达到上限后加号禁用。
## 返回值：无。
func test_plus_is_capped_by_available_points() -> void:
	var popup := _new_popup()
	if popup == null:
		return
	var attributes := _new_attributes()
	attributes.AvailablePoints = 2
	popup.call("Bind", attributes)
	var grid := popup.get_node("%AllocationGrid") as GridContainer

	for _round: int in 3:
		(_cell(grid, 0, COLUMN_PLUS) as Button).pressed.emit()

	assert_eq(_value_text(grid, 0), "10 → 14", "累计必须被可用点数封顶在 2 点。")
	assert_true(
		(_cell(grid, 0, COLUMN_PLUS) as Button).disabled,
		"余额耗尽后加号必须禁用，避免累计超出可用点数。"
	)

	_dispose_popup(popup)


## 验证减号可以逐点撤回已累计的点数。
## 返回值：无。
func test_minus_withdraws_accumulated_points() -> void:
	var popup := _new_popup()
	if popup == null:
		return
	var attributes := _new_attributes()
	attributes.AvailablePoints = 5
	popup.call("Bind", attributes)
	var grid := popup.get_node("%AllocationGrid") as GridContainer

	(_cell(grid, 0, COLUMN_PLUS) as Button).pressed.emit()
	(_cell(grid, 0, COLUMN_PLUS) as Button).pressed.emit()
	(_cell(grid, 0, COLUMN_MINUS) as Button).pressed.emit()

	assert_eq(_value_text(grid, 0), "10 → 12", "撤回一点后预计值必须回到累计 1 点的水平。")
	# 撤回同样只是弹窗内部操作。
	assert_eq(attributes.allocate_calls.size(), 0, "撤回不得触碰属性组件。")
	assert_eq(attributes.AvailablePoints, 5, "撤回不得改变可用点数。")

	(_cell(grid, 0, COLUMN_MINUS) as Button).pressed.emit()
	assert_eq(_value_text(grid, 0), "10", "累计清零后必须回到只显示当前值。")
	assert_true(
		(_cell(grid, 0, COLUMN_MINUS) as Button).disabled,
		"没有累计时减号必须禁用。"
	)

	_dispose_popup(popup)


## 验证确认按属性各写入一次，扣点、写值、关窗。
## 返回值：无。
func test_confirm_writes_each_attribute_once_and_closes() -> void:
	var popup := _new_popup()
	if popup == null:
		return
	var attributes := _new_attributes()
	attributes.AvailablePoints = 5
	popup.call("Bind", attributes)
	var grid := popup.get_node("%AllocationGrid") as GridContainer

	(_cell(grid, 0, COLUMN_PLUS) as Button).pressed.emit()
	(_cell(grid, 0, COLUMN_PLUS) as Button).pressed.emit()
	(_cell(grid, 1, COLUMN_PLUS) as Button).pressed.emit()

	# 先把弹窗置为可见，否则「确认后关闭」这条断言在从未显示的状态下会无意义地通过。
	popup.visible = true
	(popup.get_node("%ConfirmButton") as Button).pressed.emit()

	assert_eq(attributes.allocate_calls.size(), 2, "确认必须按属性各写入一次，而不是逐点调用。")
	assert_eq(attributes.allocate_calls[0]["type"], 0, "首次写入必须是物攻。")
	assert_eq(attributes.allocate_calls[0]["amount"], 2, "物攻必须一次性写入累计的 2 点。")
	assert_eq(attributes.allocate_calls[1]["type"], 1, "再次写入必须是物防。")
	assert_eq(attributes.allocate_calls[1]["amount"], 1, "物防必须一次性写入累计的 1 点。")
	assert_eq(attributes.AvailablePoints, 2, "确认后可用点数必须按累计总量扣减。")
	assert_eq(int(attributes.GetEffectiveValue(0)), 14, "确认后物攻必须真的吃下 2 点的成长。")
	assert_false(popup.visible, "确认成功后必须关闭弹窗。")

	_dispose_popup(popup)


## 验证取消不写入任何点数。
## 返回值：无。
func test_cancel_discards_accumulation() -> void:
	var popup := _new_popup()
	if popup == null:
		return
	var attributes := _new_attributes()
	attributes.AvailablePoints = 4
	popup.call("Bind", attributes)
	var grid := popup.get_node("%AllocationGrid") as GridContainer

	(_cell(grid, 0, COLUMN_PLUS) as Button).pressed.emit()
	(_cell(grid, 2, COLUMN_PLUS) as Button).pressed.emit()
	# 先把弹窗置为可见，否则「取消后关闭」这条断言会无意义地通过。
	popup.visible = true
	(popup.get_node("%CancelButton") as Button).pressed.emit()

	assert_eq(attributes.allocate_calls.size(), 0, "取消不得写入任何点数。")
	assert_eq(attributes.AvailablePoints, 4, "取消不得改变可用点数。")
	assert_false(popup.visible, "取消必须关闭弹窗。")

	_dispose_popup(popup)


## 验证直接关闭窗口同样丢弃累计，且重新打开不残留旧值。
## 返回值：无。
func test_reopening_after_close_starts_from_clean_state() -> void:
	var popup := _new_popup()
	if popup == null:
		return
	var attributes := _new_attributes()
	attributes.AvailablePoints = 4
	popup.call("Bind", attributes)
	var grid := popup.get_node("%AllocationGrid") as GridContainer

	(_cell(grid, 0, COLUMN_PLUS) as Button).pressed.emit()
	assert_eq(_value_text(grid, 0), "10 → 12", "关闭前必须先真的累计上。")

	# 模拟玩家点遮罩或按 Esc 关闭窗口。
	popup.popup_hide.emit()

	popup.call("Bind", attributes)
	assert_eq(_value_text(grid, 0), "10", "重新打开必须从零开始，不得带出上一次的残留累计。")
	assert_eq(attributes.allocate_calls.size(), 0, "关闭窗口不得写入任何点数。")

	_dispose_popup(popup)


## 验证打开期间点数被外部削减后，确认会被拒绝且保持弹窗打开。
## 返回值：无。
func test_confirm_is_refused_when_points_shrank() -> void:
	var popup := _new_popup()
	if popup == null:
		return
	var attributes := _new_attributes()
	attributes.AvailablePoints = 3
	popup.call("Bind", attributes)
	var grid := popup.get_node("%AllocationGrid") as GridContainer

	# 累计 3 点。
	for _round: int in 3:
		(_cell(grid, 0, COLUMN_PLUS) as Button).pressed.emit()

	# 打开期间点数在别处被消费掉，累计量已经超过最新余额。
	attributes.AvailablePoints = 1
	# 先把弹窗置为可见，才能验证确认被拒绝时它确实没有被关掉。
	popup.visible = true
	(popup.get_node("%ConfirmButton") as Button).pressed.emit()

	assert_eq(attributes.allocate_calls.size(), 0, "累计量超过最新余额时必须拒绝写入。")
	assert_true(popup.visible, "拒绝写入时必须保持弹窗打开，让玩家看见最新状态。")
	assert_true(
		(_cell(grid, 0, COLUMN_PLUS) as Button).disabled,
		"余额不足时加号必须按最新点数重新禁用。"
	)

	_dispose_popup(popup)


## 验证属性组件缺失时弹窗整体降级且不产生异常。
## 返回值：无。
func test_missing_component_degrades_without_errors() -> void:
	var popup := _new_popup()
	if popup == null:
		return
	popup.call("Bind", null)
	var grid := popup.get_node("%AllocationGrid") as GridContainer

	assert_eq(
		(popup.get_node("%PointsLabel") as Label).text,
		"剩余可分配点数：0",
		"组件缺失时剩余可分配点数必须显示 0。"
	)
	assert_true((popup.get_node("%ConfirmButton") as Button).disabled, "组件缺失时确认必须禁用。")
	assert_true((grid.get_child(COLUMN_PLUS) as Button).disabled, "组件缺失时加号必须禁用。")
	assert_eq(_value_text(grid, 0), "-", "组件缺失时值必须与摘要区一致地显示占位符。")

	# 强制触发两个按钮也不得抛错或写入。
	(grid.get_child(COLUMN_PLUS) as Button).pressed.emit()
	(popup.get_node("%ConfirmButton") as Button).pressed.emit()
	assert_false(popup.visible, "组件缺失时确认不得关闭或打开弹窗。")

	_dispose_popup(popup)


## 构造与生产唯一节点名一致的轻量加点弹窗并触发正常 Ready 生命周期。
##
## 刻意用脚本实例加手工子树，而不是实例化生产场景：非 @tool 的 UI 脚本在编辑器里经场景
## 实例化只会得到占位实例，连 _ready 都调不动。生产场景自身的脚本引用与四列结构由
## test_production_popup_scene_uses_gdscript_and_unique_names 独立锁定。
##
## 返回值：已进入场景树的加点弹窗。
func _new_popup() -> PopupPanel:
	## 新建生产脚本根节点，以最小子树独立验证弹窗逻辑。
	var popup := ALLOCATION_POPUP_SCRIPT.new() as PopupPanel
	popup.name = "AttributeAllocationPopupContractProbe"

	# 四个唯一名与生产场景保持一致，弹窗才能用 % 语法定位它们。
	var points_label := Label.new()
	points_label.name = "PointsLabel"
	points_label.unique_name_in_owner = true
	popup.add_child(points_label)
	points_label.owner = popup

	var grid := GridContainer.new()
	grid.name = "AllocationGrid"
	grid.columns = COLUMNS_PER_ROW
	grid.unique_name_in_owner = true
	popup.add_child(grid)
	grid.owner = popup

	var confirm_button := Button.new()
	confirm_button.name = "ConfirmButton"
	confirm_button.unique_name_in_owner = true
	popup.add_child(confirm_button)
	confirm_button.owner = popup

	var cancel_button := Button.new()
	cancel_button.name = "CancelButton"
	cancel_button.unique_name_in_owner = true
	popup.add_child(cancel_button)
	cancel_button.owner = popup

	## 编辑器主循环提供 is_node_ready 所需的真实场景树状态。
	var scene_tree := Engine.get_main_loop() as SceneTree
	scene_tree.root.add_child(popup)
	# 非 @tool 生产脚本在编辑器测试中不会自动执行脚本生命周期；
	# 节点入树后显式调用可保留 is_node_ready 契约。
	popup.call("_ready")
	return popup


## 构造带固定基础值与成长值的属性组件替身。
## 返回值：物攻 10、物防 20、法强 30、法抗 40、速度 50，每点成长均为 2。
func _new_attributes() -> FakeAttributeComponent:
	## 属性夹具用于驱动弹窗的读取与写入断言。
	var attributes := FakeAttributeComponent.new()
	for index: int in ALLOCATABLE_TYPES.size():
		var attribute_type: int = ALLOCATABLE_TYPES[index]
		attributes.base_values[attribute_type] = 10.0 * (index + 1)
		attributes.growth_per_point[attribute_type] = 2.0
	return attributes


## 读取网格中某行某列的控件。
## 参数 grid：生产属性网格。
## 参数 index：行序号。
## 参数 offset：列偏移，取 COLUMN_* 常量。
## 返回值：对应控件。
func _cell(grid: GridContainer, index: int, offset: int) -> Control:
	return grid.get_child(index * COLUMNS_PER_ROW + offset) as Control


## 读取某行的值标签文本。
## 参数 grid：生产属性网格。
## 参数 index：行序号。
## 返回值：该行的值文本。
func _value_text(grid: GridContainer, index: int) -> String:
	return (_cell(grid, index, COLUMN_VALUE) as Label).text


## 从场景树移除并释放测试弹窗。
## 参数 popup：需要销毁的加点弹窗。
## 返回值：无。
func _dispose_popup(popup: PopupPanel) -> void:
	if popup == null:
		return
	if popup.is_inside_tree():
		popup.get_parent().remove_child(popup)
	popup.free()
