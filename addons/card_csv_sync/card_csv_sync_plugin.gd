@tool
extends EditorPlugin

const MENU_EXPORT := "导出卡牌 CSV"
const MENU_IMPORT := "应用卡牌 CSV"
const MENU_SYNC := "同步卡牌 CSV"
const EXPORT_SCRIPT_PATH := "res://tools/card_csv/export_current_cards.py"
const SKILL_CSV_PATH := "res://tools/card_csv/skill_cards.csv"
const MONSTER_CSV_PATH := "res://tools/card_csv/monster_cards.csv"
const POLL_INTERVAL_SECONDS := 5.0
const RESCAN_DELAY_SECONDS := 0.5

var _elapsed_seconds := 0.0
var _is_syncing := false
var _rescan_requested := false


func _enter_tree() -> void:
	add_tool_menu_item(MENU_EXPORT, Callable(self, "_export_from_menu"))
	add_tool_menu_item(MENU_IMPORT, Callable(self, "_import_from_menu"))
	add_tool_menu_item(MENU_SYNC, Callable(self, "_sync_from_menu"))
	set_process(true)
	call_deferred("_run_auto_script")


func _exit_tree() -> void:
	set_process(false)
	remove_tool_menu_item(MENU_EXPORT)
	remove_tool_menu_item(MENU_IMPORT)
	remove_tool_menu_item(MENU_SYNC)


func _process(delta: float) -> void:
	_elapsed_seconds += delta
	if _elapsed_seconds < POLL_INTERVAL_SECONDS or _is_syncing:
		return

	_elapsed_seconds = 0.0
	_run_auto_script()



## 手动导出入口，保留在菜单中便于表格异常时快速重新生成。
func _export_from_menu() -> void:
	_run_export_script()


## 手动导入入口，用于立即把外部表格修改写回 `.tres` 资源。
func _import_from_menu() -> void:
	_run_import_script()


## 手动双向同步入口，先导入 CSV，再重新导出最新表格。
func _sync_from_menu() -> void:
	_run_sync_script()


## 调用 Python 自动同步脚本，由 Python 根据 CSV 状态文件判断导入或导出。
func _run_auto_script() -> void:
	var output := _run_python_script(["--auto"])
	if output.contains("已导入"):
		_queue_rescan_filesystem()


## 调用 Python 导出脚本生成 CSV。
## 这里刻意保持插件脚本本身非常轻量，避免 EditorPlugin 加载阶段直接解析或实例化 C# 资源导致插件被禁用。
func _run_export_script() -> void:
	_run_python_script([])
	print("Card CSV Sync：CSV 已导出到 res://tools/card_csv。")


## 调用 Python 导入脚本，把 CSV 回写到资源。
func _run_import_script() -> void:
	_run_python_script(["--import"])
	_queue_rescan_filesystem()
	print("Card CSV Sync：CSV 已应用到 Godot 资源。")


## 调用 Python 双向同步脚本，适合外部表格保存后自动执行。
func _run_sync_script() -> void:
	_run_python_script(["--sync"])
	_queue_rescan_filesystem()
	print("Card CSV Sync：CSV 与 Godot 资源已双向同步。")


func _run_python_script(arguments: Array) -> String:
	if _is_syncing:
		return ""

	_is_syncing = true
	var script_path := ProjectSettings.globalize_path(EXPORT_SCRIPT_PATH)
	var output := []
	var command_arguments := [script_path]
	command_arguments.append_array(arguments)
	var exit_code := OS.execute("python", command_arguments, output, true, false)
	if exit_code != 0:
		push_error("Card CSV Sync：执行同步脚本失败，退出码：%s，输出：%s" % [exit_code, "\n".join(output)])
		_is_syncing = false
		return "\n".join(output)

	_is_syncing = false
	return "\n".join(output)


func _queue_rescan_filesystem() -> void:
	if _rescan_requested:
		return

	_rescan_requested = true
	call_deferred("_rescan_filesystem_when_idle")


func _rescan_filesystem_when_idle() -> void:
	await get_tree().create_timer(RESCAN_DELAY_SECONDS).timeout
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem != null:
		if filesystem.has_method(&"is_scanning") and filesystem.is_scanning():
			_rescan_requested = false
			_queue_rescan_filesystem()
			return
		filesystem.scan()
	_rescan_requested = false


func _get_latest_resource_time(directory_path: String) -> int:
	var latest := 0
	var dir := DirAccess.open(directory_path)
	if dir == null:
		return latest

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if file_name.begins_with("."):
			file_name = dir.get_next()
			continue

		var child_path := directory_path + "/" + file_name
		if dir.current_is_dir():
			latest = max(latest, _get_latest_resource_time(child_path))
		elif child_path.ends_with(".tres"):
			latest = max(latest, FileAccess.get_modified_time(child_path))
		file_name = dir.get_next()
	dir.list_dir_end()
	return latest
