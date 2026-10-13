@tool
extends McpTestSuite

## 英文标签目录与 Inspector 选择器的可执行契约。

const Catalog = preload("res://resources/tags/tag_catalog.gd")
const Scanner = preload("res://addons/tag_catalog/reference_scanner.gd")
const Monitor = preload("res://addons/tag_catalog/catalog_monitor.gd")


## 返回标签测试套件名称。
## 返回值：测试套件名。
func suite_name() -> String:
	return "tag_catalog"


## 验证英文格式、去重与大小写保留。
## 返回值：无。
func test_catalog_validation_and_available_tags() -> void:
	var catalog := Catalog.new()
	catalog.Tags = [&"wood", &"wood", &"MagicItem", &"bad-tag", &"", &"中文"]
	assert_true(Catalog.is_valid_tag("MagicItem"), "英文大小写标签必须合法。")
	assert_false(Catalog.is_valid_tag("bad-tag"), "连字符标签必须拒绝。")
	assert_eq(catalog.get_available_tags(), [&"wood", &"MagicItem"], "选项必须去重但保留原大小写和顺序。")
	assert_eq(catalog.get_validation_messages().size(), 4, "重复、空项、连字符和非英文项都必须可见提示。")


## 验证新增目录项可直接被消费者读取，未登记引用不会被目录改写。
## 返回值：无。
func test_catalog_add_remove_preserves_references() -> void:
	var catalog := Catalog.new()
	catalog.Tags = [&"wood"]
	var item := ItemData.new()
	item.ItemTags = [&"wood", &"future_tag"]
	assert_true(item.ItemTags.has(&"future_tag"), "未登记标签必须保留在原物品字段。")
	catalog.Tags.append(&"future_tag")
	assert_true(catalog.get_available_tags().has(&"future_tag"), "新增源标签必须立即成为可选值。")
	catalog.Tags.erase(&"future_tag")
	assert_false(catalog.get_available_tags().has(&"future_tag"), "删除源标签只影响选择列表。")
	assert_true(item.ItemTags.has(&"future_tag"), "删除源标签不能静默清除现有引用。")


## 验证实际资源扫描能定位已删除标签的文件和行号。
## 返回值：无。
func test_reference_scanner_contract() -> void:
	var references: Dictionary = Scanner.find_references([&"wood", &"stone", &"bush"])
	var locations: PackedStringArray = references.get(&"wood", PackedStringArray())
	assert_true(not locations.is_empty(), "扫描器必须找到现有 wood 引用。")
	assert_true(locations[0].contains("res://"), "引用位置必须包含资源路径。")
	for tag: StringName in [&"stone", &"bush"]:
		var scene_locations: PackedStringArray = references.get(tag, PackedStringArray())
		var found_main := false
		for location: String in scene_locations:
			if location.begins_with("res://scenes/Main.tscn:"):
				found_main = true
		assert_true(found_main, "扫描器必须包含 Main 场景中的 %s 遭遇标签。" % tag)


## 验证目录覆盖全部生产资源和场景中的既有英文标识，保留原大小写。
## 返回值：无。
func test_default_catalog_covers_existing_asset_tags() -> void:
	# 目录可能由外部文件编辑；覆盖刷新同一缓存对象，确保检查当前磁盘内容并保留插件引用。
	var catalog: Resource = ResourceLoader.load(
		"res://resources/tags/default_tag_catalog.tres", "Resource", ResourceLoader.CACHE_MODE_REPLACE
	)
	var registered: Array[StringName] = catalog.get_available_tags()
	var missing := PackedStringArray()
	_collect_missing_asset_tags("res://", registered, missing)
	assert_eq(missing, PackedStringArray(), "英文标签源必须包含生产资产现有字段：%s" % "; ".join(missing))


## 验证插件退出后标签源不再调用旧监视器，重复清理仍安全。
## 返回值：无。
func test_monitor_disposal_disconnects_catalog_changes() -> void:
	var catalog := Catalog.new()
	catalog.Tags = [&"wood"]
	var monitor: RefCounted = Monitor.new(catalog)
	assert_true(catalog.changed.is_connected(monitor.refresh), "活跃监视器必须监听标签源。")
	monitor.dispose()
	monitor.dispose()
	assert_false(catalog.changed.is_connected(monitor.refresh), "退出后必须断开旧监视器。")


func _collect_missing_asset_tags(path: String, registered: Array[StringName], missing: PackedStringArray) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	var fields := RegEx.new()
	fields.compile("^\\s*(?:ItemTags|GrantedTags|TargetGatheringTag|GatheringTag|TriggerTag)\\s*=")
	var tokens := RegEx.new()
	tokens.compile('"([^"\\\\]*)"')
	for file: String in directory.get_files():
		if file.get_extension() not in ["tres", "tscn"]:
			continue
		var asset_path: String = path.path_join(file)
		var lines: PackedStringArray = FileAccess.get_file_as_string(asset_path).split("\n")
		for line_index: int in lines.size():
			if fields.search(lines[line_index]) == null:
				continue
			for token: RegExMatch in tokens.search_all(lines[line_index]):
				var tag: String = token.get_string(1)
				if Catalog.is_valid_tag(tag) and not registered.has(StringName(tag)):
					missing.append("%s:%d → %s" % [asset_path, line_index + 1, tag])
	for folder: String in directory.get_directories():
		# 示例测试和缓存不是生产配置；场景内嵌资源与旧地形仍必须覆盖。
		if folder.begins_with(".") or folder in ["addons", "tests"]:
			continue
		_collect_missing_asset_tags(path.path_join(folder), registered, missing)
