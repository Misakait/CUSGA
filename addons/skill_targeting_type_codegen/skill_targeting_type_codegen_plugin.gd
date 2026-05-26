@tool
extends EditorPlugin

const Codegen := preload("res://addons/skill_targeting_type_codegen/skill_targeting_type_codegen.gd")
const POLL_INTERVAL_SECONDS := 5

var _elapsed_seconds := 0.0
var _last_source_modified_time := -1


func _enter_tree() -> void:
	_elapsed_seconds = 0.0
	_last_source_modified_time = -1
	set_process(true)
	_regenerate_if_source_changed(true)


func _exit_tree() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_elapsed_seconds += delta
	if _elapsed_seconds < POLL_INTERVAL_SECONDS:
		return

	_elapsed_seconds = 0.0
	_regenerate_if_source_changed(false)


func _regenerate_if_source_changed(force: bool) -> void:
	var modified_time := FileAccess.get_modified_time(Codegen.SOURCE_PATH)
	if not Codegen.should_generate(Codegen.SOURCE_PATH, Codegen.OUTPUT_PATH, _last_source_modified_time, force):
		return

	_last_source_modified_time = modified_time
	var result: Dictionary = Codegen.generate()
	if not bool(result.get("ok", false)):
		push_error(str(result.get("message", "SkillTargetingType 代码生成失败。")))
		return

	if bool(result.get("changed", false)):
		print(str(result.get("message", "已生成 SkillTargetingType.gd。")))
		_rescan_editor_filesystem()


func _rescan_editor_filesystem() -> void:
	call_deferred(&"_rescan_editor_filesystem_when_idle")


func _rescan_editor_filesystem_when_idle() -> void:
	# 生成文件后主动刷新资源系统，让 class_name 和 enum 立即可用。
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem != null:
		if filesystem.has_method(&"is_scanning") and filesystem.is_scanning():
			await get_tree().create_timer(0.2).timeout
			_rescan_editor_filesystem_when_idle()
			return

		filesystem.scan()
