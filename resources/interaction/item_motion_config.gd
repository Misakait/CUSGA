extends Resource

## Item 的视觉动作参数；只影响 Visuals，不改变实体与鼠标命中形状。

## 待机呼吸循环时长，单位为真实秒。
@export_range(0.2, 10.0, 0.05) var IdleDuration: float = 1.8
## 待机呼吸在基础缩放上额外放大的比例。
@export_range(0.0, 0.25, 0.005) var IdleScaleAmplitude: float = 0.03
## 待机中点的颜色；末尾恢复白色。
@export var IdleTint: Color = Color(1.0, 0.97, 0.90, 1.0)
## 悬停挤压与回弹的总时长，单位为真实秒。
@export_range(0.1, 1.0, 0.01) var HoverDuration: float = 0.25
## 悬停初段横向挤压、纵向拉伸倍率。
@export var HoverSquash: Vector2 = Vector2(0.92, 1.08)
## 悬停中段横向拉伸、纵向挤压倍率。
@export var HoverStretch: Vector2 = Vector2(1.08, 0.95)
## 悬停结束时保留的高亮倍率，离开后恢复待机。
@export var HoverRest: Vector2 = Vector2(1.04, 1.04)
## 悬停的高亮颜色。
@export var HoverTint: Color = Color(1.0, 1.0, 0.82, 1.0)
## 掉落散射时长，单位为真实秒。
@export_range(0.05, 2.0, 0.01) var ScatterDuration: float = 0.35
## 拾取飞入玩家的时长，单位为真实秒。
@export_range(0.05, 2.0, 0.01) var PickupDuration: float = 0.30
