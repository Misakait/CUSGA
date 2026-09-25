extends Area2D

## 掉落物表现视图；只负责显示、鼠标交互和飞行动画。
## 掉落堆叠、房间坐标和拾取结算仍由 RoomLootStore、BoardController 与协调器拥有。

## 掉落物被点击时发出。
signal Clicked(card: Node2D)
## 左键按下时发出，供控制器保持统一输入时序。
signal Pressed(card: Node2D)
## 左键释放时发出。
signal Released(card: Node2D)
## 鼠标进入掉落物时发出。
signal HoverStarted(card: Node2D)
## 鼠标离开掉落物时发出。
signal HoverEnded(card: Node2D)

## 动画参数资源；每个掉落实例复制动画库，避免运行时修改共享资源。
@export var MotionConfig: Resource = preload("res://resources/interaction/item_motion_config.tres")

## 房间坐标，由 BoardController 在生成时登记。
var RoomPosition: Vector2i = Vector2i.ZERO
## 房间内稳定的掉落 ID，由 RoomLootStore 分配。
var LootId: int = -1

var _loot_stack: RefCounted = null
var _card_data: Resource = null
var _interaction_disabled: bool = false
var _hovered: bool = false
var _base_visual_scale: Vector2 = Vector2.ONE
var _active_tween: Tween = null
var _flight_target: Node2D = null
var _flight_elapsed: float = 0.0
var _flight_start: Vector2 = Vector2.ZERO
var _flight_finished: Callable = Callable()

@onready var _visuals: Sprite2D = $Visuals
@onready var _button: Button = $Visuals/PlayerView
@onready var _label: Label = $Visuals/PlayerView/Label
@onready var _icon: Sprite2D = $Visuals/PlayerView/Icon
@onready var _amount: Label = $Visuals/PlayerView/Amount
@onready var _interaction: Area2D = $Interaction
@onready var _animation_player: AnimationPlayer = $AnimationPlayer


## 连接唯一的鼠标输入入口并启动待机动画。
## @return 无返回值。
func _ready() -> void:
	_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interaction.input_pickable = true
	_interaction.collision_layer = 1
	_interaction.collision_mask = 0
	_interaction.input_event.connect(_on_interaction_input)
	_interaction.mouse_entered.connect(_on_mouse_entered)
	_interaction.mouse_exited.connect(_on_mouse_exited)
	_configure_motion()
	_animation_player.play("Idle")
	_update_pickable()


## 释放活动 Tween 和飞行回调。
## @return 无返回值。
func _exit_tree() -> void:
	_stop_tween()
	_flight_target = null
	_flight_finished = Callable()


## 登记掉落物所属房间和稳定 ID。
## @param room 地图房间坐标。
## @param loot_id 掉落记录 ID。
## @return 无返回值。
func SetRoomIdentity(room: Vector2i, loot_id: int = -1) -> void:
	RoomPosition = room
	LootId = loot_id


## 绑定掉落堆叠并刷新标题、图标和数量。
## @param loot_stack 带 Item、Amount 与 IsEmpty 属性的堆叠。
## @return 无返回值。
func InitializeLoot(loot_stack: RefCounted) -> void:
	if loot_stack == null or loot_stack.get("Item") == null:
		push_error("Loot.InitializeLoot 需要有效物品堆叠。")
		return
	_loot_stack = loot_stack
	_card_data = loot_stack.get("Item") as Resource
	_base_visual_scale = Vector2.ONE
	collision_layer = 0
	collision_mask = 0
	_configure_motion()
	_animation_player.play("Idle")
	RefreshView()


## 掉落视图不承载地形实例，保持 BoardController 的统一查询协议。
## @return 始终为 null。
func GetTerrainInstanceOrNull() -> RefCounted:
	return null


## 返回当前掉落堆叠。
## @return 绑定的 ItemStack，未初始化时为 null。
func GetLootStackOrNull() -> RefCounted:
	return _loot_stack


## 返回当前显示资源。
## @return 掉落物 Item 资源，未初始化时为 null。
func GetCardData() -> Resource:
	return _card_data


## 返回掉落物显示名。
## @return Item 的 CardName；未初始化时为空字符串。
func GetCardDisplayName() -> String:
	return String(_card_data.get("CardName")) if _card_data != null else ""


