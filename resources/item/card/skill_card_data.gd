extends "res://resources/item/item_data.gd"

## 玩家技能卡的生产 GDScript Resource。
##
## 卡牌包装层只保存显示、费用和标签，并把实际效果委托给保留的 CombatSkillData。
## 该脚本不声明 class_name，避免与继续作为兼容输入的 C# SkillCardData 全局类型重名。

## 实际战斗技能 Resource；迁移期继续接受 C# CombatSkillData。
@export var Skill: Resource

## 打出卡牌消耗的能量；默认值保持为 10。
@export var cost: int = 10

## 卡牌展示标签；空白标签不会进入最终换行文本。
@export var CardTags: Array[String] = []

## 过滤空白标签后生成逐行展示文本。
var DisplayTag: String:
	get:
		var tags: Array[String] = []
		for tag: String in CardTags:
			if not tag.strip_edges().is_empty():
				tags.append(tag)
		return "\n".join(tags)

## 从实际战斗技能读取五行枚举值；缺少技能时回退到 None 的数值 0。
var Element: int:
	get:
		if Skill == null:
			return 0
		var value: Variant = Skill.get("Element")
		return 0 if value == null else int(value)

## 技能卡始终按单张占用库存槽位。
func _resolve_actual_max_stack_size() -> int:
	return 1

## 优先使用卡牌独立名称，否则回退到实际战斗技能名称。
func _resolve_display_name() -> String:
	if not CardName.strip_edges().is_empty():
		return CardName
	if Skill == null:
		return ""
	var value: Variant = Skill.get("CardName")
	return "" if value == null else String(value)

## 优先使用卡牌独立描述，否则回退到实际战斗技能描述。
func _resolve_display_description() -> String:
	if not Description.strip_edges().is_empty():
		return Description
	if Skill == null:
		return ""
	var value: Variant = Skill.get("Description")
	return "" if value == null else String(value)

## 优先使用卡牌独立图标，否则回退到实际战斗技能图标。
func _resolve_display_icon() -> Texture2D:
	if CardIcon != null:
		return CardIcon
	if Skill == null:
		return null
	var value: Variant = Skill.get("CardIcon")
	return value as Texture2D if value is Texture2D else null

## 执行卡牌效果，并把权威结算委托给 CombatSkillData。
## 参数 context：包含施放者与目标的 C# SkillExecutionContext。
## 返回值：无。
func ApplyEffect(context: RefCounted) -> void:
	if Skill == null:
		push_error("SkillCardData '%s' has no CombatSkillData assigned." % CardName)
		return
	if context == null:
		push_error("SkillCardData '%s' executed with null context." % CardName)
		return
	if not Skill.has_method("Execute"):
		push_error("SkillCardData '%s' references a skill without Execute." % CardName)
		return

	var log_name: String = DisplayName
	if log_name.strip_edges().is_empty():
		log_name = CardName
	if log_name.strip_edges().is_empty():
		log_name = String(CardId)
	print("玩家打出了卡牌：%s" % log_name)
	Skill.call("Execute", context)
