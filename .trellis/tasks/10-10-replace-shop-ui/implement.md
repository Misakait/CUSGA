# 执行计划

## 审阅门槛

- [x] 用户批准创建任务。
- [x] 核对用户最新购买按钮、数量输入框和出售交互要求。
- [x] 完成需求、技术设计、执行计划和实现/检查上下文清单。
- [x] 向用户展示最新方案，并取得随后一条消息的实施批准；用户回复“好的快去吧”。
- [x] 实施批准后运行 task.py start，再委派 trellis-implement。

## 实现步骤

1. 阅读本任务规划、AGENTS.md、agent.local.md 和上下文规范；重新核对场景与用户是否再次修改。
2. 依照 design.md 新建 `core/ui/shop/` 局部根、列表、购买、出售及格子/图标适配；对指定槽位交易添加最小协议适配。
3. 接入 ShopNew 已有 BuyButton、两处 SpinBox、Notice、图标、金币、整理/升级及返回控件；补商品网格和既有交易 Bridge 装配。
4. 修改 SceneManager.shop 路径，保留旧场景兼容；核对仓库和商店往返数据刷新。
5. 添加 `tests/godot/test_shop_new_contract.gd` 和顶层发现壳；聚焦来源槽位扣除、0 数量、不足量、错误/过期拖动、点击与展示更新隔离。非 @tool 节点的生命周期行为放到运行时验证，不伪造通过。
6. 主会话同步商店说明、README 文档入口、玩法汇总与组件规范，记录全部数量边界和数值来源；保持经济数值不变。

## 验证与复核

- Godot MCP editor_state 确认 CUSGA 4.7.1，filesystem_manage scan。
- test_run 新商店聚焦套件和必要的仓库回归；测试发现需有顶层壳。
- project_run custom ShopNew，真实输入覆盖商品选择、多件购买、拖入/更换图标不出售、数量修改不出售、0 数量点击提示、有效数量图标点击出售、不足量失败。
- game_eval 检查数量/金币变化、同类独立装备来源、整理后待售失效、升级按钮费用与容量、重入格子复用及信号订阅数量。
- 验证前备份实际被写入的 user:// 存档；结束恢复，不能残留测试金币、库存或升级变化。
- 验证 WarehouseNew、主菜单往返及 Main 冒烟，logs_read 检查阻塞错误，editor_screenshot 检查场景实际显示；每轮最后只 project_manage stop，保留编辑器。
- 委派 trellis-check 全范围复核和必要自修。主会话检查最终差异、重新 git status/git log，保留用户所有输入素材，不自动提交或推送。
- 将证据写入本任务 validation.md；遇到与本次无关的既有问题写明来源与影响，不擅自扩展。

## 文件边界

产品修改：ShopNew.tscn、SceneManager.gd、新建 core/ui/shop 局部脚本、新商店测试及发现壳。
文档修改：商店系统说明、README 文档入口、玩法汇总、frontend/component-guidelines 及本任务文件。
用户现有背景、箭头、槽位素材和 SpinBox 主题原样保留；旧商店规则层、商品资源、仓库功能和其它玩法不重写。
