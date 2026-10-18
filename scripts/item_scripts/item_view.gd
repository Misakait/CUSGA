extends CharacterBody2D

## 地形卡视图；地形状态由房间仓库拥有，掉落物由独立 Loot 视图承载。
signal Clicked(card: Node2D)
signal Pressed(card: Node2D)
signal Released(card: Node2D)
signal HoverStarted(card: Node2D)
signal HoverEnded(card: Node2D)

## 动画参数资产；每个实例复制动画库后应用，避免共享资源被运行时改写。
@export var MotionConfig: Resource = preload("res://resources/interaction/item_motion_config.tres")
## 地形实体使用的物理层；默认第 6 层，与玩家的碰撞掩码一致。
@export_flags_2d_physics var TerrainCollisionLayer: int = 32
## 地形卡视觉基础倍率；不缩放碰撞形状。
@export_range(0.25, 5.0, 0.05) var TerrainVisualScale: float = 1.0

var RoomPosition: Vector2i = Vector2i.ZERO
## 地形卡不使用掉落 ID，但保留字段让 BoardController 复用移除协议时无需分支。
var LootId: int = -1
var _terrain_instance: RefCounted = null
var _card_data: Resource = null
var _interaction_disabled: bool = false
var _hovered: bool = false
var _base_visual_scale: Vector2 = Vector2.ONE
## 长按破坏期间的整卡抖动；在 _ready 中按动作参数构造，节点未就绪时保持为空。
var _shake: DestroyShake = null

@onready var _visuals: Sprite2D = $Visuals
@onready var _button: Button = $Visuals/PlayerView
@onready var _label: Label = $Visuals/PlayerView/Label
@onready var _icon: Sprite2D = $Visuals/PlayerView/Icon
## 不参与抖动的进度锚点；长按圆环锚定它而不是 _icon，否则整张卡牌一抖圆环就会跟着抖。
## 它挂在根节点下而不是 Visuals 子树里，因为被抖动的正是 Visuals。
@onready var _progress_anchor: Marker2D = $ProgressAnchor
@onready var _collision: CollisionShape2D = $Collision
@onready var _interaction: Area2D = $Interaction
@onready var _animation_player: AnimationPlayer = $AnimationPlayer
@onready var _marker_controller: Node = $MarkerController


## 连接唯一的鼠标输入入口，并配置当前实例自己的视觉动作。
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
	# 抖整张卡牌：抖 Visuals 让卡框、卡名与卡内图标一起动，而不是只抖卡里的物品图标。
	# 抖动参数走与 Idle/Hover 相同的动作参数资产；资产缺失时由组件自带兜底值接管。
	_shake = DestroyShake.new(
		_visuals,
		_motion_float("DestroyShakeAmplitude", DestroyShake.DEFAULT_AMPLITUDE),
		_motion_float("DestroyShakeStepSeconds", DestroyShake.DEFAULT_STEP_SECONDS)
	)
	_shake.SyncAnchor(_icon, _progress_anchor)
	_update_pickable()


## 退出时终止抖动，避免 Tween 与贴图偏移残留到下一次复用。
## @return 无返回值。
func _exit_tree() -> void:
	if _shake != null:
		_shake.Stop()


## 按房间坐标登记掉落身份；地形的实例 ID 由局部网格坐标决定。
## @param room 地图房间坐标。
## @param loot_id 掉落 ID；地形传入 -1。
## @return 无返回值。
func SetRoomIdentity(room: Vector2i, loot_id: int = -1) -> void:
	RoomPosition = room
	LootId = loot_id
	if _marker_controller != null and _marker_controller.has_method(&"set_room_identity"):
		_marker_controller.call(&"set_room_identity", room)


## 绑定地形状态，启用按配置设定的物理阻挡。
## @param terrain_instance 带 TerrainData 的地形实例。
## @return 无返回值。
func InitializeTerrain(terrain_instance: RefCounted) -> void:
	if terrain_instance == null:
		push_error("Item.InitializeTerrain 需要地形实例。")
		return
	var data: Resource = terrain_instance.get("TerrainData") as Resource
	if data == null:
		push_error("Item.InitializeTerrain 缺少 TerrainData。")
		return
	_terrain_instance = terrain_instance
	_card_data = data
	_base_visual_scale = Vector2.ONE * TerrainVisualScale
	_collision.set_deferred("disabled", false)
	collision_layer = TerrainCollisionLayer
	collision_mask = 0
	_configure_motion()
	_animation_player.play("Idle")
	RefreshView()


## 返回地形状态；掉落物返回 null。
## @return 当前地形实例或 null。
func GetTerrainInstanceOrNull() -> RefCounted:
	return _terrain_instance


## 返回掉落堆叠；地形卡返回 null。
## @return 当前掉落堆叠或 null。
func GetLootStackOrNull() -> RefCounted:
	return null


## 返回显示配置。
## @return 当前卡牌资源或 null。
func GetCardData() -> Resource:
	return _card_data


## 返回卡牌显示名。
## @return 资源中的 CardName；无资源时为空字符串。
func GetCardDisplayName() -> String:
	return String(_card_data.get("CardName")) if _card_data != null else ""


