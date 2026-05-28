extends Node2D
class_name SkillCard

signal hovered
signal hovered_off

var hand_position #手牌位置
var data:SkillCardData
var is_lock:bool = false
const CONTEXT_SCRIPT_PATH : String = "res://core/combat/skills/SkillExecutionContext.cs"
const ELEMENT_DISPLAY_NAMES := {
	0: "无",
	1: "木",
	2: "金",
	3: "水",
	4: "土",
	5: "火",
	"None": "无",
	"Wood": "木",
	"Metal": "金",
	"Water": "水",
	"Earth": "土",
	"Fire": "火",
}

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
	# 调用 SkillCardData.cs 的 DisplayName 属性获取实际显示的名称（如果没有独立命名则获取技能名称）
	$CardName.text = data.DisplayName
	# CardElement 只展示真实战斗技能 CombatSkillData 的五行属性，避免卡牌包装层和战斗结算数据不一致。
	$CardElement.text = _get_combat_skill_element_display_text(data)
	$CardElement.visible = not $CardElement.text.is_empty()
	# 调用 SkillCardData.cs 的 DisplayDescription 属性获取实际显示的描述（如果没有独立描述则获取技能描述）
	$CardDescription.text = data.DisplayDescription
	# 调用 SkillCardData.cs 的 DisplayTag 属性获取实际显示的标签（多个标签以换行分隔）
	$CardTag.text = data.DisplayTag
	$CardTag.visible = not $CardTag.text.is_empty()
	$CardCost.text = str(data.cost)

func _get_combat_skill_element_display_text(card_data) -> String:
	# 技能卡本身只是玩家卡牌包装，元素来源必须取自关联的 CombatSkillData.Skill，确保 UI 显示和实际战斗技能一致。
	if card_data == null or card_data.Skill == null:
		return ""

	var element = card_data.Skill.Element
	if ELEMENT_DISPLAY_NAMES.has(element):
		return ELEMENT_DISPLAY_NAMES[element]

	var element_text := str(element)
	if ELEMENT_DISPLAY_NAMES.has(element_text):
		return ELEMENT_DISPLAY_NAMES[element_text]

	return element_text

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
