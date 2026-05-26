extends SceneTree

const CODEGEN_PATH := "res://addons/skill_targeting_type_codegen/skill_targeting_type_codegen.gd"

var _failures: Array[String] = []


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var codegen_script: GDScript = load(CODEGEN_PATH)
	_assert(codegen_script != null, "技能目标类型代码生成器脚本必须存在。")
	if codegen_script == null:
		_finish()
		return

	_test_parser_preserves_csharp_enum_values(codegen_script)
	_test_renderer_emits_native_gdscript_enum(codegen_script)
	_test_missing_output_requires_regeneration(codegen_script)
	_test_checked_in_file_matches_current_csharp_enum(codegen_script)

	_finish()


func _test_parser_preserves_csharp_enum_values(codegen_script: GDScript) -> void:
	var source := """
namespace CUSGA.core.combat.skills;

public enum SkillTargetingType
{
    Self,
    SingleEnemy = 4,
    // 注释不应影响后续隐式值
    AllEnemies,
    /* 块注释也不应进入枚举项 */
    [Obsolete]
    AnySingleUnit = -2,
    AllUnits
}
"""

	var result: Dictionary = codegen_script.parse_enum_members(source, "SkillTargetingType")

	_assert(bool(result.get("ok", false)), "解析器应当成功解析 SkillTargetingType 枚举。")
	var members: Array = result.get("members", [])
	_assert(members.size() == 5, "解析器应当只返回真实枚举项。")
	_assert(_member_value(members, "Self") == 0, "首个隐式枚举值应当从 0 开始。")
	_assert(_member_value(members, "SingleEnemy") == 4, "显式赋值应当覆盖当前枚举值。")
	_assert(_member_value(members, "AllEnemies") == 5, "显式赋值后的隐式项应当继续递增。")
	_assert(_member_value(members, "AnySingleUnit") == -2, "解析器应当支持负数显式枚举值。")
	_assert(_member_value(members, "AllUnits") == -1, "负数显式赋值后的隐式项应当继续递增。")


func _test_renderer_emits_native_gdscript_enum(codegen_script: GDScript) -> void:
	var members: Array[Dictionary] = [
		{"name": "Self", "value": 0},
		{"name": "SingleEnemy", "value": 1},
		{"name": "AllEnemies", "value": 2},
	]

	var rendered: String = codegen_script.render_gdscript("SkillTargetingType", "res://core/combat/skills/SkillTargetingType.cs", members)

	_assert("class_name SkillTargetingType" in rendered, "生成文件应当注册 SkillTargetingType 类型。")
	_assert("enum Value" in rendered, "生成文件应当使用原生 GDScript enum。")
	_assert("\tSelf = 0," in rendered, "生成文件应当保留 Self 的枚举值。")
	_assert("\tSingleEnemy = 1," in rendered, "生成文件应当保留 SingleEnemy 的枚举值。")
	_assert("static func get_map() -> Dictionary:" in rendered, "生成文件应当保留名称到枚举值的查询入口。")


func _test_missing_output_requires_regeneration(codegen_script: GDScript) -> void:
	_assert(codegen_script.has_method("should_generate"), "生成器应当提供可测试的触发判断。")
	if not codegen_script.has_method("should_generate"):
		return

	var missing_output_path := "user://skill_targeting_type_codegen_tests/missing_output.gd"
	var absolute_output_path := ProjectSettings.globalize_path(missing_output_path)
	if FileAccess.file_exists(missing_output_path):
		DirAccess.remove_absolute(absolute_output_path)

	var source_modified_time := FileAccess.get_modified_time(codegen_script.SOURCE_PATH)
	var should_generate: bool = codegen_script.should_generate(
		codegen_script.SOURCE_PATH,
		missing_output_path,
		source_modified_time,
		false
	)

	_assert(should_generate, "生成文件缺失时，即使 C# 源文件未变化，也必须触发重新生成。")


func _test_checked_in_file_matches_current_csharp_enum(codegen_script: GDScript) -> void:
	var source_text := _read_text(codegen_script.SOURCE_PATH)
	var generated_text := _read_text(codegen_script.OUTPUT_PATH)
	_assert(not source_text.is_empty(), "测试应当能读取 C# 枚举源文件。")
	_assert(not generated_text.is_empty(), "测试应当能读取已生成的 GDScript 枚举文件。")
	if source_text.is_empty() or generated_text.is_empty():
		return

	var result: Dictionary = codegen_script.parse_enum_members(source_text, codegen_script.ENUM_NAME)
	_assert(bool(result.get("ok", false)), "当前 SkillTargetingType.cs 应当能被生成器解析。")
	if not bool(result.get("ok", false)):
		return

	var expected: String = codegen_script.render_gdscript(codegen_script.ENUM_NAME, codegen_script.SOURCE_PATH, result["members"])
	_assert(generated_text == expected, "已提交的 SkillTargetingType.gd 必须与当前 C# 枚举完全同步。")


func _member_value(members: Array, member_name: String) -> int:
	for member in members:
		if member.get("name", "") == member_name:
			return int(member.get("value", 0))
	return -999999


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("All SkillTargetingType codegen Godot tests passed.")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)
