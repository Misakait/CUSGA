@tool
extends RefCounted
class_name SkillTargetingTypeCodegen

const SOURCE_PATH := "res://core/combat/skills/SkillTargetingType.cs"
const OUTPUT_PATH := "res://scripts/generated/SkillTargetingType.gd"
const ENUM_NAME := "SkillTargetingType"


## 从 C# 枚举源文件生成 GDScript 枚举文件。
## 参数：
## - source_path：C# 枚举源文件路径。
## - output_path：生成的 GDScript 文件路径。
## - enum_name：需要同步的 C# 枚举名称。
## 返回值：包含 ok、changed、message 的生成结果字典。
static func generate(source_path: String = SOURCE_PATH, output_path: String = OUTPUT_PATH, enum_name: String = ENUM_NAME) -> Dictionary:
	var source_result := _read_text(source_path)
	if not bool(source_result.get("ok", false)):
		return source_result

	var parse_result := parse_enum_members(str(source_result["text"]), enum_name)
	if not bool(parse_result.get("ok", false)):
		return parse_result

	var members: Array = parse_result.get("members", [])
	var rendered := render_gdscript(enum_name, source_path, members)
	var existing_result := _read_text(output_path, true)
	if bool(existing_result.get("ok", false)) and str(existing_result.get("text", "")) == rendered:
		return {
			"ok": true,
			"changed": false,
			"message": "SkillTargetingType.gd 已是最新。"
		}

	if not _ensure_output_directory(output_path):
		return _failure("无法创建生成目录：" + output_path.get_base_dir())

	var output_file := FileAccess.open(output_path, FileAccess.WRITE)
	if output_file == null:
		return _failure("无法写入生成文件：" + output_path + "，错误：" + error_string(FileAccess.get_open_error()))

	output_file.store_string(rendered)
	output_file.close()
	return {
		"ok": true,
		"changed": true,
		"message": "已生成：" + output_path
	}


## 判断是否需要重新生成 GDScript 枚举文件。
## 参数：
## - source_path：C# 枚举源文件路径。
## - output_path：生成的 GDScript 文件路径。
## - last_source_modified_time：上次记录的源文件修改时间。
## - force：是否强制生成。
## 返回值：当源文件变化、输出文件缺失或输出文件旧于源文件时返回 true。
static func should_generate(source_path: String, output_path: String, last_source_modified_time: int, force: bool = false) -> bool:
	if force:
		return true
	if not FileAccess.file_exists(output_path):
		return true

	var source_modified_time := FileAccess.get_modified_time(source_path)
	if source_modified_time != last_source_modified_time:
		return true

	var output_modified_time := FileAccess.get_modified_time(output_path)
	return source_modified_time > output_modified_time


## 解析指定 C# 枚举声明中的成员和值。
## 参数：
## - source_text：C# 源文件文本。
## - enum_name：需要解析的枚举名称。
## 返回值：成功时返回 ok=true 和 members 数组；失败时返回 ok=false 和 message。
static func parse_enum_members(source_text: String, enum_name: String) -> Dictionary:
	if not _is_valid_identifier(enum_name):
		return _failure("枚举名称不是有效标识符：" + enum_name)

	var cleaned_text := _strip_csharp_comments(source_text)
	var declaration_pattern := RegEx.new()
	var compile_error := declaration_pattern.compile("\\benum\\s+" + enum_name + "\\b")
	if compile_error != OK:
		return _failure("无法创建枚举声明匹配表达式：" + error_string(compile_error))

	var declaration_match := declaration_pattern.search(cleaned_text)
	if declaration_match == null:
		return _failure("未找到 C# 枚举声明：" + enum_name)

	var open_brace := cleaned_text.find("{", declaration_match.get_end())
	if open_brace < 0:
		return _failure("未找到枚举起始花括号：" + enum_name)

	var close_brace := _find_matching_brace(cleaned_text, open_brace)
	if close_brace < 0:
		return _failure("未找到枚举结束花括号：" + enum_name)

	var enum_body := cleaned_text.substr(open_brace + 1, close_brace - open_brace - 1)
	var entries := _remove_csharp_attributes(enum_body).split(",")
	var members: Array[Dictionary] = []
	var current_value := 0

	for raw_entry in entries:
		var entry := str(raw_entry).strip_edges()
		if entry.is_empty():
			continue

		var parts := entry.split("=", false, 2)
		var member_name := parts[0].strip_edges()
		if not _is_valid_identifier(member_name):
			return _failure("枚举成员名称不是有效 GDScript 标识符：" + member_name)

		if parts.size() > 1:
			var value_result := _parse_csharp_int_literal(parts[1].strip_edges())
			if not bool(value_result.get("ok", false)):
				return _failure("枚举成员 " + member_name + " 的显式值无法解析：" + str(value_result.get("message", "")))
			current_value = int(value_result["value"])

		members.append({
			"name": member_name,
			"value": current_value
		})
		current_value += 1

	if members.is_empty():
		return _failure("枚举解析结果为空：" + enum_name)

	return {
		"ok": true,
		"members": members
	}