## 判断当前视图是否为掉落卡。
## @return 初始化成功后为 true。
func IsLootCard() -> bool:
	return _loot_stack != null


## 判断当前视图是否为地形卡。
## @return 始终为 false。
func IsTerrainCard() -> bool:
	return false


## 提供拾取进度或交互提示的稳定锚点。
## @return 掉落物图标节点。
func GetProgressAnchor() -> Node:
	return _icon


## 根据物品资源刷新掉落物的显示内容。
## @return 无返回值。
func RefreshView() -> void:
	if _card_data == null or not is_node_ready():
		return
	_label.text = String(_card_data.get("CardName"))
	_icon.texture = _card_data.get("CardIcon") as Texture2D
	var amount: int = int(_loot_stack.get("Amount")) if _loot_stack != null else 0
	_amount.visible = amount > 1
	_amount.text = str(amount) if amount > 1 else ""
	_visuals.scale = _base_visual_scale
	_visuals.self_modulate = Color(0.48, 0.48, 0.48) if _interaction_disabled else Color.WHITE


## 设置掉落物是否接受鼠标输入。
## @param disabled 是否禁用交互。
## @return 无返回值。
func SetInteractionDisabled(disabled: bool) -> void:
	_interaction_disabled = disabled
	_update_pickable()
	if is_node_ready():
		_visuals.self_modulate = Color(0.48, 0.48, 0.48) if disabled else Color.WHITE


## 拾取成功后关闭命中，飞行期间只保留视觉。
## @return 无返回值。
func DisableForPickup() -> void:
	_interaction_disabled = true
	_update_pickable()


## 从掉落生成点散射到仓库记录的最终落点。
## @param spawn_origin 散射起点的世界坐标。
## @param target_position 仓库记录的最终世界坐标。
## @return 无返回值。
func PlayScatterFrom(spawn_origin: Vector2, target_position: Vector2) -> void:
	_stop_tween()
	_animation_player.stop()
	global_position = spawn_origin
	_interaction.input_pickable = false
	_visuals.visible = true
	_visuals.scale = Vector2.ZERO
	var duration: float = _motion_float("ScatterDuration", 0.35)
	_active_tween = create_tween().set_parallel(true)
	_active_tween.tween_property(self, "global_position", target_position, duration).set_trans(Tween.TRANS_CIRC).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_visuals, "scale", _base_visual_scale, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.finished.connect(_on_scatter_finished, CONNECT_ONE_SHOT)


