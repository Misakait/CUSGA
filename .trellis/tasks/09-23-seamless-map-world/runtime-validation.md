# 无缝地图运行验收

会话验收日期：2026-09-24。宿主本地时钟记录为 2026-09-25，Asia/Shanghai（UTC 日期为 2026-09-24）。
验证环境：已打开的 CUSGA Godot 4.7.1-stable 编辑器，godot_ai 4.2.2。
用户授权：「好的我现在允许你godot运行验证，但是要注意不要截图，不然就完蛋了」。

## 结论

- 两个新增契约套件在新启动的游戏进程中执行：12 个用例全部通过，30,725 个断言，0 个跳过，0 个脚本异常。
- clear_creek、ordinary_wetland、forest_path、map_control、Main 均通过场景运行检查；最终 Main 和 map_control 运行日志没有新增错误或警告。
- Main 中通过原有移动输入绕开市场障碍，完成 (7,6) → (7,7) → (7,6) 往返。没有给玩家位置赋值，没有修改移动脚本。
- 只停止了运行中的游戏；Godot 编辑器仍打开。没有截图、生图、视觉审查、Trellis CLI/MCP、命令行 Godot 或 .NET 操作。

## 契约测试

| 套件 | 用例数 | 断言数 | 游戏进程结果 |
|---|---:|---:|---|
| map_world_contract | 7 | 75 | 全部通过 |
| room_module_controller_contract | 5 | 30,650 | 全部通过 |

覆盖 12 个真实 normal 房间的 16 种方向组合、重复配置、固定模块不变、全部实际瓦片碰撞、玩家真实 100×140 矩形、四方向桥中心/双侧/封闭桥口、上下房间接缝、非法进入拒绝、信号兼容、节点回收及资源复用。

编辑器 test_run 的两个新套件合计为 6 通过、6 明确跳过，不能将它单独作为全部通过的依据：插件仅发现 tests/ 顶层入口，不等待异步测试；非 @tool 场景脚本在编辑器内是占位实例。已补两个顶层入口，将需要真实节点或物理帧的用例明确转交游戏进程。

游戏验证逐个 await suite.call(test_method)，使用 script_error_capture.gd 注册临时日志捕获器，把脚本异常也计入失败，并在每例后回收夹具。没有把业务脚本改成 @tool，也没有修改测试插件。

额外回归：room_board_presenter_contract 为 5 通过、1 跳过（项目已移除的旧 C# 垫片）；room_terrain_store_contract 为 12 通过。后者重复地形/空配置两个反例故意输出错误信息，属于已有测试的预期诊断，不是游戏运行错误。

## Main 实际移动与生命周期

- 出生点 (640,360)，当前坐标 (7,6)，当前场景 ordinary_market，初始 9 个有效房间。
- 直接向右行走在 x≈877.998 被市场原有障碍挡住。碰撞对象为 Obstack/TileMapLayer，接触边 x=928；符合玩家半宽 50 和碰撞余量。
- 绕行采用移动输入，路径约为 (878,230) → (1040,230) → (1040,352) → (1370,352)，然后返回 (1040,352)。初始选卡界面仅在测试进程调用 _close_draft 恢复暂停，没有发放卡牌。
- 跨向 common_forest 时玩家 x=1280.7606；返回市场时 x=1277.3057。最大相邻物理帧位移 3.333374 像素，符合 200 像素/秒、60 物理帧，无传送跳变。
- 两次跨房分别收到一次进入房间信号；Main 保持当前场景，未暂停进入战斗。小地图新格高亮，RoomTerrainStore 建立对应房间，RoomBoardPresenter 日志记录两次正确房间。
- 活跃窗口仍为 9 个。旧窗口的 (6,5) 房间节点确实销毁且从字典移除；返回后节点实例 ID 改变，MapSceneResource 和 PackedScene 与原对象相同。
- TimeSystem.TotalTimePassed 在移动前、跨出和返回后始终为 0；新跨房源码也没有调用地图耗时、驻守、传送或过场入口。

## 日志与工具边界

- 最终 Main 游戏 run_id 为 r2014030-6：37 条日志、0 错误、0 警告；最终 map_control 为 r2379593-7：19 条日志、0 错误、0 警告。
- 首轮编辑器中的占位实例错误仍是历史日志。修正执行环境后，12 个游戏用例全部重新执行通过。
- 临时移出方向层的测试夹具曾产生 owner 警告；已在移出前清空 owner、恢复后归还。最终游戏复测无警告。
- map_control 首次立即查询遇到 250ms 存活探测超时；重新启动并等待初始化后，读到当前坐标 (7,6)、9 个实际/预期活跃房间，日志正常。
- 截图被用户明确禁止，因此没有对画面美观作验收；连续性依据坐标采样、实例身份、信号及物理测试判定。

## 后续复现

先列出会话，选择 CUSGA / Godot 4.7.1；本轮另有一个 test 项目，不能直接使用默认会话。扫描后运行两个 test_run 套件，再 project_run(custom, clear_creek.tscn, autosave=false)。等待 helper 就绪，通过 game_eval 执行以下代码；结束只 project_manage(stop)。测试器的预加载缓存提示不能用来替代新游戏进程验证。

```gdscript
var capture = load("res://addons/godot_ai/testing/script_error_capture.gd").new()
OS.add_logger(capture)
var reports: Array = []
for path in ["res://tests/godot/test_map_world_contract.gd", "res://tests/godot/test_room_module_controller_contract.gd"]:
    var suite = load(path).new()
    for entry in suite.get_method_list():
        var method = String(entry["name"])
        if not method.begins_with("test_"):
            continue
        suite._reset()
        capture.begin_capture()
        suite.setup()
        await suite.call(method)
        suite.teardown()
        suite._free_tracked()
        var errors = capture.end_capture()
        reports.append({"test": method, "passed": not suite._failed and errors.is_empty(), "skipped": suite._skipped, "assertions": suite._assertion_count, "message": suite._message, "errors": errors})
        await get_tree().process_frame
OS.remove_logger(capture)
return reports
```
