# 新商店接入设计

## 场景与职责

- `scenes/Shop/ShopNew.tscn` 保留用户最新节点和布局，增加根脚本、现有 ShopTradeBridge/Catalog 装配及商品滚动区内 GridContainer。已有 BuyButton 与两处 SpinBox 直接接线，不增加第二个购买按钮。
- 新脚本集中放在 `core/ui/shop/`。根控制器只协调 init/exit、全局组件、区域刷新、升级整理和导航；列表控制器管理格子；购买区域控制器管理商品详情和购买意图；出售区域控制器管理待售快照、图标输入与出售意图。沿用仓库既有的根/区域分工，不引入其它架构。
- 商店格子适配 `scenes/ui/item_slot2.tscn`，保留原生按钮样式和持续选中。仓库格显示数量，商品格显示单价且不伪造库存数量。不得通过修改共享仓库格子脚本破坏仓库交互。
- 点击格子详情复用 WarehouseNew 的 ItemTooltipPresenter 和 TooltipLayer/TooltipPanel。列表选中与待购买商品分开管理：仓库点击不清空购买区；买卖两侧图标右键分别调用对应区域 clear，不触发交易。
- 售卖图标为现有 TextureRect，挂局部脚本以接收 Godot Control 拖放及左键点击；保留 Area2D 和碰撞节点，但不使用物理重叠判断 UI 拖放。

## 状态与数据流

- GlobalWarehouse、PlayerWallet 和 PlayerProgression 继续拥有权威状态。商品目录/定价/交易失败码复用 ShopTradeBridge 和 ShopService。
- 商品格点击 → 更新购买详情 → SpinBox 选择数量 → BuyButton → 一次性预检和提交 → 信号刷新仓库、金币和动作区。商品点击和 value_changed 只改变显示。
- 仓库格拖动 → 校验界面身份、当前会话身份和来源槽位快照 → 出售图标接收并显示待售内容。接收、替换纹理、数量变化均不得调用交易方法。
- 出售图标明确左键点击 → 提交尚未失去焦点的 SpinBox 输入 → 读取整数数量 → 0 时 Notice 提示“请选择数量”并返回 → 重新验证来源 → 通过 Bridge 按数量出售 → 刷新显示和待售状态。
- 拖入操作的鼠标释放不能被当成后续的图标点击；出售输入必须有独立按下/释放，且拖动期间不提交。
- Quantity 使用场景现有范围和整数步长。价格详情保留现有单价语义，交易结果明确数量和总金币；数量大于来源数量时失败，不自动截断。

## 指定槽位与失败一致性

现有 InventoryComponent.TryRemoveItem 从后往前按物品类型扣除，不能保证移除拖入的独立装备。出售采用只在本次交易中存活的来源槽位适配对象：实现 Bridge 已有 ItemCnt/TryRemoveItem 协议，只访问已选来源槽位；重新核对物品、数量及 RolledAttributes，通过原库存 TrySetStackAt 更新该槽位并发出原有通知。适配对象不保存第二份长期库存，不修改原公共协议、不复制价格规则。

任何库存信号在交易中发生时先暂缓区域刷新，完整交易返回后统一刷新，避免中间回调使待售引用失效。失败保留金币和库存；整理、退出及来源身份变化清理待售状态。旧拖动载荷不得在重入后继续使用。

## 生命周期与兼容

- SceneManager 的 shop 路径切为 ShopNew，旧 Shop.tscn 与 shop_control.gd 保留。
- init 允许早于 _ready，并支持缓存实例移树后重入；创建视图及信号接线幂等。订阅库存、钱包及升级变化，exit/_exit_tree 解除外部订阅并清除临时选择。
- 装饰标签忽略鼠标输入，SpinBox 和按钮保留输入能力。不可全局忽略所有 Control。
- `scripts/export_spinbox_bg.gd`、用户图片素材、WarehouseNew 的背景与 item_slot2 的已有修改保留；只有验证确认本任务阻塞错误时才做必要修复并报告。

## 文档、风险与回退

- 同步 `docs/游戏机制与玩法内容.md` 和 `.trellis/spec/frontend/component-guidelines.md`。检索已有商店模块说明；缺失时补 `docs/商店系统.md` 并登记到现有 README 文档入口。
- 风险重点是拖动释放误交易、数量输入未提交、同类独立物品误扣、缓存重复订阅和交易中间刷新；分别用回归测试或真实输入验证。
- 不调整经济数值、资源目录和存档结构。验证使用隔离夹具；真实交易验证前备份相关 user:// 文件，结束恢复。
- 回退仅恢复本轮增加的脚本接线及 shop 路径，不回退用户准备的文件。
