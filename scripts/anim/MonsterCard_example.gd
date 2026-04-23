## MonsterCard.gd — 怪物卡牌使用示例
## 展示原子方法和复合方法的实际调用方式。
##
## 场景树：
##   MonsterCard (Node2D)  ← 挂载本脚本
##   ├── Sprite2D           ← Inspector 指定给 CardAnimator.card_sprite
##   └── CardAnimator       ← 挂载 CardAnimator.gd（可选）
class_name MonsterCard
extends Node2D

@onready var animator: CardAnimator = $CardAnimator if has_node("CardAnimator") else null

var _health: int = 30


func _ready() -> void:
	# 怪物出场后开始待机微动
	if animator:
		animator.start_idle()


## 受到攻击 —— 用原子方法自由组合
func take_damage(amount: int) -> void:
	_health -= amount

	if animator:
		# 也可以直接用复合方法 animator.play_hit()
		# 这里演示原子方法组合：先闪红再抖动
		animator.flash_red(0.12)
		await animator.shake_x(12.0).finished
	else:
		queue_free()
		
	if _health <= 0:
		die()


## 死亡 —— 停止待机，播放死亡动画
func die() -> void:
	if animator:
		animator.stop_idle()
		await animator.play_death()
	else:
		queue_free()


func _on_button_button_down() -> void:
	take_damage(3)
