@tool
extends Area2D

## 棋盘卡牌的生产视图，展示地形或掉落并转发鼠标输入。
##
## C# BoardController 继续拥有卡牌集合与 BoardCardState 兼容校验；本视图只接收
## TerrainInstance 或 ItemStack 的稳定对象协议，不复制棋盘业务状态。

## 点击卡牌时发出；禁用状态不会发出该信号。
signal Clicked(card: Node2D)
## 左键按下时发出；即使禁用也保持原按下时序，供长按协调器判断。
signal Pressed(card: Node2D)
## 左键释放时发出。
signal Released(card: Node2D)
## 鼠标进入卡牌区域时发出。
signal HoverStarted(card: Node2D)
## 鼠标离开卡牌区域时发出。
signal HoverEnded(card: Node2D)

## 地形卡静止显示时的整体缩放倍率。
@export_range(1.0, 8.0, 0.1, "or_greater") var TerrainCardRestingScale: float = 3.0

## 当前卡牌类型：0 表示未绑定，1 表示地形，2 表示掉落。
var _card_kind: int = 0
## 当前用于标题与图标的卡牌数据 Resource。
var _card_data: Resource = null
## 掉落卡保留的旧 C# 或 GDScript ItemStack。
var _loot_stack: RefCounted = null
## 地形卡保留的 C# TerrainInstance。
var _terrain_instance: RefCounted = null
## 图标节点。
var _icon_sprite: Sprite2D = null
## 标题节点。
var _title_label: Label = null
## 堆叠数量节点。
var _amount_label: Label = null
## 当前散射或飞行动画；新动画开始前会终止旧动画。
var _active_tween: Tween = null
## 资源冷却等规则是否禁用当前交互。
var _interaction_disabled: bool = false


## 解析固定子节点并连接鼠标悬浮信号。
func _ready() -> void:
	_icon_sprite = get_node("Icon") as Sprite2D
	_title_label = get_node("Title") as Label
	_amount_label = get_node("Amount") as Label
	input_pickable = true
	if not mouse_entered.is_connected(_on_mouse_entered_internal):
		mouse_entered.connect(_on_mouse_entered_internal)
	if not mouse_exited.is_connected(_on_mouse_exited_internal):
		mouse_exited.connect(_on_mouse_exited_internal)


## 退出时终止仍持有本节点的 Tween。
func _exit_tree() -> void:
	_stop_active_tween()


## 返回当前卡牌数据。
func GetCardData() -> Resource:
	return _card_data


## 返回 CardName 显示文本；没有数据时返回空字符串。
func GetCardDisplayName() -> String:
	return String(_card_data.get("CardName")) if _card_data != null else ""


## 判断当前是否为掉落卡。
func IsLootCard() -> bool:
	return _card_kind == 2


## 判断当前是否为地形卡。
func IsTerrainCard() -> bool:
	return _card_kind == 1


## 返回掉落卡持有的跨语言 ItemStack；其他卡牌返回 null。
func GetLootStackOrNull() -> RefCounted:
	return _loot_stack if IsLootCard() else null


## 返回地形卡持有的 TerrainInstance；其他卡牌返回 null。
func GetTerrainInstanceOrNull() -> RefCounted:
	return _terrain_instance if IsTerrainCard() else null


## 返回地形卡数据；其他卡牌返回 null。
func GetTerrainDataOrNull() -> Resource:
	return _card_data if IsTerrainCard() else null


## 兼容旧 Bind 名称；跨语言生产入口使用 InitializeTerrain / InitializeLoot。
## 参数 state：包含 TerrainInstance 或 LootStack 键的字典。
func Bind(state: Variant) -> void:
	if state is Dictionary:
		var dictionary: Dictionary = state
		if dictionary.has("TerrainInstance"):
			InitializeTerrain(dictionary["TerrainInstance"] as RefCounted)
			return
		if dictionary.has("LootStack"):
			InitializeLoot(dictionary["LootStack"] as RefCounted)
			return
	push_error("BoardCardView.Bind 需要 TerrainInstance 或 LootStack 状态。")


## 绑定地形实例并刷新视图。
func InitializeTerrain(terrain_instance: RefCounted) -> void:
	if terrain_instance == null:
		push_error("BoardCardView.InitializeTerrain 的 terrain_instance 不能为空。")
		return
	var terrain_data := terrain_instance.get("TerrainData") as Resource
	if terrain_data == null:
		push_error("BoardCardView.InitializeTerrain 需要有效 TerrainData。")
		return
	_card_kind = 1
	_terrain_instance = terrain_instance
	_loot_stack = null
	_card_data = terrain_data
	RefreshView()


