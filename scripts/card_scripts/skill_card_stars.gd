extends HBoxContainer

## 技能卡星级展示组件；真实星级由卡牌绑定入口传入，不根据颜色或抽卡动画推断。
## 独立纹理避免字体没有星形字形时显示方框。
const STAR: Texture2D = preload("res://res/skillcard/elemental/star.svg")
## 一行最多展开五颗星；更高星级显示单颗星与完整数字，避免挤占卡面。
const EXPANDED_LIMIT: int = 5
## 已创建的星形节点，重复绑定同一卡面时复用。
var _stars: Array[TextureRect] = []
## 超出展开上限时的完整数值。
var _overflow: Label
## 当前显示的真实星级，默认 1 星，与技能卡资源默认值一致。
var star_level: int = 1

func _ready() -> void:
	# 非战斗展示可能先绑定资源再入树，不能在 ready 时覆盖已经传入的等级。
	if _stars.is_empty():
		set_level(star_level)

## 显示技能卡星级；level 为实际资源星级，缺省或非正数按 1 星展示，返回值无。
func set_level(level: int) -> void:
	star_level = maxi(level, 1)
	if _stars.is_empty():
		for index in EXPANDED_LIMIT:
			## 纹理节点固定为 12×12，不让原始纹理尺寸影响卡面布局。
			var icon := TextureRect.new()
			icon.texture = STAR
			icon.custom_minimum_size = Vector2(12, 12)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(icon)
			_stars.append(icon)
		_overflow = Label.new()
		_overflow.add_theme_font_size_override("font_size", 13)
		_overflow.add_theme_color_override("font_color", Color("#674c2c"))
		_overflow.add_theme_constant_override("outline_size", 0)
		_overflow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_overflow)
	for index in _stars.size():
		_stars[index].visible = index < star_level if star_level <= EXPANDED_LIMIT else index == 0
	_overflow.visible = star_level > EXPANDED_LIMIT
	_overflow.text = "×%d" % star_level
