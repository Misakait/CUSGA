extends Control

## 明亮像素刻印台：复用背包外框和合成布面，在独立展示层绘制弹跳卡胚与纸屑。
## 不生成、不改写技能卡资源；粒子采用解析式运动，不推进业务抽卡使用的随机序列。

## 背包既有橙金框。
const BAG: Texture2D = preload("res://res/Nine-grid-template/背包UI.png")
## 合成界面既有缝线布面。
const CLOTH: Texture2D = preload("res://res/Nine-grid-template/面板1.png")
## 五行素材共用目录，保持卡背与揭晓动画的像素比例一致。
const CARD_ART: GDScript = preload("res://core/skill_card_art.gd")
## 既有像素印章小图。
const STAMP: Texture2D = preload("res://res/UI/图标ui/other/印章.png")
## 本界面主题常量。
const STYLE: GDScript = preload("res://core/ui/inventory/imprint_style.gd")
## 卡胚弹跳中心，位于卡牌展示区。
const CENTER: Vector2 = Vector2(640, 385)
## 纸屑统一寿命，过期后清理，避免节点不断累积。
const BURST_SECONDS: float = 0.75
## 每次爆开纸屑数量。
const BURST_PIECES: int = 18
## 彩色纸屑调色板。
const CONFETTI: Array[Color] = [Color("#ff6d73"), Color("#ffe257"), Color("#68de86"), Color("#5bcfff"), Color("#c999ff")]
## 泡泡按木、土、水、火、金顺序对应分页颜色；纸屑仍可混合彩色。
const BUBBLE_COLORS: Array[Color] = [Color("#8ee05c"), Color("#ffb850"), Color("#62d1ff"), Color("#ff8371"), Color("#ffe16a")]
## 蓄力进度 0～1，越接近末端卡胚越扁，释放后由面板归零。
var energy: float = 0.0
## 有结果时让出中心，避免装饰压住真实卡面。
var result_mode: bool = false
## 轻动效模式关闭持续浮动和纸屑。
var reduced_motion: bool = false
## 当前五行色。
var accent: Color = Color("#7fdb55")
## 当前五行字，同时用于选择对应卡背。
var glyph: String = "木"
## 只在面板可见时推进的局部时钟。
var _time: float = 0.0
## 当前活跃纸屑组，保存起点、颜色、星级与时间。
var _bursts: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	## 外框直接使用背包素材，让刻印和现有游戏界面保持同一套像素边缘。
	var frame := NinePatchRect.new()
	frame.texture = BAG
	frame.position = Vector2(12, 6)
	frame.size = Vector2(1256, 706)
	frame.patch_margin_left = 30
	frame.patch_margin_top = 34
	frame.patch_margin_right = 30
	frame.patch_margin_bottom = 30
	frame.show_behind_parent = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	## 布面沿用合成场景的裁切与缝线，只提升亮度，不编辑源图片。
	var cloth := NinePatchRect.new()
	cloth.texture = CLOTH
	cloth.region_rect = Rect2(2, 27, 232, 122)
	cloth.position = Vector2(56, 212)
	cloth.size = Vector2(584, 181)
	cloth.scale = Vector2(2, 2)
	cloth.patch_margin_left = 12
	cloth.patch_margin_top = 4
	cloth.patch_margin_right = 9
	cloth.patch_margin_bottom = 13
	cloth.modulate = Color(1.16, 1.11, 1.03)
	cloth.show_behind_parent = true
	cloth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cloth)

## 更新五行配色；color 为元素色，character 为五行字，返回值无。
func set_element(color: Color, character: String) -> void:
	accent = color
	glyph = character
	queue_redraw()

## 在指定设计坐标爆开彩色纸屑；point 为起点、color 为主色、stars 为星级，返回值无。
func burst(point: Vector2, color: Color, stars: int) -> void:
	if reduced_motion or not is_visible_in_tree():
		return
	_bursts.append({"point": point, "color": color, "stars": stars, "start": _time})

## 清除瞬态效果；无参数，返回值无。关闭或跳过时保留真实抽取结果。
func settle() -> void:
	energy = 0.0
	_bursts.clear()
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	for index in range(_bursts.size() - 1, -1, -1):
		if _time - float(_bursts[index].start) >= BURST_SECONDS:
			_bursts.remove_at(index)
	queue_redraw()

func _draw() -> void:
	## 亮色角花为布面增加活力，避开卡牌与按钮命中区域。
	for index in 12:
		## 两侧固定装饰坐标，运动幅度小，结果阶段继续保持安静。
		var point := Vector2(40 if index % 2 == 0 else 1240, 224 + floori(float(index) / 2.0) * 60)
		_star(point, 7.0, CONFETTI[index % CONFETTI.size()], 0.0)
	if not result_mode:
		_draw_card_embryo()
	for data in _bursts:
		_draw_confetti(data)

