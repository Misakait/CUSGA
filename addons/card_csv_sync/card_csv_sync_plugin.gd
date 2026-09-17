@tool
extends EditorPlugin

const MENU_OPEN_TABLE := "打开卡牌表格"
const MENU_SAFE_SYNC := "安全同步卡牌表格"
const EXPORT_SCRIPT_PATH := "res://card_table/export_current_cards.py"
const XLSX_FILE_PATH := "res://card_table/card_tables.xlsx"
const RESULT_FILE_PATH := "res://card_table/.card_csv_sync_result.json"
const RESULT_PREFIX := "CARD_CSV_SYNC_RESULT="
const RESCAN_DELAY_SECONDS := 0.5
const USAGE_METADATA_SECTION := "card_csv_sync"
const USAGE_METADATA_KEY := "has_seen_usage_guide"

# 防止重复点击时并发改写同一组表格与资源。
var _is_syncing := false
# 合并连续成功同步后的资源扫描请求，避免编辑器重复扫描整个项目。
var _rescan_requested := false
# 在用户明确确认前暂存安全同步动作，避免误点直接改写资源。
var _sync_confirmation_dialog: ConfirmationDialog
# 首次打开表格时展示一次操作顺序，降低非程序使用者误改双端数据的概率。
var _usage_guide_dialog: ConfirmationDialog
# 使用编辑器内对话框展示最终结果，减少用户查找输出面板的成本。
var _result_dialog: AcceptDialog


func _enter_tree() -> void:
	_add_result_dialogs()
	add_tool_menu_item(MENU_OPEN_TABLE, Callable(self, "_open_card_table"))
	add_tool_menu_item(MENU_SAFE_SYNC, Callable(self, "_request_safe_sync"))


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_OPEN_TABLE)
	remove_tool_menu_item(MENU_SAFE_SYNC)
	if is_instance_valid(_sync_confirmation_dialog):
		_sync_confirmation_dialog.queue_free()
	if is_instance_valid(_usage_guide_dialog):
		_usage_guide_dialog.queue_free()
	if is_instance_valid(_result_dialog):
		_result_dialog.queue_free()


## 初始化确认与结果对话框，使插件流程保持在 Godot 编辑器内完成。
func _add_result_dialogs() -> void:
	# 以编辑器根控件承载弹窗，避免在关闭插件时留下独立窗口。
	var editor_root: Control = EditorInterface.get_base_control()
	_sync_confirmation_dialog = ConfirmationDialog.new()
	_sync_confirmation_dialog.title = "安全同步卡牌表格"
	_sync_confirmation_dialog.dialog_text = "同步前请确认：\n1. 修改表格后，必须先保存并关闭 Excel/WPS；表格较新时会写回 Godot 卡牌。\n2. 在 Godot 修改卡牌后，先保存资源；资源较新时会导出到表格。\n3. 不要同时修改同一张卡牌的表格和 Godot 资源，否则会以较新的文件为准。\n4. XLSX 正在打开时只能生成 pending 表格，关闭后需再同步一次。\n\n将先校验表格、备份受影响资源，再执行同步。是否继续？"
	_sync_confirmation_dialog.confirmed.connect(_perform_safe_sync)
	editor_root.add_child(_sync_confirmation_dialog)
	_usage_guide_dialog = ConfirmationDialog.new()
	_usage_guide_dialog.title = "卡牌表格使用说明"
	_usage_guide_dialog.dialog_text = "日常只需按一个顺序操作：\n\n表格改卡：打开卡牌表格 → 修改 → 保存并关闭 Excel/WPS → 安全同步卡牌表格。\n\nGodot 改卡：在 Inspector 修改并保存资源 → 安全同步卡牌表格。\n\n请不要同时修改同一张卡牌的两个版本；同步会按较新的文件决定方向。完整字段说明、备份与恢复方法见 card_table/README.md。"
	_usage_guide_dialog.get_ok_button().text = "我已了解，打开表格"
	_usage_guide_dialog.confirmed.connect(_mark_usage_guide_read_and_open_table)
	editor_root.add_child(_usage_guide_dialog)
	_result_dialog = AcceptDialog.new()
	editor_root.add_child(_result_dialog)


