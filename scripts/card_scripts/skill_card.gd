extends Node2D
class_name SkillCard

signal hovered
signal hovered_off

var hand_position #手牌位置
var data:SkillCardData
var is_lock:bool = false
const CONTEXT_SCRIPT_PATH : String = "res://core/combat/skills/SkillExecutionContext.cs"

#该节点必须挂载在CardManager下！
func _ready() -> void:
	get_parent().connect_card_signals(self)

func _process(delta: float) -> void:
	pass

func use(target: Node = null):
	if target:
		print(data.CardName,"被使用，目标为",target.BaseData.MonsterName)
	else:
		print(data.CardName,"被使用，没有目标")
		
	var source = get_node_or_null("../../PlayerManager")
	if not source:
		source = get_tree().current_scene.get_node_or_null("PlayerManager")
	if not source:
		source = self
		
	if data.has_method("ApplyEffect"):
			var ContextClass = load(CONTEXT_SCRIPT_PATH)
			var context = null
			
			if target:
				context = ContextClass.FromSingleTarget(source, target)
			else:
				context = ContextClass.Self(source)
				
			data.ApplyEffect(context)

func init_card_data(card_data):
	data = card_data
	$CardName.text = data.CardName
	$CardDescription.text = data.Description
	$CardCost.text = str(data.cost)

func _on_area_2d_mouse_entered() -> void:
	if is_lock:
		return
	emit_signal("hovered", self)

func _on_area_2d_mouse_exited() -> void:
	if is_lock:
		return
	emit_signal("hovered_off", self)

func lock():
	$LockColor.visible = true
	is_lock = true

func unlock():
	$LockColor.visible = false
	is_lock = false
