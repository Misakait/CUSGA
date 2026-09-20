extends RefCounted

## 怪物技能在预览界面中的只读展示值对象。
##
## 技能本体继续由现有 C# CombatSkillData 或未来 GDScript Resource 提供；本对象只复制
## UI 需要的稳定字段，避免预览层直接依赖技能集合或战斗执行组件。

## 技能稳定标识，保持来源 CombatSkillData.CardId。
var SkillId: StringName = &""
## 技能显示名称，保持来源 CombatSkillData.CardName。
var DisplayName: String = ""
## 技能预览说明，优先使用条目覆盖文本。
var Description: String = ""
## 技能显示图标，保持来源 CombatSkillData.CardIcon。
var Icon: Texture2D = null
## 技能元素枚举整数，保持 C# ElementType 数值。
var Element: int = 0
## 便于跨语言读取的元素整数别名。
var ElementId: int = 0
## 技能目标类型枚举整数，保持 C# SkillTargetingType 数值。
var TargetingType: int = 0
## 便于跨语言读取的目标类型整数别名。
var TargetingTypeId: int = 0


## 从战斗技能和预览说明创建只读展示快照。
## 参数 skill：提供 CardId、CardName、CardIcon、Element 和 TargetingType 的技能 Resource。
## 参数 description：技能条目解析出的预览说明文本。
## 返回值：无；字段在构造时复制并保持稳定。
func _init(skill: Resource = null, description: String = "") -> void:
	if skill == null:
		return
	SkillId = _read_string_name(skill, &"CardId")
	DisplayName = str(skill.get("CardName"))
	Description = description
	Icon = skill.get("CardIcon") as Texture2D
	Element = int(skill.get("Element"))
	ElementId = Element
	TargetingType = int(skill.get("TargetingType"))
	TargetingTypeId = TargetingType


## 安全读取跨语言 StringName 字段，缺失时保持空标识。
## 参数 source：待读取的技能 Resource。
## 参数 property_name：属性名称。
## 返回值：StringName 形式的字段值。
func _read_string_name(source: Resource, property_name: StringName) -> StringName:
	var value: Variant = source.get(property_name)
	if value is StringName:
		return value
	return StringName(str(value))
