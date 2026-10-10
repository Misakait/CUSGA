# 使用 WarehouseNew 替换局外仓库

## 目标与已确认背景

主菜单仓库入口使用 WarehouseNew。用户要求五项功能，明确新场景功能已删减，item_slot2 的 normal/hover/pressed 已配置，禁止另造外观。
用户已批准此前规划范围并指示：“是的是的，进入规划然后干活”。规划完成后直接实施，无需再次流程确认。
仓库/行囊权威分别为 GlobalWarehouse/ItemsControl，升级和金钱权威为 PlayerProgression/PlayerWallet；编辑器4.7.1已连接。

## 需求

1. 在 ItemSection/ScrollContainer、PackbackSection/ScrollContainer 下生成全部仓库容量及可用行囊容量的格子，刷新复用。
2. 全部实例化 item_slot2.tscn，原样保留既有三种样式，不覆盖、重画或染暗。
3. 一键整理、两处升级和去商店有效。Cost 显示下一级真实费用；CoinCount 响应钱包余额变化；CapacityLabel 显示行囊占用/容量。余额不足及满级禁止升级。
4. 点击有物品格子显示名称与描述，复用 CraftingUI 的 TooltipPanel/物品兼容读取协议；物品可拖动，支持跨区及同区调整位置，遵循现有合并/交换规则，失效来源和无效目标不能丢失或复制物品。
5. 返回请求 main_menu；去商店请求 shop。进出清理提示和订阅，缓存重入不重复生成格子。
6. 保持带回物品回收、开局带入消耗、存档格式及原有容量费用规则。

## 范围外

不恢复分页、放入/取出按钮或其他已删控件，不修改 CraftingUI、商店美术、item_slot2样式、价格、存档格式，不自动提交推送。

## 验收

- [x] 主菜单进入 WarehouseNew，返回和商店有效。
- [x] 两区全部格子路径为 item_slot2，布局正确，刷新复用。
- [x] 整理、升级扣费扩容、费用和余额文案及不足/满级边界正确。
- [x] 点击描述正确；真实跨区/同区拖动数量守恒，无效拖动无副作用。
- [x] Godot MCP 扫描、聚焦测试、新仓库/主菜单/Main冒烟无本次引入错误，保存原有权威协议。
- [x] 同步机制文档和组件契约，验证后核对Git差异。
