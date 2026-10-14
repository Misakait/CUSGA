# 四界面右键取消选中复核

日期：2026-10-14。复核由已派出的 trellis-check 执行，未嵌套派代理。主会话独占 Godot 编辑器运行，本文的运行结果来自主会话验证，修复后的最终验证由主会话补记。

## 已修复的问题

- `core/ui/crafting/recipe_section_controller.gd`、`ingredient_section_controller.gd`：退出清理拆除全部格子输入订阅，但复用格子只在创建时连接，会令重新挂树后的旧格子不能选择、悬停或取消。连接调整为 `refresh` 中幂等建立；连接和断开共用各区域自己的 `_input_bindings`，没有移动业务职责或重建格子。
- `core/ui/crafting/crafting_ui_controller.gd`：新增取消信号在退出断开后没有恢复，而且重复退出可能再次断开已经断开的信号。`Open` 幂等恢复取消信号，退出用 `is_connected` 守卫。只恢复本任务新增信号，不重写旧 GameplayPort 生命周期。
- `recipe_section_controller.gd`、`ingredient_section_controller.gd`、`core/ui/shop/shop_item_slot.gd`：新增信号沿用旧声明顺序会产生新的 lint 错误。信号移到常量之前，保持公共名称与回调不变。

## 行为与范围核对

- 背包物品、装备、出战卡组三个区域均使用 `backpack_item_slot.gd`。右键已选中仅发出 `slot_clicked`，经过区域同格取消和根控制器悬停抑制；没有调用普通左键 `use_handler` 或快捷处理器。
- WarehouseNew 仓库、行囊两区均使用 `warehouse_item_slot.gd`。非拖动右键已选中复用根同格取消；数量拖动右键首先由根 `_input` 执行逐个/连续放置并消费，不进入新增 GUI 取消路径。
- ShopNew 仓库、商品两区均使用 `shop_item_slot.gd`。专用取消信号经根 `_clear_slot_selection` 和 `_hide_tooltip` 清理浏览；没有调用会清购买区的 `clear_selection`，没有改 `_buy`、`_sell`、库存或金币。退出断开的新增信号在 `shop_list_controller.refresh` 幂等恢复。
- CraftingUI 配方、材料两个区域的取消不发出 `recipe_selected`，因此 `_selected_recipe`、数量、材料需求和合成按钮仍保留；材料使用私有 `_selected_slot` 记录浏览，保持既有瞬时按钮外观。
- 固定详情面板及子装饰不拦截目标格子的鼠标输入。商店、仓库和背包适配会忽略格子装饰；合成 item_slot1 图标已有 IGNORE，Label 默认忽略。
- 没有改场景、库存/合成/经济 Model、拖动数值、存档或资源。父会话负责规范与玩法汇总；实现代理维护商店模块文档。

## 未修复的既有问题

- 受影响八个生产脚本在 HEAD 的 `gdlint` 有 30 项既有风格问题；本轮最初有 33 项，复核修复后降至 22 项。剩余为旧公共 `Open`/`Close` 与导出路径字段命名、旧超过 100 字符的长行、仓库旧信号定义顺序。逐类别与 HEAD 版本对照确认本轮没有新增 lint 问题。没有为满足默认工具风格重命名公共协议或清理无关长行。
- `tests/godot/test_item_room_content.gd` 的既有加载/解析错误由主会话确认仍存在，不是本次改动引入，不扩大范围修复。相关聚焦测试仍可执行。

## 验证

- `git diff --check`：通过。
- `gdlint` 八个生产脚本：原始全量检查未全绿，22 项均为既有问题；本任务新增/修改行没有新增问题。HEAD 基线为 30 项。
- 类型与运行验证：项目要求 Godot 4.7.1 编辑器 MCP，复核代理未另启 Godot；主会话已报告聚焦套件 14/8/1 通过、商店购买数量 2 保留、仓库/行囊 9/3 数量保留、原生拖動右键投放 1 个后会话继续且来源 8/目标 1。
- 修复后主会话已扫描并通过新游戏进程补验：CraftingUI 同一实例连续退出树再挂回两次（中间不 Open），最终 Open 后复用配方/材料格真实左键选择与右键取消均有效，数量 2、配方、制作可用状态不变；ShopNew 摘树重挂 init 后商品真实取消有效，重复右键与刷新不恢复选择。游戏日志没有生产错误。真实合成回归最终 29/29。完整证据见本任务 validation.md。

## 经验

固定详情必须同时验收显示和关闭，不只验收左键显示成功。取消应清理选择所有者，浏览状态与制作/交易状态不能混用。新增退出清理必须成对检查恢复路径；仅初次创建时连接会让缓存或复用实例产生无报错的输入失效。
