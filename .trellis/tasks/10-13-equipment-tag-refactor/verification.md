# 验证记录（2026-10-13）

任务功能与关联文档已完成；保留未提交状态，不自动归档。Godot 4.7.1 编辑器已确认加载 CUSGA，执行文件系统扫描，验证后只停止游戏。

| 编辑器聚焦套件 | 通过 | 跳过 | 失败 |
| --- | ---: | ---: | ---: |
| equipment_configuration | 6 | 0 | 0 |
| tag_catalog | 5 | 0 | 0 |
| tag_catalog_inspector | 5 | 0 | 0 |
| shared_gathering_effects | 4 | 0 | 0 |
| inventory_component_contract | 28 | 1 | 0 |
| item_chain_boundary_contract | 9 | 0 | 0 |
| player_contract | 6 | 3 | 0 |
| debug_loadout_migration | 4 | 0 | 0 |
| reusable_gathering | 58 | 0 | 0 |
| save_system_contract | 29 | 0 | 0 |
| 合计 | 154 | 4 | 0 |

## 新游戏进程验证

`project_run(mode="custom", scene="res://scenes/Main.tscn", autosave=false)` 启动成功，game_eval 通过真实玩家 Equipment 查询并执行穿脱：无斧耗时20点，装备生产Ax后3点，默认长按0.3秒，卸下后恢复20点。Pickaxe减免10点，装备实际堆叠上限1，目录四个补齐标签均存在。

同一新游戏进程中，装备套件5项行为测试执行47个断言、共享采集4项行为测试执行42个断言，全部通过。涵盖属性生成/复制不重随机、多套装去重与撤销、存档往返、装备独立实例、拾取整份放不下时不写库存、共享采集和长按快照。

`project_run(mode="main", autosave=false)` 主菜单启动成功；最终成功的Main与主菜单日志没有本次引入的SCRIPT ERROR、Parse Error或资源加载错误。游戏已停止，编辑器保持打开。

## 编辑器检查与审查

真实EditorInspector覆盖新增标签即时更新、写回与撤销重做、多选增删、删除已用标签保留旧值并提示、正式项目插件生效。装备数组提供0～15槽位枚举和专用属性Resource创建选项，拒绝普通Resource。全生产tres/tscn标签目录覆盖通过。

最终审查核对46个修改equip/tool资产的UID、CardId、名称、图标、价格和说明首行均保持，所有资产明确槽位，Ax17与Pickaxe10保留。`git diff --check`通过。

## 修复和限制

- 标签源曾被编辑器缓存旧内容：覆盖测试改为CACHE_MODE_REPLACE刷新同一Resource，保持正式插件引用，复测通过。
- 商店新增测试曾把旧CardId=null等同于运行时null，错误写死88件。新进程确认类型化StringName读成空字符串；测试改为保留原筛选规则、89条目录以及有效商品的标识/价格/顺序/身份断言，完整58项通过。生产商店未改。
- 编辑器测试发现过程仍报告未修改的test_item_room_content.gd加载失败。HEAD已有相同RefCounted测试调用get_tree的源码，本任务没有修改该脚本，不将其记录为通过。
- 工具同文reload对ItemData/EquipmentData返回错误43而无具体解析原因，未据此认定脚本有效；由上述新游戏进程补充验证生产代码。
- 存档负面测试产生预期的损坏JSON、非法参与者和版本错误日志，已按测试栈区分，正常场景无对应错误。
- 带入栏既有协议只有item/count，不保存实例洗炼属性，详见模块文档和权威玩法文档；当前任务未扩展此接口。
