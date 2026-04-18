## 行动对象 (Action)
## 用于封装战斗中的一次具体行为（如出牌、攻击、施放技能等）。
## 该对象会被推入 BattleManager 的行动队列 (action_queue) 中，
## 然后在状态机切换至 EXECUTE_ACTIONS 状态时被依次解析并执行。
class_name Action
extends RefCounted

## 来源：执行此行动的实体。
## 可以是 PlayerManager（玩家） 或 Monster（怪物）。
var source: Variant

## 目标数组：此行动的作用对象。
## 允许为多目标技能或群体攻击保留扩展性（如果是单体目标则数组长度为 1）。
var targets: Array

## 相关的卡牌数据或技能数据（如果有）。
## 主要是针对玩家打出卡牌时，保存打出的是哪张卡，以便后续调用卡牌的 ApplyEffect 效果结算。
var card_data: Resource

## 播放的动画名称。
## 用于在解析此行动时，触发相应的角色或特效表现。
var animation_name: String

## 行动类型。
## 用于区分这是什么行为，例如："CARD"（打出卡牌）, "ATTACK"（普通攻击）, "SKILL"（怪物技能）等。
## 在 BattleManager 的 _execute_single_action() 中会根据此字段执行不同的逻辑分支。
var action_type: String

## 构造函数：初始化一个新的行动对象并直接赋值给成员变量。
func _init(p_source: Variant, p_targets: Array, p_card_data: Resource = null, p_animation_name: String = "", p_action_type: String = "CARD") -> void:
	source = p_source
	targets = p_targets
	card_data = p_card_data
	animation_name = p_animation_name
	action_type = p_action_type
