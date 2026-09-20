@tool
extends McpTestSuite

## TagComponent GDScript 生产迁移的行为契约套件。

## 待验证的标签组件脚本。
const TAG_COMPONENT_SCRIPT: GDScript = preload("res://entities/components/tag_component.gd")
## 生产玩家场景路径，用于锁定实际节点脚本引用。
const PLAYER_SCENE_PATH: String = "res://scenes/player_scenes/player.tscn"
## 旧 C# 驻守概率提供器路径：迁移期用它验证反向跨语言兼容边界，C# 退役后相关对照用例整体跳过。
const LEGACY_PASSAGE_GUARD_PROVIDER_CS_PATH: String = "res://core/map/PassageGuardProbabilityProvider.cs"
## C# 可选助手：C# 缺席时安全跳过跨语言对照，避免 `preload` 造成解析期错误。
const CS_OPTIONAL := preload("res://tests/godot/csharp_optional.gd")
## GDScript 驻守设置脚本，为旧提供器提供迁移后的配置输入。
const PASSAGE_GUARD_SETTINGS_SCRIPT: GDScript = preload("res://resources/map/passage_guard_settings.gd")
## GDScript 驻守概率修正脚本，为旧提供器提供迁移后的嵌套资源输入。
const PASSAGE_GUARD_MODIFIER_SCRIPT: GDScript = preload("res://resources/map/passage_guard_probability_modifier.gd")


## 返回 GodotAI 使用的稳定套件名称。
## 返回值：标签组件契约套件名。
func suite_name() -> String:
	return "tag_component_contract"


## 验证空标签过滤、叠层、逐层移除、归零删除和缺失标签查询。
## 返回值：无。
func test_tag_component_preserves_stack_contract() -> void:
	## 待验证的标签组件实例。
	var tags := TAG_COMPONENT_SCRIPT.new() as Node
	assert_false(bool(tags.call("HasTag", &"wood")), "新组件不得预置标签。")
	assert_eq(int(tags.call("GetTagStack", &"wood")), 0, "缺失标签层数必须为 0。")
	tags.call("AddTag", &"")
	assert_false(bool(tags.call("HasTag", &"")), "空标签必须被忽略。")
	tags.call("AddTag", &"wood")
	tags.call("AddTag", &"wood")
	assert_true(bool(tags.call("HasTag", &"wood")), "增加有效标签后必须可查询。")
	assert_eq(int(tags.call("GetTagStack", &"wood")), 2, "重复增加必须累计标签层数。")
	tags.call("RemoveTag", &"wood")
	assert_true(bool(tags.call("HasTag", &"wood")), "移除一层后仍有剩余层数时标签必须保留。")
	assert_eq(int(tags.call("GetTagStack", &"wood")), 1, "移除一层必须精确递减。")
	tags.call("RemoveTag", &"wood")
	assert_false(bool(tags.call("HasTag", &"wood")), "层数归零时必须删除标签。")
	assert_eq(int(tags.call("GetTagStack", &"wood")), 0, "删除后的标签层数必须回到 0。")
	tags.call("RemoveTag", &"missing")
	assert_eq(int(tags.call("GetTagStack", &"missing")), 0, "移除缺失标签不得创建负层数。")
	tags.free()


## 验证生产玩家场景已经挂载 GDScript 标签组件。
## 返回值：无。
func test_player_scene_uses_gdscript_tag_component() -> void:
	## 强制从磁盘重新加载的玩家场景，避免编辑器继续复用切换前的 C# 脚本缓存。
	var player_scene := ResourceLoader.load(PLAYER_SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	assert_true(player_scene != null, "玩家场景必须能够加载。")
	if player_scene == null:
		return
	## 未进入场景树的玩家实例，避免聚焦测试触发无关的玩家生命周期与自动加载依赖。
	var player := player_scene.instantiate() as Node
	## 生产节点路径下实际挂载的标签组件。
	var tags := player.get_node("Components/TagComponent") as Node
	## 标签组件当前实际使用的脚本资源。
	var script := tags.get_script() as Script
	assert_true(script != null, "玩家标签节点必须保留脚本。")
	if script == null:
		player.free()
		return
	assert_eq(script.resource_path, "res://entities/components/tag_component.gd", "玩家场景必须使用 GDScript TagComponent。")
	player.free()


## 验证保留的 C# 驻守兼容垫片可查询 GDScript 标签组件。
## 返回值：无。
func test_legacy_passage_guard_provider_accepts_gdscript_tags() -> void:
	## C# 垫片已退役时本用例没有可测对象，记跳过而不是失败（C# 存在时下面的断言照常执行）。
	if not CS_OPTIONAL.present(LEGACY_PASSAGE_GUARD_PROVIDER_CS_PATH):
		skip(CS_OPTIONAL.SKIP_REASON)
		return
	## 迁移后的驻守全局配置。
	var settings := PASSAGE_GUARD_SETTINGS_SCRIPT.new() as Resource
	settings.set("BaseGuardChance", 0.2)
	## 仅在玩家拥有指定标签时生效的迁移后概率修正。
	var modifier := PASSAGE_GUARD_MODIFIER_SCRIPT.new() as Resource
	modifier.set("RequiredTag", &"guard_bonus")
	modifier.set("AdditiveChance", 0.3)
	modifier.set("Multiplier", 1.0)
	var modifiers: Array[Resource] = [modifier]
	settings.set("ProbabilityModifiers", modifiers)
	## 迁移后的玩家标签组件。
	var tags := TAG_COMPONENT_SCRIPT.new() as Node
	## 保留的旧 C# 提供器实例。
	var provider := CS_OPTIONAL.script(LEGACY_PASSAGE_GUARD_PROVIDER_CS_PATH).new() as RefCounted
	## 缺少标签协议的节点，用于锁定动态边界的安全退化行为。
	var missing_protocol := Node.new()
	assert_true(is_equal_approx(float(provider.call("Calculate", settings, missing_protocol)), 0.2), "缺少 HasTag 方法时旧 C# 提供器必须安全忽略标签修正。")
	missing_protocol.free()
	assert_true(is_equal_approx(float(provider.call("Calculate", settings, tags)), 0.2), "缺少所需标签时旧 C# 提供器必须忽略修正。")
	tags.call("AddTag", &"guard_bonus")
	assert_true(is_equal_approx(float(provider.call("Calculate", settings, tags)), 0.5), "旧 C# 提供器必须通过 HasTag 动态调用读取 GDScript 标签。")
	tags.free()
