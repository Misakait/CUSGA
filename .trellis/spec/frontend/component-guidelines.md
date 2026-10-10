# Component Guidelines

## UI 组件

- UI 脚本继承实际需要的 `Control`、`CanvasLayer` 或 `Node2D`，不把业务规则塞进按钮或标签。
- `_ready` 只解析导出路径、建立一次性子节点和连接信号；需要重复调用时必须幂等。
- 公开 `bind` 方法负责切换 Model。重新绑定前断开旧信号，绑定内容不变时直接返回。
- 重复槽位、列表和卡牌视图只在容量变化时增删节点；内容变化只刷新现有 View。
- `_exit_tree` 中断开信号、取消 Tween、隐藏提示和清理外部资源引用。

## 输入与拖拽

- View 只报告点击、按下、抬起、拖拽和取消意图；Controller 决定是否允许操作。
- 物品槽位调用库存/装备 Model 的校验和变更方法，不在 UI 重复堆叠、容量或装备规则。
- 空槽位、禁用按钮和不可用目标必须在 View 中明确反映，避免把无效输入交给业务层。

## 地图与战斗

- 复杂房间按容器拆分 UI Controller：BridgeContainer、BridgeWithBoundary、BridgeBoundary、Ground、Obstack 和 Boundary 分别有自己的模块控制器。
- 各模块控制器只管理挂载节点的直接子节点，不跨容器访问内部节点；跨模块数据使用同一 RoomContext 或公开信号。
- 只有在需要把同一上下文分发给多个模块或协调初始化顺序时，才在 MapContainer 挂载 UIMapContainerController；该脚本不得承载模块具体逻辑。
- UIMapWorldView 通过房间根节点 configure_room_context(context) 初始化房间，不直接查找各模块的内部 TileMapLayer。
- 房间根脚本只保留现有场景元数据、初始化兼容行为和薄转发入口，不得集中实现所有房间功能。
- normal 房间作为 1280×720 的完整 TileMap 场景拼接。Boundary 承载 Ground 常设地形边界；BridgeWithBoundary 阻挡无桥桥口并在有桥时关闭阻挡；BridgeBoundary 只限制有效窄桥两侧，桥中心保持可通行。
- 保留历史节点名 Obstack 以兼容场景序列化引用；控制器文件名使用 UIObstacleController。任何后续节点重命名都必须先搜索场景、脚本和资源路径。

- 地图按钮只上报方向和按键生命周期；地图 Controller 负责长按、跨房间和当前坐标更新。
- 地图 View 负责实例化当前房间及周围八个房间，缓存由 Model 管理。
- 房间 View 必须按节点职责拆分 `UI` 控制器：`UIBridgeContainerController` 管理方向桥，`UIBridgeWithBoundaryController` 管理方向桥口阻挡，`UIBridgeBoundaryController` 管理桥侧边界，`UIGroundController` 管理地面 TileMapLayer，`UIObstacleController` 管理障碍 TileMapLayer，`UIBoundaryController` 管理 Ground 常设边界；`UIMapContainerController` 只负责注入统一上下文和协调初始化顺序。
- 子控制器只管理自己的直接子节点，不跨模块搜索和修改其他容器的内部节点；跨模块状态通过房间上下文或信号传递。
- 新增房间功能时先判断它属于桥、地面、障碍、边界还是房间协调；只有确实属于多个子模块的流程才放在 `UIMapContainerController`。
- 大小地图图元也按直接子节点拆分：`WorldMapCanvas` 只绑定 Model；`RoomsContainer` 只管理直接 `RoomTemplate` 子节点；`RoomTemplate` 只向 `RoomView` 和 `BridgeContainer` 分发状态；`RoomView` 只管理纹理；`BridgeContainer` 只管理直接桥节点。桥显示与所有权等纯计算放在无状态策略脚本中，不重新堆回任何场景根脚本。
- 战斗管理脚本拥有战斗状态机；数据资源只提供技能、怪物和地形配置，不直接创建 UI。
- 通过信号传递完成、取消和失败事实，避免一个节点直接访问另一个节点的内部子路径。

## 工具提示和共享表现

- 复用已有提示节点和 Presenter 协议；不要为同一种提示创建第二套全局系统。
- 共享表现参数放在无状态配置脚本中，消费方通过 `preload` 读取，避免复制数值。

### 背包格子选中与共享提示契约

