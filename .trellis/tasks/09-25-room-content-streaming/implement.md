# 实施计划：九宫格房间内容与地形卡生命周期

状态：用户已确认实施，战斗中退出按战斗前世界快照恢复。

## 0. 动手前核对

- [ ] 读取 `AGENTS.md`、`agent.local.md`、`.trellis/spec/backend/` 和 `.trellis/spec/frontend/` 相关规范，以及地图、建筑、存档、游戏机制文档。
- [ ] 用 `rg` 核对将改动的脚本路径、公开方法、信号、节点路径、`Resource` 字段在 `.gd`、`.tscn`、`.tres`、`project.godot` 和测试中的全部引用；记录用户已有未提交改动。
- [ ] 确认 `Item.tscn` 的用户改动仍是当前版本，逐项核对 `Collision`、`Interaction`、`Visuals`、`AnimationPlayer` 层级。
- [ ] 核对战斗入口、结算返回和退出时的保存调用，锁定战前快照不被战斗中间态覆盖。

## 1. 状态与内容窗口

- [ ] 为地图视图增加房间激活/退出通知，并保证新窗口内容先就绪、旧窗口内容后释放；新增初始 3×3 的补偿绑定。
- [ ] 新建 `RoomLootStore`：按房间保存稳定 ID、物品堆叠和局部最终落点；掉落先登记后播散射，拾取按 ID 单次移除。
- [ ] 增加 `RoomContentStreamer` 和每房间 `RoomContentRoot`：首次进入窗口才生成地形；已生成房间只按原状态重建；九房增量实例化，窗口外彻底释放视图索引和节点。
- [ ] 改造 `UIRoomBoardPresenter`、`BoardController` 与建筑表现层，使卡牌索引包含房间坐标，保留当前房间旧 API 兼容入口，建筑规则和状态仓库不重复实现。
- [ ] 增加内容放置安全校验，避免地形阻断桥口、与已有障碍/玩家/建筑重叠；确认掉落退化落点也合法。

## 2. Item 表现与交互

- [ ] 基于用户的 `Item.tscn` 绑定地形和掉落数据，保持棋盘卡公开信号/方法协议；`Interaction` 统一处理鼠标输入，视觉按钮忽略输入。
- [ ] 将地形物理层与 `PlayerChar` 掩码对齐；掉落禁用 `Collision` 且物理层/掩码为 `0`，保留 `Interaction` 可点击。
- [ ] 新建检查器可编辑的内容表现和动作配置 `Resource` / `.tres`，设置安全默认值与中文注释；保留原地形池资源及生成参数。
- [ ] 实作 `Idle` 与 `Hover`，检查 `Idle` 没有 `position` / `rotation` 轨道，两者只动 `Visuals`；悬停、散射、拾取与卸载的动画优先级明确。
- [ ] 改拾取目标为 `PlayerChar`；库存成功后立即移除掉落状态并关闭命中，纯视觉飞行期间追随角色；库存失败保持掉落原状。

## 3. 可切换的局内保存

- [ ] 定义唯一的局内快照格式和编解码：地图布局/连接、房间内容、玩家位置与局内数据、时间；资源使用稳定身份，不序列化节点。
- [ ] 先核对 `project.godot` 当前 autoload 顺序与参与者实际 `_ready()` 时序，再将 `SaveManager` 的启动顺序修正到既有协议要求，并锁定主场景读档回归。
- [ ] 加入默认 `SESSION_ONLY`、可切换 `DISK` 的配置与运行时接口；门禁 `SaveManager` 的 `run` 读写，同时保持 `global` 原有自动存档。
- [ ] 让运行时模式选择经 `SettingsManager` 持久化，启动时先读取模式再决定是否恢复 `run`；内存模式保留旧磁盘快照但不应用、不以当前局覆盖。
- [ ] 修正启动时序：先决定新局或继续本局，再恢复地图与局内状态，最后创建九房并开放输入；继续本局必须绕过 `RunStartInitializer` 的新局清包逻辑。
- [ ] 覆盖运行时切换两方向、退出后重进、损坏/缺失配置、旧存档兼容和恢复失败的可诊断行为。
- [ ] 进入战斗前同步写稳定世界快照，战斗期间暂停局内写入；重启验证恢复战前世界而非半场战斗。

## 4. 验证与文档同步

- [ ] 先补聚焦的仓库/坐标/窗口/存档模式测试，再补 `Item` 交互与动画契约、主场景集成回归；不要让测试只重复实现细节。
- [ ] 用 Godot 编辑器 MCP 的 `editor_state` 或 `session_manage(op="list")` 确认打开 CUSGA；`filesystem_manage(op="scan")` 刷新脚本；`test_run` 运行相关 `tests/godot/` 套件。
- [ ] 对 `res://scenes/ItemTerrian/Item.tscn` 和 `res://scenes/Main.tscn` 分别 `project_run(mode="custom", scene=...)` 冒烟，读取 `logs_read(source="game")`，必要时用 `game_eval` 检查活动房间数、节点数、碰撞和状态；测试结束只调用 `project_manage(op="stop")`。
- [ ] 检查 `SCRIPT ERROR`、`Parse Error`、资源加载错误和本次修改资源的 UID 警告；改动后重查 `git status`，不覆盖用户工作区已有内容。
- [ ] 同步地图/建筑/存档模块文档与 `docs/游戏机制与玩法内容.md`；逐项记录新增数值的单位、生效条件、默认值及资源字段。更新 `.trellis/spec/` 中由本任务确立的长期契约。

## 风险点与回退点

- `scenes/Main.tscn` 同时接线地图、棋盘、建筑和玩家，最后一个阶段才切换主场景引用；旧 `BoardCardView.tscn` 保留到新链路通过全部运行验证。
- `SaveManager` 的主档同时包含 `global` 和 `run`，改变写入门禁时必须确保局外资产不会被错误清空；先用临时 `user://` 路径测试，再检查真实主场景。
- `Item` 的 `CharacterBody2D`、视觉按钮和独立 `Area2D` 同时存在，必须用游戏内运行检查鼠标事件和物理层，不能仅靠 `.tscn` 文本推断。
- `RoomTerrainStore` 当前持有运行时 `RefCounted`，跨重启序列化必须显式列字段并复制值，不能把它们当 JSON 对象直接写入。
