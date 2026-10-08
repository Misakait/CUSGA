# 实施计划

## 1. 依赖与结构准备

- [ ] 检索并记录 `Main.tscn`、GameplayPort、Inventory/Equipment/BattleDeck 信号与测试引用。
- [ ] 在 `OpenBackpack.tscn` 建立三个 GridContainer 和根 Controller 导出路径，保留美术节点。
- [ ] 扩展 `ItemSlot` 的显示配置与背包拖拽接口，先保证仓库和商店现有调用兼容。

## 2. MVC 控制器实现

- [ ] 实现根 `InventoryUIController` 的打开/关闭、依赖绑定、共享 Tooltip、菜单和跨区域快捷协调。
- [ ] 实现 Inventory、Equipment、Deck 三个区域 Controller，按容量创建/复用 ItemSlot 并响应组件变化信号。
- [ ] 迁移旧背包的建筑菜单、合成请求、属性摘要绑定和拖拽/快捷协议，避免业务规则进入 View。

## 3. 主场景接线与文档

- [ ] 将 `Main.tscn` 的 InventoryUI 实例替换为 `OpenBackpack.tscn`，核对 `GameplayPortPath` 与 Tooltip 路径。
- [ ] 更新背包相关测试的节点路径和必要契约断言；保留旧实现回归覆盖。
- [ ] 同步 `docs/建筑系统.md`、`docs/游戏机制与玩法内容.md`，补充新 UI 入口、格子显示和 MVC 职责。

## 4. 验证与回滚点

- [ ] 使用 Godot 编辑器 MCP 扫描新增脚本和场景。
- [ ] 运行背包契约/性能测试，确认 ItemSlot 显示配置、节点复用、组件信号和旧接口。
- [ ] 冒烟运行 `OpenBackpack.tscn` 与 `scenes/Main.tscn`，读取游戏日志并检查几何布局和截图。
- [ ] 若主场景接线回归，先将 Main.tscn 恢复旧背包资源，再继续修复新场景。
