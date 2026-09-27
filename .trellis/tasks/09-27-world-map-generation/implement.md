# 实施计划：大小地图生成、交互与标记系统

状态：第一阶段生成与桥接已经提交；第二阶段交互、标记与地图选项已经完成实现和 Godot 4.7.1 运行验证。任务保持 `in_progress`，等待用户决定是否提交与归档。

## 0. 动手前核对

- [x] 读取 `trellis-before-dev` 和 `.trellis/spec/backend/`、`.trellis/spec/frontend/` 的相关规范。
- [x] 重新运行 `git status`，确认并保护用户已有的 `project.godot`、三个地图 View 场景、`res/room_icon/` 和 `little_map_me.tscn` 删除。
- [x] 用 `rg` 再次核对 `MapWorldModel`、`RunSnapshot`、`MapLittle`、`CanvasLayer`、`open_map` 和相关动态方法/信号的调用方。
- [x] 通过 Godot 编辑器 MCP 的 `editor_state` 或 `session_manage(op="list")` 确认 Godot 4.7.1 已打开 CUSGA；没有连接时暂停实施并请用户打开编辑器。

## 1. 探索状态 Model 与快照

- [x] 在 `MapWorldModel` 增加探索集合、首次探索信号和只读查询/揭示接口；起始房间和旧存档当前房间自动加入。
- [x] 保证 `try_enter_room()` 只在原有校验成功后揭示房间；失败、非相邻和单向连接不改变探索状态。
- [x] 在 `RunSnapshot` 的 `run_world` payload 编解码探索坐标；缺失字段兼容旧存档。
- [x] 扩展地图 Model 与快照测试，覆盖初始化、幂等、失败请求、保存恢复和旧数据兼容。

## 2. 共享 WorldMapCanvas

- [x] 新建 `UIWorldMapCanvas.gd` 并挂载到 `WorldMapCanvas.tscn`；保留 `RoomsContainer`、`PinesContainer`、`PlayerMarker` 用户节点。
- [x] 接入用户新建的 `RoomTemplate.tscn`；`RoomsContainer` 生成模板，`RoomView` 管理纹理，`BridgeContainer` 管理四方向桥。
- [x] 把 `UIWorldMapCanvas.gd` 拆成 Model 协调、模板集合、模板协调、纹理 View、桥容器与无状态桥策略脚本，避免根脚本集中所有图元逻辑。
- [x] 默认显示已探索房间的所有真实连接桥，即使邻居尚未探索；保留“仅双方已探索”模式接口；双方已探索时按坐标分配唯一桥所有权；上下桥使用独立竖桥素材且不旋转。
- [x] 实现 Model 绑定、全量刷新、增量揭示、当前房间纹理更新、坐标查询和只读诊断计数。
- [x] 增加画布契约测试，覆盖模板结构、重复刷新、桥去重、未探索方向桥、策略切换和当前房间纹理切换。

## 3. MiniMap、LargeMap 与兼容适配

- [x] 在 `MiniMap/MaskContainer` 和 `LargeMap/ViewportControl` 下分别实例化 `WorldMapCanvas.tscn`。
- [x] 新建 MiniMap View 脚本：显式绑定 Model、使用实际遮罩尺寸聚焦当前房间、应用小地图独立缩放。
- [x] 新建 LargeMap View 脚本：显式绑定 Model、使用 `open_map` 切换、显示时聚焦当前房间、应用大地图独立缩放；不实现暂停/拖拽/滚轮。
- [x] 将新 MiniMap 和 LargeMap 接入 `map_control.tscn`；保留 `MapSystem/CanvasLayer` 和 `MapLittle` 节点路径。
- [x] 把 `UIMapLittle.gd` 改为 Model 兼容适配器，保留四个旧公开方法，不再生成旧格子和 SubViewport 内容。
- [x] 更新 `UIMapControl.gd`，把同一个 Model 绑定给新旧 UI；保持 `on_entered_room` 对棋盘、建筑和背景的原语义。
- [x] 增加场景和兼容测试，确认两个画布实例独立、生成结果一致，旧动态调用入口仍可执行。

## 4. 编辑器验证与视觉检查

- [x] 调用 `filesystem_manage(op="scan")` 刷新新增/修改的 GDScript。
- [x] 用 `test_run` 运行地图世界、地图 UI、快照和受影响兼容套件。
- [x] `project_run(mode="custom")` 冒烟 `res://scenes/map_scenes/map_view/MiniMap.tscn` 与 `LargeMap.tscn`；读取游戏日志，确认独立打开时不报缺少绑定 Model。
- [x] 冒烟 `res://scenes/Main.tscn`；用 `game_eval` 检查起始房间、两个画布计数与相邻房揭示同步；读取日志。
- [x] 用 `editor_screenshot(source="game")` 检查小地图裁切与居中、大地图聚焦、房间和桥层级；只修正本任务引入的布局问题。
- [x] 测试结束仅调用 `project_manage(op="stop")`，不关闭 Godot 编辑器。