## 飞向移动中的 PlayerChar 或固定世界坐标。
## @param target_position PlayerChar 节点或固定世界坐标。
## @param on_finished 飞行结束回调。
## @return 无返回值。
func PlayFlyTo(target_position: Variant, on_finished: Callable = Callable()) -> void:
	_stop_tween()
	DisableForPickup()
	_animation_player.stop()
	z_index = 1000
	_flight_target = target_position as Node2D if target_position is Node2D else null
	_flight_start = global_position
	_flight_elapsed = 0.0
	_flight_finished = on_finished
	if _flight_target == null and target_position is Vector2:
		var duration: float = _motion_float("PickupDuration", 0.30)
		_active_tween = create_tween().set_parallel(true)
		_active_tween.tween_property(self, "global_position", target_position, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_active_tween.tween_property(_visuals, "scale", Vector2.ZERO, duration)
		_active_tween.finished.connect(_finish_flight, CONNECT_ONE_SHOT)
	set_process(_flight_target != null)


## 追踪移动中的 PlayerChar，避免角色移动时掉落物飞向旧位置。
## @param delta 本帧真实秒数。
## @return 无返回值。
func _process(delta: float) -> void:
	if _flight_target == null or not is_instance_valid(_flight_target):
		_finish_flight()
		return
	_flight_elapsed += delta
	var progress: float = clampf(_flight_elapsed / _motion_float("PickupDuration", 0.30), 0.0, 1.0)
	var eased: float = progress * progress
	global_position = _flight_start.lerp(_flight_target.global_position, eased)
	_visuals.scale = _base_visual_scale.lerp(Vector2.ZERO, progress)
	if progress >= 1.0:
		_finish_flight()


## 把左键事件转换为控制器使用的稳定信号。
## @param viewport 当前视口。
## @param event 鼠标事件。
## @param _shape_index 命中的碰撞形状索引。
## @return 无返回值。
func _on_interaction_input(viewport: Viewport, event: InputEvent, _shape_index: int) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		Pressed.emit(self)
		if not _interaction_disabled:
			Clicked.emit(self)
	else:
		Released.emit(self)
	viewport.set_input_as_handled()


## 鼠标进入时只播放视觉动画，不改变掉落位置和数据。
## @return 无返回值。
func _on_mouse_entered() -> void:
	if _interaction_disabled or _flight_target != null:
		return
	if not _visuals.visible:
		_visuals.visible = true
	if is_zero_approx(_visuals.scale.x) or is_zero_approx(_visuals.scale.y):
		_visuals.scale = _base_visual_scale
	_hovered = true
	_animation_player.play("Hover")
	HoverStarted.emit(self)


## 鼠标离开时恢复待机动画。
## @return 无返回值。
func _on_mouse_exited() -> void:
	if not _hovered:
		return
	_hovered = false
	_animation_player.play("Idle")
	HoverEnded.emit(self)


func _on_scatter_finished() -> void:
	_active_tween = null
	_visuals.visible = true
	_visuals.scale = _base_visual_scale
	_animation_player.play("Idle")
	_update_pickable()


func _finish_flight() -> void:
	set_process(false)
	_flight_target = null
	var callback: Callable = _flight_finished
	_flight_finished = Callable()
	if callback.is_valid():
		callback.call()


func _update_pickable() -> void:
	if is_node_ready():
		_interaction.input_pickable = not _interaction_disabled


func _stop_tween() -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
		_active_tween = null


func _motion_float(field: StringName, fallback: float) -> float:
	if MotionConfig == null:
		return fallback
	var value: Variant = MotionConfig.get(field)
	return float(value) if value is float or value is int else fallback


func _configure_motion() -> void:
	var shared: AnimationLibrary = _animation_player.get_animation_library("")
	if shared == null:
		return
	var library: AnimationLibrary = shared.duplicate(true) as AnimationLibrary
	_animation_player.remove_animation_library("")
	_animation_player.add_animation_library("", library)
	var idle: Animation = library.get_animation("Idle")
	var hover: Animation = library.get_animation("Hover")
	if idle == null or hover == null:
		return
	var idle_duration: float = _motion_float("IdleDuration", 1.8)
	var idle_amplitude: float = _motion_float("IdleScaleAmplitude", 0.03)
	var idle_tint: Color = MotionConfig.get("IdleTint") if MotionConfig != null else Color.WHITE
	_set_track(idle, 0, [0.0, idle_duration / 2.0, idle_duration], [_base_visual_scale, _base_visual_scale * (1.0 + idle_amplitude), _base_visual_scale])
	_set_track(idle, 1, [0.0, idle_duration / 2.0, idle_duration], [Color.WHITE, idle_tint, Color.WHITE])
	idle.length = idle_duration
	var hover_duration: float = _motion_float("HoverDuration", 0.25)
	var squash: Vector2 = MotionConfig.get("HoverSquash") if MotionConfig != null else Vector2(0.92, 1.08)
	var stretch: Vector2 = MotionConfig.get("HoverStretch") if MotionConfig != null else Vector2(1.08, 0.95)
	var rest: Vector2 = MotionConfig.get("HoverRest") if MotionConfig != null else Vector2(1.04, 1.04)
	var tint: Color = MotionConfig.get("HoverTint") if MotionConfig != null else Color.WHITE
	_set_track(hover, 0, [0.0, hover_duration * 0.28, hover_duration * 0.64, hover_duration], [_base_visual_scale, _base_visual_scale * squash, _base_visual_scale * stretch, _base_visual_scale * rest])
	_set_track(hover, 1, [0.0, hover_duration * 0.28, hover_duration * 0.64, hover_duration], [Color.WHITE, tint, Color.WHITE, tint])
	hover.length = hover_duration


func _set_track(animation: Animation, track_index: int, times: Array, values: Array) -> void:
	for key_index in range(times.size()):
		animation.track_set_key_time(track_index, key_index, float(times[key_index]))
		animation.track_set_key_value(track_index, key_index, values[key_index])
