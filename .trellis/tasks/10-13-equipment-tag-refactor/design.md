# 技术设计

## 数据与编辑器边界

标签目录在 resources/tags/ 下以单个 .tres 保存 Tags 字符串数组。编辑器插件负责相关英文标签字段的单选/多选及热刷新；运行时字段仍保存 StringName，核心逻辑不依赖 EditorPlugin。源允许编辑英文标识，校验非空、英文字符、数字与下划线，不擅自改大小写。删除已引用标识时提示，保留旧引用；显示不在源中的当前值并标示未登记。

EquipmentData.ValidSlots 枚举数组沿用0～15编号；SetType 为 PackedStringArray（用户要求的字符串数组），EquipmentSetData 用单个字符串 SetType 作为套装定义键。EquipmentAttributeBonus 为专属 Resource，字段 Attribute、MinValue、MaxValue 对应枚举及整数范围；EquipmentData 使用 Array[EquipmentAttributeBonus]。套装固定加成条目另设专用 Resource，以 Attribute 和 Value 支持原浮点固定增量，避免把随机装备区间用于套装。

装备数据兼容桥集中读新字段，读取旧字典范围与旧数字套装时只用于直接历史输入，不在正式资源上保留靠名称判槽位。RollRandomStats 通过范围读取接口生成一次 RolledAttributes，装备仍应用实例值。存档保留原序列化形状并适配新允许属性列表。debug_generated_equipment_entry 输出新条目，旧调试资源字段保持数值兼容。

## 数据流

标签源 → Inspector 选择器 → 原有字符串资源字段 → 标签查询/采集匹配。

装备属性条目 → ItemStack 初次生成 → RolledAttributes → EquipmentComponent → AttributeComponent。

SetType 数组 → 每件内去重 → 按套装键独立统计 → 满足的所有等级 → 应用与撤销属性、标签。

采集配置 + 已装备工具 → 共享计算器 → 输入时快照耗时 → 完成消费同一快照 → 保留各自资源点状态规则。

## 并行修改所有权

- tags_editor：resources/tags/、addons/tag_catalog/、project.godot 的插件启用项、标签相关测试；不修改 item_data 字段形状。
- equipment_model：装备/工具及属性资源脚本、装备组件、兼容桥、ItemStack、存档属性校验、debug 条目、装备相关测试；不批量修改生产 .tres。
- gathering_rules：共享采集计算器、采集行为、世界交互协调器、采集与长按相关测试；不修改生产 .tres。
- 主会话：任务文档、模块说明、生产 .tres 文本迁移、最终运行验证与交接。

## 风险控制

资源批量迁移最小文本编辑，不使用 ResourceSaver 重存；保留原换行符、UID、CardId 和用户参数。不随意去除 item identity tags。不为了让旧测试通过复原用户Ax减免10；相关测试必须基于当前资源配置。真实 Inspector 与游戏进程验证新脚本，编辑器测试缓存警告不得忽略。