## 打开推荐的 XLSX 编辑入口；工作簿首次缺失时才生成，避免覆盖正在维护的表格。
func _open_card_table() -> void:
	if _should_show_usage_guide():
		_usage_guide_dialog.popup_centered()
		return
	_open_card_table_after_guide()


## 标记用户已阅读本项目的首次引导，再进入不会覆盖现有工作簿的打开流程。
func _mark_usage_guide_read_and_open_table() -> void:
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	editor_settings.set_project_metadata(USAGE_METADATA_SECTION, USAGE_METADATA_KEY, true)
	_open_card_table_after_guide()


## 判断当前项目是否需要展示首次使用引导；该状态仅保存在编辑器项目元数据中。
func _should_show_usage_guide() -> bool:
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	return not bool(editor_settings.get_project_metadata(USAGE_METADATA_SECTION, USAGE_METADATA_KEY, false))


## 在用户确认使用流程后打开工作簿，首次缺失时才生成，避免覆盖正在维护的表格。
func _open_card_table_after_guide() -> void:
	if not FileAccess.file_exists(XLSX_FILE_PATH):
		var workbook_result: Dictionary = _run_python_script(PackedStringArray(["--ensure-workbook"]))
		_handle_operation_result(workbook_result, false)
		if not bool(workbook_result.get("success", false)):
			return
	var open_error: int = OS.shell_open(ProjectSettings.globalize_path(XLSX_FILE_PATH))
	if open_error != OK:
		_show_error("无法打开卡牌表格，请检查系统默认表格程序。")


## 请求安全同步前先展示确认，避免误点菜单直接覆盖卡牌资源。
func _request_safe_sync() -> void:
	if _is_syncing:
		_show_error("卡牌表格同步正在进行，请等待当前操作结束。")
		return
	_sync_confirmation_dialog.popup_centered()


## 运行推荐的自动同步模式：表格较新时导入，资源较新时导出，无变更时明确提示。
func _perform_safe_sync() -> void:
	var sync_result: Dictionary = _run_python_script(PackedStringArray(["--auto"]))
	_handle_operation_result(sync_result, true)


## 执行 Python 工具并解析其最终 JSON 状态，不再用空输出猜测成功与否。
func _run_python_script(arguments: PackedStringArray) -> Dictionary:
	if _is_syncing:
		return {"success": false, "error": "已有同步正在执行。", "output": ""}
	_is_syncing = true
	# 脚本绝对路径避免编辑器工作目录变化导致找不到表格工具。
	var script_path: String = ProjectSettings.globalize_path(EXPORT_SCRIPT_PATH)
	# 每次调用生成唯一标识，防止脚本未启动或异常退出时误读上一次的结果文件。
	var request_id: String = "%s-%s" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	# 结果文件使用项目内被忽略的固定路径，Python 会以 UTF-8 原子替换该文件。
	var result_file_path: String = ProjectSettings.globalize_path(RESULT_FILE_PATH)
	# 在原动作参数后追加机器协议参数，手工命令仍可不提供这些参数。
	var operation_arguments: PackedStringArray = PackedStringArray()
	operation_arguments.append_array(arguments)
	operation_arguments.append("--result-file")
	operation_arguments.append(result_file_path)
	operation_arguments.append("--request-id")
	operation_arguments.append(request_id)
	# 按平台尝试常见解释器，Windows 优先使用 Python Launcher 的 Python 3。
	var candidates: Array[Dictionary] = _build_python_candidates(script_path, operation_arguments)
	for candidate in candidates:
		# 每次尝试都使用独立输出数组，避免失败解释器的日志污染最终结果。
		var output: Array = []
		var executable: String = str(candidate["executable"])
		var command_arguments: PackedStringArray = candidate["arguments"]
		var exit_code: int = OS.execute(executable, command_arguments, output, true, false)
		var output_text: String = _join_output(output)
		if exit_code == -1:
			continue
		_is_syncing = false
		return _build_operation_result(exit_code, output_text, request_id)
	_is_syncing = false
	return {
		"success": false,
		"error": "未找到可用的 Python 解释器；请安装 Python 3 或设置 CARD_CSV_SYNC_PYTHON 环境变量。",
		"output": ""
	}