## 绑定跨语言物品堆叠并刷新视图。
func InitializeLoot(loot_stack: RefCounted) -> void:
	var item := _read_stack_item(loot_stack)
	if item == null:
		push_error("BoardCardView.InitializeLoot 需要有效 ItemStack 协议。")
		return
	_card_kind = 2
	_loot_stack = loot_stack
	_terrain_instance = null
	_card_data = item
	RefreshView()


## 根据当前数据刷新标题、图标、缩放、数量和禁用视觉。
func RefreshView() -> void:
	if _card_data == null:
		push_error("BoardCardView 在绑定卡牌数据之前不能刷新。")
		return
	_title_label.text = String(_card_data.get("CardName"))
	_icon_sprite.texture = _card_data.get("CardIcon") as Texture2D
	scale = _get_resting_scale()
	var amount: int = _read_stack_amount(_loot_stack)
	if IsLootCard() and amount > 1:
		_amount_label.visible = true
		_amount_label.text = str(amount)
	else:
		_amount_label.visible = false
		_amount_label.text = ""
	_apply_interaction_disabled_visual()


## 把左键输入转换为原有 Pressed、Clicked、Released 信号。
func _input_event(viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button == null or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse_button.pressed:
		Pressed.emit(self)
		if not _interaction_disabled:
			Clicked.emit(self)
	else:
		Released.emit(self)
	viewport.set_input_as_handled()


## 从指定全局坐标散射到目标位置，保持原 0.35 秒 Circ/Back Out 动画。
func PlayScatterFrom(spawn_origin: Vector2, target_position: Vector2) -> void:
	_stop_active_tween()
	global_position = spawn_origin
	scale = Vector2.ZERO
	rotation = 0.0
	input_pickable = false
	_active_tween = get_tree().create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_property(self, "global_position", target_position, 0.35) \
		.set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "scale", _get_resting_scale(), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.finished.connect(_on_scatter_finished, CONNECT_ONE_SHOT)


## 飞向目标并缩小消失，保持原 0.30 秒 Sine In 动画。
func PlayFlyTo(target_position: Vector2, on_finished: Callable = Callable()) -> void:
	_stop_active_tween()
	input_pickable = false
	z_index = 1000
	_active_tween = get_tree().create_tween()
	_active_tween.set_parallel(true)
	_active_tween.tween_property(self, "global_position", target_position, 0.30) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(self, "scale", Vector2.ZERO, 0.30) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if on_finished.is_valid():
		_active_tween.finished.connect(on_finished, CONNECT_ONE_SHOT)


## 保留旧公开高亮入口；旧实现没有额外视觉状态。
func SetHighlighted(_highlighted: bool) -> void:
	pass


## 设置是否禁用交互；禁用时关闭输入并变灰。
func SetInteractionDisabled(disabled: bool) -> void:
	_interaction_disabled = disabled
	_apply_interaction_disabled_visual()


## 鼠标进入时转发当前视图。
func _on_mouse_entered_internal() -> void:
	HoverStarted.emit(self)


## 鼠标离开时转发当前视图。
func _on_mouse_exited_internal() -> void:
	HoverEnded.emit(self)


## 散射完成后按禁用状态恢复输入。
func _on_scatter_finished() -> void:
	input_pickable = not _interaction_disabled


## 地形卡使用导出倍率，掉落卡保持一倍缩放。
func _get_resting_scale() -> Vector2:
	return Vector2.ONE * TerrainCardRestingScale if IsTerrainCard() else Vector2.ONE


## 终止旧 Tween，避免多次动画同时写入变换。
func _stop_active_tween() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null


## 根据禁用状态同步输入与颜色。
func _apply_interaction_disabled_visual() -> void:
	input_pickable = not _interaction_disabled
	modulate = Color(0.45, 0.45, 0.45, 1.0) if _interaction_disabled else Color.WHITE


## 从新旧 ItemStack 读取有效 Item Resource。
func _read_stack_item(stack: RefCounted) -> Resource:
	if stack == null:
		return null
	var item := stack.get("Item") as Resource
	return item if item != null and _read_stack_amount(stack) > 0 and not bool(stack.get("IsEmpty")) else null


## 从新旧 ItemStack 读取数量。
func _read_stack_amount(stack: RefCounted) -> int:
	return int(stack.get("Amount")) if stack != null else 0
