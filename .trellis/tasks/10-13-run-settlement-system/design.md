# 轮回结算系统架构

用户已批准此架构并要求实施。赠送物品按真实收获处理，当前执行边界与默认值见 prd.md。

## 职责与所有权

| 模块 | 职责 |
|---|---|
| RunSessionData | 本局编号、统计、时长、结局、描述、流程阶段、轮回容量和待带出收获；只存内存 |
| PlayerProfile | 局外代币、永久升级等级、已结算编号；采用待领取方案时保存溢出收获 |
| SettlementManager | 持有当局数据与 Profile，收集、计算、一次入账、请求保存、提供结果 |
| SettlementConfig | 共享 Resource 配置与唯一 calculate_rewards 规则入口；只计算，不修改资产或文件 |
| 固定结果字典 | SettlementManager 生成的独立结果副本，包含编号、结束原因、统计、收获、token_delta 和保存状态 |
| SaveManager | 沿用现有读写、备份和恢复，增加写入门禁与批量提交边界 |
| Settlement 场景控制器 | 展示结果、传递导航意图，不计算或发奖 |

RunSessionData 和 PlayerProfile 建议使用 RefCounted 纯数据对象，不访问节点或文件。由常驻 SettlementManager 持有，不分别增加 autoload。

## 复用现有系统

- RunSnapshot 继续负责世界恢复，不将整个世界字典合并进 Profile。轮回流程下禁止 DISK 模式在结束前写入当局快照。
- 只有指定资源可轮回，资格配置目前为空。一般拾取只能更新统计或候选信息，不意味着物品自动进入带出收获；结算不能扫描普通背包并全部入账。
- 待带出收获以 RunSessionData 的公开选择入口管理，未来建筑调用同一入口；当前无建筑、无正式指定资源时，正常收获为空。
- 同一物品不能由背包、选择列表和资源计数重复发放。建筑开发时再决定选择动作是立即移入轮回格，还是保留在背包并在结算时验证扣除；接口不能提前宣称已支持某种转移机制。
- PlayerProfile 成为余额与永久等级的唯一数据来源。PlayerWallet、PlayerProgression 保留公开接口和信号，内部访问同一 Profile，不保留独立可写副本。
- 实物继续由 GlobalWarehouse 管理，仓库与 Profile 在同次存档提交中保存。Profile 不复制整份仓库库存。
- 沿用 player_wallet、player_progression、warehouse、carry 旧存档键，由适配入口映射；同一键只注册一个有效参与者。
- 轮回代币若不同于金币，独立定义字段，不擅自改变商店金币含义。PlayerLevel 的当局经验、属性点不自动变成永久加点。

## 数据流

1. 开局建立 run_id 与 RunSessionData。消耗带入前打开局内写入门禁，带入和时间初始化复用 RunStartInitializer。
2. 成功领取和统计事件仅更新内存，世界与战斗共享同一当局对象。待带出收获通过专用选择入口管理；当前正式收获为空。
3. 死亡、明确通关、主动结束统一请求 finish_run。阶段立即变成结束处理中，阻止继续行动、拾取和重复结束。
4. 释放玩家与世界之前停止计时、读取已确定的带出收获，并深复制条目。结束原因是死亡且测试开关开启时，在固定结果生成前通过统一添加方法添加 1 个测试物品。随后唯一调用共享配置的 calculate_rewards(harvest, statistics, reason)，生成固定结果字典。整个步骤受同局阶段门禁保护。
5. 校验奖励和容量，在 has_settled_run 门禁内将真实收获批量合并仓库，并将非负 token_delta 通过 PlayerProfile.add_tokens 合入局外代币余额，标记 run_id 已入账，清理已结束快照；单个信号不得保存部分结果。
6. 正式模式提交一次完整存档。失败保留相同结果，重试只保存，不重新计算或入账；建议保存成功后开放导航，失败显示重试入口。
7. 测试模式只入账内存并显示结算。返回菜单、继续下一把不再发奖。
8. 全新一局明确清理旧编号、快照和统计，重置时间，不能误走旧局恢复。

阶段：进行中 → 结束处理中 → 已入账待保存 → 已完成。测试完成仅表示内存入账，不显示磁盘保存成功。

player_died 与 battle_ended(false) 可能先后到达，以编号和阶段去重。整局结束后，世界协调器跳过普通回世界、恢复输入和自动保存链，避免异步回调争抢场景。普通 battle_ended(true) 继续探索，通关由明确 finish_run 入口触发。

## 持久化开关

建议 persistence_enabled 默认 false，在进程启动、载入玩法数据前确定；变更通过重启生效，不开放运行中切换，避免测试收益随后被正式保存。

| 情况 | 玩法存档写入 |
|---|---|
| 正式模式的局外准备 | 正常保存 |
| 正式模式的局内 | 暂缓全部玩法写入，覆盖带入消耗、自动保存、战斗后请求、退出兜底 |
| 正式模式的结算 | 资产增量与本局结束标记一起提交 |
| 测试模式 | 本进程玩法写入关闭，内存流程正常 |

门禁放在 SaveManager 实际写入入口，覆盖主档、备份、临时档和退出保存；仅在 SettlementManager 跳过 save_now 不够。

按键、音量偏好不承载收益。本方案门禁范围为玩法存档；若用户要求任何文件均不能写，需要额外明确偏好和日志范围。

正式局结算前强制关闭，建议放弃未结算收益。带入消耗也未落盘，重启恢复上次保存的局外准备，不保留本局所得。此口径待确认。

## 一致性与失败

