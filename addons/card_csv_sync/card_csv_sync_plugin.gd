@tool
extends EditorPlugin

const MENU_EXPORT := "导出卡牌 CSV"
const MENU_IMPORT := "应用卡牌 CSV"
const MENU_SYNC := "同步卡牌 CSV"
const EXPORT_SCRIPT_PATH := "res://card_table/export_current_cards.py"
const RESCAN_DELAY_SECONDS := 0.5

var _is_syncing := false
var _rescan_requested := false


func _enter_tree() -> void:
	add_tool_menu_item(MENU_EXPORT, Callable(self, "_export_from_menu"))
	add_tool_menu_item(MENU_IMPORT, Callable(self, "_import_from_menu"))
	add_tool_menu_item(MENU_SYNC, Callable(self, "_sync_from_menu"))


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_EXPORT)
	remove_tool_menu_item(MENU_IMPORT)
	remove_tool_menu_item(MENU_SYNC)


## 手动导出入口，保留在菜单中便于表格异常时快速重新生成。
func _export_from_menu() -> void:
	_run_export_script()


## 手动导入入口，用于立即把外部表格修改写回 `.tres` 资源。
func _import_from_menu() -> void:
	_run_import_script()


## 手动双向同步入口，先导入 CSV，再重新导出最新表格。
func _sync_from_menu() -> void:
	_run_sync_script()


## 调用 Python 导出脚本生成 CSV。
## 这里刻意保持插件脚本本身非常轻量，避免 EditorPlugin 加载阶段直接解析或实例化 C# 资源导致插件被禁用。
func _run_export_script() -> void:
	var output := _run_python_script([])
	if not output.is_empty():
		print(output)
	print("Card CSV Sync：CSV 已导出到 res://card_table。")


## 调用 Python 导入脚本，把 CSV 回写到资源。
func _run_import_script() -> void:
	var output := _run_python_script(["--import"])
	if not output.is_empty():
		print(output)
	_queue_rescan_filesystem()
	print("Card CSV Sync：CSV 已应用到 Godot 资源。")


## 调用 Python 双向同步脚本，适合手动把外部表格修改应用回 Godot。
func _run_sync_script() -> void:
	var output := _run_python_script(["--sync"])
	if not output.is_empty():
		print(output)
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