## 5. 文档、质量与收尾

- [x] 更新 `.trellis/workspace/huhu9/map-world-mvc-architecture-2026-09-24.md`，写入已经验证的大小地图数据流、节点职责和后续接口。
- [x] 更新 `docs/游戏机制与玩法内容.md`，记录探索揭示机制、临时图标和明确未实现项。
- [x] 使用 `trellis-check` 完成规格、格式、引用、测试和跨层数据流检查。
- [x] 重新运行 `git status` 和 `git diff`，区分本任务改动与用户原有改动；不提交、不推送，除非用户另行明确要求并在提交前完成规定报告。

第一、第二阶段的最终验证证据均已写入 `runtime-validation.md`；Git 提交、任务归档和提交后的 Trellis 会话记录仍须等待用户明确同意。

## 6. 第二阶段资源与标记 Model

- [x] 新增 `MapMarkerConfig` Resource 脚本和两份 room_marker 配置资源，字段覆盖显示许可、图标、激活、比例、类型键、显示名与玩家可放置属性。
- [x] 扩展 `MapWorldModel`：稳定来源标记注册、玩家标记新增或删除、只读快照、变更信号和逻辑地图坐标换算。
- [x] 新增 `UIMapMarkerController`，接入 `Item.tscn/MarkerController/MarkerPoint`；`item_view.gd` 只转交房间身份。
- [x] 给 `PinesContainer` 挂载 `UIWorldMapMarkersContainer`，两份画布绑定同一 Model 并同步刷新。

## 7. 第二阶段大小地图交互

- [x] `UIWorldMapBridgeContainer` 上下方向改用 `Room_Bridge_V.png`，不再旋转横桥。
- [x] 小地图新增可配置 Tween 过渡；读取和监听 `map/minimap_zoom` 偏好。
- [x] 新增 `UIMapPanZoomController`，实现导出上下限、鼠标中心缩放、拖拽阈值、点击或右击坐标事件。
- [x] 重构 `UILargeMap` 只协调可配置 InputMap 动作、暂停、聚焦、标记选择和 Model 调用；打开前暂停状态可恢复。
- [x] 将 `LegendUI` 改成有固定宽度、滚动列表、图标名称、明确选中态和操作提示的标记选择面板。
- [x] `project.godot` 的 `open_map` 使用物理 T 键；`UILargeMap.open_map_action` 导出到 Inspector，脚本不硬编码按键。

## 8. 第二阶段地图设置 UI

- [x] 完成 `option_panel.tscn` 的“地图”分类、小地图缩放滑条、当前值、恢复默认和返回按钮，并新增单一职责脚本。
- [x] 给 `pause_menu.tscn` 增加“参数设置”按钮和 OptionPanel 实例；主菜单或设置页切换不解除暂停。
- [x] 如需即时广播偏好变化，只给 `SettingsManager` 增加通用 `setting_changed` 信号，不让设置页直接依赖 MiniMap 节点路径。

## 9. 第二阶段测试与文档

- [x] 扩展地图 UI 或 Model 契约测试，覆盖竖桥、标记配置、去重、同步、缩放界限、T 键输入动作、暂停和设置偏好。
- [x] 用 Godot 编辑器 MCP 扫描脚本，运行目标套件并冒烟 MiniMap、LargeMap、option_panel、pause_menu、Main。
- [x] 用 `game_eval` 与截图核对大地图拖拽缩放、图例选中、放置或删除标记、两张地图同步和暂停状态。
- [x] 更新地图架构文档、《游戏机制与玩法内容》和必要 spec；`runtime-validation.md` 等待主代理完成 Godot MCP 后追加证据。重新核对 Git 状态，不提交或推送。

## 主要风险文件与回退点

- `scenes/map_scenes/map_control.tscn`：同时承担旧兼容路径和新 UI 接线。先保留节点名，再逐项替换内部显示；若新 UI 集成失败，可回退本文件的接线而不触碰地图 Model/世界 View。
- `scripts/map_scripts/UIMapLittle.gd`：动态调用较多。所有公开兼容方法保留原名和参数；若调用链异常，优先修适配，不恢复双份探索状态。
- `core/gameflow/run_snapshot.gd`：增加字段必须向后兼容。缺失或损坏的探索字段退化为当前房间，不影响其他存档字段。
- 三个用户新建场景和 `project.godot`：属于用户原始未提交内容，不能整文件重建或用仓库版本覆盖。