## 判断是否为地形卡。
## @return 绑定地形实例时为 true。
func IsTerrainCard() -> bool:
	return _terrain_instance != null


## 判断是否为掉落卡。
## @return 绑定掉落堆叠时为 true。
func IsLootCard() -> bool:
	return false


## 提供长按进度条的稳定锚点。
## @return 不参与破坏抖动的 ProgressAnchor 节点；其屏幕位置等于图标静止时的右下角。
func GetProgressAnchor() -> Node:
	return _progress_anchor


## 按绑定资源刷新外观，不改写碰撞或房间位置。
## @return 无返回值。
func RefreshView() -> void:
	if _card_data == null or not is_node_ready():
		return
	_label.text = String(_card_data.get("CardName"))
	_icon.texture = _card_data.get("CardIcon") as Texture2D
	# 锚点位置由图标纹理尺寸推导，纹理变化后必须重算，否则圆环会停在旧图标的右下角。
	if _shake != null:
		_shake.SyncAnchor(_icon, _progress_anchor)
	_base_visual_scale = Vector2.ONE * TerrainVisualScale
	_visuals.visible = true
	_visuals.scale = _base_visual_scale
	_visuals.self_modulate = Color.WHITE if not _interaction_disabled else Color(0.48, 0.48, 0.48)


## 禁用或恢复交互；冷却中的地形仍保留实体碰撞。
## @param disabled 是否禁止鼠标命中。
## @return 无返回值。
func SetInteractionDisabled(disabled: bool) -> void:
	_interaction_disabled = disabled
	_update_pickable()
	if is_node_ready():
		_visuals.self_modulate = Color(0.48, 0.48, 0.48) if disabled else Color.WHITE


## 切换「正在被长按破坏」的抖动表现；重复调用同一状态不产生额外影响。
##
## 抖的是整张卡牌（`Visuals` 及其子节点）的本地 position，卡框、卡名与卡内图标一起动；
## 不改变根节点位置、旋转、碰撞形状与鼠标命中区域，因此挂在根节点下、位于被抖子树之外的
## 进度锚点在抖动期间保持逐帧静止。
##
## @param destroying 是否正在被破坏。
## @return 无返回值。
func SetDestroying(destroying: bool) -> void:
	if _shake == null:
		return
	if destroying:
		_shake.Start()
	else:
		_shake.Stop()


## 保留棋盘卡旧高亮入口；悬停动画已经提供视觉反馈。
## @param highlighted 是否高亮。
## @return 无返回值。
func SetHighlighted(highlighted: bool) -> void:
	if highlighted:
		_on_mouse_entered()
	else:
		_on_mouse_exited()


## 接收地形卡的左键输入并转发为稳定的控制器信号。
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


func _on_mouse_entered() -> void:
	if _interaction_disabled:
		return
	# 悬停只能改视觉子树；如果上一段表现动画中断留下零缩放，先恢复基础倍率，避免卡牌看起来消失。
	if not _visuals.visible:
		_visuals.visible = true
	if is_zero_approx(_visuals.scale.x) or is_zero_approx(_visuals.scale.y):
		_visuals.scale = _base_visual_scale
	_hovered = true
	_animation_player.play("Hover")
	HoverStarted.emit(self)


func _on_mouse_exited() -> void:
	if not _hovered:
		return
	_hovered = false
	_animation_player.play("Idle")
	HoverEnded.emit(self)


func _update_pickable() -> void:
	if is_node_ready():
		_interaction.input_pickable = not _interaction_disabled


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
	var base_scale: Vector2 = _base_visual_scale
	_set_track(
		idle,
		0,
		[0.0, idle_duration / 2.0, idle_duration],
		[base_scale, base_scale * (1.0 + idle_amplitude), base_scale]
	)
	_set_track(
		idle, 1, [0.0, idle_duration / 2.0, idle_duration], [Color.WHITE, idle_tint, Color.WHITE]
	)
	idle.length = idle_duration
	var hover_duration: float = _motion_float("HoverDuration", 0.25)
	var squash: Vector2 = (
		MotionConfig.get("HoverSquash") if MotionConfig != null else Vector2(0.92, 1.08)
	)
	var stretch: Vector2 = (
		MotionConfig.get("HoverStretch") if MotionConfig != null else Vector2(1.08, 0.95)
	)
	var rest: Vector2 = (
		MotionConfig.get("HoverRest") if MotionConfig != null else Vector2(1.04, 1.04)
	)
	var tint: Color = MotionConfig.get("HoverTint") if MotionConfig != null else Color.WHITE
	_set_track(
		hover,
		0,
		[0.0, hover_duration * 0.28, hover_duration * 0.64, hover_duration],
		[base_scale, base_scale * squash, base_scale * stretch, base_scale * rest]
	)
	_set_track(
		hover,
		1,
		[0.0, hover_duration * 0.28, hover_duration * 0.64, hover_duration],
		[Color.WHITE, tint, Color.WHITE, tint]
	)
	hover.length = hover_duration


func _set_track(animation: Animation, track_index: int, times: Array, values: Array) -> void:
	for key_index in range(times.size()):
		animation.track_set_key_time(track_index, key_index, float(times[key_index]))
		animation.track_set_key_value(track_index, key_index, values[key_index])
