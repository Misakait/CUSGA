extends Node

## 全屏黑幕过场；成对切换时可在淡出结束后持续遮挡场景装配。

signal fade_complete()
signal fade_in_complete()

@onready var fade_to_black: ColorRect = $CanvasLayer/FadeToBlack
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	fade_to_black.hide()

## 从全黑淡入新画面，完成后移除遮罩并发出 fade_in_complete。
## 参数：无。返回值：无；可等待本方法完成。
func fade_in() -> void:
	animation_player.stop()
	animation_player.play("screen_transition")
	# play 的轨道通常要到下一帧才生效；先应用起点，避免先露出新场景再突然变黑。
	animation_player.advance(0.0)
	fade_to_black.show()
	
	await animation_player.animation_finished
	fade_to_black.hide()
	fade_in_complete.emit()
	
## 将当前画面淡出至全黑，完成时发出 fade_complete。
## 参数 keep_black：true 时保持全黑直到调用 fade_in，遮住跨帧场景与相机切换；
## 默认 false 兼容仅调用淡出的旧菜单、地图入口，由它们继续原有结束行为。
## 返回值：无；可等待本方法完成。
func fade_out(keep_black: bool = false) -> void:
	animation_player.stop()
	animation_player.play_backwards("screen_transition")
	# 上次动画可能留下不透明色，必须先应用反向播放起点再显示遮罩，避免首帧闪黑。
	animation_player.advance(0.0)
	fade_to_black.show()
	
	await animation_player.animation_finished
	# 战斗入口在下一帧才继续，提前隐藏会把探索画面闪回一次。
	if not keep_black:
		fade_to_black.hide()
	
	fade_complete.emit()
