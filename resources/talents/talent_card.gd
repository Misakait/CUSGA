extends Control

## 天赋选择卡的 GDScript 视图实现。
##
## 职责边界：卡片只展示现有 TalentData 字段、播放悬停反馈并转发点击；
## 天赋池、随机抽取、效果应用与暂停恢复继续由 TalentManager、Player 和既有 Autoload 负责。

## 玩家点击卡片时转发当前 TalentData Resource。
signal OnCardClicked(data: Resource)

## 卡牌视觉数值的共享来源。
##
## 与战斗手牌（`scripts/card_scripts/card_manager.gd`）和开局技能卡抽取
## （`core/gameflow/run_start_skill_card_draft.gd`）共用同一份定义，避免同一套手感
## 在多个界面里各自演化。悬停只改缩放与层级、**不改颜色**：用 `modulate` 染色
## 表达悬停会与「选中」抢语义，也与战斗侧不一致。
const CARD_VISUALS := preload("res://core/card_visual_config.gd")

## 标题标签，字段名保持旧场景序列化键。
@export var _titleLabel: Label

## 描述标签，字段名保持旧场景序列化键。
@export var _descLabel: RichTextLabel

## 覆盖整张卡片的透明点击按钮。
@export var _clickArea: Button

## 天赋图片视图。
@export var _texture: TextureRect

## 当前展示的 TalentData。
var _talent_data: Resource

## 当前悬浮缩放动画。
var _hover_tween: Tween

## 共享悬停详情浮窗；由 TalentManager 注入，缺失时只降级为不显示详情。
var _tooltip_panel: Node = null


## 连接卡片输入并保持原底部中心缩放轴心。
## 返回值：无。
func _ready() -> void:
	_clickArea.pressed.connect(_on_pressed)
	_clickArea.mouse_entered.connect(_on_hover_enter)
	_clickArea.mouse_exited.connect(_on_hover_exit)
	pivot_offset = Vector2(size.x / 2.0, size.y)


## 卡片被移出场景树时收起详情浮窗。
##
## 浮窗是独立于本卡片的节点，界面关闭不会连带隐藏它；换一轮卡时旧卡片被
## `queue_free()`，若不在这里收尾，浮窗会停在上一次悬停的那张卡上。
## 返回值：无。
func _exit_tree() -> void:
	_hide_tooltip()


## 注入共享悬停详情浮窗。
##
## 采用注入而不是让卡片导出路径：卡片是可复用场景，写死「距浮窗几层」会把它的
## 可用位置限死，而界面根天然知道自己在 HUD 层级里的位置。
## 参数 panel：共享浮窗节点；传 null 表示没有可用的浮窗。
## 返回值：无。
func SetTooltipPanel(panel: Node) -> void:
	_tooltip_panel = panel


## 绑定并刷新一份天赋数据。
##
## 参数 data：包含 TalentName、Description 与 TalentTexture 的天赋 Resource。
## 返回值：无。
func Initialize(data: Resource) -> void:
	_talent_data = data
	if _titleLabel != null:
		_titleLabel.text = str(data.get("TalentName"))
	if _descLabel != null:
		_descLabel.text = str(data.get("Description"))
	if _texture != null:
		_texture.texture = data.get("TalentTexture") as Texture2D


## 播放悬浮放大、把当前卡片提升到最上层，并展示详情浮窗。
## 返回值：无。
func _on_hover_enter() -> void:
	if _talent_data != null:
		print("TalentCard hovered: " + str(_talent_data.get("TalentName")))
	# 层级立刻切换（与战斗侧 highlight_card 一致），只有缩放走补间。
	z_index = CARD_VISUALS.CARD_Z_INDEX_HOVER
	_tween_scale(CARD_VISUALS.CARD_HOVER_SCALE)
	_show_tooltip()


## 播放悬浮恢复、还原绘制层级，并收起详情浮窗。
## 返回值：无。
func _on_hover_exit() -> void:
	z_index = CARD_VISUALS.CARD_Z_INDEX_NORMAL
	_tween_scale(CARD_VISUALS.CARD_NORMAL_SCALE)
	_hide_tooltip()


## 把卡片缩放到目标值：在场景树中走补间，否则直接落到终值。
##
## `Node.create_tween()` 在节点尚未入场景树时会报错并返回 null，而编辑器契约测试
## 会构造不入树的实例。因此显式分叉：生产路径得到动画，测试路径直接得终态，
## 两边都能被断言，也不会产生引擎级错误噪音。
## 参数 target_scale：目标缩放。
## 返回值：无。
func _tween_scale(target_scale: Vector2) -> void:
	if not is_inside_tree():
		scale = target_scale
		return

	if _hover_tween != null:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", target_scale, CARD_VISUALS.SCALE_TWEEN_DURATION)


## 展示当前天赋的名称与描述。
##
## 文案取 `TalentName` / `Description`，与卡面自身显示的文字同源，避免浮窗里的
## 说法与卡面不一致。浮窗缺失或缺少协议时静默跳过：它是纯反馈依赖，
## 不该因为它缺位就让选择流程报错。
## 返回值：无。
func _show_tooltip() -> void:
	if _tooltip_panel == null or _talent_data == null:
		return

	if not _tooltip_panel.has_method("show_tooltip"):
		return

	_tooltip_panel.call(
		"show_tooltip",
		str(_talent_data.get("TalentName")),
		str(_talent_data.get("Description"))
	)


## 收起详情浮窗。
## 返回值：无。
func _hide_tooltip() -> void:
	if _tooltip_panel != null and _tooltip_panel.has_method("hide_tooltip"):
		_tooltip_panel.call("hide_tooltip")


## 把点击转发给管理器，不在视图内应用天赋效果。
## 返回值：无。
func _on_pressed() -> void:
	if _talent_data == null:
		return
	print("TalentCard clicked: " + str(_talent_data.get("TalentName")))
	# 界面随即关闭，浮窗必须一起收起，否则会残留在已关闭的界面上。
	_hide_tooltip()
	emit_signal(&"OnCardClicked", _talent_data)
