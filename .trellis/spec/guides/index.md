# Thinking Guides

这些指南用于在修改 GDScript、场景、资源和 UI 前识别边界风险。

## 开始功能前

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

- 先搜索引用，再改公开脚本路径、节点名、信号名和资源字段。
- 先确定所有者，再决定状态放在 Model、节点还是资源中。
- 不新增 GitNexus、CodeGraph、.NET 或其他与 GDScript 无关的工具链。
- 不把历史设计文档中的迁移方案当作当前实现依据。
