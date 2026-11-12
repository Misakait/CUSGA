# 战斗昼夜滤镜只作用于背景 — 执行记录

## 行为缺口

- 战斗场景的 `day_night_filter.tscn` 实例默认 `z_index = 1500`，覆盖卡牌（常态 `1`）、怪物卡（`0`）、玩家等战斗内容；只有 `UI` / `Button`（`2000`）在滤镜之上。
- 目标是把滤镜夹在背景与全部玩法内容之间，使夜晚只压暗背景。

## 层级契约

| 节点 | z_index | 作用 |
| --- | ---: | --- |
| 静态测试背景 | -1000 | 被滤镜染色 |
| 运行时复制 `MapBackground` | -2 | 被滤镜染色 |
| `DayNightFilter` | -1 | 只覆盖背景 |
| 怪物卡 | 0 | 不受时间颜色影响 |
| 卡牌常态 / 悬停 | 1 / 2 | 不受时间颜色影响 |
| `UI` / `Button` | 2000 | 不受时间颜色影响 |

## 修改文件

- `scenes/battle_scenes/battle.tscn`：给 `DayNightFilter` 实例显式覆盖 `z_index = -1`。
- `core/gameflow/UICurrentMapBackgroundResolver.gd`：新增 `MAP_BACKGROUND_Z_INDEX = -2`，复制背景时使用该常量，保持 `z_as_relative = false`。
- `core/ui/filters/day_night_filter.gd`：更新挂载说明，明确战斗场景夹在背景与玩法内容之间，不再“压住世界”。
- `tests/godot/test_day_night_filter_contract.gd`：新增战斗层级契约与背景复制行为测试。
- `docs/游戏机制与玩法内容.md`：同步战斗场景的完整层级表。
- `.trellis/spec/frontend/component-guidelines.md`：补充“只染背景”与“压住世界但保留 UI”两类覆盖层的选层规则。

## 验证

- TDD：新增测试先失败（未覆盖时 `filter_z` 继承 `1500`，高于卡牌）；恢复 `z_index = -1` 后通过。
- `day_night_filter_contract`：`8/8` 通过。
- `passage_guard_monster_resolver_contract`：`1/1` 通过。
- 运行期战斗场景：`filter_z = -1`、静态背景 `-1000`、卡牌 `1`、怪物卡 `0`、`UI` / `Button` `2000`；夜晚滤镜色约为 `(0.3564, 0.4155, 0.6498)`。
- 运行期截图：夜晚背景明显压暗，卡牌、怪物卡、玩家与 HUD 保持原亮度。
- 既有无关问题：`test_item_room_content.gd` Parse Error；`reusable_gathering` 有 2 个既有资产断言失败（普通物品/工具资产计数与旧 C# 标头）。均与本次层级改动无关。
- 游戏已停止，编辑器保持打开；`git diff --check` 通过。

## 未做

- 未提交、未推送、未归档 Trellis 任务。
- 未修改昼夜颜色曲线、TimeSystem、探索场景 CanvasLayer 分层或卡牌常量。
