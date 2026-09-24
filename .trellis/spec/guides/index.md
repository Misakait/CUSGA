# Thinking Guides

这些指南用于在修改 GDScript、场景、资源和 UI 前识别边界风险。

## 开始功能前

- [ ] 修改无缝地图前先读 .trellis/workspace/huhu9/map-world-mvc-architecture-2026-09-24.md，按其中的 MVC 边界和房间模块约定设计。
- [ ] 对复杂场景列出各容器的单一职责 Controller，检查有没有把子系统逻辑堆到根脚本或一个大 Controller 中。
- [ ] 对同类场景检查节点结构差异；记录缺少的容器和历史节点拼写，防止场景漏挂控制器。
- [ ] View 通过稳定公开入口传递上下文；不从上层 View 硬编码访问下层容器内部节点。
- [ ] 明确功能属于 Model、View、Controller、Resource、场景或插件。
- [ ] 用 `rg` 找到脚本、节点、信号、资源字段和 autoload 的调用方。
- [ ] 画出输入 → Controller → Model → 信号 → View 的数据流。
- [ ] 选择最小的 `test_run` 或 `project_run` 验证路径。

## 常见边界

- 场景序列化值与运行时属性可能不一致。
- `Variant`、字典和动态 `call` 可能丢失类型或字段。
- 节点释放后仍留在缓存中会导致悬空实例。
- View 直接修改 Model 会绕过校验、信号和持久化。
- 多个资源副本会导致显示内容、堆叠身份或配置数值漂移。

## 修改前硬规则

- 地图跨房同时验证 Model 邻接连接与三类边界：Ground 的 Boundary 保持常设，BridgeWithBoundary 按方向开闭桥口，BridgeBoundary 限制桥两侧；不得按房间矩形推算开口。

- 先搜索引用，再改公开脚本路径、节点名、信号名和资源字段。
- 先确定所有者，再决定状态放在 Model、节点还是资源中。
- 修改完整房间前先检查 `MapContainer`、`BridgeContainer`、`BridgeWithBoundary`、`BridgeBoundary`、`Ground`、`Obstack` 和 `Boundary` 的控制器职责；不要把多个容器的逻辑集中到房间根脚本。
- 修改 Bridge、地面或障碍时先确认控制器只管理自己的直接子节点，再检查 TileSet 碰撞层、三类边界状态和 `scene_to_scene` 连接是否一致。
- 不新增 GitNexus、CodeGraph、.NET 或其他与 GDScript 无关的工具链。
- 不把历史设计文档中的迁移方案当作当前实现依据。
