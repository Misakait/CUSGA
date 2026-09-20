extends Control

## 天赋选择卡的 GDScript 视图实现。
##
## 卡片只展示现有 TalentData 字段并转发点击；天赋池、随机抽取、效果应用
## 与暂停恢复继续由 TalentManager、Player 和既有 Autoload 负责。

## 玩家点击卡片时转发当前 TalentData Resource。
signal OnCardClicked(data: Resource)

## 标题标签，字段名保持旧场景序列化键。
@export var _titleLabel: Label

## 描述标签，字段名保持旧场景序列化键。
@export var _descLabel: RichTextLabel

## 覆盖整张卡片的透明点击按钮。
@export var _clickArea: Button

## 天赋图片视图。
@export var _texture: TextureRect

## 当前展示的旧 C# 或未来 GDScript TalentData。
var _talent_data: Resource

## 当前悬浮缩放动画。
var _hover_tween: Tween


## 连接卡片输入并保持原底部中心缩放轴心。
## 返回值：无。
func _ready() -> void:
	_clickArea.pressed.connect(_on_pressed)
	_clickArea.mouse_entered.connect(_on_hover_enter)
	_clickArea.mouse_exited.connect(_on_hover_exit)
	pivot_offset = Vector2(size.x / 2.0, size.y)


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


## 播放悬浮放大并把当前卡片提升到最上层。
## 返回值：无。
func _on_hover_enter() -> void:
	if _talent_data != null:
		print("TalentCard hovered: " + str(_talent_data.get("TalentName")))
	if _hover_tween != null:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2(1.05, 1.05), 0.15) \
		.set_trans(Tween.TRANS_BACK) \
		.set_ease(Tween.EASE_OUT)
	z_index = 1


## 播放悬浮恢复并还原绘制层级。
## 返回值：无。
func _on_hover_exit() -> void:
	if _hover_tween != null:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2.ONE, 0.15) \
		.set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_OUT)
	z_index = 0


## 把点击转发给管理器，不在视图内应用天赋效果。
## 返回值：无。
func _on_pressed() -> void:
	if _talent_data == null:
		return
	print("TalentCard clicked: " + str(_talent_data.get("TalentName")))
	emit_signal(&"OnCardClicked", _talent_data)
