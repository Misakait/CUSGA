@tool
extends RefCounted

## 仅扫描资源文本中的标签字段，避免加载全部资产造成编辑器副作用。
## 资源字段仍保存英文字符串，扫描不会清除任何引用。

const FIELDS: String = "ItemTags|GrantedTags|TargetGatheringTag|GatheringTag|TriggerTag"


## 查找指定标签在项目资产中的实际引用。
## 参数 tags：待查标签；参数 root：扫描目录，默认整个项目。
## 返回值：标签到“文件路径:行号”的字符串数组映射。
static func find_references(tags: Array[StringName], root: String = "res://") -> Dictionary:
	var result: Dictionary = {}
	for tag: StringName in tags:
		result[tag] = PackedStringArray()
	if tags.is_empty():
		return result
	var field_pattern := RegEx.new()
	field_pattern.compile("^\\s*(?:%s)\\s*=" % FIELDS)
	var token_pattern := RegEx.new()
	token_pattern.compile('"([^"\\\\]*)"')
	_scan_directory(root, field_pattern, token_pattern, result)
	return result


static func _scan_directory(path: String, field_pattern: RegEx, token_pattern: RegEx, result: Dictionary) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for file: String in directory.get_files():
		if file.get_extension() not in ["tres", "tscn"]:
			continue
		var asset_path: String = path.path_join(file)
		var lines: PackedStringArray = FileAccess.get_file_as_string(asset_path).split("\n")
		for line_index: int in lines.size():
			if field_pattern.search(lines[line_index]) == null:
				continue
			for match_result: RegExMatch in token_pattern.search_all(lines[line_index]):
				var tag := StringName(match_result.get_string(1))
				if result.has(tag):
					var locations: PackedStringArray = result[tag]
					locations.append("%s:%d" % [asset_path, line_index + 1])
					result[tag] = locations
	for folder: String in directory.get_directories():
		# 插件测试与生成缓存不属于玩家配置，排除以免把示例标签算作生产引用。
		if folder.begins_with(".") or folder in ["addons", "tests"]:
			continue
		_scan_directory(path.path_join(folder), field_pattern, token_pattern, result)
