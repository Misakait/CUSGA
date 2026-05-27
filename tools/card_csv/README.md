# 卡牌 CSV 管理说明

Godot 编辑器启动后会自动启用 `Card CSV Sync` 插件，并在本目录生成两张表：

- `skill_cards.csv`：技能卡表
- `monster_cards.csv`：怪物卡表

## 常用字段

### skill_cards.csv

- `resource_path`：技能卡资源路径；新增卡时可以留空。
- `id_slug`：新增资源的文件名，例如 `fire_blast`。
- `card_id`、`card_name`、`description`、`icon_path`、`cost`、`tags`：技能卡基础展示属性。
- `combat_skill_path`：实际战斗技能资源路径；留空时会按 `id_slug` 自动生成。
- `element`：五行枚举数字，`0=None`、`1=Wood`、`2=Metal`、`3=Water`、`4=Earth`、`5=Fire`。
- `targeting_type`：目标类型枚举数字，`0=Self`、`1=SingleEnemy`、`2=AllEnemies`、`3=AnySingleUnit`、`4=AllUnits`、`5=RandomEnemy`、`6=SpreadFromEnemy`。
- `monster_owners`：拥有该技能的怪物，多个值用英文分号 `;` 分隔；可填怪物 `resource_path`、`id_slug` 或 `monster_name`。

### monster_cards.csv

- `resource_path`：怪物资源路径；新增怪物时可以留空。
- `id_slug`：新增资源的文件名，例如 `flame_wolf`。
- `monster_name`、`element`、`faction`、`max_health`：怪物基础属性。
- `skill_paths`：怪物拥有的战斗技能，多个值用英文分号 `;` 分隔；可填技能卡路径、战斗技能路径、技能文件名或技能名。
- `skill_names`：只用于直观看，不作为导入依据。
- `base_*` 与 `*_growth`：怪物初始战斗属性。

## 使用方式

1. 打开 Godot 编辑器，插件会自动导出两张 CSV。
2. 用 Excel、WPS、LibreOffice 或 VS Code 修改 CSV。
3. 保存 CSV 后保持 Godot 编辑器打开，插件会每 2 秒检测一次并自动回写 `.tres` 资源。
4. 新增技能卡或怪物卡时，复制一行并清空 `resource_path`，填写唯一 `id_slug`，保存后会自动创建资源。
5. 也可以在 Godot 顶部菜单 `项目 -> 工具 -> 导出/同步卡牌 CSV` 手动同步。

## 注意事项

- 当前 CSV 主要管理卡牌与怪物的基础字段、归属关系和数值字段。
- 技能复杂效果列表 `Effects` 暂时保留原资源内容，不在 CSV 中展开编辑，避免破坏复杂子资源结构。
- 新增技能的 `Effects` 需要后续在 Godot Inspector 中补充，或者之后再扩展表格字段生成标准伤害/状态效果。