## 渲染原生 GDScript 枚举文件内容。
## 参数：
## - enum_name：生成的 GDScript 类名。
## - source_path：源 C# 文件路径，用于写入文件头说明。
## - members：已经解析出的枚举成员数组。
## 返回值：完整的 GDScript 文件文本。
static func render_gdscript(enum_name: String, source_path: String, members: Array) -> String:
	var lines := PackedStringArray()
	lines.append("## 此文件由 SkillTargetingTypeCodegen 自动生成，请不要手动修改。")
	lines.append("## 来源：" + source_path)
	lines.append("extends RefCounted")
	lines.append("class_name " + enum_name)
	lines.append("")
	lines.append("enum Value {")

	for member in members:
		lines.append("\t%s = %d," % [str(member["name"]), int(member["value"])])

	lines.append("}")
	lines.append("")
	lines.append("## 获取枚举名称到整型值的映射。")
	lines.append("## 返回值：key 为枚举名（String），value 为枚举整型值（int）。")
	lines.append("static func get_map() -> Dictionary:")
	lines.append("\treturn {")

	for member in members:
		lines.append("\t\t\"%s\": Value.%s," % [str(member["name"]), str(member["name"])])

	lines.append("\t}")
	lines.append("")
	lines.append("## 获取指定枚举名对应的整型值。")
	lines.append("## 参数：")
	lines.append("## - name：枚举名称。")
	lines.append("## - fallback：当名称不存在时的兜底值。")
	lines.append("## 返回值：目标枚举的整型值，或兜底值。")
	lines.append("static func get_value(name: String, fallback: int = -1) -> int:")
	lines.append("\treturn int(get_map().get(name, fallback))")

	return "\n".join(lines) + "\n"


static func _read_text(path: String, allow_missing: bool = false) -> Dictionary:
	if allow_missing and not FileAccess.file_exists(path):
		return {
			"ok": false,
			"changed": false,
			"message": "文件不存在：" + path
		}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("无法读取文件：" + path + "，错误：" + error_string(FileAccess.get_open_error()))

	var text := file.get_as_text()
	file.close()
	return {
		"ok": true,
		"text": text
	}


static func _strip_csharp_comments(text: String) -> String:
	var lines := PackedStringArray()
	var in_block_comment := false

	for raw_line in text.split("\n"):
		var line := str(raw_line)
		var stripped_line := ""
		var index := 0

		while index < line.length():
			if in_block_comment:
				var block_end := line.find("*/", index)
				if block_end < 0:
					index = line.length()
				else:
					in_block_comment = false
					index = block_end + 2
				continue

			var line_comment := line.find("//", index)
			var block_start := line.find("/*", index)

			if line_comment >= 0 and (block_start < 0 or line_comment < block_start):
				stripped_line += line.substr(index, line_comment - index)
				break

			if block_start >= 0:
				stripped_line += line.substr(index, block_start - index)
				in_block_comment = true
				index = block_start + 2
				continue

			stripped_line += line.substr(index)
			break

		lines.append(stripped_line)

	return "\n".join(lines)


static func _remove_csharp_attributes(text: String) -> String:
	var output := ""
	var attribute_depth := 0
	var index := 0

	while index < text.length():
		var character := text.substr(index, 1)

		if attribute_depth > 0:
			if character == "[":
				attribute_depth += 1
			elif character == "]":
				attribute_depth -= 1
			index += 1
			continue

		if character == "[":
			attribute_depth = 1
			index += 1
			continue

		output += character
		index += 1

	return output


static func _find_matching_brace(text: String, open_brace_index: int) -> int:
	var depth := 0

	for index in range(open_brace_index, text.length()):
		var character := text.substr(index, 1)
		if character == "{":
			depth += 1
		elif character == "}":
			depth -= 1
			if depth == 0:
				return index

	return -1


static func _parse_csharp_int_literal(value_text: String) -> Dictionary:
	var text := value_text.strip_edges().replace("_", "")
	while text.length() > 0:
		var suffix := text.substr(text.length() - 1, 1).to_lower()
		if suffix != "u" and suffix != "l":
			break
		text = text.substr(0, text.length() - 1)

	if text.is_empty():
		return _failure("空数值")

	var sign := 1
	if text.begins_with("-"):
		sign = -1
		text = text.substr(1)
	elif text.begins_with("+"):
		text = text.substr(1)

	if text.begins_with("0x") or text.begins_with("0X"):
		var hex_text := text.substr(2)
		if hex_text.is_empty():
			return _failure("空十六进制数值")
		var value := 0
		for index in range(hex_text.length()):
			var digit := "0123456789abcdef".find(hex_text.substr(index, 1).to_lower())
			if digit < 0:
				return _failure("无效十六进制数值：" + value_text)
			value = (value * 16) + digit
		return {
			"ok": true,
			"value": sign * value
		}

	if not text.is_valid_int():
		return _failure("仅支持整数字面量：" + value_text)

	return {
		"ok": true,
		"value": sign * int(text)
	}


static func _is_valid_identifier(identifier: String) -> bool:
	var pattern := RegEx.new()
	if pattern.compile("^[A-Za-z_][A-Za-z0-9_]*$") != OK:
		return false
	return pattern.search(identifier) != null


static func _ensure_output_directory(output_path: String) -> bool:
	var directory := output_path.get_base_dir()
	if directory.is_empty():
		return true
	var absolute_directory := ProjectSettings.globalize_path(directory)
	var error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	return error == OK or error == ERR_ALREADY_EXISTS


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"changed": false,
		"message": message
	}