## 构建解释器候选列表，允许高级用户用环境变量指定项目专用 Python。
func _build_python_candidates(script_path: String, arguments: PackedStringArray) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var configured_python: String = OS.get_environment("CARD_CSV_SYNC_PYTHON").strip_edges()
	if not configured_python.is_empty():
		var configured_arguments: PackedStringArray = PackedStringArray([script_path])
		configured_arguments.append_array(arguments)
		candidates.append({"executable": configured_python, "arguments": configured_arguments})
	if OS.get_name() == "Windows":
		var launcher_arguments: PackedStringArray = PackedStringArray(["-3", script_path])
		launcher_arguments.append_array(arguments)
		candidates.append({"executable": "py", "arguments": launcher_arguments})
	var default_arguments: PackedStringArray = PackedStringArray([script_path])
	default_arguments.append_array(arguments)
	if OS.get_name() != "Windows":
		candidates.append({"executable": "python3", "arguments": default_arguments})
	candidates.append({"executable": "python", "arguments": default_arguments})
	return candidates


## 把 OS.execute 的动态输出转为稳定文本，便于日志和 JSON 解析共用。
func _join_output(output: Array) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for entry in output:
		lines.append(str(entry))
	return "\n".join(lines)


## 根据退出码和本次请求的机器结果构造统一状态；任一信号不一致都必须失败。
func _build_operation_result(exit_code: int, output_text: String, request_id: String) -> Dictionary:
	# UTF-8 结果文件是主通道，控制台摘要只在结果文件不可读时作为兼容回退。
	var payload: Dictionary = _read_result_payload(request_id)
	if payload.is_empty():
		payload = _parse_result_payload(output_text, request_id)
	if payload.is_empty():
		return {
			"success": false,
			"error": "同步脚本未返回本次操作的有效结果，请检查输出面板。",
			"output": output_text,
			"payload": {}
		}
	if exit_code != 0:
		return {
			"success": false,
			"error": str(payload.get("error", "同步脚本执行失败，退出码：%s" % exit_code)),
			"output": output_text,
			"payload": payload
		}
	if not bool(payload.get("success", false)):
		return {
			"success": false,
			"error": str(payload.get("error", "同步脚本报告操作失败。")),
			"output": output_text,
			"payload": payload
		}
	return {"success": true, "output": output_text, "payload": payload}


## 从 UTF-8 结果文件读取本次请求的 JSON，避免 Windows 控制台编码与输出捕获差异影响状态判断。
func _read_result_payload(request_id: String) -> Dictionary:
	# 使用绝对路径绕过 `card_table/.gdignore` 的编辑器文件系统过滤，只读取真实磁盘文件。
	var absolute_result_path: String = ProjectSettings.globalize_path(RESULT_FILE_PATH)
	if not FileAccess.file_exists(absolute_result_path):
		return {}
	# 二进制读取后显式按 UTF-8 解码，不依赖操作系统默认代码页。
	var result_file: FileAccess = FileAccess.open(absolute_result_path, FileAccess.READ)
	if result_file == null:
		return {}
	# 完整读取原子替换后的结果文件，避免只解析部分 JSON。
	var result_bytes: PackedByteArray = result_file.get_buffer(result_file.get_length())
	# `get_string_from_utf8` 明确固定字符集，中文动作与错误信息不会乱码。
	var result_text: String = result_bytes.get_string_from_utf8().strip_edges()
	# 结果文件只接受 JSON 字典，其他内容视为协议损坏。
	var parsed: Variant = JSON.parse_string(result_text)
	if parsed is Dictionary:
		# 显式收窄 Variant 类型，保证请求标识校验只接收字典。
		var parsed_payload: Dictionary = parsed
		if _payload_matches_request(parsed_payload, request_id):
			return parsed_payload
	return {}