- 同局编号与阶段保证一次入账。正式模式将资产和已结算编号放在同次提交中。
- 保存失败只重试同一结果，不发第二份奖励，不假称保存成功。
- 满仓不能静默截断。建议溢出保存到待领取收获，领取入口为待确认范围；不采用时需在入账前整体验证容量并显示失败。
- 沿用 SaveSlotCodec、物品标识和洗炼属性协议。结果不持有已释放背包节点或仍可变化的 ItemStack 引用。

## Settlement 场景分工

- 根控制器只绑定结果与区域、处理导航意图。
- Harvest/ScrollContainer 新增 SlotGrid，收获控制器按收获容量生成 item_slot1，默认 5 格，空格也保留；再把固定结果的奖励填入对应格子。复用名称、图标、数量、单选和 TooltipPanel。
- 使用结算专用格子绑定固定结果，不绑定死亡玩家的可写背包。建议第一版保留展示与详情，拖拽、装备、丢弃和使用待确认。
- 统计控制器管理 Data/TimeSection、Data/EndingSection、Data/Description。接口为 set_play_time(seconds)、set_ending(id, title)、set_description(text)、add_description(text)、set_statistics(data)。显示修改不重新计算奖励。add_description 在非空原文后先追加换行再追加新文本，保持调用顺序；原文为空时直接写入，空文本不追加空行。
- BackToMenu/Button、BackToMenu2/Button 分别挂独立脚本，只发返回菜单与新局意图，不修改资产。
- 建议在 Main 独立 UI 层弹出，锁住世界与战斗输入，暂停时按钮仍可操作。固定结果由常驻管理器持有，释放 Main 后不丢失。
- 返回菜单沿用登录菜单入口，继续下一把复用正式开局初始化。

## 候选接口

- SettlementConfig.calculate_rewards(harvest: Array, statistics: Dictionary, reason: String) -> Dictionary：唯一可覆写的纯规则计算入口，输入为真实堆叠和统计副本及结束原因，返回 harvest 独立堆叠副本与 tokens 非负代币增量。默认保留实际物品、tokens = 0，不定义额外倍率、惩罚或赠币。SettlementManager 将 tokens 规范为非负整数并记录为结果 token_delta；重复结束和保存重试不再次计算或入账。
- begin_run(context)：建立新局，不重复消费带入。
- record_resource(id, amount)：仅计成功领取，结束阶段拒绝更新。
- record_statistic(id, delta)：只改内存。
- finish_run(reason, ending_id, context)：同局重复调用返回已有结果。
- get_last_result()：固定结果，不依赖死亡玩家。
- retry_persistence()：只重试保存。
- get_harvest_capacity()：读取当前有效容量，默认 5。
- set_harvest_capacity(capacity)：由局外升级入口调整容量并通知 UI；不在本期定义升级费用和每级增长量。进行中的本局持有开局容量，下一局读取新的局外容量，避免结算结果被中途更改。
- harvest_capacity_changed(capacity)：局外容量变化通知；显示层通过公开接口刷新，不直接改内部格子数组。
- can_reincarnate(item)：查询正式资格；当前所有普通资源返回不允许，测试注入不改变此结果。
- try_select_reincarnation_item(source: Node, slot_index: int, amount: int)：未来建筑请求选择。本期只读取来源并验证进行中状态、基础参数和资格，明确返回未接入错误，不改库存或收获；后续建筑开发再补来源数量、容量、重复请求与移转规则。
- try_remove_reincarnation_item(selection_id: String, amount: int = -1)：未来建筑取消选择。本期只验证状态与参数，明确返回未接入错误；具体退回规则随建筑开发确认，不提前退货。
- get_reincarnation_selection()：本期返回空的独立数组；建筑接入后返回隔离的选择快照，不暴露内部可写数组。

## RunSessionData 与 RunSnapshot 的区别

RunSessionData 是本局正在使用的账本，记录统计和待带出的收获；生命周期从开局到结算。
RunSnapshot 是恢复世界用的快照采集和应用入口，读取地图、玩家与房间模型并编码为字典。其 capture_save_data 包含地图、时间、位置和背包，但没有轮回资格、选择规则、收获容量和一次结算状态。
快照里出现物品代表玩家当前持有该物品，不代表该物品允许轮回。若以后需要恢复选择账本，可由快照序列化入口读取 RunSessionData 的稳定字段，仍不能出现第二份可写账本；此扩展本期不实施。

## 收获容量、测试注入与建筑接入

- 局外容量数据来自 Profile 的容量字段或未来升级规则，默认 5；RunSessionData 在开局取得本局容量，固定结果字典记录它，面板按结果显示。当前不建立容量升级玩法。
- 建议提供共享 SettlementConfig Resource，导出 enable_death_test_reward 和 death_test_item，供 Inspector 修改。选择现有 wheat.tres，生成数量固定为 1，建议测试配置默认开启；此默认建议在实施摘要中明示。
- 死亡测试注入由 SettlementManager 完成，不能在面板 _ready 或打开面板时生成。关闭测试开关时，没有指定资源便显示 5 个空格。
- 测试物品走同一收获展示和入账链路，按真实物品入库，但不使普通小麦自动获得轮回资格。它独立于 persistence_enabled：生成开关控制是否赠送，持久化开关控制是否写盘。
- 未来建筑调用选择接口，然后结算读取已确定的选择；建筑不直接修改仓库、不自行写盘，也不访问结算 UI 内部节点。本期只有接口边界，不添加建筑或选择界面。
- 选择必须校验来源数量、资格、容量和当局状态，使用稳定选择标识防止重复调用复制物品。容量按格子而非简单按数量计数，最终堆叠规则复用物品系统并在建筑阶段明确。

最终命名、类型和中文文档注释在实施阶段按项目规范确定。
