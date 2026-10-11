# Resource Data Guidelines

游戏内容使用 GDScript `Resource` 和 `.tres` 资产保存。资源只持有可编辑配置，不直接操作场景节点或 UI。

## Resource 形状

- 使用 `extends Resource`，需要编辑器创建时添加 `class_name`。
- 导出字段提供安全默认值；数组和字典默认空值，数值默认采用当前系统的中性值。
- 可序列化集合使用 `Array[Resource]` 或明确的类型数组；混合资源在消费点逐项检查。
- 编辑器由用户创建的同类配置集合必须导出专属类型数组，例如地形池使用 `Array[terrain_pool_entry]`、掉落条目使用 `Array[LootDrop]`。仅注册 `class_name` 而仍导出通用 `Resource` 不足以限制资源创建菜单。
- 嵌套资源字段使用具体注册类型；一个字段确实接收多种现有策略时，使用对应类型提示或共同基类限制创建选项。保留原来的序列化字段名、资源路径和数值。
- 资源类型链与检查器操作说明维护在 `docs/地形物资配置.md`，游戏机制汇总通过链接引用该入口。
- 字段名、大小写、数组顺序和默认值属于资产兼容协议，修改前必须搜索所有 `.tres` 和 `.tscn`。

## 资源职责

- 数据 Resource 只保存配置，例如物品、怪物、技能、地形、配方和天气。
- 随机抽样、库存扣除、冷却计时和战斗结算放在领域 Model/服务，不写进资源加载副作用。
- 运行时状态放在实例节点或 Model 中；多个场景共享的资源不能保存某一张卡的临时状态。
- View 通过稳定字段协议读取显示名、说明、图标和状态，不复制另一份内容表。

## 资产与生成文件

- `.tres` 的脚本路径必须指向当前 GDScript Resource；删除或改名脚本时先迁移资产再删引用。
- `scripts/generated/` 下的文件由插件或生成器维护，不能手工改输出文件。
- 新资源需要一个最小 `test_*.gd` 契约，覆盖默认值、字段读取和代表性资产加载。
- **批量加字段做最小文本插入，不要用引擎重存**：`ResourceSaver` 会省略等于默认值的属性行，用引擎重存一批资产会把 `cost = 10` 这类既有显式行整批删掉，产生与改动无关的巨大 diff。
- **批量文本改写前先处理换行符**：仓库 `core.autocrlf=true`，同一目录下的 `.tres` 在工作区可能是 LF 与 CRLF 混合的，而 git 的归一化会掩盖这一点。改写脚本必须先探测每个文件自身的换行符、把已有 `\r\n` 规范成 `\n` 再插入内容，最后按该文件原始换行符还原；若直接在含 `\r\n` 的文本上做 `replace("\n", "\r\n")`，既有 `\r\n` 会被二次转换成 `\r\r\n`，文件内容被真实改坏。改完用 `git diff --numstat` 核对形态（例如「每文件恰好 +1 行、0 删除」），不达标就整体回滚重做。

## 验证

资源结构变更后执行文件系统扫描、对应契约测试，并用实际使用该资源的场景冒烟；读取失败、空引用和错误脚本路径都必须在日志中可定位。

### 地形物资编辑器类型契约

适用范围：用户通过检查器创建房间候选物资、地形交互和采集掉落。具体用法见 `docs/地形物资配置.md`。

| 导出字段 | 类型或创建提示 | 验证要求 |
| --- | --- | --- |
| RoomTerrainProfile.TerrainPool | Array[terrain_pool_entry] | 数组元素提示包含 terrain_pool_entry，禁止普通 Resource 候选 |
| terrain_pool_entry.TerrainData | TerrainCardData | 新建菜单提供地形数据类型 |
| TerrainCardData.InteractionBehavior | 五种已有交互的 RESOURCE_TYPE 提示 | 采集、重复采集、农场、宝库、首领都可选，普通 Resource 不可选 |
| GatheringInteraction/ReusableGatheringInteraction.DropTable | LootTableData | 专属掉落表；类名避免与 MonsterData.LootTable 字段重名 |
| LootTableData.Drops | Array[LootDrop] | 每个条目独立配置物品、概率、数量 |
| LootDrop.Item | ItemData 的 RESOURCE_TYPE 提示 | 字段保持 Resource 协议，现有派生物品身份保留 |

成功案例：新建 terrain_pool_entry → TerrainCardData → ReusableGatheringInteraction → LootTableData → LootDrop，并把现有浆果物品拖入 Item。空槽案例：TerrainPool 内新增的 null 保留，生成器跳过，不擅自填充或删除用户编辑。错误案例：仅加 class_name 而继续让 TerrainPool 导出 Array[Resource]，菜单仍能创建无关资源，不能满足编辑体验要求。

新增契约套件 `terrain_resource_authoring` 必须验证全局类注册、真实 `EditorResourcePicker.get_allowed_types()` 过滤、对象属性提示和代表性资产加载。类型数组的提示字符串形如 `24/17:terrain_pool_entry`；不能错误断言它一定使用 PROPERTY_HINT_ARRAY_TYPE。脚本缓存刷新后仍要通过真实 Main 场景确认布局及采集行为。

注册类型改名时，已展开的检查器可能保留旧资源选择器的基础类型与创建菜单。出现 `Cannot get class LootTable` 时，先核对当前脚本注册名与 DropTable 字段都是 `LootTableData`，再检查用户实际控件的 `base_type`、`get_allowed_types()` 和菜单文字。刷新检查器必须重新展示同一资源对象，保留未保存字段；新建的孤立选择器通过测试不能替代现场控件验证。重建根检查器后内嵌资源可能折叠，需要重新展开或直接检查现有采集行为对象，再验证 DropTable 的真实创建菜单。

已有资产迁移只替换 TerrainPool/Drops 对应的数组元素脚本声明。无需改脚本路径、字段名、数值或批量引擎重存。退役的 `scripts/generated/create_terrain_profiles.gd` 不属于当前地图运行路径，其旧数组构造在重新启用前需核对类型兼容，不能为此手改生成文件。