## 从控制台输出回退提取本次请求的 JSON；只在结果文件不可读时使用。
func _parse_result_payload(output_text: String, request_id: String) -> Dictionary:
	for line in output_text.split("\n", false):
		# 控制台输出可能在结果标记前加入 BOM、警告前缀或其他不可见字符，不能再要求标记位于行首。
		var marker_offset: int = line.find(RESULT_PREFIX)
		if marker_offset < 0:
			continue
		# 只截取稳定标记之后的 JSON，避免前置的解释器信息破坏结构化结果解析。
		var payload_text: String = line.substr(marker_offset + RESULT_PREFIX.length()).strip_edges()
		# 仍然使用 Godot 原生 JSON 解析与 Dictionary 类型检查，避免普通日志被误判为成功。
		var parsed: Variant = JSON.parse_string(payload_text)
		if parsed is Dictionary:
			# 控制台回退也必须校验本次请求标识，不能接受旧日志中的摘要。
			var parsed_payload: Dictionary = parsed
			if _payload_matches_request(parsed_payload, request_id):
				return parsed_payload
	return {}


## 校验结果属于当前调用，避免旧文件或并发进程的状态污染本次弹窗。
func _payload_matches_request(payload: Dictionary, request_id: String) -> bool:
	return not request_id.is_empty() and str(payload.get("request_id", "")) == request_id


## 只在脚本完整成功后展示成功结果，并按实际资源变更决定是否扫描项目文件系统。
func _handle_operation_result(result: Dictionary, may_rescan_resources: bool) -> void:
	var output_text: String = str(result.get("output", ""))
	if not output_text.is_empty():
		print(_without_result_payload(output_text))
	if not bool(result.get("success", false)):
		_show_error(str(result.get("error", "卡牌表格同步失败。")))
		return
	var payload: Dictionary = result.get("payload", {})
	var action: String = str(payload.get("action", "卡牌表格操作已完成。"))
	var warnings: Array = payload.get("warnings", [])
	if not warnings.is_empty():
		action += "\n\n提示：\n" + _join_output(warnings)
	if may_rescan_resources and _payload_changed_resources(payload):
		_queue_rescan_filesystem()
	_show_info(action)


## 过滤机器可读行，避免用户在普通日志中看到仅供插件解析的 JSON。
func _without_result_payload(output_text: String) -> String:
	var visible_lines: PackedStringArray = PackedStringArray()
	for line in output_text.split("\n", false):
		# 与结果解析保持相同的行内定位规则，避免 Windows 前置字符让机器摘要泄漏到普通日志。
		if line.find(RESULT_PREFIX) < 0:
			visible_lines.append(line)
	return "\n".join(visible_lines)


## 判断最终摘要是否确实改写了 Godot 资源，避免纯表格导出触发无意义扫描。
func _payload_changed_resources(payload: Dictionary) -> bool:
	var changed_files: Array = payload.get("changed_files", [])
	for changed_file in changed_files:
		if str(changed_file).begins_with("res://resources/"):
			return true
	return false


## 在编辑器内显示成功或无变更状态，普通用户无需翻找输出面板。
func _show_info(message: String) -> void:
	_result_dialog.title = "卡牌表格"
	_result_dialog.dialog_text = message
	_result_dialog.popup_centered()


## 在编辑器内显示失败原因，并同步写入错误日志方便开发者排查。
func _show_error(message: String) -> void:
	push_error("Card CSV Sync：%s" % message)
	_result_dialog.title = "卡牌表格同步失败"
	_result_dialog.dialog_text = message
	_result_dialog.popup_centered()


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
