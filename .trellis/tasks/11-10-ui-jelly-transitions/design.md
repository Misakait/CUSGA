# UI 自然过渡设计

用户于 2026-11-10 反馈旧版过于晃眼，要求更多自然效果。本轮只更换表现曲线、调用参数和对应测试，保留界面美术、业务架构及生命周期。

- 共用 `core/ui/transitions/ui_transition.gd`（`UITransition`）局部 Node；原 `core/ui/ui_jelly_transition.gd` 为兼容入口。不新增全局单例，保留所有现有面板节点路径。
- 调用方拥有 show/hide、导航、库存和暂停；表现助手只变更指定 CanvasItem 的位置、比例、透明度并临时阻挡鼠标误操作。
- 首次显示等待 Container 排版；退出树/缓存离场复原原属性，快速反向请求撤销旧回调。
- 助手 setup 末尾增加可选 MotionStyle，前四个位置参数兼容。SOFT_SCALE 等比缩放、RISE 上浮、SLIDE 侧滑、FADE 纯淡入；不保留旧的强回弹曲线。打开使用 cubic 缓出，关闭使用 smoothstep，透明度单调变化。
- 主菜单 RISE 0.24 秒；仓库 RISE 0.24 秒、错峰 0.015 秒；商店 SLIDE 0.24 秒且外框内容同步；背包 SOFT_SCALE 幅度 0.02、0.22 秒；合成 RISE 0.22 秒；设置 SOFT_SCALE 幅度 0.015、0.20 秒；大地图 FADE 0.20 秒；暂停菜单 FADE 0.18 秒。关闭统一 0.14 秒，暂停遮罩退场与其同步。
- RISE 打开 Y 位移 12→0、关闭到 6；SLIDE 打开 X 位移 16→0、关闭到 8。SOFT_SCALE 打开倍率 1-strength→1，关闭到 1-strength×0.5；FADE 不移动或缩放。默认 strength=0.02（限制 0～0.04）、duration=0.22。
- 局外 SceneManager 采用页面退场/入场薄入口串行切换，已有战斗/换房黑幕不改。
- 地图与暂停菜单关闭完成才归还暂停，关闭中重开保留首次记录。两者通过局部 ui_pause_owners 节点组交接恢复责任：另一界面仍展开或退场时继续保持暂停，最后一方退出才恢复；外部初始暂停和结算接管不被解除。
- 业务门禁、Tooltip、原生拖放和焦点在过渡期间必须协调，移动中的格子不提交交易。

验证：在已连接 CUSGA Godot 4.7.1 编辑器加载/测试，通过游戏进程检查中间尺度、暂停、重入和收尾；使用隔离或备份存档。禁止用旧版命令行 Godot 验证。

## 独立组件整理

- 唯一内核迁入 `core/ui/transitions/ui_transition.gd`，注册普通 `UITransition` 节点类型，继续保持无业务依赖。目录内提供 `ui_transition.tscn` 作为可拖入场景的入口。
- 添加检查器目标路径、样式、轻缩放幅度、入场时长和错峰配置；原 `setup/play_open/play_close/reset` 与查询入口保留。场景中的组件在 ready 时解析配置；代码创建的组件继续使用 setup，避免隐式覆盖现有配置。
- `core/ui/ui_jelly_transition.gd` 留作薄继承兼容入口并保留原 UID，不维护第二套动画代码。现有七个控制器和主测试引用新内核路径；不改原面板节点路径或业务状态流转。
- 不新增 Autoload、存档字段或编辑器插件。目录 README 给出检查器和代码两种接入方式；显示/隐藏、导航与暂停责任仍由宿主管理。
- 验证新增检查器配置解析、旧入口继承的 API 与枚举、既有运行检查、真实登录导航和 Main 的背包/地图/暂停行为。实际完成组件42项、合成32项、分组暂停166项、主菜单与导航7项、Main背包5项、Main地图与暂停6项检查，编辑器指定套件3项通过。结果见 `research/validation-component.json`。
