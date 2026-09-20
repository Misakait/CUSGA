extends Node

## 怪物战斗技能集合组件的并行 GDScript 实现。
##
## 组件只读取 SkillSet 的 Skills 数组和条目协议，保留旧 C# MonsterSkillSetData、
## MonsterSkillEntryData 与 CombatSkillData 的 Resource 身份；战斗执行仍由技能本体负责。

## 怪物技能集合 Resource；可承载旧 C# 或 GDScript 实现。
@export var SkillSet: Resource

## 预览值对象脚本，避免声明会与 C# 类型冲突的 class_name。
const MONSTER_SKILL_PREVIEW_SCRIPT: GDScript = preload("res://resources/monster/monster_skill_preview.gd")


## 场景加载后校验技能集合，保持旧组件的诊断时机。
## 返回值：无。
func _ready() -> void:
	_validate_skill_set()


## 在运行时替换当前怪物技能集合并立即校验。
## 参数 skill_set：包含 Skills 数组的旧 C# 或 GDScript Resource。
## 返回值：无。
func Initialize(skill_set: Resource) -> void:
	SkillSet = skill_set
	_validate_skill_set()


## 获取当前怪物配置的非空战斗技能。
## 返回值：按配置顺序排列、仅包含有效 Skill Resource 的数组。
func GetCombatSkills() -> Array[Resource]:
	var result: Array[Resource] = []
	for entry: Resource in _read_skill_entries():
		var skill := _read_combat_skill(entry)
		if skill != null:
			result.append(skill)
	return result


## 为怪物自动回合选择一个已配置的战斗技能。
## 返回值：随机有效技能；没有技能时返回 null。
func GetRandomCombatSkill() -> Resource:
	var skills := GetCombatSkills()
	if skills.is_empty():
		return null
	return skills[randi() % skills.size()]


## 构建用于 UI 预览的只读展示数据。
## 返回值：按配置顺序排列、仅包含可见且有效技能的预览值对象。
func GetSkillPreviews() -> Array[RefCounted]:
	var result: Array[RefCounted] = []
	for entry: Resource in _read_skill_entries():
		if entry == null or not _read_visible_in_preview(entry):
			continue
		var skill := _read_combat_skill(entry)
		if skill == null:
			continue
		result.append(MONSTER_SKILL_PREVIEW_SCRIPT.new(skill, _read_preview_description(entry)))
	return result


## 校验集合及条目，保留旧 C# 组件的 warning 语义而不阻断战斗启动。
func _validate_skill_set() -> void:
	if SkillSet == null:
		push_warning("%s has no MonsterSkillSetData." % _host_name())
		return
	for entry: Resource in _read_skill_entries():
		if entry == null:
			push_warning("%s has null skill entry in MonsterSkillSetData." % _host_name())
			continue
		if _read_combat_skill(entry) == null:
			push_warning("%s has MonsterSkillEntryData with null CombatSkillData." % _host_name())


## 读取技能集合中的条目数组，并兼容 C# Godot.Collections.Array。
## 返回值：过滤掉非 Resource 值后的技能条目数组。
func _read_skill_entries() -> Array[Resource]:
	var result: Array[Resource] = []
	if SkillSet == null:
		return result
	var raw_skills: Variant = SkillSet.get("Skills")
	if raw_skills == null or not (raw_skills is Array):
		return result
	for value: Variant in raw_skills:
		if value is Resource:
			result.append(value as Resource)
		else:
			# 保留空值的位置供校验诊断，但公开技能列表会自动跳过它。
			result.append(null)
	return result


## 从技能条目中读取 CombatSkillData 或兼容的技能 Resource。
## 参数 entry：待读取的技能条目 Resource。
## 返回值：条目中的技能 Resource；字段缺失或为空时返回 null。
func _read_combat_skill(entry: Resource) -> Resource:
	if entry == null:
		return null
	var value: Variant = entry.get("Skill")
	return value as Resource


## 读取预览可见标志；字段缺失时按旧默认值 true 处理。
## 参数 entry：待读取的技能条目 Resource。
## 返回值：是否应显示在技能预览中。
func _read_visible_in_preview(entry: Resource) -> bool:
	if entry == null:
		return false
	var value: Variant = entry.get("VisibleInPreview")
	return true if value == null else bool(value)


## 读取技能条目的预览说明，保持覆盖文本和技能描述回退顺序。
## 参数 entry：待读取的技能条目 Resource。
## 返回值：预览说明；缺少方法时返回空字符串。
func _read_preview_description(entry: Resource) -> String:
	if entry == null or not entry.has_method("GetPreviewDescription"):
		return ""
	return str(entry.call("GetPreviewDescription"))


## 返回宿主节点名称，供 warning 保持旧诊断上下文。
## 返回值：父节点名称；没有父节点时返回空字符串。
func _host_name() -> String:
	var host := get_parent()
	return "" if host == null else str(host.name)
