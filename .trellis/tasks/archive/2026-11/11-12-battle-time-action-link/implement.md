# 战斗行动值联动局外时间 — 执行计划

## 最小行为缺口

战斗 ATB 每次结算时，全体实体被扣掉同一段 `min_av` 来表示「战斗时间流逝」，但这段战斗时间没有进入 `TimeSystem`。结果是战斗可以推进任意多回合，局外昼夜、天数和 HUD 时间面板完全不动。

## 行为放在哪里

- 战斗侧：`scripts/battle_scripts/battle_manager.gd::_handle_calculate_turn()` 是唯一知道本次 `min_av` 的地方，因此必须在这里把战斗行动值交给时间桥。
- 换算侧：新增 `core/combat/battle_time_bridge.gd`，只负责「战斗行动值 × 倍率 → 整数局外时间点」和不足 1 点的小数余量累积，不持有时间权威。
- 时间权威：继续由 `TimeSystem.PassTime()` 推进；不修改 `TimeSystem` 内部规则，也不新增计时器。

## 预计修改文件

- `core/combat/battle_time_bridge.gd`：新增纯换算 RefCounted。
- `scripts/battle_scripts/battle_manager.gd`：新增导出倍率、可注入 `TimeSystemNode`、每回合调用换算并把整数点交给 `PassTime`。
- `tests/godot/test_battle_time_link_contract.gd`：新增契约测试，覆盖换算、余量、关闭、缺时间节点和入口调用。
- `tests/test_battle_time_link_contract.gd`：转发壳，保证 MCP 发现器能扫描到。
- `docs/游戏机制与玩法内容.md`：补充战斗时间联动规则、默认倍率和调参方式。
- `.trellis/spec/backend/gameplay-system-patterns.md`：沉淀战斗行动值到局外时间的单一换算边界。

## 明确不做

- 不改变 ATB 排序、`action_total`、速度公式或行动轴预测。
- 不改变昼夜阶段长度、颜色曲线、昼夜滤镜层级。
- 不把局外时间反向写入战斗 `action_value`；本次只做战斗 → 局外时间的单向联动。
- 不为「每张卡牌」单独扣时间；时间随 ATB 回合推进。

## 验证计划

1. 先写契约测试，确认当前缺少导出参数、入口和换算桥时失败。
2. 实现桥与 BattleManager 接入，跑 `battle_time_link_contract` 转绿。
3. 跑相关既有战斗/时间套件，区分本次回归与既有失败。
4. 在真实 `battle.tscn` 运行中记录初始与后续 `TimeSystem.TotalTimePassed`，确认 ATB 回合确实推进局外时间。
5. 检查 `git status`，只保留本任务改动；游戏停止、编辑器保持打开。

## 验证结果（2026-11-12）

- `battle_time_link_contract`：`7/7` 通过，`0` 失败。
- 首次 RED 因 MCP 返回 503 未能执行；实现后补做了真实 RED/GREEN：把 `_handle_calculate_turn()` 中的 `_advance_world_time_for_battle_action(min_av)` 临时注释后，`test_calculate_turn_calls_time_link` 失败（`6/7`），恢复后重新 `7/7` 通过。这证明入口测试不是空断言。
- 真实 `battle.tscn` 运行：初始 `TimeSystem.TotalTimePassed = 5.0`；连续结束玩家回合后依次观测到 `10.0`、`15.0`、`17.0`、`21.0`、`23.0`，ATB 状态正常在玩家回合（`2`）与执行/敌人回合（`4`）之间切换。
- 运行后读取游戏日志最近 25 条，未出现本次改动引入的 `SCRIPT ERROR` 或 `Parse Error`。
- 运行验证后 MCP 再次返回 503，无法调用 `project_manage(op="stop")`；已仅停止战斗子进程（PID 10844），Godot 编辑器进程（PID 34688）保持打开，未关闭编辑器。
- 仍待做：无关既有套件的回归结果未在本轮重跑；`test_item_room_content.gd` 仍是既有 Parse Error，与本任务无关。