1. **适用范围**：修改 `ItemSlot`、背包三个区域 Controller 或共享 `TooltipPanel` 时，检查对应消费方；旧商店 Shop.tscn 和旧仓库资源使用 ItemSlot，新商店 ShopNew 和新局外仓库 WarehouseNew 使用原生 item_slot2 Button，WarehouseNew 仍复用 TooltipPanel。
2. **接口**：`ItemSlot.set_selected(selected: bool)` 控制持续选中；`is_selected() -> bool` 读取选中；各区域 `GetSelectedSlot() -> ItemSlot` 返回当前格或空值。`TooltipPanel.set_fixed_anchor(anchor: Vector2)` 使用视口坐标，`clear_fixed_anchor()` 恢复鼠标跟随。
3. **规则**：区域拥有单选状态。点击新格先清旧格，同格再次点击取消。普通左键松开必须继续交给 Button 原生处理，不能在 `_gui_input()` 尾部调用 `accept_event()` 截断松开；点击穿透由 `MOUSE_FILTER_STOP` 阻止。选中信息与悬停信息使用相同 TooltipPanel 场景和物品名称、描述，但显示在不同实例中：选中实例归背包所有，固定在格子旁；悬停实例仍是 HUD 的共享面板，跟随鼠标。普通物品不得用操作菜单替代提示。
4. **边界**：空格无物品提示；无选中时隐藏固定面板；关闭背包清空选中和两块面板；同格取消后抑制该格悬停直到离开；关闭选中提示开关只隐藏固定面板，不禁用悬停。复制的固定面板须移出 `tooltip_panel` 全局组，避免其它悬停组件误选。鼠标从 B 离开只隐藏 B 的悬停面板，不能关闭 A 的固定面板；点击同区域 B 后关闭 A 固定面板并显示 B 固定面板。
5. **正确与错误情形**：正确情形是点击两个格子后，仅后者选中，所有按钮瞬时按压均已释放；初始情形没有选中；错误情形是选择状态虽已清除，按钮仍因松开被消费而残留深色。
6. **运行验证**：用 Godot MCP 真实发送按下和松开，读取所有格子的 `is_selected()`、`button_pressed` 并查看截图。点击 A 后移到未点击 B，断言固定面板标题为 A 且悬停面板标题为 B、两者同时可见；离开 B 后只剩 A；点击 B 后仅 B 选中且固定面板显示 B；关闭设置后固定面板隐藏而悬停仍可见。还要验证再次点击后提示隐藏、关闭背包后两块面板隐藏，以及仓库两侧互斥。
7. **实现示例**：持续选择写入 `slot.set_selected(true)`；不得用 `slot.button_pressed = true` 保存选择。普通点击的 `_gui_input()` 发出选择意图后正常返回；快捷操作单独消费事件，以保留原有快捷与拖拽协议。

### OpenBackpack 的 item_slot1 适配

- 三个区域分别从 `res://scenes/ui/item_slot1.tscn` 实例化 Button，再挂载 `res://scripts/ui_scripts/backpack_item_slot.gd`，继承 ItemSlot 的绑定、拖拽、快捷键和提示协议。原始 item_slot1 场景仍可由合成独立使用，不能通过修改共享场景改变其它界面的输入与外观。
- 原场景没有 PriceLabel，背包适配须在旧 ItemSlot 解析节点之前补齐隐藏标签；Icon、CountLabel、NameLabel 必须继续读取场景节点。标签不得拦截鼠标事件，否则点击标签和点击格子空白会产生不同结果。
- 持续选中使用场景的 pressed 样式，不额外染暗。未选中格子的 normal、hover、pressed、hover_pressed 应保持普通外观；仅当前区域选中格子显示点击外观，避免悬停或按住另一格时出现两个点击外观。不同区域可以同时各选一个，不能建立全局互斥选择。
- 运行验证读取三栏每个格子的 `scene_file_path`、`is_selected()`、`button_pressed` 和样式贴图；真实输入覆盖悬停、按住新格、松开切换、再次取消、跨栏独立、刷新复用和关闭清除。

## WarehouseNew 的 item_slot2 契约

