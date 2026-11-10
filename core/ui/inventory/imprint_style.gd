extends RefCounted

## 刻印界面的像素糖果色主题；复用背包、合成界面的字体和素材语汇。
## 此主题只作用于刻印外框与按钮，不覆盖 SkillCard 场景的主题、纹理或文字。

## 基准画布，等比缩放保持卡牌和鼠标命中区域一致。
const DESIGN_SIZE: Vector2 = Vector2(1280, 720)
## 暖黄强调色用于纸屑与主要操作。
const GOLD: Color = Color("#ffe46b")
## 深棕正文与明亮底板形成对比，与合成界面的暖色框线一致。
const INK: Color = Color("#63331c")
## 次级说明使用可读的棕色，不在亮底上使用浅灰。
const MUTED: Color = Color("#885335")
## 背包和合成界面的同一份像素字体。
const PIXEL_FONT: Font = preload("res://res/font/Uranus_Pixel_11Px.ttf")
## 稀有度只改变卡牌周围纸屑，不染色或替换技能卡本身。
const RARITY_COLORS: Array[Color] = [Color("#56cfff"), Color("#ce83ff"), Color("#ffdf48")]

## 返回项目内置像素字体；无参数，返回 Font。
static func make_font() -> Font:
	return PIXEL_FONT

## 返回星级粒子色；stars 为资源星级，返回 Color。
static func rarity_color(stars: int) -> Color:
	return RARITY_COLORS[clampi(stars - 3, 0, 2)]

## 创建厚描边弹性按钮；accent 为颜色、state 为状态、primary 为主操作，返回 StyleBoxFlat。
static func button_style(accent: Color, state: String, primary: bool = false) -> StyleBoxFlat:
	## 每个状态独立资源，防止选中分页改变其他按钮颜色。
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fff0b8") if not primary else Color("#ff804b")
	style.border_color = Color("#a35728")
	style.set_border_width_all(3)
	style.border_width_bottom = 5
	style.set_corner_radius_all(8)
	style.shadow_color = Color("#bd6b29")
	style.shadow_size = 0
	style.shadow_offset = Vector2(0, 5)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	if accent != GOLD:
		style.bg_color = accent
	if state in ["hover", "focus"]:
		style.bg_color = style.bg_color.lightened(0.16)
		style.border_color = Color("#7d3d25")
		style.shadow_color = Color("#9b5426")
	elif state in ["pressed", "hover_pressed"]:
		style.bg_color = accent
		style.border_color = Color("#ffffff")
		style.border_width_bottom = 3
		style.shadow_offset = Vector2(0, 2)
	elif state == "disabled":
		style.bg_color = Color("#d4b58c")
		style.border_color = Color("#b08c6c")
		style.shadow_offset = Vector2(0, 2)
	return style

