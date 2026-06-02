# 卡牌表格管理说明

本目录是项目的卡牌表格管理入口，路径为：

- `card_table/`

不要再使用旧目录 `tools/card_csv/`。旧目录已经迁移到项目根目录下的 `card_table/`。

Godot 编辑器会通过 `Card CSV Sync` 插件调用本目录中的同步脚本，实现技能卡、怪物卡资源与表格文件的双向同步。

## 文件说明

| 文件 | 是否建议手动编辑 | 作用 |
|---|---:|---|
| `card_tables.xlsx` | 是 | 推荐的人工编辑入口，带有 `element`、`targeting_type` 下拉选项。 |
| `skill_cards.csv` | 可选 | 技能卡 CSV，适合纯文本批量处理和查看 Git 差异。 |
| `monster_cards.csv` | 可选 | 怪物卡 CSV，适合纯文本批量处理和查看 Git 差异。 |
| `export_current_cards.py` | 否 | Godot 插件调用的同步脚本。 |
| `.sync_state.json` | 否 | 本地同步状态缓存，会自动生成，不应提交。 |
| `card_tables.pending.xlsx` | 否 | 当 `card_tables.xlsx` 被 Excel/WPS 锁定时生成的待应用工作簿。 |
| `.gdignore` | 否 | 让 Godot 忽略本目录，避免把 CSV 当资源导入。 |

## 推荐使用方式

1. 打开 Godot 编辑器。
2. 等待插件自动导出，或点击顶部菜单中的 `项目 -> 工具 -> 导出卡牌 CSV`。
3. 用 Excel、WPS 或 LibreOffice 打开 `card_table/card_tables.xlsx`。
4. 修改表格内容。
5. 保存并关闭 `card_tables.xlsx`。
6. 回到 Godot，等待自动同步，或点击 `项目 -> 工具 -> 同步卡牌 CSV`。
7. 在 Godot 控制台确认同步日志，例如：
   - `正在读取 XLSX 表格：card_table\card_tables.xlsx`
   - `读取到技能行 ... 条，怪物行 ... 条。`

如果只想批量文本处理，也可以直接编辑：

- `card_table/skill_cards.csv`
- `card_table/monster_cards.csv`

## 自动同步规则

插件会定时调用 `export_current_cards.py --auto`。

自动同步的大致规则是：

1. 如果 XLSX/CSV 在上次同步后被外部修改，脚本会先导入表格，再重新导出最新表格。
2. 如果 Godot `.tres` 资源比表格更新，脚本会从资源导出表格。
3. 如果都没有变化，只更新本地同步状态。
4. 如果 `card_tables.xlsx` 正在被 Excel/WPS 打开，脚本会把 Godot 资源变更写入 `card_tables.pending.xlsx`，等主 XLSX 解锁后自动替换。

## XLSX 打开时的注意事项

Windows 下 Excel/WPS 会锁定打开中的 `.xlsx` 文件。

因此：

- 当 `card_tables.xlsx` 打开时，Godot 无法直接覆盖它。
- 脚本会改为生成 `card_tables.pending.xlsx`。
- 关闭 `card_tables.xlsx` 后，下次自动同步会把 `card_tables.pending.xlsx` 替换为正式的 `card_tables.xlsx`。
- 如果你同时修改了主 XLSX 和 pending XLSX，脚本会优先保护较新的主 XLSX，避免覆盖你的手动编辑。

建议工作流：

1. 编辑 XLSX 时，先保存并关闭 XLSX。
2. 再回到 Godot 同步。
3. 如果要在 Godot Inspector 里改资源，最好先关闭 XLSX，或者等待生成的 `card_tables.pending.xlsx` 在关闭 XLSX 后被自动应用。

## 冲突处理原则

当前系统不会弹窗询问冲突解决方式。

如果 XLSX/CSV 和 Godot `.tres` 同时被修改，脚本会根据修改时间和 `.sync_state.json` 判断同步方向。

为了避免误覆盖，推荐遵守：

