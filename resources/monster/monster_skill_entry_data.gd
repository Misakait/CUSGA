extends Resource

## 描述怪物技能集合中的单个战斗技能及其预览显示策略。
##
## `Skill` 保持为通用 Resource，以便 C# CombatSkillData 和 GDScript 技能资源
## 可以在迁移期间共存；运行时消费者仍通过稳定的 Description 字段读取技能说明。

## 怪物实际使用的战斗技能资源。
@export var Skill: Resource

## 是否在怪物预览面板中显示该技能。
@export var VisibleInPreview: bool = true

## 覆盖技能自身 Description 的预览文本；为空白时回退到技能说明。
@export_multiline var PreviewDescriptionOverride: String = ""


## 获取用于怪物预览的技能说明。
##
## 返回值：优先返回非空白覆盖文本，否则返回 Skill 的 Description 字段；
## 缺少技能或说明时返回空字符串。
func GetPreviewDescription() -> String:
	if not PreviewDescriptionOverride.strip_edges().is_empty():
		return PreviewDescriptionOverride
	if Skill == null:
		return ""

	var description: Variant = Skill.get("Description")
	if description == null:
		return ""
	return str(description)
