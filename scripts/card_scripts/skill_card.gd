extends Node2D
class_name SkillCard

signal hovered
signal hovered_off

var hand_position #手牌位置
var data: Resource
var is_lock:bool = false
const CONTEXT_SCRIPT_PATH : String = "res://core/combat/skills/skill_execution_context.gd"
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
	#【修订说明】原实现无条件调用父节点的 connect_card_signals，隐含了「父节点必定是 CardManager」。
	# 开局技能卡抽取界面（core/gameflow/run_start_skill_card_draft.gd）要复用同一份卡面，
	# 但它的父节点是普通占位控件，无条件调用会直接抛错。因此改为存在性守卫：
	# 战斗路径下父节点始终是 CardManager（scripts/card_scripts/card_manager.gd:1019 提供该方法），
	# 守卫恒为真、连接照旧发生，战斗行为不变；非战斗场景跳过连接即可安全实例化。
	# 上面那条「必须挂载在 CardManager 下」的注释描述的是战斗路径的既有约定，本守卫只解除这条隐含依赖。
	var card_host: Node = get_parent()
	if card_host != null and card_host.has_method("connect_card_signals"):
		card_host.call("connect_card_signals", self)

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

func init_card_data(card_data: Resource) -> void:
	data = card_data
	# 通过稳定显示属性获取名称，使 C# 与 GDScript SkillCardData 共用同一界面路径。
	$CardName.text = data.DisplayName
	# CardElement 只展示真实战斗技能 CombatSkillData 的五行属性，避免卡牌包装层和战斗结算数据不一致。
	$CardElement.text = _get_combat_skill_element_display_text(data)
	$CardElement.visible = not $CardElement.text.is_empty()
	# 通过稳定显示属性获取描述，保留卡牌独立文本优先、技能文本回退的语义。
	$CardDescription.text = data.DisplayDescription
	# 通过稳定显示属性获取标签，多个标签继续以换行分隔。
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