- 要改表格时：先改 `card_tables.xlsx`，保存关闭，再回 Godot 同步。
- 要改 Godot 资源时：先关闭 XLSX，在 Godot 里改完并保存资源，再等待自动导出。
- 不要同时在 Godot 和 XLSX 中改同一张卡或同一个怪物。

## `skill_cards.csv` 字段说明

| 字段 | 说明 |
|---|---|
| `resource_path` | 技能卡资源路径。新增技能卡时可以留空。 |
| `id_slug` | 新增资源的文件名标识，例如 `fire_blast`。已有资源导出时来自 `.tres` 文件名。 |
| `card_id` | 技能卡 ID，可为空。 |
| `card_name` | 技能中文名。 |
| `description` | 技能描述。 |
| `icon_path` | 技能卡图标路径。 |
| `cost` | 技能费用。 |
| `tags` | 标签，多个值用英文分号 `;` 分隔。 |
| `combat_skill_path` | 实际战斗技能资源路径。留空时按 `id_slug` 自动生成。 |
| `element` | 五行中文名，可填/选择 `无`、`金`、`木`、`水`、`火`、`土`。 |
| `targeting_type` | 目标类型中文名，可填/选择 `自身`、`单体敌人`、`全体敌人`、`任意单体单位`、`全体单位`、`随机敌人`、`扩散敌人`。 |
| `monster_owners` | 拥有该技能的怪物中文名，多个怪物用英文分号 `;` 分隔。也兼容怪物 `resource_path` 或 `id_slug`。 |

### `monster_owners` 示例

`淬火铁卫;锻铁战偶;铁鳞魔`

如果你从某个技能的 `monster_owners` 里删除一个怪物名，同步后脚本会从该怪物技能池中移除这个技能，除非怪物表中的 `skill_names` 对该怪物进行了手动覆盖。

## `monster_cards.csv` 字段说明

| 字段 | 说明 |
|---|---|
| `resource_path` | 怪物资源路径。新增怪物时可以留空。 |
| `id_slug` | 怪物文件名标识。已有资源导出时自动来自 `.tres` 文件名，例如 `anvil_cuihuotiewei.tres` 会导出为 `anvil_cuihuotiewei`。 |
| `monster_name` | 怪物中文名。 |
| `element` | 怪物五行中文名，可填/选择 `无`、`金`、`木`、`水`、`火`、`土`。 |
| `faction` | 阵营枚举数字。 |
| `model_scene_path` | 怪物模型场景路径。 |
| `behavior_tree_scene_path` | 行为树场景路径。 |
| `skill_names` | 怪物拥有的技能中文名，多个技能用英文分号 `;` 分隔。 |
| `base_phys_atk` | 基础物理攻击。 |
| `base_phys_def` | 基础物理防御。 |
| `base_mag_power` | 基础法术强度。 |
| `base_mag_resist` | 基础法术抗性。 |
| `base_speed` | 基础速度。 |
| `base_max_health` | 基础生命上限。 |
| `base_fixed_phys_penetration` | 基础固定物理穿透。 |
| `base_phys_penetration_rate` | 基础物理穿透率。 |
| `base_fixed_magic_penetration` | 基础固定法术穿透。 |
| `base_magic_penetration_rate` | 基础法术穿透率。 |
| `base_crit_rate` | 基础暴击率。 |
| `base_crit_damage` | 基础暴击伤害倍率。 |
| `base_evasion_rate` | 基础闪避率。 |
| `base_lifesteal_rate` | 基础吸血率。 |

`StartingStats` 中除 `BaseMaxEnergy` 以外的 `Base*` 基础属性都会同步到怪物表；`BaseMaxEnergy` 继续保留在资源默认值或 Inspector 配置中，不进入 CSV/XLSX 表格。

属性成长列已经从表格中移除，例如：

- `phys_atk_growth`
- `phys_def_growth`
- `mag_power_growth`
- `mag_resist_growth`
- `speed_growth`

这些成长属性不会因为表格中没有列而被清空；脚本只是不再通过表格编辑它们。

### `skill_names` 示例

`金芒覆八方;金术;鎏光咒`

如果你把 `淬火铁卫` 的 `skill_names` 改成：

`金芒覆八方`

