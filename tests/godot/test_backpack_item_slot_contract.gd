@tool
extends McpTestSuite

## 背包运行期格子与输入状态由游戏冒烟验证；本套件锁定无法由编辑器实例化测试的资源契约。

const SECTION_SOURCE_PATHS: Array[String] = [
	"res://core/ui/inventory/inventory_section_controller.gd",
	"res://core/ui/inventory/equipment_section_controller.gd",
	"res://core/ui/inventory/deck_section_controller.gd",
]
const ITEM_SLOT_SCENE: PackedScene = preload("res://scenes/ui/item_slot1.tscn")

## 返回 GodotAI 使用的稳定套件名称。
## @return 背包格子契约套件名。
func suite_name() -> String:
	return "backpack_item_slot_contract"

## 验证 item_slot1 资源保留独立的松开和点击贴图。
## @return 无返回值。
func test_item_slot1_keeps_its_configured_release_and_click_styles() -> void:
	var slot: Button = ITEM_SLOT_SCENE.instantiate() as Button
	assert_true(slot != null, "item_slot1 必须能作为 Button 场景实例化。")
	if slot == null:
		return
	var normal_style: StyleBoxTexture = slot.get_theme_stylebox("normal") as StyleBoxTexture
	var pressed_style: StyleBoxTexture = slot.get_theme_stylebox("pressed") as StyleBoxTexture
	assert_true(normal_style != null and pressed_style != null, "item_slot1 必须配置 normal 与 pressed 贴图。")
	if normal_style != null and pressed_style != null:
		assert_ne(normal_style.texture, pressed_style.texture, "item_slot1 的点击贴图必须与松开贴图不同。")
	slot.free()

## 验证三个区域都引用统一场景和专用适配脚本。
## @return 无返回值。
func test_all_backpack_sections_use_the_shared_slot_adapter() -> void:
	for source_path: String in SECTION_SOURCE_PATHS:
		var source: String = FileAccess.get_file_as_string(source_path)
		assert_false(source.is_empty(), "必须能读取区域控制器：%s" % source_path)
		assert_true(source.contains("preload(\"res://scenes/ui/item_slot1.tscn\")"),
			"区域控制器必须实例化 item_slot1：%s" % source_path)
		assert_true(source.contains("preload(\"res://scripts/ui_scripts/backpack_item_slot.gd\")"),
			"区域控制器必须挂载背包适配脚本：%s" % source_path)

## 验证适配器覆盖所有 Button 状态，并用区域传入的选中值控制贴图。
## @return 无返回值。
func test_adapter_maps_all_button_states_to_the_area_selection() -> void:
	var source: String = FileAccess.get_file_as_string("res://scripts/ui_scripts/backpack_item_slot.gd")
	assert_false(source.is_empty(), "必须能读取背包格子适配脚本。")
	for state_name: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		assert_true(source.contains("&\"%s\"" % state_name),
			"未选中格悬停或按下时不得自行显示点击贴图，Button 状态需要统一受区域选择控制：%s" % state_name)
	assert_true(source.contains("_selected_style if selected else _normal_style"),
		"仅区域选中的格子显示 item_slot1 点击贴图。")