func _draw_card_embryo() -> void:
	## 慢速弹跳采用单一周期，蓄力时以挤压替代晃屏。
	var bounce: float = 0.0 if reduced_motion else absf(sin(_time * 2.3)) * 12.0
	## 蓄力末端横向挤开、纵向压扁，下一阶段恢复时形成果冻回弹。
	var squash := Vector2(1.0 + energy * 0.24, 1.0 - energy * 0.26)
	## 用扁椭圆阴影增强卡胚离地感。
	var center: Vector2 = CENTER + Vector2(0, -bounce + energy * 14.0)
	draw_set_transform(CENTER + Vector2(0, 97), 0.0, Vector2(1.0 - bounce * 0.008, 0.17))
	draw_circle(Vector2.ZERO, 126, Color("#cb8a43"))
	draw_set_transform(Vector2.ZERO)
	for index in 5:
		## 五行泡泡的位置围绕卡胚固定分布，轻微上下错拍。
		var angle: float = -PI * 0.5 + float(index) * TAU / 5.0
		## 泡泡与卡胚保持距离，避免覆盖实际游戏卡面。
		var point: Vector2 = CENTER + Vector2(cos(angle) * 210, sin(angle) * 119)
		point.y += 0.0 if reduced_motion else sin(_time * 2.6 + float(index)) * 6.0
		draw_circle(point + Vector2(0, 5), 23, Color("#c28139"))
		draw_circle(point, 23, BUBBLE_COLORS[index])
		draw_circle(point + Vector2(-7, -8), 5, Color(1, 1, 1, 0.7))
		draw_string(STYLE.PIXEL_FONT, point + Vector2(-13, 10), ["木", "土", "水", "火", "金"][index], HORIZONTAL_ALIGNMENT_CENTER, 26, 22, STYLE.INK)
	## 只展示当前五行的背面，正面内容仍交给真实卡牌场景绑定。
	for index in 3:
		## 两张底卡错开角度，中央卡胚正对玩家。
		var tilt: float = [-0.15, 0.13, -0.035][index]
		draw_set_transform(center + Vector2((index - 1) * 8, (2 - index) * 8), tilt, squash)
		draw_texture_rect(CARD_ART.back_for(glyph), Rect2(-126, -90, 252, 180), false)
	draw_texture_rect(STAMP, Rect2(73, -109, 64, 64), false)
	draw_set_transform(Vector2.ZERO)
	## 夸张闪星随蓄力增大，释放时会换成纸屑爆发。
	_star(center + Vector2(-164, -65), 16.0 + energy * 12.0, Color("#fff5ac"), 0.15)
	_star(center + Vector2(158, 42), 12.0 + energy * 8.0, Color.WHITE, -0.1)

func _draw_confetti(data: Dictionary) -> void:
	## 解析式抛物线按真实秒推进，帧率变化不影响纸屑终点。
	var progress: float = clampf((_time - float(data.start)) / BURST_SECONDS, 0.0, 1.0)
	## 高星使用更远、更大的纸屑，而不修改卡面稀有度标识。
	var reach: float = 80.0 + float(data.stars) * 17.0
	## 落点起始坐标由面板统一转换成设计坐标。
	var origin: Vector2 = data.point
	for index in BURST_PIECES:
		## 固定角度与长度，不使用影响抽卡的全局随机数。
		var angle: float = -PI + float(index) * TAU / float(BURST_PIECES)
		## 纸屑先向外飞，再被重力拉下。
		var point: Vector2 = origin + Vector2.from_angle(angle) * reach * progress + Vector2(0, progress * progress * 95.0)
		## 粒子尾段淡出，避免突然消失。
		var color: Color = data.color if index % 3 == 0 else CONFETTI[index % CONFETTI.size()]
		color.a = 1.0 - progress * progress
		if index % 4 == 0:
			_star(point, (8.0 if int(data.stars) < 5 else 11.0) * (1.0 - progress * 0.4), color, progress * 3.0)
		else:
			draw_set_transform(point, float(index) + progress * 6.0, Vector2.ONE)
			draw_rect(Rect2(-3, -5, 6, 10), color)
			draw_set_transform(Vector2.ZERO)

func _star(center: Vector2, radius: float, color: Color, angle: float) -> void:
	## 四角闪星使用粗壮短尖，比细长镜头光丝更接近果汁感像素界面。
	var points := PackedVector2Array()
	for index in 8:
		points.append(center + Vector2.from_angle(angle + float(index) * TAU / 8.0) * (radius if index % 2 == 0 else radius * 0.38))
	draw_colored_polygon(points, color)