同步后淬火铁卫的技能池会以这一列为准，变成只拥有 `金芒覆八方`。

## 技能归属优先级

技能归属有两个入口：

1. 技能表 `skill_cards.csv` / `card_tables.xlsx` 中的 `monster_owners`
2. 怪物表 `monster_cards.csv` / `card_tables.xlsx` 中的 `skill_names`

规则是：

- 如果某个怪物的 `skill_names` 被你手动改过，则这个怪物的技能池以 `skill_names` 为准。
- 否则，技能表的 `monster_owners` 是技能归属的权威来源。
- 删除 `monster_owners` 中的某个怪物名，会从该怪物技能池中移除对应技能。
- 删除怪物表 `skill_names` 中的某个技能名，会从该怪物技能池中移除对应技能。

## 新增技能卡

新增技能卡时：

1. 在 `skill_cards` 表中复制一行。
2. 清空 `resource_path`。
3. 填写唯一的 `id_slug`。
4. 填写 `card_name`、`description`、`element`、`targeting_type` 等字段。
5. 保存表格并同步。

脚本会自动创建：

- `resources/skill_cards/{id_slug}.tres`
- `resources/combat_skills/{id_slug}.tres`

注意：复杂 `Effects` 暂时不会通过表格展开编辑。新增技能的复杂效果需要后续在 Godot Inspector 中补充，或之后再扩展效果表。

## 新增怪物卡

新增怪物时：

1. 在 `monster_cards` 表中复制一行。
2. 清空 `resource_path`。
3. 填写唯一的 `id_slug`。
4. 填写 `monster_name`、`element`、`skill_names` 等字段。
5. 保存表格并同步。

脚本会自动创建：

- `resources/monster/{id_slug}.tres`

已有怪物导出时，`id_slug` 始终由 `.tres` 文件名决定。

## 编码与表格软件

CSV 使用 UTF-8-BOM 写出，方便 Excel/WPS 正常显示中文。

读取 CSV 时兼容：

- UTF-8-BOM
- UTF-8
- GB18030 / GBK

如果 Excel/WPS 打开 CSV 后锁定文件，脚本会跳过该 CSV 的写入，但不会中断导入流程。

## Git 与 Godot 导入说明

本目录包含 `.gdignore`，目的是让 Godot 忽略 `card_table/`，避免把 CSV 当成翻译资源或普通资源导入，生成无用的 `.import` / `.translation` 文件。

以下文件属于本地状态或生成文件，不应提交：

- `card_table/.sync_state.json`
- `card_table/card_tables.xlsx`
- `card_table/card_tables.pending.xlsx`
- `card_table/~$*.xlsx`
- `card_table/__pycache__/`

CSV、README、同步脚本和 `.gdignore` 应该提交。

## 手动命令

在项目根目录 `CUSGA/` 下可以手动运行：

- 导出表格：`python card_table/export_current_cards.py --export`
- 导入表格：`python card_table/export_current_cards.py --import`
- 双向同步：`python card_table/export_current_cards.py --sync`
- 自动判断：`python card_table/export_current_cards.py --auto`

## 常见问题

### 为什么 Godot 文件系统面板里看不到 `card_table/`？

因为本目录有 `.gdignore`。这是预期行为，用来防止 Godot 导入 CSV 和 XLSX。

### 为什么我改了 XLSX，Godot 没同步？

先看 Godot 控制台是否打印：

`正在读取 XLSX 表格：card_table\card_tables.xlsx`

如果打印的是 `正在读取 CSV 表格。`，说明脚本判断 CSV 更新，或 XLSX 没有保存成功。

建议保存并关闭 XLSX 后，再手动点击 `同步卡牌 CSV`。

### 为什么 Godot 里改了资源，XLSX 没变？

如果 XLSX 正在被 Excel/WPS 打开，脚本不能直接覆盖它，会先写入：

`card_table/card_tables.pending.xlsx`

关闭 XLSX 后等待下一次自动同步，或手动点击同步，pending 文件会替换正式 XLSX。

### `.sync_state.json` 能不能删？

可以。删除后下一次同步会重新生成。但一般不需要手动改它。