- `SceneManager.SCENE_MAP["warehouse"]` 指向 `res://scenes/Warehouse/WarehouseNew.tscn`，保留旧仓库资源兼容路径。不得把局内 `warehouse_ui.tscn` 与局外仓库入口混为一谈。
- 两区格子放在 `ItemSection/ScrollContainer`、`PackbackSection/ScrollContainer` 下的 GridContainer；仓库铺全部容量，行囊仅铺已解锁容量，内容刷新复用节点。
- 格子从 `res://scenes/ui/item_slot2.tscn` 实例化。原生 Button 的 normal/hover/pressed 和 toggle 状态直接使用场景配置；禁止套用会覆盖样式的旧 ItemSlot 初始化，禁止重画、染暗或覆盖这三种样式。
- 根控制器协调生命周期、按钮、钱包及导航；区域控制器管理自己的直接格子。仓库与行囊共同单选；点击使用现有 TooltipPanel 的名称/描述协议。空格、退出、整理或拖动后不残留错误选中描述。
- 仓库权威是 GlobalWarehouse，行囊权威是 ItemsControl。跨区转移先验证来源快照、目标索引和解锁容量，再提交；刷新与信号不得制造物品复制或丢失。保持现有 item/count 行囊存档格式，不能扩展洗炼字段。
- Cost、CoinCount 和 CapacityLabel 读取 PlayerProgression、PlayerWallet 和权威物品状态，不写死费用或余额。缓存重入应重建订阅并刷新；离开清理外部信号和提示。
- 验证包含真实点击/拖动、仓库与行囊数量守恒、失败无副作用、升级扣费/扩容、余额即时刷新、格子复用以及主菜单/商店导航。

## ShopNew 的交易提交边界

- `SceneManager.SCENE_MAP["shop"]` 使用 `res://scenes/Shop/ShopNew.tscn`。商店根协调生命周期和全局组件，购买区、出售区及滚动列表分别管理自己的控件，不将原商店分页逻辑直接堆入根脚本。
- 商品点击只展示详情，购买只由 `Shop/BuyArea/Buy/BuyButton` 提交 `Shop/BuyArea/BuyCount/SpinBox` 的整数数量；出售只由 `Shop/SellArea/ItemIcon` 独立左键点击提交 `Shop/SellArea/SpinBox` 数量。
- 点击商品或仓库物品通过现有 ItemTooltipPresenter 和 TooltipPanel 显示格子旁的固定详情；点击左侧仓库格只改变浏览选中状态，必须保留购买区的商品和数量。购买区 ItemIcon 的 gui_input 和出售图标的 _gui_input 处理右键清除各自区域，不提交交易；不可把列表浏览清理和购买区 clear() 混为同一入口。
- 拖入或替换待售图标、设置纹理、改变数量都只更新显示。拖动释放与随后独立点击必须区分，不能把放下物品当成出售。0 数量点击出售必须让 Notice 提示“请选择数量”，不能禁用图标后导致提示无法触发。
- SpinBox 输入在提交前调用其输入提交接口，使未失焦的键盘输入参与交易；保留场景主题与范围，不通过绑定脚本重置样式。
- 物品拖动载荷包含所属界面/会话身份及来源槽位快照，提交时重新校验物品、数量、洗炼属性和来源。对指定槽位出售采用既有库存协议的短期适配，不能使用按物品类型倒序移除而误卖另一格独立装备；价格和金币增减仍由现有 Bridge/Service 处理。
- 交易期间暂缓库存/金币信号引起的区域刷新，提交返回后刷新；整理、来源失效及退出清理待售内容。重入恢复订阅并复用格子。共享 item_slot2 原生三态样式和仓库行为必须保持。
- 商店空槽的 Button 保持禁用；`shop_item_slot.gd` 在 `_ready()` 中用 `add_theme_stylebox_override("disabled", get_theme_stylebox("normal"))` 复用 item_slot2 的普通样式。item_slot2 未配置 disabled，省略此适配会让空槽回退成默认灰块；不能为显示边框而启用空槽。运行验证必须查看空槽截图，并确认 disabled 仍为 true、disabled 与 normal 使用同一 StyleBox。
- 运行验证覆盖真实鼠标拖入后金币与数量不变、替换和数量变化不成交、0 数量提示、多件买卖、同类不同属性装备的来源、过期拖动、缓存重入与订阅清理。

### 可执行契约

