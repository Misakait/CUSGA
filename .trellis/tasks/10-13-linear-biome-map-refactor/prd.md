# 线性生态地图生成与配置重构

## 目标与阶段

地图重构已有代码实现。本轮保持规划，修复 Inspector 资源创建缺口。用户最新确认：点击 Biomes 数组空元素的下拉菜单，应出现 BiomeDefinitionNew 类型，点击即可创建并配置资源。自动填入五生态不是本轮目标。

## 确认需求

- R1：主线横向、支线纵向向上或向下，同生态全部房间集中生成。木土水火金为默认顺序，实际顺序由生态数组决定，新生成不含 normal。
- R2：map_type_new 管理有序生态资源数组；biome_definition_new 管理生态名称、主场景、特殊场景、可选 Boss 和特殊数量。主场景数量归生态配置，分支数量与长度归 map_position_create_new。保留 MapTypes、MapPositionCreate 名称，以及 from_name_get_road、from_name_get_attribute 旧接口。
- R3：主线使用主场景，Boss 在该生态主线末尾生成；分支使用该生态的主场景和特殊场景。
- R4：每种特殊场景满足最低数量且不超最高数量。用户例子为最少 2、最多 5，生成 2 即满足保障。
- R5：Biomes 空元素下拉菜单提供 BiomeDefinitionNew 创建选项，点击可创建并展开上述生态配置。不自动挂载五生态，不覆盖用户数组元素、资源字段或顺序。
- R6：产品改动严格限于 resources/map/biome_definition_new.gd、scripts/map_scripts/map_type_new.gd、scripts/map_scripts/map_position_create_new.gd。换回两个旧节点脚本后游戏仍正常运行。

## 当前证据

- resources/map/biome_definition_new.gd:1 继承 Resource；:2 注册 BiomeDefinitionNew；scripts/map_scripts/map_type_new.gd:6 导出 Array[BiomeDefinitionNew]，以 create_default_biomes 函数初始化默认值。
- Godot 4.7.1 已打开 CUSGA 和 map_control.tscn。实际 MapTypes 挂载新脚本，用户截图中创建菜单没有具体类型候选；全局类缓存已注册 BiomeDefinitionNew。
- MCP get_info 对新旧 BiomeDefinition 均返回 can_instantiate=false，不能据此断言非 @tool 导致菜单缺失。Godot 资源菜单检查脚本有效性与抽象状态，应验证真实选择器和刷新状态。
- 前轮已验证运行时生成、顺序调整、特殊数量、房间加载和旧脚本回退，未验证真实 Inspector 菜单。
- 现有生成器每生态分支 2～5、长度 2～5，长度不含锚点；主场景 scene_count 用于主线，支线复用不扣额度；容量不足时拒绝并保留旧结果。本轮不改变算法。
- 初始证据 scenes/map_scenes/map_control.tscn:4、:7 引用旧脚本，:21 配置 normal，目前用户自行替换脚本并保存场景。用户已有 resources/map/biomes_new/wood.tres，不得回滚、修改或重存这些文件和未保存字段。
- core/map/map_world_model.gd:67 读取 map、scene_to_scene、start_position；旧 scripts/map_scripts/map_position_create.gd:28 起的公开输出已保留。
- UIMapWorldView.gd:22 获取 ../MapTypes，:67 调用 from_name_get_road；旧 biome_definition 分类与 scene_count 经新默认工厂只读转换。

## 验收

1. R5：真实 MapTypes Inspector 中，展开 Biomes，空元素下拉菜单出现 BiomeDefinitionNew，点击能创建并展开三类场景与数量配置。
2. R5：不自动填充生态；用户元素、空槽、顺序和已编辑字段保留。
3. R1～R4：配置仍用于生成，现有地图算法和布局协议保持有效。
4. R2、R6：旧查询方法可用，编辑器 MCP 的运行验证和旧脚本回退通过。
5. R6：只改三个指定产品脚本，不保存用户场景、不新增资源或测试文件。
6. 不引入 Parse Error、SCRIPT ERROR、Failed to load script 或资源加载错误；仅停止游戏，编辑器保持打开。

## 边界

沿用既有职责分工，不新增插件，不重新设计显示、移动、战斗或采集，不删除旧脚本和 normal 美术。开发流程仅维护本任务规划文件，其他产品文档也受三个脚本限制，不扩展修改。注释中文；修改前查引用；使用 Godot 4.7.1 MCP 验证。具体菜单原因仍需最小修复与现场验证，不能预先宣称已解决。
