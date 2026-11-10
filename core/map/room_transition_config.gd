class_name RoomTransitionConfig
extends Resource

## 房间移动与地点提示的可调参数；修改默认资源后，下一次运行使用新配置。

@export_group("行动值")
## 每次成功跨入相邻房间推进的时间点数；跨生态不额外收费，0 表示免费。
@export_range(0, 1000, 1, "or_greater") var action_cost: int = 10

@export_group("地点提示")
## 关闭后只隐藏地点提示，不影响行动值结算。
@export var enabled: bool = true
## 开局或恢复当前房间时是否播放；无论是否播放，初始房间都不收费。
@export var show_initial_room: bool = false
## 房间名中心距屏幕顶部的比例；0.24 在 720 高度下约为 173 像素。
@export_range(0.1, 0.5, 0.01) var screen_y_ratio: float = 0.24
## 生态名独立显示在更上方；0.10 在 720 高度下为 72 像素。
@export_range(0.05, 0.4, 0.01) var biome_screen_y_ratio: float = 0.10
## 文本与衬底的最大宽度，单位为基准视口像素；窄窗口会自动留出两侧边距。
@export_range(240.0, 1000.0, 1.0) var banner_width: float = 620.0
## 上方生态提示的最大宽度，单位为基准视口像素。
@export_range(240.0, 1200.0, 1.0) var biome_banner_width: float = 760.0
## 中文像素字体；留空时使用项目默认字体。
@export var font: Font = preload("res://res/font/Uranus_Pixel_11Px.ttf")
## 房间提示的字号；跨生态时下方房间名也沿用此字号，单位为像素。
@export_range(14, 64, 1) var room_font_size: int = 28
## 上方生态名的独立字号，单位为像素。
@export_range(14, 96, 1) var biome_font_size: int = 48
## 正文颜色；轮廓与阴影帮助文字在明暗地形上保持清晰。
@export var text_color: Color = Color(1.0, 0.96, 0.85, 1.0)

@export_group("动效时长与幅度")
## 入场淡入及上浮时长，单位为秒。
@export_range(0.05, 2.0, 0.01) var enter_duration: float = 0.3
## 房间提示完全显示后停留的秒数，与生态提示分别计时。
@export_range(0.0, 10.0, 0.05) var room_hold_duration: float = 1.4
## 上方生态提示完全显示后停留的秒数，普通换房不会打断本计时。
@export_range(0.0, 10.0, 0.05) var biome_hold_duration: float = 2.1
## 退场淡出时长，单位为秒。
@export_range(0.05, 2.0, 0.01) var exit_duration: float = 0.35
## 入场上浮距离，单位为像素；0 表示仅淡入。
@export_range(0.0, 40.0, 1.0) var rise_distance: float = 8.0
## 装饰细线展开时长，单位为秒；从中间向两边展开。
@export_range(0.05, 2.0, 0.01) var line_duration: float = 0.45
## 横向渐隐衬底的不透明度；0 表示关闭衬底。
@export_range(0.0, 0.8, 0.01) var backdrop_opacity: float = 0.32

@export_group("地点名称与生态颜色")
## 场景内部标识到中文名称的映射；新增场景时在此补充，键可含 _t1 后缀。
@export var room_names: Dictionary[String, String] = {}
## 生态内部标识到显示名称的映射；跨生态时在上方单独显示生态名。
@export var biome_names: Dictionary[String, String] = {
	"wood": "木之生态", "earth": "土之生态", "water": "水之生态",
	"fire": "火之生态", "gold": "金之生态", "normal": "原野"
}
## 各生态装饰细线的颜色；没有配置时使用正文颜色。
@export var biome_colors: Dictionary[String, Color] = {
	"wood": Color("a6d695"), "earth": Color("e0bb87"), "water": Color("8ecfe4"),
	"fire": Color("eea080"), "gold": Color("ebd186"), "normal": Color("d8d3b8")
}