1. **适用范围**：修改 ShopNew 的图标、数量、拖放或交易协议时，使用本节复核显示更新和交易提交的边界。
2. **入口签名**：根控制器 `create_drag_data(side: StringName, index: int) -> Dictionary`、`can_drop_item(data: Dictionary) -> bool`、`drop_item(data: Dictionary) -> bool`；购买区域 `request_purchase() -> void`、出售区域 `request_sale() -> void`。返回类型与实际实现一致后才能用于调用。
3. **载荷约定**：owner/session 为界面实例与本次进入标识，side 必须为 warehouse；index 为来源格，stack_id 为槽位对象身份，item 为原 Resource，amount 为正整数，rolled 为独立属性字典。提交前与当前库存逐项相等；不接受其它界面、旧会话或形状错误的字典。
4. **校验与提示**：0 数量 → “请选择数量”且无副作用；来源失效 → 清理待售并提示重新放入；不足量、不可售、余额不足或空间不足 → 整笔失败；成功 → 数量和金币按一次提交准确变化。
5. **正常/初始/错误情况**：正常为拖入 5 件、选 2 件、另行点击后剩 3 件；初始为无待售、数量 0；错误为更换纹理后自动扣货，或出售来源格时扣了另一格同类装备。
6. **测试断言**：`shop_new_contract` 验证来源适配、零值及不足量无副作用；运行时真实输入断言 drop 后及 SpinBox 变化后库存/金币均不变，独立点击后各变化一次；验证 typed 数字尚未失焦仍能正确提交。
7. **错误与正确写法**：错误是在 `accept_drop()`、纹理 setter 或 `value_changed` 调用 `TrySellWithReason`；正确是在这些入口只刷新图标/文案，由 `request_sale()` 校验数量和来源后唯一调用既有交易服务。

## 全屏覆盖层（滤镜、遮罩）

- **先确认宿主场景的相机**：放在默认 canvas 的全屏覆盖层会随 `Camera2D` 一起变换。相机跟随玩家移动时，覆盖层会跟着移出画面——表现为「滤镜完全没生效」，且**不报任何错**；相机固定在屏幕左上角（`top_level = true`、缩放 `1`）时才不受影响。相机不固定的场景必须把覆盖层放进 `CanvasLayer`（`CanvasLayer` 不受相机变换影响）。
- 用 `CanvasLayer` 承载覆盖层时，它默认画在**所有**默认 canvas 内容之上，因此要按 `layer` 值把它排在世界之上、其余 UI `CanvasLayer` 之下（本项目探索场景的实际取值：滤镜 `0`、小地图 `1`、HUD `2`）。同层 `CanvasLayer` 之间的顺序不确定，必须错开。
- 验证口径：移动相机后，覆盖层的 `get_screen_transform().origin` 必须仍为 `(0, 0)`；只看「覆盖层大小是否为视口尺寸」会漏掉这个缺陷。
- 全屏 `Control`（`ColorRect` 滤镜、全屏遮罩）的父级必须是普通 `Node`、`Control` 或 `CanvasLayer`，**不得直接挂在 `Node2D` 下**。
- 覆盖层的强度由**离散事件**驱动时（时间按行动值跳变、血量按回合变化），参数跨度要按**最小触发步长**校验，而不是按一整轮的总跨度设计。本项目一次移动只推进昼夜阶段的十分之一（`10 / 100`），端点色差过小会让玩家以为覆盖层根本没生效、只有跨阶段那一瞬才看得出来。为「单步可见性」写契约测试（断言相邻两步的差值不低于阈值），不要只靠肉眼看一次。
- 原因：`Control` 的 anchors 以父级 `CanvasItem` 的 `anchorable_rect` 为参考，而 `Node2D` 的该矩形是空的，全屏 anchors 会算出 `0×0`。此时节点照常进树、`visible` 仍是 `true`、`color` 也能正常读写，但**什么都不画，且不产生任何报错**——只能靠像素级验证发现。
- 兜底写法：在 `_ready` 里检测退化尺寸并自愈，例如 `set_anchors_preset(Control.PRESET_TOP_LEFT)` 后显式 `size = get_viewport_rect().size`。参考 `core/ui/filters/day_night_filter.gd` 的 `_fit_to_viewport()`。
- 层级判断：默认 canvas 内按 `z_index` 排序，而 `CanvasLayer` 的内容**永远**画在默认 canvas 之上（与 `layer` 数值是否为 `0` 无关，已实测 `map_control.tscn` 的 `layer = 0` 仍在滤镜之上）。因此「压住世界但保留 UI」的覆盖层应放在默认 canvas，并取一个高于世界内容 `z_index` 的值；若某场景的 HUD 不在 `CanvasLayer` 上（战斗场景即是），必须把 HUD 根节点的 `z_index` 提到覆盖层之上。
- 覆盖层必须设 `mouse_filter = MOUSE_FILTER_IGNORE`（枚举值 `2`），否则会吞掉其下方所有输入。
- 乘法混合的 `CanvasItemMaterial` 用 `blend_mode = BLEND_MODE_MUL`，枚举值是 **`3`** 而不是 `1`（`1` 是 `BLEND_MODE_ADD`）；写错不会报错，只会得到发白的画面。
- 全屏覆盖层的入场应直接吸附到当前应有的状态（而非播放入场动画），否则场景切换时会看到一次多余的渐变或闪烁。
